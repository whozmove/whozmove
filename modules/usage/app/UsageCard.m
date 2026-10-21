// UsageCard: the usage card behind the panel, in a small window of its own under the panel.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// It's a window the panel holds, as it holds Spotify's token, so it moves with the panel as it's dragged, and the
// panel's window doesn't grow for it. It's held over the panel, so the panel's own shadow doesn't fall on the card and
// its line shows in its own colour; what its page draws is cut to what's outside the panel (below its bottom edge, and
// in its rounded corners, where the open card shows behind them), so it never covers the glass, and its page draws
// the panel's shadow on the card itself. The page (page/card.html, card.js) draws the card and all that's on it, and moves
// it; this window follows the glass, tells the page where the pointer is (it's never key, so it gets no mouse moves),
// lets clicks through but on the part of the card that shows, and never takes the keyboard.
#import "UsageCard.h"
#import "Log.h"
#import <QuartzCore/QuartzCore.h>
#import <WebKit/WebKit.h>

// The open panel's width and its corners (kWidth and kCorner in app/core/PanelWindow.m).
static const CGFloat kPanelWidth = 340, kCorner = 24;
// The window: room beside the panel and below the card for the card's shadow, the most of the card that can show
// under the panel's edge (the strip at the session limit, with its wait), and up to the top of the panel's corners.
// Its page is laid out the same way: the panel's bottom-left corner kBeside in and kCorner down (#uc in usage.css).
static const CGFloat kBeside = 24, kReach = 120, kBelow = 36;

static BOOL Calm(void) { return NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion; }

// The card's page, and the folder it may read from: the bundle's page folder, as the panel's own tokens and helpers
// are there.
static NSURL *PageFolder(void) {
    return [NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"panel" isDirectory:YES];
}

static NSURL *CardPage(void) {
    return [PageFolder() URLByAppendingPathComponent:@"modules/usage/page/card.html"];
}

// A value as JSON, which is also JavaScript, so any text in it arrives as it was; nil if it can't be.
static NSString *JSONText(id value) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    return json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : nil;
}

// What of the window is outside the panel, the part of the card that can show: all of it below the glass's bottom
// edge (`edge` up from the window's bottom, the glass from `left` to `right`), and in the glass's rounded bottom
// corners; not beside the panel above its edge, nor under the glass.
static CGPathRef OutsidePanel(CGRect bounds, CGFloat left, CGFloat right, CGFloat edge) {
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathMoveToPoint(path, NULL, 0, 0);
    CGPathAddLineToPoint(path, NULL, CGRectGetMaxX(bounds), 0);
    CGPathAddLineToPoint(path, NULL, CGRectGetMaxX(bounds), edge);
    CGPathAddLineToPoint(path, NULL, right, edge);
    CGPathAddLineToPoint(path, NULL, right, edge + kCorner);
    CGPathAddArc(path, NULL, right - kCorner, edge + kCorner, kCorner, 0, -M_PI_2, true);
    CGPathAddLineToPoint(path, NULL, left + kCorner, edge);
    CGPathAddArc(path, NULL, left + kCorner, edge + kCorner, kCorner, -M_PI_2, -M_PI, true);
    CGPathAddLineToPoint(path, NULL, left, edge);
    CGPathAddLineToPoint(path, NULL, 0, edge);
    CGPathCloseSubpath(path);
    return path;
}

// The card's window: never key, so pressing it leaves the keyboard where it was.
@interface UsageCardWindow : NSPanel
@end

@implementation UsageCardWindow
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

// WebKit ignores the click that focuses a window; the card's never focused, so it takes every click.
@interface UsageCardView : WKWebView
@end

@implementation UsageCardView
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
@end

@interface UsageCard () <WKScriptMessageHandler, WKNavigationDelegate>
@property (strong) UsageCardWindow *panel;
@property (strong) UsageCardView *view;
@property (assign) BOOL ready;
// What its page last said: there's a card, this much of it shows under the panel's edge, this far in from each side.
@property (assign) BOOL wanted;
@property (assign) CGFloat extent, inset;
// Where the glass and the list are, and whether the glass is on its way somewhere (`moves` counts each such move, so a
// later one isn't taken for done when an earlier one would have been).
@property (assign) NSRect glass, list;
@property (assign) BOOL glassMoving;
@property (assign) NSUInteger moves;
@property (assign) BOOL showing;  // there, under the open panel
// Whether its page was last told the pointer is near (it's told once when it goes), and where.
@property (assign) BOOL pointerNear;
@property (assign) NSPoint toldPointer;
@property (assign) NSPoint lastPointer;
// Its window fading in or out: from `fadeFrom` to `fadeTo` over `fadeFor` seconds from `fadeSince`.
@property (assign) CGFloat fadeFrom, fadeTo;
@property (assign) CFTimeInterval fadeSince, fadeFor;
@property (strong) NSTimer *fadeTimer;
@end

@implementation UsageCard

- (instancetype)init {
    if (!(self = [super init])) return nil;
    NSRect frame = NSMakeRect(0, 0, kPanelWidth + 2 * kBeside, kBelow + kReach + kCorner);
    self.panel = [[UsageCardWindow alloc] initWithContentRect:frame
                                                    styleMask:NSWindowStyleMaskBorderless
                                                              | NSWindowStyleMaskNonactivatingPanel
                                                      backing:NSBackingStoreBuffered defer:NO];
    self.panel.level = NSFloatingWindowLevel;
    self.panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces
                                    | NSWindowCollectionBehaviorFullScreenAuxiliary;
    self.panel.hidesOnDeactivate = NO;
    self.panel.opaque = NO;
    self.panel.backgroundColor = NSColor.clearColor;
    self.panel.hasShadow = NO;
    self.panel.ignoresMouseEvents = YES;
    self.panel.alphaValue = 0;

    // The page, in a holder cut to what's outside the panel.
    NSView *holder = [[NSView alloc] initWithFrame:frame];
    holder.wantsLayer = YES;
    self.panel.contentView = holder;
    CAShapeLayer *outline = [CAShapeLayer layer];
    outline.frame = holder.bounds;
    outline.fillColor = NSColor.blackColor.CGColor;
    CGPathRef outside = OutsidePanel(holder.bounds, kBeside, kBeside + kPanelWidth, kBelow + kReach);
    outline.path = outside;
    CGPathRelease(outside);
    holder.layer.mask = outline;
    WKWebViewConfiguration *config = [WKWebViewConfiguration new];
    [config.userContentController addScriptMessageHandler:self name:@"panel"];
    self.view = [[UsageCardView alloc] initWithFrame:holder.bounds configuration:config];
    self.view.navigationDelegate = self;
    [self.view setValue:@NO forKey:@"drawsBackground"];
    self.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [holder addSubview:self.view];
    [self load];
    return self;
}

- (NSWindow *)window {
    return self.panel;
}

#pragma mark Its page

- (void)load {
    self.ready = NO;
    [self.view loadFileURL:CardPage() allowingReadAccessToURL:PageFolder()];
}

// The card only ever shows its own page: a link or a file dropped on it would otherwise replace it.
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action
    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = action.request.URL;
    BOOL page = url.isFileURL
                && [url.URLByStandardizingPath.path isEqualToString:CardPage().URLByStandardizingPath.path];
    if (!page) PanelLog(@"kept the usage card from loading a %@: page", url.scheme ?: @"?");
    decisionHandler(page ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}

// WebKit runs the page in a process of its own; if that one ends, the card loads again, and is told what's known.
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    PanelLog(@"the usage card's process ended; reloading it");
    self.wanted = NO;
    [self update];
    [self load];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    self.ready = YES;
    self.pointerNear = NO;
    if (self.onLoad) self.onLoad();
}

- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    if (!message.frameInfo.isMainFrame) return;
    NSDictionary *msg = message.body;
    if (![msg isKindOfClass:NSDictionary.class] || ![msg[@"type"] isKindOfClass:NSString.class] || !self.onMessage)
        return;
    self.onMessage(msg[@"type"], msg);
}

// The arguments spread from one JSON list: function(...[a, b]). Before the page has loaded, nothing's sent: it's told
// what's known once it has (onLoad).
- (void)call:(NSString *)function with:(NSArray *)arguments {
    NSString *json = JSONText(arguments ?: @[]);
    if (!self.ready || !json) return;
    [self.view evaluateJavaScript:[NSString stringWithFormat:@"%@(...%@)", function, json] completionHandler:nil];
}

- (void)took:(NSDictionary *)state {
    self.wanted = [state[@"shown"] boolValue];
    self.extent = MAX(0, MIN(kReach, [state[@"extent"] doubleValue]));
    self.inset = MAX(0, MIN(kPanelWidth / 2, [state[@"inset"] doubleValue]));
    [self update];
    [self clicksAt:self.lastPointer];
}

#pragma mark Whether it's there

- (void)setAway:(BOOL)away {
    _away = away;
    [self update];
}

- (void)glassAt:(NSRect)glass list:(NSRect)list duration:(NSTimeInterval)duration {
    self.glass = glass;
    self.list = list;
    self.glassMoving = duration > 0;
    NSUInteger move = ++self.moves;
    if (duration > 0) {
        // It waits for the glass to say where it ends up; in case it never does, it looks again by then.
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((duration + 0.1) * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UsageCard *card = weakSelf;
            if (card.moves != move || !card.glassMoving) return;
            card.glassMoving = NO;
            [card update];
        });
    }
    [self update];
    if (self.showing) [self place];
}

// It's there while its page has a card to show and the panel is open and still, on its list side, with no reader
// beside the list. As the glass changes shape, it goes at once; as the panel turns over, or its page stops showing one,
// it fades.
- (void)update {
    BOOL open = !self.away && !self.glassMoving && fabs(NSWidth(self.glass) - kPanelWidth) < 1
                && NSEqualRects(self.glass, self.list);
    if (!open) {
        if (self.showing) [self hide:self.away];
    } else if (self.wanted && !self.showing) {
        self.showing = YES;
        [self place];
        [self fadeTo:1 over:0.2];
        [self call:@"cardAppear" with:@[]];
    } else if (!self.wanted && self.showing) {
        [self hide:YES];
    }
}

- (void)hide:(BOOL)fade {
    self.showing = NO;
    self.panel.ignoresMouseEvents = YES;
    if (self.pointerNear) {
        self.pointerNear = NO;
        [self call:@"cardPointer" with:@[NSNull.null]];
    }
    [self fadeTo:0 over:fade ? 0.15 : 0];
}

// Its window under the glass's bottom edge, the panel's bottom-left corner kBeside in and kCorner down.
- (void)place {
    NSRect glass = self.glass;
    NSRect frame = NSMakeRect(NSMinX(glass) - kBeside, NSMinY(glass) - kReach - kBelow,
                              kPanelWidth + 2 * kBeside, kBelow + kReach + kCorner);
    if (!NSEqualRects(frame, self.panel.frame)) [self.panel setFrame:frame display:NO];
}

#pragma mark The pointer

- (void)pointerAt:(NSPoint)point {
    self.lastPointer = point;
    if (!self.showing) return;
    // Near the card, its page is told where the pointer is in it, its y running down, from the window's top-left.
    NSRect frame = self.panel.frame;
    if (NSPointInRect(point, NSInsetRect(frame, -2, -2))) {
        NSPoint at = NSMakePoint(round(point.x - NSMinX(frame)), round(NSMaxY(frame) - point.y));
        if (!self.pointerNear || !NSEqualPoints(at, self.toldPointer)) {
            self.pointerNear = YES;
            self.toldPointer = at;
            [self call:@"cardPointer" with:@[@{@"x": @(at.x), @"y": @(at.y)}]];
        }
    } else if (self.pointerNear) {
        self.pointerNear = NO;
        [self call:@"cardPointer" with:@[NSNull.null]];
    }
    [self clicksAt:point];
}

// Only the part of the card that shows under the panel takes clicks: the panel's own edge is the panel's, and beside
// the folded card, which is narrower than the panel, is whatever's behind.
- (void)clicksAt:(NSPoint)point {
    NSRect glass = self.glass;
    BOOL onCard = self.showing && point.x >= NSMinX(glass) + self.inset && point.x < NSMaxX(glass) - self.inset
                  && point.y < NSMinY(glass) && point.y >= NSMinY(glass) - self.extent;
    if (onCard == self.panel.ignoresMouseEvents) self.panel.ignoresMouseEvents = !onCard;
}

#pragma mark Fading

- (void)fadeTo:(CGFloat)alpha over:(NSTimeInterval)seconds {
    self.fadeFrom = self.panel.alphaValue;
    self.fadeTo = alpha;
    self.fadeSince = CACurrentMediaTime();
    self.fadeFor = Calm() ? 0 : seconds;
    if (self.fadeFor <= 0) {
        [self.fadeTimer invalidate];
        self.fadeTimer = nil;
        self.panel.alphaValue = alpha;
        return;
    }
    if (self.fadeTimer) return;
    __weak typeof(self) weakSelf = self;
    self.fadeTimer = [NSTimer timerWithTimeInterval:1.0 / 60 repeats:YES block:^(NSTimer *timer) {
        [weakSelf fadeStep];
    }];
    [NSRunLoop.currentRunLoop addTimer:self.fadeTimer forMode:NSRunLoopCommonModes];
}

- (void)fadeStep {
    CGFloat t = MAX(0, MIN(1, (CACurrentMediaTime() - self.fadeSince) / self.fadeFor));
    self.panel.alphaValue = self.fadeFrom + (self.fadeTo - self.fadeFrom) * t;
    if (t < 1) return;
    [self.fadeTimer invalidate];
    self.fadeTimer = nil;
}

@end
