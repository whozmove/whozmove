// Checkouts: keeps each listed checkout's git status and branch PR fresh.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Checkouts.h"
#import "Row.h"
#import "Log.h"
#import "Git.h"
#import "GitHub.h"
#import "CheckoutWatch.h"

// What a read finds that goes to the page as part of a row's checkout, apart from the PR: cleared before each read's
// results go in, so nothing a failed read couldn't confirm stays up.
static NSArray<NSString *> *ReadKeys(void) {
    return @[@"changes", @"ahead", @"behind", @"upstream", @"remotes", @"base", @"baseRef", @"aheadOfBase",
             @"newFiles", @"filesStaged", @"filesPartly", @"filesUnstaged", @"headAt"];
}

BOOL CheckoutReadDue(BOOL watched, BOOL changed, NSTimeInterval since, BOOL activeSince, NSTimeInterval quietEvery) {
    BOOL timely = since >= 20 || (activeSince && since >= 2);
    return watched ? (changed && timely) || since >= quietEvery : timely;
}

BOOL BranchHasOwnPR(NSString *branch, NSString *base) {
    return [branch isKindOfClass:NSString.class] && ![branch isEqual:base];
}

BOOL BranchPRDue(NSString *branch, NSString *base, NSString *lookedUp, NSTimeInterval since) {
    return BranchHasOwnPR(branch, base) && (since >= 60 || ![lookedUp isEqual:branch]);
}


@interface Checkouts ()
// Per checkout (git root), what's known about it. Touched on the main thread only; git and gh run on the queue.
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *known;
@property (strong) NSMutableSet<NSString *> *reading;  // the checkouts being read now
@property (strong) NSMutableSet<NSString *> *dueNow;   // read on the next refresh, whatever the time (readSoon:)
// Each checkout's CheckoutFileChanges and CheckoutRefChanges as its last read started, and each repo's (by its main
// checkout) remotes and base branch, which hardly ever change, kept with its CheckoutRepoChanges as they were read:
// {at, remoteNames, baseBranch}.
@property (strong) NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *seen;
@property (strong) NSMutableDictionary<NSString *, NSNumber *> *listedAt;  // when each was last listed
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *repos;
@property (strong) dispatch_queue_t queue;
@end

@implementation Checkouts

- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.known = [NSMutableDictionary dictionary];
    self.reading = [NSMutableSet set];
    self.dueNow = [NSMutableSet set];
    self.seen = [NSMutableDictionary dictionary];
    self.listedAt = [NSMutableDictionary dictionary];
    self.repos = [NSMutableDictionary dictionary];
    self.queue = dispatch_queue_create("whozmove.checkouts", DISPATCH_QUEUE_SERIAL);
    self.looksUpPRs = YES;
    return self;
}

- (NSDictionary *)stateOf:(NSString *)root {
    return self.known[root];
}

- (void)readSoon:(NSString *)root {
    if (root) [self.dueNow addObject:root];
}

- (BOOL)checking {
    return self.reading.count > 0;
}

// Keeps each listed checkout's real state fresh, for the row's next steps. Git status is read every 20s, and within 2s
// of any activity by a session working there (a tool call, Claude stopping), so a commit an agent just made isn't shown
// against the uncommitted changes from before it; but once macOS tells its changes (CheckoutWatch), only after
// something in it has changed since its last read, and every 5 minutes or so anyway, in case an event was missed
// (CheckoutReadDue). While the next steps are on (Show Next Steps), the branch's PR (state, checks, reviews) is read
// every 60s, or as soon as the branch changes, once the branch is on GitHub: one never pushed has none.
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
    WatchCheckouts(@"checkouts", [NSSet setWithArray:branches.allKeys]);
    // A checkout no session works in any longer is forgotten a minute after it was last listed, so a row missing for a
    // moment, or a session started again there, finds it as it was.
    for (NSString *root in branches) self.listedAt[root] = @(now);
    for (NSString *root in self.listedAt.allKeys)
        if (!branches[root] && now - self.listedAt[root].doubleValue > 60) {
            [self.listedAt removeObjectForKey:root];
            [self.known removeObjectForKey:root];
            [self.seen removeObjectForKey:root];
        }
    BOOL prs = self.looksUpPRs;
    for (NSString *root in branches) {
        if ([self.reading containsObject:root]) continue;
        NSDictionary *known = self.known[root];
        id branch = branches[root];
        // On the base branch, as last read, there's no PR of its own to keep: another branch's from before a switch,
        // or one whose look-up landed just after it, goes at once, with no gh, so a session that waits on its PR
        // never takes it (PRWakes).
        if (!BranchHasOwnPR(branch, known[@"base"]) && (known[@"pr"] || known[@"prBranch"])) {
            NSMutableDictionary *entry = [known mutableCopy];
            [entry removeObjectsForKeys:@[@"pr", @"prBranch"]];
            self.known[root] = known = entry;
        }
        double checkedAt = [known[@"checkedAt"] doubleValue];
        BOOL watched = CheckoutWatched(root);
        NSArray *counts = @[@(CheckoutFileChanges(root)), @(CheckoutRefChanges(root))];
        BOOL changed = ![self.seen[root] isEqualToArray:counts];
        BOOL treeDue = CheckoutReadDue(watched, changed, now - checkedAt, [activity[root] doubleValue] > checkedAt,
                                       CheckoutQuietEvery(root))
            || [self.dueNow containsObject:root];
        // The branch's PR is only for the next steps, so it isn't looked up while they're off, nor on the repo's base
        // branch, as last read, where they never offer one (BranchPRDue).
        BOOL prDue = prs && gh && BranchPRDue(branch, known[@"base"], known[@"prBranch"],
                                              now - [known[@"prCheckedAt"] doubleValue]);
        if (!treeDue && !prDue) continue;
        [self.reading addObject:root];
        if (treeDue) {
            [self.dueNow removeObject:root];
            self.seen[root] = counts;
        }
        // The repo's remotes and base branch, as last read, while nothing they come from has changed since, as macOS
        // tells it; asked again by a read that comes with nothing changed, the one every few minutes in case an event
        // was missed, and kept only from a read whose checkout was watched as it started.
        NSString *repo = ProjectRoot(root) ?: root;
        NSUInteger repoAt = CheckoutRepoChanges(root);
        NSDictionary *kept = watched && changed && [self.repos[repo][@"at"] isEqual:@(repoAt)] ? self.repos[repo] : nil;
        // A PR's turn alone leaves the checkout's state as it was read last.
        BOOL upstreamKnown = [known[@"upstream"] boolValue];
        dispatch_async(self.queue, ^{
            NSDictionary *tree = treeDue ? FetchCheckoutState(root, kept[@"remoteNames"]) : nil;
            NSDictionary *counts = tree ? FetchChangeCounts(root, kept[@"baseBranch"]) : nil;
            // A branch never pushed (no upstream on a remote, no copy on one) has no PR to ask GitHub for.
            BOOL pushed = [branch isKindOfClass:NSString.class]
                && ((treeDue ? [tree[@"upstream"] boolValue] : upstreamKnown) || BranchOnRemote(root, branch));
            BOOL prFound = NO;
            id pr = prDue && pushed ? FetchBranchPR(gh, root, branch, &prFound) : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.reading removeObject:root];
                if (watched && tree[@"remoteNames"] && counts[@"baseBranch"])
                    self.repos[repo] = @{@"at": @(repoAt), @"remoteNames": tree[@"remoteNames"],
                                         @"baseBranch": counts[@"baseBranch"]};
                NSMutableDictionary *entry = [self.known[root] mutableCopy] ?: [NSMutableDictionary dictionary];
                NSTimeInterval at = NSDate.date.timeIntervalSince1970;
                // A failed git status (worktree removed, repo moved) clears what was known rather than
                // leaving old changes up; a detached HEAD has no branch PR, so drop the previous branch's.
                if (treeDue) {
                    id before = entry[@"changes"];
                    [entry removeObjectsForKeys:ReadKeys()];
                    for (NSDictionary *part in @[tree ?: @{}, counts ?: @{}])
                        for (NSString *key in part)
                            if ([ReadKeys() containsObject:key]) entry[key] = part[key];
                    if (before && ![before isEqual:entry[@"changes"]])
                        PanelLog(@"checkout %@: %@ -> %@ uncommitted changes", root.lastPathComponent, before,
                                 entry[@"changes"] ?: @"?");
                    entry[@"checkedAt"] = @(at);
                }
                // The base branch has no PR of its own to show either (BranchHasOwnPR, with the base this read found),
                // so the one a launch's first read may ask for, before the base is known, goes too.
                if (!BranchHasOwnPR(branch, entry[@"base"])) [entry removeObjectsForKeys:@[@"pr", @"prBranch"]];
                else if (!pushed && prs && gh) {
                    // Not on GitHub: it has no PR, as gh would say (so Create PR is there as soon as it's pushed),
                    // and an old branch's goes at once.
                    entry[@"pr"] = NSNull.null;
                    entry[@"prBranch"] = branch;
                    if (prDue) entry[@"prCheckedAt"] = @(at);
                } else if (prDue) {
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
