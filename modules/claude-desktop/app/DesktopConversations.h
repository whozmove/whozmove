// DesktopConversations: Claude Desktop's conversation files.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@interface DesktopConversations : NSObject
// Every conversation Claude Desktop keeps, running or not, as the fields the panel uses. Read on the session list's
// queue only.
- (NSArray<NSDictionary *> *)all;
@end
