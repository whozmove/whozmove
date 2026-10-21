// ClaudeSessions: Claude Code's running sessions, and its hooks' records.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "ClaudeSessions.h"
#import "Row.h"
#import "Files.h"
#import "Processes.h"
#import "ClaudeCodeFacts.h"
#import "ClaudeUsage.h"
#import <signal.h>

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

static pid_t PidOf(NSDictionary *session) {
    return AsNumber(session[@"pid"]).intValue;
}

// Whether a process runs as you, as every Claude Code session does. A crash can leave a session's file behind, and its
// number can go to another process later, most often one of the system's.
static BOOL RunsAsYou(pid_t pid) {
    return pid > 0 && kill(pid, 0) == 0;
}

// The processes Claude Code's registry lists that still run (paused ones too), each as its file has it.
static NSArray<NSDictionary *> *RegisteredProcesses(void) {
    NSString *registry = ClaudeDir(kClaudeCodeRegistry);
    NSMutableArray<NSDictionary *> *found = [NSMutableArray array];
    for (NSString *file in [NSFileManager.defaultManager contentsOfDirectoryAtPath:registry error:nil]) {
        if (![file.pathExtension isEqualToString:@"json"]) continue;
        NSDictionary *s = ReadJSON([registry stringByAppendingPathComponent:file]);
        if ([s isKindOfClass:NSDictionary.class] && RunsAsYou(PidOf(s))) [found addObject:s];
    }
    return found;
}

// How much a process's state calls for you: asking you something, then at work, then the rest.
static int Urgency(NSDictionary *session) {
    id status = session[@"status"];
    return [status isEqual:@"waiting"] ? 2 : [status isEqual:@"busy"] ? 1 : 0;
}

static double TimeIn(NSDictionary *session, NSString *key) {
    return AsNumber(session[key]).doubleValue;
}

// One process registered for a conversation open in more than one (resumed in a second tab while it still runs, open
// in Claude Desktop and a terminal, or paused with Ctrl+Z in one), with what's asked of it more than once.
@interface Copy : NSObject
@property (strong) NSDictionary *record;
@property (copy) NSString *key;
@property BOOL stopped;
@property BOOL untracked;  // in an app whose sessions you don't track (Claude Desktop, its switch off)
@end

@implementation Copy
@end

// Whether one copy speaks for the conversation rather than another: one in an app whose sessions you track over one in
// an app you don't, so turning that off never takes a terminal's copy out of the list with it; one that runs over one
// paused in its terminal, then the one that needs you most, then the one the row followed already, so it doesn't move
// to a copy only because it started; and when the row is new, the one whose state changed last, then the one started
// last.
static BOOL Outranks(Copy *one, Copy *other, NSString *followed) {
    if (one.untracked != other.untracked) return other.untracked;
    if (one.stopped != other.stopped) return other.stopped;
    if (Urgency(one.record) != Urgency(other.record)) return Urgency(one.record) > Urgency(other.record);
    BOOL oneFollowed = [one.key isEqual:followed], otherFollowed = [other.key isEqual:followed];
    if (oneFollowed != otherFollowed) return oneFollowed;
    double oneAt = TimeIn(one.record, @"statusUpdatedAt"), otherAt = TimeIn(other.record, @"statusUpdatedAt");
    if (oneAt != otherAt) return oneAt > otherAt;
    return TimeIn(one.record, @"startedAt") > TimeIn(other.record, @"startedAt");
}

// Running sessions from Claude Code's registry: one file per process. A conversation open in more than one process has
// a file for each; it's one session, so it's one row, the copy that outranks the others, which it names, untracked ones
// among them, as typing into one copy still has to know of the others.
NSArray<Row *> *RunningSessions(BOOL (^untracked)(Row *copy)) {
    // The copy each row followed last time, by its process (its number and when it started). Only the rows' queue
    // reads the sessions, so it's never asked from two places at once.
    static NSDictionary<NSString *, NSString *> *followed;
    NSMutableArray<NSMutableArray<Copy *> *> *found = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray<Copy *> *> *bySession = [NSMutableDictionary dictionary];
    for (NSDictionary *s in RegisteredProcesses()) {
        if (IsUsageCheck(s)) continue;
        Copy *copy = [Copy new];
        copy.record = s;
        copy.key = ProcessKey(PidOf(s), AsText(s[@"procStart"]));
        copy.stopped = ProcessStopped(PidOf(s));
        copy.untracked = untracked && untracked([[Row alloc] initWithFields:s]);
        NSString *sessionId = AsText(s[@"sessionId"]);
        NSMutableArray<Copy *> *copies = sessionId ? bySession[sessionId] : nil;
        if (copies) {
            [copies addObject:copy];
            continue;
        }
        copies = [NSMutableArray arrayWithObject:copy];
        if (sessionId) bySession[sessionId] = copies;
        [found addObject:copies];
    }
    NSDictionary<NSString *, NSString *> *before = followed;
    NSMutableDictionary<NSString *, NSString *> *now = [NSMutableDictionary dictionary];
    NSMutableArray<Row *> *out = [NSMutableArray array];
    for (NSArray<Copy *> *copies in found) {
        NSString *sessionId = AsText(copies.firstObject.record[@"sessionId"]);
        Copy *speaks = copies.firstObject;
        for (Copy *c in copies)
            if (c != speaks && Outranks(c, speaks, sessionId ? before[sessionId] : nil)) speaks = c;
        if (sessionId) now[sessionId] = speaks.key;
        Row *row = [[Row alloc] initWithFields:speaks.record];
        NSMutableArray<NSDictionary *> *others = [NSMutableArray array];
        for (Copy *c in copies) {
            if (c == speaks) continue;
            NSMutableDictionary *other = [@{@"entrypoint": AsText(c.record[@"entrypoint"]) ?: @"",
                                            @"paused": @(c.stopped),
                                            @"busy": @((BOOL)(!c.stopped && [c.record[@"status"] isEqual:@"busy"]))}
                                          mutableCopy];
            if (AsText(c.record[@"hostSessionId"])) other[@"hostSessionId"] = c.record[@"hostSessionId"];
            [others addObject:other];
        }
        if (others.count) row.alsoOpen = others;
        [out addObject:row];
    }
    followed = now;
    return out;
}

BOOL InAnotherTerminal(NSString *sessionId, pid_t pid) {
    NSString *registry = ClaudeDir(kClaudeCodeRegistry);
    for (NSString *file in [NSFileManager.defaultManager contentsOfDirectoryAtPath:registry error:nil]) {
        if (![file.pathExtension isEqualToString:@"json"]) continue;
        pid_t other = file.stringByDeletingPathExtension.intValue;
        if (other == pid || !RunsAsYou(other) || ProcessStopped(other)) continue;
        NSString *path = [registry stringByAppendingPathComponent:file];
        NSDictionary *s = ReadJSON(path);
        // Claude Code rewrites a session's file in place, so it can be caught half-written: read again, and if it's
        // still unreadable, it may be a copy, so nothing goes in.
        if (![s isKindOfClass:NSDictionary.class]) s = ReadJSON(path);
        if (![s isKindOfClass:NSDictionary.class]) return YES;
        if ([s[@"sessionId"] isEqual:sessionId] && [s[@"entrypoint"] isEqual:kClaudeCodeTerminalEntrypoint])
            return YES;
    }
    return NO;
}

NSString *CloseOtherCopies(NSString *sessionId, pid_t keep, BOOL requestWaiting, NSUInteger *closed) {
    *closed = 0;
    NSMutableArray<NSNumber *> *closing = [NSMutableArray array];
    for (NSDictionary *s in RegisteredProcesses()) {
        pid_t pid = PidOf(s);
        if (pid == keep || ![s[@"sessionId"] isEqual:sessionId]) continue;
        // Claude Desktop keeps its own, and one paused can't shut down until it's brought back.
        if (![s[@"entrypoint"] isEqual:kClaudeCodeTerminalEntrypoint] || ProcessStopped(pid)) continue;
        if ([s[@"status"] isEqual:@"busy"]) return @"Claude is working in the other copy: close it when it's done";
        if (![s[@"status"] isEqual:@"idle"]) return @"The other copy is asking you something: answer it first";
        [closing addObject:@(pid)];
    }
    if (!closing.count) return @"There's no other copy in a terminal to close";
    // Which copy a request came from can't be told, so none is closed while one waits.
    if (requestWaiting) return @"A request is waiting in this conversation: answer it first";
    // Claude Code shuts down on SIGTERM as when its tab is closed, so the tab is left at its shell's prompt.
    for (NSNumber *pid in closing)
        if (kill(pid.intValue, SIGTERM) == 0) (*closed)++;
    return *closed ? nil : @"The other copy couldn't be closed";
}

static NSString *HookRecordPath(NSString *sessionId) {
    return [AppDir(@"sessions") stringByAppendingPathComponent:[sessionId stringByAppendingPathExtension:@"json"]];
}

// Adds what the hook recorded (last prompt / reply / notice), and when it last wrote it.
void AddHookRecord(Row *row) {
    if (!row.sessionId.length) return;
    NSString *path = HookRecordPath(row.sessionId);
    NSDictionary *record = ReadJSON(path);
    if (![record isKindOfClass:NSDictionary.class]) return;
    [row takeHookRecord:record];
    NSDate *written = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil].fileModificationDate;
    if (written) row.hookRecordedAt = @(written.timeIntervalSince1970);
}
