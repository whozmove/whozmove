// BackPage: the panel's back, in a web view of its own on the back of the glass.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// It's a second web view in the panel's window, over the page's, as wide as the list and as tall as the panel; the
// window shows it, and passes it clicks, only while the panel is turned over. The panel's window is never the one you
// type in, so the page gets no mouse moves: the module tells it where the pointer is.
#import "BackPage.h"
#import "Log.h"
#import <WebKit/WebKit.h>

// The back's page, and the folder it may read from: the bundle's page folder, as the panel's own tokens, styles and
// helpers are there.
static NSURL *PageFolder(void) {
    return [NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"panel" isDirectory:YES];
}

static NSURL *BackFile(void) {
    return [PageFolder() URLByAppendingPathComponent:@"modules/apps/page/back.html"];
}

// A value as JSON, which is also JavaScript, so any text in it arrives as it was; nil if it can't be.
static NSString *JSONText(id value) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    return json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : nil;
}

// WebKit ignores the click that focuses a window; the panel's never focused, so the back takes every click.
@interface BackView : WKWebView
@end

@implementation BackView
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
@end

@interface BackPage () <WKScriptMessageHandler, WKNavigationDelegate>
@property (strong) BackView *web;
@property (assign) BOOL ready;
@end

@implementation BackPage

- (instancetype)init {
    if (!(self = [super init])) return nil;
    WKWebViewConfiguration *config = [WKWebViewConfiguration new];
    [config.userContentController addScriptMessageHandler:self name:@"panel"];
    self.web = [[BackView alloc] initWithFrame:NSMakeRect(0, 0, 340, 200) configuration:config];
    self.web.navigationDelegate = self;
    // The glass and its tint show through it, as through the panel's page.
    [self.web setValue:@NO forKey:@"drawsBackground"];
    return self;
}

- (NSView *)view {
    return self.web;
}

- (void)load {
    self.ready = NO;
    [self.web loadFileURL:BackFile() allowingReadAccessToURL:PageFolder()];
}

// The back only ever shows its own page: a link or a file dropped on it would otherwise replace it.
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action
    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = action.request.URL;
    BOOL page = url.isFileURL
                && [url.URLByStandardizingPath.path isEqualToString:BackFile().URLByStandardizingPath.path];
    if (!page) PanelLog(@"kept the panel's back from loading a %@: page", url.scheme ?: @"?");
    decisionHandler(page ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}

// WebKit runs the page in a process of its own; if that one ends, the back loads again, and is told what's known.
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    PanelLog(@"the panel's back's process ended; reloading it");
    [self load];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    self.ready = YES;
    if (self.onLoad) self.onLoad();
}

- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    if (!message.frameInfo.isMainFrame) return;
    NSDictionary *msg = message.body;
    if (![msg isKindOfClass:NSDictionary.class] || ![msg[@"type"] isKindOfClass:NSString.class] || !self.onMessage)
        return;
    self.onMessage(msg[@"type"], msg);
}

// The arguments spread from one JSON list: function(...[a, b]).
- (void)call:(NSString *)function with:(NSArray *)arguments {
    NSString *json = JSONText(arguments ?: @[]);
    if (!self.ready || !json) return;
    [self.web evaluateJavaScript:[NSString stringWithFormat:@"%@(...%@)", function, json] completionHandler:nil];
}

@end
