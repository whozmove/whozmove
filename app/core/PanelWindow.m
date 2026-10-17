// PanelWindow: the floating glass window, its drag strip, its size, and the pointer over it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "PanelWindow.h"
#import "Page.h"
#import <QuartzCore/QuartzCore.h>

// The panel's width; its header's height (--header in panel/styles/tokens.css) and the buttons at the header's right
// end, which the drag strip leaves to the page; and the most the panel grows to.
static const CGFloat kWidth = 340, kHeaderHeight = 46, kButtonsWidth = 72, kMaxHeight = 640;
// The reader's ✕, at its header's right end (.r-close in panel/styles/reader.css, with the header's padding), which
// the reader's drag strip leaves to the page.
static const CGFloat kCloseWidth = 46;
// The page is never laid out at another width: a change of width has WebKit lay it all out and draw it again, which
// shows as the whole panel flashing. So it's as wide as the list with room for the widest reader on either side of
// it (--side in panel/styles/tokens.css), always, and the window shows the part in use: the list, and the reader
// beside it while it's open. The page's left edge stays this far left of the list's.
static const CGFloat kReaderRoom = 1254, kPageWidth = kWidth + 2 * kReaderRoom;

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
@property (copy) BOOL (^mayDrag)(void);           // not while the panel changes size
@property (copy) void (^onShift)(NSPoint by);     // each step of a drag: how far the panel really moved
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
    if (self.mayDrag && !self.mayDrag()) return;
    _dragged = YES;
    NSRect was = self.window.frame, frame = was;
    frame.origin.x += now.x - _start.x;
    frame.origin.y += now.y - _start.y;
    [self.window setFrame:frame display:YES];
    _start = now;
    // By where the window is now, not by how far the pointer went: macOS rounds a window's place to whole pixels and
    // keeps it below the menu bar, so the pointer's moves added up would drift from it over a long drag.
    NSRect is = self.window.frame;
    if (self.onShift) self.onShift(NSMakePoint(NSMinX(is) - NSMinX(was), NSMinY(is) - NSMinY(was)));
}
- (void)mouseUp:(NSEvent *)event {
    if (!_dragged && self.onClick) self.onClick();
    // Not while the reader is open, which turns the name off: that size isn't the one to come back at.
    if (_dragged && self.window.frameAutosaveName.length)
        [self.window saveFrameUsingName:self.window.frameAutosaveName];
    if (_dragged && self.onMoved) self.onMoved();
}
@end

@interface PanelWindow ()
@property (strong) Page *page;
@property (strong) FloatingPanel *panel;
@property (strong) DragStrip *strip;
@property (strong) DragStrip *readerStrip;  // over the reader's header, while it's open
@property (assign) CGFloat room;        // how tall the panel can grow where it is (see updateRoom)
@property (strong) NSTimer *pointerTimer;
@property (assign) BOOL hovering;       // the pointer is over the panel
@property (assign) NSPoint lastHover;   // the last position sent to the page
@property (assign) BOOL expanded;       // grown to the screen for the reader
@property (assign) NSRect listFrame;    // where the panel was before it grew, to fold back to
@property (assign) BOOL listOnRight;    // the reader opened to the list's left
// The panel's shape, apart from the window's: the glass and the page's clip (rounded, over it) normally fill the
// window, and while the panel changes size they show only part of it (reshapeTo:).
@property (strong) NSVisualEffectView *glass;
@property (strong) NSView *clip;
@property (assign) BOOL reshaping;
@property (assign) BOOL hasPending;     // a size asked for while the panel was changing size, taken next
@property (assign) NSRect pendingFrame;
@property (copy) void (^pendingDone)(void);
@property (strong) NSTimer *shadowTimer;
// Who follows the glass and the pointer (followGlass:, followPointer:).
@property (strong) NSMutableArray *glassObservers, *pointerObservers;
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
    self.glassObservers = [NSMutableArray array];
    self.pointerObservers = [NSMutableArray array];
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

    // The glass, and over it the page in a clip of the same shape. They're apart so that the panel can change size by
    // moving their edges alone (reshapeTo:), without the page being drawn again on the way.
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kWidth, frame.size.height)];
    root.wantsLayer = YES;
    self.panel.contentView = root;
    NSVisualEffectView *glass = [[NSVisualEffectView alloc] initWithFrame:root.bounds];
    glass.material = NSVisualEffectMaterialHUDWindow;
    glass.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    glass.state = NSVisualEffectStateActive;
    glass.maskImage = RoundedMask(12);
    glass.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [root addSubview:glass];
    self.glass = glass;
    NSView *clip = [[NSView alloc] initWithFrame:root.bounds];
    clip.wantsLayer = YES;
    clip.layer.masksToBounds = YES;
    clip.layer.cornerRadius = 12;
    clip.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [root addSubview:clip];
    self.clip = clip;

    // The tint over the glass is the window's, under the page (whose own background is clear, panel/styles/base.css):
    // as the panel grows, the page paints the new space at its bottom a frame or two late, and until then bare glass
    // would show there, lighter, like a flicker. Rounded itself, as the glass's mask doesn't reach its subviews; it
    // follows the glass's edges as they move (reshapeTo:).
    NSView *tint = [[NSView alloc] initWithFrame:glass.bounds];
    tint.wantsLayer = YES;
    tint.layer.backgroundColor = [NSColor colorWithSRGBRed:16 / 255.0 green:16 / 255.0 blue:18 / 255.0
                                                     alpha:0.55].CGColor;
    tint.layer.cornerRadius = 12;
    tint.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [glass addSubview:tint];

    // The clip rounds the page with the panel's corners, so what it draws up to its edges (the usage strip's vine, the
    // collapsed header's line) meets them.
    page.view.frame = NSMakeRect(-kReaderRoom, 0, kPageWidth, NSHeight(clip.bounds));
    page.view.autoresizingMask = NSViewHeightSizable;
    [clip addSubview:page.view];

    // The panel is dragged by its header's empty parts: the list's, and the reader's while it's open. A plain click on
    // the list's folds the list, but not while the reader is open beside it.
    __weak typeof(self) weakSelf = self;
    DragStrip *strip = [[DragStrip alloc]
        initWithFrame:NSMakeRect(0, frame.size.height - kHeaderHeight, kWidth - kButtonsWidth, kHeaderHeight)];
    strip.autoresizingMask = NSViewMinYMargin | NSViewWidthSizable;
    strip.onClick = ^{ if (!weakSelf.expanded) [weakSelf.page toggleCollapsed]; };
    DragStrip *readerStrip = [[DragStrip alloc] initWithFrame:NSZeroRect];
    readerStrip.autoresizingMask = NSViewMinYMargin;
    readerStrip.hidden = YES;
    for (DragStrip *each in @[strip, readerStrip]) {
        each.onMoved = ^{ [weakSelf updateRoom]; };
        each.mayDrag = ^BOOL { return !weakSelf.reshaping; };
        // While the reader is open, the list moves with the panel, and folds back to where it is then.
        each.onShift = ^(NSPoint by) {
            if (weakSelf.expanded) weakSelf.listFrame = NSOffsetRect(weakSelf.listFrame, by.x, by.y);
            [weakSelf tellGlass:weakSelf.panel.frame over:0];
        };
    }
    [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidChangeScreenParametersNotification object:nil
                                                     queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification *note) {
        [weakSelf updateRoom];
        if (!weakSelf.reshaping) [weakSelf tellGlass:weakSelf.panel.frame over:0];
    }];
    [root addSubview:strip];
    [root addSubview:readerStrip];
    self.strip = strip;
    self.readerStrip = readerStrip;

    self.pointerTimer = [NSTimer scheduledTimerWithTimeInterval:0.04 target:self selector:@selector(pollPointer)
                                                       userInfo:nil repeats:YES];
    self.pointerTimer.tolerance = 0.01;
    return self;
}

// It fades in, so that after a deploy, when the app restarts on the new build, the panel comes back softly where it
// was rather than popping up.
- (void)show {
    [self.panel setFrameUsingName:@"Whozmove"];
    self.panel.alphaValue = 0;
    [self.panel orderFrontRegardless];
    [self tellGlass:self.panel.frame over:0];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion ? 0 : 0.2;
        self.panel.animator.alphaValue = 1;
    }];
}

- (void)setHeaderTip:(NSString *)tip {
    self.strip.toolTip = tip;
}

- (NSString *)headerTip {
    return self.strip.toolTip;
}

// What the panel holds under itself (Spotify's token) goes and comes back with it: macOS does that for a window's
// children, as long as they're left attached.
- (void)toggle {
    if (self.panel.isVisible) [self.panel orderOut:nil];
    else [self.panel orderFrontRegardless];
}

- (BOOL)shown {
    return self.panel.isVisible;
}

- (void)bringUp {
    if (!self.panel.isVisible) [self.panel orderFrontRegardless];
}

- (void)resetPosition {
    NSRect screen = NSScreen.mainScreen.visibleFrame;
    NSRect frame = self.panel.frame;
    frame.origin = NSMakePoint(NSMaxX(screen) - frame.size.width - 16, NSMaxY(screen) - frame.size.height - 16);
    [self.panel setFrame:frame display:YES];
    [self.panel saveFrameUsingName:@"Whozmove"];
    [self.panel orderFrontRegardless];
    [self updateRoom];
    [self tellGlass:self.panel.frame over:0];
}

#pragma mark Size

// How tall the panel can grow from where its top edge is: down to the bottom of the screen, and no more
// than kMaxHeight. The page caps itself to that (its list scrolls), so the panel never runs off the screen.
- (void)updateRoom {
    if (self.expanded) return;
    CGFloat room = [self roomFor:self.panel.frame];
    if (room == self.room || !self.page.ready) return;
    self.room = room;
    [self.page setRoom:room];
}

- (CGFloat)roomFor:(NSRect)frame {
    NSRect screen = (self.panel.screen ?: NSScreen.mainScreen).visibleFrame;
    return floor(MAX(kHeaderHeight + 80, MIN(kMaxHeight, NSMaxY(frame) - NSMinY(screen))));
}

- (void)resendRoom {
    self.room = 0;
    [self updateRoom];
}

- (void)fitHeight:(CGFloat)height {
    if (self.expanded || self.reshaping) return;
    height = MIN(height, self.room ?: kMaxHeight);
    NSRect frame = self.panel.frame;
    if (fabs(frame.size.height - height) < 1) return;
    frame.origin.y += frame.size.height - height;  // keep the top edge where the user put it
    frame.size.height = height;
    [self.panel setFrame:frame display:YES animate:NO];
    [self tellGlass:frame over:0];
}

- (void)attachBelow:(NSWindow *)window {
    [self.panel addChildWindow:window ordered:NSWindowBelow];
}

// Where the glass is, for what's held under the panel: the list is where the panel is, or, while the reader is open,
// where it was.
- (void)followGlass:(void (^)(NSRect, NSRect, NSRect, NSTimeInterval))observer {
    [self.glassObservers addObject:observer];
}

- (void)followPointer:(void (^)(NSPoint))observer {
    [self.pointerObservers addObject:observer];
}

- (void)tellGlass:(NSRect)glass over:(NSTimeInterval)duration {
    NSScreen *screen = self.panel.screen ?: NSScreen.mainScreen;
    for (void (^observer)(NSRect, NSRect, NSRect, NSTimeInterval) in self.glassObservers)
        observer(glass, self.expanded ? self.listFrame : glass, screen.visibleFrame, duration);
}

#pragma mark The reader

// The reader opens beside the list, which stays where it was: the panel grows towards the side with more room, so a
// panel at the right grows leftwards with its list on the right, and one at the left the other way, and downwards
// from its top edge. It grows only as far as what the reader shows needs, and no further than the screen allows
// (16pt from its edges; a longer page scrolls). The page is told which side its list is on, and how wide the reader
// is, before the panel starts to grow, so what's in it is laid out once at that size and the growing only uncovers it.
- (void)expandReader:(CGFloat)width height:(CGFloat)height {
    NSScreen *screen = self.panel.screen ?: NSScreen.mainScreen;
    NSRect visible = NSInsetRect(screen.visibleFrame, 16, 16);
    if (!self.expanded) {
        self.expanded = YES;
        self.listFrame = self.panel.frame;
        // The grown size mustn't be what the panel comes back at next launch.
        self.panel.frameAutosaveName = @"";
        NSRect list = self.listFrame;
        self.listOnRight = NSMinX(list) - NSMinX(visible) >= NSMaxX(visible) - NSMaxX(list);
    }
    NSRect list = self.listFrame;
    CGFloat room = self.listOnRight ? NSMinX(list) - NSMinX(visible) : NSMaxX(visible) - NSMaxX(list);
    CGFloat readerWidth = floor(MAX(0, MIN(MIN(width, room), kReaderRoom)));
    CGFloat top = NSMaxY(list), tall = floor(MAX(NSHeight(list), MIN(height, top - NSMinY(visible))));
    NSRect frame = NSMakeRect(self.listOnRight ? NSMinX(list) - readerWidth : NSMinX(list), top - tall,
                              NSWidth(list) + readerWidth, tall);
    [self.page readerOpened:self.listOnRight ? @"right" : @"left" width:readerWidth];
    [self reshapeTo:frame done:nil];
}

// Back to where the list was (or was dragged to with the panel), at the height the list needs now (it may have changed
// while the reader was open), so nothing is resized again once the panel has folded.
- (void)collapse:(CGFloat)height {
    // Closed before it grew (pressed again before what it shows was in): there's nothing to fold, but the page still
    // waits to hear that the reader has closed.
    if (!self.expanded) {
        [self.page readerClosed];
        return;
    }
    __weak typeof(self) weakSelf = self;
    NSRect list = self.listFrame;
    if (height > 0) {
        CGFloat tall = floor(MAX(kHeaderHeight, MIN(height, [self roomFor:list])));
        list = NSMakeRect(NSMinX(list), NSMaxY(list) - tall, NSWidth(list), tall);
    }
    [self reshapeTo:list done:^{
        weakSelf.expanded = NO;
        // Saved first, where it has folded to: given its name back, the window also moves to what's saved under it,
        // which would otherwise be where it was before the reader opened, not where it was dragged since.
        [weakSelf.panel saveFrameUsingName:@"Whozmove"];
        weakSelf.panel.frameAutosaveName = @"Whozmove";
        [weakSelf placeStrips];
        [weakSelf.page readerClosed];
        [weakSelf resendRoom];
    }];
}

// Changing the window's size every frame would have the page drawn again every frame, a frame or two behind, in tiles:
// the edge would fill in block by block. So the window takes in, at once, everything the panel covers on the way
// (from where it is to where it goes), and only the panel's edges move: the glass and the page's clip, eased out over
// about half a second, while the page stays still beneath them, drawn once. Where the panel ends up smaller, the window
// is made that size once the edges are there. Asked again on the way, the newest size is taken once this one is done.
- (void)reshapeTo:(NSRect)target done:(void (^)(void))done {
    if (self.reshaping) {
        void (^earlier)(void) = self.pendingDone;
        self.pendingFrame = target;
        self.hasPending = YES;
        self.pendingDone = ^{ if (earlier) earlier(); if (done) done(); };
        return;
    }
    NSRect from = self.panel.frame;
    if (NSEqualRects(from, target)) {
        if (done) done();
        return;
    }
    self.reshaping = YES;
    // Nothing to drag by on the way: the headers move under them (settle puts them back).
    self.strip.hidden = self.readerStrip.hidden = YES;
    NSRect span = NSUnionRect(from, target);
    __weak typeof(self) weakSelf = self;
    void (^finish)(void) = ^{
        [weakSelf settle];
        if (done) done();
        if (weakSelf.hasPending) {
            weakSelf.hasPending = NO;
            void (^next)(void) = weakSelf.pendingDone;
            weakSelf.pendingDone = nil;
            [weakSelf reshapeTo:weakSelf.pendingFrame done:next];
        }
    };
    void (^move)(void) = ^{
        [weakSelf moveEdgesTo:target then:^{
            if (NSEqualRects(span, target)) finish();
            else [weakSelf setWindowFrame:target showing:target then:finish];
        }];
    };
    if (NSEqualRects(span, from)) move();
    else [self setWindowFrame:span showing:from then:move];
}

// Where the page's left edge is on the screen: kReaderRoom left of the list, which stays put while the reader is open.
- (CGFloat)pageLeft {
    return (self.expanded ? NSMinX(self.listFrame) : NSMinX(self.panel.frame)) - kReaderRoom;
}

// Where a rectangle on the screen is in the window.
- (NSRect)inWindow:(NSRect)onScreen {
    return NSOffsetRect(onScreen, -NSMinX(self.panel.frame), -NSMinY(self.panel.frame));
}

// Shows exactly `shown` (on the screen) of a window that's now `frame`. The page is moved within its clip so that it
// stays where it is on the screen, and is laid out again at the window's new size; WebKit shows that new layout in
// step with the window's change of size. What comes next waits until the page has drawn it. (A picture of the panel
// held over it meanwhile showed as a pale flash: WebKit's pictures have a white ground under the panel's tint.)
- (void)setWindowFrame:(NSRect)frame showing:(NSRect)shown then:(void (^)(void))then {
    NSView *root = self.panel.contentView;
    root.autoresizesSubviews = NO;
    self.clip.autoresizesSubviews = NO;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self.panel setFrame:frame display:NO];
    NSRect local = [self inWindow:shown];
    self.glass.frame = local;
    self.clip.frame = local;
    self.page.view.frame = NSMakeRect([self pageLeft] - NSMinX(frame) - NSMinX(local), -NSMinY(local), kPageWidth,
                                      NSHeight(frame));
    [CATransaction commit];
    [self.panel invalidateShadow];
    [self tellGlass:shown over:0];
    [self.page afterPaint:then];
}

// The glass and the page's clip move to `target` (on the screen) within the window, the page staying put; the
// window's shadow follows them.
- (void)moveEdgesTo:(NSRect)target then:(void (^)(void))then {
    NSRect local = [self inWindow:target];
    NSView *root = self.panel.contentView;
    root.autoresizesSubviews = NO;
    self.clip.autoresizesSubviews = NO;
    __weak FloatingPanel *panel = self.panel;
    [self tellGlass:target over:NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion ? 0 : 0.5];
    self.shadowTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60 repeats:YES
                                                         block:^(NSTimer *timer) { [panel invalidateShadow]; }];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion ? 0 : 0.5;
        context.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.2 :0.8 :0.2 :1];
        self.glass.animator.frame = local;
        self.clip.animator.frame = local;
        [self.page.view.animator setFrameOrigin:NSMakePoint([self pageLeft] - NSMinX(self.panel.frame) - NSMinX(local),
                                                             -NSMinY(local))];
    } completionHandler:^{
        [self.shadowTimer invalidate];
        self.shadowTimer = nil;
        then();
    }];
}

// Done changing size: the glass, the clip and the page fill the window again, and follow it as before.
- (void)settle {
    NSView *root = self.panel.contentView;
    self.glass.frame = root.bounds;
    self.clip.frame = root.bounds;
    self.page.view.frame = NSMakeRect([self pageLeft] - NSMinX(self.panel.frame), 0, kPageWidth,
                                      NSHeight(self.clip.bounds));
    [self placeStrips];
    root.autoresizesSubviews = YES;
    self.clip.autoresizesSubviews = YES;
    self.reshaping = NO;
    [self.panel invalidateShadow];
    [self tellGlass:self.panel.frame over:0];
}

// The drag strips over the headers' empty parts: the list's, up to its buttons; and while the reader is open, the
// reader's, up to its ✕.
- (void)placeStrips {
    NSRect bounds = self.panel.contentView.bounds;
    CGFloat top = NSHeight(bounds) - kHeaderHeight;
    if (!self.expanded) {
        self.strip.frame = NSMakeRect(0, top, NSWidth(bounds) - kButtonsWidth, kHeaderHeight);
        self.strip.hidden = NO;
        self.readerStrip.hidden = YES;
        return;
    }
    CGFloat listLeft = NSMinX(self.listFrame) - NSMinX(self.panel.frame), readerWidth = NSWidth(bounds) - kWidth;
    self.strip.frame = NSMakeRect(listLeft, top, kWidth - kButtonsWidth, kHeaderHeight);
    CGFloat readerLeft = self.listOnRight ? 0 : listLeft + kWidth;
    self.readerStrip.frame = NSMakeRect(readerLeft, top, MAX(0, readerWidth - kCloseWidth), kHeaderHeight);
    self.strip.hidden = NO;
    self.readerStrip.hidden = readerWidth <= kCloseWidth;
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
    NSPoint at = NSMakePoint(point.x + [self pageLeft] - NSMinX(self.panel.frame), NSHeight(view.bounds) - point.y);
    [menu popUpMenuPositioningItem:nil atLocation:at inView:view];
}

#pragma mark Hover

// Hover follows the pointer's position, polled, not mouse events: the panel is almost never the key window of an
// active app, so WebKit gets no mouse moves, and macOS delivers mouseMoved: to such windows unreliably (often
// only entered and exited). Polling sees every position either way.
- (void)pollPointer {
    NSPoint screen = NSEvent.mouseLocation;
    if (self.panel.isVisible)
        for (void (^observer)(NSPoint) in self.pointerObservers) observer(screen);
    NSRect frame = self.panel.frame;
    BOOL inside = self.panel.isVisible && NSPointInRect(screen, frame);
    if (!inside) {
        if (self.hovering) {
            self.hovering = NO;
            [self.page hoverEnd];
        }
        return;
    }
    // The page's top is the panel's, and its left edge pageLeft.
    NSPoint page = NSMakePoint(round(screen.x - [self pageLeft]), round(NSMaxY(frame) - screen.y));
    if (self.hovering && NSEqualPoints(page, self.lastHover)) return;
    self.hovering = YES;
    self.lastHover = page;
    [self.page hoverAt:page];
}

@end
