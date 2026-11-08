// PanelWindow (Turn): turning over to the panel's back, and back.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "PanelWindow+Private.h"
#import "Turning.h"

CGFloat TurnEased(CGFloat x) {
    x = MAX(0, MIN(1, x));
    return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2;
}

CGPoint AnchorOf(NSView *view) {
    CGPoint anchor = view.layer.anchorPoint;
    NSRect frame = view.frame;
    return CGPointMake(NSMinX(frame) + anchor.x * NSWidth(frame), NSMinY(frame) + anchor.y * NSHeight(frame));
}

CATransform3D TurnAbout(CGPoint middle, CGPoint anchor, CGFloat angle, CATransform3D own, CGPoint centre) {
    CATransform3D eye = CATransform3DIdentity;
    eye.m34 = -1 / kTurnDepth;
    CATransform3D turn = CATransform3DConcat(CATransform3DMakeRotation(angle, 0, 1, 0), eye);
    CATransform3D m = CATransform3DMakeTranslation(anchor.x - centre.x, anchor.y - centre.y, 0);
    m = CATransform3DConcat(m, own);
    m = CATransform3DConcat(m, CATransform3DMakeTranslation(centre.x - middle.x, centre.y - middle.y, 0));
    m = CATransform3DConcat(m, turn);
    return CATransform3DConcat(m, CATransform3DMakeTranslation(middle.x - anchor.x, middle.y - anchor.y, 0));
}

@implementation PanelWindow (Turn)

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

- (BOOL)turningBack {
    return (self.turning && !self.turningOver) || [self.pendingTurn isEqual:@NO];
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
// under the panel going from sight as it starts, and the window is the panel again. Turning back from the buttons at
// its right end carries on the same way round, so over and back make one whole turn, while ‹ at the left end of the
// back's apps turns it back the way it came; what was held comes back as it lands. With reduced motion, one side fades
// into the other. Asked again on the way, while the panel changes shape (opening out of the cat, the reader
// folding), or while it comes back from the screen's edge (Settings… in the pawn menu brings it back first), the newest
// is taken once that's done, and what was to come after each runs in turn.
- (void)turnOver:(BOOL)over then:(void (^)(void))then {
    [self turnOver:over left:NO then:then];
}

- (void)turnOver:(BOOL)over left:(BOOL)left then:(void (^)(void))then {
    if (self.turning || self.returning || (self.reshaping && over != self.turned)) {
        void (^earlier)(void) = self.pendingTurnThen;
        self.pendingTurn = @(over);
        self.pendingTurnLeft = left;
        self.pendingTurnThen = ^{ if (earlier) earlier(); if (then) then(); };
        return;
    }
    if (!self.back || over == self.turned || (over && (self.expanded || self.folded))) {
        if (then) then();
        return;
    }
    self.turning = YES;
    self.turningOver = over;
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
    [self setWindowFrame:TurnRoom(panel) glass:panel clip:panel then:^{
        [weakSelf spin:over left:left then:^{ [weakSelf setWindowFrame:panel showing:panel then:done]; }];
    }];
}

NSRect TurnRoom(NSRect panel) {
    CGFloat grows = kTurnDepth / (kTurnDepth - kWidth / 2) - 1;
    return NSInsetRect(panel, -4, -(ceil(NSHeight(panel) / 2 * grows) + 2));
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
    [self turnOver:next.boolValue left:self.pendingTurnLeft then:after];
}

// The turn, played by Core Animation, as the folded glass's breath is: the glass, both sides and the panel's shadow
// turn as one about the panel's middle, the back coming round as the list goes, so each side shows as it is all the
// way; they swap where the panel is edge-on, and its edge shows there. Only what's drawn moves, so nothing is laid out
// or drawn again on the way.
- (void)spin:(BOOL)over left:(BOOL)left then:(void (^)(void))then {
    NSRect local = [self inWindow:self.turnFrame];
    CGPoint middle = CGPointMake(NSMidX(local), NSMidY(local));
    // It turns the way the press pushes it: its right edge sinking in, as from the buttons at its right end, so over
    // takes it half a turn and back carries on round the other half; or, `left`, its left edge sinking in, half a turn
    // the other way round.
    CGFloat from = over ? 0 : M_PI, to = from + (left ? -M_PI : M_PI);
    // The edge is on whichever side the halfway angle brings toward you, as that's the side the panel shows edge-on.
    CATransform3D halfway = CATransform3DMakeRotation((from + to) / 2, 0, 1, 0);
    BOOL nearLeft = (NSMinX(local) - middle.x) * halfway.m13 > (NSMaxX(local) - middle.x) * halfway.m13;
    CGFloat side = nearLeft ? NSMinX(local) : NSMaxX(local);
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
@end
