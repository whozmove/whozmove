// ClaudeCodeFacts: the facts about Claude Code that ClaudeCodeFacts.h describes.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "ClaudeCodeFacts.h"
#import "Files.h"
#import "Task.h"

NSString *const kClaudeCodeFolder = @".claude";

NSString *ClaudeDir(NSString *sub) {
    return [Home() stringByAppendingPathComponent:[kClaudeCodeFolder stringByAppendingPathComponent:sub]];
}
NSString *WhozmovePluginCopies(void) {
    return [[ClaudeDir(kClaudeCodePluginCache) stringByAppendingPathComponent:kWhozmoveMarketplace]
            stringByAppendingPathComponent:[kWhozmovePlugin componentsSeparatedByString:@"@"].firstObject];
}
NSString *const kClaudeCodeRegistry = @"sessions";
NSString *const kClaudeCodeTranscripts = @"projects";
NSString *const kClaudeCodeSettings = @"settings.json";
NSString *const kClaudeCodeLocalSettings = @"settings.local.json";
NSString *const kClaudeCodeManagedSettings = @"/Library/Application Support/ClaudeCode/managed-settings.json";
NSString *const kClaudeCodeShellDiffSetting = @"bashEditDiffEnabled";
NSString *const kClaudeCodeShellFailure = @"Error: Exit code";
NSString *const kClaudeCodeSubagents = @"subagents";
NSString *const kClaudeCodeToolResults = @"tool-results";
NSString *const kClaudeCodePromptHistory = @"history.jsonl";
NSString *const kClaudeCodePastes = @"paste-cache";
NSString *const kClaudeCodeEditCopies = @"file-history";
NSString *const kClaudeCodeAttachmentLine = @"attachment";
NSString *const kClaudeCodeQueuedAttachment = @"queued_command";
NSString *const kClaudeCodeTypedOrigin = @"human";
NSArray<NSString *> *const kClaudeCodePictureParts = @[@"image", @"document"];
NSString *const kClaudeCodeSnapshotLine = @"file-history-snapshot";
NSArray<NSString *> *const kClaudeCodeInstructions = @[@"CLAUDE.md", @"CLAUDE.local.md", @".claude/CLAUDE.md"];
NSArray<NSString *> *const kClaudeCodeAgentsInstructions = @[@"AGENTS.md", @".claude/AGENTS.md"];
NSArray<NSString *> *const kClaudeCodeInstructionFolders = @[@"rules", @"skills", @"agents", @"commands",
                                                            @"output-styles"];
NSString *const kClaudeCodeUserInstructions = @"CLAUDE.md";
NSString *const kClaudeCodeManagedInstructions = @"/Library/Application Support/ClaudeCode/CLAUDE.md";
NSString *const kClaudeCodeMemory = @"memory";
NSString *const kClaudeCodePluginCache = @"plugins/cache";
NSString *const kClaudeCodeProjectFolder = @".claude";
const NSInteger kClaudeCodeImportHops = 4;
NSString *const kClaudeCodeShellInput = @"<bash-input>";
NSArray<NSString *> *const kClaudeCodeShellOutputs = @[@"<bash-stdout>", @"<bash-stderr>", @"<local-command-stdout>"];
NSString *const kClaudeCodeAITitle = @"aiTitle";
NSString *const kClaudeCodeCustomTitle = @"customTitle";
const int kClaudeCodeEndWait = 5;
NSString *const kClaudeCodeClearCommand = @"purge";

BOOL ClaudeRecordsShellChanges(NSString *mode, id setting) {
    if ([setting isKindOfClass:NSNumber.class]) return [setting boolValue];
    return [mode isEqualToString:@"auto"] || [mode isEqualToString:@"bypassPermissions"];
}
NSString *const kClaudeCodeStatusBackground = @"shell";
NSString *ClaudeStatus(id status) {
    if (![status isKindOfClass:NSString.class]) return nil;
    return [status isEqualToString:kClaudeCodeStatusBackground] ? @"idle" : status;
}
NSInteger ClaudeContextWindow(NSString *model, NSInteger tokens) {
    model = model ?: @"";
    BOOL large = [model containsString:@"[1m]"] || [model containsString:@"claude-opus-5"]
        || [model containsString:@"claude-fable-5"] || tokens > 200000;
    return large ? 1000000 : 200000;
}
double ClaudeEditedAt(NSNumber *editedAt, NSString *outcome, NSNumber *outcomeAt) {
    if (editedAt) return editedAt.doubleValue;
    NSArray *changed = @[@"Implemented", @"Documented", @"Built", @"Validated", @"Tested", @"Committed", @"Pushed",
                         @"PR raised", @"Merged", @"On staging", @"Deployed"];
    return [changed containsObject:outcome ?: @""] ? outcomeAt.doubleValue : 0;
}
NSString *const kClaudeCodeJobShell = @"shell", *const kClaudeCodeJobAgent = @"subagent";
NSString *const kClaudePluginRootWord = @"${CLAUDE_PLUGIN_ROOT}", *const kWhozmoveAskScript = @"scripts/ask-panel.sh";
NSString *const kClaudeCodeStopJob = @"/tasks";
BOOL ClaudeJobHolds(NSString *type) {
    return ClaudeJobShown(type) && ![@[kClaudeCodeJobShell, @"monitor", @"cloud session"] containsObject:type ?: @""];
}
BOOL ClaudeJobShown(NSString *type) {
    return !type || ![@[@"dream", @"auto-mode scan", @"memory import"] containsObject:type];
}
NSString *ClaudeAgentRecordPath(NSString *transcript, NSString *agentId) {
    if (!transcript.length || !TaskIdPlain(agentId)) return nil;
    NSString *file = [NSString stringWithFormat:@"agent-%@.meta.json", agentId];
    return [[transcript.stringByDeletingPathExtension stringByAppendingPathComponent:kClaudeCodeSubagents]
        stringByAppendingPathComponent:file];
}
BOOL ClaudeAgentFinished(NSDictionary *record) {
    return [AsNumber(record[@"finished"]) boolValue];
}
NSString *const kClaudeCodeAgentMarks = @"CLAUDECODE CLAUDE_CODE_SESSION_ID";
NSString *const kClaudeCodeTitleWorking = @"◐◑";
NSString *const kClaudeCodeVoiceRecorders = @"rec sox";
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

BOOL ClaudeAsideResumable(NSString *sessionId) {
    return [sessionId isKindOfClass:NSString.class] && [[NSUUID alloc] initWithUUIDString:sessionId] != nil;
}

NSArray<NSString *> *ClaudeAsideArguments(NSString *sessionId, NSString *model, NSString *effort) {
    if (!ClaudeAsideResumable(sessionId)) return nil;
    NSString *refuse = @"{\"env\":{\"DISABLE_AUTO_COMPACT\":\"1\"},\"hooks\":{\"PreToolUse\":[{\"matcher\":\"*\","
        "\"hooks\":[{\"type\":\"command\",\"command\":\"/bin/sh -c 'echo A side question uses no tools >&2; "
        "exit 2'\"}]}]}}";
    NSMutableArray *arguments = [@[@"-p", kClaudeCodeResumeFlag, sessionId, @"--fork-session",
                                   @"--no-session-persistence", @"--input-format", @"stream-json", @"--output-format",
                                   @"stream-json", @"--verbose", @"--max-turns", @"1", @"--permission-mode", @"dontAsk",
                                   @"--setting-sources", @"", @"--settings", refuse] mutableCopy];
    if (model.length) [arguments addObjectsFromArray:@[@"--model", model]];
    if (effort.length) [arguments addObjectsFromArray:@[@"--effort", effort]];
    return arguments;
}
NSString *const kClaudeAsideLine = @"Whozmove: the user asks this on the side, and you're a copy of this session "
    "answering it alone. Use no tools; answer from what you already know, in a few short paragraphs, and don't carry "
    "on the task.";

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
NSString *const kReloadPluginsCommand = @"/reload-plugins";
NSString *const kForcedReloadCommand = @"/reload-plugins --force";
NSString *const kReloadedResult = @"Reloaded:";
NSString *const kWhozmoveMarketplace = @"whozmove";
NSString *const kClaudeCodePlugins = @"plugins";
NSString *const kClaudeCodeInstalledPlugins = @"installed_plugins.json";
NSString *const kClaudeCodeKnownMarketplaces = @"known_marketplaces.json";

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

NSString *const kClaudeCodeSigningIdentifier = @"com.anthropic.claude-code";
NSString *const kClaudeCodeTeam = @"Q6L2SF6YDW";
NSString *const kClaudeCodeNodeEntry = @"@anthropic-ai/claude-code/cli.js";
NSString *const kClaudeCodeProgram = @"claude";
NSString *const kClaudeCodeNpmProgram = @"claude.exe";
NSString *const kClaudeCodeNpmSignedSince = @"2.1.113";
NSString *const kClaudeCodeNodeProgram = @"node";
NSString *const kClaudeCodeVersionName = @"^[0-9]+(\\.[0-9]+)+$";
