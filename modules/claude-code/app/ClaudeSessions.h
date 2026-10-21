// ClaudeSessions: Claude Code's running sessions, from its registry, and what Whozmove's hooks recorded of each.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Row;

// The sessions Claude Code's registry lists whose process still runs, as rows, leaving out its usage check (Usage). A
// copy `untracked` says is in an app whose sessions you don't track never speaks for its conversation while another
// copy can (the core then leaves out the rest). On the rows' queue.
NSArray<Row *> *RunningSessions(BOOL (^untracked)(Row *copy));
// Whether a session's conversation runs in another terminal besides `pid` as well, as the registry says now: resumed in
// a second tab while it still runs. One paused in its terminal (Ctrl+Z) doesn't count, as it takes no keys until it's
// brought back, nor one in Claude Desktop, where no key typed into a tab can land. A file that can't be read counts.
BOOL InAnotherTerminal(NSString *sessionId, pid_t pid);
// Closes a conversation's copies in terminals other than `keep`, as the registry says now, each by its own process, as
// closing its tab would: only while each sits idle and no request waits, and none paused (Ctrl+Z) or in Claude Desktop.
// Nil once *closed of them are closing, else why none was.
NSString *CloseOtherCopies(NSString *sessionId, pid_t keep, BOOL requestWaiting, NSUInteger *closed);
// Adds what the hook recorded of a session (its last prompt, reply and notice, its live step, how far its turn took the
// work): Whozmove's own record, in its folder, and when the hook last wrote it. On the rows' queue.
void AddHookRecord(Row *row);
