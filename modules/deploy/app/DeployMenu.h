// DeployMenu: Deploy's menu behind its round button: what it runs, changing or forgetting that, passing on it, stopping
// a run, the last run's log, and the sessions that may ask for it, with the one asked for waiting, and your press kept
// while an agent works.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>

@class Core, Deploys, DeployAsks, DeployKept;

@interface DeployMenu : NSObject
- (instancetype)initWithCore:(Core *)core deploys:(Deploys *)deploys asks:(DeployAsks *)asks kept:(DeployKept *)kept;
// Deploy's round button ({step: "deploy", sessionId, x, y}): its menu opens below it.
- (void)menu:(NSDictionary *)msg;
@end
