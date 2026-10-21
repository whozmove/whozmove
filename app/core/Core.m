// Core: the core's services for modules, and the page's messages it answers itself.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Core.h"
#import "Modules.h"
#import "Page.h"
#import "PanelWindow.h"
#import "MenuBar.h"
#import "Rows.h"
#import "Focus.h"
#import "Send.h"
#import "Row.h"
#import "Processes.h"
#import "Browser.h"

@interface Core ()
@property Page *page;
@property PanelWindow *window;
@property MenuBar *menuBar;
@property BOOL printing;
@property Modules *modules;
@property Rows *rows;
@property Focus *focus;
@property Send *send;
@property (copy) NSArray<id<Host>> *hosts;
@property (copy) NSArray<id<Agent>> *agents;
// Whether each app is on this Mac, by its app id, and when that was looked up: {found, at}.
@property (strong) NSMutableDictionary<NSString *, NSArray *> *apps;
@end

// The terminal picked on New Conversation's menu, by its app id: new sessions start there from then on.
static NSString *const kStartTerminal = @"startTerminal";
// How long whether an app is on this Mac is taken as known: it's asked every second for the ended sessions' rows.
static const NSTimeInterval kAppsKnownFor = 30;

@implementation Core

- (instancetype)initWithPage:(Page *)page window:(PanelWindow *)window menuBar:(MenuBar *)menuBar {
    if (!(self = [super init])) return nil;
    self.page = page;
    self.window = window;
    self.menuBar = menuBar;
    [self makeParts];
    return self;
}

+ (instancetype)forPrinting {
    Core *core = [[self alloc] init];
    core.printing = YES;
    [core makeParts];
    return core;
}

// The modules, and the core's own parts that act on them.
- (void)makeParts {
    self.modules = [[Modules alloc] initWithCore:self];
    NSMutableArray *hosts = [NSMutableArray array], *agents = [NSMutableArray array];
    for (id module in self.modules.all) {
        if ([module conformsToProtocol:@protocol(Host)]) [hosts addObject:module];
        if ([module conformsToProtocol:@protocol(Agent)]) [agents addObject:module];
    }
    self.hosts = hosts;
    self.agents = agents;
    self.rows = [[Rows alloc] initWithCore:self];
    self.focus = [[Focus alloc] initWithCore:self];
    self.send = [[Send alloc] initWithCore:self];
}

- (id<Host>)hostFor:(NSString *)appId {
    for (id<Host> host in self.hosts)
        if ([host.appId isEqualToString:appId]) return host;
    return nil;
}

- (id<Host>)hostHolding:(Row *)row {
    for (id<Host> host in self.hosts)
        if ([host respondsToSelector:@selector(holds:)] && [host holds:row]) return host;
    return nil;
}

- (id<Host>)hostOf:(Row *)row {
    id<Host> own = [self hostHolding:row];
    if (own) return own;
    NSRunningApplication *app = OwningApp(row.pid);
    return app ? [self hostFor:app.bundleIdentifier] : [self hostRunning:row.pid];
}

- (NSRunningApplication *)appOf:(pid_t)pid {
    NSRunningApplication *app = OwningApp(pid);
    if (app) return app;
    id<Host> host = [self hostRunning:pid];
    return host ? [NSRunningApplication runningApplicationsWithBundleIdentifier:host.appId].firstObject : nil;
}

// The host that says it runs a process no app is above (Host's runsProcess:), or nil.
- (id<Host>)hostRunning:(pid_t)pid {
    if (pid <= 0) return nil;
    for (id<Host> host in self.hosts)
        if ([host respondsToSelector:@selector(runsProcess:)] && [host runsProcess:pid]) return host;
    return nil;
}

- (NSArray *)hostsThat:(Protocol *)capability {
    return [self.hosts filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id host, id _) {
        return [host conformsToProtocol:capability];
    }]];
}

- (BOOL)hasEnded:(Row *)row {
    return [row.status isEqualToString:@"closed"] && row.pid <= 0 && ![self hostHolding:row];
}

- (BOOL)hasApp:(id<Host>)host {
    if (self.printing) return host != nil;
    if (!host.appId.length) return NO;
    NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
    NSArray *known = self.apps[host.appId];
    if (known && now - [known[1] doubleValue] < kAppsKnownFor) return [known[0] boolValue];
    BOOL found = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:host.appId] != nil;
    if (!self.apps) self.apps = [NSMutableDictionary dictionary];
    self.apps[host.appId] = @[@(found), @(now)];
    return found;
}

- (NSArray<id<CommandHost>> *)startTerminals {
    NSMutableArray<id<CommandHost>> *terminals = [NSMutableArray array];
    for (id<CommandHost> terminal in [self hostsThat:@protocol(CommandHost)])
        if ([terminal respondsToSelector:@selector(whichShows:done:)] && [self hasApp:terminal])
            [terminals addObject:terminal];
    return terminals;
}

- (id<CommandHost>)startTerminal {
    NSArray<id<CommandHost>> *terminals = self.startTerminals;
    NSString *picked = self.printing ? nil : [NSUserDefaults.standardUserDefaults stringForKey:kStartTerminal];
    for (id<CommandHost> terminal in terminals)
        if ([terminal.appId isEqualToString:picked]) return terminal;
    return terminals.firstObject;
}

- (void)pickStartTerminal:(NSString *)appId {
    if (appId.length) [NSUserDefaults.standardUserDefaults setObject:appId forKey:kStartTerminal];
}

- (id<Agent>)agentOf:(Row *)row {
    return self.agents.firstObject;
}

- (NSArray *)agentsThat:(Protocol *)capability {
    return [self.agents filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id agent, id _) {
        return [agent conformsToProtocol:capability];
    }]];
}

- (NSArray<NSString *> *)agentMarks {
    if (!self.agents.count) return nil;
    NSMutableOrderedSet *marks = [NSMutableOrderedSet orderedSet];
    for (id<Agent> agent in self.agents) [marks addObjectsFromArray:agent.environmentMarks];
    return marks.array;
}

- (Browser *)browserWith:(BrowserSetup *)setup owner:(id<BrowserOwner>)owner {
    return self.printing ? nil : [[Browser alloc] initWithSetup:setup owner:owner];
}

- (NSDictionary<NSString *, void (^)(NSDictionary *)> *)messages {
    __weak typeof(self) weakSelf = self;
    return @{
        @"height": ^(NSDictionary *msg) { [weakSelf.window fitHeight:[msg[@"value"] doubleValue]]; },
        @"expand": ^(NSDictionary *msg) {
            [weakSelf.window expandReader:[msg[@"width"] doubleValue] height:[msg[@"height"] doubleValue]];
        },
        @"collapse": ^(NSDictionary *msg) { [weakSelf.window collapse:[msg[@"height"] doubleValue]]; },
        @"turn": ^(NSDictionary *msg) { [weakSelf.window turnOver:[msg[@"on"] boolValue] then:nil]; },
        @"fold": ^(NSDictionary *msg) {
            [weakSelf.window fold:[msg[@"on"] boolValue] instant:[msg[@"instant"] boolValue]];
        },
        @"catAt": ^(NSDictionary *msg) {
            [weakSelf.window catAt:NSMakePoint([msg[@"x"] doubleValue], [msg[@"y"] doubleValue])];
        },
        @"catFan": ^(NSDictionary *msg) {
            [weakSelf.window catFan:[msg[@"on"] boolValue] width:[msg[@"width"] doubleValue]
                             height:[msg[@"height"] doubleValue]];
        },
        @"catBreathe": ^(NSDictionary *msg) { [weakSelf.window catBreathe:[msg[@"working"] integerValue]]; },
        @"keyboard": ^(NSDictionary *msg) { [weakSelf.window takeKeyboard:[msg[@"on"] boolValue]]; },
        @"badge": ^(NSDictionary *msg) { [weakSelf.menuBar showCount:[msg[@"value"] integerValue]]; },
        @"open": ^(NSDictionary *msg) { [weakSelf.focus open:msg]; },
    };
}

@end
