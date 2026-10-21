// ClaudeSessions: Claude Code's running sessions, and its hooks' records.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "ClaudeSessions.h"
#import "Row.h"
#import "Files.h"
#import "Processes.h"
#import "ClaudeCodeFacts.h"
#import "ClaudeUsage.h"

// The check that asks Claude Code for your plan's usage (ClaudeUsage.m) is a session for the second it runs, registered
// like any other, in a folder kept for it. It isn't one of yours, so it's never a row. Asked of every session each
// second, so the folder's real path is found once it's there, and only a session in a folder of the same name is looked
// at further. On the sessions' queue only.
static BOOL IsUsageCheck(NSDictionary *session) {
    NSString *cwd = [session[@"cwd"] isKindOfClass:NSString.class] ? session[@"cwd"] : nil;
    if (![cwd.lastPathComponent isEqualToString:UsageFolder().lastPathComponent]) return NO;
    static NSString *real;
    if (!real && [NSFileManager.defaultManager fileExistsAtPath:UsageFolder()]) real = RealPath(UsageFolder());
    NSString *folder = real ?: UsageFolder();
    return [cwd isEqualToString:folder] || [RealPath(cwd) isEqualToString:folder];
}

// Whether one process registered for a session speaks for it rather than another: one that runs over one paused in its
// terminal, then the one started last.
static BOOL Outranks(NSDictionary *one, NSDictionary *other) {
    BOOL oneStopped = ProcessStopped([one[@"pid"] intValue]), otherStopped = ProcessStopped([other[@"pid"] intValue]);
    if (oneStopped != otherStopped) return otherStopped;
    double oneAt = [one[@"startedAt"] isKindOfClass:NSNumber.class] ? [one[@"startedAt"] doubleValue] : 0;
    double otherAt = [other[@"startedAt"] isKindOfClass:NSNumber.class] ? [other[@"startedAt"] doubleValue] : 0;
    return oneAt > otherAt;
}

// Running sessions from Claude Code's registry: one file per process. A conversation resumed while an earlier process
// of it is still there (paused with Ctrl+Z, say) has a file for each; it's one session, so it's one row.
NSArray<Row *> *RunningSessions(void) {
    NSString *registry = ClaudeDir(kClaudeCodeRegistry);
    NSMutableArray<NSDictionary *> *found = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSNumber *> *bySession = [NSMutableDictionary dictionary];
    for (NSString *file in [NSFileManager.defaultManager contentsOfDirectoryAtPath:registry error:nil]) {
        if (![file.pathExtension isEqualToString:@"json"]) continue;
        NSDictionary *s = ReadJSON([registry stringByAppendingPathComponent:file]);
        if (![s isKindOfClass:NSDictionary.class] || !ProcessAlive([s[@"pid"] intValue])) continue;
        if (IsUsageCheck(s)) continue;
        NSString *sessionId = [s[@"sessionId"] isKindOfClass:NSString.class] ? s[@"sessionId"] : nil;
        NSNumber *seen = sessionId ? bySession[sessionId] : nil;
        if (seen) {
            if (Outranks(s, found[seen.unsignedIntegerValue])) found[seen.unsignedIntegerValue] = s;
            continue;
        }
        if (sessionId) bySession[sessionId] = @(found.count);
        [found addObject:s];
    }
    NSMutableArray<Row *> *out = [NSMutableArray array];
    for (NSDictionary *s in found) [out addObject:[[Row alloc] initWithFields:s]];
    return out;
}

// Adds what the hook recorded (last prompt / reply / notice).
void AddHookRecord(Row *row) {
    NSDictionary *record = row.sessionId
        ? ReadJSON([AppDir(@"sessions")
                    stringByAppendingPathComponent:[row.sessionId stringByAppendingPathExtension:@"json"]])
        : nil;
    if ([record isKindOfClass:NSDictionary.class]) [row takeHookRecord:record];
}
