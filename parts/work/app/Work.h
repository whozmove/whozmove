// Work: who's at work in a checkout, and what waits for them. The next steps and Deploy both wait while an agent
// works where they'd act, so they never act on files half-way through a change.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Row;

// Whether a row's agent is in the middle of something: working, asking, or compacting. The next steps wait for it,
// as Deploy does, so they never act on files half-way through a change.
BOOL AgentAtWork(Row *row);
// Whether a row's session waits on you: a request or question for you, or a status that says so. The page's twin is
// whose-move.js's NEEDS_STATUSES (parts/list/page): a status counted there is counted here.
BOOL AgentAsksYou(Row *row);
// Whether a row's session is working now: busy and not asking you, compacting, busy in a copy of it open elsewhere, or
// running jobs in the background that hold (BackgroundAtWork). One waiting on you isn't: it changes nothing until you
// answer it, which may be days away. OthersAtWork goes by it, and the usage module counts the sessions working with it.
BOOL SessionWorking(Row *row);
// Whether a row's agent still runs jobs in the background that can change files in its folder (its `background` ones
// that hold: agents of its own, say), though its turn has ended and it takes your messages. The steps and Deploy wait
// for them as they do for the agent at work; a shell command it left running (a dev server) doesn't hold them.
BOOL BackgroundAtWork(Row *row);
// The other sessions among `rows` whose agent is working (or compacting) in the folder the row's steps act on (as their
// own checkout or folder, or the one their edits land in). The steps wait for them too: a formatter, a rebase or
// another agent's edits may be half-way through there. One waiting on you doesn't count: it changes nothing until you
// answer it, which may be days away. (The row's own agent holds them while it asks you something too, as a step typed
// in then could answer it.)
NSArray<Row *> *OthersAtWork(Row *row, NSArray<Row *> *rows);
// How a wait for what the row runs in the background is said, or nil when nothing there holds its steps: "until “Review
// the native side” is done in the background" (a long name cut at a word's end), or how many, and what to type in the
// session to stop one sooner, as its agent says (each job's `stop`). WhyStepsWait says it, and it's on the row (`backgroundWait`) for its Deploy's tip.
NSString *BackgroundWait(Row *row);
// Why the row's steps, or Deploy, wait now, starting with `what` ("Deploy waits"): until its own agent is done, or what
// it runs in the background (BackgroundWait), or the ones in the other sessions at work in its folder, named. Nil when nothing does. The steps stay on the row meanwhile, dimmed, to show where the work stands;
// only what they'd do waits.
NSString *WhyStepsWait(Row *row, NSArray<Row *> *rows, NSString *what);
