// OneTaskModule: its face for the core (contracts/Module.h). A session hands the user a task with ask-panel.sh task,
// and asks for the answer with ask-panel.sh task-answer: both only show something, so they need none of a session's
// switches (only One Task on, in Settings). Each session's tasks and answers are kept apart
// (AppDir/one-task/<session>/record.json, TaskRecord.h), found by the session the core found asking, never by anything
// the task says, and they go once the session's process ends or its row goes. A team's lead's record also keeps the
// picks it sends itself (ask-panel.sh task --pick-for), placed by the queue its row carries (the team module's
// team.queue). It sends the page what waits (setTasks), for the view beside the list, and takes your answers back
// (taskAnswer, taskPutBack), copies a task's command and opens its links for you (taskCopy, taskOpen), always from
// the task as it was checked, never from what the page says. A row in Settings turns it off. While something waits,
// the pawn menu has One Task, which opens it, with how many wait as the page counts them (oneTaskWaiting). It has the
// print runs --print-tasks and --print-task-asks.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import "Module.h"
#import "Core.h"
#import "Files.h"
#import "Links.h"
#import "Log.h"
#import "Menus.h"
#import "Modules.h"
#import "Page.h"
#import "PanelWindow.h"
#import "Processes.h"
#import "Text.h"
#import "Printing.h"
#import "Row.h"
#import "SessionAsks.h"
#import "Send.h"
#import "Task.h"
#import "TaskRecord.h"
#include <signal.h>

// The longest task a session's ask may carry once decoded: a task within Task.h's limits is well under it.
static const NSUInteger kMostTask = 12000;
// How long a session's row may be missing from the list before its tasks go: one read can miss a row now and then.
static const NSTimeInterval kRowGoneAfter = 60;
// How long words typed into a session may go without its own record showing it took them before the talk says so.
static const double kTakenWithinMs = 5000;
// Settings' switch, on unless you turn it off: while it's off nothing shows, and a session that sends a task is told.
static NSString *const kOneTaskOn = @"oneTask";
// How One Task works, as its page on the panel's back sets it: who may hand you tasks (any session, or only a team's
// lead), whether each task says why it's where it is, whether a task to do now waits for your Go, whether the talk is
// under each task, and whether words written while a session works go in by themselves or wait for Send Now. The order
// itself isn't a choice: each ticket's own priority (the page's order.js). Each default is what One Task
// recommends.
static NSString *const kWho = @"oneTaskWho", *const kWhy = @"oneTaskWhy", *const kWaitForGo = @"oneTaskWaitForGo",
                *const kTalk = @"oneTaskTalk", *const kHeld = @"oneTaskHeld";
static NSDictionary *OneTaskDefaults(void) {
    return @{kWho: @"any", kWhy: @NO, kWaitForGo: @YES, kTalk: @YES, kHeld: @"self"};
}
// One Task's page under Tools, as the panel's back names it.
static NSString *const kPageId = @"one-task";
static NSString *Chosen(NSString *key) {
    NSString *value = [NSUserDefaults.standardUserDefaults stringForKey:key];
    return value ?: OneTaskDefaults()[key];
}
static NSString *const kOff = @"refused: One Task is off: the user can turn it on in Settings ▸ One Task";
// The way past "Whozmove needs the Accessibility permission", on the talk's button, and where it goes.
static NSString *const kAccessibilityWay = @"Open Accessibility Settings";
static NSString *const kAccessibilitySettings = @"x-apple.systempreferences:com.apple.preference.security?"
                                                 "Privacy_Accessibility";

@interface OneTaskModule : NSObject <Module>
@property (weak) Core *core;
// Each session's record, by its id, as on disk: read once, then kept here, as this module is its only writer.
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *records;
// When each session with tasks was first found missing from the list.
@property (strong) NSMutableDictionary<NSString *, NSDate *> *missingSince;
// What the page was last told, so it's told only when that changes.
@property (copy) NSString *told;
// The pawn menu's One Task, shown while something waits.
@property (strong) NSMenuItem *menuItem;
// The rows as last listed, by session: where the talk's words go, and how far they've got.
@property (copy) NSDictionary<NSString *, Row *> *listed;
// The replies to your words, by "session task at", read from the session as its turn ended and cut into prose and code
// (TaskReplyParts): held here only, never kept. Those being read now, so each is asked once at a time; and those read
// again after Whozmove restarted, so each is read again only once.
@property (strong) NSMutableDictionary<NSString *, NSArray *> *replies;
@property (strong) NSMutableSet<NSString *> *reading, *readAgain;
// Set by the print run for the state with teams not shown, so its tests never depend on this Mac's own settings.
@property (assign) BOOL printTeamsOff;
@end

static int PrintTaskAsks(Core *core, NSArray<NSString *> *arguments);

// Whether a session id can name a folder: letters, digits and dashes, as Claude Code's are (the check every module
// makes of one).
static BOOL PlainSessionId(NSString *sessionId) {
    return IsPlainId(sessionId, 128);
}

static NSString *TasksDir(void) {
    return AppDir(@"one-task");
}

static NSString *RecordPath(NSString *sessionId) {
    return [[TasksDir() stringByAppendingPathComponent:sessionId] stringByAppendingPathComponent:@"record.json"];
}

// Now, in whole milliseconds since 1970.
static double Now(void) {
    return floor(NSDate.date.timeIntervalSince1970 * 1000);
}

// Whether the process that sent a record's tasks is still the same one running.
static BOOL ProcessStill(NSDictionary *record) {
    pid_t pid = AsNumber(record[@"pid"]).intValue;
    long long started = AsNumber(record[@"processStart"]).longLongValue;
    return pid > 0 && started && ProcessStartedAt(pid) == started;
}

@implementation OneTaskModule

+ (NSString *)moduleName {
    return @"one-task";
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.missingSince = [NSMutableDictionary dictionary];
    self.replies = [NSMutableDictionary dictionary];
    self.reading = [NSMutableSet set];
    self.readAgain = [NSMutableSet set];
    NSMutableDictionary *defaults = [OneTaskDefaults() mutableCopy];
    defaults[kOneTaskOn] = @YES;
    [NSUserDefaults.standardUserDefaults registerDefaults:defaults];
    return self;
}

#pragma mark - Each session's record

// Every session's record, read from disk the first time it's needed.
- (NSMutableDictionary<NSString *, NSDictionary *> *)allRecords {
    if (self.records) return self.records;
    self.records = [NSMutableDictionary dictionary];
    for (NSString *sessionId in [NSFileManager.defaultManager contentsOfDirectoryAtPath:TasksDir() error:nil]) {
        NSDictionary *record = PlainSessionId(sessionId) ? AsRecord(ReadJSON(RecordPath(sessionId))) : nil;
        if (record) self.records[sessionId] = record;
    }
    return self.records;
}

// A session's record, or nil; one whose process has ended is gone, and taken away.
- (NSDictionary *)recordOf:(NSString *)sessionId {
    if (!PlainSessionId(sessionId)) return nil;
    NSDictionary *record = self.allRecords[sessionId];
    if (record && !ProcessStill(record)) {
        [self forget:sessionId];
        return nil;
    }
    return record;
}

// Keeps a session's record, on disk and here; NO if it couldn't be written, when nothing changes.
- (BOOL)keep:(NSDictionary *)record of:(NSString *)sessionId {
    if (!PlainSessionId(sessionId)) return NO;
    NSString *dir = [TasksDir() stringByAppendingPathComponent:sessionId];
    NSFileManager *files = NSFileManager.defaultManager;
    [files createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700}
                           error:nil];
    NSData *json = [NSJSONSerialization isValidJSONObject:record]
        ? [NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingSortedKeys error:nil] : nil;
    if (!json || ![json writeToFile:RecordPath(sessionId) atomically:YES]) {
        LogProblem([NSString stringWithFormat:@"one-task: couldn't keep %@'s tasks", sessionId]);
        return NO;
    }
    [files setAttributes:@{NSFilePosixPermissions: @0600} ofItemAtPath:RecordPath(sessionId) error:nil];
    self.allRecords[sessionId] = record;
    [self tell];
    return YES;
}

- (void)forget:(NSString *)sessionId {
    if (!PlainSessionId(sessionId)) return;
    [self.allRecords removeObjectForKey:sessionId];
    [self.missingSince removeObjectForKey:sessionId];
    [NSFileManager.defaultManager removeItemAtPath:[TasksDir() stringByAppendingPathComponent:sessionId] error:nil];
    [self tell];
}

- (void)rows:(NSArray<Row *> *)rows phase:(RowPhase)phase {
    if (phase != RowPhaseListed || self.core.printing) return;
    NSMutableSet *listed = [NSMutableSet set];
    for (Row *row in rows)
        if (row.sessionId) [listed addObject:row.sessionId];
    [self dropEndedBut:listed at:NSDate.date];
    for (Row *row in rows) [self placePicks:row];
    NSMutableDictionary *bySession = [NSMutableDictionary dictionary];
    for (Row *row in rows)
        if (row.sessionId) bySession[row.sessionId] = row;
    self.listed = bySession;
    [self talkOn];
    [self tell];
}

// The lead's picks, placed by its queue (the team module's team.queue, which only the lead's row has): each pick it sent
// itself, by id, in its order, with how pressing its job is, which puts a Critical or P0 pick ahead of the line (the
// page's order.js). A row without a queue places nothing.
- (void)placePicks:(Row *)row {
    if (!PlainSessionId(row.sessionId) || row.pid <= 0) return;
    NSDictionary *record = self.allRecords[row.sessionId];
    NSArray *queue = AsList(row.team[@"queue"]);
    if (!queue || !record) return;
    NSMutableArray *ids = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSString *> *priorities = [NSMutableDictionary dictionary];
    for (id one in queue) {
        NSString *pick = AsText(AsRecord(one)[@"id"]);
        if (!pick) continue;
        [ids addObject:pick];
        if (AsText(AsRecord(one)[@"priority"])) priorities[pick] = AsText(AsRecord(one)[@"priority"]);
    }
    NSDictionary *placed = TaskRecordQueue(record, ids, priorities, Now());
    if (placed != record) [self keep:placed of:row.sessionId];
}

// Each session's tasks go once the process that sent them has ended; or once its row has gone, at once when that
// process now runs another listed session (a /clear started another conversation in it), else after a minute missing,
// as one read can miss a row. `listed`: the sessions whose rows are listed, or nil to look only at their processes.
- (void)dropEndedBut:(NSSet<NSString *> *)listed at:(NSDate *)now {
    for (NSString *sessionId in self.allRecords.allKeys) {
        NSDictionary *record = [self recordOf:sessionId];
        if (!record || !listed) continue;
        if ([listed containsObject:sessionId]) {
            [self.missingSince removeObjectForKey:sessionId];
            continue;
        }
        pid_t found = 0;
        Row *runs = [self.core sessionOfProcess:AsNumber(record[@"pid"]).intValue found:&found];
        NSDate *since = self.missingSince[sessionId] ?: now;
        self.missingSince[sessionId] = since;
        if ((runs && ![runs.sessionId isEqual:sessionId] && [listed containsObject:runs.sessionId])
            || [now timeIntervalSinceDate:since] >= kRowGoneAfter)
            [self forget:sessionId];
    }
}

// Your answer to one of a session's tasks, a comment as any other: the task no longer waits.
- (void)answer:(NSString *)taskId of:(NSString *)sessionId with:(NSString *)answer note:(NSString *)note {
    NSDictionary *record = [self recordOf:sessionId];
    if (!record) return;
    if ([self keep:TaskRecordAnswer(record, taskId, answer, note, Now()) of:sessionId])
        PanelLog(@"one-task: %@'s %@ answered %@", sessionId, Clip(taskId, 64), Clip(answer, 40));
}

- (void)putBack:(NSString *)taskId of:(NSString *)sessionId {
    NSDictionary *record = [self recordOf:sessionId];
    if (record) [self keep:TaskRecordPutBack(record, taskId, Now()) of:sessionId];
}

#pragma mark - The talk about a task

// Where words about a task go: the session that sent it, or for the lead's pick, its member (its `for`, a session that
// counted as that member when the pick was sent) unless you chose the lead; once the talk has begun, the session it
// began with. Nil while that session isn't listed. Never a session the page or a task names: a record whose talk names
// any other session takes no words at all.
- (Row *)talkRowFor:(NSDictionary *)entry of:(NSString *)sessionId toLead:(BOOL)toLead {
    BOOL isPick = [entry[@"pick"] boolValue];
    NSString *member = isPick ? AsText(entry[@"for"]) : nil;
    NSString *to = AsText(AsRecord(entry[@"talk"])[@"to"]);
    if (!to) to = member && !toLead ? member : sessionId;
    // Only the session itself, or the member the pick is for now, and while its own row still places it on the lead's
    // team: a talk with a member it's no longer for, or that has left the team, stops there.
    if (![to isEqual:sessionId] && !(member && [to isEqual:member])) return nil;
    if (![to isEqual:sessionId] && self.listed[sessionId] && ![self stillOnTeam:to of:self.listed[sessionId]]) return nil;
    return PlainSessionId(to) ? self.listed[to] : nil;
}

// The terminal a session runs in, by name, as the talk says where it is ("Ghostty"), or nil.
- (NSString *)terminalNameOf:(Row *)row {
    return row && ![self.core.send conversationHostOf:row] ? [self.core.send terminalOf:row].name : nil;
}

// The lead's name as the list shows it, for the line a member gets.
- (NSString *)leadNameOf:(NSString *)sessionId {
    Row *lead = self.listed[sessionId];
    return AsText(lead.team[@"name"]) ?: lead.name ?: @"";
}

- (NSDictionary *)entryOf:(NSString *)taskId in:(NSString *)sessionId {
    for (NSDictionary *each in TaskRecordWaiting([self recordOf:sessionId]))
        if ([each[@"task"][@"id"] isEqual:taskId]) return each;
    return nil;
}

// Your words about the task the page names (as you saw it): held in its record, then typed in at once if the session
// can take them now, as you pressed Send.
- (void)say:(NSDictionary *)message {
    if (!SwitchedOn(kTalk)) return;
    NSDictionary *task = [self taskOf:message];
    NSString *sessionId = AsText(message[@"sessionId"]), *words = AsText(message[@"words"]);
    if (!task || words.length > TaskMostTalkLine) return;
    NSDictionary *entry = [self entryOf:task[@"id"] in:sessionId];
    BOOL toLead = [entry[@"pick"] boolValue] && [AsText(message[@"to"]) isEqual:@"lead"];
    Row *row = [self talkRowFor:entry of:sessionId toLead:toLead];
    if (!row) return;
    BOOL member = ![row.sessionId isEqual:sessionId];
    NSString *line = TaskTalkLine(task, member ? [self leadNameOf:sessionId] : nil, words), *why = nil;
    if (!line) return;
    NSDictionary *record = [self recordOf:sessionId];
    NSDictionary *next = TaskRecordSay(record, task[@"id"], words, line, row.sessionId,
                                       !member && [entry[@"pick"] boolValue], Now(), &why);
    if (!next || ![self keep:next of:sessionId]) return;
    PanelLog(@"one-task: words about %@'s %@ for %@", sessionId, Clip(task[@"id"], 64), row.sessionId);
    NSDictionary *said = AsList(AsRecord([self entryOf:task[@"id"] in:sessionId][@"talk"])[@"says"]).lastObject;
    [self tryToSay:said about:task[@"id"] of:sessionId pressed:YES];
}

// Your words as they'd go in, put on the clipboard (Copy and Go): the page then takes you to the session.
- (void)copyTalk:(NSDictionary *)message {
    NSDictionary *task = [self taskOf:message];
    NSString *sessionId = AsText(message[@"sessionId"]), *words = AsText(message[@"words"]);
    if (!task || words.length > TaskMostTalkLine) return;
    NSDictionary *entry = [self entryOf:task[@"id"] in:sessionId];
    BOOL toLead = [entry[@"pick"] boolValue] && [AsText(message[@"to"]) isEqual:@"lead"];
    Row *row = [self talkRowFor:entry of:sessionId toLead:toLead];
    if (!row) return;
    BOOL member = ![row.sessionId isEqual:sessionId];
    NSString *line = TaskTalkLine(task, member ? [self leadNameOf:sessionId] : nil, words);
    if (!line) return;
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:line forType:NSPasteboardTypeString];
    PanelLog(@"one-task: words about %@'s %@ copied for %@", sessionId, Clip(task[@"id"], 64), row.sessionId);
}

// Whether words can go into a session now, as far as its row tells: idle at its prompt with nothing asked of you and
// nothing else from the panel going in. Send checks again, and before each key.
- (BOOL)takesWords:(Row *)row {
    return row && ([row.status isEqual:@"idle"] || [row.status isEqual:@"shell"]) && !row.ask
        && ![self.core.send typingInto:row.sessionId];
}

// Held words go in once the session can take them: at once for your press, and by themselves only into a terminal
// that isn't the app in front at all (Send's ReachGoesByItself: the tab it shows may have changed since it last said),
// asked again before each key (Send's stillAway:), so nothing types where you're typing, and Claude Desktop never comes
// forward without your press. When none of it can go in, it's
// `refused`, with why and the way past it (the terminal's own, or Accessibility's), and you can copy it and go there;
// while another change from the panel is still going in, words that go by themselves wait for it.
- (void)tryToSay:(NSDictionary *)said about:(NSString *)taskId of:(NSString *)sessionId pressed:(BOOL)pressed {
    if (![said[@"state"] isEqual:@"held"]) return;
    NSDictionary *entry = [self entryOf:taskId in:sessionId];
    Row *row = [self talkRowFor:entry of:sessionId toLead:NO];
    if (![self takesWords:row]) return;
    BOOL desktop = !![self.core.send conversationHostOf:row];
    // Words that wait for your Send Now never go in by themselves.
    if (!pressed && [Chosen(kHeld) isEqual:@"wait"]) return;
    SessionReach *reach = [self.core.send reachOf:row];
    if (!pressed && !ReachGoesByItself(reach, row.focused,
                                       NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier)) return;
    double at = AsNumber(said[@"at"]).doubleValue;
    NSString *where = desktop ? @"Claude Desktop" : [self terminalNameOf:row];
    NSString *refused = WhyNoWords(reach, @"sent from here", @"say it there");
    if (refused && !pressed && [refused isEqual:kStillChanging]) return;
    if (refused) {
        NSString *way = WayPast(reach, refused) ?: (reach.desktop && !reach.mayControl ? kAccessibilityWay : nil);
        [self keep:TaskRecordTalkState([self recordOf:sessionId], taskId, at,
                                       @{@"state": @"refused", @"why": refused, @"way": way ?: NSNull.null,
                                         @"permission": @(way == kAccessibilityWay), @"where": where ?: NSNull.null})
                 of:sessionId];
        PanelLog(@"one-task: words about %@'s %@ not typed in", sessionId, Clip(taskId, 64));
        return;
    }
    [self keep:TaskRecordTalkState([self recordOf:sessionId], taskId, at, @{@"state": @"typing"}) of:sessionId];
    __weak typeof(self) weakSelf = self;
    [self.core.send say:said[@"line"] row:row reach:reach here:@"sent from here" there:@"say it there"
                   also:pressed ? nil : [self.core.send stillAway:row] done:^(NSString *why, NSString *way) {
        NSDictionary *record = [weakSelf recordOf:sessionId];
        if (!record) return;
        NSDictionary *change = why ? @{@"state": @"stopped", @"why": why, @"way": way ?: NSNull.null,
                                       @"where": where ?: NSNull.null}
                                   : @{@"state": @"typed", @"typedAt": @(Now())};
        [weakSelf keep:TaskRecordTalkState(record, taskId, at, change) of:sessionId];
        PanelLog(@"one-task: words about %@'s %@ %@", sessionId, Clip(taskId, 64), why ? @"stopped" : @"typed in");
    }];
}

// What a reply to words said at `at` about a task is held by.
static NSString *ReplyKey(NSString *sessionId, NSString *taskId, double at) {
    return [NSString stringWithFormat:@"%@ %@ %.0f", sessionId, taskId, at];
}

// Words a session's own record shows it took, since `since`: the line they were typed as, as its hook keeps a prompt
// (on one line, its spaces run together, cut with "…").
static BOOL TookLine(Row *row, NSString *line, double since) {
    NSString *(^squeeze)(NSString *) = ^NSString *(NSString *text) {
        NSArray *words = [text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        return [[words filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]]
                componentsJoinedByString:@" "];
    };
    NSString *prompt = row.lastPrompt ?: @"";
    if (row.lastPromptAt.doubleValue < since - 2000) return NO;
    if ([prompt hasSuffix:@"…"]) prompt = [prompt substringToIndex:prompt.length - 1];
    NSString *took = squeeze(prompt);
    return took.length && [squeeze(line) hasPrefix:took];
}

// The talk moves on as the rows do: held words go in once they can, typed ones are taken (the session's own record
// shows them) or not, and a taken one's reply is read as the session's turn ends.
- (void)talkOn {
    double now = Now();
    for (NSString *sessionId in self.allRecords.allKeys)
        for (NSDictionary *entry in TaskRecordWaiting(self.allRecords[sessionId])) {
            NSArray *says = AsList(AsRecord(entry[@"talk"])[@"says"]);
            // Words about a task taken back go with it, never typed in.
            if (!says.count || entry[@"takenBack"]) continue;
            NSString *taskId = entry[@"task"][@"id"];
            Row *row = [self talkRowFor:entry of:sessionId toLead:NO];
            for (NSDictionary *said in says) {
                NSString *state = said[@"state"];
                double at = AsNumber(said[@"at"]).doubleValue, typedAt = AsNumber(said[@"typedAt"]).doubleValue;
                NSDictionary *change = nil;
                if ([state isEqual:@"held"]) {
                    [self tryToSay:said about:taskId of:sessionId pressed:NO];
                    break;  // one at a time, in order
                }
                if (([state isEqual:@"typed"] || [state isEqual:@"notTaken"]) && row) {
                    if (TookLine(row, said[@"line"], typedAt))
                        change = @{@"state": @"sent", @"sentAt": row.lastPromptAt ?: @(now)};
                    else if ([state isEqual:@"typed"] && now - typedAt > kTakenWithinMs)
                        change = @{@"state": @"notTaken"};
                } else if ([state isEqual:@"sent"] && row && [self takesWords:row]
                           && row.lastReplyAt.doubleValue > AsNumber(said[@"sentAt"]).doubleValue) {
                    [self readReplyTo:said about:taskId of:sessionId row:row];
                } else if ([state isEqual:@"replied"] && row && !self.replies[ReplyKey(sessionId, taskId, at)]
                           && ![self.readAgain containsObject:ReplyKey(sessionId, taskId, at)]) {
                    // Read before Whozmove restarted: read again, once, as nothing of it was kept.
                    [self.readAgain addObject:ReplyKey(sessionId, taskId, at)];
                    [self readReplyTo:said about:taskId of:sessionId row:row];
                }
                if (change) {
                    NSDictionary *record = self.allRecords[sessionId];
                    [self keep:TaskRecordTalkState(record, taskId, at, change) of:sessionId];
                }
            }
        }
}

// What the session answered your words: its whole reply in the turn whose prompt is exactly the line typed in, read by
// its agent off the main thread (AgentWork's replyTo:, 16 KB at most), cut into prose and code, and held in memory
// only. Words sent are `replied` once it has one, or `noReply` when that turn ended without words.
- (void)readReplyTo:(NSDictionary *)said about:(NSString *)taskId of:(NSString *)sessionId row:(Row *)row {
    double at = AsNumber(said[@"at"]).doubleValue;
    NSString *key = ReplyKey(sessionId, taskId, at);
    if ([self.reading containsObject:key]) return;
    id<Agent> agent = [self.core agentOf:row];
    NSNumber *ended = row.lastReplyAt ?: @(Now());
    __weak typeof(self) weakSelf = self;
    void (^took)(NSString *) = ^(NSString *reply) {
        [weakSelf.reading removeObject:key];
        NSArray *parts = TaskReplyParts(reply);
        if (parts.count) weakSelf.replies[key] = parts;
        NSDictionary *record = weakSelf.allRecords[sessionId];
        NSString *now = AsText(AsRecord([weakSelf saidAt:at about:taskId in:record])[@"state"]);
        if ([now isEqual:@"sent"])
            [weakSelf keep:TaskRecordTalkState(record, taskId, at, @{@"state": parts.count ? @"replied" : @"noReply",
                                                                     @"repliedAt": ended}) of:sessionId];
        else [weakSelf tell];
    };
    if (![agent conformsToProtocol:@protocol(AgentWork)]) {
        took(nil);
        return;
    }
    [self.reading addObject:key];
    // Typed in just before it was taken: a little before, for the session's own clock.
    double since = (AsNumber(said[@"typedAt"]).doubleValue ?: AsNumber(said[@"sentAt"]).doubleValue) - 2000;
    [(id<AgentWork>)agent replyTo:said[@"line"] of:row.sessionId since:since done:took];
}

// What's said at `at` about `taskId` in `record`, as kept now.
- (NSDictionary *)saidAt:(double)at about:(NSString *)taskId in:(NSDictionary *)record {
    for (NSDictionary *entry in TaskRecordWaiting(record))
        if ([entry[@"task"][@"id"] isEqual:taskId])
            for (NSDictionary *said in AsList(AsRecord(entry[@"talk"])[@"says"]))
                if (AsNumber(said[@"at"]).doubleValue == at) return said;
    return nil;
}

// A code block of a reply you asked about, put on the clipboard (the reply's Copy): exactly what was between its
// fences, from the reply as the app read it, never anything the page says. Nothing in it is ever run.
- (void)copyReplyPart:(NSDictionary *)message {
    NSDictionary *task = [self taskOf:message];
    NSString *sessionId = AsText(message[@"sessionId"]);
    NSArray *parts = task ? self.replies[ReplyKey(sessionId, task[@"id"], AsNumber(message[@"at"]).doubleValue)] : nil;
    NSInteger n = AsNumber(message[@"part"]).integerValue;
    NSString *code = n >= 0 && n < (NSInteger)parts.count ? AsText(AsRecord(parts[(NSUInteger)n])[@"code"]) : nil;
    if (!code) return;
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:code forType:NSPasteboardTypeString];
    PanelLog(@"one-task: a block of %@'s reply about %@ copied", sessionId, Clip(task[@"id"], 64));
}

// The talk as the page shows it: what's kept, each reply read (only while the app runs), where it goes, and the
// lines that open the words, so the box shows exactly what will go in.
- (NSDictionary *)talkOf:(NSDictionary *)entry in:(NSString *)sessionId {
    NSMutableDictionary *talk = [AsRecord(entry[@"talk"]) mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableArray *says = [NSMutableArray array];
    for (NSDictionary *said in AsList(talk[@"says"])) {
        NSMutableDictionary *one = [said mutableCopy];
        [one removeObjectForKey:@"line"];
        NSArray *reply = self.replies[ReplyKey(sessionId, entry[@"task"][@"id"], AsNumber(said[@"at"]).doubleValue)];
        if (reply) one[@"reply"] = reply;
        [says addObject:one];
    }
    talk[@"says"] = says;
    talk[@"lead"] = TaskTalkLead(entry[@"task"], nil);
    // The terminal each session the talk may be with runs in, for where its heading says it is, and those of them
    // whose terminal is the app in front, where held words wait for your press (Send's ReachTerminalInFront).
    NSMutableDictionary *terminals = [NSMutableDictionary dictionary];
    NSMutableArray *inFront = [NSMutableArray array];
    NSString *front = NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier;
    for (NSString *one in @[sessionId, AsText(entry[@"for"]) ?: @""]) {
        Row *row = one.length ? self.listed[one] : nil;
        NSString *name = [self terminalNameOf:row];
        if (name) terminals[one] = name;
        if (name && ReachTerminalInFront([self.core.send reachOf:row], front)) [inFront addObject:one];
    }
    talk[@"terminals"] = terminals;
    talk[@"inFront"] = inFront;
    if ([entry[@"pick"] boolValue])
        talk[@"leadForMember"] = TaskTalkLead(entry[@"task"], [self leadNameOf:sessionId]);
    return talk;
}

#pragma mark - The page

- (void)pageLoaded {
    self.told = nil;
    [self tell];
}

// What waits, for the view beside the list: each session's tasks as they were checked, each { sessionId, task, at,
// back }, and whether One Task is on. Told only when it changes.
- (void)tell {
    if (self.core.printing) return;
    BOOL on = SwitchedOn(kOneTaskOn), teams = [self teamsShown];
    NSMutableArray *tasks = [NSMutableArray array], *turnedAway = [NSMutableArray array];
    for (NSString *sessionId in [self.allRecords.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        // A session that may not hand you tasks now: what it sent before waits unseen, until you let it again.
        Row *row = self.listed[sessionId];
        if (on && row && ![self mayHand:row]) {
            if (TaskRecordWaiting(self.allRecords[sessionId]).count) [turnedAway addObject:sessionId];
            continue;
        }
        for (NSDictionary *each in on ? TaskRecordWaiting(self.allRecords[sessionId]) : @[]) {
            // A pick the lead sent itself shows only once its queue names it, and only while teams show.
            if ([each[@"pick"] boolValue] && (![each[@"shown"] boolValue] || !teams)) continue;
            NSMutableDictionary *one = [each mutableCopy];
            one[@"sessionId"] = sessionId;
            one[@"talk"] = [self talkOf:each in:sessionId];
            [tasks addObject:one];
        }
    }
    // The kinds' words come with them, from the task's contract (TaskKindWords), the one copy there is; and the rules
    // its page on the back sets, which the page orders, explains and holds by, with the sessions they turn away.
    NSDictionary *rules = @{@"why": @(SwitchedOn(kWhy)), @"waitForGo": @(SwitchedOn(kWaitForGo)),
                            @"talk": @(SwitchedOn(kTalk)), @"held": Chosen(kHeld), @"turnedAway": turnedAway};
    NSData *json = [NSJSONSerialization dataWithJSONObject:@[tasks, @(on), rules] options:NSJSONWritingSortedKeys
                                                     error:nil];
    NSString *told = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : nil;
    if (!told || [told isEqual:self.told]) return;
    self.told = told;
    [self.core.page call:@"setTasks" with:@[tasks, @(on), TaskKindWords, rules]];
}

// The task the page names, as it waits now: only as it was sent when the page showed it (`sent`), so an answer never
// lands on a step, or words, sent after you'd read the ones before. Nil when it doesn't wait, or was sent again since.
- (NSDictionary *)taskOf:(NSDictionary *)message {
    NSString *sessionId = AsText(message[@"sessionId"]), *taskId = AsText(message[@"id"]);
    if (!SwitchedOn(kOneTaskOn) || !PlainSessionId(sessionId) || !TaskIdPlain(taskId)) return nil;
    for (NSDictionary *each in TaskRecordWaiting([self recordOf:sessionId]))
        if ([each[@"task"][@"id"] isEqual:taskId])
            return [AsNumber(each[@"sent"]) isEqual:AsNumber(message[@"sent"])] && !each[@"takenBack"] ? each[@"task"]
                                                                                                    : nil;
    return nil;
}

// The pawn menu's One Task: the panel comes up (back from hidden or the screen's edge, and back to its list from its
// back), and the page opens One Task, from the folded panel too.
- (NSArray<MenuEntry *> *)menuEntries {
    self.menuItem = [[NSMenuItem alloc] initWithTitle:@"One Task" action:@selector(openOneTask) keyEquivalent:@""];
    self.menuItem.target = self;
    self.menuItem.hidden = YES;
    return @[[MenuEntry entryIn:MenuSectionTop order:5 item:self.menuItem]];
}

- (void)openOneTask {
    PanelWindow *window = self.core.window;
    if (!self.core.page.ready) return;
    [window bringUp];
    __weak typeof(self) weakSelf = self;
    void (^open)(void) = ^{ [weakSelf.core.page call:@"openOneTask" with:@[]]; };
    if (window.folded) open();
    else [window turnOver:NO then:open];
}

- (NSDictionary<NSString *, void (^)(NSDictionary *message)> *)messages {
    __weak typeof(self) weakSelf = self;
    return @{
        // Your answer: one of the kind's own (TaskRecordFits), with what you typed, if anything.
        @"taskAnswer": ^(NSDictionary *message) {
            NSDictionary *task = [weakSelf taskOf:message];
            NSString *answer = AsText(message[@"answer"]), *note = AsText(message[@"note"]);
            note = [note stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (!task || !TaskRecordFits(task, answer) || note.length > TaskMostNote) return;
            if ([answer isEqual:@"Comment"] && !note.length) return;
            [weakSelf answer:task[@"id"] of:message[@"sessionId"] with:answer note:note.length ? note : nil];
        },
        // How many wait, as the page counts them (a session's own requests among them): the pawn menu's One Task
        // says so, and shows only while something does.
        @"oneTaskWaiting": ^(NSDictionary *message) {
            NSInteger count = MAX(0, AsNumber(message[@"count"]).integerValue);
            weakSelf.menuItem.hidden = !count || !SwitchedOn(kOneTaskOn);
            weakSelf.menuItem.title = count > 1 ? [NSString stringWithFormat:@"One Task · %ld", (long)count]
                                                : @"One Task";
        },
        // Your words about a task, to the session it's about (taskSay), and held words taken back before they go in
        // (taskTakeBack) or sent now, by your press, into the tab you're in or Claude Desktop (taskSayNow): each by
        // the task as you saw it, and what's said by when it was.
        @"taskSay": ^(NSDictionary *message) { [weakSelf say:message]; },
        @"taskTakeBack": ^(NSDictionary *message) {
            NSDictionary *task = [weakSelf taskOf:message];
            NSString *sessionId = message[@"sessionId"];
            if (task) [weakSelf keep:TaskRecordTakeBack([weakSelf recordOf:sessionId], task[@"id"],
                                                        AsNumber(message[@"at"]).doubleValue) of:sessionId];
        },
        @"taskSayNow": ^(NSDictionary *message) {
            NSDictionary *task = [weakSelf taskOf:message];
            NSString *sessionId = message[@"sessionId"];
            double at = AsNumber(message[@"at"]).doubleValue;
            for (NSDictionary *said in AsList(AsRecord([weakSelf entryOf:task[@"id"] in:sessionId][@"talk"])[@"says"]))
                if (task && AsNumber(said[@"at"]).doubleValue == at)
                    [weakSelf tryToSay:said about:task[@"id"] of:sessionId pressed:YES];
        },
        // Words that can't be typed in, put on the clipboard for you to paste in the session yourself: the line as the
        // app makes it from your words, for the session the talk is with, never anything the page says goes in.
        @"taskTalkCopy": ^(NSDictionary *message) { [weakSelf copyTalk:message]; },
        // Your own words about a task taken back while you were away (Copy Your Words): on one line, never run.
        @"taskWordsCopy": ^(NSDictionary *message) {
            NSString *words = PlainOneLine(AsText(message[@"words"]), TaskMostTalkLine);
            if (!words.length) return;
            [NSPasteboard.generalPasteboard clearContents];
            [NSPasteboard.generalPasteboard setString:words forType:NSPasteboardTypeString];
        },
        // A code block of a session's reply, by its place among the reply's parts: copied, never run.
        @"taskReplyCopy": ^(NSDictionary *message) { [weakSelf copyReplyPart:message]; },
        // The way past "Whozmove needs the Accessibility permission": its pane in System Settings, by your press.
        @"taskTalkPermission": ^(NSDictionary *message) { OpenLink(kAccessibilitySettings); },
        // A task taken back, let go by the page once you've moved on from it (or at once, when it isn't the one in
        // front): it leaves the record.
        @"taskLetGo": ^(NSDictionary *message) {
            NSString *sessionId = AsText(message[@"sessionId"]), *taskId = AsText(message[@"id"]);
            NSDictionary *record = PlainSessionId(sessionId) && TaskIdPlain(taskId) ? [weakSelf recordOf:sessionId] : nil;
            NSDictionary *next = record ? TaskRecordLetGo(record, taskId) : nil;
            if (next && next != record) [weakSelf keep:next of:sessionId];
        },
        @"taskPutBack": ^(NSDictionary *message) {
            NSDictionary *task = [weakSelf taskOf:message];
            if (task) [weakSelf putBack:task[@"id"] of:message[@"sessionId"]];
        },
        // You're on a task you've read: kept with it, through its next steps and a restart, so nothing takes its place.
        @"taskSeen": ^(NSDictionary *message) {
            NSDictionary *task = [weakSelf taskOf:message];
            if (!task) return;
            NSDictionary *record = [weakSelf recordOf:message[@"sessionId"]];
            NSDictionary *next = TaskRecordSeen(record, task[@"id"], Now());
            if (next != record) [weakSelf keep:next of:message[@"sessionId"]];
        },
        // Its command, put on the clipboard for you to run: Whozmove never runs it.
        @"taskCopy": ^(NSDictionary *message) {
            NSString *run = AsText(AsRecord([weakSelf taskOf:message][@"command"])[@"run"]);
            if (!run) return;
            [NSPasteboard.generalPasteboard clearContents];
            [NSPasteboard.generalPasteboard setString:run forType:NSPasteboardTypeString];
        },
        // One of its links, by its place among what's attached, in your browser: only the web's, as it was checked.
        @"taskOpen": ^(NSDictionary *message) {
            NSArray *attached = AsList([weakSelf taskOf:message][@"attach"]);
            NSInteger at = AsNumber(message[@"at"]).integerValue;
            NSString *url = at >= 0 && at < (NSInteger)attached.count ? AsText(AsRecord(attached[at])[@"url"]) : nil;
            NSURL *page = url ? [NSURL URLWithString:url] : nil;
            if ([page.scheme isEqual:@"https"]) OpenInWebBrowser(page);
        },
    };
}

// Settings ▸ One Task: on unless you turn it off.
// Settings' One Task row opens its page under Tools, where its switch and its choices are, saying whether it's on.
- (NSArray<SettingEntry *> *)settingEntries {
    SettingEntry *page = [SettingEntry pageWithKey:kOneTaskOn title:@"One Task" app:kPageId];
    page.said = ^NSString * { return SwitchedOn(kOneTaskOn) ? @"On" : @"Off"; };
    page.group = 20;
    page.order = 30;
    return @[page];
}

// One Task's page under Tools on the panel's back, after Storage: what it does, its own switch, then how it works, in
// groups, each choice with a line on what it does and New where it's new; while it's off, the groups under its switch
// are dimmed. Use the Recommended Settings, the back's own, puts its choices back as recommended. Quiet hours are the
// notifications module's group on this page, not One Task's.
- (NSArray<AppEntry *> *)appEntries {
    __weak typeof(self) weakSelf = self;
    void (^changed)(void) = ^{ [weakSelf tell]; };
    BOOL (^teams)(void) = ^BOOL { return [weakSelf teamsShown]; };
    void (^choose)(NSString *, NSString *) = ^(NSString *key, NSString *value) {
        [NSUserDefaults.standardUserDefaults setObject:value forKey:key];
        changed();
    };
    BOOL (^on)(void) = ^BOOL { return SwitchedOn(kOneTaskOn); };
    AppSwitch *(^toggle)(NSString *, NSString *, NSString *, BOOL) =
        ^AppSwitch *(NSString *key, NSString *title, NSString *help, BOOL isNew) {
            AppSwitch *one = [AppSwitch switchWithKey:key title:title help:help on:^BOOL { return SwitchedOn(key); }
                                                  set:^(BOOL value) {
                                                      SetSwitch(key, value);
                                                      changed();
                                                  }];
            one.isNew = isNew;
            return one;
        };
    AppEntry *page = [AppEntry appWithId:kPageId name:@"One Task"
                                    does:@"Hands you the one thing your agents need from you most, beside your "
                                         @"sessions: one at a time, with what to do and why. These are all set to "
                                         @"work as they are."
                                   order:205];
    page.tool = YES;
    page.present = ^BOOL { return YES; };

    AppGroup *itself = [AppGroup groupWithTitle:nil rows:@[toggle(kOneTaskOn, @"One Task", @"The one thing that needs "
        "you most, beside the list. While it's off, a session that hands you a task is told so.", NO)] foot:nil order:10];

    AppChoice *who = [AppChoice choiceWithKey:kWho title:@"Who may hand you tasks" choices:^NSArray * {
        return @[@{@"id": @"any", @"name": @"Any session", @"help": @"Every agent can hand you a task. Recommended."},
                 @{@"id": @"lead", @"name": @"Only a team's chief",
                   @"help": @"Only a session leading a team, with its picks for you. Others are told why."}];
    } picked:^NSString * { return Chosen(kWho); } pick:^(NSString *choice) { choose(kWho, choice); }];
    AppGroup *whoMay = [AppGroup groupWithTitle:@"Who may hand you tasks" rows:@[who]
                                           foot:@"A session that may not is told so when it asks, so its agent stops "
                                                 "asking." order:20];

    // The order, which isn't a choice: a row that can't be pressed, with nothing to pick under it.
    AppChoice *order = [AppChoice choiceWithKey:@"oneTaskOrder" title:@"What comes first" choices:^NSArray * {
        return @[];
    } picked:^NSString * { return nil; } pick:^(NSString *choice) {}];
    order.fixed = @{@"name": @"Each ticket's own priority, first come first served within it",
                    @"help": @"From each session's ticket, in its tracker's own order. Always."};
    AppGroup *first = [AppGroup groupWithTitle:@"What comes first" rows:@[
        order,
        toggle(kWhy, @"Say why each is here", @"A line on why the task in front is first, and each after it by name "
               "and why it's where it is. Off, the foot says only how many.", YES),
        toggle(kWaitForGo, @"To-do-now tasks wait for your Go", @"A task you've read stays until you leave it; one to "
               "do now asks from the top, and you come back to where you were.", YES)] foot:nil order:30];

    AppChoice *held = [AppChoice choiceWithKey:kHeld title:@"Words you write while it works" choices:^NSArray * {
        return @[@{@"id": @"self", @"name": @"Words go in once it's free", @"help": @"Written while it works, they go in "
                   "by themselves when it's done, never into the tab you're in. Recommended."},
                 @{@"id": @"wait", @"name": @"Words wait for Send Now", @"help": @"Nothing goes in until you press Send "
                   "Now."}];
    } picked:^NSString * { return Chosen(kHeld); } pick:^(NSString *choice) { choose(kHeld, choice); }];
    held.shown = ^BOOL { return SwitchedOn(kTalk); };
    AppGroup *talk = [AppGroup groupWithTitle:@"Talking with the agent" rows:@[
        toggle(kTalk, @"Talk under each task", @"A box under the task asks its session what it's about.", NO), held]
                                         foot:nil order:40];

    AppGroup *after = [AppGroup groupWithTitle:nil rows:@[] foot:@"A change applies to what comes next: the task you "
                                                                 "have open stays where it is." order:90];
    for (AppGroup *group in @[whoMay, first, talk]) group.enabled = on;
    // A team's chief means nothing while teams don't show, so the choice of one isn't offered then; but only a team's
    // chief, once chosen, stays in sight, as it turns every session away, so you can choose Any session again.
    whoMay.shown = ^BOOL { return teams() || [Chosen(kWho) isEqual:@"lead"]; };
    page.groups = @[itself, whoMay, first, talk, after];
    // As recommended while every choice is as it starts; One Task's own switch isn't a choice of how it works.
    page.recommended = ^BOOL {
        NSDictionary *defaults = OneTaskDefaults();
        for (NSString *key in defaults)
            if (![[NSUserDefaults.standardUserDefaults objectForKey:key] ?: defaults[key] isEqual:defaults[key]])
                return NO;
        return YES;
    };
    page.useRecommended = ^{
        for (NSString *key in OneTaskDefaults()) [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
        changed();
    };
    return @[page];
}

#pragma mark - What a session asks

- (NSDictionary<NSString *, SessionAsk *> *)sessionAsks {
    __weak typeof(self) weakSelf = self;
    SessionAsk *task = [SessionAsk askShowing:^NSString *(Row *row, pid_t process, NSDictionary *asked) {
        return [weakSelf take:asked from:row process:process];
    }];
    SessionAsk *answer = [SessionAsk askShowing:^NSString *(Row *row, pid_t process, NSDictionary *asked) {
        return [weakSelf answerFor:asked from:row];
    }];
    SessionAsk *withdraw = [SessionAsk askShowing:^NSString *(Row *row, pid_t process, NSDictionary *asked) {
        return [weakSelf withdraw:asked from:row];
    }];
    // Each logs what's worth keeping itself: a task sent, never the answer's note, nor each ask that finds none yet.
    task.logsItself = answer.logsItself = withdraw.logsItself = YES;
    return @{@"task": task, @"task-answer": answer, @"task-withdraw": withdraw};
}

// Whether a session may hand you tasks now: any, unless you've chosen only a team's lead, a session whose row lists
// the sessions it leads (team.leads), by session, never by any role word. While teams don't show, no session leads
// one, so that choice turns every session away: it stays yours, never widened without your press.
- (BOOL)mayHand:(Row *)row {
    return ![Chosen(kWho) isEqual:@"lead"] || AsList(row.team[@"leads"]).count > 0;
}

// Whether teams show in this Whozmove now, as the team module says (TeamFacts), never by reading its setting.
- (BOOL)teamsShown {
    return !self.printTeamsOff && [[self.core moduleThat:@protocol(TeamFacts)] teamsShown];
}

- (NSString *)take:(NSDictionary *)asked from:(Row *)row process:(pid_t)process {
    if (!SwitchedOn(kOneTaskOn)) return kOff;
    if (![self mayHand:row])
        return [self teamsShown]
            ? @"refused: the user lets only a team's chief hand them tasks: ask them in your chat instead"
            : @"refused: only a team's chief may hand the user tasks, and teams aren't shown: the user can tick "
              @"Working on Whozmove ▸ Show Teams, or choose Any session in One Task's settings";
    if (!PlainSessionId(row.sessionId)) return @"refused: Whozmove can't keep tasks for this session";
    NSString *encoded = AsText(asked[@"task64"]);
    NSData *raw = encoded ? [[NSData alloc] initWithBase64EncodedString:encoded options:0] : nil;
    if (raw.length > kMostTask)
        return [NSString stringWithFormat:@"refused: a task may be %lu KB at most: send it with less in it",
                                          (unsigned long)(kMostTask / 1000)];
    id json = raw ? [NSJSONSerialization JSONObjectWithData:raw options:0 error:nil] : nil;
    if (!json) return @"refused: Whozmove couldn't read the task: give it on stdin as JSON (docs/reference/task.md)";
    NSString *why = nil;
    NSDictionary *task = TaskFrom(json, &why);
    if (!task) return [@"refused: " stringByAppendingString:why];
    long long started = ProcessStartedAt(process);
    if (!started) return @"refused: Whozmove couldn't tell when this session's process started: try again";
    // A team's lead sending a pick for one of its members: checked as every task is, then kept in its record with
    // that member, the one it names here and nowhere else.
    if (asked[@"pickFor"]) return [self takePick:task for:AsText(asked[@"pickFor"]) from:row process:process
                                         started:started];
    // One sent from another of the session's processes (its conversation resumed) joins those waiting, and they go once
    // the process that sent last has ended.
    NSString *said = nil;
    NSDictionary *next = TaskRecordSend([self recordOf:row.sessionId], task, process, started, Now(), &said, &why);
    if (!next) return [@"refused: " stringByAppendingString:why];
    if (![self keep:next of:row.sessionId]) return @"refused: Whozmove couldn't keep the task: try again";
    PanelLog(@"one-task: %@ sent %@ (%@)", row.sessionId, task[@"id"], task[@"kind"]);
    return said;
}

// A pick from a team's lead for one of its members (ask-panel.sh task --pick-for): only from a session whose row
// lists sessions it leads (team.leads), only for one of them whose own row still has its place on the team, named by
// its session id or by its name in the team, never one two share. Being a lead is enough, as a pick only shows you
// something. Answered at once, as every task is.
- (NSString *)takePick:(NSDictionary *)task for:(NSString *)name from:(Row *)row process:(pid_t)process
               started:(long long)started {
    if (![self teamsShown])
        return @"refused: teams aren't shown in this Whozmove, so a pick can't reach One Task: the user can tick "
               @"Working on Whozmove ▸ Show Teams (holding ⌥ as they open the pawn menu)";
    NSArray *leads = AsList(row.team[@"leads"]);
    if (!leads.count) return @"refused: --pick-for is only for a team's lead, and this session leads no team: send it "
                             @"without --pick-for, as your own task";
    NSString *member = [self memberOf:row named:name why:nil];
    if (!member) {
        NSString *why = nil;
        [self memberOf:row named:name why:&why];
        return [@"refused: " stringByAppendingString:why];
    }
    NSString *said = nil, *why = nil;
    NSDictionary *next = TaskRecordPick([self recordOf:row.sessionId], task, member, process, started, Now(), &said,
                                        &why);
    if (!next) return [@"refused: " stringByAppendingString:why];
    if (![self keep:next of:row.sessionId]) return @"refused: Whozmove couldn't keep the pick: try again";
    PanelLog(@"one-task: %@ sent the pick %@ (%@) for %@", row.sessionId, task[@"id"], task[@"kind"], member);
    return said;
}

// The session of the lead's member `name` names: its session id, or its name in the team, among the sessions it leads
// whose own row still places them on the team; nil, with why, for none or two.
- (NSString *)memberOf:(Row *)lead named:(NSString *)name why:(NSString **)why {
    NSMutableArray *found = [NSMutableArray array];
    for (NSString *one in AsList(lead.team[@"leads"])) {
        if (![one isKindOfClass:NSString.class] || ![self stillOnTeam:one of:lead]) continue;
        Row *row = self.listed[one];
        if ([one isEqualToString:name] || [AsText(row.team[@"name"]) isEqualToString:name]) [found addObject:one];
    }
    if (found.count == 1) return found.firstObject;
    if (why) *why = found.count ? [NSString stringWithFormat:@"two on your team are called %@: use its session id", name]
                                : [NSString stringWithFormat:@"%@ isn't on your team", name];
    return nil;
}

// Whether `member` is still one the lead leads, and its own row still gives it its place on the team.
- (BOOL)stillOnTeam:(NSString *)member of:(Row *)lead {
    Row *row = self.listed[member];
    return [AsList(lead.team[@"leads"]) containsObject:member] && AsText(row.team[@"role"]) && !row.team[@"inFolderOf"];
}

// A session taking back a task of its own, or a lead its pick (in the lead's own record), because it was answered
// elsewhere or its job was parked or dropped: only ever the asking session's own, found by the session the core found
// asking, never by anything the ask says.
- (NSString *)withdraw:(NSDictionary *)asked from:(Row *)row {
    NSString *taskId = AsText(asked[@"id"]), *why = AsText(asked[@"why"]);
    if (!TaskIdPlain(taskId)) return @"refused: name the task by the id it was sent with";
    if (![TaskTakenBackWhys containsObject:why ?: @""])
        return [NSString stringWithFormat:@"refused: say why it's taken back, as one of %@",
                                          [TaskTakenBackWhys componentsJoinedByString:@", "]];
    NSString *said = nil;
    NSDictionary *next = TaskRecordTakeBackTask([self recordOf:row.sessionId], taskId, why, Now(), &said);
    if (next && [self keep:next of:row.sessionId])
        PanelLog(@"one-task: %@'s %@ taken back (%@)", row.sessionId, Clip(taskId, 64), why);
    return said;
}

- (NSString *)answerFor:(NSDictionary *)asked from:(Row *)row {
    NSString *taskId = AsText(asked[@"id"]);
    if (!TaskIdPlain(taskId))
        return @"refused: name the task by the id it was sent with";
    // An answer you gave before turning One Task off still reaches the session.
    NSDictionary *record = [self recordOf:row.sessionId];
    NSString *says = TaskRecordSays(record, taskId);
    if (!SwitchedOn(kOneTaskOn) && ![says hasPrefix:@"answered:"]) return kOff;
    return says;
}

#pragma mark - Print runs

+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return @{
        @"--print-tasks": ^int(Core *core, NSArray<NSString *> *arguments) { return PrintTasks(arguments); },
        @"--print-task-asks": ^int(Core *core, NSArray<NSString *> *arguments) {
            return PrintTaskAsks(core, arguments);
        },
    };
}

// `Whozmove --print-task-asks <socket> <seconds>`: the asks for the sessions in $HOME, where tests put Asker and
// Other. What the panel answers each (a task sent, its answer asked for by Asker and by Other, a task in words it can't
// read, one too large, one from a process no session runs), what Asker's ask says once the task's answered or put back,
// and that Asker's tasks go once its process has ended. Then it listens at `socket` until `<socket>.done` is there or
// `seconds` have gone, answering the first task it finds from Asker a second after it comes, for ask-panel.sh to be
// tried from inside Asker's process. It changes Whozmove's folder in $HOME, so it refuses your own.
static int PrintTaskAsks(Core *core, NSArray<NSString *> *arguments) {
    if (arguments.count < 2) return 2;
    if (HomeIsYourOwn()) {
        fprintf(stderr, "--print-task-asks changes Whozmove's folder in $HOME: give it a throwaway one\n");
        return 2;
    }
    [NSFileManager.defaultManager createDirectoryAtPath:AppDir(nil) withIntermediateDirectories:YES
                                             attributes:@{NSFilePosixPermissions: @0700} error:nil];
    OneTaskModule *module = nil;
    for (id each in core.modules.all)
        if ([each isKindOfClass:OneTaskModule.class]) module = each;
    Row *asker = nil, *other = nil, *gone = nil;
    for (Row *row in SettledRows(core)) {
        if ([row.name isEqual:@"Asker"]) asker = row;
        if ([row.name isEqual:@"Other"]) other = row;
        if ([row.name isEqual:@"Gone"]) gone = row;
    }
    if (!asker || !other || !gone) {
        fprintf(stderr, "--print-task-asks needs the sessions Asker, Other and Gone in $HOME\n");
        return 2;
    }
    void (^say)(NSString *, NSString *) = ^(NSString *what, NSString *said) {
        printf("%s: %s\n", what.UTF8String, (said ?: @"(nothing)").UTF8String);
    };
    NSString *(^ask)(NSDictionary *, pid_t) = ^NSString *(NSDictionary *asked, pid_t pid) {
        NSData *json = [NSJSONSerialization dataWithJSONObject:asked options:0 error:nil];
        return [core.asks answer:[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] from:pid];
    };
    NSDictionary *(^sending)(NSString *) = ^NSDictionary *(NSString *json) {
        return @{@"ask": @"task", @"task64": [[json dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0]};
    };
    NSString *passkeys = @"{\"id\": \"passkeys\", \"kind\": \"try\", \"title\": \"Passkey sign-in\", \"why\": \"On the "
        "preview.\", \"step\": {\"n\": 1, \"of\": 2}, \"todo\": [\"Make an account\"]}";
    NSDictionary *answerOf = @{@"ask": @"task-answer", @"id": @"passkeys"};

    say(@"Asker sends a task, with no switch on", ask(sending(passkeys), asker.pid));
    say(@"Asker asks for its answer", ask(answerOf, asker.pid));
    say(@"Other asks for Asker's task's answer", ask(answerOf, other.pid));
    say(@"Other sends a task with Asker's id", ask(sending(passkeys), other.pid));
    [module answer:@"passkeys" of:other.sessionId with:@"Works" note:nil];
    say(@"…answered as Other's, Asker asks", ask(answerOf, asker.pid));
    [module answer:@"passkeys" of:asker.sessionId with:@"Works" note:nil];
    say(@"Asker's answered, Asker asks", ask(answerOf, asker.pid));
    say(@"Asker asks by an id that's a path", ask(@{@"ask": @"task-answer", @"id": @"../x"}, asker.pid));
    say(@"Asker sends words the panel can't read", ask(@{@"ask": @"task", @"task64": @"not base64!"}, asker.pid));
    NSString *big = [NSString stringWithFormat:@"{\"id\": \"big\", \"kind\": \"seen\", \"title\": \"Big\", \"why\": \"%@\"}",
                     [@"" stringByPaddingToLength:13000 withString:@"x" startingAtIndex:0]];
    say(@"Asker sends a task too large", ask(sending(big), asker.pid));
    say(@"A process no session runs sends one", ask(sending(passkeys), 1));
    ask(sending(@"{\"id\": \"later\", \"kind\": \"do\", \"title\": \"Turn on two-factor\", \"why\": \"Only a password.\"}"),
        asker.pid);
    [module putBack:@"later" of:asker.sessionId];
    say(@"Put back with Can't Now, Asker asks", ask(@{@"ask": @"task-answer", @"id": @"later"}, asker.pid));
    say(@"Asker takes it back, answered elsewhere",
        ask(@{@"ask": @"task-withdraw", @"id": @"later", @"why": @"answered"}, asker.pid));
    say(@"…and asks for its answer", ask(@{@"ask": @"task-answer", @"id": @"later"}, asker.pid));
    say(@"…takes back one with no why it knows",
        ask(@{@"ask": @"task-withdraw", @"id": @"later", @"why": @"bored"}, asker.pid));
    say(@"…takes back one that doesn't wait",
        ask(@{@"ask": @"task-withdraw", @"id": @"nope", @"why": @"parked"}, asker.pid));
    say(@"…by an id that's a path", ask(@{@"ask": @"task-withdraw", @"id": @"../x", @"why": @"parked"}, asker.pid));
    // A team, as the team module puts it on rows: Asker leads Other, called Wren in the team; Gone is listed with no
    // place on it.
    asker.team = @{@"role": @"lead", @"name": @"Atlas", @"leads": @[other.sessionId]};
    other.team = @{@"role": @"member", @"name": @"Wren"};
    module.listed = @{asker.sessionId: asker, other.sessionId: other, gone.sessionId: gone};
    NSDictionary *(^picking)(NSString *, NSString *) = ^NSDictionary *(NSString *json, NSString *member) {
        NSMutableDictionary *asked = [sending(json) mutableCopy];
        asked[@"pickFor"] = member;
        return asked;
    };
    NSString *pickJson = @"{\"id\": \"j12\", \"kind\": \"approve\", \"title\": \"Search box\", \"why\": \"Wren's plan.\"}";
    NSDictionary *pickAnswer = @{@"ask": @"task-answer", @"id": @"j12"};
    say(@"Other, leading no team, sends a pick", ask(picking(pickJson, @"Atlas"), other.pid));
    say(@"Asker, the lead, sends a pick for Wren, by name", ask(picking(pickJson, @"Wren"), asker.pid));
    say(@"…asks for its answer before its queue names it", ask(pickAnswer, asker.pid));
    say(@"…sends it again unchanged, by Wren's session id", ask(picking(pickJson, other.sessionId), asker.pid));
    say(@"…for a listed session that isn't on its team", ask(picking(pickJson, gone.sessionId), asker.pid));
    say(@"…for a name no one on its team has", ask(picking(pickJson, @"Moss"), asker.pid));
    say(@"…with a why past 160 characters, refused before it's kept",
        ask(picking([NSString stringWithFormat:@"{\"id\": \"j13\", \"kind\": \"seen\", \"title\": \"T\", \"why\": \"%@\"}",
                     [@"" stringByPaddingToLength:161 withString:@"w" startingAtIndex:0]], @"Wren"), asker.pid));
    gone.team = @{@"role": @"member", @"name": @"Wren"};
    asker.team = @{@"role": @"lead", @"name": @"Atlas", @"leads": @[other.sessionId, gone.sessionId]};
    say(@"…for a name two on its team share", ask(picking(pickJson, @"Wren"), asker.pid));
    gone.team = nil;
    other.team = @{@"inFolderOf": @"Atlas"};
    asker.team = @{@"role": @"lead", @"name": @"Atlas", @"leads": @[other.sessionId]};
    say(@"…for Wren once its own row no longer places it on the team", ask(picking(pickJson, @"Wren"), asker.pid));
    other.team = @{@"role": @"member", @"name": @"Wren"};
    asker.team = @{@"role": @"lead", @"name": @"Atlas", @"leads": @[other.sessionId],
                   @"queue": @[@{@"id": @"j12", @"job": @"j12"}, @{@"id": @"unsent"}]};
    [module placePicks:asker];
    [NSUserDefaults.standardUserDefaults setObject:@"lead" forKey:kWho];
    say(@"Only a team's chief may hand tasks: Other, leading none, sends one", ask(sending(passkeys), other.pid));
    say(@"…Asker, a lead, sends one", ask(sending(@"{\"id\": \"lead-own\", \"kind\": \"seen\", \"title\": \"T\", "
                                                "\"why\": \"W.\"}"), asker.pid));
    module.printTeamsOff = YES;
    say(@"…with teams not shown, Other sends one", ask(sending(passkeys), other.pid));
    say(@"…and Asker, the lead, sends a pick for Wren", ask(picking(pickJson, @"Wren"), asker.pid));
    module.printTeamsOff = NO;
    [NSUserDefaults.standardUserDefaults removeObjectForKey:kWho];
    say(@"Its queue names it: task-answer says", ask(pickAnswer, asker.pid));
    say(@"…an id its queue names that Asker never sent", ask(@{@"ask": @"task-answer", @"id": @"unsent"}, asker.pid));
    say(@"…the talk's words to Wren go to", [module talkRowFor:[module entryOf:@"j12" in:asker.sessionId]
                                                            of:asker.sessionId toLead:NO].name ?: @"(nobody)");
    other.team = @{@"inFolderOf": @"Atlas"};
    say(@"…once Wren has left the team", [module talkRowFor:[module entryOf:@"j12" in:asker.sessionId]
                                                         of:asker.sessionId toLead:NO].name ?: @"(nobody)");
    asker.team = other.team = nil;
    say(@"Gone sends a task", ask(sending(passkeys), gone.pid));
    pid_t found = 0;
    if ([core sessionOfProcess:gone.pid found:&found] == gone && found == gone.pid) {
        kill(gone.pid, SIGKILL);
        for (int i = 0; i < 50 && ProcessAlive(gone.pid); i++) [NSThread sleepForTimeInterval:0.1];
    }
    [module dropEndedBut:nil at:NSDate.date];
    say(@"Once Gone's process has ended, its record is there",
        [NSFileManager.defaultManager fileExistsAtPath:RecordPath(gone.sessionId)] ? @"yes" : @"no");
    say(@"…and Asker's", [NSFileManager.defaultManager fileExistsAtPath:RecordPath(asker.sessionId)] ? @"yes" : @"no");
    ask(sending(passkeys), other.pid);
    NSSet *withoutOther = [NSSet setWithObjects:asker.sessionId, gone.sessionId, nil];
    [module dropEndedBut:withoutOther at:NSDate.date];
    say(@"Other's row missing from one read, its record is there",
        [NSFileManager.defaultManager fileExistsAtPath:RecordPath(other.sessionId)] ? @"yes" : @"no");
    [module dropEndedBut:withoutOther at:[NSDate dateWithTimeIntervalSinceNow:61]];
    say(@"…and once it has been missing a minute",
        [NSFileManager.defaultManager fileExistsAtPath:RecordPath(other.sessionId)] ? @"yes" : @"no");
    // A /clear: Asker's process now runs Asker, while tasks it sent before are kept for another conversation.
    [module keep:@{@"pid": @(asker.pid), @"processStart": @(ProcessStartedAt(asker.pid)), @"tasks": @[], @"answers": @{}}
              of:@"s-cleared"];
    [module dropEndedBut:withoutOther at:NSDate.date];
    say(@"Tasks from a conversation its process has left (a /clear), once that process runs a listed session",
        [NSFileManager.defaultManager fileExistsAtPath:RecordPath(@"s-cleared")] ? @"kept" : @"gone at once");
    [module forget:asker.sessionId];
    fflush(stdout);

    // ask-panel.sh, from inside Asker, over the socket: its first task is answered a second after it comes.
    NSString *socket = arguments[0], *done = [socket stringByAppendingString:@".done"];
    if (![core.asks listenAt:socket]) return 1;
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:arguments[1].doubleValue], *came = nil;
    BOOL answered = NO;
    while (until.timeIntervalSinceNow > 0 && ![NSFileManager.defaultManager fileExistsAtPath:done]) {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        NSArray *waiting = TaskRecordWaiting([module recordOf:asker.sessionId]);
        if (!answered && waiting.count && !came) came = NSDate.date;
        if (!answered && came && -came.timeIntervalSinceNow > 1) {
            [module answer:waiting.firstObject[@"task"][@"id"] of:asker.sessionId with:@"Works" note:nil];
            answered = YES;
        }
    }
    [core.asks stop];
    return 0;
}

@end
