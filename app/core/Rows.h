// Rows: the rows the panel shows, read once a second and whenever one has something new to show: the sessions on their
// own queue, from the agents that run them and the hosts that keep them, then each module's part of every row, phase by
// phase on the main thread (RowPhase in Module.h); then they're sent to the page.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Core, Row;

@interface Rows : NSObject
- (instancetype)initWithCore:(Core *)core;
// Reads the rows and sends them once a second from now on.
- (void)start;
// Reads the rows and sends them, now, or once the read that's out is back.
- (void)refresh;
// Reads them without sending them (a print run's): `done` gets them, or nil.
- (void)read:(void (^)(NSArray<Row *> *rows))done;
// The rows as the last read had them, by session id: what the panel acts on when a row is pressed.
@property (readonly, copy) NSDictionary<NSString *, Row *> *byId;
@end
