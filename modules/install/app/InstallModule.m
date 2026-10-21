// InstallModule: the install module's face for the core (contracts/Module.h): Whozmove setting itself up as it opens
// (Install), looked at again while it waits; the line under the header told how it stands, and its presses; the cards
// on the panel's back, on Git's page and the one the agent's settings go on; and its print modes.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
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
    install.tools = ^BOOL (BOOL now) { return now ? DeveloperToolsLookNow() : DeveloperToolsReady(); };
    install.installer = ^BOOL { return InstallerOpen(); };
    install.askTools = ^{ AskForTools(); };
    install.connect = ^NSDictionary *(NSString *answer, BOOL before, NSString *from) {
        return [agent connect:answer before:before from:from];
    };
    __weak typeof(self) weakSelf = self;
    install.onFound = ^(NSDictionary *found) { [weakSelf tell]; };
    self.install = install;
    [install check:nil];
}

- (void)pageLoaded {
    [self tell];
}

- (void)tick {
    [self.install tick];
}

#pragma mark The line, and the presses

// The line under the header, told how things stand each time that changes, as a press sets a check going, and when
// the page loads again: {state, detail, since, busy}, busy while a check is under way, when the line's button waits.
- (void)tell {
    NSDictionary *found = self.install.found;
    if (!found || !self.core.page.ready) return;
    NSMutableDictionary *told = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"state", @"detail", @"since"])
        if (found[key]) told[key] = found[key];
    told[@"busy"] = @(self.install.working);
    [self.core.page call:@"setInstall" with:@[told]];
}

- (NSDictionary<NSString *, void (^)(NSDictionary *)> *)messages {
    __weak typeof(self) weakSelf = self;
    return @{@"install": ^(NSDictionary *msg) { [weakSelf act:AsText(msg[@"action"])]; }};
}

// A press on the line or one of the cards on the panel's back, if it still fits how things stand (one made just as they
// changed, or while a check is under way, does nothing): Install has macOS open its installer, unless they're in or
// it's open; Add Back, Turn On and Try Again go to the agent; each on the check's queue, one at a time. Get Claude Code
// opens its install page in your browser. The line is told how things stand after every press, as its button waits
// from the press until it is.
- (void)act:(NSString *)action {
    NSDictionary *found = self.install.found;
    NSString *state = found[@"state"];
    NSDictionary<NSString *, NSString *> *fits = @{@"addBack": @"removed", @"turnOn": @"turnedOff", @"retry": @"failed"};
    BOOL fit = !found || self.install.working ? NO
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
    };
}

@end
