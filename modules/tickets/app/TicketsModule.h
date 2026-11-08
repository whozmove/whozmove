// TicketsModule: tickets for sessions, from any tracker, never naming one (TicketsModule.m says how). Its face for the
// core is Module's; what's here is for its print run (TicketsPrints.m), which drives it as the core and the page would.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Module.h"
#import "Tracker.h"

@interface TicketsModule : NSObject <Module>
@property (weak) Core *core;
// The trackers, as the core finds them, unless a print run gives its own.
@property (copy) NSArray<id<Tracker>> *givenTrackers;
// Bindings are kept in this folder (AppDir/tickets as it launches), and what's there is read, to offer back.
- (void)keepIn:(NSString *)folder;
// What a session asks (ticket-use, ticket, ticket-move from its process, ticket-stop), and your answers on its row (use
// or notNow; move or notNow, for the move its card showed), as the core and the page say them.
- (NSString *)use:(NSDictionary *)asked from:(Row *)row;
- (NSString *)ticketFor:(Row *)row;
- (NSString *)move:(NSDictionary *)asked from:(Row *)row process:(pid_t)process;
- (NSString *)stop:(NSDictionary *)asked from:(Row *)row;
- (void)answer:(NSString *)act for:(NSString *)sessionId;
- (void)moveAnswer:(NSString *)act for:(NSString *)sessionId key:(NSString *)key step:(NSString *)stepId
                at:(NSNumber *)at;
// A new ticket a session drafts (ticket-draft), and your answer on its card (create, which is Try Again until its
// tracker has checked it, or notYet, for the draft that card showed, by when it was asked: draftAskedAt).
- (NSString *)draft:(NSDictionary *)asked from:(Row *)row;
- (void)draftAnswer:(NSString *)act for:(NSString *)sessionId at:(NSNumber *)at;
- (NSNumber *)draftAskedAt:(NSString *)sessionId;
// When the move waiting on a session's row was asked, as its card has it (`at`, in milliseconds); nil for none.
- (NSNumber *)moveAskedAt:(NSString *)sessionId;
// Reads a session's ticket again, unless it was tried less than `after` seconds ago, or its tracker asked to wait
// (unless `now`): Try Again on its card reads it at once.
- (void)read:(NSString *)sessionId after:(NSTimeInterval)after ignoringWait:(BOOL)now;
@end

// Its print modes, for the tests (TicketsPrints.m).
NSDictionary<NSString *, PrintMode> *TicketsPrintModes(void);
