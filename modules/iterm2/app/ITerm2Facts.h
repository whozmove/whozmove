// ITerm2Facts: what Whozmove relies on about iTerm2 that iTerm2 could change. When it does, the fix goes here. The
// version these were last checked with is in the README ("Tested with").
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// Its app id, and its name as the panel says it.
static NSString *const kITerm2AppId = @"com.googlecode.iterm2";
static NSString *const kITerm2Name = @"iTerm2";

// iTerm2 runs its sessions under a server of its own, which it starts and stays above while it runs. After a crash, an
// update or a quit that keeps them, the server lives on with them, under launchd, and iTerm2 takes them back as it
// starts. The server is a program named for its own version, which needn't be the app's (iTermServer-3.6.9 under
// iTerm2 3.7.6), in iTerm2's folder in Application Support, or elsewhere for a copy with settings of its own, so it's
// known by its name alone.
static NSString *const kITerm2ServerPrefix = @"iTermServer-";

// A command iTerm2 is given as a new tab's own program is first read as text of its own, where a backslash starts an
// escape (\" is ", \( a value worked out), and each $$NAME$$ is asked of you; then it's split into words by quotes and
// backslashes, as a shell would, but with nothing expanded. So the command is given as plain words, of these
// characters only, and what the tab runs goes in a file of commands.
static NSString *const kITerm2PlainCharacters = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789/._-";

// The characters a key sends, which go into a session as typed (its `write text`): Return, Backspace, Ctrl+S, and
// Shift+Tab, which is Escape and these after it. iTerm2 sends a script's text through Broadcast Input, which can copy
// it to the other sessions in the window, and nothing in its scripting says whether that's on.
enum { kITerm2Return = 13, kITerm2Backspace = 127, kITerm2ControlS = 19, kITerm2Escape = 27 };
static NSString *const kITerm2ShiftTabAfterEscape = @"[Z";

// What the panel asks iTerm2 while it's in front, as the codes iTerm2's scripting dictionary (iTerm2.sdef, in its app)
// gives the terms: its current window, that window's current tab and current session, the sessions in a tab, and each
// session's tty. Everything else is told it in AppleScript, by the same dictionary's words (ITerm2.m).
enum : FourCharCode {
    kITerm2CurrentWindow = 'Crwn', kITerm2CurrentTab = 'Crtb', kITerm2CurrentSession = 'Wcsn',
    kITerm2SessionClass = 'Trms', kITerm2Tty = 'Stty',
};
