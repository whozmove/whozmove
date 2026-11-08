// ClaudeProgram: whether a running process is Claude Code's own program, told by what the system says of it, never by
// what Claude Code's records or the process say, but for an older npm install's record, which only holds back: its
// native build by Anthropic's signature (ClaudeCodeFacts), as the system keeps it for the running program, and an
// older npm install, run by Node, by its path or its record.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, ClaudeProgram) {
    ClaudeProgramNone,      // any other program, or a process that has ended
    ClaudeProgramSigned,    // Claude Code's native build, signed by Anthropic
    ClaudeProgramByPath,    // Node running an older Claude Code from npm, which only its path or record tells
};

// What a process runs, checked once for each process (its pid and when it started), as a signature check takes a few
// milliseconds. `standIn`: a program's path that counts as the signed build, for a print run's stand-in processes only.
ClaudeProgram ClaudeProgramOf(pid_t pid, NSString *standIn);
// The rule ClaudeProgramOf follows, from what the system says of a process: its program's path, its arguments as they
// read now, whether it has its own record in Claude Code's registry, and whether it's signed by Anthropic as Claude
// Code. A stand-in's path counts as the signed build; Node counts as an older npm install by its entry among its
// arguments, or else by its record.
ClaudeProgram ClaudeProgramFrom(NSString *path, NSArray<NSString *> *arguments, BOOL hasRecord, BOOL signedByAnthropic,
                                NSString *standIn);
// Why a process isn't Claude Code's own build, signed by Anthropic, in words for the user, `program` being what
// ClaudeProgramOf said of it: an older one from npm, run by Node, which no signature tells; signed in Claude Code's
// name but not proven Anthropic's, with what failed; or another program. nil when it's the signed build.
NSString *ClaudeProgramWhyNot(pid_t pid, ClaudeProgram program);
// The same reason without what the process itself should do next ("then ask again", "only Claude Code itself can
// ask"), for where it's said to the user about the session: what to update, and that Whozmove may need updating,
// are kept. Its first letter is small, as it's the rest of a sentence.
NSString *ClaudeProgramCause(pid_t pid, ClaudeProgram program);
// Whether a process's short name, as the system's list of processes keeps it, could be Claude Code's: so only those are
// looked at further.
BOOL ClaudeProgramMayBe(NSString *name, NSString *standIn);
