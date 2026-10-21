// Focus: the session you're on, marked in the list: the conversation Claude Desktop shows, or the session in the tab a
// terminal shows, whichever of those apps you were in last; and opening a session from its row, which makes it the one
// you're on, an ended terminal session too, opened again in a new tab.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Host.h"

@class Core, Row;

@interface Focus : NSObject
- (instancetype)initWithCore:(Core *)core;
// Follows which app comes to the front, from now on.
- (void)start;
// Marks the session you're on among the rows, once they're whole (Rows), and when you last looked at each.
- (void)mark:(NSArray<Row *> *)rows;
// Opens the session of a row the page sent back, when it was pressed (the page's "open"): a terminal session that has
// ended, in a new tab of the terminal it ran in.
- (void)open:(NSDictionary *)message;
// Once the rows are whole (Rows): each ended terminal session's row says which terminal a press opens it again in
// (opensIn), one opened again from here is no longer waited for once it's running, and a row pressed as its session
// was ending opens it again once it's grey.
- (void)nameReopens:(NSArray<Row *> *)rows;
// A terminal has just brought forward a tab with a session in it (a new conversation started there): it's the one
// you're on, and an answer about the tab before it, already on its way, isn't taken.
- (void)tabCameForward:(id<Host>)host session:(NSString *)sessionId;
@end
