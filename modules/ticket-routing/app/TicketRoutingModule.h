// TicketRoutingModule: where a ticket given to a new conversation starts, for each project: its own worktree, the
// project's folder, or by one of its tickets' fields (TicketRoutingModule.m says how). Its face for the core is
// Module's; what's here is for its print run (TicketRoutingPrints.m), which drives it as the core and the page would.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Module.h"
#import "Tracker.h"

@interface TicketRoutingModule : NSObject <Module>
@property (weak) Core *core;
// Each project's way, as kept: {project: {runs, at}}.
@property (strong, readonly) NSMutableDictionary<NSString *, NSDictionary *> *routes;
// The trackers, as the core finds them (modulesThat: Tracker), unless a print run gives its own; and what each answer
// for the page is handed to, unless it's the page's ticketRouted.
@property (copy) NSArray<id<Tracker>> *givenTrackers;
@property (copy) void (^answered)(NSDictionary *answer);
// The ways are kept in this file (AppDir/ticket-routing/routes.json as it launches), and what's there is read.
- (void)keepIn:(NSString *)path;
// The page's asks, as its messages bring them.
- (void)route:(NSDictionary *)msg;
- (void)setRoute:(NSDictionary *)msg;
// What the rows say, for before and after: the tickets the project's own conversations work in its folder.
@property (copy) NSArray<Row *> *rowsSeen;
@end

// Its print modes, for the tests (TicketRoutingPrints.m).
NSDictionary<NSString *, PrintMode> *TicketRoutingPrintModes(void);
