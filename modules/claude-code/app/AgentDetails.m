// AgentDetails: each session's model, effort, permission mode and context, and its Shift+Tab cycle.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "AgentDetails.h"
#import "Row.h"
#import "Files.h"
#import "Processes.h"
#import "ClaudeCodeFacts.h"

@interface AgentDetails ()
@property (strong) NSMutableDictionary<NSString *, NSArray *> *processArgs;  // ProcessKey -> launch arguments
@property (strong) NSDictionary *settingsCache;                             // {mtime, settings}
@property (assign) NSTimeInterval settingsCheckedAt;                         // when its mtime was last looked at
@end

@implementation AgentDetails

- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.processArgs = [NSMutableDictionary dictionary];
    return self;
}

// Fills in each session's model, effort, permission mode and context use, from the most specific source first.
// - mode: the app that keeps the conversation (Claude Desktop's live record of it, the row's hostDetails), then the
//   hook (the live mode in a terminal, which changes with Shift+Tab), then the transcript (the mode of the last
//   prompt, or the one the session started in, which is all there is for a session started before the hook was set
//   up), then --permission-mode, then permissions.defaultMode in the settings.
// - model: Claude Desktop's conversation (it changes the moment the model is switched), then the latest reply in
//   the transcript, then --model, then the settings' model.
// - effort: Claude Desktop, then the latest reply in the transcript (the effort it was made with), then --effort,
//   then the settings' modelSettings[model].effortLevel, then effortLevel.
- (void)describe:(Row *)row transcript:(NSDictionary *)transcript chosen:(NSDictionary *)chosen {
    NSDictionary *usage = transcript[@"usage"];
    NSDictionary *desktop = row.hostDetails;
    NSArray *args = [self argumentsOf:row];
    NSDictionary *settings = [self userSettings];

    NSString *mode = desktop[@"mode"] ?: row.permissionMode ?: transcript[@"mode"]
                  ?: FlagValue(args, @"--permission-mode") ?: settings[@"permissions"][@"defaultMode"] ?: @"default";
    NSString *model = desktop[@"model"] ?: ([usage[@"model"] length] ? usage[@"model"] : nil)
                   ?: FlagValue(args, @"--model") ?: settings[@"model"];
    NSString *replied = [usage[@"effort"] length] ? usage[@"effort"] : nil;
    NSString *effort = desktop[@"effort"] ?: replied ?: FlagValue(args, @"--effort");
    if (!effort && model) {  // keyed by the exact model, e.g. claude-opus-5 (Opus 5) apart from claude-opus-5-5
        NSString *canonical = [model componentsSeparatedByString:@"["].firstObject;  // drop "[1m]"
        NSDictionary *perModel = settings[@"modelSettings"][canonical];
        if ([perModel isKindOfClass:NSDictionary.class]) effort = perModel[@"effortLevel"];
    }
    effort = effort ?: settings[@"effortLevel"];
    // A change made in the panel shows at once, until a source above has caught up: Claude Desktop's record the
    // next time Claude saves it, and in a terminal the hook's mode with the session's next event, and the model and
    // effort with its next reply.
    double hookAt = MAX(MAX(row.stageAt.doubleValue, row.activityAt.doubleValue),
                        MAX(row.lastPromptAt.doubleValue, row.lastReplyAt.doubleValue));
    double savedAt = [desktop[@"at"] doubleValue];
    double modeSeen = desktop ? savedAt : MAX(hookAt, [transcript[@"modeAt"] doubleValue]);
    double modelSeen = desktop ? savedAt : TimestampMs(usage[@"at"]);
    double effortSeen = desktop ? savedAt : replied ? TimestampMs(usage[@"at"]) : 0;
    if (chosen[@"mode"] && modeSeen < [chosen[@"modeAt"] doubleValue]) mode = chosen[@"mode"];
    if (chosen[@"model"] && modelSeen < [chosen[@"modelAt"] doubleValue]) model = chosen[@"model"];
    if (chosen[@"effort"] && effortSeen < [chosen[@"effortAt"] doubleValue]) effort = chosen[@"effort"];
    // Where auto-compact kicks in, if it's set (/autocompact): per model, else for all of them.
    NSString *canonical = [model componentsSeparatedByString:@"["].firstObject;
    NSDictionary *perModel = [settings[@"modelSettings"] isKindOfClass:NSDictionary.class]
        ? settings[@"modelSettings"][canonical ?: @""] : nil;
    id compactWindow = [perModel isKindOfClass:NSDictionary.class] ? perModel[@"autoCompactWindow"] : nil;
    if (![compactWindow isKindOfClass:NSNumber.class]) compactWindow = settings[@"autoCompactWindow"];
    row.agent = @{@"mode": mode, @"model": model ?: @"", @"effort": effort ?: @"",
                      @"tokens": usage[@"tokens"] ?: @0,
                      @"compactWindow": [compactWindow isKindOfClass:NSNumber.class] ? compactWindow : @0};
}

// The flags a session's process was started with, looked up once per process. A lookup that fails is
// tried again next time rather than remembered as "no flags".
- (NSArray<NSString *> *)argumentsOf:(Row *)row {
    pid_t pid = row.pid;
    if (pid <= 0) return @[];
    NSString *key = ProcessKey(row.pid, row.procStart);
    NSArray *args = self.processArgs[key];
    if (!args) {
        args = ProcessArguments(pid);
        if (args.count) self.processArgs[key] = args;
    }
    return args;
}

- (void)keepFlagsOf:(NSArray<Row *> *)rows {
    NSMutableSet *running = [NSMutableSet set];
    for (Row *row in rows) [running addObject:ProcessKey(row.pid, row.procStart)];
    for (NSString *key in self.processArgs.allKeys)
        if (![running containsObject:key]) [self.processArgs removeObjectForKey:key];
}

// ~/.claude/settings.json, re-read only when it changes. Every row asks for it on every tick, so whether it has
// changed is looked at no more than twice a second.
- (NSDictionary *)userSettings {
    NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
    if (self.settingsCache && now - self.settingsCheckedAt < 0.5) return self.settingsCache[@"settings"];
    self.settingsCheckedAt = now;
    NSString *path = ClaudeDir(kClaudeCodeSettings);
    NSDate *mtime = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil].fileModificationDate;
    if (!self.settingsCache || ![self.settingsCache[@"mtime"] isEqual:mtime]) {
        NSDictionary *settings = ReadJSON(path);
        self.settingsCache = @{@"mtime": mtime ?: NSDate.distantPast,
                               @"settings": [settings isKindOfClass:NSDictionary.class] ? settings : @{}};
    }
    return self.settingsCache[@"settings"];
}

// The Shift+Tab cycles this session could have. Claude Code's runs default → acceptEdits → plan, then the
// optional modes, bypassPermissions and auto, and back to default.
// - Bypass is in it only for a session started with --dangerously-skip-permissions,
//   --allow-dangerously-skip-permissions or --permission-mode bypassPermissions, or with bypass as the default
//   mode in the user's settings or the machine's managed settings (and not disabled there). A session in bypass
//   now has it whatever started it.
// - Auto is in it only where the account, the model and the settings allow it, and Anthropic can turn it off
//   too, none of which shows from outside. So it's certain only while the session is in auto mode, and ruled
//   out by a settings file that disables it. Having been in auto earlier proves nothing: a /model switch can
//   take it away. Otherwise both cycles are possible, and both come back.
- (NSArray<NSArray<NSString *> *> *)modeCyclesFor:(Row *)row {
    NSArray *args = [self argumentsOf:row];
    NSDictionary *managedSettings = ReadJSON(MachineFile(kClaudeCodeManagedSettings));
    if (![managedSettings isKindOfClass:NSDictionary.class]) managedSettings = @{};
    NSDictionary *mine = [self userSettings][@"permissions"], *managed = managedSettings[@"permissions"];
    if (![mine isKindOfClass:NSDictionary.class]) mine = nil;
    if (![managed isKindOfClass:NSDictionary.class]) managed = nil;
    BOOL bypass = [args containsObject:@"--dangerously-skip-permissions"]
               || [args containsObject:@"--allow-dangerously-skip-permissions"]
               || [FlagValue(args, @"--permission-mode") isEqual:@"bypassPermissions"]
               || [mine[@"defaultMode"] isEqual:@"bypassPermissions"]
               || [managed[@"defaultMode"] isEqual:@"bypassPermissions"];
    if ([mine[@"disableBypassPermissionsMode"] isEqual:@"disable"]
        || [managed[@"disableBypassPermissionsMode"] isEqual:@"disable"])
        bypass = NO;
    if ([row.agent[@"mode"] isEqual:@"bypassPermissions"]) bypass = YES;
    NSArray *cycle = bypass ? @[@"default", @"acceptEdits", @"plan", @"bypassPermissions"]
                            : @[@"default", @"acceptEdits", @"plan"];
    NSArray *withAuto = [cycle arrayByAddingObject:@"auto"];
    if ([row.agent[@"mode"] isEqual:@"auto"]) return @[withAuto];  // in it now, whatever a setting says
    if ([self autoModeDisabledFor:row managedSettings:managedSettings]) return @[cycle];
    return @[withAuto, cycle];
}

// Whether a settings file turns auto mode off for this session: the user's, its project's, or the machine's
// managed settings.
- (BOOL)autoModeDisabledFor:(Row *)row managedSettings:(NSDictionary *)managedSettings {
    NSMutableArray *files = [@[[self userSettings] ?: @{}, managedSettings ?: @{}] mutableCopy];
    NSString *cwd = row.cwd;
    if ([cwd isKindOfClass:NSString.class] && cwd.isAbsolutePath)
        for (NSString *name in @[@".claude/settings.json", @".claude/settings.local.json"])
            [files addObject:ReadJSON([cwd stringByAppendingPathComponent:name]) ?: @{}];
    for (NSDictionary *settings in files) {
        if (![settings isKindOfClass:NSDictionary.class]) continue;
        id permissions = settings[@"permissions"];
        if ([settings[@"disableAutoMode"] isEqual:@"disable"]
            || ([permissions isKindOfClass:NSDictionary.class] && [permissions[@"disableAutoMode"] isEqual:@"disable"]))
            return YES;
    }
    return NO;
}

static NSInteger ShiftTabs(NSString *from, NSString *to, NSArray<NSString *> *cycle) {
    NSInteger extra = 0;
    if ([from isEqual:@"dontAsk"]) { from = @"default"; extra = 1; }  // dontAsk's Shift+Tab goes to default
    NSUInteger i = [cycle indexOfObject:from], j = [cycle indexOfObject:to];
    if (i == NSNotFound || j == NSNotFound) return -1;
    return extra + (NSInteger)((j + cycle.count - i) % cycle.count);
}

// How many Shift+Tabs take the session from one mode to another: the same in every cycle it could have, or -1
// when a mode isn't in one of them or the counts differ (a key too many or too few would land it in another mode).
- (NSInteger)shiftTabsFrom:(NSString *)from to:(NSString *)to cycles:(NSArray<NSArray<NSString *> *> *)cycles {
    NSInteger presses = -1;
    for (NSArray *cycle in cycles) {
        NSInteger here = ShiftTabs(from, to, cycle);
        if (here < 0 || (presses >= 0 && here != presses)) return -1;
        presses = here;
    }
    return presses;
}

@end
