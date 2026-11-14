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
#import "Command.h"
#import "Modules.h"
#import "Send.h"
#import "Text.h"
#import "Files.h"
#import "Links.h"
#import "Processes.h"
#import "Allowed.h"
#import "CompactTime.h"
#import "Focus.h"

// A terminal that answers for a session's tab without being asked, for --print-why-not: under the panel's first
// terminal's name, with the tab found and certainly the session's, and no reason of its own, nor a way past one,
// unless a variant says otherwise.
@interface SampleTerminal : NSObject <TypingHost>
@property (strong) NSString *name, *whyNot, *wayPast;
@property (assign) BOOL found, unique;
@end

@implementation SampleTerminal
- (NSString *)appId { return @"sample"; }
- (BOOL)open:(Row *)row { return NO; }
- (NSString *)tabFor:(Row *)row unique:(BOOL *)unique { *unique = self.unique; return self.found ? @"tab" : nil; }
- (void)type:(NSString *)text inTab:(NSString *)tab {}
- (void)press:(TerminalKey)key times:(NSInteger)times inTab:(NSString *)tab {}
- (NSString *)whyNotTypeIn:(NSString *)tab { return self.whyNot; }
- (NSString *)wayPastIn:(NSString *)tab { return self.wayPast; }
- (void)takeWayPastIn:(NSString *)tab done:(void (^)(NSString *, BOOL))done {}
@end

// A session's reach as the menus find it (Send's SessionReach, all as the sample home has it: whether an app keeps it
// as a conversation, its first message, whether it's open twice, why keys can't go in now, the terminals' names), but
// for what can't be asked in a test: its terminal and tab are a SampleTerminal's (none when `terminal` is nil), and
// Whozmove may control Claude, never asked of macOS. A variant can say its first message is sent, that it's open
// elsewhere too, or in another terminal, that it's paused in its terminal, or that a change from the panel is still
// going in.
@interface SampleReach : SessionReach
@property (strong) SampleTerminal *sample;
@property (assign) BOOL allowed, pausedNow, changingNow;
@property (strong) NSNumber *startedNow, *openElsewhereNow, *openTwiceNow;
@end

@implementation SampleReach
- (id<TypingHost>)typing { return self.desktop ? nil : self.sample; }
- (Reason *)whyNotType { return self.pausedNow ? [Reason kind:ReasonPaused] : super.whyNotType; }
- (BOOL)changing { return self.changingNow || super.changing; }
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

// What a row's menus, Compact card and next steps would say about why nothing can go in now (null: it can), and the
// button past it the menus and the card would offer, only where they would.
static NSDictionary *WhyNotOf(Row *row, SampleReach *reach, BOOL compacting, Core *core) {
    NSMutableDictionary *said = [NSMutableDictionary dictionary];
    for (NSString *field in @[@"model", @"effort", @"mode"]) {
        NSArray *cycles = [field isEqual:@"mode"] && !reach.desktop
            ? [(id<AgentCommands>)[core agentOf:row] modeCyclesFor:row] : nil;
        said[[@"pick " stringByAppendingString:field]] = WhyNoPick(row, field, reach, cycles) ?: NSNull.null;
    }
    said[@"compact"] = WhyNoCompact(reach, compacting) ?: NSNull.null;
    said[@"ask"] = WhyNoAsk(reach) ?: NSNull.null;
    NSString *way = WayPast(reach, WhyNoCompact(reach, compacting));
    if (way) said[@"way past"] = way;
    return said;
}

// `Whozmove --print-why-not`: for each session in $HOME, what its model, effort and mode menus, its Compact card and
// its next steps (Send's WhyNoAsk) would say about why nothing can go into it now (null: something can), with the
// session's reach as the menus find it in the sample home (SampleReachOf); then the same for a terminal session and a
// Claude Desktop conversation with parts of their reach changed; and what each session's mode menu says under each of
// the switches at its foot (what it does, or why it can't be turned on and the way past that it offers), which go by
// none of those, as nothing is typed for them; and the item that turns back on the switches that went off as Whozmove
// restarted, for a sample lead (not in your own home). As JSON, then quit. tests/rows.sh checks them: the
// wording, and the order things are looked at in, is what keeps a key from going where it shouldn't.
static int PrintWhyNot(Core *core) {
    NSMutableDictionary *found = [NSMutableDictionary dictionary];
    NSMutableDictionary *out = [@{@"as found": found} mutableCopy];
    NSMutableDictionary<NSString *, Row *> *byId = [NSMutableDictionary dictionary];
    for (Row *row in SettledRows(core)) {
        if (!row.sessionId) continue;
        byId[row.sessionId] = row;
        SampleReach *reach = SampleReachOf(row, core);
        found[row.sessionId] = WhyNotOf(row, reach, NO, core);
        for (SessionSwitch *each in [core.allowed switchesFor:row]) {
            NSMutableDictionary *says = out[each.title] ?: (out[each.title] = [NSMutableDictionary dictionary]);
            NSString *why = each.whyNot ? each.whyNot(row) : nil;
            // With the way past it the menu offers under it, when its module has one.
            if (why && each.way && each.wayTitle) why = [NSString stringWithFormat:@"%@ · %@", why, each.wayTitle];
            says[row.sessionId] = why ?: each.line;
        }
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
    variant(@"s-clone", @"its terminal's own reason", NO, ^(SampleReach *r) {
        r.sample.whyNot = @"Its window has other tabs, which the terminal could type into";
    });
    // A way past the terminal's reason is offered beside that reason only: not for a tab that isn't found, nor beside
    // another reason that comes first.
    variant(@"s-clone", @"its terminal's own reason, with a way past it", NO, ^(SampleReach *r) {
        r.sample.whyNot = @"Its window has other tabs, which the terminal could type into";
        r.sample.wayPast = @"Turn On the Terminal's Way Past…";
    });
    variant(@"s-clone", @"its tab not found, with its terminal's reason and a way past it", NO, ^(SampleReach *r) {
        r.sample.found = NO;
        r.sample.whyNot = @"Whozmove is asking macOS whether it may control the terminal";
        r.sample.wayPast = @"Turn On the Terminal's Way Past…";
    });
    variant(@"s-clone", @"paused, with its terminal's reason and a way past it", NO, ^(SampleReach *r) {
        r.pausedNow = YES;
        r.sample.whyNot = @"Its window has other tabs, which the terminal could type into";
        r.sample.wayPast = @"Turn On the Terminal's Way Past…";
    });
    variant(@"s-clone", @"its tab not found, with its terminal's reason", NO, ^(SampleReach *r) {
        r.sample.found = NO;
        r.sample.whyNot = @"Whozmove is asking macOS whether it may control the terminal";
    });
    // A session paused in its terminal is out of its foreground, where a terminal may find no tab for it: the pause is
    // what's said.
    variant(@"s-clone", @"paused in its terminal, its tab not found", NO, ^(SampleReach *r) {
        r.pausedNow = YES;
        r.sample.found = NO;
    });
    // A change from the panel still going in comes before its tab and its terminal's reason, in a terminal and in
    // Claude Desktop alike.
    variant(@"s-clone", @"a change from the panel still going in", NO, ^(SampleReach *r) {
        r.changingNow = YES;
        r.sample.whyNot = @"Its window has other tabs, which the terminal could type into";
    });
    variant(@"s-desk", @"its first message sent, a change from the panel still going in", NO, ^(SampleReach *r) {
        r.startedNow = @YES;
        r.changingNow = YES;
    });
    // The terminal's own reason comes before what the session is doing.
    variant(@"s-topic", @"working, with its terminal's own reason", NO, ^(SampleReach *r) {
        r.sample.whyNot = @"Its window has other tabs, which the terminal could type into";
    });
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
    // Words say: won't send, as Claude would take them as a command, once they're made one plain line; and words it
    // sends, though they have one of those characters later on.
    NSMutableDictionary *commands = [NSMutableDictionary dictionary];
    for (NSArray<NSString *> *each in @[@[@"/exit", @"/exit"], @[@"a shell line", @"!rm -rf build"],
                                        @[@"a memory", @"# remember this"], @[@"&", @"& later"],
                                        @[@"spaces, then /clear", @"  /clear"],
                                        @[@"a zero-width space, then /exit", @"\u200B/exit"],
                                        @[@"a next step's words", @"Commit the changes."],
                                        @[@"/ later on", @"Is 2/3 done?"], @[@"# later on", @"What does #12 say?"]])
        commands[each[0]] = @(WordsRunACommand(PlainOneLine(each[1], 600)));
    out[@"words that would run a command"] = commands;
    // The item that turns back on what went off as Whozmove restarted, for the team's lead with every switch kept in
    // memory ticked in this very process, and every one kept for a folder ticked for a sample folder, shop (a sample
    // ticked.json), open once and twice, and for a member, which isn't offered the switches. This run doesn't work in
    // shop, so a switch kept for it is greyed, saying so. It writes that file, so not in your own home.
    if (!HomeIsYourOwn()) {
        NSString *here = [Home() stringByAppendingPathComponent:@"shop"];
        [NSFileManager.defaultManager createDirectoryAtPath:here withIntermediateDirectories:YES attributes:nil error:nil];
        here = RealPath(here);
        NSMutableDictionary *ticked = [NSMutableDictionary dictionary], *kept = [NSMutableDictionary dictionary];
        for (SessionSwitch *each in core.allowed.switches) {
            if (each.lasts == SwitchLastsWhileRunning)
                ticked[each.key] = @{@"at": @1, @"pid": @(getpid()), @"processStart": @(ProcessStartedAt(getpid()))};
            if (each.lasts == SwitchLastsWorkspace)
                kept[each.key] = @{@"at": @1, @"held": @((long long)(NSDate.date.timeIntervalSince1970 * 1000))};
        }
        [NSFileManager.defaultManager createDirectoryAtPath:AppDir(nil) withIntermediateDirectories:YES
                                                 attributes:@{NSFilePosixPermissions: @0700} error:nil];
        [[NSJSONSerialization dataWithJSONObject:@{@"s-restarted": ticked, @"workspaces": @{here: kept}} options:0
                                           error:nil] writeToFile:AppDir(@"ticked.json") atomically:YES];
        [core.allowed keepTickedAt:AppDir(@"ticked.json")];
        NSMutableDictionary *turnBack = [NSMutableDictionary dictionary];
        for (NSArray *each in @[@[@"the team's lead, open once", @"lead", @NO],
                                @[@"the team's lead, open twice", @"lead", @YES],
                                @[@"a member of the team", @"member", @NO]]) {
            Row *row = [[Row alloc] initWithFields:@{@"sessionId": @"s-restarted", @"pid": @(getpid()), @"cwd": here}];
            row.team = @{@"role": each[1]};
            if ([each[2] boolValue]) row.alsoOpen = @[@{@"entrypoint": @"cli"}];
            turnBack[each[0]] = TurnBackOnItem(core.allowed, row) ?: NSNull.null;
        }
        out[@"Turn Back On"] = turnBack;
        // What a press on each switch kept for a folder does, on a row in that folder where it's kept (its dash) and on
        // one in another: it turns on only where nothing is kept, so a press on a dash never ticks.
        NSMutableDictionary *press = [NSMutableDictionary dictionary];
        Row *there = [[Row alloc] initWithFields:@{@"sessionId": @"s-restarted", @"pid": @(getpid()), @"cwd": here}];
        Row *elsewhere = [[Row alloc] initWithFields:@{@"sessionId": @"s-elsewhere", @"pid": @(getpid()),
                                                       @"cwd": AppDir(nil)}];
        there.team = elsewhere.team = @{@"role": @"lead"};
        for (SessionSwitch *each in core.allowed.switches)
            if (each.lasts == SwitchLastsWorkspace) {
                BOOL dash = SwitchPressTurnsOn(core.allowed, each.key, there);
                BOOL none = SwitchPressTurnsOn(core.allowed, each.key, elsewhere);
                press[each.title] = @{@"kept, its dash": dash ? @"on" : @"off", @"not kept": none ? @"on" : @"off"};
            }
        out[@"a press on a switch kept for a folder turns it"] = press;
    }
    return PrintJSON(out);
}

// `Whozmove --print-compact-time`: whether CompactTime says now is a good time to compact each sample session, and
// why (null: not now), as JSON, then quit. Each case is the sample's row with a few fields changed. tests/rows.sh checks
// them: the breaks, and everything that's never one.
static int PrintCompactTime(void) {
    double now = 1760000000000, minute = 60000;
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSDictionary *(^opus)(NSInteger) = ^(NSInteger tokens) {
        return @{@"model": @"claude-opus-5-5", @"tokens": @(tokens), @"window": @1000000};
    };
    void (^show)(NSString *, NSDictionary *, double, BOOL, double, void (^)(Row *)) =
        ^(NSString *name, NSDictionary *agent, double onItAt, BOOL focused, double compactedAt, void (^change)(Row *)) {
        Row *row = [Row new];
        row.sessionId = @"s-sample";
        row.status = @"idle";
        row.pid = 101;
        row.agent = agent;
        row.lastPromptAt = @(now - 15 * minute);
        row.lastReplyAt = row.messageAt = @(now - 10 * minute);
        row.git = @{@"root": @"/work/app"};
        if (change) change(row);
        out[name] = CompactTime(row, onItAt, focused, compactedAt, now)[@"why"] ?: NSNull.null;
    };
    void (^ago)(Row *, double) = ^(Row *row, double minutes) {
        row.lastReplyAt = row.messageAt = @(now - minutes * minute);
        row.lastPromptAt = @(now - (minutes + 5) * minute);
    };
    show(@"compact now: nearly full", @{@"model": @"claude-sonnet-5-5", @"tokens": @175000, @"window": @200000},
         0, NO, 0, nil);
    show(@"not now: long, but at no break", opus(450000), 0, NO, 0, nil);
    show(@"compact now: big, its work committed", opus(250000), 0, NO, 0, ^(Row *r) { r.outcome = @"Committed"; });
    show(@"compact now: big, its work merged", opus(250000), 0, NO, 0, ^(Row *r) { r.outcome = @"Merged"; });
    show(@"compact now: big, after an hour away", opus(250000), 0, NO, 0, ^(Row *r) { ago(r, 61); });
    show(@"not now: big, its edits not committed yet", opus(250000), 0, NO, 0, ^(Row *r) {
        r.workEditedAt = now - 10 * minute;
        r.workRoot = @"/work/app";
        r.checkout = @{@"changes": @3};
    });
    show(@"compact now: big, its edits in its own checkout all committed", opus(250000), 0, NO, 0, ^(Row *r) {
        r.workEditedAt = now - 10 * minute;
        r.workRoot = @"/work/app";
        r.checkout = @{@"changes": @0};
    });
    show(@"not now: big, its edits left in another checkout", opus(250000), 0, NO, 0, ^(Row *r) {
        r.workEditedAt = now - 10 * minute;
        r.workRoot = @"/work/app-x";
        r.checkout = @{@"changes": @0};
    });
    show(@"not now: big, its checkout clean, but when it edited there not known", opus(250000), 0, NO, 0, ^(Row *r) {
        r.workRoot = @"/work/app";
        r.checkout = @{@"changes": @0};
    });
    show(@"not now: committed, but small", opus(150000), 0, NO, 0, ^(Row *r) { r.outcome = @"Committed"; });
    show(@"not now: small, after an hour away", opus(150000), 0, NO, 0, ^(Row *r) { ago(r, 61); });
    show(@"compact now: a 200k window, big from 100k, its work committed",
         @{@"model": @"claude-sonnet-5-5", @"tokens": @120000, @"window": @200000}, 0, NO, 0,
         ^(Row *r) { r.outcome = @"Committed"; });
    show(@"compact now: no window given, taken as 200k", @{@"model": @"x", @"tokens": @180000}, 0, NO, 0, nil);
    show(@"not now: big, quiet for an hour, but you were on it since", opus(250000), now - 5 * minute, NO, 0,
         ^(Row *r) { ago(r, 61); });
    show(@"not now: big, quiet for an hour, and it's the one you're on", opus(250000), 0, YES, 0,
         ^(Row *r) { ago(r, 61); });
    show(@"not now: at work", opus(950000), 0, NO, 0, ^(Row *r) { r.status = @"busy"; });
    show(@"not now: asking", opus(950000), 0, NO, 0, ^(Row *r) { r.ask = @{@"id": @"a", @"tool": @"Bash"}; });
    show(@"not now: waiting for you", opus(950000), 0, NO, 0, ^(Row *r) { r.status = @"waiting"; });
    show(@"not now: compacting", opus(950000), 0, NO, 0, ^(Row *r) { r.compacting = @(now - minute); });
    show(@"not now: ended", opus(950000), 0, NO, 0, ^(Row *r) {
        r.status = @"closed";
        r.pid = 0;
    });
    show(@"not now: a compaction couldn't go in", opus(950000), 0, NO, 0, ^(Row *r) { r.noCompact = YES; });
    show(@"not now: a pick going in", opus(950000), 0, NO, 0, ^(Row *r) {
        r.goingIn = @{@"field": @"model", @"value": @"claude-sonnet-5-5", @"inTerminal": @NO};
    });
    show(@"not now: \"Switch model?\" asked", opus(950000), 0, NO, 0, ^(Row *r) {
        r.switchAsk = @{@"from": @"claude-opus-5-5", @"to": @"claude-sonnet-5-5"};
    });
    show(@"not now: compacted from the panel since its last message", opus(950000), 0, NO, now - 2 * minute,
         ^(Row *r) { r.outcome = @"Committed"; });
    show(@"compact now: compacted from the panel before its last message", opus(250000), 0, NO, now - 30 * minute,
         ^(Row *r) { r.outcome = @"Committed"; });
    show(@"not now: nothing known of its size", @{@"model": @"claude-opus-5-5"}, 0, NO, 0,
         ^(Row *r) { r.outcome = @"Committed"; });
    show(@"not now: started before Whozmove's hooks, compacted from the panel, its transcript not moved since",
         opus(950000), 0, NO, now - 5 * minute, ^(Row *r) {
        r.reload = @{@"state": @"needed"};
        r.lastPromptAt = nil;
        r.messageAt = @(now - 5 * minute + 10000);
    });
    show(@"compact now: started before Whozmove's hooks, compacted from the panel, its transcript moved since",
         opus(950000), 0, NO, now - 5 * minute, ^(Row *r) {
        r.reload = @{@"state": @"needed"};
        r.lastPromptAt = nil;
        r.messageAt = @(now - 2 * minute);
    });
    return PrintJSON(out);
}

@interface CommandsModule : NSObject <Module, SessionCompacting>
@property (weak) Core *core;
@property (strong) Commands *commands;
// When you were last on each session, and the one you're on, from the rows as last listed (tick): a read marks its rows
// only after every module's part, so CompactTime goes by the read before.
@property (strong) NSDictionary<NSString *, NSNumber *> *onItAt;
@property (copy) NSString *focusedId;
@end

// `Whozmove --print-command-logs`, in a throwaway home: how panel.log says each kind of command (CommandLogged), and,
// for a /compact whose focus holds a made-up token, that the token is in none of it. Then that /compact is really sent,
// going in by itself, to the session named Compacter in that home, which no terminal or Claude Desktop holds, so it
// goes no further than the line that says why it wasn't sent, as a print run never types or sends anything; and
// whether panel.log has that line and the token. The token is made as it starts and never printed.
// modules/commands/tests/test.sh compares it with a recorded copy.
static int PrintCommandLogs(Core *core) {
    if (HomeIsYourOwn()) {
        fprintf(stderr, "--print-command-logs writes Whozmove's log in $HOME: give it a throwaway one\n");
        return 2;
    }
    [NSFileManager.defaultManager createDirectoryAtPath:AppDir(nil) withIntermediateDirectories:YES attributes:nil
                                                  error:nil];
    FILE *file = fopen(AppDir(@"panel.log").fileSystemRepresentation, "w");
    if (file) fclose(file);
    NSString *token = [@"wz-made-up-" stringByAppendingString:NSUUID.UUID.UUIDString];
    NSString *focus = [@"keep what we said about " stringByAppendingString:token];
    void (^say)(NSString *, NSString *) = ^(NSString *what, NSString *said) {
        printf("%s: %s\n", what.UTF8String, said.UTF8String);
    };
    for (NSArray<NSString *> *pick in @[@[@"A model pick", @"model", @"claude-opus-5-5"],
                                        @[@"An effort pick", @"effort", @"high"], @[@"A mode pick", @"mode", @"plan"],
                                        @[@"A /compact with no focus", @"compact", @""]])
        say([pick[0] stringByAppendingString:@", as the log says it"], CommandLogged(pick[1], pick[2]));
    NSString *compact = CommandLogged(@"compact", focus);
    say(@"A /compact with a focus holding a made-up token", [compact containsString:token] ? @"the token's in it"
                                                                                            : compact);
    CommandsModule *module = nil;
    for (id each in core.modules.all)
        if ([each isKindOfClass:CommandsModule.class]) module = each;
    Row *compacter = nil;
    for (Row *row in SettledRows(core))
        if ([row.name isEqual:@"Compacter"]) compacter = row;
    if (!module || !compacter) {
        say(@"Sent to a session", @"no session named Compacter, so only CommandLogged is checked");
        return 0;
    }
    __block NSString *ended = nil;
    [module.commands compactRow:compacter focus:focus stillMay:^BOOL { return YES; }
                       whenOver:^(CompactEnd end, NSString *why) { ended = why ?: @"it went in"; }];
    NSString *log = [NSString stringWithContentsOfFile:AppDir(@"panel.log") encoding:NSUTF8StringEncoding error:nil];
    say(@"Sent to Compacter, going in by itself", ended ? @"not sent" : @"nothing said");
    say(@"…panel.log", [NSString stringWithFormat:@"%@, %@",
        [log containsString:[compact stringByAppendingString:@" not sent by itself"]] ? @"says why it wasn't sent"
                                                                                      : @"has no line for it",
        [log containsString:token] ? @"has the token" : @"hasn't the token"]);
    return 0;
}

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
    return @{@"--print-why-not": ^(Core *core, NSArray *a) { return PrintWhyNot(core); },
             @"--print-compact-time": ^(Core *core, NSArray *a) { return PrintCompactTime(); },
             @"--print-command-logs": ^(Core *core, NSArray *a) { return PrintCommandLogs(core); }};
}

- (NSDictionary<NSString *, void (^)(NSDictionary *)> *)messages {
    __weak Commands *commands = self.commands;
    return @{
        @"pick": ^(NSDictionary *msg) { [commands pick:msg]; },
        @"compact": ^(NSDictionary *msg) { [commands compact:msg]; },
        @"switchAnswer": ^(NSDictionary *msg) { [commands answerSwitch:msg]; },
        // Open Accessibility Settings, on a pick's note when Claude Desktop needs Whozmove allowed there: by your press.
        @"accessibilitySettings": ^(NSDictionary *msg) {
            OpenLink(@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility");
        },
    };
}

// Each session's work: a compaction sent from the panel that hasn't ended, a pick its details show until the session
// confirms it, a pick on its way in and "Switch model?" while it's asked, and whether a compaction certainly couldn't
// go in now. Once the rows are whole, picks for sessions long gone are forgotten.
- (void)rows:(NSArray<Row *> *)rows phase:(RowPhase)phase {
    if (phase == RowPhaseWork) {
        for (Row *row in rows) {
            NSString *sid = row.sessionId;
            // A compaction the panel sent shows from when it was sent. One the hook saw begin before the panel's last
            // had its result was that one, which is over, even if the hook didn't hear it end (stopped with Esc).
            NSNumber *since = [self.commands compactingSince:sid], *answered = [self.commands compactEndedAt:sid];
            if (since) row.compacting = since;
            else if (row.compacting && answered && row.compacting.doubleValue <= answered.doubleValue)
                row.compacting = nil;
            row.chosen = [self.commands chosenFor:sid];
            // A session that has ended has nothing going in, nor a question asked for it.
            BOOL ended = [self.core hasEnded:row];
            row.goingIn = ended ? nil : [self.commands goingIn:sid];
            row.switchAsk = ended ? nil : [self.commands switchQuestionFor:row];
            // After those, as a change still going in is one reason it couldn't.
            row.noCompact = CantCompactNow([self.core.send reachOf:row]);
        }
    } else if (phase == RowPhaseListed) {
        [self.commands keepPicksOf:rows];
        // Whether now is a natural break to compact each one, once its context size is in (RowPhaseDetails).
        double now = NSDate.date.timeIntervalSince1970 * 1000;
        for (Row *row in rows)
            row.compactTime = CompactTime(row, self.onItAt[row.sessionId ?: @""].doubleValue,
                                          [row.sessionId isEqualToString:self.focusedId],
                                          [self.commands compactedAt:row.sessionId].doubleValue, now);
    }
}

- (void)tick {
    NSMutableDictionary *onIt = [NSMutableDictionary dictionary];
    NSString *focused = nil;
    for (Row *row in self.core.rows.byId.allValues) {
        if (!row.sessionId) continue;
        onIt[row.sessionId] = @(row.onItAt);
        if (row.focused) focused = row.sessionId;
    }
    self.onItAt = onIt;
    self.focusedId = focused;
}

#pragma mark SessionCompacting

- (NSString *)whyNotCompact:(Row *)row wayPast:(NSString **)way {
    SessionReach *reach = [self.core.send reachOf:row];
    NSString *why = WhyNoCompact(reach, [self.commands compactingSince:row.sessionId] != nil || row.compacting != nil)
        ?: WhyNotByItself(reach);
    if (way) *way = why ? WayPast(reach, why) : nil;
    return why;
}

- (void)compact:(Row *)row focus:(NSString *)focus stillMay:(BOOL (^)(void))stillMay
       whenOver:(void (^)(CompactEnd end, NSString *why))whenOver {
    [self.commands compactRow:row focus:focus stillMay:stillMay whenOver:whenOver];
}

- (BOOL)compactingAny {
    return self.commands.compactingAny;
}

@end
