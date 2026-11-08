// MenuBar: Whozmove's mark in the menu bar, its count, and its menu: the panel, Working on Whozmove, and the modules'
// items (Settings… among them), each in its section; and the panel's switches, which Git's page on the panel's back
// sets.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "MenuBar.h"
#import "PanelWindow.h"
#import "Page.h"
#import "Files.h"
#import "Menus.h"
#import "Builds.h"
#import "Module.h"
#import "CatShape.h"

// The panel's switches, kept in the app's preferences as the grouping is: Show Next Steps (each row's next steps) and
// Show Deploy (its Deploy step), on until turned off on Git's page on the panel's back; and the menu's Show
// Build in Header, for working on Whozmove itself, off until ticked.
static NSString *const kShowNextSteps = @"showNextSteps", *const kShowDeploy = @"showDeploy",
                *const kShowBuild = @"showBuild";

// The mark in the menu bar: the folded cat alone, its head and folded ears in one colour with its eyes and nose cut
// out, as the name's o has it, a template image so it takes the menu bar's tint. Its shapes are in the cat's own units
// (CatShape.h), scaled to fill a 16-point box but for half a point each side.
static NSImage *MenuBarMark(void) {
    NSImage *mark = [NSImage imageWithSize:NSMakeSize(16, 16) flipped:YES drawingHandler:^BOOL(NSRect rect) {
        CGFloat scale = (NSWidth(rect) - 1) / kCatWide;
        NSAffineTransform *place = [NSAffineTransform transform];
        [place translateXBy:NSMidX(rect) yBy:NSMidY(rect) - kCatMiddleY * scale];
        [place scaleBy:scale];
        // The head and its ears are filled apiece: as one path, the right ear, drawn the other way round, would cancel
        // out where it overlaps the head.
        NSBezierPath *head = CatPath(kCatHead), *ears = CatPath(kCatEars), *nose = CatPath(kCatNose);
        NSBezierPath *eyes = [NSBezierPath bezierPath];
        for (int side = -1; side <= 1; side += 2)
            [eyes appendBezierPath:[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(side * kCatEyeX - kCatEyeR,
                kCatEyeY - kCatEyeR, 2 * kCatEyeR, 2 * kCatEyeR)]];
        for (NSBezierPath *path in @[head, ears, nose, eyes]) [path transformUsingAffineTransform:place];
        [NSColor.blackColor setFill];
        [head fill];
        [ears fill];
        NSGraphicsContext.currentContext.compositingOperation = NSCompositingOperationDestinationOut;
        [eyes fill];
        [nose fill];
        return YES;
    }];
    mark.template = YES;
    mark.accessibilityDescription = @"Whozmove";
    return mark;
}

@interface MenuBar () <NSMenuDelegate>
@property (strong) Page *page;
@property (strong) PanelWindow *window;
@property (strong) NSStatusItem *statusItem;
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
    self.statusItem.button.image = MenuBarMark();
    self.statusItem.button.imagePosition = NSImageLeft;
    // Its own items, in the sections modules' items go in too (addEntries:), each with its order there.
    self.showBuildItem = [self item:@"Show Build in Header" action:@selector(toggleShowBuild) key:@""];
    self.entries = [@[[MenuEntry entryIn:MenuSectionWhozmove order:10 item:self.showBuildItem]] mutableCopy];
    NSMenu *menu = [NSMenu new];
    menu.delegate = self;
    self.statusItem.menu = menu;
    [self layOut];
    // The page is told the panel's look with the switches, each time Settings changes it.
    __weak typeof(self) weakSelf = self;
    [window followLook:^{ [weakSelf applySavedSwitches]; }];
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

// The menu, from the top: the top section (with a line under it), the panel's own items, the features (Settings…),
// Working on Whozmove (shown only while ⌥ is held: menuNeedsUpdate:), Whozmove's own (Open at Login) and Quit. Each
// section's items, its own and the modules', in their order there. What you choose once and come back to now and then
// is in Settings, on the panel's back; what's here works while the panel is hidden, folded or lost off the screen.
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
    NSArray *features = section(MenuSectionFeatures);
    if (features.count) [menu addItem:NSMenuItem.separatorItem];
    for (NSMenuItem *item in features) put(item, menu);
    // Only for working on Whozmove itself: it shows while ⌥ is held as the menu opens (menuNeedsUpdate:).
    NSMenuItem *line = NSMenuItem.separatorItem;
    [menu addItem:line];
    NSMenu *woz = [NSMenu new];
    for (NSMenuItem *item in section(MenuSectionWhozmove)) put(item, woz);
    NSMenuItem *wozItem = [menu addItemWithTitle:@"Working on Whozmove" action:nil keyEquivalent:@""];
    wozItem.submenu = woz;
    self.wozItems = @[line, wozItem];
    [menu addItem:NSMenuItem.separatorItem];
    for (NSMenuItem *item in section(MenuSectionApp)) put(item, menu);
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

// The switches: each changes its preference, and the page is told.
- (void)toggleShowBuild {
    FlipSwitch(kShowBuild);
    [self applySavedSwitches];
}

- (BOOL)showsNextSteps {
    return SwitchedOn(kShowNextSteps);
}

- (void)setShowsNextSteps:(BOOL)on {
    SetSwitch(kShowNextSteps, on);
    [self applySavedSwitches];
}

- (BOOL)showsDeploy {
    return SwitchedOn(kShowDeploy);
}

- (void)setShowsDeploy:(BOOL)on {
    SetSwitch(kShowDeploy, on);
    [self applySavedSwitches];
}

- (void)applySavedSwitches {
    self.showBuildItem.state = SwitchedOn(kShowBuild) ? NSControlStateValueOn : NSControlStateValueOff;
    self.window.headerTip = SwitchedOn(kShowBuild) ? RunningBuildTip() : nil;
    [self.page setSwitches:@{@"nextSteps": @(SwitchedOn(kShowNextSteps)), @"deploy": @(SwitchedOn(kShowDeploy)),
                             @"build": @(SwitchedOn(kShowBuild)), @"look": self.window.look ?: @"grey"}];
}

@end
