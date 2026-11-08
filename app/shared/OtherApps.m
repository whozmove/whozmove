// OtherApps: whether Whozmove may act on other apps now.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "OtherApps.h"
#import "Files.h"
#import "Log.h"

BOOL MayActOnOtherApps(void) {
    if (HomeSurelyYourOwn()) return YES;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        PanelLog(@"Whozmove pressed, typed, opened and sent nothing in other apps: this run's home isn't your own");
    });
    return NO;
}
