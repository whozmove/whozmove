// Links: opening an address (a web page, or a pane of System Settings) the way macOS opens it, in the app that takes
// it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// NO if there's no such address, or nothing opened it.
BOOL OpenLink(NSString *address);
// A page, a file's included, in the app that opens web pages (your default browser), never in whichever app a file of
// its kind opens in (often an editor, for .html). NO if there's no such app, or it didn't take it.
BOOL OpenInWebBrowser(NSURL *page);
