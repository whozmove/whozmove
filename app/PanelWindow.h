// PanelWindow: the floating glass window, its drag strip, its size, and the pointer over it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>

@class Page;

@interface PanelWindow : NSObject
// Builds the window around the page's view, and starts following the pointer over it.
- (instancetype)initWithPage:(Page *)page;
// Shows it where it was last left, or at the top right of the screen the first time.
- (void)show;
// The menu bar's Show / Hide Panel and Reset Position.
- (void)toggle;
- (void)resetPosition;
// Tells a freshly loaded page how tall the panel can grow.
- (void)resendRoom;
// The height the page asks for, kept within that room.
- (void)fitHeight:(CGFloat)height;
// A text box in the page was clicked into (YES), or left (NO).
- (void)takeKeyboard:(BOOL)on;
// Gives the keyboard up if the panel has it, so it goes back to the app being opened. YES if it had it.
- (BOOL)releaseKeyboard;
// Opens a menu at a point in the page's coordinates.
- (void)popUpMenu:(NSMenu *)menu atPagePoint:(NSPoint)point;
@end
