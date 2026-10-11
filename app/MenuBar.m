// MenuBar: the pawn in the menu bar, its count, and the grouping menu.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "MenuBar.h"
#import "PanelWindow.h"
#import "Page.h"

@interface MenuBar ()
@property (strong) Page *page;
@property (strong) NSStatusItem *statusItem;
@property (strong) NSMenuItem *groupByStatusItem;
@property (strong) NSMenuItem *groupByActivityItem;
@property (strong) NSMenuItem *groupByProjectItem;
@end

@implementation MenuBar

- (instancetype)initWithWindow:(PanelWindow *)window page:(Page *)page {
    if (!(self = [super init])) return nil;
    self.page = page;
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    // The Whozmove pawn ("your move"), drawn as a template image so it follows the menu bar's light/dark
    // tint. Same shape as the app icon (PawnPath in make-icon.m) and the panel's header mark; keep the three
    // in step. One path, so it fills as one shape with no seams where its parts meet; the body runs the same
    // way round as the oval and rounded rectangles, or the overlaps would cancel out.
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
    NSMenu *menu = [NSMenu new];
    [menu addItemWithTitle:@"Show / Hide Panel" action:@selector(toggle) keyEquivalent:@""].target = window;
    [menu addItemWithTitle:@"Reset Position" action:@selector(resetPosition) keyEquivalent:@""].target = window;
    [menu addItem:NSMenuItem.separatorItem];
    self.groupByStatusItem = [menu addItemWithTitle:@"Group by Status" action:@selector(groupByStatus)
                                      keyEquivalent:@""];
    self.groupByStatusItem.target = self;
    self.groupByActivityItem = [menu addItemWithTitle:@"Group by Activity" action:@selector(groupByActivity)
                                        keyEquivalent:@""];
    self.groupByActivityItem.target = self;
    self.groupByProjectItem = [menu addItemWithTitle:@"Group by Project" action:@selector(groupByProject)
                                       keyEquivalent:@""];
    self.groupByProjectItem.target = self;
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItemWithTitle:@"Quit Whozmove" action:@selector(terminate:) keyEquivalent:@"q"].target = NSApp;
    self.statusItem.menu = menu;
    return self;
}

- (void)showCount:(NSInteger)count {
    self.statusItem.button.title = count > 0 ? [NSString stringWithFormat:@" %ld", (long)count] : @"";
}

// The panel's grouping, chosen from this menu: Status (Needs you, Working, Your turn, Idle), Activity (the same
// sections, but a session stays under Your turn until it has been quiet for an hour, read or not) or Project.
- (void)groupByStatus { [self applyGroupBy:@"status"]; }

- (void)groupByProject { [self applyGroupBy:@"project"]; }

- (void)groupByActivity { [self applyGroupBy:@"activity"]; }

- (void)applySavedGrouping {
    [self applyGroupBy:[NSUserDefaults.standardUserDefaults stringForKey:@"groupBy"]];
}

- (void)applyGroupBy:(NSString *)mode {
    if (![@[@"project", @"activity"] containsObject:mode]) mode = @"status";
    [NSUserDefaults.standardUserDefaults setObject:mode forKey:@"groupBy"];
    [self.page setGroupBy:mode];
    self.groupByStatusItem.state = [mode isEqual:@"status"] ? NSControlStateValueOn : NSControlStateValueOff;
    self.groupByProjectItem.state = [mode isEqual:@"project"] ? NSControlStateValueOn : NSControlStateValueOff;
    self.groupByActivityItem.state = [mode isEqual:@"activity"] ? NSControlStateValueOn : NSControlStateValueOff;
}

@end
