// TicketReads: what the conversations working in a project read of your tickets (`ask-panel.sh tickets`), as plain
// functions, so the tests check every case without the app. A project reads every ticket you can see, through Whozmove,
// once a conversation there has worked one of your tickets, or you've turned reading on for it in Settings ▸ Tickets,
// until you turn it off there; the projects are kept by their folders.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Ticket.h"

// The projects you've turned reading off for, those you've turned it on for, and those where a conversation has been
// given one of your tickets (Use It, or a conversation started from one), read back and checked ({"off": [folder],
// "on": [folder], "worked": [folder]}, each a full path), and kept where only you can read it (0600); NO when it
// couldn't be written.
NSSet<NSString *> *TicketReadsKept(NSString *path, NSString *which);
BOOL TicketReadsWrite(NSString *path, NSSet<NSString *> *off, NSSet<NSString *> *on, NSSet<NSString *> *worked);

// Whether a project's conversations read your tickets: never outside a project (nil: a folder that isn't a repo's, or
// none); as you turned it for that project; else only once a conversation there has worked one of your tickets.
BOOL TicketReadsIn(NSString *project, NSSet<NSString *> *off, NSSet<NSString *> *on, NSSet<NSString *> *worked);
// What a conversation in a project that reads none is told (`name`, the project's folder's name): that you turned it
// off, or, for one never turned on, that it reads none until you turn it on; each says where.
NSString *TicketReadsRefusal(NSString *name, BOOL turnedOff);

// The row's `ticket` (TicketShown's) with what Use It or Create Ticket would also do, for a session in a project that
// doesn't read your tickets yet and isn't turned off (`project`, its folder's name; nil leaves it as it is): its offer
// and its draft each say `reads`, {project, tracker}, so their cards say pressing also lets that project's
// conversations read your tickets.
NSDictionary *TicketReadsAlso(NSDictionary *shown, NSString *project, NSString *tracker);

// What every answer with tickets in it says first, so their words are never taken as asks.
extern NSString *const kTicketWordsNote;

// The time a conversation asks for only what changed since, as ISO 8601 (2030-01-06T06:30:00Z, with or without its
// fraction of a second, or an offset): nil for anything else, or a time still to come.
NSDate *TicketsSince(NSString *text);

// The answer to `tickets`: a first line, {readAt, tickets, since, more}, when they were read (to give as --since next
// time), how many follow and, when its tracker cut the list at the most it reads, that there are more; then each ticket
// as one line of JSON, as Ticket's jsonWhole gives it, without its next steps, which aren't read for a list. And to
// `tickets --full KEY`: the ticket as one line, likewise, with its description and the moves it was given, left out
// when its tracker didn't say them.
// The lines stop before `mostBytes` (one send down the ask's line), saying there are more.
NSString *TicketsRead(NSArray<Ticket *> *tickets, NSDate *readAt, NSDate *since, BOOL more, NSUInteger mostBytes);
NSString *TicketWhole(Ticket *ticket);
// Why they couldn't be read, as told: "waiting: …" while the tracker asked to slow down, with when to ask again, so a
// --wait waits through it; when a read failed, on which sites, the tracker's why, and to ask again in a minute; else "can't now: …"
// with the tracker's why.
NSString *TicketsNotRead(TrackerAnswer *answer, NSArray<NSString *> *sites);
