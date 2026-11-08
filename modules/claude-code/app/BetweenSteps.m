// BetweenSteps: words held for a session's own words hook, handed in once.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "BetweenSteps.h"
#import "Files.h"
#import "Log.h"
#import "Processes.h"

NSString *const kBetweenStepsLine = @"The user sent this from Whozmove while you were working: ";

// The flag the hook looks for before it starts Python: there only while words wait for any session's hook, so a step
// with nothing for it costs a shell's check and no more.
static NSString *FlagPath(void) {
    return AppDir(@"words-waiting");
}

NSString *BetweenStepsHandOut(NSArray<NSString *> *words) {
    if (!words.count) return nil;
    return [kBetweenStepsLine stringByAppendingString:[words componentsJoinedByString:@"\n"]];
}

BOOL BetweenStepsHookOf(pid_t hookParent, pid_t hookGrandparent, BOOL shellBetween, pid_t session) {
    if (session <= 0) return NO;
    return hookParent == session || (shellBetween && hookGrandparent == session);
}

// Whether a process runs a shell, as Claude Code may start a hook's command under one.
static BOOL RunsShell(pid_t pid) {
    NSString *name = ProcessPath(pid).lastPathComponent;
    return [@[@"sh", @"bash", @"zsh", @"dash"] containsObject:name ?: @""];
}

@implementation BetweenSteps {
    // By id: {words, sessionId, pid, order}, and {at, event} once handed.
    NSMutableDictionary<NSString *, NSMutableDictionary *> *_words;
    NSUInteger _order;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _words = [NSMutableDictionary dictionary];
    return self;
}

- (void)start {
    @synchronized (self) {
        [NSFileManager.defaultManager removeItemAtPath:FlagPath() error:nil];
        [self flagNow];
    }
}

- (void)hold:(NSString *)words session:(NSString *)sessionId pid:(pid_t)sessionPid id:(NSString *)wordsId {
    if (!words.length || !sessionId || !wordsId || sessionPid <= 0) return;
    @synchronized (self) {
        _words[wordsId] = [@{@"words": words, @"sessionId": sessionId, @"pid": @(sessionPid), @"order": @(_order++)}
                           mutableCopy];
        [self flagNow];
    }
}

- (BOOL)takeBack:(NSString *)wordsId {
    @synchronized (self) {
        NSMutableDictionary *held = _words[wordsId];
        if (!held || held[@"at"]) return NO;
        [_words removeObjectForKey:wordsId];
        [self flagNow];
        return YES;
    }
}

- (NSString *)handOver:(NSString *)sessionId hookPid:(pid_t)hookPid event:(NSString *)event {
    pid_t parent = ProcessParent(hookPid), grandparent = parent > 1 ? ProcessParent(parent) : 0;
    BOOL shell = parent > 1 && RunsShell(parent);
    @synchronized (self) {
        NSMutableArray<NSMutableDictionary *> *mine = [NSMutableArray array];
        for (NSMutableDictionary *held in _words.allValues)
            if ([held[@"sessionId"] isEqual:sessionId] && !held[@"at"]) [mine addObject:held];
        if (!mine.count) return nil;
        if (!BetweenStepsHookOf(parent, grandparent, shell, [mine.firstObject[@"pid"] intValue])) {
            PanelLog(@"%@ -> words not handed: the hook asking isn't its own process's", sessionId);
            return nil;
        }
        [mine sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"order" ascending:YES]]];
        double now = NSDate.date.timeIntervalSince1970 * 1000;
        for (NSMutableDictionary *held in mine) {
            held[@"at"] = @(now);
            held[@"event"] = event ?: @"";
        }
        [self flagNow];
        PanelLog(@"%@ -> words handed in at %@", sessionId, event);
        return BetweenStepsHandOut([mine valueForKey:@"words"]);
    }
}

- (NSDictionary *)handed:(NSString *)wordsId {
    @synchronized (self) {
        NSDictionary *held = _words[wordsId];
        return held[@"at"] ? [held copy] : nil;
    }
}

- (void)forget:(NSString *)wordsId {
    @synchronized (self) {
        [_words removeObjectForKey:wordsId];
        [self flagNow];
    }
}

// The flag is there exactly while some words wait for a hook (called within @synchronized).
- (void)flagNow {
    BOOL waiting = NO;
    for (NSDictionary *held in _words.allValues) waiting = waiting || !held[@"at"];
    NSString *flag = FlagPath();
    BOOL there = [NSFileManager.defaultManager fileExistsAtPath:flag];
    if (waiting && !there) {
        [NSFileManager.defaultManager createDirectoryAtPath:flag.stringByDeletingLastPathComponent
                                withIntermediateDirectories:YES attributes:nil error:nil];
        [NSData.data writeToFile:flag atomically:NO];
    } else if (!waiting && there) {
        [NSFileManager.defaultManager removeItemAtPath:flag error:nil];
    }
}

@end
