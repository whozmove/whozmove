// ClaudeSessions: Claude Code's running sessions, from its registry, and what Whozmove's hooks recorded of each.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Row;

// The sessions Claude Code's registry lists whose process still runs, as rows, leaving out its usage check (Usage). On
// the rows' queue.
NSArray<Row *> *RunningSessions(void);
// Adds what the hook recorded of a session (its last prompt, reply and notice, its live step, how far its turn took the
// work): Whozmove's own record, in its folder. On the rows' queue.
void AddHookRecord(Row *row);
