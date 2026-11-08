// WaitsPrints: --print-wakes, the waits module driven as the core would drive it, step by step, with a made-up source
// ("sample"), a made-up gear and a clock of its own, in a throwaway home only: waits begun, and refused when there's
// nothing to wait on or nothing that can be read; what came, from before and after a wait began; wakes going as the
// gear has room, oldest first, your own answer at once, every one with Usage Gear off or no gear picked; waits ending
// as their process does, runs again, stops asking or their row goes; what's kept, and read back after a restart; the
// rows' `wait`; the plain functions over made-up cases; and panel.log, which carries no word of what came.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "WaitsModule.h"
#import "Waits.h"
#import "Core.h"
#import "Row.h"
#import "Files.h"
#import "Printing.h"
#import "Notice.h"

// A made-up source: for each session, the things it has to wait on, by their words ("#12"), each readable or not;
// what came for each (a kind, at the clock's time, maybe your own answer), counted only from when it was watched, as a
// real source counts only what comes after the wait began; and each watch and unwatch, said as it's asked.
@interface SampleSource : NSObject <WakeSource>
@property (strong) NSMutableDictionary<NSString *, NSMutableArray<WaitOn *> *> *has;
@property (strong) NSMutableDictionary<NSString *, NSMutableArray<Wake *> *> *events;
@property (strong) NSMutableDictionary<NSString *, NSNumber *> *since;
@property (copy) double (^clock)(void);
- (const char *)name;
@end

@implementation SampleSource
- (const char *)name {
    return [self isKindOfClass:NSClassFromString(@"OtherSource")] ? "other" : "sample";
}
- (WaitOn *)waitsOn:(Row *)row {
    return self.has[row.sessionId].firstObject;
}
- (BOOL)watch:(Row *)row since:(double)since options:(NSDictionary *)options {
    // As a real source does, it watches what it has for the session, else what the wait began on, when that's its own.
    NSString *name = @(self.name);
    BOOL began = NO;
    for (NSDictionary *on in options[@"on"] ?: @[]) began = began || [on[@"source"] isEqual:name];
    if (!self.has[row.sessionId] && !began) return NO;
    self.since[row.sessionId] = @(since);
    printf("   (%s watches %s from %+.0fs%s)\n", self.name, row.sessionId.UTF8String, (since - self.clock()) / 1000,
           [options[@"comments"] boolValue] ? ", comments too" : "");
    return YES;
}
- (void)unwatch:(NSString *)sessionId {
    if (!self.since[sessionId]) return;
    [self.since removeObjectForKey:sessionId];
    printf("   (%s stops watching %s)\n", self.name, sessionId.UTF8String);
}
- (NSArray<Wake *> *)wakesFor:(NSString *)sessionId {
    NSNumber *since = self.since[sessionId];
    if (!since) return @[];
    return [self.events[sessionId] ?: @[] filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(Wake *wake, NSDictionary *b) { return wake.at > since.doubleValue; }]];
}
@end

// A second source for the same sessions, so a wait on two things, and wakes from both, can be tried.
@interface OtherSource : SampleSource
@end
@implementation OtherSource
@end

static void PrintLine(NSString *text) {
    printf("%s\n", text.UTF8String);
}

static NSString *JSONLine(id object) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object ?: NSNull.null
                                                   options:NSJSONWritingSortedKeys | NSJSONWritingFragmentsAllowed
                                                         | NSJSONWritingWithoutEscapingSlashes error:nil];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"?";
}

// The plain functions over made-up cases: the row's words, which held wakes go, and a let-go wake's seat.
static void PrintCases(void) {
    WaitOn *(^on)(NSString *, NSString *, NSString *) = ^WaitOn *(NSString *says, NSString *spoken, NSString *cant) {
        WaitOn *each = [WaitOn waitOn:@{@"source": @"sample", @"says": says} says:says spoken:spoken];
        each.cant = cant;
        return each;
    };
    WaitOn *pr = on(@"#12", @"pull request 12", nil), *ticket = on(@"PAY-142", @"ticket PAY-142", nil);
    WaitOn *task = on(@"your try", @"your try", nil), *unread = on(@"#12", @"pull request 12", @"gh isn't signed in");
    WaitOn *longName = on(@"A very long ticket name that goes on", nil, nil);
    for (NSArray *c in @[@[@"one", @[pr]], @[@"two", @[pr, ticket]], @[@"three", @[pr, ticket, task]],
                         @[@"one can't be read", @[ticket, unread]], @[@"none can be read", @[unread]],
                         @[@"a long name, cut at a word", @[longName]], @[@"nothing", @[]]])
        PrintLine([NSString stringWithFormat:@"says, %@: %@ | %@", c[0], WaitSays(c[1]) ?: @"(nothing)",
                   WaitSpoken(c[1]) ?: @"(nothing)"]);
    Wake *approved = [Wake wakeFrom:@"pull request" kind:@"approved" says:@"#12 approved" at:1 facts:nil];
    Wake *moved = [Wake wakeFrom:@"ticket" kind:@"moved" says:@"PAY-142 moved" at:2 facts:nil];
    PrintLine([NSString stringWithFormat:@"came: %@ | %@ | %@", WaitCameSays(@[approved]),
               WaitCameSays(@[approved, moved]), WaitCameSays(@[]) ?: @"(nothing)"]);
    NSDictionary *held = @{@"b": @20, @"a": @10, @"c": @20, @"d": @5};
    NSArray *(^go)(NSDictionary *, NSInteger) = ^NSArray *(NSDictionary *gear, NSInteger letGo) {
        return [WakesThatGo(held, gear, letGo).allObjects sortedArrayUsingSelector:@selector(compare:)];
    };
    PrintLine([NSString stringWithFormat:@"go, held d@5 a@10 b@20 c@20: gear off %@; no gear picked %@; room 0 %@; "
               @"room 1 %@; room 3 %@; room 3 with 1 let go %@; room 9 %@; room 2 with 5 let go %@",
               JSONLine(go(nil, 0)), JSONLine(go(@{@"room": NSNull.null}, 0)), JSONLine(go(@{@"room": @0}, 0)),
               JSONLine(go(@{@"room": @1}, 0)), JSONLine(go(@{@"room": @3}, 0)), JSONLine(go(@{@"room": @3}, 1)),
               JSONLine(go(@{@"room": @9}, 0)), JSONLine(go(@{@"room": @2}, 5))]);
    PrintLine([NSString stringWithFormat:@"let go still taken: 10s on %@; 10s on, at work %@; 31s on %@; never let go %@",
               @(LetGoStillTaken(1000, NO, 11000)), @(LetGoStillTaken(1000, YES, 11000)),
               @(LetGoStillTaken(1000, NO, 32000)), @(LetGoStillTaken(0, NO, 11000))]);
    WaitState *wait = [WaitState new];
    wait.since = 2e12;
    wait.pid = 42;
    wait.started = 7;
    wait.on = @[pr];
    PrintLine([@"kept: " stringByAppendingString:JSONLine(WaitKept(wait))]);
    WaitState *back = WaitFromKept(WaitKept(wait));
    PrintLine([NSString stringWithFormat:@"read back: since %.0f, pid %d, started %lld, on %@", back.since, back.pid,
               back.started, JSONLine(back.on.firstObject.on)]);
    PrintLine([NSString stringWithFormat:@"read back, not a wait's: %@ %@ %@", WaitFromKept(@{}) ?: @"nil",
               WaitFromKept(@{@"since": @"x", @"pid": @1, @"started": @1}) ?: @"nil",
               WaitFromKept(@{@"since": @1, @"pid": @1}) ?: @"nil"]);
}

// Each step's line out of the step: `row <id>` (a session running in this process), `newproc <id>` (the same
// conversation running in another process), `closed <id>` (its process gone) and `gone <id>` (its row gone);
// `has <id> <words> [cant] [other]`, something of its for the sample source (or the other one) to wait on, readable or
// not, and `nothing <id>`, none (the source then watches it only on what its wait began on); `ask <id> [now]
// [comments]`, its wait command asking; `came <id> <kind> [yours] [other]`, something coming for it now; `later
// <seconds>`, the Mac awake, and `sleep <seconds>`, the Mac asleep; `gear off`, `gear unpicked`, or `gear <room> [<id at
// work>…]`; `pass`, a second's pass over the rows, and `unread`, one before the rows have been read; `rows`, each row's `wait`; `kept`, the files kept; `relaunch`, a new
// copy reading what's kept; `notices`, what it has to tell you; `reopen <id>`, its words for that conversation as it's
// opened again from its row; `say <id>`, your press of Resume on a row run again that hasn't asked (Send stood in for); `words`, its background waits (BackgroundWaits), one a line; `cases`, the plain functions; `log`, whether panel.log says any word of what came; and
// `logged`, its lines since the last, without their times.
static int PrintWakes(Core *core, NSArray<NSString *> *steps) {
    if (HomeIsYourOwn()) {
        fprintf(stderr, "--print-wakes runs only in a throwaway home\n");
        return 2;
    }
    __block double now = 2e12, awake = 1e6;
    double (^clock)(void) = ^double { return now; };
    SampleSource *sample = [SampleSource new], *other = [OtherSource new];
    for (SampleSource *source in @[sample, other]) {
        source.has = [NSMutableDictionary dictionary];
        source.events = [NSMutableDictionary dictionary];
        source.since = [NSMutableDictionary dictionary];
        source.clock = clock;
    }
    __block NSDictionary *gear = nil;
    NSString *folder = AppDir(@"waits");
    WaitsModule *(^make)(void) = ^WaitsModule *{
        WaitsModule *module = [[WaitsModule alloc] initWithCore:core];
        module.givenSources = @[sample, other];
        module.givenGear = ^NSDictionary * { return gear; };
        module.clock = clock;
        module.awakeClock = ^double { return awake; };
        module.givenSay = ^(NSString *words, Row *row, void (^done)(NSString *, NSString *)) {
            printf("   (said into %s, by your press: %s)\n", row.sessionId.UTF8String, words.UTF8String);
            done(nil, nil);
        };
        [module keepIn:folder];
        return module;
    };
    WaitsModule *waits = make();
    NSMutableDictionary<NSString *, Row *> *rows = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    NSUInteger logRead = 0;
    for (NSString *step in steps) {
        NSArray<NSString *> *words = [step componentsSeparatedByString:@" "];
        NSString *verb = words.firstObject, *sessionId = words.count > 1 ? words[1] : @"";
        NSArray<NSString *> *rest = words.count > 2 ? [words subarrayWithRange:NSMakeRange(2, words.count - 2)] : @[];
        SampleSource *source = [rest containsObject:@"other"] ? other : sample;
        printf("== %s\n", step.UTF8String);
        if ([@[@"row", @"newproc", @"closed"] containsObject:verb]) {
            Row *row = [Row new];
            row.sessionId = sessionId;
            row.status = @"idle";
            row.pid = [verb isEqual:@"row"] ? getpid() : [verb isEqual:@"newproc"] ? getppid() : 0;
            if (!rows[sessionId]) [order addObject:sessionId];
            rows[sessionId] = row;
        } else if ([verb isEqual:@"gone"]) {
            [rows removeObjectForKey:sessionId];
            [order removeObject:sessionId];
        } else if ([verb isEqual:@"has"]) {
            NSString *says = rest.firstObject ?: @"#12";
            WaitOn *each = [WaitOn waitOn:@{@"source": source == other ? @"other" : @"sample", @"id": says} says:says
                                   spoken:[@"sample " stringByAppendingString:says]];
            if ([rest containsObject:@"cant"]) each.cant = @"it can't be reached";
            source.has[sessionId] = [NSMutableArray arrayWithObject:each];
        } else if ([verb isEqual:@"nothing"]) {
            [sample.has removeObjectForKey:sessionId];
            [other.has removeObjectForKey:sessionId];
        } else if ([verb isEqual:@"ask"]) {
            NSDictionary *asked = @{@"ask": @"wait", @"now": @([rest containsObject:@"now"]),
                                    @"comments": @([rest containsObject:@"comments"])};
            PrintLine([waits wait:asked from:rows[sessionId]]);
        } else if ([verb isEqual:@"came"]) {
            NSString *kind = rest.firstObject ?: @"approved";
            NSString *what = source.has[sessionId].firstObject.says ?: @"it";
            Wake *wake = [Wake wakeFrom:source == other ? @"other" : @"sample" kind:kind
                                   says:[NSString stringWithFormat:@"%@ %@", what, kind] at:now
                                  facts:@{@"what": what, @"by": @"someone"}];
            wake.yours = [rest containsObject:@"yours"];
            if (!source.events[sessionId]) source.events[sessionId] = [NSMutableArray array];
            [source.events[sessionId] addObject:wake];
        } else if ([verb isEqual:@"later"]) {
            now += (sessionId.doubleValue ?: 1) * 1000;
            awake += (sessionId.doubleValue ?: 1) * 1000;
        } else if ([verb isEqual:@"sleep"]) {
            now += (sessionId.doubleValue ?: 1) * 1000;
        } else if ([verb isEqual:@"unread"]) {
            [waits pass:nil];
        } else if ([verb isEqual:@"gear"]) {
            if ([sessionId isEqual:@"off"]) gear = nil;
            else if ([sessionId isEqual:@"unpicked"]) gear = @{@"room": NSNull.null, @"counted": @[]};
            else gear = @{@"room": @(sessionId.integerValue), @"counted": rest};
        } else if ([verb isEqual:@"pass"]) {
            NSMutableArray *listed = [NSMutableArray array];
            for (NSString *each in order) [listed addObject:rows[each]];
            [waits pass:listed];
        } else if ([verb isEqual:@"rows"]) {
            NSMutableArray *listed = [NSMutableArray array];
            for (NSString *each in order) [listed addObject:rows[each]];
            [waits rows:listed phase:RowPhaseListed];
            for (Row *row in listed)
                PrintLine([NSString stringWithFormat:@"%@: %@", row.sessionId, JSONLine(row.wait)]);
        } else if ([verb isEqual:@"kept"]) {
            NSArray *names = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil]
                              sortedArrayUsingSelector:@selector(compare:)];
            if (!names.count) PrintLine(@"(none)");
            for (NSString *name in names) {
                NSString *path = [folder stringByAppendingPathComponent:name];
                NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
                NSMutableDictionary *kept = [AsRecord(ReadJSON(path)) mutableCopy];
                // Its process as the same or another, since pids change from run to run.
                kept[@"pid"] = [kept[@"pid"] intValue] == getpid() ? @"this process" : @"another";
                kept[@"started"] = @"(when it started)";
                PrintLine([NSString stringWithFormat:@"%@ (%lo): %@", name,
                           (unsigned long)[attributes[NSFilePosixPermissions] unsignedLongValue], JSONLine(kept)]);
            }
        } else if ([verb isEqual:@"relaunch"]) {
            waits = make();
        } else if ([verb isEqual:@"notices"]) {
            NSArray<Notice *> *notices = [waits notices];
            if (!notices.count) PrintLine(@"(no notices)");
            for (Notice *notice in notices)
                PrintLine([NSString stringWithFormat:@"%@ (%@): %@ [%@], since %@", notice.key, notice.session,
                           notice.text, notice.button ?: @"", notice.since]);
        } else if ([verb isEqual:@"say"]) {
            [waits sayResume:sessionId];
        } else if ([verb isEqual:@"reopen"]) {
            PrintLine([NSString stringWithFormat:@"its words as it's opened again: %@",
                       [(id<ReopenWords>)waits wordsOnReopen:rows[sessionId]] ?: @"(none)"]);
        } else if ([verb isEqual:@"words"]) {
            for (NSArray<NSString *> *wait in [waits backgroundWaits])
                PrintLine([@"wait words: " stringByAppendingString:[wait componentsJoinedByString:@" "]]);
        } else if ([verb isEqual:@"cases"]) {
            PrintCases();
        } else if ([verb isEqual:@"log"]) {
            NSString *log = [NSString stringWithContentsOfFile:AppDir(@"panel.log") encoding:NSUTF8StringEncoding
                                                         error:nil] ?: @"";
            BOOL said = [log containsString:@"someone"] || [log containsString:@"#12"];
            printf("panel.log %s a word of what came or what it waits on\n", said ? "HAS" : "has none of");
        } else if ([verb isEqual:@"logged"]) {
            NSString *log = [NSString stringWithContentsOfFile:AppDir(@"panel.log") encoding:NSUTF8StringEncoding
                                                         error:nil] ?: @"";
            NSArray<NSString *> *lines = [log componentsSeparatedByString:@"\n"];
            for (NSUInteger i = logRead; i < lines.count; i++) {
                NSRange gap = [lines[i] rangeOfString:@"  "];
                if (gap.location != NSNotFound) printf("%s\n", [lines[i] substringFromIndex:NSMaxRange(gap)].UTF8String);
            }
            logRead = lines.count ? lines.count - 1 : 0;
        } else {
            fprintf(stderr, "--print-wakes: no step %s\n", verb.UTF8String);
            return 2;
        }
    }
    return 0;
}

NSDictionary<NSString *, PrintMode> *WaitsPrintModes(void) {
    return @{@"--print-wakes": ^int(Core *core, NSArray<NSString *> *arguments) { return PrintWakes(core, arguments); }};
}
