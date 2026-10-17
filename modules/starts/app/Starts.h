// Starts: new conversations started from the panel's card, in Claude Desktop or a terminal. The folder's trust is
// checked first (and recorded once you've said yes on the card), the session is opened with your words, and it's
// watched for until it's listed, when the page's pending row becomes its row.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import "Host.h"

@class Core, Row;

@interface Starts : NSObject
// Starts open in the core's hosts: a terminal the panel types into, or the app that keeps conversations of its own.
- (instancetype)initWithCore:(Core *)core;
// The page's messages: whether Claude may work in a folder (checkFolder), the menu of folders a card can start in
// (startMenu), and a start (start).
- (void)checkFolder:(NSDictionary *)msg;
- (void)menu:(NSDictionary *)msg;
- (void)start:(NSDictionary *)msg;
// Each tick, with the rows: the starts still waiting are matched to the sessions they became, or given up on.
- (void)watch:(NSArray<Row *> *)rows;
// What the page needs to offer starts: the terminal one can open in (null when there's none).
- (NSDictionary *)options;
// A terminal start that brings its tab forward, with the session that tab will hold: its tab is the one you're on
// from then, as when a session is opened from the panel.
@property (copy) void (^onTabForward)(id<Host> terminal, NSString *sessionId);
@end
