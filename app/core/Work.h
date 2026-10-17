// Work: who's at work in a checkout, and what waits for them. The island's steps and Deploy both wait while an agent
// works where they'd act, so they never act on files half-way through a change.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Row;

// Whether a row's agent is in the middle of something: working, asking, or compacting. The island's steps wait for it,
// as Deploy does, so they never act on files half-way through a change.
BOOL AgentAtWork(Row *row);
// The other sessions among `rows` whose agent is working (or compacting) in the folder the row's steps act on (as their
// own checkout or folder, or the one their edits land in). The steps wait for them too: a formatter, a rebase or
// another agent's edits may be half-way through there. One waiting on you doesn't count: it changes nothing until you
// answer it, which may be days away. (The row's own agent holds them while it asks you something too, as a step typed
// in then could answer it.)
NSArray<Row *> *OthersAtWork(Row *row, NSArray<Row *> *rows);
// Why the row's steps, or Deploy, wait now, starting with `what` ("Deploy waits"): until its own agent is done, or the
// ones in the other sessions at work in its folder, named. Nil when nothing does. The island and its menus stay up
// meanwhile, to show where the work stands; only what they'd do waits.
NSString *WhyStepsWait(Row *row, NSArray<Row *> *rows, NSString *what);
