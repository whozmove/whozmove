// Checkouts: keeps each listed checkout's git status, extra stage and branch PR fresh.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Row, Core;

@interface Checkouts : NSObject
// Starts the git and gh reads that are due for the checkouts these sessions work in.
- (void)refreshFor:(NSArray<Row *> *)sessions;
// What's known about a checkout (its git root): {changes, ahead, behind, upstream, remotes, added, removed, base,
// aheadOfBase, newFiles, filesStaged, filesPartly, filesUnstaged, stage, pr, prBranch, checkedAt, prCheckedAt}, or nil
// before its first read.
- (NSDictionary *)stateOf:(NSString *)root;
// What only the island's menus and file lists need, from the last read: {files, newPaths, stagedPaths, partlyPaths,
// unstagedPaths, commits, menu, declined}, or nil.
- (NSDictionary *)detailsOf:(NSString *)root;
// Has the checkout read again on the next refresh, as something has just changed it.
- (void)readSoon:(NSString *)root;
// Whether extra stages are run and each branch's pull request is looked up: not while the islands, which show them,
// are switched off (Show Next Steps).
@property (atomic, assign) BOOL runsStages;
// The core, whose agentMarks (the marks agents put on their commands) are taken off an extra stage's command.
@property (weak) Core *core;
// Whether any read is still out. A test run waits until none is.
@property (readonly) BOOL checking;
@end
