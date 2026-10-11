// Sessions: running sessions and recent Claude Desktop conversations, as the rows the panel shows.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class DesktopConversations, Row;

@interface Sessions : NSObject
- (instancetype)initWithConversations:(DesktopConversations *)conversations;
// Every session to list, as a row with what the hook recorded, its checkout and any request waiting on it. The
// files are read on a queue of the list's own; `done` gets the rows on the main thread, or nil if something went
// wrong (it's logged).
- (void)read:(void (^)(NSArray<Row *> *rows))done;
@end
