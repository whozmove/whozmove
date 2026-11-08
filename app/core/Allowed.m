// Allowed: a file for each session with a switch turned on, allowed/<session>.json, {key: {at, pid, processStart,
// bound}}: when it was turned on (ms), and, for a switch that lasts for the process, which process that was (its pid and
// when it started, so a later process given the same pid isn't taken for it), and what it was given for. A switch that
// lasts only while Whozmove runs keeps the same record in memory instead, never in the file: one the file names is
// ignored. Those in memory are also written to ticked.json (the user's ticks, kept for the next copy to offer, never
// to turn on), as {session id: {key: record}}; a copy that starts reads it into `waiting`, never into memory. A switch
// kept for a folder (SwitchLastsWorkspace) is kept in memory by that folder, {at, session, pid, processStart}: when, and
// the session and process it was ticked in or brought back on, which only tells its module when a new session holds
// it. ticked.json has those under `workspaces`, {folder: {key: {at}}}: the folder and the switch, nothing of who.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Allowed.h"
#import "Core.h"
#import "Modules.h"
#import "Row.h"
#import "Files.h"
#import "Text.h"
#import "Processes.h"
#import "Log.h"

// How long a session's file stays at least, listed or not, and how often the ended ones are looked for.
static const NSTimeInterval kKeptAfterGone = 24 * 3600, kPruneEvery = 3600;
// How long after launch a waiting record whose session isn't listed is kept: the first rows can come before every
// session is listed.
static const NSTimeInterval kWaitingGrace = 60;
// Where ticked.json keeps the switches kept for a folder, beside the sessions' own: never a session's id, as an id is a
// UUID.
static NSString *const kWorkspaces = @"workspaces";
// How long a switch kept for a folder stays kept once no session there has held it (it lapses then, as a folder left
// behind would otherwise be kept for good), how often whether one holds it is looked at, and how often that's written
// to ticked.json, so a Quit or a restart keeps it.
static const double kKeptForMs = 7 * 24 * 3600 * 1000.0;
static const NSTimeInterval kHeldLookedAtEvery = 60;
static const double kHeldWrittenEveryMs = 3600 * 1000.0;

@interface Allowed ()
@property (weak) Core *core;
@property (assign) NSTimeInterval prunedAt;
// The switches kept only while Whozmove runs: session id -> {key: record}.
@property (strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *inMemory;
// What the user had on in the copy before this one, which this copy only offers to turn back on (bringBack:): session
// id -> {key: record}, read from ticked.json as this copy started.
@property (strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *waiting;
// Where ticked.json is kept, nil until the app (or a print run in a throwaway home) says: so a print run that sets a
// switch never writes the user's own.
@property (copy) NSString *tickedPath;
@property (assign) NSTimeInterval keptAt;
// Whether ticked.json couldn't be written the last time, so it is written again as the next rows come.
@property (assign) BOOL tickedUnsaved;
// The switches kept for a folder: folder -> {key: record}; those the copy before this one had, which only your press
// turns on again: folder -> {key: {at}}; and what each has done for each session that held it: session id -> {key: n}.
@property (strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *kept;
@property (strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *keptWaiting;
@property (strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *counts;
// When it was last looked at whether a session holds each switch kept for a folder (noteHeld:).
@property (assign) NSTimeInterval heldLookedAt;
@end

// A session's file, or nil for an id that isn't one.
static NSString *FileOf(NSString *sessionId) {
    if (!IsPlainId(sessionId, 128)) return nil;
    return [AppDir(@"allowed") stringByAppendingPathComponent:[sessionId stringByAppendingPathExtension:@"json"]];
}

static NSDictionary<NSString *, NSDictionary *> *RecordsOf(NSString *sessionId) {
    NSString *path = FileOf(sessionId);
    NSDictionary *records = path ? AsRecord(ReadJSON(path)) : nil;
    return records ?: @{};
}

// Writes a session's records, only you able to read them; with none left, its file goes.
static BOOL WriteRecords(NSString *sessionId, NSDictionary *records) {
    NSString *path = FileOf(sessionId);
    if (!path) return NO;
    NSFileManager *files = NSFileManager.defaultManager;
    if (!records.count) return [files removeItemAtPath:path error:nil] || ![files fileExistsAtPath:path];
    [files createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES
                      attributes:@{NSFilePosixPermissions: @0700} error:nil];
    NSData *json = [NSJSONSerialization dataWithJSONObject:records options:NSJSONWritingSortedKeys error:nil];
    if (![json writeToFile:path options:NSDataWritingAtomic error:nil]) return NO;
    [files setAttributes:@{NSFilePosixPermissions: @0600} ofItemAtPath:path error:nil];
    return YES;
}

@implementation Allowed

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.inMemory = [NSMutableDictionary dictionary];
    self.waiting = [NSMutableDictionary dictionary];
    self.kept = [NSMutableDictionary dictionary];
    self.keptWaiting = [NSMutableDictionary dictionary];
    self.counts = [NSMutableDictionary dictionary];
    // The first look an hour after launch, once the ended sessions kept are surely among the rows.
    self.prunedAt = NSDate.timeIntervalSinceReferenceDate;
    return self;
}

- (NSArray<SessionSwitch *> *)switches {
    // A print run's own stand-ins, so the tests try these rules apart from any module's checks; never in the app.
    if (self.printingSwitches && self.core.printing) return self.printingSwitches;
    return self.core.modules.sessionSwitches;
}

- (NSArray<SessionSwitch *> *)switchesFor:(Row *)row {
    NSMutableArray *shown = [NSMutableArray array];
    for (SessionSwitch *each in self.switches)
        if (!each.shown || each.shown(row)) [shown addObject:each];
    return shown;
}

- (SessionSwitch *)switchWithKey:(NSString *)key {
    for (SessionSwitch *each in self.switches)
        if ([each.key isEqual:key]) return each;
    return nil;
}

// Whether a switch is given to one process of a session, so ends with it.
static BOOL ForTheProcess(SessionSwitch *each) {
    return each.lasts == SwitchLastsProcess || each.lasts == SwitchLastsWhileRunning;
}

// A session's record of a switch: from memory for one kept only while Whozmove runs, else from its file.
- (NSDictionary *)recordOf:(SessionSwitch *)each session:(NSString *)sessionId {
    if (!sessionId) return nil;
    if (each.lasts == SwitchLastsWhileRunning) return AsRecord(self.inMemory[sessionId][each.key]);
    return AsRecord(RecordsOf(sessionId)[each.key]);
}

// Why a record no longer counts, or nil while it does: the process it was given to has ended (one that lasts for the
// process), or what it was given for has changed.
static NSString *Ended(SessionSwitch *each, NSDictionary *record, Row *row) {
    if (ForTheProcess(each)) {
        pid_t pid = AsNumber(record[@"pid"]).intValue;
        long long started = AsNumber(record[@"processStart"]).longLongValue;
        if (pid <= 0 || !started || ProcessStartedAt(pid) != started)
            return [NSString stringWithFormat:@"%@ ended with the session it was turned on in", each.title];
    }
    if (each.bound && row) {
        NSString *now = each.bound(row), *then = AsText(record[@"bound"]);
        if (!(now == then || [now isEqual:then]))
            return [NSString stringWithFormat:@"%@ ended: %@", each.title,
                                              each.boundSays ?: @"what it was turned on for has changed since"];
    }
    return nil;
}

- (NSString *)whyOff:(NSString *)key for:(Row *)row {
    return [self whyOff:key for:row from:0];
}

- (NSString *)whyOff:(NSString *)key for:(Row *)row from:(pid_t)process {
    SessionSwitch *each = [self switchWithKey:key];
    if (!each) return @"Whozmove has no such switch";
    if (each.lasts == SwitchLastsWorkspace) return [self whyKeptOff:each for:row from:process];
    NSDictionary *record = [self recordOf:each session:row.sessionId];
    if (!record && [[self waitingFor:row] containsObject:each])
        return [NSString stringWithFormat:@"%@ is off since Whozmove restarted: the user turns it back on with one "
                                          @"press in this session's mode menu", each.title];
    // One kept only while Whozmove runs may have been on before it restarted: the way back is said either way.
    if (!record && each.lasts == SwitchLastsWhileRunning && each.shown && !each.shown(row))
        return [NSString stringWithFormat:@"%@ is off: %@", each.title,
                                          each.hiddenSays ?: @"it isn't offered for this session"];
    if (!record && each.lasts == SwitchLastsWhileRunning)
        return [NSString stringWithFormat:@"%@ is off: it lasts only while Whozmove and this session run; turn it on "
                                          @"again in this session's mode menu", each.title];
    if (!record) return [NSString stringWithFormat:@"%@ isn't on for this session", each.title];
    if (each.shown && !each.shown(row))
        return [NSString stringWithFormat:@"%@ is off while %@", each.title,
                                          each.hiddenSays ?: @"it isn't offered for this session"];
    NSString *ended = Ended(each, record, row);
    if (ended) return ended;
    if (process && ForTheProcess(each) && AsNumber(record[@"pid"]).intValue != process)
        return [NSString stringWithFormat:@"%@ is on only in the process it was turned on in, not this copy of the "
                                          @"conversation", each.title];
    return nil;
}

// The folder a row works in, for a switch kept by folder, or nil: none, or a row with no session.
static NSString *FolderFor(SessionSwitch *each, Row *row) {
    NSString *folder = row.sessionId && each.workspace ? each.workspace(row) : nil;
    return folder.length ? folder : nil;
}

// Why a switch kept by folder is off for a row, or nil while it's on: kept for the row's folder, shown for it, the
// module's whyNot saying nothing now (which session there may hold it), and asked from the process the row follows.
- (NSString *)whyKeptOff:(SessionSwitch *)each for:(Row *)row from:(pid_t)process {
    NSString *folder = FolderFor(each, row);
    NSDictionary *record = folder ? AsRecord(self.kept[folder][each.key]) : nil;
    if (!record && [[self waitingFor:row] containsObject:each])
        return [NSString stringWithFormat:@"%@ is off since Whozmove restarted: the user turns it back on with one "
                                          @"press in this session's mode menu", each.title];
    if (!record && each.shown && !each.shown(row))
        return [NSString stringWithFormat:@"%@ is off: %@", each.title,
                                          each.hiddenSays ?: @"it isn't offered for this session"];
    if (!record) return [NSString stringWithFormat:@"%@ isn't on for this session's folder", each.title];
    if (each.shown && !each.shown(row))
        return [NSString stringWithFormat:@"%@ is kept for %@, but off while %@", each.title, folder.lastPathComponent,
                                          each.hiddenSays ?: @"it isn't offered for this session"];
    NSString *why = each.whyNot ? each.whyNot(row) : nil;
    if (why)
        return [NSString stringWithFormat:@"%@ is kept for %@, but off now: %@", each.title, folder.lastPathComponent,
                                          AfterColon(why)];
    if (process && process != row.pid)
        return [NSString stringWithFormat:@"%@ is on only in the process this session's row follows, not this copy of "
                                          @"the conversation", each.title];
    return nil;
}

- (BOOL)isOn:(NSString *)key for:(Row *)row {
    return row.sessionId && ![self whyOff:key for:row];
}

// Your press on a switch kept by folder: kept from now for the row's folder, with the session and process it was
// ticked in, or taken away, waiting or not. An untick holds even when ticked.json can't be written, as below.
- (BOOL)setKept:(SessionSwitch *)each for:(Row *)row on:(BOOL)on {
    NSString *folder = FolderFor(each, row), *sessionId = row.sessionId;
    if (!folder) return NO;
    if (on) {
        long long started = ProcessStartedAt(row.pid);
        if (row.pid <= 0 || !started) return NO;
        if (!self.kept[folder]) self.kept[folder] = [NSMutableDictionary dictionary];
        long long now = (long long)(NSDate.date.timeIntervalSince1970 * 1000);
        self.kept[folder][each.key] = @{@"at": @(now), @"held": @(now), @"session": sessionId, @"pid": @(row.pid),
                                        @"processStart": @(started)};
    } else {
        [self.kept[folder] removeObjectForKey:each.key];
        if (!self.kept[folder].count) [self.kept removeObjectForKey:folder];
    }
    [self.keptWaiting[folder] removeObjectForKey:each.key];
    if (!self.keptWaiting[folder].count) [self.keptWaiting removeObjectForKey:folder];
    if (![self writeTicked] && !on && ![self removeTicked]) [self emptyTicked];
    PanelLog(@"%@ -> %@ %@ for %@", sessionId, each.title, on ? @"on" : @"off", folder.lastPathComponent);
    if (each.changed) each.changed(sessionId, on);
    return YES;
}

- (BOOL)set:(NSString *)key for:(Row *)row on:(BOOL)on {
    SessionSwitch *each = [self switchWithKey:key];
    NSString *sessionId = row.sessionId;
    if (!each || !FileOf(sessionId)) return NO;
    if (on && each.whyNot && each.whyNot(row)) return NO;
    if (each.lasts == SwitchLastsWorkspace) return [self setKept:each for:row on:on];
    BOOL inMemory = each.lasts == SwitchLastsWhileRunning;
    NSMutableDictionary *records = [(inMemory ? self.inMemory[sessionId] : RecordsOf(sessionId)) mutableCopy]
        ?: [NSMutableDictionary dictionary];
    if (on) {
        NSMutableDictionary *record = [@{@"at": @((long long)(NSDate.date.timeIntervalSince1970 * 1000))}
                                       mutableCopy];
        if (ForTheProcess(each)) {
            long long started = ProcessStartedAt(row.pid);
            if (row.pid <= 0 || !started) return NO;
            record[@"pid"] = @(row.pid);
            record[@"processStart"] = @(started);
        }
        NSString *bound = each.bound ? each.bound(row) : nil;
        if (bound) record[@"bound"] = bound;
        records[key] = record;
    } else {
        [records removeObjectForKey:key];
    }
    BOOL done = YES;
    if (inMemory) {
        self.inMemory[sessionId] = records.count ? records : nil;
        // Ticked or unticked by hand, it is no longer one to offer.
        [self.waiting[sessionId] removeObjectForKey:key];
        if (!self.waiting[sessionId].count) [self.waiting removeObjectForKey:sessionId];
        // An untick holds even when ticked.json can't be written: the switch is off in memory, and the file, which
        // would offer it again, is taken away; or, in a folder that can't be changed, emptied where it lies, as the
        // file itself may still be written.
        if (![self writeTicked] && !on && ![self removeTicked]) [self emptyTicked];
    } else {
        done = WriteRecords(sessionId, records);
    }
    PanelLog(@"%@ -> %@ %@%@", sessionId, each.title, on ? @"on" : @"off", done ? @"" : @" (couldn't be saved)");
    if (done && each.changed) each.changed(sessionId, on);
    return done;
}

- (BOOL)has:(NSString *)key session:(NSString *)sessionId {
    return AsRecord(RecordsOf(sessionId)[key]) != nil;
}

// Each switch that ends once it's hidden, hidden now for a listed session it's on for (Let It Deploy while Deploy is):
// a few small files read each second, in a folder that's usually empty.
- (void)endHidden:(NSArray<Row *> *)rows {
    NSFileManager *files = NSFileManager.defaultManager;
    NSMutableDictionary<NSString *, Row *> *listed = [NSMutableDictionary dictionary];
    for (Row *row in rows)
        if (row.sessionId) listed[row.sessionId] = row;
    for (NSString *name in [files contentsOfDirectoryAtPath:AppDir(@"allowed") error:nil]) {
        Row *row = [name.pathExtension isEqualToString:@"json"] ? listed[name.stringByDeletingPathExtension] : nil;
        if (!row) continue;
        NSMutableDictionary *records = [RecordsOf(row.sessionId) mutableCopy];
        NSMutableArray<SessionSwitch *> *ended = [NSMutableArray array];
        for (NSString *key in records.allKeys) {
            SessionSwitch *each = [self switchWithKey:key];
            if (!each.endsHidden || !each.shown || each.shown(row)) continue;
            [records removeObjectForKey:key];
            [ended addObject:each];
        }
        if (!ended.count || !WriteRecords(row.sessionId, records)) continue;
        for (SessionSwitch *each in ended) {
            PanelLog(@"%@ -> %@ ended, as it's hidden", row.sessionId, each.title);
            if (each.changed) each.changed(row.sessionId, NO);
        }
    }
}

// A session's id is kept for good (a conversation carried on keeps it), so its file goes only once its row has gone:
// listed neither running nor kept as ended. A listed one's switches go as they end.
// The switches kept in memory go as they end, each time: the sessions' own, and those of a session no longer listed.
- (void)endInMemory:(NSArray<Row *> *)rows {
    NSMutableDictionary<NSString *, Row *> *listed = [NSMutableDictionary dictionary];
    for (Row *row in rows)
        if (row.sessionId) listed[row.sessionId] = row;
    BOOL ended = NO;
    for (NSString *sessionId in self.inMemory.allKeys) {
        Row *row = listed[sessionId];
        NSMutableDictionary *records = self.inMemory[sessionId];
        for (NSString *key in records.allKeys) {
            SessionSwitch *each = [self switchWithKey:key];
            if (each && row && !Ended(each, records[key], row) && !(each.endsHidden && each.shown && !each.shown(row)))
                continue;
            [records removeObjectForKey:key];
            [self.waiting[sessionId] removeObjectForKey:key];
            ended = YES;
            PanelLog(@"%@ -> %@ ended", sessionId, each.title ?: key);
            if (each.changed) each.changed(sessionId, NO);
        }
        if (!records.count) [self.inMemory removeObjectForKey:sessionId];
    }
    if (ended) [self writeTicked];
}

// What waits for a press goes once it can't be brought back any more: its session isn't listed (but not in the first
// minute, while the sessions are still being listed), its process has ended, what it was given for has changed, or the
// switch isn't offered for its row now.
- (void)endWaiting:(NSArray<Row *> *)rows {
    // One kept for a folder waits for any session there, so it goes only once its folder has.
    BOOL gone = NO;
    for (NSString *folder in self.keptWaiting.allKeys) {
        BOOL isFolder = NO;
        if ([NSFileManager.defaultManager fileExistsAtPath:folder isDirectory:&isFolder] && isFolder) continue;
        [self.keptWaiting removeObjectForKey:folder];
        gone = YES;
        PanelLog(@"switches kept for %@ no longer offered back: the folder has gone", folder.lastPathComponent);
    }
    if (gone) [self writeTicked];
    if (!self.waiting.count) return;
    NSMutableDictionary<NSString *, Row *> *listed = [NSMutableDictionary dictionary];
    for (Row *row in rows)
        if (row.sessionId) listed[row.sessionId] = row;
    BOOL early = NSDate.timeIntervalSinceReferenceDate - self.keptAt < kWaitingGrace, ended = NO;
    for (NSString *sessionId in self.waiting.allKeys) {
        Row *row = listed[sessionId];
        if (!row && early) continue;
        NSMutableDictionary *records = self.waiting[sessionId];
        for (NSString *key in records.allKeys) {
            SessionSwitch *each = [self switchWithKey:key];
            NSDictionary *record = AsRecord(records[key]);
            if (each && record && row && !Ended(each, record, row) && (!each.shown || each.shown(row))) continue;
            [records removeObjectForKey:key];
            ended = YES;
            PanelLog(@"%@ -> %@ no longer offered back", sessionId, each.title ?: key);
        }
        if (!records.count) [self.waiting removeObjectForKey:sessionId];
    }
    if (ended) [self writeTicked];
}

- (void)countUp:(NSString *)key session:(NSString *)sessionId {
    SessionSwitch *each = [self switchWithKey:key];
    // One kept by folder counts for each session that holds it, in memory only, so a new session starts again.
    if (each.lasts == SwitchLastsWorkspace && sessionId) {
        if (!self.counts[sessionId]) self.counts[sessionId] = [NSMutableDictionary dictionary];
        self.counts[sessionId][key] = @(AsNumber(self.counts[sessionId][key]).integerValue + 1);
        return;
    }
    NSDictionary *record = each.lasts == SwitchLastsWhileRunning ? [self recordOf:each session:sessionId] : nil;
    if (!record) return;
    NSMutableDictionary *counted = [record mutableCopy];
    counted[@"count"] = @(AsNumber(record[@"count"]).integerValue + 1);
    self.inMemory[sessionId][key] = counted;
    [self writeTicked];
}

- (NSInteger)count:(NSString *)key session:(NSString *)sessionId {
    SessionSwitch *each = [self switchWithKey:key];
    if (each.lasts == SwitchLastsWorkspace) return sessionId ? AsNumber(self.counts[sessionId][key]).integerValue : 0;
    return each ? MAX(AsNumber([self recordOf:each session:sessionId][@"count"]).integerValue, 0) : 0;
}

#pragma mark ticked.json

// Everything on or waiting, as it is written: session id -> {key: record}, what is on winning where both have a key.
- (NSDictionary *)tickedRecords {
    NSMutableDictionary *all = [NSMutableDictionary dictionary];
    for (NSDictionary<NSString *, NSMutableDictionary *> *kept in @[self.waiting, self.inMemory])
        for (NSString *sessionId in kept) {
            if (!kept[sessionId].count) continue;
            NSMutableDictionary *records = all[sessionId] ?: [NSMutableDictionary dictionary];
            [records addEntriesFromDictionary:kept[sessionId]];
            all[sessionId] = records;
        }
    // Those kept for a folder, on or waiting: the folder, the switch and when, never the session or process.
    NSMutableDictionary *folders = [NSMutableDictionary dictionary];
    for (NSDictionary<NSString *, NSMutableDictionary *> *kept in @[self.keptWaiting, self.kept])
        for (NSString *folder in kept)
            for (NSString *key in kept[folder]) {
                if (!folders[folder]) folders[folder] = [NSMutableDictionary dictionary];
                NSDictionary *record = AsRecord(kept[folder][key]);
                folders[folder][key] = @{@"at": AsNumber(record[@"at"]) ?: @0,
                                         @"held": AsNumber(record[@"held"]) ?: AsNumber(record[@"at"]) ?: @0};
            }
    if (folders.count) all[kWorkspaces] = folders;
    return all;
}

// Takes ticked.json away. Whether it's gone.
- (BOOL)removeTicked {
    NSFileManager *files = NSFileManager.defaultManager;
    return !self.tickedPath || [files removeItemAtPath:self.tickedPath error:nil]
        || ![files fileExistsAtPath:self.tickedPath];
}

// Overwrites ticked.json where it lies, not through a new file beside it, with nothing in it: the last way to keep what
// was unticked from being offered, when the folder it is in can't be changed. The rest of what it held is not offered
// either; the next write that can be made puts it back.
- (void)emptyTicked {
    [[@"{}" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:self.tickedPath options:0 error:nil];
}

// Writes ticked.json to say what is on or waiting, only you able to read it; with none, it goes. Nothing is written
// until the app says where (keepTickedAt:). Whether it's as it should be: when it isn't, it is tried again as the
// rows come, so what was unticked reaches the file once the folder can be written.
- (BOOL)writeTicked {
    if (!self.tickedPath) return YES;
    BOOL saved = [self writeTickedNow];
    if (!saved && !self.tickedUnsaved) PanelLog(@"ticked.json couldn't be written");
    self.tickedUnsaved = !saved;
    return saved;
}

- (BOOL)writeTickedNow {
    NSDictionary *all = [self tickedRecords];
    if (!all.count) return [self removeTicked];
    NSFileManager *files = NSFileManager.defaultManager;
    [files createDirectoryAtPath:self.tickedPath.stringByDeletingLastPathComponent withIntermediateDirectories:YES
                      attributes:@{NSFilePosixPermissions: @0700} error:nil];
    NSData *json = [NSJSONSerialization dataWithJSONObject:all options:NSJSONWritingSortedKeys error:nil];
    if (![json writeToFile:self.tickedPath options:NSDataWritingAtomic error:nil]) return NO;
    [files setAttributes:@{NSFilePosixPermissions: @0600} ofItemAtPath:self.tickedPath error:nil];
    return YES;
}

// Whether a switch kept for a folder, last held then (ms since 1970), has lapsed: no session has held it for 7 days.
static BOOL Lapsed(NSNumber *held) {
    return NSDate.date.timeIntervalSince1970 * 1000 - held.doubleValue > kKeptForMs;
}

// Notes, once a minute, which switches kept for a folder a listed session holds now, so they're kept 7 days more, and
// lets go of those none has held for 7 days, waiting or not. When one was last held is written to ticked.json at most
// once an hour, so a Quit or a restart keeps it, and at once when one lapses.
- (void)noteHeld:(NSArray<Row *> *)rows {
    NSTimeInterval looked = NSDate.timeIntervalSinceReferenceDate;
    if ((!self.kept.count && !self.keptWaiting.count) || looked - self.heldLookedAt < kHeldLookedAtEvery) return;
    self.heldLookedAt = looked;
    double now = NSDate.date.timeIntervalSince1970 * 1000;
    BOOL write = NO;
    for (NSString *folder in self.kept.allKeys)
        for (NSString *key in [self.kept[folder] allKeys]) {
            SessionSwitch *each = [self switchWithKey:key];
            NSDictionary *record = AsRecord(self.kept[folder][key]);
            for (Row *row in rows) {
                if (![FolderFor(each, row) isEqualToString:folder] || ![self isOn:key for:row]) continue;
                if (now - [record[@"held"] doubleValue] > kHeldWrittenEveryMs) write = YES;
                NSMutableDictionary *held = [record mutableCopy];
                held[@"held"] = @((long long)now);
                self.kept[folder][key] = held;
                break;
            }
        }
    for (NSMutableDictionary<NSString *, NSMutableDictionary *> *kept in @[self.kept, self.keptWaiting])
        for (NSString *folder in kept.allKeys) {
            for (NSString *key in [kept[folder] allKeys]) {
                NSDictionary *record = AsRecord(kept[folder][key]);
                if (!Lapsed(AsNumber(record[@"held"]) ?: AsNumber(record[@"at"]))) continue;
                [kept[folder] removeObjectForKey:key];
                write = YES;
                PanelLog(@"%@ -> %@ no longer kept: no session there has held it for 7 days",
                         folder.lastPathComponent, key);
            }
            if (!kept[folder].count) [kept removeObjectForKey:folder];
        }
    if (write) [self writeTicked];
}

// What the copy before this one kept for folders, read into what waits for your press: only a folder named by its
// whole real path that's there, and a switch kept by folder. How many wait.
- (NSInteger)keepWaitingFolders:(NSDictionary *)saved {
    NSInteger taken = 0;
    for (NSString *folder in saved) {
        BOOL isFolder = NO;
        if (![folder isKindOfClass:NSString.class] || !folder.isAbsolutePath || ![RealPath(folder) isEqual:folder]
            || ![NSFileManager.defaultManager fileExistsAtPath:folder isDirectory:&isFolder] || !isFolder) {
            PanelLog(@"switches for a folder that isn't one not offered back");
            continue;
        }
        NSDictionary *records = AsRecord(saved[folder]);
        for (NSString *key in records) {
            SessionSwitch *each = [self switchWithKey:key];
            NSDictionary *record = AsRecord(records[key]);
            NSNumber *held = AsNumber(record[@"held"]) ?: AsNumber(record[@"at"]);
            BOOL lapsed = record && Lapsed(held);
            if (!each || each.lasts != SwitchLastsWorkspace || !record || lapsed) {
                PanelLog(@"%@ -> %@ not offered back: %@", folder.lastPathComponent, key,
                         lapsed ? @"no session there has held it for 7 days"
                         : each ? @"it isn't kept for a folder" : @"Whozmove has no such switch");
                continue;
            }
            if (!self.keptWaiting[folder]) self.keptWaiting[folder] = [NSMutableDictionary dictionary];
            self.keptWaiting[folder][key] = @{@"at": AsNumber(record[@"at"]) ?: @0, @"held": held ?: @0};
            taken++;
            PanelLog(@"%@ -> %@ off since Whozmove restarted, offered back", folder.lastPathComponent, each.title);
        }
    }
    return taken;
}

// Only what a copy kept in memory could have had: a session's id, a switch kept in memory, and a record whose process
// still runs, started when it says, so a session that ended meanwhile is not offered. What it was given for (`bound`)
// is checked against its row as the rows come, as for any record.
- (NSInteger)keepTickedAt:(NSString *)path {
    // A print run never writes the user's own file; one in a throwaway home may be given its path.
    if (self.core.printing && HomeIsYourOwn()) return 0;
    self.tickedPath = path;
    self.keptAt = NSDate.timeIntervalSinceReferenceDate;
    NSDictionary *saved = AsRecord(ReadJSON(path));
    NSInteger taken = [self keepWaitingFolders:AsRecord(saved[kWorkspaces])];
    for (NSString *sessionId in saved) {
        if ([sessionId isEqual:kWorkspaces]) continue;
        if (!FileOf(sessionId)) {
            PanelLog(@"switches for a session id that isn't one not offered back");
            continue;
        }
        NSDictionary *records = AsRecord(saved[sessionId]);
        for (NSString *key in records) {
            SessionSwitch *each = [self switchWithKey:key];
            NSDictionary *record = AsRecord(records[key]);
            NSString *ended = each && record ? Ended(each, record, nil) : nil;
            if (!each || each.lasts != SwitchLastsWhileRunning || !record || ended) {
                PanelLog(@"%@ -> %@ not offered back: %@", sessionId, key,
                         ended ?: (each ? @"it isn't kept in memory" : @"Whozmove has no such switch"));
                continue;
            }
            NSMutableDictionary *kept = [NSMutableDictionary dictionary];
            for (NSString *field in @[@"at", @"pid", @"processStart"])
                if (AsNumber(record[field])) kept[field] = AsNumber(record[field]);
            if (AsNumber(record[@"count"])) kept[@"count"] = @(MAX(AsNumber(record[@"count"]).integerValue, 0));
            if (AsText(record[@"bound"])) kept[@"bound"] = AsText(record[@"bound"]);
            if (!self.waiting[sessionId]) self.waiting[sessionId] = [NSMutableDictionary dictionary];
            self.waiting[sessionId][key] = kept;
            taken++;
            PanelLog(@"%@ -> %@ off since Whozmove restarted, offered back", sessionId, each.title);
        }
    }
    // What was refused is not kept, and a file with nothing left in it goes.
    if (saved.count) [self writeTicked];
    return taken;
}

- (NSArray<SessionSwitch *> *)waitingFor:(Row *)row {
    NSDictionary *records = row.sessionId ? self.waiting[row.sessionId] : nil;
    if (row.pid <= 0 || (!records.count && !self.keptWaiting.count)) return @[];
    NSMutableArray *offered = [NSMutableArray array];
    for (SessionSwitch *each in self.switches) {
        // One kept for a folder is offered to any session working there it's shown for, as it isn't one session's.
        if (each.lasts == SwitchLastsWorkspace) {
            NSString *folder = FolderFor(each, row);
            if (folder && self.keptWaiting[folder][each.key] && !self.kept[folder][each.key]
                && (!each.shown || each.shown(row)))
                [offered addObject:each];
            continue;
        }
        NSDictionary *record = AsRecord(records[each.key]);
        if (!record || (each.shown && !each.shown(row))) continue;
        // Only the very process it was ticked in: the record's pid is the row's, and it started when the record says.
        if (AsNumber(record[@"pid"]).intValue != row.pid || Ended(each, record, row)) continue;
        [offered addObject:each];
    }
    return offered;
}

// Why a switch waiting for the row's session can't be turned back on in it now, or nil when it can; `waits` says
// whether it waits for the row at all. Every check ticking makes, made again now: the row's role and process may have
// changed since the menu was drawn.
- (NSString *)whyNotBack:(SessionSwitch *)each row:(Row *)row waits:(BOOL *)waits {
    NSString *sessionId = row.sessionId;
    NSString *hidden = each.shown && !each.shown(row)
        ? [NSString stringWithFormat:@"%@ is off while %@", each.title,
                                     each.hiddenSays ?: @"it isn't offered for this session"]
        : nil;
    if (each.lasts == SwitchLastsWorkspace) {
        NSString *folder = FolderFor(each, row);
        *waits = folder && FileOf(sessionId) && self.keptWaiting[folder][each.key] && row.pid > 0;
        if (!*waits) return nil;
        NSString *no = hidden ?: each.whyNot ? each.whyNot(row) : nil;
        return no ?: ProcessStartedAt(row.pid) ? nil : @"This session's process has ended";
    }
    NSDictionary *record = FileOf(sessionId) ? AsRecord(self.waiting[sessionId][each.key]) : nil;
    *waits = record != nil;
    if (!record) return nil;
    return hidden
        ?: AsNumber(record[@"pid"]).intValue != row.pid
        ? [NSString stringWithFormat:@"%@ was ticked in another process than the one this row follows now", each.title]
        : Ended(each, record, row) ?: (each.whyNot ? each.whyNot(row) : nil);
}

- (NSArray<SessionSwitch *> *)bringableFor:(Row *)row among:(NSArray<SessionSwitch *> *)switches
                                        why:(NSString **)why {
    // Only those offered for the row (waitingFor:) come back, and the reason is one of theirs, so it's never one for a
    // switch the item or notice doesn't name. With none offered, one that waits but isn't offered says why: the row
    // may have changed since the menu was drawn (no longer the lead's, say).
    NSArray<SessionSwitch *> *offered = [self waitingFor:row];
    NSMutableArray<SessionSwitch *> *able = [NSMutableArray array];
    NSString *first = nil, *notOffered = nil;
    BOOL any = NO;
    for (SessionSwitch *each in switches ?: self.switches) {
        BOOL waits = NO;
        NSString *no = [self whyNotBack:each row:row waits:&waits];
        // One not offered with nothing against it is one already on again: it doesn't wait.
        if (!waits || (![offered containsObject:each] && !no)) continue;
        any = YES;
        if (![offered containsObject:each]) notOffered = notOffered ?: no;
        else if (no) first = first ?: no;
        else [able addObject:each];
    }
    if (why) *why = first ?: able.count ? nil : notOffered ?: any ? nil
        : @"Nothing is waiting to be turned back on for this session";
    return able;
}

- (NSArray<SessionSwitch *> *)bringBack:(Row *)row why:(NSString **)why {
    NSString *sessionId = row.sessionId;
    NSArray<SessionSwitch *> *brought = [self bringableFor:row among:nil why:why];
    if (!brought.count) return @[];
    long long now = (long long)(NSDate.date.timeIntervalSince1970 * 1000);
    for (SessionSwitch *each in brought) {
        if (each.lasts == SwitchLastsWorkspace) {
            // Given in the row you pressed on, whatever the file said, so the next session to hold it is told.
            NSString *folder = FolderFor(each, row);
            if (!self.kept[folder]) self.kept[folder] = [NSMutableDictionary dictionary];
            self.kept[folder][each.key] = @{@"at": @(now), @"held": @(now), @"session": sessionId, @"pid": @(row.pid),
                                            @"processStart": @(ProcessStartedAt(row.pid))};
            [self.keptWaiting[folder] removeObjectForKey:each.key];
            if (!self.keptWaiting[folder].count) [self.keptWaiting removeObjectForKey:folder];
            continue;
        }
        NSMutableDictionary *records = self.waiting[sessionId];
        NSDictionary *record = AsRecord(records[each.key]);
        NSMutableDictionary *kept = [NSMutableDictionary dictionary];
        kept[@"at"] = @(now);
        for (NSString *field in @[@"pid", @"processStart"])
            if (AsNumber(record[field])) kept[field] = AsNumber(record[field]);
        if (AsNumber(record[@"count"])) kept[@"count"] = @(MAX(AsNumber(record[@"count"]).integerValue, 0));
        if (AsText(record[@"bound"])) kept[@"bound"] = AsText(record[@"bound"]);
        if (!self.inMemory[sessionId]) self.inMemory[sessionId] = [NSMutableDictionary dictionary];
        self.inMemory[sessionId][each.key] = kept;
        [records removeObjectForKey:each.key];
        if (records && !records.count) [self.waiting removeObjectForKey:sessionId];
    }
    [self writeTicked];
    for (SessionSwitch *each in brought) {
        PanelLog(@"%@ -> %@ on, brought back after Whozmove restarted", sessionId, each.title);
        if (each.changed) each.changed(sessionId, YES);
    }
    return brought;
}

- (void)endRun:(BOOL)restarting {
    if (restarting) return;
    // A Quit forgets what one session had, and leaves what's kept for folders to be offered back by the next copy, as
    // you chose; with none, the file goes.
    [self.waiting removeAllObjects];
    [self.inMemory removeAllObjects];
    // A file that can't be written then is taken away, or emptied where it lies, as for an untick: what one session had
    // must never be offered after a Quit.
    if (!(self.kept.count || self.keptWaiting.count) || ![self writeTicked])
        if (![self removeTicked]) [self emptyTicked];
    // Nothing writes it again as the app closes.
    self.tickedPath = nil;
}

- (NSString *)keptFolder:(NSString *)key for:(Row *)row {
    SessionSwitch *each = [self switchWithKey:key];
    NSString *folder = each.lasts == SwitchLastsWorkspace ? FolderFor(each, row) : nil;
    return folder && (self.kept[folder][key] || self.keptWaiting[folder][key]) ? folder : nil;
}

- (NSDictionary *)tickedIn:(NSString *)key for:(Row *)row {
    SessionSwitch *each = [self switchWithKey:key];
    NSString *folder = each.lasts == SwitchLastsWorkspace ? FolderFor(each, row) : nil;
    NSDictionary *record = folder ? AsRecord(self.kept[folder][key]) : nil;
    return record ? @{@"session": record[@"session"] ?: @"", @"pid": record[@"pid"] ?: @0} : nil;
}

+ (NSString *)namesOf:(NSArray<SessionSwitch *> *)switches {
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    for (SessionSwitch *each in switches) [titles addObject:each.title];
    if (titles.count < 2) return titles.firstObject ?: @"";
    NSString *last = titles.lastObject;
    [titles removeLastObject];
    return [NSString stringWithFormat:@"%@ and %@", [titles componentsJoinedByString:@", "], last];
}

- (void)rowsListed:(NSArray<Row *> *)rows {
    if (self.tickedUnsaved) [self writeTicked];
    [self noteHeld:rows];
    [self endInMemory:rows];
    [self endWaiting:rows];
    [self endHidden:rows];
    NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
    if (self.core.printing || now - self.prunedAt < kPruneEvery) return;
    self.prunedAt = now;
    NSMutableDictionary<NSString *, Row *> *listed = [NSMutableDictionary dictionary];
    for (Row *row in rows)
        if (row.sessionId) listed[row.sessionId] = row;
    NSString *folder = AppDir(@"allowed");
    NSFileManager *files = NSFileManager.defaultManager;
    for (NSString *name in [files contentsOfDirectoryAtPath:folder error:nil]) {
        if (![name.pathExtension isEqualToString:@"json"]) continue;
        NSString *sessionId = name.stringByDeletingPathExtension;
        NSDictionary *records = RecordsOf(sessionId);
        Row *row = listed[sessionId];
        NSDate *changed = [files attributesOfItemAtPath:[folder stringByAppendingPathComponent:name]
                                                  error:nil].fileModificationDate;
        BOOL gone = !row && changed && -changed.timeIntervalSinceNow > kKeptAfterGone;
        NSMutableDictionary *kept = [records mutableCopy];
        NSMutableArray<SessionSwitch *> *ended = [NSMutableArray array];
        for (NSString *key in records) {
            SessionSwitch *each = [self switchWithKey:key];
            NSDictionary *record = AsRecord(records[key]);
            if (each && record && !gone && !Ended(each, record, row)) continue;
            [kept removeObjectForKey:key];
            if (each) [ended addObject:each];
        }
        if (kept.count == records.count || !WriteRecords(sessionId, kept)) continue;
        for (SessionSwitch *each in ended) {
            PanelLog(@"%@ -> %@ ended", sessionId, each.title);
            if (each.changed) each.changed(sessionId, NO);
        }
    }
}

@end
