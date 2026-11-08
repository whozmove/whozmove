// Background: the jobs a session's agent still runs in the background after its turn, from its hook's record.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Row;

// The row's jobs in the background as the page gets them (Row's `background`), oldest first, or nil when there are
// none: from its hook's record (`background`, {id: {type, what, command, startedAt, listedAt, step}}), leaving out the
// ones that are plainly over, which the hook can't always tell, as no event comes for them. Asked for every row every
// second, on the rows' queue, so it only looks at what's cheap to look at: the record is never changed (it's shared).
NSArray<NSDictionary *> *RunningBackground(Row *row, NSDictionary *record);
// Whether a job's whole command is one of Whozmove's own waits in the background, run through the plugin's own
// ask-panel.sh: named under the plugin's root as Claude Code writes it, or by the real path of one of its copies in
// `copies` (the folder that holds each version's copy), then exactly one of `waits` (the words each module gives for
// its asks, BackgroundWaits), and nothing else: no second command, pipe, redirect or substitution. `exact` is whether
// its hook recorded the command just as it was written (its record joins lines, folds tabs and spaces, and cuts a long
// one): only an exact one is taken, so a second command on a line of its own ("ask-panel.sh", then "ticket --wait")
// never is, and a record from before the hook said (no `exact`) stays shown. Such a job is the panel's own and isn't
// shown as the session's.
BOOL ClaudeJobIsOwnWait(NSString *command, BOOL exact, NSString *copies, NSArray<NSArray<NSString *> *> *waits);
// Each module's background waits, as the agent's module gathers them (modulesThat: BackgroundWaits), kept for the rows'
// queue, which reads every row's jobs; only a list each word of which after the first is a flag (starting "--") is
// kept, so nothing in a wait names a program. None until they're given: then nothing is left out.
void KeepOwnWaits(NSArray<id> *modules);
NSArray<NSArray<NSString *> *> *OwnWaits(void);
