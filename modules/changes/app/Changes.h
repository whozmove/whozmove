// Changes: what each session changed in its checkout that isn't committed yet, line by line, as git status sees it;
// and, when asked, what its commits not on GitHub yet changed. Each changed line is credited to whoever wrote it, a
// listed session whose edits (or its sub-agents', or its shell commands') put it in or took it out, else no session.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Row, Core;

// A unified diff (git diff's) as files: [{path, status (new, changed, gone), binary, hunks: [{oldStart, newStart,
// lines: [[sign, text, key]]}]}], `sign` being "+", "-" or " ", `text` cut short past 2,000 characters and `key` the
// whole text's LineKey (NSNull for a blank line). Plain, for the tests.
NSArray<NSDictionary *> *ParseDiff(NSString *diff);

@interface Changes : NSObject
// Where what each session edited comes from: its agent (AgentWork's editsOf:).
@property (weak) Core *core;
// Starts working out again whose each changed line is, in each checkout the listed sessions edited files in, where
// something changed since the last time: a file, a commit, or a session's edits.
- (void)refreshFor:(NSArray<Row *> *)sessions;
// A session's own changes not committed yet, for its row: {known, added, removed, files: [{path, added, removed, edits,
// at, created, saved, shared}], parts: {who: [added, removed]}, complete (as viewOf: says), v}, or nil when it has
// none there. While they aren't known (a shell command of its ran unrecorded), `known` is NO and the counts are the
// whole checkout's, with no files or parts. `parts` is the checkout's uncommitted change by whose it is: a session's
// id; "outside", no listed session's record has it; or "short", a short or repeated line with nothing around it to
// tell by. `v` changes whenever anything in it might have.
- (NSDictionary *)rowChangesOf:(Row *)row;
// What the changes view shows, for one session: its own files (`scope` "session") or the whole checkout's ("branch"),
// each with its hunks and whose each line is: {scope, v, files: [{path, status, binary, saved, complete, counts: {who:
// [added, removed]}, hunks: [{oldStart, newStart, lines: [[sign, text, who]]}]}], complete} (`saved`, nothing in the
// file is left unstaged; `complete`, whether every session in the checkout is known and no command's record left
// lines out, so that "outside" means no listed session's), or nil before the first count. A session that isn't known
// gets the checkout's. Its own ("session") has only its own parts of each file. Built where it's called: the panel
// asks for it with viewOf:scope:done:, which builds it off the main thread.
- (NSDictionary *)viewOf:(NSString *)sessionId scope:(NSString *)scope;
// The same, or the commits view (`scope` "commits"), built off the main thread with its JSON, and `done` given the
// JSON on the main thread: the view, or {missing} for one there isn't yet.
- (void)viewOf:(NSString *)sessionId scope:(NSString *)scope done:(void (^)(NSString *json))done;
// The commits view, for one session's checkout: what its commits not on GitHub yet changed, as the island's commits
// stage counts them, as viewOf: gives the rest ({scope "commits", v, files, complete}). Worked out off the main
// thread; `done` gets it on the main thread, or nil.
- (void)commitsOf:(NSString *)sessionId done:(void (^)(NSDictionary *view))done;
// The file a changes view may open: one of the changes in that session's checkout, as a full path, or nil.
- (NSString *)fileOf:(NSString *)sessionId path:(NSString *)path;
// Whether a count is still being worked out. A test run waits until none is.
@property (readonly) BOOL working;
@end
