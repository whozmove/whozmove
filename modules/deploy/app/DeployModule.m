// DeployModule: Deploy's face for the core (Module): the round button's presses, its set-up card and its menu, each
// row's project and folder kept fresh, Let It Deploy and what a session it's on for asks, and the print modes the
// tests check.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Module.h"
#import "Core.h"
#import "Page.h"
#import "Modules.h"
#import "MenuBar.h"
#import "Rows.h"
#import "Row.h"
#import "Printing.h"
#import "Processes.h"
#import "Deploys.h"
#import "DeployMenu.h"
#import "DeployAsks.h"
#import "DeployKept.h"
#import "Allowed.h"
#import "Files.h"
#import "Git.h"
#import "SessionAsks.h"
#import "Work.h"
#include <signal.h>

// `Whozmove --print-deploys <folder>…`: for each folder, by its name, the command Whozmove suggests for Deploy there
// (null for none), the port a deploy there gets in $PORT, its last run as the page gets it (when it has one), what a
// deploy from it would note it starts from
// now (`now`, in a checkout), and its project's build in place as Deploy keeps it once it reads the folder (`inPlace`,
// when there is one, its folders by their names), as JSON, then quit, keeping nothing. tests/rows.sh and the deploy
// module's tests check them against sample projects and runs.
static int PrintDeploys(NSArray<NSString *> *folders) {
    NSMutableDictionary<NSString *, NSString *> *projectOf = [NSMutableDictionary dictionary];
    for (NSString *folder in folders) projectOf[folder] = ProjectRoot(folder) ?: folder;
    NSDictionary *inPlace = BuildsInPlaceSeen(projectOf);
    NSDictionary *(^named)(NSDictionary *) = ^NSDictionary *(NSDictionary *build) {
        NSMutableDictionary *shown = [build mutableCopy];
        shown[@"folder"] = [build[@"folder"] lastPathComponent];
        if ([build[@"before"] isKindOfClass:NSDictionary.class]) {
            NSMutableDictionary *before = [build[@"before"] mutableCopy];
            before[@"folder"] = [before[@"folder"] lastPathComponent];
            shown[@"before"] = before;
        }
        return shown;
    };
    NSMutableDictionary *deploys = [NSMutableDictionary dictionary];
    for (NSString *folder in folders) {
        NSMutableDictionary *state = [@{@"suggested": SuggestDeploy(folder) ?: NSNull.null} mutableCopy];
        state[@"port"] = DeployPort(projectOf[folder], folder, NO) ?: NSNull.null;
        if (LastDeployRun(folder)) state[@"run"] = LastDeployRun(folder);
        if (BuildNow(folder).count) state[@"now"] = BuildNow(folder);
        NSDictionary *build = inPlace[RealPath(projectOf[folder])];
        if (build) state[@"inPlace"] = named(build);
        deploys[folder.lastPathComponent] = state;
    }
    return PrintJSON(deploys);
}

// `Whozmove --print-deploy-checks <folder> <command>…`: what the set-up card would be told about each command in that
// folder (CheckDeploy), with what would be kept as it's confirmed, as a `fingerprint` (DeployCheckText's SHA-256, its
// first 16 hex digits), by command, as JSON, then quit.
static int PrintDeployChecks(NSArray<NSString *> *arguments) {
    if (!arguments.count) return 2;
    NSMutableDictionary *checks = [NSMutableDictionary dictionary];
    for (NSString *command in [arguments subarrayWithRange:NSMakeRange(1, arguments.count - 1)]) {
        NSMutableDictionary *check = [CheckDeploy(arguments[0], command) mutableCopy];
        check[@"fingerprint"] = [DeployRunsHash(arguments[0], command) substringToIndex:16];
        checks[command] = check;
    }
    return PrintJSON(checks);
}

static int PrintDeployAsks(Core *core, NSArray<NSString *> *arguments);
static int PrintBuildsUp(Core *core, NSArray<NSString *> *arguments);

@interface DeployModule : NSObject <Module, BuildsInPlace>
@property (weak) Core *core;
@property (strong) Deploys *deploys;  // made as the app starts: what it reads and runs is the app's alone
@property (strong) DeployMenu *menu;
@property (strong) DeployAsks *asks;
@property (strong) DeployKept *kept;
@end

@implementation DeployModule

+ (NSString *)moduleName {
    return @"deploy";
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    return self;
}

- (void)launch {
    self.deploys = [[Deploys alloc] initWithPage:self.core.page];
    self.asks = [[DeployAsks alloc] initWithCore:self.core deploys:self.deploys];
    self.kept = [[DeployKept alloc] initWithCore:self.core deploys:self.deploys];
    self.menu = [[DeployMenu alloc] initWithCore:self.core deploys:self.deploys asks:self.asks kept:self.kept];
}

+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return @{
        @"--print-deploys": ^(Core *core, NSArray *a) { return PrintDeploys(a); },
        @"--print-deploy-checks": ^(Core *core, NSArray *a) { return PrintDeployChecks(a); },
        @"--print-deploy-asks": ^(Core *core, NSArray *a) { return PrintDeployAsks(core, a); },
        @"--print-builds-up": ^(Core *core, NSArray *a) { return PrintBuildsUp(core, a); },
    };
}

- (void)tick {
    [self.asks tick];
    [self.kept tick];
}

#pragma mark What a session may do

// Let It Deploy, at the foot of a session's mode menu while Deploy shows: that session may ask for its project's
// Deploy. It lasts for the session's process, and is given for the project and the command you confirmed for it, so
// it ends once either changes.
- (NSArray<SessionSwitch *> *)sessionSwitches {
    __weak typeof(self) weakSelf = self;
    SessionSwitch *deploy = [SessionSwitch switchWithKey:kLetItDeploy title:@"Let It Deploy"
                                                    line:@"It can ask to deploy its own checkout, once no other "
                                                         @"agent's at work there and you're off the panel"
                                                   lasts:SwitchLastsProcess];
    deploy.shown = ^BOOL(Row *row) {
        Core *core = weakSelf.core;
        return DeployFolder(row) && (core.printing || (core.menuBar.showsDeploy && core.menuBar.showsNextSteps));
    };
    deploy.hiddenSays = @"Deploy is hidden in the panel (Show Deploy, on Git's page on its back)";
    // Hiding Deploy is taken as "not now": turned on again, the switch has to be too.
    deploy.endsHidden = YES;
    deploy.whyNot = ^NSString *(Row *row) {
        if (row.pid <= 0) return @"Can be turned on while the session runs";
        if (![weakSelf.deploys commandFor:row]) return @"Set up Deploy for this project first";
        return nil;
    };
    // The set-up card, on this row, as Deploy's ▾ opens it: the row may not have Deploy's button to open it from.
    deploy.wayTitle = @"Set Up Deploy…";
    deploy.way = ^(Row *row) {
        [weakSelf.core.page call:@"openDeploySetup" with:@[row.sessionId ?: @"", @"save"]];
    };
    deploy.bound = ^NSString *(Row *row) {
        NSString *command = [weakSelf.deploys commandFor:row];
        return command ? [NSString stringWithFormat:@"%@\n%@", DeployProject(row), command] : nil;
    };
    deploy.boundSays = @"this project's Deploy command has changed since it was turned on";
    deploy.changed = ^(NSString *sessionId, BOOL on) {
        if (!on) [weakSelf.asks dropFrom:sessionId];
    };
    return @[deploy];
}

// Both log themselves (DeployAsks), as status's answer can quote its run's last line, which could carry a token: the
// core logs only its own refusals of them.
- (NSDictionary<NSString *, SessionAsk *> *)sessionAsks {
    __weak typeof(self) weakSelf = self;
    SessionAsk *put = [SessionAsk askNeeding:kLetItDeploy
                                      answer:^NSString *(Row *row, pid_t process, NSDictionary *asked) {
        return [weakSelf.asks ask:row from:process folder:AsText(asked[@"folder"])];
    }];
    SessionAsk *status = [SessionAsk askNeeding:kLetItDeploy
                                         answer:^NSString *(Row *row, pid_t process, NSDictionary *asked) {
        return [weakSelf.asks status:row folder:AsText(asked[@"folder"])];
    }];
    put.logsItself = status.logsItself = YES;
    return @{@"put-in-place": put, @"status": status};
}

// For a print run, which never launches: Deploy's parts without a page, and what the rows' projects have, read now.
- (void)readyForPrinting:(NSArray<Row *> *)rows {
    if (!self.deploys) {
        self.deploys = [[Deploys alloc] initWithPage:nil];
        self.asks = [[DeployAsks alloc] initWithCore:self.core deploys:self.deploys];
        self.kept = [[DeployKept alloc] initWithCore:self.core deploys:self.deploys];
    }
    [self.deploys readNowFor:rows];
}

- (void)pageLoaded {
    [self.deploys resend];
}

- (NSDictionary<NSString *, void (^)(NSDictionary *)> *)messages {
    __weak typeof(self) weakSelf = self;
    Row *(^rowOf)(NSDictionary *) = ^Row *(NSDictionary *msg) { return weakSelf.core.rows.byId[msg[@"sessionId"]]; };
    return @{
        // Your press: kept while an agent works in the checkout (DeployKept), as nothing may start then, or run now.
        @"deploy": ^(NSDictionary *msg) {
            Row *row = rowOf(msg);
            if (!row) return;
            if ([weakSelf.deploys whyNotNow:row] && [weakSelf.kept keep:row]) return;
            [weakSelf.deploys deploy:row];
        },
        @"saveDeployCommand": ^(NSDictionary *msg) {
            Row *row = rowOf(msg);
            if (row) [weakSelf.deploys save:msg[@"command"] forRow:row thenDeploy:[msg[@"deployNow"] boolValue]];
        },
        @"checkDeployCommand": ^(NSDictionary *msg) {
            Row *row = rowOf(msg);
            if (row) [weakSelf.deploys check:msg[@"command"] forRow:row];
        },
        @"openDeployLog": ^(NSDictionary *msg) {
            Row *row = rowOf(msg);
            if (row) [weakSelf.deploys openLogOf:row];
        },
        // Install First…, which shows on its card what the install runs; and Install and Deploy, on that card, your
        // press only, never kept for later, with what the card showed (`words`, `hash`), so nothing else runs.
        @"checkInstall": ^(NSDictionary *msg) {
            Row *row = rowOf(msg);
            if (row) [weakSelf.deploys checkInstallOf:row];
        },
        @"installAndDeploy": ^(NSDictionary *msg) {
            Row *row = rowOf(msg);
            if (row) [weakSelf.deploys installAndDeploy:row as:@{@"words": AsText(msg[@"words"]) ?: @"",
                                                                 @"hash": AsText(msg[@"hash"]) ?: @""}];
        },
        @"copyInstall": ^(NSDictionary *msg) {
            Row *row = rowOf(msg);
            if (row) [weakSelf.deploys copyInstallOf:row];
        },
        @"stopDeploy": ^(NSDictionary *msg) {
            Row *row = rowOf(msg);
            if (row) [weakSelf.deploys stop:row];
        },
        @"deployCard": ^(NSDictionary *msg) {
            Row *row = rowOf(msg);
            if (row) [weakSelf.deploys cardAct:AsText(msg[@"act"]) forRow:row];
        },
        @"openAddress": ^(NSDictionary *msg) {
            Row *row = rowOf(msg);
            if (row) [weakSelf.deploys openAddress:row];
        },
        @"stepMenu": ^(NSDictionary *msg) { [weakSelf.menu menu:msg]; },
    };
}

// Each session's work: Deploy's runs and suggestions for its folder are read alongside, and sent when they change.
- (void)rows:(NSArray<Row *> *)rows phase:(RowPhase)phase {
    if (phase == RowPhaseWork) [self.deploys refreshFor:rows];
    // Why a row's Deploy waits for what it runs in the background, in the work part's words, for its button's tip: the
    // page says only what it's told of that, as the next steps' notes do.
    if (phase == RowPhaseListed)
        for (Row *row in rows) row.backgroundWait = BackgroundWait(row);
}

#pragma mark On the panel's back

// Show Deploy, on Git's page on the panel's back. Its round button sits among a row's next steps, so it's on only
// while they show, and turning it on turns them on too; turned off with them, it keeps its own choice for when they're
// back. Like them, it waits for Apple's developer tools (DeveloperToolsReady).
- (NSArray<AppEntry *> *)appEntries {
    __weak typeof(self) weakSelf = self;
    AppSwitch *deploy = [AppSwitch switchWithKey:@"deploy" title:@"Show Deploy"
                                            help:@"The round button that puts your project's build in place: on the row "
                                                 @"you're on, among its next steps, and at the end of another row's line"
                                              on:^BOOL {
                                                  return weakSelf.core.menuBar.showsDeploy
                                                      && weakSelf.core.menuBar.showsNextSteps;
                                              }
                                             set:^(BOOL on) {
                                                 if (on) weakSelf.core.menuBar.showsNextSteps = YES;
                                                 weakSelf.core.menuBar.showsDeploy = on;
                                             }];
    deploy.enabled = ^BOOL { return DeveloperToolsReady(); };
    return @[[AppEntry switches:@[deploy] forApp:@"git"]];
}

#pragma mark For other modules

// BuildsInPlace: each project's build in place, from what Deploy last read, so asking never waits on the disk.
- (NSDictionary *)buildInPlaceFor:(NSString *)project {
    return [self.deploys buildInPlaceFor:project];
}

@end

// `Whozmove --print-deploy-asks <socket> <seconds> [<copy>]`: Let It Deploy for the sessions in $HOME, where tests
// put Asker, whose processes ask, Other, in the same folder (shop, a repo whose worktree is shop-try), and `copy`, the
// pid of Asker's conversation resumed in a second process. What the mode menu says of the switch with no Deploy command
// and with one; what the panel answers each ask (from Asker, from its copy, from Other naming Asker, from a process no
// session runs, an ask it doesn't know, one it can't read, and naming its own checkout or another, the project's or
// not); what each second's look decides for an ask (run, wait and why, or drop and why); how long one would wait, by
// what's in the way; and when the switch ends (its command changed, another process given its pid, its process gone).
// Then it listens at `socket`, Asker's switch on, until `<socket>.done` is there or `seconds` have gone, for
// ask-panel.sh to be tried from inside Asker's process and from outside any session. It changes Whozmove's folder in
// $HOME, so it refuses your own.
static int PrintDeployAsks(Core *core, NSArray<NSString *> *arguments) {
    if (arguments.count < 2) return 2;
    if (HomeIsYourOwn()) {
        fprintf(stderr, "--print-deploy-asks changes Whozmove's folder in $HOME: give it a throwaway one\n");
        return 2;
    }
    // Whozmove's folder, as the app makes it as it starts.
    [NSFileManager.defaultManager createDirectoryAtPath:AppDir(nil) withIntermediateDirectories:YES
                                             attributes:@{NSFilePosixPermissions: @0700} error:nil];
    DeployModule *module = nil;
    for (id each in core.modules.all)
        if ([each isKindOfClass:DeployModule.class]) module = each;
    NSArray<Row *> *rows = SettledRows(core);
    Row *asker = nil, *other = nil;
    for (Row *row in rows) {
        if ([row.name isEqual:@"Asker"]) asker = row;
        if ([row.name isEqual:@"Other"]) other = row;
    }
    if (!asker || !other) {
        fprintf(stderr, "--print-deploy-asks needs the sessions Asker and Other in $HOME\n");
        return 2;
    }
    pid_t copy = arguments.count > 2 ? arguments[2].intValue : 0;
    [module readyForPrinting:rows];
    Allowed *allowed = core.allowed;
    DeployAsks *asks = module.asks;
    SessionSwitch *deploy = [allowed switchWithKey:kLetItDeploy];
    NSString *folder = DeployFolder(asker);
    void (^say)(NSString *, NSString *) = ^(NSString *what, NSString *said) {
        printf("%s: %s\n", what.UTF8String, (said ?: @"(nothing)").UTF8String);
    };
    NSString *(^menu)(Row *) = ^NSString *(Row *row) {
        NSString *why = deploy.whyNot(row);
        return why ? [NSString stringWithFormat:@"%@, with %@", why, deploy.wayTitle] : deploy.line;
    };
    NSString *(^ask)(NSString *, pid_t) = ^NSString *(NSString *line, pid_t pid) {
        return [core.asks answer:line from:pid];
    };
    NSString *(^turn)(Row *, BOOL) = ^NSString *(Row *row, BOOL on) {
        return [allowed set:kLetItDeploy for:row on:on] ? (on ? @"on" : @"off") : @"not changed";
    };
    NSString *(^decided)(void) = ^NSString *{ return asks.decided[folder] ?: @"nothing decided"; };
    void (^confirm)(NSString *) = ^(NSString *command) {
        [module.deploys check:command forRow:asker];  // the card shows what it runs, then it's confirmed
        [module.deploys save:command forRow:asker thenDeploy:NO];
        [module.deploys settle];
        [module.deploys readNowFor:rows];
    };
    NSString *put = @"{\"ask\": \"put-in-place\"}";

    say(@"Asker's mode menu, no Deploy command yet", menu(asker));
    say(@"Turned on then", turn(asker, YES));
    say(@"Asker asks then", ask(put, asker.pid));
    confirm(@"make install");
    say(@"Asker's mode menu, with a Deploy command", menu(asker));
    say(@"Turned on then", turn(asker, YES));
    say(@"Asker asks", ask(put, asker.pid));
    say(@"…and the look decides", decided());
    say(@"Asker asks for status", ask(@"{\"ask\": \"status\"}", asker.pid));
    say(@"Asker asks for something no module answers", ask(@"{\"ask\": \"launch\"}", asker.pid));
    say(@"Asker asks in words the panel can't read", ask(@"put-in-place", asker.pid));
    if (copy) say(@"Asker's conversation resumed in another process asks", ask(put, copy));

    // A folder named: the session's own checkout, or any other, the project's (its worktree shop-try) or not (a folder
    // outside it, one whose .git only points at the repo, one that isn't there).
    NSString *(^askIn)(NSString *, NSString *) = ^NSString *(NSString *word, NSString *named) {
        NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"ask": word, @"folder": named} options:0 error:nil];
        return ask([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding], asker.pid);
    };
    NSString *(^in)(NSString *) = ^NSString *(NSString *name) { return [Home() stringByAppendingPathComponent:name]; };
    say(@"Asker asks, naming its own checkout", askIn(@"put-in-place", in(@"shop")));
    say(@"Asker asks for its project's other checkout", askIn(@"put-in-place", in(@"shop-try")));
    say(@"…and for its status", askIn(@"status", in(@"shop-try")));
    say(@"Asker asks for a folder outside its project", askIn(@"put-in-place", in(@"elsewhere")));
    say(@"Asker asks for a folder whose .git only points at the repo", askIn(@"put-in-place", in(@"shop-fake")));
    say(@"Asker asks for a folder that isn't there", askIn(@"put-in-place", in(@"gone")));
    say(@"Other asks, naming Asker", ask(@"{\"ask\": \"put-in-place\", \"sessionId\": \"s-asker\"}", other.pid));
    say(@"A process no session runs asks", ask(put, 1));

    // What each second's look decides for an ask, as things change while it waits.
    // Its own turn going on doesn't hold it up: it asks once what it changed is ready.
    asker.status = @"busy";
    ask(put, asker.pid);
    say(@"Asked during Asker's own turn", decided());
    asker.status = @"idle";
    other.status = @"busy";
    ask(put, asker.pid);
    say(@"Asked while Other works in the same folder", decided());
    other.status = @"idle";
    [asks tick];
    say(@"…once Other is done", decided());
    other.status = @"busy";
    ask(put, asker.pid);
    NSString *cwd = asker.cwd;
    NSDictionary *git = asker.git;
    asker.cwd = [Home() stringByAppendingPathComponent:@"elsewhere"];
    asker.git = nil;
    [asks tick];
    say(@"Asked, then Asker moves to another project", decided());
    asker.cwd = cwd;
    asker.git = git;
    ask(put, asker.pid);
    turn(asker, NO);
    [asks tick];
    say(@"Asked, then Let It Deploy turned off", decided());
    other.status = @"idle";
    turn(asker, YES);

    // Its checkout's build up (a server): the answer says it restarts it, and the look stops it, keeping the ask, then
    // runs it once the build has stopped. Deploy's run, as it notes one, has Asker's own process standing in for the
    // server; a print run stops nothing, so the stop is written as Stop Deploy leaves one, and the run taken away after.
    NSString *runDir = DeployLogPath(folder).stringByDeletingLastPathComponent;
    NSString *runKept = [runDir stringByAppendingString:@".kept"];  // the real run before, put back after
    // A build that's up counts as the project's build in place, which a print run keeps nothing of: as it was, after.
    NSData *inPlaceBefore = [NSData dataWithContentsOfFile:AppDir(@"in-place.json")];
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm removeItemAtPath:runKept error:nil];
    BOOL hadRun = [fm moveItemAtPath:runDir toPath:runKept error:nil];
    [fm createDirectoryAtPath:runDir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700}
                        error:nil];
    double nowMs = floor(NSDate.date.timeIntervalSince1970 * 1000);
    void (^noteRun)(long long) = ^(long long processStart) {
        [[NSJSONSerialization dataWithJSONObject:@{@"folder": folder, @"command": @"make install",
                                                   @"startedAt": @(nowMs - 60000), @"pid": @(asker.pid),
                                                   @"processStart": @(processStart)} options:0 error:nil]
            writeToFile:[runDir stringByAppendingPathComponent:@"run.json"] atomically:YES];
    };
    noteRun(ProcessStartedAt(asker.pid));
    [[NSJSONSerialization dataWithJSONObject:@{@"port": @3000, @"at": @(nowMs - 50000)} options:0 error:nil]
        writeToFile:[runDir stringByAppendingPathComponent:@"up.json"] atomically:YES];
    [module.deploys readNowFor:rows];
    say(@"Whether an ask restarts, its build up", AskRestarts([module.deploys runIn:folder]) ? @"restarts" : @"deploys");
    say(@"Asker asks while its checkout's build is up", ask(put, asker.pid));
    say(@"…and the look decides", decided());
    [asks tick];
    say(@"…a second on, the build still stopping", decided());
    noteRun(ProcessStartedAt(asker.pid) + 1);
    [@"" writeToFile:[runDir stringByAppendingPathComponent:@"stopped"] atomically:YES encoding:NSUTF8StringEncoding
               error:nil];
    [module.deploys readNowFor:rows];
    say(@"Whether an ask restarts, its build stopped", AskRestarts([module.deploys runIn:folder]) ? @"restarts"
                                                                                                    : @"deploys");
    [asks tick];
    say(@"…once it has stopped", decided());
    [fm removeItemAtPath:runDir error:nil];
    if (hadRun) [fm moveItemAtPath:runKept toPath:runDir error:nil];
    if (inPlaceBefore) [inPlaceBefore writeToFile:AppDir(@"in-place.json") atomically:YES];
    else [fm removeItemAtPath:AppDir(@"in-place.json") error:nil];
    [module.deploys readNowFor:rows];

    // How long an ask waits, by what holds it up, the first of them that does.
    say(@"Waits, with nothing in the way", AskWaits(asker, rows, NO, NO) ?: @"runs now");
    say(@"Waits, while you're on the panel", AskWaits(asker, rows, YES, NO));
    say(@"Waits, while a deploy runs there", AskWaits(asker, rows, NO, YES));
    asker.status = @"busy";
    say(@"Waits, while Asker's own turn goes on", AskWaits(asker, rows, NO, NO) ?: @"runs now");
    asker.status = @"idle";
    other.status = @"busy";
    say(@"Waits, while Other works in the same folder", AskWaits(asker, rows, YES, NO));
    other.status = @"idle";

    // When it ends.
    confirm(@"make release");
    say(@"After the command changed, Asker asks", ask(put, asker.pid));
    say(@"Turned on again", turn(asker, YES));
    say(@"Asker asks then", ask(put, asker.pid));
    NSString *file = [AppDir(@"allowed") stringByAppendingPathComponent:@"s-asker.json"];
    NSMutableDictionary *records = [AsRecord(ReadJSON(file)) mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *record = [AsRecord(records[kLetItDeploy]) mutableCopy] ?: [NSMutableDictionary dictionary];
    NSNumber *started = AsNumber(record[@"processStart"]) ?: @0;
    record[@"processStart"] = @(started.longLongValue + 1);
    records[kLetItDeploy] = record;
    [[NSJSONSerialization dataWithJSONObject:records options:0 error:nil] writeToFile:file atomically:YES];
    say(@"With another process given its pid", [allowed whyOff:kLetItDeploy for:asker] ?: @"on");
    record[@"processStart"] = started;
    records[kLetItDeploy] = record;
    [[NSJSONSerialization dataWithJSONObject:records options:0 error:nil] writeToFile:file atomically:YES];
    say(@"Its own process again", [allowed whyOff:kLetItDeploy for:asker] ?: @"on");
    // Deploy hidden (Show Deploy off), which a print run's switch never is: as the switch then says it isn't shown.
    BOOL (^shown)(Row *) = deploy.shown;
    deploy.shown = ^BOOL(Row *row) { return NO; };
    say(@"With Deploy hidden, Asker asks", ask(put, asker.pid));
    [allowed rowsListed:rows];
    deploy.shown = shown;
    say(@"…and once it shows again, after the rows were read meanwhile", [allowed whyOff:kLetItDeploy for:asker] ?: @"on");
    turn(asker, YES);
    say(@"Other turned on", turn(other, YES));
    // Stopped only while its pid is still the stand-in's own process, as the registry names it.
    pid_t found = 0;
    if ([core sessionOfProcess:other.pid found:&found] == other && found == other.pid) {
        kill(other.pid, SIGKILL);
        for (int i = 0; i < 50 && ProcessAlive(other.pid); i++) [NSThread sleepForTimeInterval:0.1];
    }
    say(@"Once Other's process has ended", [allowed whyOff:kLetItDeploy for:other] ?: @"on");
    fflush(stdout);

    // ask-panel.sh, from inside Asker and from outside any session, over the socket.
    NSString *socket = arguments[0], *done = [socket stringByAppendingString:@".done"];
    if (![core.asks listenAt:socket]) return 1;
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:arguments[1].doubleValue];
    while (until.timeIntervalSinceNow > 0 && ![NSFileManager.defaultManager fileExistsAtPath:done])
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    [core.asks stop];

    // A made-up token in the project's command, which prints it and fails: confirmed (which ends Let It Deploy, so
    // it's turned on again), really run and waited for, then asked about through the core's asks, the way a session's
    // ask-panel.sh reaches them, which log each ask unless it logs itself. The ask an earlier step left waiting goes
    // first, so status answers with the run's last line. Only whether each answer and panel.log hold
    // the token is printed, never the token, the command or the answer.
    NSString *token = [@"wz-made-up-" stringByAppendingString:NSUUID.UUID.UUIDString];
    NSString *carries = [NSString stringWithFormat:@"echo %@; false", token];
    confirm(carries);
    turn(asker, YES);
    [module.deploys runIn:folder project:DeployProject(asker) expecting:nil by:nil reconfirm:NULL];
    NSDate *ends = [NSDate dateWithTimeIntervalSinceNow:60];
    while (ends.timeIntervalSinceNow > 0 && [LastDeployRun(folder)[@"running"] boolValue])
        [NSThread sleepForTimeInterval:0.2];
    [module.deploys readNowFor:rows];
    [asks dropIn:folder];
    NSString *(^holds)(NSString *) = ^NSString *(NSString *text) {
        return [text containsString:token] ? @"names the token" : @"doesn't name it";
    };
    NSString *status = holds(ask(@"{\"ask\": \"status\"}", asker.pid));
    NSString *asked = holds(ask(put, asker.pid));
    NSString *log = [NSString stringWithContentsOfFile:AppDir(@"panel.log") encoding:NSUTF8StringEncoding error:nil];
    say(@"A made-up token in the command, run and failed, then status and put-in-place asked",
        [NSString stringWithFormat:@"status's answer %@, put-in-place's %@, panel.log %@", status, asked,
                                   [log containsString:token] ? @"has it" : @"hasn't it"]);
    return 0;
}

// `Whozmove --print-builds-up <seconds> <project> <worktree> [<base port>]`: really runs Deploy in a sample project's main checkout
// and a worktree of it, from Whozmove's folder in $HOME (so only a throwaway one), and prints what each run was given and
// how it went, each waited for up to <seconds>: the command confirmed on the card in the main checkout; each
// checkout's run, with its own port in $PORT; the ports kept; the worktree's Makefile changed after the card showed it
// there, as a branch or an agent could, so a press there doesn't run but shows the card again, a session's ask is
// refused, and confirming what the card showed before the change saves nothing, while confirming what it shows now
// does; the main checkout, whose recipe is now not the one confirmed; a command confirmed before what it runs was kept,
// which needs confirming once more, and one that names nothing checked, which runs. The project's Makefile has a `show`
// target the tests write. Then, given a block of free ports starting at <base port>, stand-in servers: one in each
// checkout, side by side, each up on its own $PORT, the later one in place; one on every address; one on a port of its
// own; one on two ports; one that never listens; one whose program isn't installed, with a package.json and no
// node_modules and then with neither (what its card goes by, and its last lines with terminal codes taken out); one
// that ends by itself once up; and one its shell leaves running, which Stop Deploy stops by its pid.
// The deploy module's tests check it.
static int PrintBuildsUp(Core *core, NSArray<NSString *> *arguments) {
    if (arguments.count < 3) return 2;
    if (HomeIsYourOwn()) {
        fprintf(stderr, "--print-builds-up runs deploys from Whozmove's folder in $HOME: give it a throwaway one\n");
        return 2;
    }
    [NSFileManager.defaultManager createDirectoryAtPath:AppDir(nil) withIntermediateDirectories:YES
                                             attributes:@{NSFilePosixPermissions: @0700} error:nil];
    DeployModule *module = nil;
    for (id each in core.modules.all)
        if ([each isKindOfClass:DeployModule.class]) module = each;
    [module readyForPrinting:@[]];
    Deploys *deploys = module.deploys;
    NSTimeInterval seconds = arguments[0].doubleValue;
    NSString *project = arguments[1], *tree = arguments[2], *command = @"make show";
    void (^say)(NSString *, NSString *) = ^(NSString *what, NSString *said) {
        printf("%s: %s\n", what.UTF8String, (said ?: @"(nothing)").UTF8String);
        fflush(stdout);
    };
    Row *(^rowIn)(NSString *) = ^Row *(NSString *folder) {
        Row *row = [[Row alloc] initWithFields:@{@"sessionId": @"s-print", @"cwd": folder}];
        row.git = @{@"root": folder, @"mainRoot": project};
        return row;
    };
    // A run, waited for: its port and the last line of its log, or why it didn't run.
    NSString *(^run)(NSString *, NSString *, NSString *) = ^NSString *(NSString *folder, NSString *named, NSString *by) {
        BOOL reconfirm = NO;
        NSString *why = [deploys runIn:folder project:project expecting:by ? named : nil by:by reconfirm:&reconfirm];
        if (why) return [NSString stringWithFormat:@"not run: %@%@", why,
                                                   reconfirm ? @" (and the set-up card shows it again)" : @""];
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
        while (until.timeIntervalSinceNow > 0 && [LastDeployRun(folder)[@"running"] boolValue])
            [NSThread sleepForTimeInterval:0.1];
        NSDictionary *last = LastDeployRun(folder);
        NSString *log = [NSString stringWithContentsOfFile:DeployLogPath(folder) encoding:NSUTF8StringEncoding error:nil];
        NSString *line = nil;
        for (NSString *each in [log ?: @"" componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet])
            if (each.length) line = each;
        return [NSString stringWithFormat:@"%@, $PORT %@, it said \"%@\"",
                [last[@"running"] boolValue] ? @"still running" : [last[@"ok"] boolValue] ? @"went through" : @"failed",
                last[@"port"] ?: @"not given", line ?: @""];
    };
    NSString *(^saved)(void) = ^NSString *{
        NSDictionary *entry = ReadJSON(AppDir(@"deploy.json"))[@"projects"][RealPath(project)];
        if (![entry isKindOfClass:NSDictionary.class]) return @"nothing saved";
        return [NSString stringWithFormat:@"%@, %@, %@", entry[@"command"],
                [entry[@"ports"] boolValue] ? @"with ports" : @"without ports",
                [entry[@"runsHash"] isKindOfClass:NSString.class] ? @"what it runs kept" : @"what it runs not kept"];
    };
    NSString *(^showCard)(NSString *, NSString *) = ^NSString *(NSString *folder, NSString *named) {
        [deploys check:named forRow:rowIn(folder)];
        [deploys settle];
        return [CheckDeploy(folder, named)[@"runs"] stringByReplacingOccurrencesOfString:@"\n" withString:@" / "];
    };
    NSString *(^confirm)(NSString *, NSString *) = ^NSString *(NSString *folder, NSString *named) {
        id before = ReadJSON(AppDir(@"deploy.json"))[@"projects"][RealPath(project)][@"savedAt"];
        [deploys save:named forRow:rowIn(folder) thenDeploy:NO];
        [deploys settle];
        id after = ReadJSON(AppDir(@"deploy.json"))[@"projects"][RealPath(project)][@"savedAt"];
        return [after isEqual:before] ? @"not saved" : [@"saved: " stringByAppendingString:saved()];
    };
    NSString *(^ports)(void) = ^NSString *{
        NSDictionary *folders = ReadJSON(AppDir(@"ports.json"))[@"projects"][RealPath(project)][@"folders"];
        NSMutableArray<NSString *> *each = [NSMutableArray array];
        for (NSString *path in [[folders allKeys] sortedArrayUsingSelector:@selector(compare:)])
            [each addObject:[NSString stringWithFormat:@"%@ %@", path.lastPathComponent, folders[path]]];
        return each.count ? [each componentsJoinedByString:@", "] : @"none";
    };
    void (^keepOnly)(NSDictionary *) = ^(NSDictionary *entry) {
        NSMutableDictionary *store = [ReadJSON(AppDir(@"deploy.json")) mutableCopy];
        store[@"projects"] = @{RealPath(project): entry};
        [[NSJSONSerialization dataWithJSONObject:store options:0 error:nil] writeToFile:AppDir(@"deploy.json")
                                                                           atomically:YES];
    };

    say(@"The card in the main checkout shows it runs", showCard(project, command));
    say(@"Confirmed", confirm(project, command));
    say(@"The ports kept once it's confirmed", ports());
    say(@"Deployed in the main checkout", run(project, command, nil));
    say(@"Deployed in the worktree", run(tree, command, nil));
    say(@"The ports kept", ports());
    say(@"The card in the worktree shows it runs", showCard(tree, command));
    [@"show:\n\t@echo changed by a branch\n" writeToFile:[tree stringByAppendingPathComponent:@"Makefile"]
                                                atomically:YES encoding:NSUTF8StringEncoding error:nil];
    say(@"The worktree's recipe changed then, and Deploy pressed there", run(tree, command, nil));
    say(@"…and asked for there by a session", run(tree, command, @"Asker"));
    say(@"Confirmed in the worktree, as the card showed it before the change", confirm(tree, command));
    say(@"…and once the card has shown it again", (showCard(tree, command), confirm(tree, command)));
    say(@"Deployed in the worktree then", run(tree, command, nil));
    say(@"Deployed in the main checkout then", run(project, command, nil));
    keepOnly(@{@"command": command, @"savedAt": @0});
    say(@"A command confirmed before what it runs was kept, deployed in the main checkout", run(project, command, nil));
    say(@"…and asked for by a session", run(project, command, @"Asker"));
    keepOnly(@{@"command": @"echo nothing checked", @"savedAt": @0});
    say(@"One that names nothing checked, deployed in the main checkout",
        run(project, @"echo nothing checked", nil));
    say(@"…which keeps that from then on", saved());
    if (arguments.count < 4) return 0;

    // Servers, with a block of ports the tests found free (never 3000), each port said from there ("base+1").
    long base = arguments[3].longLongValue;
    [[NSJSONSerialization dataWithJSONObject:@{@"projects": @{RealPath(project): @{@"base": @(base), @"folders": @{}}}}
                                     options:0 error:nil] writeToFile:AppDir(@"ports.json") atomically:YES];
    NSString *(^offset)(id) = ^NSString *(id port) {
        return [NSString stringWithFormat:@"base+%ld", [port longValue] - base];
    };
    // Its first look that sees it listening, every fifth of a second, as the panel looks every couple of seconds.
    NSString *(^upIn)(NSString *) = ^NSString *(NSString *folder) {
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
        NSDictionary *last = nil;
        while (until.timeIntervalSinceNow > 0) {
            NoteRunUp(folder);
            last = LastDeployRun(folder);
            if (last[@"up"] || ![last[@"running"] boolValue]) break;
            [NSThread sleepForTimeInterval:0.2];
        }
        NSDictionary *up = last[@"up"];
        if (!up) return [last[@"running"] boolValue] ? @"running, listening on nothing" : @"ended without listening";
        NSMutableArray *also = [NSMutableArray array];
        for (id port in up[@"also"]) [also addObject:offset(port)];
        return [NSString stringWithFormat:@"up at %@%@%@%@", offset(up[@"port"]),
                [up[@"port"] isEqual:last[@"port"]] ? @", its $PORT" : @", not its $PORT",
                [up[@"every"] boolValue] ? @", on every address" : @", on this Mac only",
                also.count ? [@", also " stringByAppendingString:[also componentsJoinedByString:@" and "]] : @""];
    };
    // Stop Deploy, waited for until it has landed (what it started given its 2 seconds, then gone), for up to a minute
    // however busy the Mac is; if it hasn't by then, what's still there, so a failure says why.
    NSString *(^stop)(NSString *) = ^NSString *(NSString *folder) {
        [deploys stop:rowIn(folder)];
        [deploys settle];
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:MAX(seconds, 60)];
        while (until.timeIntervalSinceNow > 0 && [LastDeployRun(folder)[@"running"] boolValue])
            [NSThread sleepForTimeInterval:0.2];
        NSDictionary *last = LastDeployRun(folder);
        if (![last[@"running"] boolValue]) return [last[@"stopped"] boolValue] ? @"stopped" : @"ended";
        NSString *dir = DeployLogPath(folder).stringByDeletingLastPathComponent;
        NSDictionary *shell = ReadJSON([dir stringByAppendingPathComponent:@"run.json"]);
        NSUInteger live = 0;
        for (NSDictionary *each in ReadJSON([dir stringByAppendingPathComponent:@"members.json"]) ?: @[])
            if (ProcessStartedAt([each[@"pid"] intValue]) == [each[@"start"] longLongValue]) live++;
        return [NSString stringWithFormat:@"still running a minute on: its shell %@, %lu noted member%@ still there, "
                                          @"its group %@",
                ProcessStartedAt([shell[@"pid"] intValue]) == [shell[@"processStart"] longLongValue] ? @"there" : @"gone",
                (unsigned long)live, live == 1 ? @"" : @"s",
                GroupMembers([shell[@"pid"] intValue]).count ? @"not empty" : @"empty"];
    };
    NSString *(^serve)(NSString *) = ^NSString *(NSString *named) {
        showCard(project, named);
        return confirm(project, named);
    };
    // A deploy started, or why not: a run still going there (one a case before left) is said, rather than taken for
    // the new one.
    NSString *(^started)(NSString *) = ^NSString *(NSString *folder) {
        id before = LastDeployRun(folder)[@"startedAt"];
        NSString *why = [deploys runIn:folder project:project expecting:nil by:nil reconfirm:NULL];
        if (why) return why;
        return [LastDeployRun(folder)[@"startedAt"] isEqual:before] ? @"not started: a run was still going there"
                                                                    : @"started";
    };
    NSString *local = @"python3 -m http.server --bind 127.0.0.1";

    say(@"A server on $PORT, confirmed", serve([local stringByAppendingString:@" $PORT"]));
    say(@"Deployed in the main checkout", started(project));
    say(@"Deployed in the worktree", started(tree));
    say(@"The main checkout's", upIn(project));
    say(@"The worktree's", upIn(tree));
    NSDictionary *inPlace = BuildsInPlaceSeen(@{project: project, tree: project})[RealPath(project)];
    say(@"The build in place", [NSString stringWithFormat:@"%@'s, the last up", [inPlace[@"folder"] lastPathComponent]]);
    say(@"Stop Deploy in the main checkout", stop(project));
    say(@"…and in the worktree", stop(tree));
    say(@"A server on every address, confirmed and deployed",
        [NSString stringWithFormat:@"%@, %@", serve(@"python3 -m http.server --bind :: $PORT"), started(project)]);
    say(@"It's", upIn(project));
    say(@"Stopped", stop(project));
    NSString *fixed = [NSString stringWithFormat:@"%@ %ld", local, base + 5];
    say(@"A server on a port of its own, confirmed and deployed",
        [NSString stringWithFormat:@"%@, %@", serve(fixed), started(project)]);
    say(@"It's", upIn(project));
    say(@"Stopped", stop(project));
    NSString *two = [NSString stringWithFormat:@"%@ $PORT & %@ %ld", local, local, base + 6];
    say(@"Two servers, confirmed and deployed", [NSString stringWithFormat:@"%@, %@", serve(two), started(project)]);
    say(@"They're", upIn(project));
    say(@"Stopped", stop(project));
    say(@"One that never listens, confirmed and deployed",
        [NSString stringWithFormat:@"%@, %@", serve(@"sleep 30"), started(project)]);
    say(@"It's", upIn(project));
    say(@"Stopped", stop(project));
    // How a run that didn't go through ended, waited for: what its card goes by (deployRunCard), and its last lines
    // as the card shows them, terminal codes and direction marks taken out.
    NSString *(^ended)(NSString *) = ^NSString *(NSString *folder) {
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:MAX(seconds, 60)];
        while (until.timeIntervalSinceNow > 0 && [LastDeployRun(folder)[@"running"] boolValue])
            [NSThread sleepForTimeInterval:0.2];
        NSDictionary *last = LastDeployRun(folder);
        if ([last[@"running"] boolValue]) return @"still running";
        return [NSString stringWithFormat:@"%@%@%@, its last lines \"%@\"",
                [last[@"ok"] boolValue] ? @"went through" : @"failed",
                [last[@"endedItself"] boolValue] ? @", ended by itself once up" : @"",
                [last[@"noPackages"] boolValue] ? [NSString stringWithFormat:@", its packages not installed (%@)",
                                                   last[@"install"]] : @"",
                [last[@"lastLines"] componentsJoinedByString:@" / "] ?: @""];
    };
    NSString *json = [project stringByAppendingPathComponent:@"package.json"];
    [@"{}\n" writeToFile:json atomically:YES encoding:NSUTF8StringEncoding error:nil];
    say(@"One whose program isn't installed, in a checkout with a package.json and no node_modules, confirmed and "
        @"deployed", [NSString stringWithFormat:@"%@, %@", serve(@"printf 'starting\\n\\033[31m\\342\\200\\256vite\\033[0m: "
                                                                 @"command not found\\n'; exit 127"), started(project)]);
    say(@"It", ended(project));
    // What its card's Copy copies and Install First runs, for each lock file the checkout could have, each on its
    // own: Yarn 1's told by its lock file's first lines.
    NSString *(^words)(void) = ^NSString *{
        NSDictionary *install = DeployInstallWords(project);
        return [NSString stringWithFormat:@"%@%@", install[@"words"],
                [install[@"makesLockfile"] boolValue] ? @", making a lock file" : @""];
    };
    NSMutableArray<NSString *> *installs = [NSMutableArray arrayWithObject:words()];
    for (NSArray<NSString *> *lock in @[@[@"package-lock.json", @"{}\n"], @[@"pnpm-lock.yaml", @""],
                                        @[@"yarn.lock", @"# THIS IS AN AUTOGENERATED FILE.\n# yarn lockfile v1\n"],
                                        @[@"yarn.lock", @"__metadata:\n  version: 8\n"], @[@"bun.lock", @""],
                                        @[@"bun.lockb", @""]]) {
        NSString *path = [project stringByAppendingPathComponent:lock[0]];
        [lock[1] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [installs addObject:[NSString stringWithFormat:@"%@%@: %@", lock[0], [lock[0] isEqual:@"yarn.lock"]
                                 ? ([lock[1] containsString:@"v1"] ? @" (Yarn 1)" : @" (Yarn 2 on)") : @"", words()]];
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    }
    say(@"Its card's Copy, with no lock file, then with each", [installs componentsJoinedByString:@"; "]);
    [NSFileManager.defaultManager removeItemAtPath:json error:nil];
    say(@"The same, once its package.json is gone", started(project));
    say(@"It", ended(project));
    // Install First: Install and Deploy, your press, runs the lock file's install once, then the command, in the same
    // shell, its output at the start of the log. A stand-in npm, first on the PATH your shell sets up in this $HOME,
    // stands in for a real one, so nothing is fetched. Not while an agent works there, and never kept for later. Its
    // files go only in the throwaway $HOME (Home(), which follows $HOME, where the system's own home is always yours),
    // and only where nothing is yet, so nothing there is replaced or taken away.
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *bin = [Home() stringByAppendingPathComponent:@"stand-ins"];
    BOOL madeBin = !HomeIsYourOwn() && ![files fileExistsAtPath:bin]
        && [files createDirectoryAtPath:bin withIntermediateDirectories:NO attributes:nil error:nil];
    // A stand-in npm that installs, and a stand-in pnpm whose install doesn't go through.
    if (madeBin) {
        NSArray<NSArray<NSString *> *> *stands = @[
            @[@"npm", @"echo \"stand-in npm $*\"\nmkdir -p node_modules\n"],
            @[@"pnpm", @"echo \"stand-in pnpm $*: the lock file is out of date\"\nexit 1\n"]];
        for (NSArray<NSString *> *stand in stands) {
            NSString *path = [bin stringByAppendingPathComponent:stand[0]];
            [[@"#!/bin/sh\n" stringByAppendingString:stand[1]] writeToFile:path atomically:YES
                                                                  encoding:NSUTF8StringEncoding error:nil];
            [files setAttributes:@{NSFilePosixPermissions: @0755} ofItemAtPath:path error:nil];
        }
    }
    NSMutableArray<NSString *> *made = [NSMutableArray array];
    for (NSString *name in @[@".zshrc", @".bash_profile"]) {
        NSString *path = [Home() stringByAppendingPathComponent:name];
        if (!madeBin || [files fileExistsAtPath:path]) continue;
        [[NSString stringWithFormat:@"export PATH=\"%@:$PATH\"\n", bin] writeToFile:path atomically:YES
                                                                     encoding:NSUTF8StringEncoding error:nil];
        [made addObject:path];
    }
    // The sample project's own files, made here only where there's none, and taken away after only if made here.
    NSString *lock = [project stringByAppendingPathComponent:@"package-lock.json"];
    NSString *modules = [project stringByAppendingPathComponent:@"node_modules"];
    for (NSString *path in @[json, lock])
        if (![files fileExistsAtPath:path] && [@"{}\n" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding
                                                               error:nil])
            [made addObject:path];
    if (![files fileExistsAtPath:modules]) [made addObject:modules];
    NSString *needs = @"test -d node_modules && echo started || { echo \"Error: Cannot find module 'vite'\"; exit 1; }";
    say(@"One that needs its packages, in a checkout with a package-lock.json and no node_modules, confirmed and "
        @"deployed", [NSString stringWithFormat:@"%@, %@", serve(needs), started(project)]);
    say(@"It", ended(project));
    NSString *(^installed)(void) = ^NSString *{
        NSString *log = [NSString stringWithContentsOfFile:DeployLogPath(project) encoding:NSUTF8StringEncoding
                                                     error:nil];
        NSDictionary *last = LastDeployRun(project);
        return [NSString stringWithFormat:@"%@, its log \"%@\", node_modules %@",
                [last[@"running"] boolValue] ? @"still running" : [last[@"ok"] boolValue] ? @"went through"
                                                                                           : @"failed",
                [[log stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet]
                    stringByReplacingOccurrencesOfString:@"\n" withString:@" / "] ?: @"",
                [NSFileManager.defaultManager fileExistsAtPath:[project stringByAppendingPathComponent:@"node_modules"]]
                    ? @"there" : @"not there"];
    };
    Row *working = [[Row alloc] initWithFields:@{@"sessionId": @"s-codegen", @"name": @"codegen", @"cwd": project,
                                                 @"status": @"busy"}];
    working.git = @{@"root": project, @"mainRoot": project};
    // What Install First's second step shows, as its card would be given it: the install, its lock file, and the
    // project's own install scripts (none, in this package.json).
    NSString *(^shows)(NSDictionary *) = ^NSString *(NSDictionary *check) {
        return [NSString stringWithFormat:@"%@, from %@, %@%@", check[@"words"], check[@"lockfile"] ?: @"no lock file",
                AsText(check[@"runs"]) ? [@"runs: " stringByAppendingString:
                    [check[@"runs"] stringByReplacingOccurrencesOfString:@"\n" withString:@" / "]]
                                       : @"no install scripts of its own",
                [check[@"unsure"] count] ? [@", unsure: " stringByAppendingString:
                    [check[@"unsure"] componentsJoinedByString:@"; "]] : @""];
    };
    NSDictionary *shown = DeployInstallCheck(project);
    say(@"Install First's second step shows", shows(shown));
    [deploys readNowFor:@[rowIn(project), working]];
    id startedBefore = LastDeployRun(project)[@"startedAt"];
    [deploys installAndDeploy:rowIn(project) as:shown];
    [deploys settle];
    say(@"Install and Deploy pressed while an agent works there",
        [LastDeployRun(project)[@"startedAt"] isEqual:startedBefore] ? @"nothing run" : @"it ran");
    // An agent adds a postinstall after the card showed it: nothing runs, and the step shows the new script.
    [deploys readNowFor:@[rowIn(project)]];
    [@"{\"scripts\": {\"postinstall\": \"node scripts/setup.js\"}}\n" writeToFile:json atomically:YES
                                                                         encoding:NSUTF8StringEncoding error:nil];
    [deploys installAndDeploy:rowIn(project) as:shown];
    [deploys settle];
    say(@"Install and Deploy pressed after package.json gained a postinstall",
        [NSString stringWithFormat:@"%@, the step now shows %@",
         [LastDeployRun(project)[@"startedAt"] isEqual:startedBefore] ? @"nothing run" : @"it ran",
         shows(DeployInstallCheck(project))]);
    [@"{}\n" writeToFile:json atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [deploys installAndDeploy:rowIn(project) as:DeployInstallCheck(project)];
    [deploys settle];
    ended(project);
    say(@"Install and Deploy pressed once it's done", installed());
    // An install that doesn't go through: the command never runs, and the run says so, rather than no packages again.
    [files removeItemAtPath:[project stringByAppendingPathComponent:@"node_modules"] error:nil];
    NSString *pnpmLock = [project stringByAppendingPathComponent:@"pnpm-lock.yaml"];
    if (![files fileExistsAtPath:pnpmLock] && [@"lockfileVersion: '9.0'\n" writeToFile:pnpmLock atomically:YES
                                                                              encoding:NSUTF8StringEncoding error:nil])
        [made addObject:pnpmLock];
    [deploys installAndDeploy:rowIn(project) as:DeployInstallCheck(project)];
    [deploys settle];
    ended(project);
    NSDictionary *failedInstall = LastDeployRun(project);
    say(@"…and with a pnpm lock file whose install doesn't go through", [NSString stringWithFormat:@"%@, %@",
        installed(), failedInstall[@"installFailed"] ? [NSString stringWithFormat:@"its install (%@) didn't go through",
                                                                            failedInstall[@"installFailed"]]
                                                      : [failedInstall[@"noPackages"] boolValue] ? @"no packages again"
                                                                                                : @"nothing said"]);
    if (madeBin) [made addObject:bin];
    for (NSString *path in made) [files removeItemAtPath:path error:nil];
    NSString *dies = [NSString stringWithFormat:@"%@ $PORT & %@; sleep 1; kill $!; echo the server ended; exit 1",
                                                local, @"for i in $(seq 1 150); do nc -z 127.0.0.1 $PORT 2>/dev/null "
                                                       @"&& break; sleep 0.2; done"];
    say(@"A server that ends by itself once up, confirmed and deployed",
        [NSString stringWithFormat:@"%@, %@", serve(dies), started(project)]);
    say(@"It's", upIn(project));
    say(@"It", ended(project));
    // Its shell ends once the server it started in the background listens (and a second more, so the panel's looks
    // note it), leaving it running (with nohup, as an interactive shell hangs up its jobs as it ends): the run goes on
    // while the server noted as its member does, and Stop Deploy stops just that, by its pid and start time. Each step
    // is waited for, however busy the Mac.
    NSString *listened = @"for i in $(seq 1 150); do nc -z 127.0.0.1 $PORT 2>/dev/null && break; sleep 0.2; done";
    BOOL (^shellGone)(NSString *) = ^BOOL(NSString *folder) {
        NSDictionary *run = ReadJSON([DeployLogPath(folder).stringByDeletingLastPathComponent
                                      stringByAppendingPathComponent:@"run.json"]);
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:MAX(seconds, 60)];
        while (until.timeIntervalSinceNow > 0
               && ProcessStartedAt([run[@"pid"] intValue]) == [run[@"processStart"] longLongValue])
            [NSThread sleepForTimeInterval:0.2];
        return ProcessStartedAt([run[@"pid"] intValue]) != [run[@"processStart"] longLongValue];
    };
    NSString *left = [NSString stringWithFormat:@"nohup %@ $PORT > /dev/null 2>&1 & %@; sleep 1", local, listened];
    say(@"A server its shell leaves running, confirmed and deployed",
        [NSString stringWithFormat:@"%@, %@", serve(left), started(project)]);
    say(@"It's", upIn(project));
    shellGone(project);
    NSDictionary *shell = ReadJSON([DeployLogPath(project).stringByDeletingLastPathComponent
                                    stringByAppendingPathComponent:@"run.json"]);
    say(@"Once its shell has ended", [NSString stringWithFormat:@"its shell %@, the run %@",
        ProcessStartedAt([shell[@"pid"] intValue]) == [shell[@"processStart"] longLongValue] ? @"still there" : @"gone",
        [LastDeployRun(project)[@"running"] boolValue] ? @"still running" : @"ended"]);
    say(@"Stopped", stop(project));

    // A process that joins its group after its shell has ended (a sleep a helper starts once the shell has gone, the
    // shell ending once the server listens): it's never noted, as the group isn't read once its shell has gone, and
    // Stop Deploy leaves it alone. The test stops it itself, by its pid and start time; it waits a minute, longer than
    // a stop takes however busy the Mac, so it can't have ended by itself before it's looked for.
    NSString *late = [NSString stringWithFormat:@"nohup %@ $PORT > /dev/null 2>&1 & nohup sh -c 'while kill -0 $PPID "
                                                @"2>/dev/null; do sleep 0.2; done; sleep 60' > /dev/null 2>&1 & %@; "
                                                @"sleep 1", local, listened];
    say(@"A process that joins its group after its shell has ended, confirmed and deployed",
        [NSString stringWithFormat:@"%@, %@", serve(late), started(project)]);
    say(@"It's", upIn(project));
    shellGone(project);
    NSDictionary *lateRun = ReadJSON([DeployLogPath(project).stringByDeletingLastPathComponent
                                      stringByAppendingPathComponent:@"run.json"]);
    // Only one still there a second later counts: the helper's last short sleep, as it notices the shell has gone,
    // is in the group too, and ends by itself.
    NSMutableArray<NSDictionary *> *joined = [NSMutableArray array];
    for (NSDate *until = [NSDate dateWithTimeIntervalSinceNow:MAX(seconds, 30)];
         !joined.count && until.timeIntervalSinceNow > 0; [NSThread sleepForTimeInterval:0.2]) {
        NoteRunUp(project);
        NSArray *noted = ReadJSON([DeployLogPath(project).stringByDeletingLastPathComponent
                                   stringByAppendingPathComponent:@"members.json"]);
        NSMutableArray<NSDictionary *> *found = [NSMutableArray array];
        for (NSDictionary *each in GroupMembers([lateRun[@"pid"] intValue]))
            if (![noted containsObject:each]) [found addObject:each];
        if (!found.count) continue;
        [NSThread sleepForTimeInterval:1];
        for (NSDictionary *each in found)
            if (ProcessStartedAt([each[@"pid"] intValue]) == [each[@"start"] longLongValue]) [joined addObject:each];
    }
    say(@"Once its shell has ended", [NSString stringWithFormat:@"%@ in its group not noted", joined.count
        ? [NSString stringWithFormat:@"%lu process%@", (unsigned long)joined.count, joined.count == 1 ? @"" : @"es"]
        : @"nothing"]);
    say(@"Stopped", stop(project));
    NSUInteger untouched = 0;
    for (NSDictionary *each in joined)
        if (ProcessStartedAt([each[@"pid"] intValue]) == [each[@"start"] longLongValue]) {
            untouched++;
            kill([each[@"pid"] intValue], SIGKILL);
        }
    say(@"What joined it after its shell ended", untouched ? @"left alone by Stop Deploy" : @"stopped too");

    // A server that takes no notice of being told to end, never noted (Stop pressed before the panel looked): what its
    // group had as Stop was pressed is made to stop 2 seconds later, one by one.
    // sh passes an ignored signal on to the program it becomes (zsh, your login shell here, doesn't).
    NSString *deaf = [NSString stringWithFormat:@"sh -c 'trap \"\" TERM; exec %@ $PORT'", local];
    say(@"A server that ignores being told to end, confirmed and deployed",
        [NSString stringWithFormat:@"%@, %@", serve(deaf), started(project)]);
    [NSThread sleepForTimeInterval:1.5];
    NSDictionary *deafRun = ReadJSON([DeployLogPath(project).stringByDeletingLastPathComponent
                                      stringByAppendingPathComponent:@"run.json"]);
    NSUInteger before = GroupMembers([deafRun[@"pid"] intValue]).count;
    say(@"Stopped, before the panel looked", stop(project));
    [NSThread sleepForTimeInterval:1];
    say(@"Its group", [NSString stringWithFormat:@"%@ as Stop was pressed, %@ 3 seconds later",
        before ? @"processes in it" : @"nothing in it",
        GroupMembers([deafRun[@"pid"] intValue]).count ? @"something still there" : @"nothing left"]);

    // Restart, which stops the build, then deploys once it has ended, checking its waits again just before. The main
    // thread is let run meanwhile, as the app's is, and what it says is read from the log, as a print run has no row.
    NSString *(^said)(void) = ^NSString *{
        NSString *log = [NSString stringWithContentsOfFile:AppDir(@"panel.log") encoding:NSUTF8StringEncoding error:nil];
        NSString *found = @"(nothing)";
        for (NSString *line in [log ?: @"" componentsSeparatedByString:@"\n"]) {
            NSRange at = [line rangeOfString:@"Not (restarted|deployed)" options:NSRegularExpressionSearch];
            if (at.location != NSNotFound) found = [line substringFromIndex:at.location];
        }
        return found;
    };
    // Each waits until the Restart has done all it will (deployed again, or left it stopped), and then for a run it
    // started to be up, for up to two minutes however busy the Mac is, so none is still waiting as the next case
    // begins. `meanwhile` is what happens as it waits.
    NSString *(^restartWhile)(void (^)(void)) = ^NSString *(void (^meanwhile)(void)) {
        id was = LastDeployRun(project)[@"startedAt"];  // the build being restarted, still up as it stops
        [deploys restart:rowIn(project)];
        if (meanwhile) meanwhile();
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:MAX(seconds, 120)];
        while (until.timeIntervalSinceNow > 0 && [deploys deployWaitsIn:project])
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
        NSDictionary *last = LastDeployRun(project);
        while (until.timeIntervalSinceNow > 0 && ![last[@"startedAt"] isEqual:was] && [last[@"running"] boolValue]
               && !last[@"up"]) {
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
            NoteRunUp(project);
            last = LastDeployRun(project);
        }
        if ([deploys deployWaitsIn:project]) return @"still waiting two minutes on";
        return ![last[@"startedAt"] isEqual:was] && [last[@"running"] boolValue] && last[@"up"] ? @"up again"
                                                                                                : @"left stopped";
    };
    say(@"A server on $PORT, confirmed and deployed for Restart",
        [NSString stringWithFormat:@"%@, %@", serve([local stringByAppendingString:@" $PORT"]), started(project)]);
    say(@"It's", upIn(project));
    [deploys readNowFor:@[rowIn(project)]];  // its session listed, as a row's is
    say(@"Restarted", restartWhile(nil));
    // An agent starts work in the folder while the build stops: Restart checks again, and leaves it stopped.
    Row *busy = [[Row alloc] initWithFields:@{@"sessionId": @"s-codegen", @"name": @"codegen", @"cwd": project,
                                              @"status": @"busy"}];
    busy.git = @{@"root": project, @"mainRoot": project};
    say(@"Restarted while an agent starts work there", restartWhile(^{ [deploys readNowFor:@[rowIn(project), busy]]; }));
    say(@"…which the row says", said());
    // The row's own session starts a turn while the build stops: the row as listed now is what's checked.
    say(@"Deployed again", started(project));
    say(@"It's", upIn(project));
    [deploys readNowFor:@[rowIn(project)]];
    Row *turning = rowIn(project);
    turning.status = @"busy";
    say(@"Restarted while its own session starts a turn", restartWhile(^{ [deploys readNowFor:@[turning]]; }));
    say(@"…which the row says", said());
    say(@"Deployed again", started(project));
    say(@"It's", upIn(project));
    say(@"Restarted once its session is no longer listed", restartWhile(^{ [deploys readNowFor:@[]]; }));
    say(@"…which the row says", said());
    [deploys readNowFor:@[rowIn(project)]];
    // Stop Deploy pressed while Restart waits for the build to end: it calls the Restart off.
    say(@"Deployed again", started(project));
    say(@"It's", upIn(project));
    say(@"Restarted, then Stop Deploy pressed as it waits", restartWhile(^{ [deploys stop:rowIn(project)]; }));
    [deploys readNowFor:@[rowIn(project)]];
    // The build before still stopping when Restart stops looking (here at once, a server taking no notice of being told
    // to end): it says so, and leaves it.
    say(@"A server that ignores being told to end, confirmed and deployed for Restart",
        [NSString stringWithFormat:@"%@, %@", serve(deaf), started(project)]);
    say(@"It's", upIn(project));
    deploys.restartTries = 0;
    say(@"Restarted, looking only once", restartWhile(nil));
    say(@"…which the row says", said());
    deploys.restartTries = 20;
    [deploys readNowFor:@[]];
    say(@"Stopped", stop(project));

    // Your press while an agent works in the checkout: kept, then run once it's done, everything checked again; and
    // dropped, with Don't Deploy, once the command has changed, or once its session isn't listed.
    DeployKept *pressKept = module.kept;
    NSString *(^decidedHere)(void) = ^NSString *{ return pressKept.decided[project] ?: @"nothing decided"; };
    say(@"A server on $PORT, confirmed", serve([local stringByAppendingString:@" $PORT"]));
    [deploys readNowFor:@[rowIn(project), busy]];
    say(@"Deploy pressed while an agent works there", [pressKept keep:rowIn(project)] ? decidedHere() : @"not kept");
    [pressKept tick];
    say(@"…a second on, the agent still at work", decidedHere());
    [deploys readNowFor:@[rowIn(project)]];
    [pressKept tick];
    say(@"…once it's done", decidedHere());
    [deploys settle];
    say(@"It's", upIn(project));
    say(@"…and nothing kept after", [pressKept keptIn:project] ? @"still kept" : @"nothing kept");
    say(@"Stopped", stop(project));
    [deploys readNowFor:@[rowIn(project), busy]];
    [pressKept keep:rowIn(project)];
    serve([local stringByAppendingString:@" --directory . $PORT"]);
    [deploys readNowFor:@[rowIn(project), busy]];
    [pressKept tick];
    say(@"Kept, then the command changed", decidedHere());
    [pressKept keep:rowIn(project)];
    [pressKept dropIn:project];
    say(@"Kept, then Don't Deploy", [pressKept keptIn:project] ? @"still kept" : @"nothing kept");
    [pressKept keep:rowIn(project)];
    [deploys readNowFor:@[busy]];
    [pressKept tick];
    say(@"Kept, then its session no longer listed", decidedHere());
    say(@"…and nothing ran", [LastDeployRun(project)[@"running"] boolValue] ? @"one runs" : @"nothing runs");
    if (arguments.count < 5) return 0;

    // The port checked before a press runs, with what's on it said from the base, and the card Deploy keeps.
    NSString *(^at)(id) = ^NSString *(id port) { return port ? offset(port) : @"none"; };
    NSString *(^described)(NSDictionary *) = ^NSString *(NSDictionary *card) {
        if (!card) return @"no card";
        NSMutableArray *said = [NSMutableArray arrayWithObject:[NSString stringWithFormat:@"%@ on %@", card[@"kind"],
                                                                                         at(card[@"port"])]];
        if (card[@"other"]) [said addObject:[NSString stringWithFormat:@"%@'s build", card[@"other"]]];
        if (card[@"fixed"]) [said addObject:@"a server that picks its own port"];
        if (card[@"old"]) [said addObject:@"a command confirmed before ports"];
        // How long it's run, said as whether the card has it right, from the program's own start time (the card's
        // minutes, or the one before if a minute turned between the two looks), as that depends on how busy the Mac is.
        if ([card[@"kind"] isEqual:@"held"]) {
            NSDictionary *holder = PortHolder([card[@"port"] intValue]);
            long ran = (long)((NSDate.date.timeIntervalSince1970 * 1e6 - [holder[@"start"] doubleValue]) / 60e6);
            long minutes = [card[@"minutes"] longValue];
            [said addObject:[NSString stringWithFormat:@"%@, %@", [card[@"name"] length] ? @"named" : @"unnamed",
                             minutes == ran || minutes == ran - 1 ? @"running as long as it has"
                                                                   : [NSString stringWithFormat:@"running %ld min, "
                                                                      @"not %ld", minutes, ran]]];
        }
        if (card[@"sessionName"]) [said addObject:[NSString stringWithFormat:@"started by “%@”", card[@"sessionName"]]];
        [said addObject:[NSString stringWithFormat:@"next %@", at(card[@"next"])]];
        return [said componentsJoinedByString:@", "];
    };
    // A press, as the row's: the card it leaves, or that it ran.
    NSString *(^press)(NSString *) = ^NSString *(NSString *folder) {
        [deploys readNowFor:@[rowIn(project), rowIn(folder)]];
        [deploys deploy:rowIn(folder)];
        [deploys settle];
        [deploys readNowFor:@[rowIn(project), rowIn(folder)]];
        NSDictionary *card = [deploys cardIn:folder];
        return card ? described(card) : [LastDeployRun(folder)[@"running"] boolValue] ? @"ran" : @"didn't run";
    };
    NSString *(^act)(NSString *, NSString *) = ^NSString *(NSString *folder, NSString *what) {
        [deploys cardAct:what forRow:rowIn(folder)];
        [deploys settle];
        // Until it has run, and Stop It and Deploy is no longer waiting for the build it stopped, for up to two minutes
        // however busy the Mac is.
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:MAX(seconds, 120)];
        while (until.timeIntervalSinceNow > 0
               && ([deploys deployWaitsIn:folder] || ![LastDeployRun(folder)[@"running"] boolValue]))
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
        [deploys readNowFor:@[rowIn(project), rowIn(folder)]];
        return [deploys cardIn:folder] ? described([deploys cardIn:folder]) : upIn(folder);
    };
    // A session's ask, as Let It Deploy runs one once nothing waits: the card it leaves for you, or that it ran and
    // where it's up. And what the ask's status says then, its ports said from the base.
    NSString *(^asked)(NSString *) = ^NSString *(NSString *folder) {
        [deploys readNowFor:@[rowIn(project), rowIn(folder)]];
        id before = LastDeployRun(folder)[@"startedAt"];
        [deploys deployAsked:rowIn(folder) in:folder expecting:[deploys commandFor:rowIn(folder)] by:@"Asker"];
        [deploys settle];
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];  // what's noted on main
        [deploys readNowFor:@[rowIn(project), rowIn(folder)]];
        NSDictionary *card = [deploys cardIn:folder];
        if (card) return [NSString stringWithFormat:@"didn't run, the card waits: %@, asked by “%@”", described(card),
                                                    card[@"asked"]];
        return [LastDeployRun(folder)[@"startedAt"] isEqual:before] ? @"didn't run"
                                                                     : [@"ran, " stringByAppendingString:upIn(folder)];
    };
    NSString *(^askedStatus)(NSString *) = ^NSString *(NSString *folder) {
        [deploys readNowFor:@[rowIn(project), rowIn(folder)]];
        NSString *said = [module.asks status:rowIn(folder) folder:nil];
        NSMutableString *based = [said mutableCopy];
        NSRegularExpression *number = [NSRegularExpression regularExpressionWithPattern:@"\\b\\d{4,5}\\b" options:0
                                                                                   error:nil];
        for (NSTextCheckingResult *found in [number matchesInString:said options:0 range:NSMakeRange(0, said.length)]
                                                .reverseObjectEnumerator)
            [based replaceCharactersInRange:found.range
                                 withString:offset(@([said substringWithRange:found.range].longLongValue))];
        return based;
    };
    // A command confirmed before ports, its server on a port of its own: the worktree's would take the same one.
    NSString *older = [NSString stringWithFormat:@"%@ %ld", local, base + 5];
    keepOnly(@{@"command": older, @"savedAt": @0, @"runsHash": DeployRunsHash(project, older)});
    say(@"A command confirmed before ports, deployed in the main checkout", started(project));
    say(@"It's", upIn(project));
    say(@"Deploy pressed in the worktree", press(tree));
    say(@"…Cancel", ([deploys cardAct:@"cancel" forRow:rowIn(tree)], [deploys settle],
                     [deploys readNowFor:@[rowIn(tree)]], described([deploys cardIn:tree])));
    say(@"Stopped", stop(project));
    // The same server confirmed with ports: it listens on its own port whatever $PORT says, which its first run shows.
    say(@"A server on a port of its own, confirmed and deployed in the main checkout",
        [NSString stringWithFormat:@"%@, %@", serve(older), started(project)]);
    say(@"It's", upIn(project));
    // A session's ask meeting it: no next port for a server that picks its own, so nothing of the main checkout's is
    // stopped, and the card waits for you.
    say(@"Asked for in the worktree by a session", asked(tree));
    say(@"…its status", askedStatus(tree));
    say(@"…and the main checkout's", [LastDeployRun(project)[@"running"] boolValue] ? @"still running" : @"stopped");
    say(@"Deploy pressed in the worktree", press(tree));
    say(@"…Stop It and Deploy", act(tree, @"replace"));
    say(@"…and the main checkout's", [LastDeployRun(project)[@"running"] boolValue] ? @"still running"
                                                                                   : @"stopped");
    say(@"Stopped", stop(tree));
    // A program Deploy didn't start on the worktree's port (the test's own server, on base+7): named, never stopped,
    // and the next free port offered, which Use Port runs on, from now on.
    serve([local stringByAppendingString:@" $PORT"]);
    NSMutableDictionary *record = [ReadJSON(AppDir(@"ports.json")) mutableCopy];
    NSMutableDictionary *entry = [record[@"projects"][RealPath(project)] mutableCopy];
    NSMutableDictionary *kept = [entry[@"folders"] mutableCopy];
    kept[RealPath(tree)] = @(base + 7);
    entry[@"folders"] = kept;
    record[@"projects"] = @{RealPath(project): entry};
    [[NSJSONSerialization dataWithJSONObject:record options:0 error:nil] writeToFile:AppDir(@"ports.json") atomically:YES];
    say(@"Deploy pressed in the worktree, its port held", press(tree));
    // Who started it: the test's own shell, standing in for a session's process, counts only if it started first.
    pid_t parent = arguments[4].intValue;
    long long since = ProcessStartedAt(parent);
    NSDictionary *named = [deploys portCheckIn:tree project:project sessions:@[@{@"sid": @"s-agent",
        @"name": @"cart total", @"pid": @(parent), @"start": @(since)}]];
    say(@"…with the session that started it listed", described(named));
    NSDictionary *later = [deploys portCheckIn:tree project:project sessions:@[@{@"sid": @"s-agent",
        @"name": @"cart total", @"pid": @(parent), @"start": @(since + 3600000000LL)}]];
    say(@"…and one listed as starting after it (a pid used again)", described(later));
    // An agent starts work in the worktree as Use Port finds the port: the waits are checked again once it has, and the
    // card stays.
    Row *editing = [[Row alloc] initWithFields:@{@"sessionId": @"s-codegen", @"name": @"codegen", @"cwd": tree,
                                                 @"status": @"busy"}];
    editing.git = @{@"root": tree, @"mainRoot": project};
    [deploys readNowFor:@[rowIn(project), rowIn(tree)]];
    [deploys cardAct:@"next" forRow:rowIn(tree)];
    [deploys readNowFor:@[rowIn(project), rowIn(tree), editing]];
    [deploys settle];
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
    [deploys settle];
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    [deploys readNowFor:@[rowIn(project), rowIn(tree), editing]];
    say(@"…Use Port while an agent starts work there", [NSString stringWithFormat:@"%@, %@, the card %@",
        [LastDeployRun(tree)[@"running"] boolValue] ? @"ran" : @"didn't run", said(),
        [deploys cardIn:tree] ? @"still there" : @"gone"]);
    [deploys readNowFor:@[rowIn(project), rowIn(tree)]];  // the agent done
    say(@"…Use Port", act(tree, @"next"));
    say(@"The worktree's port from now on", at(ReadJSON(AppDir(@"ports.json"))[@"projects"][RealPath(project)]
                                                   [@"folders"][RealPath(tree)]));
    say(@"Stopped", stop(tree));
    // A session's ask, the worktree's port held by that program again: it takes the next free port, kept from now on,
    // with the program left running, and its status says which.
    record = [ReadJSON(AppDir(@"ports.json")) mutableCopy];
    entry = [record[@"projects"][RealPath(project)] mutableCopy];
    kept = [entry[@"folders"] mutableCopy];
    kept[RealPath(tree)] = @(base + 7);
    entry[@"folders"] = kept;
    record[@"projects"] = @{RealPath(project): entry};
    [[NSJSONSerialization dataWithJSONObject:record options:0 error:nil] writeToFile:AppDir(@"ports.json") atomically:YES];
    say(@"Asked for in the worktree by a session, its port held", asked(tree));
    say(@"…its status", askedStatus(tree));
    say(@"…the worktree's port from now on", at(ReadJSON(AppDir(@"ports.json"))[@"projects"][RealPath(project)]
                                                    [@"folders"][RealPath(tree)]));
    say(@"…and the program on its old port", PortHolder((int)base + 7) ? @"still there" : @"gone");
    say(@"Stopped", stop(tree));

    // A made-up token in a confirmed command, which prints it and fails, so its run's last line holds it too: set on
    // the card, deployed by a press, run once more as asked for by a session, and a version too long to save. None of
    // it reaches panel.log; only the run's own log has it. Nothing here prints the command, its answers or its lines.
    NSString *token = [@"wz-made-up-" stringByAppendingString:NSUUID.UUID.UUIDString];
    NSString *carries = [NSString stringWithFormat:@"echo %@; false", token];
    [deploys readNowFor:@[rowIn(project)]];
    [deploys check:carries forRow:rowIn(project)];
    [deploys settle];
    [deploys save:carries forRow:rowIn(project) thenDeploy:NO];
    [deploys settle];
    void (^ends)(void) = ^{
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:MAX(seconds, 60)];
        while (until.timeIntervalSinceNow > 0 && [LastDeployRun(project)[@"running"] boolValue])
            [NSThread sleepForTimeInterval:0.2];
    };
    [deploys readNowFor:@[rowIn(project)]];
    id pressedAfter = LastDeployRun(project)[@"startedAt"];
    [deploys deploy:rowIn(project)];
    [deploys settle];
    NSString *pressed = [LastDeployRun(project)[@"startedAt"] isEqual:pressedAfter] ? @"didn't run" : @"ran";
    ends();
    [deploys runIn:project project:project expecting:carries by:@"Asker" reconfirm:NULL];
    ends();
    [deploys save:[carries stringByPaddingToLength:1200 withString:@" #" startingAtIndex:0] forRow:rowIn(project)
       thenDeploy:NO];
    [deploys settle];
    NSString *(^has)(NSString *) = ^NSString *(NSString *path) {
        NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        return [text containsString:token] ? @"has it" : @"hasn't it";
    };
    say(@"A made-up token in a confirmed command, set, pressed, asked for and too long to save",
        [NSString stringWithFormat:@"the press %@, panel.log %@, the run's own log %@", pressed,
                                   has(AppDir(@"panel.log")), has(DeployLogPath(project))]);
    return 0;
}
