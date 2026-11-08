// PanelWindow (Hover): the pointer over the panel: its place, its shape, and who's told.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "PanelWindow+Private.h"

@implementation PanelWindow (Hover)

CatWay CatWayFor(NSRect glass, NSRect visible) {
    CatWay way;
    way.right = NSMidX(glass) < NSMidX(visible);
    way.up = NSMidY(glass) < NSMidY(visible);
    way.across = floor(way.right ? NSMaxX(visible) - NSMidX(glass) : NSMidX(glass) - NSMinX(visible));
    CGFloat tall = way.up ? NSMaxY(visible) - NSMinY(glass) : NSMaxY(glass) - NSMinY(visible);
    way.tall = floor(MAX(0, MIN(kAboveRoom, tall)));
    return way;
}

BOOL CatRoomTakes(NSPoint point, NSArray<NSValue *> *parts, CGFloat margin) {
    for (NSValue *part in parts)
        if (NSPointInRect(point, NSInsetRect(part.rectValue, -margin, -margin))) return YES;
    return NO;
}

#pragma mark Hover

- (BOOL)inUseWithin:(NSTimeInterval)seconds {
    return NSDate.timeIntervalSinceReferenceDate - self.usedAt < seconds;
}

// The page says what the pointer should look like where it is: the hand over what a press does something with, the
// text cursor over text, else the arrow. Shown only while the pointer is on the page, and set again each time the
// pointer is looked at (pollPointer), as the app in front may set its own.
- (void)pointerShape:(NSString *)shape {
    NSCursor *cursor = [shape isEqual:@"hand"] ? NSCursor.pointingHandCursor
                     : [shape isEqual:@"text"] ? NSCursor.IBeamCursor : nil;
    BOOL had = self.shape != nil;
    self.shape = cursor;
    if (!self.hovering) return;
    if (cursor) [cursor set];
    else if (had) [NSCursor.arrowCursor set];
}

// Off the page, the arrow is back at once, so a hand never stays over another app.
- (void)dropShape {
    if (!self.shape) return;
    self.shape = nil;
    [NSCursor.arrowCursor set];
}

// Hover follows the pointer's position, polled, not mouse events: the panel is almost never the key window of an
// active app, so WebKit gets no mouse moves, and macOS delivers mouseMoved: to such windows unreliably (often
// only entered and exited). Polling sees every position either way.
- (void)pollPointer {
    NSPoint screen = NSEvent.mouseLocation;
    BOOL moved = !NSEqualPoints(screen, self.lastScreen);
    self.lastScreen = screen;
    if ((self.panel.isVisible && NSPointInRect(screen, self.panel.frame)) || self.panel.wantsKeyboard)
        self.usedAt = NSDate.timeIntervalSinceReferenceDate;
    // Off the catch under a swipe on Whozmove at the screen's edge, what's left of the swipe goes where the pointer is.
    if (self.awayHeld && !NSPointInRect(screen, self.swipeCatch.frame)) [self letGoAway];
    if (self.panel.isVisible)
        for (void (^observer)(NSPoint) in self.pointerObservers) observer(screen);
    [self pointBrowsersAt:screen moved:moved];
    // Turned over, the list isn't what the pointer is on: the back's page follows it (followPointer:).
    if (self.turned) {
        [self dropShape];
        if (self.hovering) {
            self.hovering = NO;
            [self.page hoverEnd:NO held:NO];
        }
        return;
    }
    NSRect frame = self.panel.frame;
    if (self.folded && !self.reshaping) {
        [self tellCatPointer:screen];
        [self tellCatWay];
    }
    // Folded with room beside the cat, only the cat and what's drawn there take the pointer and clicks: elsewhere they
    // go through to what's under the panel, as if it weren't there. Not changed while a button is held, so a press that
    // started on the page isn't taken from it as it moves off.
    BOOL taken = YES;
    if (self.folded && self.roomHeld && !self.reshaping) {
        taken = NSPointInRect(screen, [self catBoxIn:frame]) || CatRoomTakes(screen, self.roomParts, kRoomMargin);
        if (NSEvent.pressedMouseButtons == 0) [self passClicks:!taken];
    }
    // A site in the panel isn't the page: the pointer on one is off the page. Nor is the panel while it's away, even as
    // it's pulled back out under the pointer.
    BOOL inside = self.panel.isVisible && taken && !self.parked && NSPointInRect(screen, frame)
                  && ![self browserAt:[self.panel convertPointFromScreen:screen]];
    // Off the panel without moving, its edge moved past the pointer (a card folding away) or one of its menus closed
    // where the pointer picked from it: the page is told it's still there, and again once it moves.
    if (!inside) {
        [self dropShape];
        BOOL held = [self heldTakes:screen];
        if (self.hovering || held != self.pointerHeld) {
            if (self.hovering) self.leftStill = !moved;
            self.hovering = NO;
            self.pointerHeld = held;
            [self.page hoverEnd:self.leftStill held:held];
        } else if (self.leftStill && moved) {
            self.leftStill = NO;
            [self.page hoverEnd:NO held:held];
        }
        return;
    }
    self.leftStill = NO;
    self.pointerHeld = NO;
    [self.shape set];
    // The page's top is above its list's (pageTop), and its left edge pageLeft. Cut down to the whole point, as WebKit
    // cuts a press's, so what the page lights under the pointer is what a press there lands on, even within a point of
    // where two things meet (Side Chat's bar beside Deploy).
    NSPoint page = NSMakePoint(floor(screen.x - [self pageLeft]), floor([self pageTop] - screen.y));
    if (self.hovering && NSEqualPoints(page, self.lastHover)) return;
    self.hovering = YES;
    self.lastHover = page;
    [self.page hoverAt:page];
}

// Whether the pointer at `screen` is on what the panel holds over or under itself (Spotify's token, the usage card),
// where that takes it: off the page, but still with the panel, so the folded cat's list stays out (peek.js). Each takes
// the pointer only over what shows of it, as it has just been told where the pointer is.
- (BOOL)heldTakes:(NSPoint)screen {
    for (NSWindow *window in self.panel.childWindows)
        if (window != self.shade && window.isVisible && window.alphaValue > 0 && !window.ignoresMouseEvents
            && NSPointInRect(screen, window.frame)) return YES;
    return NO;
}

// Looks at the pointer this often from now on (pollPointer), unless it's resting (restPointer:).
- (void)pollPointerEvery:(NSTimeInterval)every {
    if (self.pointerResting) return;
    if (self.pointerTimer && fabs(self.pointerTimer.timeInterval - every) < 0.001) return;
    [self.pointerTimer invalidate];
    self.pointerTimer = [NSTimer scheduledTimerWithTimeInterval:every target:self selector:@selector(pollPointer)
                                                       userInfo:nil repeats:YES];
    self.pointerTimer.tolerance = every / 4;
}

// The pointer isn't looked at while nothing of the panel can be seen (hidden, the screen asleep or locked: `seen`, in
// parts/glass, which counts a panel flicked off the screen's edge as seen, as a swipe on Whozmove there needs the
// pointer). First the page hears it has gone, the arrow is back, and the folded cat stops watching. Seen again, it's
// looked at as often as the panel needs.
- (void)restPointer:(BOOL)resting {
    if (resting == self.pointerResting) return;
    if (resting) {
        [self dropShape];
        if (self.hovering || self.pointerHeld) {
            self.hovering = self.pointerHeld = NO;
            [self.page hoverEnd:NO held:NO];
        }
        [self tellCatPointerGone];
        self.pointerResting = YES;
        [self.pointerTimer invalidate];
        self.pointerTimer = nil;
    } else {
        self.pointerResting = NO;
        [self pollPointerEvery:self.roomHeld ? kPointerEveryWatched : kPointerEvery];
    }
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

// Which way what comes out of the cat goes, as the page should lay it out before it comes: told as it changes, as the
// cat is moved about the screen, while nothing is out (what is goes in as it moves, tellMoving:).
- (void)tellCatWay {
    if (self.roomHeld || self.movingTold || !self.page.ready) return;
    NSRect visible = (self.panel.screen ?: NSScreen.mainScreen).visibleFrame;
    CatWay way = CatWayFor([self foldedGlassIn:self.panel.frame], visible), told = self.toldWay;
    if (self.wayTold && way.right == told.right && way.up == told.up && way.across == told.across
        && way.tall == told.tall) return;
    self.toldWay = way;
    self.wayTold = YES;
    [self.page catWay:way.right up:way.up across:way.across tall:way.tall];
}

- (void)tellCatPointerGone {
    if (!self.catSeesPointer) return;
    self.catSeesPointer = NO;
    // While there's room beside the cat, the pointer is looked at as often still, for what takes clicks there.
    [self pollPointerEvery:self.roomHeld ? kPointerEveryWatched : kPointerEvery];
    [self.page catPointerGone];
}
@end
