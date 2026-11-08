// PanelWindow+Private: what the panel window's parts share, one class in a file per part (PanelWindow+<Part>.m):
// the constants, the helper views and windows, the window's own state, and the methods a part calls in another.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "PanelWindow.h"
#import "Page.h"
#import "Appearance.h"
#import "Log.h"
#import "Browser.h"
#import "EdgeIcon.h"
#import "Easing.h"
#import <QuartzCore/QuartzCore.h>
#include <dlfcn.h>

// The panel's width; its header's height (--header in panel/styles/tokens.css) and the buttons at the header's right
// end, which the drag strip leaves to the page.
static const CGFloat kWidth = 340, kHeaderHeight = 46, kButtonsWidth = 104;
// The reader's ✕, at its header's right end (the kit's icon button, .icon-button in panel/styles/controls.css, with
// the header's padding), which the reader's drag strip leaves to the page.
static const CGFloat kCloseWidth = 46;
// The page is never laid out at another width: a change of width has WebKit lay it all out and draw it again, which
// shows as the whole panel flashing. So it's as wide as the list with room for the widest reader on either side of
// it (--side in panel/styles/tokens.css), always, and the window shows the part in use: the list, and the reader
// beside it while it's open. The page's left edge stays this far left of the list's.
static const CGFloat kReaderRoom = 1254, kPageWidth = kWidth + 2 * kReaderRoom;
// In the same way, the page always has this much room above the list (--above), out of sight, which the folded cat's
// chats come up into while it's low on the screen: so nothing in the page has to move, in step with the window, to
// make room for them. The page's top is this far above the list's.
static const CGFloat kAboveRoom = 800;
// Folded, the panel is a round glass kFoldGlass across, on the name's o in the open panel's header, in a window
// kFoldBox square: the room round the glass is for its shadow (parts/cat/page/cat.js draws the cat in it). The glass's
// corners are kCorner while it's open, and half its width while it's round.
static const CGFloat kFoldBox = 102, kFoldGlass = 76, kCorner = 24;
// Folded, the glass's middle is this far from the open panel's top-left corner, just above the name's o, so the cat's
// raised head is on the o, as the page says once it has measured it (catAt:, in whole points): the panel grows around
// the cat, which stays where it is and only changes size.
static const NSPoint kCatAt = {45, 23};
// Opening, the glass spreads from the circle behind the cat to the whole panel in kSpread, wider and taller together;
// folding, it closes back in on the cat the same way. The cat changes size on the same curve (parts/cat/page/cat.css).
static const NSTimeInterval kSpread = 0.5;
// How near the pointer has to be for the folded cat to be told where it is: its eyes follow it within 480pt (cat.js),
// and it's told a little further out, so it hears when the pointer leaves.
static const CGFloat kCatSees = 520;
// How often the pointer is looked at (pollPointer): 25 times a second for hover, and as often as the screen is drawn
// while the folded cat's eyes follow it, so they keep up with it, and while chats are out beside it, so clicks go
// through the room between them as soon as the pointer's there.
static const NSTimeInterval kPointerEvery = 0.04, kPointerEveryWatched = 1.0 / 60;
// Whether the panel was folded when it was left, so it comes back folded before its page has loaded.
static NSString *const kFoldedKey = @"panelFolded";
// The panel's shadow is its own, in a window held under the panel (shadeGlass), with this much room round the glass.
static const CGFloat kShadeRoom = 80;
// Turning over (turnOver:then:) takes kTurn. It's seen from kTurnDepth away, and its edge is kEdge thick, kEdgeInset in
// from the glass's top and bottom, where its corners round off.
static const NSTimeInterval kTurn = 0.7;
static const CGFloat kTurnDepth = 1100, kEdge = 6, kEdgeInset = 12;
// Turned over, the back's header leaves its left end to its page, for the ‹ back a page; the drag strip covers the
// rest, up to its buttons, as on the list's.
static const CGFloat kBackLead = 44;
// A sideways swipe: how far the fingers go before it's taken to be sideways or not, how far the panel leans with them
// at most, how fast they must be going as they lift for a flick (points a second), and how long the panel takes to go
// off the screen's edge, and to come back, at least and at most.
static const CGFloat kSwipeDecide = 6, kLeanMost = 20, kFlickSpeed = 800;
static const NSTimeInterval kParkLeast = 0.25, kParkMost = 0.7, kUnpark = 0.45;
// Pulled back from the screen's edge, how far past where it was the panel goes at most; let go too soon, how long it
// takes to slide back off. The catch under the pointer that takes the rest of a swipe on Whozmove there (holdAway): how
// big it is (two fingers on a trackpad don't move the pointer), how long it waits after the fingers lift for the
// trackpad's glide to start, and, should the glide's end never come, how long at most it stays.
static const CGFloat kPullPast = 40, kCatch = 32;
static const NSTimeInterval kSlideBack = 0.25, kGlideStarts = 0.15, kGlideMost = 3;
// Folded, the room beside the cat (catRoom:) takes in this much round each part the page draws there, for its shadow;
// and a click this near one is its, rather than going through to what's under the panel.
static const CGFloat kRoomShadow = 18, kRoomMargin = 6;


// Clicking the panel doesn't take the keyboard from the app being typed in (a click on a row, say, leaves it with
// Claude's message box): the panel becomes the key window only while one of its own text boxes is being typed in
// (wantsKeyboard, set by the page).
@interface FloatingPanel : NSPanel
@property (assign) BOOL wantsKeyboard;
@end

// A window that can't be seen, which takes the keyboard from the panel and goes at once (giveBackKeyboard).
@interface HandOffPanel : NSPanel
@end

// Transparent strip over the header: drag moves the panel, a plain click is handed to the page.
@interface DragStrip : NSView
@property (copy) void (^onClick)(void);
@property (copy) BOOL (^onDrag)(NSPoint by);  // each step of a drag (PanelWindow's dragBy:): NO if it can't move now
@property (copy) void (^onDragged)(void);     // the drag is over (draggedByHand)
@property (copy) void (^onPress)(BOOL down);  // the button pressed on it, and let go
@end

// A side of the panel: the page's clip, or the panel's back (holdBack:). The side turned away from you takes no
// clicks, and while the panel turns, neither does.
@interface SideView : NSView
@property (assign) BOOL away;
@end

// What modules hold over the page (hold:overPage:) is in this, laid over the page in its clip and kept where the page
// is: everything that moves the page (the panel growing, folding, turning over) moves it too, and the clip cuts it at
// the panel's rounded edges. Its y runs down from the page's top, as the page's own does. It takes no clicks itself,
// only those on what's in it, so the page under it gets the rest. It's beside the page rather than in it, so keys and
// scrolls a site in it doesn't use never reach the panel's page.
@interface PageCover : NSView
@end

// The tint over the glass, which makes the panel its look (Settings' Appearance, parts/settings): grey or black,
// solid, in the page's own colour for it (--panel in panel/styles/tokens.css), or glass. On the dark panel, glass is
// the HUD's dark glass, darkened; on the light one, a popover's light glass, lightened, and black is white. It has no
// edge of its own, only the panel's shadow. It's painted again whenever the panel turns light or dark, with the Mac
// or from Settings' Appearance, light or dark as the window is: the glass gives what's in it a look of its own, which
// may stay dark.
@interface Tint : NSView
@property (nonatomic, copy) NSString *look;
- (void)paint;
@end

// What the panel's shadow is drawn in (shadeGlass), told when the app turns light or dark: the shadow is softer on the
// light panel.
@interface ShadeView : NSView
@property (copy) void (^onLook)(void);
@end

@interface PanelWindow ()
@property (strong) Page *page;
@property (strong) FloatingPanel *panel;
@property (strong) DragStrip *strip;
@property (strong) DragStrip *readerStrip;  // over the reader's header, while it's open
@property (assign) CGFloat room;        // how tall the panel can grow where it is (see updateRoom)
@property (assign) CGFloat listLimit;   // the most the header and the list take on its screen (ListLimitFor)
// How far below the panel each window it holds may hang (keepBelow:for:), and the most of them (keptBelow).
@property (strong) NSMapTable<NSWindow *, NSNumber *> *belowKept;
@property (readonly) CGFloat keptBelow;
@property (assign) CGFloat linesUnder;  // how tall the lines under the header are, as the page last said (linesUnder:)
// What the page asked for while the panel was folded (fitHeight:), which it opens at; 0 until it asks.
@property (assign) CGFloat foldedAsked;
// Whether the page has heard if the panel can be seen, and what (tellSeen:).
@property (assign) BOOL seenTold, seenSaid;
@property (readonly) BOOL seen;  // anything of it can be seen, or it's flicked away (PanelWindow.m)
- (void)tellSeen:(BOOL)seen;
@property (strong) NSTimer *pointerTimer;
@property (assign) BOOL hovering;       // the pointer is over the panel
@property (assign) NSPoint lastHover;   // the last position sent to the page
@property (assign) BOOL pointerResting;  // not looked at while nothing of the panel can be seen (restPointer:)
@property (strong) NSCursor *shape;    // the pointer's shape the page asks for where it is, or nil for the arrow
@property (assign) NSPoint lastScreen;  // where the pointer was at the last look, on the screen
@property (assign) NSTimeInterval usedAt;  // when you last used the panel (inUseWithin:)
@property (assign) BOOL leftStill;      // it came off the panel without moving, and hasn't moved since
@property (assign) BOOL pointerHeld;    // off the page, on what the panel holds over or under itself (heldTakes:)
// The keyboard: a site's in the panel (Browser) since a click into it, or a box of the page's since it asked; the site
// the pointer was last passed to; and what watches clicks for the keyboard.
@property (assign) BOOL browserKeys;
@property (weak) Browser *keyboardBrowser;
@property (assign) BOOL pageKeys;
@property (weak) Browser *pointedBrowser;
@property (strong) id clickWatch;
// A sideways swipe on the panel (swiped:): whether it's allowed, whether it has been taken to be sideways or not and
// is the panel's, how far the fingers have gone, how fast they were going, and when the last part of it came; and
// where the panel was as it started.
@property (strong) id swipeWatch;
@property (assign) BOOL swipeAllowed, swipeDecided, swipeMine;
@property (assign) CGFloat swipeX, swipeY, swipeSpeed;
@property (assign) NSTimeInterval swipeAt;
@property (assign) NSPoint swipeFrom;
@property (assign) CGFloat swipeTop;
// Pushed off the screen's edge (parked), on its way (parkTimer), coming back from there (returning: a turn asked for
// meanwhile waits until it's back in its place), where it was before and the room on the screen it went from (the
// screen it's on once it has gone may be another), and who hears it has gone.
@property (assign) BOOL parked;
@property (strong) NSTimer *parkTimer;
@property (assign) BOOL returning;
@property (assign) NSPoint parkedFrom;
@property (assign) CGFloat parkedTop;
@property (assign) NSRect parkScreen;
@property (strong) NSMutableArray *awayObservers;
// Away, a swipe on Whozmove peeking out where it went (swipedAway:): the window it's on and who's told; whether this
// swipe is one, pulls the panel (else it pushes Whozmove), and still has its fingers down; the catch under the pointer
// that takes the rest of it (holdAway), whether it's there, and whether the trackpad's glide after it has started; and
// which catch a letting go that comes late is for.
@property (weak) NSWindow *awaySwipeWindow;
@property (copy) void (^awaySwiped)(CGFloat pushed, BOOL down);
@property (assign) BOOL swipeAway, pulling, awayDown;
@property (strong) FloatingPanel *swipeCatch;
@property (assign) BOOL awayHeld, gliding;
@property (assign) NSUInteger awayHold;
@property (strong) NSPanel *handOff;  // the keyboard's way back to the app in front (giveBackKeyboard)
@property (assign) BOOL expanded;       // grown to the screen for the reader
// The reader's size, asked for while the panel was opening out of the cat (a press on a chat beside it opened both),
// taken once it has opened.
@property (strong) NSValue *pendingReader;
@property (assign) NSRect listFrame;    // where the panel was before it grew, to fold back to
@property (assign) BOOL listOnRight;    // the reader opened to the list's left
// The panel's shape, apart from the window's: the glass and the page's clip (rounded, over it) normally fill the
// window, and while the panel changes size they show only part of it (reshapeTo:).
@property (strong) NSVisualEffectView *glass;
@property (strong) Tint *tint;
// The panel's shadow (shadeGlass): the window held under the panel, and in it the shadow, where the glass is.
@property (strong) NSPanel *shade;
@property (strong) CALayer *shadow;
@property (strong) SideView *clip;
// The panel's other side (holdBack:), and the edge that shows between the two while it turns (turnOver:then:).
@property (strong) SideView *back;
@property (strong) NSView *edge;
@property (strong) CAGradientLayer *edgeShade;
// Turned over, or on the way to or from it; turning; a turn asked for meanwhile, which way round, and what to do after
// it, taken next; the height the page asked for meanwhile; and who's told as it turns over and once it's back.
@property (assign) BOOL turned;
@property (assign) BOOL turning;
@property (assign) BOOL turningOver;  // the way the turn under way goes
@property (strong) NSNumber *pendingTurn;
@property (assign) BOOL pendingTurnLeft;
@property (copy) void (^pendingTurnThen)(void);
@property (assign) CGFloat heightAsked;
@property (assign) NSRect turnFrame;    // where the panel is as it turns, the window having taken in room round it
@property (strong) NSMutableArray *turnObservers;
@property (assign) BOOL reshaping;
@property (strong) NSMutableArray *stillWaiters;  // run once the panel has stopped changing size (whenStill:)
@property (strong) PageCover *cover;    // what modules hold over the page (hold:overPage:), made with the first
@property (assign) BOOL hasPending;     // a size asked for while the panel was changing size, taken next
@property (assign) NSRect pendingFrame;
@property (copy) void (^pendingDone)(void);
// Moving the glass, the clip and the page together, a step at a time (moveGlassTo:).
@property (strong) NSTimer *moveTimer;
// Who follows the glass and the pointer (followGlass:, followPointer:), and the side the icons at its edge are on.
@property (strong) NSMutableArray *glassObservers, *pointerObservers;
// How much of the header shows as it's pushed away (headerShowing:gone:), and who hears it has gone; who
// hears the panel fold and open, and its look change.
@property (assign) CGFloat headerPoints;
@property (assign) BOOL headerGone;
@property (strong) NSMutableArray *headerObservers, *foldObservers, *lookObservers;
@property (copy) NSString *edgeSide;
// Folded into the cat (fold:instant:); how tall the panel was as it folded, to open at again; a fold or an opening
// asked for while one was moving, taken next (nil for none).
@property (assign) BOOL folded;
// Folded, the room beside the cat the page asked for (catRoom:): whether the window holds any, so it's larger than the
// cat's square; where the cat's square is in it, from its bottom-left corner; and the parts drawn there, on the
// screen, which take clicks. While it changes, those following the glass aren't told: the cat's circle stays where it
// is.
@property (assign) BOOL roomHeld;
@property (assign) NSPoint roomOffset;
@property (strong) NSArray<NSValue *> *roomParts;
@property (assign) BOOL roomChanging;
// Whether clicks go through the panel to what's under it, where nothing's drawn in that room (passClicks:).
@property (assign) BOOL clicksThrough;
// Which way the page was last told the room goes (catWay:), or nil; and whether it was told the cat is moving.
@property (assign) CatWay toldWay;
@property (assign) BOOL wayTold, movingTold;
@property (copy) NSString *readerSideTold;  // the side the page last heard the reader would open to (tellReaderSide)
// Whether the page was told the folded cat is pressed (catPressed:), and not yet that it's let go.
@property (assign) BOOL pressTold;
// While the panel folds or opens (holdsPage), where the top-left corner of the page's list is held on the screen
// (rootAt): it starts where it was and goes where it ends, whatever the window takes in on the way.
@property (assign) BOOL holdsPage;
@property (assign) NSPoint pageAt;
// Where the glass's middle is from the open panel's top-left corner, folded (kCatAt until the page says).
@property (assign) NSPoint catAt;
@property (assign) CGFloat openHeight;
// The glass's corners now (roundGlass:).
@property (assign) CGFloat glassRadius;
@property (strong) NSNumber *pendingFold;
// Folding with chats still out beside the cat, the room they go back out to as it folds (fold:instant:room:peek:), as
// the page lays them out; held once it has folded.
@property (copy) NSArray *foldRoom;
// The fold or opening under way (foldMoving): whether one is, and whether it's the folded cat's list coming out or going
// back in (peek, asked for next, then the one moving), which turns back from where it is if asked the other way; which
// run it is, each of its steps going on only while it's still the one moving; the cat's square it folds into or opens
// out of; and whether the window keeps room beside the cat for chats meanwhile.
@property (assign) BOOL foldInMotion, askedPeek, foldPeek;
@property (assign) NSUInteger foldRun;
@property (assign) NSRect foldBox;
@property (assign) BOOL foldRoomOut;
// The room beside the cat asked for while the panel was folding, opening or changing its room, taken next.
@property (strong) NSDictionary *pendingRoom;
// Where the pointer last was from the folded glass's centre, as the page was told, and whether it was near enough.
@property (assign) BOOL catSeesPointer;
@property (assign) NSPoint lastCatPointer;
// The folded glass's breath (catBreathe:): how many sessions the page last said are working, whether it's breathing,
// and which run of breaths is the live one, so one that's been stopped doesn't take another breath.
@property (assign) NSInteger breathWorking;
@property (assign) BOOL breathing;
@property (assign) NSUInteger breathRun;
@end

// What the chats part does that the other parts call.
@interface PanelWindow (ChatsInside)
- (void)letRoomGo;
- (void)passClicks:(BOOL)through;
- (NSArray<NSValue *> *)roomParts:(id)list around:(NSRect)box;
@end
// What the flick part does that the other parts call.
@interface PanelWindow (FlickInside)
- (void)backAtOnce;
- (void)letGoAway;
- (NSEvent *)swiped:(NSEvent *)event;
@end
// What the fold part does that the other parts call.
@interface PanelWindow (FoldInside)
- (NSRect)catBoxIn:(NSRect)frame;
- (NSRect)foldedFrameFrom:(NSRect)open;
// The room the open panel will have, opened out of the cat's square `box` where it is now (RoomFor).
- (CGFloat)openRoomFrom:(NSRect)box;
- (NSRect)foldedGlassIn:(NSRect)frame;
- (void)placeAtOnce;
- (void)startBreathing;
- (void)takePending;
@end
// What the glass part does that the other parts call.
@interface PanelWindow (GlassInside)
- (NSRect)glassOnScreen;
- (NSRect)inWindow:(NSRect)onScreen;
- (void)moveGlassTo:(NSRect)glass clip:(NSRect)clip corner:(CGFloat)corner glassCorner:(CGFloat)glassCorner
               over:(NSTimeInterval)seconds easing:(Easing)easing then:(void (^)(void))then;
- (CGFloat)pageLeft;
- (CGFloat)pageTop;
- (void)placeStrips;
- (void)reshapeTo:(NSRect)target done:(void (^)(void))done;
- (CGFloat)roomFor:(NSRect)frame;
- (NSPoint)rootAround:(NSRect)box;
- (void)settle;
- (void)setWindowFrame:(NSRect)frame glass:(NSRect)glass clip:(NSRect)clip then:(void (^)(void))then;
- (void)setWindowFrame:(NSRect)frame showing:(NSRect)shown then:(void (^)(void))then;
- (void)tellGlass:(NSRect)glass over:(NSTimeInterval)duration;
@end
// What the hover part does that the other parts call.
@interface PanelWindow (HoverInside)
- (void)pollPointerEvery:(NSTimeInterval)every;
- (void)restPointer:(BOOL)resting;
- (void)tellCatPointerGone;
- (void)tellCatWay;
@end
// What the keyboard part does that the other parts call.
@interface PanelWindow (KeyboardInside)
- (Browser *)browserAt:(NSPoint)at;
- (void)clickedAt:(NSPoint)at;
- (void)dropKeyboard;
- (void)pointBrowsersAt:(NSPoint)screen moved:(BOOL)moved;
@end
// What the pane part does that the other parts call.
@interface PanelWindow (PaneInside)
- (void)tellStill;
@end
// What the turn part does that the other parts call.
@interface PanelWindow (TurnInside)
- (void)placeBack;
- (void)takePendingTurn;
- (void)turnBackAtOnce;
@end
