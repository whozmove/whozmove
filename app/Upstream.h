// Upstream: what Whozmove relies on about the apps it works with, Claude Code, Claude Desktop and Ghostty,
// that they could change. When one of them changes, the fix belongs here.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// The versions these were last checked with are in the README ("Tested with").
//
// What isn't here, and why: the layout of a file is known only to the code that reads it (transcripts,
// Claude Desktop's conversation files, the settings files), so it is still in one place each. The hooks know
// Claude Code's tool names and events. The panel page keeps the few facts it needs itself, in
// panel/scripts/whose-move.js: Claude Desktop's scratch folder, and each model's context window.
#import <Foundation/Foundation.h>

// App ids.
extern NSString *const kClaudeDesktopAppId;
extern NSString *const kGhosttyAppId;

// Claude Code's own folder in the home folder, and what Whozmove reads in it.
extern NSString *const kClaudeCodeFolder;
extern NSString *const kClaudeCodeRegistry;      // one file per running session
extern NSString *const kClaudeCodeTranscripts;   // one folder per project, one transcript per session
extern NSString *const kClaudeCodeSettings;
// Settings an organisation sets for the whole machine.
extern NSString *const kClaudeCodeManagedSettings;

// Claude Desktop: its conversation files and its log, both in the home folder.
extern NSString *const kClaudeDesktopConversations;
extern NSString *const kClaudeDesktopLog;
extern NSString *const kClaudeDesktopLogTimeFormat;     // how each log line starts
extern NSString *const kClaudeDesktopFocusLine;         // logged when it shows another conversation
extern NSString *const kClaudeDesktopConversationPrefix; // its own conversation ids start with this
// Links Claude Desktop opens: a conversation (?session=<its id>), or a new one in a folder (?folder=<path>).
extern NSString *const kClaudeDesktopOpenLink;
extern NSString *const kClaudeDesktopNewLink;
// Its window, as the Accessibility API sees it.
extern NSString *const kClaudeDesktopPromptLabel;       // the message box
NSArray<NSString *> *ClaudeDesktopSendLabels(void);     // the message box's send button
extern NSString *const kClaudeDesktopSwitchModelLabel;  // "Switch model?": its button
extern NSString *const kClaudeDesktopCancelLabel;       // and its other button
extern NSString *const kClaudeDesktopDontAskSuffix;     // and its "Don't ask again" box, either apostrophe
// Electron builds a window's accessibility tree only once something asks for it with this attribute.
extern NSString *const kElectronManualAccessibility;

// The choices the details line offers, as [the value Claude Code takes, the name shown]. Models are the
// current family, by the id /model takes; efforts are Claude Code's levels; modes are in Claude's own order.
NSArray<NSArray<NSString *> *> *ModelChoices(void);
NSArray<NSArray<NSString *> *> *EffortChoices(void);
NSArray<NSArray<NSString *> *> *ModeChoices(void);
