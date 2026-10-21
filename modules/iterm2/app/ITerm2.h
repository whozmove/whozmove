// ITerm2: sessions running in iTerm2: a session's window, tab and pane brought forward, keys typed into a session
// (through its Python API, else only into one alone in its window), and a command run in a new tab (a new
// conversation, Sign in), through AppleScript, and which tab iTerm2 shows, through its Apple events. A host
// (contracts/Host.h) whose sessions run under its server, not under the app.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Module.h"
#import "Host.h"

@interface ITerm2 : NSObject <Module, TypingHost, CommandHost>
@end
