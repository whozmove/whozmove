// Builds: the build of Whozmove running now, as build.sh recorded it, for the header's line (Show Build in Header)
// and the install module.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// Where this app's own build came from, as build.sh recorded it, or nil for a build it didn't record.
NSDictionary *RunningBuild(void);
// The same, in words, for the header's tooltip.
NSString *RunningBuildTip(void);
// Whether an agent made this build (build.sh records Claude Code's CLAUDECODE mark), whose hooks are never put in place:
// every session you start would run them, and an agent's may be half-way through a change.
BOOL BuiltByAgent(void);
