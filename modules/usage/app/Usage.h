// Usage: how much of your Claude plan you've used, in the five-hour session and the week, asked of Claude Code itself
// for the strip at the bottom of the panel.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import "Host.h"
#import "Agent.h"

@class Page, PanelWindow;

@interface Usage : NSObject
// Asked of the agent (AgentUsage).
- (instancetype)initWithPage:(Page *)page window:(PanelWindow *)window agent:(id<AgentUsage>)agent;
// From the 1-second tick: asks the agent when a check is due.
- (void)pollIfDue;
// A freshly loaded page gets what's known.
- (void)resend;
// The strip's Sign in: a tab signing the agent in, in `terminal` (the first on this Mac that runs a command), then a
// check every 15 seconds until it has.
- (void)signInWith:(id<CommandHost>)terminal;
@end
