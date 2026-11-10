// ClaudeCodeFacts: the facts about Claude Code that ClaudeCodeFacts.h describes.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "ClaudeCodeFacts.h"
#import "Files.h"
#import "Git.h"
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
NSString *const kClaudeCodeCredentials = @".credentials.json";
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
NSString *const kClaudeCodePlanChangesWords = @"The user wants changes to the plan: ";
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

NSArray<NSString *> *ClaudeAsideArguments(NSString *sessionId, NSString *model, NSString *effort, BOOL git) {
    if (!ClaudeAsideResumable(sessionId)) return nil;
    NSDictionary *hook = @{@"type": @"command", @"command": kClaudeAsideHook, @"timeout": @(kClaudeAsideHookTimeout)};
    NSDictionary *settings = @{@"env": @{@"DISABLE_AUTO_COMPACT": @"1"},
                               @"hooks": @{@"PreToolUse": @[@{@"matcher": @"*", @"hooks": @[hook]}]}};
    NSData *json = [NSJSONSerialization dataWithJSONObject:settings
                                                   options:NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes
                                                     error:nil];
    NSMutableArray<NSString *> *tools = [@[kClaudeToolRead, kClaudeToolGrep, kClaudeToolGlob] mutableCopy];
    if (git)
        for (NSString *command in GitReadOnlyCommands())
            [tools addObject:[NSString stringWithFormat:@"%@(git %@:*)", kClaudeToolBash, command]];
    NSMutableArray *arguments = [@[@"-p", kClaudeCodeResumeFlag, sessionId, @"--fork-session",
                                   @"--no-session-persistence", @"--input-format", @"stream-json", @"--output-format",
                                   @"stream-json", @"--verbose", @"--max-turns", @(kClaudeAsideTurns).stringValue,
                                   @"--permission-mode", @"dontAsk", @"--setting-sources", @"",
                                   @"--allowedTools", [tools componentsJoinedByString:@","],
                                   @"--settings", [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]]
                                 mutableCopy];
    if (model.length) [arguments addObjectsFromArray:@[@"--model", model]];
    if (effort.length) [arguments addObjectsFromArray:@[@"--effort", effort]];
    return arguments;
}
const NSInteger kClaudeAsideTurns = 12;
NSArray<NSString *> *ClaudeAsideThinkingArguments(void) { return @[@"--thinking-display", @"summarized"]; }
NSArray<NSString *> *ClaudeAsideThinkingVersions(void) { return @[@"2.1.319"]; }
NSString *ClaudeCodeVersionAt(NSString *program) {
    NSString *real = program.length ? RealPath(program) ?: program : nil;
    BOOL (^version)(NSString *) = ^BOOL(NSString *name) {
        return [name rangeOfString:kClaudeCodeVersionName options:NSRegularExpressionSearch].location != NSNotFound;
    };
    NSString *file = real.lastPathComponent, *folder = real.stringByDeletingLastPathComponent.lastPathComponent;
    if (version(file)) return file;
    if ([file isEqual:kClaudeCodeProgram] && version(folder)) return folder;
    return nil;
}
NSString *const kClaudeAsideHook = @"/bin/sh -c '\"$WHOZMOVE_ASIDE_CHECK\" --helper-aside-check "
    "\"$WHOZMOVE_ASIDE_FOLDER\" || exit 2'";
const NSInteger kClaudeAsideHookTimeout = 600;
NSString *const kClaudeAsideCheckVariable = @"WHOZMOVE_ASIDE_CHECK";
NSString *const kClaudeAsideFolderVariable = @"WHOZMOVE_ASIDE_FOLDER";
NSString *const kClaudeAsideCheckFlag = @"--helper-aside-check";
NSString *const kClaudeHookToolName = @"tool_name", *const kClaudeHookToolInput = @"tool_input";
NSString *const kClaudeToolRead = @"Read", *const kClaudeToolGrep = @"Grep", *const kClaudeToolGlob = @"Glob",
    *const kClaudeToolBash = @"Bash";
NSString *const kClaudeToolFilePath = @"file_path", *const kClaudeToolPath = @"path",
    *const kClaudeToolPattern = @"pattern", *const kClaudeToolCommand = @"command",
    *const kClaudeToolInBackground = @"run_in_background", *const kClaudeToolGrepFilter = @"glob";
NSString *const kClaudeToolGrepMode = @"output_mode", *const kClaudeGrepContent = @"content",
    *const kClaudeGrepFiles = @"files_with_matches", *const kClaudeGrepCount = @"count";
NSArray<NSString *> *ClaudeGrepSkips(void) { return @[@".git", @".svn", @".hg", @".bzr", @".jj", @".sl"]; }
// Words in a list: "a", "a and b", "a, b and c".
static NSString *Listed(NSArray<NSString *> *words) {
    if (words.count < 2) return words.firstObject ?: @"";
    return [NSString stringWithFormat:@"%@ and %@",
            [[words subarrayWithRange:NSMakeRange(0, words.count - 1)] componentsJoinedByString:@", "],
            words.lastObject];
}

NSString *ClaudeAsideLine(void) {
    // The commands and what each needs are git's own (GitReadOnlyCommands), so these words and the checker never
    // disagree: those that need options, and the options, said once for each set.
    NSMutableArray<NSString *> *needing = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *byNeeds = [NSMutableDictionary dictionary];
    for (NSString *command in GitReadOnlyCommands()) {
        NSString *needs = [GitReadOnlyNeeds(command) componentsJoinedByString:@" "];
        if (!needs.length) continue;
        if (!byNeeds[needs]) {
            byNeeds[needs] = [NSMutableArray array];
            [needing addObject:needs];
        }
        [byNeeds[needs] addObject:command];
    }
    NSMutableArray<NSString *> *withOptions = [NSMutableArray array];
    for (NSString *needs in needing)
        [withOptions addObject:[NSString stringWithFormat:@"%@ with %@", Listed(byNeeds[needs]), needs]];
    NSString *options = withOptions.count
        ? [NSString stringWithFormat:@" (%@)", [withOptions componentsJoinedByString:@"; "]] : @"";
    return [NSString stringWithFormat:@"Whozmove: the user asks this on the side, and you're a copy of this session "
            "answering it alone. You may read the project's files and run git %@ in its folder%@; change nothing, "
            "message no one, and don't carry on the task. Answer in a few short paragraphs.",
            Listed(GitReadOnlyCommands()), options];
}

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
