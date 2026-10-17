// Builds: the build of Whozmove running now, as build.sh recorded it, for the header's line (Show Build in Header).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// Where this app's own build came from, as build.sh recorded it, or nil for a build it didn't record.
NSDictionary *RunningBuild(void);
// The same, in words, for the header's tooltip.
NSString *RunningBuildTip(void);
