// ClaudeDesktopFacts: the facts about Claude Desktop that ClaudeDesktopFacts.h describes.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "ClaudeDesktopFacts.h"
#import <AppKit/AppKit.h>

NSString *const kClaudeDesktopAppId = @"com.anthropic.claudefordesktop";
NSString *const kClaudeDesktopEntrypoint = @"claude-desktop";
NSString *const kClaudeDesktopDownloadPage = @"https://claude.com/download";

NSString *const kClaudeDesktopConversations = @"Library/Application Support/Claude/claude-code-sessions";
NSString *const kClaudeDesktopLog = @"Library/Logs/Claude/main.log";
NSString *const kClaudeDesktopLogTimeFormat = @"yyyy-MM-dd HH:mm:ss";
NSString *const kClaudeDesktopFocusLine = @"setFocusedSession: sessionId=";
NSString *const kClaudeDesktopStartLine = @"LocalSessions.start:";
NSString *const kClaudeDesktopSessionLine = @"Starting local session ";
NSString *const kClaudeDesktopConversationPrefix = @"local_";
NSString *const kClaudeDesktopScratchFolders = @"Library/Application Support/Claude/scratch-workspaces";
NSString *const kClaudeDesktopOpenLink = @"claude://code/continue";
NSString *const kClaudeDesktopNewLink = @"claude://code/new";
const NSUInteger kClaudeDesktopLinkWordsMax = 4000;  // Claude keeps 14,336 (2.31226.1); well within that
NSString *const kClaudeDesktopPromptLabel = @"Prompt";
NSString *const kClaudeDesktopSwitchModelLabel = @"Switch model";
NSString *const kClaudeDesktopCancelLabel = @"Cancel";
NSString *const kClaudeDesktopDontAskSuffix = @"t ask again";
NSString *const kClaudeDesktopTrustLabel = @"Trust workspace";
NSString *const kClaudeDesktopPresets = @"Library/Application Support/Claude/ccd-session-presets.json";
NSString *const kClaudeDesktopLocalTarget = @"local";
NSString *const kClaudeDesktopEnvironmentPrefix = @"Environment: ";
NSString *const kClaudeDesktopRecentEnvironmentsLabel = @"Recent environments";
NSString *const kClaudeDesktopNoFolderLabel = @"No folder";
NSString *const kClaudeDesktopSelectFolderLabel = @"Select folder…";
NSString *const kClaudeDesktopNoBranchLabel = @"—";
NSString *const kElectronManualAccessibility = @"AXManualAccessibility";

NSArray<NSString *> *ClaudeDesktopSendLabels(void) {
    return @[@"Submit", @"Send", @"Send message"];
}

pid_t ClaudeDesktopPid(void) {
    return [NSRunningApplication runningApplicationsWithBundleIdentifier:kClaudeDesktopAppId].firstObject
        .processIdentifier;
}

void ActivateClaudeDesktop(void) {
    [[NSRunningApplication runningApplicationsWithBundleIdentifier:kClaudeDesktopAppId].firstObject
        activateWithOptions:0];
}
