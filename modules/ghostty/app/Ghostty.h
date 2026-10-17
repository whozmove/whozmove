// Ghostty: finding a session's Ghostty tab, bringing it forward and typing into it, through AppleScript, and which
// tab it shows, through its Apple events. A host the panel types into (contracts/Host.h).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Module.h"
#import "Host.h"

@interface Ghostty : NSObject <Module, TypingHost, CommandHost>
@end
