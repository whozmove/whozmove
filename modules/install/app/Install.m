// Install: Whozmove setting itself up as it opens, a step at a time (Install.h).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Install.h"
#import "Files.h"
#import "Log.h"
#import "Printing.h"
#import "LoginItem.h"
#import "LaunchdFacts.h"

// How often it looks again while it waits for the agent or for Apple's developer tools, which macOS is asked about at
// most every 5 minutes (DeveloperToolsGit), unless its installer for them is open.
static const NSTimeInterval kLookAgain = 10;
// How often it looks again once the agent has said how its hooks stand: you may turn them off or take them out there,
// or back on, while Whozmove runs, and the line says so within minutes. Each look runs the agent's own command, so not
// often.
static const NSTimeInterval kLookAgainSettled = 5 * 60;
// How long Install waits for macOS's installer to show, after asking for it, and how often it looks meanwhile.
static const NSTimeInterval kInstallerWait = 5, kInstallerLook = 0.25;

BOOL InApplications(NSString *app) {
    NSString *path = app.stringByStandardizingPath;
    for (NSString *folder in @[@"/Applications", [Home() stringByAppendingPathComponent:@"Applications"]])
        if ([path hasPrefix:[folder stringByAppendingString:@"/"]]) return YES;
    return NO;
}

// Notes where this app runs from, in Whozmove's folder (`app`), where the hooks read it: written whole, beside it and
// then moved in, and only when it changed. Nil once it's there, else why not.
static NSString *NoteApp(NSString *app) {
    NSString *file = AppDir(@"app"), *line = [app stringByAppendingString:@"\n"];
    NSString *noted = [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil];
    if ([noted isEqualToString:line]) return nil;
    [NSFileManager.defaultManager createDirectoryAtPath:AppDir(nil) withIntermediateDirectories:YES
                                             attributes:@{NSFilePosixPermissions: @0700} error:nil];
    return [line writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil]
        ? nil : @"couldn't note where Whozmove runs from";
}

// The module's own record, in Whozmove's folder (install.json) rather than the app's preferences, which a print run's
// $HOME doesn't reach: when the hooks were first found in the agent, so ones you take out later aren't put back; and
// what the last check found and since when, so that time holds across launches while it stays so.
static NSDictionary *Record(void) {
    return AsRecord(ReadJSON(AppDir(@"install.json"))) ?: @{};
}

static void KeepRecord(NSDictionary *record) {
    [NSFileManager.defaultManager createDirectoryAtPath:AppDir(nil) withIntermediateDirectories:YES
                                             attributes:@{NSFilePosixPermissions: @0700} error:nil];
    NSData *json = [NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingSortedKeys error:nil];
    if (![json writeToFile:AppDir(@"install.json") atomically:YES]) LogProblem(@"install: couldn't keep its record");
}

@interface Install ()
@property (copy) NSString *app, *hooks;
@property (assign) BOOL agentBuild;
@property (strong) dispatch_queue_t queue;
@property (assign) NSInteger queued;  // checks queued or under way, counted on the main thread
@property (strong) NSDictionary *found;
@property (assign) NSTimeInterval checkedAt;
@property (copy) NSString *said;  // the outcome last said in the log, on the queue
@property (assign) BOOL wasInstalling;  // on the queue: macOS's installer was open at the last look, the tools not in
@end

@implementation Install

- (instancetype)initWithApp:(NSString *)app builtByAgent:(BOOL)agentBuild hooks:(NSString *)hooks {
    if (!(self = [super init])) return nil;
    self.app = app;
    self.agentBuild = agentBuild;
    self.hooks = hooks;
    self.queue = dispatch_queue_create("whozmove.install", DISPATCH_QUEUE_SERIAL);
    return self;
}

- (BOOL)working {
    return self.queued > 0;
}

- (void)check:(NSString *)answer {
    self.queued++;
    dispatch_async(self.queue, ^{
        NSDictionary *found = [self go:answer];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.queued--;
            self.found = found;
            self.checkedAt = NSDate.date.timeIntervalSince1970;
            if (self.onFound) self.onFound(found);
        });
    });
}

- (void)tick {
    NSString *state = self.found[@"state"];
    BOOL waiting = [@[@"noTools", @"installing", @"noCommand"] containsObject:state ?: @""]
                || [self.found[@"tools"] isEqualToString:@"installing"];
    BOOL settled = [@[@"ready", @"added", @"updated", @"turnedOff", @"removed", @"failed"] containsObject:state ?: @""];
    if (self.queued || !(waiting || settled)) return;
    if (NSDate.date.timeIntervalSince1970 - self.checkedAt < (waiting ? kLookAgain : kLookAgainSettled)) return;
    [self check:nil];
}

// On the queue: each step in turn, as the module's README lays them out, each one's outcome said in the log. How
// Apple's developer tools stand is looked at first, wherever this copy runs from, for Git's page on the panel's back,
// where Install works whatever else stands. A copy running from anywhere but an Applications folder changes nothing
// more, as it may be gone tomorrow and the hooks would record nothing then.
- (NSDictionary *)go:(NSString *)answer {
    NSString *tools = [self lookForTools:answer];
    if (!InApplications(self.app)) {
        [self say:[NSString stringWithFormat:@"install: running from %@, not an Applications folder, so nothing is "
                                              "set up", self.app]];
        return @{@"state": @"notInApplications", @"tools": tools};
    }
    NSString *why = NoteApp(self.app);
    if (why) LogProblem([@"install: " stringByAppendingString:why]);
    NSMutableDictionary *record = [Record() mutableCopy];
    BOOL login = [self loginFrom:record];
    NSMutableDictionary *found = [[self stamp:[self setUp:answer tools:tools record:record] tools:tools
                                         record:record] mutableCopy];
    found[@"login"] = @(login);
    return found;
}

#pragma mark Open at Login

// On from the very first open, which has no choice recorded yet; after that, as you set it in the pawn menu. Each
// open puts the login item right, for this app wherever it now runs from; it's never loaded into launchd from here, as
// the next login loads it, and loading it now would start a second copy that bows out.
- (BOOL)loginFrom:(NSMutableDictionary *)record {
    if (!AsNumber(record[@"openAtLogin"])) {
        record[@"openAtLogin"] = @YES;
        KeepRecord(record);
        [self say:@"install: Open at Login turned on, as Whozmove opens for the first time"];
    }
    BOOL on = [record[@"openAtLogin"] boolValue];
    [self putLoginItem:on];
    return on;
}

// On: the login item is written, when what it holds differs. Off: it's taken out, and its job unloaded, unless this
// very copy is the one launchd runs for it, which would stop it.
- (void)putLoginItem:(BOOL)on {
    if (!self.label.length || !self.program.length) return;
    if (on) {
        BOOL wrote = NO;
        NSString *why = KeepLoginItem(self.label, self.program, &wrote);
        if (why) LogProblem([@"install: " stringByAppendingString:why]);
        else if (wrote) PanelLog(@"install: login item written, to open %@ at login", self.program);
        return;
    }
    if (!RemoveLoginItem(self.label)) return;
    PanelLog(@"install: login item taken out");
    NSString *job = LaunchdJob(self.label);
    NSString *printed = self.launchctl ? self.launchctl(@[@"print", job]) : nil;
    if (printed && LoginJobPid(printed) != getpid()) self.launchctl(@[@"bootout", job]);
}

- (void)openAtLogin:(BOOL)on {
    self.queued++;
    dispatch_async(self.queue, ^{
        NSMutableDictionary *record = [Record() mutableCopy];
        record[@"openAtLogin"] = @(on);
        KeepRecord(record);
        BOOL here = InApplications(self.app);
        if (here) [self putLoginItem:on];
        PanelLog(@"install: Open at Login turned %@", on ? @"on" : @"off");
        dispatch_async(dispatch_get_main_queue(), ^{
            self.queued--;
            NSMutableDictionary *found = [self.found mutableCopy] ?: [NSMutableDictionary dictionary];
            if (here) found[@"login"] = @(on);
            self.found = found;
            if (self.onFound) self.onFound(found);
        });
    });
}

// Apple's developer tools: in, missing, or installing while macOS's installer for them is open. While it's open, and at
// the look after it closes, macOS is asked again at each look (every 10 seconds), rather than at most every 5 minutes,
// so they're found as soon as they're in; closed without them, they're missing again, and Install is offered again.
// Install (`tools`) has macOS open it, unless it's open already or they're in, and waits a moment for it to show.
- (NSString *)lookForTools:(NSString *)answer {
    BOOL open = self.installer();
    if ([answer isEqualToString:@"tools"] && !open && !self.tools(YES)) {
        self.askTools();
        for (NSTimeInterval waited = 0; !open && waited < kInstallerWait; waited += kInstallerLook) {
            [NSThread sleepForTimeInterval:kInstallerLook];
            open = self.installer();
        }
        if (!open) LogProblem(@"install: macOS's installer for the developer tools didn't open");
    }
    BOOL in = self.tools(open || self.wasInstalling);
    self.wasInstalling = open && !in;
    return in ? @"in" : open ? @"installing" : @"missing";
}

// The rest, from an Applications folder: the agent is looked for before Apple's developer tools are asked for, as only
// its sessions need them, and nothing of Whozmove's runs the agent before the tools are in, as it may run git.
- (NSDictionary *)setUp:(NSString *)answer tools:(NSString *)tools record:(NSMutableDictionary *)record {
    if (!self.agentHere()) {
        [self say:@"install: waiting for the agent, which isn't on this Mac"];
        return @{@"state": @"noCommand"};
    }
    if (![tools isEqualToString:@"in"]) {
        BOOL installing = [tools isEqualToString:@"installing"];
        [self say:installing ? @"install: waiting for macOS's installer to put Apple's developer tools in"
                             : @"install: waiting for Apple's command line developer tools"];
        return @{@"state": installing ? @"installing" : @"noTools"};
    }
    if (self.agentBuild) {
        [self say:@"install: an agent made this build, so its hooks are left as they are"];
        return @{@"state": @"agentBuild"};
    }
    // Only the agent's own presses are its business: Install has been done with by now.
    NSString *press = [@[@"addBack", @"turnOn", @"retry"] containsObject:answer ?: @""] ? answer : nil;
    BOOL before = record[@"connectedAt"] != nil;
    NSDictionary *found = (self.connect ? self.connect(press, before, self.hooks) : nil)
        ?: @{@"state": @"failed", @"detail": @"There's no agent to put the hooks into"};
    NSString *state = AsText(found[@"state"]) ?: @"failed";
    NSNumber *now = @((long long)(NSDate.date.timeIntervalSince1970 * 1000));
    if (!before && [@[@"ready", @"added", @"updated", @"turnedOff"] containsObject:state]) {
        record[@"connectedAt"] = now;
        KeepRecord(record);
    }
    // When they last went in (the first time, put back, or turned on again): sessions running since before then run
    // without them until they reload them.
    if ([state isEqualToString:@"added"]) {
        record[@"addedAt"] = now;
        KeepRecord(record);
    }
    NSString *detail = AsText(found[@"detail"]);
    [self say:[NSString stringWithFormat:@"install: hooks %@%@", state,
                                         detail ? [@": " stringByAppendingString:detail] : @""]];
    return found;
}

// What was found, with since when it has been so: kept in the record while it stays so, across launches too, and the
// time now once it changes. A × on the line holds for that time (the page keeps it), so a message you've put away
// comes back only once something has changed and changed back.
- (NSDictionary *)stamp:(NSDictionary *)found tools:(NSString *)tools record:(NSMutableDictionary *)record {
    NSString *state = AsText(found[@"state"]) ?: @"failed";
    NSNumber *since = AsNumber(record[@"since"]);
    if (!since || ![AsText(record[@"state"]) isEqualToString:state]) {
        since = @((long long)(NSDate.date.timeIntervalSince1970 * 1000));
        record[@"state"] = state;
        record[@"since"] = since;
        KeepRecord(record);
    }
    NSMutableDictionary *stamped = [found mutableCopy];
    stamped[@"state"] = state;
    stamped[@"since"] = since;
    stamped[@"tools"] = tools;
    // Only once they've really gone in from here: hooks found already in (put in before, by an earlier install, say)
    // went in before any session now open, as far as can be told.
    NSNumber *hooksAt = AsNumber(record[@"addedAt"]);
    if (hooksAt) stamped[@"hooksAt"] = hooksAt;
    return stamped;
}

// An outcome in the log, unless it's the one said last: while it waits, it looks every 10 seconds, and the log is
// cleared once it's full (Log.m), with everything else in it.
- (void)say:(NSString *)line {
    if ([line isEqualToString:self.said]) return;
    self.said = line;
    PanelLog(@"%@", line);
}

@end

#pragma mark What the panel's back says

// A card on the panel's back: a word or two on how it stands, a line under its heading, whether all's well, and its
// button with what a press asks, if it has one.
static NSDictionary *Card(NSString *said, NSString *note, BOOL ok, NSString *button, NSString *action, BOOL busy) {
    NSMutableDictionary *card = [@{@"said": said, @"note": note, @"ok": @(ok), @"busy": @(busy)} mutableCopy];
    if (button) {
        card[@"button"] = button;
        card[@"action"] = action;
    }
    return card;
}

NSDictionary *ToolsCard(NSString *tools, BOOL busy) {
    if ([tools isEqualToString:@"in"]) return Card(@"Installed", @"Git runs from them.", YES, nil, nil, busy);
    if ([tools isEqualToString:@"installing"])
        return Card(@"Installing…", @"macOS's installer is putting them in.", NO, nil, nil, busy);
    return Card(@"Not installed", @"Git needs them, and macOS installs them in a few minutes.", NO, @"Install",
                @"tools", busy);
}

// What went wrong, as the agent said it, made a sentence of.
static NSString *Sentence(NSString *text) {
    text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [text hasSuffix:@"."] || [text hasSuffix:@"!"] || [text hasSuffix:@"?"] ? text
                                                                                   : [text stringByAppendingString:@"."];
}

NSDictionary *PluginCard(NSDictionary *found, BOOL busy) {
    NSString *state = AsText(found[@"state"]), *detail = AsText(found[@"detail"]);
    if (!state) return Card(@"Checking…", @"", NO, nil, nil, busy);
    if ([@[@"ready", @"added", @"updated"] containsObject:state])
        return Card(@"Connected", @"Sessions you start record what they do, for their rows here.", YES, nil, nil,
                    busy);
    if ([state isEqualToString:@"noTools"])
        return Card(@"Waiting", @"It runs on Apple's developer tools: install them to see what each session is doing.",
                    NO, @"Install", @"tools", busy);
    if ([state isEqualToString:@"installing"])
        return Card(@"Waiting", @"Waiting for Apple's developer tools to finish installing.", NO, nil, nil, busy);
    if ([state isEqualToString:@"turnedOff"])
        return Card(@"Off", @"Turn it on to see what each session is doing, and answer its requests here.", NO,
                    @"Turn On", @"turnOn", busy);
    if ([state isEqualToString:@"removed"])
        return Card(@"Not added", @"Add it back to see what each session is doing, and answer its requests here.", NO,
                    @"Add", @"addBack", busy);
    if ([state isEqualToString:@"noCommand"])
        return Card(@"Not found", @"Claude Code isn't on this Mac.", NO, @"Get Claude Code", @"getAgent", busy);
    if ([state isEqualToString:@"notInApplications"])
        return Card(@"Not set up", @"Whozmove sets it up once it runs from your Applications folder.", NO, nil, nil,
                    busy);
    if ([state isEqualToString:@"agentBuild"])
        return Card(@"Left as it is", @"An agent made this build of Whozmove, so it leaves the plugin as it is.", NO,
                    nil, nil, busy);
    return Card(@"Not connected", detail ? [@"Couldn't connect: " stringByAppendingString:Sentence(detail)]
                                         : @"Couldn't connect to Claude Code.",
                NO, @"Try Again", @"retry", busy);
}

#pragma mark The print modes

// What each case sets up: where the app runs from (~ for $HOME), whether an agent made it, the answers in turn (the
// last one standing) to whether the agent is on this Mac (`here`), whether the developer tools are and whether macOS's
// installer for them is open, and the agent's own; whether the hooks went in before, how many times it looks in all
// (the ticks' looks after the first), your presses on the line, made one straight after the other, and whether it's
// opened again after (`again`, the next launch, from what it recorded).
static NSDictionary<NSString *, NSDictionary *> *InstallCases(void) {
    return @{
        @"applications": @{@"app": @"~/Applications/Whozmove.app", @"agent": @[@"added"]},
        @"nested": @{@"app": @"/Applications/Tools/Whozmove.app", @"agent": @[@"ready"]},
        @"downloads": @{@"app": @"~/Downloads/Whozmove.app"},
        @"disk-image": @{@"app": @"/Volumes/Whozmove/Whozmove.app"},
        @"translocated": @{@"app": @"/private/var/folders/zz/T/AppTranslocation/0A1B2C/d/Whozmove.app"},
        @"build-folder": @{@"app": @"~/Applications/../whozmove/build/Whozmove.app"},
        @"agent-build": @{@"app": @"~/Applications/Whozmove.app", @"agentBuild": @YES},
        @"no-agent-yet": @{@"app": @"~/Applications/Whozmove.app", @"here": @[@NO, @YES], @"agent": @[@"added"],
                           @"looks": @2},
        @"tools-later": @{@"app": @"~/Applications/Whozmove.app", @"tools": @[@NO, @YES], @"agent": @[@"added"],
                          @"looks": @2},
        @"neither-yet": @{@"app": @"~/Applications/Whozmove.app", @"here": @[@NO, @YES], @"tools": @[@NO, @NO, @YES],
                          @"agent": @[@"added"], @"looks": @3},
        @"no-command-yet": @{@"app": @"~/Applications/Whozmove.app", @"agent": @[@"noCommand", @"added"],
                             @"looks": @2},
        @"taken-out": @{@"app": @"~/Applications/Whozmove.app", @"before": @YES, @"agent": @[@"removed"]},
        @"turned-off": @{@"app": @"~/Applications/Whozmove.app", @"agent": @[@"turnedOff"]},
        @"turned-off-again": @{@"app": @"~/Applications/Whozmove.app", @"agent": @[@"turnedOff"], @"again": @YES},
        @"presses": @{@"app": @"~/Applications/Whozmove.app", @"before": @YES,
                      @"agent": @[@"removed", @"added", @"ready"], @"presses": @[@"addBack", @"retry"]},
        @"install-pressed": @{@"app": @"~/Applications/Whozmove.app", @"tools": @[@NO, @NO, @NO, @NO, @YES],
                              @"installer": @[@NO, @NO, @YES, @YES, @NO], @"agent": @[@"added"],
                              @"presses": @[@"tools"], @"looks": @3},
        @"installer-closed": @{@"app": @"~/Applications/Whozmove.app", @"tools": @[@NO],
                               @"installer": @[@NO, @NO, @YES, @NO], @"presses": @[@"tools"], @"looks": @3},
        @"tools-in-first": @{@"app": @"~/Applications/Whozmove.app", @"tools": @[@NO, @YES],
                             @"agent": @[@"added"], @"presses": @[@"tools"]},
        @"install-without-agent": @{@"app": @"~/Applications/Whozmove.app", @"here": @[@NO], @"tools": @[@NO],
                                    @"installer": @[@NO, @NO, @YES], @"presses": @[@"tools"]},
        @"install-outside": @{@"app": @"~/Downloads/Whozmove.app", @"tools": @[@NO],
                              @"installer": @[@NO, @NO, @YES], @"presses": @[@"tools"]},
        // Open at Login: the very first open turns it on; after that it's as you set it.
        @"login-first": @{@"app": @"~/Applications/Whozmove.app", @"login": @{}},
        @"login-kept": @{@"app": @"~/Applications/Whozmove.app", @"login": @{@"chosen": @YES, @"file": @"same"}},
        @"login-moved": @{@"app": @"/Applications/Whozmove.app", @"login": @{@"chosen": @YES, @"file": @"elsewhere"}},
        @"login-chosen-off": @{@"app": @"~/Applications/Whozmove.app",
                               @"login": @{@"chosen": @NO, @"file": @"same", @"launchd": @"none"}},
        @"login-turned-off": @{@"app": @"~/Applications/Whozmove.app",
                               @"login": @{@"launchd": @"another"}, @"presses": @[@"loginOff"]},
        @"login-turned-off-in-its-copy": @{@"app": @"~/Applications/Whozmove.app",
                                           @"login": @{@"launchd": @"this"}, @"presses": @[@"loginOff"]},
        @"login-turned-on-again": @{@"app": @"~/Applications/Whozmove.app",
                                    @"login": @{@"chosen": @NO, @"launchd": @"none"}, @"presses": @[@"loginOn"]},
        @"login-outside": @{@"app": @"~/Downloads/Whozmove.app", @"login": @{}, @"presses": @[@"loginOn"]},
    };
}

// Runs the main run loop until `install` has no check queued or under way, 10 seconds at most.
static void Settle(Install *install) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:10];
    while (install.working && until.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

// The next of a stand-in's answers, the last one standing once the others are used up.
static id Next(NSMutableArray *answers, NSObject *lock) {
    @synchronized (lock) {
        id answer = answers.firstObject;
        if (answers.count > 1) [answers removeObjectAtIndex:0];
        return answer;
    }
}

// `Whozmove --print-install <case>…`: each case set up with stand-ins for where the app runs from, whether an agent
// made it, the agent, Apple's developer tools and macOS's installer for them, and checked as the app checks as it
// opens; then, as JSON, what each look found (how the developer tools stood, and whether since when it had been so was
// new or kept), what the agent was asked, in order (each call's start and end, so two never overlap), how macOS was
// asked about the tools, and what was noted in Whozmove's folder in $HOME, which each case starts without.
// modules/install/tests/test.sh checks it. It writes in Whozmove's folder there, so it refuses to run in your own home
// folder.
int PrintInstall(NSArray<NSString *> *cases) {
    if (HomeIsYourOwn()) {
        fprintf(stderr, "--print-install writes into Whozmove's folder in $HOME: run it with a throwaway HOME, as "
                        "modules/install/tests/test.sh does\n");
        return 2;
    }
    NSDictionary<NSString *, NSDictionary *> *setups = InstallCases();
    NSMutableArray *printed = [NSMutableArray array];
    for (NSString *name in cases) {
        NSDictionary *setup = setups[name];
        if (!setup) {
            fprintf(stderr, "no case named %s\n", name.UTF8String);
            return 2;
        }
        [NSFileManager.defaultManager removeItemAtPath:AppDir(@"app") error:nil];
        [NSFileManager.defaultManager removeItemAtPath:AppDir(@"install.json") error:nil];
        if ([setup[@"before"] boolValue]) KeepRecord(@{@"connectedAt": @1});
        // The login item's case: the choice recorded before (none: the very first open), the file already there (as
        // this app's, or another place's), and the copy launchd runs for its job, which launchctl's stand-in says.
        NSDictionary *login = setup[@"login"];
        NSString *label = @"com.whozmove.app";
        [NSFileManager.defaultManager removeItemAtPath:LoginItemPath(label) error:nil];
        NSMutableArray *launchctlAsked = [NSMutableArray array];
        NSObject *lock = [NSObject new];
        NSMutableArray *here = [setup[@"here"] ?: @[@YES] mutableCopy];
        NSMutableArray *tools = [setup[@"tools"] ?: @[@YES] mutableCopy];
        NSMutableArray *installer = [setup[@"installer"] ?: @[@NO] mutableCopy];
        NSMutableArray *answers = [setup[@"agent"] ?: @[] mutableCopy];
        NSMutableArray *asked = [NSMutableArray array], *toolsAsked = [NSMutableArray array];
        NSMutableArray *looks = [NSMutableArray array], *since = [NSMutableArray array];
        NSMutableArray *toolsFound = [NSMutableArray array];
        // Since when the last look's state had been so: kept only for the same state, as two looks can fall in one
        // millisecond.
        __block NSNumber *lastSince = nil;
        __block NSString *lastState = nil;
        NSString *app = setup[@"app"];
        if ([app hasPrefix:@"~/"]) app = [Home() stringByAppendingPathComponent:[app substringFromIndex:2]];
        NSString *program = [app stringByAppendingPathComponent:@"Contents/MacOS/Whozmove"];
        if (login[@"chosen"]) KeepRecord(@{@"openAtLogin": login[@"chosen"]});
        BOOL wroteBefore = NO;
        if ([login[@"file"] isEqual:@"same"]) KeepLoginItem(label, program, &wroteBefore);
        if ([login[@"file"] isEqual:@"elsewhere"])
            KeepLoginItem(label, @"/Volumes/Whozmove/Whozmove.app/Contents/MacOS/Whozmove", &wroteBefore);
        NSString *launchd = login[@"launchd"] ?: @"none";
        // Which file was there before, by its number on the disk: a file written again (whole, then moved in) has
        // another.
        id fileBefore = [NSFileManager.defaultManager attributesOfItemAtPath:LoginItemPath(label)
                                                                       error:nil][NSFileSystemFileNumber];
        Install *(^opening)(void) = ^Install * {
            Install *install = [[Install alloc] initWithApp:app builtByAgent:[setup[@"agentBuild"] boolValue]
                                                      hooks:@"<the hooks this app carries>"];
            install.agentHere = ^BOOL { return [Next(here, lock) boolValue]; };
            install.tools = ^BOOL (BOOL now) {
                @synchronized (lock) { [toolsAsked addObject:now ? @"asked now" : @"as last asked"]; }
                return [Next(tools, lock) boolValue];
            };
            install.installer = ^BOOL { return [Next(installer, lock) boolValue]; };
            install.askTools = ^{
                @synchronized (lock) { [toolsAsked addObject:@"asked to install them"]; }
            };
            install.connect = ^NSDictionary *(NSString *answer, BOOL before, NSString *hooks) {
                NSString *call = [NSString stringWithFormat:@"%@, before %@", answer ?: @"at launch",
                                                            before ? @"yes" : @"no"];
                @synchronized (lock) { [asked addObject:[@"start: " stringByAppendingString:call]]; }
                [NSThread sleepForTimeInterval:0.05];
                NSString *state = Next(answers, lock) ?: @"ready";
                @synchronized (lock) { [asked addObject:[@"end: " stringByAppendingString:call]]; }
                return @{@"state": state};
            };
            if (login) {
                install.label = label;
                install.program = program;
                install.launchctl = ^NSString *(NSArray<NSString *> *arguments) {
                    NSString *job = LaunchdJob(label);
                    NSString *said = [[arguments componentsJoinedByString:@" "]
                                      stringByReplacingOccurrencesOfString:job withString:@"gui/<you>/<label>"];
                    @synchronized (lock) { [launchctlAsked addObject:said]; }
                    if (![arguments.firstObject isEqual:@"print"]) return @"";
                    if ([launchd isEqual:@"none"]) return nil;
                    pid_t pid = [launchd isEqual:@"this"] ? getpid() : getpid() + 1;
                    return [NSString stringWithFormat:@"%@ = {\n\tstate = running\n\t%@%d\n}\n", job,
                                                      kLaunchctlPidLine, pid];
                };
            }
            install.onFound = ^(NSDictionary *found) {
                [looks addObject:found[@"state"]];
                [toolsFound addObject:found[@"tools"] ?: NSNull.null];
                NSNumber *at = found[@"since"];
                BOOL kept = [at isEqual:lastSince] && [found[@"state"] isEqual:lastState];
                [since addObject:!at ? @"none" : kept ? @"kept" : @"new"];
                if (at) lastSince = at;
                lastState = found[@"state"];
            };
            return install;
        };
        Install *install = opening();
        [install check:nil];
        for (NSString *press in setup[@"presses"] ?: @[]) {
            if ([press hasPrefix:@"login"]) [install openAtLogin:[press isEqualToString:@"loginOn"]];
            else [install check:press];
        }
        Settle(install);
        for (NSInteger more = [setup[@"looks"] integerValue] - 1; more > 0; more--) {
            [install check:nil];
            Settle(install);
        }
        if ([setup[@"again"] boolValue]) {
            Install *next = opening();
            [next check:nil];
            Settle(next);
        }
        NSString *noted = [NSString stringWithContentsOfFile:AppDir(@"app") encoding:NSUTF8StringEncoding error:nil];
        noted = [[noted stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
                 stringByReplacingOccurrencesOfString:Home() withString:@"~"];
        NSDictionary *record = Record();
        NSMutableDictionary *result = [@{@"case": name, @"found": looks, @"since": since, @"tools": toolsFound,
                                         @"tools asked": toolsAsked, @"asked": asked, @"noted": noted ?: NSNull.null,
                                         @"connected": record[@"connectedAt"] ? @"recorded" : @"not recorded",
                                         @"went in": record[@"addedAt"] ? @"recorded" : @"not recorded"} mutableCopy];
        if (login) {
            NSDictionary *file = [NSDictionary dictionaryWithContentsOfFile:LoginItemPath(label)];
            NSString *opens = [AsText(AsList(file[@"ProgramArguments"]).firstObject)
                               stringByReplacingOccurrencesOfString:Home() withString:@"~"];
            id fileAfter = [NSFileManager.defaultManager attributesOfItemAtPath:LoginItemPath(label)
                                                                          error:nil][NSFileSystemFileNumber];
            result[@"login"] = @{@"chosen": record[@"openAtLogin"] ?: NSNull.null,
                                 @"written now": @(fileAfter && ![fileAfter isEqual:fileBefore]),
                                 @"file": !file ? @"none" : [file isEqual:LoginItemContents(label, program)]
                                     ? @"this app's" : @"something else",
                                 @"opens": opens ?: NSNull.null,
                                 @"restarts after": file ? [AsRecord(file[@"KeepAlive"]).allKeys
                                                            componentsJoinedByString:@", "] : NSNull.null,
                                 @"launchctl asked": launchctlAsked};
        }
        [printed addObject:result];
    }
    return PrintJSON(printed);
}

// `Whozmove --print-install-cards`: what the panel's back says on Git's page for each way the developer tools can
// stand, and on the agent's for each state of its hooks (a failure with what the agent said, and with nothing), with
// a press under way for one of them.
int PrintInstallCards(void) {
    NSMutableArray *git = [NSMutableArray array], *agent = [NSMutableArray array];
    for (NSString *tools in @[@"in", @"missing", @"installing"])
        [git addObject:@{@"tools": tools, @"card": ToolsCard(tools, NO)}];
    [git addObject:@{@"tools": @"missing, Install pressed", @"card": ToolsCard(@"missing", YES)}];
    NSArray *states = @[@"ready", @"added", @"updated", @"noTools", @"installing", @"turnedOff", @"removed",
                        @"noCommand", @"notInApplications", @"agentBuild"];
    [agent addObject:@{@"state": @"not looked yet", @"card": PluginCard(nil, NO)}];
    for (NSString *state in states) [agent addObject:@{@"state": state, @"card": PluginCard(@{@"state": state}, NO)}];
    NSDictionary *failed = @{@"state": @"failed", @"detail": @"Marketplace whozmove failed to load: cache-miss"};
    [agent addObject:@{@"state": @"failed, with what it said", @"card": PluginCard(failed, NO)}];
    [agent addObject:@{@"state": @"failed, saying nothing", @"card": PluginCard(@{@"state": @"failed"}, NO)}];
    [agent addObject:@{@"state": @"removed, Add pressed", @"card": PluginCard(@{@"state": @"removed"}, YES)}];
    return PrintJSON(@{@"git": git, @"agent": agent});
}
