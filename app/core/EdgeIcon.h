// EdgeIcon: an icon tucked half under the panel's glass at its edge, on the side facing the screen's middle: Spotify's
// round token at the bottom corner, and Whozmove's own at the top while the header has gone. What they share: a small
// window of its own that the panel holds under itself, so it's really beneath the glass; following the glass as it
// moves and grows; changing sides with the panel, under the glass; waiting under the glass while the panel opens, then
// coming out; going from sight while the panel is turned over; taking clicks only over itself; and the label beside it
// saying what a press does, in its own lane outside the panel. Each icon draws itself in its box and brings its own
// moves.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

@class PanelWindow;

// How far out from the glass's edge an icon's middle is when it's tucked (all of it under the glass); at rest it's 0
// (half out).
extern const CGFloat kEdgeTucked;

@interface EdgeIcon : NSObject
// Made with its box's size, the icon drawn in it about its middle, and how far from its middle a press or the pointer
// counts.
- (instancetype)initWithBox:(CGFloat)box reach:(CGFloat)reach;
// Its own small window.
@property (readonly) NSWindow *window;
// Held under the panel's glass, following the glass, the pointer, and the panel turning over.
- (void)holdBy:(PanelWindow *)panel;
@property (readonly, weak) PanelWindow *panelWindow;
// Off, it tucks away and stays away.
@property (nonatomic) BOOL shown;
// The panel is opening out of the cat: it stays under the glass until the glass has come to rest, then comes out with
// one small bounce.
- (void)panelOpening;
// Back out after a press that went under the glass and couldn't go through.
- (void)untuck;

// For each icon itself.
// The box it's drawn in, its middle the icon's middle.
@property (readonly) CALayer *box;
// The side of the panel it's on, left or right.
@property (readonly, copy) NSString *side;
// Whether it's on the dark panel or the light one (the panel's Look menu, app/core/MenuBar.m).
@property (readonly) BOOL dark;
// Out from under the glass: shown, and wanting to be (wantsOut), not tucking, the panel neither opening nor turned
// over, nor pushed off the screen's edge (but for an icon that shows then).
@property (readonly) BOOL visible;
// The pointer is over it (only the part outside the glass counts), and where the pointer was last.
@property (readonly) BOOL over;
@property (readonly) NSPoint pointer;
// How far out from the glass's edge and along it its middle is now, and where it's headed. Changing sides and coming
// out after an opening move it by themselves; otherwise step: does.
@property (assign) CGFloat out, along, outTo, alongTo;
// Changing sides, about to, or coming out after the panel has opened: moves of its own that the pointer waits for.
@property (readonly) BOOL busy;
// The panel has just moved (a drag): for a while the pointer was moving the panel, not reaching for the icon.
@property (readonly) BOOL movedJustNow;
// The glass's edge as it is now, partway through a move, and the icon's middle on the screen, `out` from it.
- (NSRect)glassNow;
- (NSPoint)centerOut:(CGFloat)out along:(CGFloat)along;
// Where the glass is headed (or is, once it's still).
@property (readonly) NSRect glass;
// Goes in under the glass, then runs `then` once it's all the way under; meanwhile, and after, it's tucking.
- (void)tuckThen:(void (^)(void))then;
@property (readonly) BOOL tucking;
// A tuck whose `then` has run is over: out again as it's next aimed. One still going under carries on.
- (void)endTuck;
// Where it's headed again, from whatever changed; and its moves run, a frame at a time, until it has settled.
- (void)aim;
- (void)kick;
// The label beside it: what a press does, and after a dot, what to; and showing it or not.
- (void)setLabel:(NSString *)what more:(NSString *)more;
- (void)showLabel:(BOOL)on;

// What each icon fills in.
// Whether it wants to be out now, besides being shown (YES unless it says otherwise).
- (BOOL)wantsOut;
// The height of its middle beside `glass` (Spotify's near the bottom, Whozmove's near the top).
- (CGFloat)heightBeside:(NSRect)glass;
// Each frame it isn't changing sides or coming out: out and along toward outTo and alongTo, a share of what's left
// (the default), or its own way; and whether it has settled.
- (void)step:(CFTimeInterval)dt;
- (BOOL)settled;
// Each frame, after it's placed: its own drawing.
- (void)drawAt:(CFTimeInterval)now;
// The pointer, while it's out and its own moves allow: `over` it or not. Nothing by default.
- (void)pointerMoved:(NSPoint)point over:(BOOL)over;
// A press on it (the default: pressed), the pointer dragged with it held, and let go, on the screen.
- (void)downAt:(NSPoint)point;
- (void)draggedTo:(NSPoint)point;
- (void)upAt:(NSPoint)point;
- (void)pressed;
// Its colours, painted again whenever the panel turns light or dark: call super for the label's.
- (void)paint;
// Visible has changed to `visible`: on its way out or in.
- (void)aimed:(BOOL)visible;
// The glass has started moving to `glass` over `duration` seconds (0 for at once).
- (void)glassMoving:(NSRect)glass over:(NSTimeInterval)duration;
// Whether it keeps its place and side whatever the glass does, for moves of its own (NO by default); and its window
// put where its middle is now (place, as the glass and its out say, unless it keeps its place), or at `middle`.
- (BOOL)keepsPlace;
- (void)place;
- (void)placeAt:(NSPoint)middle;
// Held down by a press on it, from the press until it's let go.
@property (readonly) BOOL pressing;
// Whether it stays out while the panel is pushed off the screen's edge (NO by default: it goes with the panel).
- (BOOL)showsWhileAway;
@end

// Which side of the panel the icons are on, from where the list is on the screen: the side facing the screen's middle,
// so a panel at the left has them at its right. Across the middle it changes only past a little leeway, so a panel
// dragged along the middle doesn't send them back and forth. `current` is nil at first.
NSString *EdgeSideFor(NSRect list, NSRect screen, NSString *current);
