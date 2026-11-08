// HookLine: the panel's end of the hooks' connections (hook.sock in Whozmove's own folder): each request for your OK,
// each question, plan, and "Switch model?", asked over a connection the permission hook opens, and answered only down
// it, so nothing written in a file can answer one; and the words hook asking for words to hand in between steps.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// The hook checks the panel's own process is at the other end; the panel checks, as the request comes in, that the
// hook runs in the session the request names (its process walked up to one Claude Code's registry lists), so one
// session can't ask, or be answered, as another. A program written to pose as the panel isn't stopped by this: it would
// have to stop the panel, take its socket and run as Whozmove. What it stops is a line written in a file.
#import <Foundation/Foundation.h>

@interface HookLine : NSObject
// The one the panel listens with: started as the app starts (ClaudeCode's launch), never in a print run but its own.
+ (instancetype)shared;
// Listens at `path`, only you able to connect, off the main thread. `sessionOf` names the session a process runs in
// (walking up its parents), on the line's queue. NO if it couldn't.
- (BOOL)listenAt:(NSString *)path sessionOf:(NSString *(^)(pid_t pid))sessionOf;
- (void)stop;
// Listens again if its socket has been taken away (removed, or another put in its place): each tick.
- (void)keepListening;
// The requests waiting, by id: each as its hook asked it, {id, sessionId, tool, input, cwd, at, pid, expiresAt}, with
// `pid` the hook's process, as macOS names it. From any thread.
- (NSDictionary<NSString *, NSDictionary *> *)requests;
// Passes your answer down its request's connection ({behavior, answers, message, stop}, and `approvePlan` from a
// session you allow to approve plans for you, AnswerFor), once, never waiting on it: NO
// if the request has gone, was answered already, or its hook isn't reading (then it's let go, and Claude asks itself).
// And a hold: you're answering it, so one that goes by itself waits at least a minute past `at` (ms), and no session you
// allow answers it for you meanwhile.
- (BOOL)answer:(NSString *)askId with:(NSDictionary *)reply;
- (BOOL)hold:(NSString *)askId at:(double)at;
// When a request was last held, as you answered it (ms), whether it goes by itself or not; 0 for never, or gone.
- (double)heldAt:(NSString *)askId;
// Whether a request still waits on its line, not answered yet.
- (BOOL)stillAsking:(NSString *)askId;
// Why a request that waited lately has gone: `answered` (from the panel), `waitedOut` (its hook's hour on the line
// ran out, so only Claude's own prompt can answer it now), `letGo` (its hook wasn't reading, so Claude's own prompt
// has it), or `gone` (answered in Claude, or its hook stopped); nil for one not known.
- (NSString *)whyGone:(NSString *)askId;
// What the words hook in a process is handed for its session (`event`, PostToolBatch or Stop), on the line's queue:
// asked once the line has checked the process runs in that session, its answer sent down the line, which then closes.
@property (copy) NSString *(^wordsFor)(NSString *sessionId, pid_t hookPid, NSString *event);
// "Switch model?" for a session while its hook waits: {sessionId, from, to, tokens, at, pid}, or nil; and your answer.
- (NSDictionary *)switchQuestionFor:(NSString *)sessionId;
- (BOOL)answerSwitch:(NSString *)sessionId allow:(BOOL)allow;
// What happened to each connection the last while, for the tests: "asked by <session>", "refused: <why>", "answered".
@property (readonly) NSArray<NSString *> *told;
// A print run has no hooks to ask over a line: it takes the requests its sample home keeps in files as if they had
// been (Asks.m), so the rows it prints have them.
@property (assign) BOOL printing;
@end
