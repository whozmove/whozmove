// SessionAsks: what a session asks the panel (ask-panel.sh, in every build): to do something you've allowed that session
// to do (Allowed), or to show you something, which needs nothing allowed. Which session asks is found from the process
// that connects, as macOS says it, never from what it sends.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Core;

@interface SessionAsks : NSObject
- (instancetype)initWithCore:(Core *)core;
// Listens on a socket at `path` (AppDir/ask.sock), only you able to connect, off the main thread: each connection is
// one line asked, {"ask": word} with what that word takes (a folder), and one line answered. NO if it couldn't.
- (BOOL)listenAt:(NSString *)path;
- (void)stop;
// What the panel answers a process asking with `line`, on the main thread: refused and why, or what the module whose
// ask it is says, once the session it's found to be has that ask's switch on (or at once, for an ask that only shows
// something). Until the sessions have first been read, "starting:", as who asks can't be known yet.
- (NSString *)answer:(NSString *)line from:(pid_t)pid;
@end
