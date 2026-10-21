// EdgeIcon: what every icon at the panel's edge shares (EdgeIcon.h).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// It's a small window of its own that the panel holds under itself, so it's really beneath the glass: the glass hides
// half of it, it moves with the panel as it's dragged, and the panel's own window doesn't grow to make room for it
// (which would take clicks from the desktop beside it). It lets clicks through except while the pointer is over the
// icon, and never takes the keyboard.
//
// Its motion keeps to CONTRIBUTING.md's rules. It's always the same icon: changing sides, it goes in under the glass at
// one corner, travels under the panel and comes out at the other, and never jumps. Opening out of the cat, the panel
// opens first, and only then does it come out, with the same small bounce as on the other side. The label saying what
// a press does comes out beside it, in its own lane outside the panel. Reduced motion has it fade in place instead.
#import "EdgeIcon.h"
#import "PanelWindow.h"
#import "Appearance.h"
#import "Easing.h"

const CGFloat kEdgeTucked = -26;
// The room beside its box for the label.
static const CGFloat kLabelRoom = 230;
// Changing sides takes this long, after a moment's wait once the panel has crossed the middle, so it's clear what set
// it off; the middle has this much leeway either side before it does.
static const NSTimeInterval kCrossing = 1.0, kCrossingWait = 0.35;
static const CGFloat kLeeway = 40;
// Coming out on the other side, it goes this far past where it rests, then settles back: one small bounce. Once the
// panel has opened out of the cat, the same bounce brings it out, taking this long.
static const CGFloat kBounce = 23;
static const NSTimeInterval kPopOut = 0.35;
// Opening out of the cat, it waits under the glass until the glass has come to rest, or this long at most.
static const NSTimeInterval kOpeningAtMost = 1.5;
// After the panel has moved, it keeps still this long before it reaches for the pointer again: the pointer was
// dragging the panel, not reaching for it.
static const NSTimeInterval kStillAfterMove = 0.6;

NSString *EdgeSideFor(NSRect list, NSRect screen, NSString *current) {
    CGFloat middle = NSMidX(screen), at = NSMidX(list);
    if ([current isEqual:@"right"]) return at > middle + kLeeway ? @"left" : @"right";
    if ([current isEqual:@"left"]) return at < middle - kLeeway ? @"right" : @"left";
    return at < middle ? @"right" : @"left";
}

static BOOL Calm(void) { return NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion; }
static CGFloat Ease(CGFloat t) { t = MAX(0, MIN(1, t)); return 1 - pow(1 - t, 3); }
static CGFloat EaseInOut(CGFloat t) {
    t = MAX(0, MIN(1, t));
    return t < .5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2;
}
static CGFloat Lerp(CGFloat a, CGFloat b, CGFloat t) { return a + (b - a) * t; }

static NSRect LerpRect(NSRect a, NSRect b, CGFloat t) {
    return NSMakeRect(Lerp(NSMinX(a), NSMinX(b), t), Lerp(NSMinY(a), NSMinY(b), t), Lerp(NSWidth(a), NSWidth(b), t),
                      Lerp(NSHeight(a), NSHeight(b), t));
}
static BOOL NearlySame(NSRect a, NSRect b) {
    return fabs(NSMinX(a) - NSMinX(b)) < 1 && fabs(NSMinY(a) - NSMinY(b)) < 1 && fabs(NSWidth(a) - NSWidth(b)) < 1
           && fabs(NSHeight(a) - NSHeight(b)) < 1;
}

// How far out from the glass's edge it is `t` of the way through coming out with one small bounce: from under the
// glass to past its resting place by the bounce, then back to it.
static CGFloat Bounced(CGFloat t) {
    return t < 0.55 ? Lerp(kEdgeTucked, kBounce, Ease(t / 0.55)) : Lerp(kBounce, 0, EaseInOut((t - 0.55) / 0.45));
}

// Its window: never key, so pressing it leaves the keyboard where it was.
@interface EdgeWindow : NSPanel
@end

@implementation EdgeWindow
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

// Its view: a press, the pointer dragged with it held, and let go, each where the pointer is on the screen.
@interface EdgeView : NSView
@property (copy) void (^onDown)(NSPoint at);
@property (copy) void (^onDrag)(NSPoint at);
@property (copy) void (^onUp)(NSPoint at);
@property (copy) void (^onLook)(void);  // the app has turned light or dark
@end

@implementation EdgeView
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (void)mouseDown:(NSEvent *)event { if (self.onDown) self.onDown(NSEvent.mouseLocation); }
- (void)mouseDragged:(NSEvent *)event { if (self.onDrag) self.onDrag(NSEvent.mouseLocation); }
- (void)mouseUp:(NSEvent *)event { if (self.onUp) self.onUp(NSEvent.mouseLocation); }
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    if (self.onLook) self.onLook();
}
@end

@interface EdgeIcon ()
@property (strong) EdgeWindow *iconWindow;
@property (strong) EdgeView *view;
@property (strong) CALayer *box, *label;
@property (strong) CATextLayer *labelText;
@property (weak) PanelWindow *panelWindow;
@property (assign) CGFloat boxSize, reach, windowWidth;
@property (copy) NSString *side;
@property (copy) NSString *labelWhat, *labelMore;
@property (assign) BOOL over;
@property (assign) NSPoint pointer;
@property (assign) BOOL turned;          // the panel is turned over to its back, so it stays out of sight
@property (assign) BOOL pressing;        // held down by a press on it
@property (assign) BOOL away;            // the panel is pushed off the screen's edge
// Where the glass is, easing from where it was over `glassFor` seconds from `glassSince`.
@property (assign) NSRect glass, glassFrom;
@property (assign) CFTimeInterval glassSince, glassFor;
@property (assign) BOOL tucking;         // pressed: going under the glass before what was pressed happens
@property (copy) void (^afterTuck)(void);
@property (assign) BOOL waitingForOpen;  // the panel opening out of the cat: out once its glass has come to rest
@property (assign) NSUInteger openingRun;  // which opening the wait is for, so a late fallback can't end a newer one
@property (assign) CFTimeInterval poppingSince;  // coming out with the bounce once the panel has opened, or 0
// Changing sides: from which side, and since when.
@property (copy) NSString *crossingFrom;
@property (assign) CFTimeInterval crossingSince;
@property (assign) CGFloat crossingOut;
@property (copy) NSString *sideAhead;    // the side it's about to cross to, once it has waited
@property (assign) CFTimeInterval movedAt;  // when the panel last moved
@property (strong) NSTimer *frameTimer;
@property (assign) CFTimeInterval lastFrame;
@end

@implementation EdgeIcon

- (instancetype)initWithBox:(CGFloat)box reach:(CGFloat)reach {
    if (!(self = [super init])) return nil;
    self.boxSize = box;
    self.reach = reach;
    self.windowWidth = box + kLabelRoom;
    self.iconWindow = [[EdgeWindow alloc] initWithContentRect:NSMakeRect(0, 0, self.windowWidth, box)
                                                    styleMask:NSWindowStyleMaskBorderless
                                                              | NSWindowStyleMaskNonactivatingPanel
                                                      backing:NSBackingStoreBuffered defer:NO];
    self.iconWindow.level = NSFloatingWindowLevel;
    self.iconWindow.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces
                                         | NSWindowCollectionBehaviorFullScreenAuxiliary;
    self.iconWindow.hidesOnDeactivate = NO;
    self.iconWindow.opaque = NO;
    self.iconWindow.backgroundColor = NSColor.clearColor;
    self.iconWindow.hasShadow = NO;
    self.iconWindow.ignoresMouseEvents = YES;
    self.iconWindow.alphaValue = 0;
    self.view = [[EdgeView alloc] initWithFrame:NSMakeRect(0, 0, self.windowWidth, box)];
    self.view.wantsLayer = YES;
    self.iconWindow.contentView = self.view;
    __weak typeof(self) weakSelf = self;
    self.view.onDown = ^(NSPoint at) {
        weakSelf.pressing = YES;
        [weakSelf downAt:at];
    };
    self.view.onDrag = ^(NSPoint at) { [weakSelf draggedTo:at]; };
    self.view.onUp = ^(NSPoint at) {
        EdgeIcon *icon = weakSelf;
        icon.pressing = NO;
        [icon upAt:at];
        // Let go, it takes the side it kept while it was held.
        if (!icon.keepsPlace && icon.panelWindow) [icon takeSide:icon.panelWindow.edgeSide];
    };
    self.view.onLook = ^{
        [weakSelf paint];
        [weakSelf renderLabel];
    };

    CGFloat scale = NSScreen.mainScreen.backingScaleFactor ?: 2;
    self.box = [CALayer layer];
    self.box.frame = CGRectMake(0, 0, box, box);
    [self.view.layer addSublayer:self.box];
    // The label: what a press does, beside the icon, outside the panel.
    self.label = [CALayer layer];
    self.label.cornerRadius = 7;
    self.label.borderWidth = 0.5;
    self.label.opacity = 0;
    self.labelText = [CATextLayer layer];
    self.labelText.contentsScale = scale;
    [self.label addSublayer:self.labelText];
    [self.view.layer addSublayer:self.label];
    [self paint];
    self.out = self.outTo = kEdgeTucked;
    return self;
}

- (NSWindow *)window {
    return self.iconWindow;
}

// Held under the panel, it follows the glass, the pointer and the turn. As the panel turns over, it goes from sight, as
// the panel's edge would otherwise turn away from over it; once it's back on its list side, it comes out from under
// the glass again.
- (void)holdBy:(PanelWindow *)panel {
    self.panelWindow = panel;
    [panel attachBelow:self.window];
    __weak typeof(self) weakSelf = self;
    __weak PanelWindow *weakPanel = panel;
    [panel followGlass:^(NSRect glass, NSRect list, NSRect screen, NSTimeInterval duration) {
        [weakSelf glassAt:glass side:weakPanel.edgeSide duration:duration];
    }];
    [panel followPointer:^(NSPoint point) { [weakSelf pointerAt:point]; }];
    [panel followTurn:^(BOOL turned) {
        EdgeIcon *icon = weakSelf;
        icon.turned = turned;
        if (turned) [icon fadeAway];
        [icon aim];
    }];
    // Pushed off the screen's edge, the panel takes it with it, but for one that shows there (showsWhileAway).
    [panel followAway:^(BOOL away) {
        EdgeIcon *icon = weakSelf;
        icon.away = away;
        if (away && !icon.showsWhileAway) [icon fadeAway];
        [icon aim];
    }];
}

- (void)fadeAway {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.15;
        self.window.animator.alphaValue = 0;
    }];
}

#pragma mark Drawing

- (BOOL)dark {
    return IsDark(self.view.effectiveAppearance);
}

// The label's colour and edge, the panel's, light or dark.
- (void)paint {
    BOOL dark = self.dark;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.label.backgroundColor = (dark ? [NSColor colorWithSRGBRed:0.08 green:0.08 blue:0.106 alpha:0.94]
                                       : [NSColor colorWithWhite:1 alpha:0.96]).CGColor;
    self.label.borderColor = [NSColor colorWithWhite:dark ? 1 : 0 alpha:dark ? 0.14 : 0.1].CGColor;
    [CATransaction commit];
}

- (void)setLabel:(NSString *)what more:(NSString *)more {
    self.labelWhat = what;
    self.labelMore = more;
    [self renderLabel];
}

- (void)renderLabel {
    NSString *what = self.labelWhat, *more = self.labelMore;
    if (!what) return;
    NSFont *font = [NSFont systemFontOfSize:11];
    BOOL dark = self.dark;
    NSColor *words = [NSColor colorWithWhite:dark ? 0.93 : 0.13 alpha:1];
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:what attributes:@{
        NSFontAttributeName: font, NSForegroundColorAttributeName: words}];
    if (more.length)
        [text appendAttributedString:[[NSAttributedString alloc]
            initWithString:[@" · " stringByAppendingString:more]
                attributes:@{NSFontAttributeName: font,
                             NSForegroundColorAttributeName: [NSColor colorWithWhite:dark ? 0.62 : 0.42 alpha:1]}]];
    CGFloat width = MIN(kLabelRoom - 10, ceil(text.size.width)), height = 20;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.labelText.string = text;
    self.labelText.truncationMode = kCATruncationEnd;
    self.labelText.frame = CGRectMake(8, 3, width, 14);
    self.label.bounds = CGRectMake(0, 0, width + 16, height);
    [self layoutForSide];
    [CATransaction commit];
}

// The box at the window's end that meets the panel, the label beyond it.
// Not animated: the window moves in the same frame, so the icon stays where it is on the screen.
- (void)layoutForSide {
    BOOL left = [self.side isEqual:@"left"];
    CGFloat box = self.boxSize, labelWidth = NSWidth(self.label.bounds);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.box.frame = CGRectMake(left ? self.windowWidth - box : 0, 0, box, box);
    self.label.position = CGPointMake(left ? self.windowWidth - box - 2 - labelWidth / 2 : box + 2 + labelWidth / 2,
                                      box / 2);
    [CATransaction commit];
}

// The label comes out beside the icon, lifting 3px as it fades in; it goes quicker.
- (void)showLabel:(BOOL)on {
    [CATransaction begin];
    [CATransaction setAnimationDuration:Calm() ? 0 : on ? 0.25 : 0.12];
    self.label.opacity = on ? 1 : 0;
    self.label.transform = on || Calm() ? CATransform3DIdentity : CATransform3DMakeTranslation(0, -3, 0);
    [CATransaction commit];
}

#pragma mark Where it is

- (void)setShown:(BOOL)shown {
    _shown = shown;
    [self aim];
}

- (void)glassAt:(NSRect)glass side:(NSString *)side duration:(NSTimeInterval)duration {
    CFTimeInterval now = CACurrentMediaTime();
    // Opening out of the cat, the glass is told where it's headed as it starts spreading, and told again there once it
    // has come to rest: the icon comes out then.
    BOOL opened = self.waitingForOpen && duration == 0 && NearlySame(glass, self.glass);
    self.glassFrom = [self glassNow:now];
    self.glass = glass;
    self.glassSince = now;
    self.glassFor = Calm() || NSIsEmptyRect(self.glassFrom) ? 0 : duration;
    if (duration == 0 && !NSEqualRects(self.glassFrom, glass)) {
        self.movedAt = now;
        if (self.outTo > 0 || self.alongTo != 0) {
            self.outTo = 0;
            self.alongTo = 0;
        }
    }
    [self glassMoving:glass over:self.glassFor];
    // With moves of its own, or held by a press, it keeps to its side whatever the glass does meanwhile.
    if (!self.keepsPlace && !self.pressing) [self takeSide:side];
    [self place];
    [self kick];
    if (opened) [self panelOpened];
}

// The side the icons are on now: changing to it at once while out of sight, else after a moment, under the glass.
- (void)takeSide:(NSString *)side {
    if (!self.side) {
        self.side = side;
        [self layoutForSide];
    } else if ([side isEqual:self.side]) {
        self.sideAhead = nil;
    } else if (self.window.alphaValue == 0 || Calm()) {
        // Out of sight, it just changes sides.
        self.side = side;
        [self layoutForSide];
    } else if (![side isEqual:self.sideAhead]) {
        // In sight, it waits a moment, then travels under the glass, unless the panel has gone back meanwhile.
        self.sideAhead = side;
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kCrossingWait * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [weakSelf cross:side]; });
    }
}

- (void)cross:(NSString *)side {
    if (![side isEqual:self.sideAhead] || [side isEqual:self.side]) return;
    // Still crossing the other way: it finishes first, then comes back, so it never jumps.
    if (self.crossingFrom) {
        NSTimeInterval left = kCrossing - (CACurrentMediaTime() - self.crossingSince);
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((MAX(0, left) + 0.05) * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [weakSelf cross:side]; });
        return;
    }
    self.sideAhead = nil;
    self.poppingSince = 0;
    self.crossingFrom = self.side;
    self.crossingSince = CACurrentMediaTime();
    self.crossingOut = self.out;
    self.side = side;
    [self kick];
}

- (NSRect)glassNow:(CFTimeInterval)now {
    if (self.glassFor <= 0) return self.glass;
    // On the curve the panel's edges move on as the reader opens and closes, so it keeps to the glass's corner.
    return LerpRect(self.glassFrom, self.glass, Eased(kSettle, (now - self.glassSince) / self.glassFor));
}

- (NSRect)glassNow {
    return [self glassNow:CACurrentMediaTime()];
}

- (void)panelOpening {
    self.waitingForOpen = YES;
    NSUInteger run = ++self.openingRun;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kOpeningAtMost * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (weakSelf.openingRun == run) [weakSelf panelOpened];
    });
    [self aim];
}

// The panel has opened: the icon comes out from under the glass where it waited, with the bounce.
- (void)panelOpened {
    if (!self.waitingForOpen) return;
    self.waitingForOpen = NO;
    self.openingRun++;
    if (self.visible && !Calm() && !self.crossingFrom) {
        self.window.alphaValue = 1;
        self.out = kEdgeTucked;
        self.poppingSince = CACurrentMediaTime();
    }
    [self aim];
}

- (BOOL)visible {
    return self.shown && !self.tucking && !self.waitingForOpen && !self.turned && (!self.away || self.showsWhileAway)
           && [self wantsOut];
}

- (BOOL)busy {
    return self.crossingFrom || self.sideAhead || self.poppingSince;
}

- (BOOL)movedJustNow {
    return CACurrentMediaTime() - self.movedAt < kStillAfterMove;
}

// Where it's headed, from whether it's out and the pointer.
- (void)aim {
    BOOL visible = self.visible;
    if (!visible) {
        self.pressing = NO;     // once it has gone, no press is still on it
        self.poppingSince = 0;  // going back under from wherever it is
        self.outTo = kEdgeTucked;
        self.alongTo = 0;
        self.over = NO;
        self.window.ignoresMouseEvents = YES;
        [self showLabel:NO];
    } else {
        if (self.window.alphaValue == 0) self.window.alphaValue = 1;  // still under the glass: it comes out from there
        if (self.outTo < 0) self.outTo = 0;
    }
    [self aimed:visible];
    [self kick];
}

- (void)tuckThen:(void (^)(void))then {
    self.tucking = YES;
    self.afterTuck = then;
    [self aim];
}

- (void)untuck {
    self.tucking = NO;
    self.afterTuck = nil;
    [self aim];
}

- (void)endTuck {
    if (!self.afterTuck) self.tucking = NO;
}

- (void)pointerAt:(NSPoint)point {
    self.pointer = point;
    if (!self.visible || self.busy || self.pressing || self.keepsPlace) return;
    NSPoint now = [self centerOut:self.out along:self.along];
    // Only the part outside the glass: a click on the part under it goes to the panel above.
    BOOL over = hypot(point.x - now.x, point.y - now.y) <= self.reach + 2 && !NSPointInRect(point, self.glass);
    if (over != self.over) {
        self.over = over;
        self.window.ignoresMouseEvents = !over;
        [self showLabel:over];
    }
    [self pointerMoved:point over:over];
}

// Its middle on the screen: `out` from the glass's edge on `side`, `along` it from its resting height.
- (NSPoint)centerOut:(CGFloat)out along:(CGFloat)along glass:(NSRect)glass side:(NSString *)side {
    CGFloat y = [self heightBeside:glass] + along;
    return NSMakePoint([side isEqual:@"left"] ? NSMinX(glass) - out : NSMaxX(glass) + out, y);
}

- (NSPoint)centerOut:(CGFloat)out along:(CGFloat)along {
    return [self centerOut:out along:along glass:self.glass side:self.side];
}

- (void)place {
    CFTimeInterval now = CACurrentMediaTime();
    NSRect glass = [self glassNow:now];
    NSPoint center;
    if (self.crossingFrom) {
        // In under the glass on the side it was on, across beneath the panel, and out on the other with one small
        // bounce.
        CGFloat p = (now - self.crossingSince) / kCrossing;
        NSString *from = self.crossingFrom, *to = self.side;
        if (p < 0.25) {
            center = [self centerOut:Lerp(self.crossingOut, kEdgeTucked, Ease(p / 0.25)) along:0 glass:glass side:from];
        } else if (p < 0.65) {
            NSPoint a = [self centerOut:kEdgeTucked along:0 glass:glass side:from];
            NSPoint b = [self centerOut:kEdgeTucked along:0 glass:glass side:to];
            CGFloat q = EaseInOut((p - 0.25) / 0.4);
            center = NSMakePoint(Lerp(a.x, b.x, q), a.y);
            if (q >= 0.5 && ![self.boxSide isEqual:to]) [self layoutForSide];
        } else {
            // Out past its resting place by the bounce, then back to it; one that's to stay tucked just stays under.
            CGFloat out = self.visible ? Bounced(MIN(1, (p - 0.65) / 0.35)) : kEdgeTucked;
            center = [self centerOut:out along:0 glass:glass side:to];
            self.out = out;
            self.along = 0;
        }
        if (p >= 1) {
            self.crossingFrom = nil;
            self.outTo = self.out;
            self.alongTo = 0;
        }
    } else if (self.poppingSince) {
        // Out from under the glass once the panel has opened, past its resting place by the bounce, then back to it.
        CGFloat t = MIN(1, (now - self.poppingSince) / kPopOut);
        self.out = Bounced(t);
        self.along = 0;
        if (t >= 1) self.poppingSince = 0;
        center = [self centerOut:self.out along:0 glass:glass side:self.side];
    } else {
        center = [self centerOut:self.out along:self.along glass:glass side:self.side];
    }
    [self placeAt:center];
}

- (void)placeAt:(NSPoint)middle {
    BOOL boxLeft = [self.boxSide isEqual:@"left"];
    CGFloat box = self.boxSize;
    NSPoint origin = NSMakePoint(boxLeft ? middle.x + box / 2 - self.windowWidth : middle.x - box / 2,
                                 middle.y - box / 2);
    [self.window setFrameOrigin:NSMakePoint(round(origin.x), round(origin.y))];
}

// Which end of the window the box is at now.
- (NSString *)boxSide {
    return NSMinX(self.box.frame) > 0 ? @"left" : @"right";
}

#pragma mark Moving

// Moves run on a frame timer, only while something is on its way.
- (void)kick {
    if (self.frameTimer) return;
    __weak typeof(self) weakSelf = self;
    self.frameTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60 repeats:YES block:^(NSTimer *timer) {
        [weakSelf frame];
    }];
    [NSRunLoop.currentRunLoop addTimer:self.frameTimer forMode:NSRunLoopCommonModes];
}

- (void)frame {
    CFTimeInterval now = CACurrentMediaTime();
    CFTimeInterval dt = self.lastFrame ? MIN(0.05, now - self.lastFrame) : 1.0 / 60;
    self.lastFrame = now;
    if (!self.crossingFrom && !self.poppingSince) [self step:dt];
    [self place];
    [self drawAt:now];
    BOOL glassMoving = self.glassFor > 0 && now - self.glassSince < self.glassFor;
    BOOL settled = !self.crossingFrom && !self.poppingSince && !glassMoving && [self settled];
    if (self.tucking && self.out <= kEdgeTucked + 1) {
        void (^then)(void) = self.afterTuck;
        self.afterTuck = nil;
        if (then) then();
    }
    if (!settled) return;
    [self.frameTimer invalidate];
    self.frameTimer = nil;
    self.lastFrame = 0;
    if (!self.visible && self.out <= kEdgeTucked) self.window.alphaValue = 0;
}

#pragma mark What each icon fills in

- (BOOL)wantsOut {
    return YES;
}

- (CGFloat)heightBeside:(NSRect)glass {
    return NSMidY(glass);
}

// Each frame closes a share of what's left, so it eases out, and follows the pointer smoothly as it moves.
- (void)step:(CFTimeInterval)dt {
    CGFloat share = Calm() ? 1 : 0.2;
    self.out += (self.outTo - self.out) * share;
    self.along += (self.alongTo - self.along) * share;
    if (fabs(self.outTo - self.out) < 0.2) self.out = self.outTo;
    if (fabs(self.alongTo - self.along) < 0.2) self.along = self.alongTo;
}

- (BOOL)settled {
    return self.out == self.outTo && self.along == self.alongTo;
}

- (void)drawAt:(CFTimeInterval)now {
}

- (void)pointerMoved:(NSPoint)point over:(BOOL)over {
}

- (void)downAt:(NSPoint)point {
    [self pressed];
}

- (void)draggedTo:(NSPoint)point {
}

- (void)upAt:(NSPoint)point {
}

- (void)pressed {
}

- (void)aimed:(BOOL)visible {
}

- (void)glassMoving:(NSRect)glass over:(NSTimeInterval)duration {
}

- (BOOL)keepsPlace {
    return NO;
}

- (BOOL)showsWhileAway {
    return NO;
}

@end
