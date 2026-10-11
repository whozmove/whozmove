// Checkouts: keeps each listed checkout's git status and branch PR fresh.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Row;

@interface Checkouts : NSObject
// Starts the git and gh reads that are due for the checkouts these sessions work in.
- (void)refreshFor:(NSArray<Row *> *)sessions;
// What's known about a checkout (its git root): {changes, ahead, behind, upstream, remotes, pr, prBranch,
// checkedAt, prCheckedAt}, or nil before its first read.
- (NSDictionary *)stateOf:(NSString *)root;
// Whether any read is still out. A test run waits until none is.
@property (readonly) BOOL checking;
@end
