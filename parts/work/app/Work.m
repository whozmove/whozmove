// Work: who's at work in a checkout, and what waits for them.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Work.h"
#import "Row.h"
#import "Files.h"

BOOL AgentAtWork(Row *row) {
    return [@[@"busy", @"waiting"] containsObject:row.status ?: @""] || row.ask || row.compacting;
}

BOOL AgentAsksYou(Row *row) {
    return row.ask != nil
        || [@[@"waiting", @"needs_input", @"requires_action", @"blocked"] containsObject:row.status ?: @""];
}

// The row's background jobs that hold its steps.
static NSArray<NSDictionary *> *Holding(Row *row) {
    return [row.background filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"holds == YES"]];
}

BOOL BackgroundAtWork(Row *row) {
    return Holding(row).count > 0;
}

// The folder a row's steps and Deploy act on: the checkout its session runs in (for one that runs outside any, the one
// it last edited files in), or its folder outside git. And the folders a session works in: its own checkout (or
// folder), and the one its edits last landed in (workRoot) while the turn it's on has edited files there, whichever row
// that checkout's next steps are on.
static NSString *FolderOf(Row *row) {
    return (row.workGit ?: row.git)[@"root"] ?: row.cwd;
}

// Whether a session's last edits (workRoot) came during the turn it's on now: they landed after that turn began. An
// older hook doesn't note when it edited; then it's taken that they did. The page asks the same (editingThisTurn in
// modules/deploy/page/deploys.js).
static BOOL EditingThisTurn(Row *row) {
    return !row.editedAt || !row.lastPromptAt || row.editedAt.doubleValue >= row.lastPromptAt.doubleValue;
}

static BOOL CopyAtWork(Row *row) {
    for (NSDictionary *copy in row.alsoOpen)
        if ([copy[@"busy"] boolValue]) return YES;
    return NO;
}

// Working, or compacting: one waiting on you changes nothing until you answer it, and may wait for days. A conversation
// open more than once works wherever one of its copies does, though its row shows another. Its agents in the
// background count too: they edit files there while it takes your messages.
BOOL SessionWorking(Row *row) {
    return ([row.status isEqual:@"busy"] && !row.ask) || row.compacting || CopyAtWork(row) || BackgroundAtWork(row);
}

NSArray<Row *> *OthersAtWork(Row *row, NSArray<Row *> *rows) {
    NSString *folder = FolderOf(row);
    NSMutableArray<Row *> *others = [NSMutableArray array];
    for (Row *other in folder ? rows : @[]) {
        if ([other.sessionId isEqual:row.sessionId] || !SessionWorking(other)) continue;
        if ([folder isEqual:other.git[@"root"] ?: other.cwd]
            || ([folder isEqual:other.workRoot] && EditingThisTurn(other)))
            [others addObject:other];
    }
    return others;
}

// A name cut to `most` characters at most, at the end of a word, with "…" where it was cut, so no word shows in half.
static NSString *UpToWord(NSString *text, NSUInteger most) {
    if (text.length <= most) return text;
    NSString *cut = Clip(text, most - 1);
    NSRange space = [cut rangeOfCharacterFromSet:NSCharacterSet.whitespaceCharacterSet options:NSBackwardsSearch];
    if (space.location != NSNotFound && space.location > 0) cut = [cut substringToIndex:space.location];
    NSMutableCharacterSet *loose = NSMutableCharacterSet.whitespaceCharacterSet;
    [loose formUnionWithCharacterSet:NSCharacterSet.punctuationCharacterSet];
    return [[cut stringByTrimmingCharactersInSet:loose] stringByAppendingString:@"…"];
}

NSString *BackgroundWait(Row *row) {
    NSArray<NSDictionary *> *holding = Holding(row);
    if (!holding.count) return nil;
    // The way to stop one sooner, as its agent says: what to type in the session.
    NSString *stop = AsText(holding[0][@"stop"]);
    NSString *how = !stop.length ? @""
        : [NSString stringWithFormat:@" (type %@ in the session to stop %@ sooner)", stop,
                                     holding.count == 1 ? @"it" : @"one"];
    if (holding.count > 1)
        return [NSString stringWithFormat:@"until the %lu agents in the background are done%@",
                                          (unsigned long)holding.count, how];
    NSString *named = [holding[0][@"what"] length]
        ? [NSString stringWithFormat:@"“%@” is done in the background", UpToWord(holding[0][@"what"], 40)]
        : @"the agent in the background is done";
    return [NSString stringWithFormat:@"until %@%@", named, how];
}

NSString *WhyStepsWait(Row *row, NSArray<Row *> *rows, NSString *what) {
    if (AgentAtWork(row)) return [what stringByAppendingString:@" until the agent is done"];
    NSString *background = BackgroundWait(row);
    if (background) return [NSString stringWithFormat:@"%@ %@", what, background];
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
