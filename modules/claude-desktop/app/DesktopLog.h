// DesktopLog: Claude Desktop's log, which says when it shows another conversation, and when it starts one.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@interface DesktopLog : NSObject
// Catches up with the log, reading only what was written since; from any thread.
- (void)catchUp;
// The conversation the log last said Claude shows (nil: none), and when, in ms since 1970; when it last said it started
// a new conversation (to the second); and the last few it started, oldest first, as {id, folder, at}.
@property (readonly, copy) NSString *loggedFocusId;
@property (readonly) double loggedFocusAt, loggedStartAt;
@property (readonly, copy) NSArray<NSDictionary *> *loggedStarts;
@end
