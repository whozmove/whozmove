// AppleScript: running a script.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "AppleScript.h"
#import "Log.h"

NSString *RunAppleScript(NSString *source) {
    NSDictionary *error = nil;
    NSAppleEventDescriptor *result = [[[NSAppleScript alloc] initWithSource:source] executeAndReturnError:&error];
    if (!result) PanelLog(@"AppleScript failed: %@", error);
    return result.stringValue;
}
