// ClaudeCode: the Claude Code module's class, which the core finds and asks for everything Claude Code does.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "ClaudeCode.h"
#import "Core.h"
#import "Page.h"
#import "Row.h"
#import "Text.h"
#import "ClaudeCodeFacts.h"
#import "ClaudeSessions.h"
#import "Transcripts.h"
#import "Writings.h"
#import "Edits.h"
#import "AgentDetails.h"
#import "Asks.h"
#import "SettingsFile.h"
#import "Trust.h"
#import "ClaudeUsage.h"
#import "Prompt.h"
#import "Results.h"

// The words are read from their file as the command runs, so they never pass through your shell's line editor, its
// quoting or its history.
static NSString *StartCommand(NSString *sessionId, NSString *wordsFile) {
    NSString *command = [NSString stringWithFormat:@"%@ --session-id %@", kClaudeCodeCommand, sessionId];
    if (wordsFile) command = [command stringByAppendingFormat:@" \"$(cat %@)\"", ShellWord(wordsFile)];
    return command;
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
@property (assign) NSTimeInterval lastRead;  // when the transcripts were last read
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
    self.queue = dispatch_queue_create("whozmove.claude-code", DISPATCH_QUEUE_SERIAL);
    return self;
}

+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return ClaudeCodePrintModes();
}

- (NSDictionary<NSString *, void (^)(NSDictionary *)> *)messages {
    __weak typeof(self) weakSelf = self;
    return @{
        // A request answered in the panel, for the permission hook to pass on.
        @"answerAsk": ^(NSDictionary *msg) { AnswerAsk(msg); },
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
        case RowPhaseListed: return [self.details keepFlagsOf:rows];
    }
}

// In the first phase, so the reads start as soon as the rows are known: what's new in the listed sessions'
// transcripts, every 10s, and whether Claude Code records shell commands' changes in their folders. What they find
// shows in the rows from a later read on.
- (void)readNewFor:(NSArray<Row *> *)rows {
    self.transcripts.sessionIds = [rows valueForKey:@"sessionId"];
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (now - self.lastRead >= 10) {
        self.lastRead = now;
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

// Never in a print run: what it prints can't depend on this Mac's login.
- (NSDictionary *)askUsage {
    return self.core.printing ? nil : [self.usage ask];
}

- (NSString *)startCommand:(NSString *)sessionId wordsFile:(NSString *)wordsFile {
    return StartCommand(sessionId, wordsFile);
}

- (BOOL)folderTrusted:(NSString *)folder {
    return FolderTrusted(folder);
}

- (NSString *)trustFolder:(NSString *)folder {
    return TrustFolder(folder);
}

@end
