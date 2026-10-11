// Terminal: the shape every terminal the panel works with fills in, and typing a command into a session through it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Terminal.h"

id<Terminal> TerminalFor(NSArray<id<Terminal>> *terminals, NSString *appId) {
    for (id<Terminal> terminal in terminals)
        if ([terminal.appId isEqualToString:appId]) return terminal;
    return nil;
}

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
void TypeCommand(id<Terminal> terminal, NSString *tab, NSString *command, Reason *(^whyNot)(void),
                 void (^done)(Reason *why, NSUInteger typed, NSUInteger steps)) {
    TypeSteps(@[^{ [terminal type:@"x" inTab:tab]; },
                ^{ [terminal press:TerminalKeyControlS times:1 inTab:tab]; },
                ^{ [terminal type:command inTab:tab]; },
                ^{ [terminal press:TerminalKeyReturn times:1 inTab:tab]; }],
              0, whyNot, done);
}

void DeleteFiller(id<Terminal> terminal, NSString *tab) {
    [terminal press:TerminalKeyBackspace times:1 inTab:tab];
}
