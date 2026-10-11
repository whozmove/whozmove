// Page: loading panel/panel.html, and every message between it and the app.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@interface Page : NSObject
// The view the page shows in, for the panel's window to hold.
@property (readonly) WKWebView *view;
// Whether the page has loaded, so it can be called.
@property (readonly) BOOL ready;
// Called each time the page has loaded, and for each message it sends (`type` says which).
@property (copy) void (^onLoad)(void);
@property (copy) void (^onMessage)(NSString *type, NSDictionary *message);

- (void)load;

// The functions the page offers the app, under the page's own names.
- (void)update:(NSData *)rows;
- (void)setRoom:(CGFloat)room;
- (void)hoverAt:(NSPoint)point;
- (void)hoverEnd;
- (void)setGroupBy:(NSString *)mode;
- (void)toggleCollapsed;
- (void)askSwitch:(NSDictionary *)question;
- (void)compactNote:(NSString *)sid text:(NSString *)text;
@end
