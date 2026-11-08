// Links: opening an address (a web page, or a pane of System Settings) or a file the way macOS opens it, in the app
// that takes it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>

// Every opening in another app goes through these: a link can carry words into one (Claude Desktop's new
// conversation) and a file can run commands in one (Terminal's .command), so each opens nothing, NO, while Whozmove may
// not act on other apps (MayActOnOtherApps). The first opens `url` where macOS opens it; the second opens `urls` in
// `app`, telling `done` (when given) how it went: at once, with no app, when it opens nothing.
BOOL OpenInOtherApp(NSURL *url);
BOOL OpenInOtherAppWith(NSArray<NSURL *> *urls, NSURL *app, NSWorkspaceOpenConfiguration *configuration,
                        void (^done)(NSRunningApplication *opened, NSError *error));

// NO if there's no such address, or nothing opened it.
BOOL OpenLink(NSString *address);
// A page, a file's included, in the app that opens web pages (your default browser), never in whichever app a file of
// its kind opens in (often an editor, for .html). NO if there's no such app, or it didn't take it.
BOOL OpenInWebBrowser(NSURL *page);
