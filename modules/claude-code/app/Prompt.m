// Prompt: typing a command into a session's prompt through its terminal, and when keys may go in.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Prompt.h"
#import "Files.h"
#import "Processes.h"
#import "Asks.h"
#import "ClaudeSessions.h"
#import "ClaudeCodeFacts.h"

// The keystrokes go one at a time, paced so each lands after the one before, and each only while `whyNot` finds
// nothing against it (the session still at its prompt). A prompt that comes up meanwhile gets none of them.
static void TypeSteps(NSArray<void (^)(void)> *steps, NSUInteger i, Reason *(^whyNot)(void),
                      void (^done)(Reason *why, NSUInteger typed, NSUInteger steps)) {
    Reason *why = whyNot();
    if (why) {
        done(why, i, steps.count);
        return;
    }
    steps[i]();
    BOOL more = i + 1 < steps.count;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((more ? 0.12 : 0.24) * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (more) TypeSteps(steps, i + 1, whyNot, done);
        else done(nil, steps.count, steps.count);
    });
}

// Claude Code's prompt keeps a draft through a command this way: Ctrl+S stashes the draft, and Claude Code puts it
// back once the command has run. On an empty prompt, though, Ctrl+S brings back an older stash instead, so a filler
// "x" goes in first, and DeleteFiller takes it out again afterwards.
void TypeCommand(id<TypingHost> terminal, NSString *tab, NSString *command, Reason *(^whyNot)(void),
                 void (^done)(Reason *why, NSUInteger typed, NSUInteger steps)) {
    TypeSteps(@[^{ [terminal type:@"x" inTab:tab]; },
                ^{ [terminal press:TerminalKeyControlS times:1 inTab:tab]; },
                ^{ [terminal type:command inTab:tab]; },
                ^{ [terminal press:TerminalKeyReturn times:1 inTab:tab]; }],
              0, whyNot, done);
}

void DeleteFiller(id<TypingHost> terminal, NSString *tab) {
    [terminal press:TerminalKeyBackspace times:1 inTab:tab];
}

// What the checks below share: the session is still listed as itself, isn't paused in its terminal (Ctrl+Z, where its
// keys would go to the shell), is in one of `statuses` by Claude Code's own registry, read now (a row is up to a second
// old), and has no permission request pending. With `alone`, its conversation runs in no other terminal either.
static Reason *WhyNoKey(NSString *sessionId, pid_t pid, NSArray<NSString *> *statuses, BOOL alone) {
    NSDictionary *live = ReadJSON(ClaudeDir([kClaudeCodeRegistry
        stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.json", pid]]));
    if (![live isKindOfClass:NSDictionary.class] || ![live[@"sessionId"] isEqual:sessionId])
        return [Reason kind:ReasonSessionGone];
    if (ProcessStopped(pid)) return [Reason kind:ReasonPaused];
    if (alone && [live[@"entrypoint"] isEqual:kClaudeCodeTerminalEntrypoint] && InAnotherTerminal(sessionId, pid))
        return [Reason kind:ReasonOpenTwice];
    if (![statuses containsObject:live[@"status"] ?: @""]) return [Reason status:live[@"status"]];
    if (PendingAsks()[sessionId]) return [Reason kind:ReasonRequestWaiting];
    return nil;
}

// Keys go into a terminal session only while it sits idle at its prompt with no permission request pending. In a
// permission prompt Enter would answer yes, and Shift+Tab would allow all edits for the rest of the session. And never
// while its conversation runs in another terminal too: its terminal can't always tell their tabs apart, so a key could
// land in the other one.
Reason *WhyNotTypeInto(NSString *sessionId, pid_t pid) {
    return WhyNoKey(sessionId, pid, @[@"idle"], YES);
}

// The one key the panel presses while Claude works: a Backspace, once a request it sent has gone in, taking out the
// filler it put before the draft it stashed (TypeCommand). Claude Code puts the draft back the moment a message is
// sent, while Claude starts on it (so its 2.1.270 code reads; its docs don't say), and a Backspace there only edits
// the draft: stopping Claude takes Esc or Ctrl+C. Never while Claude asks something or a request waits, where a key
// could answer it. It goes into the tab the request went into, by its id, so a copy in another tab can't take it.
Reason *WhyNotEditDraft(NSString *sessionId, pid_t pid) {
    return WhyNoKey(sessionId, pid, @[@"idle", @"busy"], NO);
}
