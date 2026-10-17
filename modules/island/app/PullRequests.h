// PullRequests: the PRs each session made or worked on, and their state.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Core, Row;

@interface PullRequests : NSObject
// The PRs are the ones each session's agent recorded (AgentWork's prLinksOf:), for the sessions listed now.
@property (weak) Core *core;
@property (copy) NSArray<Row *> *rows;
// Asks GitHub about each listed session's PRs that are due a check.
- (void)check;
// A session's PRs with what's known about them, newest first.
- (NSArray *)prsFor:(Row *)row;
@end
