// WaitsModule: a session whose next step is someone else's (a review of its pull request, an approval, a merge) runs
// `ask-panel.sh wait` in the background and ends its turn, so it holds no seat. Its wait command asks every 10
// seconds; the module asks each source (WakeSource, contracts/Wake.h) what the session waits on and what has come, and
// answers "woke: …" once something has and the gear has room for it, oldest first. Claude Code then carries the
// conversation on. The row says what it waits on, and what came while it waits for a seat. What a wait answers and why
// one ends are Waits.m's plain functions; this is its face for the core.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "WaitsModule.h"
#import "Waits.h"
#import "Core.h"
#import "Row.h"
#import "Rows.h"
#import "Log.h"
#import "Files.h"
#import "Text.h"
#import "Processes.h"
#import "Notice.h"
#import "Focus.h"
#import "Send.h"
#import "Page.h"
#import <time.h>

// What a conversation that closed while it waited is told as it's opened again from its row (by Resume, its row's own
// press, or anything that opens it as that does): fixed words, never anything from outside.
static NSString *const kResumeWords = @"Whozmove: this conversation closed while it waited on someone else. As the "
    @"waiting skill says, run ask-panel.sh wait --now to hear what came since the wait began, and carry on from there.";

@interface WaitsModule () <ReopenWords>
@property (strong, readwrite) NSMutableDictionary<NSString *, WaitState *> *waits;
// Sessions let go to wake, by id, with when: each counts as taken in the gear until it's counted at work (LetGoStillTaken).
@property (strong) NSMutableDictionary<NSString *, NSNumber *> *letGo;
// The held waits that may wake now, as the last look at the gear found them.
@property (copy) NSSet<NSString *> *mayGo;
@property (copy) NSString *keptFolder;
// When the last pass ran, by the wall clock and by the time the Mac has been awake, to tell how long it slept between;
// and the rows it was given, by id.
@property (assign) double lastPassAt, lastPassAwake;
@property (copy) NSDictionary<NSString *, Row *> *passed;
@end

@implementation WaitsModule

+ (NSString *)moduleName {
    return @"waits";
}

+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return WaitsPrintModes();
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.waits = [NSMutableDictionary dictionary];
    self.letGo = [NSMutableDictionary dictionary];
    self.mayGo = [NSSet set];
    return self;
}

- (void)launch {
    [self keepIn:AppDir(@"waits")];
}

- (double)now {
    return self.clock ? self.clock() : NSDate.date.timeIntervalSince1970 * 1000;
}

// The time the Mac has been awake, which stops while it sleeps (CLOCK_UPTIME_RAW).
- (double)awake {
    return self.awakeClock ? self.awakeClock() : clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1e6;
}

- (NSArray<id<WakeSource>> *)sources {
    return self.givenSources ?: [self.core modulesThat:@protocol(WakeSource)];
}

// The gear as the usage module keeps it: nil while Usage Gear is off (or there's no usage module), when every wake goes.
- (NSDictionary *)gear {
    if (self.givenGear) return self.givenGear();
    id<GearFacts> facts = [self.core moduleThat:@protocol(GearFacts)];
    return facts.gear;
}

#pragma mark What's kept

// Waits kept by a copy of the app before this one are read back: their commands keep asking through the restart, so
// each is given a minute from now to ask again, and is watched again from when it began, on what it began on, so what
// came while the app was away is found.
- (void)keepIn:(NSString *)folder {
    self.keptFolder = folder;
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES
                                             attributes:@{NSFilePosixPermissions: @0700} error:nil];
    double now = [self now];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil]) {
        NSString *sessionId = [name hasSuffix:@".json"] ? name.stringByDeletingPathExtension : nil;
        WaitState *wait = IsPlainId(sessionId, 64)
            ? WaitFromKept(AsRecord(ReadJSON([folder stringByAppendingPathComponent:name]))) : nil;
        if (!wait) continue;
        wait.askedAt = now;
        self.waits[sessionId] = wait;
    }
}

- (NSString *)keptPath:(NSString *)sessionId {
    return self.keptFolder && IsPlainId(sessionId, 64)
        ? [self.keptFolder stringByAppendingPathComponent:[sessionId stringByAppendingPathExtension:@"json"]] : nil;
}

// Only you able to read it, and never a word of what came.
- (void)keep:(NSString *)sessionId {
    NSString *path = [self keptPath:sessionId];
    WaitState *wait = self.waits[sessionId];
    NSData *data = path && wait ? [NSJSONSerialization dataWithJSONObject:WaitKept(wait)
                                                                  options:NSJSONWritingSortedKeys error:nil] : nil;
    if (data) [NSFileManager.defaultManager createFileAtPath:path contents:data attributes:@{NSFilePosixPermissions: @0600}];
}

#pragma mark Asked

- (NSDictionary<NSString *, SessionAsk *> *)sessionAsks {
    __weak typeof(self) weakSelf = self;
    // It only reads back what came, and does nothing in the session's name. It's asked every 10 seconds, so it logs
    // only a wait's beginning, what came and its end itself.
    SessionAsk *wait = [SessionAsk askShowing:^NSString *(Row *row, pid_t process, NSDictionary *asked) {
        return [weakSelf wait:asked from:row];
    }];
    wait.logsItself = YES;
    return @{@"wait": wait};
}

// `wait`, run in the background, with its flags in each order ask-panel.sh takes them: this module's own ask waiting
// on the panel, which the agent's module doesn't list as the session's work (BackgroundWaits). Its test runs each
// through ask-panel.sh, so they never drift from what it takes.
- (NSArray<NSArray<NSString *> *> *)backgroundWaits {
    return @[@[@"wait"], @[@"wait", @"--comments"], @[@"wait", @"--now"], @[@"wait", @"--now", @"--comments"],
             @[@"wait", @"--comments", @"--now"]];
}

// What it would wait on now, as each source says.
- (NSArray<WaitOn *> *)onFor:(Row *)row {
    NSMutableArray *on = [NSMutableArray array];
    for (id<WakeSource> source in self.sources) {
        WaitOn *each = [source waitsOn:row];
        if (each.says.length) [on addObject:each];
    }
    return on;
}

// Whether the row is still the process the wait began in.
- (BOOL)wait:(WaitState *)wait isIn:(Row *)row {
    return row.pid > 0 && row.pid == wait.pid && ProcessStartedAt(row.pid) == wait.started;
}

- (NSString *)wait:(NSDictionary *)asked from:(Row *)row {
    NSString *sessionId = row.sessionId;
    double now = [self now];
    BOOL justNow = [AsNumber(asked[@"now"]) boolValue], comments = [AsNumber(asked[@"comments"]) boolValue];
    WaitState *wait = self.waits[sessionId];
    if (wait && ![self wait:wait isIn:row]) {
        // Its conversation carried on in a new process (Resume, its row's press, claude --resume): once its old one has
        // gone, the wait goes on there, from when it began, so what came while it was closed still wakes it. A copy
        // open beside the old one begins a wait of its own.
        if (wait.closed || !ProcessAlive(wait.pid)) [self carryOn:wait in:row now:now];
        else {
            [self end:sessionId why:@"its conversation runs in another process beside it"];
            wait = nil;
        }
    }
    if (!wait && justNow) return @"nothing yet: no wait has begun here; run ask-panel.sh wait in the background to begin one";
    if (!wait) return [self begin:row comments:comments now:now];
    wait.askedAt = now;
    [self findCame:sessionId];
    // A wake from someone else goes only as the gear has room, as the last look found it, or this one now.
    if (wait.came.count && !justNow && !WaitCameYours(wait)) [self seat];
    BOOL wakes = NO, ends = NO;
    NSString *answer = WaitAnswer(wait, justNow, [self.mayGo containsObject:sessionId], now, &wakes, &ends);
    if (ends) [self end:sessionId why:@"nothing it waited on could be read for a while"];
    if (wakes) {
        if (!justNow) self.letGo[sessionId] = @(now);
        NSMutableArray *kinds = [NSMutableArray array];
        for (Wake *each in wait.came) [kinds addObject:[NSString stringWithFormat:@"%@ %@", each.source, each.kind]];
        // Its sources and kinds only, never who or what was said.
        [self end:sessionId why:[@"woke: " stringByAppendingString:[kinds componentsJoinedByString:@", "]]];
    }
    return answer;
}

- (void)carryOn:(WaitState *)wait in:(Row *)row now:(double)now {
    wait.pid = row.pid;
    wait.started = ProcessStartedAt(row.pid);
    wait.closed = wait.reopened = wait.missed = NO;
    wait.handedOverAt = 0;
    wait.askedAt = now;
    [self keep:row.sessionId];
    PanelLog(@"%@ -> its wait carries on in its new process", row.sessionId);
}

// A wait begun: what it waits on, as each source says; watched by each from now. One with nothing to wait on, or
// nothing that can be read now, is said so at once, so a session never waits on nothing.
- (NSString *)begin:(Row *)row comments:(BOOL)comments now:(double)now {
    NSString *sessionId = row.sessionId;
    if (row.pid <= 0) return @"refused: only a session that's running can wait";
    NSArray<WaitOn *> *on = [self onFor:row];
    NSArray<WaitOn *> *readable = [on filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"cant == nil"]];
    if (!readable.count) {
        PanelLog(@"%@ asked wait: nothing to wait for", sessionId);
        if (!on.count) return @"nothing to wait for: nothing of this session's waits on someone else now";
        NSMutableArray *cant = [NSMutableArray array];
        for (WaitOn *each in on) [cant addObject:[NSString stringWithFormat:@"%@ can't be read now (%@)", each.says, each.cant]];
        return [@"nothing to wait for: " stringByAppendingString:[cant componentsJoinedByString:@"; "]];
    }
    WaitState *wait = [WaitState new];
    wait.since = wait.askedAt = now;
    wait.pid = row.pid;
    wait.started = ProcessStartedAt(row.pid);
    wait.comments = comments;
    wait.on = readable;
    self.waits[sessionId] = wait;
    [self watch:row wait:wait];
    [self keep:sessionId];
    PanelLog(@"%@ -> waits on %lu%@", sessionId, (unsigned long)readable.count, comments ? @", comments too" : @"");
    return [@"waiting: " stringByAppendingString:WaitSays(readable)];
}

// Each source that doesn't watch the wait yet is asked to, with what the wait began on, until it says it does: one
// that couldn't name what it waits on yet (a pull request not read since a restart) is asked again on the next pass.
- (void)watch:(Row *)row wait:(WaitState *)wait {
    NSMutableArray *began = [NSMutableArray array];
    for (WaitOn *each in wait.on)
        if (each.on) [began addObject:each.on];
    for (id<WakeSource> source in self.sources) {
        if ([wait.watchedBy containsObject:source]) continue;
        if ([source watch:row since:wait.since options:@{@"comments": @(wait.comments), @"on": began}])
            [wait.watchedBy addObject:source];
    }
}

- (void)findCame:(NSString *)sessionId {
    WaitState *wait = self.waits[sessionId];
    NSMutableArray<Wake *> *came = [NSMutableArray array];
    for (id<WakeSource> source in self.sources) [came addObjectsFromArray:[source wakesFor:sessionId] ?: @[]];
    [came sortUsingComparator:^NSComparisonResult(Wake *a, Wake *b) {
        return a.at < b.at ? NSOrderedAscending : a.at > b.at ? NSOrderedDescending : NSOrderedSame;
    }];
    if (came.count && !wait.came.count) PanelLog(@"%@ -> something came for its wait", sessionId);
    wait.came = came;
}

// Which held wakes may go now, with the gear as it is: those let go and not yet at work count as taken.
- (void)seat {
    double now = [self now];
    NSDictionary *gear = [self gear];
    NSSet *atWork = [NSSet setWithArray:AsList(gear[@"counted"]) ?: @[]];
    for (NSString *sessionId in self.letGo.allKeys)
        if (!LetGoStillTaken(self.letGo[sessionId].doubleValue, [atWork containsObject:sessionId], now))
            [self.letGo removeObjectForKey:sessionId];
    NSMutableDictionary<NSString *, NSNumber *> *held = [NSMutableDictionary dictionary];
    for (NSString *sessionId in self.waits) {
        WaitState *wait = self.waits[sessionId];
        // A closed one waits for your Resume, not for a seat.
        if (wait.came.count && !wait.closed && !WaitCameYours(wait)) held[sessionId] = @(wait.came.firstObject.at);
    }
    self.mayGo = WakesThatGo(held, gear, (NSInteger)self.letGo.count);
    for (NSString *sessionId in held) {
        WaitState *wait = self.waits[sessionId];
        BOOL waitsForSeat = ![self.mayGo containsObject:sessionId];
        if (waitsForSeat && !wait.held) PanelLog(@"%@ -> its wake waits for a seat in the gear", sessionId);
        wait.held = waitsForSeat;
    }
}

- (void)end:(NSString *)sessionId why:(NSString *)why {
    if (!self.waits[sessionId]) return;
    for (id<WakeSource> source in self.sources) [source unwatch:sessionId];
    [self.waits removeObjectForKey:sessionId];
    NSString *path = [self keptPath:sessionId];
    if (path) [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    PanelLog(@"%@ -> wait over: %@", sessionId, why);
}

#pragma mark Each second

// Each module's tick comes before every read of the rows, so the rows show what this pass found without asking for a
// read of their own. Nothing is decided before the rows have been read once (`rows` nil): until then every session
// would look gone, and every kept wait would end.
- (void)tick {
    if (!self.core.printing) [self pass:self.core.rows.byId.allValues];
}

- (void)pass:(NSArray<Row *> *)rows {
    if (!rows) return;
    double now = [self now], awake = [self awake];
    // While the Mac slept no command could ask, so its last ask moves on by that long: a wait never ends for the sleep.
    double slept = self.lastPassAt > 0 ? WaitSlept(now - self.lastPassAt, awake - self.lastPassAwake) : 0;
    self.lastPassAt = now;
    self.lastPassAwake = awake;
    NSMutableDictionary<NSString *, Row *> *byId = [NSMutableDictionary dictionary];
    for (Row *row in rows)
        if (row.sessionId) byId[row.sessionId] = row;
    self.passed = byId;
    for (NSString *sessionId in self.waits.allKeys) {
        WaitState *wait = self.waits[sessionId];
        wait.askedAt += slept;
        Row *row = byId[sessionId];
        BOOL closed = row && (row.pid <= 0 || [self.core hasEnded:row]);
        BOOL same = row && !closed && [self wait:wait isIn:row];
        // Run again in a new process, it has a while to ask (Resume's words ask at once); closed again, or back in its
        // own, that while is over, and a next try gets its own.
        wait.handedOverAt = row ? WaitHandOver(wait, closed, !closed && !same, now) : wait.handedOverAt;
        // Running again in a new process, it isn't shown as closed (no Resume, no notice) while that has its while to
        // ask; it's still closed to the wait, which that process's first ask carries on.
        wait.reopened = row && !closed && !same;
        // Run again and not asking in its while, it isn't ended: its row offers Resume's words, by your press.
        BOOL missed = WaitMissed(wait, now);
        if (missed && !wait.missed) PanelLog(@"%@ -> its conversation runs again and hasn't asked: Resume offered", sessionId);
        wait.missed = missed;
        NSString *why = WhyWaitEnds(wait, row != nil, closed, same, now);
        if (why) {
            [self end:sessionId why:why];
            continue;
        }
        // Closed while it waits: kept, and watched, so what comes makes it your move, with Resume.
        if (closed && !wait.closed) {
            wait.closed = YES;
            [self keep:sessionId];
            PanelLog(@"%@ -> its conversation closed while it waits: kept for Resume", sessionId);
        }
        [self watch:row wait:wait];
        NSArray<WaitOn *> *on = [self onFor:row];
        if (on.count) wait.on = on;
        BOOL readable = [wait.on indexOfObjectPassingTest:^BOOL(WaitOn *each, NSUInteger i, BOOL *stop) {
            return each.cant == nil;
        }] != NSNotFound;
        if (readable) wait.cantSince = 0;
        else if (!wait.cantSince) wait.cantSince = now;
        [self findCame:sessionId];
    }
    [self seat];
}

#pragma mark The page

- (NSDictionary<NSString *, void (^)(NSDictionary *message)> *)messages {
    __weak typeof(self) weakSelf = self;
    return @{@"waitSay": ^(NSDictionary *msg) {
        NSString *sessionId = AsText(msg[@"sessionId"]);
        if (sessionId) [weakSelf sayResume:sessionId];
    }};
}

// Resume's words, typed in as you'd send them, by this press, as Send says it's safe; where they can't go in, the row
// says why, with the way past it where there's one.
- (void)sayResume:(NSString *)sessionId {
    WaitState *wait = self.waits[sessionId];
    Row *row = self.passed[sessionId];
    if (!wait.missed || !row) return;
    PanelLog(@"%@ -> Resume pressed on its row: its words go in", sessionId);
    __weak typeof(self) weakSelf = self;
    void (^done)(NSString *, NSString *) = ^(NSString *why, NSString *way) {
        if (!why) return;
        PanelLog(@"%@ -> Resume's words didn't go in: %@", sessionId, why);
        if (way) [weakSelf.core.page stepNote:sessionId text:why way:way];
        else [weakSelf.core.page stepNote:sessionId text:why];
    };
    if (self.givenSay) return self.givenSay(kResumeWords, row, done);
    [self.core.send say:kResumeWords row:row here:@"sent from here" there:@"send them there" done:done];
}

#pragma mark Closed while it waits

// The words for one that closed while it waited, as it's opened again from its row.
- (NSString *)wordsOnReopen:(Row *)row {
    return row.sessionId && self.waits[row.sessionId].closed ? kResumeWords : nil;
}

// For each closed conversation something came for: what came, with Resume, which opens it as its row's own press does.
// It's your move, as only your press carries it on.
- (NSArray<Notice *> *)notices {
    NSMutableArray<Notice *> *notices = [NSMutableArray array];
    for (NSString *sessionId in self.waits) {
        WaitState *wait = self.waits[sessionId];
        Row *row = self.passed[sessionId];
        if (!wait.closed || wait.reopened || !wait.came.count || !row) continue;
        NSString *name = row.name.length ? row.name : row.cwd.lastPathComponent ?: @"its conversation";
        Notice *notice = [Notice noticeWithKey:[@"resume-" stringByAppendingString:sessionId] level:NoticeSoon
                                          text:[NSString stringWithFormat:@"%@: Resume “%@”?", WaitCameSays(wait.came),
                                                                          name]];
        notice.button = @"Resume";
        // Put away with its ×, it stays away until more comes (its `since`).
        notice.closes = YES;
        notice.session = sessionId;
        notice.since = [NSString stringWithFormat:@"%.0f", wait.came.firstObject.at];
        __weak typeof(self) weakSelf = self;
        notice.press = ^{
            Row *now = weakSelf.passed[sessionId];
            if (!now) return;
            [weakSelf.core.focus open:@{@"sessionId": sessionId, @"pid": @(now.pid), @"cwd": now.cwd ?: @"",
                                        @"name": now.name ?: @"", @"entrypoint": now.entrypoint ?: @"",
                                        @"hostSessionId": now.hostSessionId ?: @"", @"carryOn": @YES}];
        };
        [notices addObject:notice];
    }
    return notices;
}

- (void)rows:(NSArray<Row *> *)rows phase:(RowPhase)phase {
    if (phase != RowPhaseListed) return;
    for (Row *row in rows) {
        WaitState *wait = row.sessionId ? self.waits[row.sessionId] : nil;
        row.wait = wait ? WaitShown(wait) : nil;
    }
}

@end
