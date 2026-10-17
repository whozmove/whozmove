// Links: opening an address (a web page, or a pane of System Settings) the way macOS opens it, in the app that takes
// it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// NO if there's no such address, or nothing opened it.
BOOL OpenLink(NSString *address);
