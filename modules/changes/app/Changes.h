// Changes: what isn't committed in each listed checkout, line by line, as git status splits it, each changed line
// credited to whoever wrote it, a listed session whose edits (or its sub-agents', or its shell commands') put it in or
// took it out, else no session; and, when asked, the commits not on GitHub yet, one by one.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Row, Core;

// A unified diff (git diff's) as files: [{path, status (new, changed, renamed, gone), binary, hunks: [{oldStart,
// newStart, lines: [[sign, text, key]]}]}], `sign` being "+", "-" or " ", `text` cut short past 2,000 characters and
// `key` the whole text's LineKey (NSNull for a blank line). Plain, for the tests.
NSArray<NSDictionary *> *ParseDiff(NSString *diff);

@interface Changes : NSObject
// Where what each session edited comes from: its agent (AgentWork's editsOf:).
@property (weak) Core *core;
// Starts counting again what isn't committed in each listed checkout with something to commit, where something
// changed since the last time: a file, a commit, what's staged, or a session's edits; and reading ahead the commits
// not on GitHub yet, while there are some.
- (void)refreshFor:(NSArray<Row *> *)sessions;
// What isn't committed in a session's checkout, for its row: {all: {added, removed, files, unstaged: {files, added,
// removed}, staged: {files, added, removed}}, known, added, removed, files: [{path, added, removed, edits, at,
// created, saved, shared}], parts: {who: [added, removed]}, complete, v}, or nil before it's been counted. `all` is the
// checkout's, as git counts it: every change since the last commit, each file once, then what isn't staged (new files
// included) and what's staged, a file staged and changed again counting in both. The rest is the session's own share:
// while it isn't known (a shell command of its ran unrecorded), `known` is NO and the counts are the whole checkout's,
// with no files or parts. `parts` is the checkout's uncommitted change by whose it is: a session's id; "outside", no
// listed session's record has it; or "short", a short or repeated line with nothing around it to tell by. `v` changes
// whenever anything in it might have.
- (NSDictionary *)rowChangesOf:(Row *)row;
// What the changes view shows of a session's checkout, as git shows it, `done` given it on the main thread:
// `unstaged`, what `git diff` shows and then the files git doesn't track yet, {scope, v, files: [{path, status, binary,
// untracked, alsoStaged, cut, hunks: [{oldStart, newStart, lines: [[sign, text]]}]}]}; `staged`, what `git diff
// --cached` shows, each file with `alsoUnstaged` in place of `alsoStaged`; or `outgoing`, the commits not on GitHub yet,
// newest first, {scope, v, upstream (the branch they're ahead of, or null for one never published), commits: [{hash,
// short, subject, at, files}], more}. Past 30,000 lines a file comes `cut`, with its `added` and `removed` and no lines.
// {missing} for one there isn't yet.
- (void)view:(NSString *)sessionId scope:(NSString *)scope done:(void (^)(NSDictionary *view))done;
// The same, made JSON off the main thread as the page's showChanges takes it, [sid, scope, view], given to `done` on the
// main thread.
- (void)viewOf:(NSString *)sessionId scope:(NSString *)scope done:(void (^)(NSString *json))done;
// The file a changes view may open: one of the changes in that session's checkout, or of its commits not on GitHub
// yet, as a full path, or nil.
- (NSString *)fileOf:(NSString *)sessionId path:(NSString *)path;
// Whether a count is still being worked out. A test run waits until none is.
@property (readonly) BOOL working;
@end
