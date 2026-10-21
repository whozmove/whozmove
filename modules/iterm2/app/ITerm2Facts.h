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

// Its Python API, which takes text for one session only, past Broadcast Input, while it's switched on (Settings ▸
// General ▸ Magic ▸ Enable Python API). It listens only then, and only on a Unix socket in its folder in Application
// Support, whose file can outlast it. A connection is a WebSocket, upgraded from one HTTP request to "/" whose headers
// it checks: the protocol and a library's name and version (only "python" versions are checked), a Host and an Origin
// of localhost, and a one-time cookie and key from its scripting's `request cookie and key for app named`, which shows
// you nothing, adds a line to its Script Console, and errs while the API is off; with the auth box turned off, a
// connection without a good cookie is refused silently. Its messages are proto2 (api.proto), each in a binary frame:
// a ClientOriginatedMessage's id and send_text_request, a SendTextRequest's session (the session's id, as its scripting
// gives it; "all" would be every session), text and suppress_broadcast, and a ServerOriginatedMessage's id, error,
// send_text_response, whose status is OK or SESSION_NOT_FOUND, and notification. It never pings, nor closes a quiet
// connection.
static NSString *const kITerm2APISocket = @"iTerm2/private/socket";  // in Application Support
// The API is on while its settings say so, under this key. It's turned on in its Settings window, as the Accessibility
// API shows it: the app menu's Settings item (Preferences before macOS 13), the General button in the window's
// toolbar beside Profiles, the Magic tab there, and the Enable Python API box, whose ticking has iTerm2 ask you its own
// question ("Enable Python API?") first, holding the tick until you've answered. These are its English words.
static NSString *const kITerm2APISetting = @"EnableAPIServer";
static NSString *const kITerm2SettingsItems[] = {@"Settings…", @"Settings...", @"Preferences…", @"Preferences..."};
static NSString *const kITerm2GeneralPane = @"General", *const kITerm2ProfilesPane = @"Profiles";
static NSString *const kITerm2MagicTab = @"Magic", *const kITerm2APIBox = @"Enable Python API";
static NSString *const kITerm2APIProtocol = @"api.iterm2.com";
static NSString *const kITerm2APILibrary = @"objc 1.0";
enum {
    kITerm2APIMessageId = 1, kITerm2APIError = 2, kITerm2APISendText = 107, kITerm2APINotification = 1000,
    kITerm2APITextSession = 1, kITerm2APITextText = 2, kITerm2APITextNoBroadcast = 3,
    kITerm2APITextStatus = 1, kITerm2APITextTaken = 0, kITerm2APITextSessionGone = 1,
};

// What the panel asks iTerm2 while it's in front, as the codes iTerm2's scripting dictionary (iTerm2.sdef, in its app)
// gives the terms: its current window, that window's current tab and current session, the sessions in a tab, and each
// session's tty. Everything else is told it in AppleScript, by the same dictionary's words (ITerm2.m).
enum : FourCharCode {
    kITerm2CurrentWindow = 'Crwn', kITerm2CurrentTab = 'Crtb', kITerm2CurrentSession = 'Wcsn',
    kITerm2SessionClass = 'Trms', kITerm2Tty = 'Stty',
};
