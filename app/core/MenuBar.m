// MenuBar: the pawn in the menu bar, its count, and its menu: the grouping, Next Steps, Working on Whozmove, and the
// modules' items, each in its section.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "MenuBar.h"
#import "PanelWindow.h"
#import "Page.h"
#import "Files.h"
#import "Menus.h"
#import "Builds.h"
#import "Module.h"

// The menu's switches, kept in the app's preferences as the grouping is: Show Next Steps (each row's island, with
// its menus) and Show Deploy (its Deploy step), on until unticked; and Show Build in Header, for working on Whozmove
// itself, off until ticked.
static NSString *const kShowNextSteps = @"showNextSteps", *const kShowDeploy = @"showDeploy",
                *const kShowBuild = @"showBuild";

@interface MenuBar () <NSMenuDelegate>
@property (strong) Page *page;
@property (strong) PanelWindow *window;
@property (strong) NSStatusItem *statusItem;
@property (strong) NSMenuItem *groupByStatusItem;
@property (strong) NSMenuItem *groupByProjectItem;
@property (strong) NSMenuItem *showNextStepsItem;
@property (strong) NSMenuItem *showDeployItem;
@property (strong) NSMenuItem *showBuildItem;
@property (copy) NSArray<NSMenuItem *> *wozItems;  // Working on Whozmove, and the line above it
@property (strong) NSMutableArray<MenuEntry *> *entries;  // its own items and the modules', by section
@end

@implementation MenuBar

- (instancetype)initWithWindow:(PanelWindow *)window page:(Page *)page {
    if (!(self = [super init])) return nil;
    self.page = page;
    self.window = window;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults registerDefaults:@{kShowNextSteps: @YES, kShowDeploy: @YES, kShowBuild: @NO}];
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    // The Whozmove pawn ("your move"), drawn as a template image so it follows the menu bar's light/dark
    // tint. Same shape as the app icon (PawnPath in make-icon.m), the panel's header mark and its deploy button
    // (PAWN_ICON in panel/scripts/icons.js); keep them in step. One path, so it fills as one shape with no seams
    // where its parts meet; the body runs the same way round as the oval and rounded rectangles, or the overlaps
    // would cancel out.
    NSImage *pawn = [NSImage imageWithSize:NSMakeSize(16, 16) flipped:YES drawingHandler:^BOOL(NSRect rect) {
        NSBezierPath *shape = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(5.6, 1.5, 4.8, 4.8)];
        [shape appendBezierPath:[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(4.9, 6.1, 6.2, 1.3)
                                                                xRadius:0.65 yRadius:0.65]];
        [shape moveToPoint:NSMakePoint(9.7, 7.3)];
        [shape curveToPoint:NSMakePoint(11.6, 12.2)
              controlPoint1:NSMakePoint(9.7, 9.8) controlPoint2:NSMakePoint(11.0, 11.3)];
        [shape lineToPoint:NSMakePoint(4.4, 12.2)];
        [shape curveToPoint:NSMakePoint(6.3, 7.3)
              controlPoint1:NSMakePoint(5.0, 11.3) controlPoint2:NSMakePoint(6.3, 9.8)];
        [shape closePath];
        [shape appendBezierPath:[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(3.2, 11.9, 9.6, 2.3)
                                                                xRadius:1.15 yRadius:1.15]];
        [NSColor.blackColor setFill];
        [shape fill];
        return YES;
    }];
    pawn.template = YES;
    pawn.accessibilityDescription = @"Whozmove";
    self.statusItem.button.image = pawn;
    self.statusItem.button.imagePosition = NSImageLeft;
    // Its own items, in the sections modules' items go in too (addEntries:), each with its order there.
    self.groupByStatusItem = [self item:@"Group by Status" action:@selector(groupByStatus) key:@""];
    self.groupByProjectItem = [self item:@"Group by Project" action:@selector(groupByProject) key:@""];
    NSMenu *steps = [NSMenu new];
    steps.autoenablesItems = NO;
    self.showNextStepsItem = [steps addItemWithTitle:@"Show Next Steps" action:@selector(toggleNextSteps)
                                       keyEquivalent:@""];
    self.showNextStepsItem.target = self;
    self.showDeployItem = [steps addItemWithTitle:@"Show Deploy" action:@selector(toggleDeploy) keyEquivalent:@""];
    self.showDeployItem.target = self;
    NSMenuItem *stepsItem = [self item:@"Next Steps" action:nil key:@""];
    stepsItem.submenu = steps;
    self.showBuildItem = [self item:@"Show Build in Header" action:@selector(toggleShowBuild) key:@""];
    self.entries = [@[[MenuEntry entryIn:MenuSectionFeatures order:10 item:stepsItem],
                      [MenuEntry entryIn:MenuSectionWhozmove order:10 item:self.showBuildItem]] mutableCopy];
    NSMenu *menu = [NSMenu new];
    menu.delegate = self;
    self.statusItem.menu = menu;
    [self layOut];
    return self;
}

// An item of this menu's own, which it answers itself.
- (NSMenuItem *)item:(NSString *)title action:(SEL)action key:(NSString *)key {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
    item.target = self;
    return item;
}

- (void)addEntries:(NSArray<MenuEntry *> *)entries {
    [self.entries addObjectsFromArray:entries];
    [self layOut];
}

// The menu, from the top: the top section (with a line under it), the panel's own items, the grouping, the features,
// Working on Whozmove (shown only while ⌥ is held: menuNeedsUpdate:) and Quit. Each section's items, its own and the
// modules', in their order there.
- (void)layOut {
    NSMenu *menu = self.statusItem.menu;
    [menu removeAllItems];
    NSArray<NSMenuItem *> *(^section)(MenuSection) = ^NSArray<NSMenuItem *> *(MenuSection which) {
        NSPredicate *inIt = [NSPredicate predicateWithBlock:^BOOL(MenuEntry *entry, NSDictionary *bindings) {
            return entry.section == which;
        }];
        NSArray *entries = [[self.entries filteredArrayUsingPredicate:inIt]
            sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"order" ascending:YES]]];
        return [entries valueForKey:@"item"];
    };
    // An item is in one menu at a time, so one laid out before leaves the menu it was in first.
    void (^put)(NSMenuItem *, NSMenu *) = ^(NSMenuItem *item, NSMenu *into) {
        [item.menu removeItem:item];
        [into addItem:item];
    };
    NSArray *top = section(MenuSectionTop);
    for (NSMenuItem *item in top) put(item, menu);
    if (top.count) [menu addItem:NSMenuItem.separatorItem];
    [menu addItemWithTitle:@"Show / Hide Panel" action:@selector(toggle) keyEquivalent:@""].target = self.window;
    [menu addItemWithTitle:@"Reset Position" action:@selector(resetPosition) keyEquivalent:@""].target = self.window;
    [menu addItem:NSMenuItem.separatorItem];
    for (NSMenuItem *item in @[self.groupByStatusItem, self.groupByProjectItem]) put(item, menu);
    [menu addItem:NSMenuItem.separatorItem];
    for (NSMenuItem *item in section(MenuSectionFeatures)) put(item, menu);
    // Only for working on Whozmove itself: it shows while ⌥ is held as the menu opens (menuNeedsUpdate:).
    NSMenuItem *line = NSMenuItem.separatorItem;
    [menu addItem:line];
    NSMenu *woz = [NSMenu new];
    for (NSMenuItem *item in section(MenuSectionWhozmove)) put(item, woz);
    NSMenuItem *wozItem = [menu addItemWithTitle:@"Working on Whozmove" action:nil keyEquivalent:@""];
    wozItem.submenu = woz;
    self.wozItems = @[line, wozItem];
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItemWithTitle:@"Quit Whozmove" action:@selector(terminate:) keyEquivalent:@"q"].target = NSApp;
}

// Working on Whozmove is only for people working on Whozmove itself, so it shows only while ⌥ is held as the menu
// opens.
- (void)menuNeedsUpdate:(NSMenu *)menu {
    if (menu != self.statusItem.menu) return;
    BOOL option = (NSEvent.modifierFlags & NSEventModifierFlagOption) != 0;
    for (NSMenuItem *item in self.wozItems) item.hidden = !option;
    for (MenuEntry *entry in self.entries)
        if (entry.willOpen) entry.willOpen();
}

- (void)showCount:(NSInteger)count {
    self.statusItem.button.title = count > 0 ? [NSString stringWithFormat:@" %ld", (long)count] : @"";
}

// The panel's grouping, chosen from this menu: Status (Your turn, Working, Seen, Idle) or Project.
- (void)groupByStatus { [self applyGroupBy:@"status"]; }

- (void)groupByProject { [self applyGroupBy:@"project"]; }

- (void)applySavedGrouping {
    [self applyGroupBy:[NSUserDefaults.standardUserDefaults stringForKey:@"groupBy"]];
}

// Anything but Project is Status, a grouping this menu no longer offers included, and it's saved as such.
- (void)applyGroupBy:(NSString *)mode {
    if (![mode isEqual:@"project"]) mode = @"status";
    [NSUserDefaults.standardUserDefaults setObject:mode forKey:@"groupBy"];
    [self.page setGroupBy:mode];
    self.groupByStatusItem.state = [mode isEqual:@"status"] ? NSControlStateValueOn : NSControlStateValueOff;
    self.groupByProjectItem.state = [mode isEqual:@"project"] ? NSControlStateValueOn : NSControlStateValueOff;
}

// The switches: each flips its preference, and the page is told.
- (void)toggleNextSteps { [self flip:kShowNextSteps]; }

- (void)toggleDeploy { [self flip:kShowDeploy]; }

- (void)toggleShowBuild { [self flip:kShowBuild]; }

- (void)flip:(NSString *)key {
    FlipSwitch(key);
    [self applySavedSwitches];
}

- (BOOL)showsNextSteps {
    return SwitchedOn(kShowNextSteps);
}

- (void)applySavedSwitches {
    self.showNextStepsItem.state = SwitchedOn(kShowNextSteps) ? NSControlStateValueOn : NSControlStateValueOff;
    self.showDeployItem.state = SwitchedOn(kShowDeploy) ? NSControlStateValueOn : NSControlStateValueOff;
    self.showDeployItem.enabled = SwitchedOn(kShowNextSteps);  // Deploy is one of the next steps
    self.showBuildItem.state = SwitchedOn(kShowBuild) ? NSControlStateValueOn : NSControlStateValueOff;
    self.window.headerTip = SwitchedOn(kShowBuild) ? RunningBuildTip() : nil;
    [self.page setSwitches:@{@"nextSteps": @(SwitchedOn(kShowNextSteps)), @"deploy": @(SwitchedOn(kShowDeploy)),
                             @"build": @(SwitchedOn(kShowBuild))}];
}

@end
