// Side chat's face for the core: your words to a session from its side chat, sent through Send (sayBetweenSteps:),
// how far each got kept in a record only you can read until the session's process ends, its replies read by its agent,
// your questions on the side, answered by a copy of its conversation (its agent's AgentAside) and kept in memory only,
// and all of it told to the page (setSideChats).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import "Module.h"
#import "Core.h"
#import "Files.h"
#import "Links.h"
#import "Log.h"
#import "Page.h"
#import "Printing.h"
#import "Processes.h"
#import "Row.h"
#import "Rows.h"
#import "Send.h"
#import "Text.h"
#import "SideChatRecord.h"

@interface SideChatModule : NSObject <Module>
@property (weak) Core *core;
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *records;  // by session, read from disk once
@property (strong) NSMutableDictionary<NSString *, NSString *> *wordsIds;     // Send's ids, by `<session> <at>`
@property (strong) NSMutableDictionary<NSString *, NSArray *> *replies;       // replies read, by `<session> <at>`
@property (strong) NSMutableSet<NSString *> *reading;                         // replies being read now
@property (strong) NSMutableDictionary<NSString *, NSArray *> *asides;        // asked on the side, by session, in memory
@property (strong) NSMutableDictionary<NSString *, NSNumber *> *asideWords;   // the side question words went as, by
                                                                              // `<session> <at>`, in memory
@property (strong) NSMutableDictionary<NSString *, NSArray *> *asks;  // [ask id, its agent], by `<session> <at>`
@property (copy) NSDictionary<NSString *, Row *> *listed;
@property (copy) NSString *told;
- (void)ask:(NSString *)question opening:(NSString *)opening of:(Row *)row sessionId:(NSString *)sessionId
    through:(id<AgentAside>)agent at:(double)at;
@end

// Where the way past "Whozmove needs the Accessibility permission" goes (SideChatAccessibilityWay), which Send can't
// give itself (it's no terminal's): offered under words Claude Desktop couldn't take, wherever the chat is drawn.
static NSString *const kAccessibilitySettings = @"x-apple.systempreferences:com.apple.preference.security?"
                                                 "Privacy_Accessibility";

static NSString *ChatsDir(void) {
    return AppDir(@"side-chat");
}

static NSString *RecordPath(NSString *sessionId) {
    return [ChatsDir() stringByAppendingPathComponent:[sessionId stringByAppendingPathExtension:@"json"]];
}

// Now, in whole milliseconds since 1970.
static double Now(void) {
    return floor(NSDate.date.timeIntervalSince1970 * 1000);
}

static NSString *Key(NSString *sessionId, double at) {
    return [NSString stringWithFormat:@"%@ %.0f", sessionId, at];
}

// Whether the process a record's words were for is still the same one running.
static BOOL ProcessStill(NSDictionary *record) {
    pid_t pid = AsNumber(record[@"pid"]).intValue;
    long long started = AsNumber(record[@"processStart"]).longLongValue;
    return pid > 0 && started && ProcessStartedAt(pid) == started;
}

// Whether a session's chat has gone: its process has ended; or, for a Claude Desktop conversation, which keeps no
// process while it sits idle, it's no longer listed (`listed` nil before the rows are first read keeps it).
static BOOL ChatGone(NSDictionary *record, NSString *sessionId, NSDictionary *listed) {
    if (AsNumber(record[@"pid"]).intValue > 0) return !ProcessStill(record);
    return listed && !listed[sessionId];
}

// Whether a session is at work, asking you something included.
static BOOL Works(Row *row) {
    return [row.status isEqual:@"busy"] || [row.status isEqual:@"waiting"] || row.ask;
}

static int PrintSideChat(SideChatModule *module);

@implementation SideChatModule

+ (NSString *)moduleName {
    return @"side-chat";
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.wordsIds = [NSMutableDictionary dictionary];
    self.replies = [NSMutableDictionary dictionary];
    self.reading = [NSMutableSet set];
    self.asides = [NSMutableDictionary dictionary];
    self.asideWords = [NSMutableDictionary dictionary];
    self.asks = [NSMutableDictionary dictionary];
    return self;
}

#pragma mark - Each session's record

// Every session's record, read from disk the first time it's needed. Words that hadn't gone in when Whozmove last
// stopped are back in your box, as nothing goes in that you can't see.
- (NSMutableDictionary<NSString *, NSDictionary *> *)allRecords {
    if (self.records) return self.records;
    self.records = [NSMutableDictionary dictionary];
    for (NSString *file in [NSFileManager.defaultManager contentsOfDirectoryAtPath:ChatsDir() error:nil]) {
        NSString *sessionId = file.stringByDeletingPathExtension;
        NSDictionary *record = IsPlainId(sessionId, 128) && [file.pathExtension isEqual:@"json"]
            ? AsRecord(ReadJSON(RecordPath(sessionId))) : nil;
        if (!record) continue;
        NSDictionary *restarted = SideChatRecordRestarted(record);
        self.records[sessionId] = record;
        if (restarted != record) [self keep:restarted of:sessionId];
    }
    return self.records;
}

// A session's record, or nil; one whose process has ended is gone, and taken away.
- (NSDictionary *)recordOf:(NSString *)sessionId {
    if (!IsPlainId(sessionId, 128)) return nil;
    NSDictionary *record = self.allRecords[sessionId];
    if (record && ChatGone(record, sessionId, self.listed)) {
        [self forget:sessionId];
        return nil;
    }
    return record;
}

// Kept in a file only you can read, in a folder only you can open, and told to the page.
- (BOOL)keep:(NSDictionary *)record of:(NSString *)sessionId {
    if (!IsPlainId(sessionId, 128)) return NO;
    NSFileManager *files = NSFileManager.defaultManager;
    [files createDirectoryAtPath:ChatsDir() withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700}
                           error:nil];
    // Set each time, so a folder left open to others from before is closed again before anything goes in it.
    [files setAttributes:@{NSFilePosixPermissions: @0700} ofItemAtPath:ChatsDir() error:nil];
    NSData *json = [NSJSONSerialization isValidJSONObject:record]
        ? [NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingSortedKeys error:nil] : nil;
    if (!json || ![json writeToFile:RecordPath(sessionId) atomically:YES]) {
        LogProblem([NSString stringWithFormat:@"side-chat: couldn't keep %@'s chat", sessionId]);
        return NO;
    }
    [files setAttributes:@{NSFilePosixPermissions: @0600} ofItemAtPath:RecordPath(sessionId) error:nil];
    self.allRecords[sessionId] = record;
    [self tell];
    return YES;
}

- (void)forget:(NSString *)sessionId {
    [self forgetAsides:sessionId];
    [self.allRecords removeObjectForKey:sessionId];
    [NSFileManager.defaultManager removeItemAtPath:RecordPath(sessionId) error:nil];
    NSString *prefix = [sessionId stringByAppendingString:@" "];
    for (NSMutableDictionary *byKey in @[self.wordsIds, self.replies, self.asideWords])
        for (NSString *key in [byKey.allKeys copy])
            if ([key hasPrefix:prefix]) [byKey removeObjectForKey:key];
}

#pragma mark - Your words

// Your words to a session, sent through Send: kept held at once, and moved on as Send says how far they've got. A side
// question sent this way (with Send's words, `aside`, when it was asked) goes as the app's own copy of it, never the
// page's words, only while it may (SideChatAsideSendable), and is marked sent in the same step, so a second press is
// refused; it's known by its words until they've gone, so taking them back unsends it.
- (void)send:(NSDictionary *)message {
    NSString *sessionId = AsText(message[@"sessionId"]);
    NSNumber *asideAt = AsNumber(message[@"aside"]);
    NSDictionary *aside = asideAt ? SideChatAsideSendable(self.asides[sessionId], asideAt.doubleValue) : nil;
    if (message[@"aside"] && !aside) return;
    // What goes, with the words that open it where the chat is drawn (One Task's task and step): put back with why
    // when it can't (SideChatToGo).
    NSDictionary *going = SideChatToGo(AsText(message[@"words"]), AsText(message[@"opening"]), aside);
    if (going[@"why"]) return [self notSent:going of:sessionId];
    NSString *words = going[@"words"], *opening = going[@"opening"];
    Row *row = self.listed[sessionId];
    // A Claude Desktop conversation may have no process while it sits idle: its words go into its message box, and its
    // chat goes by its listing alone (pid 0), so it isn't dropped as its process comes and goes.
    BOOL desktop = [row.entrypoint isEqual:@"claude-desktop"];
    long long started = row.pid > 0 && !desktop ? ProcessStartedAt(row.pid) : 0;
    if (!row || (!started && !desktop) || !words.length) return;
    double at = Now();
    if (![self keep:SideChatRecordSaid([self recordOf:sessionId], words, opening, at, started ? row.pid : 0, started)
             of:sessionId]) return;
    PanelLog(@"side-chat: words for %@", sessionId);
    if (asideAt) {
        self.asides[sessionId] = SideChatAsideSent(self.asides[sessionId], asideAt.doubleValue, at);
        self.asideWords[Key(sessionId, at)] = asideAt;
        [self tell];
    }
    [self go:going[@"line"] row:row at:at];
}

- (void)go:(NSString *)words row:(Row *)row at:(double)at {
    NSString *sessionId = row.sessionId;
    __weak typeof(self) weakSelf = self;
    NSString *wordsId = [self.core.send sayBetweenSteps:words row:row progress:^(NSDictionary *said) {
        // Refused for want of the Accessibility permission, with no way past from Send: its pane is the way.
        SessionReach *reach = [said[@"state"] isEqual:@"refused"] ? [weakSelf.core.send reachOf:row] : nil;
        NSDictionary *change = SideChatRefusedWay(said, reach.desktop, reach.mayControl);
        NSDictionary *record = [weakSelf recordOf:sessionId];
        if (record) [weakSelf keep:SideChatRecordProgress(record, at, change) of:sessionId];
        // Words back in your box (refused, or their session ended first) didn't go: their side question, if they were
        // one, is no longer sent.
        if ([SideChatBackStates containsObject:AsText(change[@"state"]) ?: @""])
            [weakSelf unsendAsideOf:sessionId at:at];
    }];
    if (wordsId) self.wordsIds[Key(sessionId, at)] = wordsId;
}

// Words taken back: out of Send if they haven't gone yet, else the page says how far they'd got.
- (void)takeBack:(NSDictionary *)message {
    NSString *sessionId = AsText(message[@"sessionId"]);
    double at = AsNumber(message[@"at"]).doubleValue;
    NSDictionary *record = [self recordOf:sessionId], *said = SideChatRecordAt(record, at);
    if (!said) return;
    NSString *wordsId = self.wordsIds[Key(sessionId, at)];
    NSString *state = AsText(said[@"state"]);
    NSString *late = wordsId ? [self.core.send takeBack:wordsId] : [state isEqual:@"held"] ? nil : state;
    if (!late) [self.wordsIds removeObjectForKey:Key(sessionId, at)];
    [self keep:SideChatRecordTakeBack(record, at, late) of:sessionId];
    if (!late) [self unsendAsideOf:sessionId at:at];
}

// The side question words said at `at` went as, if they were one, back to how its copy left it, with Ask Again and
// Send's words: the words didn't go.
- (void)unsendAsideOf:(NSString *)sessionId at:(double)at {
    NSNumber *asideAt = self.asideWords[Key(sessionId, at)];
    if (!asideAt) return;
    [self.asideWords removeObjectForKey:Key(sessionId, at)];
    self.asides[sessionId] = SideChatAsideUnsent(self.asides[sessionId], asideAt.doubleValue);
    [self tell];
}

// Held words sent now, by your press; or words the session stopped before reading, sent again, now it's idle.
- (void)sendNow:(NSDictionary *)message {
    NSString *sessionId = AsText(message[@"sessionId"]);
    double at = AsNumber(message[@"at"]).doubleValue;
    NSDictionary *said = SideChatRecordAt([self recordOf:sessionId], at);
    Row *row = self.listed[sessionId];
    if (!said || !row) return;
    if ([said[@"state"] isEqual:@"held"] && self.wordsIds[Key(sessionId, at)])
        [self.core.send sendNow:self.wordsIds[Key(sessionId, at)]];
    else if ([said[@"state"] isEqual:@"stopped"] && !Works(row)) {
        [self keep:SideChatRecordProgress([self recordOf:sessionId], at, @{@"state": @"held"}) of:sessionId];
        [self go:SideChatLine(said) row:row at:at];
    }
}

// Words put on the clipboard as they'd go in, from the box or the conversation (Copy and Go), for you to paste in the
// session yourself; the page then takes you there. Nothing is run. Held words are taken out of Send first, as Take
// Back takes them, so they can't also go in by themselves once you've pasted them: copied, or, when Send had already
// passed them on, not copied, with how far they'd got.
- (void)copyWords:(NSDictionary *)message {
    NSString *sessionId = AsText(message[@"sessionId"]);
    double at = AsNumber(message[@"at"]).doubleValue;
    NSDictionary *record = [self recordOf:sessionId], *said = message[@"at"] ? SideChatRecordAt(record, at) : nil;
    NSString *line = SideChatCopyLine(said, AsText(message[@"words"]), AsText(message[@"opening"]));
    if (!line) return [self notSent:SideChatToGo(AsText(message[@"words"]), AsText(message[@"opening"]), nil)
                                 of:sessionId];
    if (!self.listed[sessionId] || !line.length) return;
    if ([said[@"state"] isEqual:@"held"]) {
        NSString *wordsId = self.wordsIds[Key(sessionId, at)];
        NSString *late = wordsId ? [self.core.send takeBack:wordsId] : nil;
        if (late) {
            [self keep:SideChatRecordTakeBack(record, at, late) of:sessionId];
            return;
        }
        [self.wordsIds removeObjectForKey:Key(sessionId, at)];
        [self keep:SideChatRecordCopied(record, at, Now()) of:sessionId];
    }
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:line forType:NSPasteboardTypeString];
    PanelLog(@"side-chat: words for %@ copied", sessionId);
}

// A code block of a reply, put on the clipboard (the reply's Copy): exactly what was between its fences, from the
// reply as the app read it, never anything the page says. Nothing in it is ever run.
- (void)copyReplyPart:(NSDictionary *)message {
    NSString *sessionId = AsText(message[@"sessionId"]);
    NSArray *parts = self.replies[Key(sessionId, AsNumber(message[@"at"]).doubleValue)];
    NSInteger n = AsNumber(message[@"part"]).integerValue;
    NSString *code = n >= 0 && n < (NSInteger)parts.count ? AsText(AsRecord(parts[(NSUInteger)n])[@"code"]) : nil;
    if (!code) return;
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:code forType:NSPasteboardTypeString];
    PanelLog(@"side-chat: a block of %@'s reply copied", sessionId);
}

#pragma mark - Asked on the side

// The agent a session is asked on the side through, or nil: never a Claude Desktop conversation's yet (the agent
// inside it isn't the one Whozmove knows to run), nor one that has ended.
- (id<AgentAside>)asideAgentOf:(Row *)row {
    id agent = row ? [self.core agentOf:row] : nil;
    if (![agent conformsToProtocol:@protocol(AgentAside)] || [self.core.send reachOf:row].desktop
        || [self.core hasEnded:row]) return nil;
    return agent;
}

// A question asked on the side, by your press: one at a time for each session, and only while its agent can say
// nothing stands in the way. Kept in memory only, as /btw keeps its own. One that can't be asked once you've pressed
// (what stood in the way changed meanwhile) stays in the chat as not asked, with Ask Again, as the page has already
// emptied your box.
- (void)ask:(NSDictionary *)message {
    NSString *sessionId = AsText(message[@"sessionId"]);
    // The words that open yours where the chat is drawn (One Task's task and step), so the copy knows what you mean
    // as the session would: put back with why when they can't go with it (SideChatToGo).
    NSDictionary *going = SideChatToGo(PlainOneLine(AsText(message[@"question"]), SideChatMost),
                                       AsText(message[@"opening"]), nil);
    Row *row = self.listed[sessionId];
    if (!going || !row) return;
    if (going[@"why"]) return [self notSent:going of:sessionId];
    NSString *question = going[@"words"], *opening = going[@"opening"];
    [self ask:question opening:opening of:row sessionId:sessionId through:[self asideAgentOf:row] at:Now()];
    [self tell];
}

// Words that can't go (SideChatToGo's {words, why}): back in your box, saying why, as words Send refuses are, never
// gone with nothing said.
- (void)notSent:(NSDictionary *)going of:(NSString *)sessionId {
    Row *row = self.listed[sessionId];
    NSString *line = PlainOneLine(going[@"words"], SideChatMost);
    if (!row || !line.length) return;
    double at = Now();
    NSDictionary *record = SideChatRecordSaid([self recordOf:sessionId], line, nil, at, row.pid, row.pid > 0
                                              ? ProcessStartedAt(row.pid) : 0);
    [self keep:SideChatRecordProgress(record, at, @{@"state": @"notSent", @"why": going[@"why"] ?: @""}) of:sessionId];
}

// The question asked at `at` through the session's agent (none: not asked), kept as it goes: still being asked, on
// each step its agent says the answer takes, or didn't answer when it couldn't start. --print-side-chat asks through a
// sample agent. Its agent is asked the question after the words that open it (`opening`), and the chat keeps your
// question alone.
- (void)ask:(NSString *)question opening:(NSString *)opening of:(Row *)row sessionId:(NSString *)sessionId
    through:(id<AgentAside>)agent at:(double)at {
    NSArray *asked = agent && ![agent asideWhyNot:row]
        ? SideChatAsideAsked(self.asides[sessionId], question, opening, at) : nil;
    if (!asked) {
        self.asides[sessionId] = SideChatAsideNotAsked(self.asides[sessionId], question, opening, at);
        return;
    }
    self.asides[sessionId] = asked;
    __weak typeof(self) weakSelf = self;
    NSString *askId = [agent ask:[opening ?: @"" stringByAppendingString:question] aside:row
                         earlier:SideChatAsidesEarlier(asked, at)
                            step:^(NSString *step) {
        [weakSelf stepped:step of:sessionId at:at];
    } done:^(NSDictionary *answer) {
        [weakSelf answered:answer of:sessionId at:at];
    }];
    if (askId) self.asks[Key(sessionId, at)] = @[askId, agent];
    else self.asides[sessionId] = SideChatAsideAnswered(asked, at, @{@"state": @"noAnswer"}, Now());
    PanelLog(@"side-chat: a side question for %@%@", sessionId, askId ? @"" : @", which couldn't start");
}

// A new step of its answer, as its agent says it: kept with the question while it's still being asked, and told.
- (void)stepped:(NSString *)step of:(NSString *)sessionId at:(double)at {
    NSArray *asides = self.asides[sessionId];
    if (!asides) return;  // its session went meanwhile
    NSArray *now = SideChatAsideToStep(asides, at, step);
    if ([now isEqual:asides]) return;
    self.asides[sessionId] = now;
    [self tell];
}

// Its agent's answer: kept with the question, its tokens and any error status logged (only numbers, never words), and
// told.
- (void)answered:(NSDictionary *)answer of:(NSString *)sessionId at:(double)at {
    [self.asks removeObjectForKey:Key(sessionId, at)];
    NSArray *asides = self.asides[sessionId];
    if (!asides) return;  // its session went meanwhile
    self.asides[sessionId] = SideChatAsideAnswered(asides, at, answer, Now());
    NSNumber *status = AsNumber(answer[@"status"]);
    PanelLog(@"side-chat: side question for %@: %@%@, %@ read from cache, %@ new, %@ written, %@ out", sessionId,
             AsText(answer[@"state"]) ?: @"no state",
             status ? [NSString stringWithFormat:@" (error %ld)", (long)status.integerValue] : @"",
             AsNumber(answer[@"cacheRead"]) ?: @"?", AsNumber(answer[@"fresh"]) ?: @"?",
             AsNumber(answer[@"written"]) ?: @"?", AsNumber(answer[@"output"]) ?: @"?");
    [self tell];
}

- (void)askStop:(NSDictionary *)message {
    NSString *sessionId = AsText(message[@"sessionId"]);
    NSArray *ask = self.asks[Key(sessionId, AsNumber(message[@"at"]).doubleValue)];
    if (ask) [(id<AgentAside>)ask[1] stopAside:ask[0]];
}

// A session's questions on the side let go of, with any still being answered stopped: its session has gone.
- (void)forgetAsides:(NSString *)sessionId {
    // Stopped through the agent each was asked of: its row may already be gone from the list.
    NSString *prefix = [sessionId stringByAppendingString:@" "];
    for (NSString *key in [self.asks.allKeys copy]) {
        if (![key hasPrefix:prefix]) continue;
        NSArray *ask = self.asks[key];
        [(id<AgentAside>)ask[1] stopAside:ask[0]];
        [self.asks removeObjectForKey:key];
    }
    [self.asides removeObjectForKey:sessionId];
}

// A side question's answer as the app read it, its question, or one of its answer's code blocks, put on the
// clipboard: never anything the page says. Nothing in it is ever run.
- (void)copyAside:(NSDictionary *)message {
    NSString *sessionId = AsText(message[@"sessionId"]), *what = AsText(message[@"what"]);
    NSDictionary *aside = SideChatAsideAt(self.asides[sessionId], AsNumber(message[@"at"]).doubleValue);
    NSString *copied = nil;
    if ([what isEqual:@"answer"]) copied = AsText(aside[@"text"]);
    else if ([what isEqual:@"question"]) copied = SideChatAsideLine(aside);
    else if ([what isEqual:@"code"]) {
        NSArray *parts = AsList(aside[@"answer"]);
        NSInteger n = AsNumber(message[@"part"]).integerValue;
        copied = n >= 0 && n < (NSInteger)parts.count ? AsText(AsRecord(parts[(NSUInteger)n])[@"code"]) : nil;
    }
    if (!copied.length) return;
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:copied forType:NSPasteboardTypeString];
    PanelLog(@"side-chat: a side answer of %@ copied", sessionId);
}

// The command that signs the session's agent in, for you to run in a terminal, as the newest side question found it
// signed out.
- (void)copySignIn:(NSDictionary *)message {
    NSString *sessionId = AsText(message[@"sessionId"]), *signIn = nil;
    for (NSDictionary *aside in [self.asides[sessionId] reverseObjectEnumerator])
        if (!signIn) signIn = AsText(aside[@"signIn"]);
    if (!signIn.length) return;
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:signIn forType:NSPasteboardTypeString];
}

// Where to get the session's agent, opened in your browser.
- (void)getAgent:(NSDictionary *)message {
    Row *row = self.listed[AsText(message[@"sessionId"])];
    id agent = row ? [self.core agentOf:row] : nil;
    NSURL *page = [agent conformsToProtocol:@protocol(AgentInstall)] ? [(id<AgentInstall>)agent installPage] : nil;
    if (page) OpenInWebBrowser(page);
}

#pragma mark - Replies

// Words read go on to their reply as the session's turn ends: its whole reply in the turn whose prompt is exactly the
// words typed in, read by its agent off the main thread (AgentWork's replyTo:, 16 KB at most), cut into prose and code
// and held in memory only. After a restart, a reply is read again, once.
- (void)readReplies {
    for (NSString *sessionId in [self.allRecords.allKeys copy]) {
        Row *row = self.listed[sessionId];
        if (!row || Works(row)) continue;
        for (NSDictionary *said in AsList([self recordOf:sessionId][@"says"])) {
            double at = AsNumber(said[@"at"]).doubleValue, done = AsNumber(said[@"doneAt"]).doubleValue;
            NSString *state = AsText(said[@"state"]);
            // Typed in, its turn's reply comes after them; handed in, the turn they went into has ended now it's idle.
            BOOL read = [state isEqual:@"read"]
                && (![said[@"how"] isEqual:@"typed"] || row.lastReplyAt.doubleValue > done);
            BOOL again = [state isEqual:@"replied"] && !self.replies[Key(sessionId, at)];
            if (!(read || again)) continue;
            if ([said[@"how"] isEqual:@"typed"]) [self readReplyTo:said of:row];
            else if (read) [self readHandedReplyTo:said of:row];
        }
    }
}

// Words handed in between steps: their reply is what the session wrote after them in that turn, as its agent read it in
// its transcript, once the turn has ended (the session is idle again); none then, it finished without a reply. Their
// agent lets them go then. Read again after a restart, they can't be: nothing of which they were is kept.
- (void)readHandedReplyTo:(NSDictionary *)said of:(Row *)row {
    NSString *sessionId = row.sessionId;
    double at = AsNumber(said[@"at"]).doubleValue;
    NSString *key = Key(sessionId, at), *wordsId = self.wordsIds[key];
    id agent = [self.core agentOf:row];
    if ([self.reading containsObject:key]) return;
    if (!wordsId || ![agent conformsToProtocol:@protocol(AgentBetweenSteps)]) {
        NSDictionary *record = [self recordOf:sessionId];
        if (record) [self keep:SideChatRecordReplied(record, at, NO, 0) of:sessionId];
        return;
    }
    [self.reading addObject:key];
    NSNumber *ended = row.lastReplyAt ?: @(Now());
    __weak typeof(self) weakSelf = self;
    [(id<AgentBetweenSteps>)agent wordsState:wordsId row:row done:^(NSDictionary *state) {
        [weakSelf.reading removeObject:key];
        NSArray *parts = ReplyParts(AsText(state[@"reply"]));
        if (parts.count) weakSelf.replies[key] = parts;
        [(id<AgentBetweenSteps>)agent forgetWords:wordsId];
        [weakSelf.wordsIds removeObjectForKey:key];
        NSDictionary *record = [weakSelf recordOf:sessionId];
        if (record) [weakSelf keep:SideChatRecordReplied(record, at, parts.count > 0, ended.doubleValue) of:sessionId];
    }];
}

- (void)readReplyTo:(NSDictionary *)said of:(Row *)row {
    NSString *sessionId = row.sessionId;
    double at = AsNumber(said[@"at"]).doubleValue;
    NSString *key = Key(sessionId, at);
    id agent = [self.core agentOf:row];
    if ([self.reading containsObject:key] || ![agent conformsToProtocol:@protocol(AgentWork)]) return;
    [self.reading addObject:key];
    NSNumber *ended = row.lastReplyAt ?: @(Now());
    __weak typeof(self) weakSelf = self;
    [(id<AgentWork>)agent replyTo:SideChatLine(said) of:sessionId since:AsNumber(said[@"doneAt"]).doubleValue - 2000
                             done:^(NSString *reply) {
        [weakSelf.reading removeObject:key];
        NSArray *parts = ReplyParts(reply);
        if (parts.count) weakSelf.replies[key] = parts;
        NSDictionary *record = [weakSelf recordOf:sessionId];
        if (record) [weakSelf keep:SideChatRecordReplied(record, at, parts.count > 0, ended.doubleValue) of:sessionId];
    }];
}

#pragma mark - What the page is told

// Each session's chat as the page draws it: your words with each reply read, your questions on the side, why none can
// be asked now and the name of the agent they're asked through, whether its agent's hook hands words in between its
// steps, the words that open yours while it works, its terminal when that's the app in front, and why nothing can be
// typed into it while it's idle, when nothing can. Told only when it changes.
- (void)tell {
    if (self.core.printing) return;
    NSMutableDictionary *chats = [NSMutableDictionary dictionary];
    NSString *front = NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier;
    for (NSString *sessionId in self.listed) {
        Row *row = self.listed[sessionId];
        NSMutableArray *says = [NSMutableArray array];
        for (NSDictionary *said in AsList(self.allRecords[sessionId][@"says"])) {
            NSMutableDictionary *one = [said mutableCopy];
            NSArray *reply = self.replies[Key(sessionId, AsNumber(said[@"at"]).doubleValue)];
            if (reply) one[@"reply"] = reply;
            if (self.asideWords[Key(sessionId, AsNumber(said[@"at"]).doubleValue)]) one[@"fromAside"] = @YES;
            [says addObject:one];
        }
        SessionReach *reach = [self.core.send reachOf:row];
        id<Host> host = [self.core hostOf:row];
        NSDictionary *idleWay = reach.desktop || [self.core hasEnded:row] ? nil
            : reach.openTwice ? @{@"kind": @"twice"}
            : !reach.terminal ? @{@"kind": @"cantType", @"host": host.name ?: @"its terminal"} : nil;
        id agent = [self.core agentOf:row];
        id<AgentBetweenSteps> steps = [agent conformsToProtocol:@protocol(AgentBetweenSteps)] ? agent : nil;
        id<AgentAside> aside = [self asideAgentOf:row];
        chats[sessionId] = @{@"says": says, @"asides": SideChatAsidesShown(self.asides[sessionId]),
                             @"askWhyNot": [aside asideWhyNot:row] ?: NSNull.null, @"agent": aside.name ?: @"",
                             @"hook": @([steps takesWordsBetweenSteps:row]),
                             @"older": @([steps startedBeforeBetweenSteps:row]), @"frame": steps.betweenStepsLine ?: @"",
                             @"front": ReachTerminalInFront(reach, front) ?: @"",
                             @"idleWay": idleWay ?: NSNull.null};
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:chats options:NSJSONWritingSortedKeys error:nil];
    NSString *told = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : nil;
    if (!told || [told isEqual:self.told]) return;
    self.told = told;
    [self.core.page call:@"setSideChats" with:@[chats]];
}

#pragma mark - Module

- (void)pageLoaded {
    self.told = nil;
    [self tell];
}

// The rows are whole: each session's chat goes once its process has ended, replies are read as turns end, and the
// page is told.
- (void)rows:(NSArray<Row *> *)rows phase:(RowPhase)phase {
    if (phase != RowPhaseListed || self.core.printing) return;
    NSMutableDictionary *bySession = [NSMutableDictionary dictionary];
    for (Row *row in rows)
        if (row.sessionId) bySession[row.sessionId] = row;
    self.listed = bySession;
    for (NSString *sessionId in [self.allRecords.allKeys copy]) [self recordOf:sessionId];
    // A side question goes with its session: once it's no longer listed, or has ended, it's stopped and let go.
    for (NSString *sessionId in [self.asides.allKeys copy]) {
        Row *row = bySession[sessionId];
        if (!row || [self.core hasEnded:row]) [self forgetAsides:sessionId];
    }
    [self readReplies];
    [self tell];
}

- (NSDictionary<NSString *, void (^)(NSDictionary *message)> *)messages {
    __weak typeof(self) weakSelf = self;
    return @{
        @"sideChatSend": ^(NSDictionary *message) { [weakSelf send:message]; },
        @"sideChatTakeBack": ^(NSDictionary *message) { [weakSelf takeBack:message]; },
        @"sideChatSendNow": ^(NSDictionary *message) { [weakSelf sendNow:message]; },
        @"sideChatCopy": ^(NSDictionary *message) { [weakSelf copyWords:message]; },
        @"sideChatReplyCopy": ^(NSDictionary *message) { [weakSelf copyReplyPart:message]; },
        @"sideChatAsk": ^(NSDictionary *message) { [weakSelf ask:message]; },
        @"sideChatAskStop": ^(NSDictionary *message) { [weakSelf askStop:message]; },
        @"sideChatAsideCopy": ^(NSDictionary *message) { [weakSelf copyAside:message]; },
        @"sideChatCopySignIn": ^(NSDictionary *message) { [weakSelf copySignIn:message]; },
        // The way past words Claude Desktop couldn't take for want of the Accessibility permission: its pane in System
        // Settings, by your press.
        @"sideChatAccessibility": ^(NSDictionary *message) { OpenLink(kAccessibilitySettings); },
        @"sideChatGetAgent": ^(NSDictionary *message) { [weakSelf getAgent:message]; },
        // Words the page has put back in your box: gone from the record, so they're put back only once.
        @"sideChatPutBack": ^(NSDictionary *message) {
            NSString *sessionId = AsText(message[@"sessionId"]);
            NSDictionary *record = [weakSelf recordOf:sessionId];
            NSDictionary *next = SideChatRecordPutBack(record, AsNumber(message[@"at"]).doubleValue);
            if (next != record) [weakSelf keep:next of:sessionId];
        },
    };
}

+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return @{@"--print-side-chat": ^int(Core *core, NSArray<NSString *> *arguments) {
        return PrintSideChat([[SideChatModule alloc] initWithCore:core]);
    }};
}

@end

// A terminal the panel can type into that holds no session as its own (no holds:), as a real terminal is, for
// --print-side-chat: a session runs in it only by its process.
@interface SideChatSampleTerminal : NSObject <TypingHost>
@end

@implementation SideChatSampleTerminal
- (NSString *)appId { return @"com.example.terminal"; }
- (NSString *)name { return @"Sample Terminal"; }
- (BOOL)open:(Row *)row { return NO; }
- (NSString *)tabFor:(Row *)row unique:(BOOL *)unique { *unique = YES; return @"tab"; }
- (void)type:(NSString *)text inTab:(NSString *)tab {}
- (void)press:(TerminalKey)key times:(NSInteger)times inTab:(NSString *)tab {}
@end

// A session's reach as Send finds it, but for the terminal it runs in, which only a live process shows: a
// SideChatSampleTerminal (none when `terminal` is nil), or a conversation Claude Desktop keeps (`desktop`).
@interface SideChatSampleReach : SessionReach
@property (strong) id<TypingHost> sample;
@property (assign) BOOL inDesktop;
@end

@implementation SideChatSampleReach
- (BOOL)desktop { return self.inDesktop; }
- (id<TypingHost>)typing { return self.inDesktop ? nil : self.sample; }
@end

// An agent that answers side questions as the run tells it, for --print-side-chat: whether the next ask starts at all
// (`refuses`), or may be asked (`whyNot`); `step` and `done`, the steps and the answer of the ask under way, given when
// the run says.
@interface SideChatSampleAgent : NSObject <AgentAside>
@property (assign) BOOL refuses;
@property (copy) NSDictionary *whyNot;
@property (copy) void (^step)(NSString *step);
@property (copy) void (^done)(NSDictionary *answer);
@property (copy) NSString *asked;
@end

@implementation SideChatSampleAgent
- (NSString *)name { return @"Sample Agent"; }
- (NSArray<Row *> *)readSessions { return @[]; }
- (NSArray<Row *> *)readEndedSessions:(NSArray<Row *> *)listed { return @[]; }
- (void)addRecordTo:(Row *)row {}
- (void)addRequestsTo:(NSArray<Row *> *)rows {}
- (NSString *)titleOf:(Row *)row now:(BOOL)now { return nil; }
- (BOOL)titleShowsWork:(NSString *)title { return NO; }
// None: it only answers side questions, so no session reads instructions from it. Every Agent says what it has.
- (NSArray<NSString *> *)instructionPages { return @[]; }
- (NSArray<NSString *> *)environmentMarks { return @[]; }
- (NSString *)sessionOfProcess:(pid_t)pid { return nil; }
- (NSString *)whyNotAsker:(pid_t)pid { return @"a sample"; }
- (NSString *)whyNot:(Row *)row speakFrom:(pid_t)process { return @"a sample"; }
- (NSDictionary *)asideWhyNot:(Row *)row { return self.whyNot; }
- (NSString *)ask:(NSString *)question aside:(Row *)row earlier:(NSArray<NSDictionary *> *)earlier
             step:(void (^)(NSString *step))step done:(void (^)(NSDictionary *answer))done {
    if (self.refuses) return nil;
    self.asked = question;
    self.step = step;
    self.done = done;
    return @"sample-ask";
}
- (void)stopAside:(NSString *)askId {}
@end

// `Whozmove --print-side-chat`: what the record keeps as your words move on (SideChatRecord.m), who can open it once
// it's kept, in the home folder the run is given, whether held words go in by themselves (Send's WordsGoByThemselves,
// and for a session's reach, ReachGoesByItself and ReachTerminalInFront) and what they do now (HeldWordsStep), what's
// kept in memory of questions asked on the side as they're answered, and a reply cut into prose and code (ReplyParts).
static int PrintSideChat(SideChatModule *module) {
    void (^say)(NSString *, id) = ^(NSString *what, id value) {
        NSData *json = [NSJSONSerialization dataWithJSONObject:value ?: NSNull.null
                                                       options:NSJSONWritingSortedKeys | NSJSONWritingFragmentsAllowed
                                                         error:nil];
        NSString *line = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
        printf("%s: %s\n", what.UTF8String, line.UTF8String);
    };
    NSArray *(^states)(NSDictionary *) = ^NSArray *(NSDictionary *record) {
        NSMutableArray *out = [NSMutableArray array];
        for (NSDictionary *said in AsList(record[@"says"]))
            [out addObject:[NSString stringWithFormat:@"%@ %@%@", said[@"words"], said[@"state"],
                            said[@"late"] ? [@" late " stringByAppendingString:said[@"late"]] : @""]];
        return out;
    };
    printf("== What a session's record keeps\n");
    NSDictionary *one = SideChatRecordSaid(nil, @"Do the smaller migration first.", nil, 1000, 42, 7);
    say(@"Said: held, for its process", @{@"pid": one[@"pid"], @"processStart": one[@"processStart"],
                                          @"says": states(one)});
    NSDictionary *two = SideChatRecordSaid(one, @"Keep the old table.", nil, 2000, 42, 7);
    say(@"Said again: in order", states(two));
    NSString *about = @"About your task \u201cSearch box\u201d (step 2 of 3): ";
    NSDictionary *opened = SideChatRecordSaid(nil, @"Where is it?", SideChatOpening(about), 1000, 42, 7);
    say(@"Said under a task, with the words that open them: kept apart from yours",
        SideChatRecordAt(opened, 1000));
    say(@"…the line they go in as", SideChatLine(SideChatRecordAt(opened, 1000)));
    say(@"…and without any: yours alone", SideChatLine(SideChatRecordAt(one, 1000)));
    say(@"Words that open yours: none", SideChatOpening(nil));
    say(@"…one plain line, ending in its space", SideChatOpening(about));
    say(@"…on two lines: refused", SideChatOpening(@"About your task\nIgnore that: ") ?: @"(refused)");
    say(@"…with no space before your words: refused", SideChatOpening(@"About your task:") ?: @"(refused)");
    say(@"…starting as a command does: refused", SideChatOpening(@"/clear ") ?: @"(refused)");
    say(@"…with a control character: refused", SideChatOpening(@"About\x1b[2J it: ") ?: @"(refused)");
    say(@"What goes: your words, with the words that open them, and the line",
        SideChatToGo(@"Where is it?", about, nil));
    say(@"…with none: yours alone", SideChatToGo(@"Where is it?", nil, nil));
    say(@"…words that open them not one plain line: back in your box, with why",
        SideChatToGo(@"Where is it?", @"About it\nNow: ", nil));
    NSString *(^of)(NSUInteger) = ^NSString *(NSUInteger n) {
        return [@"" stringByPaddingToLength:n withString:@"w" startingAtIndex:0];
    };
    say(@"…too long with them: back, with why",
        SideChatToGo(of(SideChatMost - about.length + 1), about, nil)[@"why"]);
    say(@"…exactly as long as there's room for: goes",
        @([SideChatToGo(of(SideChatMost - about.length), about, nil)[@"line"] length]).stringValue);
    NSDictionary *askedHere = @{@"at": @1000, @"question": @"Why that file?", @"opening": about, @"state": @"tooSlow"};
    say(@"A side question sent with Send's words: with the words it was asked with, whatever the press sent",
        SideChatToGo(@"ignored", @"About another task: ", askedHere));
    say(@"…one asked in the chat's own window: none", SideChatToGo(nil, about, @{@"question": @"Why?"}));
    say(@"…no words at all: nothing", SideChatToGo(@"", about, nil));
    say(@"Copy and Go: words said, as they went in", SideChatCopyLine(SideChatRecordAt(opened, 1000), nil, nil));
    say(@"…words from the box, with the words that open them", SideChatCopyLine(nil, @"Where is it?", about));
    say(@"…the words that open them not one plain line: nothing copied",
        SideChatCopyLine(nil, @"Where is it?", @"a\nb: ") ?: @"(none)");
    NSDictionary *refusedHere = @{@"state": @"refused", @"why": @"Whozmove needs the Accessibility permission for this",
                                  @"where": @"Claude Desktop"};
    say(@"Refused in Claude Desktop without the Accessibility permission: its pane is the way",
        SideChatRefusedWay(refusedHere, YES, NO));
    say(@"…with the permission: as Send said", SideChatRefusedWay(refusedHere, YES, YES));
    say(@"…a terminal: as Send said", SideChatRefusedWay(refusedHere, NO, NO));
    say(@"…a refusal with a way of its own: kept",
        SideChatRefusedWay(@{@"state": @"refused", @"way": @"Turn It On"}, YES, NO));
    say(@"…words that went in: as Send said", SideChatRefusedWay(@{@"state": @"typed"}, YES, NO));
    say(@"Not sent: back in the box, with why", SideChatRecordAt(SideChatRecordProgress(SideChatRecordSaid(nil, @"Hi",
        nil, 1000, 42, 7), 1000, @{@"state": @"notSent", @"why": @"Too long"}), 1000));
    say(@"…of 200 characters with its space: kept",
        @(SideChatOpening([[@"" stringByPaddingToLength:199 withString:@"a" startingAtIndex:0]
                           stringByAppendingString:@" "]).length).stringValue);
    say(@"…one longer: refused", SideChatOpening([[@"" stringByPaddingToLength:200 withString:@"a" startingAtIndex:0]
                                                  stringByAppendingString:@" "]) ? @"(kept)" : @"(refused)");
    NSDictionary *typed = SideChatRecordProgress(two, 1000, @{@"state": @"typed", @"at": @1500});
    say(@"Typed in", SideChatRecordAt(typed, 1000));
    NSDictionary *read = SideChatRecordProgress(typed, 1000, @{@"state": @"read", @"how": @"typed", @"at": @1600});
    say(@"Read, as its record shows", SideChatRecordAt(read, 1000));
    say(@"Read stays read", SideChatRecordAt(SideChatRecordProgress(read, 1000, @{@"state": @"stopped"}), 1000));
    NSDictionary *refused = SideChatRecordProgress(read, 2000, @{@"state": @"refused", @"why": @"Couldn't find its tab",
                                                                 @"way": NSNull.null, @"where": @"Ghostty"});
    say(@"Refused, with why", SideChatRecordAt(refused, 2000));
    say(@"Back in the box stays there", SideChatRecordAt(SideChatRecordProgress(refused, 2000, @{@"state": @"typing"}),
                                                         2000)[@"state"]);
    NSDictionary *copied = SideChatRecordCopied(two, 2000, 2500);
    say(@"Held words copied with Copy and Go", SideChatRecordAt(copied, 2000));
    say(@"…stay copied, whatever Send said before it let them go",
        SideChatRecordAt(SideChatRecordProgress(copied, 2000, @{@"state": @"typing"}), 2000)[@"state"]);
    say(@"Words already read aren't copied this way", SideChatRecordAt(SideChatRecordCopied(read, 1000, 2500),
                                                                       1000)[@"state"]);
    say(@"Put back by the page: gone", states(SideChatRecordPutBack(refused, 2000)));
    say(@"Put back, but it wasn't back: kept", states(SideChatRecordPutBack(refused, 1000)));
    say(@"Replied", SideChatRecordAt(SideChatRecordReplied(read, 1000, YES, 1900), 1000));
    say(@"No reply", SideChatRecordAt(SideChatRecordReplied(read, 1000, NO, 1900), 1000)[@"state"]);
    say(@"A reply to words not read yet: nothing", states(SideChatRecordReplied(two, 1000, YES, 1900)));
    say(@"Taken back in time", states(SideChatRecordTakeBack(two, 2000, nil)));
    say(@"Taken back too late", states(SideChatRecordTakeBack(two, 2000, @"handed")));
    NSDictionary *mixed = SideChatRecordProgress(SideChatRecordProgress(two, 1000, @{@"state": @"handed"}), 2000,
                                                 @{@"state": @"typing"});
    say(@"After a restart: what hadn't gone in is back in the box", states(SideChatRecordRestarted(
        SideChatRecordSaid(mixed, @"And the docs.", nil, 3000, 42, 7))));
    say(@"After a restart: read words stay", states(SideChatRecordRestarted(read)));

    printf("\n== Who can open it once it's kept\n");
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *(^mode)(NSString *) = ^NSString *(NSString *path) {
        return [NSString stringWithFormat:@"%lo", [[files attributesOfItemAtPath:path error:nil][NSFilePosixPermissions]
                                                   unsignedLongValue]];
    };
    [files createDirectoryAtPath:ChatsDir() withIntermediateDirectories:YES attributes:nil error:nil];
    [files setAttributes:@{NSFilePosixPermissions: @0755} ofItemAtPath:ChatsDir() error:nil];
    say(@"Its folder, left open to others from before", mode(ChatsDir()));
    say(@"Kept", @([module keep:one of:@"sample-session"]));
    say(@"Kept: its folder", mode(ChatsDir()));
    say(@"Kept: its file", mode(RecordPath(@"sample-session")));
    say(@"A session id that's a path: not kept", @([module keep:one of:@"../elsewhere"]));
    [module forget:@"sample-session"];
    say(@"Its process ended: gone", @([files fileExistsAtPath:RecordPath(@"sample-session")]));

    printf("\n== What held words do now\n");
    void (^step)(NSString *, BOOL, BOOL, BOOL, BOOL, BOOL) = ^(NSString *what, BOOL works, BOOL first, BOOL pressed,
                                                              BOOL byThemselves, BOOL changing) {
        BOOL still = NO;
        NSString *next = HeldWordsStep(works, first, pressed, byThemselves, changing, &still);
        say(what, [NSString stringWithFormat:@"%@%@", next, still ? @", still pressed" : @""]);
    };
    step(@"Sent while it's idle: in now, as pressed", NO, YES, YES, NO, NO);
    step(@"Sent while it's idle, but it turned to work first: its turn's end, the press gone", YES, YES, YES, YES, NO);
    step(@"Pressed, behind words still going in: later, the press gone", NO, NO, YES, YES, NO);
    step(@"At work", YES, YES, NO, YES, NO);
    step(@"Its turn ended, safe to go by themselves", NO, YES, NO, YES, NO);
    step(@"Its turn ended, its terminal in front: your press", NO, YES, NO, NO, NO);
    step(@"Its turn ended, another change still going in: later", NO, YES, NO, YES, YES);
    step(@"Send Now pressed: in now", NO, YES, YES, NO, NO);

    printf("\n== Whether held words go in by themselves\n");
    say(@"Its terminal behind another app", @(WordsGoByThemselves(NO, NO, @"com.example.terminal",
                                                                   @"com.example.browser")));
    say(@"Its terminal in front", @(WordsGoByThemselves(NO, NO, @"com.example.terminal", @"com.example.terminal")));
    say(@"The session you're on", @(WordsGoByThemselves(YES, NO, @"com.example.terminal", @"com.example.browser")));
    say(@"In Claude Desktop", @(WordsGoByThemselves(NO, YES, @"com.example.desktop", @"com.example.browser")));
    say(@"Its terminal unknown", @(WordsGoByThemselves(NO, NO, nil, @"com.example.browser")));
    say(@"Nothing in front", @(WordsGoByThemselves(NO, NO, @"com.example.terminal", nil)));
    say(@"Asked again before each key: you've come to its terminal", @(WordsGoByThemselves(NO, NO,
        @"com.example.terminal", @"com.example.terminal")));
    say(@"…or to its tab", @(WordsGoByThemselves(YES, NO, @"com.example.terminal", @"com.example.browser")));

    printf("\n== Whether held words go in by themselves, from the session's reach\n");
    SideChatSampleReach *(^reachIn)(BOOL, BOOL) = ^SideChatSampleReach *(BOOL terminal, BOOL desktop) {
        Row *row = [[Row alloc] initWithFields:@{@"sessionId": @"sample-session"}];
        SideChatSampleReach *reach = [[SideChatSampleReach alloc] initWithRow:row send:module.core.send];
        reach.sample = terminal ? [SideChatSampleTerminal new] : nil;
        reach.inDesktop = desktop;
        return reach;
    };
    SideChatSampleReach *inTerminal = reachIn(YES, NO);
    say(@"In a terminal no app holds it in, behind another app",
        @(ReachGoesByItself(inTerminal, NO, @"com.example.browser")));
    say(@"…its terminal in front", @(ReachGoesByItself(inTerminal, NO, @"com.example.terminal")));
    say(@"…the session you're on", @(ReachGoesByItself(inTerminal, YES, @"com.example.browser")));
    say(@"In Claude Desktop", @(ReachGoesByItself(reachIn(NO, YES), NO, @"com.example.browser")));
    say(@"In a terminal the panel can't type into", @(ReachGoesByItself(reachIn(NO, NO), NO, @"com.example.browser")));
    say(@"Its terminal named as in front, when it is", ReachTerminalInFront(inTerminal, @"com.example.terminal"));
    say(@"…when it's behind another app", ReachTerminalInFront(inTerminal, @"com.example.browser"));
    say(@"…in Claude Desktop", ReachTerminalInFront(reachIn(NO, YES), @"com.example.desktop"));

    printf("\n== Asked on the side, in memory only\n");
    NSArray *asked = SideChatAsideAsked(nil, @"Why that file?", nil, 1000);
    say(@"Asked", asked);
    say(@"Asked again while it's being answered: not asked", SideChatAsideAsked(asked, @"And the tests?", nil, 2000));
    say(@"On a step of its answer", SideChatAsideToStep(asked, 1000, @"Reading cart.ts"));
    say(@"…said on more than one line, and long: one line, cut", SideChatAsideToStep(asked, 1000,
        [@"Looking at\nthe cart " stringByPaddingToLength:200 withString:@"and more " startingAtIndex:0]));
    say(@"…no words, or another time's: as it was", @[SideChatAsideToStep(asked, 1000, @" \n"),
                                                       SideChatAsideToStep(asked, 2000, @"Reading cart.ts")]);
    say(@"…once answered, its step goes", SideChatAsideAnswered(SideChatAsideToStep(asked, 1000, @"Thinking"), 1000,
                                                                @{@"state": @"tooSlow"}, 1500));
    NSArray *answered = SideChatAsideAnswered(asked, 1000, @{@"state": @"answered", @"text": @"Because it holds the "
                                                             "cart.\n```sh\nnpm test\n```", @"cacheRead": @90000},
                                              1500);
    say(@"Answered: its words as read, and cut into prose and code", answered);
    say(@"Told to the page: without its words as read", SideChatAsidesShown(answered));
    say(@"Answered again: kept as it was", SideChatAsideAnswered(answered, 1000, @{@"state": @"stopped"}, 1600));
    say(@"Asked again once it's answered", @(SideChatAsideAsked(answered, @"And the tests?", nil, 2000).count));
    say(@"Answered with no words: didn't answer", SideChatAsideAnswered(asked, 1000, @{@"state": @"answered"}, 1500));
    say(@"A state it doesn't know: didn't answer", SideChatAsideAnswered(asked, 1000, @{@"state": @"odd"}, 1500));
    say(@"Your plan's limit, with when it resets", SideChatAsideAnswered(asked, 1000,
        @{@"state": @"limit", @"resetsAt": @9000, @"text": @"ignored"}, 1500));
    NSArray *signedOut = SideChatAsideAnswered(asked, 1000, @{@"state": @"signedOut", @"signIn": @"claude auth login"},
                                               1500);
    say(@"Signed out, with the command that signs it in", signedOut);
    say(@"…which the page isn't told", SideChatAsidesShown(signedOut));
    say(@"No command found to run", SideChatAsideAnswered(asked, 1000, @{@"state": @"noCommand"}, 1500));
    NSArray *failed = SideChatAsideAnswered(asked, 1000, @{@"state": @"apiError", @"status": @400}, 1500);
    say(@"An error its provider sent back", failed);
    NSArray *sent = SideChatAsideSent(failed, 1000, 2000);
    say(@"…then sent the normal way (Wait for Its Turn)", sent);
    say(@"…but never one still being asked", SideChatAsideSent(asked, 1000, 2000));
    say(@"…nor one already sent", SideChatAsideSent(sent, 1000, 3000));
    say(@"Two presses for one question: the first may send it, the second finds it sent, so its words go in once",
        @[@(!!SideChatAsideSendable(failed, 1000)), @(!!SideChatAsideSendable(sent, 1000))]);
    say(@"Its words taken back: back to its failed line, to send again", SideChatAsideUnsent(sent, 1000));
    say(@"…and sendable again", @(!!SideChatAsideSendable(SideChatAsideUnsent(sent, 1000), 1000)));
    say(@"One not sent: unsent, kept as it was", SideChatAsideUnsent(failed, 1000));
    say(@"Couldn't be asked once pressed: kept, not asked",
        SideChatAsideNotAsked(answered, @"And the tests?", nil, 2000));
    say(@"The question asked at a time not asked: none", SideChatAsideAt(asked, 5));
    NSArray *remembered = SideChatAsideAnswered(SideChatAsideAsked(answered, @"And the tests?", nil, 2000), 2000,
                                                @{@"state": @"answered", @"text": @"They pass.", @"remembered": @1},
                                                2500);
    say(@"Answered, with how many earlier ones the side conversation knew", SideChatAsideAt(remembered, 2000));
    NSArray *stopped = SideChatAsideAnswered(SideChatAsideAsked(remembered, @"Stopped?", nil, 2600), 2600,
                                             @{@"state": @"stopped"}, 2700);
    NSArray *five = SideChatAsideAsked(SideChatAsideNotAsked(stopped, @"Not asked?", nil, 2800), @"Which file?", nil,
                                       3000);
    say(@"The earlier ones its agent is told, before the one asked now: only those answered with words",
        SideChatAsidesEarlier(five, 3000));
    say(@"…none before the first", SideChatAsidesEarlier(remembered, 1000));
    NSArray *underTask = SideChatAsideAnswered(SideChatAsideAsked(nil, @"Which step?", @"About your task: ", 1000),
                                               1000, @{@"state": @"answered", @"text": @"Step 2."}, 1500);
    say(@"Asked under a task: kept with the words that opened it", underTask.firstObject);
    say(@"…as its agent was asked it, and Copy the Question copies it", SideChatAsideLine(underTask.firstObject));
    say(@"…and told to a later question's copy with them", SideChatAsidesEarlier(underTask, 2000));
    say(@"…not asked: kept with them too", SideChatAsideNotAsked(nil, @"Which step?", @"About your task: ", 1000));

    printf("\n== Asked on the side, through its agent as you press\n");
    SideChatSampleAgent *agent = [SideChatSampleAgent new];
    Row *asker = [[Row alloc] initWithFields:@{@"sessionId": @"sample-aside"}];
    NSArray *(^now)(void) = ^NSArray *(void) {
        NSMutableArray *out = [NSMutableArray array];
        for (NSDictionary *aside in module.asides[@"sample-aside"])
            [out addObject:[NSString stringWithFormat:@"%@ %@%@", aside[@"question"], aside[@"state"],
                            aside[@"step"] ? [NSString stringWithFormat:@" (%@)", aside[@"step"]] : @""]];
        return out;
    };
    [module ask:@"Why that file?" opening:nil of:asker sessionId:@"sample-aside" through:agent at:1000];
    say(@"The first: being asked", now());
    agent.step(@"Thinking");
    say(@"…its agent says it's thinking", now());
    agent.step(@"Reading cart.ts");
    say(@"…then reading", now());
    agent.done(@{@"state": @"answered", @"text": @"It holds the cart."});
    say(@"…then answered: its step gone", now());
    [module ask:@"And the tests?" opening:nil of:asker sessionId:@"sample-aside" through:agent at:2000];
    agent.step(@"Running git log");
    say(@"A follow-up, on a step", now());
    agent.done(@{@"state": @"answered", @"text": @"They pass."});
    say(@"…then answered", now());
    [module ask:@"And now?" opening:nil of:asker sessionId:@"sample-aside" through:agent at:3000];
    say(@"Another: being asked", now());
    [module ask:@"One more?" opening:nil of:asker sessionId:@"sample-aside" through:agent at:3500];
    say(@"…another while it's being asked: not asked", now());
    agent.done(@{@"state": @"tooSlow"});
    agent.refuses = YES;
    [module ask:@"Still there?" opening:nil of:asker sessionId:@"sample-aside" through:agent at:4000];
    say(@"One that couldn't start: didn't answer", now());
    agent.whyNot = @{@"why": @"noConversation"};
    [module ask:@"Anything?" opening:nil of:asker sessionId:@"sample-aside" through:agent at:5000];
    say(@"One its agent says can't be asked now: not asked", now());
    agent.whyNot = nil;
    agent.refuses = NO;
    [module ask:@"Where is it?" opening:@"About your task \u201cSearch box\u201d (step 2 of 3): " of:asker
      sessionId:@"sample-aside" through:agent at:6000];
    say(@"One asked under a task: its agent is asked it after the words that open it", agent.asked);
    say(@"…and the chat keeps your question alone", now().lastObject);

    printf("\n== A reply, cut into prose and code\n");
    say(@"Prose, a command, prose", ReplyParts(@"Okay: the smaller migration first.\n```sh\nnpm run migrate -- "
                                               "--dry-run\n```\nThen I carry on."));
    say(@"A fence left open runs to the end", ReplyParts(@"Try:\n~~~\nls -la"));
    say(@"Nothing", ReplyParts(nil));
    return 0;
}
