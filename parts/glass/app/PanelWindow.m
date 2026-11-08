// PanelWindow: the floating glass window, its drag strip, its size, and the page in it; its other parts are
// categories of it, each in a file of its own (PanelWindow+<Part>.m).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "PanelWindow+Private.h"
static void LetPointerShapesIn(void);

// The most the header and the list take together, on any screen with that much room under the menu bar (ListLimitFor);
// and the gap kept above the screen's bottom under what hangs below the panel (RoomFor).
static const CGFloat kListMost = 640, kBelowGap = 16;

@implementation FloatingPanel
- (BOOL)canBecomeKeyWindow { return self.wantsKeyboard; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

@implementation DragStrip {
    NSPoint _start;
    BOOL _dragged, _tried;
}
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (void)mouseDown:(NSEvent *)event {
    _start = [NSEvent mouseLocation];
    _dragged = _tried = NO;
    if (self.onPress) self.onPress(YES);
}
- (void)mouseDragged:(NSEvent *)event {
    NSPoint now = [NSEvent mouseLocation];
    if (!_dragged && hypot(now.x - _start.x, now.y - _start.y) < 3) return;
    _tried = YES;
    if (!self.onDrag(NSMakePoint(now.x - _start.x, now.y - _start.y))) return;
    _dragged = YES;
    _start = now;
}
// A press that moved far enough to be a drag is one, even where the panel couldn't move yet (the folded cat's chats
// going in first): it never counts as a click.
- (void)mouseUp:(NSEvent *)event {
    if (self.onPress) self.onPress(NO);
    if (_tried) self.onDragged();
    else if (self.onClick) self.onClick();
}
@end

@implementation SideView
- (NSView *)hitTest:(NSPoint)point { return self.away ? nil : [super hitTest:point]; }
@end

@implementation PageCover
- (BOOL)isFlipped { return YES; }

- (NSView *)hitTest:(NSPoint)point {
    NSView *hit = [super hitTest:point];
    return hit == self ? nil : hit;
}
@end

@implementation Tint
- (void)setLook:(NSString *)look {
    _look = [look copy];
    [self paint];
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self paint];
}

- (void)paint {
    BOOL dark = IsDark(self.window.effectiveAppearance ?: NSApp.effectiveAppearance);
    ((NSVisualEffectView *)self.superview).material = dark ? NSVisualEffectMaterialHUDWindow
                                                           : NSVisualEffectMaterialPopover;
    BOOL glass = [self.look isEqual:@"glass"], black = [self.look isEqual:@"black"];
    // Its red, green and blue, out of 255, and how much of it covers the glass.
    CGFloat r, g, b, cover = glass ? (dark ? 0.55 : 0.5) : 1;
    if (dark && glass) r = g = 16, b = 18;
    else if (dark && black) r = g = 14, b = 17;
    else if (dark) r = g = 32, b = 35;
    else if (black) r = g = b = 255;
    else r = g = 245, b = 247;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.layer.backgroundColor = [NSColor colorWithSRGBRed:r / 255 green:g / 255 blue:b / 255 alpha:cover].CGColor;
    [CATransaction commit];
}
@end

@implementation ShadeView
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    if (self.onLook) self.onLook();
}
@end

// The glass's rounded corners, as a mask that stretches to any size.
// The rectangle `along` of the way from `a` to `b`.
static NSRect Between(NSRect a, NSRect b, CGFloat along) {
    return NSMakeRect(NSMinX(a) + (NSMinX(b) - NSMinX(a)) * along, NSMinY(a) + (NSMinY(b) - NSMinY(a)) * along,
                      NSWidth(a) + (NSWidth(b) - NSWidth(a)) * along,
                      NSHeight(a) + (NSHeight(b) - NSHeight(a)) * along);
}

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
    self.turnObservers = [NSMutableArray array];
    self.stillWaiters = [NSMutableArray array];
    self.catAt = kCatAt;
    self.pointerObservers = [NSMutableArray array];
    self.headerObservers = [NSMutableArray array];
    self.foldObservers = [NSMutableArray array];
    self.lookObservers = [NSMutableArray array];
    self.awayObservers = [NSMutableArray array];
    self.headerPoints = kHeaderHeight;
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
    // Its shadow is its own (shadeGlass): macOS's draws a light line round a window's edge on the dark panel.
    self.panel.hasShadow = NO;
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
    glass.maskImage = RoundedMask(kCorner);
    glass.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [root addSubview:glass];
    self.glass = glass;
    SideView *clip = [[SideView alloc] initWithFrame:root.bounds];
    clip.wantsLayer = YES;
    clip.layer.masksToBounds = YES;
    clip.layer.cornerRadius = kCorner;
    clip.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [root addSubview:clip];
    self.clip = clip;

    // The tint over the glass is the window's, under the page (whose own background is clear, panel/styles/base.css):
    // as the panel grows, the page paints the new space at its bottom a frame or two late, and until then bare glass
    // would show there, lighter, like a flicker. Rounded itself, as the glass's mask doesn't reach its subviews; it
    // follows the glass's edges as they move (reshapeTo:). Grey until Appearance says otherwise.
    Tint *tint = [[Tint alloc] initWithFrame:glass.bounds];
    tint.wantsLayer = YES;
    tint.layer.cornerRadius = kCorner;
    tint.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [glass addSubview:tint];
    tint.look = @"grey";
    self.tint = tint;

    // A window of its own that can't be seen, which the keyboard goes to on its way back (giveBackKeyboard).
    self.handOff = [[HandOffPanel alloc] initWithContentRect:NSMakeRect(NSMinX(frame), NSMinY(frame), 1, 1)
                                                   styleMask:NSWindowStyleMaskBorderless
                                                             | NSWindowStyleMaskNonactivatingPanel
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    self.handOff.level = self.panel.level;
    self.handOff.collectionBehavior = self.panel.collectionBehavior;
    self.handOff.hidesOnDeactivate = NO;
    self.handOff.opaque = NO;
    self.handOff.backgroundColor = NSColor.clearColor;
    self.handOff.hasShadow = NO;
    self.handOff.ignoresMouseEvents = YES;

    // The catch, which takes the rest of a swipe on Whozmove at the screen's edge (holdAway): it can't be seen, and,
    // never key (wantsKeyboard stays NO), never takes the keyboard. It takes the pointer though nothing's drawn in it,
    // as the room beside the folded cat does (passClicks:), above the panel and what it holds.
    self.swipeCatch = [[FloatingPanel alloc] initWithContentRect:NSMakeRect(0, 0, kCatch, kCatch)
                                                       styleMask:NSWindowStyleMaskBorderless
                                                                 | NSWindowStyleMaskNonactivatingPanel
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
    self.swipeCatch.level = self.panel.level + 1;
    self.swipeCatch.collectionBehavior = self.panel.collectionBehavior;
    self.swipeCatch.hidesOnDeactivate = NO;
    self.swipeCatch.opaque = NO;
    self.swipeCatch.backgroundColor = NSColor.clearColor;
    self.swipeCatch.hasShadow = NO;
    self.swipeCatch.ignoresMouseEvents = NO;

    // The panel's shadow, in a window of its own under it that takes no clicks, with room round the glass for it.
    self.shade = [[NSPanel alloc] initWithContentRect:NSInsetRect(frame, -kShadeRoom, -kShadeRoom)
                                            styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
    self.shade.level = self.panel.level;
    self.shade.collectionBehavior = self.panel.collectionBehavior;
    self.shade.hidesOnDeactivate = NO;
    self.shade.opaque = NO;
    self.shade.backgroundColor = NSColor.clearColor;
    self.shade.hasShadow = NO;
    self.shade.ignoresMouseEvents = YES;
    ShadeView *shadeView = [[ShadeView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(self.shade.frame),
                                                                       NSHeight(self.shade.frame))];
    shadeView.wantsLayer = YES;
    self.shade.contentView = shadeView;
    self.shadow = [CALayer layer];
    self.shadow.shadowColor = NSColor.blackColor.CGColor;
    self.shadow.mask = [CAShapeLayer layer];
    ((CAShapeLayer *)self.shadow.mask).fillRule = kCAFillRuleEvenOdd;
    [shadeView.layer addSublayer:self.shadow];

    // The clip rounds the page with the panel's corners, so what it draws up to its edges (the usage strip's vine)
    // meets them.
    page.view.frame = NSMakeRect(-kReaderRoom, 0, kPageWidth, NSHeight(clip.bounds) + kAboveRoom);
    page.view.autoresizingMask = NSViewHeightSizable;
    [clip addSubview:page.view];

    // The panel is dragged by its header's empty parts: the list's, and the reader's while it's open. A plain click on
    // the list's folds the list, but not while the reader is open beside it.
    __weak typeof(self) weakSelf = self;
    DragStrip *strip = [[DragStrip alloc]
        initWithFrame:NSMakeRect(0, frame.size.height - kHeaderHeight, kWidth - kButtonsWidth, kHeaderHeight)];
    strip.autoresizingMask = NSViewMinYMargin | NSViewWidthSizable;
    // Turned over, it turns back first.
    strip.onClick = ^{
        if (weakSelf.turned) [weakSelf turnOver:NO then:^{ [weakSelf.page toggleCollapsed]; }];
        else if (!weakSelf.expanded) [weakSelf.page toggleCollapsed];
    };
    DragStrip *readerStrip = [[DragStrip alloc] initWithFrame:NSZeroRect];
    readerStrip.autoresizingMask = NSViewMinYMargin;
    readerStrip.hidden = YES;
    for (DragStrip *each in @[strip, readerStrip]) {
        each.onDrag = ^BOOL(NSPoint by) { return [weakSelf dragBy:by]; };
        each.onDragged = ^{ [weakSelf draggedByHand]; };
    }
    // Pressed while folded, the folded cat's list doesn't come out on pointing until the button is let go: a press
    // there opens the panel, or drags it.
    strip.onPress = ^(BOOL down) {
        PanelWindow *me = weakSelf;
        if (down ? !me.folded || me.pressTold : !me.pressTold) return;
        me.pressTold = down;
        [me.page catPressed:down];
    };
    [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidChangeScreenParametersNotification object:nil
                                                     queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification *note) {
        [weakSelf updateRoom];
        if (!weakSelf.reshaping) [weakSelf tellGlass:[weakSelf glassOnScreen] over:0];
    }];
    // Another app took the keyboard (you clicked into it), or the panel gave it up: the page's box lets it go too, so
    // the page doesn't think it still has it.
    [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidResignKeyNotification object:self.panel
                                                     queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification *note) {
        weakSelf.panel.wantsKeyboard = NO;
        weakSelf.browserKeys = weakSelf.pageKeys = NO;
        [weakSelf.page keyboardGone];
    }];
    // A click into a site in the panel (Browser.h) takes the keyboard for it; one anywhere else in the panel gives it
    // back. Seen before the click goes to what's under it, so the site has the keyboard as it gets the click.
    self.clickWatch = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown
                                                            handler:^NSEvent *(NSEvent *event) {
        if (event.window != weakSelf.panel) return event;
        [weakSelf clickedAt:event.locationInWindow];
        return event;
    }];
    // A sideways two-finger swipe on the panel moves it (swiped:): seen before the page gets it, which then doesn't.
    self.swipeWatch = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskScrollWheel
                                                            handler:^NSEvent *(NSEvent *event) {
        return [weakSelf swiped:event];
    }];
    // The edge between the panel's two sides, seen only while it turns: a strip of the panel's own colour, lighter in
    // its middle as a rounded edge would catch the light (paintEdge). It's see-through but while its animation runs
    // (spin:then:), so it's never left lying flat at the panel's side once that has ended, not even for a frame.
    NSView *edge = [[NSView alloc] initWithFrame:NSZeroRect];
    edge.wantsLayer = YES;
    edge.alphaValue = 0;
    self.edgeShade = [CAGradientLayer layer];
    self.edgeShade.startPoint = CGPointMake(0, 0.5);
    self.edgeShade.endPoint = CGPointMake(1, 0.5);
    self.edgeShade.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    [edge.layer addSublayer:self.edgeShade];
    [root addSubview:edge];
    self.edge = edge;
    [root addSubview:strip];
    [root addSubview:readerStrip];
    self.strip = strip;
    self.readerStrip = readerStrip;
    // The shadow follows the window wherever it's moved or resized to. Once the panel turns light or dark, the tint is
    // painted again and the shadow is softer or firmer: the shadow's window hears of it, as nothing in it is under glass.
    for (NSNotificationName name in @[NSWindowDidResizeNotification, NSWindowDidMoveNotification])
        [NSNotificationCenter.defaultCenter addObserverForName:name object:self.panel queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(NSNotification *note) { [weakSelf shadeGlass]; }];
    shadeView.onLook = ^{
        [weakSelf.tint paint];
        [weakSelf shadeGlass];
    };
    // Whether anything of it can be seen changes as it's hidden or shown, and as the screen sleeps, locks or wakes.
    NSNotificationName occlusion = NSWindowDidChangeOcclusionStateNotification;
    void (^seenNow)(NSNotification *) = ^(NSNotification *note) { [weakSelf tellSeen:weakSelf.seen]; };
    [NSNotificationCenter.defaultCenter addObserverForName:occlusion object:self.panel queue:NSOperationQueue.mainQueue
                                                usingBlock:seenNow];

    LetPointerShapesIn();
    [self pollPointerEvery:kPointerEvery];
    return self;
}

// It fades in, so that after a deploy, when the app restarts on the new build, the panel comes back softly where it
// was rather than popping up.
- (void)show {
    [self.panel setFrameUsingName:@"Whozmove"];
    // Folded as it was left, before the page has loaded to say so (it does then, fold:instant:), so it doesn't show
    // open for a moment first.
    self.folded = [NSUserDefaults.standardUserDefaults boolForKey:kFoldedKey];
    [self placeAtOnce];
    self.panel.alphaValue = self.shade.alphaValue = 0;
    [self tellSeen:YES];
    [self.panel orderFrontRegardless];
    [self holdShade];
    [self shadeGlass];
    [self tellGlass:[self glassOnScreen] over:0];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion ? 0 : 0.2;
        self.panel.animator.alphaValue = 1;
        self.shade.animator.alphaValue = 1;
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
    if (self.parked) [self unpark];
    else if (self.panel.isVisible) {
        [self.panel orderOut:nil];
        [self tellSeen:NO];
    }
    else [self bringUp];
}

- (BOOL)shown {
    return self.panel.isVisible;
}

// Whether anything of the panel can be seen: on the screen, not hidden from the menu bar, on a screen that's awake and
// not locked, and not all under other windows. Flicked off the screen's edge it counts as seen: a pull or a press on
// Whozmove there brings it straight back, its list showing on the way.
- (BOOL)seen {
    return self.parked || (self.panel.isVisible && (self.panel.occlusionState & NSWindowOcclusionStateVisible));
}

// Tells the page whether the panel can be seen, when that changes, so it draws its list only while it can (panelSeen,
// in parts/bridge's app-calls.js). Each way of bringing the panel back says so just before it comes, so the list is
// drawn as it is by then.
- (void)tellSeen:(BOOL)seen {
    [self restPointer:!seen];  // nor is the pointer looked at meanwhile (parts/hover)
    if (!self.page.ready || (self.seenTold && self.seenSaid == seen)) return;
    self.seenTold = YES;
    self.seenSaid = seen;
    [self.page call:@"panelSeen" with:@[@(seen)]];
}

- (NSString *)look {
    return self.tint.look;
}

- (void)setLook:(NSString *)look {
    self.tint.look = look;
    for (void (^observer)(void) in self.lookObservers) observer();
}

// Back on the screen, the shadow is held just under it again, over what was held under it while it was away.
- (void)bringUp {
    if (self.parked) return [self unpark];
    if (self.panel.isVisible) return;
    [self tellSeen:YES];
    [self.panel orderFrontRegardless];
    [self holdShade];
}

- (void)resetPosition {
    if (self.parked || self.parkTimer) [self backAtOnce];
    // Folded with something out beside the cat, it goes in, and comes out again once the cat is there.
    BOOL roomOut = self.folded && self.roomHeld;
    if (roomOut) {
        [self tellMoving:YES];
        [self.panel setFrame:[self catBoxIn:self.panel.frame] display:NO];
        [self letRoomGo];
    }
    NSRect screen = NSScreen.mainScreen.visibleFrame;
    NSRect frame = self.panel.frame;
    // Folded, the cat goes where the name's o is in the panel put back there.
    if (self.folded) frame.size = NSMakeSize(kWidth, self.openHeight ?: 200);
    frame.origin = NSMakePoint(NSMaxX(screen) - frame.size.width - 16, NSMaxY(screen) - frame.size.height - 16);
    if (self.folded) frame = [self foldedFrameFrom:frame];
    [self.panel setFrame:frame display:YES];
    if (self.folded) [self placeAtOnce];
    [self.panel saveFrameUsingName:@"Whozmove"];
    [self tellSeen:YES];
    [self.panel orderFrontRegardless];
    [self updateRoom];
    [self tellGlass:[self glassOnScreen] over:0];
    if (roomOut) [self tellMoving:NO];
}

#pragma mark Size

// How tall the panel can grow from where its top edge is, down to the bottom of the screen, less the room kept there
// for what hangs under it (RoomFor), and the most its header and list take on that screen (ListLimitFor): told to the
// page as either changes. The page keeps itself to the room (its list gives way and scrolls), so the panel never runs
// off the screen, and its header and list to the limit, with what opens under the list or the header on top of that
// (page/glass.css). Folded, the room is the one the panel will open into from where the cat is (openRoomFrom:), so the
// page asks for the height it then opens at, on a screen of another size too (fitHeight:); with the reader open, the
// room waits until the list is back by itself, but the limit is told at once.
- (void)updateRoom {
    CGFloat limit = ListLimitFor(NSHeight((self.panel.screen ?: NSScreen.mainScreen).visibleFrame));
    if (self.expanded && !self.room) return;
    CGFloat room = self.expanded ? self.room
                 : self.folded ? [self openRoomFrom:[self catBoxIn:self.panel.frame]] : [self roomFor:self.panel.frame];
    if ((room == self.room && limit == self.listLimit) || !self.page.ready) return;
    self.room = room;
    self.listLimit = limit;
    [self.page setRoom:room limit:limit];
}

- (CGFloat)roomFor:(NSRect)frame {
    NSRect screen = (self.panel.screen ?: NSScreen.mainScreen).visibleFrame;
    return RoomFor(NSMaxY(frame), NSMinY(screen), self.keptBelow, self.linesUnder);
}

CGFloat RoomFor(CGFloat top, CGFloat bottom, CGFloat below, CGFloat under) {
    CGFloat whole = top - bottom, least = MIN(kHeaderHeight + under + 80, whole);
    return floor(MAX(kHeaderHeight + 80, MAX(least, whole - (below > 0 ? below + kBelowGap : 0))));
}

CGFloat OpenedHeight(CGFloat kept, CGFloat asked, CGFloat room) {
    return floor(MAX(kHeaderHeight, MIN(asked > 0 ? asked : kept ?: 200, room)));
}

- (void)linesUnder:(CGFloat)under {
    if (under == self.linesUnder) return;
    self.linesUnder = under;
    [self updateRoom];
}

CGFloat ListLimitFor(CGFloat visible) {
    return floor(MIN(kListMost, visible));
}

- (void)keepBelow:(CGFloat)points for:(NSWindow *)window {
    if (!window) return;
    if (!self.belowKept) self.belowKept = [NSMapTable weakToStrongObjectsMapTable];
    CGFloat was = self.keptBelow;
    if (points > 0) [self.belowKept setObject:@(points) forKey:window];
    else [self.belowKept removeObjectForKey:window];
    if (self.keptBelow != was) [self updateRoom];
}

- (CGFloat)keptBelow {
    CGFloat most = 0;
    for (NSWindow *window in self.belowKept) most = MAX(most, [[self.belowKept objectForKey:window] doubleValue]);
    return most;
}

- (void)resendRoom {
    self.room = 0;
    self.listLimit = 0;
    // A page loaded afresh hasn't heard which way what comes out of the folded cat goes either, nor that the panel is
    // turned over, nor whether it can be seen.
    self.wayTold = NO;
    [self updateRoom];
    if (self.turned) [self.page turned:YES];
    self.seenTold = NO;
    [self tellSeen:self.seen];
    self.readerSideTold = nil;
    [self tellReaderSide];
}

// The side the reader would open to now, the one facing the screen's middle (edgeSide), or while it's open the side it
// opened to (listOnRight), however the panel has been dragged since: told to the page as it changes, so a row's room at
// that edge says where its chat comes out. The reader opens to edgeSide once it's known (expandReader:height:).
- (void)tellReaderSide {
    NSString *side = self.expanded ? (self.listOnRight ? @"left" : @"right") : self.edgeSide;
    if (!side || [side isEqual:self.readerSideTold]) return;
    self.readerSideTold = side;
    [self.page readerSide:side];
}

- (void)fitHeight:(CGFloat)height {
    // Turned over, or on its way there or back, the panel keeps the size it turned at, so the back stays the list's size
    // as it was then rather than following the list out of sight: the height the list asks for meanwhile is taken once
    // the panel is back on its list side.
    if (self.turned || self.turning) {
        self.heightAsked = height;
        return;
    }
    // Folded, what the page asks for is the height the panel opens at (openFrameFrom:): the rows, or the list's limit on
    // the screen the folded panel was taken to, may have changed since it folded.
    if (self.folded && !self.reshaping) self.foldedAsked = height;
    if (self.expanded || self.reshaping || self.folded) return;
    height = MIN(height, self.room ?: [self roomFor:self.panel.frame]);
    NSRect frame = self.panel.frame;
    if (fabs(frame.size.height - height) < 1) return;
    frame.origin.y += frame.size.height - height;  // keep the top edge where the user put it
    frame.size.height = height;
    [self.panel setFrame:frame display:YES animate:NO];
    [self tellGlass:[self glassOnScreen] over:0];
}

- (void)attachBelow:(NSWindow *)window {
    [self.panel addChildWindow:window ordered:NSWindowBelow];
    if (self.panel.isVisible) [self holdShade];
}

- (void)attachAbove:(NSWindow *)window {
    [self.panel addChildWindow:window ordered:NSWindowAbove];
}

// Where the glass is, for what's held under the panel: the list is where the panel is, or, while the reader is open,
// where it was.
- (void)followGlass:(void (^)(NSRect, NSRect, NSRect, NSTimeInterval))observer {
    [self.glassObservers addObject:observer];
}

- (void)followPointer:(void (^)(NSPoint))observer {
    [self.pointerObservers addObject:observer];
}

- (void)headerShowing:(CGFloat)showing gone:(BOOL)gone {
    self.headerPoints = showing;
    if (!self.reshaping) [self placeStrips];
    if (gone == self.headerGone) return;
    self.headerGone = gone;
    for (void (^observer)(BOOL) in self.headerObservers) observer(gone);
}

- (void)followHeader:(void (^)(BOOL))observer {
    [self.headerObservers addObject:observer];
}

- (void)followLook:(void (^)(void))observer {
    [self.lookObservers addObject:observer];
}

- (NSPoint)listCorner {
    return [self rootAt];
}

- (BOOL)dragBy:(NSPoint)by {
    if (self.reshaping) return NO;
    // Folded with something out beside the cat, that goes in first (the page gives the room back), and the cat moves
    // once it has: the drag, which counts from where it started, catches up then.
    if (self.folded && self.roomHeld) {
        [self tellMoving:YES];
        return NO;
    }
    NSRect was = self.panel.frame;
    [self.panel setFrame:NSOffsetRect(was, by.x, by.y) display:YES];
    // By where the window is now, not by how far the pointer went: macOS rounds a window's place to whole pixels and
    // keeps it below the menu bar, so the pointer's moves added up would drift from it over a long drag. While the
    // reader is open, the list moves with the panel, and folds back to where it is then.
    NSRect is = self.panel.frame;
    if (self.expanded)
        self.listFrame = NSOffsetRect(self.listFrame, NSMinX(is) - NSMinX(was), NSMinY(is) - NSMinY(was));
    [self tellGlass:[self glassOnScreen] over:0];
    return YES;
}

// Not while the reader is open, which turns the name off: that size isn't the one to come back at.
- (void)draggedByHand {
    [self keepPlace];
    [self tellMoving:NO];
}

- (void)keepPlace {
    if (self.panel.frameAutosaveName.length) [self.panel saveFrameUsingName:self.panel.frameAutosaveName];
    [self updateRoom];
}

// The page hears the folded cat has started moving with something out beside it, which goes in meanwhile, and once it
// has stopped, with which way what comes out of it goes from there (tellCatWay), so it comes out that way.
- (void)tellMoving:(BOOL)moving {
    if (moving == self.movingTold) return;
    self.movingTold = moving;
    if (!moving) {
        self.wayTold = NO;
        [self tellCatWay];
    }
    [self.page catMoving:moving];
}

- (void)hold:(NSWindow *)window over:(BOOL)over {
    [self.panel removeChildWindow:window];
    [self.panel addChildWindow:window ordered:over ? NSWindowAbove : NSWindowBelow];
    if (!over && self.panel.isVisible) [self holdShade];
}

- (void)tellGlass:(NSRect)glass over:(NSTimeInterval)duration {
    if (self.roomChanging) return;
    NSScreen *screen = self.panel.screen ?: NSScreen.mainScreen;
    NSRect list = self.expanded ? self.listFrame : glass;
    // Flicked away, or on its way there or back, the icons keep the side facing back onto the screen (parkToward:).
    if (!self.parked && !self.parkTimer) self.edgeSide = EdgeSideFor(list, screen.visibleFrame, self.edgeSide);
    [self tellReaderSide];
    for (void (^observer)(NSRect, NSRect, NSRect, NSTimeInterval) in self.glassObservers)
        observer(glass, list, screen.visibleFrame, duration);
}

#pragma mark Over the page

- (void)hold:(NSView *)view overPage:(NSRect)rect {
    if (!view) return;
    if (!self.cover) {
        PageCover *cover = [[PageCover alloc] initWithFrame:self.page.view.frame];
        cover.autoresizingMask = NSViewNotSizable;
        [self.clip addSubview:cover positioned:NSWindowAbove relativeTo:self.page.view];
        self.cover = cover;
        // The page is moved and sized in many places (the panel growing, folding into the cat, turning over), each a
        // step at a time: told of every change, as it's made, the cover is where the page is in every frame.
        self.page.view.postsFrameChangedNotifications = YES;
        __weak typeof(self) weakSelf = self;
        [NSNotificationCenter.defaultCenter addObserverForName:NSViewFrameDidChangeNotification
                                                        object:self.page.view
                                                         queue:nil
                                                    usingBlock:^(NSNotification *note) {
            weakSelf.cover.frame = weakSelf.page.view.frame;
        }];
    }
    view.frame = NSIntegralRect(rect);
    if (view.superview != self.cover) [self.cover addSubview:view];
}

- (void)letGo:(NSView *)view {
    if (view.superview == self.cover) [view removeFromSuperview];
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
        } else {
            [weakSelf tellStill];
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

// Where the top-left corner of the page's list (#root) is on the screen: the panel's (the list's, which stays put while
// the reader is open); folded, catAt from the glass's middle, as the page draws the cat at the name's o (cat.js), so as
// the panel folds round it, and once it has, the page stays where it was.
- (NSPoint)rootAt {
    if (self.holdsPage) return self.pageAt;
    if (self.folded) return [self rootAround:[self catBoxIn:self.panel.frame]];
    // Turning over, the window has taken in room round the panel to turn in: the page stays where the panel is.
    if (self.turning) return NSMakePoint(NSMinX(self.turnFrame), NSMaxY(self.turnFrame));
    return NSMakePoint(self.expanded ? NSMinX(self.listFrame) : NSMinX(self.panel.frame), NSMaxY(self.panel.frame));
}

// Where the page's list's top-left corner is while the cat's square is `box`: catAt from the glass's middle.
- (NSPoint)rootAround:(NSRect)box {
    return NSMakePoint(NSMidX(box) - self.catAt.x, NSMidY(box) + self.catAt.y);
}

// Where the page's left edge is on the screen: kReaderRoom left of the list; and its top, kAboveRoom above the list's.
- (CGFloat)pageLeft {
    return [self rootAt].x - kReaderRoom;
}

- (CGFloat)pageTop {
    return [self rootAt].y + kAboveRoom;
}

// The page's frame in the clip, which is `local` in a window that's `frame` on the screen: its list where rootAt says,
// with the room above it (kAboveRoom), and as tall as from there to the window's bottom. Folded, and while it folds or
// opens, it's at least as tall as the open panel, past the window's bottom: so it's laid out at the one size all the
// way, and opening shows more of it rather than having WebKit lay it out and draw it again as the cat starts to shrink.
- (NSRect)pageFrameIn:(NSRect)frame clip:(NSRect)local {
    NSPoint at = [self rootAt];
    CGFloat tall = at.y - NSMinY(frame);
    if (self.folded || self.holdsPage) tall = MAX(tall, self.openHeight ?: 200);
    // Turning over, it keeps the panel's height, so it isn't laid out again for the room taken in below the panel.
    if (self.turning) tall = NSHeight(self.turnFrame);
    return PageFrameIn(at, tall, frame, local);
}

NSRect PageFrameIn(NSPoint root, CGFloat tall, NSRect window, NSRect clip) {
    return NSMakeRect(root.x - kReaderRoom - NSMinX(window) - NSMinX(clip),
                      root.y - tall - NSMinY(window) - NSMinY(clip), kPageWidth, tall + kAboveRoom);
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
    [self setWindowFrame:frame glass:shown clip:shown then:then];
}

// The same, with the glass and the page's clip each where it's shown on the screen: while the panel folds into the cat
// or opens out of it, the glass is round inside the square the page shows the cat in.
- (void)setWindowFrame:(NSRect)frame glass:(NSRect)glass clip:(NSRect)clip then:(void (^)(void))then {
    NSView *root = self.panel.contentView;
    root.autoresizesSubviews = NO;
    self.clip.autoresizesSubviews = NO;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self.panel setFrame:frame display:NO];
    // The page by where the window really is, as the glass and the clip are: near the top of the screen, macOS keeps
    // the window under the menu bar, lower than `frame` (the room a turn takes in above the panel), and a page placed
    // by `frame` would drop that much as the turn starts.
    NSRect local = [self inWindow:clip];
    self.glass.frame = [self inWindow:glass];
    self.clip.frame = local;
    self.page.view.frame = [self pageFrameIn:self.panel.frame clip:local];
    [self placeBack];
    [CATransaction commit];
    [self shadeGlass];
    [self tellGlass:glass over:0];
    [self.page afterPaint:then];
}

// The glass and the page's clip move to `target` (on the screen) within the window, the page staying put; the
// panel's shadow follows them.
- (void)moveEdgesTo:(NSRect)target then:(void (^)(void))then {
    [self moveGlassTo:target clip:target corner:kCorner glassCorner:kCorner over:0.5 easing:kSettle then:then];
}

// The same, with the glass and the page's clip each going to a place of its own, and their corners to `glassCorner` and
// `corner`, over `seconds` on `easing`: folding, the glass closes in on the cat and ends round about it. The page
// stays where it is on the screen, or goes where rootAt says. All three are moved together at each step, from one
// clock: the glass can't be moved by Core Animation (its corners are a mask image, and AppKit steps its frame itself),
// and a clip moved by Core Animation beside it ran ahead or behind it, showing the page past the glass's edge.
- (void)moveGlassTo:(NSRect)glass clip:(NSRect)clip corner:(CGFloat)corner glassCorner:(CGFloat)glassCorner
               over:(NSTimeInterval)seconds easing:(Easing)easing then:(void (^)(void))then {
    NSView *root = self.panel.contentView;
    root.autoresizesSubviews = NO;
    self.clip.autoresizesSubviews = NO;
    NSTimeInterval duration = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion ? 0 : seconds;
    [self tellGlass:glass over:duration];
    // Each from where it is now, in the window, which doesn't change meanwhile; the page on the screen.
    NSRect glassFrom = self.glass.frame, glassTo = [self inWindow:glass];
    NSRect clipFrom = self.clip.frame, clipTo = [self inWindow:clip];
    CGFloat cornerFrom = self.clip.layer.cornerRadius, glassCornerFrom = self.glassRadius;
    NSPoint window = self.panel.frame.origin, at = [self rootAt];
    NSPoint pageFrom = NSMakePoint(window.x + NSMinX(clipFrom) + NSMinX(self.page.view.frame),
                                   window.y + NSMinY(clipFrom) + NSMinY(self.page.view.frame));
    NSPoint pageTo = NSMakePoint(at.x - kReaderRoom, at.y + kAboveRoom - NSHeight(self.page.view.frame));
    __weak typeof(self) weakSelf = self;
    void (^step)(CGFloat) = ^(CGFloat along) {
        PanelWindow *me = weakSelf;
        NSRect clipNow = Between(clipFrom, clipTo, along);
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        me.glass.frame = Between(glassFrom, glassTo, along);
        me.clip.frame = clipNow;
        me.clip.layer.cornerRadius = cornerFrom + (corner - cornerFrom) * along;
        NSPoint page = NSMakePoint(pageFrom.x + (pageTo.x - pageFrom.x) * along,
                                   pageFrom.y + (pageTo.y - pageFrom.y) * along);
        [me.page.view setFrameOrigin:NSMakePoint(page.x - window.x - NSMinX(clipNow),
                                                 page.y - window.y - NSMinY(clipNow))];
        [CATransaction commit];
        [me roundGlass:round((glassCornerFrom + (glassCorner - glassCornerFrom) * along) * 2) / 2];
        [me shadeGlass];
    };
    [self.moveTimer invalidate];
    self.moveTimer = nil;
    if (duration <= 0) {
        step(1);
        [self roundGlass:glassCorner];
        dispatch_async(dispatch_get_main_queue(), then);
        return;
    }
    CFTimeInterval start = CACurrentMediaTime();
    NSTimer *timer = [NSTimer timerWithTimeInterval:1.0 / 120 repeats:YES block:^(NSTimer *each) {
        CGFloat x = (CACurrentMediaTime() - start) / duration;
        step(Eased(easing, x));
        if (x < 1) return;
        [each invalidate];
        PanelWindow *me = weakSelf;
        if (me.moveTimer == each) me.moveTimer = nil;
        [me roundGlass:glassCorner];
        then();
    }];
    self.moveTimer = timer;
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
}

// Done changing size: the glass, the clip and the page fill the window again, and follow it as before. Folded, the
// glass is the round one in the cat's square, and the clip the circle round it, or the whole window while chats are out
// beside it.
- (void)settle {
    NSView *root = self.panel.contentView;
    self.holdsPage = NO;
    if (self.folded) {
        self.glass.frame = [self inWindow:[self foldedGlassIn:self.panel.frame]];
        [self roundGlass:kFoldGlass / 2];
        self.clip.layer.cornerRadius = self.roomHeld ? 0 : kFoldBox / 2;
    } else {
        [self letRoomGo];
    }
    // Back to the cat's square from the room beside it, which was never saved, it's saved as itself again.
    if (!self.roomHeld && !self.expanded && !self.panel.frameAutosaveName.length) {
        [self.panel saveFrameUsingName:@"Whozmove"];
        self.panel.frameAutosaveName = @"Whozmove";
    }
    if (!self.folded) {
        self.glass.frame = root.bounds;
        [self roundGlass:kCorner];
        self.clip.layer.cornerRadius = kCorner;
    }
    self.clip.frame = root.bounds;
    self.page.view.frame = [self pageFrameIn:self.panel.frame clip:self.clip.frame];
    [self placeBack];
    [self placeStrips];
    root.autoresizesSubviews = YES;
    self.clip.autoresizesSubviews = YES;
    self.reshaping = NO;
    [self shadeGlass];
    [self tellGlass:[self glassOnScreen] over:0];
    // Folded again while sessions still work, the glass breathes again.
    [self startBreathing];
    // A turn asked for while it changed shape is taken now; a turn of its own takes it itself once it's done.
    if (self.pendingTurn && !self.turning) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf takePendingTurn]; });
    }
}

// The drag strips over the headers' empty parts: the list's, up to its buttons; and while the reader is open, the
// reader's, up to its ✕.
- (void)placeStrips {
    NSRect bounds = self.panel.contentView.bounds;
    CGFloat top = NSHeight(bounds) - kHeaderHeight;
    // Folded, the cat's square is dragged by, and a click on it opens the panel; the room beside it is the page's.
    if (self.folded) {
        self.strip.frame = [self inWindow:[self catBoxIn:self.panel.frame]];
        self.strip.hidden = NO;
        self.readerStrip.hidden = YES;
        return;
    }
    if (!self.expanded) {
        // Only over the part of the header that still shows as it's pushed away, so a press on the rows that have come
        // up under it goes to them; none once it has gone. The back's header stays where it is.
        CGFloat lead = self.turned ? kBackLead : 0;
        CGFloat showing = self.turned ? kHeaderHeight : MAX(0, MIN(kHeaderHeight, self.headerPoints));
        self.strip.frame = NSMakeRect(lead, NSHeight(bounds) - showing, NSWidth(bounds) - kButtonsWidth - lead,
                                      showing);
        self.strip.hidden = showing < 1;
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

// Where the glass is on the screen: the round one in the middle of the folded window, or the whole panel.
- (NSRect)glassOnScreen {
    return self.folded ? [self foldedGlassIn:self.panel.frame] : self.panel.frame;
}

// The panel's shadow, its own rather than the window's: macOS draws a light line round a window's edge with the
// window's shadow on the dark panel. It's under the glass wherever the glass is (opening the reader, folding into the
// cat and back, breathing), with its corners, in the window held under the panel, so whatever else is held under it
// (Spotify's token) has the panel's shadow fall on it. Nothing is under the glass itself, which may be see-through.
// The open panel's is the widest; round the folded cat it's smaller, and on the light panel softer.
- (void)shadeGlass {
    if (!self.shade) return;
    NSRect window = self.panel.frame, room = NSInsetRect(window, -kShadeRoom, -kShadeRoom);
    if (!NSEqualRects(room, self.shade.frame)) [self.shade setFrame:room display:NO];
    // From where the shadow's window really is: near the top of the screen, macOS keeps it below the menu bar, lower
    // than the room above the panel would put it, and a shadow placed as if it weren't would hang below the panel,
    // round nothing.
    NSRect shade = self.shade.frame;
    NSRect glass = NSOffsetRect(self.glass.frame, NSMinX(window) - NSMinX(shade), NSMinY(window) - NSMinY(shade));
    CGFloat radius = MIN(self.glassRadius ?: kCorner, MIN(NSWidth(glass), NSHeight(glass)) / 2);
    // How far it is from the open panel's corners to the folded cat's circle.
    CGFloat circle = MAX(0, MIN(1, (radius - kCorner) / (kFoldGlass / 2 - kCorner)));
    BOOL dark = IsDark(self.panel.effectiveAppearance);
    CGRect bounds = CGRectMake(0, 0, NSWidth(glass), NSHeight(glass));
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.shadow.frame = glass;
    CGPathRef shape = CGPathCreateWithRoundedRect(bounds, radius, radius, NULL);
    self.shadow.shadowPath = shape;
    CGPathRelease(shape);
    self.shadow.shadowRadius = 22 + (9 - 22) * circle;
    self.shadow.shadowOffset = CGSizeMake(0, -14 + (14 - 6) * circle);
    self.shadow.shadowOpacity = (0.5 + (0.38 - 0.5) * circle) * (dark ? 1 : 0.45);
    CAShapeLayer *outside = (CAShapeLayer *)self.shadow.mask;
    outside.frame = CGRectInset(bounds, -kShadeRoom, -kShadeRoom);
    CGMutablePathRef cut = CGPathCreateMutable();
    CGPathAddRect(cut, NULL, outside.bounds);
    CGPathAddRoundedRect(cut, NULL, CGRectOffset(bounds, kShadeRoom, kShadeRoom), radius, radius);
    outside.path = cut;
    CGPathRelease(cut);
    [CATransaction commit];
}

// The shadow's window, held just under the panel, over anything else held under it.
- (void)holdShade {
    [self.panel removeChildWindow:self.shade];
    [self.panel addChildWindow:self.shade ordered:NSWindowBelow];
}

// The glass's corners: its mask's, which doesn't reach its subviews, and the tint's.
- (void)roundGlass:(CGFloat)radius {
    if (radius == self.glassRadius && self.glass.maskImage) return;
    self.glassRadius = radius;
    self.glass.maskImage = RoundedMask(radius);
    self.tint.layer.cornerRadius = radius;
}

// macOS shows only the pointer shapes the app in front sets, and ignores a background app's, so the panel, whose app is
// never in front, could only ever show the arrow. A setting of macOS's window server that isn't public (checked on macOS
// 26.2) has it take them from this app too. It's looked up as the app runs, so a macOS without it leaves the arrow.
static void LetPointerShapesIn(void) {
    int (*connection)(void) = dlsym(RTLD_DEFAULT, "_CGSDefaultConnection");
    int (*setProperty)(int, int, CFStringRef, CFTypeRef) = dlsym(RTLD_DEFAULT, "CGSSetConnectionProperty");
    if (!connection || !setProperty) {
        LogProblem(@"Pointer shapes: macOS's background setting isn't there");
        return;
    }
    int problem = setProperty(connection(), connection(), CFSTR("SetsCursorInBackground"), kCFBooleanTrue);
    if (problem)
        LogProblem([NSString stringWithFormat:@"Pointer shapes: macOS refused its background setting (%d)", problem]);
}
@end
