// PRWakes: the pull request a waiting session waits on, and what has come on it since its wait began (a review, a
// comment, a merge, a close), for the waits module through contracts/Wake.h. It knows nothing of waiting: only which
// session's pull request to watch, and from when.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Wake.h"

@class PullRequests, Row;

@interface PRWakes : NSObject
// The PRs each session linked, newest first, for one whose branch has none.
@property (weak) PullRequests *pullRequests;
// A session's pull request: its branch's, while open, else the newest open one it linked; with why it can't be read
// now. Nil for one with none.
- (WaitOn *)waitsOn:(Row *)row;
// Watches the pull request the wait began on (its options' `on`), else the session's own; NO for one with none.
- (BOOL)watch:(Row *)row since:(double)since options:(NSDictionary *)options;
- (void)unwatch:(NSString *)sessionId;
// What came on it after its watch began, oldest first: approvals, reviews asking for changes, merges and closes always
// (and a merge or close from just before the wait, as it's first read so); comments and commenting reviews only for a
// wait that asked for comments.
- (NSArray<Wake *> *)wakesFor:(NSString *)sessionId;
// Asks gh about each watched pull request once a minute, on a queue of its own.
- (void)check;
// What gh said of a pull request, as FetchPRActivity gives it, or nil when it couldn't answer: for the tests, and for
// what check found.
- (void)took:(NSDictionary *)activity for:(NSString *)url;
@end
