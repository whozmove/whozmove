// Menus: a switch's state, and a line that only says something.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Menus.h"

BOOL SwitchedOn(NSString *key) {
    return [NSUserDefaults.standardUserDefaults boolForKey:key];
}

void FlipSwitch(NSString *key) {
    SetSwitch(key, !SwitchedOn(key));
}

void SetSwitch(NSString *key, BOOL on) {
    [NSUserDefaults.standardUserDefaults setBool:on forKey:key];
}

void SayInMenu(NSMenu *menu, NSString *text) {
    [menu addItemWithTitle:text action:nil keyEquivalent:@""].enabled = NO;
}
