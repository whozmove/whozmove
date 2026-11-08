// PanelWindow (Flick): flicked off the screen's edge by a sideways swipe, and back.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "PanelWindow+Private.h"

@implementation PanelWindow (Flick)

#pragma mark Flicked off the screen's edge

int SwipeWay(CGFloat x, CGFloat y) {
    if (hypot(x, y) < kSwipeDecide) return 0;
    return fabs(x) > 2 * fabs(y) ? 1 : -1;
}

BOOL SwipeFlicks(CGFloat speed, CGFloat x) {
    return fabs(speed) > kFlickSpeed && speed * x > 0;
}

CGFloat SwipePulled(CGFloat travel, CGFloat room) {
    if (travel <= 0) return 0;
    return travel <= room ? travel : room + Stretched(travel - room, kPullPast);
}

BOOL PullBrings(CGFloat out, CGFloat width, CGFloat speed) {
    return (out >= width / 3 && speed >= -kFlickSpeed) || speed > kFlickSpeed;
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
// on the open panel's list, with the reader closed, and not while one of the page's boxes has the keyboard. Away, one
// on Whozmove peeking out where the panel went is the panel's too (swipedAway:), the rest of it coming to the catch
// under the pointer (holdAway). Only a swipe whose start was seen, on what it started on, counts: what comes in from
// elsewhere, its start having gone to another app, is left alone.
- (NSEvent *)swiped:(NSEvent *)event {
    BOOL onWhozmove = event.window && (event.window == self.awaySwipeWindow || event.window == self.swipeCatch);
    if ((event.window != self.panel && !onWhozmove) || !event.hasPreciseScrollingDeltas) return event;
    if (event.momentumPhase != NSEventPhaseNone) {
        if (self.swipeAway && self.swipeMine) [self glided:event.momentumPhase];
        return self.swipeMine ? nil : event;
    }
    if (event.phase == NSEventPhaseBegan || event.phase == NSEventPhaseMayBegin) {
        // A new swipe: the last one's catch goes, so this one goes to what's under the pointer.
        [self letGoAway];
        self.swipeMine = self.swipeDecided = NO;
        self.swipeX = self.swipeY = self.swipeSpeed = 0;
        self.swipeAt = event.timestamp;
        self.swipeAway = onWhozmove;
        // Away, only once the panel has gone (not on its way there or back), and not while a button is held.
        if (onWhozmove) self.swipeAllowed = self.parked && !self.parkTimer && NSEvent.pressedMouseButtons == 0;
        // Not while one of the page's boxes has the keyboard: a sideways swipe there moves through its words.
        else self.swipeAllowed = !self.folded && !self.expanded && !self.turned && !self.turning && !self.reshaping
                                 && !self.parked && !self.parkTimer && !self.panel.wantsKeyboard;
        return event;
    }
    if (!self.swipeAllowed || self.swipeAway != onWhozmove) return event;
    if (self.swipeAway) return [self swipedAway:event];
    // Folding meanwhile (its list on pointing going back in, the pointer having left it), the panel is the fold's: the
    // swipe is given up where it is, and never sends it off the screen's edge. The fold saves its place as it settles.
    if (self.folded || self.reshaping) {
        self.swipeMine = self.swipeAllowed = NO;
        return event;
    }
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
        // Over: only its momentum still counts as this swipe's (above).
        self.swipeAllowed = NO;
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

- (void)takeSwipesAwayOn:(NSWindow *)window swiped:(void (^)(CGFloat, BOOL))swiped {
    self.awaySwipeWindow = window;
    self.awaySwiped = swiped;
}

// A swipe on Whozmove peeking out where the panel went, sideways from its first moves as the flick is, the way it goes
// then kept till the fingers lift. Toward the screen's middle, the panel comes out from the edge with the fingers,
// point for point, Whozmove at its edge, fading in as it comes onto the screen as it faded going. Toward the edge,
// Whozmove is pushed in (SideCat.m). With reduced motion nothing follows the fingers.
- (NSEvent *)swipedAway:(NSEvent *)event {
    // Flicked toward the right, its icons face back onto the screen from its left (parkToward:).
    CGFloat toMiddle = [self.edgeSide isEqual:@"left"] ? -1 : 1;
    if (event.phase == NSEventPhaseChanged) {
        CGFloat way = event.isDirectionInvertedFromDevice ? 1 : -1;
        CGFloat dx = event.scrollingDeltaX * way, dy = event.scrollingDeltaY * way;
        self.swipeX += dx;
        self.swipeY += dy;
        if (!self.swipeDecided) {
            int way = SwipeWay(self.swipeX, self.swipeY);
            if (!way) return nil;
            self.swipeDecided = YES;
            self.swipeMine = way > 0 && self.parked;
            if (!self.swipeMine) return nil;
            self.pulling = self.swipeX * toMiddle > 0;
            [self holdAway];
        }
        if (!self.swipeMine || !self.awayDown) return nil;
        NSTimeInterval dt = event.timestamp - self.swipeAt;
        self.swipeAt = event.timestamp;
        if (dt > 0.001) self.swipeSpeed = 0.6 * dx / dt + 0.4 * self.swipeSpeed;
        // Brought back meanwhile some other way (Show Panel, ⌃⌥N), it moves nothing more; the rest of the swipe still
        // comes to the catch, so it goes nowhere else.
        if (!self.parked) {
            [self endAwaySwipe:NO];
            return nil;
        }
        CGFloat toward = self.swipeX * toMiddle;
        if (!self.pulling) self.awaySwiped(MAX(0, -toward), YES);
        else if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion)
            [self pulledTo:SwipePulled(toward, [self pullRoom])];
        return nil;
    }
    if (event.phase == NSEventPhaseEnded || event.phase == NSEventPhaseCancelled) {
        self.swipeAllowed = NO;
        if (!self.swipeMine) return nil;
        if (self.awayDown) [self endAwaySwipe:event.phase == NSEventPhaseEnded];
        [self liftedAway];
        return nil;
    }
    return nil;
}

// The fingers have lifted (`lifted`), or the swipe was given up. Pulled a third of the way out, or flicked toward the
// screen's middle, the panel carries on to where it was at the fingers' speed, as a flick sends it off, or with reduced
// motion fades back in there, as a press on Whozmove brings it; else it slides back off the edge. Pushed, Whozmove
// springs back out.
- (void)endAwaySwipe:(BOOL)lifted {
    self.awayDown = NO;
    if (self.pulling && self.parked) {
        CGFloat toMiddle = [self.edgeSide isEqual:@"left"] ? -1 : 1;
        NSRect frame = self.panel.frame;
        CGFloat out = SwipePulled(self.swipeX * toMiddle, [self pullRoom]), speed = self.swipeSpeed * toMiddle;
        if (lifted && PullBrings(out, NSWidth(frame), speed)) {
            CGFloat left = fabs(self.parkedFrom.x - NSMinX(frame));
            [self unparkOver:MAX(kParkLeast, MIN(kParkMost, 3 * left / MAX(speed, 1)))];
        } else if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
            [self slideTo:NSMakePoint([self parkedX], self.parkedTop) over:kSlideBack fading:YES
                     then:^(PanelWindow *me) {}];
        }
    }
    self.awaySwiped(0, NO);
}

// Where the panel's left edge is while it's away, and how far it has to come from there to where it was.
- (CGFloat)parkedX {
    return ParkedOrigin(self.panel.frame, self.parkScreen, [self.edgeSide isEqual:@"left"]).x;
}

- (CGFloat)pullRoom {
    return fabs(self.parkedFrom.x - [self parkedX]);
}

// Pulled `out` points out from the screen's edge, at the height it was.
- (void)pulledTo:(CGFloat)out {
    CGFloat toMiddle = [self.edgeSide isEqual:@"left"] ? -1 : 1;
    [self.panel setFrameOrigin:[self originAt:NSMakePoint(round([self parkedX] + toMiddle * out), self.parkedTop)]];
    self.panel.alphaValue = self.shade.alphaValue = ParkedShows(self.panel.frame, self.parkScreen);
    [self tellGlass:[self glassOnScreen] over:0];
}

// Once a swipe on Whozmove is taken to be the panel's, the rest of it, and the trackpad's glide after it, come to the
// catch: a window that can't be seen, under the pointer, above everything, which never takes the keyboard. Whatever
// moves underneath (the panel coming out under the pointer, Whozmove going in, or hiding as the panel comes back),
// none of it goes to what's under the pointer, and the swipe ends here. It goes the moment the swipe has ended: its
// glide over (glided:), or the fingers lifted with none to come (liftedAway), or the pointer off it (pollPointer, a
// Magic Mouse moved meanwhile, which ends the swipe where it is); and as another swipe starts.
- (void)holdAway {
    NSPoint p = NSEvent.mouseLocation;
    [self.swipeCatch setFrame:NSMakeRect(round(p.x - kCatch / 2), round(p.y - kCatch / 2), kCatch, kCatch) display:NO];
    [self.swipeCatch orderFrontRegardless];
    self.awayHold++;
    self.awayHeld = self.awayDown = YES;
    self.gliding = NO;
    self.awaySwiped(0, YES);
}

// The fingers have lifted: a glide, if there's one, starts at once (glided:), so with none by kGlideStarts the swipe
// is over. kGlideMost is only a safety net, should its end never come.
- (void)liftedAway {
    NSUInteger hold = ++self.awayHold;
    __weak typeof(self) weakSelf = self;
    dispatch_queue_t queue = dispatch_get_main_queue();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kGlideStarts * NSEC_PER_SEC)), queue, ^{
        if (weakSelf.awayHold == hold && !weakSelf.gliding) [weakSelf letGoAway];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kGlideMost * NSEC_PER_SEC)), queue, ^{
        if (weakSelf.awayHold == hold) [weakSelf letGoAway];
    });
}

- (void)glided:(NSEventPhase)phase {
    if (phase == NSEventPhaseEnded || phase == NSEventPhaseCancelled) [self letGoAway];
    else self.gliding = YES;
}

// The catch goes. With the fingers still down (the pointer moved off it), the swipe ends where it is, and the rest of
// it, wherever it goes, counts for nothing here.
- (void)letGoAway {
    self.awayHold++;
    if (!self.awayHeld) return;
    if (self.awayDown) [self endAwaySwipe:NO];
    self.awayHeld = self.gliding = NO;
    self.swipeAllowed = NO;
    [self.swipeCatch orderOut:nil];
}

// Off that edge of the screen it was flicked toward, carrying on at the flick's speed and easing out, fading as it goes
// past the edge (on a display beside it, it never shows): just past the edge, Whozmove peeks out from it. The icons at
// its edge take the side facing back onto the screen at once, while still out of sight, and keep it while it's away,
// so Whozmove comes out at the screen's edge as the panel arrives. What's held over or under it goes as it starts; with
// reduced motion, once the panel has faded and gone, so Whozmove fades in at the edge. Open from pointing at the folded
// cat, the page keeps it open first (flickedAway): its list would otherwise fold back round the cat as the pointer is
// off it, which a flicked panel always is, folding the panel while it's away.
- (void)parkToward:(BOOL)right speed:(CGFloat)speed {
    NSRect visible = (self.panel.screen ?: NSScreen.mainScreen).visibleFrame, frame = self.panel.frame;
    CGFloat x = ParkedOrigin(frame, visible, right).x;
    [self.page flickedAway];
    self.parked = YES;
    self.returning = NO;  // flicked away again on its way back: a turn waits for the next time it's back
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

// Back where it was, sliding in from the screen's edge (over `seconds`, from a pull), what's held over or under it
// coming back with it as it does. With reduced motion, Whozmove fades at the edge first, then the panel fades in where
// it was.
- (void)unpark {
    [self unparkOver:kUnpark];
}

- (void)unparkOver:(NSTimeInterval)seconds {
    if (!self.parked) return;
    self.parked = NO;
    self.returning = YES;
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
    [self slideTo:[self parkedCorner] over:seconds fading:YES then:back];
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
    self.returning = NO;
    [self takePendingTurn];
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
@end
