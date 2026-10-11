// Sessions: running sessions and recent Claude Desktop conversations, as the rows the panel shows.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Sessions.h"
#import "DesktopConversations.h"
#import "Row.h"
#import "Log.h"
#import "Files.h"
#import "Processes.h"
#import "Asks.h"
#import "Git.h"
#import "Upstream.h"

// Claude Desktop conversations with no running process are listed if active this recently.
static const NSTimeInterval kRecentConversationWindow = 3 * 24 * 3600;

@interface Sessions ()
@property (strong) DesktopConversations *conversations;
@property (copy) NSString *lastFocusTrace;  // what the log last said about the open conversation; on the queue only
@property (strong) dispatch_queue_t queue;
@end

@implementation Sessions

- (instancetype)initWithConversations:(DesktopConversations *)conversations {
    if (!(self = [super init])) return nil;
    self.conversations = conversations;
    self.queue = dispatch_queue_create("whozmove.sessions", DISPATCH_QUEUE_SERIAL);
    return self;
}

// An exception left to escape the queue would end the app, so one is logged instead, and the next read tries again.
- (void)read:(void (^)(NSArray<Row *> *rows))done {
    dispatch_async(self.queue, ^{
        NSArray<Row *> *rows = nil;
        @try {
            rows = [self list];
        } @catch (NSException *e) {
            LogProblem([NSString stringWithFormat:@"sessions not read: %@: %@", e.name, e.reason]);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            done(rows);
        });
    });
}

// Running sessions from Claude Code's registry, plus recent Claude Desktop conversations whose process isn't
// running (none are, once Claude Desktop quits), which come back with status "closed". Desktop sessions also
// carry Claude's own activityAt (the last real activity) and lastFocusedAt (when it was last looked at in
// Claude), because the registry's statusUpdatedAt moves whenever a process merely starts.
- (NSArray<Row *> *)list {
    NSString *registry = ClaudeDir(kClaudeCodeRegistry);
    NSArray<NSDictionary *> *conversations = [self.conversations all];
    NSMutableDictionary<NSString *, NSDictionary *> *conversationById = [NSMutableDictionary dictionary];
    for (NSDictionary *c in conversations) if (c[@"sessionId"]) conversationById[c[@"sessionId"]] = c;

    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *running = [NSMutableSet set];
    for (NSString *file in [NSFileManager.defaultManager contentsOfDirectoryAtPath:registry error:nil]) {
        if (![file.pathExtension isEqualToString:@"json"]) continue;
        NSDictionary *s = ReadJSON([registry stringByAppendingPathComponent:file]);
        if (![s isKindOfClass:NSDictionary.class] || !ProcessAlive([s[@"pid"] intValue])) continue;
        Row *row = [[Row alloc] initWithFields:s];
        if (row.sessionId) [running addObject:row.sessionId];
        NSDictionary *c = row.hostSessionId ? conversationById[row.hostSessionId] : nil;
        if (c) {
            [running addObject:row.hostSessionId];
            [self take:c into:row];
        }
        [out addObject:[self withContext:row]];
    }

    // The conversation open in Claude Desktop right now. Claude stamps lastFocusedAt on a conversation when it's
    // switched to, but saves the file a couple of seconds later, while its log has the switch at once. Whichever
    // is newer wins (the log's clock only has whole seconds).
    NSString *openId = nil;
    double latestFocus = 0;
    for (NSDictionary *c in conversations)
        if ([c[@"lastFocusedAt"] doubleValue] > latestFocus) {
            latestFocus = [c[@"lastFocusedAt"] doubleValue];
            openId = c[@"sessionId"];
        }
    [self.conversations readFocusLog];
    if (self.conversations.loggedFocusAt > 0 && self.conversations.loggedFocusAt >= latestFocus - 1000)
        openId = self.conversations.loggedFocusId;  // nil: nothing open
    BOOL claudeRunning =
        [NSRunningApplication runningApplicationsWithBundleIdentifier:kClaudeDesktopAppId].count > 0;
    if (!claudeRunning) openId = nil;

    [out addObjectsFromArray:[self stoppedConversations:conversations running:running open:openId]];

    BOOL marked = NO;
    for (Row *row in out)
        if (openId && [row.hostSessionId isEqual:openId]) { row.focused = YES; marked = YES; }
    NSString *trace = [NSString stringWithFormat:@"%@ %@", openId ?: @"none", marked ? @"marked" : @"no row"];
    if (![trace isEqualToString:self.lastFocusTrace]) {
        PanelLog(@"open in Claude: %@ (log %@, files %@)", trace, self.conversations.loggedFocusId ?: @"-",
                 @(latestFocus));
        self.lastFocusTrace = trace;
    }

    NSDictionary *asks = PendingAsks();
    for (Row *row in out)
        if (row.sessionId && asks[row.sessionId]) row.ask = asks[row.sessionId];
    return out;
}

// Recent Claude Desktop conversations with no running process, as rows with status "closed". The one open in
// Claude is listed however old it is, because it has no process for a moment after it's switched to.
- (NSArray *)stoppedConversations:(NSArray<NSDictionary *> *)conversations running:(NSSet *)running
                              open:(NSString *)openId {
    NSMutableArray *out = [NSMutableArray array];
    double cutoff = (NSDate.date.timeIntervalSince1970 - kRecentConversationWindow) * 1000;
    for (NSDictionary *c in conversations) {
        if (![c[@"sessionId"] isKindOfClass:NSString.class]) continue;
        // `running` holds the running sessions' ids and their Claude Desktop ids. A conversation that's running,
        // in Claude or resumed in a terminal (the same session id), is listed once, as that session.
        if ([c[@"isArchived"] boolValue] || [running containsObject:c[@"sessionId"]]
            || [running containsObject:c[@"cliSessionId"] ?: @""])
            continue;
        if ([c[@"lastActivityAt"] doubleValue] < cutoff && ![c[@"sessionId"] isEqual:openId]) continue;
        NSString *cwd = c[@"cwd"];
        if (![cwd isKindOfClass:NSString.class] || ![NSFileManager.defaultManager fileExistsAtPath:cwd])
            cwd = c[@"originCwd"];  // e.g. a removed worktree
        if (![cwd isKindOfClass:NSString.class]) continue;
        Row *row = [Row new];
        row.sessionId = [c[@"cliSessionId"] isKindOfClass:NSString.class] ? c[@"cliSessionId"] : c[@"sessionId"];
        row.hostSessionId = c[@"sessionId"];
        row.name = [c[@"title"] isKindOfClass:NSString.class] ? c[@"title"] : @"Untitled";
        row.cwd = cwd;
        row.entrypoint = @"claude-desktop";
        row.status = @"closed";
        // A new conversation has no activity yet.
        row.statusUpdatedAt = [c[@"lastActivityAt"] isKindOfClass:NSNumber.class] ? c[@"lastActivityAt"] : @0;
        row.activityAt = row.statusUpdatedAt;
        [self take:c into:row];
        [out addObject:[self withContext:row]];
    }
    return out;
}

// What Claude Desktop's own record of a conversation adds to its row.
- (void)take:(NSDictionary *)c into:(Row *)row {
    if ([c[@"lastActivityAt"] isKindOfClass:NSNumber.class]) row.activityAt = c[@"lastActivityAt"];
    if ([c[@"lastFocusedAt"] isKindOfClass:NSNumber.class]) row.lastFocusedAt = c[@"lastFocusedAt"];
    if ([c[@"summaryStatus"] isKindOfClass:NSString.class]) row.summaryStatus = c[@"summaryStatus"];
    row.desktop = c;  // its model, effort and permission mode, for the details line
}

// Adds what the hook recorded (last prompt / reply / notice) and the checkout's branch and worktree.
- (Row *)withContext:(Row *)row {
    NSDictionary *record = row.sessionId
        ? ReadJSON([AppDir(@"sessions")
                    stringByAppendingPathComponent:[row.sessionId stringByAppendingPathExtension:@"json"]])
        : nil;
    if ([record isKindOfClass:NSDictionary.class]) [row takeHookRecord:record];
    if (row.cwd) row.git = GitInfo(row.cwd);
    // The checkout the session last edited files in, when it isn't the one it runs in (from the hook).
    if (row.workRoot && ![row.workRoot isEqual:row.git[@"root"]]) {
        NSDictionary *workGit = GitInfo(row.workRoot);
        if (workGit) row.workGit = workGit;
    }
    return row;
}

@end
