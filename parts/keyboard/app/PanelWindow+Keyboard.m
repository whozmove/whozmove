// PanelWindow (Keyboard): the keyboard: when the panel takes it, and gives it back.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "PanelWindow+Private.h"

@implementation HandOffPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

// Whether a view is in sight in a window: in it, not hidden, and with some of it showing.
static BOOL Shows(NSView *view, NSWindow *window) {
    return view && view.window == window && !view.isHiddenOrHasHiddenAncestor && !NSIsEmptyRect(view.visibleRect);
}

// WebKit hears of the pointer through its view's own tracking area, never the view's mouseMoved:, so a move passed in
// goes to that area's owner, as macOS would send it there.
static void PassPointer(NSView *view, NSEventType type, NSPoint at) {
    NSWindow *window = view.window;
    if (!window) return;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    NSEvent *event = type == NSEventTypeMouseMoved
        ? [NSEvent mouseEventWithType:type location:at modifierFlags:NSEvent.modifierFlags timestamp:now
                         windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:0 pressure:0]
        : [NSEvent enterExitEventWithType:type location:at modifierFlags:NSEvent.modifierFlags timestamp:now
                             windowNumber:window.windowNumber context:nil eventNumber:0 trackingNumber:0 userData:NULL];
    for (NSTrackingArea *area in view.trackingAreas) {
        id owner = area.owner;
        if (owner == view || !(area.options & NSTrackingMouseMoved)) continue;
        if (type == NSEventTypeMouseMoved && [owner respondsToSelector:@selector(mouseMoved:)])
            [owner mouseMoved:event];
        if (type == NSEventTypeMouseExited && [owner respondsToSelector:@selector(mouseExited:)])
            [owner mouseExited:event];
        return;
    }
}

@implementation PanelWindow (Keyboard)

#pragma mark Keyboard

// The page's box takes the keyboard from a site in the panel, but its letting go doesn't take it from one: pressed from
// the box into a site, the box lets go a moment after the site took it.
- (void)takeKeyboard:(BOOL)on {
    self.pageKeys = on;
    if (!on && self.browserKeys) return;
    if (on && self.browserKeys) {
        self.browserKeys = NO;
        [self.panel makeFirstResponder:self.page.view];
    }
    [self wantKeyboard:on];
}

- (void)wantKeyboard:(BOOL)on {
    if (on && self.panel.wantsKeyboard) return;
    self.panel.wantsKeyboard = on;
    if (on) [self.panel makeKeyWindow];
    else [self giveBackKeyboard];
}

- (BOOL)releaseKeyboard {
    self.browserKeys = self.pageKeys = NO;
    if (!self.panel.isKeyWindow) return NO;
    self.panel.wantsKeyboard = NO;
    [self giveBackKeyboard];
    return YES;
}

// The keyboard goes back to the app it came from, the one in front. Asking that app to come forward does nothing while
// it's in front already, and the panel would keep the keyboard; so the panel hands it to a window of its own that can't
// be seen, which goes at once, and macOS gives the keyboard back to the app in front, as when any panel that has it
// closes.
- (void)giveBackKeyboard {
    if (!self.panel.isKeyWindow) return;
    [self.handOff setFrameOrigin:self.panel.frame.origin];
    [self.handOff orderWindow:NSWindowBelow relativeTo:self.panel.windowNumber];
    [self.handOff makeKeyWindow];
    [self.handOff orderOut:nil];
}

- (BOOL)keptKeyboard {
    return self.panel.isKeyWindow && !self.panel.wantsKeyboard;
}

// Whoever in the panel has the keyboard gives it back: the panel folds or turns over.
- (void)dropKeyboard {
    self.browserKeys = NO;
    [self takeKeyboard:NO];
}

// The site shown at a point in the window, if one is, and nothing covers it there.
- (Browser *)browserAt:(NSPoint)at {
    NSArray<Browser *> *browsers = [Browser inWindow:self.panel];
    if (!browsers.count) return nil;
    NSView *root = self.panel.contentView;
    NSView *hit = [root hitTest:[root.superview ?: root convertPoint:at fromView:nil]];
    for (Browser *browser in browsers)
        if (hit && [hit isDescendantOf:browser.view] && !browser.view.isHiddenOrHasHiddenAncestor) return browser;
    return nil;
}

// A click into a site takes the keyboard for it, as typing there is what it's for. One elsewhere in the panel gives it
// back to the app it came from, unless it's into one of the page's own boxes, which asks for it (takeKeyboard:) as the
// click lands.
- (void)clickedAt:(NSPoint)at {
    Browser *into = [self browserAt:at];
    if (into) {
        self.browserKeys = YES;
        self.keyboardBrowser = into;
        [self wantKeyboard:YES];
        [self.panel makeFirstResponder:into.view];
        return;
    }
    if (!self.browserKeys) return;
    self.browserKeys = NO;
    [self.panel makeFirstResponder:self.page.view];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!weakSelf.browserKeys && !weakSelf.pageKeys) [weakSelf wantKeyboard:NO];
    });
}

// WebKit follows the pointer only in the window you type in, so a site gets it only while the panel has the keyboard;
// and macOS sends a window that doesn't make its app active none of the pointer's moves, so they're passed in from
// here. Once the site that was given the keyboard has gone (closed, or out of sight), the keyboard goes back; and a
// site the pointer leaves is told so.
- (void)pointBrowsersAt:(NSPoint)screen moved:(BOOL)moved {
    if (self.browserKeys && !Shows(self.keyboardBrowser.view, self.panel)) [self dropKeyboard];
    NSPoint at = [self.panel convertPointFromScreen:screen];
    Browser *on = self.panel.isVisible && self.panel.isKeyWindow ? [self browserAt:at] : nil;
    Browser *was = self.pointedBrowser;
    if (was && was != on) PassPointer(was.view, NSEventTypeMouseExited, at);
    if (on && (moved || on != was)) PassPointer(on.view, NSEventTypeMouseMoved, at);
    self.pointedBrowser = on;
}

- (void)popUpMenu:(NSMenu *)menu atPagePoint:(NSPoint)point {
    NSView *view = self.panel.contentView;  // not flipped; the page's y runs down from its top, above the list's
    NSPoint at = NSMakePoint(point.x + [self pageLeft] - NSMinX(self.panel.frame),
                             [self pageTop] - NSMinY(self.panel.frame) - point.y);
    self.usedAt = NSDate.timeIntervalSinceReferenceDate;
    [menu popUpMenuPositioningItem:nil atLocation:at inView:view];
    self.usedAt = NSDate.timeIntervalSinceReferenceDate;  // it was open till now
    // The pointer isn't looked at while the menu is up: it's taken to be where the menu closed, so it hasn't left the
    // panel until it moves on from there (pollPointer).
    self.lastScreen = NSEvent.mouseLocation;
}
@end
