// AppleScript: running a script that tells another app what to do. Only on the main thread, where AppleScript is
// promised to run; off it, an app is asked with Apple events of Whozmove's own (AppleEvents.h).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// Runs `source`, and returns what it returns, as text (nil if it failed: why goes in the log).
NSString *RunAppleScript(NSString *source);
