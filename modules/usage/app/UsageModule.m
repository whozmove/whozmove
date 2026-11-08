// UsageModule: the usage card's face for the core (Module): your plan's usage asked of the agent when a check is due,
// the card behind the panel that shows it, which session uses the most of it today, your gear (GearFacts) and its
// switch in Settings, its Sign in, and Working on Whozmove's Preview the Wait.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import "Module.h"
#import "Core.h"
#import "PanelWindow.h"
#import "Usage.h"
#import "UsageCard.h"
#import "Page.h"
#import "Files.h"
#import "Gear.h"
#import "Row.h"
#import "Log.h"
#import "Menus.h"
#import "Rows.h"

@interface UsageModule : NSObject <Module, GearFacts> {
    GearTotals _totals;  // what the reads of the rows add up, carried on from the last sample
}
@property (weak) Core *core;
@property (strong) Usage *usage;  // made as the app starts: it watches the screens sleep and wake
@property (strong) UsageCard *card;
@property (copy) NSDictionary<NSString *, void (^)(NSDictionary *)> *answers;  // its page's messages, by type
@property (strong) id heaviest;  // what the card was last told of the session using the most today, or NSNull
@property (strong) id<AgentUsage> agent;               // the agent the usage is asked of: its sessions are counted
@property (copy) NSArray<NSDictionary *> *samples;     // the answers the gear measures from (usage-gear.json)
@property (copy) NSDictionary *lastAnswer;             // the last "ok" answer, which the gear measures at
@property (copy) NSArray<Row *> *counted;              // the sessions working at the last read
@property (copy) NSDictionary *measured, *counts;      // GearMeasured's, at the last answer or press; GearCounts'
@property (copy) NSDictionary *facts;                  // what both pages were last told (setGear), nil until measured
@property (copy) NSDictionary *fileSaid;               // what gear.json last said that matters to a lead
@property (assign) NSTimeInterval fileAt;              // when it was last written
@end

@implementation UsageModule

// Settings' Usage Gear: the gear is on until you turn it off there. The key keeps its name.
static NSString *const kGearShown = @"usageGear";

static BOOL GearShown(void) {
    return SwitchedOn(kGearShown);
}

+ (NSString *)moduleName {
    return @"usage";
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    [NSUserDefaults.standardUserDefaults registerDefaults:@{kGearShown: @YES}];
    return self;
}

// The card is held by the panel, over its shadow, following the glass and the pointer. Its page has a bridge of its own: what it
// says is answered here, as the panel's page's messages would be, and once it has loaded it's told what's known.
- (void)launch {
    self.card = [UsageCard new];
    self.agent = [self.core agentsThat:@protocol(AgentUsage)].firstObject;
    self.usage = [[Usage alloc] initWithCard:self.card window:self.core.window agent:self.agent];
    // Off as the app starts, the gear keeps nothing either, and gear.json says it's off: the app may have quit as it
    // was turned off, before it forgot, or the switch may have been set outside the app.
    if (!GearShown()) GearForget(NSUserDefaults.standardUserDefaults, NSDate.date.timeIntervalSince1970);
    else [self keepGearFile];
    self.samples = GearShown() ? GearSamplesFrom(AsRecord(ReadJSON(AppDir(@"usage-gear.json")))[@"samples"]) : @[];
    _totals = GearTotalsFrom(self.samples);
    [self.core.window attachAbove:self.card.window];
    // The panel keeps room under itself for the card at its tallest from the start, so it doesn't shorten as the first
    // answer comes in; only an answer that leaves no card lets it go, and one with a card keeps it again. It never
    // changes as the card slides out, opens or folds, so nothing moves then.
    [self.core.window keepBelow:UsageCardReach for:self.card.window];
    __weak typeof(self) weakSelf = self;
    self.usage.cardShown = ^(BOOL shown) {
        UsageModule *me = weakSelf;
        [me.core.window keepBelow:shown ? UsageCardReach : 0 for:me.card.window];
    };
    [self.core.window followGlass:^(NSRect glass, NSRect list, NSRect screen, NSTimeInterval duration) {
        [weakSelf.card glassAt:glass list:list duration:duration];
    }];
    [self.core.window followPointer:^(NSPoint point) { [weakSelf.card pointerAt:point]; }];
    // Out of sight while the panel is turned over, or pushed off the screen's edge.
    [self.core.window followTurn:^(BOOL turned) { weakSelf.card.away = turned || weakSelf.core.window.parked; }];
    [self.core.window followAway:^(BOOL away) { weakSelf.card.away = away || weakSelf.core.window.turned; }];
    self.answers = [self messages];
    self.card.onMessage = ^(NSString *type, NSDictionary *message) {
        void (^answer)(NSDictionary *) = weakSelf.answers[type];
        if (answer) answer(message);
    };
    self.card.onLoad = ^{
        [weakSelf.usage resend];
        if (weakSelf.heaviest) [weakSelf.card call:@"setHeaviest" with:@[weakSelf.heaviest]];
        if (weakSelf.facts) [weakSelf.card call:@"setGear" with:@[weakSelf.facts, @NO]];
    };
    self.usage.answered = ^(NSDictionary *usage) { [weakSelf answered:usage]; };
}

// The panel's page, loaded again, gets the gear too (core.gear, for what shows it beyond the card), or that it's off.
- (void)pageLoaded {
    if (self.facts) [self.core.page call:@"setGear" with:@[self.facts, @NO]];
    else if (!GearShown()) [self.core.page call:@"setGear" with:@[NSNull.null, @NO, @YES]];
}

// The time is compared on every tick, so a Mac that slept through a check asks as it wakes.
- (void)tick {
    [self.usage pollIfDue];
}

// Once the rows are whole: whether a session is at work, which moves the usage, so it's asked more often meanwhile; and
// the session that has used the most today, as its agent counts it (`today`, each reply once), with its share of what
// the listed sessions used and how long its conversation is now, for the line at the foot of the open card; nothing
// while fewer than two sessions have used any, as then there's no one to single out.
- (void)rows:(NSArray<Row *> *)rows phase:(RowPhase)phase {
    if (phase != RowPhaseListed || !self.card) return;
    self.usage.working = [rows indexOfObjectPassingTest:^BOOL(Row *row, NSUInteger i, BOOL *stop) {
        return [row.status isEqual:@"busy"];
    }] != NSNotFound;
    [self countFrom:rows];
    long long total = 0, most = 0;
    NSUInteger using = 0;
    Row *top = nil;
    for (Row *row in rows) {
        long long today = [row.agent[@"today"] longLongValue];
        if (today <= 0) continue;
        total += today;
        using++;
        if (today > most) { most = today; top = row; }
    }
    NSString *name = top.name.length ? top.name : top.cwd.lastPathComponent;
    // At most 99% while another session has used some, so a share that rounds up never reads as all of it.
    long long share = MIN(99, llround(100.0 * most / total));
    id heaviest = using >= 2 && name.length
        ? @{@"name": name, @"share": @(share), @"tokens": top.agent[@"tokens"] ?: @0}
        : NSNull.null;
    if ([heaviest isEqual:self.heaviest]) return;
    self.heaviest = heaviest;
    [self.card call:@"setHeaviest" with:@[heaviest]];
}

#pragma mark Your gear

// The gear you set: kept across launches, so a restart (Deploy's) keeps it; nil until your first press.
- (NSNumber *)gearSet {
    return GearOf([NSUserDefaults.standardUserDefaults objectForKey:@"gear"]);
}

// Each read: the sessions working on the plan this card shows (the ones whose agent it's asked of), added to the
// totals for the time since the last read. Nothing's counted while the gear is off.
- (void)countFrom:(NSArray<Row *> *)rows {
    if (!GearShown()) return;
    id<AgentUsage> agent = self.agent;
    __weak Core *core = self.core;
    self.counted = GearCounted(rows, ^BOOL(Row *row) { return (id)[core agentOf:row] == (id)agent; });
    GearRead(&_totals, self.counted.count, NSDate.date.timeIntervalSince1970);
    self.counts = GearCounts(self.counted, self.gearSet);
    [self tellGear:NO];
}

// Each answer in state "ok": a sample of it with the totals, kept 3 days, and what they measure now; with the gear off,
// only the answer, which the gear measures at once it's turned back on.
- (void)answered:(NSDictionary *)usage {
    self.lastAnswer = usage;
    if (!GearShown()) return;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    self.samples = GearKeep(self.samples, GearSample(usage, _totals, now), now);
    GearWrite(@"usage-gear.json", @{@"samples": self.samples});
    self.measured = GearMeasured(self.samples, usage, self.gearSet);
    [self tellGear:NO];
}

// Your press on a seat: the gear is that seat's, kept, and both pages are told at once, with the forecast at it. A
// press that names no seat, or comes while the gear is off or not yet known, changes nothing.
- (void)setGearTo:(id)to {
    NSNumber *gear = GearOf(to);
    if (!self.facts || !gear || [self.gearSet isEqual:gear]) return;
    [NSUserDefaults.standardUserDefaults setObject:gear forKey:@"gear"];
    [NSUserDefaults.standardUserDefaults setObject:@(llround(NSDate.date.timeIntervalSince1970 * 1000))
                                            forKey:@"gearChangedAt"];
    // Said in the log, as the preferences keep only the latest, so the gear's history can be read back from it.
    PanelLog(@"gear set to %@", gear);
    if (self.lastAnswer) self.measured = GearMeasured(self.samples, self.lastAnswer, gear);
    self.counts = GearCounts(self.counted ?: @[], gear);
    [self tellGear:YES];
}

// Settings' Usage Gear turned off: the gear you set and everything kept for it are forgotten (the preferences, gear.json
// for a lead, the samples), and both pages are told the gear is off, so the card shows only your usage, no row says
// Over the gear, and Up next lets every queued job in. Turned on again, it counts and measures afresh, with no gear
// until your press.
- (void)showGear:(BOOL)on {
    SetSwitch(kGearShown, on);
    PanelLog(@"Usage Gear turned %@", on ? @"on" : @"off");
    self.samples = @[];
    _totals = GearTotalsFrom(@[]);
    self.counted = nil;
    self.counts = nil;
    self.facts = nil;
    self.fileSaid = nil;
    self.measured = on && self.lastAnswer ? GearMeasured(@[], self.lastAnswer, nil) : nil;
    if (on) [self keepGearFile];
    else GearForget(NSUserDefaults.standardUserDefaults, NSDate.date.timeIntervalSince1970);
    if (self.card.ready) [self.card call:@"setGear" with:@[NSNull.null, @NO, @(!on)]];
    [self.core.page call:@"setGear" with:@[NSNull.null, @NO, @(!on)]];
    [self.core.rows refresh];
}

// While Usage Gear is on, gear.json never says it's off: the off record, or no file, gives way to one saying no gear
// yet (`gear` null), which lets nothing in, until the gear is known. The off record goes first, so a write that fails
// leaves no file, which a lead reads as none too, never as no limit.
- (void)keepGearFile {
    NSDictionary *file = AsRecord(ReadJSON(AppDir(@"gear.json")));
    if (file && !GearFileIsOff(file)) return;
    [NSFileManager.defaultManager removeItemAtPath:AppDir(@"gear.json") error:nil];
    GearWrite(@"gear.json", GearFileFor(@{}, nil, NSDate.date.timeIntervalSince1970));
}

// The facts, from the gear set, the counts and what was measured, told to the card's page and the panel's when they
// change (setGear, with whether your press made them); and gear.json for a lead, when what it says has changed, at
// most once a minute but at once for a press.
- (void)tellGear:(BOOL)pressed {
    if (!GearShown() || !self.measured || !self.counts) return;
    NSMutableDictionary *facts = [@{@"gear": self.gearSet ?: NSNull.null, @"recommended": NSNull.null,
                                    @"notYet": NSNull.null, @"bound": NSNull.null, @"forecast": NSNull.null}
                                  mutableCopy];
    [facts addEntriesFromDictionary:self.counts];
    [facts addEntriesFromDictionary:self.measured];
    if (pressed || ![facts isEqual:self.facts]) {
        self.facts = facts;
        if (self.card.ready) [self.card call:@"setGear" with:@[facts, @(pressed)]];
        [self.core.page call:@"setGear" with:@[facts, @(pressed)]];
    }
    NSDictionary *said = @{@"gear": facts[@"gear"], @"atWork": facts[@"atWork"], @"recommended": facts[@"recommended"]};
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if ([said isEqual:self.fileSaid] || (!pressed && now - self.fileAt < 60)) return;
    NSNumber *changedAt = AsNumber([NSUserDefaults.standardUserDefaults objectForKey:@"gearChangedAt"]);
    GearWrite(@"gear.json", GearFileFor(facts, changedAt, now));
    self.fileSaid = said;
    self.fileAt = now;
}

- (NSDictionary *)gear {
    return self.facts;
}

// Its switch in Settings, on a card of its own: Usage Gear, on until you turn it off.
- (NSArray<SettingEntry *> *)settingEntries {
    __weak typeof(self) weakSelf = self;
    SettingEntry *entry = [SettingEntry switchWithKey:kGearShown title:@"Usage Gear" glyph:@"gauge"
        on:^BOOL { return GearShown(); }
        set:^(BOOL on) { if (on != GearShown()) [weakSelf showGear:on]; }];
    entry.foot = @"How many sessions may work at once, set on the usage card. Off, queued jobs start without a limit, "
                 @"the card shows only your usage, no row says Over the gear, and the gear you set is forgotten.";
    entry.group = 30;
    entry.order = 10;
    return @[entry];
}

// The card's page's messages (page/card.js).
- (NSDictionary<NSString *, void (^)(NSDictionary *)> *)messages {
    __weak typeof(self) weakSelf = self;
    return @{
        // In the first terminal on this Mac that runs a command in a new tab: Ghostty, else iTerm2, else macOS's
        // Terminal.
        @"usageSignIn": ^(NSDictionary *msg) {
            NSArray<id<CommandHost>> *terminals = [weakSelf.core hostsThat:@protocol(CommandHost)];
            id<CommandHost> terminal = nil;
            for (id<CommandHost> host in terminals)
                if ([NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:host.appId]) {
                    terminal = host;
                    break;
                }
            [weakSelf.usage signInWith:terminal among:terminals];
        },
        // A press on a seat of the gear's, on the card (page/gear.js): {to: the gear, from 1 to 30}.
        @"gearSet": ^(NSDictionary *msg) { [weakSelf setGearTo:msg[@"to"]]; },
        // Whether there's a card, and how much of it shows under the panel's edge.
        @"usageCard": ^(NSDictionary *msg) { [weakSelf.card took:msg]; },
    };
}

+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return @{@"--print-usage-checks": ^(Core *core, NSArray *a) { return PrintUsageChecks(a); },
             @"--print-usage-kept": ^(Core *core, NSArray *a) { return PrintUsageKept(a); },
             @"--print-usage-said": ^(Core *core, NSArray *a) { return PrintUsageSaid(a); },
             @"--print-gear": ^(Core *core, NSArray *a) { return PrintGear(a); },
             @"--print-sign-in": ^(Core *core, NSArray *a) {
                 return PrintSignIn([[core hostsThat:@protocol(CommandHost)] valueForKey:@"name"]);
             }};
}

// The wait the card shows at the session limit, and its reset, played now: to try it without a limit.
- (NSArray<MenuEntry *> *)menuEntries {
    NSMenuItem *preview = [[NSMenuItem alloc] initWithTitle:@"Preview the Wait" action:@selector(previewWait)
                                              keyEquivalent:@""];
    preview.target = self;
    return @[[MenuEntry entryIn:MenuSectionWhozmove order:20 item:preview]];
}

- (void)previewWait {
    [self.card call:@"previewWait" with:@[]];
}

@end
