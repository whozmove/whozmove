// UsageCard: the usage card behind the panel, as wide as it: a small window of its own under the panel, showing a page
// of its own (page/card.html and card.js), which draws the card folded, slid out and open, and moves it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>

@interface UsageCard : NSObject
// Its own small window, which the panel holds over itself (PanelWindow attachAbove:), drawing only outside it.
@property (readonly) NSWindow *window;
// Its page has loaded; it's told what's known then (onLoad), and again if it ever loads again.
@property (readonly) BOOL ready;
@property (copy) void (^onLoad)(void);
// A message from its page ({type, …}), for the module that answers that type.
@property (copy) void (^onMessage)(NSString *type, NSDictionary *message);
// Calls one of the functions its page offers the app, with these arguments.
- (void)call:(NSString *)function with:(NSArray *)arguments;
// What its page says ({shown, extent, inset}): whether there's a card, how much of it shows under the panel's bottom
// edge, and how far in from each of the panel's sides it is, in points, which is where it takes clicks.
- (void)took:(NSDictionary *)state;
// Where the panel's glass is on the screen and where its list is (the reader grows beside it), got to over `duration`
// seconds, or at once. The card is there only under the open panel at rest: not while the glass moves, while the
// reader is open beside the list, or while the panel is folded into the cat.
- (void)glassAt:(NSRect)glass list:(NSRect)list duration:(NSTimeInterval)duration;
// While the panel is turned over to its back, the card stays out of sight: it fades as the panel starts turning, and
// comes back once it's on its list side again.
@property (nonatomic) BOOL away;
// The pointer, wherever it is: its page is told where it is while it's near the card (it slides out, or shows what
// the pointer is on), and the window takes clicks only while it's on the part of the card that shows.
- (void)pointerAt:(NSPoint)point;
@end
