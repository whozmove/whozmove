// PanelWindow: the floating glass window, its drag strip, its size, and the pointer over it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "PanelWindow.h"
#import "Page.h"
#import "Appearance.h"
#import "Browser.h"
#import "EdgeIcon.h"
#import "Easing.h"
#import <QuartzCore/QuartzCore.h>

// The panel's width; its header's height (--header in panel/styles/tokens.css) and the buttons at the header's right
// end, which the drag strip leaves to the page.
static const CGFloat kWidth = 340, kHeaderHeight = 46, kButtonsWidth = 104;
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
// The panel's shadow is its own, in a window held under the panel (shadeGlass), with this much room round the glass.
static const CGFloat kShadeRoom = 80;
// Turning over (turnOver:then:) takes kTurn. It's seen from kTurnDepth away, the prototype's perspective, and its edge
// is kEdge thick, kEdgeInset in from the glass's top and bottom, where its corners round off.
static const NSTimeInterval kTurn = 0.7;
static const CGFloat kTurnDepth = 1100, kEdge = 6, kEdgeInset = 12;
// Turned over, the back's header leaves its left end to its page, for the ‹ back to its apps; the drag strip covers the
// rest, up to its buttons, as on the list's.
static const CGFloat kBackLead = 44;
// A sideways swipe: how far the fingers go before it's taken to be sideways or not, how far the panel leans with them
// at most, how fast they must be going as they lift for a flick (points a second), and how long the panel takes to go
// off the screen's edge, and to come back, at least and at most.
static const CGFloat kSwipeDecide = 6, kLeanMost = 20, kFlickSpeed = 800;
static const NSTimeInterval kParkLeast = 0.25, kParkMost = 0.7, kUnpark = 0.45;

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

// A window that can't be seen, which takes the keyboard from the panel and goes at once (giveBackKeyboard).
@interface HandOffPanel : NSPanel
@end

@implementation HandOffPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

// Transparent strip over the header: drag moves the panel, a plain click is handed to the page.
@interface DragStrip : NSView
@property (copy) void (^onClick)(void);
@property (copy) BOOL (^onDrag)(NSPoint by);  // each step of a drag (PanelWindow's dragBy:): NO if it can't move now
@property (copy) void (^onDragged)(void);     // the drag is over (draggedByHand)
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
    if (!self.onDrag(NSMakePoint(now.x - _start.x, now.y - _start.y))) return;
    _dragged = YES;
    _start = now;
}
- (void)mouseUp:(NSEvent *)event {
    if (!_dragged && self.onClick) self.onClick();
    if (_dragged) self.onDragged();
}
@end

// A side of the panel: the page's clip, or the panel's back (holdBack:). The side turned away from you takes no
// clicks, and while the panel turns, neither does.
@interface SideView : NSView
@property (assign) BOOL away;
@end

@implementation SideView
- (NSView *)hitTest:(NSPoint)point { return self.away ? nil : [super hitTest:point]; }
@end

// What modules hold over the page (hold:overPage:) is in this, laid over the page in its clip and kept where the page
// is: everything that moves the page (the panel growing, folding, turning over) moves it too, and the clip cuts it at
// the panel's rounded edges. Its y runs down from the page's top, as the page's own does. It takes no clicks itself,
// only those on what's in it, so the page under it gets the rest. It's beside the page rather than in it, so keys and
// scrolls a site in it doesn't use never reach the panel's page.
@interface PageCover : NSView
@end

@implementation PageCover
- (BOOL)isFlipped { return YES; }

- (NSView *)hitTest:(NSPoint)point {
    NSView *hit = [super hitTest:point];
    return hit == self ? nil : hit;
}
@end

// The tint over the glass, which makes the panel its look (the Look menu, app/core/MenuBar.m): grey or black, solid,
// in the page's own colour for it (--panel in panel/styles/tokens.css), or glass. On the dark panel, glass is the HUD's
// dark glass, darkened; on the light one, a popover's light glass, lightened, and black is white. It has no edge of its
// own, only the panel's shadow. It's painted again whenever the panel turns light or dark, with the Mac or from the
// Look menu, light or dark as the window is: the glass gives what's in it a look of its own, which may stay dark.
@interface Tint : NSView
@property (nonatomic, copy) NSString *look;
- (void)paint;
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

// What the panel's shadow is drawn in (shadeGlass), told when the app turns light or dark: the shadow is softer on the
// light panel.
@interface ShadeView : NSView
@property (copy) void (^onLook)(void);
@end

@implementation ShadeView
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    if (self.onLook) self.onLook();
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
// The keyboard: a site's in the panel (Browser) since a click into it, or a box of the page's since it asked; the site
// the pointer was last passed to; and what watches clicks for the keyboard.
@property (assign) BOOL browserKeys;
@property (weak) Browser *keyboardBrowser;
@property (assign) BOOL pageKeys;
@property (weak) Browser *pointedBrowser;
@property (strong) id clickWatch;
// A sideways swipe on the panel (swiped:): whether it's allowed, whether it has been taken to be sideways or not and
// is the panel's, how far the fingers have gone, how fast they were going, and when the last part of it came; and
// where the panel was as it started.
@property (strong) id swipeWatch;
@property (assign) BOOL swipeAllowed, swipeDecided, swipeMine;
@property (assign) BOOL foldedSwipe;    // a swipe on the folded cat, moving it (swipedFolded:), and its momentum
@property (assign) NSPoint foldedFrom, foldedTotal;  // where the folded glass started, and how far the swipe has gone
@property (assign) CGFloat swipeX, swipeY, swipeSpeed;
@property (assign) NSTimeInterval swipeAt;
@property (assign) NSPoint swipeFrom;
@property (assign) CGFloat swipeTop;
// Pushed off the screen's edge (parked), on its way (parkTimer), where it was before and the room on the screen it went
// from (the screen it's on once it has gone may be another), and who hears it has gone.
@property (assign) BOOL parked;
@property (strong) NSTimer *parkTimer;
@property (assign) NSPoint parkedFrom;
@property (assign) CGFloat parkedTop;
@property (assign) NSRect parkScreen;
@property (strong) NSMutableArray *awayObservers;
@property (strong) NSPanel *handOff;  // the keyboard's way back to the app in front (giveBackKeyboard)
@property (assign) BOOL expanded;       // grown to the screen for the reader
@property (assign) NSRect listFrame;    // where the panel was before it grew, to fold back to
@property (assign) BOOL listOnRight;    // the reader opened to the list's left
// The panel's shape, apart from the window's: the glass and the page's clip (rounded, over it) normally fill the
// window, and while the panel changes size they show only part of it (reshapeTo:).
@property (strong) NSVisualEffectView *glass;
@property (strong) Tint *tint;
// The panel's shadow (shadeGlass): the window held under the panel, and in it the shadow, where the glass is.
@property (strong) NSPanel *shade;
@property (strong) CALayer *shadow;
@property (strong) SideView *clip;
// The panel's other side (holdBack:), and the edge that shows between the two while it turns (turnOver:then:).
@property (strong) SideView *back;
@property (strong) NSView *edge;
@property (strong) CAGradientLayer *edgeShade;
// Turned over, or on the way to or from it; turning; a turn asked for meanwhile, and what to do after it, taken next;
// the height the page asked for meanwhile; and who's told as it turns over and once it's back.
@property (assign) BOOL turned;
@property (assign) BOOL turning;
@property (strong) NSNumber *pendingTurn;
@property (copy) void (^pendingTurnThen)(void);
@property (assign) CGFloat heightAsked;
@property (assign) NSRect turnFrame;    // where the panel is as it turns, the window having taken in room round it
@property (strong) NSMutableArray *turnObservers;
@property (assign) BOOL reshaping;
@property (strong) NSMutableArray *stillWaiters;  // run once the panel has stopped changing size (whenStill:)
@property (strong) PageCover *cover;    // what modules hold over the page (hold:overPage:), made with the first
@property (assign) BOOL hasPending;     // a size asked for while the panel was changing size, taken next
@property (assign) NSRect pendingFrame;
@property (copy) void (^pendingDone)(void);
// Moving the glass, the clip and the page together, a step at a time (moveGlassTo:).
@property (strong) NSTimer *moveTimer;
// Who follows the glass and the pointer (followGlass:, followPointer:), and the side the icons at its edge are on.
@property (strong) NSMutableArray *glassObservers, *pointerObservers;
// How much of the header shows as it slides away with the list (headerShowing:gone:), and who hears it has gone; who
// hears the panel fold and open, and its look change.
@property (assign) CGFloat headerPoints;
@property (assign) BOOL headerGone;
@property (strong) NSMutableArray *headerObservers, *foldObservers, *lookObservers;
@property (copy) NSString *edgeSide;
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
// The rectangle `along` of the way from `a` to `b`.
static NSRect Between(NSRect a, NSRect b, CGFloat along) {
    return NSMakeRect(NSMinX(a) + (NSMinX(b) - NSMinX(a)) * along, NSMinY(a) + (NSMinY(b) - NSMinY(a)) * along,
                      NSWidth(a) + (NSWidth(b) - NSWidth(a)) * along,
                      NSHeight(a) + (NSHeight(b) - NSHeight(a)) * along);
}

// Turning over: gentle at both ends and quickest where the panel is edge-on, as the prototype's.
static CGFloat TurnEased(CGFloat x) {
    x = MAX(0, MIN(1, x));
    return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2;
}

// Where a view's layer has its anchor point, in its superview's coordinates, which its layer's transform turns about.
static CGPoint AnchorOf(NSView *view) {
    CGPoint anchor = view.layer.anchorPoint;
    NSRect frame = view.frame;
    return CGPointMake(NSMinX(frame) + anchor.x * NSWidth(frame), NSMinY(frame) + anchor.y * NSHeight(frame));
}

// The turn by `angle` about the upright line through `middle`, seen from kTurnDepth away, as a layer's transform for a
// layer whose anchor point is at `anchor`, after `own` (its own turn about its own `centre`; identity for none).
static CATransform3D TurnAbout(CGPoint middle, CGPoint anchor, CGFloat angle, CATransform3D own, CGPoint centre) {
    CATransform3D eye = CATransform3DIdentity;
    eye.m34 = -1 / kTurnDepth;
    CATransform3D turn = CATransform3DConcat(CATransform3DMakeRotation(angle, 0, 1, 0), eye);
    CATransform3D m = CATransform3DMakeTranslation(anchor.x - centre.x, anchor.y - centre.y, 0);
    m = CATransform3DConcat(m, own);
    m = CATransform3DConcat(m, CATransform3DMakeTranslation(centre.x - middle.x, centre.y - middle.y, 0));
    m = CATransform3DConcat(m, turn);
    return CATransform3DConcat(m, CATransform3DMakeTranslation(middle.x - anchor.x, middle.y - anchor.y, 0));
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

// Whether a view is in sight in a window: in it, not hidden, and with some of it showing.
static BOOL Shows(NSView *view, NSWindow *window) {
    return view && view.window == window && !view.isHiddenOrHasHiddenAncestor && !NSIsEmptyRect(view.visibleRect);
}

// WebKit hears of the pointer through its view's own tracking area, never the view's mouseMoved:, so a move passed in
// goes to that area's owner, as macOS would send it there.
static void PassPointer(NSView *view, NSEventType type, NSPoint at) {
    NSWindow *window = view.window;
    if (!window) return;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    NSEvent *event = type == NSEventTypeMouseMoved
        ? [NSEvent mouseEventWithType:type location:at modifierFlags:NSEvent.modifierFlags timestamp:now
                         windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:0 pressure:0]
        : [NSEvent enterExitEventWithType:type location:at modifierFlags:NSEvent.modifierFlags timestamp:now
                             windowNumber:window.windowNumber context:nil eventNumber:0 trackingNumber:0 userData:NULL];
    for (NSTrackingArea *area in view.trackingAreas) {
        id owner = area.owner;
        if (owner == view || !(area.options & NSTrackingMouseMoved)) continue;
        if (type == NSEventTypeMouseMoved && [owner respondsToSelector:@selector(mouseMoved:)])
            [owner mouseMoved:event];
        if (type == NSEventTypeMouseExited && [owner respondsToSelector:@selector(mouseExited:)])
            [owner mouseExited:event];
        return;
    }
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
    // follows the glass's edges as they move (reshapeTo:). Grey until the Look menu says otherwise.
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
    page.view.frame = NSMakeRect(-kReaderRoom, 0, kPageWidth, NSHeight(clip.bounds));
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
        if (event.window == weakSelf.panel) [weakSelf clickedAt:event.locationInWindow];
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
    else if (self.panel.isVisible) [self.panel orderOut:nil];
    else [self bringUp];
}

- (BOOL)shown {
    return self.panel.isVisible;
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
    [self.panel orderFrontRegardless];
    [self holdShade];
}

- (void)resetPosition {
    if (self.parked || self.parkTimer) [self backAtOnce];
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
    // A page loaded afresh hasn't heard which way the folded cat's tags go either, nor that the panel is turned over.
    self.toldSide = nil;
    [self updateRoom];
    if (self.turned) [self.page turned:YES];
}

- (void)fitHeight:(CGFloat)height {
    // Turned over, or on its way there or back, the panel keeps the size it turned at, so the back stays the list's size
    // as it was then rather than following the list out of sight: the height the list asks for meanwhile is taken once
    // the panel is back on its list side.
    if (self.turned || self.turning) {
        self.heightAsked = height;
        return;
    }
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

- (void)followFold:(void (^)(BOOL, BOOL))observer {
    [self.foldObservers addObject:observer];
}

- (void)tellFold:(BOOL)done {
    for (void (^observer)(BOOL, BOOL) in self.foldObservers) observer(self.folded, done);
}

- (void)followLook:(void (^)(void))observer {
    [self.lookObservers addObject:observer];
}

- (NSPoint)listCorner {
    return [self rootAt];
}

- (BOOL)dragBy:(NSPoint)by {
    if (self.reshaping) return NO;
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
    if (self.panel.frameAutosaveName.length) [self.panel saveFrameUsingName:self.panel.frameAutosaveName];
    [self updateRoom];
}

- (void)hold:(NSWindow *)window over:(BOOL)over {
    [self.panel removeChildWindow:window];
    [self.panel addChildWindow:window ordered:over ? NSWindowAbove : NSWindowBelow];
    if (!over && self.panel.isVisible) [self holdShade];
}

#pragma mark Flicked off the screen's edge

NSPoint FoldedMove(NSRect glass, NSPoint by, NSRect visible) {
    // How far it may go each way: up to the screen's edge, and nowhere further out where it's past that already.
    CGFloat left = MIN(0, NSMinX(visible) - NSMinX(glass)), right = MAX(0, NSMaxX(visible) - NSMaxX(glass));
    CGFloat down = MIN(0, NSMinY(visible) - NSMinY(glass)), up = MAX(0, NSMaxY(visible) - NSMaxY(glass));
    return NSMakePoint(MAX(left, MIN(right, by.x)), MAX(down, MIN(up, by.y)));
}

// Folded, a two-finger swipe on the cat, any way, moves it with the fingers, and as they lift it goes on with the
// trackpad's own momentum, as far as the swipe was quick, slowing to a stop: always within the screen, stopping at its
// edge. Its place is kept once the swipe, and then its momentum, has ended. Not while it's folding or opening.
- (NSEvent *)swipedFolded:(NSEvent *)event {
    if (event.phase == NSEventPhaseBegan || event.phase == NSEventPhaseMayBegin) {
        self.foldedFrom = [self foldedGlassIn:self.panel.frame].origin;
        self.foldedTotal = NSZeroPoint;
        return nil;
    }
    if (self.folded) {
        // Which way the fingers went, whichever way scrolling goes on this Mac; the screen's y runs up. The swipe's
        // total so far, kept within the screen from where the glass started, places it: macOS rounds a window's place,
        // so a fraction of a point added each time would be lost, and a turn back moves it at once.
        CGFloat way = event.isDirectionInvertedFromDevice ? 1 : -1;
        NSPoint total = NSMakePoint(self.foldedTotal.x + event.scrollingDeltaX * way,
                                    self.foldedTotal.y - event.scrollingDeltaY * way);
        NSRect visible = (self.panel.screen ?: NSScreen.mainScreen).visibleFrame;
        NSRect glass = [self foldedGlassIn:self.panel.frame];
        self.foldedTotal = total = FoldedMove((NSRect){self.foldedFrom, glass.size}, total, visible);
        NSPoint by = NSMakePoint(self.foldedFrom.x + total.x - NSMinX(glass),
                                 self.foldedFrom.y + total.y - NSMinY(glass));
        if (by.x || by.y) [self dragBy:by];  // not while it changes shape (dragBy:): the next step catches up
    }
    BOOL ends = event.momentumPhase == NSEventPhaseEnded || event.momentumPhase == NSEventPhaseCancelled
                || (event.momentumPhase == NSEventPhaseNone
                    && (event.phase == NSEventPhaseEnded || event.phase == NSEventPhaseCancelled));
    if (ends) [self draggedByHand];
    // A swipe with momentum to come stays the cat's until that has run out.
    if (event.momentumPhase == NSEventPhaseEnded || event.momentumPhase == NSEventPhaseCancelled) self.foldedSwipe = NO;
    return nil;
}

int SwipeWay(CGFloat x, CGFloat y) {
    if (hypot(x, y) < kSwipeDecide) return 0;
    return fabs(x) > 2 * fabs(y) ? 1 : -1;
}

BOOL SwipeFlicks(CGFloat speed, CGFloat x) {
    return fabs(speed) > kFlickSpeed && speed * x > 0;
}

NSPoint ParkedOrigin(NSRect frame, NSRect visible, BOOL right) {
    return NSMakePoint(right ? NSMaxX(visible) : NSMinX(visible) - NSWidth(frame), NSMinY(frame));
}

CGFloat ParkedShows(NSRect frame, NSRect visible) {
    CGFloat inside = NSWidth(NSIntersectionRect(frame, visible)) / NSWidth(frame);
    return inside * inside;
}

- (void)followAway:(void (^)(BOOL))observer {
    [self.awayObservers addObject:observer];
}

// A two-finger swipe on the panel, as the trackpad says it goes: from the fingers landing (began), as they move
// (changed), to their lifting (ended), the trackpad's momentum after it. One whose first moves are mostly sideways is
// the panel's, from then till its momentum has run out, and the page doesn't get it; up and down stay the list's. Only
// on the open panel's list, with the reader closed, and not while one of the page's boxes has the keyboard.
- (NSEvent *)swiped:(NSEvent *)event {
    if (event.window != self.panel || !event.hasPreciseScrollingDeltas) return event;
    // A swipe that starts on the folded cat is the cat's, to its end, momentum and all.
    if (event.phase == NSEventPhaseBegan || event.phase == NSEventPhaseMayBegin)
        self.foldedSwipe = self.folded && !self.reshaping;
    if (self.foldedSwipe) return [self swipedFolded:event];
    if (event.momentumPhase != NSEventPhaseNone) return self.swipeMine ? nil : event;
    if (event.phase == NSEventPhaseBegan || event.phase == NSEventPhaseMayBegin) {
        self.swipeMine = self.swipeDecided = NO;
        self.swipeX = self.swipeY = self.swipeSpeed = 0;
        self.swipeAt = event.timestamp;
        // Not while one of the page's boxes has the keyboard: a sideways swipe there moves through its words.
        self.swipeAllowed = !self.folded && !self.expanded && !self.turned && !self.turning && !self.reshaping
                            && !self.parked && !self.parkTimer && !self.panel.wantsKeyboard;
        return event;
    }
    if (!self.swipeAllowed) return event;
    if (event.phase == NSEventPhaseChanged) {
        // Which way the fingers went, whichever way scrolling goes on this Mac.
        CGFloat way = event.isDirectionInvertedFromDevice ? 1 : -1;
        CGFloat dx = event.scrollingDeltaX * way, dy = event.scrollingDeltaY * way;
        self.swipeX += dx;
        self.swipeY += dy;
        if (!self.swipeDecided) {
            int way = SwipeWay(self.swipeX, self.swipeY);
            if (!way) return event;
            self.swipeDecided = YES;
            self.swipeMine = way > 0;
            if (!self.swipeMine) return event;
            // Its place is kept as it was, not where it leans or goes.
            self.swipeFrom = self.panel.frame.origin;
            self.swipeTop = NSMaxY(self.panel.frame);
            [self.panel saveFrameUsingName:@"Whozmove"];
            self.panel.frameAutosaveName = @"";
        }
        if (!self.swipeMine) return event;
        NSTimeInterval dt = event.timestamp - self.swipeAt;
        self.swipeAt = event.timestamp;
        if (dt > 0.001) self.swipeSpeed = 0.6 * dx / dt + 0.4 * self.swipeSpeed;
        // It leans with the fingers, less the further they go.
        CGFloat lean = kLeanMost * tanh(self.swipeX / 60);
        [self.panel setFrameOrigin:NSMakePoint(self.swipeFrom.x + lean, self.swipeTop - NSHeight(self.panel.frame))];
        [self tellGlass:[self glassOnScreen] over:0];
        return nil;
    }
    if (event.phase == NSEventPhaseEnded || event.phase == NSEventPhaseCancelled) {
        if (!self.swipeMine) return event;
        BOOL flick = event.phase == NSEventPhaseEnded && SwipeFlicks(self.swipeSpeed, self.swipeX);
        if (flick) [self parkToward:self.swipeSpeed > 0 speed:fabs(self.swipeSpeed)];
        else [self slideTo:NSMakePoint(self.swipeFrom.x, self.swipeTop) over:0.25 fading:NO then:^(PanelWindow *me) {
            [me.panel saveFrameUsingName:@"Whozmove"];
            me.panel.frameAutosaveName = @"Whozmove";
        }];
        return nil;
    }
    return event;
}

// Off that edge of the screen it was flicked toward, carrying on at the flick's speed and easing out, fading as it goes
// past the edge (on a display beside it, it never shows): just past the edge, Whozmove peeks out from it. The icons at
// its edge take the side facing back onto the screen at once, while still out of sight, and keep it while it's away,
// so Whozmove comes out at the screen's edge as the panel arrives. What's held over or under it goes as it starts; with
// reduced motion, once the panel has faded and gone, so Whozmove fades in at the edge.
- (void)parkToward:(BOOL)right speed:(CGFloat)speed {
    NSRect visible = (self.panel.screen ?: NSScreen.mainScreen).visibleFrame, frame = self.panel.frame;
    CGFloat x = ParkedOrigin(frame, visible, right).x;
    self.parked = YES;
    self.parkScreen = visible;
    self.parkedFrom = self.swipeFrom;
    self.parkedTop = self.swipeTop;
    self.edgeSide = right ? @"left" : @"right";
    [self tellGlass:[self glassOnScreen] over:0];
    [self dropKeyboard];
    void (^gone)(PanelWindow *) = ^(PanelWindow *me) {
        for (void (^observer)(BOOL) in me.awayObservers) observer(YES);
    };
    if (NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion)
        return [self fadeTo:NSMakePoint(x, NSMaxY(frame)) coming:NO then:^(PanelWindow *me) {
            me.panel.ignoresMouseEvents = YES;
            gone(me);
        }];
    gone(self);
    NSTimeInterval seconds = MAX(kParkLeast, MIN(kParkMost, 3 * fabs(x - NSMinX(frame)) / speed));
    [self slideTo:NSMakePoint(x, NSMaxY(frame)) over:seconds fading:YES then:^(PanelWindow *me) {
        me.panel.ignoresMouseEvents = YES;
    }];
}

// Where it was before it was flicked away: its top-left corner. Its place is found from that and its height as it is
// then (originAt:), as it keeps growing and shrinking from its top while it's away or on its way.
- (NSPoint)parkedCorner {
    return NSMakePoint(self.parkedFrom.x, self.parkedTop);
}

- (NSPoint)originAt:(NSPoint)corner {
    return NSMakePoint(corner.x, corner.y - NSHeight(self.panel.frame));
}

// With reduced motion, it fades out where it is, then goes (parking); or comes back, then fades in: to its top-left
// `corner`.
- (void)fadeTo:(NSPoint)corner coming:(BOOL)coming then:(void (^)(PanelWindow *me))then {
    __weak typeof(self) weakSelf = self;
    void (^go)(void) = ^{
        [weakSelf.panel setFrameOrigin:[weakSelf originAt:corner]];
        [weakSelf tellGlass:[weakSelf glassOnScreen] over:0];
    };
    if (coming) go();
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.2;
        weakSelf.panel.animator.alphaValue = coming ? 1 : 0;
        weakSelf.shade.animator.alphaValue = coming ? 1 : 0;
    } completionHandler:^{
        if (!coming) go();
        if (weakSelf) then(weakSelf);
    }];
}

// Back where it was, sliding in from the screen's edge, what's held over or under it coming back with it as it does.
// With reduced motion, Whozmove fades at the edge first, then the panel fades in where it was.
- (void)unpark {
    if (!self.parked) return;
    self.parked = NO;
    self.panel.ignoresMouseEvents = NO;
    for (void (^observer)(BOOL) in self.awayObservers) observer(NO);
    void (^back)(PanelWindow *) = ^(PanelWindow *me) { [me backAtOnce]; };
    if (NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf fadeTo:[weakSelf parkedCorner] coming:YES then:back];
        });
        return;
    }
    [self slideTo:[self parkedCorner] over:kUnpark fading:YES then:back];
}

// Back where it was, at once: in sight, and its place kept again, saved first as it is, as given its name back the
// window also moves to what's saved under it.
- (void)backAtOnce {
    [self.parkTimer invalidate];
    self.parkTimer = nil;
    BOOL wasParked = self.parked;
    self.parked = NO;
    [self.panel setFrameOrigin:[self originAt:[self parkedCorner]]];
    self.panel.alphaValue = self.shade.alphaValue = 1;
    self.panel.ignoresMouseEvents = NO;
    [self.panel saveFrameUsingName:@"Whozmove"];
    self.panel.frameAutosaveName = @"Whozmove";
    [self tellGlass:[self glassOnScreen] over:0];
    if (wasParked) for (void (^observer)(BOOL) in self.awayObservers) observer(NO);
}

// The panel slides its top-left corner to `corner` over `seconds`, easing out, its place found each step from that
// and its height then (it may grow or shrink from its top on the way), and those following the glass are told each
// step; then `then`. Fading, it's as faint as it is past the screen's edge.
- (void)slideTo:(NSPoint)corner over:(NSTimeInterval)seconds fading:(BOOL)fading
            then:(void (^)(PanelWindow *me))then {
    [self.parkTimer invalidate];
    NSPoint from = NSMakePoint(NSMinX(self.panel.frame), NSMaxY(self.panel.frame));
    CFTimeInterval start = CACurrentMediaTime();
    __weak typeof(self) weakSelf = self;
    void (^step)(CGFloat) = ^(CGFloat along) {
        PanelWindow *me = weakSelf;
        CGFloat e = 1 - pow(1 - along, 3);
        [me.panel setFrameOrigin:[me originAt:NSMakePoint(round(from.x + (corner.x - from.x) * e),
                                                         from.y + (corner.y - from.y) * e)]];
        if (fading) me.panel.alphaValue = me.shade.alphaValue = ParkedShows(me.panel.frame, me.parkScreen);
        [me tellGlass:[me glassOnScreen] over:0];
    };
    if (seconds <= 0) {
        step(1);
        self.parkTimer = nil;
        then(self);
        return;
    }
    self.parkTimer = [NSTimer timerWithTimeInterval:1.0 / 120 repeats:YES block:^(NSTimer *timer) {
        CGFloat along = MIN(1, (CACurrentMediaTime() - start) / seconds);
        step(along);
        if (along < 1) return;
        [timer invalidate];
        PanelWindow *me = weakSelf;
        if (me.parkTimer == timer) me.parkTimer = nil;
        if (me) then(me);
    }];
    [NSRunLoop.mainRunLoop addTimer:self.parkTimer forMode:NSRunLoopCommonModes];
}

- (void)tellGlass:(NSRect)glass over:(NSTimeInterval)duration {
    NSScreen *screen = self.panel.screen ?: NSScreen.mainScreen;
    NSRect list = self.expanded ? self.listFrame : glass;
    // Flicked away, or on its way there or back, the icons keep the side facing back onto the screen (parkToward:).
    if (!self.parked && !self.parkTimer) self.edgeSide = EdgeSideFor(list, screen.visibleFrame, self.edgeSide);
    for (void (^observer)(NSRect, NSRect, NSRect, NSTimeInterval) in self.glassObservers)
        observer(glass, list, screen.visibleFrame, duration);
}

#pragma mark The reader

// The reader opens beside the list, which stays where it was: the panel grows towards the side with more room, so a
// panel at the right grows leftwards with its list on the right, and one at the left the other way, and downwards
// from its top edge. It grows only as far as what the reader shows needs, and no further than the screen allows
// (16pt from its edges; a longer page scrolls). The page is told which side its list is on, and how wide the reader
// is, before the panel starts to grow, so what's in it is laid out once at that size and the growing only uncovers it.
- (void)expandReader:(CGFloat)width height:(CGFloat)height {
    // The reader opens from a row, and there are none to see while it's folded or turned over.
    if (self.folded || self.turned) return;
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

- (void)whenStill:(void (^)(void))then {
    if (!then) return;
    if (self.reshaping) [self.stillWaiters addObject:[then copy]];
    else then();
}

// The panel has stopped changing size, with no other size asked for: whoever waited for that goes now, unless what
// they did after the last change (folding back calls the page) has started the panel changing size again.
- (void)tellStill {
    if (self.reshaping || !self.stillWaiters.count) return;
    NSArray *waiting = [self.stillWaiters copy];
    [self.stillWaiters removeAllObjects];
    for (void (^then)(void) in waiting) then();
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
    // Turning over, it keeps the panel's height, so it isn't laid out again for the room taken in below the panel.
    if (self.turning) tall = NSHeight(self.turnFrame);
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
    // Folded, the cat's corner is dragged by, and a click on it opens the panel; the tags' room below it is the page's.
    if (self.folded) {
        self.strip.frame = [self inWindow:[self catBoxIn:self.panel.frame]];
        self.strip.hidden = NO;
        self.readerStrip.hidden = YES;
        return;
    }
    if (!self.expanded) {
        // Only over the part of the header that still shows as it slides away with the list, so a press on the rows
        // that have come up under it goes to them; none once it has gone. The back's header stays where it is.
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

#pragma mark Folding into the cat

// Where the glass is on the screen: the round one in the middle of the folded window, or the whole panel.
- (NSRect)glassOnScreen {
    return self.folded ? [self foldedGlassIn:self.panel.frame] : self.panel.frame;
}

// The panel's shadow, its own rather than the window's: macOS draws a light line round a window's edge with the
// window's shadow on the dark panel. It's under the glass wherever the glass is (opening the reader, folding into the
// cat and back, breathing), with its corners, in the window held under the panel, so whatever else is held under it
// (Spotify's token) has the panel's shadow fall on it, as before. Nothing is under the glass itself, which may be
// see-through. The open panel's is as wide as the prototypes'; round the folded cat it's smaller, and on the light
// panel softer.
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
    // It folds from its list side: turned over (a page loaded afresh says how it was left), it's put back at once.
    if (self.turned && !self.turning) [self turnBackAtOnce];
    [NSUserDefaults.standardUserDefaults setBool:on forKey:kFoldedKey];
    if (self.reshaping) {
        self.pendingFold = @(on);
        return;
    }
    BOOL changed = on != self.folded;
    self.folded = on;
    if (on) [self dropKeyboard];
    if (!on) [self stopBreathing];
    if (!changed || instant) {
        [self placeAtOnce];
        if (changed) [self tellFold:YES];
        return;
    }
    if (on) self.openHeight = NSHeight(self.panel.frame);
    [self tellFold:NO];
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
    // The panel's shadow breathes with it.
    for (CALayer *layer in @[self.glass.layer, self.shadow])
        [layer addAnimation:[self breath:breath of:layer] forKey:@"breath"];
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
    for (CALayer *layer in @[self.glass.layer, self.shadow]) [layer removeAnimationForKey:@"breath"];
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
        [weakSelf tellFold:YES];
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

#pragma mark Turning over

- (void)holdBack:(NSView *)view {
    NSView *root = self.panel.contentView;
    // As wide as the list always, so its page is never laid out at another width; as tall as the panel.
    SideView *back = [[SideView alloc] initWithFrame:NSMakeRect(0, 0, kWidth, MAX(NSHeight(root.bounds), 200))];
    back.wantsLayer = YES;
    back.layer.masksToBounds = YES;
    back.layer.cornerRadius = kCorner;
    back.autoresizingMask = NSViewHeightSizable | NSViewMaxXMargin;
    back.alphaValue = 0;
    back.away = YES;
    view.frame = back.bounds;
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [back addSubview:view];
    [root addSubview:back positioned:NSWindowAbove relativeTo:self.clip];
    self.back = back;
    [self placeBack];
}

// The back where the list is, as tall as the panel: while it turns, where the panel was before the window took in room
// round it. Folded, it stays as it was, out of sight, so its page isn't laid out at the cat's size.
- (void)placeBack {
    if (!self.back || self.folded || self.holdsPage) return;
    NSRect list = self.turning ? self.turnFrame : self.expanded ? self.listFrame : self.panel.frame;
    self.back.frame = [self inWindow:list];
}

- (void)followTurn:(void (^)(BOOL))observer {
    [self.turnObservers addObject:observer];
}

// Turned over from the moment it starts turning, and back as it lands on its list side: the list's page and whoever
// follows the turn are told each, in the same frame the turn starts or ends, so what's held over or under the panel
// goes and comes back with it.
- (void)becomeTurned:(BOOL)on {
    if (on == self.turned) return;
    self.turned = on;
    [self.page turned:on];
    for (void (^observer)(BOOL) in self.turnObservers) observer(on);
}

// Turning over, the box that had the keyboard lets go of it, and the window takes in room round the panel for its near
// edge, which comes toward you and is seen taller and a little wider than the panel; then it turns, what's held over or
// under the panel going from sight as it starts, and the window is the panel again. Turning back carries on the same
// way round, so over and back make one whole turn, and what was held comes back as it lands. With reduced motion, one
// side fades into the other. Asked again on the way, or while the panel changes shape (opening out of the cat, the
// reader folding), the newest is taken once that's done, and what was to come after each runs in turn.
- (void)turnOver:(BOOL)over then:(void (^)(void))then {
    if (self.turning || (self.reshaping && over != self.turned)) {
        void (^earlier)(void) = self.pendingTurnThen;
        self.pendingTurn = @(over);
        self.pendingTurnThen = ^{ if (earlier) earlier(); if (then) then(); };
        return;
    }
    if (!self.back || over == self.turned || (over && (self.expanded || self.folded))) {
        if (then) then();
        return;
    }
    self.turning = YES;
    self.reshaping = YES;  // nothing else changes the panel's size or shape meanwhile
    NSRect panel = self.panel.frame;
    self.turnFrame = panel;
    // The room it turns in mustn't be what the panel comes back at next launch (settle saves it as itself again).
    self.panel.frameAutosaveName = @"";
    if (over) [self dropKeyboard];
    self.clip.away = self.back.away = YES;
    self.strip.hidden = self.readerStrip.hidden = YES;
    __weak typeof(self) weakSelf = self;
    void (^done)(void) = ^{ [weakSelf doneTurning:over then:then]; };
    if (NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
        if (over) [self becomeTurned:YES];
        [self fadeSides:over then:done];
        return;
    }
    CGFloat grows = kTurnDepth / (kTurnDepth - kWidth / 2) - 1;
    NSRect room = NSInsetRect(panel, -4, -(ceil(NSHeight(panel) / 2 * grows) + 2));
    [self setWindowFrame:room glass:panel clip:panel then:^{
        [weakSelf spin:over then:^{ [weakSelf setWindowFrame:panel showing:panel then:done]; }];
    }];
}

// Done turning: the side facing you takes clicks, and once it's back on its list side, the panel is told, and takes the
// height its page asked for meanwhile; then what was to come after, and what was asked for on the way.
- (void)doneTurning:(BOOL)over then:(void (^)(void))then {
    self.turning = NO;
    self.clip.away = over;
    self.back.away = !over;
    if (!over) [self becomeTurned:NO];
    [self settle];
    if (!over && self.heightAsked > 0) {
        CGFloat height = self.heightAsked;
        self.heightAsked = 0;
        [self fitHeight:height];
    }
    if (then) then();
    [self takePending];
    [self takePendingTurn];
}

// A turn asked for while the panel was turning or changing shape, once it's done: not while it's changing shape again
// (the next settle asks once more).
- (void)takePendingTurn {
    NSNumber *next = self.pendingTurn;
    if (!next || self.turning || self.reshaping) return;
    void (^after)(void) = self.pendingTurnThen;
    self.pendingTurn = nil;
    self.pendingTurnThen = nil;
    [self turnOver:next.boolValue then:after];
}

// The turn, played by Core Animation, as the folded glass's breath is: the glass, both sides and the panel's shadow
// turn as one about the panel's middle, the back coming round as the list goes, so each side shows as it is all the
// way; they swap where the panel is edge-on, and its edge shows there. Only what's drawn moves, so nothing is laid out
// or drawn again on the way.
- (void)spin:(BOOL)over then:(void (^)(void))then {
    NSRect local = [self inWindow:self.turnFrame];
    CGPoint middle = CGPointMake(NSMidX(local), NSMidY(local));
    // It always turns the same way round: over takes it half a turn, and back carries on round the other half, rather
    // than going back the way it came.
    CGFloat from = over ? 0 : M_PI, to = over ? M_PI : 2 * M_PI;
    // The edge is on the side that comes toward you, halfway through: on the list's one side turning over, and on its
    // other turning back, as that's the side facing the same way by then.
    CATransform3D halfway = CATransform3DMakeRotation((from + to) / 2, 0, 1, 0);
    BOOL left = (NSMinX(local) - middle.x) * halfway.m13 > (NSMaxX(local) - middle.x) * halfway.m13;
    CGFloat side = left ? NSMinX(local) : NSMaxX(local);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.edge.frame = NSMakeRect(side - kEdge / 2, NSMinY(local) + kEdgeInset, kEdge, NSHeight(local) - 2 * kEdgeInset);
    self.edgeShade.frame = CGRectMake(0, 0, kEdge, NSHeight(local) - 2 * kEdgeInset);
    [CATransaction commit];
    [self paintEdge];
    CGPoint glassAt = AnchorOf(self.glass), frontAt = AnchorOf(self.clip), backAt = AnchorOf(self.back);
    CGPoint edgeAt = AnchorOf(self.edge), edgeMiddle = CGPointMake(NSMidX(self.edge.frame), NSMidY(self.edge.frame));
    CGPoint shadowAt = self.shadow.position;
    // Finely enough for every frame the screen draws; each a little turn from the last.
    const int samples = 96;
    NSMutableArray *times = [NSMutableArray array], *glass = [NSMutableArray array], *front = [NSMutableArray array],
                   *back = [NSMutableArray array], *edge = [NSMutableArray array], *shadow = [NSMutableArray array];
    for (int i = 0; i <= samples; i++) {
        CGFloat along = (CGFloat)i / samples, angle = from + (to - from) * TurnEased(along);
        // The edge stands across the panel's side, as thick as the panel is turned from you, so it's never seen flat.
        CATransform3D across = CATransform3DConcat(CATransform3DMakeScale(MAX(0.001, fabs(sin(angle))), 1, 1),
                                                   CATransform3DMakeRotation(M_PI_2, 0, 1, 0));
        [times addObject:@(along)];
        [glass addObject:[NSValue valueWithCATransform3D:TurnAbout(middle, glassAt, angle, CATransform3DIdentity,
                                                                   glassAt)]];
        [front addObject:[NSValue valueWithCATransform3D:TurnAbout(middle, frontAt, angle, CATransform3DIdentity,
                                                                   frontAt)]];
        // The back is the other way round, so it reads as it should once it has come round.
        [back addObject:[NSValue valueWithCATransform3D:TurnAbout(middle, backAt, angle - M_PI, CATransform3DIdentity,
                                                                  backAt)]];
        [edge addObject:[NSValue valueWithCATransform3D:TurnAbout(middle, edgeAt, angle, across, edgeMiddle)]];
        [shadow addObject:[NSValue valueWithCATransform3D:TurnAbout(shadowAt, shadowAt, angle, CATransform3DIdentity,
                                                                    shadowAt)]];
    }
    CAKeyframeAnimation *(^turning)(NSArray *) = ^CAKeyframeAnimation *(NSArray *values) {
        CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"transform"];
        animation.values = values;
        animation.keyTimes = times;
        animation.duration = kTurn;
        return animation;
    };
    // Each side shows only while it faces you: they swap halfway, where the panel is edge-on.
    CAKeyframeAnimation *(^swap)(BOOL) = ^CAKeyframeAnimation *(BOOL showsAfter) {
        CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
        animation.values = showsAfter ? @[@0, @0, @1, @1] : @[@1, @1, @0, @0];
        animation.keyTimes = @[@0, @0.499, @0.501, @1];
        animation.duration = kTurn;
        return animation;
    };
    __weak typeof(self) weakSelf = self;
    if (over) [self becomeTurned:YES];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [CATransaction setCompletionBlock:^{
        if (!over) [weakSelf becomeTurned:NO];
        then();
    }];
    // The edge shows only while it turns: once its animation has gone, it's see-through again.
    CAKeyframeAnimation *showing = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    showing.values = @[@1, @1];
    showing.duration = kTurn;
    [self.glass.layer addAnimation:turning(glass) forKey:@"turn"];
    [self.clip.layer addAnimation:turning(front) forKey:@"turn"];
    [self.back.layer addAnimation:turning(back) forKey:@"turn"];
    [self.edge.layer addAnimation:turning(edge) forKey:@"turn"];
    [self.edge.layer addAnimation:showing forKey:@"side"];
    [self.shadow addAnimation:turning(shadow) forKey:@"turn"];
    [self.clip.layer addAnimation:swap(!over) forKey:@"side"];
    [self.back.layer addAnimation:swap(over) forKey:@"side"];
    self.clip.alphaValue = over ? 0 : 1;
    self.back.alphaValue = over ? 1 : 0;
    [CATransaction commit];
}

// With reduced motion, the side going fades as the one coming in does, in place.
- (void)fadeSides:(BOOL)over then:(void (^)(void))then {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [CATransaction setCompletionBlock:then];
    for (SideView *side in @[self.clip, self.back]) {
        BOOL shows = (side == self.back) == over;
        CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fade.fromValue = @(shows ? 0 : 1);
        fade.toValue = @(shows ? 1 : 0);
        fade.duration = 0.25;
        [side.layer addAnimation:fade forKey:@"side"];
        side.alphaValue = shows ? 1 : 0;
    }
    [CATransaction commit];
}

// Back on its list side at once, as it folds (fold:instant:).
- (void)turnBackAtOnce {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.clip.alphaValue = 1;
    self.back.alphaValue = 0;
    [CATransaction commit];
    self.clip.away = NO;
    self.back.away = YES;
    [self becomeTurned:NO];
    [self placeStrips];
    // It's folding: the page says how tall it is again once it opens.
    self.heightAsked = 0;
}

// The edge in the panel's own colour, from the tint's: a little lighter on the dark panel and darker on the light one,
// most in its middle, as a rounded edge catches the light.
- (void)paintEdge {
    BOOL dark = IsDark(self.panel.effectiveAppearance);
    NSColor *tint = [[NSColor colorWithCGColor:self.tint.layer.backgroundColor]
                        colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: NSColor.grayColor;
    CGFloat r = tint.redComponent, g = tint.greenComponent, b = tint.blueComponent;
    NSMutableArray *colours = [NSMutableArray array];
    for (NSNumber *by in @[@0.04, @0.11, @0.02]) {
        CGFloat k = dark ? by.doubleValue : -by.doubleValue;
        [colours addObject:(__bridge id)[NSColor colorWithSRGBRed:MAX(0, MIN(1, r + k)) green:MAX(0, MIN(1, g + k))
                                                             blue:MAX(0, MIN(1, b + k)) alpha:1].CGColor];
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.edgeShade.colors = colours;
    [CATransaction commit];
}

#pragma mark Keyboard

// The page's box takes the keyboard from a site in the panel, but its letting go doesn't take it from one: pressed from
// the box into a site, the box lets go a moment after the site took it.
- (void)takeKeyboard:(BOOL)on {
    self.pageKeys = on;
    if (!on && self.browserKeys) return;
    if (on && self.browserKeys) {
        self.browserKeys = NO;
        [self.panel makeFirstResponder:self.page.view];
    }
    [self wantKeyboard:on];
}

- (void)wantKeyboard:(BOOL)on {
    if (on && self.panel.wantsKeyboard) return;
    self.panel.wantsKeyboard = on;
    if (on) [self.panel makeKeyWindow];
    else [self giveBackKeyboard];
}

- (BOOL)releaseKeyboard {
    self.browserKeys = self.pageKeys = NO;
    if (!self.panel.isKeyWindow) return NO;
    self.panel.wantsKeyboard = NO;
    [self giveBackKeyboard];
    return YES;
}

// The keyboard goes back to the app it came from, the one in front. Asking that app to come forward does nothing while
// it's in front already, and the panel would keep the keyboard; so the panel hands it to a window of its own that can't
// be seen, which goes at once, and macOS gives the keyboard back to the app in front, as when any panel that has it
// closes.
- (void)giveBackKeyboard {
    if (!self.panel.isKeyWindow) return;
    [self.handOff setFrameOrigin:self.panel.frame.origin];
    [self.handOff orderWindow:NSWindowBelow relativeTo:self.panel.windowNumber];
    [self.handOff makeKeyWindow];
    [self.handOff orderOut:nil];
}

- (BOOL)keptKeyboard {
    return self.panel.isKeyWindow && !self.panel.wantsKeyboard;
}

// Whoever in the panel has the keyboard gives it back: the panel folds or turns over.
- (void)dropKeyboard {
    self.browserKeys = NO;
    [self takeKeyboard:NO];
}

// The site shown at a point in the window, if one is, and nothing covers it there.
- (Browser *)browserAt:(NSPoint)at {
    NSArray<Browser *> *browsers = [Browser inWindow:self.panel];
    if (!browsers.count) return nil;
    NSView *root = self.panel.contentView;
    NSView *hit = [root hitTest:[root.superview ?: root convertPoint:at fromView:nil]];
    for (Browser *browser in browsers)
        if (hit && [hit isDescendantOf:browser.view] && !browser.view.isHiddenOrHasHiddenAncestor) return browser;
    return nil;
}

// A click into a site takes the keyboard for it, as typing there is what it's for. One elsewhere in the panel gives it
// back to the app it came from, unless it's into one of the page's own boxes, which asks for it (takeKeyboard:) as the
// click lands.
- (void)clickedAt:(NSPoint)at {
    Browser *into = [self browserAt:at];
    if (into) {
        self.browserKeys = YES;
        self.keyboardBrowser = into;
        [self wantKeyboard:YES];
        [self.panel makeFirstResponder:into.view];
        return;
    }
    if (!self.browserKeys) return;
    self.browserKeys = NO;
    [self.panel makeFirstResponder:self.page.view];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!weakSelf.browserKeys && !weakSelf.pageKeys) [weakSelf wantKeyboard:NO];
    });
}

// WebKit follows the pointer only in the window you type in, so a site gets it only while the panel has the keyboard;
// and macOS sends a window that doesn't make its app active none of the pointer's moves, so they're passed in from
// here. Once the site that was given the keyboard has gone (closed, or out of sight), the keyboard goes back; and a
// site the pointer leaves is told so.
- (void)pointBrowsersAt:(NSPoint)screen moved:(BOOL)moved {
    if (self.browserKeys && !Shows(self.keyboardBrowser.view, self.panel)) [self dropKeyboard];
    NSPoint at = [self.panel convertPointFromScreen:screen];
    Browser *on = self.panel.isVisible && self.panel.isKeyWindow ? [self browserAt:at] : nil;
    Browser *was = self.pointedBrowser;
    if (was && was != on) PassPointer(was.view, NSEventTypeMouseExited, at);
    if (on && (moved || on != was)) PassPointer(on.view, NSEventTypeMouseMoved, at);
    self.pointedBrowser = on;
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
    [self pointBrowsersAt:screen moved:moved];
    // Turned over, the list isn't what the pointer is on: the back's page follows it (followPointer:).
    if (self.turned) {
        if (self.hovering) {
            self.hovering = NO;
            [self.page hoverEnd:NO];
        }
        return;
    }
    NSRect frame = self.panel.frame;
    if (self.folded && !self.reshaping) {
        [self tellCatPointer:screen];
        [self tellCatSide];
    }
    // A site in the panel isn't the page: the pointer on one is off the page.
    BOOL inside = self.panel.isVisible && NSPointInRect(screen, frame)
                  && ![self browserAt:[self.panel convertPointFromScreen:screen]];
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
