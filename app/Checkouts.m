// Checkouts: keeps each listed checkout's git status and branch PR fresh.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Checkouts.h"
#import "Row.h"
#import "Log.h"
#import "Git.h"
#import "GitHub.h"

@interface Checkouts ()
// Per checkout (git root), what's known about it. Touched on the main thread only; git and gh run on the queue.
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *known;
@property (strong) NSMutableSet<NSString *> *reading;  // the checkouts being read now
@property (strong) dispatch_queue_t queue;
@end

@implementation Checkouts

- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.known = [NSMutableDictionary dictionary];
    self.reading = [NSMutableSet set];
    self.queue = dispatch_queue_create("whozmove.checkouts", DISPATCH_QUEUE_SERIAL);
    return self;
}

- (NSDictionary *)stateOf:(NSString *)root {
    return self.known[root];
}

- (BOOL)checking {
    return self.reading.count > 0;
}

// Keeps each listed checkout's real state fresh, for the panel's "current action". Git status is read every 20s,
// and within 2s of any activity by a session working there (a tool call, Claude stopping), so a commit an agent
// just made isn't shown against the uncommitted changes from before it. The branch's PR (state, checks, reviews)
// is read every 60s, or as soon as the branch changes.
- (void)refreshFor:(NSArray<Row *> *)sessions {
    NSString *gh = GhPath();
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSMutableDictionary<NSString *, id> *branches = [NSMutableDictionary dictionary];  // root -> branch or NSNull
    NSMutableDictionary<NSString *, NSNumber *> *activity = [NSMutableDictionary dictionary];  // root -> latest, in s
    for (Row *row in sessions) {
        NSDictionary *git = row.workGit ?: row.git;
        if (![git isKindOfClass:NSDictionary.class] || ![git[@"root"] isKindOfClass:NSString.class]) continue;
        branches[git[@"root"]] = git[@"branch"] ?: NSNull.null;
        double latest = MAX(row.stageAt.doubleValue,
                            MAX(row.lastReplyAt.doubleValue, row.outcomeAt.doubleValue)) / 1000;
        activity[git[@"root"]] = @(MAX(latest, [activity[git[@"root"]] doubleValue]));
    }
    // A listed checkout is read at least every 20s, so one not read for a minute has no session working in it.
    for (NSString *root in self.known.allKeys)
        if (!branches[root] && now - [self.known[root][@"checkedAt"] doubleValue] > 60)
            [self.known removeObjectForKey:root];
    for (NSString *root in branches) {
        if ([self.reading containsObject:root]) continue;
        NSDictionary *known = self.known[root];
        id branch = branches[root];
        double checkedAt = [known[@"checkedAt"] doubleValue];
        BOOL treeDue = now - checkedAt >= 20 || ([activity[root] doubleValue] > checkedAt && now - checkedAt >= 2);
        BOOL prDue = gh && [branch isKindOfClass:NSString.class]
            && (now - [known[@"prCheckedAt"] doubleValue] >= 60 || ![known[@"prBranch"] isEqual:branch]);
        if (!treeDue && !prDue) continue;
        [self.reading addObject:root];
        dispatch_async(self.queue, ^{
            NSDictionary *tree = FetchCheckoutState(root);
            BOOL prFound = NO;
            id pr = prDue ? FetchBranchPR(gh, root, branch, &prFound) : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.reading removeObject:root];
                NSMutableDictionary *entry = [self.known[root] mutableCopy] ?: [NSMutableDictionary dictionary];
                NSTimeInterval at = NSDate.date.timeIntervalSince1970;
                // A failed git status (worktree removed, repo moved) clears what was known rather than
                // leaving old changes up; a detached HEAD has no branch PR, so drop the previous branch's.
                id before = entry[@"changes"];
                [entry removeObjectsForKeys:@[@"changes", @"ahead", @"behind", @"upstream", @"remotes"]];
                if (tree) [entry addEntriesFromDictionary:tree];
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

@end
