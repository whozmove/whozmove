// AgentDetails: each session's model, effort, permission mode and context, and its Shift+Tab cycle.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Row;

@interface AgentDetails : NSObject
// Fills in a row's agent: {mode, model, effort, tokens, compactWindow}. `transcript` is what's been read of the
// session's transcript, and `chosen` what was picked for it in the panel and not confirmed yet.
- (void)describe:(Row *)row transcript:(NSDictionary *)transcript chosen:(NSDictionary *)chosen;
// Keeps the launch flags only of these rows' processes; the others have ended.
- (void)keepFlagsOf:(NSArray<Row *> *)rows;
// The Shift+Tab cycles a terminal session could have, and how many presses take it from one mode to another in
// all of them (-1 when that isn't certain).
- (NSArray<NSArray<NSString *> *> *)modeCyclesFor:(Row *)row;
- (NSInteger)shiftTabsFrom:(NSString *)from to:(NSString *)to cycles:(NSArray<NSArray<NSString *> *> *)cycles;
@end
