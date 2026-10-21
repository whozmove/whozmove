// LaunchdFacts: what Whozmove relies on about macOS's launchd for its login item, which a new macOS could change. When
// it does, the fix goes here. The version these were last checked with is in the README ("Tested with").
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// Where a login item of your own goes, in the home folder: a file named for its label, loaded at each login.
extern NSString *const kLaunchAgentsFolder;
// launchctl, and the name of a job in your login session (its domain, gui/<your user id>, then its label), which
// `print` describes, a line of it saying `pid = <the process it runs>` while it runs one, and `bootout` unloads.
extern NSString *const kLaunchctl;
NSString *LaunchdJob(NSString *label);
extern NSString *const kLaunchctlPidLine;
