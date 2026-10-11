// Upstream: the facts about Claude Code, Claude Desktop and Ghostty that Upstream.h describes.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Upstream.h"

NSString *const kClaudeDesktopAppId = @"com.anthropic.claudefordesktop";
NSString *const kGhosttyAppId = @"com.mitchellh.ghostty";

NSString *const kClaudeCodeFolder = @".claude";
NSString *const kClaudeCodeRegistry = @"sessions";
NSString *const kClaudeCodeTranscripts = @"projects";
NSString *const kClaudeCodeSettings = @"settings.json";
NSString *const kClaudeCodeManagedSettings = @"/Library/Application Support/ClaudeCode/managed-settings.json";

NSString *const kClaudeDesktopConversations = @"Library/Application Support/Claude/claude-code-sessions";
NSString *const kClaudeDesktopLog = @"Library/Logs/Claude/main.log";
NSString *const kClaudeDesktopLogTimeFormat = @"yyyy-MM-dd HH:mm:ss";
NSString *const kClaudeDesktopFocusLine = @"setFocusedSession: sessionId=";
NSString *const kClaudeDesktopConversationPrefix = @"local_";
NSString *const kClaudeDesktopOpenLink = @"claude://code/continue";
NSString *const kClaudeDesktopNewLink = @"claude://code/new";
NSString *const kClaudeDesktopPromptLabel = @"Prompt";
NSString *const kClaudeDesktopSwitchModelLabel = @"Switch model";
NSString *const kClaudeDesktopCancelLabel = @"Cancel";
NSString *const kClaudeDesktopDontAskSuffix = @"t ask again";
NSString *const kElectronManualAccessibility = @"AXManualAccessibility";

NSArray<NSString *> *ClaudeDesktopSendLabels(void) {
    return @[@"Submit", @"Send", @"Send message"];
}

NSArray<NSArray<NSString *> *> *ModelChoices(void) {
    return @[@[@"claude-opus-5-5", @"Opus 5.5"], @[@"claude-sonnet-5-5", @"Sonnet 5.5"],
             @[@"claude-haiku-5-5", @"Haiku 5.5"], @[@"claude-fable-5-1", @"Fable 5.1"]];
}

NSArray<NSArray<NSString *> *> *EffortChoices(void) {
    return @[@[@"low", @"low"], @[@"medium", @"medium"], @[@"high", @"high"], @[@"xhigh", @"xhigh"], @[@"max", @"max"]];
}

NSArray<NSArray<NSString *> *> *ModeChoices(void) {
    return @[@[@"default", @"Ask permissions"], @[@"acceptEdits", @"Accept edits"], @[@"plan", @"Plan mode"],
             @[@"auto", @"Auto mode"], @[@"bypassPermissions", @"Bypass permissions"]];
}
