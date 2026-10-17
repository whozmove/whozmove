// GhosttyFacts: what Whozmove relies on about Ghostty that Ghostty could change. When it does, the fix goes here. The
// version these were last checked with is in the README ("Tested with").
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// Its app id, and its name as the panel says it.
static NSString *const kGhosttyAppId = @"com.mitchellh.ghostty";
static NSString *const kGhosttyName = @"Ghostty";

// What the panel asks Ghostty while it's in front, as the codes Ghostty's scripting dictionary (Ghostty.sdef, in its app)
// gives the terms: its front window, that window's selected tab, the terminals in it and the one of them with the
// keyboard, and each terminal's id, folder and title. Everything else is told it in AppleScript, by the same
// dictionary's words (Ghostty.m).
enum : FourCharCode {
    kGhosttyFrontWindow = 'GFWn', kGhosttySelectedTab = 'GWsT', kGhosttyFocusedTerminal = 'GTfT',
    kGhosttyTerminalClass = 'Gtrm', kGhosttyTerminalId = 'ID  ', kGhosttyWorkingDirectory = 'Gwdr', kGhosttyTitle = 'pnam',
};
