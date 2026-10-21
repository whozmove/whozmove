// InstallModule: the install module's face for the core (contracts/Module.h): Whozmove setting itself up as it opens
// (Install), looked at again while it waits; the sessions running since before the hooks went in, reloaded from the
// panel (Reloads); a newer version out through Homebrew, said and never installed (Updates), and Open at Login in the
// pawn menu (LoginItem); the line under the header told how it stands, and its presses; the cards on the panel's back,
// on Git's page and the one the agent's settings go on; and its print modes.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import <ServiceManagement/ServiceManagement.h>
#import "Module.h"
#import "Agent.h"
#import "Core.h"
#import "Page.h"
#import "Builds.h"
#import "Files.h"
#import "Links.h"
#import "Log.h"
#import "Processes.h"
#import "Install.h"
#import "Reloads.h"
#import "LoginItem.h"
#import "LaunchdFacts.h"
#import "HomebrewFacts.h"
#import "Updates.h"
#import "ToolsFacts.h"

// Whether macOS's installer for Apple's developer tools is open: from its question until they're in, or you close it.
static BOOL InstallerOpen(void) {
    return [NSRunningApplication runningApplicationsWithBundleIdentifier:kToolsInstallerId].count > 0;
}

// Has macOS ask whether to install them, in its own window: it puts them in from there.
static void AskForTools(void) {
    NSDictionary *run = RunBriefly(kToolsInstallCommand, @[kToolsInstallFlag], nil, 10, 4096, YES);
    NSString *said = run ? [[[NSString alloc] initWithData:run[@"out"] encoding:NSUTF8StringEncoding]
                            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : nil;
    PanelLog(@"install: asked macOS to install Apple's developer tools -> %@", said.length ? said
             : run ? run[@"status"] : @"didn't start");
}

@interface InstallModule : NSObject <Module>
@property (weak) Core *core;
@property (strong) Install *install;
@property (strong) Reloads *reloads;
@property (strong) Updates *updates;
// A press that came while a check was under way, judged again once it has ended.
@property (copy) NSString *pressed;
// Open at Login, in the pawn menu; and whether you've turned Whozmove off in System Settings' Login Items, where only
// you can turn it back on, so a press takes you there.
@property (strong) NSMenuItem *loginItem;
@property (assign) BOOL loginOffInSettings;
// Your last press on it, until the check's queue has done it, so its tick follows the press at once.
@property (strong) NSNumber *loginWanted;
@property (weak) id<AgentInstall> agent;
@end

@implementation InstallModule

+ (NSString *)moduleName {
    return @"install";
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    return self;
}

// Made here, not in setting up, as a print run never sets itself up: the agent is found once every module is made.
- (void)launch {
    id<AgentInstall> agent = [self.core agentsThat:@protocol(AgentInstall)].firstObject;
    self.agent = agent;
    NSString *hooks = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"plugin"];
    Install *install = [[Install alloc] initWithApp:NSBundle.mainBundle.bundlePath builtByAgent:BuiltByAgent()
                                              hooks:hooks];
    install.agentHere = ^BOOL { return agent.onThisMac; };
    install.label = NSBundle.mainBundle.bundleIdentifier;
    install.program = NSBundle.mainBundle.executablePath;
    install.launchctl = ^NSString *(NSArray<NSString *> *arguments) {
        NSDictionary *run = RunBriefly(kLaunchctl, arguments, nil, 10, 65536, NO);
        if (!run || [run[@"status"] intValue] != 0) return nil;
        return [[NSString alloc] initWithData:run[@"out"] encoding:NSUTF8StringEncoding] ?: @"";
    };
    install.tools = ^BOOL (BOOL now) { return now ? DeveloperToolsLookNow() : DeveloperToolsReady(); };
    install.installer = ^BOOL { return InstallerOpen(); };
    install.askTools = ^{ AskForTools(); };
    install.connect = ^NSDictionary *(NSString *answer, BOOL before, NSString *from) {
        return [agent connect:answer before:before from:from];
    };
    __weak typeof(self) weakSelf = self;
    Reloads *reloads = agent ? [[Reloads alloc] initWithCore:self.core agent:agent] : nil;
    reloads.onChange = ^{ [weakSelf tell]; };
    self.reloads = reloads;
    // Sessions running since before the hooks went in need reloading only while they're in.
    install.onFound = ^(NSDictionary *found) {
        BOOL in = [@[@"ready", @"added", @"updated"] containsObject:AsText(found[@"state"]) ?: @""];
        weakSelf.reloads.hooksAt = in ? AsNumber(found[@"hooksAt"]) : nil;
        // A press waiting for a check goes once nothing is queued any more (Open at Login may be, behind it).
        NSString *pressed = weakSelf.install.working ? nil : weakSelf.pressed;
        if (!weakSelf.install.working) weakSelf.loginWanted = nil;
        if (pressed) {
            weakSelf.pressed = nil;
            [weakSelf act:pressed];
        } else {
            [weakSelf tell];
        }
    };
    self.install = install;
    [install check:nil];
    // A new version out, for a copy Homebrew installed; a build from a checkout (one with a build record, the core's
    // RunningBuild) never looks.
    NSString *own = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    Updates *updates = [[Updates alloc] initWithPrefix:kHomebrewPrefix version:own fromCheckout:RunningBuild() != nil];
    updates.fetch = ^NSString *(NSURL *url) { return FetchText(url); };
    updates.onFound = ^{ [weakSelf tell]; };
    self.updates = updates;
    [updates look];
}

// GitHub's copy of the cask: a plain request, with no sign-in, cookies or cache, given up after 10 seconds. Only a
// page that answered with it counts. Called off the main thread.
static NSString *FetchText(NSURL *url) {
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.timeoutIntervalForRequest = 10;
    config.timeoutIntervalForResource = 10;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    dispatch_semaphore_t answered = dispatch_semaphore_create(0);
    __block NSString *text = nil;
    [[session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode
                                                                             : 0;
        if (!error && status == 200 && data.length < 65536)
            text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        dispatch_semaphore_signal(answered);
    }] resume];
    dispatch_semaphore_wait(answered, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(12 * NSEC_PER_SEC)));
    [session finishTasksAndInvalidate];
    return text;
}

- (void)pageLoaded {
    [self tell];
}

// A look that starts by itself tells the line too, so its button waits while it's under way.
- (void)tick {
    BOOL was = self.install.working;
    [self.install tick];
    if (!was && self.install.working) [self tell];
    [self.reloads tick];
    [self.updates tick];
}

// Once the rows are whole, each session that runs without the hooks is marked, for its row.
- (void)rows:(NSArray<Row *> *)rows phase:(RowPhase)phase {
    if (phase == RowPhaseListed) [self.reloads mark:rows];
}

#pragma mark The line, and the presses

// The line under the header, told how things stand each time that changes, as a press sets a check going, and when
// the page loads again: {state, detail, since, busy, reload, update}, busy while a check is under way, when the line's
// button waits, reload how the sessions running since before the hooks went in stand (Reloads' summary), and update a
// newer version out (Updates' found).
- (void)tell {
    NSDictionary *found = self.install.found;
    if (!found || !self.core.page.ready) return;
    NSMutableDictionary *told = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"state", @"detail", @"since"])
        if (found[key]) told[key] = found[key];
    told[@"busy"] = @(self.install.working || self.pressed != nil);
    if (self.reloads.summary) told[@"reload"] = self.reloads.summary;
    if (self.updates.found) told[@"update"] = self.updates.found;
    [self.core.page call:@"setInstall" with:@[told]];
}

- (NSDictionary<NSString *, void (^)(NSDictionary *)> *)messages {
    __weak typeof(self) weakSelf = self;
    return @{@"install": ^(NSDictionary *msg) {
        NSString *action = AsText(msg[@"action"]);
        if ([action isEqualToString:@"copyUpgrade"]) [weakSelf copyUpgrade];
        else if ([action isEqualToString:@"restart"]) [weakSelf restartIntoNewVersion];
        else if ([action isEqualToString:@"putAwayUpdate"]) [weakSelf.updates putAway:AsText(msg[@"version"])];
        else if ([action isEqualToString:@"reloadAll"]) [weakSelf.reloads reloadAll];
        else if ([action isEqualToString:@"reload"]) [weakSelf.reloads reload:AsText(msg[@"sessionId"])];
        else [weakSelf act:action];
    }};
}

// A press on the line or one of the cards on the panel's back, if it still fits how things stand (one made just as they
// changed does nothing; one made while a check is under way waits for it, then is judged by what it found): Install
// has macOS open its installer, unless they're in or it's open; Add Back, Turn On and Try Again go to the agent; each
// on the check's queue, one at a time. Get Claude Code opens its install page in your browser. The line is told how
// things stand after every press, as its button waits from the press until it is.
- (void)act:(NSString *)action {
    if (self.install.working && action) {
        self.pressed = action;
        [self tell];
        return;
    }
    NSDictionary *found = self.install.found;
    NSString *state = found[@"state"];
    NSDictionary<NSString *, NSString *> *fits = @{@"addBack": @"removed", @"turnOn": @"turnedOff", @"retry": @"failed"};
    BOOL fit = !found ? NO
             : [action isEqualToString:@"tools"] ? [self.toolsNow isEqualToString:@"missing"]
             : [action isEqualToString:@"getAgent"] ? [state isEqualToString:@"noCommand"]
             : action && [fits[action] isEqualToString:state];
    if (fit && [action isEqualToString:@"getAgent"]) {
        NSURL *page = self.agent.installPage;
        if (page) OpenLink(page.absoluteString);
    } else if (fit) {
        PanelLog(@"install: %@ pressed", action);
        [self.install check:action];
    }
    [self tell];
}

#pragma mark A new version

// The command that updates it, put on the clipboard for you to paste in a terminal: Whozmove never runs brew itself.
- (void)copyUpgrade {
    NSString *command = self.updates.found[@"command"];
    if (!command) return;
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:command forType:NSPasteboardTypeString];
    PanelLog(@"updates: copied \"%@\"", command);
}

// Homebrew put the new version in place of this one, which still runs: it's opened again from where it is, a second
// after this copy quits (a copy opened sooner would bow out to it), by a shell of its own with a clean environment.
- (void)restartIntoNewVersion {
    if (![self.updates.found[@"installed"] boolValue]) return;
    NSString *app = NSBundle.mainBundle.bundlePath;
    PanelLog(@"updates: restarting into %@", self.updates.found[@"version"]);
    pid_t pid = SpawnDetached(@"/bin/sh", @[@"-c", @"sleep 1; /usr/bin/open \"$0\"", app],
                              @{@"PATH": @"/usr/bin:/bin"}, nil, nil);
    if (pid <= 0) {
        LogProblem(@"updates: couldn't start Whozmove again, so it's left running");
        return;
    }
    [NSApp terminate:nil];
}

#pragma mark Open at Login

// Ticked while Whozmove opens at login, as the last check found; outside an Applications folder, where nothing is set
// up, it isn't there. On macOS 13 and later, macOS also says whether you've turned Whozmove off in its Login Items:
// then it's unticked, and a press opens Login Items, as only you can turn it on there.
- (NSArray<MenuEntry *> *)menuEntries {
    self.loginItem = [[NSMenuItem alloc] initWithTitle:@"Open at Login" action:@selector(pressLogin)
                                         keyEquivalent:@""];
    self.loginItem.target = self;
    MenuEntry *entry = [MenuEntry entryIn:MenuSectionApp order:10 item:self.loginItem];
    __weak typeof(self) weakSelf = self;
    entry.willOpen = ^{ [weakSelf showLogin]; };
    [self showLogin];
    return @[entry];
}

- (void)showLogin {
    NSNumber *login = self.loginWanted ?: AsNumber(self.install.found[@"login"]);
    self.loginItem.hidden = login == nil;
    BOOL on = login.boolValue;
    self.loginOffInSettings = NO;
    if (@available(macOS 13.0, *)) {
        if (on && self.install.label) {
            NSURL *file = [NSURL fileURLWithPath:LoginItemPath(self.install.label)];
            self.loginOffInSettings = [SMAppService statusForLegacyURL:file] == SMAppServiceStatusRequiresApproval;
        }
    }
    self.loginItem.state = on && !self.loginOffInSettings ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)pressLogin {
    if (self.loginOffInSettings) {
        if (@available(macOS 13.0, *)) [SMAppService openSystemSettingsLoginItems];
        return;
    }
    BOOL on = self.loginItem.state != NSControlStateValueOn;
    self.loginWanted = @(on);
    self.loginItem.state = on ? NSControlStateValueOn : NSControlStateValueOff;
    [self.install openAtLogin:on];
}

#pragma mark On the panel's back

// How the developer tools stand, for Git's page: while macOS's installer for them is open, as the last check found;
// otherwise as they are now.
- (NSString *)toolsNow {
    if ([self.install.found[@"tools"] isEqualToString:@"installing"]) return @"installing";
    return DeveloperToolsReady() ? @"in" : @"missing";
}

// What the line asks stays on the panel's back, with its button, so what you put away with its × can be done later:
// Apple's developer tools on Git's page, which git needs whatever else is set up, and Whozmove's plugin on the page the
// agent's settings go on (Claude Code's are on Claude's), under the agent's name.
- (NSArray<AppEntry *> *)appEntries {
    __weak typeof(self) weakSelf = self;
    AppStatus *tools = [AppStatus statusWithKey:@"tools" title:@"Apple's command line developer tools"
                                            now:^NSDictionary * {
                                                return ToolsCard(weakSelf.toolsNow, weakSelf.install.working);
                                            }
                                          press:^{ [weakSelf act:@"tools"]; }];
    tools.section = @"Developer tools";
    NSMutableArray<AppEntry *> *entries = [NSMutableArray arrayWithObject:[AppEntry statuses:@[tools] forApp:@"git"]];
    id<AgentInstall> agent = self.agent ?: [self.core agentsThat:@protocol(AgentInstall)].firstObject;
    if (agent.appId) {
        AppStatus *plugin = [AppStatus statusWithKey:@"plugin" title:@"Whozmove's plugin"
                                                 now:^NSDictionary * {
                                                     return PluginCard(weakSelf.install.found, weakSelf.install.working);
                                                 }
                                               press:^{
                                                   [weakSelf act:PluginCard(weakSelf.install.found, NO)[@"action"]];
                                               }];
        plugin.section = agent.name;
        [entries addObject:[AppEntry statuses:@[plugin] forApp:agent.appId]];
    }
    return entries;
}

+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return @{
        @"--print-install": ^(Core *core, NSArray<NSString *> *arguments) { return PrintInstall(arguments); },
        @"--print-install-cards": ^(Core *core, NSArray<NSString *> *arguments) { return PrintInstallCards(); },
        @"--print-updates": ^(Core *core, NSArray<NSString *> *arguments) { return PrintUpdates(arguments); },
    };
}

@end
