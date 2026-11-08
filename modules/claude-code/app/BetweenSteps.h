// BetweenSteps: words held for a session's own words hook (whozmove-claude-words.py), which asks for them over the
// hook's line as the session's current tool calls finish, or as its turn ends, and hands them in once. Only a process
// the session itself started takes them, one level under the process its row follows or under a shell it started: its
// hook, or a command it runs, as no check can tell the two apart; never another session's.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// The line that opens your words as the hook hands them in.
extern NSString *const kBetweenStepsLine;

// What a hook is handed, from the words held for its session, oldest first: the line that opens them, then each on a
// line of its own; nil for none.
NSString *BetweenStepsHandOut(NSArray<NSString *> *words);
// Whether a hook's process may take a session's words: its parent is the session's own process, or a shell
// (`shellBetween`) whose parent is.
BOOL BetweenStepsHookOf(pid_t hookParent, pid_t hookGrandparent, BOOL shellBetween, pid_t session);

@interface BetweenSteps : NSObject
// As the app starts, nothing is held: a flag left by a run that quit or crashed while words waited goes, so no hook
// starts Python for nothing.
- (void)start;
// Words held for a session's hook (`sessionPid`, the process its row follows), named by `wordsId`.
- (void)hold:(NSString *)words session:(NSString *)sessionId pid:(pid_t)sessionPid id:(NSString *)wordsId;
// Taken back: YES if its hook hadn't taken them yet.
- (BOOL)takeBack:(NSString *)wordsId;
// From any thread: what the hook in process `hookPid`, at `event` (PostToolBatch or Stop), takes for its session, as
// it's handed in (BetweenStepsHandOut), or nil. Each of the words goes once, and only to its own session's process.
- (NSString *)handOver:(NSString *)sessionId hookPid:(pid_t)hookPid event:(NSString *)event;
// Held words once their hook has taken them: {words, at, event}, else nil.
- (NSDictionary *)handed:(NSString *)wordsId;
- (void)forget:(NSString *)wordsId;
@end
