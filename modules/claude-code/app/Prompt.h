// Prompt: a command typed into a Claude Code session's prompt through the terminal it runs in (a TypingHost,
// contracts/Host.h), the way its prompt keeps your draft through it; and when keys may go in at all.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Host.h"
#import "Reason.h"

// Types a slash command into a session's prompt, keeping any draft there, a keystroke at a time and each only while
// `whyNot` returns nil. `done` gets nil once every keystroke is in, or why typing stopped and after how many.
// DeleteFiller takes out the filler it leaves at the end of the draft, once the draft is back.
void TypeCommand(id<TypingHost> terminal, NSString *tab, NSString *command, Reason *(^whyNot)(void),
                 void (^done)(Reason *why, NSUInteger typed, NSUInteger steps));
void DeleteFiller(id<TypingHost> terminal, NSString *tab);

// Why keys can't go into a terminal session right now, or nil when it's safe.
Reason *WhyNotTypeInto(NSString *sessionId, pid_t pid);
// Why the one key that may go into a terminal session while Claude works, a Backspace taking out the filler of a
// request sent from the panel, can't go in now, or nil when it can.
Reason *WhyNotEditDraft(NSString *sessionId, pid_t pid);
