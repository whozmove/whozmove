// CompactAtBreaksModule: with its switch on in Settings, a long conversation in a terminal the panel types into is
// compacted for you at a natural break (the row's compactTime, the rule the context ring goes by), while it sits at
// its prompt and nobody's on it, never while Claude works or asks; its row says when it has, until its next message.
// It compacts through the commands module (SessionCompacting), as the Compact card does.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import "Module.h"
#import "Core.h"
#import "Focus.h"
#import "Send.h"
#import "Row.h"
#import "Rows.h"
#import "Log.h"
#import "Menus.h"
#import "Printing.h"
#import "PanelWindow.h"
#import "AppleEvents.h"
#import "ForYou.h"

// The switch in Settings, off until you turn it on.
static NSString *const kSwitch = @"autoCompact";
// What /compact keeps, the same every time: never words from anywhere else, so nothing outside can steer what goes in.
static NSString *const kKeep = @"Keep exactly where the work stands so it can carry on without asking again: the task "
    @"and its goal; every instruction and decision from the user, or from the session that sent the work, in their "
    @"own words; what is done, what is left and the next step; what it is waiting for and from whom; the files, "
    @"branches and commits it changed; anything promised. Summarize exploration, tool output and settled discussion "
    @"briefly.";
// How recently the panel's use counts as you being on it; how long a session whose terminal said no waits before its
// tab is looked for again; how long the size after a compaction is waited for before it's taken as it is.
static const NSTimeInterval kPanelInUseWithin = 5;
static const double kLookAgainMs = 60000, kSizeAfterMs = 30000;
// A command's result is watched for about eleven minutes, so one going in longer than this has been lost track of.
static const double kGoingAtMostMs = 15 * 60000;

// A size in context as the log says it: 412k.
static NSString *Kilo(NSInteger tokens) {
    return [NSString stringWithFormat:@"%ldk", (long)((tokens + 500) / 1000)];
}

static NSInteger TokensOf(Row *row) {
    id tokens = row.agent[@"tokens"];
    return [tokens isKindOfClass:NSNumber.class] ? [tokens integerValue] : 0;
}

#pragma mark For the tests

// `Whozmove --print-compact-for-you`: whether Compact at Breaks would compact each sample session now, or why not, and
// whether nobody's on it, as JSON, then quit. Each case is a session at a natural break (its work saved, its turn over
// 10 minutes ago, nobody on it) with a few things changed. The module's tests check them.
static int PrintCompactForYou(void) {
    double now = 1760000000000, minute = 60000;
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    void (^show)(NSString *, void (^)(Row *, ForYouFacts *)) = ^(NSString *name, void (^change)(Row *, ForYouFacts *)) {
        Row *row = [Row new];
        row.sessionId = @"s-sample";
        row.status = @"idle";
        row.agent = @{@"model": @"claude-opus-5-5", @"tokens": @412000, @"window": @1000000};
        row.compactTime = @{@"why": @"your work is saved", @"kind": @"saved"};
        row.lastPromptAt = @(now - 15 * minute);
        row.lastReplyAt = row.messageAt = @(now - 10 * minute);
        ForYouFacts facts = {.now = now, .startedAt = now - 60 * minute, .atTheMac = YES, .byThemselves = YES};
        if (change) change(row, &facts);
        NSString *why = WhyNotCompactForYou(row, facts);
        out[name] = @{@"compacts": why ? why : @"yes", @"nobody on it": @(NobodyOnIt(row, facts))};
    };
    show(@"at a break, nobody on it", nil);
    show(@"nearly full", ^(Row *r, ForYouFacts *f) {
        r.compactTime = @{@"why": @"it's nearly full, and would soon compact by itself", @"kind": @"full"};
    });
    show(@"at no break", ^(Row *r, ForYouFacts *f) { r.compactTime = nil; });
    show(@"another compaction going in", ^(Row *r, ForYouFacts *f) { f->oneGoingIn = YES; });
    show(@"started before Whozmove's hooks", ^(Row *r, ForYouFacts *f) { r.reload = @{@"state": @"needed"}; });
    show(@"Whozmove started 3 minutes ago", ^(Row *r, ForYouFacts *f) { f->startedAt = now - 3 * minute; });
    show(@"you wrote to it 4 minutes ago", ^(Row *r, ForYouFacts *f) {
        r.lastPromptAt = @(now - 4 * minute);
        r.lastReplyAt = r.messageAt = @(now - 3 * minute);
    });
    show(@"another session wrote to it 4 minutes ago", ^(Row *r, ForYouFacts *f) {
        r.lastPromptAt = @(now - 4 * minute);
        r.promptFrom = @"Lead";
        r.lastReplyAt = r.messageAt = @(now - 3 * minute);
    });
    show(@"you looked at it in Claude 4 minutes ago", ^(Row *r, ForYouFacts *f) {
        r.lastFocusedAt = @(now - 4 * minute);
    });
    show(@"away an hour: the ring's suggestion only", ^(Row *r, ForYouFacts *f) {
        r.compactTime = @{@"why": @"you've been away from it for an hour", @"kind": @"away"};
    });
    show(@"a Claude Desktop conversation", ^(Row *r, ForYouFacts *f) { f->desktop = YES; });
    show(@"compacted since its last message", ^(Row *r, ForYouFacts *f) { f->lastDone = now - 5 * minute; });
    show(@"compacted before its last message", ^(Row *r, ForYouFacts *f) { f->lastDone = now - 20 * minute; });
    show(@"something in the background that can change files", ^(Row *r, ForYouFacts *f) {
        r.background = @[@{@"what": @"Review the native side", @"holds": @YES}];
    });
    show(@"a dev server left running in the background", ^(Row *r, ForYouFacts *f) {
        r.background = @[@{@"what": @"npm run dev", @"holds": @NO}];
    });
    show(@"its turn ended a minute ago", ^(Row *r, ForYouFacts *f) {
        r.lastReplyAt = r.messageAt = @(now - minute);
    });
    show(@"its turn ended over an hour ago", ^(Row *r, ForYouFacts *f) {
        r.lastReplyAt = r.messageAt = @(now - 61 * minute);
        r.lastPromptAt = @(now - 70 * minute);
    });
    show(@"seen in the last 5 minutes", ^(Row *r, ForYouFacts *f) { r.seenAt = @(now - 4 * minute); });
    show(@"seen 6 minutes ago", ^(Row *r, ForYouFacts *f) { r.seenAt = @(now - 6 * minute); });
    show(@"you at the Mac, in its terminal or on it", ^(Row *r, ForYouFacts *f) { f->byThemselves = NO; });
    show(@"you away from the Mac, its terminal in front", ^(Row *r, ForYouFacts *f) {
        f->byThemselves = NO;
        f->atTheMac = NO;
    });
    show(@"the panel in use", ^(Row *r, ForYouFacts *f) { f->panelInUse = YES; });
    return PrintJSON(out);
}

@interface CompactAtBreaksModule : NSObject <Module>
@property (weak) Core *core;
// By session: when it last compacted it or tried (done); what it did for it until its next message (forYou): {at, why,
// before, after} once it compacted it, {at, stopped} once it stopped part-way, {at, failed} once it didn't go through;
// why its terminal said it can't, {cant, way, at} (cant); the reason last logged for it (logged). The session going in
// now, and when Whozmove started.
@property (strong) NSMutableDictionary<NSString *, NSNumber *> *done;
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *forYou, *cant;
@property (strong) NSMutableDictionary<NSString *, NSString *> *logged;
@property (copy) NSString *going;
@property (assign) double goingSince, startedAt;
@end

@implementation CompactAtBreaksModule

+ (NSString *)moduleName {
    return @"compact-at-breaks";
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.done = [NSMutableDictionary dictionary];
    self.forYou = [NSMutableDictionary dictionary];
    self.cant = [NSMutableDictionary dictionary];
    self.logged = [NSMutableDictionary dictionary];
    self.startedAt = NSDate.date.timeIntervalSince1970 * 1000;
    return self;
}

+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return @{@"--print-compact-for-you": ^(Core *core, NSArray *a) { return PrintCompactForYou(); }};
}

// A switch in Settings, with the panel's other ways of working with your sessions.
- (NSArray<SettingEntry *> *)settingEntries {
    __weak typeof(self) weakSelf = self;
    SettingEntry *entry = [SettingEntry switchWithKey:kSwitch title:@"Compact at Breaks" glyph:@"list"
        on:^BOOL { return SwitchedOn(kSwitch); }
        set:^(BOOL on) {
            SetSwitch(kSwitch, on);
            PanelLog(@"Compact at Breaks turned %@", on ? @"on" : @"off");
            if (!on) [weakSelf.cant removeAllObjects];
            [weakSelf.core.rows refresh];
        }];
    entry.foot = [NSString stringWithFormat:@"Compacts a long conversation in %@ at a natural break, while it sits at "
                                            @"its prompt, never while Claude works or asks. Its row says when it has.",
                                            self.core.send.terminalNames];
    entry.group = 20;
    entry.order = 40;
    return @[entry];
}

// What's known of a session beside its row, now. Its terminal is the one it runs in that the panel types into (Send's
// terminalOf:, as whyNotControl: asks), as hostHolding: finds only an app that keeps a session as its own
// conversation, Claude Desktop.
- (ForYouFacts)factsFor:(Row *)row now:(double)now atTheMac:(BOOL)atTheMac panelInUse:(BOOL)inUse {
    BOOL desktop = [self.core.send conversationHostOf:row] != nil;
    NSString *front = NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier;
    id<SessionCompacting> compacting = [self.core moduleThat:@protocol(SessionCompacting)];
    return (ForYouFacts){
        .now = now, .startedAt = self.startedAt, .lastDone = self.done[row.sessionId].doubleValue,
        .oneGoingIn = compacting.compactingAny, .desktop = desktop, .atTheMac = atTheMac,
        .byThemselves = WordsGoByThemselves(row.focused, desktop, [self.core.send terminalOf:row].appId, front),
        .panelInUse = inUse,
    };
}

// Once a second, with its switch on and nothing compacting from the panel: the biggest session that may be compacted
// for you now is, one at a time. The checks are asked cheapest first, and its tab is looked for last, only for the one
// session that has passed the rest, as asking a terminal for every row each second is what the rows' noCompact avoids.
- (void)tick {
    double now = NSDate.date.timeIntervalSince1970 * 1000;
    if (self.going && now - self.goingSince > kGoingAtMostMs) {
        PanelLog(@"%@ -> compacting for you never ended; letting it go", self.going);
        self.going = nil;
    }
    if (self.core.printing || !SwitchedOn(kSwitch) || self.going) return;
    id<SessionCompacting> compacting = [self.core moduleThat:@protocol(SessionCompacting)];
    if (!compacting) return;
    // What a terminal said it can't do is looked at again once you've been on the session, as you may have put it
    // right there: it's asked again when you've gone.
    for (NSString *sid in self.cant.allKeys) {
        Row *row = self.core.rows.byId[sid];
        if (row && row.onItAt > [self.cant[sid][@"at"] doubleValue]) [self.cant removeObjectForKey:sid];
    }
    NSArray<Row *> *rows = [self.core.rows.byId.allValues
        filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(Row *row, NSDictionary *b) {
            return row.sessionId && row.compactTime != nil;
        }]];
    if (!rows.count) return;
    rows = [rows sortedArrayUsingComparator:^NSComparisonResult(Row *a, Row *b) {
        return TokensOf(a) > TokensOf(b) ? NSOrderedAscending : TokensOf(a) < TokensOf(b) ? NSOrderedDescending
                                                                                          : NSOrderedSame;
    }];
    BOOL atTheMac = AtTheMac(), inUse = [self.core.window inUseWithin:kPanelInUseWithin];
    for (Row *row in rows) {
        NSString *sid = row.sessionId;
        NSString *why = WhyNotCompactForYou(row, [self factsFor:row now:now atTheMac:atTheMac panelInUse:inUse]);
        if (why) {
            [self log:sid why:why];
            continue;
        }
        NSDictionary *cant = self.cant[sid];
        if (cant && now - [cant[@"at"] doubleValue] < kLookAgainMs) continue;
        NSString *way = nil, *refused = [self whyNotControl:row] ?: [compacting whyNotCompact:row wayPast:&way];
        if (refused) {
            self.cant[sid] = @{@"cant": refused, @"way": way ?: NSNull.null, @"at": @(now)};
            [self log:sid why:[@"its terminal says: " stringByAppendingString:refused]];
            if (!cant) [self.core.rows refresh];
            continue;
        }
        [self.cant removeObjectForKey:sid];
        [self compact:row with:compacting];
        return;
    }
}

// Why Whozmove can't look for the session's tab without asking you: macOS hasn't let it control the terminal yet. Its
// tab is looked for only once it has, as looking would have macOS ask, with nobody's press, over the app you're in;
// a press on the Compact card asks. A session in no terminal the panel types into is left to the commands module's
// check, which says why.
- (NSString *)whyNotControl:(Row *)row {
    id<Host> host = [self.core.send terminalOf:row];
    if (!host) return nil;
    NSString *name = host.name.length ? host.name : @"its terminal";
    pid_t pid = host.appId.length
        ? [NSRunningApplication runningApplicationsWithBundleIdentifier:host.appId].firstObject.processIdentifier : 0;
    if (pid <= 0) return [NSString stringWithFormat:@"%@ isn't open, so its tab can't be found", name];
    if (AutomationPermission(pid, NO) == noErr) return nil;
    return [NSString stringWithFormat:@"Whozmove may not control %@ yet: compact it once from this card, and macOS "
                                      @"asks you", name];
}

// Why it doesn't compact a session now, in panel.log once each time it changes, but for "at no break", the
// commonest, and another compaction going in, which passes in a moment: they say nothing worth keeping.
- (void)log:(NSString *)sid why:(NSString *)why {
    if ([why isEqualToString:@"a compaction is going into a session already"]) return;
    if ([self.logged[sid] isEqualToString:why]) return;
    self.logged[sid] = why;
    PanelLog(@"%@ -> not compacted for you yet: %@", sid, why);
}

- (void)compact:(Row *)row with:(id<SessionCompacting>)compacting {
    NSString *sid = row.sessionId, *kind = row.compactTime[@"why"] ?: @"";
    NSInteger before = TokensOf(row);
    self.going = sid;
    self.goingSince = NSDate.date.timeIntervalSince1970 * 1000;
    [self.logged removeObjectForKey:sid];
    PanelLog(@"%@ -> compacting for you at a break (%@), with %@ in context", sid, kind, Kilo(before));
    __weak typeof(self) weakSelf = self;
    [compacting compact:row focus:kKeep
               stillMay:^BOOL { return [weakSelf nobodyOn:sid]; }
               whenOver:^(CompactEnd end, NSString *why) {
        [weakSelf over:sid end:end why:why kind:kind before:before];
    }];
}

// Whether nobody has come to the session since it started going in: asked before each key, and once its result has
// come, before its filler is taken out of the prompt.
- (BOOL)nobodyOn:(NSString *)sid {
    Row *row = self.core.rows.byId[sid];
    if (!row) return NO;
    double now = NSDate.date.timeIntervalSince1970 * 1000;
    return NobodyOnIt(row, [self factsFor:row now:now atTheMac:AtTheMac()
                               panelInUse:[self.core.window inUseWithin:kPanelInUseWithin]]);
}

// Once it has run its course: what it did stays on the row until the session's next message, and nothing more is
// tried before then, but for one you came to before any key went in, which is tried again once you've gone.
- (void)over:(NSString *)sid end:(CompactEnd)end why:(NSString *)why kind:(NSString *)kind before:(NSInteger)before {
    double now = NSDate.date.timeIntervalSince1970 * 1000;
    if ([self.going isEqualToString:sid]) self.going = nil;
    switch (end) {
        case CompactEndCompacted:
            self.forYou[sid] = @{@"at": @(now), @"why": kind, @"before": @(before)};
            PanelLog(@"%@ -> compacted for you (%@), from %@", sid, kind, Kilo(before));
            break;
        case CompactEndLeftForYou:
            PanelLog(@"%@ -> compacting for you left for you: %@", sid, why ?: @"you came to it");
            break;
        case CompactEndStoppedPartWay:
            self.forYou[sid] = @{@"at": @(now), @"stopped": why ?: @"it stopped"};
            PanelLog(@"%@ -> compacting for you stopped part-way: %@; not again until its next message", sid,
                     why ?: @"no reason given");
            break;
        case CompactEndFailed:
            self.forYou[sid] = @{@"at": @(now), @"failed": why ?: @"The compaction didn't go through"};
            PanelLog(@"%@ -> compacting for you didn't go through: %@; not again until its next message", sid,
                     why ?: @"no reason given");
            break;
    }
    if (end != CompactEndLeftForYou) self.done[sid] = @(now);
    [self.core.rows refresh];
}

// Each row says what it did for the session, until its next message: compacted, with its size after once that has been
// read (the transcript's next read, a moment after the result), or after 30s, as a compaction can leave it as it was;
// stopped part-way; or didn't go through. Or, with its switch on, why it can't, while it's at a break, as the row's
// compactNote, which the ring's tip and its Compact card say.
- (void)rows:(NSArray<Row *> *)rows phase:(RowPhase)phase {
    if (phase != RowPhaseListed) return;
    BOOL on = SwitchedOn(kSwitch);
    double now = NSDate.date.timeIntervalSince1970 * 1000;
    for (Row *row in rows) {
        NSString *sid = row.sessionId;
        if (!sid) continue;
        NSDictionary *done = self.forYou[sid];
        if (done && row.lastPromptAt.doubleValue > [done[@"at"] doubleValue]) {
            [self.forYou removeObjectForKey:sid];
            done = nil;
        }
        if (done && done[@"before"] && !done[@"after"]) {
            NSInteger tokens = TokensOf(row), before = [done[@"before"] integerValue];
            if (tokens != before || now - [done[@"at"] doubleValue] > kSizeAfterMs) {
                NSMutableDictionary *with = [done mutableCopy];
                with[@"after"] = @(tokens);
                self.forYou[sid] = done = with;
                PanelLog(@"%@ -> compacted for you: %@ → %@ in context", sid, Kilo(before), Kilo(tokens));
            }
        }
        if (!row.compactTime) [self.cant removeObjectForKey:sid];
        NSDictionary *cant = on ? self.cant[sid] : nil;
        row.compactedFor = done;
        if (cant)
            row.compactNote = @{@"text": [@"Compact at Breaks can't: " stringByAppendingString:cant[@"cant"]],
                                @"way": cant[@"way"]};
    }
}

@end
