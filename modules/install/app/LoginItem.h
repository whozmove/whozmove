// LoginItem: Whozmove opening at login, as a login item of its own, a file in ~/Library/LaunchAgents that launchd loads
// at each login. Plain functions: Install decides when (from an Applications folder only, on its queue), and asks
// launchctl only through a stand-in in its print mode, so a print run never reaches your real login item, which answers
// to the same label whatever $HOME says.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// Where the login item's file goes, for its label (the app's bundle id), in the home folder ($HOME).
NSString *LoginItemPath(NSString *label);
// What it holds to open `program` (the app's own, inside it) at each login: started when it loads, again only after a
// crash (so one left behind with the app gone fails once at login, rather than every few seconds), in your login
// session only, as an app you use, and named for the app in System Settings' Login Items.
NSDictionary *LoginItemContents(NSString *label, NSString *program);
// Writes it, only when what's there differs (a moved app gets a new one): nil once it holds what it should, with
// *wrote saying whether it was written now, else why it couldn't be.
NSString *KeepLoginItem(NSString *label, NSString *program, BOOL *wrote);
// Takes it out: whether there was one.
BOOL RemoveLoginItem(NSString *label);
// The process launchd runs the login item's job as, from what `launchctl print` said of it, or 0 while it runs none.
pid_t LoginJobPid(NSString *printed);
