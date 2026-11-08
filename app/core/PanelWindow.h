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
// The header is pushed away by the row you're on as the list scrolls (parts/header): how many of its points
// still show at the panel's top, which the drag strip covers and no more, and whether it has gone. Those following it
// hear whether it has gone, as it changes.
- (void)headerShowing:(CGFloat)showing gone:(BOOL)gone;
@property (readonly) BOOL headerGone;
- (void)followHeader:(void (^)(BOOL gone))observer;
// The menu bar's Show / Hide Panel and Reset Position.
- (void)toggle;
// Whether the panel is on screen (not hidden from the menu bar), or flicked off its edge (parked).
@property (readonly) BOOL shown;
// How the panel looks, from Settings' Appearance: "grey" or "black" (white on the light panel), solid, or "glass",
// what's behind it showing through, blurred and tinted. Light or dark as the app is, which Appearance sets too.
@property (nonatomic, copy) NSString *look;
// Brings the panel back if it was hidden or flicked off the screen's edge, and leaves it as it is if it's showing
// (⌃⌥N).
- (void)bringUp;
- (void)resetPosition;
// Tells a freshly loaded page how tall the panel can grow (and, folded, which way what comes out of the cat goes).
- (void)resendRoom;
// The height the page asks for, kept within that room.
- (void)fitHeight:(CGFloat)height;
// How tall the lines under the header are (a notice, the setup line, a new conversation's card), which the panel always
// has room for, with the header and a row, where the screen allows (RoomFor).
- (void)linesUnder:(CGFloat)under;
// A module's view held over part of the page (a page shown in the reader's body, Browser.h), `rect` in the page's
// points from its top-left corner: cut by the panel's rounded edges, uncovered as the panel grows, and moving wherever
// the page does, as the page's own parts do. Held again, it moves to the new place.
- (void)hold:(NSView *)view overPage:(NSRect)rect;
- (void)letGo:(NSView *)view;
// Whether it's turned over, or on its way to or from there.
@property (readonly) BOOL turned;
// A small window held under the panel, moving with it (Spotify's token).
- (void)attachBelow:(NSWindow *)window;
// A window held under the panel held over it instead, or back under it (Whozmove beside the panel, coming in front of
// the glass as the panel folds round it).
- (void)hold:(NSWindow *)window over:(BOOL)over;
// The same, held over the panel instead, so the panel's shadow doesn't fall on it: for a window that draws nothing
// where the panel is (the usage card).
- (void)attachAbove:(NSWindow *)window;
// How far below the panel's bottom edge a window it holds may hang (the usage card, open), in points, so the panel
// keeps that much room, and a little more, above the screen's bottom (RoomFor); 0 lets it go. The panel keeps the
// most any window asks for.
- (void)keepBelow:(CGFloat)points for:(NSWindow *)window;
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
// Each told when Appearance changes the panel's look (light or dark comes to each view by itself).
- (void)followLook:(void (^)(void))observer;
// Where the page's list's top-left corner is on the screen, which the page's places (catAt) count from.
@property (readonly) NSPoint listCorner;
// The panel dragged by hand, by `by` points (the drag strip over the header, or Whozmove beside the panel): it moves as
// far as macOS lets it, and what follows the glass hears. NO while it's changing size, when it can't be dragged, and
// while chats are out beside the folded cat, until they've gone in (the page is told the cat is moving).
- (BOOL)dragBy:(NSPoint)by;
// The drag is over: the panel's place is kept, the room it has below worked out again, and the page told the folded
// cat has stopped moving.
- (void)draggedByHand;
// A sideways two-finger flick on the open panel's list pushes it off that edge of the screen, out of sight, with
// Whozmove peeking out where it went (SideCat.h); it comes back where it was from there, or from Show / Hide Panel or
// ⌃⌥N (unpark). Whether it's away, and each told as it goes (YES) and as it starts back (NO): what's held over or under
// it stays out of sight meanwhile. It isn't kept away when the app starts again.
@property (readonly) BOOL parked;
@end

@interface PanelWindow (Pane)
// The reader: the panel grows beside the list, which stays where it was, by as much as the reader needs (its width,
// and the height of the whole panel), within the screen; asked again as what it shows changes. Then folds back.
- (void)expandReader:(CGFloat)width height:(CGFloat)height;
- (void)collapse:(CGFloat)height;
// Runs `then` once the panel has stopped changing size (the reader growing beside the list, or folding back), or at
// once if it isn't: for what should start only once it's in view.
- (void)whenStill:(void (^)(void))then;
@end

@interface PanelWindow (Turn)
// The panel's other side: a view (the apps module's page) on the back of the glass, as wide as the list and as tall as
// the panel, which shows while the panel is turned over.
- (void)holdBack:(NSView *)view;
// Turns the panel over to its back, or back to its list: about its middle, the glass with its shadow and both sides
// as one. `then` runs once it has, or at once if it's that way already. Not while the reader is open, nor folded.
// It turns as a press at the panel's right end pushes it, that edge sinking in; `left`, the other way round, as a
// press at its left end does.
- (void)turnOver:(BOOL)over then:(void (^)(void))then;
- (void)turnOver:(BOOL)over left:(BOOL)left then:(void (^)(void))then;
// Whether it's on its way back to its list side: turning there now, or asked to once what it's doing is done.
@property (readonly) BOOL turningBack;
// Each told in the frame the panel starts turning over (YES), and in the frame it lands back on its list side (NO):
// what's held over or under the panel goes with the turn, and stays out of sight meanwhile.
- (void)followTurn:(void (^)(BOOL turned))observer;
@end

@interface PanelWindow (Fold)
// Folded, the panel is the cat in a small round glass where the name's o is in its header (parts/cat/page/cat.js); the
// page says when it folds and opens, moving, or at once as it loads.
- (void)fold:(BOOL)on instant:(BOOL)instant;
// The same, folding with chats still out beside the cat: `room` is where they go back out to as it folds, as catRoom:
// has its parts, and the window holds that room once it has folded. `peek` for the folded cat's list coming out while
// it's pointed at, or going back in (parts/peek/page/peek.js): asked the other way while it's still moving, it turns
// back from where it is, and how the panel is left for next launch isn't changed.
- (void)fold:(BOOL)on instant:(BOOL)instant room:(NSArray *)room peek:(BOOL)peek;
// The folded cat's list on pointing is kept open (pressed, peek.js): the panel is left open for next launch.
- (void)keepOpen;
// Where the page has the name's o, from the list's top-left corner: where the folded glass's middle is.
- (void)catAt:(NSPoint)at;
// How many sessions are working: while any are, the folded glass breathes, quicker the more there are; once none are,
// it finishes the breath it's in and rests.
- (void)catBreathe:(NSInteger)working;
// The rest of what's said with folded, above.
- (void)followFold:(void (^)(BOOL folded, BOOL done))observer;
@end

@interface PanelWindow (Chats)
// Folded, room beside the cat for what comes out of it (its chats, chats.js), as the page lays it out: `parts`, each
// [x, y, width, height] in points from the glass's middle with y running down, which the window takes in, with room
// for their shadows, letting clicks through everywhere else. With no parts, the window is the cat's square again. The
// page hears once the window has the room (catRoomTaken).
- (void)catRoom:(NSDictionary *)room;
@end

@interface PanelWindow (Keyboard)
// A text box in the page was clicked into (YES), or left (NO).
- (void)takeKeyboard:(BOOL)on;
// Gives the keyboard back to the app in front if the panel has it, before the app being opened comes forward. YES if
// it had it.
- (BOOL)releaseKeyboard;
// Whether the panel still has the keyboard though nothing in it asks for it now, as a box or a site let it go.
- (BOOL)keptKeyboard;
// Opens a menu at a point in the page's coordinates.
- (void)popUpMenu:(NSMenu *)menu atPagePoint:(NSPoint)point;
@end

@interface PanelWindow (Hover)
// What the pointer looks like over the page where it is now: hand, text or arrow.
- (void)pointerShape:(NSString *)shape;
// Whether you've been using the panel in the last `seconds`: the pointer on it, one of its menus open, or the
// keyboard with it. What a session asks the panel to do that you'd see happen waits till you've stepped off it.
- (BOOL)inUseWithin:(NSTimeInterval)seconds;
@end

@interface PanelWindow (Flick)
// The rest of what's said with parked, above.
- (void)followAway:(void (^)(BOOL away))observer;
- (void)unpark;
// Away, a sideways two-finger swipe on `window` (Whozmove peeking out where the panel went) is the panel's too, and
// nothing under the pointer gets it: toward the screen's middle, it pulls the panel back out with the fingers
// (SwipePulled), and once they lift, the panel carries on to where it was (PullBrings) or goes back off the edge.
// Toward the edge, `swiped` is told how far the fingers have gone that way. It's told `down` once the swipe is taken,
// and not once its fingers have lifted (or it's given up). The rest of the swipe, and the trackpad's glide after it, go
// to a window under the pointer that can't be seen, so none of it goes to what's under the pointer.
- (void)takeSwipesAwayOn:(NSWindow *)window swiped:(void (^)(CGFloat pushed, BOOL down))swiped;
@end

// A two-finger swipe whose fingers have gone `x` across and `y` down so far: 0 while it's too soon to say, 1 once it's
// sideways (the panel's), -1 once it isn't (the list's, to scroll).
int SwipeWay(CGFloat x, CGFloat y);
// Whether fingers lifting at `speed` points a second across, having gone `x`, flick the panel off the screen's edge:
// fast enough, and the way they went.
BOOL SwipeFlicks(CGFloat speed, CGFloat x);
// How far out from the screen's edge the panel comes as fingers pull it back, having gone `travel` points toward the
// screen's middle, with `room` points from the edge to where it was: point for point, then harder past where it was.
CGFloat SwipePulled(CGFloat travel, CGFloat room);
// Whether fingers lifting with the panel `out` points out from the screen's edge, `width` wide, at `speed` points a
// second toward the screen's middle, bring it the rest of the way back: a third of it out, unless they flick it back
// toward the edge, or a flick toward the middle.
BOOL PullBrings(CGFloat out, CGFloat width, CGFloat speed);
// Which way what comes out of the folded cat goes, for its glass `glass` on a screen whose room is `visible`: toward
// the screen's middle, so to its right while it's on the screen's left half, and up from its foot while it's on the
// lower half, else down from its top; `across` points from the glass's middle to the screen's edge that way, and `tall`
// from its top (going down) or its foot (going up) to the screen's edge, no more than the page has room for above the
// list (kAboveRoom), either way.
typedef struct { BOOL right, up; CGFloat across, tall; } CatWay;
CatWay CatWayFor(NSRect glass, NSRect visible);
// The folded window that takes in the cat's square `box` and each of `parts` (on the screen), with `shadow` points
// round each part for its shadow, in whole points.
NSRect CatRoomFrame(NSRect box, NSArray<NSValue *> *parts, CGFloat shadow);
// Whether a press at `point` lands on one of `parts` (on the screen), or within `margin` points of one: where the room
// beside the cat takes a click, rather than letting it through to what's under the panel.
BOOL CatRoomTakes(NSPoint point, NSArray<NSValue *> *parts, CGFloat margin);
// Where the panel goes, flicked toward the right or the left of the screen's room `visible`: just past its edge.
NSPoint ParkedOrigin(NSRect frame, NSRect visible, BOOL right);
// How much the panel shows as it goes past the screen's edge or comes back from there: none of it past the edge, less
// and less as less of it is on the screen, so on a display beside it, it never shows.
CGFloat ParkedShows(NSRect frame, NSRect visible);
// The window turning over takes in this room round the panel `panel` (on the screen): above and below it for its near
// edge, which comes toward you and is seen taller than the panel, and a little either side.
NSRect TurnRoom(NSRect panel);
// The page's frame in the clip `clip` of a window that's `window` on the screen, with its list's top-left corner at
// `root` on the screen and `tall` points of it below there: the reader's room either side of the list, and the room
// above it (kAboveRoom). `window` is where the window really is, which near the top of the screen may be lower than it
// was asked to be: macOS keeps it under the menu bar.
NSRect PageFrameIn(NSPoint root, CGFloat tall, NSRect window, NSRect clip);
// How tall the open panel can grow with its top edge at `top` on a screen whose room starts at `bottom` (above a Dock
// along its foot): down to there, or, with `below` points kept for what hangs under the panel, that and 16 more above
// it. Never less than the header, the lines under it (`under` tall) and a row, where the screen has that much: so
// dragged so low, what hangs below gives way first. In whole points.
CGFloat RoomFor(CGFloat top, CGFloat bottom, CGFloat below, CGFloat under);
// The open panel's height, opening out of the folded panel: what the page asked for while it was folded (`asked`, 0 if
// it hasn't), else what it was as it folded (`kept`, 0 for not known: 200), within `room`; at least the header.
CGFloat OpenedHeight(CGFloat kept, CGFloat asked, CGFloat room);
// The most the header and the list take together on a screen whose room under the menu bar is `visible` points tall:
// 640, or all of it on a screen shorter than that, in whole points. What opens under the header and the strips come on
// top (page/glass.css), and the room the panel has where it is keeps it on the screen (RoomFor).
CGFloat ListLimitFor(CGFloat visible);
