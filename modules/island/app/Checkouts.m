// Checkouts: keeps each listed checkout's git status, extra stage and branch PR fresh.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Checkouts.h"
#import "Core.h"
#import "Row.h"
#import "Log.h"
#import "Git.h"
#import "GitHub.h"
#import "Stages.h"

// What a read finds that goes to the page as part of a row's checkout, apart from the PR: cleared before each read's
// results go in, so nothing a failed read couldn't confirm stays up.
static NSArray<NSString *> *ReadKeys(void) {
    return @[@"changes", @"ahead", @"behind", @"upstream", @"remotes", @"base", @"aheadOfBase",
             @"newFiles", @"filesStaged", @"filesPartly", @"filesUnstaged", @"stage"];
}

// What a read finds that only the island's menus and file lists need: kept here, not sent with every row.
static NSArray<NSString *> *DetailKeys(void) {
    return @[@"files", @"newPaths", @"stagedPaths", @"partlyPaths", @"unstagedPaths", @"commits", @"menu", @"declined"];
}

// The files outside the extra stage, as it names them (`named`), split as git sees them (`tree`, FetchCheckoutState;
// `counts`, FetchChangeCounts): {parts: {staged, partly, unstaged}} for the files stage's gauge, and in place of git's
// own lists, the first 100 of each kind (stagedPaths, partlyPaths, unstagedPaths, newPaths) for the lists its parts
// show, and the first 10 others (files) for its menu. A file git doesn't track is new, and one git sees no change in
// has nothing staged: both count as unstaged, as git's new files do.
static NSDictionary *SplitNamed(NSArray<NSString *> *named, NSDictionary *tree, NSDictionary *counts) {
    NSDictionary<NSString *, NSNumber *> *kindOf = tree[@"kindOf"];
    NSSet<NSString *> *untracked = counts[@"untracked"];
    NSInteger n[3] = {0, 0, 0};
    NSArray<NSMutableArray<NSString *> *> *lists = @[[NSMutableArray array], [NSMutableArray array],
                                                     [NSMutableArray array]];
    NSMutableArray<NSString *> *fresh = [NSMutableArray array], *files = [NSMutableArray array];
    for (NSString *path in named) {
        NSNumber *kind = kindOf[path];
        BOOL isNew = !kind && [untracked containsObject:path];
        NSUInteger k = kind ? kind.unsignedIntegerValue : 2;
        n[k]++;
        NSMutableArray<NSString *> *list = isNew ? fresh : lists[k];
        if (list.count < 100) [list addObject:path];
        if (!isNew && files.count < 10) [files addObject:path];
    }
    return @{@"parts": @{@"staged": @(n[0]), @"partly": @(n[1]), @"unstaged": @(n[2])}, @"stagedPaths": lists[0],
             @"partlyPaths": lists[1], @"unstagedPaths": lists[2], @"newPaths": fresh, @"files": files};
}

@interface Checkouts ()
// Per checkout (git root), what's known about it. Touched on the main thread only; git and gh run on the queue.
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *known;
// Per checkout, what only the menus need (file names, commit subjects, the extra stage's menu): kept here rather than
// sent with every row. Main thread only.
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *details;
// Per checkout, the last problem logged, so one that persists is logged once, not every read. Main thread only.
@property (strong) NSMutableDictionary<NSString *, NSString *> *problems;
@property (strong) NSMutableSet<NSString *> *reading;  // the checkouts being read now
@property (strong) NSMutableSet<NSString *> *dueNow;   // read on the next refresh, whatever the time (readSoon:)
// Per checkout, until when its extra stage isn't run, after it took too long. On the queue only.
@property (strong) NSMutableDictionary<NSString *, NSNumber *> *slowUntil;
@property (strong) dispatch_queue_t queue;
@end

@implementation Checkouts

- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.known = [NSMutableDictionary dictionary];
    self.details = [NSMutableDictionary dictionary];
    self.problems = [NSMutableDictionary dictionary];
    self.reading = [NSMutableSet set];
    self.dueNow = [NSMutableSet set];
    self.slowUntil = [NSMutableDictionary dictionary];
    self.queue = dispatch_queue_create("whozmove.checkouts", DISPATCH_QUEUE_SERIAL);
    self.runsStages = YES;
    return self;
}

- (NSDictionary *)stateOf:(NSString *)root {
    return self.known[root];
}

- (NSDictionary *)detailsOf:(NSString *)root {
    return root ? self.details[root] : nil;
}

- (void)readSoon:(NSString *)root {
    if (root) [self.dueNow addObject:root];
}

- (BOOL)checking {
    return self.reading.count > 0;
}

// Keeps each listed checkout's real state fresh, for the panel's "current action" and the row's island. Git status
// (and the extra stage, if the checkout has one you've allowed) is read every 20s, and within 2s of any activity by a
// session working there (a tool call, Claude stopping), so a commit an agent just made isn't shown against the
// uncommitted changes from before it. The branch's PR (state, checks, reviews) is read every 60s, or as soon as the
// branch changes.
- (void)refreshFor:(NSArray<Row *> *)sessions {
    NSString *gh = GhPath();
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSMutableDictionary<NSString *, id> *branches = [NSMutableDictionary dictionary];  // root -> branch or NSNull
    NSMutableDictionary<NSString *, NSString *> *projects = [NSMutableDictionary dictionary];  // root -> main checkout
    NSMutableDictionary<NSString *, NSNumber *> *activity = [NSMutableDictionary dictionary];  // root -> latest, in s
    for (Row *row in sessions) {
        NSDictionary *git = row.workGit ?: row.git;
        if (![git isKindOfClass:NSDictionary.class] || ![git[@"root"] isKindOfClass:NSString.class]) continue;
        branches[git[@"root"]] = git[@"branch"] ?: NSNull.null;
        projects[git[@"root"]] = git[@"mainRoot"] ?: git[@"root"];
        double latest = MAX(row.stageAt.doubleValue,
                            MAX(row.lastReplyAt.doubleValue, row.outcomeAt.doubleValue)) / 1000;
        activity[git[@"root"]] = @(MAX(latest, [activity[git[@"root"]] doubleValue]));
    }
    // A listed checkout is read at least every 20s, so one not read for a minute has no session working in it.
    for (NSString *root in self.known.allKeys)
        if (!branches[root] && now - [self.known[root][@"checkedAt"] doubleValue] > 60) {
            [self.known removeObjectForKey:root];
            [self.details removeObjectForKey:root];
            [self.problems removeObjectForKey:root];
        }
    BOOL stages = self.runsStages;
    NSArray<NSString *> *marks = self.core.agentMarks;
    for (NSString *root in branches) {
        if ([self.reading containsObject:root]) continue;
        NSDictionary *known = self.known[root];
        id branch = branches[root];
        NSString *project = projects[root];
        double checkedAt = [known[@"checkedAt"] doubleValue];
        BOOL treeDue = now - checkedAt >= 20 || ([activity[root] doubleValue] > checkedAt && now - checkedAt >= 2)
            || [self.dueNow containsObject:root];
        BOOL prDue = gh && [branch isKindOfClass:NSString.class]
            && (now - [known[@"prCheckedAt"] doubleValue] >= 60 || ![known[@"prBranch"] isEqual:branch]);
        if (!treeDue && !prDue) continue;
        [self.dueNow removeObject:root];
        [self.reading addObject:root];
        dispatch_async(self.queue, ^{
            NSDictionary *tree = FetchCheckoutState(root);
            NSDictionary *counts = tree ? FetchChangeCounts(root, tree) : nil;
            // An extra stage that ran too long is left alone for a minute, so it can't hold up every checkout's read
            // (they share this queue) each time round.
            NSDictionary *stage = nil, *split = nil;
            BOOL ranStage = tree && stages && [self.slowUntil[root] doubleValue] <= now;
            if (ranStage) {
                stage = ReadStage(root, project, marks);
                if ([stage[@"slow"] boolValue]) self.slowUntil[root] = @(now + 60);
            }
            // While the extra stage holds something, the files stage counts only the files outside it; when it names
            // them, they're what its gauge splits and lists, in place of all of git's.
            if (stage[@"named"] && counts && [stage[@"stage"][@"count"] integerValue] > 0) {
                split = SplitNamed(stage[@"named"], tree, counts);
                NSMutableDictionary *withParts = [stage mutableCopy], *inStage = [stage[@"stage"] mutableCopy];
                inStage[@"parts"] = split[@"parts"];
                withParts[@"stage"] = inStage;
                stage = withParts;
            }
            BOOL prFound = NO;
            id pr = prDue ? FetchBranchPR(gh, root, branch, &prFound) : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.reading removeObject:root];
                NSMutableDictionary *entry = [self.known[root] mutableCopy] ?: [NSMutableDictionary dictionary];
                NSTimeInterval at = NSDate.date.timeIntervalSince1970;
                // A failed git status (worktree removed, repo moved) clears what was known rather than
                // leaving old changes up; a detached HEAD has no branch PR, so drop the previous branch's.
                id before = entry[@"changes"];
                if (tree) {
                    [entry removeObjectsForKeys:ReadKeys()];
                    NSMutableDictionary *details = [NSMutableDictionary dictionary];
                    for (NSDictionary *part in @[tree, counts ?: @{}, stage ?: @{}, split ?: @{}])
                        for (NSString *key in part) {
                            if ([DetailKeys() containsObject:key])
                                details[key] = part[key];
                            else if ([ReadKeys() containsObject:key])
                                entry[key] = part[key];
                        }
                    self.details[root] = details;
                    // Only a stage that ran says whether it works: one left alone this time says nothing.
                    if (ranStage) [self note:stage[@"problem"] in:root];
                } else {
                    [entry removeObjectsForKeys:ReadKeys()];
                    [self.details removeObjectForKey:root];
                }
                if (before && ![before isEqual:entry[@"changes"]])
                    PanelLog(@"checkout %@: %@ -> %@ uncommitted changes", root.lastPathComponent, before,
                             entry[@"changes"] ?: @"?");
                entry[@"checkedAt"] = @(at);
                if (![branch isKindOfClass:NSString.class]) [entry removeObjectsForKeys:@[@"pr", @"prBranch"]];
                if (prDue) {
                    // Retried after the usual 60s even when gh couldn't answer; a PR known for another
                    // branch is dropped rather than shown against this one.
                    if (prFound) entry[@"pr"] = pr;
                    else if (![entry[@"prBranch"] isEqual:branch]) [entry removeObjectForKey:@"pr"];
                    entry[@"prBranch"] = branch;
                    entry[@"prCheckedAt"] = @(at);
                }
                self.known[root] = entry;
            });
        });
    }
}

// Logs what went wrong with a checkout's extra stage once each time it changes, not on every read.
- (void)note:(NSString *)problem in:(NSString *)root {
    if ([problem isEqual:self.problems[root]] || (!problem && !self.problems[root])) return;
    if (problem) {
        self.problems[root] = problem;
        LogProblem([NSString stringWithFormat:@"extra stage in %@: %@", root, problem]);
    } else {
        [self.problems removeObjectForKey:root];
        PanelLog(@"extra stage in %@: working again", root);
    }
}

@end
