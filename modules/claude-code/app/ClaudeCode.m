// ClaudeCode: the Claude Code module's class, which the core finds and asks for everything Claude Code does.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Background.h"
#import "ClaudeCode.h"
#import "Core.h"
#import "Page.h"
#import "Rows.h"
#import "Row.h"
#import "Work.h"
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
#import "DontWait.h"
#import "HookLine.h"
#import "Allowed.h"
#import "SettingsFile.h"
#import "Trust.h"
#import "ClaudeUsage.h"
#import "Prompt.h"
#import "Results.h"
#import "Conversations.h"
#import "KeptSessions.h"
#import "PluginInstall.h"
#import "ClaudeCommand.h"
#import "AnswerFor.h"
#import "Records.h"
#import "BetweenSteps.h"
#import "ClaudeAside.h"
#import "ClaudeProgram.h"
#import "WhereSeenWorking.h"

// The words are read from their file as the command runs, so they never pass through your shell's line editor, its
// quoting or its history.
static NSString *StartCommand(NSString *sessionId, NSString *wordsFile) {
    NSString *command = [NSString stringWithFormat:@"%@ --session-id %@", kClaudeCodeCommand, sessionId];
    if (wordsFile) command = [command stringByAppendingFormat:@" \"$(cat %@)\"", ShellWord(wordsFile)];
    return command;
}

// Run in the session's own folder, where the terminal's new tab opens. Its id is one Claude Code made, a UUID, so it
// goes in as it is.
static NSString *ResumeCommand(NSString *sessionId, NSString *wordsFile) {
    NSString *command = [NSString stringWithFormat:@"%@ %@ %@", kClaudeCodeCommand, kClaudeCodeResumeFlag, sessionId];
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
@property (strong) KeptSessions *kept;  // its terminal sessions, kept so they're listed once they've ended
// The sessions whose row had a `wait` as the rows were last listed, noted in the first phase, before the rows read now
// take their place; nil until they've been listed once.
@property (copy) NSSet<NSString *> *waitedAsListed;
@property (strong) BetweenSteps *betweenSteps;  // your words held for its sessions' words hook
@property (strong) ClaudeAside *aside;  // questions asked on its sessions' side, while each is answered
// Whether each session can be asked on the side, as last found, with when (on the main thread only): found again only
// every few seconds, as the side chat asks of every listed session as the rows are read.
@property (strong) NSMutableDictionary<NSString *, NSArray *> *asideWhy;
@property (assign) NSTimeInterval claudeLookedAt;
@property (assign) BOOL claudeHere;
// Whether each session's process runs the words hook, by its pid and start, with when a no was found: a yes holds for
// the process's life, as the hooks it runs are fixed as it starts; a no is asked again after a while.
@property (strong) NSMutableDictionary<NSString *, NSArray *> *takesWords;
// Each session's own process, and where it was seen working, for who may speak for it.
@property (strong) WhereSeenWorking *whereSeen;
@property (strong) Conversations *conversationList;  // every conversation it keeps, for Sessions
@property (strong) AnswerFor *answerFor;  // what a session you allow answers for you in a team member's
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
    self.betweenSteps = [BetweenSteps new];
    self.aside = [ClaudeAside new];
    self.asideWhy = [NSMutableDictionary dictionary];
    self.takesWords = [NSMutableDictionary dictionary];
    self.conversationList = [Conversations new];
    __weak typeof(self) weakSelf = self;
    ClaudeProgram (^programOf)(pid_t) = ^ClaudeProgram(pid_t pid) { return [weakSelf programOf:pid]; };
    self.whereSeen = [[WhereSeenWorking alloc] initWithProgram:programOf];
    self.answerFor = [[AnswerFor alloc] initWithCore:core program:programOf mayBe:^BOOL(NSString *name) {
        if (ClaudeProgramMayBe(name, nil)) return YES;
        for (NSString *standIn in weakSelf.standIns)
            if (ClaudeProgramMayBe(name, standIn)) return YES;
        return NO;
    }];
    self.answerFor.bypassWhy = ^NSString *(Row *row, pid_t process) {
        return [weakSelf.details whyBypassPossible:row process:process];
    };
    self.queue = dispatch_queue_create("whozmove.claude-code", DISPATCH_QUEUE_SERIAL);
    [HookLine shared].printing = core.printing;
    return self;
}

// Its terminal sessions are kept from now on, and what the reads find in its transcripts, written once more as Whozmove
// quits (a restart's stop too): a print run reads what's kept, and never writes any. Its hooks' requests are taken over
// their line from now on, each only from a process that runs in the session it names (walked up to one the registry
// lists). And Don't Wait on Me's file goes for each session without the switch.
- (void)launch {
    // Every module's own asks that wait in the background, so its row doesn't list one as the session's work.
    KeepOwnWaits([self.core modulesThat:@protocol(BackgroundWaits)]);
    [self.kept start];
    [self.transcripts keepIn:ReadsFolder()];
    Transcripts *transcripts = self.transcripts;
    ClaudeAside *aside = self.aside;
    // A side question still being answered goes with Whozmove: nothing of it is left running.
    [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationWillTerminateNotification object:nil
                                                     queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification *note) {
        [transcripts keepNow];
        [aside stopAll];
    }];
    [[HookLine shared] listenAt:AppDir(@"hook.sock") sessionOf:^NSString *(pid_t pid) {
        return SessionAbove(pid, NULL);
    }];
    // The words hook's asks: held words handed to it, only for its own session's process (BetweenSteps).
    [self.betweenSteps start];
    BetweenSteps *betweenSteps = self.betweenSteps;
    [HookLine shared].wordsFor = ^NSString *(NSString *sessionId, pid_t hookPid, NSString *event) {
        return [betweenSteps handOver:sessionId hookPid:hookPid event:event];
    };
    [self dropDontWaitWithoutSwitch];
}

// The hook goes by Don't Wait on Me's file, and the menu by the switch's record, so a file left without its record
// (taken away while Whozmove wasn't running, say) is taken away too: a session never goes on not waiting on you while
// its menu shows the switch off.
- (NSArray<NSString *> *)dropDontWaitWithoutSwitch {
    Allowed *allowed = self.core.allowed;
    NSArray<NSString *> *dropped = DropFilesWithoutSwitch(^BOOL(NSString *sessionId) {
        return [allowed has:kDontWaitKey session:sessionId];
    });
    for (NSString *sessionId in dropped)
        PanelLog(@"%@ -> Don't Wait on Me's file taken away, as the switch is off", sessionId);
    return dropped;
}

+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return ClaudeCodePrintModes();
}

- (NSDictionary<NSString *, void (^)(NSDictionary *)> *)messages {
    __weak typeof(self) weakSelf = self;
    return @{
        // A request answered in the panel, for the permission hook to pass on.
        @"answerAsk": ^(NSDictionary *msg) { AnswerAsk(msg); },
        // A request being answered in the panel: kept from a session you allow, and one that goes by itself if no
        // one answers held off a while longer.
        @"holdAsk": ^(NSDictionary *msg) { if (ActiveAtTheMac()) HoldAsk(AsText(msg[@"id"])); },
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
        case RowPhaseCheckout:
            [self noteWaitsAsListed];
            return [self readNewFor:rows];
        case RowPhaseWork:
            [self workOf:rows];
            [self.answerFor markRows:rows];
            return;
        case RowPhaseDetails: return [self detailsOf:rows];
        case RowPhaseListed:
            [self.details keepFlagsOf:rows];
            [self keep:rows];
            return;
    }
}

// Each second, a request is held while you're in its session's tab, at the Mac and using it, as the last read found
// you there: kept from a session you allow, and one that goes by itself if no one answers held off.
- (void)tick {
    if (self.core.printing) return;
    [[HookLine shared] keepListening];
    for (NSString *askId in AsksToHold(self.core.rows.byId.allValues, NSDate.date.timeIntervalSince1970 * 1000,
                                              SecondsIdle()))
        HoldAsk(askId);
}

// Each running terminal session's record, kept so its row stays once it ends: the terminal it runs in, the app above
// it, else the host that says it runs it (an iTerm2 session's app can be gone while it runs on); its transcript as
// the reads found it, never looked for here among every project's, which would be on the main thread, every second;
// and whether its row, as the rows were last listed, had a `wait` (docs/reference/rows.md), as noted in the first
// phase (noteWaitsAsListed): nothing until the rows have been listed once.
- (void)keep:(NSArray<Row *> *)rows {
    __weak typeof(self) weakSelf = self;
    NSSet<NSString *> *waited = self.waitedAsListed;
    [self.kept keep:rows transcriptOf:^NSString *(Row *row) {
        return [weakSelf.transcripts stateOf:row.sessionId][@"path"];
    } terminalOf:^NSString *(Row *row) {
        return OwningApp(row.pid).bundleIdentifier ?: [weakSelf.core hostOf:row].appId;
    } waits:waited ? ^BOOL(Row *row) { return row.sessionId && [waited containsObject:row.sessionId]; } : nil];
}

// The rows are read afresh each time, and the waits module puts each one's `wait` on it in the last phase, after this
// module's, which goes by its name; so which had one is read in the first phase, while the rows listed last are still
// the core's, every module's part on them.
- (void)noteWaitsAsListed {
    NSDictionary<NSString *, Row *> *listed = self.core.rows.byId;
    if (!listed) return;
    NSMutableSet<NSString *> *waited = [NSMutableSet set];
    for (NSString *sessionId in listed)
        if (listed[sessionId].wait) [waited addObject:sessionId];
    self.waitedAsListed = waited;
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
    NSMutableArray<id<Host>> *untracked = [NSMutableArray array];
    for (id<ConversationHost> host in [self.core hostsThat:@protocol(ConversationHost)])
        if (!host.tracked) [untracked addObject:host];
    __weak Core *core = self.core;
    NSArray<Row *> *rows = RunningSessions(untracked.count ? ^BOOL(Row *copy) {
        id<Host> host = [core hostOf:copy];
        return host && [untracked containsObject:host];
    } : nil);
    [self.whereSeen note];
    return rows;
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
    return @{@"files": t[@"edits"] ?: @{}, @"count": @([t[@"editIds"] count]), @"version": t[@"editsVersion"] ?: @0,
             @"known": @(SessionKnown(t, [self settingFor:row.cwd])), @"failed": t[@"shellFailed"] ?: @0,
             @"doubts": t[@"shellDoubts"] ?: @[]};
}

- (void)replyTo:(NSString *)prompt of:(NSString *)sessionId since:(double)since done:(void (^)(NSString *reply))done {
    [self.transcripts replyTo:prompt of:sessionId since:since done:done];
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

// Only a session whose hooks ask over their line gets the panel's note of a switch: an older hook would take it, then
// wait a minute for an answer the panel no longer gives, while Claude's own question waits behind it. Without the note,
// it says nothing, and Claude asks at once.
- (void)noteSwitchOf:(NSString *)sessionId to:(NSString *)model {
    Row *row = self.core.rows.byId[sessionId];
    if (model.length && !(row.pid > 0 && SessionHasHookPart(row.pid, HookPartHookLine, !self.core.printing))) return;
    NoteSwitch(sessionId, model);
}

- (BOOL)asksSwitchInPanel:(Row *)row {
    return row.pid > 0 && SessionHasHookPart(row.pid, HookPartSwitches, !self.core.printing)
        && SessionHasHookPart(row.pid, HookPartHookLine, !self.core.printing);
}

- (NSDictionary *)switchAskedIn:(NSString *)sessionId {
    return SwitchQuestion(sessionId);
}

- (void)answerSwitchIn:(NSString *)sessionId allow:(BOOL)allow {
    AnswerSwitch(sessionId, allow);
}

#pragma mark What sessions may do

// Don't Wait on Me, at the foot of a terminal session's mode menu (Claude Desktop's conversations ask in Claude's own
// window, which no hook can answer for): a question or a request for your OK that no one answers in a few minutes goes
// by itself, so the session carries on. It lasts for the conversation, as its id is what the hook goes by. Only a
// running session's hooks can make a request go by itself, and only hooks it started with: Claude Code gives a session
// the hooks it had as it started.
- (NSArray<SessionSwitch *> *)sessionSwitches {
    __weak typeof(self) weakSelf = self;
    SessionSwitch *dontWait = [SessionSwitch switchWithKey:kDontWaitKey title:@"Don't Wait on Me"
                                                      line:DontWaitSays(kDontWaitMinutes)
                                                     lasts:SwitchLastsConversation];
    dontWait.shown = ^BOOL(Row *row) { return ![weakSelf.core hostHolding:row]; };
    dontWait.whyNot = ^NSString *(Row *row) {
        if (row.pid <= 0) return @"Can be turned on while the session runs";
        if (!SessionHasHookPart(row.pid, HookPartDontWait, !weakSelf.core.printing))
            return @"Works in sessions started after Whozmove's last update: start this one again to use it";
        return nil;
    };
    // The hook's own file, which it reads as each request comes in.
    dontWait.changed = ^(NSString *sessionId, BOOL on) {
        if (!SetStopsWaiting(sessionId, on)) PanelLog(@"%@ -> Don't Wait on Me's file not changed", sessionId);
    };
    return [@[dontWait] arrayByAddingObjectsFromArray:self.answerFor.switches];
}

// What a session you allow asks the panel, to answer for you in a team member's session.
- (NSDictionary<NSString *, SessionAsk *> *)sessionAsks {
    return self.answerFor.asks;
}

- (NSArray<Notice *> *)notices {
    return self.answerFor.notices;
}

// The stand-in programs a print run's sample sessions run, by their paths (WHOZMOVE_STAND_IN_CLAUDE, parted by colons),
// counted as Claude Code's own: in a print run only, never in the panel you're using.
- (NSArray<NSString *> *)standIns {
    if (!self.core.printing) return @[];
    NSString *given = NSProcessInfo.processInfo.environment[@"WHOZMOVE_STAND_IN_CLAUDE"];
    return given.length ? [given componentsSeparatedByString:@":"] : @[];
}

- (ClaudeProgram)programOf:(pid_t)pid {
    ClaudeProgram program = ClaudeProgramOf(pid, nil);
    for (NSString *standIn in self.standIns)
        if (program == ClaudeProgramNone) program = ClaudeProgramOf(pid, standIn);
    return program;
}

- (NSString *)sessionOfProcess:(pid_t)pid {
    return SessionOfProcess(pid);
}

// Only Claude Code's own build, signed by Anthropic, asks in a session's name: anything running as you can write a
// session's record in the registry, but not that signature.
- (NSString *)whyNotAsker:(pid_t)pid {
    return ClaudeProgramWhyNot(pid, [self programOf:pid]);
}

// A process that has its session's record and Claude Code's program may still not be that session: one can rewrite its
// record to say it's any session. WhereSeenWorking says which process is the session's own.
- (NSString *)whyNot:(Row *)row speakFrom:(pid_t)process {
    return [self.whereSeen whyNot:row speakFrom:process];
}

#pragma mark Records

- (NSArray<NSDictionary *> *)records {
    return ClaudeRecords();
}

- (NSDictionary *)about:(NSString *)path line:(NSDictionary *)line {
    return ClaudeRecordAbout(path, line);
}

- (NSString *)clearCommandFor:(NSString *)folder {
    return ClaudeClearCommand(folder);
}

#pragma mark Between steps

// A session runs the words hook once it started after the hook went in (HookPartBetweenSteps): asked of the hooks'
// files once for a process that does, and every half minute for one that doesn't, rather than every second.
- (BOOL)takesWordsBetweenSteps:(Row *)row {
    if (row.pid <= 0) return NO;
    NSString *key = [NSString stringWithFormat:@"%d %@", row.pid, row.procStart ?: @""];
    NSArray *known = self.takesWords[key];
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (known && ([known[0] boolValue] || now - [known[1] doubleValue] < 30)) return [known[0] boolValue];
    BOOL takes = SessionHasHookPart(row.pid, HookPartBetweenSteps, !self.core.printing);
    if (self.takesWords.count > 500) [self.takesWords removeAllObjects];
    self.takesWords[key] = @[@(takes), @(now)];
    return takes;
}

- (BOOL)startedBeforeBetweenSteps:(Row *)row {
    return row.pid > 0 && HookPartInPlace(HookPartBetweenSteps) && ![self takesWordsBetweenSteps:row];
}

- (NSString *)betweenStepsLine {
    return kBetweenStepsLine;
}

- (void)holdWords:(NSString *)words for:(Row *)row id:(NSString *)wordsId {
    [self.betweenSteps hold:words session:row.sessionId pid:row.pid id:wordsId];
}

- (BOOL)takeBackWords:(NSString *)wordsId {
    return [self.betweenSteps takeBack:wordsId];
}

// Once its hook has taken them, the words are read when the transcript records them taken in (AfterHandedWords), with
// what Claude wrote after them, from a little before they were handed, for the session's own clock.
- (void)wordsState:(NSString *)wordsId row:(Row *)row done:(void (^)(NSDictionary *state))done {
    NSDictionary *handed = [self.betweenSteps handed:wordsId];
    if (!handed || !row) return done(nil);
    NSString *how = [handed[@"event"] isEqual:@"Stop"] ? @"turnEnd" : @"step";
    [self.transcripts afterWords:handed[@"words"] of:row.sessionId since:[handed[@"at"] doubleValue] - 2000
                            done:^(NSDictionary *found) {
        if (!found) return done(@{@"state": @"handed", @"at": handed[@"at"]});
        NSMutableDictionary *state = [@{@"state": @"read", @"how": how, @"at": found[@"at"],
                                        @"turnEnded": found[@"turnEnded"] ?: @NO} mutableCopy];
        if (found[@"reply"]) state[@"reply"] = found[@"reply"];
        done(state);
    }];
}

- (void)forgetWords:(NSString *)wordsId {
    [self.betweenSteps forget:wordsId];
}

#pragma mark Conversations

- (NSArray<NSDictionary *> *)conversations {
    return [self.conversationList all];
}

- (NSArray<NSString *> *)filesOfConversation:(NSString *)conversationId {
    return ConversationFiles(conversationId);
}

// Your typed prompts are kept apart, in history.jsonl, which Sessions never touches.
- (NSString *)whatStaysOfConversations {
    return @"Your typed prompts stay in Claude Code's history.";
}

- (BOOL)isPlaceOfConversation:(NSString *)path {
    return IsConversationPlace(path);
}

- (BOOL)conversationIsOpen:(NSString *)conversationId {
    BOOL open = NO;
    WhyNotEndConversation(conversationId, &open);
    return open;
}

// Its agents at work in the background hold it too: the registry says idle while they run.
- (NSString *)whyNotEnd:(NSString *)conversationId {
    BOOL open = NO;
    NSString *why = WhyNotEndConversation(conversationId, &open);
    if (!why && open && [self agentsAtWorkIn:conversationId]) why = @"Its agents are still at work";
    return why;
}

- (BOOL)agentsAtWorkIn:(NSString *)conversationId {
    Row *row = self.core.rows.byId[conversationId];
    return row && BackgroundAtWork(row);
}

// Each of its processes sent SIGTERM, then waited for, a tenth of a second at a time, for up to kClaudeCodeEndWait: off
// the module's own queue, which this would hold up meanwhile.
- (void)endConversation:(NSString *)conversationId done:(void (^)(NSString *why))done {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *why = [self agentsAtWorkIn:conversationId] ? @"Its agents are still at work" : nil;
        NSArray<NSNumber *> *ending = why ? nil : EndConversation(conversationId, &why);
        for (int waited = 0; ending && waited < kClaudeCodeEndWait * 10; waited++) {
            BOOL left = NO;
            for (NSNumber *pid in ending) if (kill(pid.intValue, 0) == 0) left = YES;
            if (!left) break;
            usleep(100000);
        }
        BOOL open = NO;
        if (!why) WhyNotEndConversation(conversationId, &open);
        if (!why && open) why = @"It didn't end in time: end it in its terminal";
        dispatch_async(dispatch_get_main_queue(), ^{ done(why); });
    });
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
// there were no claude to ask, but said as not ready (`noPlan`), as it isn't missing.
- (NSDictionary *)askUsage {
    if (self.core.printing) return nil;
    return DeveloperToolsReady() ? [self.usage ask] : @{@"state": @"none", @"noPlan": @"notReady"};
}

#pragma mark Asked on the side

// Found without running anything: its command on this Mac (looked for once a minute), a session id it may resume
// (ClaudeAsideResumable: one that isn't a UUID is taken as no conversation, and never asked), and the session's
// conversation where it keeps them (once every 10 seconds for each session). Whether it's signed in is the ask's own
// to find.
- (NSDictionary *)asideWhyNot:(Row *)row {
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (now - self.claudeLookedAt >= 60) {
        self.claudeLookedAt = now;
        self.claudeHere = ClaudeCodeOnThisMac();
    }
    if (!self.claudeHere) return @{@"why": @"noCommand"};
    if (!ClaudeAsideResumable(row.sessionId)) return @{@"why": @"noConversation"};
    NSArray *kept = self.asideWhy[row.sessionId];
    if (kept && now - [kept[0] doubleValue] < 10) return kept[1] == NSNull.null ? nil : kept[1];
    NSString *path = [self.transcripts pathOf:row.sessionId];
    NSDictionary *why = !path || ![NSFileManager.defaultManager fileExistsAtPath:path]
        ? @{@"why": row.lastPromptAt ? @"noConversation" : @"notStarted"} : nil;
    if (self.asideWhy.count > 200) [self.asideWhy removeAllObjects];
    self.asideWhy[row.sessionId] = @[@(now), why ?: NSNull.null];
    return why;
}

// A copy of its conversation, with its model and effort, asked in its own folder (ClaudeAside).
- (NSString *)ask:(NSString *)question aside:(Row *)row done:(void (^)(NSDictionary *answer))done {
    if (self.core.printing || !row.sessionId || !row.cwd.length || [self asideWhyNot:row]) return nil;
    NSDictionary *agent = row.agent;
    NSString *model = ClaudeAsideModel(AsText(agent[@"model"]), FlagValue(ProcessArguments(row.pid), @"--model"),
                                       AsNumber(agent[@"tokens"]).integerValue);
    return [self.aside ask:question running:row.pid > 0 ? ProcessPath(row.pid) : nil sessionId:row.sessionId
                      model:model effort:AsText(agent[@"effort"]) folder:row.cwd done:done];
}

- (void)stopAside:(NSString *)askId {
    [self.aside stop:askId];
}

- (NSString *)startCommand:(NSString *)sessionId wordsFile:(NSString *)wordsFile {
    return StartCommand(sessionId, wordsFile);
}

- (NSString *)resumeCommand:(NSString *)sessionId wordsFile:(NSString *)wordsFile {
    return [sessionId isKindOfClass:NSString.class] && [[NSUUID alloc] initWithUUIDString:sessionId]
        ? ResumeCommand(sessionId, wordsFile) : nil;
}

- (BOOL)folderTrusted:(NSString *)folder {
    return FolderTrusted(folder);
}

- (NSString *)trustFolder:(NSString *)folder {
    return TrustFolder(folder);
}

#pragma mark Voice

// In voice mode the session's own process records, or a SoX recorder it started where it can't.
- (BOOL)takesVoice:(pid_t)pid parent:(pid_t)parent path:(NSString *)path among:(NSArray<Row *> *)rows {
    NSArray<NSString *> *recorders = [kClaudeCodeVoiceRecorders componentsSeparatedByString:@" "];
    BOOL recorder = [recorders containsObject:path.lastPathComponent];
    for (Row *row in rows)
        if (row.pid > 0 && (row.pid == pid || (recorder && row.pid == parent))) return YES;
    return NO;
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

- (NSString *)hooksStamp {
    return self.core.printing ? nil : HooksStamp();
}

- (NSURL *)installPage {
    return [NSURL URLWithString:kClaudeCodeInstallPage];
}

// Its settings on the panel's back are on Claude's page, which the app that keeps its sessions as conversations of its
// own (Claude Desktop) lists on every Mac, with the rest of Claude's; nil without one.
- (NSString *)appId {
    return [[self.core hostsThat:@protocol(ConversationHost)].firstObject appId];
}

// Claude Code loads its plugins as a session's process starts, so one that started before the hooks went in has none of
// them, until it reloads its plugins. One whose hooks have recorded anything since it started has them: hooks taken out
// and put back while it runs keep running in it, from the copy it loaded.
- (BOOL)runsWithoutHooks:(Row *)row since:(NSTimeInterval)since {
    if (row.pid <= 0 || since <= 0) return NO;
    long long started = ProcessStartedAt(row.pid);  // microseconds since 1970
    if (started <= 0 || started / 1e6 >= since) return NO;
    return row.hookRecordedAt.doubleValue < started / 1e6;
}

- (NSString *)reloadCommand {
    return kReloadPluginsCommand;
}

- (NSString *)forcedReloadCommand {
    return kForcedReloadCommand;
}

- (BOOL)reloaded:(NSString *)result {
    return ReloadedResult(result);
}

@end
