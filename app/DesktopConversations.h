// DesktopConversations: Claude Desktop's conversation files, and which one it shows now.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@interface DesktopConversations : NSObject
// Every conversation Claude Desktop keeps, running or not, as the fields the panel uses. Read on the session list's
// queue only.
- (NSArray<NSDictionary *> *)all;
// Catches up with Claude Desktop's log, which says when it shows another conversation.
- (void)readFocusLog;
// The conversation the log last said Claude shows (nil: none), and when, in ms since 1970.
@property (readonly, copy) NSString *loggedFocusId;
@property (readonly) double loggedFocusAt;
@end
