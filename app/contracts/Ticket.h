// Ticket: one ticket as a tracker gives it (Jira's issue, Linear's issue, Asana's task), the same shape for every
// tracker, and what a tracker's answer says when it isn't a ticket. Nothing here knows a status by name: a ticket's
// state is the tracker's own name for it and one of four kinds, and its next steps are the tracker's, each with an id
// only it reads.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// The four kinds every tracker's states fall into, as the list colours them: to do, under way, done, dropped (Jira's
// status categories; Linear's state types, its triage and backlog counted as to do; Asana's completed flag).
typedef NS_ENUM(NSInteger, TicketKind) {
    TicketKindToDo,
    TicketKindUnderWay,
    TicketKindDone,
    TicketKindDropped,
};
// How a kind is written in JSON, for the page and for a session: todo, doing, done, dropped.
NSString *TicketKindWord(TicketKind kind);

// Where a ticket stands, or where a step leads: the tracker's own name for it, and its kind.
@interface TicketState : NSObject
+ (instancetype)named:(NSString *)name kind:(TicketKind)kind;
@property (readonly, copy) NSString *name;
@property (readonly) TicketKind kind;
@end

// Another ticket named by this one: its parent (an epic, a project's issue, a task it's a subtask of).
@interface TicketRef : NSObject
@property (copy) NSString *key, *title, *type;
@end

// A board, team or project the ticket is on (one person can be on many, and a ticket on several), with the sprint or
// cycle it's in there, if any.
@interface TicketGroup : NSObject
@property (copy) NSString *groupId, *name, *kind, *sprint;
@end

// A field a step or a new ticket needs: its id as the tracker reads it, its name as people see it, its kind (`text`, a
// `number`, an `option` from `options`, a `person`, a `date`), whether it must be given, and whether it takes a list
// of them (`many`). A value for it is the same for every tracker: text, a number, an option's name as `options` gives
// it, or, where it takes many, a list of those; its tracker turns that into its own shape as it sends it.
@interface TicketField : NSObject
@property (copy) NSString *fieldId, *name, *kind;
@property BOOL required, many;
@property (copy) NSArray<NSString *> *options;
@end

// One of a ticket's next steps, as its tracker gives it for that ticket now: an id only the tracker reads, the step's
// name, where it leads, and the fields it needs.
@interface TicketStep : NSObject
@property (copy) NSString *stepId, *name;
@property (strong) TicketState *to;
@property (copy) NSArray<TicketField *> *needs;
@end

@interface Ticket : NSObject
// Its tracker's name, the site it's on, its key as people write it (PAY-142), the tracker's own id, its title, its
// address, and its type (Bug, Story).
@property (copy) NSString *tracker, *site, *key, *ticketId, *title, *link, *type;
@property (strong) TicketState *state;
@property (strong) TicketRef *parent;
@property (copy) NSArray<TicketGroup *> *groups;
@property (copy) NSString *priority, *assignee;
@property (copy) NSArray<TicketStep *> *steps;
// The ticket as JSON (for the page and for a session's ask): every word the tracker gave, as it gave it, for whoever
// shows it to escape.
- (NSDictionary *)json;
@end

// How a tracker's answer ended, when it isn't what was asked: a sign-in is wanted (none, or run out), macOS asks you
// before it gives this build the sign-in it kept (your press of Allow, through signIn:), the tracker's
// admin turned Whozmove away, it asked to slow down (until `retryAt`), the ticket isn't there (or isn't yours to see),
// a step that's no longer one of the ticket's, it couldn't be done now, or the tracker turned away what it was given
// (a new ticket with a priority, a parent or a field that project doesn't take), which trying again as it is won't
// change; each with its why in plain words, never the tracker's own text.
typedef NS_ENUM(NSInteger, TrackerEnd) {
    TrackerEndDone,
    TrackerEndSignIn,
    TrackerEndAsksMac,
    TrackerEndBlocked,
    TrackerEndSlowDown,
    TrackerEndNotFound,
    TrackerEndStepGone,
    TrackerEndFailed,
    TrackerEndRefused,
};

@interface TrackerAnswer : NSObject
+ (instancetype)done;
+ (instancetype)end:(TrackerEnd)end why:(NSString *)why;
@property (readonly) TrackerEnd end;
@property (readonly, copy) NSString *why;
@property (strong) NSDate *retryAt;
@property (readonly) BOOL ok;
@end
