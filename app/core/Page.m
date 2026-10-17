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
// whatever loaded would keep the bridge that answers permission requests. The one frame inside it is the reader's,
// showing a prototype a session wrote from its text (srcdoc), and it never goes anywhere else.
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action
    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = action.request.URL;
    if (action.targetFrame && !action.targetFrame.isMainFrame) {
        BOOL inline_ = [url.absoluteString isEqualToString:@"about:srcdoc"]
                       || [url.absoluteString isEqualToString:@"about:blank"];
        if (!inline_) PanelLog(@"kept a prototype from loading a %@: page", url.scheme ?: @"?");
        decisionHandler(inline_ ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
        return;
    }
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

// Only the panel's own page speaks for you. A prototype in the reader runs its own scripts, and none of them may
// answer a request or press anything.
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    if (!message.frameInfo.isMainFrame) return;
    NSDictionary *msg = message.body;
    if (![msg isKindOfClass:NSDictionary.class] || ![msg[@"type"] isKindOfClass:NSString.class] || !self.onMessage)
        return;
    self.onMessage(msg[@"type"], msg);
}

#pragma mark Calls into the page

// Each is one of the functions the page offers the app (panel/scripts/panel.js, and modules' own), and this is the
// only place the app runs anything there.
- (void)call:(NSString *)function arguments:(NSString *)arguments {
    [self.view evaluateJavaScript:[NSString stringWithFormat:@"%@(%@)", function, arguments ?: @""]
                completionHandler:nil];
}

// A value as JSON, which is also JavaScript, so any text in it arrives as it was; nil if it can't be.
static NSString *JSONText(id value) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    return json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : nil;
}

// The arguments spread from one JSON list: function(...[a, b]).
- (void)call:(NSString *)function with:(NSArray *)arguments {
    NSString *json = JSONText(arguments ?: @[]);
    if (json) [self call:function arguments:[@"..." stringByAppendingString:json]];
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

- (void)setRunningBuild:(NSDictionary *)running {
    NSString *json = running ? JSONText(running) : @"null";
    if (json) [self call:@"setRunningBuild" arguments:json];
}

- (void)setSwitches:(NSDictionary *)switches {
    NSString *json = JSONText(switches);
    if (json) [self call:@"setSwitches" arguments:json];
}

- (void)readerOpened:(NSString *)side width:(CGFloat)width {  // side is "left" or "right" (PanelWindow)
    [self call:@"readerOpened" arguments:[NSString stringWithFormat:@"'%@', %.0f", side, width]];
}

- (void)readerClosed {
    [self call:@"readerClosed" arguments:nil];
}

// Two animation frames: the first runs before the page's next drawing, the second once it has drawn.
- (void)afterPaint:(void (^)(void))done {
    __block BOOL called = NO;
    void (^once)(void) = ^{
        if (called) return;
        called = YES;
        done();
    };
    [self.view callAsyncJavaScript:@"await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)))"
                         arguments:nil inFrame:nil inContentWorld:WKContentWorld.pageWorld
                 completionHandler:^(id result, NSError *error) { once(); }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), once);
}

- (void)showWriting:(NSString *)sid id:(NSString *)writingId read:(NSDictionary *)read {
    NSString *json = JSONText(@[sid ?: @"", writingId ?: @"", read ?: @{}]);
    if (json) [self call:@"showWriting" arguments:[@"..." stringByAppendingString:json]];
}

- (void)stepNote:(NSString *)sid text:(NSString *)text {
    [self stepNote:sid text:text quiet:NO];
}

- (void)stepNote:(NSString *)sid text:(NSString *)text quiet:(BOOL)quiet {
    NSString *json = JSONText(@[sid ?: @"", text ?: @"", @(quiet)]);
    if (json) [self call:@"stepNote" arguments:[@"..." stringByAppendingString:json]];
}

@end
