// DeployMenu: Deploy's menu behind its round button: what it runs, changing or forgetting that, passing on it, stopping
// a run, and the last run's log.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>

@class Core, Deploys;

@interface DeployMenu : NSObject
- (instancetype)initWithCore:(Core *)core deploys:(Deploys *)deploys;
// Deploy's round button ({step: "deploy", sessionId, x, y}): its menu opens below it.
- (void)menu:(NSDictionary *)msg;
@end
