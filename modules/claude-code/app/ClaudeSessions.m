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

// Running sessions from Claude Code's registry: one file per process.
NSArray<Row *> *RunningSessions(void) {
    NSString *registry = ClaudeDir(kClaudeCodeRegistry);
    NSMutableArray<Row *> *out = [NSMutableArray array];
    for (NSString *file in [NSFileManager.defaultManager contentsOfDirectoryAtPath:registry error:nil]) {
        if (![file.pathExtension isEqualToString:@"json"]) continue;
        NSDictionary *s = ReadJSON([registry stringByAppendingPathComponent:file]);
        if (![s isKindOfClass:NSDictionary.class] || !ProcessAlive([s[@"pid"] intValue])) continue;
        if (IsUsageCheck(s)) continue;
        [out addObject:[[Row alloc] initWithFields:s]];
    }
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
