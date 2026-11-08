// AgentDetails: each session's model, effort, permission mode and context, and its Shift+Tab cycle.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Row;

@interface AgentDetails : NSObject
// Fills in a row's agent: {mode, model, effort, tokens, window, compactWindow}. `transcript` is what's been read of the
// session's transcript, and `chosen` what was picked for it in the panel and not confirmed yet.
- (void)describe:(Row *)row transcript:(NSDictionary *)transcript chosen:(NSDictionary *)chosen;
// Keeps the launch flags only of these rows' processes; the others have ended.
- (void)keepFlagsOf:(NSArray<Row *> *)rows;
// The Shift+Tab cycles a terminal session could have, and how many presses take it from one mode to another in
// all of them (-1 when that isn't certain).
- (NSArray<NSArray<NSString *> *> *)modeCyclesFor:(Row *)row;
- (NSInteger)shiftTabsFrom:(NSString *)from to:(NSString *)to cycles:(NSArray<NSArray<NSString *> *> *)cycles;
// Why a session's process might bypass permissions, now or after a Shift+Tab, or nil only once that's ruled out: its
// own flags (read afresh: flags that can't be read can't rule it out), a --settings file or JSON, the project's
// settings, yours and the machine's managed settings, and the mode it's in. Stricter than modeCyclesFor:, which only
// counts presses, as it guards what a plan approved from the panel goes back to.
- (NSString *)whyBypassPossible:(Row *)row process:(pid_t)pid;
@end
