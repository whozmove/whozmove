// Team: the team the session leading it keeps in Whozmove's folder (team/team.json, docs/reference/team.md), read when
// it changes, and each row's place in it: the session you talk to, the lead, one of its members, one of your own
// sessions it follows, or another session open where one of them works.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Row;

// Who holds a member's seat in its own workspace this pass. `here` is each session running or ended there that the file
// names for no one, with the file's own session for it while it's there, each {session, process, startedAt, running,
// movedAt} (`process` its ProcessKey, none without a process; `startedAt` when that process started, 0 when not known;
// `movedAt` when its conversation last moved, in ms); `recorded` the file's session for it; `last` the seat's holder
// last pass, {session, process, pid, startedAt}, if any (no process for an ended one); and `lastUnseen` whether that
// one's process still runs though no row listed has it (for a minute at most, which the caller counts). Returns
// {seat, ended, holder, duplicates}: the running session holding the seat (none while nothing runs there, or while the
// last holder's row is missed); while nothing runs there, the ended one standing for the member (the last holder, else
// the file's own, else the one that moved last); what to remember as the holder, either of those; and each other
// running one, by session, YES when it was opened before the holder.
NSDictionary *SeatOf(NSArray<NSDictionary *> *here, NSString *recorded, NSDictionary *last, BOOL lastUnseen);
// `Whozmove --print-seats <cases.json>`: SeatOf for each sample case, {name, here, recorded, last, lastUnseen}.
int PrintSeats(NSArray<NSString *> *arguments);

@interface Team : NSObject
// Looks at whether the file has changed (no more than twice a second), and reads it again off the main thread if it has.
- (void)refresh;
// Whether a read is under way, which a print run waits for.
@property (readonly) BOOL working;
// Each row's place in the team, as the page gets it (docs/reference/rows.md's `team`), in the rows' order, NSNull for
// none: all at once, as who holds a member's seat in its workspace depends on who else runs there.
- (NSArray *)placesOf:(NSArray<Row *> *)rows;
// Each team as a whole (TeamFacts, contracts/Module.h): the same array until the file is read again.
@property (readonly, copy) NSArray<NSDictionary *> *teams;
@end
