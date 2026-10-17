// Focus: the session you're on, marked in the list: the conversation Claude Desktop shows, or the session in the tab a
// terminal shows, whichever of the two apps you were in last; and opening a session from its row, which makes it the
// one you're on.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Host.h"

@class Core, Row;

@interface Focus : NSObject
- (instancetype)initWithCore:(Core *)core;
// Follows which app comes to the front, from now on.
- (void)start;
// Marks the session you're on among the rows, once they're whole (Rows).
- (void)mark:(NSArray<Row *> *)rows;
// Opens the session of a row the page sent back, when it was pressed (the page's "open").
- (void)open:(NSDictionary *)message;
// A terminal has just brought forward a tab with a session in it (a new conversation started there): it's the one
// you're on, and an answer about the tab before it, already on its way, isn't taken.
- (void)tabCameForward:(id<Host>)host session:(NSString *)sessionId;
@end
