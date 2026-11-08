// Gear: how many sessions work at once on your plan, and how many it can carry to the week's end.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Gear.h"
#import "Row.h"
#import "Work.h"
#import "Files.h"
#import "Log.h"
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

const NSInteger GearLowest = 1, GearHighest = 30;

// A gap between reads longer than this adds nothing: the Mac slept, or Whozmove wasn't running.
static const NSTimeInterval kReadGap = 10;
// Samples are kept 3 days, and measured over the last 2 (of the window they're in).
static const NSTimeInterval kKeepFor = 3 * 86400, kMeasureOver = 2 * 86400;
// A stretch between two answers counts only if Whozmove watched 90% of it.
static const double kWatched = 0.9;
// A first reading needs the week to rise this many points and the sessions to have worked this many hours; the session
// window, this many points and this long into it. Percents are whole numbers, so fewer points would be mostly rounding.
static const double kWeekRise = 5, kWeekHours = 2, kSessionRise = 5;
static const NSTimeInterval kSessionSettle = 20 * 60, kSessionWindow = 5 * 3600;
// The recommendation is the highest gear whose week ends by about this, so the limit isn't reached before its last day;
// the session window only has to last until its own reset.
static const double kWeekEndsBy = 95, kSessionEndsBy = 100;

NSArray<Row *> *GearCounted(NSArray<Row *> *rows, BOOL (^ours)(Row *row)) {
    NSMutableArray<Row *> *counted = [NSMutableArray array];
    for (Row *row in rows)
        if (row.sessionId && SessionWorking(row) && ours(row)) [counted addObject:row];
    return [counted sortedArrayUsingComparator:^NSComparisonResult(Row *a, Row *b) {
        return [a.sessionId compare:b.sessionId];
    }];
}

void GearRead(GearTotals *totals, NSUInteger working, NSTimeInterval now) {
    NSTimeInterval since = now - totals->lastRead;
    if (totals->lastRead > 0 && since > 0 && since <= kReadGap) {
        totals->sessionHours += working * since / 3600;
        totals->watchedHours += since / 3600;
        if (working) totals->workHours += since / 3600;
    }
    totals->lastRead = now;
}

// JSON's own true or false, never a number: an NSNumber made from true equals 1.
static BOOL IsTrueOrFalse(id value) {
    return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
}

NSNumber *GearOf(id value) {
    NSNumber *gear = IsTrueOrFalse(value) ? nil : AsNumber(value);
    double g = gear.doubleValue;
    return gear && g == floor(g) && g >= GearLowest && g <= GearHighest ? @((NSInteger)g) : nil;
}

// A number read from the file, or 0 for anything else.
static NSNumber *Number(id value) {
    return AsNumber(value) ?: @0;
}

NSArray<NSDictionary *> *GearSamplesFrom(id samples) {
    NSMutableArray<NSDictionary *> *clean = [NSMutableArray array];
    for (id each in AsList(samples) ?: @[]) {
        NSDictionary *s = AsRecord(each);
        if (!s) continue;
        NSDictionary *week = AsRecord(s[@"week"]), *session = AsRecord(s[@"session"]);
        [clean addObject:@{@"at": Number(s[@"at"]),
                           @"week": @{@"used": Number(week[@"used"]), @"resetsAt": Number(week[@"resetsAt"])},
                           @"session": @{@"used": Number(session[@"used"]), @"resetsAt": Number(session[@"resetsAt"])},
                           @"sessionHours": Number(s[@"sessionHours"]), @"watchedHours": Number(s[@"watchedHours"]),
                           @"workHours": Number(s[@"workHours"])}];
    }
    return clean;
}

GearTotals GearTotalsFrom(NSArray<NSDictionary *> *samples) {
    NSDictionary *last = samples.lastObject;
    return (GearTotals){[last[@"sessionHours"] doubleValue], [last[@"watchedHours"] doubleValue],
                        [last[@"workHours"] doubleValue], 0};
}

// A window of an answer as it's kept: its percent used and its reset, numbers only.
static NSDictionary *WindowKept(NSDictionary *usage, NSString *window) {
    NSDictionary *each = AsRecord(usage[window]);
    return @{@"used": AsNumber(each[@"used"]) ?: @0, @"resetsAt": AsNumber(each[@"resetsAt"]) ?: @0};
}

NSDictionary *GearSample(NSDictionary *usage, GearTotals totals, NSTimeInterval now) {
    return @{@"at": @(now), @"week": WindowKept(usage, @"week"), @"session": WindowKept(usage, @"session"),
             @"sessionHours": @(totals.sessionHours), @"watchedHours": @(totals.watchedHours),
             @"workHours": @(totals.workHours)};
}

NSArray<NSDictionary *> *GearKeep(NSArray<NSDictionary *> *samples, NSDictionary *sample, NSTimeInterval now) {
    NSMutableArray<NSDictionary *> *kept = [NSMutableArray array];
    for (NSDictionary *each in [samples arrayByAddingObject:sample])
        if (now - [each[@"at"] doubleValue] <= kKeepFor) [kept addObject:each];
    return kept;
}

BOOL GearAtLimit(NSDictionary *usage, NSTimeInterval now) {
    NSDictionary *session = AsRecord(usage[@"session"]);
    return [session[@"used"] doubleValue] >= 100 && [session[@"resetsAt"] doubleValue] / 1000 > now
        && ![usage[@"extraUsage"] boolValue];
}

// Which window of `name` a sample read: its reset to the minute, as it jitters by a fraction of a second; nil for none,
// or for one whose reset had passed as it was read (the old window's).
static NSNumber *WindowOf(NSDictionary *sample, NSString *name) {
    double resetsAt = [sample[name][@"resetsAt"] doubleValue] / 1000;
    if (!(resetsAt > [sample[@"at"] doubleValue])) return nil;
    return @(llround(resetsAt / 60));
}

// What the stretches between answers of the last sample's window add up to, from `since`: the rise while a session
// worked and the session-hours worked, the rise with none working and those hours (the plan's other use: claude.ai,
// the apps), the hours any session worked and the hours watched, and the stretches Whozmove wasn't watching: their
// rise and their hours, beside the hours of those it was.
typedef struct {
    double workRise, sessionHours, otherRise, otherHours, workHours, watchedHours, unwatchedRise, unwatchedHours,
        keptHours;
} Stretches;

static Stretches Measure(NSArray<NSDictionary *> *samples, NSString *name, NSTimeInterval since) {
    Stretches s = {0};
    NSNumber *window = WindowOf(samples.lastObject, name);
    if (!window) return s;
    for (NSUInteger i = 1; i < samples.count; i++) {
        NSDictionary *a = samples[i - 1], *b = samples[i];
        if ([a[@"at"] doubleValue] < since || ![WindowOf(a, name) isEqual:window]
            || ![WindowOf(b, name) isEqual:window])
            continue;
        double hours = ([b[@"at"] doubleValue] - [a[@"at"] doubleValue]) / 3600;
        if (hours <= 0) continue;
        double rise = MAX(0, [b[name][@"used"] doubleValue] - [a[name][@"used"] doubleValue]);
        double watched = [b[@"watchedHours"] doubleValue] - [a[@"watchedHours"] doubleValue];
        double sessionHours = [b[@"sessionHours"] doubleValue] - [a[@"sessionHours"] doubleValue];
        if (watched < kWatched * hours || sessionHours < 0) {
            s.unwatchedRise += rise;
            s.unwatchedHours += hours;
            continue;
        }
        s.keptHours += hours;
        if (sessionHours > 0) {
            s.workRise += rise;
            s.sessionHours += sessionHours;
        } else {
            s.otherRise += rise;
            s.otherHours += hours;
        }
        s.workHours += [b[@"workHours"] doubleValue] - [a[@"workHours"] doubleValue];
        s.watchedHours += watched;
    }
    return s;
}

// The highest gear from the lowest up that `fits`, or the lowest when none does.
static NSInteger Highest(BOOL (^fits)(NSInteger gear)) {
    NSInteger highest = GearLowest;
    for (NSInteger gear = GearLowest; gear <= GearHighest; gear++)
        if (fits(gear)) highest = gear;
    return highest;
}

NSDictionary *GearMeasured(NSArray<NSDictionary *> *samples, NSDictionary *usage, NSNumber *gear) {
    NSTimeInterval at = [usage[@"checkedAt"] doubleValue] / 1000;
    NSMutableDictionary *measured = [@{@"limit": @(GearAtLimit(usage, at)), @"checkedAt": usage[@"checkedAt"] ?: @0}
                                     mutableCopy];
    // The week: the share of it a working session-hour took lately, the plan's other use an hour, and the part of the
    // time sessions worked; measurable once it has risen enough over enough hours worked.
    Stretches week = Measure(samples, @"week", at - kMeasureOver);
    double rise = week.workRise + week.otherRise;
    if (rise < kWeekRise || week.sessionHours < kWeekHours) {
        // Not watched only when the rise was there in stretches Whozmove missed, and those were most of the time: a
        // stretch dropped around a restart alone doesn't make it so.
        BOOL unwatched = rise + week.unwatchedRise >= kWeekRise && week.unwatchedHours > week.keptHours;
        NSString *reason = rise >= kWeekRise ? @"hours" : unwatched ? @"watched" : @"rise";
        measured[@"notYet"] = @{@"reason": reason, @"rise": @(llround(floor(rise))),
                                @"hours": @(llround(floor(week.sessionHours)))};
        return measured;
    }
    double draw = week.workRise / week.sessionHours;
    double other = week.otherHours > 0 ? week.otherRise / week.otherHours : 0;
    double share = week.watchedHours > 0 ? MIN(1, week.workHours / week.watchedHours) : 0;
    NSDictionary *w = WindowKept(usage, @"week"), *s = WindowKept(usage, @"session");
    double used = [w[@"used"] doubleValue], resetsAt = [w[@"resetsAt"] doubleValue];
    double hoursLeft = MAX(0, (resetsAt / 1000 - at) / 3600);
    double (^weekEnds)(NSInteger) = ^double(NSInteger g) {
        return used + hoursLeft * (g * draw * share + other * (1 - share));
    };
    // The session window can only lower the week's gear, once it has run 20 minutes and risen enough.
    double sessionUsed = [s[@"used"] doubleValue], sessionResets = [s[@"resetsAt"] doubleValue] / 1000;
    Stretches session = Measure(samples, @"session", sessionResets - kSessionWindow);
    BOOL sessionKnown = sessionResets > at && at - (sessionResets - kSessionWindow) >= kSessionSettle
        && session.workRise + session.otherRise >= kSessionRise && session.sessionHours > 0;
    double sessionDraw = sessionKnown ? session.workRise / session.sessionHours : 0;
    double sessionHoursLeft = MAX(0, (sessionResets - at) / 3600);
    double (^sessionEnds)(NSInteger) = ^double(NSInteger g) {
        return sessionUsed + sessionHoursLeft * g * sessionDraw;
    };
    NSInteger byWeek = Highest(^BOOL(NSInteger g) { return weekEnds(g) <= kWeekEndsBy; });
    NSInteger bySession = sessionKnown ? Highest(^BOOL(NSInteger g) { return sessionEnds(g) <= kSessionEndsBy; })
                                       : GearHighest;
    NSInteger recommended = MIN(byWeek, bySession);
    measured[@"recommended"] = @(recommended);
    measured[@"bound"] = bySession < byWeek ? @"session" : @"week";
    // Where the week ends at the gear set (or the recommended one), and when it, or the session, runs out first.
    NSInteger g = gear ? gear.integerValue : recommended;
    double ends = weekEnds(g);
    NSMutableDictionary *forecast = [@{@"gear": @(g), @"ends": @(llround(ends)), @"resetsAt": @(resetsAt)} mutableCopy];
    if (ends > 100 && hoursLeft > 0)
        forecast[@"runsOutAt"] = @(llround((at + (100 - used) / ((ends - used) / hoursLeft) * 3600) * 1000));
    if (sessionKnown && sessionEnds(g) > 100 && sessionDraw > 0)
        forecast[@"sessionRunsOutAt"] = @(llround((at + (100 - sessionUsed) / (g * sessionDraw) * 3600) * 1000));
    measured[@"forecast"] = forecast;
    return measured;
}

NSDictionary *GearCounts(NSArray<Row *> *counted, NSNumber *gear) {
    NSMutableArray<NSString *> *ids = [NSMutableArray array], *over = [NSMutableArray array];
    for (Row *row in counted) [ids addObject:row.sessionId];
    NSInteger beyond = gear ? MIN((NSInteger)counted.count, (NSInteger)counted.count - gear.integerValue) : 0;
    if (beyond > 0) {
        NSArray<Row *> *latest = [counted sortedArrayUsingComparator:^NSComparisonResult(Row *a, Row *b) {
            return [@(b.lastPromptAt.doubleValue) compare:@(a.lastPromptAt.doubleValue)];
        }];
        for (NSInteger i = 0; i < beyond; i++) [over addObject:latest[i].sessionId];
    }
    // How many more the gear lets work: what shows the gear beyond the card (a lead's queue) lets that many in.
    id room = gear ? @(MAX(0, gear.integerValue - (NSInteger)counted.count)) : NSNull.null;
    return @{@"atWork": @(counted.count), @"counted": ids, @"over": over, @"room": room};
}

NSDictionary *GearFileFor(NSDictionary *facts, NSNumber *changedAt, NSTimeInterval now) {
    return @{@"gear": facts[@"gear"] ?: NSNull.null, @"atWork": facts[@"atWork"] ?: @0,
             @"recommended": facts[@"recommended"] ?: NSNull.null, @"checkedAt": facts[@"checkedAt"] ?: NSNull.null,
             @"changedAt": changedAt ?: NSNull.null, @"updatedAt": @(llround(now * 1000))};
}

NSDictionary *GearOffFile(NSTimeInterval now) {
    return @{@"off": @YES, @"updatedAt": @(llround(now * 1000))};
}

BOOL GearFileIsOff(NSDictionary *file) {
    return IsTrueOrFalse(file[@"off"]) && [file[@"off"] boolValue];
}

id GearFileLimit(NSDictionary *file) {
    if (GearFileIsOff(file)) return NSNull.null;
    return GearOf(file[@"gear"]) ?: @0;
}

// Written beside it first, readable only by you from the start, then put in its place, so nothing reads it half
// written. A write that fails leaves what was there, and says why in the log.
void GearWrite(NSString *name, id json) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingSortedKeys error:nil];
    NSString *path = AppDir(name), *writing = [path stringByAppendingString:@".writing"];
    int fd = data ? open(writing.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600) : -1;
    if (fd < 0) {
        LogProblem([NSString stringWithFormat:@"%@ not written: %s", name, data ? strerror(errno) : "not JSON"]);
        return;
    }
    BOOL whole = fchmod(fd, 0600) == 0 && write(fd, data.bytes, data.length) == (ssize_t)data.length;
    int why = errno;
    close(fd);
    if (whole && rename(writing.fileSystemRepresentation, path.fileSystemRepresentation) == 0) return;
    if (whole) why = errno;
    unlink(writing.fileSystemRepresentation);
    LogProblem([NSString stringWithFormat:@"%@ not written: %s", name, strerror(why ?: EIO)]);
}

// gear.json goes before its off record is written, so a write that fails leaves no file, which lets nothing in,
// rather than the gear as it was.
void GearForget(NSUserDefaults *preferences, NSTimeInterval now) {
    for (NSString *key in @[@"gear", @"gearChangedAt"]) [preferences removeObjectForKey:key];
    for (NSString *name in @[@"gear.json", @"usage-gear.json"]) unlink(AppDir(name).fileSystemRepresentation);
    GearWrite(@"gear.json", GearOffFile(now));
}

#pragma mark Print run

static NSString *JSONText(id value) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:value
                                                   options:NSJSONWritingSortedKeys | NSJSONWritingFragmentsAllowed
                                                     error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

// Samples written in a case as {at (minutes), week, session (used, resetsAt in minutes), sessionHours, watchedHours,
// workHours}, as the app keeps them (seconds; resets in ms).
static NSArray<NSDictionary *> *SamplesOf(NSArray<NSDictionary *> *written) {
    NSMutableArray<NSDictionary *> *samples = [NSMutableArray array];
    for (NSDictionary *w in written) {
        NSMutableDictionary *s = [w mutableCopy];
        s[@"at"] = @([w[@"at"] doubleValue] * 60);
        for (NSString *name in @[@"week", @"session"])
            s[name] = @{@"used": w[name][@"used"] ?: @0, @"resetsAt": @([w[name][@"resetsAt"] doubleValue] * 60000)};
        [samples addObject:s];
    }
    return samples;
}

// Each case is one of: {name, rows} (the rows' fields: which are counted, with `gear`, which are over it); {name, reads:
// [[second, working]]} (the totals after them); {name, samples, now (minutes), gear} (what they measure; the answer is
// the last sample's, `extraUsage` aside); {name, to} (the gear a press on a seat asks for, as kept); {name, keep, now}
// (which samples are kept); {name, read} (usage-gear.json's samples as read, cleaned, and measured); {name, file: facts}
// (gear.json as written, read back); {name, limit: gear.json or null for none} (how many a lead may have working by
// it); {name, off} (what the gear keeps in the preferences and Whozmove's folder, what's left of it once the gear is
// turned off, and gear.json then). A gear
// in a case is read as the preferences' is (GearOf), or as given with `raw`.
int PrintGear(NSArray<NSString *> *arguments) {
    if (HomeIsYourOwn()) {
        fprintf(stderr, "--print-gear changes Whozmove's folder: give it a throwaway HOME\n");
        return 1;
    }
    NSArray<NSDictionary *> *cases = arguments.count ? AsList(ReadJSON(arguments[0])) : nil;
    if (!cases) {
        fprintf(stderr, "usage: Whozmove --print-gear <cases.json>\n");
        return 1;
    }
    [NSFileManager.defaultManager createDirectoryAtPath:AppDir(@"") withIntermediateDirectories:YES attributes:nil
                                                  error:nil];
    for (NSDictionary *c in cases) {
        id result = nil;
        if (c[@"rows"]) {
            NSMutableArray<Row *> *rows = [NSMutableArray array];
            for (NSDictionary *fields in c[@"rows"]) {
                Row *row = [[Row alloc] initWithFields:fields];
                row.ask = AsRecord(fields[@"ask"]);
                row.compacting = AsNumber(fields[@"compacting"]);
                row.alsoOpen = AsList(fields[@"alsoOpen"]);
                row.background = AsList(fields[@"background"]);
                row.lastPromptAt = AsNumber(fields[@"lastPromptAt"]);
                [rows addObject:row];
            }
            NSArray<Row *> *counted = GearCounted(rows, ^BOOL(Row *row) { return YES; });
            result = GearCounts(counted, c[@"raw"] ? AsNumber(c[@"gear"]) : GearOf(c[@"gear"]));
        } else if (c[@"reads"]) {
            GearTotals totals = {0};
            for (NSArray<NSNumber *> *read in c[@"reads"])
                GearRead(&totals, read[1].unsignedIntegerValue, read[0].doubleValue);
            result = [NSString stringWithFormat:@"%.4f session-hours, %.4f watched, %.4f with a session at work",
                                                totals.sessionHours, totals.watchedHours, totals.workHours];
        } else if (c[@"samples"]) {
            NSArray<NSDictionary *> *samples = SamplesOf(c[@"samples"]);
            NSDictionary *last = samples.lastObject;
            NSDictionary *usage = @{@"week": last[@"week"], @"session": last[@"session"],
                                    @"checkedAt": @([c[@"now"] doubleValue] * 60000),
                                    @"extraUsage": c[@"extraUsage"] ?: @NO};
            result = GearMeasured(samples, usage, AsNumber(c[@"gear"]));
        } else if (c[@"to"]) {
            result = GearOf(c[@"to"]);
        } else if (c[@"keep"]) {
            NSArray<NSDictionary *> *samples = SamplesOf(c[@"keep"]);
            NSArray<NSDictionary *> *kept = GearKeep([samples subarrayWithRange:NSMakeRange(0, samples.count - 1)],
                                                     samples.lastObject, [c[@"now"] doubleValue] * 60);
            NSMutableArray *at = [NSMutableArray array];
            for (NSDictionary *s in kept) [at addObject:@([s[@"at"] doubleValue] / 60)];
            result = at;
        } else if (c[@"read"]) {
            NSArray<NSDictionary *> *samples = GearSamplesFrom(c[@"read"]);
            GearTotals totals = GearTotalsFrom(samples);
            result = @{@"samples": samples, @"carriedOn": @(totals.sessionHours),
                       @"measured": GearMeasured(samples, @{@"checkedAt": @0}, nil)};
        } else if (c[@"file"]) {
            GearWrite(@"gear.json", GearFileFor(c[@"file"], c[@"changedAt"], 0));
            NSDictionary *mode = [NSFileManager.defaultManager attributesOfItemAtPath:AppDir(@"gear.json") error:nil];
            result = @{@"file": ReadJSON(AppDir(@"gear.json")) ?: NSNull.null,
                       @"mode": [NSString stringWithFormat:@"%lo", (long)[mode[NSFilePosixPermissions] integerValue]]};
        } else if (c[@"limit"]) {
            result = GearFileLimit(AsRecord(c[@"limit"]));
        } else if (c[@"off"]) {
            // Preferences don't follow $HOME, so the case keeps its gear in a bare build's own ("Whozmove", the only
            // ones tests/sandboxed.sh lets a test write), never the app's, whichever build runs it. What was there
            // first is said too, so a write refused there doesn't pass for one forgotten.
            NSUserDefaults *preferences = [[NSUserDefaults alloc] initWithSuiteName:@"Whozmove"];
            [preferences setObject:@8 forKey:@"gear"];
            [preferences setObject:@1 forKey:@"gearChangedAt"];
            GearWrite(@"gear.json", GearFileFor(@{@"gear": @8, @"atWork": @6}, nil, 0));
            GearWrite(@"usage-gear.json", @{@"samples": @[]});
            NSArray<NSString *> *(^kept)(void) = ^NSArray<NSString *> * {
                NSMutableArray<NSString *> *names = [NSMutableArray array];
                for (NSString *key in @[@"gear", @"gearChangedAt"])
                    if ([preferences objectForKey:key]) [names addObject:key];
                for (NSString *name in @[@"gear.json", @"usage-gear.json"])
                    if ([NSFileManager.defaultManager fileExistsAtPath:AppDir(name)]) [names addObject:name];
                return names;
            };
            NSArray<NSString *> *before = kept();
            GearForget(preferences, 0);
            result = @{@"before": before, @"left": kept(), @"gear.json": ReadJSON(AppDir(@"gear.json")) ?: NSNull.null};
        }
        printf("%s: %s\n", [c[@"name"] UTF8String], [JSONText(result ?: NSNull.null) UTF8String]);
    }
    return 0;
}
