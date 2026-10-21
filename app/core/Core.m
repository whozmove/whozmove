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
@end

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
    return [self hostHolding:row] ?: [self hostFor:OwningApp(row.pid).bundleIdentifier];
}

- (NSArray *)hostsThat:(Protocol *)capability {
    return [self.hosts filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id host, id _) {
        return [host conformsToProtocol:capability];
    }]];
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

- (NSDictionary<NSString *, void (^)(NSDictionary *)> *)messages {
    __weak typeof(self) weakSelf = self;
    return @{
        @"height": ^(NSDictionary *msg) { [weakSelf.window fitHeight:[msg[@"value"] doubleValue]]; },
        @"expand": ^(NSDictionary *msg) {
            [weakSelf.window expandReader:[msg[@"width"] doubleValue] height:[msg[@"height"] doubleValue]];
        },
        @"collapse": ^(NSDictionary *msg) { [weakSelf.window collapse:[msg[@"height"] doubleValue]]; },
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
