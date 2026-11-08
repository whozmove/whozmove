// Talking: who records from a microphone, read the moment a process starts or stops recording, or a microphone starts
// or stops (CoreAudio calls back at once for each); and, in case it doesn't for some process, looked at four times a
// second while a recording is going, and once a second while a microphone runs with none. Each recording is judged
// once, as it's first seen, by what was in front then: dictation types into the app in front, so what was in front as
// it began says who it's for. What's read off CoreAudio and the process table is read on a queue of its own; the
// judging and all the state are on the main thread.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import "Talking.h"
#import "Core.h"
#import "Focus.h"
#import "Rows.h"
#import "Row.h"
#import "Audio.h"
#import "Files.h"
#import "Log.h"
#import "Processes.h"

// How often who records is looked at besides, while a recording is going, and while a microphone runs with none (a
// headset runs for its sound too).
static const NSTimeInterval kLookWhileRecording = 0.25, kLookWhileRunning = 1;

// Whether a host holds sessions as conversations of its own (Claude Desktop), and they're tracked.
static BOOL Tracking(id<Host> host) {
    return [host conformsToProtocol:@protocol(ConversationHost)] && ((id<ConversationHost>)host).tracked;
}

@interface Talking ()
@property (weak) Core *core;
@property (strong) dispatch_queue_t queue;
@property (strong) NSMutableArray *followers;
@property (copy) dispatch_block_t stopListening;
@property (strong) dispatch_source_t looks;     // on the queue, while a microphone runs
@property (assign) NSTimeInterval lookingEvery; // on the queue: how often they look, 0 for not at all
// Each recording seen, by pid: why it counts, or NSNull when it doesn't.
@property (strong) NSMutableDictionary<NSNumber *, id> *recordings;
@property (assign) BOOL talking;
@end

@implementation Talking

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.queue = dispatch_queue_create("whozmove.talking", DISPATCH_QUEUE_SERIAL);
    self.followers = [NSMutableArray array];
    self.recordings = [NSMutableDictionary dictionary];
    return self;
}

- (id)follow:(void (^)(BOOL))changed {
    id follower = [changed copy];
    [self.followers addObject:follower];
    if (self.followers.count == 1) [self listen];
    return follower;
}

- (void)unfollow:(id)follower {
    if (!follower || ![self.followers containsObject:follower]) return;
    [self.followers removeObject:follower];
    if (self.followers.count) return;
    if (self.stopListening) self.stopListening();
    self.stopListening = nil;
    dispatch_async(self.queue, ^{ [self lookEvery:0]; });
    [self.recordings removeAllObjects];
    self.talking = NO;
}

// What's recording when listening begins was going already, so only a session's own voice or an app's that holds
// sessions counts among it.
- (void)listen {
    if (self.core.printing) return;
    if (@available(macOS 14.0, *)) {} else return;
    __weak typeof(self) weakSelf = self;
    self.stopListening = ListenToMicrophones(self.queue, ^{ [weakSelf look:NO]; });
    dispatch_async(self.queue, ^{ [weakSelf look:YES]; });
}

// On the queue: who records now, each with its parent and its program, handed to the main thread.
- (void)look:(BOOL)first {
    NSArray<NSNumber *> *pids = MicrophoneRecorders() ?: @[];
    [self lookEvery:pids.count ? kLookWhileRecording : MicrophoneInUse() ? kLookWhileRunning : 0];
    NSMutableArray<NSDictionary *> *recording = [NSMutableArray array];
    for (NSNumber *pid in pids)
        [recording addObject:@{@"pid": pid, @"parent": @(ProcessParent(pid.intValue)),
                               @"path": ProcessPath(pid.intValue) ?: @""}];
    dispatch_async(dispatch_get_main_queue(), ^{ [self saw:recording going:first]; });
}

// On the queue: looks every `seconds` from now, or, for 0, not at all.
- (void)lookEvery:(NSTimeInterval)seconds {
    if (seconds == self.lookingEvery) return;
    self.lookingEvery = seconds;
    if (self.looks) dispatch_source_cancel(self.looks);
    self.looks = nil;
    if (!seconds) return;
    __weak typeof(self) weakSelf = self;
    self.looks = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.queue);
    dispatch_source_set_timer(self.looks, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)),
                              (uint64_t)(seconds * NSEC_PER_SEC), (uint64_t)(0.05 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(self.looks, ^{ [weakSelf look:NO]; });
    dispatch_resume(self.looks);
}

// On the main thread: a recording seen for the first time is judged by what's in front now, as it has only just
// begun; one that has stopped is forgotten.
- (void)saw:(NSArray<NSDictionary *> *)recording going:(BOOL)going {
    if (!self.followers.count) return;
    NSMutableDictionary<NSNumber *, id> *now = [NSMutableDictionary dictionary];
    for (NSDictionary *each in recording) {
        id why = self.recordings[each[@"pid"]];
        if (!why) {
            NSMutableDictionary *process = [each mutableCopy];
            process[@"app"] = [self.core appOf:[each[@"pid"] intValue]].bundleIdentifier ?: @"";
            NSDictionary *then = @{@"front": NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier ?: @"",
                                   @"tab": [self.core.focus terminalSessionInFront] ?: @"",
                                   @"keyboard": @(NSApp.keyWindow != nil), @"going": @(going)};
            why = [self whyCounts:process then:then rows:self.core.rows.byId.allValues] ?: NSNull.null;
            // Only a recording that counts is logged, by why: which apps record otherwise (a call) is no one's
            // business.
            if (why != NSNull.null) PanelLog(@"talking to an agent: a recording (%@)", why);
        }
        now[each[@"pid"]] = why;
    }
    self.recordings = now;
    BOOL talking = NO;
    for (id why in now.allValues) talking = talking || why != NSNull.null;
    if (talking == self.talking) return;
    self.talking = talking;
    for (void (^changed)(BOOL) in [self.followers copy]) changed(talking);
}

- (NSString *)whyCounts:(NSDictionary *)recording then:(NSDictionary *)then rows:(NSArray<Row *> *)rows {
    pid_t pid = [AsNumber(recording[@"pid"]) intValue], parent = [AsNumber(recording[@"parent"]) intValue];
    NSString *path = AsText(recording[@"path"]) ?: @"";
    for (id<AgentVoice> agent in [self.core agentsThat:@protocol(AgentVoice)])
        if ([agent takesVoice:pid parent:parent path:path among:rows]) return @"voice";
    if (Tracking([self.core hostFor:AsText(recording[@"app"])])) return @"app";
    if ([AsNumber(then[@"going"]) boolValue]) return nil;
    if ([AsNumber(then[@"keyboard"]) boolValue]) return @"panel";
    if (Tracking([self.core hostFor:AsText(then[@"front"])]) || AsText(then[@"tab"]).length) return @"front";
    return nil;
}

@end
