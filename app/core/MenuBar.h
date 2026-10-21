// MenuBar: the pawn in the menu bar, its count, and its menu: the look, the grouping, Working on Whozmove, and the
// modules' items, each in its section; and the panel's switches, which Git's page on the panel's back sets.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>

@class PanelWindow, Page, MenuEntry;

@interface MenuBar : NSObject
// Puts the pawn in the menu bar, with a menu for the window, the page's grouping and its switches.
- (instancetype)initWithWindow:(PanelWindow *)window page:(Page *)page;
// The modules' items, each into its section of the menu, in its order there (contracts/Module.h).
- (void)addEntries:(NSArray<MenuEntry *> *)entries;
// The count beside the pawn, as the page reports it; none shows the pawn alone.
- (void)showCount:(NSInteger)count;
// Tells a freshly loaded page the grouping last chosen (Status until one is).
- (void)applySavedGrouping;
// Tells a freshly loaded page the switches last set: Show Next Steps, Show Deploy, Show Build in Header.
- (void)applySavedSwitches;
// Whether Show Next Steps is on (the rows' next steps), and Show Deploy (its Deploy step):
// set from Git's page on the panel's back, each saved, and the page told.
@property (nonatomic) BOOL showsNextSteps;
@property (nonatomic) BOOL showsDeploy;
@end
