// KeptSessions: the terminal sessions Claude Code ran lately, kept so their rows stay once they've ended (their tab
// closed, their terminal quit, the Mac restarted), as Claude Desktop keeps its own conversations: one small file for
// each, written while it runs, in Whozmove's own folder, and read back as a row with status "closed".
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Row;

// How long an ended session stays listed after its conversation last moved: as long as Claude Desktop's conversations
// (kRecentConversationWindow in the Claude Desktop module).
extern const NSTimeInterval kKeptFor;
// How long one that waits on someone else stays listed after its conversation last moved, at most, in place of that
// (its record's `waits`, while its row has a `wait`), so one woken while it was closed still has its Resume: a ceiling,
// so a wait that never ends can't keep a row for ever.
extern const NSTimeInterval kKeptWaitingFor;

// What's kept of a running session, {sessionId, cwd, name, terminal, pid, procStart, transcript, activeAt}, or nil for
// one that isn't kept: one not started in a terminal, not running, or with no transcript yet (nothing to carry on).
// `terminal` is the app id of the terminal it runs in ("" when that isn't known), and `activeAt` when its conversation
// last moved, as the page counts it (lastActive in whose-move.js), since a session merely started moves its status.
// No prompt or reply goes in: those stay in its hooks' record. KeptSessions adds `waits` while its row waits on someone
// else.
NSDictionary *KeptRecord(Row *row, NSString *transcript, NSString *terminal);
// A kept record with its note that it waits as `waits` says: added, kept or taken away.
NSDictionary *KeptNoting(NSDictionary *record, BOOL waits);
// The kept sessions whose process runs another conversation of the rows' now: one cleared (/clear), or one another was
// carried on in (/resume), which you left there.
NSArray<NSString *> *LeftBehind(NSDictionary<NSString *, NSDictionary *> *kept, NSArray<Row *> *rows);
// The kept sessions that have gone, at `now` (seconds since 1970): their conversation last moved longer ago than
// kKeptFor (kKeptWaitingFor for one whose record says it waits), or their transcript has gone (Claude Code clears old
// ones away). Never one of the `running` ones.
NSArray<NSString *> *Stale(NSDictionary<NSString *, NSDictionary *> *kept, NSSet<NSString *> *running,
                           NSTimeInterval now);
// Where they're kept, in Whozmove's own folder, and what's kept there, by session id, each file as it reads (a file is
// taken only when it's named for the session it holds).
NSString *KeptFolder(void);
NSDictionary<NSString *, NSDictionary *> *KeptIn(NSString *folder);
// One session's, from Whozmove's own folder, or nil.
NSDictionary *KeptOf(NSString *sessionId);

@interface KeptSessions : NSObject
// From launch on, never in a print run: what's kept is read, then pruned of what's gone once the sessions running now
// are known, and every hour.
- (void)start;
// For a print run, in place of start: what's kept, read at once; and a wait until every write it has sent has been
// made, so its files can be read.
- (void)readNow;
- (void)written;
// On the main thread, once the rows are whole: each running terminal session's record, written when it has changed,
// with the terminal `terminalOf` finds for its process (looked for again every few seconds while it finds none), and
// its transcript as `transcriptOf` knows it; and what the rows' processes left behind is dropped. Each kept session,
// running or ended, notes in its record whether its row waits on someone else (`waits`, as `waits` says from the rows
// as last listed): only once they've been listed (`waits` given), so a note is never cleared before the waits module
// has said. Nothing until it has started.
- (void)keep:(NSArray<Row *> *)rows transcriptOf:(NSString *(^)(Row *row))transcriptOf
  terminalOf:(NSString *(^)(Row *row))terminalOf waits:(BOOL (^)(Row *row))waits;
// On the rows' queue: the kept sessions that have ended, as rows, leaving out those `listed` has, those whose process
// runs another of them now, those past kKeptFor (kKeptWaitingFor for one that waits), and those whose transcript or
// folder has gone. Each is a terminal session's row with status "closed", no process, its last move as
// statusUpdatedAt, and the terminal it ran in.
- (NSArray<Row *> *)endedBesides:(NSArray<Row *> *)listed;
@end
