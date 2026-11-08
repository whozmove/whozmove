// PanelWindow (Chats): the room beside the folded cat for its chats, and the clicks it lets through.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "PanelWindow+Private.h"

@implementation PanelWindow (Chats)

NSRect CatRoomFrame(NSRect box, NSArray<NSValue *> *parts, CGFloat shadow) {
    NSRect frame = box;
    for (NSValue *part in parts) frame = NSUnionRect(frame, NSInsetRect(part.rectValue, -shadow, -shadow));
    return NSIntegralRect(frame);
}

// Folded, what comes out beside the cat (its chats, chats.js) has the room the page lays it out in: the window takes
// in, at once, everything it covers, the cat's square staying where it is, so the page stays put beneath it and nothing
// in it moves but what the page moves; and where the room ends up smaller, the window is made that size once it's done.
// The page is told once it's done, with which of its asks that was (catRoomTaken:). Asked again meanwhile, the newest is taken once this is done; asked
// while the panel folds or opens, once that is. While there's room, the window's frame isn't saved: the panel comes
// back next time as the cat alone. Those following the glass aren't told of it: the cat's circle stays where it was.
- (void)catRoom:(NSDictionary *)room {
    if (!self.folded) return;
    if (self.reshaping) {
        self.pendingRoom = room;
        return;
    }
    NSRect frame = self.panel.frame, box = [self catBoxIn:frame];
    NSArray<NSValue *> *parts = [self roomParts:room[@"parts"] around:box];
    BOOL held = parts.count > 0;
    NSRect target = held ? CatRoomFrame(box, parts, kRoomShadow) : box;
    // What takes clicks is as the page has it now, even where the window is already the size it needs.
    self.roomParts = held ? parts : nil;
    if (NSEqualRects(target, frame) && held == self.roomHeld) {
        [self.page catRoomTaken:room[@"ask"]];
        return;
    }
    if (held && !self.roomHeld) {
        [self.panel saveFrameUsingName:@"Whozmove"];
        self.panel.frameAutosaveName = @"";
        [self pollPointerEvery:kPointerEveryWatched];
    }
    CGFloat inset = (kFoldBox - kFoldGlass) / 2;
    NSRect circle = NSInsetRect(box, inset, inset), span = NSUnionRect(frame, target);
    self.reshaping = YES;
    self.roomChanging = YES;
    self.strip.hidden = YES;
    // The page stays where the cat's square has it throughout (rootAt), whatever the window takes in on the way.
    self.pageAt = [self rootAround:box];
    self.holdsPage = YES;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.clip.layer.cornerRadius = 0;
    [CATransaction commit];
    __weak typeof(self) weakSelf = self;
    void (^finish)(void) = ^{
        PanelWindow *me = weakSelf;
        me.roomChanging = NO;
        if (held) {
            me.roomHeld = YES;
            me.roomOffset = NSMakePoint(NSMinX(box) - NSMinX(target), NSMinY(box) - NSMinY(target));
        } else [me letRoomGo];  // which gives the slower polling back
        [me settle];
        [me.page catRoomTaken:room[@"ask"]];
        [me takePending];
    };
    void (^fit)(void) = ^{
        if (NSEqualRects(span, target)) finish();
        else [weakSelf setWindowFrame:target glass:circle clip:target then:finish];
    };
    if (NSEqualRects(span, frame)) fit();
    else [self setWindowFrame:span glass:circle clip:span then:fit];
}

// The parts of the room beside the cat the page names, each [x, y, width, height] in points from the glass's middle
// with y running down, on the screen round the cat's square `box`; anything else is left out.
- (NSArray<NSValue *> *)roomParts:(id)list around:(NSRect)box {
    NSPoint middle = NSMakePoint(NSMidX(box), NSMidY(box));
    NSMutableArray<NSValue *> *parts = [NSMutableArray array];
    for (id part in [list isKindOfClass:NSArray.class] ? list : @[]) {
        if (![part isKindOfClass:NSArray.class] || [part count] != 4) continue;
        BOOL numbers = YES;
        for (id each in part) numbers = numbers && [each isKindOfClass:NSNumber.class];
        if (!numbers) continue;
        CGFloat w = MAX(0, [part[2] doubleValue]), h = MAX(0, [part[3] doubleValue]);
        NSRect each = NSMakeRect(middle.x + [part[0] doubleValue], middle.y - [part[1] doubleValue] - h, w, h);
        if (!NSIsEmptyRect(each)) [parts addObject:[NSValue valueWithRect:each]];
    }
    return parts;
}

// No room beside the cat: the window is the cat's square (or opening out of it), and takes clicks again.
- (void)letRoomGo {
    BOOL had = self.roomHeld;
    self.roomHeld = NO;
    self.roomOffset = NSZeroPoint;
    self.roomParts = nil;
    [self passClicks:NO];
    if (had && !self.catSeesPointer) [self pollPointerEvery:kPointerEvery];
}

// Clicks go through the panel where nothing's drawn in the room beside the cat, or come to it again. Flicked off the
// screen, it takes none either way.
- (void)passClicks:(BOOL)through {
    if (through == self.clicksThrough) return;
    self.clicksThrough = through;
    self.panel.ignoresMouseEvents = through || self.parked;
}
@end
