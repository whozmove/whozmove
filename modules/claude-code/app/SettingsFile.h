// SettingsFile: putting the /model and /effort defaults back in Claude Code's settings, key by key.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@interface SettingsFile : NSObject
// Before a /model or /effort command goes in: remembers the defaults it may overwrite.
- (void)holdDefaults:(NSString *)field;
// Once that command has run, or won't: puts those defaults back if it saved its own. Called once for each hold.
- (void)releaseDefaults:(NSString *)field saved:(BOOL)saved;
@end
