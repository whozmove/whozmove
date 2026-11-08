// DontWait: a file for each session you've told not to wait on you, dont-wait/<session>.json, {since, after}: when it
// was turned on (ms) and how long a request waits for an answer then (seconds), which the permission hook reads as each
// request comes in and every few seconds while it waits. Only you may read them, as the hook's requests.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "DontWait.h"
#import <CoreGraphics/CoreGraphics.h>
#import "Files.h"
#import "Text.h"
#import "Row.h"

const NSInteger kDontWaitMinutes = 5;
NSString *const kDontWaitKey = @"dontWait";
// How recently you must have used the keyboard or the mouse, and been on a session in its tab, for its request to be
// held off.
static const NSTimeInterval kActiveWithin = 30;
static const double kOnItWithinMs = 3000;

// A session's file, or nil for an id that isn't one (plain, as the hook takes them).
static NSString *FileOf(NSString *sessionId) {
    if (!IsPlainId(sessionId, 128)) return nil;
    return [AppDir(@"dont-wait") stringByAppendingPathComponent:[sessionId stringByAppendingPathExtension:@"json"]];
}

NSString *DontWaitSays(NSInteger minutes) {
    return [NSString stringWithFormat:@"Questions and requests no one answers in %ld minutes go, and Claude carries on",
                                      (long)minutes];
}

BOOL SetStopsWaiting(NSString *sessionId, BOOL on) {
    NSString *path = FileOf(sessionId);
    if (!path) return NO;
    NSFileManager *files = NSFileManager.defaultManager;
    if (!on) return [files removeItemAtPath:path error:nil] || ![files fileExistsAtPath:path];
    [files createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES
                      attributes:@{NSFilePosixPermissions: @0700} error:nil];
    NSDictionary *record = @{@"since": @((long long)(NSDate.date.timeIntervalSince1970 * 1000)),
                             @"after": @(kDontWaitMinutes * 60)};
    NSData *json = [NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingSortedKeys error:nil];
    if (![json writeToFile:path options:NSDataWritingAtomic error:nil]) return NO;
    [files setAttributes:@{NSFilePosixPermissions: @0600} ofItemAtPath:path error:nil];
    return YES;
}

NSNumber *DontWaitFor(NSString *sessionId) {
    NSString *path = FileOf(sessionId);
    double after = path ? AsNumber(AsRecord(ReadJSON(path))[@"after"]).doubleValue : 0;
    return after > 0 ? @(after * 1000) : nil;
}

NSArray<NSString *> *DropFilesWithoutSwitch(BOOL (^kept)(NSString *sessionId)) {
    NSMutableArray<NSString *> *dropped = [NSMutableArray array];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:AppDir(@"dont-wait") error:nil]) {
        NSString *sessionId = name.stringByDeletingPathExtension;
        if (![name.pathExtension isEqualToString:@"json"] || !FileOf(sessionId) || kept(sessionId)) continue;
        if (SetStopsWaiting(sessionId, NO)) [dropped addObject:sessionId];
    }
    return dropped;
}

NSTimeInterval SecondsIdle(void) {
    return CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateHIDSystemState, kCGAnyInputEventType);
}

BOOL ActiveAtTheMac(void) {
    return SecondsIdle() < kActiveWithin;
}

// Every request, whether it goes by itself or not: a session you allow doesn't answer one you may be answering there.
NSArray<NSString *> *AsksToHold(NSArray<Row *> *rows, double now, NSTimeInterval idle) {
    NSMutableArray<NSString *> *held = [NSMutableArray array];
    if (idle >= kActiveWithin) return held;
    for (Row *row in rows) {
        NSString *askId = AsText(row.ask[@"id"]);
        BOOL legacy = [row.ask[@"legacy"] boolValue] && !AsNumber(row.ask[@"expiresAt"]);
        if (askId && !legacy && row.seenAt && now - row.seenAt.doubleValue < kOnItWithinMs)
            [held addObject:askId];
    }
    return held;
}
