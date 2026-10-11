// Page: loading panel/panel.html, and every message between it and the app.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Page.h"
#import "Log.h"

// WKWebView ignores the click that focuses a window; the panel is rarely focused, so take every click.
@interface ClickThroughWebView : WKWebView
@end

@implementation ClickThroughWebView
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
@end

@interface Page () <WKScriptMessageHandler, WKNavigationDelegate>
@property (strong) WKWebView *view;
@property (assign) BOOL ready;
@end

@implementation Page

// The page and everything it loads live in the bundle's panel folder, the one the page may read from.
static NSURL *PageURL(void) {
    return [NSBundle.mainBundle URLForResource:@"panel" withExtension:@"html" subdirectory:@"panel"];
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    WKWebViewConfiguration *config = [WKWebViewConfiguration new];
    [config.userContentController addScriptMessageHandler:self name:@"panel"];
    self.view = [[ClickThroughWebView alloc] initWithFrame:NSZeroRect configuration:config];
    self.view.navigationDelegate = self;
    [self.view setValue:@NO forKey:@"drawsBackground"];
    return self;
}

- (void)load {
    self.ready = NO;
    [self.view loadFileURL:PageURL() allowingReadAccessToURL:PageURL().URLByDeletingLastPathComponent];
}

// The panel only ever shows panel.html. A link or a file dropped on it would otherwise replace the page, and
// whatever loaded would keep the bridge that answers permission requests.
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action
    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = action.request.URL;
    BOOL page = url.isFileURL
                && [url.URLByStandardizingPath.path isEqualToString:PageURL().URLByStandardizingPath.path];
    if (!page) PanelLog(@"kept the panel from loading a %@: page", url.scheme ?: @"?");
    decisionHandler(page ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}

// WebKit runs the page in a process of its own; if that one ends (a crash, memory pressure), the panel
// would stay blank until relaunched. Load it again instead.
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    PanelLog(@"the page's process ended; reloading it");
    [self load];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    self.ready = YES;
    if (self.onLoad) self.onLoad();
}

- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    NSDictionary *msg = message.body;
    if (![msg isKindOfClass:NSDictionary.class] || ![msg[@"type"] isKindOfClass:NSString.class] || !self.onMessage)
        return;
    self.onMessage(msg[@"type"], msg);
}

#pragma mark Calls into the page

// Each is one of the functions the page offers the app (see panel/scripts/panel.js), and this is the only place the
// app runs anything there.
- (void)call:(NSString *)function arguments:(NSString *)arguments {
    [self.view evaluateJavaScript:[NSString stringWithFormat:@"%@(%@)", function, arguments ?: @""]
                completionHandler:nil];
}

// A value as JSON, which is also JavaScript, so any text in it arrives as it was; nil if it can't be.
static NSString *JSONText(id value) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    return json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : nil;
}

- (void)update:(NSData *)rows {
    NSString *json = [[NSString alloc] initWithData:rows encoding:NSUTF8StringEncoding];
    [self call:@"update"
     arguments:[NSString stringWithFormat:@"%@, %.0f", json, NSDate.date.timeIntervalSince1970 * 1000]];
}

- (void)setRoom:(CGFloat)room {
    [self call:@"setRoom" arguments:[NSString stringWithFormat:@"%.0f", room]];
}

- (void)hoverAt:(NSPoint)point {
    [self call:@"hoverAt" arguments:[NSString stringWithFormat:@"%.0f, %.0f", point.x, point.y]];
}

- (void)hoverEnd {
    [self call:@"hoverEnd" arguments:nil];
}

- (void)setGroupBy:(NSString *)mode {  // one of three fixed words (MenuBar), so it can go in as it is
    [self call:@"setGroupBy" arguments:[NSString stringWithFormat:@"'%@'", mode]];
}

- (void)toggleCollapsed {
    [self call:@"toggleCollapsed" arguments:nil];
}

- (void)askSwitch:(NSDictionary *)question {
    NSString *json = JSONText(question);
    if (json) [self call:@"askSwitch" arguments:json];
}

- (void)compactNote:(NSString *)sid text:(NSString *)text {
    NSString *json = JSONText(@[sid ?: @"", text ?: @""]);
    if (json) [self call:@"compactNote" arguments:[@"..." stringByAppendingString:json]];
}

@end
