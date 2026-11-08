// Usage: how much of your Claude plan you've used, in the five-hour session and the week, asked of Claude Code itself
// for the usage card under the panel.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import "Host.h"
#import "Agent.h"

@class PanelWindow, UsageCard;

// When it's next asked, as plain values the tick moves on (UsageDue, UsageAnswered, UsageSoon), so a print run can
// check them: due by `busyAt` while a session works or the card shows more than its line, else by `quietAt`;
// `retryAfter` while asking fails; asked often until `signingInUntil` after Sign in; `away`, you were, at the last tick.
typedef struct {
    NSTimeInterval busyAt, quietAt, retryAfter, signingInUntil;
    BOOL away;
} UsageTimes;

// On a tick at `now`, `idle` seconds since a key or the pointer last moved: whether to ask now.
BOOL UsageDue(UsageTimes *times, NSTimeInterval now, NSTimeInterval idle, BOOL busy);
// What was found (its state, "failed" for nothing) and when its windows reset (seconds since 1970, 0 for none): when
// it's next asked.
void UsageAnswered(UsageTimes *times, NSString *state, NSArray<NSNumber *> *resets, NSTimeInterval now);
// Asked again by `at`, if it wasn't going to be sooner: waking, Sign in.
void UsageSoon(UsageTimes *times, NSTimeInterval at);
// `Whozmove --print-usage-checks <cases.json>`: for each sample stretch of time, when the usage would be asked, through
// the functions above, then which answers leave a card (UsageShowsCard); the exit status.
int PrintUsageChecks(NSArray<NSString *> *arguments);
// The last plan numbers found, in usage-last.json in Whozmove's own folder, so a script of yours can follow your pace
// without starting `claude` again: when they were checked, and each window's percent used and reset (ms since 1970),
// nothing else of the answer.
void UsageKeepLast(NSDictionary *usage);
// Whether an answer in `state` leaves a card to show: its numbers ("ok"), or Sign in ("signedOut"); not one with no
// plan's numbers ("other", the agent's `noPlan` saying why), nor one with nothing to ask ("none") (page/usage.js's
// usageView says the same).
BOOL UsageShowsCard(NSString *state);
// `Whozmove --print-usage-kept <usage.json>`: what UsageKeepLast keeps of that answer; it refuses your own home.
int PrintUsageKept(NSArray<NSString *> *arguments);
// What panel.log says of an answer, once each time its state or why it has no plan's numbers (`noPlan`) changes from
// `was` (what this gave back for the last answer, a failed one too; nil at the start, so each start says it once):
// with no card, the card is hidden and why; else what the card does: shows your plan's numbers, asks you to sign in,
// or keeps what it last showed when no answer came; and an answer with no state, or one it doesn't know, hides the card
// as one that can't be read. Each in words of its own written out in its call, so a reader of the log tells them apart
// by their words alone, and `noPlan` itself never in a line. `agent` is its name, or nil when there's none. It gives
// back what to pass as `was` next: the answer's {state, noPlan}, a missing or unknown state as "unreadable".
NSDictionary *UsageLogAnswer(NSDictionary *was, NSDictionary *found, NSString *agent);
// `Whozmove --print-usage-said <answers.json>`: each run of answers, from a fresh start, through UsageLogAnswer, and
// the lines it wrote to panel.log, without their times; it refuses your own home, as it writes there.
int PrintUsageSaid(NSArray<NSString *> *arguments);
// Why Sign in can't open with no terminal on this Mac, naming the terminals Whozmove opens (`names`, each terminal the
// core finds, in its order), so it follows the terminal modules there are: "…: Whozmove opens Ghostty, iTerm2 or
// Terminal".
NSString *UsageNoTerminal(NSArray<NSString *> *names);
// What the card says when Sign in couldn't open a terminal: `why`, then the one way left whatever the terminal does,
// running `command` (the sign-in command, as the agent gives it, put in as it is) in any terminal yourself: "Ghostty
// didn't open a tab for it. Or run … in any terminal yourself." `why` alone when there's no command.
NSString *UsageSignInOr(NSString *why, NSString *command);
// `Whozmove --print-sign-in`: the no-terminal sentence for the terminals Whozmove opens (`names`), and for none, one
// and two; and what the card says with the command to run yourself, for a sample reason and command, with none, for a
// reason ending in a full stop, and for the no-terminal sentence.
int PrintSignIn(NSArray<NSString *> *names);

@interface Usage : NSObject
// Asked of the agent (AgentUsage), for the card's page.
- (instancetype)initWithCard:(UsageCard *)card window:(PanelWindow *)window agent:(id<AgentUsage>)agent;
// From the 1-second tick: asks the agent when a check is due.
- (void)pollIfDue;
// A session is at work (a row's `busy`), so the usage moves: it's asked more often.
@property (assign) BOOL working;
// The card's page, freshly loaded, gets what's known.
- (void)resend;
// Each answer in state "ok", as the card's page has it (with `checkedAt`): the gear measures from it.
@property (copy) void (^answered)(NSDictionary *usage);
// Each answer, but one that failed (which leaves the card as it was): whether it leaves a card to show (UsageShowsCard).
@property (copy) void (^cardShown)(BOOL shown);
// The card's Sign in: a tab signing the agent in, in `terminal` (the first of `terminals`, those the core finds, that's
// on this Mac), then a check every 15 seconds until it has; or, on the card, why it couldn't open, and the command to
// run yourself.
- (void)signInWith:(id<CommandHost>)terminal among:(NSArray<id<CommandHost>> *)terminals;
@end
