// InboxRecord: what the inbox keeps (AppDir/inbox/inbox.json), as plain functions over the record: a message kept for
// a team's lead, the order its lead reads them in, the next one and its answer, the line that tells the lead one waits
// and that line's fate joined back to its message, the week's counts of what went astray, and what goes once it's old.
// Nothing here reads a file or the clock: the module gives each the record and the time.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// The priorities a sender sets, most pressing first, and the most each part of a message may be.
extern NSArray<NSString *> *const InboxPriorities;
extern const NSUInteger InboxMostText, InboxMostAbout, InboxMostNote;
// How many of one sender's messages may wait unanswered: a ceiling against runaway scripts.
extern const NSUInteger InboxMostWaiting;

// The record as read from its file, its parts checked: {version, messages, weeks}; an empty one for nil or one of
// another shape, so a damaged file never stops the inbox.
NSDictionary *InboxRecordFrom(id json);

// Why words can't be kept as a message, in words its sender can act on, or nil: none, too many, or something shaped
// like a key in them (or in `about`).
NSString *InboxWhyNotWords(NSString *text, NSString *about);

// The record with a message kept: from `from` ({session, name}), for the lead of `project`, at `priority`, about
// `about` (or nil), at `now`. Its id comes back in `kept`. Nil, with why, when its sender already has
// InboxMostWaiting waiting.
NSDictionary *InboxRecordKeep(NSDictionary *record, NSDictionary *from, NSString *project, NSString *priority,
                              NSString *about, NSString *text, double now, NSString **kept, NSString **why);

// A project's messages not answered yet, most pressing first (urgent, question, report, note), the oldest first
// within each.
NSArray<NSDictionary *> *InboxWaiting(NSDictionary *record, NSString *project);
// Of those, the first `reader` hasn't read: one an earlier lead read and nobody answered counts as unread for the next.
NSDictionary *InboxNextFor(NSDictionary *record, NSString *project, NSString *reader);
// One message by its id, or nil.
NSDictionary *InboxMessage(NSDictionary *record, NSString *messageId);

// The record with that message read by `reader` at `now`.
NSDictionary *InboxRecordRead(NSDictionary *record, NSString *messageId, NSString *reader, double now);
// The record with that message answered by `reader` at `now`, with `note` (or nil); nil, with why, for one that isn't
// there. One answered already keeps its first answer, and says so in `said`.
NSDictionary *InboxRecordAnswered(NSDictionary *record, NSString *messageId, NSString *reader, NSString *note,
                                  double now, NSString **said, NSString **why);

// The line that tells the lead a message waits, which its sender sends with the agent's own messages: "Inbox m-7f3a ·
// question from Pip: " and the message's first 80 characters. And the kept message's id at the start of a line, or nil.
NSString *InboxLine(NSDictionary *message);
NSString *InboxIdInLine(NSString *line);

// The record with what became of that line (the agent's message `lineId`), as the agent says (`state`, one of its
// deliveries, since `at`), kept as the message's `told`, only when `sender` is the session that kept it, so no one
// else's line can change it. Each held, expired, denied, dropped or failed line counts once in its week. The record as it was when
// nothing changed.
NSDictionary *InboxRecordRing(NSDictionary *record, NSString *keptId, NSString *sender, NSString *lineId,
                              NSString *state, double at, double now);
// The record with a plain message to a project's lead counted lost this week (expired, turned down, dropped or failed),
// once by its id.
NSDictionary *InboxRecordLost(NSDictionary *record, NSString *project, NSString *messageId, double now);
// This week's counts, for one project or all of them (nil): {held, expired, denied, dropped, failed, lost}.
NSDictionary *InboxWeekCounts(NSDictionary *record, NSString *project, double now);

// The record without what's old: answered messages after 7 days, unanswered ones after 14, and weeks' counts after 8
// weeks. The record as it was when nothing went.
NSDictionary *InboxRecordPrune(NSDictionary *record, double now);

// What `inbox` lists of a message, without its words: {id, from, priority, about, at, readAt, readBy, told}.
NSDictionary *InboxSummary(NSDictionary *message);
