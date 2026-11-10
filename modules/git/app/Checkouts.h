// Checkouts: keeps each listed checkout's git status and branch PR fresh.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Row;

// Whether a checkout's git status is due a read, `since` seconds after its last: every 20s, and 2s after a session's
// activity there (`activeSince`), when it isn't `watched`; watched, on that schedule only once something in it has
// `changed`, and every `quietEvery` seconds anyway. Plain, for the tests.
BOOL CheckoutReadDue(BOOL watched, BOOL changed, NSTimeInterval since, BOOL activeSince, NSTimeInterval quietEvery);

// Whether a checkout's branch can have a pull request of its own, to look up and keep: a branch, and not the repo's
// base branch (`base`, its default, as last read), which pull requests go into rather than come from, and the next
// steps never offer Create PR there. Plain, for the tests.
BOOL BranchHasOwnPR(NSString *branch, NSString *base);

// Whether a checkout's branch is due its pull request's look-up, `since` seconds after the last: every 60s, or at once
// for a branch other than the one last looked up (`lookedUp`); never for one that can't have a PR of its own
// (BranchHasOwnPR). Plain, for the tests.
BOOL BranchPRDue(NSString *branch, NSString *base, NSString *lookedUp, NSTimeInterval since);

@interface Checkouts : NSObject
// Starts the git and gh reads that are due for the checkouts these sessions work in.
- (void)refreshFor:(NSArray<Row *> *)sessions;
// What's known about a checkout (its git root): {changes, ahead, behind, upstream, remotes, added, removed, base,
// aheadOfBase, newFiles, filesStaged, filesPartly, filesUnstaged, pr, prBranch, checkedAt, prCheckedAt}, or nil before
// its first read.
- (NSDictionary *)stateOf:(NSString *)root;
// Has the checkout read again on the next refresh, as something has just changed it.
- (void)readSoon:(NSString *)root;
// Whether each branch's pull request is looked up: not while the next steps, which go by it, are switched off (Show
// Next Steps).
@property (atomic, assign) BOOL looksUpPRs;
// Whether any read is still out. A test run waits until none is.
@property (readonly) BOOL checking;
@end
