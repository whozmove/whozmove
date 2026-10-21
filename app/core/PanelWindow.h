// PanelWindow: the floating glass window, its drag strip, its size, and the pointer over it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>

@class Page;

@interface PanelWindow : NSObject
// Builds the window around the page's view, and starts following the pointer over it.
- (instancetype)initWithPage:(Page *)page;
// Shows it where it was last left, or at the top right of the screen the first time.
- (void)show;
// The tooltip over the header, which the drag strip covers (so the page's own can't show there): the running
// build's details, while Show Build in Header is ticked; nil for none.
@property (copy) NSString *headerTip;
// The header slides away with the list's scroll (panel/scripts/header.js): how many of its points still show at the
// panel's top, which the drag strip covers and no more, and whether it has gone. Those following it hear whether it
// has gone, as it changes.
- (void)headerShowing:(CGFloat)showing gone:(BOOL)gone;
@property (readonly) BOOL headerGone;
- (void)followHeader:(void (^)(BOOL gone))observer;
// The menu bar's Show / Hide Panel and Reset Position.
- (void)toggle;
// Whether the panel is on screen (not hidden from the menu bar), or flicked off its edge (parked).
@property (readonly) BOOL shown;
// How the panel looks, from the Look menu (MenuBar): "grey" or "black" (white on the light panel), solid, or "glass",
// what's behind it showing through, blurred and tinted. Light or dark as the app is, which the Look menu sets too.
@property (nonatomic, copy) NSString *look;
// Brings the panel back if it was hidden or flicked off the screen's edge, and leaves it as it is if it's showing
// (⌃⌥N).
- (void)bringUp;
- (void)resetPosition;
// Tells a freshly loaded page how tall the panel can grow (and, folded, which way the cat's tags go).
- (void)resendRoom;
// The height the page asks for, kept within that room.
- (void)fitHeight:(CGFloat)height;
// The reader: the panel grows beside the list, which stays where it was, by as much as the reader needs (its width,
// and the height of the whole panel), within the screen; asked again as what it shows changes. Then folds back.
- (void)expandReader:(CGFloat)width height:(CGFloat)height;
- (void)collapse:(CGFloat)height;
// Runs `then` once the panel has stopped changing size (the reader growing beside the list, or folding back), or at
// once if it isn't: for what should start only once it's in view.
- (void)whenStill:(void (^)(void))then;
// A module's view held over part of the page (a page shown in the reader's body, Browser.h), `rect` in the page's
// points from its top-left corner: cut by the panel's rounded edges, uncovered as the panel grows, and moving wherever
// the page does, as the page's own parts do. Held again, it moves to the new place.
- (void)hold:(NSView *)view overPage:(NSRect)rect;
- (void)letGo:(NSView *)view;
// The panel's other side: a view (the apps module's page) on the back of the glass, as wide as the list and as tall as
// the panel, which shows while the panel is turned over.
- (void)holdBack:(NSView *)view;
// Turns the panel over to its back, or back to its list: about its middle, the glass with its shadow and both sides
// as one. `then` runs once it has, or at once if it's that way already. Not while the reader is open, nor folded.
- (void)turnOver:(BOOL)over then:(void (^)(void))then;
// Whether it's turned over, or on its way to or from there.
@property (readonly) BOOL turned;
// Each told in the frame the panel starts turning over (YES), and in the frame it lands back on its list side (NO):
// what's held over or under the panel goes with the turn, and stays out of sight meanwhile.
- (void)followTurn:(void (^)(BOOL turned))observer;
// Folded, the panel is the cat in a small round glass where the name's o is in its header (panel/scripts/cat.js); the
// page says when it folds and opens, moving, or at once as it loads.
- (void)fold:(BOOL)on instant:(BOOL)instant;
// Where the page has the name's o, from the list's top-left corner: where the folded glass's middle is.
- (void)catAt:(NSPoint)at;
// Folded, room under and beside the cat for its tags while they're out (cat.js), `width` and `height` points from the
// cat's square's top corner on the far side from them; and that room taken away once they've gone.
- (void)catFan:(BOOL)on width:(CGFloat)width height:(CGFloat)height;
// How many sessions are working: while any are, the folded glass breathes, quicker the more there are; once none are,
// it finishes the breath it's in and rests.
- (void)catBreathe:(NSInteger)working;
// A text box in the page was clicked into (YES), or left (NO).
- (void)takeKeyboard:(BOOL)on;
// Gives the keyboard back to the app in front if the panel has it, before the app being opened comes forward. YES if
// it had it.
- (BOOL)releaseKeyboard;
// Whether the panel still has the keyboard though nothing in it asks for it now, as a box or a site let it go.
- (BOOL)keptKeyboard;
// Opens a menu at a point in the page's coordinates.
- (void)popUpMenu:(NSMenu *)menu atPagePoint:(NSPoint)point;
// A small window held under the panel, moving with it (Spotify's token).
- (void)attachBelow:(NSWindow *)window;
// A window held under the panel held over it instead, or back under it (Whozmove beside the panel, coming in front of
// the glass as the panel folds round it).
- (void)hold:(NSWindow *)window over:(BOOL)over;
// The same, held over the panel instead, so the panel's shadow doesn't fall on it: for a window that draws nothing
// where the panel is (the usage card).
- (void)attachAbove:(NSWindow *)window;
// Each told whenever the glass moves or changes size: where it is on the screen, where the list is (the reader grows
// beside it), the screen's room, and how long it takes to get there (0 for at once).
- (void)followGlass:(void (^)(NSRect glass, NSRect list, NSRect screen, NSTimeInterval duration))observer;
// Each told the pointer's place on the screen, wherever it is, as often as it's polled.
- (void)followPointer:(void (^)(NSPoint screen))observer;
// The side of the panel the icons at its edge are on (EdgeIcon.h), left or right, facing the screen's middle: worked
// out once each time the glass moves, before those following it are told, so the icons always agree.
@property (readonly, copy) NSString *edgeSide;
// Folded into the cat, or on its way there; and each told as the panel starts folding or opening (`done` NO), and once
// it has (`done` YES), or once only, at once, for a fold that doesn't move.
@property (readonly) BOOL folded;
- (void)followFold:(void (^)(BOOL folded, BOOL done))observer;
// Each told when the Look menu changes the panel's look (light or dark comes to each view by itself).
- (void)followLook:(void (^)(void))observer;
// Where the page's list's top-left corner is on the screen, which the page's places (catAt) count from.
@property (readonly) NSPoint listCorner;
// The panel dragged by hand, by `by` points (the drag strip over the header, or Whozmove beside the panel): it moves as
// far as macOS lets it, and what follows the glass hears. NO while it's changing size, when it can't be dragged.
- (BOOL)dragBy:(NSPoint)by;
// The drag is over: the panel's place is kept, and the room it has below worked out again.
- (void)draggedByHand;
// A sideways two-finger flick on the open panel's list pushes it off that edge of the screen, out of sight, with
// Whozmove peeking out where it went (SideCat.h); it comes back where it was from there, or from Show / Hide Panel or
// ⌃⌥N (unpark). Whether it's away, and each told as it goes (YES) and as it starts back (NO): what's held over or under
// it stays out of sight meanwhile. It isn't kept away when the app starts again.
@property (readonly) BOOL parked;
- (void)followAway:(void (^)(BOOL away))observer;
- (void)unpark;
@end

// A two-finger swipe whose fingers have gone `x` across and `y` down so far: 0 while it's too soon to say, 1 once it's
// sideways (the panel's), -1 once it isn't (the list's, to scroll).
int SwipeWay(CGFloat x, CGFloat y);
// Whether fingers lifting at `speed` points a second across, having gone `x`, flick the panel off the screen's edge:
// fast enough, and the way they went.
BOOL SwipeFlicks(CGFloat speed, CGFloat x);
// Folded, how far its round glass `glass` moves for a swipe that would move it `by`: as far as that, up to the edge of
// the screen's room `visible` and no further; one already past an edge isn't pulled back, but goes no further out.
NSPoint FoldedMove(NSRect glass, NSPoint by, NSRect visible);
// Where the panel goes, flicked toward the right or the left of the screen's room `visible`: just past its edge.
NSPoint ParkedOrigin(NSRect frame, NSRect visible, BOOL right);
// How much the panel shows as it goes past the screen's edge or comes back from there: none of it past the edge, less
// and less as less of it is on the screen, so on a display beside it, it never shows.
CGFloat ParkedShows(NSRect frame, NSRect visible);
