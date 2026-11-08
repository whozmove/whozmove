// ForYou: whether Compact at Breaks may compact a session by itself now.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "ForYou.h"
#import "Row.h"
#import "Work.h"

const double kSettledMs = 2 * 60000, kWarmMs = 60 * 60000, kOnItWithinMs = 5 * 60000;

BOOL NobodyOnIt(Row *row, ForYouFacts facts) {
    double onIt = row.onItAt;
    if (onIt > 0 && facts.now - onIt < kOnItWithinMs) return NO;
    return (!facts.atTheMac || facts.byThemselves) && !facts.panelInUse;
}

NSString *WhyNotCompactForYou(Row *row, ForYouFacts facts) {
    if (facts.oneGoingIn) return @"a compaction is going into a session already";
    NSString *kind = row.compactTime[@"kind"];
    if (!kind) return @"it's at no break";
    if ([kind isEqual:@"away"]) return @"nobody has been on it for an hour, so its cache has gone cold";
    if (facts.desktop) return @"it's a Claude Desktop conversation, which would come forward";
    if (row.reload) return @"it started before Whozmove's hooks, so its next message couldn't be told";
    if (facts.lastDone > 0 && facts.lastDone >= row.lastPromptAt.doubleValue)
        return @"it was compacted, or tried, since its last message";
    if (BackgroundAtWork(row)) return @"it runs something in the background that can change files";
    double moved = MAX(row.lastReplyAt.doubleValue, row.messageAt.doubleValue);
    if (!moved || facts.now - moved < kSettledMs) return @"its turn ended less than 2 minutes ago";
    if (facts.now - moved >= kWarmMs) return @"its turn ended over an hour ago, so its cache has gone cold";
    if (facts.now - facts.startedAt < kOnItWithinMs)
        return @"Whozmove started less than 5 minutes ago, so it can't yet tell whether you're on it";
    if (!NobodyOnIt(row, facts)) return @"you may be on it";
    return nil;
}
