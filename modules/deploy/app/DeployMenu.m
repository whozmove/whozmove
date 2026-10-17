// DeployMenu: Deploy's menu.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "DeployMenu.h"
#import "Deploys.h"
#import "Core.h"
#import "Rows.h"
#import "Page.h"
#import "PanelWindow.h"
#import "Menus.h"
#import "Files.h"
#import "Row.h"

@interface DeployMenu ()
@property (weak) Core *core;
@property (strong) Deploys *deploys;
@end

@implementation DeployMenu

- (instancetype)initWithCore:(Core *)core deploys:(Deploys *)deploys {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.deploys = deploys;
    return self;
}

- (void)menu:(NSDictionary *)msg {
    Row *row = self.core.rows.byId[msg[@"sessionId"]];
    if (!row) return;
    NSMenu *menu = [NSMenu new];
    menu.autoenablesItems = NO;
    if ([msg[@"step"] isEqual:@"deploy"]) [self addDeployTo:menu row:row];
    if (!menu.numberOfItems) return;
    [self.core.window popUpMenu:menu atPagePoint:NSMakePoint([msg[@"x"] doubleValue], [msg[@"y"] doubleValue])];
}

- (NSMenuItem *)add:(NSString *)title to:(NSMenu *)menu action:(SEL)action row:(Row *)row {
    NSMenuItem *item = [menu addItemWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
    item.representedObject = row.sessionId;
    return item;
}

// Deploy's menu, from its round button (a right-click, or a press while a deploy runs). While a run goes on: what's
// running, stopping it, and its log so far. Once you've confirmed a command: what it runs (so you always see it),
// changing it, forgetting it (Deploy is then offered only after new work again), and the last run's log. With only a
// suggestion: setting it up, or passing on it until the next piece of work.
- (void)addDeployTo:(NSMenu *)menu row:(Row *)row {
    NSDictionary *deploy = [self.deploys stateOf:row];
    if ([deploy[@"running"] boolValue]) {
        if (deploy[@"command"]) SayInMenu(menu, [@"Running: " stringByAppendingString:Clip(deploy[@"command"], 60)]);
        [self add:@"Stop Deploy" to:menu action:@selector(stop:) row:row];
    } else if (deploy[@"command"]) {
        SayInMenu(menu, [@"Runs: " stringByAppendingString:Clip(deploy[@"command"], 60)]);
        [self add:@"Change Deploy Command…" to:menu action:@selector(change:) row:row];
        [self add:@"Forget Deploy Command" to:menu action:@selector(forget:) row:row];
    } else {
        SayInMenu(menu, deploy[@"suggested"] ? [@"Suggested: " stringByAppendingString:Clip(deploy[@"suggested"], 60)]
                                       : @"Not set up for this project yet");
        [self add:@"Set Up Deploy…" to:menu action:@selector(setUp:) row:row];
        [self add:@"Not This Time" to:menu action:@selector(skip:) row:row];
    }
    if (deploy[@"log"]) {
        [menu addItem:NSMenuItem.separatorItem];
        NSMenuItem *log = [self add:@"Open Log" to:menu action:@selector(openLog:) row:row];
        log.representedObject = deploy[@"log"];
    }
}

- (void)change:(NSMenuItem *)item {
    [self.core.page call:@"openDeploySetup" with:@[item.representedObject ?: @"", @"save"]];
}

- (void)setUp:(NSMenuItem *)item {
    [self.core.page call:@"openDeploySetup" with:@[item.representedObject ?: @"", @"deploy"]];
}

- (void)skip:(NSMenuItem *)item {
    Row *row = self.core.rows.byId[item.representedObject];
    if (row) [self.deploys skip:row];
}

- (void)forget:(NSMenuItem *)item {
    Row *row = self.core.rows.byId[item.representedObject];
    if (row) [self.deploys forget:row];
}

- (void)stop:(NSMenuItem *)item {
    Row *row = self.core.rows.byId[item.representedObject];
    if (row) [self.deploys stop:row];
}

- (void)openLog:(NSMenuItem *)item {
    [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:item.representedObject]];
}

@end
