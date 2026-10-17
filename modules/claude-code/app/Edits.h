// Edits: the files a session changed with Claude's edit tools and its shell commands, and the lines it wrote and took
// out, found in its transcript.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// What a part of a transcript says about edits: each edit asked for (Edit, MultiEdit, Write) and each one's result,
// as {id (the call's), path, at, created, added, removed}, and each call that failed or was turned down, {id, failed}, where `added` and `removed` are the lines it put in and took
// out, as LineKeys; and the lines each shell command changed, as Claude Code recorded them, except for commands that
// run git (`git`, from ShellNews). Read on the transcripts' queue.
NSArray<NSDictionary *> *EditNews(NSData *chunk, NSUInteger end, NSSet<NSString *> *git);

// Adds that news to what's known of a session's edits, `state` being its transcript state: `edits` (path ->
// {path, edits, at, created, added, removed}, the line sets growing with each edit) and `editIds` (the edits counted,
// so an edit's request and its result, or a transcript read again from the start after a rewrite, count once). A call
// that failed, or that you turned down ({id, failed}), takes its edit back out (`editLines`, `failedIds`). On the main
// thread.
void AddEditNews(NSMutableDictionary *state, NSArray<NSDictionary *> *news);

// What a part of a transcript says about the session's shell commands (Bash calls), for whether what they changed is
// known: Claude Code records the lines a command changed in its checkout (bashEditDiff, read by EditNews) only in
// some permission modes (ClaudeRecordsShellChanges). {modes: {mode: count} (the mode each command ran in;
// in plan mode, the mode plan was entered from; commands of git alone aren't counted), git: [id] (commands running a
// git command that brings in work that already exists, a merge, a rebase, a checkout, whose records aren't credited;
// "~" before the id when the command ran other things too, so the files it names are in doubt), doubts: [path] (files a command changed whose lines its record leaves
// out: past the most it records with their lines, it only names them), partial: count (records that can't even say
// which files they leave out), failed: count (commands that failed, which Claude Code records nothing of, though they
// may have changed files first), mode, base}. `mode` and
// `base` (the last mode that wasn't plan) are where the part before left off, and come back as this part leaves them.
// `git` are the commands already known to run git. Read on the transcripts' queue.
NSDictionary *ShellNews(NSData *chunk, NSUInteger end, NSString *mode, NSString *base, NSSet<NSString *> *git);

// Adds that news to a session's transcript state: `shellModes`, `shellPartial`, `shellFailed`, `shellDoubts`,
// `gitCalls` (the newest 500) and where the modes left off (`shellMode`, `shellBase`). On the main thread.
void AddShellNews(NSMutableDictionary *state, NSDictionary *news);

// Whether what a session changed is all known, from its transcript state and the setting that turns Claude Code's
// records of shell commands on or off for it (ShellDiffSetting).
BOOL SessionKnown(NSDictionary *transcript, id setting);
// That setting for a session in `project` (the folder it runs in), as Claude Code goes by it: the machine's, else the
// project's own, else yours, else nil. It reads files: off the main thread.
id ShellDiffSetting(NSString *project);
