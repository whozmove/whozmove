// NextSteps: the steps a row's checkout has to take, as git sees it (Commit and its ways, Push, Publish, Create PR into
// the branch you pick), each asked of the session's agent in fixed words; and the branches GitHub's copy has, for
// Create PR's card.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>

@class Core;

@interface NextSteps : NSObject
// The steps ask the agent through the core (its Send), which has the rows and the page too.
- (instancetype)initWithCore:(Core *)core;
// A step pressed on a row or in the changes view ({sessionId, step, into}: commit, push, publish, pr or draftPR; `into`,
// the branch a pull request goes into, else the repo's default): asked of the agent in its fixed words, only if the
// checkout as last read has it to take, `into` is one of the repo's branches on GitHub, and nothing waits (if something
// does, the row says why).
- (void)takeStep:(NSDictionary *)msg;
// The ways to commit, in a menu where the changes view's ⌄ is ({sessionId, x, y}): Commit, Commit and Push, Commit and
// Open a Pull Request.
- (void)commitMenu:(NSDictionary *)msg;
// The branches GitHub's copy of the row's repo has, as this Mac last fetched them, for Create PR's card ({sessionId}):
// read off the main thread, and sent with setPRBranches(sid, {base, branches}).
- (void)branchesFor:(NSDictionary *)msg;
@end
