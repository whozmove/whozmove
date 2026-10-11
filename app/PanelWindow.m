// PanelWindow: the floating glass window, its drag strip, its size, and the pointer over it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "PanelWindow.h"
#import "Page.h"

// The panel's width; its header's height (--header in panel/styles/base.css) and the buttons at the header's right
// end, which the drag strip leaves to the page; and the most the panel grows to.
static const CGFloat kWidth = 340, kHeaderHeight = 46, kButtonsWidth = 64, kMaxHeight = 640;

// Clicking the panel doesn't take the keyboard from the app being typed in (a click on a row, say, leaves it with
// Claude's message box): the panel becomes the key window only while one of its own text boxes is being typed in
// (wantsKeyboard, set by the page).
@interface FloatingPanel : NSPanel
@property (assign) BOOL wantsKeyboard;
@end

@implementation FloatingPanel
- (BOOL)canBecomeKeyWindow { return self.wantsKeyboard; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

// Transparent strip over the header: drag moves the panel, a plain click is handed to the page.
@interface DragStrip : NSView
@property (copy) void (^onClick)(void);
@property (copy) void (^onMoved)(void);
@end

@implementation DragStrip {
    NSPoint _start;
    BOOL _dragged;
}
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (void)mouseDown:(NSEvent *)event {
    _start = [NSEvent mouseLocation];
    _dragged = NO;
}
- (void)mouseDragged:(NSEvent *)event {
    NSPoint now = [NSEvent mouseLocation];
    if (!_dragged && hypot(now.x - _start.x, now.y - _start.y) < 3) return;
    _dragged = YES;
    NSRect frame = self.window.frame;
    frame.origin.x += now.x - _start.x;
    frame.origin.y += now.y - _start.y;
    [self.window setFrame:frame display:YES];
    _start = now;
}
- (void)mouseUp:(NSEvent *)event {
    if (!_dragged && self.onClick) self.onClick();
    if (_dragged) [self.window saveFrameUsingName:self.window.frameAutosaveName];
    if (_dragged && self.onMoved) self.onMoved();
}
@end

@interface PanelWindow ()
@property (strong) Page *page;
@property (strong) FloatingPanel *panel;
@property (assign) CGFloat room;        // how tall the panel can grow where it is (see updateRoom)
@property (strong) NSTimer *pointerTimer;
@property (assign) BOOL hovering;       // the pointer is over the panel
@property (assign) NSPoint lastHover;   // the last position sent to the page
@end

// The glass's rounded corners, as a mask that stretches to any size.
static NSImage *RoundedMask(CGFloat radius) {
    CGFloat edge = radius * 2 + 1;
    NSImage *mask = [NSImage imageWithSize:NSMakeSize(edge, edge) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [NSColor.blackColor set];
        [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius] fill];
        return YES;
    }];
    mask.capInsets = NSEdgeInsetsMake(radius, radius, radius, radius);
    mask.resizingMode = NSImageResizingModeStretch;
    return mask;
}

@implementation PanelWindow

- (instancetype)initWithPage:(Page *)page {
    if (!(self = [super init])) return nil;
    self.page = page;
    NSRect screen = NSScreen.mainScreen.visibleFrame;
    NSRect frame = NSMakeRect(NSMaxX(screen) - kWidth - 16, NSMaxY(screen) - 200 - 16, kWidth, 200);
    self.panel = [[FloatingPanel alloc] initWithContentRect:frame
                                                  styleMask:NSWindowStyleMaskBorderless
                                                            | NSWindowStyleMaskNonactivatingPanel
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    self.panel.level = NSFloatingWindowLevel;
    self.panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces
                                    | NSWindowCollectionBehaviorFullScreenAuxiliary;
    self.panel.hidesOnDeactivate = NO;
    self.panel.opaque = NO;
    self.panel.backgroundColor = NSColor.clearColor;
    self.panel.hasShadow = YES;
    // The page is styled for dark glass.
    self.panel.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
    self.panel.frameAutosaveName = @"Whozmove";

    NSVisualEffectView *glass = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, kWidth, frame.size.height)];
    glass.material = NSVisualEffectMaterialHUDWindow;
    glass.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    glass.state = NSVisualEffectStateActive;
    glass.maskImage = RoundedMask(12);
    glass.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.panel.contentView = glass;

    page.view.frame = glass.bounds;
    page.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [glass addSubview:page.view];

    DragStrip *strip = [[DragStrip alloc]
        initWithFrame:NSMakeRect(0, frame.size.height - kHeaderHeight, kWidth - kButtonsWidth, kHeaderHeight)];
    strip.autoresizingMask = NSViewMinYMargin | NSViewWidthSizable;
    __weak typeof(self) weakSelf = self;
    strip.onClick = ^{ [weakSelf.page toggleCollapsed]; };
    strip.onMoved = ^{ [weakSelf updateRoom]; };
    [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidChangeScreenParametersNotification object:nil
                                                     queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification *note) { [weakSelf updateRoom]; }];
    [glass addSubview:strip];

    self.pointerTimer = [NSTimer scheduledTimerWithTimeInterval:0.04 target:self selector:@selector(pollPointer)
                                                       userInfo:nil repeats:YES];
    self.pointerTimer.tolerance = 0.01;
    return self;
}

- (void)show {
    [self.panel setFrameUsingName:@"Whozmove"];
    [self.panel orderFrontRegardless];
}

- (void)toggle {
    if (self.panel.isVisible) [self.panel orderOut:nil];
    else [self.panel orderFrontRegardless];
}

- (void)resetPosition {
    NSRect screen = NSScreen.mainScreen.visibleFrame;
    NSRect frame = self.panel.frame;
    frame.origin = NSMakePoint(NSMaxX(screen) - frame.size.width - 16, NSMaxY(screen) - frame.size.height - 16);
    [self.panel setFrame:frame display:YES];
    [self.panel saveFrameUsingName:@"Whozmove"];
    [self.panel orderFrontRegardless];
    [self updateRoom];
}

#pragma mark Size

// How tall the panel can grow from where its top edge is: down to the bottom of the screen, and no more
// than kMaxHeight. The page caps itself to that (its list scrolls), so the panel never runs off the screen.
- (void)updateRoom {
    NSRect frame = self.panel.frame, screen = (self.panel.screen ?: NSScreen.mainScreen).visibleFrame;
    CGFloat room = floor(MAX(kHeaderHeight + 80, MIN(kMaxHeight, NSMaxY(frame) - NSMinY(screen))));
    if (room == self.room || !self.page.ready) return;
    self.room = room;
    [self.page setRoom:room];
}

- (void)resendRoom {
    self.room = 0;
    [self updateRoom];
}

- (void)fitHeight:(CGFloat)height {
    height = MIN(height, self.room ?: kMaxHeight);
    NSRect frame = self.panel.frame;
    if (fabs(frame.size.height - height) < 1) return;
    frame.origin.y += frame.size.height - height;  // keep the top edge where the user put it
    frame.size.height = height;
    [self.panel setFrame:frame display:YES animate:NO];
}

#pragma mark Keyboard

- (void)takeKeyboard:(BOOL)on {
    if (on == self.panel.wantsKeyboard) return;
    self.panel.wantsKeyboard = on;
    if (on) [self.panel makeKeyWindow];
    else if (self.panel.isKeyWindow)  // the keyboard goes back to the app it came from
        [NSWorkspace.sharedWorkspace.frontmostApplication activateWithOptions:0];
}

- (BOOL)releaseKeyboard {
    if (!self.panel.isKeyWindow) return NO;
    self.panel.wantsKeyboard = NO;
    return YES;
}

- (void)popUpMenu:(NSMenu *)menu atPagePoint:(NSPoint)point {
    NSView *view = self.panel.contentView;  // not flipped; the page's y runs down from the top
    NSPoint at = NSMakePoint(point.x, NSHeight(view.bounds) - point.y);
    [menu popUpMenuPositioningItem:nil atLocation:at inView:view];
}

#pragma mark Hover

// Hover follows the pointer's position, polled, not mouse events: the panel is almost never the key window of an
// active app, so WebKit gets no mouse moves, and macOS delivers mouseMoved: to such windows unreliably (often
// only entered and exited). Polling sees every position either way.
- (void)pollPointer {
    NSPoint screen = NSEvent.mouseLocation;
    NSRect frame = self.panel.frame;
    BOOL inside = self.panel.isVisible && NSPointInRect(screen, frame);
    if (!inside) {
        if (self.hovering) {
            self.hovering = NO;
            [self.page hoverEnd];
        }
        return;
    }
    // The page fills the borderless panel, so page coordinates are offsets from its top-left corner.
    NSPoint page = NSMakePoint(round(screen.x - NSMinX(frame)), round(NSMaxY(frame) - screen.y));
    if (self.hovering && NSEqualPoints(page, self.lastHover)) return;
    self.hovering = YES;
    self.lastHover = page;
    [self.page hoverAt:page];
}

@end
