// Focus: the session you're on, marked in the list: the conversation Claude Desktop shows, or the session in the tab a
// terminal shows, whichever of those apps you were in last; and opening a session from its row, which makes it the one
// you're on, an ended terminal session too, opened again in a new tab.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Host.h"

@class Core, Row;

// Whether a window of the app with process `pid` is on top, among the windows on the screen, front first, as
// CGWindowListCopyWindowInfo lists them: no other app's normal window (layer 0) is above its first one, wherever on
// the screen. Its own windows count at any level, and only windows that can be seen count; Whozmove's own (process
// `own`) never do.
BOOL FrontWindowOnTop(NSArray<NSDictionary *> *windows, pid_t pid, pid_t own);

// Whether you're at the Mac: its screen awake and unlocked, and the keyboard or the mouse used in the last 5 minutes.
BOOL AtTheMac(void);

@interface Focus : NSObject
- (instancetype)initWithCore:(Core *)core;
// Follows which app comes to the front, from now on.
- (void)start;
// Marks the session you're on among the rows, once they're whole (Rows), and when you last looked at each.
- (void)mark:(NSArray<Row *> *)rows;
// Opens the session of a row the page sent back, when it was pressed (the page's "open"): a terminal session that has
// ended, in a new tab of the terminal it ran in. With `carryOn` in it (its row's own press, a Resume), a module's words
// for it go in as its first message (ReopenWords); without it (a press only to look, Take Me There), none.
- (void)open:(NSDictionary *)message;
// Once the rows are whole (Rows): each ended terminal session's row says which terminal a press opens it again in
// (opensIn), one opened again from here is no longer waited for once it's running, and a row pressed as its session
// was ending opens it again once it's grey.
- (void)nameReopens:(NSArray<Row *> *)rows;
// The session in the tab the terminal in front shows, as it last said, while that session is listed; nil when the app
// in front is any other (Claude Desktop's conversation in front is marked as the rows are read).
- (NSString *)terminalSessionInFront;
// A terminal has just brought forward a tab with a session in it (a new conversation started there): it's the one
// you're on, and an answer about the tab before it, already on its way, isn't taken.
- (void)tabCameForward:(id<Host>)host session:(NSString *)sessionId;
@end
