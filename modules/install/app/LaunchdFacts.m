// LaunchdFacts: what Whozmove relies on about launchd for its login item (LaunchdFacts.h).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "LaunchdFacts.h"
#import <unistd.h>

NSString *const kLaunchAgentsFolder = @"Library/LaunchAgents";
NSString *const kLaunchctl = @"/bin/launchctl";
NSString *const kLaunchctlPidLine = @"pid = ";

NSString *LaunchdJob(NSString *label) {
    return [NSString stringWithFormat:@"gui/%u/%@", getuid(), label];
}
