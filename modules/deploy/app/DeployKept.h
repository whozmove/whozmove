// DeployKept: your press of Deploy while an agent is at work in the checkout, kept until it's done, then run as a press
// runs, everything checked again. In the app's memory only, so a restart of Whozmove drops it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Core, Deploys, Row;

@interface DeployKept : NSObject
- (instancetype)initWithCore:(Core *)core deploys:(Deploys *)deploys;
// A press of Deploy on `row` while it waits (Deploys' whyNotNow:): kept for its folder, with the command you confirmed
// for the project, replacing one kept there before. NO, and nothing kept, when the project has no command.
- (BOOL)keep:(Row *)row;
// Each second: each press kept runs once nothing holds it up (Deploys' deploy:, which checks the port and what the
// command runs), and goes once its session isn't listed, the checkout has gone or isn't its session's now, the
// project's command has changed or been forgotten, Deploy is hidden, or a deploy has run there since. What was
// decided for each folder at the last look ("would run now", "Deploy waits …", "dropped, as …"), for the tests.
- (void)tick;
@property (readonly) NSDictionary<NSString *, NSString *> *decided;
// The press kept in a folder, {sessionId, command, at}, or nil; Don't Deploy, from Deploy's menu, drops it.
- (NSDictionary *)keptIn:(NSString *)folder;
- (void)dropIn:(NSString *)folder;
@end
