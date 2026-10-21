// ClaudeCodeFacts: the facts about Claude Code that ClaudeCodeFacts.h describes.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "ClaudeCodeFacts.h"
#import "Files.h"

NSString *const kClaudeCodeFolder = @".claude";

NSString *ClaudeDir(NSString *sub) {
    return [Home() stringByAppendingPathComponent:[kClaudeCodeFolder stringByAppendingPathComponent:sub]];
}
NSString *const kClaudeCodeRegistry = @"sessions";
NSString *const kClaudeCodeTranscripts = @"projects";
NSString *const kClaudeCodeSettings = @"settings.json";
NSString *const kClaudeCodeLocalSettings = @"settings.local.json";
NSString *const kClaudeCodeManagedSettings = @"/Library/Application Support/ClaudeCode/managed-settings.json";
NSString *const kClaudeCodeShellDiffSetting = @"bashEditDiffEnabled";
NSString *const kClaudeCodeShellFailure = @"Error: Exit code";
NSString *const kClaudeCodeSubagents = @"subagents";

BOOL ClaudeRecordsShellChanges(NSString *mode, id setting) {
    if ([setting isKindOfClass:NSNumber.class]) return [setting boolValue];
    return [mode isEqualToString:@"auto"] || [mode isEqualToString:@"bypassPermissions"];
}
NSString *const kClaudeCodeAgentMarks = @"CLAUDECODE CLAUDE_CODE_SESSION_ID";
NSString *const kClaudeCodeTitleWorking = @"◐◑";
NSString *const kClaudeCodeTerminalEntrypoint = @"cli";
NSString *const kClaudeCodeCommand = @"claude";
NSString *const kClaudeCodeResumeFlag = @"--resume";
NSString *const kClaudeCodeState = @".claude.json";
NSString *const kClaudeCodeStateLock = @".lock";
NSString *const kClaudeCodeTrustKey = @"hasTrustDialogAccepted";

NSArray<NSString *> *ClaudeCommandFolders(void) {
    return @[@".local/bin", [kClaudeCodeFolder stringByAppendingPathComponent:@"local"], @"/opt/homebrew/bin",
             @"/usr/local/bin"];
}
NSString *const kClaudeDesktopCommands = @"Library/Application Support/Claude/claude-code";
NSString *const kClaudeDesktopCommandInBuild = @"claude.app/Contents/MacOS/claude";

NSArray<NSString *> *ClaudeUsageArguments(void) {
    return @[@"-p", @"--input-format", @"stream-json", @"--output-format", @"stream-json", @"--verbose", @"--safe-mode",
             @"--no-session-persistence", @"--strict-mcp-config"];
}
NSString *const kClaudeUsageRequest = @"get_usage";

NSArray<NSString *> *ClaudeAuthStatusArguments(void) {
    return @[@"auth", @"status"];
}

NSArray<NSString *> *ClaudeSignInArguments(void) {
    return @[@"auth", @"login"];
}

NSArray<NSString *> *ClaudeOtherAuthVariables(void) {
    return @[@"ANTHROPIC_API_KEY", @"ANTHROPIC_AUTH_TOKEN", @"CLAUDE_CODE_USE_BEDROCK", @"CLAUDE_CODE_USE_VERTEX",
             @"CLAUDE_CODE_USE_FOUNDRY"];
}

NSString *const kClaudeCodeInstallPage = @"https://code.claude.com/docs/en/setup";

NSString *const kWhozmovePlugin = @"whozmove@whozmove";
NSString *const kWhozmoveMarketplace = @"whozmove";

NSArray<NSString *> *PluginListArguments(void) {
    return @[@"plugin", @"list", @"--json"];
}

NSArray<NSString *> *PluginMarketplaceAddArguments(NSString *folder) {
    return @[@"plugin", @"marketplace", @"add", folder];
}

NSArray<NSString *> *PluginInstallArguments(void) {
    return @[@"plugin", @"install", kWhozmovePlugin];
}

NSArray<NSString *> *PluginMarketplaceUpdateArguments(void) {
    return @[@"plugin", @"marketplace", @"update", kWhozmoveMarketplace];
}

NSArray<NSString *> *PluginUpdateArguments(void) {
    return @[@"plugin", @"update", kWhozmovePlugin];
}

NSArray<NSString *> *PluginEnableArguments(void) {
    return @[@"plugin", @"enable", kWhozmovePlugin];
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

// The fields of a project Claude Desktop adds to Claude Code's state file before trusting it (2.31226.1): Claude Code
// reads a project with them, so one Whozmove adds starts the same way.
NSDictionary *ClaudeCodeProjectDefaults(void) {
    return @{@"allowedTools": @[], @"mcpContextUris": @[], @"enabledMcpjsonServers": @[],
             @"disabledMcpjsonServers": @[], @"hasTrustDialogAccepted": @NO, @"projectOnboardingSeenCount": @0,
             @"hasClaudeMdExternalIncludesApproved": @NO, @"hasClaudeMdExternalIncludesWarningShown": @NO};
}
