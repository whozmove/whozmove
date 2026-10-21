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
// The menu bar's Show / Hide Panel and Reset Position.
- (void)toggle;
// Whether the panel is on screen (not hidden from the menu bar).
@property (readonly) BOOL shown;
// Brings the panel back if it was hidden, and leaves it as it is if it's showing (⌃⌥N).
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
// Gives the keyboard up if the panel has it, so it goes back to the app being opened. YES if it had it.
- (BOOL)releaseKeyboard;
// Opens a menu at a point in the page's coordinates.
- (void)popUpMenu:(NSMenu *)menu atPagePoint:(NSPoint)point;
// A small window held under the panel, moving with it (Spotify's token).
- (void)attachBelow:(NSWindow *)window;
// The same, held over the panel instead, so the panel's shadow doesn't fall on it: for a window that draws nothing
// where the panel is (the usage card).
- (void)attachAbove:(NSWindow *)window;
// Each told whenever the glass moves or changes size: where it is on the screen, where the list is (the reader grows
// beside it), the screen's room, and how long it takes to get there (0 for at once).
- (void)followGlass:(void (^)(NSRect glass, NSRect list, NSRect screen, NSTimeInterval duration))observer;
// Each told the pointer's place on the screen, wherever it is, as often as it's polled.
- (void)followPointer:(void (^)(NSPoint screen))observer;
@end
