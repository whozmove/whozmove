// MenuBar: Whozmove's mark in the menu bar, its count, and its menu: the look, the grouping, Working on Whozmove, and
// the modules' items, each in its section; and the panel's switches, which Git's page on the panel's back sets.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "MenuBar.h"
#import "PanelWindow.h"
#import "Page.h"
#import "Files.h"
#import "Menus.h"
#import "Builds.h"
#import "Module.h"
#import "Appearance.h"

// The panel's switches, kept in the app's preferences as the grouping is: Show Next Steps (each row's island, with its
// menus) and Show Deploy (its Deploy step), on until turned off on Git's page on the panel's back; and the menu's Show
// Build in Header, for working on Whozmove itself, off until ticked.
static NSString *const kShowNextSteps = @"showNextSteps", *const kShowDeploy = @"showDeploy",
                *const kShowBuild = @"showBuild";
// The panel's look, kept the same way: grey until Black (white on the light panel) or Glass is picked, and light or dark
// as the Mac is until Light or Dark is. While macOS's Reduce Transparency is on, Glass is grey, and can't be picked, as
// macOS's own Liquid Glass choice can't.
static NSString *const kPanelLook = @"panelLook", *const kAppearance = @"appearance";

// The mark in the menu bar: the folded cat alone, its head and folded ears in one colour with its eyes and nose cut
// out, as the name's o has it, a template image so it takes the menu bar's tint. Its shapes are in the cat's own units
// (panel/scripts/cat.js), scaled to fill a 16-point box but for half a point each side.
static NSString *const kCatHead =
    @"M0 74C-46 74 -84 50 -84 10C-84 -20 -76 -40 -64 -52C-62 -64 -54 -72 -42 -72C-34 -72 -28 -68 -24 -64C-8 -68 8 -68 "
    @"24 -64C28 -68 34 -72 42 -72C54 -72 62 -64 64 -52C76 -40 84 -20 84 10C84 50 46 74 0 74Z";
static NSString *const kCatEars =
    @"M-70 -44C-68 -60 -54 -72 -36 -70C-30 -69 -26 -66 -24 -62L-45 -43C-49 -39 -54 -38 -58 -40ZM70 -44C68 -60 54 -72 "
    @"36 -70C30 -69 26 -66 24 -62L45 -43C49 -39 54 -38 58 -40Z";
static NSString *const kCatNose = @"M-7 22C-7 18 7 18 7 22C7 26 3 28 0 30C-3 28 -7 26 -7 22Z";
// Its eyes' middles and size, and its shape's middle and width, in its units.
static const CGFloat kCatEyeX = 30, kCatEyeY = 6, kCatEyeR = 13, kCatMiddleY = 1, kCatWide = 168;

// An SVG path's absolute M, L, C and Z, as an NSBezierPath.
static NSBezierPath *PathFrom(NSString *svg) {
    NSBezierPath *path = [NSBezierPath bezierPath];
    NSScanner *scan = [NSScanner scannerWithString:svg];
    scan.charactersToBeSkipped = [NSCharacterSet characterSetWithCharactersInString:@" ,"];
    NSCharacterSet *letters = [NSCharacterSet characterSetWithCharactersInString:@"MLCZ"];
    unichar command = 'M';
    double v[6];
    while (!scan.isAtEnd) {
        NSString *next = nil;
        if ([scan scanCharactersFromSet:letters intoString:&next]) {
            for (NSUInteger i = 0; i + 1 < next.length; i++)
                if ([next characterAtIndex:i] == 'Z') [path closePath];
            command = [next characterAtIndex:next.length - 1];
            if (command == 'Z') {
                [path closePath];
                continue;
            }
        }
        int count = command == 'C' ? 6 : 2;
        for (int i = 0; i < count; i++)
            if (![scan scanDouble:&v[i]]) return path;
        if (command == 'M') [path moveToPoint:NSMakePoint(v[0], v[1])];
        else if (command == 'L') [path lineToPoint:NSMakePoint(v[0], v[1])];
        else [path curveToPoint:NSMakePoint(v[4], v[5]) controlPoint1:NSMakePoint(v[0], v[1])
                  controlPoint2:NSMakePoint(v[2], v[3])];
        // More points after a move are lines, as in SVG.
        if (command == 'M') command = 'L';
    }
    return path;
}

static NSImage *MenuBarMark(void) {
    NSImage *mark = [NSImage imageWithSize:NSMakeSize(16, 16) flipped:YES drawingHandler:^BOOL(NSRect rect) {
        CGFloat scale = (NSWidth(rect) - 1) / kCatWide;
        NSAffineTransform *place = [NSAffineTransform transform];
        [place translateXBy:NSMidX(rect) yBy:NSMidY(rect) - kCatMiddleY * scale];
        [place scaleBy:scale];
        // The head and its ears are filled apiece: as one path, the right ear, drawn the other way round, would cancel
        // out where it overlaps the head.
        NSBezierPath *head = PathFrom(kCatHead), *ears = PathFrom(kCatEars), *nose = PathFrom(kCatNose);
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
@property (strong) NSMenuItem *groupByStatusItem;
@property (strong) NSMenuItem *groupByProjectItem;
@property (strong) NSMenuItem *showBuildItem;
@property (strong) NSMenuItem *lookItem, *blackItem, *greyItem, *glassItem, *systemItem, *lightItem, *darkItem;
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
    self.groupByStatusItem = [self item:@"Group by Status" action:@selector(groupByStatus) key:@""];
    self.groupByProjectItem = [self item:@"Group by Project" action:@selector(groupByProject) key:@""];
    self.showBuildItem = [self item:@"Show Build in Header" action:@selector(toggleShowBuild) key:@""];
    NSMenu *look = [NSMenu new];
    look.autoenablesItems = NO;
    self.blackItem = [self item:@"Black" action:@selector(pickBlack) key:@""];
    self.greyItem = [self item:@"Grey" action:@selector(pickGrey) key:@""];
    self.glassItem = [self item:@"Glass" action:@selector(pickGlass) key:@""];
    self.systemItem = [self item:@"Match System" action:@selector(pickSystem) key:@""];
    self.lightItem = [self item:@"Light" action:@selector(pickLight) key:@""];
    self.darkItem = [self item:@"Dark" action:@selector(pickDark) key:@""];
    for (NSMenuItem *item in @[self.greyItem, self.blackItem, self.glassItem, NSMenuItem.separatorItem, self.systemItem,
                               self.lightItem, self.darkItem])
        [look addItem:item];
    self.lookItem = [self item:@"Look" action:nil key:@""];
    self.lookItem.submenu = look;
    self.entries = [@[[MenuEntry entryIn:MenuSectionWhozmove order:10 item:self.showBuildItem]] mutableCopy];
    NSMenu *menu = [NSMenu new];
    menu.delegate = self;
    self.statusItem.menu = menu;
    [self layOut];
    [self applySavedLook];
    NSNotificationCenter *workspace = NSWorkspace.sharedWorkspace.notificationCenter;
    [workspace addObserver:self selector:@selector(applySavedLook)
                      name:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification object:nil];
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

// The menu, from the top: the top section (with a line under it), the panel's own items and its look, the grouping,
// the features, Working on Whozmove (shown only while ⌥ is held: menuNeedsUpdate:) and Quit. Each section's items, its
// own and the modules', in their order there.
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
    put(self.lookItem, menu);
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
// opens. The Look menu's Black says White if the Mac has turned light since.
- (void)menuNeedsUpdate:(NSMenu *)menu {
    if (menu != self.statusItem.menu) return;
    [self nameLook];
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

// The panel's look, from the Look menu: grey, black or glass, and light, dark or as the Mac is.
- (void)pickBlack { [self save:@"black" as:kPanelLook]; }

- (void)pickGrey { [self save:@"grey" as:kPanelLook]; }

- (void)pickGlass { [self save:@"glass" as:kPanelLook]; }

- (void)pickSystem { [self save:@"system" as:kAppearance]; }

- (void)pickLight { [self save:@"light" as:kAppearance]; }

- (void)pickDark { [self save:@"dark" as:kAppearance]; }

- (void)save:(NSString *)choice as:(NSString *)key {
    [NSUserDefaults.standardUserDefaults setObject:choice forKey:key];
    [self applySavedLook];
}

// The look last picked, on the panel and the app's other windows (the page's colours follow, panel/styles/tokens.css),
// and ticked in the menu; asked again when macOS's display settings change, for Reduce Transparency.
- (void)applySavedLook {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    BOOL plain = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceTransparency;
    NSString *look = self.look;
    self.window.look = look;
    self.blackItem.state = [look isEqual:@"black"] ? NSControlStateValueOn : NSControlStateValueOff;
    self.greyItem.state = [look isEqual:@"grey"] ? NSControlStateValueOn : NSControlStateValueOff;
    self.glassItem.state = [look isEqual:@"glass"] ? NSControlStateValueOn : NSControlStateValueOff;
    self.glassItem.enabled = !plain;
    self.glassItem.toolTip = plain ? @"Off while Reduce Transparency is on in System Settings" : nil;
    NSString *appearance = [defaults stringForKey:kAppearance];
    if (![appearance isEqual:@"light"] && ![appearance isEqual:@"dark"]) appearance = @"system";
    NSApp.appearance = [appearance isEqual:@"light"] ? [NSAppearance appearanceNamed:NSAppearanceNameAqua]
                     : [appearance isEqual:@"dark"] ? [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua] : nil;
    self.systemItem.state = [appearance isEqual:@"system"] ? NSControlStateValueOn : NSControlStateValueOff;
    self.lightItem.state = [appearance isEqual:@"light"] ? NSControlStateValueOn : NSControlStateValueOff;
    self.darkItem.state = [appearance isEqual:@"dark"] ? NSControlStateValueOn : NSControlStateValueOff;
    [self nameLook];
    [self applySavedSwitches];
}

// The panel's look as it is: the one picked (grey until another is), and grey for Glass while Reduce Transparency is
// on.
- (NSString *)look {
    NSString *look = [NSUserDefaults.standardUserDefaults stringForKey:kPanelLook];
    if (![look isEqual:@"black"] && ![look isEqual:@"glass"]) look = @"grey";
    if ([look isEqual:@"glass"] && NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceTransparency)
        look = @"grey";
    return look;
}

// Black is white on the light panel, and the menu says which, as the app looks now.
- (void)nameLook {
    self.blackItem.title = IsDark(NSApp.effectiveAppearance) ? @"Black" : @"White";
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
                             @"build": @(SwitchedOn(kShowBuild)), @"look": self.look}];
}

@end
