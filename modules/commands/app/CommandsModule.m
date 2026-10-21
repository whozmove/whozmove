// CommandsModule: the commands' face for the core (Module): the page's messages for a session's model, effort and
// mode menus, the Compact card and "Switch model?"; their part of each row (a pick not confirmed yet, a compaction
// under way); and the print mode the tests check.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Module.h"
#import "Core.h"
#import "Rows.h"
#import "Row.h"
#import "Reason.h"
#import "Printing.h"
#import "Commands.h"
#import "Send.h"

// A terminal that answers for a session's tab without being asked, for --print-why-not: under the panel's first
// terminal's name, with the tab found and certainly the session's unless a variant says otherwise.
@interface SampleTerminal : NSObject <TypingHost>
@property (strong) NSString *name;
@property (assign) BOOL found, unique;
@end

@implementation SampleTerminal
- (NSString *)appId { return @"sample"; }
- (BOOL)open:(Row *)row { return NO; }
- (NSString *)tabFor:(Row *)row unique:(BOOL *)unique { *unique = self.unique; return self.found ? @"tab" : nil; }
- (void)type:(NSString *)text inTab:(NSString *)tab {}
- (void)press:(TerminalKey)key times:(NSInteger)times inTab:(NSString *)tab {}
@end

// A session's reach as the menus find it (Send's SessionReach, all as the sample home has it: whether an app keeps it
// as a conversation, its first message, whether it's open twice, why keys can't go in now, the terminals' names), but
// for what can't be asked in a test: its terminal and tab are a SampleTerminal's (none when `terminal` is nil), and
// Whozmove may control Claude, never asked of macOS. A variant can say its first message is sent, or that it's open
// elsewhere too, or in another terminal.
@interface SampleReach : SessionReach
@property (strong) SampleTerminal *sample;
@property (assign) BOOL allowed;
@property (strong) NSNumber *startedNow, *openElsewhereNow, *openTwiceNow;
@end

@implementation SampleReach
- (id<TypingHost>)typing { return self.desktop ? nil : self.sample; }
- (BOOL)mayControl { return self.allowed; }
- (BOOL)started { return self.startedNow ? self.startedNow.boolValue : super.started; }
- (BOOL)openElsewhere { return self.openElsewhereNow ? self.openElsewhereNow.boolValue : super.openElsewhere; }
- (BOOL)openTwice { return self.openTwiceNow ? self.openTwiceNow.boolValue : super.openTwice; }
@end

static SampleReach *SampleReachOf(Row *row, Core *core) {
    SampleReach *reach = [[SampleReach alloc] initWithRow:row send:core.send];
    reach.sample = [SampleTerminal new];
    reach.sample.name = [[core hostsThat:@protocol(TypingHost)].firstObject name];
    reach.sample.found = reach.sample.unique = YES;
    reach.allowed = YES;
    return reach;
}

// What a row's menus, Compact card and next steps would say about why nothing can go in now (null: it can).
static NSDictionary *WhyNotOf(Row *row, SampleReach *reach, BOOL compacting, Core *core) {
    NSMutableDictionary *said = [NSMutableDictionary dictionary];
    for (NSString *field in @[@"model", @"effort", @"mode"]) {
        NSArray *cycles = [field isEqual:@"mode"] && !reach.desktop
            ? [(id<AgentCommands>)[core agentOf:row] modeCyclesFor:row] : nil;
        said[[@"pick " stringByAppendingString:field]] = WhyNoPick(row, field, reach, cycles) ?: NSNull.null;
    }
    said[@"compact"] = WhyNoCompact(reach, compacting) ?: NSNull.null;
    said[@"ask"] = WhyNoAsk(reach) ?: NSNull.null;
    return said;
}

// `Whozmove --print-why-not`: for each session in $HOME, what its model, effort and mode menus, its Compact card and
// its next steps (Send's WhyNoAsk) would say about why nothing can go into it now (null: something can), with the
// session's reach as the menus find it in the sample home (SampleReachOf); then the same for a terminal session and a
// Claude Desktop conversation with parts of their reach changed. As JSON, then quit. tests/rows.sh checks them: the
// wording, and the order things are looked at in, is what keeps a key from going where it shouldn't.
static int PrintWhyNot(Core *core) {
    NSMutableDictionary *found = [NSMutableDictionary dictionary], *out = [@{@"as found": found} mutableCopy];
    NSMutableDictionary<NSString *, Row *> *byId = [NSMutableDictionary dictionary];
    for (Row *row in SettledRows(core)) {
        if (!row.sessionId) continue;
        byId[row.sessionId] = row;
        found[row.sessionId] = WhyNotOf(row, SampleReachOf(row, core), NO, core);
    }
    void (^variant)(NSString *, NSString *, BOOL, void (^)(SampleReach *)) =
        ^(NSString *sid, NSString *name, BOOL compacting, void (^change)(SampleReach *)) {
        Row *row = byId[sid];
        if (!row) return;
        SampleReach *reach = SampleReachOf(row, core);
        change(reach);
        out[[NSString stringWithFormat:@"%@, %@", sid, name]] = WhyNotOf(row, reach, compacting, core);
    };
    variant(@"s-clone", @"no terminal the panel can type into", NO, ^(SampleReach *r) { r.sample = nil; });
    variant(@"s-clone", @"its tab not found", NO, ^(SampleReach *r) { r.sample.found = NO; });
    variant(@"s-clone", @"another tab like its own", NO, ^(SampleReach *r) { r.sample.unique = NO; });
    variant(@"s-clone", @"compacting already", YES, ^(SampleReach *r) {});
    variant(@"s-clone", @"open in another terminal too", NO, ^(SampleReach *r) {
        r.openElsewhereNow = r.openTwiceNow = @YES;
    });
    variant(@"s-clone", @"open in another terminal too, with no terminal the panel can type into", NO,
            ^(SampleReach *r) {
        r.sample = nil;
        r.openElsewhereNow = r.openTwiceNow = @YES;
    });
    variant(@"s-clone", @"open in Claude Desktop too", NO, ^(SampleReach *r) { r.openElsewhereNow = @YES; });
    variant(@"s-desk", @"its first message sent", NO, ^(SampleReach *r) { r.startedNow = @YES; });
    variant(@"s-desk", @"its first message sent, Claude not allowed to be controlled", NO, ^(SampleReach *r) {
        r.startedNow = @YES;
        r.allowed = NO;
    });
    variant(@"s-desk", @"its first message sent, open in a terminal too", NO, ^(SampleReach *r) {
        r.startedNow = @YES;
        r.openElsewhereNow = @YES;
    });
    return PrintJSON(out);
}

@interface CommandsModule : NSObject <Module>
@property (weak) Core *core;
@property (strong) Commands *commands;
@end

@implementation CommandsModule

+ (NSString *)moduleName {
    return @"commands";
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.commands = [[Commands alloc] initWithPage:core.page window:core.window core:core];
    // A row with something new to show (a pick, a compaction starting or ending) is shown at once.
    __weak Core *weakCore = core;
    self.commands.onChange = ^{ [weakCore.rows refresh]; };
    return self;
}

+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return @{@"--print-why-not": ^(Core *core, NSArray *a) { return PrintWhyNot(core); }};
}

- (NSDictionary<NSString *, void (^)(NSDictionary *)> *)messages {
    __weak Commands *commands = self.commands;
    return @{
        @"pick": ^(NSDictionary *msg) { [commands pick:msg]; },
        @"compact": ^(NSDictionary *msg) { [commands compact:msg]; },
        @"switchAnswer": ^(NSDictionary *msg) { [commands answerSwitch:msg]; },
    };
}

// Each session's work: a compaction sent from the panel that hasn't ended, and a pick its details show until the
// session confirms it. Once the rows are whole, picks for sessions long gone are forgotten.
- (void)rows:(NSArray<Row *> *)rows phase:(RowPhase)phase {
    if (phase == RowPhaseWork) {
        for (Row *row in rows) {
            NSString *sid = row.sessionId;
            if ([self.commands compactingSince:sid]) row.compacting = [self.commands compactingSince:sid];
            row.chosen = [self.commands chosenFor:sid];
        }
    } else if (phase == RowPhaseListed) {
        [self.commands keepPicksOf:rows];
    }
}

@end
