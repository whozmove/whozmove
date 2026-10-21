// Usage: how much of your Claude plan you've used, in the five-hour session and the week, asked of Claude Code itself
// for the usage card under the panel.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import "Host.h"
#import "Agent.h"

@class PanelWindow, UsageCard;

@interface Usage : NSObject
// Asked of the agent (AgentUsage), for the card's page.
- (instancetype)initWithCard:(UsageCard *)card window:(PanelWindow *)window agent:(id<AgentUsage>)agent;
// From the 1-second tick: asks the agent when a check is due.
- (void)pollIfDue;
// The card's page, freshly loaded, gets what's known.
- (void)resend;
// The card's Sign in: a tab signing the agent in, in `terminal` (the first on this Mac that runs a command), then a
// check every 15 seconds until it has.
- (void)signInWith:(id<CommandHost>)terminal;
@end
