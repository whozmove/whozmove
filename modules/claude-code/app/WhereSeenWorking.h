// WhereSeenWorking: which process is each session's own, and where it was seen working, so a process that only says
// it's a session (its record written by another) is told from the session's own when it asks the panel something in
// that session's name; with the rule for that in a plain function, WhyNotSpeakFrom.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "ClaudeProgram.h"

@class Row;

@interface WhereSeenWorking : NSObject
// `programOf` says what a process runs, a print run's stand-ins counted as the signed build.
- (instancetype)initWithProgram:(ClaudeProgram (^)(pid_t pid))programOf;
// Notes each session's own process and the folder it works in, as the system says, from every copy in Claude Code's
// registry (not only the one each row follows: a record another program wrote can outrank the session's own). Kept for
// as long as Whozmove runs, so a process that takes up a session once its own has ended is taken as its own only where
// the session was seen working, as carrying it on there does; for a session not seen since Whozmove started, where
// Whozmove kept it working once it ended. Called on the rows' queue as they're read; the rest asks under a lock.
- (void)note;
// Why `process`, found as the row's session's own, can't speak for it now, read fresh at the ask; nil when it can.
- (NSString *)whyNot:(Row *)row speakFrom:(pid_t)process;
@end

// The other processes Claude Code's registry says are a session, `besides` the one asking, that run Claude Code
// (`programOf`, signed or from npm): a record any program wrote for one isn't a copy. What makes a session open twice,
// for the asks here and for which session may hold AnswerFor's switches (SwitchHolder).
NSArray<NSNumber *> *ClaudeCopiesOf(NSString *sessionId, pid_t besides, ClaudeProgram (^programOf)(pid_t pid));

// The rule, from what's known at the ask. `process` works in `working`; `copies` are the other processes running
// Claude Code now that the registry says are the session; `seen` is where its own was seen, {pid, origin, folder}, or
// nil, and `seenRuns` whether that process still runs; `recorded` is where Whozmove kept it working, or its record
// says, for a session not seen; `name` is the row's. Another copy refuses it, as open twice; while the one seen runs,
// only that one may speak; once it has ended, only one working where it was seen working (where it started, or where
// it last was), or inside it, as a worktree it made is. Each refusal says what to do.
NSString *WhyNotSpeakFrom(pid_t process, NSString *working, NSArray<NSNumber *> *copies, NSDictionary *seen,
                          BOOL seenRuns, NSString *recorded, NSString *name);
