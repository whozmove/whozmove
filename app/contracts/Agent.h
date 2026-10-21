// Agent: the coding agent that runs the sessions the panel lists (Claude Code), and what the panel asks of it. An agent
// is a module that adopts Agent; what more it does, it says by the protocols it adopts beside it, one for each part of
// the panel that uses it, so none of them reaches into the whole agent: AgentWork (what a session did: its edits and
// its PRs), AgentCommands (its menus' choices, the commands that make them, and whether one took), AgentPrompt (a
// command put into a session's prompt while keeping your draft), AgentUsage (your plan's usage) and AgentStarts (a new
// session, and whether it may work in a folder). The core finds the agent that runs a row's session (Core's agentOf:).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Row, Reason;
@protocol TypingHost;

@protocol Agent <NSObject>
// Its name, as the panel says it ("Claude Code").
@property (readonly) NSString *name;
// As the rows are read, on their queue (Rows, in the core): the sessions it runs now, as rows, leaving out its own (its
// usage check); then, once the hosts have added what they know of them, what its hooks recorded of each, which goes on
// the row after the host's own record (where both say when the session last moved, the later time stands); and last,
// the requests waiting for your answer.
- (NSArray<Row *> *)readSessions;
- (void)addRecordTo:(Row *)row;
- (void)addRequestsTo:(NSArray<Row *> *)rows;
// The title it gives a session, which it also puts in the session's terminal tab (Claude Code's topic), or nil: as the
// last read of the rows found it, or, `now`, read again. A terminal finds a session's tab by it.
- (NSString *)titleOf:(Row *)row now:(BOOL)now;
// Whether a terminal tab's whole title, as the agent put it there, says it's at work in that tab (Claude Code turns a
// mark before its topic while it works). Two tabs with the same title, the same conversation open twice, are told
// apart by it.
- (BOOL)titleShowsWork:(NSString *)title;
// The marks it puts on the commands its sessions run, as the names of environment variables. A command you set off from
// the panel (an extra stage's, say) is yours, so they're taken off it.
@property (readonly) NSArray<NSString *> *environmentMarks;
@end

// What a session did, as the agent records it (Claude Code's transcripts, read a little at a time).
@protocol AgentWork <Agent>
// The PRs a session made or worked on, by their address: {url, number, repo, at}. `onPRLinks` is called when new ones
// turn up.
- (NSDictionary<NSString *, NSDictionary *> *)prLinksOf:(NSString *)sessionId;
@property (copy) void (^onPRLinks)(void);
// What a session edited: {files: {path: {path, edits, at, created, added, removed}}, count (the edits counted, which
// changes whenever they do), known (whether everything it changed is known: a shell command whose changes the agent
// didn't record could have changed anything), failed (its shell commands that failed, which record nothing of what they
// may have changed first), doubts (the files a command changed whose lines its record leaves out)}. `added` and
// `removed` are the lines' keys (LineKey, shared/Text.h).
- (NSDictionary *)editsOf:(Row *)row;
@end

// The settings a session's menus change (model, effort and permission mode), the commands that change them and that
// compact a session, and reading what such a command did.
@protocol AgentCommands <Agent>
// A field's choices (model, effort or mode), as [the value it takes, the name shown].
- (NSArray<NSArray<NSString *> *> *)choicesFor:(NSString *)field;
// The command that sets a field to a value, as typed in a session's prompt ("/model claude-opus-5-5"), or nil when no
// command does (a mode other than plan); and the one that compacts a session, with what to focus on, or none.
- (NSString *)commandSetting:(NSString *)field to:(NSString *)value;
- (NSString *)compactCommand:(NSString *)focus;
// The Shift+Tab cycles a session in a terminal could have, and how many presses take it from one mode to another in all
// of them (-1 when that isn't certain: a key too many or too few would land it in another mode).
- (NSArray<NSArray<NSString *> *> *)modeCyclesFor:(Row *)row;
- (NSInteger)shiftTabsFrom:(NSString *)from to:(NSString *)to cycles:(NSArray<NSArray<NSString *> *> *)cycles;
// Where a command's result will be written, marked as the command goes in, or nil while the session has nowhere yet;
// then the result written since that mark (nil while there's none), and what it says: the value that now applies for
// the field the command changed (nil: nothing changed, declined or failed), whether it saved the pick as the default
// for new sessions, and after a compaction, nil once it compacted, else what to say about it, in plain text ("" when
// there's nothing to say).
- (id)markResultsOf:(NSString *)sessionId;
- (NSString *)resultOf:(NSString *)command since:(id)mark;
- (NSString *)resultApplies:(NSString *)field value:(NSString *)value result:(NSString *)result;
- (BOOL)resultSavedDefault:(NSString *)result;
- (NSString *)compactNote:(NSString *)result;
// A command that sets the model or effort also saves the pick as the default for new sessions, while a pick in the
// panel is for one session: before one goes in, the defaults it may overwrite are kept, and once it has run (or won't),
// put back if it saved its own. One release for each hold.
- (void)holdDefaults:(NSString *)field;
- (void)releaseDefaults:(NSString *)field saved:(BOOL)saved;
@end

// Words put into a session's prompt, in a terminal keeping any draft there.
@protocol AgentPrompt <Agent>
// Whether a session's first message has been sent (it has a transcript): before that, a command would start one.
- (BOOL)hasStarted:(NSString *)sessionId;
// Why keys can't go into a session's prompt now, or nil when it's safe: only while it sits idle at its prompt with no
// request waiting, where a stray Return would answer it. And why the one key that may go in while it works can't now:
// the Backspace that takes out the filler typing a command left.
- (Reason *)whyNotTypeInto:(NSString *)sessionId pid:(pid_t)pid;
- (Reason *)whyNotEditDraft:(NSString *)sessionId pid:(pid_t)pid;
// Types a command into a session's prompt through its terminal, keeping any draft there, a key at a time and each only
// while `whyNot` returns nil. `done` gets nil once every key is in, or why typing stopped, after how many of how many.
// The filler it leaves at the end of the draft is taken out once the draft is back.
- (void)type:(NSString *)command into:(id<TypingHost>)terminal tab:(NSString *)tab whyNot:(Reason *(^)(void))whyNot
        done:(void (^)(Reason *why, NSUInteger typed, NSUInteger steps))done;
- (void)deleteFillerIn:(id<TypingHost>)terminal tab:(NSString *)tab;
@end

// Your plan's usage, as the agent knows it.
@protocol AgentUsage <Agent>
// On a queue of the caller's, as it can take a few seconds: {state, plan, session, week, limits, extraUsage} as the
// usage strip takes them (the usage module's Usage.m says what each is), with `signIn`, the command that signs the
// agent in as typed in a terminal, once one answered; nil in a print run, where it's never asked.
- (NSDictionary *)askUsage;
@end

// A new session started from the panel, and whether the agent may work in a folder.
@protocol AgentStarts <Agent>
// The command a terminal runs for a new session with this id, its first message read from `wordsFile` (nil: none).
- (NSString *)startCommand:(NSString *)sessionId wordsFile:(NSString *)wordsFile;
// Whether it may work in a folder (it, its checkout, its repo or a folder above it is trusted), and recording your yes
// to that: nil once done, else why it couldn't be, as the panel says it. Both block: call them off the main thread.
- (BOOL)folderTrusted:(NSString *)folder;
- (NSString *)trustFolder:(NSString *)folder;
@end
