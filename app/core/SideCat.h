// SideCat: Whozmove beside the panel. While the header has gone, pushed away by the row you're on as the list scrolls
// (panel/scripts/header.js), the cat's head peeks out from behind the panel's top corner, on the side facing the
// screen's middle: an EdgeIcon, as Spotify's token is at the bottom corner. It keeps the folded cat's moods, notices
// the pointer, slow-blinks when the pointer rests on it and flicks an ear when something new needs you. Pressed, it
// comes in front of the glass and the panel folds round it right where it is, the cat growing a little into the folded
// cat; dragged, it moves the panel.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "EdgeIcon.h"

@class Page;

@interface SideCat : EdgeIcon
- (instancetype)initWithPage:(Page *)page;
// How many sessions need you (the pawn's count): an ear flicked when more do.
- (void)needs:(NSInteger)count;
// The folded cat's pose, as the page has it (cat.js's catPose): asleep, watch (sessions working) or turn (looking at
// you, while something is your turn). It keeps the same mood, so it grows into the folded cat as that one sits.
- (void)takeMood:(NSString *)pose;
// The page's own folded cat has taken over where this one grew (catShown): it goes.
- (void)tookOver;
@end

// Where the folded glass's middle goes as the panel folds round it, from the list's top-left corner (`corner`, on the
// screen) in whole points with y running down, as the page's places are: where its head, raised and grown into the
// folded cat, keeps the middle its head has now, with its middle at `middle` on the screen, `shift` along and `lift`
// down from there, so it only grows.
NSPoint SideCatFoldAt(NSPoint middle, CGFloat shift, CGFloat lift, NSPoint corner);
