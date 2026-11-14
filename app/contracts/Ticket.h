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

// Another ticket named by this one: its parent (an epic, a project's issue, a task it's a subtask of), or one it's
// linked to, with how, in the tracker's own words for the link ("is blocked by", "relates to").
@interface TicketRef : NSObject
@property (copy) NSString *key, *title, *type, *how;
@end

// Someone on a ticket (who reported it, who it's assigned to, who moved it): the tracker's own id for their account, and
// their name as it shows it.
@interface TicketPerson : NSObject
@property (copy) NSString *personId, *name;
@end

// A board, team or project the ticket is on (one person can be on many, and a ticket on several), with the sprint or
// cycle it's in there, if any, and when that starts and ends, as the tracker writes a time (ISO 8601).
@interface TicketGroup : NSObject
@property (copy) NSString *groupId, *name, *kind, *sprint, *sprintStarts, *sprintEnds;
@end

// A move the ticket was given: from where to where, by its states' names, who made it and when (ISO 8601).
@interface TicketMoveMade : NSObject
@property (copy) NSString *from, *to, *at;
@property (strong) TicketPerson *by;
@end

// A field a step or a new ticket needs: its id as the tracker reads it, its name as people see it, its kind (`text`, a
// `number`, an `option` from `options`, a `person`, a `date`), whether it must be given, and whether it takes a list
// of them (`many`). A value for it is the same for every tracker: text, a number, an option's name as `options` gives
// it, or, where it takes many, a list of those; its tracker turns that into its own shape as it sends it.
@interface TicketField : NSObject
@property (copy) NSString *fieldId, *name, *kind;
@property BOOL required, many;
@property (copy) NSArray<NSString *> *options;
// Each option's id as the tracker reads it, in the order of `options`, when it gives them (a ticket's value names its
// option by that id, which stays when the option is renamed): empty when it doesn't.
@property (copy) NSArray<NSString *> *optionIds;
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
// Who reported it and who it's assigned to, by their accounts (`assignee` is the second's name alone); its labels; the
// other tickets it's linked to, each with how; and when it was last changed, as its tracker writes a time (ISO 8601).
@property (strong) TicketPerson *reporter, *assignedTo;
@property (copy) NSArray<NSString *> *labels;
@property (copy) NSArray<TicketRef *> *links;
@property (copy) NSString *updated;
// The moves it was given, oldest first, when it was read whole (Tracker's readWhole:): nil otherwise.
@property (copy) NSArray<TicketMoveMade *> *moves;
// Where its priority stands in its tracker's own list of priorities, the most pressing first (0 the top), and how many
// that list has, so tickets from trackers that name their priorities differently can be put in one order: each nil when
// its tracker gives no order, or hasn't read it yet.
@property (copy) NSNumber *priorityAt, *priorities;
@property (copy) NSArray<TicketStep *> *steps;
// The option it has, in each field of its own that takes one from a list (a team, a component of its project), by the
// field's id: {id, name}, the option's id and its name as people see it. Only for whoever asks: never in its JSON.
@property (copy) NSDictionary<NSString *, NSDictionary *> *values;
// Its description, as text (Markdown, or whatever its tracker writes it in), for the session working it to understand
// what's asked: only for whoever asks, never in its JSON, so no row, page, kept file or log line carries it. Nil when
// it has none, or its tracker gave none.
@property (copy) NSString *about;
// The ticket as JSON (for the page and for a session's ask): every word the tracker gave, as it gave it, for whoever
// shows it to escape. Never its description (`about`).
- (NSDictionary *)json;
// The same, with who reported it and who has it by their accounts, its labels, its links, when it changed, its
// sprint's dates and its moves: only for a session reading your tickets (`ask-panel.sh tickets`), never a row or the
// page.
- (NSDictionary *)jsonWhole;
@end

// How a tracker's answer ended, when it isn't what was asked: a sign-in is wanted (none, or run out), macOS asks you
// before it gives this build the sign-in it kept (your press of Allow, through signIn:), the tracker's
// admin turned Whozmove away, it asked to slow down (until `retryAt`), the ticket isn't there (or isn't yours to see),
// a step that's no longer one of the ticket's, it couldn't be done now, or the tracker turned away what it was given
// (a new ticket with a priority, a parent or a field that project doesn't take; a move with a field to fill in on the
// ticket first, or that isn't yours to make), which trying again as it is won't change; each with its why in plain
// words, never the tracker's own text. What the tracker itself said of one it turned away, when it said, is apart
// (`trackerSays`): for whoever shows it to escape, and given to a session only as JSON, never logged.
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
@property (copy) NSString *trackerSays;
// A list it left some out of, cut at the most its tracker reads at once.
@property BOOL more;
@property (readonly) BOOL ok;
@end
