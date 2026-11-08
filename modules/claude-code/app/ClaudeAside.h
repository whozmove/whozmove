// ClaudeAside: a question asked on the side of one of Claude Code's sessions, answered by a throwaway copy of its
// conversation that runs no tool and saves nothing (ClaudeAsideArguments), while the session works on and never sees
// it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@interface ClaudeAside : NSObject
// Asks, off the main thread, in the session's folder: the session's own program (`running`) where that's where Claude
// Code is installed (ClaudeAsideProgram), with only what ClaudeEnvironment gives it. Returns the ask's id, or nil for a
// session it may not resume (ClaudeAsideArguments gives none), and then `done` is never called; else `done` is called
// once, on the main thread, with AgentAside's answer (`signIn` with signedOut). Three minutes at most.
- (NSString *)ask:(NSString *)question running:(NSString *)running sessionId:(NSString *)sessionId
            model:(NSString *)model effort:(NSString *)effort folder:(NSString *)folder
             done:(void (^)(NSDictionary *answer))done;
// Ends an ask by its own process, checked by its start time, with everything it started; its `done` says stopped.
- (void)stop:(NSString *)askId;
// Ends every ask still running, as Whozmove quits.
- (void)stopAll;
@end

// The parts the module's --print-aside prints, for its tests.
// What a side question's output says, from its stream-json lines as they came: AgentAside's answer, `state` answered
// (`text`, its words, 16,384 characters at most), wantedTool, limit (`resetsAt`), signedOut, tooLong, tooSlow
// (`timedOut`: it hadn't finished in time), apiError (any other error the API sent back), stopped (`stopped`) or
// noAnswer (noCommand is the ask's own, when no program is found to run), with the API's error status (`status`) and
// the tokens it read from the cache, read fresh, wrote to the cache and wrote out, when it said.
NSDictionary *ClaudeAsideAnswer(NSArray<NSData *> *lines, BOOL timedOut, BOOL stopped);
// The model a side question asks: the session's, with the long context ("[1m]") its own --model asked for, or that a
// conversation of `tokens` must have had.
NSString *ClaudeAsideModel(NSString *model, NSString *flagModel, NSInteger tokens);
// The program a side question runs: the session's own `running`, when it's one of `candidates` (where Claude Code is
// installed); else the first of them; nil with none.
NSString *ClaudeAsideProgram(NSString *running, NSArray<NSString *> *candidates);
