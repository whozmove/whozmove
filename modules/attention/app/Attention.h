// Attention: what the attention module keeps, as plain functions (what each line says, the day's file it goes in,
// when a look at a session is kept, and which days' files have had their 14 days), and its one writer, which adds a
// line to its day's file.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// How long each day's file is kept; how often one session's look is kept while you stay on it; and how long a gap in
// its seenAt (brought up to date each second you're on it) makes the next one a new look.
extern const NSInteger kAttentionDays;
extern const double kAttentionSeenEvery, kAttentionNewLookAfter;

// An app came to the front (`at` in seconds since 1970): only whether it's one Whozmove works with (a terminal it
// knows, or Claude Desktop), never which.
NSDictionary *AttentionFront(double at, BOOL worksWithIt);
// You went away from the Mac (no key or pointer for 5 minutes, or its screen locked or asleep), or came back.
NSDictionary *AttentionPresence(double at, BOOL atTheMac);
// You looked at a session's row or window, by its id.
NSDictionary *AttentionSeen(double at, NSString *sessionId);
// Whether a session's seenAt (in ms) is kept, given the one last kept for it and the one last seen: a new look (the
// first, or after a gap) at once, and then once a minute while you stay on it.
BOOL AttentionSeenDue(NSNumber *lastKept, NSNumber *lastSeen, double seenAt);
// The day's file a line kept at `at` goes in: "2030-01-15.jsonl", by this Mac's own days.
NSString *AttentionFileFor(double at);
// Of a folder's files, those whose day is before the one kAttentionDays before `now`'s: to be taken away.
NSArray<NSString *> *AttentionExpired(NSArray<NSString *> *names, double now);
// One line added to its day's file in the folder (the folder 0700, the file 0600). NO if it couldn't be written.
BOOL AttentionAppend(NSString *folder, NSDictionary *line, double now);
