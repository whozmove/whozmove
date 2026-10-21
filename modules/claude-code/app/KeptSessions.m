// KeptSessions: the terminal sessions Claude Code ran lately, kept so their rows stay once they've ended.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "KeptSessions.h"
#import "Row.h"
#import "Files.h"
#import "Processes.h"
#import "Text.h"
#import "Log.h"
#import "ClaudeCodeFacts.h"

const NSTimeInterval kKeptFor = 3 * 24 * 3600;
// How often the terminal a running session is in is looked for again while it isn't known.
static const NSTimeInterval kLookAgainAfter = 10;

// A session id as a file's name: plain, as Claude Code's are, so it names a file in the folder and nothing else.
static BOOL SafeId(NSString *sessionId) {
    return IsPlainId(sessionId, 64);
}

// When a row's conversation last moved, as the page's lastActive counts it: your message, Claude's reply or the newest
// message in its transcript; else when its live line last changed; else when its status did.
static NSNumber *ActiveAt(Row *row) {
    double moved = MAX(MAX(row.lastReplyAt.doubleValue, row.lastPromptAt.doubleValue), row.messageAt.doubleValue);
    if (moved > 0) return @(moved);
    if (row.activityAt.doubleValue > 0) return row.activityAt;
    return row.statusUpdatedAt ?: @0;
}

NSDictionary *KeptRecord(Row *row, NSString *transcript, NSString *terminal) {
    if (![row.entrypoint isEqualToString:kClaudeCodeTerminalEntrypoint] || row.pid <= 0 || !SafeId(row.sessionId)
        || !row.cwd.length || !transcript.length)
        return nil;
    NSMutableDictionary *record = [@{@"sessionId": row.sessionId, @"cwd": row.cwd, @"terminal": terminal ?: @"",
                                     @"pid": @(row.pid), @"procStart": row.procStart ?: @"",
                                     @"transcript": transcript, @"activeAt": ActiveAt(row)} mutableCopy];
    if (row.name.length) record[@"name"] = row.name;
    return record;
}

static NSString *ProcessOf(NSDictionary *record) {
    return ProcessKey([AsNumber(record[@"pid"]) intValue], AsText(record[@"procStart"]));
}

NSArray<NSString *> *LeftBehind(NSDictionary<NSString *, NSDictionary *> *kept, NSArray<Row *> *rows) {
    NSMutableDictionary<NSString *, NSString *> *now = [NSMutableDictionary dictionary];  // process -> its session
    for (Row *row in rows)
        if (row.pid > 0 && row.sessionId) now[ProcessKey(row.pid, row.procStart)] = row.sessionId;
    NSSet<NSString *> *live = [NSSet setWithArray:now.allValues];
    NSMutableArray<NSString *> *left = [NSMutableArray array];
    [kept enumerateKeysAndObjectsUsingBlock:^(NSString *sessionId, NSDictionary *record, BOOL *stop) {
        NSString *there = now[ProcessOf(record)];
        if (there && ![there isEqualToString:sessionId] && ![live containsObject:sessionId]) [left addObject:sessionId];
    }];
    return [left sortedArrayUsingSelector:@selector(compare:)];
}

NSArray<NSString *> *Stale(NSDictionary<NSString *, NSDictionary *> *kept, NSSet<NSString *> *running,
                           NSTimeInterval now) {
    NSMutableArray<NSString *> *gone = [NSMutableArray array];
    [kept enumerateKeysAndObjectsUsingBlock:^(NSString *sessionId, NSDictionary *record, BOOL *stop) {
        if ([running containsObject:sessionId]) return;
        NSString *transcript = AsText(record[@"transcript"]);
        if ([AsNumber(record[@"activeAt"]) doubleValue] / 1000 < now - kKeptFor || !transcript
            || ![NSFileManager.defaultManager fileExistsAtPath:transcript])
            [gone addObject:sessionId];
    }];
    return [gone sortedArrayUsingSelector:@selector(compare:)];
}

NSString *KeptFolder(void) {
    return AppDir(@"conversations");
}

// One kept file, as it reads: only when it's named for the session it holds, and holds a folder.
static NSDictionary *KeptAt(NSString *path) {
    NSDictionary *record = AsRecord(ReadJSON(path));
    NSString *sessionId = AsText(record[@"sessionId"]);
    NSString *named = [sessionId stringByAppendingPathExtension:@"json"];
    if (!SafeId(sessionId) || ![path.lastPathComponent isEqualToString:named] || !AsText(record[@"cwd"]).length)
        return nil;
    return record;
}

NSDictionary<NSString *, NSDictionary *> *KeptIn(NSString *folder) {
    NSMutableDictionary<NSString *, NSDictionary *> *kept = [NSMutableDictionary dictionary];
    for (NSString *file in [NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil]) {
        if (![file.pathExtension isEqualToString:@"json"]) continue;
        NSDictionary *record = KeptAt([folder stringByAppendingPathComponent:file]);
        if (record) kept[record[@"sessionId"]] = record;
    }
    return kept;
}

@interface KeptSessions ()
@property (copy) NSString *folder;
@property (strong) dispatch_queue_t queue;  // where the files are read at the start, written and taken away
// On the main thread: what's kept, by session id, once it's been read (nil until then); the terminal each running
// session's process is in, by ProcessKey ("" while none is known), and when it was last looked for and not found; the
// sessions kept that run now, once the rows have been through once (nil until then); and the hourly prune.
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *kept;
@property (copy) NSDictionary<NSString *, NSString *> *terminals;
@property (copy) NSDictionary<NSString *, NSNumber *> *missedAt;
@property (copy) NSSet<NSString *> *running;
@property (strong) NSTimer *pruning;
// On the rows' queue: each file as last read, by its path, {at: its date, record}, so one is read again only once it
// has changed, as Claude Desktop's conversations are (DesktopConversations).
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *read;
@end

@implementation KeptSessions

- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.folder = KeptFolder();
    self.queue = dispatch_queue_create("whozmove.kept-sessions", DISPATCH_QUEUE_SERIAL);
    self.read = [NSMutableDictionary dictionary];
    return self;
}

- (void)start {
    __weak typeof(self) weakSelf = self;
    NSString *folder = self.folder;
    dispatch_async(self.queue, ^{
        NSDictionary *found = KeptIn(folder);
        dispatch_async(dispatch_get_main_queue(), ^{ weakSelf.kept = [found mutableCopy]; });
    });
    self.pruning = [NSTimer scheduledTimerWithTimeInterval:3600 repeats:YES block:^(NSTimer *timer) {
        [weakSelf prune];
    }];
    self.pruning.tolerance = 60;
}

- (NSString *)pathOf:(NSString *)sessionId {
    return [self.folder stringByAppendingPathComponent:[sessionId stringByAppendingPathExtension:@"json"]];
}

// What has gone is found on the queue, as it looks for each transcript; on the main thread, each is forgotten then,
// unless it has changed or runs again since, and its file taken away on the queue, in turn with the writes, so a record
// written again later is never taken away after it. Only once the sessions running now are known, so one idle for days
// that still runs isn't taken for gone.
- (void)prune {
    if (!self.kept || !self.running) return;
    NSDictionary<NSString *, NSDictionary *> *kept = [self.kept copy];
    NSSet<NSString *> *running = self.running;
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.queue, ^{
        NSArray<NSString *> *gone = Stale(kept, running, NSDate.date.timeIntervalSince1970);
        dispatch_async(dispatch_get_main_queue(), ^{
            KeptSessions *sessions = weakSelf;
            for (NSString *sessionId in gone)
                if ([sessions.kept[sessionId] isEqualToDictionary:kept[sessionId]]
                    && ![sessions.running containsObject:sessionId])
                    [sessions drop:sessionId why:@"gone"];
        });
    });
}

- (void)drop:(NSString *)sessionId why:(NSString *)why {
    [self.kept removeObjectForKey:sessionId];
    NSString *path = [self pathOf:sessionId];
    PanelLog(@"kept session %@ dropped: %@", sessionId, why);
    dispatch_async(self.queue, ^{ [NSFileManager.defaultManager removeItemAtPath:path error:nil]; });
}

// Only you may read them, as Claude Code keeps its own files: written whole at once, in a folder of their own.
- (void)write:(NSDictionary *)record {
    NSData *json = [NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingSortedKeys error:nil];
    if (!json) return;
    NSString *folder = self.folder, *path = [self pathOf:record[@"sessionId"]];
    dispatch_async(self.queue, ^{
        NSFileManager *files = NSFileManager.defaultManager;
        [files createDirectoryAtPath:folder withIntermediateDirectories:YES
                          attributes:@{NSFilePosixPermissions: @0700} error:nil];
        if (![json writeToFile:path options:NSDataWritingAtomic error:nil]) return;
        [files setAttributes:@{NSFilePosixPermissions: @0600} ofItemAtPath:path error:nil];
    });
}

- (void)keep:(NSArray<Row *> *)rows transcriptOf:(NSString *(^)(Row *row))transcriptOf
  terminalOf:(NSString *(^)(Row *row))terminalOf {
    if (!self.kept) return;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSMutableDictionary<NSString *, NSString *> *terminals = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *missedAt = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *running = [NSMutableSet set];
    for (Row *row in rows) {
        if (row.pid <= 0 || ![row.entrypoint isEqualToString:kClaudeCodeTerminalEntrypoint]) continue;
        // A session never moves terminal, so its process's is kept once found; while it isn't, it's looked for again
        // now and then (its app may not have been above it yet, or iTerm2's server not yet known for its own).
        NSString *process = ProcessKey(row.pid, row.procStart);
        NSString *terminal = self.terminals[process];
        if (!terminal.length) {
            NSNumber *missed = self.missedAt[process];
            if (missed && now - missed.doubleValue < kLookAgainAfter) missedAt[process] = missed;
            else if (!(terminal = terminalOf(row)).length) missedAt[process] = @(now);
        }
        terminals[process] = terminal ?: @"";
        NSDictionary *record = KeptRecord(row, transcriptOf(row), terminals[process]);
        if (!record) continue;
        [running addObject:row.sessionId];
        if ([self.kept[row.sessionId] isEqualToDictionary:record]) continue;
        self.kept[row.sessionId] = record;
        [self write:record];
    }
    self.terminals = terminals;
    self.missedAt = missedAt;
    BOOL first = !self.running;
    self.running = running;
    for (NSString *sessionId in LeftBehind(self.kept, rows))
        [self drop:sessionId why:@"its process went on to another conversation"];
    // What's gone is pruned once the sessions running now are known, then every hour.
    if (first) [self prune];
}

- (NSArray<Row *> *)endedBesides:(NSArray<Row *> *)listed {
    NSMutableSet<NSString *> *ids = [NSMutableSet set], *processes = [NSMutableSet set];
    for (Row *row in listed) {
        if (row.sessionId) [ids addObject:row.sessionId];
        if (row.pid > 0) [processes addObject:ProcessKey(row.pid, row.procStart)];
    }
    NSFileManager *files = NSFileManager.defaultManager;
    double since = (NSDate.date.timeIntervalSince1970 - kKeptFor) * 1000;
    NSMutableSet<NSString *> *present = [NSMutableSet set];
    NSMutableArray<Row *> *ended = [NSMutableArray array];
    NSArray *names = [files contentsOfDirectoryAtPath:self.folder error:nil];
    for (NSString *file in [names sortedArrayUsingSelector:@selector(compare:)]) {
        if (![file.pathExtension isEqualToString:@"json"]) continue;
        NSString *path = [self.folder stringByAppendingPathComponent:file];
        NSDate *at = [files attributesOfItemAtPath:path error:nil].fileModificationDate ?: NSDate.distantPast;
        NSDictionary *read = self.read[path];
        if (!read || ![read[@"at"] isEqual:at]) self.read[path] = read = @{@"at": at, @"record": KeptAt(path) ?: @{}};
        [present addObject:path];
        NSDictionary *record = read[@"record"];
        NSString *sessionId = record[@"sessionId"], *cwd = record[@"cwd"], *transcript = AsText(record[@"transcript"]);
        BOOL folder = NO;
        // One whose process runs another conversation now was left there (KeptSessions' keep: drops it soon too).
        if (!sessionId || [ids containsObject:sessionId] || [processes containsObject:ProcessOf(record)]
            || [AsNumber(record[@"activeAt"]) doubleValue] < since || !transcript
            || ![files fileExistsAtPath:transcript] || ![files fileExistsAtPath:cwd isDirectory:&folder] || !folder)
            continue;
        Row *row = [Row new];
        row.sessionId = sessionId;
        row.cwd = cwd;
        row.name = AsText(record[@"name"]);
        row.entrypoint = kClaudeCodeTerminalEntrypoint;
        row.status = @"closed";
        row.statusUpdatedAt = AsNumber(record[@"activeAt"]);
        row.ranIn = AsText(record[@"terminal"]).length ? record[@"terminal"] : nil;
        [ended addObject:row];
    }
    for (NSString *path in self.read.allKeys)
        if (![present containsObject:path]) [self.read removeObjectForKey:path];
    return ended;
}

@end
