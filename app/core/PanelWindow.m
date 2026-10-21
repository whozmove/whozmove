// PanelWindow: the floating glass window, its drag strip, its size, and the pointer over it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "PanelWindow.h"
#import "Page.h"
#import <QuartzCore/QuartzCore.h>

// The panel's width; its header's height (--header in panel/styles/tokens.css) and the buttons at the header's right
// end, which the drag strip leaves to the page.
static const CGFloat kWidth = 340, kHeaderHeight = 46, kButtonsWidth = 72;
// The reader's ✕, at its header's right end (.r-close in panel/styles/reader.css, with the header's padding), which
// the reader's drag strip leaves to the page.
static const CGFloat kCloseWidth = 46;
// The page is never laid out at another width: a change of width has WebKit lay it all out and draw it again, which
// shows as the whole panel flashing. So it's as wide as the list with room for the widest reader on either side of
// it (--side in panel/styles/tokens.css), always, and the window shows the part in use: the list, and the reader
// beside it while it's open. The page's left edge stays this far left of the list's.
static const CGFloat kReaderRoom = 1254, kPageWidth = kWidth + 2 * kReaderRoom;
// Folded, the panel is a round glass kFoldGlass across, on the name's o in the open panel's header, in a window
// kFoldBox square: the room round the glass is for its shadow (panel/scripts/cat.js draws the cat in it). The glass's
// corners are kCorner while it's open, and half its width while it's round.
static const CGFloat kFoldBox = 102, kFoldGlass = 76, kCorner = 24;
// Folded, the glass's middle is this far from the open panel's top-left corner, just above the name's o, so the cat's
// raised head is on the o, as the page says once it has measured it (catAt:, in whole points): the panel grows around
// the cat, which stays where it is and only changes size.
static const NSPoint kCatAt = {45, 23};
// Opening, the glass spreads from the circle behind the cat to the whole panel in kSpread, wider and taller together;
// folding, it closes back in on the cat the same way. The cat changes size on the same curve (panel/styles/cat.css).
static const NSTimeInterval kSpread = 0.5;
// How near the pointer has to be for the folded cat to be told where it is: its eyes follow it within 480pt (cat.js),
// and it's told a little further out, so it hears when the pointer leaves.
static const CGFloat kCatSees = 520;
// How often the pointer is looked at (pollPointer): 25 times a second for hover, and as often as the screen is drawn
// while the folded cat's eyes follow it, so they keep up with it.
static const NSTimeInterval kPointerEvery = 0.04, kPointerEveryWatched = 1.0 / 60;
// Whether the panel was folded when it was left, so it comes back folded before its page has loaded.
static NSString *const kFoldedKey = @"panelFolded";

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
@property (assign) NSPoint lastScreen;  // where the pointer was at the last look, on the screen
@property (assign) BOOL leftStill;      // it came off the panel without moving, and hasn't moved since
@property (assign) BOOL expanded;       // grown to the screen for the reader
@property (assign) NSRect listFrame;    // where the panel was before it grew, to fold back to
@property (assign) BOOL listOnRight;    // the reader opened to the list's left
// The panel's shape, apart from the window's: the glass and the page's clip (rounded, over it) normally fill the
// window, and while the panel changes size they show only part of it (reshapeTo:).
@property (strong) NSVisualEffectView *glass;
@property (strong) NSView *tint;
// The folded glass's own shadow while the cat's tags are out, when the window has none (catFan:).
@property (strong) NSView *catShadow;
@property (strong) NSView *clip;
@property (assign) BOOL reshaping;
@property (assign) BOOL hasPending;     // a size asked for while the panel was changing size, taken next
@property (assign) NSRect pendingFrame;
@property (copy) void (^pendingDone)(void);
// Moving the glass, the clip and the page together, a step at a time (moveGlassTo:).
@property (strong) NSTimer *moveTimer;
// Who follows the glass and the pointer (followGlass:, followPointer:).
@property (strong) NSMutableArray *glassObservers, *pointerObservers;
// Folded into the cat (fold:instant:); how tall the panel was as it folded, to open at again; a fold or an opening
// asked for while one was moving, taken next (nil for none).
@property (assign) BOOL folded;
// Folded, whether the window has made room for the cat's tags (catFan:), so it's larger than the cat's corner; and
// whether they fan out to its right (the cat is on the screen's left half), the cat then in the window's top-left.
@property (assign) BOOL fanOpen;
@property (assign) BOOL fanRight;
// The side the page was last told the tags go (catSide:), or nil.
@property (strong) NSNumber *toldSide;
// While the panel folds or opens (holdsPage), where the top-left corner of the page's list is held on the screen
// (rootAt): it starts where it was and goes where it ends, whatever the window takes in on the way.
@property (assign) BOOL holdsPage;
@property (assign) NSPoint pageAt;
// Where the glass's middle is from the open panel's top-left corner, folded (kCatAt until the page says).
@property (assign) NSPoint catAt;
@property (assign) CGFloat openHeight;
// The glass's corners now (roundGlass:).
@property (assign) CGFloat glassRadius;
@property (strong) NSNumber *pendingFold;
// The cat's tags' room asked for while the panel was folding or opening ({on, width, height}), taken next.
@property (strong) NSDictionary *pendingFan;
// Where the pointer last was from the folded glass's centre, as the page was told, and whether it was near enough.
@property (assign) BOOL catSeesPointer;
@property (assign) NSPoint lastCatPointer;
// The folded glass's breath (catBreathe:): how many sessions the page last said are working, whether it's breathing,
// and which run of breaths is the live one, so one that's been stopped doesn't take another breath.
@property (assign) NSInteger breathWorking;
@property (assign) BOOL breathing;
@property (assign) NSUInteger breathRun;
@end

// The glass's rounded corners, as a mask that stretches to any size.
// How far along a move is at `x` of its time, on a curve given as CSS gives one, cubic-bezier(x1, y1, x2, y2).
typedef struct { CGFloat x1, y1, x2, y2; } Easing;
// The reader's: quick, then settling. Folding and opening: gentle at both ends, as the cat changes size with the glass.
static const Easing kSettle = {0.2, 0.8, 0.2, 1}, kFoldEasing = {0.4, 0, 0.2, 1};

static CGFloat Eased(Easing e, CGFloat x) {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    // The curve's own time for `x` (Newton's method), then how far along it is there.
    CGFloat t = x;
    for (int i = 0; i < 8; i++) {
        CGFloat u = 1 - t;
        CGFloat off = 3 * u * u * t * e.x1 + 3 * u * t * t * e.x2 + t * t * t - x;
        CGFloat slope = 3 * u * u * e.x1 + 6 * u * t * (e.x2 - e.x1) + 3 * t * t * (1 - e.x2);
        if (fabs(off) < 1e-6 || fabs(slope) < 1e-6) break;
        t = MIN(1, MAX(0, t - off / slope));
    }
    CGFloat u = 1 - t;
    return 3 * u * u * t * e.y1 + 3 * u * t * t * e.y2 + t * t * t;
}

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

// How the folded glass breathes with `working` sessions (catBreathe:): seconds a breath, how much wider at its fullest,
// where the breath in ends and the breath out, and how far it has turned into a heartbeat, from 0 to 1.
typedef struct { NSTimeInterval seconds; CGFloat depth, in, out, heart; } Breath;

static Breath BreathFor(NSInteger working) {
    static const Breath steps[] = {{3.0, .06, .38, .84, 0}, {2.4, .065, .38, .86, 0}, {1.9, .07, .39, .88, 0},
                                   {1.7, .072, .39, .90, 0}, {1.5, .075, .40, .92, 0}};
    if (working <= 5) return steps[MAX(1, working) - 1];
    CGFloat heart = MIN(1, (working - 5) / 15.0);
    return (Breath){1.5 + (0.8 - 1.5) * heart, .075 + (.08 - .075) * heart, .40, .92, heart};
}

static CGFloat EaseBoth(CGFloat x) {
    return (1 - cos(M_PI * MAX(0, MIN(1, x)))) / 2;
}

// A beat of the heart `along` a breath: up to `size` from `start` to `peak`, and down by `end`.
static CGFloat Beat(CGFloat along, CGFloat start, CGFloat peak, CGFloat end, CGFloat size) {
    if (along < start || along > end) return 0;
    CGFloat rise = EaseBoth((along - start) / (peak - start)), fall = 1 - EaseBoth((along - peak) / (end - peak));
    return size * (along < peak ? rise : fall);
}

// How full the glass is `along` a breath, from 0 to 1: a cat's breath (in, slowing as it fills; out, eased; still),
// blended as far as `breath.heart` with a heartbeat (a beat, a smaller one, and a rest).
static CGFloat BreathLevel(Breath breath, CGFloat along) {
    CGFloat lungs = along < breath.in ? sin(M_PI / 2 * along / breath.in)
                  : along < breath.out ? 1 - EaseBoth((along - breath.in) / (breath.out - breath.in)) : 0;
    CGFloat heart = Beat(along, 0, .09, .22, 1) + Beat(along, .22, .31, .46, .625);
    return (1 - breath.heart) * lungs + breath.heart * heart;
}

@implementation PanelWindow

- (instancetype)initWithPage:(Page *)page {
    if (!(self = [super init])) return nil;
    self.page = page;
    self.glassObservers = [NSMutableArray array];
    self.catAt = kCatAt;
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
    glass.maskImage = RoundedMask(kCorner);
    glass.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [root addSubview:glass];
    self.glass = glass;
    NSView *clip = [[NSView alloc] initWithFrame:root.bounds];
    clip.wantsLayer = YES;
    clip.layer.masksToBounds = YES;
    clip.layer.cornerRadius = kCorner;
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
    tint.layer.cornerRadius = kCorner;
    tint.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [glass addSubview:tint];
    self.tint = tint;

    // While the folded cat's tags are out, the window's own shadow would outline the cat and the tags as one shape, the
    // tags' soft shadows joining them up; so the window has none then, and the glass this one of its own.
    NSView *catShadow = [[NSView alloc] initWithFrame:NSZeroRect];
    catShadow.wantsLayer = YES;
    catShadow.layer.shadowColor = NSColor.blackColor.CGColor;
    catShadow.layer.shadowOpacity = 0.38;
    catShadow.layer.shadowRadius = 9;
    catShadow.layer.shadowOffset = CGSizeMake(0, -6);
    catShadow.hidden = YES;
    [root addSubview:catShadow positioned:NSWindowBelow relativeTo:glass];
    self.catShadow = catShadow;

    // The clip rounds the page with the panel's corners, so what it draws up to its edges (the usage strip's vine)
    // meets them.
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
            [weakSelf tellGlass:[weakSelf glassOnScreen] over:0];
        };
    }
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
        [weakSelf.page keyboardGone];
    }];
    [root addSubview:strip];
    [root addSubview:readerStrip];
    self.strip = strip;
    self.readerStrip = readerStrip;

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
    self.panel.alphaValue = 0;
    [self.panel orderFrontRegardless];
    [self tellGlass:[self glassOnScreen] over:0];
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
    // Folded, the cat goes where the name's o is in the panel put back there.
    if (self.folded) frame.size = NSMakeSize(kWidth, self.openHeight ?: 200);
    frame.origin = NSMakePoint(NSMaxX(screen) - frame.size.width - 16, NSMaxY(screen) - frame.size.height - 16);
    if (self.folded) frame = [self foldedFrameFrom:frame];
    [self.panel setFrame:frame display:YES];
    if (self.folded) [self placeAtOnce];
    [self.panel saveFrameUsingName:@"Whozmove"];
    [self.panel orderFrontRegardless];
    [self updateRoom];
    [self tellGlass:[self glassOnScreen] over:0];
}

#pragma mark Size

// How tall the panel can grow from where its top edge is: down to the bottom of the screen. The page keeps itself to
// that (its list gives way and scrolls), so the panel never runs off the screen; within it, the page keeps its header
// and list to 640pt, and what opens under the list or the header comes on top of that (panel/styles/base.css).
- (void)updateRoom {
    if (self.expanded || self.folded) return;
    CGFloat room = [self roomFor:self.panel.frame];
    if (room == self.room || !self.page.ready) return;
    self.room = room;
    [self.page setRoom:room];
}

- (CGFloat)roomFor:(NSRect)frame {
    NSRect screen = (self.panel.screen ?: NSScreen.mainScreen).visibleFrame;
    return floor(MAX(kHeaderHeight + 80, NSMaxY(frame) - NSMinY(screen)));
}

- (void)resendRoom {
    self.room = 0;
    // A page loaded afresh hasn't heard which way the folded cat's tags go either.
    self.toldSide = nil;
    [self updateRoom];
}

- (void)fitHeight:(CGFloat)height {
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
    if (self.folded) return;  // the reader opens from a row, and there are none to see while it's folded
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

// Where the top-left corner of the page's list (#root) is on the screen: the panel's (the list's, which stays put while
// the reader is open); folded, catAt from the glass's middle, as the page draws the cat at the name's o (cat.js), so as
// the panel folds round it, and once it has, the page stays where it was.
- (NSPoint)rootAt {
    if (self.holdsPage) return self.pageAt;
    if (self.folded) return [self rootAround:[self catBoxIn:self.panel.frame]];
    return NSMakePoint(self.expanded ? NSMinX(self.listFrame) : NSMinX(self.panel.frame), NSMaxY(self.panel.frame));
}

// Where the page's list's top-left corner is while the cat's square is `box`: catAt from the glass's middle.
- (NSPoint)rootAround:(NSRect)box {
    return NSMakePoint(NSMidX(box) - self.catAt.x, NSMidY(box) + self.catAt.y);
}

// Where the page's left edge is on the screen: kReaderRoom left of the list.
- (CGFloat)pageLeft {
    return [self rootAt].x - kReaderRoom;
}

// The page's frame in the clip, which is `local` in a window that's `frame` on the screen: its list where rootAt says,
// and as tall as from there to the window's bottom. Folded, and while it folds or opens, it's at least as tall as the
// open panel, past the window's bottom: so it's laid out at the one size all the way, and opening shows more of it
// rather than having WebKit lay it out and draw it again as the cat starts to shrink.
- (NSRect)pageFrameIn:(NSRect)frame clip:(NSRect)local {
    NSPoint at = [self rootAt];
    CGFloat tall = at.y - NSMinY(frame);
    if (self.folded || self.holdsPage) tall = MAX(tall, self.openHeight ?: 200);
    return NSMakeRect(at.x - kReaderRoom - NSMinX(frame) - NSMinX(local), at.y - tall - NSMinY(frame) - NSMinY(local),
                      kPageWidth, tall);
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
    NSRect local = [self inWindow:clip];
    self.glass.frame = [self inWindow:glass];
    self.clip.frame = local;
    self.page.view.frame = [self pageFrameIn:frame clip:local];
    [CATransaction commit];
    [self.panel invalidateShadow];
    [self tellGlass:glass over:0];
    [self.page afterPaint:then];
}

// The glass and the page's clip move to `target` (on the screen) within the window, the page staying put; the
// window's shadow follows them.
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
    NSPoint pageTo = NSMakePoint(at.x - kReaderRoom, at.y - NSHeight(self.page.view.frame));
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
        [me.panel invalidateShadow];
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
// glass is the round one in the cat's square, and the clip the circle round it, or the whole window while the tags are
// out.
- (void)settle {
    NSView *root = self.panel.contentView;
    self.holdsPage = NO;
    if (self.folded) {
        self.glass.frame = [self inWindow:[self foldedGlassIn:self.panel.frame]];
        [self roundGlass:kFoldGlass / 2];
        self.clip.layer.cornerRadius = self.fanOpen ? 0 : kFoldBox / 2;
    } else {
        self.fanOpen = NO;
    }
    [self shadeForFan];
    // Back to the cat's corner from the tags' room, which was never saved, it's saved as itself again.
    if (!self.fanOpen && !self.expanded && !self.panel.frameAutosaveName.length) {
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
    [self placeStrips];
    root.autoresizesSubviews = YES;
    self.clip.autoresizesSubviews = YES;
    self.reshaping = NO;
    [self.panel invalidateShadow];
    [self tellGlass:[self glassOnScreen] over:0];
    // Folded again while sessions still work, the glass breathes again.
    [self startBreathing];
}

// The drag strips over the headers' empty parts: the list's, up to its buttons; and while the reader is open, the
// reader's, up to its ✕.
- (void)placeStrips {
    NSRect bounds = self.panel.contentView.bounds;
    CGFloat top = NSHeight(bounds) - kHeaderHeight;
    // Folded, the cat's corner is dragged by, and a click on it opens the panel; the tags' room below it is the page's.
    if (self.folded) {
        self.strip.frame = [self inWindow:[self catBoxIn:self.panel.frame]];
        self.strip.hidden = NO;
        self.readerStrip.hidden = YES;
        return;
    }
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

#pragma mark Folding into the cat

// Where the glass is on the screen: the round one in the middle of the folded window, or the whole panel.
- (NSRect)glassOnScreen {
    return self.folded ? [self foldedGlassIn:self.panel.frame] : self.panel.frame;
}

// While the folded cat's tags are out, the window has no shadow of its own (it would outline the cat and the tags as
// one shape) and the glass has its own instead; otherwise the window's, as ever.
- (void)shadeForFan {
    BOOL fan = self.folded && (self.fanOpen || self.breathing);
    self.catShadow.hidden = !fan;
    if (fan) {
        self.catShadow.frame = self.glass.frame;
        CGPathRef circle = CGPathCreateWithEllipseInRect(self.catShadow.bounds, NULL);
        self.catShadow.layer.shadowPath = circle;
        CGPathRelease(circle);
    }
    if (self.panel.hasShadow == fan) self.panel.hasShadow = !fan;
    [self.panel invalidateShadow];
}

// The folded glass in a window that's `frame`: round, in the middle of the cat's square, whatever room the tags have
// below and beside it.
- (NSRect)foldedGlassIn:(NSRect)frame {
    CGFloat inset = (kFoldBox - kFoldGlass) / 2;
    return NSInsetRect([self catBoxIn:frame], inset, inset);
}

// The cat's square (kFoldBox) in a folded window that's `frame`: its top-right corner, or its top-left while the tags
// are out to the right.
- (NSRect)catBoxIn:(NSRect)frame {
    CGFloat left = self.fanOpen && self.fanRight ? NSMinX(frame) : NSMaxX(frame) - kFoldBox;
    return NSMakeRect(left, NSMaxY(frame) - kFoldBox, kFoldBox, kFoldBox);
}

// The glass's corners: its mask's, which doesn't reach its subviews, and the tint's.
- (void)roundGlass:(CGFloat)radius {
    if (radius == self.glassRadius && self.glass.maskImage) return;
    self.glassRadius = radius;
    self.glass.maskImage = RoundedMask(radius);
    self.tint.layer.cornerRadius = radius;
}

// The folded window: the cat's square, round the name's o in the open panel's header, so the cat stays where it is as
// the panel folds round it.
- (NSRect)foldedFrameFrom:(NSRect)open {
    return NSMakeRect(NSMinX(open) + self.catAt.x - kFoldBox / 2, NSMaxY(open) - self.catAt.y - kFoldBox / 2, kFoldBox,
                      kFoldBox);
}

// The open panel, from the cat's square: its name's o on the cat, as tall as it was when it folded (the page then says
// how tall it needs to be), and moved in if it would run off the screen.
- (NSRect)openFrameFrom:(NSRect)box {
    NSRect visible = (self.panel.screen ?: NSScreen.mainScreen).visibleFrame;
    CGFloat top = MIN(NSMidY(box) + self.catAt.y, NSMaxY(visible));
    CGFloat room = MAX(kHeaderHeight + 80, top - NSMinY(visible));
    CGFloat tall = floor(MAX(kHeaderHeight, MIN(self.openHeight ?: 200, room)));
    CGFloat left = MAX(MIN(NSMidX(box) - self.catAt.x, NSMaxX(visible) - kWidth), NSMinX(visible));
    return NSMakeRect(left, top - tall, kWidth, tall);
}

// Where the page measured the name's o, from the list's top-left corner (cat.js). Folded, the page moves to put it on
// the glass, which stays where it is. It's kept in whole points, so the cat's square and the open panel, each found
// from the other, are on whole points too: macOS puts a window on whole points, and a fraction rounded away at each
// fold and opening would walk the panel down the screen.
- (void)catAt:(NSPoint)at {
    at = NSMakePoint(round(at.x), round(at.y));
    if (NSEqualPoints(at, self.catAt)) return;
    self.catAt = at;
    if (self.folded && !self.reshaping) [self settle];
}

// The page says the panel folds into the cat, or opens out of it (panel.js): moving, or at once as it loads. Not while
// the reader is open (the page doesn't fold then). Asked again while it's moving, the newest is taken once it's done.
- (void)fold:(BOOL)on instant:(BOOL)instant {
    if (self.expanded) return;
    [NSUserDefaults.standardUserDefaults setBool:on forKey:kFoldedKey];
    if (self.reshaping) {
        self.pendingFold = @(on);
        return;
    }
    BOOL changed = on != self.folded;
    self.folded = on;
    if (!on) [self stopBreathing];
    if (!changed || instant) {
        [self placeAtOnce];
        return;
    }
    if (on) self.openHeight = NSHeight(self.panel.frame);
    [self foldMoving];
}

// The cat's tags come out (cat.js): the folded window takes in the room they need under and beside the cat, the cat's
// square, and so the glass, staying put; the page is laid out again at the new height, showing nothing new but the
// tags. Once they've gone, the window is the cat's corner again. Asked while the panel folds or opens, it's done once
// that's over. They go the way the page was told (tellCatSide), as it laid them out that way. While they're out the
// window's frame isn't saved: the panel comes back next time as the cat alone.
- (void)catFan:(BOOL)on width:(CGFloat)width height:(CGFloat)height {
    if (!self.folded) return;
    if (self.reshaping) {
        self.pendingFan = @{@"on": @(on), @"width": @(width), @"height": @(height)};
        return;
    }
    if (!on && !self.fanOpen) return;
    NSRect box = [self catBoxIn:self.panel.frame];
    NSRect visible = (self.panel.screen ?: NSScreen.mainScreen).visibleFrame;
    if (on) self.fanRight = self.toldSide.boolValue;
    CGFloat w = on ? MAX(kFoldBox, ceil(width)) : kFoldBox;
    CGFloat h = on ? MIN(MAX(kFoldBox, ceil(height)), NSMaxY(box) - NSMinY(visible)) : kFoldBox;
    NSRect target = on && self.fanRight ? NSMakeRect(NSMinX(box), NSMaxY(box) - h, w, h)
                                        : NSMakeRect(NSMaxX(box) - w, NSMaxY(box) - h, w, h);
    if (NSEqualRects(target, self.panel.frame) && on == self.fanOpen) return;
    if (on && !self.fanOpen) {
        [self.panel saveFrameUsingName:@"Whozmove"];
        self.panel.frameAutosaveName = @"";
    }
    self.fanOpen = on;
    // Changing shape until the page has drawn it there: a fold asked for meanwhile waits for it.
    self.reshaping = YES;
    __weak typeof(self) weakSelf = self;
    [self setWindowFrame:target glass:[self foldedGlassIn:target] clip:target then:^{
        [weakSelf settle];
        [weakSelf takePending];
    }];
}

// What was asked for while the panel was changing shape, once it's done: a fold or an opening first (the tags' room
// then goes with it), else the tags' room.
- (void)takePending {
    NSNumber *fold = self.pendingFold;
    NSDictionary *fan = self.pendingFan;
    self.pendingFold = nil;
    self.pendingFan = nil;
    if (fold && fold.boolValue != self.folded) [self fold:fold.boolValue instant:NO];
    else if (fan)
        [self catFan:[fan[@"on"] boolValue] width:[fan[@"width"] doubleValue] height:[fan[@"height"] doubleValue]];
}

// While sessions work, the folded glass breathes as a cat does (the page says how many, cat.js): a breath in, quicker,
// a breath out, slower, and a pause; about 20 a minute with one at work, quicker and a little deeper with each more up
// to 5, and from there turning little by little into a soft double heartbeat, all of it by 20. Only the glass moves,
// about its middle, the cat on it staying still. Core Animation plays each breath, so it's smooth and costs the app
// nothing meanwhile; the next is shaped for how many are working then, so the rhythm changes only between breaths, and
// once none are, it finishes the breath it's in and rests. Only while folded, and not with reduced motion.
- (void)catBreathe:(NSInteger)working {
    self.breathWorking = MAX(0, working);
    [self startBreathing];
}

- (void)startBreathing {
    if (self.breathing || self.breathWorking == 0 || !self.folded
        || NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion)
        return;
    self.breathing = YES;
    [self shadeForFan];
    [self breathe:++self.breathRun];
}

// One breath, for how many are working now, and then the next while some still are.
- (void)breathe:(NSUInteger)run {
    if (run != self.breathRun) return;
    if (self.breathWorking == 0 || !self.folded || NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
        [self stopBreathing];
        return;
    }
    Breath breath = BreathFor(self.breathWorking);
    // The glass's own shadow breathes with it.
    for (NSView *view in @[self.glass, self.catShadow])
        [view.layer addAnimation:[self breath:breath of:view.layer] forKey:@"breath"];
    __weak typeof(self) weakSelf = self;
    dispatch_time_t next = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(breath.seconds * NSEC_PER_SEC));
    dispatch_after(next, dispatch_get_main_queue(), ^{ [weakSelf breathe:run]; });
}

// A breath for `layer`: wider about its middle, as far along as the breath has it, sampled finely enough to be smooth.
- (CAKeyframeAnimation *)breath:(Breath)breath of:(CALayer *)layer {
    CGSize size = layer.bounds.size;
    CGPoint anchor = layer.anchorPoint;
    NSMutableArray *values = [NSMutableArray array], *times = [NSMutableArray array];
    const int samples = 72;
    for (int i = 0; i <= samples; i++) {
        CGFloat along = (CGFloat)i / samples, scale = 1 + breath.depth * BreathLevel(breath, along);
        CATransform3D grow = CATransform3DConcat(CATransform3DMakeScale(scale, scale, 1),
            CATransform3DMakeTranslation((0.5 - anchor.x) * size.width * (1 - scale),
                                         (0.5 - anchor.y) * size.height * (1 - scale), 0));
        [values addObject:[NSValue valueWithCATransform3D:grow]];
        [times addObject:@(along)];
    }
    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"transform"];
    animation.values = values;
    animation.keyTimes = times;
    animation.duration = breath.seconds;
    return animation;
}

// No more breaths: between them, the glass is already at its size; opening, it goes to it at once.
- (void)stopBreathing {
    self.breathRun++;
    if (!self.breathing) return;
    self.breathing = NO;
    for (NSView *view in @[self.glass, self.catShadow]) [view.layer removeAnimationForKey:@"breath"];
    [self shadeForFan];
}

// The panel as it is now, folded or open, with nothing moving: at launch, from the frame saved last, either way.
- (void)placeAtOnce {
    NSRect frame = self.panel.frame;
    BOOL round = fabs(NSWidth(frame) - kWidth) > 1;
    self.fanOpen = NO;
    self.pendingFan = nil;
    if (self.folded && !round) {
        self.openHeight = NSHeight(frame);
        [self.panel setFrame:[self foldedFrameFrom:frame] display:NO];
    } else if (self.folded && !NSEqualSizes(frame.size, NSMakeSize(kFoldBox, kFoldBox))) {
        // Left with room for its tags (the app quit while they were out): just the cat's corner.
        [self.panel setFrame:[self foldedFrameFrom:frame] display:NO];
    } else if (!self.folded && round) {
        [self.panel setFrame:[self openFrameFrom:frame] display:NO];
    }
    [self settle];
    [self tellCatPointerGone];
    if (!self.folded) [self resendRoom];
}

// Folding: as the cat grows back from the name's o and the rest of the panel fades (cat.js), the glass closes in on the
// cat from every side at once, wider and taller together, its corners rounding off into the circle, while the cat stays
// where it is; then the window becomes the cat's square. Opening runs it backwards: the glass spreads out from behind
// the cat as the cat becomes the name's o. Only the edges move, as with the reader (reshapeTo:), so the page is drawn
// once. Where the open panel is moved in from the screen's edge, the page slides with the glass between the two places.
- (void)foldMoving {
    self.reshaping = YES;
    self.strip.hidden = self.readerStrip.hidden = YES;
    [self tellCatPointerGone];
    CGFloat inset = (kFoldBox - kFoldGlass) / 2;
    NSRect from = self.panel.frame;
    __weak typeof(self) weakSelf = self;
    void (^finish)(void) = ^{
        [weakSelf settle];
        [weakSelf.panel saveFrameUsingName:@"Whozmove"];
        if (!weakSelf.folded) [weakSelf resendRoom];
        [weakSelf takePending];
    };
    if (self.folded) {
        NSRect box = [self foldedFrameFrom:from], glass = NSInsetRect(box, inset, inset);
        // The page starts where the open panel has it (it's marked folded already, so rootAt would take the open
        // panel's frame for the cat's square), and goes where the folded cat has it.
        self.pageAt = NSMakePoint(NSMinX(from), NSMaxY(from));
        self.holdsPage = YES;
        [self setWindowFrame:NSUnionRect(from, box) glass:from clip:from then:^{
            weakSelf.pageAt = [weakSelf rootAround:box];
            [weakSelf moveGlassTo:glass clip:glass corner:kFoldGlass / 2 glassCorner:kFoldGlass / 2 over:kSpread
                           easing:kFoldEasing then:^{
                [weakSelf setWindowFrame:box glass:glass clip:box then:finish];
            }];
        }];
    } else {
        NSRect box = [self catBoxIn:from], glass = [self foldedGlassIn:from];
        BOOL tagsOut = self.fanOpen;
        // The page starts where the folded cat has it (the panel is marked open already, so rootAt would take the
        // cat's square for the open panel), and goes where the open panel has it.
        self.pageAt = [self rootAround:box];
        self.holdsPage = YES;
        self.fanOpen = NO;
        [self shadeForFan];
        NSRect open = [self openFrameFrom:box];
        // While the tags are out, the page's clip keeps them in as they fade (cat.css), until the glass starts.
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self.clip.layer.cornerRadius = tagsOut ? 0 : kFoldGlass / 2;
        [CATransaction commit];
        [self setWindowFrame:NSUnionRect(open, from) glass:glass clip:tagsOut ? from : glass then:^{
            // The cat shrinks into the name's o as the glass spreads out from behind it, starting together.
            [weakSelf.page catGlass:^{
                if (tagsOut) [weakSelf clipTo:glass corner:kFoldGlass / 2];
                weakSelf.pageAt = NSMakePoint(NSMinX(open), NSMaxY(open));
                [weakSelf moveGlassTo:open clip:open corner:kCorner glassCorner:kCorner over:kSpread
                               easing:kFoldEasing then:^{
                    if (NSEqualRects(NSUnionRect(open, from), open)) finish();
                    else [weakSelf setWindowFrame:open showing:open then:finish];
                }];
            }];
        }];
    }
}

// The page's clip, at once, to `clip` (on the screen) with corners `corner`, the page staying put on the screen.
- (void)clipTo:(NSRect)clip corner:(CGFloat)corner {
    NSPoint window = self.panel.frame.origin;
    NSPoint page = NSMakePoint(window.x + NSMinX(self.clip.frame) + NSMinX(self.page.view.frame),
                               window.y + NSMinY(self.clip.frame) + NSMinY(self.page.view.frame));
    NSRect local = [self inWindow:clip];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.clip.frame = local;
    self.clip.layer.cornerRadius = corner;
    [self.page.view setFrameOrigin:NSMakePoint(page.x - window.x - NSMinX(local), page.y - window.y - NSMinY(local))];
    [CATransaction commit];
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
    NSPoint at = NSMakePoint(point.x + [self pageLeft] - NSMinX(self.panel.frame),
                             [self rootAt].y - NSMinY(self.panel.frame) - point.y);
    [menu popUpMenuPositioningItem:nil atLocation:at inView:view];
    // The pointer isn't looked at while the menu is up: it's taken to be where the menu closed, so it hasn't left the
    // panel until it moves on from there (pollPointer).
    self.lastScreen = NSEvent.mouseLocation;
}

#pragma mark Hover

// Hover follows the pointer's position, polled, not mouse events: the panel is almost never the key window of an
// active app, so WebKit gets no mouse moves, and macOS delivers mouseMoved: to such windows unreliably (often
// only entered and exited). Polling sees every position either way.
- (void)pollPointer {
    NSPoint screen = NSEvent.mouseLocation;
    BOOL moved = !NSEqualPoints(screen, self.lastScreen);
    self.lastScreen = screen;
    if (self.panel.isVisible)
        for (void (^observer)(NSPoint) in self.pointerObservers) observer(screen);
    NSRect frame = self.panel.frame;
    if (self.folded && !self.reshaping) {
        [self tellCatPointer:screen];
        [self tellCatSide];
    }
    BOOL inside = self.panel.isVisible && NSPointInRect(screen, frame);
    // Off the panel without moving, its edge moved past the pointer (a card folding away) or one of its menus closed
    // where the pointer picked from it: the page is told it's still there, and again once it moves.
    if (!inside) {
        if (self.hovering) {
            self.hovering = NO;
            self.leftStill = !moved;
            [self.page hoverEnd:self.leftStill];
        } else if (self.leftStill && moved) {
            self.leftStill = NO;
            [self.page hoverEnd:NO];
        }
        return;
    }
    self.leftStill = NO;
    // The page's top is its list's (rootAt), and its left edge pageLeft.
    NSPoint page = NSMakePoint(round(screen.x - [self pageLeft]), round([self rootAt].y - screen.y));
    if (self.hovering && NSEqualPoints(page, self.lastHover)) return;
    self.hovering = YES;
    self.lastHover = page;
    [self.page hoverAt:page];
}

// Looks at the pointer this often from now on (pollPointer).
- (void)pollPointerEvery:(NSTimeInterval)every {
    if (self.pointerTimer && fabs(self.pointerTimer.timeInterval - every) < 0.001) return;
    [self.pointerTimer invalidate];
    self.pointerTimer = [NSTimer scheduledTimerWithTimeInterval:every target:self selector:@selector(pollPointer)
                                                       userInfo:nil repeats:YES];
    self.pointerTimer.tolerance = every / 4;
}

// The folded cat's eyes follow the pointer while it's near (cat.js): the page is told where it is from the glass's
// centre, in points, its y running down, as it moves, and once that it has gone. Meanwhile the pointer is looked at
// more often.
- (void)tellCatPointer:(NSPoint)screen {
    NSRect glass = [self glassOnScreen];
    CGFloat dx = screen.x - NSMidX(glass), dy = NSMidY(glass) - screen.y;
    if (self.panel.isVisible && hypot(dx, dy) < kCatSees) {
        BOOL same = fabs(dx - self.lastCatPointer.x) < 0.5 && fabs(dy - self.lastCatPointer.y) < 0.5;
        if (self.catSeesPointer && same) return;
        if (!self.catSeesPointer) [self pollPointerEvery:kPointerEveryWatched];
        self.catSeesPointer = YES;
        self.lastCatPointer = NSMakePoint(dx, dy);
        [self.page catPointer:NSMakePoint(dx, dy)];
    } else {
        [self tellCatPointerGone];
    }
}

// Which way the tags go, as the page should lay them out before they come: told whenever it changes, as the cat is
// dragged across the screen's middle.
- (BOOL)catOnLeftHalf:(NSRect)box {
    NSRect visible = (self.panel.screen ?: NSScreen.mainScreen).visibleFrame;
    return NSMidX(box) < NSMidX(visible);
}

- (void)tellCatSide {
    if (self.fanOpen || !self.page.ready) return;
    BOOL right = [self catOnLeftHalf:[self catBoxIn:self.panel.frame]];
    if (self.toldSide && self.toldSide.boolValue == right) return;
    self.toldSide = @(right);
    [self.page catSide:right];
}

- (void)tellCatPointerGone {
    if (!self.catSeesPointer) return;
    self.catSeesPointer = NO;
    [self pollPointerEvery:kPointerEvery];
    [self.page catPointerGone];
}

@end
