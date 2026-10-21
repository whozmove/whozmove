// SpotifyToken: Spotify's round token, tucked half under the panel at its bottom corner.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// It's a small window of its own that the panel holds under itself, so it's really beneath the glass: the glass hides
// half of it, it moves with the panel as it's dragged, and the panel's own window doesn't grow to make room for it
// (which would take clicks from the desktop beside it). It lets clicks through except while the pointer is over the
// disc, and never takes the keyboard.
//
// Its motion keeps to CONTRIBUTING.md's rules. It's always the same token: changing sides, it goes in under the glass
// at one corner, travels under the panel and comes out at the other, and never jumps. As the pointer comes near, it
// leans out toward it and slides along the edge to meet it (the "magnet"), and the label saying what a press does
// comes out beside it, in its own lane outside the panel. Pressed, it squashes, then goes in under the glass before
// Spotify is asked to play, so it's gone before the strip grows; a song paused comes back out only once the strip has
// folded. Opening out of the cat, the panel opens first, and only then does the token come out, with the same small
// bounce as on the other side. Reduced motion has it fade in place instead.
#import "SpotifyToken.h"
#import "Spotify.h"
#import "SpotifyFacts.h"
#import <QuartzCore/QuartzCore.h>

// The disc, the box it's drawn in (with its ring and shadow), and the window: the box, then room for the label.
static const CGFloat kDisc = 36, kBox = 52, kLabelRoom = 230, kWindowWidth = kBox + kLabelRoom;
// How far it sits from the glass's bottom edge (its centre), at most: the collapsed panel's header is less tall.
static const CGFloat kAboveBottom = 30;
// How far out from the glass's edge its centre goes: tucked (all of it under the glass), at rest (half out), pointed
// at, and at most as the pointer comes near; and how far along the edge it slides to meet the pointer, and from how
// far away the pointer pulls it.
static const CGFloat kTucked = -26, kPointedAt = 9, kMostOut = 13, kMostAlong = 12, kPullFrom = 120;
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
// After the panel has moved, the token keeps still this long before it leans toward the pointer again: the pointer
// was dragging the panel, not reaching for the token.
static const NSTimeInterval kStillAfterMove = 0.6;

NSString *TokenSideFor(NSRect list, NSRect screen, NSString *current) {
    CGFloat middle = NSMidX(screen), at = NSMidX(list);
    if ([current isEqual:@"right"]) return at > middle + kLeeway ? @"left" : @"right";
    if ([current isEqual:@"left"]) return at < middle - kLeeway ? @"right" : @"left";
    return at < middle ? @"right" : @"left";
}

static BOOL Calm(void) { return NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion; }
static CGFloat Ease(CGFloat t) { t = MAX(0, MIN(1, t)); return 1 - pow(1 - t, 3); }
static CGFloat EaseInOut(CGFloat t) { t = MAX(0, MIN(1, t)); return t < .5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2; }
static CGFloat Lerp(CGFloat a, CGFloat b, CGFloat t) { return a + (b - a) * t; }

// The curve the panel's edges move on as the reader opens and closes (moveEdgesTo: in PanelWindow.m), a cubic Bézier
// from (0,0) to (1,1) through (.2,.8) and (.2,1): how far along it is `t` of the way through, so the token keeps to the
// glass's corner all the way.
static CGFloat EdgeCurve(CGFloat t) {
    t = MAX(0, MIN(1, t));
    const CGFloat x1 = 0.2, y1 = 0.8, x2 = 0.2, y2 = 1;
    CGFloat lo = 0, hi = 1, u = t;
    for (int i = 0; i < 30; i++) {  // the curve's own parameter where its x is t
        u = (lo + hi) / 2;
        CGFloat x = 3 * (1 - u) * (1 - u) * u * x1 + 3 * (1 - u) * u * u * x2 + u * u * u;
        if (x < t) lo = u; else hi = u;
    }
    return 3 * (1 - u) * (1 - u) * u * y1 + 3 * (1 - u) * u * u * y2 + u * u * u;
}
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
    return t < 0.55 ? Lerp(kTucked, kBounce, Ease(t / 0.55)) : Lerp(kBounce, 0, EaseInOut((t - 0.55) / 0.45));
}

// The token's window: never key, so pressing it leaves the keyboard where it was.
@interface TokenWindow : NSPanel
@end

@implementation TokenWindow
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

@interface TokenView : NSView
@property (copy) void (^onDown)(void);
@end

@implementation TokenView
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (void)mouseDown:(NSEvent *)event { if (self.onDown) self.onDown(); }
@end

@interface SpotifyToken ()
@property (strong) TokenWindow *panel;
@property (strong) TokenView *view;
@property (strong) CALayer *box, *holder, *disc, *icon, *cover, *badge, *label;
@property (strong) CAShapeLayer *ringTrack, *ring;
@property (strong) CATextLayer *labelText;
@property (copy) NSDictionary *token;
@property (copy) NSString *state;        // as shown: missing, ready, paused, refused or hidden
@property (copy) NSString *side;         // left or right
@property (copy) NSString *artShown;     // the address of the cover loaded into it, the song's or an earlier one's
@property (strong) NSImage *appIcon;      // Spotify's icon, taken from the app once it's there
// Where the glass is, easing from where it was over `glassFor` seconds from `glassSince`.
@property (assign) NSRect glass, glassFrom;
@property (assign) CFTimeInterval glassSince, glassFor;
// How far out from the edge and along it the disc is now, and where it's headed.
@property (assign) CGFloat out, along, outTo, alongTo;
@property (assign) BOOL over;            // the pointer is over the disc
@property (assign) BOOL tucking;         // pressed: going under the glass before what was pressed happens
@property (copy) void (^afterTuck)(void);
@property (assign) BOOL waitingForFold;  // a song paused: out once the strip has folded
@property (assign) BOOL waitingForOpen;  // the panel opening out of the cat: out once its glass has come to rest
@property (assign) NSUInteger openingRun;  // which opening the wait is for, so a late fallback can't end a newer one
@property (assign) CFTimeInterval poppingSince;  // coming out with the bounce once the panel has opened, or 0
@property (strong) NSNumber *tokenWasInStrip;  // hidden because the strip showed the song
// Changing sides: from which side, and since when.
@property (copy) NSString *crossingFrom;
@property (assign) CFTimeInterval crossingSince;
@property (assign) CGFloat crossingOut;
@property (copy) NSString *sideAhead;    // the side it's about to cross to, once it has waited
@property (assign) CFTimeInterval movedAt;  // when the panel last moved
@property (strong) NSTimer *frameTimer;
@end

@implementation SpotifyToken

- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.panel = [[TokenWindow alloc] initWithContentRect:NSMakeRect(0, 0, kWindowWidth, kBox)
                                                styleMask:NSWindowStyleMaskBorderless
                                                          | NSWindowStyleMaskNonactivatingPanel
                                                  backing:NSBackingStoreBuffered defer:NO];
    self.panel.level = NSFloatingWindowLevel;
    self.panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces
                                    | NSWindowCollectionBehaviorFullScreenAuxiliary;
    self.panel.hidesOnDeactivate = NO;
    self.panel.opaque = NO;
    self.panel.backgroundColor = NSColor.clearColor;
    self.panel.hasShadow = NO;
    self.panel.ignoresMouseEvents = YES;
    self.panel.alphaValue = 0;
    self.view = [[TokenView alloc] initWithFrame:NSMakeRect(0, 0, kWindowWidth, kBox)];
    self.view.wantsLayer = YES;
    self.panel.contentView = self.view;
    __weak typeof(self) weakSelf = self;
    self.view.onDown = ^{ [weakSelf pressed]; };
    [self buildLayers];
    self.out = self.outTo = kTucked;
    self.state = @"hidden";
    return self;
}

- (NSWindow *)window {
    return self.panel;
}

#pragma mark Drawing

- (void)buildLayers {
    CGFloat scale = NSScreen.mainScreen.backingScaleFactor ?: 2;
    CGFloat c = kBox / 2;
    self.box = [CALayer layer];
    self.box.frame = CGRectMake(0, 0, kBox, kBox);
    [self.view.layer addSublayer:self.box];

    CGPathRef ringPath = CGPathCreateWithEllipseInRect(CGRectMake(c - 20.5, c - 20.5, 41, 41), NULL);
    self.ringTrack = [CAShapeLayer layer];
    self.ring = [CAShapeLayer layer];
    for (CAShapeLayer *each in @[self.ringTrack, self.ring]) {
        each.frame = self.box.bounds;
        each.path = ringPath;
        each.fillColor = NSColor.clearColor.CGColor;
        each.lineWidth = 2;
        each.opacity = 0;
        [self.box addSublayer:each];
    }
    CGPathRelease(ringPath);
    self.ringTrack.strokeColor = [NSColor colorWithWhite:1 alpha:0.12].CGColor;
    self.ring.strokeColor = [NSColor colorWithWhite:1 alpha:0.85].CGColor;
    // Clockwise from the top, as a clock's hand goes.
    self.ring.transform = CATransform3DMakeRotation(M_PI_2, 0, 0, 1);
    self.ring.transform = CATransform3DScale(self.ring.transform, 1, -1, 1);

    self.holder = [CALayer layer];
    self.holder.frame = CGRectMake(c - kDisc / 2, c - kDisc / 2, kDisc, kDisc);
    self.holder.shadowColor = NSColor.blackColor.CGColor;
    self.holder.shadowOpacity = 0.4;
    self.holder.shadowRadius = 6;
    self.holder.shadowOffset = CGSizeMake(0, -3);
    CGPathRef discPath = CGPathCreateWithEllipseInRect(self.holder.bounds, NULL);
    self.holder.shadowPath = discPath;
    CGPathRelease(discPath);
    [self.box addSublayer:self.holder];

    self.disc = [CALayer layer];
    self.disc.frame = self.holder.bounds;
    self.disc.cornerRadius = kDisc / 2;
    self.disc.masksToBounds = YES;
    self.disc.borderWidth = 0.5;
    self.disc.borderColor = [NSColor colorWithWhite:1 alpha:0.18].CGColor;
    [self.holder addSublayer:self.disc];
    // An app's icon has a margin round its picture: drawn larger than the disc, the picture fills it.
    self.icon = [CALayer layer];
    self.icon.frame = CGRectInset(self.disc.bounds, -4, -4);
    self.icon.contentsGravity = kCAGravityResizeAspectFill;
    self.icon.contentsScale = scale;
    [self.disc addSublayer:self.icon];
    self.cover = [CALayer layer];
    self.cover.frame = self.disc.bounds;
    self.cover.contentsGravity = kCAGravityResizeAspectFill;
    self.cover.contentsScale = scale;
    self.cover.opacity = 0;
    [self.disc addSublayer:self.cover];
    // The badge at the disc's top corner: Spotify's icon on a paused song's cover, or an amber dot when macOS hasn't
    // allowed Whozmove to control Spotify.
    self.badge = [CALayer layer];
    self.badge.frame = CGRectMake(c - kDisc / 2 - 2, c + kDisc / 2 + 2 - 14, 14, 14);
    self.badge.cornerRadius = 7;
    self.badge.masksToBounds = YES;
    self.badge.borderWidth = 1.5;
    self.badge.borderColor = [NSColor colorWithSRGBRed:0.12 green:0.12 blue:0.15 alpha:1].CGColor;
    self.badge.contentsGravity = kCAGravityResizeAspectFill;
    self.badge.contentsScale = scale;
    self.badge.opacity = 0;
    [self.box addSublayer:self.badge];

    // The label: what a press does, beside the token, outside the panel.
    self.label = [CALayer layer];
    self.label.backgroundColor = [NSColor colorWithSRGBRed:0.08 green:0.08 blue:0.106 alpha:0.94].CGColor;
    self.label.cornerRadius = 7;
    self.label.borderWidth = 0.5;
    self.label.borderColor = [NSColor colorWithWhite:1 alpha:0.14].CGColor;
    self.label.opacity = 0;
    self.labelText = [CATextLayer layer];
    self.labelText.contentsScale = scale;
    [self.label addSublayer:self.labelText];
    [self.view.layer addSublayer:self.label];
}

// Spotify's mark, drawn, for when there's no app on this Mac to take its icon from: the same green disc and three
// sound waves, so the token looks the same before Spotify is installed as after. Drawn with the margin an app's icon
// has, so it fills the disc the same way.
static NSImage *SpotifyMark(void) {
    static NSImage *mark;
    if (mark) return mark;
    mark = [NSImage imageWithSize:NSMakeSize(96, 96) flipped:YES drawingHandler:^BOOL(NSRect rect) {
        [[NSColor colorWithSRGBRed:0.12 green:0.84 blue:0.38 alpha:1] set];
        [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(rect, 8, 8)] fill];
        NSAffineTransform *place = [NSAffineTransform transform];
        [place translateXBy:48 - 12 * 3.1 yBy:48 - 12.6 * 3.1];
        [place scaleBy:3.1];
        NSBezierPath *waves = [NSBezierPath bezierPath];
        [waves moveToPoint:NSMakePoint(5, 9.2)];
        [waves curveToPoint:NSMakePoint(19, 10.4) controlPoint1:NSMakePoint(9.6, 7.7) controlPoint2:NSMakePoint(14.6, 8.1)];
        [waves moveToPoint:NSMakePoint(6, 12.9)];
        [waves curveToPoint:NSMakePoint(17.3, 13.9) controlPoint1:NSMakePoint(9.8, 11.8) controlPoint2:NSMakePoint(13.8, 12.1)];
        [waves moveToPoint:NSMakePoint(7, 16.4)];
        [waves curveToPoint:NSMakePoint(15.6, 17.2) controlPoint1:NSMakePoint(10, 15.6) controlPoint2:NSMakePoint(13, 15.8)];
        [waves transformUsingAffineTransform:place];
        waves.lineWidth = 2.4 * 3.1;
        waves.lineCapStyle = NSLineCapStyleRound;
        [[NSColor colorWithWhite:0.04 alpha:1] set];
        [waves stroke];
        return YES;
    }];
    return mark;
}

static CGImageRef ImageOf(NSImage *image, CGFloat size) {
    NSRect rect = NSMakeRect(0, 0, size, size);
    return [image CGImageForProposedRect:&rect context:nil hints:nil];
}

- (void)show:(NSDictionary *)token {
    NSString *was = self.state;
    self.token = token;
    NSString *state = token[@"state"] ?: @"hidden";
    // A song the strip showed comes out once the strip has gone, so the two never overlap.
    if ([was isEqual:@"hidden"] && ![state isEqual:@"hidden"] && [self.tokenWasInStrip boolValue]) {
        self.waitingForFold = YES;
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf stripFolded];
        });
    }
    self.tokenWasInStrip = token[@"strip"];
    self.state = state;
    // A press still going under the glass carries on; once it has gone through, what Spotify says next is shown.
    if (!self.afterTuck) self.tucking = NO;
    [self drawState:![was isEqual:@"hidden"]];
    [self aim];
}

- (void)untuck {
    self.tucking = NO;
    self.afterTuck = nil;
    [self aim];
}

- (void)stripFolded {
    if (!self.waitingForFold) return;
    self.waitingForFold = NO;
    [self aim];
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

// The panel has opened: the token comes out from under the glass where it waited, with the bounce.
- (void)panelOpened {
    if (!self.waitingForOpen) return;
    self.waitingForOpen = NO;
    self.openingRun++;
    if (self.visible && !Calm() && !self.crossingFrom) {
        self.panel.alphaValue = 1;
        self.out = kTucked;
        self.poppingSince = CACurrentMediaTime();
    }
    [self aim];
}

// What the disc wears for its state. A change while it's out cross-fades; one while it's tucked away just changes.
- (void)drawState:(BOOL)fade {
    NSString *state = self.state;
    if ([state isEqual:@"hidden"]) return;
    BOOL missing = [state isEqual:@"missing"], refused = [state isEqual:@"refused"];
    BOOL song = [state isEqual:@"paused"];
    // Spotify's icon is taken from the app once, when it's there (looking it up can be slow); until then its mark.
    if (missing) self.appIcon = nil;
    else if (!self.appIcon) {
        NSURL *app = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:kSpotifyAppId];
        self.appIcon = app ? [NSWorkspace.sharedWorkspace iconForFile:app.path] : nil;
    }
    NSImage *icon = self.appIcon ?: SpotifyMark();
    BOOL coverReady = song && [self.artShown isEqual:self.token[@"artUrl"]];
    [CATransaction begin];
    [CATransaction setAnimationDuration:fade && !Calm() ? 0.4 : 0];
    self.icon.contents = (__bridge id)ImageOf(icon, 96);
    self.icon.opacity = coverReady ? 0 : 1;
    self.disc.backgroundColor = [NSColor colorWithWhite:0.12 alpha:1].CGColor;
    self.cover.opacity = coverReady ? 1 : 0;
    self.ringTrack.opacity = self.ring.opacity = song ? 1 : 0;
    self.ring.strokeEnd = song ? [self.token[@"progress"] doubleValue] : 0;
    self.badge.opacity = song || refused ? 1 : 0;
    self.badge.contents = song ? (__bridge id)ImageOf(icon, 32) : nil;
    self.badge.backgroundColor = refused ? [NSColor colorWithSRGBRed:0.95 green:0.70 blue:0.24 alpha:1].CGColor
                                         : NSColor.clearColor.CGColor;
    [CATransaction commit];
    if (song && !coverReady) [self loadCover:self.token[@"artUrl"]];
    [self drawLabel];
}

// The song's cover, once it has loaded: until then, or if it has none or it doesn't load, Spotify's icon, never an
// earlier song's cover.
- (void)loadCover:(NSString *)address {
    NSURL *url = address.length ? [NSURL URLWithString:address] : nil;
    if (!url) return;
    __weak typeof(self) weakSelf = self;
    [[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
        NSImage *image = data ? [[NSImage alloc] initWithData:data] : nil;
        if (!image) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            SpotifyToken *token = weakSelf;
            if (![token.token[@"artUrl"] isEqual:address]) return;
            token.artShown = address;
            BOOL song = [token.state isEqual:@"paused"];
            [CATransaction begin];
            [CATransaction setAnimationDuration:Calm() ? 0 : 0.5];
            token.cover.contents = (__bridge id)ImageOf(image, 96);
            token.cover.opacity = song ? 1 : 0;
            token.icon.opacity = song ? 0 : 1;
            [CATransaction commit];
        });
    }] resume];
}

- (void)drawLabel {
    NSString *state = self.state, *what = nil, *more = nil;
    if ([state isEqual:@"missing"]) { what = @"Download"; more = @"Spotify"; }
    else if ([state isEqual:@"ready"]) { what = @"Play"; more = @"Spotify"; }
    else if ([state isEqual:@"paused"]) { what = [@"Resume " stringByAppendingString:self.token[@"title"] ?: @""];
                                          more = self.token[@"artist"]; }
    else if ([state isEqual:@"refused"]) { what = @"Allow in Settings"; more = @"to control Spotify"; }
    if (!what) return;
    NSFont *font = [NSFont systemFontOfSize:11];
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:what attributes:@{
        NSFontAttributeName: font, NSForegroundColorAttributeName: [NSColor colorWithWhite:0.93 alpha:1]}];
    if (more.length)
        [text appendAttributedString:[[NSAttributedString alloc]
            initWithString:[@" · " stringByAppendingString:more]
                attributes:@{NSFontAttributeName: font,
                             NSForegroundColorAttributeName: [NSColor colorWithWhite:0.62 alpha:1]}]];
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
// Not animated: the window moves in the same frame, so the disc stays where it is on the screen.
- (void)layoutForSide {
    BOOL left = [self.side isEqual:@"left"];
    CGFloat labelWidth = NSWidth(self.label.bounds);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.box.frame = CGRectMake(left ? kWindowWidth - kBox : 0, 0, kBox, kBox);
    self.label.position = CGPointMake(left ? kWindowWidth - kBox - 2 - labelWidth / 2 : kBox + 2 + labelWidth / 2,
                                      kBox / 2);
    [CATransaction commit];
}

#pragma mark Where it is

- (void)setShown:(BOOL)shown {
    _shown = shown;
    [self aim];
}

- (void)glassAt:(NSRect)glass list:(NSRect)list screen:(NSRect)screen duration:(NSTimeInterval)duration {
    CFTimeInterval now = CACurrentMediaTime();
    // Opening out of the cat, the glass is told where it's headed as it starts spreading, and told again there once it
    // has come to rest: the token comes out then.
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
    NSString *side = TokenSideFor(list, screen, self.side);
    if (!self.side) {
        self.side = side;
        [self layoutForSide];
    } else if ([side isEqual:self.side]) {
        self.sideAhead = nil;
    } else if (self.panel.alphaValue == 0 || Calm()) {
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
    [self place];
    [self kick];
    if (opened) [self panelOpened];
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
    return LerpRect(self.glassFrom, self.glass, EdgeCurve((now - self.glassSince) / self.glassFor));
}

- (BOOL)visible {
    return self.shown && !self.tucking && !self.waitingForFold && !self.waitingForOpen
           && ![self.state isEqual:@"hidden"];
}

// Where the disc is headed, from its state and the pointer.
- (void)aim {
    if (!self.visible) {
        self.poppingSince = 0;  // going back under from wherever it is
        self.outTo = kTucked;
        self.alongTo = 0;
        self.over = NO;
        self.panel.ignoresMouseEvents = YES;
        [self showLabel:NO];
    } else {
        if (self.panel.alphaValue == 0) self.panel.alphaValue = 1;  // still under the glass: it comes out from there
        if (self.outTo < 0) self.outTo = 0;
    }
    [self kick];
}

- (void)pointerAt:(NSPoint)point {
    if (!self.visible || self.crossingFrom || self.sideAhead || self.poppingSince) return;
    BOOL still = CACurrentMediaTime() - self.movedAt < kStillAfterMove || NSEvent.pressedMouseButtons != 0;
    NSPoint rest = [self centerOut:0 along:0 glass:self.glass side:self.side];
    CGFloat dx = point.x - rest.x, dy = point.y - rest.y;
    CGFloat pull = MAX(0, 1 - hypot(dx, dy) / kPullFrom);
    NSPoint now = [self centerOut:self.out along:self.along glass:self.glass side:self.side];
    // Only the part outside the glass: a click on the part under it goes to the panel above.
    BOOL over = hypot(point.x - now.x, point.y - now.y) <= kDisc / 2 + 2 && !NSPointInRect(point, self.glass);
    CGFloat outTo = MAX(pull * kMostOut, over ? kPointedAt : 0);
    CGFloat alongTo = MAX(-kMostAlong, MIN(kMostAlong, dy * 0.3 * pull));
    if (Calm() || still) { outTo = over && !still ? kPointedAt : 0; alongTo = 0; }
    if (over != self.over) {
        self.over = over;
        self.panel.ignoresMouseEvents = !over;
        [self showLabel:over];
    }
    if (fabs(outTo - self.outTo) < 0.1 && fabs(alongTo - self.alongTo) < 0.1) return;
    self.outTo = outTo;
    self.alongTo = alongTo;
    [self kick];
}

// The label comes out beside the token, lifting 3px as it fades in; it goes quicker.
- (void)showLabel:(BOOL)on {
    [CATransaction begin];
    [CATransaction setAnimationDuration:Calm() ? 0 : on ? 0.25 : 0.12];
    self.label.opacity = on ? 1 : 0;
    self.label.transform = on || Calm() ? CATransform3DIdentity : CATransform3DMakeTranslation(0, -3, 0);
    [CATransaction commit];
}

// The disc's centre on the screen: `out` from the glass's edge on `side`, `along` it from its resting height.
- (NSPoint)centerOut:(CGFloat)out along:(CGFloat)along glass:(NSRect)glass side:(NSString *)side {
    CGFloat y = NSMinY(glass) + MIN(kAboveBottom, NSHeight(glass) / 2) + along;
    return NSMakePoint([side isEqual:@"left"] ? NSMinX(glass) - out : NSMaxX(glass) + out, y);
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
            center = [self centerOut:Lerp(self.crossingOut, kTucked, Ease(p / 0.25)) along:0 glass:glass side:from];
        } else if (p < 0.65) {
            NSPoint a = [self centerOut:kTucked along:0 glass:glass side:from];
            NSPoint b = [self centerOut:kTucked along:0 glass:glass side:to];
            CGFloat q = EaseInOut((p - 0.25) / 0.4);
            center = NSMakePoint(Lerp(a.x, b.x, q), a.y);
            if (q >= 0.5 && ![self.boxSide isEqual:to]) [self layoutForSide];
        } else {
            // Out past its resting place by the bounce, then back to it; one that's to stay tucked just stays under.
            CGFloat out = self.visible ? Bounced(MIN(1, (p - 0.65) / 0.35)) : kTucked;
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
    BOOL boxLeft = [self.boxSide isEqual:@"left"];
    NSPoint origin = NSMakePoint(boxLeft ? center.x + kBox / 2 - kWindowWidth : center.x - kBox / 2,
                                 center.y - kBox / 2);
    [self.panel setFrameOrigin:NSMakePoint(round(origin.x), round(origin.y))];
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
    BOOL calm = Calm();
    // Each frame closes a share of what's left, so it eases out, and follows the pointer smoothly as it moves.
    CGFloat share = calm ? 1 : 0.2;
    if (!self.crossingFrom && !self.poppingSince) {
        self.out += (self.outTo - self.out) * share;
        self.along += (self.alongTo - self.along) * share;
        if (fabs(self.outTo - self.out) < 0.2) self.out = self.outTo;
        if (fabs(self.alongTo - self.along) < 0.2) self.along = self.alongTo;
    }
    [self place];
    BOOL glassMoving = self.glassFor > 0 && now - self.glassSince < self.glassFor;
    BOOL settled = !self.crossingFrom && !self.poppingSince && !glassMoving && self.out == self.outTo
                   && self.along == self.alongTo;
    if (self.tucking && self.out <= kTucked + 1) {
        void (^then)(void) = self.afterTuck;
        self.afterTuck = nil;
        if (then) then();
    }
    if (!settled) return;
    [self.frameTimer invalidate];
    self.frameTimer = nil;
    if (!self.visible && self.out <= kTucked) self.panel.alphaValue = 0;
}

#pragma mark Pressing

// Play and Resume squash the disc, then it goes in under the glass, and only then is Spotify asked: so it's gone
// before the strip grows. Download and Allow in Settings just open what they say.
- (void)pressed {
    if (!self.visible || !self.onPress) return;
    NSString *state = self.state;
    if (![state isEqual:@"ready"] && ![state isEqual:@"paused"]) return self.onPress(state);
    [self showLabel:NO];
    self.panel.ignoresMouseEvents = YES;
    __weak typeof(self) weakSelf = self;
    void (^tuck)(void) = ^{
        SpotifyToken *token = weakSelf;
        token.tucking = YES;
        token.afterTuck = ^{ if (weakSelf.onPress) weakSelf.onPress(state); };
        [token aim];
    };
    if (Calm()) return tuck();
    [CATransaction begin];
    [CATransaction setCompletionBlock:tuck];
    CAKeyframeAnimation *squash = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    squash.values = @[@1, @0.82, @1.06, @1];
    squash.keyTimes = @[@0, @0.35, @0.7, @1];
    squash.duration = 0.32;
    [self.holder addAnimation:squash forKey:@"squash"];
    [CATransaction commit];
}

@end
