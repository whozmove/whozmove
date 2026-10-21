// SideCat: Whozmove beside the panel (SideCat.h).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// It's the cat's head alone, drawn from its own shapes (CatShape.h) in layers: its face, each ear (one flicks), its
// nose, its eyes (which close for a blink, and look about) and its eyes shut. It reacts with its face rather than by
// moving: it peeks out head first, tilted toward the edge, one ear and one eye clear of the glass, then, after a pause
// and a look at you, the rest of the way; as the pointer comes near it straightens and lifts its head, its eyes on the
// pointer; rested on, its eyes close slowly and open again, once; and an ear flicks when something new needs you.
// Asleep, its eyes are shut and its chin down; watching sessions work, its eyes drift over them; looking at you while
// something needs you, its head is up. Each value moves toward where it's going like a weight on a spring just stiff
// enough not to go past it, worked out exactly for however long a frame was (as the folded cat's eyes are, catSpring
// in panel/scripts/cat.js), on the edge icon's frame timer, which runs only while something is on its way; the eyes'
// drift is Core Animation's, so a watching cat costs nothing between moves.
//
// Pressed, it comes out in front of the glass at once, dipping under the press, its eyes on you, and the panel folds
// round it where it is: the folded glass's middle goes where its head, raised and grown, keeps its middle where its
// head's is now, so it only grows. It grows on the glass's own move, on the fold's curve, everything about it going
// from how it was to how the folded cat sits there, its shadow going as it does, so it ends as the page's folded cat
// is; the page's takes over there (catLanded, catShown), and this one goes back under the glass, out of sight. With
// reduced motion it fades as the panel does.
#import "SideCat.h"
#import "PanelWindow.h"
#import "Page.h"
#import "CatShape.h"
#import "Easing.h"

// Its head, from the cat's own units to points: 24 points across as it peeks, and as the folded cat's (cat.js, 448
// units to 92 points). Its raised head's middle is this many units below the folded glass's middle (cat.js's
// CAT_HEAD_AT); its shape is moved this far down within its box (cat.js's translate(0 8)).
static const CGFloat kPeekScale = 0.143, kFoldScale = 92.0 / 448, kHeadAt = 9, kHeadDown = 8;
// Its box, and how far from its middle a press counts; how far out from the glass's edge its middle goes when pointed
// at, and how far down from the glass's top it sits.
static const CGFloat kBox = 52, kReach = 18, kPointedAt = 9, kDown = 30;
// How far the pointer is noticed from, and woken at; how far its eyes turn at most (cat.js's CAT_GLANCE).
static const CGFloat kNotice = 150, kWake = 90, kGlance = 12;
// Peeking: how long it holds the first look, and then the pause before it's out; how long it stays awake after.
static const NSTimeInterval kPeekLook = 0.34, kPeekOut = 0.3, kAwakeAfterPeek = 2.6;
// Pressed: how long it dips before the panel folds, and how long it waits for the fold before going back.
static const NSTimeInterval kDip = 0.11, kFoldWait = 0.9, kLandWait = 1.5;

static BOOL Calm(void) { return NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion; }
static CGFloat Lerp(CGFloat a, CGFloat b, CGFloat t) { return a + (b - a) * t; }
static CGFloat Clamp(CGFloat v, CGFloat lo, CGFloat hi) { return MAX(lo, MIN(hi, v)); }
static CGFloat Smooth(CGFloat x) { return x * x * (3 - 2 * x); }

// A value on its way, as a weight on a spring just stiff enough (`k`) not to go past where it's going.
typedef struct { CGFloat x, v; } Spring;
static void Pull(Spring *s, CGFloat to, CGFloat k, CGFloat dt) {
    CGFloat w = sqrt(k), c1 = s->x - to, c2 = s->v + w * c1, e = exp(-w * dt);
    s->x = to + (c1 + c2 * dt) * e;
    s->v = (c2 - w * (c1 + c2 * dt)) * e;
}
static BOOL Still(Spring s, CGFloat to) { return fabs(s.x - to) < 0.01 && fabs(s.v) < 0.05; }

// The panel's own colour for its look, for the cat's eyes and nose (--panel in panel/styles/tokens.css): keep them
// matching.
static NSColor *PanelColour(NSString *look, BOOL dark) {
    BOOL black = [look isEqual:@"black"], glass = [look isEqual:@"glass"];
    if (dark) return black ? [NSColor colorWithSRGBRed:14 / 255.0 green:14 / 255.0 blue:17 / 255.0 alpha:1]
                    : glass ? [NSColor colorWithSRGBRed:29 / 255.0 green:29 / 255.0 blue:32 / 255.0 alpha:1]
                            : [NSColor colorWithSRGBRed:32 / 255.0 green:32 / 255.0 blue:35 / 255.0 alpha:1];
    return black ? NSColor.whiteColor
                 : [NSColor colorWithSRGBRed:245 / 255.0 green:245 / 255.0 blue:247 / 255.0 alpha:1];
}

typedef NS_ENUM(NSInteger, Phase) {
    PhaseTucked, PhasePeekLook, PhasePeekPause, PhaseOut, PhaseDucking, PhasePress, PhaseGrowing, PhaseGrown,
    PhaseLanded
};

// What it's like, apart from where its middle is: each value the spring moves.
typedef struct { CGFloat shift, tilt, lift, squash, shut, gx, gy; } Face;

@interface SideCat ()
@property (strong) Page *page;
@property (strong) CALayer *shade, *face, *head, *gaze, *drift, *earLeft, *earRight;
@property (strong) NSArray<CAShapeLayer *> *creams, *features, *eyes;
@property (strong) CAShapeLayer *shut;
@property (assign) Phase phase;
@property (assign) NSUInteger planRun;     // which plans still count: a newer phase makes older ones moot
@property (assign) BOOL headerGone;
@property (assign) NSInteger needsCount;
@property (copy) NSString *mood;           // the folded cat's pose (takeMood:)
@property (assign) CFTimeInterval awakeUntil, overSince, blinkAt, flickAt;
@property (assign) BOOL blinked;
// Its springs: out from the glass's edge (with its out), shift along it, tilt, lift, squash, eyes shut, and gaze.
@property (assign) CGFloat outV;
@property (assign) Spring shiftS, tiltS, liftS, squashS, shutS, gxS, gyS;
@property (assign) Face stepTo;            // where each spring was last headed
@property (assign) BOOL calmShown;         // with reduced motion: faded in where it rests, or out
// Pressed: where its middle was then, and where the folded glass's middle goes; growing, since when and for how long,
// and how it was as it started; whether the panel has finished folding round it.
@property (assign) NSPoint pressedAt, foldAt, windowMiddle;
@property (assign) CFTimeInterval growingSince, growingFor;
@property (assign) Face grewFrom;
@property (assign) BOOL foldDone;
// Where the pointer was last, and whether it was over it.
@property (assign) NSPoint pointerWas;
@property (assign) BOOL overWas;
// A press, and the pointer dragged with it held: where from, and whether it has moved the panel.
@property (assign) NSPoint dragFrom, pressAt;
@property (assign) BOOL dragged;
@end

@implementation SideCat

- (instancetype)initWithPage:(Page *)page {
    if (!(self = [super initWithBox:kBox reach:kReach])) return nil;
    self.page = page;
    Spring rest = {0, 0};
    self.shiftS = self.tiltS = self.liftS = self.shutS = self.gxS = self.gyS = rest;
    self.squashS = (Spring){1, 0};
    [self buildLayers];
    [self paint];
    [self setLabel:@"Collapse" more:nil];
    // It has no switch: it's the way to fold the panel while the header has gone, and back from the screen's edge.
    self.shown = YES;
    return self;
}

- (void)holdBy:(PanelWindow *)panel {
    [super holdBy:panel];
    __weak typeof(self) weakSelf = self;
    [panel followHeader:^(BOOL gone) {
        weakSelf.headerGone = gone;
        [weakSelf aim];
    }];
    [panel followFold:^(BOOL folded, BOOL done) { [weakSelf folded:folded done:done]; }];
    [panel followLook:^{ [weakSelf paint]; }];
    // At the screen's edge, a press brings the panel back.
    [panel followAway:^(BOOL away) { [weakSelf setLabel:away ? @"Show Panel" : @"Collapse" more:nil]; }];
    [self paint];
}

#pragma mark Drawing

- (void)buildLayers {
    CGFloat c = kBox / 2;
    // Its shadow, under the glass, where it's out against what's beside the panel; the face is drawn the cat's way up.
    self.shade = [CALayer layer];
    self.shade.frame = self.box.bounds;
    self.shade.shadowColor = NSColor.blackColor.CGColor;
    self.shade.shadowOffset = CGSizeMake(0, -1.5);
    self.shade.shadowRadius = 1.5;
    [self.box addSublayer:self.shade];
    self.face = [CALayer layer];
    self.face.frame = self.box.bounds;
    self.face.geometryFlipped = YES;
    [self.shade addSublayer:self.face];
    self.head = [CALayer layer];
    self.head.bounds = CGRectZero;
    self.head.position = CGPointMake(c, c);
    [self.face addSublayer:self.head];

    CAShapeLayer *(^shape)(NSString *, CALayer *) = ^CAShapeLayer *(NSString *svg, CALayer *into) {
        CAShapeLayer *layer = [CAShapeLayer layer];
        CGPathRef path = CatCGPath(svg);
        layer.path = path;
        CGPathRelease(path);
        [into addSublayer:layer];
        return layer;
    };
    CAShapeLayer *skull = shape(kCatHead, self.head);
    // Each ear turns about where it meets the head, for the flick.
    CALayer *(^ear)(NSString *, CGFloat) = ^CALayer *(NSString *svg, CGFloat pivotX) {
        CALayer *holder = [CALayer layer];
        holder.bounds = CGRectZero;
        holder.position = CGPointMake(pivotX, -52);
        [self.head addSublayer:holder];
        CAShapeLayer *layer = shape(svg, holder);
        layer.position = CGPointMake(-pivotX, 52);
        return holder;
    };
    self.earLeft = ear(kCatEarLeft, -42);
    self.earRight = ear(kCatEarRight, 42);
    CAShapeLayer *nose = shape(kCatNose, self.head);
    // Its eyes look about as a whole (gaze), drift while it watches (drift), and close each about its own middle.
    self.gaze = [CALayer layer];
    self.gaze.bounds = CGRectZero;
    [self.head addSublayer:self.gaze];
    self.drift = [CALayer layer];
    self.drift.bounds = CGRectZero;
    [self.gaze addSublayer:self.drift];
    NSMutableArray *eyes = [NSMutableArray array];
    for (int side = -1; side <= 1; side += 2) {
        CAShapeLayer *eye = [CAShapeLayer layer];
        CGPathRef circle = CGPathCreateWithEllipseInRect(CGRectMake(-kCatEyeR, -kCatEyeR, 2 * kCatEyeR, 2 * kCatEyeR),
                                                         NULL);
        eye.path = circle;
        CGPathRelease(circle);
        eye.position = CGPointMake(side * kCatEyeX, kCatEyeY);
        [self.drift addSublayer:eye];
        [eyes addObject:eye];
    }
    self.eyes = eyes;
    self.shut = shape(kCatShut, self.head);
    self.shut.fillColor = NSColor.clearColor.CGColor;
    self.shut.lineWidth = 9;
    self.shut.lineCap = kCALineCapRound;
    self.shut.opacity = 0;
    self.creams = @[skull, self.earLeft.sublayers.firstObject, self.earRight.sublayers.firstObject];
    self.features = [@[nose] arrayByAddingObjectsFromArray:eyes];
    // Nothing in it moves by itself: each frame says where everything is.
    for (CALayer *layer in @[self.head, self.earLeft, self.earRight, self.gaze, self.drift, self.shut, skull, nose])
        layer.actions = @{@"transform": NSNull.null, @"opacity": NSNull.null, @"position": NSNull.null};
    for (CALayer *eye in eyes) eye.actions = @{@"transform": NSNull.null};
    [self drawAt:CACurrentMediaTime()];
}

// The folded cat's colours (cat.css): its face --cream, dark on the light panel, and its eyes and nose the panel's own
// colour, as if the panel showed through; its shadow softer on the light panel. The label's are the edge icon's.
- (void)paint {
    [super paint];
    BOOL dark = self.dark;
    NSColor *cream = dark ? [NSColor colorWithSRGBRed:243 / 255.0 green:235 / 255.0 blue:226 / 255.0 alpha:1]
                          : [NSColor colorWithSRGBRed:42 / 255.0 green:36 / 255.0 blue:32 / 255.0 alpha:1];
    NSColor *feature = PanelColour(self.panelWindow.look, dark);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (CAShapeLayer *layer in self.creams) layer.fillColor = cream.CGColor;
    for (CAShapeLayer *layer in self.features) layer.fillColor = feature.CGColor;
    self.shut.strokeColor = feature.CGColor;
    self.shade.shadowOpacity = dark ? 0.45 : 0.25;
    [CATransaction commit];
}

// Everything where it is now: its head (moved, turned, at its size), its eyes, its ear and its shadow.
- (void)drawAt:(CFTimeInterval)now {
    CGFloat grow = 0, shadow = 1;
    NSPoint offset = NSZeroPoint;
    if (self.phase == PhaseGrowing || self.phase == PhaseGrown) {
        CGFloat q = self.growingFor > 0 ? Clamp((now - self.growingSince) / self.growingFor, 0, 1) : 1;
        grow = Eased(kFoldEasing, q);
        shadow = 1 - Smooth(q);
    }
    if ([self keepsPlace]) {
        // Pressed and growing, its window stays put, and its middle moves within it, a fraction of a point at a time.
        NSPoint middle = [self middleNow:grow];
        offset = NSMakePoint(middle.x - self.windowMiddle.x, -(middle.y - self.windowMiddle.y));
    }
    // Its eyes: shut as it's asleep, and for the slow blink, once.
    CGFloat closed = Clamp(self.shutS.x, 0, 1);
    if (self.blinkAt) {
        CGFloat b = (now - self.blinkAt) * 1000;
        CGFloat c = b < 420 ? Smooth(b / 420) : b < 640 ? 1 : b < 1120 ? 1 - Smooth((b - 640) / 480) : 0;
        closed = MAX(closed, c);
    }
    // One quick flick of the ear on the outside, and a smaller one after it.
    CGFloat flick = 0;
    if (self.flickAt) {
        CGFloat f = (now - self.flickAt) * 1000;
        flick = f < 70 ? -18 * f / 70 : f < 150 ? Lerp(-18, 5, (f - 70) / 80) : f < 220 ? Lerp(5, -10, (f - 150) / 70)
              : f < 330 ? Lerp(-10, 0, (f - 220) / 110) : 0;
    }
    BOOL left = [self.side isEqual:@"left"];
    CGFloat scale = Lerp(kPeekScale, kFoldScale, grow);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CATransform3D t = CATransform3DMakeTranslation(0, kHeadDown, 0);
    t = CATransform3DConcat(t, CATransform3DMakeScale(scale, scale, 1));
    t = CATransform3DConcat(t, CATransform3DMakeRotation(self.tiltS.x * M_PI / 180, 0, 0, 1));
    t = CATransform3DConcat(t, CATransform3DMakeTranslation(self.shiftS.x + offset.x, self.liftS.x + offset.y, 0));
    t = CATransform3DConcat(t, CATransform3DMakeScale(self.squashS.x, self.squashS.x, 1));
    self.head.transform = t;
    self.gaze.transform = CATransform3DMakeTranslation(self.gxS.x, self.gyS.x, 0);
    for (CALayer *eye in self.eyes) eye.transform = CATransform3DMakeScale(1, 1 - 0.92 * closed, 1);
    self.shut.opacity = Clamp((closed - 0.7) / 0.3, 0, 1);
    CALayer *outer = left ? self.earLeft : self.earRight, *inner = left ? self.earRight : self.earLeft;
    outer.transform = CATransform3DMakeRotation(flick * (left ? 1 : -1) * M_PI / 180, 0, 0, 1);
    inner.transform = CATransform3DIdentity;
    self.shade.shadowOpacity = (self.dark ? 0.45 : 0.25) * shadow;
    [CATransaction commit];
}

#pragma mark What's said about it

// Told with each update: only something new needing you moves it, an ear flicking, once, while it's out.
- (void)needs:(NSInteger)count {
    BOOL more = count > self.needsCount;
    self.needsCount = count;
    if (!more || (self.phase != PhasePeekPause && self.phase != PhaseOut)) return;
    self.flickAt = CACurrentMediaTime();
    [self kick];
}

- (void)takeMood:(NSString *)pose {
    if ([pose isEqual:self.mood]) return;
    self.mood = pose;
    [self kick];
}

// Its mood, the folded cat's: looking at you while something is your turn, watching while sessions work, asleep
// otherwise.
- (NSString *)pose {
    return self.mood ?: @"asleep";
}

- (void)folded:(BOOL)folded done:(BOOL)done {
    if (folded && self.phase >= PhasePress) {
        if (!done) return;
        // The glass has closed round it: the page's folded cat takes over once this one has grown, or at once with
        // reduced motion.
        self.foldDone = YES;
        if (self.phase == PhasePress && Calm()) self.phase = PhaseGrown;
        [self landIfReady];
        return;
    }
    // Folded some other way, or opening: it's under the glass, out of sight, until the header goes again. Opening, the
    // header is all there (header.js), whatever the page last said.
    if (!folded) self.headerGone = NO;
    self.planRun++;
    self.phase = PhaseTucked;
    self.foldDone = NO;
    self.out = kEdgeTucked;
    self.outV = 0;
    self.blinkAt = self.flickAt = 0;
    self.window.alphaValue = 0;
    self.calmShown = NO;
    [self.panelWindow hold:self.window over:NO];
    [self aim];
}

- (void)tookOver {
    if (self.phase < PhaseGrowing) return;
    self.phase = PhaseLanded;
    self.planRun++;
    self.window.alphaValue = 0;
    self.calmShown = NO;
    [self.panelWindow hold:self.window over:NO];
    self.out = kEdgeTucked;
    self.outV = 0;
    [self aim];
}

- (void)landIfReady {
    if (self.phase != PhaseGrown || !self.foldDone) return;
    [self.page catLanded];
    // If the page's folded cat never says it has taken over, this one goes anyway.
    NSUInteger run = self.planRun;
    __weak typeof(self) weakSelf = self;
    [self after:kLandWait run:run do:^{ [weakSelf tookOver]; }];
}

#pragma mark Where it is

- (BOOL)wantsOut {
    if (self.phase >= PhasePress) return self.phase != PhaseLanded;
    return self.panelWindow.parked || (self.headerGone && !self.panelWindow.folded);
}

// Pushed off the screen's edge, the panel leaves it peeking out from there, to bring the panel back.
- (BOOL)showsWhileAway {
    return YES;
}

- (CGFloat)heightBeside:(NSRect)glass {
    return NSMaxY(glass) - MIN(kDown, NSHeight(glass) / 2);
}

- (BOOL)keepsPlace {
    return self.phase == PhasePress || self.phase == PhaseGrowing || self.phase == PhaseGrown;
}

// Pressed, where its middle is: where it was, on its way to the folded glass's middle as it grows.
- (NSPoint)middleNow:(CGFloat)grow {
    return NSMakePoint(Lerp(self.pressedAt.x, self.foldAt.x, grow), Lerp(self.pressedAt.y, self.foldAt.y, grow));
}

- (void)place {
    if (![self keepsPlace]) return [super place];
    [self placeAt:self.windowMiddle];
}

// Out or in, from the header going and coming back. With reduced motion it fades from where it was (step:).
- (void)aimed:(BOOL)visible {
    if (Calm()) self.window.alphaValue = self.calmShown ? 1 : 0;
    if (visible && (self.phase == PhaseTucked || self.phase == PhaseDucking)) [self peek];
    else if (!visible && (self.phase == PhasePeekLook || self.phase == PhasePeekPause || self.phase == PhaseOut))
        [self duck];
}

// Things to do this long from now, unless something newer has happened since (planRun).
- (void)after:(NSTimeInterval)seconds run:(NSUInteger)run do:(void (^)(void))then {
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (weakSelf.planRun == run) then();
    });
}

- (void)peek {
    NSUInteger run = ++self.planRun;
    self.awakeUntil = CACurrentMediaTime() + kAwakeAfterPeek;
    __weak typeof(self) weakSelf = self;
    if (Calm()) {
        self.phase = PhaseOut;
        [self kick];
        return;
    }
    self.phase = PhasePeekLook;
    [self after:kPeekLook run:run do:^{
        weakSelf.phase = PhasePeekPause;
        [weakSelf kick];
        [weakSelf after:kPeekOut run:run do:^{
            weakSelf.phase = PhaseOut;
            [weakSelf kick];
        }];
    }];
    [self kick];
}

- (void)duck {
    NSUInteger run = ++self.planRun;
    self.phase = PhaseDucking;
    self.overSince = 0;
    __weak typeof(self) weakSelf = self;
    [self after:0.42 run:run do:^{
        weakSelf.phase = PhaseTucked;
        [weakSelf kick];
    }];
    [self kick];
}

#pragma mark Each frame

// Where its eyes look: toward the pointer, turning less once it's close (catGaze in cat.js); down a little with none.
- (NSPoint)lookFrom:(NSPoint)middle {
    NSPoint p = self.pointer;
    CGFloat dx = p.x - middle.x, dy = -(p.y - middle.y), length = hypot(dx, dy);
    if (length < 0.001) return NSMakePoint(0, 1);
    CGFloat turn = kGlance * MIN(1, length / 16);
    return NSMakePoint(dx / length * turn, dy / length * turn);
}

- (void)step:(CFTimeInterval)dt {
    CFTimeInterval now = CACurrentMediaTime();
    CGFloat o = [self.side isEqual:@"left"] ? -1 : 1;
    NSPoint middle = [self centerOut:self.out along:0];
    NSString *pose = self.pose;
    CGFloat moodLift = [pose isEqual:@"asleep"] ? 3 : [pose isEqual:@"watch"] ? 1.5 : 0;
    BOOL awake = now < self.awakeUntil || ![pose isEqual:@"asleep"];
    BOOL over = self.phase == PhaseOut && self.over;
    CGFloat d = hypot(self.pointer.x - middle.x, self.pointer.y - middle.y);
    CGFloat outTo = kEdgeTucked, k = 170;
    Face to = {0, 0, moodLift + 2, 1, awake ? 0 : 1, 0, 0};
    BOOL drifts = NO;
    switch (self.phase) {
        case PhasePeekLook:
            // Its head tilted toward the edge, one ear and one eye clear of the glass, looking out.
            outTo = -10;
            to = (Face){6 * o, 26 * o, -1, 1, 0, 10 * o, -3};
            break;
        case PhasePeekPause: {
            // A pause, and a look at you.
            NSPoint l = [self lookFrom:middle];
            outTo = -10;
            to = (Face){6 * o, 24 * o, -1, 1, 0, l.x, l.y};
            break;
        }
        case PhaseOut: {
            CGFloat near = Clamp(1 - (d - kReach) / (kNotice - kReach), 0, 1);
            BOOL up = awake || d < kWake || over;
            outTo = 0;
            to = (Face){3.5 * o, 10 * o, up ? 0 : moodLift, 1, up ? 0 : 1, 0, 0};
            if (near > 0 && up) {
                // It notices you: straightens, lifts its head, its eyes on the pointer.
                NSPoint l = [self lookFrom:middle];
                to.tilt = Lerp(to.tilt, 0, near);
                to.shift = Lerp(to.shift, 0, near);
                to.lift = Lerp(to.lift, -1.5, near);
                to.gx = l.x;
                to.gy = l.y;
            } else if ([pose isEqual:@"watch"] && up) {
                // Watching the work: its eyes drift over it.
                to.gy = 7;
                drifts = YES;
            }
            if (over) {
                outTo = kPointedAt;
                to.tilt = to.shift = 0;
                to.lift = -2;
            }
            break;
        }
        case PhaseDucking:
            outTo = kEdgeTucked;
            to.lift = moodLift + 4;
            to.shut = self.shutS.x;
            k = 420;
            break;
        case PhasePress: {
            // It dips under your press, head up, its eyes on you.
            NSPoint l = [self lookFrom:self.pressedAt];
            outTo = self.out;
            to = (Face){0, 0, -2, 0.92, 0, l.x, l.y};
            k = 500;
            break;
        }
        case PhaseGrowing:
        case PhaseGrown: {
            // On the glass's own curve, from how it was to how the folded cat sits, raised, its eyes where the folded
            // cat's pose starts them (cat.css's cat-drift for watching).
            CGFloat q = self.growingFor > 0 ? Clamp((now - self.growingSince) / self.growingFor, 0, 1) : 1;
            CGFloat e = Eased(kFoldEasing, q);
            BOOL watch = [pose isEqual:@"watch"];
            Face from = self.grewFrom, end = {0, 0, 0, 1, 0, watch ? -6 : 0, watch ? 7 : 0};
            self.shiftS = (Spring){Lerp(from.shift, end.shift, e), 0};
            self.tiltS = (Spring){Lerp(from.tilt, end.tilt, e), 0};
            self.liftS = (Spring){Lerp(from.lift, end.lift, e), 0};
            self.squashS = (Spring){Lerp(from.squash, end.squash, e), 0};
            self.shutS = (Spring){Lerp(from.shut, end.shut, e), 0};
            self.gxS = (Spring){Lerp(from.gx, end.gx, e), 0};
            self.gyS = (Spring){Lerp(from.gy, end.gy, e), 0};
            if (q >= 1 && self.phase == PhaseGrowing) {
                self.phase = PhaseGrown;
                [self landIfReady];
            }
            [self driftEyes:NO];
            return;
        }
        default:
            break;
    }
    [self driftEyes:drifts];
    // The slow blink: rested on a moment, its eyes close slowly, stay shut a moment, and open again, once.
    if (over) {
        if (!self.overSince) self.overSince = now;
        if (!self.blinked && now - self.overSince > 0.38) {
            self.blinked = YES;
            self.blinkAt = now;
        }
    } else if (self.phase != PhasePress) {
        self.overSince = 0;
        if (d > kReach + 30) self.blinked = NO;
    }
    if (self.blinkAt && now - self.blinkAt >= 1.12) self.blinkAt = 0;
    if (self.flickAt && now - self.flickAt >= 0.33) self.flickAt = 0;
    if (Calm()) {
        self.out = outTo;
        self.outV = 0;
        self.shiftS = (Spring){to.shift, 0};
        self.tiltS = (Spring){to.tilt, 0};
        self.liftS = (Spring){to.lift, 0};
        self.squashS = (Spring){to.squash, 0};
        self.shutS = (Spring){to.shut, 0};
        self.gxS = (Spring){to.gx, 0};
        self.gyS = (Spring){to.gy, 0};
        // It comes and goes by fading where it rests, and as the panel folds round it.
        BOOL show = self.phase == PhaseOut;
        if (show != self.calmShown) {
            self.calmShown = show;
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
                context.duration = 0.2;
                self.window.animator.alphaValue = show ? 1 : 0;
            }];
        }
    } else {
        Spring out = {self.out, self.outV}, s;
        Pull(&out, outTo, k, dt);
        self.out = out.x;
        self.outV = out.v;
        s = self.shiftS; Pull(&s, to.shift, 130, dt); self.shiftS = s;
        s = self.tiltS; Pull(&s, to.tilt, 130, dt); self.tiltS = s;
        s = self.liftS; Pull(&s, to.lift, 110, dt); self.liftS = s;
        s = self.squashS; Pull(&s, to.squash, 500, dt); self.squashS = s;
        s = self.shutS; Pull(&s, to.shut, 260, dt); self.shutS = s;
        s = self.gxS; Pull(&s, to.gx, 320, dt); self.gxS = s;
        s = self.gyS; Pull(&s, to.gy, 320, dt); self.gyS = s;
    }
    self.outTo = outTo;
    self.stepTo = to;
}

// While it watches, its eyes drift over the work, back and forth, as the folded cat's do (cat.css's cat-drift); when
// they stop, they carry on from where the drift had them.
- (void)driftEyes:(BOOL)on {
    BOOL drifting = [self.drift animationForKey:@"drift"] != nil;
    if (on == drifting || Calm()) return;
    if (on) {
        CAKeyframeAnimation *drift = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
        drift.values = @[@-6, @6, @-6];
        drift.keyTimes = @[@0, @0.5, @1];
        drift.timingFunctions = @[[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
                                  [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
        drift.duration = 3.4;
        drift.repeatCount = HUGE_VALF;
        [self.drift addAnimation:drift forKey:@"drift"];
        return;
    }
    CGFloat x = [[self.drift.presentationLayer valueForKeyPath:@"transform.translation.x"] doubleValue];
    [self.drift removeAnimationForKey:@"drift"];
    Spring gx = self.gxS;
    gx.x += x;
    self.gxS = gx;
}

- (BOOL)settled {
    if (self.phase == PhaseGrowing || self.blinkAt || self.flickAt) return NO;
    if (self.phase == PhaseGrown || self.phase == PhaseLanded) return YES;
    Face to = self.stepTo;
    return fabs(self.out - self.outTo) < 0.05 && fabs(self.outV) < 0.05 && Still(self.shiftS, to.shift)
           && Still(self.tiltS, to.tilt) && Still(self.liftS, to.lift) && Still(self.squashS, to.squash)
           && Still(self.shutS, to.shut) && Still(self.gxS, to.gx) && Still(self.gyS, to.gy);
}

// The pointer is polled many times a second, wherever it is: its moves start the frames only when they can change
// something, near enough to be noticed (now or before), or while it peeks or dips, when its eyes are on the pointer
// wherever that is.
- (void)pointerMoved:(NSPoint)point over:(BOOL)over {
    NSPoint was = self.pointerWas, middle = [self centerOut:self.out along:0];
    self.pointerWas = point;
    if (hypot(point.x - was.x, point.y - was.y) < 0.5 && over == self.overWas) return;
    self.overWas = over;
    CGFloat far = kNotice + 20;
    BOOL near = hypot(point.x - middle.x, point.y - middle.y) < far || hypot(was.x - middle.x, was.y - middle.y) < far;
    if (near || over || self.phase == PhasePeekPause || self.phase == PhasePress) [self kick];
}

#pragma mark Pressing and dragging

// Out, for a press or a drag: one while it's still peeking out finishes coming out, and counts.
- (BOOL)outNow {
    if (self.phase == PhasePeekLook || self.phase == PhasePeekPause) {
        self.planRun++;
        self.phase = PhaseOut;
        [self kick];
    }
    return self.phase == PhaseOut;
}

- (void)downAt:(NSPoint)point {
    self.pressAt = self.dragFrom = point;
    self.dragged = NO;
}

// Held and moved, it moves the panel, as the folded cat does.
- (void)draggedTo:(NSPoint)point {
    if (self.panelWindow.parked || ![self outNow]) return;
    if (!self.dragged && hypot(point.x - self.pressAt.x, point.y - self.pressAt.y) < 3) return;
    if (![self.panelWindow dragBy:NSMakePoint(point.x - self.dragFrom.x, point.y - self.dragFrom.y)]) return;
    if (!self.dragged) [self showLabel:NO];
    self.dragged = YES;
    self.dragFrom = point;
}

- (void)upAt:(NSPoint)point {
    if (!self.dragged) return [self pressed];
    self.dragged = NO;
    [self.panelWindow draggedByHand];
}

// Pressed, it comes out in front of the glass at once, dipping, its eyes on you, and the panel folds round it where it
// is (foldHere); the glass closing round it, it grows into the folded cat (glassMoving:over:).
- (void)pressed {
    if (!self.visible || ![self outNow]) return;
    // At the screen's edge, it brings the panel back, going in under its edge as it comes (unless the header has gone).
    if (self.panelWindow.parked) {
        [self showLabel:NO];
        return [self.panelWindow unpark];
    }
    NSUInteger run = ++self.planRun;
    self.phase = PhasePress;
    self.blinkAt = self.flickAt = 0;
    self.foldDone = NO;
    [self showLabel:NO];
    // Where its window has it now, in whole points (placeAt:).
    NSPoint middle = [self centerOut:self.out along:0];
    self.pressedAt = self.windowMiddle = NSMakePoint(round(middle.x), round(middle.y));
    [self.panelWindow hold:self.window over:YES];
    [self place];
    [self kick];
    __weak typeof(self) weakSelf = self;
    [self after:Calm() ? 0 : kDip run:run do:^{ [weakSelf foldHere]; }];
    // If the panel doesn't fold after all, it goes back under the glass.
    [self after:kFoldWait run:run do:^{
        SideCat *cat = weakSelf;
        if (cat.phase != PhasePress || cat.panelWindow.folded) return;
        cat.phase = PhaseOut;
        [cat.panelWindow hold:cat.window over:NO];
        [cat kick];
    }];
}

NSPoint SideCatFoldAt(NSPoint middle, CGFloat shift, CGFloat lift, NSPoint corner) {
    CGFloat x = middle.x + shift, y = middle.y - (lift + kHeadAt * (kPeekScale - kFoldScale));
    return NSMakePoint(round(x - corner.x), round(corner.y - y));
}

// The panel folds round it where it is (SideCatFoldAt), the page told where.
- (void)foldHere {
    if (self.phase != PhasePress) return;
    NSPoint corner = self.panelWindow.listCorner;
    NSPoint at = SideCatFoldAt(self.pressedAt, self.shiftS.x, self.liftS.x, corner);
    self.foldAt = NSMakePoint(corner.x + at.x, corner.y - at.y);
    [self.page foldFromSide:at];
}

- (void)glassMoving:(NSRect)glass over:(NSTimeInterval)duration {
    if (self.phase != PhasePress || duration <= 0 || !self.panelWindow.folded) return;
    self.grewFrom = (Face){self.shiftS.x, self.tiltS.x, self.liftS.x, self.squashS.x, self.shutS.x, self.gxS.x,
                           self.gyS.x};
    self.growingSince = CACurrentMediaTime();
    self.growingFor = duration;
    self.phase = PhaseGrowing;
    [self kick];
}

@end
