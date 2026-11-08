// PanelWindow (Fold): folding into the cat and opening round it, and the folded glass's breath.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "PanelWindow+Private.h"

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

@implementation PanelWindow (Fold)

- (void)followFold:(void (^)(BOOL, BOOL))observer {
    [self.foldObservers addObject:observer];
}

- (void)tellFold:(BOOL)done {
    for (void (^observer)(BOOL, BOOL) in self.foldObservers) observer(self.folded, done);
}

#pragma mark Folding into the cat

// The folded glass in a window that's `frame`: round, in the middle of the cat's square, whatever room there is beside
// it.
- (NSRect)foldedGlassIn:(NSRect)frame {
    CGFloat inset = (kFoldBox - kFoldGlass) / 2;
    return NSInsetRect([self catBoxIn:frame], inset, inset);
}

// The cat's square (kFoldBox) in a folded window that's `frame`: all of it, or where it is in the room beside it.
- (NSRect)catBoxIn:(NSRect)frame {
    return NSMakeRect(NSMinX(frame) + self.roomOffset.x, NSMinY(frame) + self.roomOffset.y, kFoldBox, kFoldBox);
}

// The folded window: the cat's square, round the name's o in the open panel's header, so the cat stays where it is as
// the panel folds round it.
- (NSRect)foldedFrameFrom:(NSRect)open {
    return NSMakeRect(NSMinX(open) + self.catAt.x - kFoldBox / 2, NSMaxY(open) - self.catAt.y - kFoldBox / 2, kFoldBox,
                      kFoldBox);
}

// Where the open panel's top edge goes, from the cat's square: its name's o on the cat, under the top of the screen.
- (CGFloat)openTopFrom:(NSRect)box {
    NSRect visible = (self.panel.screen ?: NSScreen.mainScreen).visibleFrame;
    return MIN(NSMidY(box) + self.catAt.y, NSMaxY(visible));
}

- (CGFloat)openRoomFrom:(NSRect)box {
    NSRect visible = (self.panel.screen ?: NSScreen.mainScreen).visibleFrame;
    return RoomFor([self openTopFrom:box], NSMinY(visible), self.keptBelow, self.linesUnder);
}

// The open panel, from the cat's square: its name's o on the cat, as tall as the page asked for while it was folded
// (or as it was when it folded), and moved in if it would run off the screen. It keeps to the room the open panel has
// there (RoomFor, the glass's), what hangs below it and the lines under the header included, so it lands at the height
// the page then keeps it at, on a screen of another size too.
- (NSRect)openFrameFrom:(NSRect)box {
    NSRect visible = (self.panel.screen ?: NSScreen.mainScreen).visibleFrame;
    CGFloat top = [self openTopFrom:box];
    CGFloat tall = OpenedHeight(self.openHeight, self.foldedAsked, [self openRoomFrom:box]);
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
// the reader is open (the page doesn't fold then). Asked again while it's moving, the newest is taken once it's done;
// but the folded cat's list coming out or going back in (peek.js), asked the other way meanwhile, turns back from where
// it is, as the chats moving with it do (landing.js), rather than finishing first. Folding with chats still out beside
// the cat, `room` is where they go back out to as it folds.
- (void)fold:(BOOL)on instant:(BOOL)instant room:(NSArray *)room peek:(BOOL)peek {
    self.foldRoom = on && !instant ? room : nil;
    if (self.expanded) return;
    // How it's left for next launch (show), as the page keeps it: the list on pointing isn't (keepOpen).
    if (!peek) [NSUserDefaults.standardUserDefaults setBool:on forKey:kFoldedKey];
    if (on) self.pendingReader = nil;
    if (self.reshaping && self.foldInMotion && self.foldPeek && !instant) {
        self.pendingFold = nil;
        if (on == self.folded) return;
        self.folded = on;
        self.askedPeek = peek;
        if (on) [self dropKeyboard];
        else [self stopBreathing];
        [self tellFold:NO];
        [self foldMoving];
        return;
    }
    self.askedPeek = peek;
    [self fold:on instant:instant];
}

- (void)keepOpen {
    [NSUserDefaults.standardUserDefaults setBool:NO forKey:kFoldedKey];
}

- (void)fold:(BOOL)on instant:(BOOL)instant {
    if (self.expanded) return;
    // It folds from its list side: turned over (a page loaded afresh says how it was left), it's put back at once.
    if (self.turned && !self.turning) [self turnBackAtOnce];
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
    if (on) {
        self.openHeight = NSHeight(self.panel.frame);
        self.foldedAsked = 0;
    }
    [self tellFold:NO];
    [self foldMoving];
}

// What was asked for while the panel was changing shape, once it's done: a fold or an opening first (the room beside
// the cat then goes with it), else the room beside the cat.
- (void)takePending {
    NSNumber *fold = self.pendingFold;
    NSDictionary *room = self.pendingRoom;
    self.pendingFold = nil;
    self.pendingRoom = nil;
    if (fold && fold.boolValue != self.folded) [self fold:fold.boolValue instant:NO];
    else if (room) [self catRoom:room];
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
    // With room beside the cat (a page loaded afresh while something was out), just the cat's square.
    if (self.roomHeld) [self.panel setFrame:[self catBoxIn:self.panel.frame] display:NO];
    self.foldInMotion = NO;
    [self letRoomGo];
    self.pendingRoom = nil;
    NSRect frame = self.panel.frame;
    BOOL round = fabs(NSWidth(frame) - kWidth) > 1;
    if (self.folded && !round) {
        self.openHeight = NSHeight(frame);
        self.foldedAsked = 0;
        [self.panel setFrame:[self foldedFrameFrom:frame] display:NO];
    } else if (self.folded && !NSEqualSizes(frame.size, NSMakeSize(kFoldBox, kFoldBox))) {
        // Not the cat's square: just that.
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
// Turned back on its way (fold:instant:room:peek:), it starts from where the glass, the page's clip and the page are,
// toward the same cat's square or the open panel round it, over as much of the time as it has left to go.
- (void)foldMoving {
    BOOL back = self.foldInMotion;
    self.reshaping = YES;
    self.foldInMotion = YES;
    self.foldPeek = self.askedPeek;
    self.askedPeek = NO;
    NSUInteger run = ++self.foldRun;
    if (back) {
        [self.moveTimer invalidate];
        self.moveTimer = nil;
    }
    self.strip.hidden = self.readerStrip.hidden = YES;
    [self tellCatPointerGone];
    CGFloat inset = (kFoldBox - kFoldGlass) / 2;
    NSRect from = self.panel.frame;
    // Where the glass, the page's clip and the page's list are on the screen now, for a move turned back on its way.
    NSRect glassNow = NSOffsetRect(self.glass.frame, NSMinX(from), NSMinY(from));
    NSRect clipNow = NSOffsetRect(self.clip.frame, NSMinX(from), NSMinY(from));
    NSRect pageView = self.page.view.frame;
    NSPoint pageNow = NSMakePoint(NSMinX(from) + NSMinX(self.clip.frame) + NSMinX(pageView) + kReaderRoom,
                                  NSMinY(from) + NSMinY(self.clip.frame) + NSMaxY(pageView) - kAboveRoom);
    __weak typeof(self) weakSelf = self;
    BOOL (^moving)(void) = ^BOOL { return weakSelf && weakSelf.foldRun == run; };
    void (^finish)(void) = ^{
        if (!moving()) return;
        weakSelf.foldInMotion = NO;
        [weakSelf settle];
        // Holding room for chats beside the cat, the place kept is the open panel's, as it was saved as it folded.
        if (!weakSelf.roomHeld) [weakSelf.panel saveFrameUsingName:@"Whozmove"];
        if (!weakSelf.folded) [weakSelf resendRoom];
        [weakSelf tellFold:YES];
        [weakSelf takePending];
        NSValue *reader = weakSelf.pendingReader;
        weakSelf.pendingReader = nil;
        if (reader && !weakSelf.folded && !weakSelf.reshaping)
            [weakSelf expandReader:reader.sizeValue.width height:reader.sizeValue.height];
    };
    if (self.folded) {
        NSRect box = back ? self.foldBox : [self foldedFrameFrom:from], glass = NSInsetRect(box, inset, inset);
        self.foldBox = box;
        // With chats going back out beside the cat as it folds (landing.js), the window takes in the room they go to
        // from the start, the page's clip keeping it all as the glass closes, and holds it once it has folded, the
        // place kept the open panel's, as while chats are out (turned back on its way, the window isn't that: what was
        // saved stays).
        NSArray<NSValue *> *parts = [self roomParts:self.foldRoom around:box];
        self.foldRoom = nil;
        BOOL roomOut = parts.count > 0;
        self.foldRoomOut = roomOut;
        NSRect end = roomOut ? CatRoomFrame(box, parts, kRoomShadow) : box, span = NSUnionRect(from, end);
        if (roomOut) {
            if (!back) [self.panel saveFrameUsingName:@"Whozmove"];
            self.panel.frameAutosaveName = @"";
            [self pollPointerEvery:kPointerEveryWatched];
        }
        // The page starts where the open panel has it (it's marked folded already, so rootAt would take the open
        // panel's frame for the cat's square), or where it is, and goes where the folded cat has it.
        self.pageAt = back ? pageNow : NSMakePoint(NSMinX(from), NSMaxY(from));
        self.holdsPage = YES;
        NSTimeInterval seconds = back ? [self foldTimeFrom:glassNow to:glass other:[self openFrameFrom:box]] : kSpread;
        [self setWindowFrame:span glass:back ? glassNow : from clip:roomOut ? span : back ? clipNow : from then:^{
            if (!moving()) return;
            weakSelf.pageAt = [weakSelf rootAround:box];
            [weakSelf moveGlassTo:glass clip:roomOut ? span : glass corner:roomOut ? 0 : kFoldGlass / 2
                      glassCorner:kFoldGlass / 2 over:seconds easing:kFoldEasing then:^{
                if (!moving()) return;
                if (roomOut) {
                    PanelWindow *me = weakSelf;
                    me.roomParts = parts;
                    me.roomHeld = YES;
                    me.roomOffset = NSMakePoint(NSMinX(box) - NSMinX(end), NSMinY(box) - NSMinY(end));
                }
                [weakSelf setWindowFrame:end glass:glass clip:end then:finish];
            }];
        }];
    } else {
        NSRect box = back ? self.foldBox : [self catBoxIn:from], glass = back ? glassNow : [self foldedGlassIn:from];
        self.foldBox = box;
        BOOL roomOut = back ? self.foldRoomOut : self.roomHeld;
        self.foldRoomOut = roomOut;
        // The page starts where the folded cat has it (the panel is marked open already, so rootAt would take the
        // cat's square for the open panel), or where it is, and goes where the open panel has it.
        self.pageAt = back ? pageNow : [self rootAround:box];
        self.holdsPage = YES;
        [self letRoomGo];
        // A fold turned back before it held its room watched the pointer more often meanwhile.
        if (back && roomOut && !self.catSeesPointer) [self pollPointerEvery:kPointerEvery];
        NSRect open = [self openFrameFrom:box], span = NSUnionRect(open, from);
        NSTimeInterval seconds = back ? [self foldTimeFrom:glassNow to:open other:NSInsetRect(box, inset, inset)]
                                      : kSpread;
        // While chats are out beside the cat, each moves into its row as the glass spreads out from behind the cat
        // (landing.js): the page's clip keeps all the room they need till the glass has spread, the page keeping the
        // rest of the panel out of sight meanwhile.
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        if (roomOut) self.clip.layer.cornerRadius = 0;
        else if (!back) self.clip.layer.cornerRadius = kFoldGlass / 2;
        [CATransaction commit];
        [self setWindowFrame:span glass:glass clip:roomOut ? span : back ? clipNow : glass then:^{
            if (!moving()) return;
            // The cat shrinks into the name's o as the glass spreads out from behind it, starting together.
            [weakSelf.page catGlass:^{
                if (!moving()) return;
                weakSelf.pageAt = NSMakePoint(NSMinX(open), NSMaxY(open));
                [weakSelf moveGlassTo:open clip:roomOut ? span : open corner:roomOut ? 0 : kCorner glassCorner:kCorner
                                 over:seconds easing:kFoldEasing then:^{
                    if (!moving()) return;
                    if (NSEqualRects(span, open)) finish();
                    else [weakSelf setWindowFrame:open showing:open then:finish];
                }];
            }];
        }];
    }
}

// How long a fold or an opening turned back on its way takes from the glass `now` to `to`: kSpread for the whole way
// from `other`, where it was going, and as much less as it has less to go, though never so little that it jumps.
- (NSTimeInterval)foldTimeFrom:(NSRect)now to:(NSRect)to other:(NSRect)other {
    CGFloat whole = MAX(MAX(fabs(NSWidth(other) - NSWidth(to)), fabs(NSHeight(other) - NSHeight(to))), 1);
    CGFloat left = MAX(fabs(NSWidth(now) - NSWidth(to)), fabs(NSHeight(now) - NSHeight(to)));
    return kSpread * MIN(1, MAX(0.4, left / whole));
}
@end
