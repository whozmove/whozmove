// MenuBar: the pawn in the menu bar, its count, and the grouping menu.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>

@class PanelWindow, Page;

@interface MenuBar : NSObject
// Puts the pawn in the menu bar, with a menu for the window and the page's grouping.
- (instancetype)initWithWindow:(PanelWindow *)window page:(Page *)page;
// The count beside the pawn, as the page reports it; none shows the pawn alone.
- (void)showCount:(NSInteger)count;
// Tells a freshly loaded page the grouping last chosen (Status until one is).
- (void)applySavedGrouping;
@end
