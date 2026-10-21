// SpotifyToken: Spotify's round token, tucked half under the panel at its bottom corner.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// The core's EdgeIcon holds it under the glass, moves it with the panel and across to the other side, brings it out
// once the panel has opened, and puts its label beside it. What's Spotify's own: its disc, with Spotify's icon or the
// paused song's cover, the ring round it for how far into the song it is, and the badge at its corner; the "magnet",
// which leans it out toward the pointer as it comes near and slides it along the edge to meet it; and its press, which
// squashes the disc, then sends it in under the glass before Spotify is asked to play, so it's gone before the strip
// grows. A song paused comes back out only once the strip has folded.
#import "SpotifyToken.h"
#import "Spotify.h"
#import "SpotifyFacts.h"
#import <QuartzCore/QuartzCore.h>

// The disc, and the box it's drawn in (with its ring and shadow).
static const CGFloat kDisc = 36, kBox = 52;
// How far it sits from the glass's bottom edge (its centre), at most: the collapsed panel's header is less tall.
static const CGFloat kAboveBottom = 30;
// How far out from the glass's edge its centre goes when pointed at, and at most as the pointer comes near; and how far
// along the edge it slides to meet the pointer, and from how far away the pointer pulls it.
static const CGFloat kPointedAt = 9, kMostOut = 13, kMostAlong = 12, kPullFrom = 120;

static BOOL Calm(void) { return NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion; }

@interface SpotifyToken ()
@property (strong) CALayer *holder, *disc, *icon, *cover, *badge;
@property (strong) CAShapeLayer *ringTrack, *ring;
@property (copy) NSDictionary *token;
@property (copy) NSString *state;        // as shown: missing, ready, paused, refused or hidden
@property (copy) NSString *artShown;     // the address of the cover loaded into it, the song's or an earlier one's
@property (strong) NSImage *appIcon;      // Spotify's icon, taken from the app once it's there
@property (assign) BOOL waitingForFold;  // a song paused: out once the strip has folded
@property (strong) NSNumber *tokenWasInStrip;  // hidden because the strip showed the song
@end

@implementation SpotifyToken

- (instancetype)init {
    if (!(self = [super initWithBox:kBox reach:kDisc / 2])) return nil;
    [self buildLayers];
    [self paint];
    self.state = @"hidden";
    return self;
}

#pragma mark Drawing

- (void)buildLayers {
    CGFloat scale = NSScreen.mainScreen.backingScaleFactor ?: 2;
    CGFloat c = kBox / 2;
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
    // Clockwise from the top, as a clock's hand goes.
    self.ring.transform = CATransform3DMakeRotation(M_PI_2, 0, 0, 1);
    self.ring.transform = CATransform3DScale(self.ring.transform, 1, -1, 1);

    self.holder = [CALayer layer];
    self.holder.frame = CGRectMake(c - kDisc / 2, c - kDisc / 2, kDisc, kDisc);
    self.holder.shadowColor = NSColor.blackColor.CGColor;
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
    self.badge.contentsGravity = kCAGravityResizeAspectFill;
    self.badge.contentsScale = scale;
    self.badge.opacity = 0;
    [self.box addSublayer:self.badge];
}

// Its colours, the panel's: its ring, the disc's edge and its colour behind Spotify's icon, the badge's edge (the
// panel's dark, or its light, setting it apart from the disc), and its shadow, softer on the light panel; the label's
// are the edge icon's. Painted again whenever the panel turns light or dark.
- (void)paint {
    [super paint];
    BOOL dark = self.dark;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.ringTrack.strokeColor = [NSColor colorWithWhite:dark ? 1 : 0 alpha:0.12].CGColor;
    self.ring.strokeColor = [NSColor colorWithWhite:dark ? 1 : 0 alpha:dark ? 0.85 : 0.6].CGColor;
    self.holder.shadowOpacity = dark ? 0.4 : 0.22;
    self.disc.borderColor = [NSColor colorWithWhite:dark ? 1 : 0 alpha:dark ? 0.18 : 0.12].CGColor;
    self.disc.backgroundColor = [NSColor colorWithWhite:dark ? 0.12 : 0.95 alpha:1].CGColor;
    self.badge.borderColor = (dark ? [NSColor colorWithSRGBRed:0.12 green:0.12 blue:0.15 alpha:1]
                                   : [NSColor colorWithSRGBRed:0.96 green:0.96 blue:0.97 alpha:1]).CGColor;
    [CATransaction commit];
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
    [self endTuck];
    [self drawState:![was isEqual:@"hidden"]];
    [self aim];
}

- (void)stripFolded {
    if (!self.waitingForFold) return;
    self.waitingForFold = NO;
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
    self.cover.opacity = coverReady ? 1 : 0;
    self.ringTrack.opacity = self.ring.opacity = song ? 1 : 0;
    self.ring.strokeEnd = song ? [self.token[@"progress"] doubleValue] : 0;
    self.badge.opacity = song || refused ? 1 : 0;
    self.badge.contents = song ? (__bridge id)ImageOf(icon, 32) : nil;
    self.badge.backgroundColor = refused ? [NSColor colorWithSRGBRed:0.95 green:0.70 blue:0.24 alpha:1].CGColor
                                         : NSColor.clearColor.CGColor;
    [CATransaction commit];
    if (song && !coverReady) [self loadCover:self.token[@"artUrl"]];
    [self describePress];
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

// What a press does, for the label.
- (void)describePress {
    NSString *state = self.state, *what = nil, *more = nil;
    if ([state isEqual:@"missing"]) { what = @"Download"; more = @"Spotify"; }
    else if ([state isEqual:@"ready"]) { what = @"Play"; more = @"Spotify"; }
    else if ([state isEqual:@"paused"]) { what = [@"Resume " stringByAppendingString:self.token[@"title"] ?: @""];
                                          more = self.token[@"artist"]; }
    else if ([state isEqual:@"refused"]) { what = @"Allow in Settings"; more = @"to control Spotify"; }
    if (what) [self setLabel:what more:more];
}

#pragma mark Where it is

- (BOOL)wantsOut {
    return !self.waitingForFold && ![self.state isEqual:@"hidden"];
}

- (CGFloat)heightBeside:(NSRect)glass {
    return NSMinY(glass) + MIN(kAboveBottom, NSHeight(glass) / 2);
}

// The magnet: as the pointer comes near, the disc leans out toward it and slides along the edge to meet it; over it,
// it's out as far as pointed at. Not while the panel has just moved, nor while a button is held: the pointer was
// dragging the panel.
- (void)pointerMoved:(NSPoint)point over:(BOOL)over {
    BOOL still = self.movedJustNow || NSEvent.pressedMouseButtons != 0;
    NSPoint rest = [self centerOut:0 along:0];
    CGFloat dx = point.x - rest.x, dy = point.y - rest.y;
    CGFloat pull = MAX(0, 1 - hypot(dx, dy) / kPullFrom);
    CGFloat outTo = MAX(pull * kMostOut, over ? kPointedAt : 0);
    CGFloat alongTo = MAX(-kMostAlong, MIN(kMostAlong, dy * 0.3 * pull));
    if (Calm() || still) { outTo = over && !still ? kPointedAt : 0; alongTo = 0; }
    if (fabs(outTo - self.outTo) < 0.1 && fabs(alongTo - self.alongTo) < 0.1) return;
    self.outTo = outTo;
    self.alongTo = alongTo;
    [self kick];
}

#pragma mark Pressing

// Play and Resume squash the disc, then it goes in under the glass, and only then is Spotify asked: so it's gone
// before the strip grows. Download and Allow in Settings just open what they say.
- (void)pressed {
    if (!self.visible || !self.onPress) return;
    NSString *state = self.state;
    if (![state isEqual:@"ready"] && ![state isEqual:@"paused"]) return self.onPress(state);
    [self showLabel:NO];
    self.window.ignoresMouseEvents = YES;
    __weak typeof(self) weakSelf = self;
    void (^tuck)(void) = ^{
        [weakSelf tuckThen:^{ if (weakSelf.onPress) weakSelf.onPress(state); }];
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
