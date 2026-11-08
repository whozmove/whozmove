// ForYou: whether Compact at Breaks may compact a session by itself now, as plain functions the tests check.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Row;

// What's known of a session beside its row, as the module finds it each second.
typedef struct {
    double now;            // in ms since 1970
    double startedAt;      // when Whozmove started, in ms since 1970
    double lastDone;       // when it last compacted the session, or last tried and couldn't (0 for never)
    BOOL oneGoingIn;       // a compaction from the panel is going into a session now
    BOOL desktop;          // the session is a Claude Desktop conversation
    BOOL atTheMac;         // you're at the Mac (Focus's AtTheMac)
    BOOL byThemselves;     // where held words go in by themselves (Send's WordsGoByThemselves)
    BOOL panelInUse;       // you've used the panel in the last few seconds
} ForYouFacts;

// How long a break has to have lasted before it compacts, how long after a turn ends Claude's cache of the
// conversation is taken to stay warm, and how recently you've been on a session for it to wait.
extern const double kSettledMs, kWarmMs, kOnItWithinMs;

// Whether nobody's on the session, so nothing typed by itself can meet your keys: you haven't been on it in the last 5
// minutes (looking at it, or writing to it: the row's onItAt), and either you're away from the Mac or it's where held
// words go in by themselves (not the session you're on, and its terminal not the app in front), and you haven't used
// the panel in the last few seconds. Asked again before each key.
BOOL NobodyOnIt(Row *row, ForYouFacts facts);

// Why Compact at Breaks doesn't compact a session now, in plain words for panel.log, or nil once it may (but for its
// tab, which is looked for last, for the one session that gets this far). Cheapest first: nothing else going in; a
// break (the row's compactTime, as the ring goes by) other than "away an hour", which is the ring's suggestion for
// your press, as compacting a session whose cache has gone cold reads all of it at full price; a terminal session, not
// Claude Desktop's, which would come forward; one whose messages its hooks record (not one started before them, whose
// next message couldn't be told); not done since its last message; nothing it runs in the background that can change
// files; its break settled (its turn over for 2 minutes, so a quick back-and-forth is never interrupted) and its cache
// still warm (within the hour); Whozmove running for 5 minutes, as who's been on each session is known only from then;
// and nobody on it (NobodyOnIt).
NSString *WhyNotCompactForYou(Row *row, ForYouFacts facts);
