// Links: opening an address.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Links.h"
#import <Cocoa/Cocoa.h>

BOOL OpenLink(NSString *address) {
    NSURL *url = [NSURL URLWithString:address];
    return url && [NSWorkspace.sharedWorkspace openURL:url];
}
