// Usage: how much of your Claude plan you've used, in the five-hour session and the week, for the usage card under the
// panel: asked of the agent (AgentUsage; Claude Code's module asks the `claude` command) every few minutes, and its Sign
// in.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Usage.h"
#import "UsageCard.h"
#import "PanelWindow.h"
#import "Files.h"
#import "Log.h"

// How often it's asked: every 3 minutes while a session works or the card is slid out or open, else every 10; again 20
// seconds after a window resets, when that comes sooner; every 15 seconds for 5 minutes after Sign in; from 30 seconds
// to 15 minutes apart while asking fails; and every 10 minutes while there's no `claude` to ask. Never while you're
// away (no key pressed or pointer moved for 5 minutes): each check starts `claude`, a large program, so with nobody to
// look it costs only energy.
static const NSTimeInterval kEvery = 180, kQuietEvery = 600, kAway = 300, kAfterReset = 20, kSignInEvery = 15,
                            kSignInFor = 300, kFirstRetry = 30, kSlowest = 900, kNoClaudeAgain = 600;

// As you come back, it's due as it would be while busy (3 minutes after the last answer), so the card is right when
// you look, without waiting out the quiet 10 minutes.
BOOL UsageDue(UsageTimes *times, NSTimeInterval now, NSTimeInterval idle, BOOL busy) {
    BOOL away = idle >= kAway;
    if (times->away && !away) times->quietAt = MIN(times->quietAt, times->busyAt);
    times->away = away;
    return !away && now >= (busy ? times->busyAt : times->quietAt);
}

void UsageAnswered(UsageTimes *times, NSString *state, NSArray<NSNumber *> *resets, NSTimeInterval now) {
    if ([state isEqual:@"failed"]) {
        times->retryAfter = times->retryAfter ? MIN(times->retryAfter * 2, kSlowest) : kFirstRetry;
        times->busyAt = times->quietAt = now + times->retryAfter;
    } else {
        times->retryAfter = 0;
        BOOL none = [state isEqual:@"none"];
        times->busyAt = now + (none ? kNoClaudeAgain : kEvery);
        times->quietAt = now + (none ? kNoClaudeAgain : kQuietEvery);
        for (NSNumber *resetsAt in resets)
            if (resetsAt.doubleValue > now) UsageSoon(times, resetsAt.doubleValue + kAfterReset);
    }
    if (times->signingInUntil > now) {
        if ([state isEqual:@"ok"] || [state isEqual:@"other"]) times->signingInUntil = 0;
        else UsageSoon(times, now + kSignInEvery);
    }
}

void UsageSoon(UsageTimes *times, NSTimeInterval at) {
    times->busyAt = MIN(times->busyAt, at);
    times->quietAt = MIN(times->quietAt, at);
}

// The start of the case's stretch (each [from, to) in minutes) that the second `t` is in, in seconds; -1 for none.
static NSTimeInterval StretchStart(NSArray<NSArray<NSNumber *> *> *stretches, NSTimeInterval t) {
    for (NSArray<NSNumber *> *s in stretches)
        if (t >= s[0].doubleValue * 60 && t < s[1].doubleValue * 60) return s[0].doubleValue * 60;
    return -1;
}

// Each case is {name, minutes, away, busy, failing} (stretches of minutes: you left at an `away` stretch's start, a
// session works through `busy`, asking fails through `failing`), with `resetsAt` (the minute a window resets) and
// `signInAt` (the minute Sign in is pressed, signed in a minute later). It ticks every second from 0, answered at once.
int PrintUsageChecks(NSArray<NSString *> *arguments) {
    NSData *data = arguments.count ? [NSData dataWithContentsOfFile:arguments[0]] : nil;
    NSArray<NSDictionary *> *cases = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![cases isKindOfClass:NSArray.class]) {
        fprintf(stderr, "usage: Whozmove --print-usage-checks <cases.json>\n");
        return 1;
    }
    for (NSDictionary *c in cases) {
        UsageTimes times = {0};
        NSMutableArray<NSString *> *checks = [NSMutableArray array];
        NSTimeInterval end = [c[@"minutes"] doubleValue] * 60;
        NSTimeInterval resetsAt = c[@"resetsAt"] ? [c[@"resetsAt"] doubleValue] * 60 : 0;
        NSTimeInterval signInAt = c[@"signInAt"] ? [c[@"signInAt"] doubleValue] * 60 : -1;
        for (NSTimeInterval t = 0; t <= end; t++) {
            if (t == signInAt) {
                times.signingInUntil = t + kSignInFor;
                UsageSoon(&times, t + kSignInEvery);
            }
            NSTimeInterval left = StretchStart(c[@"away"], t);
            if (!UsageDue(&times, t, left < 0 ? 0 : t - left, StretchStart(c[@"busy"], t) >= 0)) continue;
            [checks addObject:[NSString stringWithFormat:@"%d:%02d", (int)t / 60, (int)t % 60]];
            NSString *state = StretchStart(c[@"failing"], t) >= 0 ? @"failed"
                              : signInAt >= 0 && t >= signInAt && t < signInAt + 60 ? @"signedOut" : @"ok";
            UsageAnswered(&times, state, @[@(resetsAt)], t);
        }
        printf("%s: %lu, at %s\n", [c[@"name"] UTF8String], (unsigned long)checks.count,
               [[checks componentsJoinedByString:@" "] UTF8String]);
    }
    // Whether each answer leaves a card, which the panel keeps room under itself for (a failed one changes nothing).
    printf("A card, and room kept for it, after an answer:");
    for (NSString *state in @[@"ok", @"signedOut", @"other", @"none"])
        printf(" %s %s", state.UTF8String, UsageShowsCard(state) ? "yes" : "no");
    printf("\n");
    return 0;
}

void UsageKeepLast(NSDictionary *usage) {
    NSMutableDictionary *last = [NSMutableDictionary dictionaryWithObject:usage[@"checkedAt"] forKey:@"checkedAt"];
    for (NSString *window in @[@"session", @"week"]) {
        NSDictionary *each = AsRecord(usage[window]);
        if (!AsNumber(each[@"used"])) continue;
        last[window] = AsNumber(each[@"resetsAt"]) ? @{@"used": each[@"used"], @"resetsAt": each[@"resetsAt"]}
                                                   : @{@"used": each[@"used"]};
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:last options:NSJSONWritingSortedKeys error:nil];
    [json writeToFile:AppDir(@"usage-last.json") atomically:YES];
}

// `--print-usage-kept <usage.json>`: what's kept of that answer, read back from the file, in a throwaway home only.
int PrintUsageKept(NSArray<NSString *> *arguments) {
    if (HomeIsYourOwn()) {
        fprintf(stderr, "--print-usage-kept changes Whozmove's folder: give it a throwaway HOME\n");
        return 1;
    }
    NSDictionary *usage = arguments.count ? AsRecord(ReadJSON(arguments[0])) : nil;
    if (!usage) return 1;
    [NSFileManager.defaultManager createDirectoryAtPath:AppDir(@"") withIntermediateDirectories:YES attributes:nil
                                                  error:nil];
    UsageKeepLast(usage);
    printf("%s\n", [[NSString stringWithContentsOfFile:AppDir(@"usage-last.json") encoding:NSUTF8StringEncoding
                                                  error:nil] ?: @"(nothing kept)" UTF8String]);
    return 0;
}

NSString *UsageNoTerminal(NSArray<NSString *> *names) {
    NSString *says = @"There's no terminal to sign in from";
    if (!names.count) return says;
    NSString *first = [[names subarrayWithRange:NSMakeRange(0, names.count - 1)] componentsJoinedByString:@", "];
    return [NSString stringWithFormat:@"%@: Whozmove opens %@", says,
                                      first.length ? [NSString stringWithFormat:@"%@ or %@", first, names.lastObject]
                                                   : names.lastObject];
}

NSString *UsageSignInOr(NSString *why, NSString *command) {
    if (!command.length) return why;
    return [NSString stringWithFormat:@"%@%@ Or run %@ in any terminal yourself.", why,
                                      [why hasSuffix:@"."] ? @"" : @".", command];
}

int PrintSignIn(NSArray<NSString *> *names) {
    printf("with no terminal, naming the ones Whozmove opens: %s\n", UsageNoTerminal(names).UTF8String);
    for (NSArray<NSString *> *sample in @[@[], @[@"Ghostty"], @[@"Ghostty", @"iTerm2"]])
        printf("naming %lu: %s\n", (unsigned long)sample.count, UsageNoTerminal(sample).UTF8String);
    // A quoted path is put in as it is, so the card names the command Sign in runs, word for word.
    NSString *command = @"'/Applications/Sample Folder/claude' auth login";
    NSString *reason = @"Ghostty didn't open a tab for it";
    printf("a terminal's reason, with the way: %s\n", UsageSignInOr(reason, command).UTF8String);
    printf("the same reason, with no command: %s\n", UsageSignInOr(reason, nil).UTF8String);
    printf("a reason ending in a full stop: %s\n", UsageSignInOr(@"Terminal didn't open it.", command).UTF8String);
    printf("with no terminal, with the way: %s\n",
           UsageSignInOr(UsageNoTerminal(@[@"Ghostty", @"iTerm2"]), command).UTF8String);
    return 0;
}

// Seconds since a key was pressed or the pointer moved, anywhere on this Mac (no permission needed to ask).
static NSTimeInterval SecondsIdle(void) {
    return CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateHIDSystemState, kCGAnyInputEventType);
}

@interface Usage () {
    UsageTimes _times;  // when it's next asked, in seconds since 1970
}
@property (strong) UsageCard *card;
@property (strong) PanelWindow *window;
@property (strong) id<AgentUsage> agent;
@property (strong) dispatch_queue_t queue;
@property (assign) BOOL checking;
@property (assign) BOOL asleep;                    // the screens are
@property (copy) NSDictionary *known;              // what the card's page has, or gets once it loads
@property (copy) NSString *signIn;                 // the command that signs in the agent that answered
@property (copy) NSDictionary *lastSaid;           // the last answer's {state, noPlan}, for the log: only changes
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
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.asleep = NO;
            UsageSoon(&strongSelf->_times, NSDate.date.timeIntervalSince1970 + 5);
        }];
    return self;
}

// The time is compared on every tick rather than waited for, so a Mac that slept through a check asks as it wakes.
// Nothing's asked while the panel is hidden; shown again, it's asked straight away if a check came due meanwhile.
- (void)pollIfDue {
    if (self.checking || self.asleep || !self.window.shown) return;
    if (!UsageDue(&_times, NSDate.date.timeIntervalSince1970, SecondsIdle(), self.working || self.card.seen)) return;
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
    self.lastSaid = UsageLogAnswer(self.lastSaid, found, self.agent.name);
    // What was known stays on the card when asking fails (its times keep counting); nothing new is said.
    NSMutableArray<NSNumber *> *resets = [NSMutableArray array];
    if (![state isEqual:@"failed"]) {
        if (found[@"signIn"]) self.signIn = found[@"signIn"];
        NSMutableDictionary *usage = [found mutableCopy];
        [usage removeObjectsForKeys:@[@"signIn", @"noPlan"]];
        usage[@"checkedAt"] = @(now * 1000);
        self.known = usage;
        if (self.card.ready) [self.card call:@"setUsage" with:@[usage]];
        for (NSString *window in @[@"session", @"week"])
            [resets addObject:@([usage[window][@"resetsAt"] doubleValue] / 1000)];
        if ([state isEqual:@"ok"]) {
            UsageKeepLast(usage);
            if (self.answered) self.answered(usage);
        }
        if (self.cardShown) self.cardShown(UsageShowsCard(state));
    }
    UsageAnswered(&_times, state, resets, now);
}

#pragma mark Signing in

// A terminal that couldn't open it says why on the card (`signInFailed`), as the terminal says it, and gives the
// command to run yourself: a cause that stays (a permission turned down) would otherwise fail the same way at every
// press.
- (void)signInWith:(id<CommandHost>)terminal among:(NSArray<id<CommandHost>> *)terminals {
    NSString *command = self.signIn;
    NSString *cant = !terminal ? UsageSignInOr(UsageNoTerminal([terminals valueForKey:@"name"]), command)
                   : !command ? @"Whozmove hasn't found how to sign in yet: try again in a minute" : nil;
    if (cant) return [self.card call:@"signInFailed" with:@[cant]];
    NSString *where = terminal.name;
    __weak typeof(self) weakSelf = self;
    [terminal newTabIn:Home() running:command named:[@"Sign in to " stringByAppendingString:self.agent.name]
               forward:YES done:^(NSString *why) {
        if (!why) return;
        PanelLog(@"plan usage: Sign in didn't open in %@: %@", where, why);
        [weakSelf.card call:@"signInFailed" with:@[UsageSignInOr(why, command)]];
    }];
    PanelLog(@"plan usage: signing in, in %@", terminal.name);
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    _times.signingInUntil = now + kSignInFor;
    UsageSoon(&_times, now + kSignInEvery);
}

@end

BOOL UsageShowsCard(NSString *state) {
    return [state isEqual:@"ok"] || [state isEqual:@"signedOut"];
}

NSDictionary *UsageLogAnswer(NSDictionary *was, NSDictionary *found, NSString *agent) {
    // An answer with no state, or one it doesn't know, is one that can't be read, whichever it was.
    NSString *state = AsText(found[@"state"]), *why = AsText(found[@"noPlan"]);
    if (![@[@"ok", @"signedOut", @"other", @"none", @"failed"] containsObject:state ?: @""]) state = @"unreadable";
    NSDictionary *said = why ? @{@"state": state, @"noPlan": why} : @{@"state": state};
    if ([said isEqual:was]) return said;
    NSString *name = agent.length ? agent : @"the agent";
    if ([state isEqual:@"other"]) {
        if ([why isEqual:@"signedIn"])
            PanelLog(@"plan usage: the card is hidden: %@ says it's signed in, but can't give a plan's numbers", name);
        else if ([why isEqual:@"shell"])
            PanelLog(@"plan usage: the card is hidden: %@ can't give a plan's numbers: your shell sets an API key or "
                     @"another provider", name);
        else if ([why isEqual:@"unknown"])
            PanelLog(@"plan usage: the card is hidden: %@ can't give a plan's numbers, and whether it's signed in "
                     @"can't be read", name);
        else
            PanelLog(@"plan usage: the card is hidden: %@ can't give a plan's numbers, and didn't say why", name);
    } else if ([state isEqual:@"none"]) {
        if (agent.length && [why isEqual:@"notFound"])
            PanelLog(@"plan usage: the card is hidden: can't find %@ on this Mac", agent);
        else if (agent.length && [why isEqual:@"notReady"])
            PanelLog(@"plan usage: the card is hidden: %@ can't be asked until this Mac is set up for it", agent);
        else
            PanelLog(@"plan usage: the card is hidden: can't ask for a plan's numbers here, and no reason was given");
    } else if ([state isEqual:@"ok"]) {
        PanelLog(@"plan usage: the card shows your plan's numbers");
    } else if ([state isEqual:@"signedOut"]) {
        PanelLog(@"plan usage: the card asks you to sign in: %@ isn't signed in", name);
    } else if ([state isEqual:@"failed"]) {
        PanelLog(@"plan usage: couldn't get an answer from %@, so the card keeps what it last showed", name);
    } else {
        PanelLog(@"plan usage: the card is hidden: %@'s answer couldn't be read", name);
    }
    return said;
}

// Each run as {name, agent (null for none), answers}, its answers passed in turn as the app passes them, from a fresh
// start. The log's lines are read back from panel.log in this HOME's Whozmove folder, which the run empties first.
int PrintUsageSaid(NSArray<NSString *> *arguments) {
    if (HomeIsYourOwn()) {
        fprintf(stderr, "--print-usage-said writes Whozmove's panel.log: give it a throwaway HOME\n");
        return 1;
    }
    NSArray *runs = arguments.count ? AsList(ReadJSON(arguments[0])) : nil;
    if (!runs) {
        fprintf(stderr, "usage: Whozmove --print-usage-said <answers.json>\n");
        return 1;
    }
    [NSFileManager.defaultManager createDirectoryAtPath:AppDir(@"") withIntermediateDirectories:YES attributes:nil
                                                  error:nil];
    NSUInteger longest = 0;
    for (NSDictionary *run in runs) {
        [NSFileManager.defaultManager removeItemAtPath:AppDir(@"panel.log") error:nil];
        NSDictionary *was = nil;
        for (NSDictionary *answer in AsList(run[@"answers"]))
            was = UsageLogAnswer(was, AsRecord(answer), AsText(run[@"agent"]));
        printf("== %s\n", [AsText(run[@"name"]) ?: @"" UTF8String]);
        NSString *log = [NSString stringWithContentsOfFile:AppDir(@"panel.log") encoding:NSUTF8StringEncoding
                                                     error:nil] ?: @"";
        for (NSString *line in [log componentsSeparatedByString:@"\n"]) {
            NSRange gap = [line rangeOfString:@"  "];
            if (gap.location == NSNotFound) continue;
            NSString *said = [line substringFromIndex:NSMaxRange(gap)];
            longest = MAX(longest, said.length);
            printf("%s\n", said.UTF8String);
        }
    }
    printf("Every line under 120 characters: %s\n", longest < 120 ? "yes" : "no");
    return 0;
}
