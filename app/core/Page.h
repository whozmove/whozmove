// Page: loading panel/panel.html, and every message between it and the app.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@interface Page : NSObject
// The view the page shows in, for the panel's window to hold.
@property (readonly) WKWebView *view;
// Whether the page has loaded, so it can be called.
@property (readonly) BOOL ready;
// Called each time the page has loaded, and for each message it sends (`type` says which).
@property (copy) void (^onLoad)(void);
@property (copy) void (^onMessage)(NSString *type, NSDictionary *message);

- (void)load;

// One of the page's functions, called with these arguments, written as JavaScript (JSON is): the only way the app
// runs anything in the page.
- (void)call:(NSString *)function arguments:(NSString *)arguments;
// The same with the arguments as values, each made JSON, so any text in them arrives as it was: the way a module calls
// its own page functions. Nothing is called when one can't be made JSON.
- (void)call:(NSString *)function with:(NSArray *)arguments;
// The functions the page core offers the app, and those of the pieces not moved into a module yet.
- (void)update:(NSData *)rows;
- (void)setRoom:(CGFloat)room;
- (void)hoverAt:(NSPoint)point;
// The pointer is off the panel; `still` while it hasn't moved there yet (the panel's edge moved past it), and `held`
// while it's on what the panel holds over or under itself (Spotify's token, the usage card), where the folded cat's
// list on pointing stays out.
- (void)hoverEnd:(BOOL)still held:(BOOL)held;
// The panel no longer has the keyboard: another app took it, or the panel gave it back.
- (void)keyboardGone;
// The panel is turning over to its back (YES), or is back on its list side (NO): PanelWindow's turnOver:then:.
- (void)turned:(BOOL)on;
// Where the pointer is from the folded cat's glass, in points with y running down, while it's near; and that it has
// gone (cat.js).
- (void)catPointer:(NSPoint)offset;
- (void)catPointerGone;
// Which way what comes out of the folded cat goes (PanelWindow.h's CatWayFor): told as it changes, while nothing is
// out.
- (void)catWay:(BOOL)right up:(BOOL)up across:(CGFloat)across tall:(CGFloat)tall;
// The window has taken in the room the page asked for beside the folded cat, or given it back (catRoom), `ask` being
// which of the page's asks that was.
- (void)catRoomTaken:(id)ask;
// The folded cat pressed (YES), and the press let go (NO): its list doesn't come out on pointing meanwhile (peek.js).
- (void)catPressed:(BOOL)down;
// The folded cat is being dragged with something out beside it, which goes in meanwhile (YES); and it has stopped
// (NO).
- (void)catMoving:(BOOL)moving;
// That the glass is about to spread out from behind the folded cat as the panel opens: the cat shrinks into the name's
// o (cat.js). `then` runs once the page has started it (its next frame), or a moment later if it
// doesn't say, so the glass starts with it.
- (void)catGlass:(void (^)(void))then;
// Whozmove beside the panel was pressed while the header was gone: the panel folds round it where it is, `at` its
// place from the list's top-left corner, in whole points with y running down (cat.js).
- (void)foldFromSide:(NSPoint)at;
// The cat beside the panel has grown into the folded cat where the glass has closed round it: the page's own takes
// over there, and says so (catShown).
- (void)catLanded;
- (void)setGroupBy:(NSString *)mode;
- (void)toggleCollapsed;
// Why a /compact from the Compact card didn't go in, and the words of a button past it (WayPast in Send.h), or nil.
- (void)compactNote:(NSString *)sid text:(NSString *)text way:(NSString *)way;
- (void)setRunningBuild:(NSDictionary *)running;
- (void)setSwitches:(NSDictionary *)switches;
- (void)readerOpened:(NSString *)side width:(CGFloat)width;
- (void)readerClosed;
// Calls back once the page has been laid out and drawn as it is now (after a change of size, say); at the latest
// after a quarter of a second.
- (void)afterPaint:(void (^)(void))done;
- (void)showWriting:(NSString *)sid id:(NSString *)writingId read:(NSDictionary *)read;
- (void)stepNote:(NSString *)sid text:(NSString *)text;
// A quiet note says how something went that worked; the other kind, why something couldn't happen.
- (void)stepNote:(NSString *)sid text:(NSString *)text quiet:(BOOL)quiet;
// Why a step couldn't go in, with the words of a button past that (WayPast in Send.h), which stays a while longer.
- (void)stepNote:(NSString *)sid text:(NSString *)text way:(NSString *)way;
@end
