// Waits: the plain functions of waiting and waking (Waits.h).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Waits.h"
#import "Files.h"

const double kWaitStoppedAfterMs = 60000, kLetGoCountsMs = 30000, kCantReadForMs = 30 * 60000, kHandOverMs = 120000;

@implementation WaitState
- (instancetype)init {
    if (!(self = [super init])) return nil;
    _on = @[];
    _came = @[];
    _watchedBy = [NSHashTable weakObjectsHashTable];
    return self;
}
@end

// A name as the row says it: up to 24 characters, cut at a word's end with "…", so no key or name shows in half.
static NSString *WaitName(NSString *text) {
    const NSUInteger most = 24;
    if (text.length <= most) return text;
    NSString *cut = [text substringToIndex:most - 1];
    NSRange space = [cut rangeOfCharacterFromSet:NSCharacterSet.whitespaceCharacterSet options:NSBackwardsSearch];
    if (space.location != NSNotFound && space.location > 0) cut = [cut substringToIndex:space.location];
    return [cut stringByAppendingString:@"…"];
}

// Each readable one's words joined with " · ", then each that can't be read now; or, with none readable, why the
// first can't, in its source's words, so the row says what would put it right.
NSString *WaitSays(NSArray<WaitOn *> *on) {
    NSMutableArray *read = [NSMutableArray array], *cant = [NSMutableArray array];
    WaitOn *firstCant = nil;
    for (WaitOn *each in on) {
        if (!each.says.length) continue;
        if (each.cant) {
            firstCant = firstCant ?: each;
            [cant addObject:[NSString stringWithFormat:@"%@ can't be read now", WaitName(each.says)]];
        } else [read addObject:WaitName(each.says)];
    }
    if (!read.count && firstCant)
        return [NSString stringWithFormat:@"Waits on %@: %@", WaitName(firstCant.says), firstCant.cant];
    if (!read.count) return nil;
    return [[@[[@"Waits on " stringByAppendingString:[read componentsJoinedByString:@" · "]]]
             arrayByAddingObjectsFromArray:cant] componentsJoinedByString:@" · "];
}

NSString *WaitClosedSays(NSArray<WaitOn *> *on) {
    NSMutableArray *names = [NSMutableArray array];
    for (WaitOn *each in on)
        if (each.says.length) [names addObject:WaitName(each.says)];
    if (!names.count) return nil;
    return [@"Stopped, waiting on " stringByAppendingString:[names componentsJoinedByString:@" · "]];
}

NSString *WaitMissedSays(NSArray<WaitOn *> *on) {
    NSMutableArray *names = [NSMutableArray array];
    for (WaitOn *each in on)
        if (each.says.length) [names addObject:WaitName(each.says)];
    if (!names.count) return nil;
    return [NSString stringWithFormat:@"Not waiting on %@ any more", [names componentsJoinedByString:@" · "]];
}

NSString *WaitSpoken(NSArray<WaitOn *> *on) {
    NSMutableArray *read = [NSMutableArray array];
    WaitOn *firstCant = nil;
    for (WaitOn *each in on) {
        if (!each.spoken.length && !each.says.length) continue;
        if (each.cant) firstCant = firstCant ?: each;
        else [read addObject:each.spoken.length ? each.spoken : each.says];
    }
    if (!read.count && firstCant)
        return [NSString stringWithFormat:@"Waits on %@: %@", firstCant.spoken.length ? firstCant.spoken : firstCant.says,
                firstCant.cant];
    if (!read.count) return nil;
    NSString *last = read.lastObject;
    NSString *list = read.count == 1 ? last
        : [NSString stringWithFormat:@"%@ and %@",
           [[read subarrayWithRange:NSMakeRange(0, read.count - 1)] componentsJoinedByString:@", "], last];
    return [@"Waits on " stringByAppendingString:list];
}

NSString *WaitCameSays(NSArray<Wake *> *came) {
    if (!came.count) return nil;
    NSString *first = came.firstObject.says.length ? WaitName(came.firstObject.says) : @"Something came";
    return came.count > 1 ? [NSString stringWithFormat:@"%@ +%lu", first, (unsigned long)came.count - 1] : first;
}

NSString *WaitCameSpoken(NSArray<Wake *> *came) {
    if (!came.count) return nil;
    NSString *first = came.firstObject.says.length ? came.firstObject.says : @"Something came";
    return came.count > 1 ? [NSString stringWithFormat:@"%@, and %lu more", first, (unsigned long)came.count - 1] : first;
}

NSDictionary *WaitShown(WaitState *wait) {
    NSString *says = WaitSays(wait.on);
    if (!says && !wait.came.count) return nil;
    NSMutableArray *on = [NSMutableArray array];
    for (WaitOn *each in wait.on)
        if (each.on) [on addObject:each.on];
    NSMutableDictionary *shown = [NSMutableDictionary dictionary];
    BOOL closed = wait.closed && !wait.reopened;
    shown[@"says"] = closed ? WaitClosedSays(wait.on) ?: says : wait.missed ? WaitMissedSays(wait.on) ?: says : says;
    // For VoiceOver, each by its name in full, as an open one's is: "Stopped, waiting on pull request 12".
    NSString *spoken = WaitSpoken(wait.on);
    NSString *names = [spoken hasPrefix:@"Waits on "] ? [spoken substringFromIndex:@"Waits on ".length] : nil;
    shown[@"spoken"] = closed ? (names ? [@"Stopped, waiting on " stringByAppendingString:names] : shown[@"says"])
        : wait.missed ? (names ? [NSString stringWithFormat:@"Not waiting on %@ any more", names] : shown[@"says"])
        : spoken;
    shown[@"on"] = on;
    shown[@"came"] = WaitCameSays(wait.came);
    shown[@"cameSpoken"] = WaitCameSpoken(wait.came);
    if (wait.came.count) {
        shown[@"cameFirst"] = WaitCameSays(@[wait.came.firstObject]);
        shown[@"cameMore"] = @(wait.came.count - 1);
    }
    if (wait.held) shown[@"held"] = @YES;
    if (closed) shown[@"closed"] = @YES;
    if (wait.missed && !closed) shown[@"missed"] = @YES;
    return shown;
}

NSSet<NSString *> *WakesThatGo(NSDictionary<NSString *, NSNumber *> *held, NSDictionary *gear, NSInteger letGo) {
    id room = gear[@"room"];
    if (!gear || ![room isKindOfClass:NSNumber.class]) return [NSSet setWithArray:held.allKeys];
    // Oldest wake first; two that came at once by their ids, so the order is the same on every pass.
    NSArray *order = [held.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSComparisonResult when = [held[a] compare:held[b]];
        return when != NSOrderedSame ? when : [a compare:b];
    }];
    NSInteger free = MAX(0, [room integerValue] - letGo);
    return [NSSet setWithArray:[order subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)free, order.count))]];
}

BOOL LetGoStillTaken(double letGoAt, BOOL atWork, double now) {
    return letGoAt > 0 && !atWork && now - letGoAt < kLetGoCountsMs;
}

NSString *WokeAnswer(NSArray<Wake *> *came) {
    NSMutableArray *facts = [NSMutableArray array];
    for (Wake *wake in came) {
        NSMutableDictionary *each = [NSMutableDictionary dictionaryWithDictionary:wake.facts ?: @{}];
        each[@"source"] = wake.source ?: @"";
        each[@"kind"] = wake.kind ?: @"";
        each[@"at"] = [[NSISO8601DateFormatter new] stringFromDate:[NSDate dateWithTimeIntervalSince1970:wake.at / 1000]];
        [facts addObject:each];
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"came": facts}
                                                   options:NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes
                                                     error:nil];
    return [@"woke: " stringByAppendingString:json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]
                                                   : @"{\"came\": []}"];
}

BOOL WaitCameYours(WaitState *wait) {
    for (Wake *wake in wait.came)
        if (wake.yours) return YES;
    return NO;
}

NSString *WaitAnswer(WaitState *wait, BOOL justNow, BOOL mayGo, double now, BOOL *wakes, BOOL *ends) {
    *wakes = *ends = NO;
    NSString *says = WaitSays(wait.on) ?: @"what it waited on";
    if (!wait.came.count && wait.cantSince > 0 && now - wait.cantSince >= kCantReadForMs) {
        *ends = YES;
        return [NSString stringWithFormat:@"nothing to wait for: none of what it waited on could be read for %.0f "
                                          @"minutes (%@); tell the user", kCantReadForMs / 60000, says];
    }
    if (!wait.came.count) return [(justNow ? @"nothing yet: " : @"waiting: ") stringByAppendingString:says];
    if (!justNow && !WaitCameYours(wait) && !mayGo)
        return [@"waiting: for a free seat in the gear: " stringByAppendingString:WaitCameSays(wait.came)];
    *wakes = YES;
    return WokeAnswer(wait.came);
}

NSString *WhyWaitEnds(WaitState *wait, BOOL listed, BOOL closed, BOOL sameProcess, double now) {
    if (!listed) return @"its row has gone";
    if (closed || !sameProcess) return nil;
    if (!wait.closed && now - wait.askedAt > kWaitStoppedAfterMs) return @"its wait stopped asking";
    return nil;
}

double WaitHandOver(WaitState *wait, BOOL closed, BOOL elsewhere, double now) {
    if (closed || !elsewhere) return 0;
    return wait.handedOverAt > 0 ? wait.handedOverAt : now;
}

BOOL WaitMissed(WaitState *wait, double now) {
    return wait.handedOverAt > 0 && now - wait.handedOverAt > kHandOverMs;
}

double WaitSlept(double wallGap, double awakeGap) {
    double slept = wallGap - awakeGap;
    return slept >= 2000 ? slept : 0;
}

NSDictionary *WaitKept(WaitState *wait) {
    NSMutableArray *on = [NSMutableArray array];
    for (WaitOn *each in wait.on)
        if (each.on) [on addObject:each.on];
    return @{@"since": @(wait.since), @"pid": @(wait.pid), @"started": @(wait.started), @"comments": @(wait.comments),
             @"closed": @(wait.closed), @"on": on};
}

WaitState *WaitFromKept(NSDictionary *kept) {
    NSNumber *since = AsNumber(kept[@"since"]), *pid = AsNumber(kept[@"pid"]), *started = AsNumber(kept[@"started"]);
    if (!since || !pid || !started) return nil;
    WaitState *wait = [WaitState new];
    wait.since = since.doubleValue;
    wait.pid = pid.intValue;
    wait.started = started.longLongValue;
    wait.comments = [AsNumber(kept[@"comments"]) boolValue];
    wait.closed = [AsNumber(kept[@"closed"]) boolValue];
    NSMutableArray *on = [NSMutableArray array];
    for (id each in AsList(kept[@"on"]) ?: @[])
        if (AsRecord(each)) [on addObject:[WaitOn waitOn:each says:nil spoken:nil]];
    wait.on = on;
    return wait;
}
