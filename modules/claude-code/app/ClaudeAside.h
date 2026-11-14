// ClaudeAside: questions asked on the side of Claude Code's sessions, one side conversation for each session: a copy of
// its conversation (ClaudeAsideArguments), kept open for follow-ups while the session hasn't moved on, which may read
// in the session's folder (AsideReads) but changes nothing and saves nothing, while the session works on and never
// sees it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@interface ClaudeAside : NSObject
// `checker` is the program the copy's hook runs before each tool (Whozmove's own, kClaudeAsideCheckFlag); `program`,
// for --print-aside alone, a stand-in every copy runs in Claude Code's place (nil: Claude Code, found as below).
- (instancetype)initWithChecker:(NSString *)checker program:(NSString *)program;
// How long an ask waits for its answer after an early empty result (ClaudeAsideEarlyResult) before "Didn't answer",
// its copy then ended: 60 s; --print-aside's shorter.
@property (assign) NSTimeInterval afterEarly;
// Asks, off the main thread, in the session's folder: into the session's copy when one is open, waiting, with the same
// model and effort, and the session hasn't moved since it opened (`mark`, ClaudeAsideMoved); else in a fresh copy, the
// open one ended, whose first message carries `earlier` (the session's earlier side questions with their answers,
// oldest first, each {question, text, at}, as ClaudeAsideCarried gives them). A fresh copy runs
// the session's own program (`running`) where that's where Claude Code is installed (ClaudeAsideProgram), with
// ClaudeAsideEnvironment, and asks for its thinking's summaries where that version takes them (ClaudeAsideThinks);
// one that turns the flag down is asked again without it, and isn't asked for them again while Whozmove runs. Returns
// the ask's id, or nil for a session it may not resume (ClaudeAsideArguments gives none), and then neither block is
// called; else `step` is called on the main thread with each new step of its answer as it starts (ClaudeAsideStep),
// and then `done` once, with AgentAside's answer (`signIn` with signedOut), and `remembered`, how many earlier
// questions the copy knew. Five minutes at most for each answer; a copy that isn't asked again within five minutes
// ends.
- (NSString *)ask:(NSString *)question earlier:(NSArray<NSDictionary *> *)earlier running:(NSString *)running
        sessionId:(NSString *)sessionId model:(NSString *)model effort:(NSString *)effort folder:(NSString *)folder
             mark:(NSDictionary *)mark step:(void (^)(NSString *step))step
             done:(void (^)(NSDictionary *answer))done;
// Ends an ask by its copy's own process, checked by its start time, with everything it started; its `done` says
// stopped.
- (void)stop:(NSString *)askId;
// The sessions with a copy open, each with when it opened (ms since 1970).
- (NSDictionary<NSString *, NSNumber *> *)openSince;
// Ends a session's copy: at once while it waits, or once the answer it's giving is done.
- (void)end:(NSString *)sessionId;
// Ends every copy, as Whozmove quits.
- (void)stopAll;
@end

// The parts the module's --print-aside prints, for its tests.
// What a side question's output says, from its stream-json lines as they came: AgentAside's answer, `state` answered
// (`text`, its words, 16,384 characters at most), wantedTool (it used every round it may and still wanted more),
// limit (`resetsAt`), signedOut, tooLong, tooSlow (`timedOut`: it hadn't finished in time), apiError (any other error
// the API sent back), stopped (`stopped`) or noAnswer (noCommand is the ask's own, when no program is found to run),
// with the API's error status (`status`) and the tokens it read from the cache, read fresh, wrote to the cache and
// wrote out, when it said.
NSDictionary *ClaudeAsideAnswer(NSArray<NSData *> *lines, BOOL timedOut, BOOL stopped);
// The step one line of its output starts, in words for the line the session's row shows while it works, or nil for a
// line that starts none (a tool's result, its words, the result): "Thinking", or the first line of its thinking's
// summary (80 characters at most, and never one that names a path or holds anything shaped like a key); a tool it
// calls as the session's own hook words it ("Reading cart.ts", the name only of a file in `folder`, the session's;
// "Searching for “total”", a pattern only when it names no path; "Finding files *.ts"; "Running git log", git's own
// command, never Claude's words for it); "Working" for any other tool.
NSString *ClaudeAsideStep(NSDictionary *line, NSString *folder);
// Whether a `result` line is a copy's early one rather than the ask's answer: it came before the copy said anything for
// the ask (`said`, an `assistant` line since the ask's message), it used nothing (no usage above 0), and it says
// nothing ClaudeAsideAnswer would tell (only noAnswer). Seen live within a second of a fresh copy's start, with the
// real answer a few seconds after (2.1.319); never against a stand-in API.
BOOL ClaudeAsideEarlyResult(NSDictionary *result, BOOL said);
// What panel.log keeps of such a result: its shape, never its words: whether the copy was kept or fresh (`kept`), its
// Claude Code `version`, the seconds since the ask, the subtype, is_error, num_turns, duration_ms, the API's status and
// how many characters it said.
NSString *ClaudeAsideResultShape(NSDictionary *result, double seconds, BOOL kept, NSString *version);
// Whether a copy of Claude Code `version` is asked for its thinking's summaries: a version they were checked with
// (ClaudeAsideThinkingVersions), and not one that turned the flag down (`refused`).
BOOL ClaudeAsideThinks(NSString *version, NSSet<NSString *> *refused);
// Whether a copy run with that flag may have turned it down, and so is asked again without it: it ran, wrote nothing
// at all and ended with an error, neither stopped nor out of time.
BOOL ClaudeAsideFlagRefused(NSDictionary *ran, BOOL heard, BOOL stopped);
// The model a side question asks: the session's, with the long context ("[1m]") its own --model asked for, or that a
// conversation of `tokens` must have had.
NSString *ClaudeAsideModel(NSString *model, NSString *flagModel, NSInteger tokens);
// The program a side question runs: the session's own `running`, when it's one of `candidates` (where Claude Code is
// installed); else the first of them; nil with none.
NSString *ClaudeAsideProgram(NSString *running, NSArray<NSString *> *candidates);
// Whether the session has moved since its copy opened: its transcript's size or newest message (`mark`, {size, at})
// isn't what it was, or either isn't known.
BOOL ClaudeAsideMoved(NSDictionary *opened, NSDictionary *now);
// Whether a follow-up goes into the session's open copy: it's waiting (not `busy` answering or ending), its process is
// the one it started (`started`, its start time, the same now and not 0), asked with the same `model` and `effort`, and
// the session hasn't moved since it opened (`mark`, ClaudeAsideMoved). Else a fresh copy opens.
BOOL ClaudeAsideReuses(NSDictionary *opened, NSDictionary *now);
// The earlier side questions a fresh copy is told: those asked after the session last compacted (`compactedAt`, ms
// since 1970, 0 for never), the newest that fit in a few thousand words, oldest first.
NSArray<NSDictionary *> *ClaudeAsideCarried(NSArray<NSDictionary *> *earlier, double compactedAt);
// What a side question sends: ClaudeAsideLine(), then, in a fresh copy, the earlier questions it's told with their
// answers, then the question.
NSString *ClaudeAsideWords(NSString *question, NSArray<NSDictionary *> *carried, BOOL fresh);
// The copy's environment: `base` (ClaudeEnvironment's) with git's settings for reading only (GitReadOnlyEnvironment),
// and the checker and the session's folder for its hook.
NSDictionary<NSString *, NSString *> *ClaudeAsideEnvironment(NSDictionary<NSString *, NSString *> *base,
                                                             NSString *checker, NSString *folder);
