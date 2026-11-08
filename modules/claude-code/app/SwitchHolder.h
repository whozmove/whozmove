// SwitchHolder: which session may hold AnswerFor's switches kept for its folder, by what the system says of its
// process, never what files say of it; with the rule for that in a plain function, WhyNotHold.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "ClaudeProgram.h"

@class Core, Row;

// The folder a session works in, which the switches are kept for: its checkout's top folder, else the folder it runs
// in, as a real path; nil when neither can be read.
NSString *KeptFolderOf(Row *row);

// Where the walk up a session's parents stops, as it looks for a Claude Code session it was started inside (which then
// keeps it from holding the switches): in a print run, at the print run's own process, as all above it is the tests'
// harness, which may itself run inside a Claude Code session; in the app, nowhere short of the system's own process.
// Only whether this is a print run (Core's `printing`) decides it, so the app's walk never stops early.
pid_t StartedWalkStopsAt(BOOL printing);

@interface SwitchHolder : NSObject
// `programOf` says what a process runs, a print run's stand-ins counted as the signed build, and `mayBe` whether a
// process's short name could be Claude Code's, so only those are looked at further; `named` is how a listed session in
// the way is named.
- (instancetype)initWithCore:(Core *)core program:(ClaudeProgram (^)(pid_t pid))programOf
                       mayBe:(BOOL (^)(NSString *name))mayBe named:(NSString *(^)(Row *row))named;
// Whether a session can hold the switches kept for its folder now: {why, kind} when it can't, with `other` (a listed
// session's id) for one in the way, or an empty record when it can. What files say of it (the team file, Claude Code's
// registry) decides only which session it is: each fact here is what the system says of its process. Checked again
// once a second at most, as each row pass, menu and ask may want it.
- (NSDictionary *)whyNot:(Row *)row;
// Forgets what was last checked, so the next ask checks again at once: for a print run whose stand-in processes change
// between its steps.
- (void)forget;
@end

// The rule alone, from what the system says. `folder` is the one the switches are kept for (nil: it can't be read);
// `working` where the session's process works (nil: it can't be read); `program` what it runs, and `programWhy` why
// that isn't Claude Code's own build (ClaudeProgramCause, at a sentence's start); `followsCopy` whether Claude Code's
// registry has other copies of its conversation; `copies` those that run Claude Code; `startedInside` the Claude Code
// session it was started inside and `otherHere` another Claude Code session working in that folder, each {name,
// session} (both only when it's listed), or nil for none. Its process must work in the folder; a row following a copy
// that isn't Claude Code's own has another copy to close; then it must be Claude Code's own build, open in one place,
// started inside no other session, and the only session there. Each reason is the cause alone, starting with a plain
// word, as where it's said adds what to do next; `kind` says which (folder, copy, npm, program, started, other), for the
// way past it.
NSDictionary *WhyNotHold(NSString *folder, NSString *working, ClaudeProgram program, NSString *programWhy,
                         BOOL followsCopy, NSArray<NSNumber *> *copies, NSDictionary *startedInside,
                         NSDictionary *otherHere);
