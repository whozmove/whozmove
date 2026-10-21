// ClaudeCode: the Claude Code module's class, which the core finds and asks for everything Claude Code does.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "ClaudeCode.h"
#import "Core.h"
#import "Page.h"
#import "Rows.h"
#import "Row.h"
#import "Files.h"
#import "Log.h"
#import "Processes.h"
#import "Text.h"
#import "ClaudeCodeFacts.h"
#import "ClaudeSessions.h"
#import "Transcripts.h"
#import "Writings.h"
#import "Edits.h"
#import "AgentDetails.h"
#import "Asks.h"
#import "Switches.h"
#import "SettingsFile.h"
#import "Trust.h"
#import "ClaudeUsage.h"
#import "Prompt.h"
#import "Results.h"
#import "KeptSessions.h"
#import "PluginInstall.h"
#import "ClaudeCommand.h"

// The words are read from their file as the command runs, so they never pass through your shell's line editor, its
// quoting or its history.
static NSString *StartCommand(NSString *sessionId, NSString *wordsFile) {
    NSString *command = [NSString stringWithFormat:@"%@ --session-id %@", kClaudeCodeCommand, sessionId];
    if (wordsFile) command = [command stringByAppendingFormat:@" \"$(cat %@)\"", ShellWord(wordsFile)];
    return command;
}

// Run in the session's own folder, where the terminal's new tab opens. Its id is one Claude Code made, a UUID, so it
// goes in as it is.
static NSString *ResumeCommand(NSString *sessionId) {
    return [NSString stringWithFormat:@"%@ %@ %@", kClaudeCodeCommand, kClaudeCodeResumeFlag, sessionId];
}

// Where a command's result will be written: the session's transcript, and how long it was as the command went in.
@interface ResultsMark : NSObject
@property (copy) NSString *path;
@property (assign) unsigned long long from;
@end

@implementation ResultsMark
@end

@interface ClaudeCode ()
@property (weak) Core *core;
@property Transcripts *transcripts;
@property AgentDetails *details;
@property (strong) SettingsFile *settingsFile;
@property (strong) ClaudeUsage *usage;
@property (strong) KeptSessions *kept;  // its terminal sessions, kept so they're listed once they've ended
@property (assign) NSTimeInterval lastRead;  // when the transcripts were last read
@property (copy) NSSet<NSString *> *compacting;  // the sessions its hook recorded compacting as the rows were last read
@property (assign) BOOL readSoon;  // a compaction has ended, so the transcripts are read again once no read is out
// Whether Claude Code is set to record shell commands' changes (ShellDiffSetting), for each folder a listed session
// runs in and for none, as last read on the queue, when that was, and whether a read is out.
@property (strong) dispatch_queue_t queue;
@property (strong) id shellSetting;
@property (strong) NSDictionary<NSString *, id> *shellSettings;
@property (assign) NSTimeInterval settingReadAt;
@property (assign) BOOL readingSettings;
@end

@implementation ClaudeCode

+ (NSString *)moduleName {
    return @"claude-code";
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.transcripts = [Transcripts new];
    self.details = [AgentDetails new];
    self.settingsFile = [SettingsFile new];
    self.usage = [ClaudeUsage new];
    self.kept = [KeptSessions new];
    self.queue = dispatch_queue_create("whozmove.claude-code", DISPATCH_QUEUE_SERIAL);
    return self;
}

// Its terminal sessions are kept from now on: a print run reads what's kept, and never writes any.
- (void)launch {
    [self.kept start];
}

+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return ClaudeCodePrintModes();
}

- (NSDictionary<NSString *, void (^)(NSDictionary *)> *)messages {
    __weak typeof(self) weakSelf = self;
    return @{
        // A request answered in the panel, for the permission hook to pass on.
        @"answerAsk": ^(NSDictionary *msg) { AnswerAsk(msg); },
        // The other copies of a conversation open in more than one terminal, closed from its "open twice" card: the
        // copy its row follows stays. The row's note says how it went.
        @"closeCopy": ^(NSDictionary *msg) {
            NSString *sid = AsText(msg[@"sessionId"]);
            Row *row = sid ? weakSelf.core.rows.byId[sid] : nil;
            if (!row || row.pid <= 0) return;
            NSUInteger closed = 0;
            NSString *why = CloseOtherCopies(sid, row.pid, PendingAsks()[sid] != nil, &closed);
            NSString *done = closed > 1 ? @"Closing the other copies" : @"Closing the other copy";
            PanelLog(@"%@ -> %@", sid, why ?: done);
            if (why) NSBeep();
            [weakSelf.core.page stepNote:sid text:why ?: done quiet:!why];
            [weakSelf.core.rows refresh];
        },
        // One of a session's writings, for the reader.
        @"readWriting": ^(NSDictionary *msg) {
            NSString *sid = msg[@"sessionId"], *wid = msg[@"id"];
            if (![sid isKindOfClass:NSString.class] || ![wid isKindOfClass:NSString.class]) return;
            [weakSelf.transcripts readWriting:wid of:sid done:^(NSDictionary *read) {
                [weakSelf.core.page showWriting:sid id:wid read:read];
            }];
        },
    };
}

#pragma mark The rows

- (void)rows:(NSArray<Row *> *)rows phase:(RowPhase)phase {
    switch (phase) {
        case RowPhaseCheckout: return [self readNewFor:rows];
        case RowPhaseWork: return [self workOf:rows];
        case RowPhaseDetails: return [self detailsOf:rows];
        case RowPhaseListed:
            [self.details keepFlagsOf:rows];
            [self keep:rows];
            return;
    }
}

// Each running terminal session's record, kept so its row stays once it ends: the terminal it runs in, the app above
// it, else the host that says it runs it (an iTerm2 session's app can be gone while it runs on); and its transcript as
// the reads found it, never looked for here among every project's, which would be on the main thread, every second.
- (void)keep:(NSArray<Row *> *)rows {
    __weak typeof(self) weakSelf = self;
    [self.kept keep:rows transcriptOf:^NSString *(Row *row) {
        return [weakSelf.transcripts stateOf:row.sessionId][@"path"];
    } terminalOf:^NSString *(Row *row) {
        return OwningApp(row.pid).bundleIdentifier ?: [weakSelf.core hostOf:row].appId;
    }];
}

// In the first phase, so the reads start as soon as the rows are known: what's new in the listed sessions'
// transcripts, every 10s, and at once when a compaction has just ended, as the context's new size is there; and
// whether Claude Code records shell commands' changes in their folders. What they find shows in the rows from a later
// read on.
- (void)readNewFor:(NSArray<Row *> *)rows {
    self.transcripts.sessionIds = [rows valueForKey:@"sessionId"];
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSMutableSet<NSString *> *compacting = [NSMutableSet set];
    for (Row *row in rows)
        if (row.compacting && row.sessionId) [compacting addObject:row.sessionId];
    if (self.compacting && ![self.compacting isSubsetOfSet:compacting]) self.readSoon = YES;
    self.compacting = compacting;
    // A read still out would skip the session, so the one for a compaction waits for it to come back.
    BOOL soon = self.readSoon && !self.transcripts.reading, timed = now - self.lastRead >= 10;
    if (soon || timed) {
        if (soon) self.readSoon = NO;
        if (timed) self.lastRead = now;
        [self.transcripts readNew];
    }
    [self readSettingSoon:rows];
}

// When each session's conversation last moved, and what it wrote for you to read.
- (void)workOf:(NSArray<Row *> *)rows {
    for (Row *row in rows) {
        NSDictionary *transcript = [self.transcripts stateOf:row.sessionId];
        if (transcript[@"messageAt"]) row.messageAt = transcript[@"messageAt"];
        if ([transcript[@"writings"] count]) row.writings = RowWritings(transcript);
    }
}

// Each session's details, with a pick from the panel the session hasn't confirmed yet.
- (void)detailsOf:(NSArray<Row *> *)rows {
    for (Row *row in rows)
        [self.details describe:row transcript:[self.transcripts stateOf:row.sessionId] chosen:row.chosen];
}

- (BOOL)working {
    return self.transcripts.reading || self.readingSettings;
}

// Whether Claude Code is set to record shell commands' changes, for each folder a listed session runs in, read again
// every few seconds on the queue, not on the main thread.
- (void)readSettingSoon:(NSArray<Row *> *)sessions {
    NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
    if (now - self.settingReadAt < 5) return;
    self.settingReadAt = now;
    self.readingSettings = YES;
    NSMutableSet<NSString *> *projects = [NSMutableSet set];
    for (Row *row in sessions)
        if (row.cwd.length) [projects addObject:row.cwd];
    dispatch_async(self.queue, ^{
        NSMutableDictionary *settings = [NSMutableDictionary dictionary];
        for (NSString *project in projects) {
            id setting = ShellDiffSetting(project);
            if (setting) settings[project] = setting;
        }
        id mine = ShellDiffSetting(nil);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.shellSettings = settings;
            self.shellSetting = mine;
            self.readingSettings = NO;
        });
    });
}

// The setting for a session in `project`: its own, read last time, or else the one with no project's.
- (id)settingFor:(NSString *)project {
    return (project ? self.shellSettings[project] : nil) ?: self.shellSetting;
}

#pragma mark Agent

- (NSString *)name {
    return @"Claude Code";
}

- (NSArray<Row *> *)readSessions {
    return RunningSessions();
}

- (NSArray<Row *> *)readEndedSessions:(NSArray<Row *> *)listed {
    return [self.kept endedBesides:listed];
}

- (void)addRecordTo:(Row *)row {
    AddHookRecord(row);
}

- (void)addRequestsTo:(NSArray<Row *> *)rows {
    NSDictionary *asks = PendingAsks();
    for (Row *row in rows)
        if (row.sessionId && asks[row.sessionId]) row.ask = asks[row.sessionId];
}

// Its transcript's topic, which Claude Code also puts in its terminal tab's title ("✳ <topic>").
- (NSString *)titleOf:(Row *)row now:(BOOL)now {
    return now ? [self.transcripts topicOf:row.sessionId] : [self.transcripts lastTopicOf:row.sessionId];
}

- (BOOL)titleShowsWork:(NSString *)title {
    return title.length && [[NSCharacterSet characterSetWithCharactersInString:kClaudeCodeTitleWorking]
                               characterIsMember:[title characterAtIndex:0]];
}

- (NSArray<NSString *> *)environmentMarks {
    return [kClaudeCodeAgentMarks componentsSeparatedByString:@" "];
}

#pragma mark Work

- (NSDictionary<NSString *, NSDictionary *> *)prLinksOf:(NSString *)sessionId {
    return [self.transcripts stateOf:sessionId][@"prs"];
}

- (void (^)(void))onPRLinks {
    return self.transcripts.onPRLinks;
}

- (void)setOnPRLinks:(void (^)(void))onPRLinks {
    self.transcripts.onPRLinks = onPRLinks;
}

- (NSDictionary *)editsOf:(Row *)row {
    NSDictionary *t = [self.transcripts stateOf:row.sessionId];
    return @{@"files": t[@"edits"] ?: @{}, @"count": @([t[@"editIds"] count]),
             @"known": @(SessionKnown(t, [self settingFor:row.cwd])), @"failed": t[@"shellFailed"] ?: @0,
             @"doubts": t[@"shellDoubts"] ?: @[]};
}

#pragma mark Commands

- (NSArray<NSArray<NSString *> *> *)choicesFor:(NSString *)field {
    return [field isEqual:@"model"] ? ModelChoices() : [field isEqual:@"effort"] ? EffortChoices() : ModeChoices();
}

// The only mode a slash command sets is Plan; the others are Shift+Tab presses in a terminal.
- (NSString *)commandSetting:(NSString *)field to:(NSString *)value {
    if ([field isEqual:@"mode"]) return [value isEqual:@"plan"] ? @"/plan" : nil;
    return [NSString stringWithFormat:@"/%@ %@", field, value];
}

- (NSString *)compactCommand:(NSString *)focus {
    return focus.length ? [@"/compact " stringByAppendingString:focus] : @"/compact";
}

- (NSArray<NSArray<NSString *> *> *)modeCyclesFor:(Row *)row {
    return [self.details modeCyclesFor:row];
}

- (NSInteger)shiftTabsFrom:(NSString *)from to:(NSString *)to cycles:(NSArray<NSArray<NSString *> *> *)cycles {
    return [self.details shiftTabsFrom:from to:to cycles:cycles];
}

- (id)markResultsOf:(NSString *)sessionId {
    NSString *path = [self.transcripts pathOf:sessionId];
    if (!path) return nil;
    ResultsMark *mark = [ResultsMark new];
    mark.path = path;
    mark.from = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil].fileSize;
    return mark;
}

- (NSString *)resultOf:(NSString *)command since:(ResultsMark *)mark {
    return mark ? CommandResult(mark.path, mark.from, command) : nil;
}

- (NSString *)resultApplies:(NSString *)field value:(NSString *)value result:(NSString *)result {
    return ResultApplies(field, value, result);
}

- (BOOL)resultSavedDefault:(NSString *)result {
    return ResultSavedDefault(result);
}

- (NSString *)compactNote:(NSString *)result {
    return CompactNote(result);
}

- (void)holdDefaults:(NSString *)field {
    [self.settingsFile holdDefaults:field];
}

- (void)releaseDefaults:(NSString *)field saved:(BOOL)saved {
    [self.settingsFile releaseDefaults:field saved:saved];
}

- (void)noteSwitchOf:(NSString *)sessionId to:(NSString *)model {
    NoteSwitch(sessionId, model);
}

- (BOOL)asksSwitchInPanel:(Row *)row {
    return row.pid > 0 && SessionAsksSwitches(row.pid);
}

- (NSDictionary *)switchAskedIn:(NSString *)sessionId {
    return SwitchQuestion(sessionId);
}

- (void)answerSwitchIn:(NSString *)sessionId allow:(BOOL)allow {
    AnswerSwitch(sessionId, allow);
}

#pragma mark Prompt

- (BOOL)hasStarted:(NSString *)sessionId {
    return [self.transcripts pathOf:sessionId] != nil;
}

- (Reason *)whyNotTypeInto:(NSString *)sessionId pid:(pid_t)pid {
    return WhyNotTypeInto(sessionId, pid);
}

- (Reason *)whyNotEditDraft:(NSString *)sessionId pid:(pid_t)pid {
    return WhyNotEditDraft(sessionId, pid);
}

- (void)type:(NSString *)command into:(id<TypingHost>)terminal tab:(NSString *)tab whyNot:(Reason *(^)(void))whyNot
        done:(void (^)(Reason *why, NSUInteger typed, NSUInteger steps))done {
    TypeCommand(terminal, tab, command, whyNot, done);
}

- (void)deleteFillerIn:(id<TypingHost>)terminal tab:(NSString *)tab {
    DeleteFiller(terminal, tab);
}

#pragma mark Usage and starts

// Never in a print run: what it prints can't depend on this Mac's login. Nor before Apple's developer tools are
// installed: claude may run git, which offers to install them each time until they are, so until then it's as if
// there were no claude to ask.
- (NSDictionary *)askUsage {
    if (self.core.printing) return nil;
    return DeveloperToolsReady() ? [self.usage ask] : @{@"state": @"none"};
}

- (NSString *)startCommand:(NSString *)sessionId wordsFile:(NSString *)wordsFile {
    return StartCommand(sessionId, wordsFile);
}

- (NSString *)resumeCommand:(NSString *)sessionId {
    return [sessionId isKindOfClass:NSString.class] && [[NSUUID alloc] initWithUUIDString:sessionId]
        ? ResumeCommand(sessionId) : nil;
}

- (BOOL)folderTrusted:(NSString *)folder {
    return FolderTrusted(folder);
}

- (NSString *)trustFolder:(NSString *)folder {
    return TrustFolder(folder);
}

#pragma mark Its hooks

// Never in a print run, where what it prints can't depend on this Mac's Claude Code: the print mode runs it with a
// stand-in claude instead (--print-plugin-install).
- (NSDictionary *)connect:(NSString *)answer before:(BOOL)before from:(NSString *)hooks {
    if (self.core.printing) return nil;
    return ConnectPlugin(answer, before, hooks, LoginPath());
}

- (BOOL)onThisMac {
    return ClaudeCodeOnThisMac();
}

- (NSURL *)installPage {
    return [NSURL URLWithString:kClaudeCodeInstallPage];
}

// Its settings on the panel's back are on Claude's page, which the app that keeps its sessions as conversations of its
// own (Claude Desktop) lists on every Mac, with the rest of Claude's; nil without one.
- (NSString *)appId {
    return [[self.core hostsThat:@protocol(ConversationHost)].firstObject appId];
}

@end
