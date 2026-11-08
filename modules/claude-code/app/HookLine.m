// HookLine: each hook's connection, kept for as long as its request waits: what it asked, from which process, and
// whether it has been answered. All of it on the line's own queue; the rest of the app asks it from any thread.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "HookLine.h"
#import "Files.h"
#import "Text.h"
#import "Log.h"
#import "UnixSockets.h"
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

// The most a request may be (a tool's input can hold a whole file), how many of the last connections the tests are told
// about, and how long a connection may take to say what it asks.
static const NSUInteger kLongestLine = 8 * 1024 * 1024, kToldKept = 50;
static const int64_t kAskWithinSeconds = 5;
// How many requests that have gone are remembered, with why, and how long the hook waits on its line at most
// (WAIT_LIMIT in the hook, 3500 s), less a little, so one gone after that is known to have waited its hour out.
static const NSUInteger kGoneKept = 100;
static const double kWaitedOutMs = 3480 * 1000.0;

// One hook's connection: its process, as macOS names it, and what it asked over it (`kind` ask or switch; words is
// answered at once), once it has.
@interface HookConnection : NSObject
@property (assign) int fd;
@property (assign) pid_t pid;
@property (strong) dispatch_source_t source;
@property (strong) NSMutableData *buffer;
@property (copy) NSString *kind;
@property (strong) NSMutableDictionary *asked;
@property (assign) BOOL answered;
// Let go as its hook wasn't reading, so Claude's own prompt has it.
@property (assign) BOOL letGo;
// When it was last held, as you answered it (ms), whether or not it goes by itself; 0 for never.
@property (assign) double heldAt;
@end

@implementation HookConnection
@end

@interface HookLine ()
@property (strong) dispatch_queue_t queue;
@property (strong) dispatch_source_t listener;
@property (copy) NSString *path;
@property (assign) ino_t inode;
@property (copy) NSString *(^sessionOf)(pid_t pid);
@property (strong) NSMutableArray<HookConnection *> *connections;
@property (strong) NSMutableArray<NSString *> *toldSoFar;
// The requests that have gone lately, by id: why (`answered`, `waitedOut` or `gone`), oldest first in `goneOrder`.
@property (strong) NSMutableDictionary<NSString *, NSString *> *goneWhy;
@property (strong) NSMutableArray<NSString *> *goneOrder;
@end

@implementation HookLine

+ (instancetype)shared {
    static HookLine *line;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ line = [HookLine new]; });
    return line;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.queue = dispatch_queue_create("whozmove.hook-line", DISPATCH_QUEUE_SERIAL);
    self.connections = [NSMutableArray array];
    self.toldSoFar = [NSMutableArray array];
    self.goneWhy = [NSMutableDictionary dictionary];
    self.goneOrder = [NSMutableArray array];
    return self;
}

- (BOOL)listenAt:(NSString *)path sessionOf:(NSString *(^)(pid_t pid))sessionOf {
    [self stop];
    self.sessionOf = sessionOf;
    __weak typeof(self) weakSelf = self;
    ino_t inode = 0;
    dispatch_source_t listener = ListenAtSocket(path, self.queue, @"requests over the hook's line", &inode,
                                                ^(int fd, pid_t pid) { [weakSelf take:fd from:pid]; });
    if (!listener) return NO;
    self.path = path;
    self.inode = inode;
    dispatch_sync(self.queue, ^{ self.listener = listener; });
    return YES;
}

- (void)keepListening {
    if (self.path && !SocketStillAt(self.path, self.inode)) {
        LogProblem(@"the hook's line was taken away: listening again");
        [self listenAt:self.path sessionOf:self.sessionOf];
    }
}

- (void)stop {
    dispatch_sync(self.queue, ^{
        if (self.listener) dispatch_source_cancel(self.listener);
        self.listener = nil;
        for (HookConnection *each in self.connections) dispatch_source_cancel(each.source);
        [self.connections removeAllObjects];
    });
    if (self.path && SocketStillAt(self.path, self.inode)) unlink(self.path.fileSystemRepresentation);
}

// On the queue: a connection from a process running as you, which macOS names. One that hasn't said what it asks within
// a few seconds is let go.
- (void)take:(int)client from:(pid_t)pid {
    HookConnection *connection = [HookConnection new];
    connection.fd = client;
    connection.pid = pid;
    connection.buffer = [NSMutableData data];
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)client, 0, self.queue);
    __weak typeof(self) weakSelf = self;
    __weak HookConnection *weakConnection = connection;
    dispatch_source_set_event_handler(source, ^{ [weakSelf read:weakConnection]; });
    dispatch_source_set_cancel_handler(source, ^{ close(client); });
    connection.source = source;
    [self.connections addObject:connection];
    dispatch_resume(source);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kAskWithinSeconds * NSEC_PER_SEC), self.queue, ^{
        HookConnection *still = weakConnection;
        if (still && !still.kind) [weakSelf drop:still];
    });
}

// On the queue: what's come in, line by line. The connection closing (the hook's gone: answered, in the panel or in
// Claude, or stopped) is the request going.
- (void)read:(HookConnection *)connection {
    if (!connection) return;
    char chunk[65536];
    ssize_t got = recv(connection.fd, chunk, sizeof chunk, 0);
    if (got <= 0 || connection.buffer.length + (NSUInteger)got > kLongestLine) {
        [self drop:connection];
        return;
    }
    [connection.buffer appendBytes:chunk length:(NSUInteger)got];
    for (;;) {
        const char *bytes = connection.buffer.bytes;
        const char *end = memchr(bytes, '\n', connection.buffer.length);
        if (!end) return;
        NSUInteger length = (NSUInteger)(end - bytes);
        NSData *line = [connection.buffer subdataWithRange:NSMakeRange(0, length)];
        [connection.buffer replaceBytesInRange:NSMakeRange(0, length + 1) withBytes:NULL length:0];
        NSDictionary *message = AsRecord([NSJSONSerialization JSONObjectWithData:line options:0 error:nil]);
        if (![self heard:message on:connection]) return;
    }
}

// On the queue: one message from a hook; NO once the connection has gone. Its first says what it asks, which the
// panel takes only from a process that runs in the session it names; the rest change when an ask goes by itself.
- (BOOL)heard:(NSDictionary *)message on:(HookConnection *)connection {
    if (!connection.kind) {
        NSString *kind = AsRecord(message[@"ask"]) ? @"ask" : AsRecord(message[@"switch"]) ? @"switch"
                       : AsRecord(message[@"words"]) ? @"words" : nil;
        NSMutableDictionary *asked = [AsRecord(message[kind ?: @""]) mutableCopy];
        NSString *sessionId = AsText(asked[@"sessionId"]);
        NSString *runsIn = self.sessionOf ? self.sessionOf(connection.pid) : nil;
        NSString *why = !kind ? @"it asked nothing the panel knows"
            : !IsPlainId(sessionId, 128) ? @"it named no session"
            : ([kind isEqual:@"ask"] && !IsPlainId(AsText(asked[@"id"]), 64)) ? @"its request has no id"
            : ([kind isEqual:@"ask"] && [self askConnection:AsText(asked[@"id"])]) ? @"its request's id is another's"
            : ![runsIn isEqual:sessionId] ? [NSString stringWithFormat:@"its process runs in %@, not %@",
                                                                       runsIn ?: @"no session", sessionId]
            : nil;
        if (why) {
            [self tell:[@"refused: " stringByAppendingString:why]];
            [self write:@{@"refused": why} to:connection];
            [self drop:connection];
            return NO;
        }
        // The words hook asks once: what it's handed goes down the line, which then closes.
        if ([kind isEqual:@"words"]) {
            NSString *event = AsText(asked[@"event"]);
            NSString *words = self.wordsFor && [@[@"PostToolBatch", @"Stop"] containsObject:event ?: @""]
                ? self.wordsFor(sessionId, connection.pid, event) : nil;
            [self tell:[NSString stringWithFormat:@"words asked by %@: %@", sessionId, words ? @"handed" : @"none"]];
            [self write:@{@"words": words ?: @""} to:connection];
            [self drop:connection];
            return NO;
        }
        asked[@"pid"] = @(connection.pid);
        connection.kind = kind;
        connection.asked = asked;
        [self tell:[NSString stringWithFormat:@"%@ asked by %@", kind, sessionId]];
        return YES;
    }
    if ([connection.kind isEqual:@"ask"] && message[@"expiresAt"]) {
        NSNumber *at = AsNumber(message[@"expiresAt"]);
        if (at) connection.asked[@"expiresAt"] = at;
        else [connection.asked removeObjectForKey:@"expiresAt"];
    }
    return YES;
}

- (void)drop:(HookConnection *)connection {
    if (![self.connections containsObject:connection]) return;
    dispatch_source_cancel(connection.source);
    [self.connections removeObject:connection];
    NSString *askId = [connection.kind isEqual:@"ask"] ? AsText(connection.asked[@"id"]) : nil;
    if (!askId) return;
    double waited = NSDate.date.timeIntervalSince1970 * 1000 - AsNumber(connection.asked[@"at"]).doubleValue;
    self.goneWhy[askId] = connection.letGo ? @"letGo" : connection.answered ? @"answered"
        : waited >= kWaitedOutMs ? @"waitedOut" : @"gone";
    [self.goneOrder addObject:askId];
    if (self.goneOrder.count > kGoneKept) {
        [self.goneWhy removeObjectForKey:self.goneOrder.firstObject];
        [self.goneOrder removeObjectAtIndex:0];
    }
}

// Never waits: a hook that isn't reading (its session paused, say) mustn't hold up the panel, so a line that can't take
// all of a message now is let go, and its hook steps aside for Claude's own prompt. NO then.
- (BOOL)write:(NSDictionary *)message to:(HookConnection *)connection {
    NSMutableData *line = [[NSJSONSerialization dataWithJSONObject:message options:0 error:nil] mutableCopy];
    if (!line) return NO;
    [line appendBytes:"\n" length:1];
    if (SendWithoutWaiting(connection.fd, line)) return YES;
    [self tell:@"let go: its hook isn't reading"];
    connection.letGo = YES;
    [self drop:connection];
    return NO;
}

- (void)tell:(NSString *)what {
    [self.toldSoFar addObject:what];
    if (self.toldSoFar.count > kToldKept) [self.toldSoFar removeObjectAtIndex:0];
}

- (NSArray<NSString *> *)told {
    __block NSArray *told;
    dispatch_sync(self.queue, ^{ told = [self.toldSoFar copy]; });
    return told;
}

- (NSDictionary<NSString *, NSDictionary *> *)requests {
    __block NSMutableDictionary *requests = [NSMutableDictionary dictionary];
    dispatch_sync(self.queue, ^{
        for (HookConnection *each in self.connections)
            if ([each.kind isEqual:@"ask"]) requests[each.asked[@"id"]] = [each.asked copy];
    });
    return requests;
}

// The connection of a request, on the queue.
- (HookConnection *)askConnection:(NSString *)askId {
    for (HookConnection *each in self.connections)
        if ([each.kind isEqual:@"ask"] && [each.asked[@"id"] isEqual:askId]) return each;
    return nil;
}

- (BOOL)answer:(NSString *)askId with:(NSDictionary *)reply {
    __block BOOL done = NO;
    dispatch_sync(self.queue, ^{
        HookConnection *connection = [self askConnection:askId];
        if (!connection || connection.answered) return;
        connection.answered = YES;
        done = [self write:@{@"answer": reply} to:connection];
        if (done) [self tell:[@"answered " stringByAppendingString:askId]];
        else connection.answered = NO;
    });
    return done;
}

// Every request's hold is kept, so the panel can tell you're answering it; only one that goes by itself is told down its
// line, as only its hook has a use for it.
- (BOOL)hold:(NSString *)askId at:(double)at {
    __block BOOL done = NO;
    dispatch_sync(self.queue, ^{
        HookConnection *connection = [self askConnection:askId];
        if (!connection || connection.answered) return;
        connection.heldAt = MAX(connection.heldAt, at);
        done = !connection.asked[@"expiresAt"] || [self write:@{@"held": @(at)} to:connection];
    });
    return done;
}

- (double)heldAt:(NSString *)askId {
    __block double at = 0;
    dispatch_sync(self.queue, ^{ at = [self askConnection:askId].heldAt; });
    return at;
}

- (BOOL)stillAsking:(NSString *)askId {
    __block BOOL asking = NO;
    dispatch_sync(self.queue, ^{
        HookConnection *connection = [self askConnection:askId];
        asking = connection && !connection.answered;
    });
    return asking;
}

- (NSString *)whyGone:(NSString *)askId {
    __block NSString *why;
    dispatch_sync(self.queue, ^{ why = askId ? self.goneWhy[askId] : nil; });
    return why;
}

// The newest question for a session, while its hook waits.
- (HookConnection *)switchConnection:(NSString *)sessionId {
    HookConnection *found = nil;
    for (HookConnection *each in self.connections)
        if ([each.kind isEqual:@"switch"] && [each.asked[@"sessionId"] isEqual:sessionId] && !each.answered)
            found = each;
    return found;
}

- (NSDictionary *)switchQuestionFor:(NSString *)sessionId {
    __block NSDictionary *question;
    dispatch_sync(self.queue, ^{ question = [[self switchConnection:sessionId].asked copy]; });
    return question;
}

- (BOOL)answerSwitch:(NSString *)sessionId allow:(BOOL)allow {
    __block BOOL done = NO;
    dispatch_sync(self.queue, ^{
        HookConnection *connection = [self switchConnection:sessionId];
        if (!connection) return;
        connection.answered = YES;
        done = [self write:@{@"answer": @{@"allow": @(allow)}} to:connection];
        if (done) [self tell:[NSString stringWithFormat:@"switch for %@ answered", sessionId]];
    });
    return done;
}

@end
