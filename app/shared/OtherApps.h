// OtherApps: whether Whozmove may act on other apps now: press their buttons, type or post keys into them, open links
// and files in them, or send them Apple events. Launching an app, or bringing one forward, isn't acting on it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// Only while this run's home is surely your own, so a test, a print run or a copy given a throwaway home never
// presses, types or sends anything in your apps, which no sandbox a test runs in can stop. Every way Whozmove acts on
// another app (AppleEvents.h, AppleScript.h, Accessibility.h's presses and posts, Links.h's openings, iTerm2's API)
// asks it first and does nothing when it says no, which panel.log says once.
BOOL MayActOnOtherApps(void);
