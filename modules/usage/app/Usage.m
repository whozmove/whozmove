// Usage: how much of your Claude plan you've used, in the five-hour session and the week, for the usage card under the
// panel: asked of the agent (AgentUsage; Claude Code's module asks the `claude` command) every few minutes, and its Sign
// in.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Usage.h"
#import "UsageCard.h"
#import "PanelWindow.h"
#import "Files.h"
#import "Log.h"

// How often it's asked: every 3 minutes; again 20 seconds after a window resets, when that comes sooner; every 15
// seconds for 5 minutes after Sign in; from 30 seconds to 15 minutes apart while asking fails; and every 10 minutes
// while there's no `claude` to ask.
static const NSTimeInterval kEvery = 180, kAfterReset = 20, kSignInEvery = 15, kSignInFor = 300, kFirstRetry = 30,
                            kSlowest = 900, kNoClaudeAgain = 600;


@interface Usage ()
@property (strong) UsageCard *card;
@property (strong) PanelWindow *window;
@property (strong) id<AgentUsage> agent;
@property (strong) dispatch_queue_t queue;
@property (assign) BOOL checking;
@property (assign) NSTimeInterval nextAt;          // when it's next asked, in seconds since 1970
@property (assign) NSTimeInterval retryAfter;      // while asking fails, how long until it's asked again
@property (assign) NSTimeInterval signingInUntil;  // after Sign in, asked often until then
@property (assign) BOOL asleep;                    // the screens are
@property (copy) NSDictionary *known;              // what the card's page has, or gets once it loads
@property (copy) NSString *signIn;                 // the command that signs in the agent that answered
@property (copy) NSString *lastState;              // for the log, which says only what changed
@end

@implementation Usage

- (instancetype)initWithCard:(UsageCard *)card window:(PanelWindow *)window agent:(id<AgentUsage>)agent {
    if (!(self = [super init])) return nil;
    self.card = card;
    self.window = window;
    self.agent = agent;
    self.queue = dispatch_queue_create("whozmove.usage", DISPATCH_QUEUE_SERIAL);
    // Asleep, nothing's asked; awake again, it's asked soon (a few seconds, for the network to come back).
    NSNotificationCenter *center = NSWorkspace.sharedWorkspace.notificationCenter;
    __weak typeof(self) weakSelf = self;
    [center addObserverForName:NSWorkspaceScreensDidSleepNotification object:nil queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification *note) { weakSelf.asleep = YES; }];
    for (NSNotificationName woke in @[NSWorkspaceScreensDidWakeNotification, NSWorkspaceDidWakeNotification])
        [center addObserverForName:woke object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            weakSelf.asleep = NO;
            weakSelf.nextAt = MIN(weakSelf.nextAt, NSDate.date.timeIntervalSince1970 + 5);
        }];
    return self;
}

// The time is compared on every tick rather than waited for, so a Mac that slept through a check asks as it wakes.
// Nothing's asked while the panel is hidden; shown again, it's asked straight away if a check came due meanwhile.
- (void)pollIfDue {
    if (self.checking || self.asleep || !self.window.shown) return;
    if (NSDate.date.timeIntervalSince1970 < self.nextAt) return;
    id<AgentUsage> agent = self.agent;
    if (!agent) return [self took:@{@"state": @"none"}];
    self.checking = YES;
    dispatch_async(self.queue, ^{
        NSDictionary *found = nil;
        @try {
            found = [agent askUsage];
        } @catch (NSException *e) {
            LogProblem([NSString stringWithFormat:@"plan usage not asked: %@: %@", e.name, e.reason]);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.checking = NO;
            [self took:found ?: @{@"state": @"failed"}];
        });
    });
}

- (void)resend {
    if (self.known) [self.card call:@"setUsage" with:@[self.known]];
}

// On the main thread: what was found goes to the card's page, and when to ask next is worked out.
- (void)took:(NSDictionary *)found {
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSString *state = found[@"state"];
    if (![state isEqual:self.lastState]) {
        PanelLog(@"plan usage: %@", state);
        self.lastState = state;
    }
    if ([state isEqual:@"failed"]) {
        // What was known stays on the card (its times keep counting); nothing new is said.
        self.retryAfter = self.retryAfter ? MIN(self.retryAfter * 2, kSlowest) : kFirstRetry;
        self.nextAt = now + self.retryAfter;
    } else {
        self.retryAfter = 0;
        if (found[@"signIn"]) self.signIn = found[@"signIn"];
        NSMutableDictionary *usage = [found mutableCopy];
        [usage removeObjectForKey:@"signIn"];
        usage[@"checkedAt"] = @(now * 1000);
        self.known = usage;
        if (self.card.ready) [self.card call:@"setUsage" with:@[usage]];
        self.nextAt = now + ([state isEqual:@"none"] ? kNoClaudeAgain : kEvery);
        for (NSString *window in @[@"session", @"week"]) {
            NSTimeInterval resetsAt = [usage[window][@"resetsAt"] doubleValue] / 1000;
            if (resetsAt > now) self.nextAt = MIN(self.nextAt, resetsAt + kAfterReset);
        }
    }
    if (self.signingInUntil > now) {
        if ([state isEqual:@"ok"] || [state isEqual:@"other"]) self.signingInUntil = 0;
        else self.nextAt = MIN(self.nextAt, now + kSignInEvery);
    }
}

#pragma mark Signing in

- (void)signInWith:(id<CommandHost>)terminal {
    if (!self.signIn || !terminal) return;
    [terminal newTabIn:Home() running:self.signIn named:[@"Sign in to " stringByAppendingString:self.agent.name]
               forward:YES];
    PanelLog(@"plan usage: signing in, in %@", terminal.name);
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    self.signingInUntil = now + kSignInFor;
    self.nextAt = MIN(self.nextAt, now + kSignInEvery);
}

@end
