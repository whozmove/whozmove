// PanelWindow (Pane): the reader beside the list: the panel growing for it and folding back.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "PanelWindow+Private.h"

@implementation PanelWindow (Pane)

#pragma mark The reader

// The reader opens beside the list, which stays where it was: the panel grows towards the side facing the screen's
// middle (edgeSide, where a row's room says it comes out; the side with more room before that's known), so a panel at
// the right grows leftwards with its list on the right, and one at the left the other way, and downwards
// from its top edge. It grows only as far as what the reader shows needs, and no further than the screen allows
// (16pt from its edges; a longer page scrolls). The page is told which side its list is on, and how wide the reader
// is, before the panel starts to grow, so what's in it is laid out once at that size and the growing only uncovers it.
- (void)expandReader:(CGFloat)width height:(CGFloat)height {
    // The reader opens from a row, and there are none to see while it's folded or turned over. Opening out of the cat,
    // it grows once the panel has opened, from where the list is then.
    if (self.folded || self.turned) return;
    if (self.reshaping && !self.expanded && self.holdsPage) {
        self.pendingReader = [NSValue valueWithSize:NSMakeSize(width, height)];
        return;
    }
    NSScreen *screen = self.panel.screen ?: NSScreen.mainScreen;
    NSRect visible = NSInsetRect(screen.visibleFrame, 16, 16);
    if (!self.expanded) {
        self.expanded = YES;
        self.listFrame = self.panel.frame;
        // The grown size mustn't be what the panel comes back at next launch.
        self.panel.frameAutosaveName = @"";
        // Towards the side the page was told (tellReaderSide), where a row's room says its chat comes out; the side
        // with more room only before the glass has worked one out.
        NSRect list = self.listFrame;
        self.listOnRight = self.edgeSide ? [self.edgeSide isEqual:@"left"]
                                         : NSMinX(list) - NSMinX(visible) >= NSMaxX(visible) - NSMaxX(list);
    }
    NSRect list = self.listFrame;
    CGFloat room = self.listOnRight ? NSMinX(list) - NSMinX(visible) : NSMaxX(visible) - NSMaxX(list);
    CGFloat readerWidth = floor(MAX(0, MIN(MIN(width, room), kReaderRoom)));
    CGFloat top = NSMaxY(list), tall = floor(MAX(NSHeight(list), MIN(height, top - NSMinY(visible))));
    NSRect frame = NSMakeRect(self.listOnRight ? NSMinX(list) - readerWidth : NSMinX(list), top - tall,
                              NSWidth(list) + readerWidth, tall);
    [self.page readerOpened:self.listOnRight ? @"right" : @"left" width:readerWidth];
    [self reshapeTo:frame done:nil];
}

// Back to where the list was (or was dragged to with the panel), at the height the list needs now (it may have changed
// while the reader was open), so nothing is resized again once the panel has folded.
- (void)collapse:(CGFloat)height {
    // Closed without having grown (it was asked to while the panel was folded or turned over): there's nothing to fold,
    // but the page still waits to hear that the reader has closed.
    if (!self.expanded) {
        self.pendingReader = nil;
        [self.page readerClosed];
        return;
    }
    __weak typeof(self) weakSelf = self;
    NSRect list = self.listFrame;
    if (height > 0) {
        CGFloat tall = floor(MAX(kHeaderHeight, MIN(height, [self roomFor:list])));
        list = NSMakeRect(NSMinX(list), NSMaxY(list) - tall, NSWidth(list), tall);
    }
    [self reshapeTo:list done:^{
        weakSelf.expanded = NO;
        // Saved first, where it has folded to: given its name back, the window also moves to what's saved under it,
        // which would otherwise be where it was before the reader opened, not where it was dragged since.
        [weakSelf.panel saveFrameUsingName:@"Whozmove"];
        weakSelf.panel.frameAutosaveName = @"Whozmove";
        [weakSelf placeStrips];
        [weakSelf.page readerClosed];
        [weakSelf resendRoom];
    }];
}

- (void)whenStill:(void (^)(void))then {
    if (!then) return;
    if (self.reshaping) [self.stillWaiters addObject:[then copy]];
    else then();
}

// The panel has stopped changing size, with no other size asked for: whoever waited for that goes now, unless what
// they did after the last change (folding back calls the page) has started the panel changing size again.
- (void)tellStill {
    if (self.reshaping || !self.stillWaiters.count) return;
    NSArray *waiting = [self.stillWaiters copy];
    [self.stillWaiters removeAllObjects];
    for (void (^then)(void) in waiting) then();
}
@end
