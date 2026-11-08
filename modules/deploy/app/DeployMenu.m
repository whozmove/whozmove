// DeployMenu: Deploy's menu.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "DeployMenu.h"
#import "Deploys.h"
#import "DeployAsks.h"
#import "DeployKept.h"
#import "Allowed.h"
#import "Core.h"
#import "Rows.h"
#import "Page.h"
#import "PanelWindow.h"
#import "Menus.h"
#import "Files.h"
#import "Row.h"
#import "Links.h"

@interface DeployMenu ()
@property (weak) Core *core;
@property (strong) Deploys *deploys;
@property (strong) DeployAsks *asks;
@property (strong) DeployKept *kept;
@end

@implementation DeployMenu

- (instancetype)initWithCore:(Core *)core deploys:(Deploys *)deploys asks:(DeployAsks *)asks kept:(DeployKept *)kept {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.deploys = deploys;
    self.asks = asks;
    self.kept = kept;
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

// Deploy's menu, from its round button (a right-click, or a press while a deploy runs). While a server's up: where it
// runs and for how long, opening it, restarting it and stopping it. While another run goes on: what's running,
// stopping it, and its log so far. Once you've confirmed a command: what it runs (so you always see it),
// changing it, forgetting it (Deploy is then offered only after new work again), and the last run's log; and while
// your press is kept for an agent at work there, what it waits for, with Don't Deploy. With only a suggestion: setting
// it up, or passing on it until the next piece of work.
- (void)addDeployTo:(NSMenu *)menu row:(Row *)row {
    NSDictionary *deploy = [self.deploys stateOf:row];
    NSDictionary *up = deploy[@"up"];
    if (up) {
        // A server that's up: where, and for how long; opening it; restarting it (not while something it waits for
        // is at work, which it says); stopping it.
        NSString *address = [self.deploys addressOf:row].absoluteString;
        address = [address stringByReplacingOccurrencesOfString:@"http://" withString:@""];
        long minutes = (long)((NSDate.date.timeIntervalSince1970 * 1000 - [up[@"at"] doubleValue]) / 60000);
        SayInMenu(menu, [NSString stringWithFormat:@"Running at %@%@", address,
                         minutes < 1 ? @", started just now"
                         : minutes < 60 ? [NSString stringWithFormat:@" for %ld min", minutes]
                                        : [NSString stringWithFormat:@" for %ld h", minutes / 60]]);
        [self add:[@"Open " stringByAppendingString:address] to:menu action:@selector(openAddress:) row:row];
        NSString *wait = [self.deploys whyNotNow:row];
        NSMenuItem *restart = [self add:@"Restart" to:menu action:@selector(restart:) row:row];
        restart.enabled = !wait;
        if (wait) SayInMenu(menu, wait);
        [self add:@"Stop Deploy" to:menu action:@selector(stop:) row:row];
    } else if ([deploy[@"running"] boolValue]) {
        if (deploy[@"command"]) SayInMenu(menu, [@"Running: " stringByAppendingString:Clip(deploy[@"command"], 60)]);
        [self add:@"Stop Deploy" to:menu action:@selector(stop:) row:row];
    } else if (deploy[@"command"]) {
        SayInMenu(menu, [@"Runs: " stringByAppendingString:Clip(deploy[@"command"], 60)]);
        if ([self.kept keptIn:DeployFolder(row)]) {
            // What it waits for, as the button says it ("Deploy waits until the agent … is done"), said as what
            // happens then.
            NSString *wait = [self.deploys whyNotNow:row];
            NSString *until = @"Deploy waits until ";
            NSString *once = [wait hasPrefix:until]
                ? [@"Deploys once " stringByAppendingString:[wait substringFromIndex:until.length]] : wait;
            SayInMenu(menu, once ?: @"Deploys now");
            NSMenuItem *drop = [self add:@"Don't Deploy" to:menu action:@selector(dropKept:) row:row];
            drop.representedObject = DeployFolder(row);
        }
        [self add:@"Change Deploy Command…" to:menu action:@selector(change:) row:row];
        [self add:@"Forget Deploy Command" to:menu action:@selector(forget:) row:row];
    } else {
        SayInMenu(menu, deploy[@"suggested"] ? [@"Suggested: " stringByAppendingString:Clip(deploy[@"suggested"], 60)]
                                       : @"Not set up for this project yet");
        [self add:@"Set Up Deploy…" to:menu action:@selector(setUp:) row:row];
        [self add:@"Not This Time" to:menu action:@selector(skip:) row:row];
    }
    [self addAskersTo:menu row:row];
    if (deploy[@"log"]) {
        [menu addItem:NSMenuItem.separatorItem];
        NSMenuItem *log = [self add:@"Open Log" to:menu action:@selector(openLog:) row:row];
        log.representedObject = deploy[@"log"];
    }
}

// Who may ask for Deploy in this checkout (Let It Deploy, in their mode menus: the sessions whose own checkout it is),
// and the deploy one asked for, waiting in this folder, with Not This Time to drop it.
- (void)addAskersTo:(NSMenu *)menu row:(Row *)row {
    NSString *folder = DeployFolder(row);
    NSDictionary *asked = [self.asks askedIn:folder];
    NSMutableArray<NSString *> *may = [NSMutableArray array];
    for (Row *other in self.core.rows.byId.allValues)
        if ([DeployFolder(other) isEqual:folder] && [self.core.allowed isOn:kLetItDeploy for:other])
            [may addObject:[NSString stringWithFormat:@"“%@”", SessionTitle(other)]];
    if (!asked && !may.count) return;
    [menu addItem:NSMenuItem.separatorItem];
    if (asked) {
        SayInMenu(menu, [NSString stringWithFormat:@"Asked by “%@”: it %@", asked[@"by"],
                                                   asked[@"waits"] ?: @"runs now"]);
        NSMenuItem *drop = [self add:@"Not This Time" to:menu action:@selector(dropAsk:) row:row];
        drop.representedObject = folder;
    }
    [may sortUsingSelector:@selector(compare:)];
    if (may.count)
        SayInMenu(menu, [NSString stringWithFormat:@"%@ may ask for Deploy",
                                                   [may componentsJoinedByString:@", "]]);
}

- (void)dropAsk:(NSMenuItem *)item {
    [self.asks dropIn:item.representedObject];
}

- (void)dropKept:(NSMenuItem *)item {
    [self.kept dropIn:item.representedObject];
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

- (void)openAddress:(NSMenuItem *)item {
    Row *row = self.core.rows.byId[item.representedObject];
    if (row) [self.deploys openAddress:row];
}

- (void)restart:(NSMenuItem *)item {
    Row *row = self.core.rows.byId[item.representedObject];
    if (row) [self.deploys restart:row];
}

- (void)openLog:(NSMenuItem *)item {
    OpenInOtherApp([NSURL fileURLWithPath:item.representedObject]);
}

@end
