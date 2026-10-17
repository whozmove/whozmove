// Work: who's at work in a checkout, and what waits for them.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Work.h"
#import "Row.h"
#import "Files.h"

BOOL AgentAtWork(Row *row) {
    return [@[@"busy", @"waiting"] containsObject:row.status ?: @""] || row.ask || row.compacting;
}

// The folder a row's steps and Deploy act on: the checkout its session runs in (for one that runs outside any, the one
// it last edited files in), or its folder outside git. And the folders a session works in: its own checkout (or
// folder), and the one its edits last landed in (workRoot) while the turn it's on has edited files there, whichever row
// that checkout's island is on.
static NSString *FolderOf(Row *row) {
    return (row.workGit ?: row.git)[@"root"] ?: row.cwd;
}

// Whether a session's last edits (workRoot) came during the turn it's on now: they landed after that turn began. An
// older hook doesn't note when it edited; then it's taken that they did. The page asks the same (editingThisTurn in
// modules/deploy/page/deploys.js).
static BOOL EditingThisTurn(Row *row) {
    return !row.editedAt || !row.lastPromptAt || row.editedAt.doubleValue >= row.lastPromptAt.doubleValue;
}

NSArray<Row *> *OthersAtWork(Row *row, NSArray<Row *> *rows) {
    NSString *folder = FolderOf(row);
    NSMutableArray<Row *> *others = [NSMutableArray array];
    for (Row *other in folder ? rows : @[]) {
        // Working, or compacting: one waiting on you changes nothing until you answer it, and may wait for days.
        BOOL working = ([other.status isEqual:@"busy"] && !other.ask) || other.compacting;
        if ([other.sessionId isEqual:row.sessionId] || !working) continue;
        if ([folder isEqual:other.git[@"root"] ?: other.cwd]
            || ([folder isEqual:other.workRoot] && EditingThisTurn(other)))
            [others addObject:other];
    }
    return others;
}

NSString *WhyStepsWait(Row *row, NSArray<Row *> *rows, NSString *what) {
    if (AgentAtWork(row)) return [what stringByAppendingString:@" until the agent is done"];
    // The others named as their rows are titled, so they can be found in the list; in order, so it reads the same each
    // time. The page says it the same way (untilDone in modules/deploy/page/deploys.js).
    NSMutableSet<NSString *> *named = [NSMutableSet set];
    for (Row *other in OthersAtWork(row, rows))
        [named addObject:[NSString stringWithFormat:@"“%@”", Clip(other.name.length ? other.name
                                                                     : other.cwd.lastPathComponent ?: @"", 40)]];
    NSArray<NSString *> *titles = [named.allObjects sortedArrayUsingSelector:@selector(compare:)];
    if (!titles.count) return nil;
    if (titles.count == 1) return [NSString stringWithFormat:@"%@ until the agent in %@ is done", what, titles[0]];
    NSString *rest = titles.count == 2 ? titles[1]
                                       : [NSString stringWithFormat:@"%lu others", (unsigned long)titles.count - 1];
    return [NSString stringWithFormat:@"%@ until the agents in %@ and %@ are done", what, titles[0], rest];
}
