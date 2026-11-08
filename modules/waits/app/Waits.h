// Waits: the plain functions of waiting and waking: what a session waits on in words, what came, which wakes go now
// with the gear as it is, what a wait answers, and the record kept of each wait. WaitsModule.m is its face for the
// core; nothing here asks anything of the app.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Wake.h"

// One session's wait: when it began (ms since 1970); when its wait command last asked, as the panel's own clock counts
// it (moved on by any time the Mac slept, WaitSlept); since when nothing it waits on could be read (0 while something
// can); since when its conversation has run in a new process that hasn't asked yet (0 for none, and again once it has
// closed or runs in its own process); the process it began in (its pid, and when that started, so a pid used again
// isn't taken for it); whether comments wake it too; what it waits on, as the sources named it; what has come, oldest
// first; whether what came waits for a seat; whether its conversation has closed (its process gone: it's kept, and
// watched, for Resume), and whether it runs again in another process now, which hasn't asked yet (so it isn't shown as
// closed); and the sources that watch it in this copy of the app.
@interface WaitState : NSObject
@property (assign) double since, askedAt, cantSince, handedOverAt;
@property (assign) pid_t pid;
@property (assign) long long started;
@property (assign) BOOL comments, held, closed, reopened, missed;
@property (copy) NSArray<WaitOn *> *on;
@property (copy) NSArray<Wake *> *came;
@property (strong) NSHashTable *watchedBy;
@end

// How long a wait goes without its command asking before it's taken to have stopped (the command asks every 10
// seconds); how long one let go to wake counts as taken in the gear before its row shows it at work; and how long
// nothing it waits on can be read before the wait ends, so the session says so rather than waiting on it for good;
// and how long its conversation, run again in a new process, has to ask before the wait ends (Resume's words ask at
// once).
extern const double kWaitStoppedAfterMs, kLetGoCountsMs, kCantReadForMs, kHandOverMs;

// The row's words for what it waits on, "Waits on #12 · #13", with what can't be read now said after it ("Waits on
// #12 · #13 can't be read now"), or, when none can be, why the first can't, as its source says it ("Waits on #12: gh
// may need you to sign in (gh auth login)"); and the same for VoiceOver, "Waits on pull request 12 and pull request
// 13". Each name cut at a word's end. Nil for nothing.
NSString *WaitSays(NSArray<WaitOn *> *on);
// The same for a closed one: "Stopped, waiting on #12"; and for one run again that hasn't asked in its while: "Not
// waiting on #12 any more".
NSString *WaitClosedSays(NSArray<WaitOn *> *on);
NSString *WaitMissedSays(NSArray<WaitOn *> *on);
NSString *WaitSpoken(NSArray<WaitOn *> *on);
// What came, in a few words for the row while it waits for a seat: the first, "#12 approved", with how many more; and
// the same for VoiceOver, "#12 approved, and 1 more".
NSString *WaitCameSays(NSArray<Wake *> *came);
NSString *WaitCameSpoken(NSArray<Wake *> *came);
// The row's `wait` (Row.h), from the state.
NSDictionary *WaitShown(WaitState *wait);

// Which held waits may wake now, oldest wake first: all with no gear (Usage Gear off: `gear` nil) or none picked yet
// (`room` NSNull); else as many as the gear has room for, less those let go and not yet at work (`letGo`). `held`
// is each waiting session's id with when its first wake came.
NSSet<NSString *> *WakesThatGo(NSDictionary<NSString *, NSNumber *> *held, NSDictionary *gear, NSInteger letGo);
// Whether a let-go wake still counts as taken in the gear: until its session is counted at work, for 30 seconds.
BOOL LetGoStillTaken(double letGoAt, BOOL atWork, double now);

// What a wake says: "woke: " and what came, as one line of JSON ({came: [facts…]}, oldest first).
NSString *WokeAnswer(NSArray<Wake *> *came);
// Whether what came includes your own answer, which goes over the gear.
BOOL WaitCameYours(WaitState *wait);
// What a wait answers its command now: "waiting: …" (or "nothing yet: …" when asked to answer at once) until
// something has come; then, once the gear lets it go (`mayGo`) or it's your own answer, or it was asked at once (the
// session is at work already), "woke: …", setting `wakes`; else "waiting: for a free seat in the gear: …". A wait whose
// every thing has been unreadable for kCantReadForMs ends instead, "nothing to wait for: …", setting `ends`.
NSString *WaitAnswer(WaitState *wait, BOOL justNow, BOOL mayGo, double now, BOOL *wakes, BOOL *ends);
// Why a wait is over now, or nil: its row has gone, or, while it runs in its own process, its command hasn't asked for
// kWaitStoppedAfterMs of the panel's time. A conversation that has closed (`closed`) goes on waiting, kept for Resume,
// and so does one run again in a new process that hasn't asked (WaitMissed says when it's had its while).
NSString *WhyWaitEnds(WaitState *wait, BOOL listed, BOOL closed, BOOL sameProcess, double now);
// How long the Mac slept between two passes, from the wall clock's gap and the awake clock's (which stops while the Mac
// sleeps), in ms: 0 for a gap under 2 seconds, which is only a pass that came late.
double WaitSlept(double wallGap, double awakeGap);
// Since when its conversation has run in a new process that hasn't asked, on a pass that finds its row closed, in the
// wait's own process, or in another (`elsewhere`): 0 but in another, where it's when that was first seen, so a later
// try (a second Resume after a first that closed before it asked) gets a while of its own.
double WaitHandOver(WaitState *wait, BOOL closed, BOOL elsewhere, double now);
// Whether its conversation, run again in a new process, has had its while to ask (kHandOverMs) and hasn't: its row then
// offers Resume's words, sent by your press.
BOOL WaitMissed(WaitState *wait, double now);

// The record kept of a wait, in Whozmove's folder, so a restart finds what came while it was away: when it began, its
// process, whether comments wake it, whether its conversation has closed, and what it waits on by the sources' ids.
// Never a word of what came. And read back, nil for one that isn't a wait's.
NSDictionary *WaitKept(WaitState *wait);
WaitState *WaitFromKept(NSDictionary *kept);
