// SessionAsks: the socket a session asks through, and the checks every ask goes through before its module hears it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "SessionAsks.h"
#import "Core.h"
#import "Modules.h"
#import "Allowed.h"
#import "Row.h"
#import "Rows.h"
#import "Files.h"
#import "Log.h"
#import "UnixSockets.h"
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

// The most an ask may be (a note for a plan sent back, base64-encoded, fits), and how long one connection may take to
// send it.
static const NSUInteger kLongestAsk = 16384;
static const int kSendWithinSeconds = 2;
// What's said while the panel can't know who asks yet (it's starting, and hasn't read its sessions) or any more (it's
// closing): a word of its own, so an ask that waits (ask-panel.sh task-answer --wait) waits through it.
static NSString *const kStarting = @"starting: Whozmove is starting up: ask again in a moment";
static NSString *const kClosing = @"starting: Whozmove is closing: ask again once it's back";

@interface SessionAsks ()
@property (weak) Core *core;
@property (strong) dispatch_queue_t queue;
@property (strong) dispatch_source_t source;
@property (copy) NSString *path;
@end

@implementation SessionAsks

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.queue = dispatch_queue_create("whozmove.session-asks", DISPATCH_QUEUE_SERIAL);
    return self;
}

- (BOOL)listenAt:(NSString *)path {
    [self stop];
    __weak typeof(self) weakSelf = self;
    self.source = ListenAtSocket(path, self.queue, @"session asks", NULL, ^(int fd, pid_t pid) {
        [weakSelf take:fd from:pid];
    });
    if (!self.source) return NO;
    self.path = path;
    return YES;
}

- (void)stop {
    if (!self.source) return;
    dispatch_source_cancel(self.source);
    self.source = nil;
    unlink(self.path.fileSystemRepresentation);
}

// On the queue: one connection's line, read until its end (or the most an ask may be, or 2 seconds for all of it, so
// one sending slowly holds up the asks after it no longer than that), from a process running as you, which macOS
// names; answered on the main thread, written back here without waiting on it.
- (void)take:(int)client from:(pid_t)pid {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:kSendWithinSeconds];
    NSMutableData *read = [NSMutableData data];
    char chunk[512];
    while (read.length < kLongestAsk) {
        NSTimeInterval left = until.timeIntervalSinceNow;
        if (left <= 0) break;
        struct timeval wait = {.tv_sec = (time_t)left, .tv_usec = (suseconds_t)((left - floor(left)) * 1e6)};
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &wait, sizeof wait);
        ssize_t got = recv(client, chunk, sizeof chunk, 0);
        if (got <= 0) break;
        [read appendBytes:chunk length:(NSUInteger)got];
        if (memchr(chunk, '\n', (size_t)got)) break;
    }
    // An ask that fills all the room without ending is more than one ask may be: said as such, not as one not
    // understood.
    BOOL tooLong = read.length >= kLongestAsk && !memchr(read.bytes, '\n', read.length);
    NSString *line = tooLong ? @"" : [[NSString alloc] initWithData:read encoding:NSUTF8StringEncoding] ?: @"";
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *answer = tooLong ? @"refused: that's more than one ask may be (16 KB): send less"
            : [weakSelf answer:line from:pid] ?: kClosing;
        NSData *out = [[answer stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
        dispatch_async(weakSelf.queue ?: dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            SendWithoutWaiting(client, out);
            close(client);
        });
    });
}

- (NSString *)answer:(NSString *)line from:(pid_t)pid {
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *message = data ? AsRecord([NSJSONSerialization JSONObjectWithData:data options:0 error:nil]) : nil;
    NSString *word = AsText(message[@"ask"]);
    if (!word) return @"refused: Whozmove didn't understand that";
    SessionAsk *ask = self.core.modules.sessionAsks[word];
    if (!ask) return [NSString stringWithFormat:@"refused: Whozmove can't be asked to %@", Clip(word, 40)];
    if (!self.core.rows.byId) return kStarting;
    pid_t process = 0;
    NSString *notAsker = nil;
    Row *row = [self.core sessionOfProcess:pid found:&process why:&notAsker];
    if (!row)
        return [@"refused: " stringByAppendingString:
                    notAsker ?: @"this doesn't run in one of the sessions Whozmove lists"];
    // One that only shows you something goes in the session's name with no switch to bind it to its process, so the
    // core checks, at the ask, that the process speaking is that session's only one, where it was seen working.
    NSString *notNow = ask.showsOnly ? [self.core whyNot:row asksFrom:pid] : nil;
    if (notNow) {
        PanelLog(@"%@ asked %@: refused: %@", row.sessionId, word, notNow);
        return [@"refused: " stringByAppendingString:notNow];
    }
    // An ask that needs any one of several switches goes on once one is on, and says why the first is off otherwise;
    // one that names no switch never goes on, but one that only shows the user something.
    NSString *why = ask.switchKeys.count || ask.showsOnly ? nil : @"Whozmove can't be asked that without a switch for it";
    NSMutableArray<NSString *> *offs = [NSMutableArray array];
    for (NSString *key in ask.switchKeys) {
        NSString *off = [self.core.allowed whyOff:key for:row from:process];
        if (!off) {
            [offs removeAllObjects];
            break;
        }
        [offs addObject:off];
    }
    if (offs.count) why = [offs componentsJoinedByString:@"; and "];
    NSString *answer = why ? [@"refused: " stringByAppendingString:why] : ask.answer(row, process, message);
    if (!ask.logsItself || why) PanelLog(@"%@ asked %@: %@", row.sessionId, word, answer);
    return answer;
}

@end
