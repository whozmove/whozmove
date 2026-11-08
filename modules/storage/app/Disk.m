// Disk: how full this Mac's disk is, and whether it's running low (Disk.h).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Disk.h"
#import "Files.h"

static const double kGB = 1e9, kDayMs = 24 * 3600 * 1000.0;
// Low is under 25 GB free, or under 50 GB and full within a week at this pace; under 5 GB, builds and sessions start to
// fail, as there's no room left for what they write.
static const double kLowFree = 25 * kGB, kLowSoon = 50 * kGB, kSoonDays = 7, kSevereFree = 5 * kGB;
// A sample each hour, kept for two weeks; how fast it's filling is worked out from the last week's, once they span a
// day; a pace slower than two months to full isn't one worth naming.
static const double kSampleEveryMs = 3600 * 1000.0, kKeepMs = 14 * kDayMs, kPaceOverMs = 7 * kDayMs;
static const double kPaceNeedsMs = kDayMs, kPaceAtMostDays = 60;
// The line's × keeps it away for a day, or until the disk is a tenth fuller.
static const double kClosedForMs = kDayMs, kClosedUntil = 0.9;

NSString *DiskSize(double bytes) {
    double gb = bytes / kGB;
    if (gb >= 9.95) return [NSString stringWithFormat:@"%.0f GB", gb];
    if (gb >= 0.995) {
        NSString *size = [NSString stringWithFormat:@"%.1f", gb];
        if ([size hasSuffix:@".0"]) size = [size substringToIndex:size.length - 2];
        return [size stringByAppendingString:@" GB"];
    }
    if (bytes >= 0.995e6) return [NSString stringWithFormat:@"%.0f MB", bytes / 1e6];
    return bytes > 0 ? [NSString stringWithFormat:@"%.0f KB", MAX(1, bytes / 1e3)] : @"0 KB";
}

// How many days until the disk is full at the pace its free space has fallen over the last week (a straight line
// through the samples, the free space now among them); -1 while it isn't falling; nil until the samples span a day.
static NSNumber *DaysToFull(NSArray *samples, double free, double now) {
    NSMutableArray<NSArray<NSNumber *> *> *points = [NSMutableArray array];
    for (id sample in samples) {
        NSArray *pair = AsList(sample);
        if (pair.count != 2 || !AsNumber(pair[0]) || !AsNumber(pair[1])) continue;
        double at = [pair[0] doubleValue];
        if (at >= now - kPaceOverMs && at < now) [points addObject:@[pair[0], pair[1]]];
    }
    if (!points.count || now - [points.firstObject[0] doubleValue] < kPaceNeedsMs) return nil;
    [points addObject:@[@(now), @(free)]];
    double n = points.count, sumT = 0, sumF = 0;
    for (NSArray<NSNumber *> *p in points) {
        sumT += (p[0].doubleValue - now) / kDayMs;
        sumF += p[1].doubleValue;
    }
    double meanT = sumT / n, meanF = sumF / n, across = 0, spread = 0;
    for (NSArray<NSNumber *> *p in points) {
        double t = (p[0].doubleValue - now) / kDayMs - meanT;
        across += t * (p[1].doubleValue - meanF);
        spread += t * t;
    }
    double perDay = spread > 0 ? across / spread : 0;  // bytes of free space a day: falling while it's below 0
    if (perDay >= 0) return @(-1);
    return @(free / -perDay);
}

static NSString *InDays(double days) {
    if (days < 1) return @"within a day";
    long whole = lround(days);
    return whole == 1 ? @"in about a day" : [NSString stringWithFormat:@"in about %ld days", whole];
}

NSDictionary *DiskSays(NSDictionary *known, double now) {
    double total = AsNumber(known[@"total"]).doubleValue, free = MAX(0, AsNumber(known[@"free"]).doubleValue);
    if (total <= 0) return nil;
    NSNumber *days = DaysToFull(AsList(known[@"samples"]), free, now);
    BOOL filling = days && days.doubleValue >= 0 && days.doubleValue <= kPaceAtMostDays;
    BOOL slowly = days && days.doubleValue > kPaceAtMostDays;
    BOOL severe = free < kSevereFree;
    BOOL low = severe || free < kLowFree || (free < kLowSoon && filling && days.doubleValue < kSoonDays);
    // Put away with its ×: away for a day, until the disk is a tenth fuller, or until it runs out when it hadn't.
    NSDictionary *closed = AsRecord(known[@"closed"]);
    BOOL away = closed && now - AsNumber(closed[@"at"]).doubleValue < kClosedForMs
             && free > AsNumber(closed[@"free"]).doubleValue * kClosedUntil
             && !(severe && ![AsNumber(closed[@"severe"]) boolValue]);
    NSString *size = DiskSize(free), *soon = filling ? [@"full " stringByAppendingString:InDays(days.doubleValue)] : nil;
    NSMutableArray *lines = [NSMutableArray array];
    if (severe) [lines addObject:@"Builds and sessions may fail: there's little room left for what they write"];
    else if (filling) [lines addObject:[NSString stringWithFormat:@"Full %@ at this pace", InDays(days.doubleValue)]];
    else if (slowly) [lines addObject:@"Filling slowly: months from full"];
    else if (days) [lines addObject:@"Not filling up this week"];
    return @{@"free": @(free), @"total": @(total), @"used": @(MIN(1, MAX(0, 1 - free / total))),
             @"tone": severe ? @"severe" : low ? @"low" : NSNull.null, @"show": @((BOOL)(low && !away)),
             @"head": soon ? [NSString stringWithFormat:@"%@ left · %@", size, soon]
                           : [NSString stringWithFormat:@"%@ left on your Mac", size],
             @"sub": severe ? @"Builds and sessions may fail" : @"See what you can clean up",
             @"fullInDays": filling ? days : NSNull.null, @"lines": lines};
}

const NSTimeInterval kMapFreshFor = 3600;

NSString *DiskAgo(double at, double now) {
    NSInteger minutes = MAX(0, (NSInteger)lround((now - at) / 60000));
    NSInteger hours = (NSInteger)lround(minutes / 60.0), days = (NSInteger)lround(minutes / 1440.0);
    return minutes < 1 ? @"just now" : minutes < 60 ? [NSString stringWithFormat:@"%ld min ago", (long)minutes]
         : minutes < 90 ? @"an hour ago" : hours < 36 ? [NSString stringWithFormat:@"%ld hours ago", (long)hours]
         : days < 2 ? @"a day ago" : [NSString stringWithFormat:@"%ld days ago", (long)days];
}

NSString *DiskLineSub(NSString *said, BOOL severe, long long cleanable, double cleanableAt, long long inTrash,
                      double now) {
    if (inTrash > 0)
        return [NSString stringWithFormat:@"Empty the Trash to get %@ back", DiskSize(inTrash)];
    if (cleanable > 0) {
        NSString *sub = [NSString stringWithFormat:severe ? @"Clean up %@ now" : @"%@ can be cleaned up",
                         DiskSize(cleanable)];
        return cleanableAt > 0 && now - cleanableAt > kMapFreshFor * 1000
            ? [NSString stringWithFormat:@"%@ · measured %@", sub, DiskAgo(cleanableAt, now)] : sub;
    }
    if (cleanable == 0 && !severe) return @"See what's using it";
    return said;
}

@interface Disk ()
@property (copy) NSString *path;
@property (strong) dispatch_queue_t queue;
// What's kept in the file ({samples, closed}), read once on the queue and only changed there; and the last look's
// total and free space.
@property (strong) NSMutableDictionary *kept;
@property (assign) double total, free;
@property (readwrite, copy) NSDictionary *said;
@end

@implementation Disk

- (instancetype)initWithFile:(NSString *)path {
    if (!(self = [super init])) return nil;
    self.path = path;
    self.queue = dispatch_queue_create("whozmove.storage.disk", DISPATCH_QUEUE_SERIAL);
    return self;
}

// On the queue: what's kept, read from its file the first time.
- (NSMutableDictionary *)keptHere {
    if (!self.kept) {
        NSDictionary *read = AsRecord(ReadJSON(self.path));
        self.kept = [NSMutableDictionary dictionary];
        self.kept[@"samples"] = AsList(read[@"samples"]) ?: @[];
        if (AsRecord(read[@"closed"])) self.kept[@"closed"] = read[@"closed"];
    }
    return self.kept;
}

// On the queue: kept for the next launch, in a folder of its own beside Whozmove's other files.
- (void)save {
    NSData *json = [NSJSONSerialization dataWithJSONObject:self.kept options:0 error:nil];
    if (!json) return;
    [NSFileManager.defaultManager createDirectoryAtPath:self.path.stringByDeletingLastPathComponent
                            withIntermediateDirectories:YES attributes:nil error:nil];
    [json writeToFile:self.path atomically:YES];
}

// On the queue: what's said now, handed to the main thread.
- (void)say {
    NSMutableDictionary *known = [self.keptHere mutableCopy];
    known[@"total"] = @(self.total);
    known[@"free"] = @(self.free);
    NSDictionary *said = DiskSays(known, NSDate.date.timeIntervalSince1970 * 1000);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!said || [said isEqualToDictionary:self.said]) return;
        self.said = said;
        if (self.onChange) self.onChange(said);
    });
}

- (void)look {
    dispatch_async(self.queue, ^{
        // A URL of its own each time: a URL keeps the values it has read.
        NSURL *home = [NSURL fileURLWithPath:Home() isDirectory:YES];
        NSDictionary *values = [home resourceValuesForKeys:@[NSURLVolumeTotalCapacityKey,
                                                             NSURLVolumeAvailableCapacityForImportantUsageKey]
                                                     error:nil];
        double total = AsNumber(values[NSURLVolumeTotalCapacityKey]).doubleValue;
        NSNumber *free = AsNumber(values[NSURLVolumeAvailableCapacityForImportantUsageKey]);
        if (total <= 0 || !free) return;
        self.total = total;
        self.free = free.doubleValue;
        double now = NSDate.date.timeIntervalSince1970 * 1000;
        NSMutableDictionary *kept = self.keptHere;
        NSMutableArray *samples = [NSMutableArray array];
        for (id sample in kept[@"samples"]) {
            NSArray *pair = AsList(sample);
            if (pair.count == 2 && [AsNumber(pair[0]) doubleValue] > now - kKeepMs) [samples addObject:pair];
        }
        BOOL changed = samples.count != [kept[@"samples"] count];
        if (!samples.count || now - [AsNumber([samples.lastObject firstObject]) doubleValue] >= kSampleEveryMs) {
            [samples addObject:@[@(round(now)), @(round(self.free))]];
            changed = YES;
        }
        kept[@"samples"] = samples;
        if (changed) [self save];
        [self say];
    });
}

- (void)closeNote {
    dispatch_async(self.queue, ^{
        if (self.total <= 0) return;
        self.keptHere[@"closed"] = @{@"at": @(round(NSDate.date.timeIntervalSince1970 * 1000)),
                                     @"free": @(round(self.free)), @"severe": @(self.free < kSevereFree)};
        [self save];
        [self say];
    });
}

@end
