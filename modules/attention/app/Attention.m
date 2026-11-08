// Attention: what the attention module keeps, as plain functions (Attention.h).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Attention.h"
#import <fcntl.h>
#import <sys/stat.h>
#import <unistd.h>

const NSInteger kAttentionDays = 14;
const double kAttentionSeenEvery = 60, kAttentionNewLookAfter = 5;

NSDictionary *AttentionFront(double at, BOOL worksWithIt) {
    return @{@"at": @(at), @"kind": @"front", @"app": worksWithIt ? @"agent" : @"other"};
}

NSDictionary *AttentionPresence(double at, BOOL atTheMac) {
    return @{@"at": @(at), @"kind": atTheMac ? @"back" : @"away"};
}

NSDictionary *AttentionSeen(double at, NSString *sessionId) {
    return @{@"at": @(at), @"kind": @"seen", @"session": sessionId ?: @""};
}

BOOL AttentionSeenDue(NSNumber *lastKept, NSNumber *lastSeen, double seenAt) {
    if (!lastKept || !lastSeen) return YES;
    if (seenAt - lastSeen.doubleValue > kAttentionNewLookAfter * 1000) return YES;
    return seenAt - lastKept.doubleValue >= kAttentionSeenEvery * 1000;
}

// One formatter for the day names, made once: the module asks for today's name on every tick.
static NSDateFormatter *DayNames(void) {
    static NSDateFormatter *days;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        days = [NSDateFormatter new];
        days.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        days.dateFormat = @"yyyy-MM-dd";
    });
    return days;
}

NSString *AttentionFileFor(double at) {
    return [[DayNames() stringFromDate:[NSDate dateWithTimeIntervalSince1970:at]] stringByAppendingString:@".jsonl"];
}

// Names are compared as they're written, year first, never parsed back: a day whose midnight a clock change skips
// would parse to nothing and never go.
NSArray<NSString *> *AttentionExpired(NSArray<NSString *> *names, double now) {
    NSDate *cutoff = [NSCalendar.currentCalendar dateByAddingUnit:NSCalendarUnitDay value:-kAttentionDays
                                                           toDate:[NSDate dateWithTimeIntervalSince1970:now] options:0];
    NSString *oldest = AttentionFileFor(cutoff.timeIntervalSince1970);
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *name in names)
        if ([name hasSuffix:@".jsonl"] && name.length == oldest.length && [name compare:oldest] == NSOrderedAscending)
            [out addObject:name];
    return out;
}

BOOL AttentionAppend(NSString *folder, NSDictionary *line, double now) {
    NSFileManager *files = NSFileManager.defaultManager;
    if (![files createDirectoryAtPath:folder withIntermediateDirectories:YES
                           attributes:@{NSFilePosixPermissions: @0700} error:nil])
        return NO;
    [files setAttributes:@{NSFilePosixPermissions: @0700} ofItemAtPath:folder error:nil];
    NSMutableData *data = [[NSJSONSerialization dataWithJSONObject:line options:NSJSONWritingSortedKeys error:nil]
                           mutableCopy];
    if (!data) return NO;
    [data appendBytes:"\n" length:1];
    NSString *path = [folder stringByAppendingPathComponent:AttentionFileFor(now)];
    int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0600);
    if (fd < 0) return NO;
    // A file another program made, or one made before, still ends up only yours to read.
    fchmod(fd, 0600);
    BOOL whole = write(fd, data.bytes, data.length) == (ssize_t)data.length;
    close(fd);
    return whole;
}
