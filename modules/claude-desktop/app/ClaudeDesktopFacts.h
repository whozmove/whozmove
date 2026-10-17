// ClaudeDesktopFacts: what Whozmove relies on about Claude Desktop that Claude Desktop could change. When it does, the fix
// goes here. The version these were last checked with is in the README ("Tested with").
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// Its app id, and how Claude Code's registry marks a session it runs (its `entrypoint`). Its process while it runs (else
// 0), and bringing it forward.
extern NSString *const kClaudeDesktopAppId;
extern NSString *const kClaudeDesktopEntrypoint;
pid_t ClaudeDesktopPid(void);
void ActivateClaudeDesktop(void);

// Its conversation files and its log, both in the home folder.
extern NSString *const kClaudeDesktopConversations;
extern NSString *const kClaudeDesktopLog;
extern NSString *const kClaudeDesktopLogTimeFormat;     // how each log line starts
extern NSString *const kClaudeDesktopFocusLine;         // logged when it shows another conversation
extern NSString *const kClaudeDesktopStartLine;         // logged as it starts a new conversation (its first message)
extern NSString *const kClaudeDesktopSessionLine;       // then "<this><its id> in <its folder>" (also for one carried on)
extern NSString *const kClaudeDesktopConversationPrefix; // its own conversation ids start with this
// A conversation started with "No folder" gets a folder of its own, made in here.
extern NSString *const kClaudeDesktopScratchFolders;
// Links Claude Desktop opens: a conversation (?session=<its id>), or a new one, which takes the first message too
// (?q=<words>): Claude puts it in the new conversation's message box, and sends nothing until Send is pressed. It cuts
// longer words short, so only so many go in this way. The new one's link takes a folder as well (&folder=<path>), but
// Claude then asks to trust it every time, and loses it, starting the conversation with "No folder": so the folder is
// chosen in Claude's own folder list instead (its button and list below).
extern NSString *const kClaudeDesktopOpenLink;
extern NSString *const kClaudeDesktopNewLink;
extern const NSUInteger kClaudeDesktopLinkWordsMax;
// Its window, as the Accessibility API sees it.
extern NSString *const kClaudeDesktopPromptLabel;       // the message box
NSArray<NSString *> *ClaudeDesktopSendLabels(void);     // the message box's send button
extern NSString *const kClaudeDesktopSwitchModelLabel;  // "Switch model?": its button
extern NSString *const kClaudeDesktopCancelLabel;       // and its other button
extern NSString *const kClaudeDesktopDontAskSuffix;     // and its "Don't ask again" box, either apostrophe
extern NSString *const kClaudeDesktopTrustLabel;        // "Trust this workspace?": its button
// A new conversation's folder button shows the name of the folder it will start in, or one of these with none; its
// list names each Recent folder with its path as its tooltip. The branch box beside it shows a dash until the folder
// chosen is ready (in a git repository: there's no branch box outside one).
extern NSString *const kClaudeDesktopNoFolderLabel;
extern NSString *const kClaudeDesktopSelectFolderLabel;
extern NSString *const kClaudeDesktopNoBranchLabel;
// Electron builds a window's accessibility tree only once something asks for it with this attribute.
extern NSString *const kElectronManualAccessibility;
