// Stages: a checkout's extra stage, between your edits and your commits on its row's island. A command the checkout's
// own git config names (whozmove.stage) says what the stage holds and what can be done with it; Whozmove runs it only
// once you've allowed it in the panel, and asks again whenever it changes (docs/reference/stages.md).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Core, Checkouts, Row;

// What a checkout's extra stage holds now, for the checkouts' queue: {stage: {count, label, edits}, menu: {header,
// items, more, actions}, named} once allowed and run, `named` being the files outside it when it names them all;
// {stage: {ask: command}} before you've said; {declined: command} after Not Now; {slow: YES} when it ran too long; nil
// without one. Anything that went wrong is in {problem}. `project` is the main checkout, which holds the config every
// worktree shares; `marks`, the marks agents put on their commands, taken off its command (the core's agentMarks).
// Blocking.
NSDictionary *ReadStage(NSString *root, NSString *project, NSArray<NSString *> *marks);

@interface Stages : NSObject
// The core gives the page, and the marks agents put on their commands, which are taken off the stage's own.
- (instancetype)initWithCore:(Core *)core checkouts:(Checkouts *)checkouts;
// The trust card's answer, {command, allow}: run this command for the project's extra stage, or not.
- (void)trust:(NSDictionary *)msg row:(Row *)row;
// From the menus: Stop This Stage (Not Now, until the command changes), and Ask About It Again (the card comes back).
- (void)stop:(Row *)row;
- (void)askAgain:(Row *)row;
// One of the stage's own actions that runs a command, {title, run}, chosen from its menu.
- (void)run:(NSDictionary *)action row:(Row *)row;
// What's running from this checkout's menu now, by its title, or nil.
- (NSString *)runningIn:(NSString *)root;
@end
