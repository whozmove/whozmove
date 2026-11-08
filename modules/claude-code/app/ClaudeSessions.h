// ClaudeSessions: Claude Code's running sessions, from its registry, and what Whozmove's hooks recorded of each.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Row;

// The sessions Claude Code's registry lists whose process still runs, as rows, leaving out its usage check (Usage) and
// the copies asked questions on the side (NoteAsideProcess). A copy `untracked` says is in an app whose sessions you
// don't track never speaks for its conversation while another copy can (the core then leaves out the rest). On the
// rows' queue.
NSArray<Row *> *RunningSessions(BOOL (^untracked)(Row *copy));
// A copy of a session's conversation asked a question on the side, noted as it starts (`running`) and as it ends: it's
// left out of everything read from the registry here, as the usage check is.
void NoteAsideProcess(pid_t pid, BOOL running);
// Whether a process is one of those copies, while it runs: it's never another session in its folder.
BOOL IsAsideCopy(pid_t pid);
// The session a running process of Claude Code's is, by its id, from the registry; nil for any other process.
NSString *SessionOfProcess(pid_t pid);
// The session a process runs in: the first process up from it (itself included) that's one of Claude Code's running
// sessions, by its id, and that process in *found; nil for none. A session's hooks and tools run a few processes down
// from it.
NSString *SessionAbove(pid_t pid, pid_t *found);
// Every running process the registry lists for a session, {pid, sessionId}, each copy of a conversation on its own,
// leaving out the usage check and the side questions' copies. On the rows' queue.
NSArray<NSDictionary *> *RegisteredCopies(void);
// The other running processes the registry lists for a session besides `pid`, as it says now, in any app and paused
// or not.
NSArray<NSNumber *> *OtherCopiesOf(NSString *sessionId, pid_t pid);
// Whether a session's conversation runs in another terminal besides `pid` as well, as the registry says now: resumed in
// a second tab while it still runs. One paused in its terminal (Ctrl+Z) doesn't count, as it takes no keys until it's
// brought back, nor one in Claude Desktop, where no key typed into a tab can land. A file that can't be read counts.
BOOL InAnotherTerminal(NSString *sessionId, pid_t pid);
// Closes a conversation's copies in terminals other than `keep`, as the registry says now, each by its own process, as
// closing its tab would: only while each sits idle and no request waits, and none paused (Ctrl+Z) or in Claude Desktop.
// Nil once *closed of them are closing, else why none was.
NSString *CloseOtherCopies(NSString *sessionId, pid_t keep, BOOL requestWaiting, NSUInteger *closed);
// Why a conversation can't be ended now, as Sessions says it, with `open` set to whether a process has it open at all;
// nil when it can be, or isn't open. The same holds as CloseOtherCopies' on each copy.
NSString *WhyNotEndConversation(NSString *sessionId, BOOL *open);
// Ends every copy of a conversation in a terminal, each only while it's still that session's own process; returns the
// processes sent SIGTERM, or nil with `why` when one is no longer free to end.
NSArray<NSNumber *> *EndConversation(NSString *sessionId, NSString **why);
// Adds what the hook recorded of a session (its last prompt, reply and notice, its live step, how far its turn took the
// work): Whozmove's own record, in its folder, and when the hook last wrote it. On the rows' queue.
void AddHookRecord(Row *row);
// Where the hook keeps its record of a session, in Whozmove's own folder.
NSString *HookRecordPath(NSString *sessionId);
