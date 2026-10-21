// BackPage: the panel's back, a page of its own (page/back.html) in a web view of its own, which the panel's window
// holds on the back of its glass (PanelWindow's holdBack:), with a bridge of its own in the same shape as the panel's
// page's.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>

@interface BackPage : NSObject
// The view the page shows in, for the panel's window to hold.
@property (readonly) NSView *view;
// Called each time the page has loaded, and for each message it sends (`type` says which).
@property (copy) void (^onLoad)(void);
@property (copy) void (^onMessage)(NSString *type, NSDictionary *message);
- (void)load;
// One of the page's functions, with these arguments, each made JSON; nothing's called before the page has loaded.
- (void)call:(NSString *)function with:(NSArray *)arguments;
@end
