// Menus: the small parts the pawn's and the island's menus are made of.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>

// Whether one of the pawn menu's switches is on, as you last left it (each is kept in the app's defaults by its key).
BOOL SwitchedOn(NSString *key);
// That switch turned over: on if it was off, off if it was on.
void FlipSwitch(NSString *key);
// A line of a menu that only says something: it can't be chosen.
void SayInMenu(NSMenu *menu, NSString *text);
