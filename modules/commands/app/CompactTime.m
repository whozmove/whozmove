// CompactTime: whether now is a natural break to compact a session.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "CompactTime.h"
#import "Row.h"
#import "Work.h"

NSString *const kCompactSaved = @"saved", *const kCompactFull = @"full", *const kCompactAway = @"away";
// How long after a compaction's result its own lines may still be landing in the transcript.
static const double kCompactWrittenMs = 30000;

// The outcomes of a turn that saved its work somewhere it stays.
static NSArray<NSString *> *SavedOutcomes(void) {
    return @[@"Committed", @"Pushed", @"PR raised", @"Merged", @"On staging", @"Deployed"];
}

NSDictionary *CompactTime(Row *row, double onItAt, BOOL focused, double compactedAt, double now) {
    NSInteger tokens = [row.agent[@"tokens"] isKindOfClass:NSNumber.class] ? [row.agent[@"tokens"] integerValue] : 0;
    if (tokens <= 0 || ![row.status isEqual:@"idle"] || AgentAtWork(row) || row.noCompact || row.goingIn
        || row.switchAsk)
        return nil;
    // Its next message is when its hooks record one; for a session started before them, which records none, when its
    // transcript moves again, past what the compaction itself wrote there.
    BOOL movedSince = row.reload && row.messageAt.doubleValue > compactedAt + kCompactWrittenMs;
    if (compactedAt > 0 && compactedAt >= row.lastPromptAt.doubleValue && !movedSince) return nil;
    NSInteger window = [row.agent[@"window"] isKindOfClass:NSNumber.class] ? [row.agent[@"window"] integerValue] : 0;
    if (window <= 0) window = 200000;
    if (tokens * 100 >= window * 85)
        return @{@"why": @"it's nearly full, and would soon compact by itself", @"kind": kCompactFull};
    if (tokens < MIN(200000, window / 2)) return nil;
    NSString *root = (row.git ?: row.workGit)[@"root"];
    id changes = row.checkout[@"changes"];
    BOOL editedHere = root && [row.workRoot isEqualToString:root] && row.workEditedAt > 0;
    BOOL committed = editedHere && [changes isKindOfClass:NSNumber.class] && [changes integerValue] == 0;
    if ([SavedOutcomes() containsObject:row.outcome ?: @""] || committed)
        return @{@"why": @"your work is saved", @"kind": kCompactSaved};
    double moved = MAX(MAX(row.lastReplyAt.doubleValue, row.messageAt.doubleValue), onItAt);
    if (moved > 0 && !focused && now - moved >= 3600000)
        return @{@"why": @"you've been away from it for an hour, so Claude would read all of it again with your next "
                         @"message",
                 @"kind": kCompactAway};
    return nil;
}
