// WhereSeenWorking: each session's own process, and where it was seen working.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "WhereSeenWorking.h"
#import "Row.h"
#import "Files.h"
#import "Processes.h"
#import "ClaudeSessions.h"
#import "KeptSessions.h"

@interface WhereSeenWorking ()
@property (copy) ClaudeProgram (^programOf)(pid_t pid);
// By session id, {pid, started, folder, origin}: from the first process of Claude Code's own program seen for it, the
// folder followed only as that same process moves, `origin` the folder it was first seen working in. Written on the
// rows' queue and read as a session asks, so kept under a lock.
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *seen;
@end

@implementation WhereSeenWorking

- (instancetype)initWithProgram:(ClaudeProgram (^)(pid_t pid))programOf {
    if (!(self = [super init])) return nil;
    self.programOf = programOf;
    self.seen = [NSMutableDictionary dictionary];
    return self;
}

- (NSDictionary *)seenFor:(NSString *)sessionId {
    @synchronized (self.seen) {
        return self.seen[sessionId];
    }
}

static BOOL Runs(NSDictionary *seen) {
    return seen && ProcessStartedAt([seen[@"pid"] intValue]) == [seen[@"started"] longLongValue];
}

static BOOL WithinAny(NSString *folder, NSArray<NSString *> *places) {
    for (NSString *place in places)
        if (PathWithin(folder, place)) return YES;
    return NO;
}

- (void)note {
    for (NSDictionary *copy in RegisteredCopies()) {
        pid_t pid = [copy[@"pid"] intValue];
        NSString *sessionId = copy[@"sessionId"];
        long long started = ProcessStartedAt(pid);
        NSDictionary *was = [self seenFor:sessionId];
        BOOL same = [was[@"pid"] intValue] == pid && [was[@"started"] longLongValue] == started;
        if (!started || (Runs(was) && !same)) continue;  // the one seen first still runs: it stays the session's own
        if (!same && self.programOf(pid) != ClaudeProgramSigned) continue;
        NSString *folder = ProcessFolder(pid), *kept = was ? nil : AsText(KeptOf(sessionId)[@"cwd"]);
        if (!folder) continue;
        NSArray<NSString *> *places = was ? @[was[@"origin"], was[@"folder"]] : kept ? @[kept] : nil;
        if (!same && places && !WithinAny(folder, places)) continue;
        @synchronized (self.seen) {
            self.seen[sessionId] = @{@"pid": @(pid), @"started": @(started), @"folder": folder,
                                     @"origin": was[@"origin"] ?: kept ?: folder};
        }
    }
    @synchronized (self.seen) {
        if (self.seen.count > 1024) [self.seen removeAllObjects];
    }
}

// A record blocks no one unless its process is Node, which could be an older Claude Code from npm, and then it only
// holds the session's asks back. The rows are up to a second old, so the registry and the processes are read again
// here. What stays open: a real Claude Code started in that same folder can take up a session that has ended, as
// resuming it there would, which anything running as you can do.
- (NSString *)whyNot:(Row *)row speakFrom:(pid_t)process {
    NSArray<NSNumber *> *copies = ClaudeCopiesOf(row.sessionId, process, self.programOf);
    NSDictionary *seen = [self seenFor:row.sessionId];
    return WhyNotSpeakFrom(process, ProcessFolder(process), copies, seen, Runs(seen),
                           AsText(KeptOf(row.sessionId)[@"cwd"]) ?: row.cwd, row.name);
}

@end

NSArray<NSNumber *> *ClaudeCopiesOf(NSString *sessionId, pid_t besides, ClaudeProgram (^programOf)(pid_t pid)) {
    NSMutableArray<NSNumber *> *copies = [NSMutableArray array];
    for (NSNumber *other in OtherCopiesOf(sessionId, besides))
        if (programOf(other.intValue) != ClaudeProgramNone) [copies addObject:other];
    return copies;
}

NSString *WhyNotSpeakFrom(pid_t process, NSString *working, NSArray<NSNumber *> *copies, NSDictionary *seen,
                          BOOL seenRuns, NSString *recorded, NSString *name) {
    NSString *(^openTwice)(NSNumber *) = ^NSString *(NSNumber *other) {
        return [NSString stringWithFormat:@"this conversation is open in another process too (%@): close the other "
                                          @"copy, then ask again", other];
    };
    if (copies.count) return openTwice(copies.firstObject);
    if (seen && seenRuns) return [seen[@"pid"] intValue] == process ? nil : openTwice(seen[@"pid"]);
    NSArray<NSString *> *places = seen ? @[seen[@"origin"], seen[@"folder"]] : @[recorded ?: @""];
    if (WithinAny(working, places)) return nil;
    NSString *where = working ?: @"a folder that can't be read", *who = name.length ? name : @"its session";
    if (![places.firstObject length])
        return [NSString stringWithFormat:@"this process works in %@, and Whozmove doesn't know where %@ works: ask "
                                          @"from that session's own Claude Code", where, who];
    return [NSString stringWithFormat:@"this process works in %@, not where %@ was seen working (%@): ask from that "
                                      @"session's own Claude Code", where, who, places.firstObject];
}
