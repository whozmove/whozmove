// InboxModule: the inbox's face for the core (contracts/Module.h). A session writes to its team's lead with
// ask-panel.sh message, which keeps the message first (AppDir/inbox/inbox.json, InboxRecord.h) and gives back the line
// that tells the lead, for the session to send with the agent's own messages: so a line held or lost on the way loses
// nothing. The lead reads its inbox one message at a time, most pressing first (inbox-next), and marks each answered
// (inbox-answered); `inbox` lists what waits. Only the session the team module names its team's lead reads or marks
// it, found by the session the core found asking, never by anything an ask says. What became of each line is joined
// back from the agent's messages (AgentMessages), only from the session that kept it. And Messages, beside the list
// behind Working on Whozmove ▸: every message the sessions sent each other in the last two days, with what the inbox
// kept, sent to the page (setMessages) only while it's open. It has the print runs --print-inbox and
// --print-inbox-asks.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import "Module.h"
#import "AgentMessages.h"
#import "Core.h"
#import "Files.h"
#import "Git.h"
#import "InboxRecord.h"
#import "Log.h"
#import "Modules.h"
#import "Page.h"
#import "Printing.h"
#import "Row.h"
#import "SessionAsks.h"
#import "Text.h"
#include <sys/stat.h>

// How far back Messages reads, which the agent is told, the one place it's decided: last night's messages for a
// morning's catch-up.
static const double kWindow = 2 * 24 * 60 * 60 * 1000.0;
// How often what's old goes from the record while Whozmove runs, in ms.
static const double kPruneEvery = 60 * 60 * 1000.0;
// What a plain message to a lead counts as, lost: it never reached the lead's conversation.
static NSArray<NSString *> *const kLost = @[@"expired", @"denied", @"dropped", @"failed"];

static NSString *RecordPath(void) {
    return [AppDir(@"inbox") stringByAppendingPathComponent:@"inbox.json"];
}

// Now, in whole milliseconds since 1970.
static double Now(void) {
    return floor(NSDate.date.timeIntervalSince1970 * 1000);
}

// Words ask-panel.sh sent base64-encoded, so nothing in them can break its line; nil for none it can read.
static NSString *Decoded(id encoded) {
    NSString *text = AsText(encoded);
    NSData *raw = text ? [[NSData alloc] initWithBase64EncodedString:text options:0] : nil;
    return raw ? [[NSString alloc] initWithData:raw encoding:NSUTF8StringEncoding] : nil;
}

// One line of JSON, as the asks print what they list.
static NSString *JSONLine(id object) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:object
                                                   options:NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes
                                                     error:nil];
    return json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"{}";
}

static int PrintInbox(void);
static int PrintInboxAsks(Core *core, NSArray<NSString *> *arguments);

@interface InboxModule : NSObject <Module, KeptMessages>
@property (weak) Core *core;
// The record as kept, read from its file the first time it's needed; written only on `writes`, whole.
@property (strong, nonatomic) NSDictionary *record;
@property (strong) dispatch_queue_t writes;
@property double prunedAt;
// The rows as last listed, by session: who's running, and their names and folders; and each session with whether it
// has ended, so the page is told again only when one comes, goes or ends.
@property (copy) NSDictionary<NSString *, Row *> *listed;
@property (copy) NSSet<NSString *> *running;
// Each team as the team module gives it (TeamFacts); a print run gives its own.
@property (copy) NSArray<NSDictionary *> *(^teams)(void);
// The agent that records its sessions' messages, once found (nil: none does), and what it said of their messages in
// the last two days, by id, as far as it has said (`seen`, its count of changes then).
@property (strong) id<AgentMessages> agent;
@property BOOL agentLooked, fetching, firstRead;
@property NSUInteger seen;
@property (strong) NSMutableDictionary<NSString *, AgentMessage *> *heard;
// Whether Messages shows beside the list, and what the page was last told, so only what changed is sent.
@property BOOL open, dirty;
@property (copy) NSDictionary<NSString *, NSDictionary *> *told;
@property (copy) NSArray *toldInboxes;
@property (copy) NSDictionary *toldCounts;
@property BOOL toldReading;
@end

@implementation InboxModule

+ (NSString *)moduleName {
    return @"inbox";
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.writes = dispatch_queue_create("whozmove.inbox.writes", DISPATCH_QUEUE_SERIAL);
    self.heard = [NSMutableDictionary dictionary];
    __weak typeof(self) weakSelf = self;
    self.teams = ^NSArray<NSDictionary *> *{
        return [[weakSelf.core moduleThat:@protocol(TeamFacts)] teams] ?: @[];
    };
    return self;
}

#pragma mark - The record

- (NSDictionary *)record {
    if (!_record) _record = InboxRecordPrune(InboxRecordFrom(ReadJSON(RecordPath())), Now());
    return _record;
}

// Keeps `next` as the record, here and in its file, replaced whole on the writes' queue; with `wait`, until it's
// written, NO if it couldn't be, when nothing changes. The record as it is keeps nothing.
- (BOOL)keepRecord:(NSDictionary *)next wait:(BOOL)wait {
    if (!next || next == self.record) return YES;
    __block BOOL kept = YES;
    void (^write)(void) = ^{
        NSFileManager *files = NSFileManager.defaultManager;
        [files createDirectoryAtPath:AppDir(@"inbox") withIntermediateDirectories:YES
                          attributes:@{NSFilePosixPermissions: @0700} error:nil];
        NSData *json = [NSJSONSerialization isValidJSONObject:next]
            ? [NSJSONSerialization dataWithJSONObject:next options:NSJSONWritingSortedKeys error:nil] : nil;
        if (!json || ![json writeToFile:RecordPath() atomically:YES]) {
            LogProblem(@"inbox: couldn't keep the inbox");
            kept = NO;
            return;
        }
        chmod(RecordPath().fileSystemRepresentation, 0600);
    };
    if (wait) dispatch_sync(self.writes, write);
    else dispatch_async(self.writes, write);
    if (!kept) return NO;
    self.record = next;
    self.dirty = YES;
    return YES;
}

#pragma mark - Teams and their leads

// The team of the project a folder is in (its repo's main checkout, for a worktree too), as the team module gives it.
- (NSDictionary *)teamOfFolder:(NSString *)folder {
    if (!folder.length) return nil;
    NSString *project = RealPath(ProjectRoot(folder) ?: folder);
    for (NSDictionary *team in self.teams())
        if ([RealPath(team[@"project"]) isEqual:project]) return team;
    return nil;
}

- (NSDictionary *)teamOfProject:(NSString *)project {
    for (NSDictionary *team in self.teams())
        if ([team[@"project"] isEqual:project]) return team;
    return nil;
}

// The team a session leads now, or nil, with why it reads no inbox: its project's team names another lead, or keeps
// none. A fresh lead's session is the one the team file names, so it reads what waited for the one before.
- (NSDictionary *)teamLedBy:(Row *)row why:(NSString **)why {
    for (NSDictionary *team in self.teams())
        if (row.sessionId && [team[@"lead"][@"session"] isEqual:row.sessionId]) return team;
    NSDictionary *team = [self teamOfFolder:row.cwd], *lead = team[@"lead"];
    if (why) *why = !team ? @"this project keeps no team, so there's no inbox here"
                  : !lead ? @"no one leads this project's team now"
                  : [NSString stringWithFormat:@"this session isn't its team's lead: the team file names %@",
                                               AsText(lead[@"name"]).length ? lead[@"name"] : @"another session"];
    return nil;
}

// The project whose team a session leads, for counting what was lost on the way to it.
- (NSString *)projectLedBy:(NSString *)sessionId {
    if (!sessionId) return nil;
    for (NSDictionary *team in self.teams())
        if ([team[@"lead"][@"session"] isEqual:sessionId]) return team[@"project"];
    return nil;
}

#pragma mark - What a session asks

- (NSDictionary<NSString *, SessionAsk *> *)sessionAsks {
    __weak typeof(self) weakSelf = self;
    // Each only keeps or shows words between sessions, acting on nothing of yours, so needs no switch; each logs what's
    // worth keeping itself: the ask, the message's id and its priority, never its words or what it's about.
    SessionAsk *message = [SessionAsk askShowing:^NSString *(Row *row, pid_t process, NSDictionary *asked) {
        return [weakSelf message:asked from:row];
    }];
    SessionAsk *inbox = [SessionAsk askShowing:^NSString *(Row *row, pid_t process, NSDictionary *asked) {
        return [weakSelf inboxOf:row];
    }];
    SessionAsk *next = [SessionAsk askShowing:^NSString *(Row *row, pid_t process, NSDictionary *asked) {
        return [weakSelf nextFor:row];
    }];
    SessionAsk *answered = [SessionAsk askShowing:^NSString *(Row *row, pid_t process, NSDictionary *asked) {
        return [weakSelf answered:asked by:row];
    }];
    message.logsItself = inbox.logsItself = next.logsItself = answered.logsItself = YES;
    return @{@"message": message, @"inbox": inbox, @"inbox-next": next, @"inbox-answered": answered};
}

// Who sent a message: its session, and its name in the team, else as its row shows it.
- (NSDictionary *)senderOf:(Row *)row {
    NSString *name = AsText(row.team[@"name"]) ?: row.name;
    return name.length ? @{@"session": row.sessionId, @"name": name} : @{@"session": row.sessionId};
}

- (NSString *)message:(NSDictionary *)asked from:(Row *)row {
    if (![AsText(asked[@"to"]) isEqual:@"lead"]) return @"refused: a message goes to your team's lead: --to lead";
    NSString *priority = AsText(asked[@"priority"]);
    if (![InboxPriorities containsObject:priority ?: @""])
        return [NSString stringWithFormat:@"refused: say how pressing it is: --priority %@",
                                          [InboxPriorities componentsJoinedByString:@"|"]];
    NSString *text = Decoded(asked[@"text64"]), *about = asked[@"about64"] ? Decoded(asked[@"about64"]) : nil;
    if (!text || (asked[@"about64"] && !about))
        return @"refused: Whozmove couldn't read the message: give it on stdin, as text";
    NSString *why = InboxWhyNotWords(text, about);
    if (why) return [@"refused: " stringByAppendingString:why];
    if (!IsPlainId(row.sessionId, 128)) return @"refused: Whozmove can't keep messages from this session";
    NSDictionary *team = [self teamOfFolder:row.cwd], *lead = team[@"lead"];
    if (!team)
        return @"refused: this project keeps no team, so it has no lead's inbox: send it to your lead by name, the "
               @"way your agent sends messages between sessions";
    if (!lead)
        return @"refused: no one leads this project's team now: send it to the one you're working for by name, the "
               @"way your agent sends messages between sessions";
    if ([lead[@"session"] isEqual:row.sessionId]) return @"refused: this session is its team's lead: the inbox is its own";
    NSString *kept = nil;
    NSDictionary *next = InboxRecordKeep(self.record, [self senderOf:row], team[@"project"], priority,
                                         about ? PlainOneLine(about, InboxMostAbout) : nil, text, Now(), &kept, &why);
    if (!next) return [@"refused: " stringByAppendingString:why];
    if (![self keepRecord:next wait:YES]) return @"refused: Whozmove couldn't keep the message: try again";
    PanelLog(@"inbox: %@ kept %@ (%@) for its lead", row.sessionId, kept, priority);
    NSString *line = InboxLine(InboxMessage(next, kept));
    NSString *name = AsText(lead[@"name"]).length ? lead[@"name"] : @"your lead";
    // Until an agent says where its sessions listen, there's no address: the line goes by the lead's name, said so.
    id<AgentMessages> agent = self.agentMessages;
    if (!agent)
        return [NSString stringWithFormat:@"kept %@\nno address to ring yet: Whozmove can't tell where sessions listen "
                                          @"on this Mac, so send the line below to %@ by name, the way your agent "
                                          @"sends messages between sessions\nline: %@", kept, name, line];
    NSString *address = [agent addressOfSession:lead[@"session"]];
    if (!address)
        return [NSString stringWithFormat:@"kept %@\n%@ isn't running: it reads this when it starts, so there's "
                                          @"nothing to ring", kept, name];
    return [NSString stringWithFormat:@"kept %@\nring: %@\nline: %@", kept, address, line];
}

- (NSString *)inboxOf:(Row *)row {
    NSString *why = nil;
    NSDictionary *team = [self teamLedBy:row why:&why];
    if (!team) return [@"refused: " stringByAppendingString:why];
    NSArray *waiting = InboxWaiting(self.record, team[@"project"]);
    PanelLog(@"inbox: %@ listed its inbox (%lu waiting)", row.sessionId, (unsigned long)waiting.count);
    if (!waiting.count) return @"empty";
    NSMutableArray *lines = [NSMutableArray array];
    for (NSDictionary *message in waiting) [lines addObject:JSONLine(InboxSummary(message))];
    return [lines componentsJoinedByString:@"\n"];
}

- (NSString *)nextFor:(Row *)row {
    NSString *why = nil;
    NSDictionary *team = [self teamLedBy:row why:&why];
    if (!team) return [@"refused: " stringByAppendingString:why];
    NSDictionary *message = InboxNextFor(self.record, team[@"project"], row.sessionId);
    if (!message) return @"empty";
    if (![self keepRecord:InboxRecordRead(self.record, message[@"id"], row.sessionId, Now()) wait:YES])
        return @"refused: Whozmove couldn't mark it read: try again";
    PanelLog(@"inbox: %@ read %@ (%@)", row.sessionId, message[@"id"], message[@"priority"]);
    NSMutableDictionary *whole = [InboxSummary(message) mutableCopy];
    whole[@"text"] = message[@"text"];
    [whole removeObjectsForKeys:@[@"readAt", @"readBy"]];
    return JSONLine(whole);
}

- (NSString *)answered:(NSDictionary *)asked by:(Row *)row {
    NSString *messageId = AsText(asked[@"id"]);
    if (messageId.length != 8 || ![messageId hasPrefix:@"m-"] || !IsPlainId(messageId, 8))
        return @"refused: name the message by the id inbox-next gave, as m-7f3a2c";
    NSString *note = asked[@"note64"] ? Decoded(asked[@"note64"]) : nil;
    if (asked[@"note64"] && !note) return @"refused: Whozmove couldn't read the note: give it on stdin, as text";
    if (note && LooksLikeSecret(note))
        return @"refused: the note has something shaped like a key in it: take it out, and say where it's kept";
    NSDictionary *message = InboxMessage(self.record, messageId);
    NSDictionary *team = message ? [self teamOfProject:message[@"to"][@"lead"]] : nil;
    if (message && ![team[@"lead"][@"session"] isEqual:row.sessionId])
        return @"refused: only its team's lead marks a message answered";
    NSString *said = nil, *why = nil;
    NSDictionary *next = InboxRecordAnswered(self.record, messageId, row.sessionId,
                                             note ? PlainOneLine(note, InboxMostNote) : nil, Now(), &said, &why);
    if (!next) return [@"refused: " stringByAppendingString:why];
    if (![self keepRecord:next wait:YES]) return @"refused: Whozmove couldn't mark it answered: try again";
    PanelLog(@"inbox: %@ answered %@", row.sessionId, messageId);
    return said;
}

#pragma mark - What the agent says of its messages

// The agent that records its sessions' messages, found the first time it's asked for (the agents are all there by
// then), or nil.
- (id<AgentMessages>)agentMessages {
    if (!self.agentLooked) {
        self.agentLooked = YES;
        self.agent = [self.core agentsThat:@protocol(AgentMessages)].firstObject;
    }
    return self.agent;
}

// Whether a message only tells its receiver of one the inbox keeps: its line, starting with that message's id, sent
// by the session that kept it.
- (BOOL)keeps:(AgentMessage *)message {
    NSString *kept = InboxIdInLine(message.text);
    return kept && [InboxMessage(self.record, kept)[@"from"][@"session"] isEqual:message.fromSession];
}

// What the agent said since it was last asked: each line's fate joined to its message, a plain message lost on its way
// to a lead counted, and only the last two days kept here.
- (void)took:(NSArray<AgentMessage *> *)taken as:(NSUInteger)change {
    self.fetching = NO;
    self.firstRead = YES;
    self.seen = change;
    double now = Now();
    NSDictionary *record = self.record;
    for (AgentMessage *message in taken) {
        if (!message.messageId.length) continue;
        self.heard[message.messageId] = message;
        if ([self keeps:message]) {
            record = InboxRecordRing(record, InboxIdInLine(message.text), message.fromSession, message.messageId,
                                     message.delivery, message.deliveryAt ?: message.sentAt, now);
            continue;
        }
        NSString *project = [self projectLedBy:message.toSession];
        if (project && [kLost containsObject:message.delivery ?: @""])
            record = InboxRecordLost(record, project, message.messageId, now);
    }
    for (NSString *messageId in self.heard.allKeys)
        if (self.heard[messageId].sentAt < now - kWindow) [self.heard removeObjectForKey:messageId];
    [self keepRecord:record wait:NO];
    self.dirty = YES;
}

- (void)tick {
    double now = Now();
    if (now - self.prunedAt > kPruneEvery) {
        self.prunedAt = now;
        [self keepRecord:InboxRecordPrune(self.record, now) wait:NO];
    }
    // The agent is asked only when its count of changes has moved, and once at the start: it reads as far back as
    // the window the first time, and only what's new after.
    id<AgentMessages> agent = self.agentMessages;
    if (agent && !self.fetching && (!self.firstRead || agent.changes != self.seen)) {
        self.fetching = YES;
        __weak typeof(self) weakSelf = self;
        [agent messagesAfter:now - kWindow change:self.seen then:^(NSArray<AgentMessage *> *taken, NSUInteger change) {
            dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf took:taken as:change]; });
        }];
    }
    [self tell:NO];
}

// Who's running is in the rows: a name, a folder and whether it has ended go with each message, and change only as
// sessions come and go.
- (void)rows:(NSArray<Row *> *)rows phase:(RowPhase)phase {
    if (phase != RowPhaseListed) return;
    NSMutableDictionary *listed = [NSMutableDictionary dictionary];
    NSMutableSet *running = [NSMutableSet set];
    for (Row *row in rows) {
        if (!row.sessionId) continue;
        listed[row.sessionId] = row;
        [running addObject:[NSString stringWithFormat:@"%@ %d", row.sessionId, [row.status isEqual:@"closed"]]];
    }
    if (![running isEqualToSet:self.running ?: [NSSet set]]) self.dirty = YES;
    self.running = running;
    self.listed = listed;
}

#pragma mark - Messages, beside the list

// A session as a message shows it: {session, name, folder, ended}. Its name is the one given, else its row's.
- (NSDictionary *)who:(NSString *)sessionId named:(NSString *)name {
    Row *row = sessionId ? self.listed[sessionId] : nil;
    NSString *shown = name.length ? name : row.name;
    BOOL ended = !row || [row.status isEqual:@"closed"];
    return @{@"session": sessionId ?: NSNull.null, @"name": shown.length ? shown : NSNull.null,
             @"folder": row.cwd.lastPathComponent ?: NSNull.null, @"ended": @(ended)};
}

// Every message the page shows, by its id: what the inbox kept (unanswered ones whatever their age), each as its
// words with its line's fate, the line itself never shown; then the agent's other messages of the last two days.
// `keptAs` gets each kept message's id in the page's ids.
- (NSDictionary<NSString *, NSDictionary *> *)entriesKeptAs:(NSMutableDictionary *)keptAs {
    double since = Now() - kWindow;
    NSMutableDictionary *entries = [NSMutableDictionary dictionary];
    NSMutableSet *lines = [NSMutableSet set];
    for (NSDictionary *kept in self.record[@"messages"]) {
        if (kept[@"answeredAt"] && [kept[@"at"] doubleValue] < since) continue;
        NSDictionary *told = AsRecord(kept[@"told"]), *lead = [self teamOfProject:kept[@"to"][@"lead"]][@"lead"];
        AgentMessage *line = self.heard[AsText(told[@"messageId"]) ?: @""];
        if (line) [lines addObject:line.messageId];
        NSString *entryId = line.messageId ?: kept[@"id"];
        keptAs[kept[@"id"]] = entryId;
        NSMutableDictionary *facts = [NSMutableDictionary dictionary];
        for (NSString *key in @[@"id", @"priority", @"about", @"readAt", @"readBy", @"answeredAt", @"note"])
            facts[key] = kept[key] ?: NSNull.null;
        entries[entryId] = @{
            @"id": entryId,
            @"from": [self who:kept[@"from"][@"session"] named:kept[@"from"][@"name"]],
            @"to": [self who:line.toSession ?: lead[@"session"] named:lead[@"name"] ?: line.toName],
            @"at": kept[@"at"], @"text": kept[@"text"], @"cut": @NO,
            @"delivery": line.delivery ?: told[@"state"] ?: @"kept",
            @"deliveryAt": line ? @(line.deliveryAt) : told[@"at"] ?: NSNull.null,
            @"canAsk": @(line.canAsk), @"kept": facts,
        };
    }
    // A line sent again for a message kept here shows no more than the first: the message shows once, as kept.
    for (AgentMessage *message in self.heard.allValues) {
        if ([lines containsObject:message.messageId] || [self keeps:message] || message.sentAt < since) continue;
        entries[message.messageId] = @{
            @"id": message.messageId,
            @"from": [self who:message.fromSession named:message.fromName],
            @"to": [self who:message.toSession named:message.toName],
            @"at": @(message.sentAt), @"text": message.text ?: @"", @"cut": @(message.cut),
            @"delivery": message.delivery ?: @"sent", @"deliveryAt": @(message.deliveryAt),
            @"canAsk": @(message.canAsk), @"kept": NSNull.null,
        };
    }
    return entries;
}

// Each team's inbox with messages its lead hasn't read, in the order it reads them: the app's order alone.
- (NSArray *)inboxesKeptAs:(NSDictionary *)keptAs {
    NSMutableArray *inboxes = [NSMutableArray array];
    for (NSDictionary *team in self.teams()) {
        NSDictionary *lead = team[@"lead"];
        if (!lead) continue;
        NSMutableArray *unread = [NSMutableArray array];
        for (NSDictionary *message in InboxWaiting(self.record, team[@"project"]))
            if (![message[@"readBy"] isEqual:lead[@"session"]] && keptAs[message[@"id"]])
                [unread addObject:keptAs[message[@"id"]]];
        if (unread.count) [inboxes addObject:@{@"project": team[@"project"], @"lead": lead, @"unread": unread}];
    }
    return inboxes;
}

// Tells the page what changed while Messages shows: all of it as it opens (`whole`), then only the messages new or
// changed since, with the inboxes and the week's counts whole. Nothing is sent while it's closed.
- (void)tell:(BOOL)whole {
    if (!self.open || (!whole && !self.dirty && self.toldReading == (self.agentMessages && !self.firstRead))) return;
    self.dirty = NO;
    NSMutableDictionary *keptAs = [NSMutableDictionary dictionary];
    NSDictionary *entries = [self entriesKeptAs:keptAs];
    NSArray *inboxes = [self inboxesKeptAs:keptAs];
    NSDictionary *counts = InboxWeekCounts(self.record, nil, Now());
    BOOL reading = self.agentMessages && !self.firstRead;
    // One gone since (pruned, or older than the window) can't be merged away: the whole is sent again.
    for (NSString *entryId in self.told)
        if (!entries[entryId]) whole = YES;
    NSMutableArray *changed = [NSMutableArray array];
    for (NSString *entryId in entries)
        if (whole || ![self.told[entryId] isEqual:entries[entryId]]) [changed addObject:entries[entryId]];
    if (!whole && !changed.count && [inboxes isEqual:self.toldInboxes] && [counts isEqual:self.toldCounts]
        && reading == self.toldReading)
        return;
    [changed sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"at" ascending:YES]]];
    self.told = entries;
    self.toldInboxes = inboxes;
    self.toldCounts = counts;
    self.toldReading = reading;
    // The agent's own name, as it says it, so the page names none itself; null while no agent records its messages.
    NSDictionary *facts = @{@"reading": @(reading), @"agent": self.agentMessages.name ?: NSNull.null, @"now": @(Now())};
    [self.core.page call:@"setMessages" with:@[changed, inboxes, counts, facts, @(whole)]];
}

// The page loaded again has nothing beside the list: nothing is sent until Messages opens there.
- (void)pageLoaded {
    self.open = NO;
    self.told = nil;
}

- (NSDictionary<NSString *, void (^)(NSDictionary *message)> *)messages {
    __weak typeof(self) weakSelf = self;
    return @{
        @"messagesOpen": ^(NSDictionary *message) {
            weakSelf.open = YES;
            [weakSelf tell:YES];
        },
        @"messagesClosed": ^(NSDictionary *message) {
            weakSelf.open = NO;
            weakSelf.told = nil;
            weakSelf.toldInboxes = nil;
            weakSelf.toldCounts = nil;
        },
        // A message that never reached its session, copied for you to send again: the words held here, found by the
        // id the page names, never words the page sends.
        @"messagesCopy": ^(NSDictionary *message) {
            NSDictionary *entry = weakSelf.told[AsText(message[@"id"]) ?: @""];
            if (!entry || entry[@"kept"] != NSNull.null) return;
            [NSPasteboard.generalPasteboard clearContents];
            [NSPasteboard.generalPasteboard setString:entry[@"text"] forType:NSPasteboardTypeString];
            PanelLog(@"inbox: a message's words copied");
        },
    };
}

// Working on Whozmove ▸ Show Messages: ticked while Messages shows beside the list; a press opens it, or closes it.
- (NSArray<MenuEntry *> *)menuEntries {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Show Messages" action:@selector(toggleShown)
                                           keyEquivalent:@""];
    item.target = self;
    MenuEntry *entry = [MenuEntry entryIn:MenuSectionWhozmove order:45 item:item];
    __weak typeof(self) weakSelf = self;
    entry.willOpen = ^{ item.state = weakSelf.open ? NSControlStateValueOn : NSControlStateValueOff; };
    return @[entry];
}

- (void)toggleShown {
    [self.core.page call:self.open ? @"closeMessages" : @"openMessages" with:@[]];
}

#pragma mark - Print runs

+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return @{
        @"--print-inbox": ^int(Core *core, NSArray<NSString *> *arguments) { return PrintInbox(); },
        @"--print-inbox-asks": ^int(Core *core, NSArray<NSString *> *arguments) {
            return PrintInboxAsks(core, arguments);
        },
    };
}

@end

// `Whozmove --print-inbox`: the record's rules over made-up messages, at made-up times: words refused, the order a lead
// reads in, the next for a lead and for a fresh one, answered, the line and its id, a line's fate joined only from its
// sender, the week's counts, the ceiling, what goes once it's old, and a damaged record. It reads and writes nothing.
static int PrintInbox(void) {
    const double day = 24 * 60 * 60 * 1000.0, start = 1772625600000;  // a Wednesday, 12:00 UTC
    void (^say)(NSString *, id) = ^(NSString *what, id said) {
        NSString *words = [said isKindOfClass:NSString.class] ? said : said ? JSONLine(said) : @"(nothing)";
        printf("%s: %s\n", what.UTF8String, words.UTF8String);
    };
    say(@"No words", InboxWhyNotWords(@" \n ", nil));
    say(@"8,001 characters", InboxWhyNotWords([@"" stringByPaddingToLength:8001 withString:@"w" startingAtIndex:0], nil));
    say(@"8,000 characters", InboxWhyNotWords([@"" stringByPaddingToLength:8000 withString:@"w" startingAtIndex:0], nil));
    NSString *key = [@"ghp_" stringByPaddingToLength:40 withString:@"a1B2" startingAtIndex:0];
    say(@"A key in the words", InboxWhyNotWords([@"The token is " stringByAppendingString:key], nil));
    say(@"A key in what it's about", InboxWhyNotWords(@"Fine words", key));

    NSDictionary *pip = @{@"session": @"s-pip", @"name": @"Pip"}, *moss = @{@"session": @"s-moss", @"name": @"Moss"};
    NSString *shop = @"/work/shop";
    NSDictionary *record = InboxRecordFrom(nil);
    NSMutableDictionary<NSString *, NSString *> *ids = [NSMutableDictionary dictionary];
    NSArray *sent = @[@[pip, @"note", @"tidy", @"The guide's first section is tidied."],
                      @[moss, @"question", @"node", @"Node 18 or 20 in the guide?"],
                      @[pip, @"report", @"J12", @"Done: the coupon field is in, with 14 tests."],
                      @[moss, @"urgent", @"stop", @"Stop: the migration drops the coupons table."],
                      @[pip, @"question", @"J12", @"Take the cent next, or leave it?"]];
    for (NSUInteger i = 0; i < sent.count; i++) {
        NSString *kept = nil, *why = nil;
        record = InboxRecordKeep(record, sent[i][0], shop, sent[i][1], sent[i][2], sent[i][3], start + i * 60000, &kept,
                                 &why);
        ids[[NSString stringWithFormat:@"%@-%@", sent[i][1], sent[i][2]]] = kept;
    }
    // Given the record each time, as a block keeps the one it was made with.
    NSString *(^order)(NSDictionary *, NSString *) = ^NSString *(NSDictionary *record, NSString *project) {
        NSMutableArray *words = [NSMutableArray array];
        for (NSDictionary *message in InboxWaiting(record, project))
            [words addObject:[NSString stringWithFormat:@"%@ %@ (%@)", message[@"priority"], message[@"about"],
                                                        message[@"from"][@"name"]]];
        return words.count ? [words componentsJoinedByString:@", "] : @"none";
    };
    say(@"Five kept, in the order the lead reads them", order(record, shop));
    say(@"Another project's inbox", order(record, @"/work/blog"));
    NSDictionary *next = InboxNextFor(record, shop, @"s-lead");
    say(@"Next for the lead", [NSString stringWithFormat:@"%@ %@", next[@"priority"], next[@"about"]]);
    record = InboxRecordRead(record, next[@"id"], @"s-lead", start + day);
    next = InboxNextFor(record, shop, @"s-lead");
    say(@"…once it's read, next", [NSString stringWithFormat:@"%@ %@", next[@"priority"], next[@"about"]]);
    next = InboxNextFor(record, shop, @"s-lead-2");
    say(@"For a fresh lead, the one the lead before read and nobody answered",
        [NSString stringWithFormat:@"%@ %@", next[@"priority"], next[@"about"]]);
    NSString *said = nil, *why = nil;
    NSString *urgent = ids[@"urgent-stop"];
    record = InboxRecordAnswered(record, urgent, @"s-lead-2", @"Told Moss to keep the table", start + day, &said, &why);
    say(@"Answered, with a note", said);
    say(@"…answered by", InboxMessage(record, urgent)[@"answeredBy"]);
    say(@"…read by, the lead before", InboxMessage(record, urgent)[@"readBy"]);
    say(@"…its note", InboxMessage(record, urgent)[@"note"]);
    InboxRecordAnswered(record, urgent, @"s-lead-2", nil, start + day, &said, &why);
    say(@"Answered again", said);
    say(@"Answered, an id it hasn't", InboxRecordAnswered(record, @"m-000000", @"s-lead-2", nil, start, &said, &why)
                                      ? @"kept" : why);
    say(@"Now waiting", order(record, shop));

    NSDictionary *question = InboxMessage(record, ids[@"question-J12"]);
    NSString *line = InboxLine(question);
    say(@"Its line", [line stringByReplacingOccurrencesOfString:question[@"id"] withString:@"m-…"]);
    say(@"…the id at its start", [InboxIdInLine(line) isEqual:question[@"id"]] ? @"its own" : @"another");
    say(@"A line that only names an id later", InboxIdInLine([@"See Inbox " stringByAppendingString:question[@"id"]]));
    NSString *q = question[@"id"];
    record = InboxRecordRing(record, q, @"s-moss", @"msg-1", @"held", start, start);
    say(@"Its line held, as Moss said", InboxMessage(record, q)[@"told"]);
    record = InboxRecordRing(record, q, @"s-pip", @"msg-1", @"held", start, start);
    say(@"…as Pip, who kept it, said", InboxMessage(record, q)[@"told"][@"state"]);
    record = InboxRecordRing(record, q, @"s-pip", @"msg-1", @"held", start, start);
    record = InboxRecordRing(record, q, @"s-pip", @"msg-1", @"expired", start + 60000, start);
    say(@"…then expired", InboxMessage(record, q)[@"told"][@"state"]);
    record = InboxRecordRing(record, ids[@"report-J12"], @"s-pip", @"msg-2", @"denied", start, start);
    record = InboxRecordRing(record, ids[@"note-tidy"], @"s-pip", @"msg-3", @"arrived", start, start);
    record = InboxRecordLost(record, shop, @"msg-9", start);
    record = InboxRecordLost(record, shop, @"msg-9", start);
    record = InboxRecordLost(record, @"/work/blog", @"msg-8", start);
    say(@"This week's counts, for the shop", InboxWeekCounts(record, shop, start));
    say(@"…for every project", InboxWeekCounts(record, nil, start));
    say(@"…next week", InboxWeekCounts(record, nil, start + 7 * day));
    say(@"What inbox lists of one", [[InboxSummary(InboxMessage(record, q)).allKeys
                                      sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@", "]);

    NSDictionary *full = InboxRecordFrom(nil);
    for (NSUInteger i = 0; i < InboxMostWaiting; i++)
        full = InboxRecordKeep(full, pip, shop, @"note", nil, @"Again.", start, nil, nil);
    say(@"Pip with 50 waiting sends another", InboxRecordKeep(full, pip, shop, @"note", nil, @"Again.", start, nil, &why)
                                             ? @"kept" : why);
    say(@"…and Moss", InboxRecordKeep(full, moss, shop, @"note", nil, @"Hi.", start, nil, &why) ? @"kept" : why);

    NSDictionary *old = InboxRecordFrom(nil);
    NSString *a = nil, *b = nil, *c = nil;
    old = InboxRecordKeep(old, pip, shop, @"note", @"answered 8 days ago", @"A.", start - 9 * day, &a, nil);
    old = InboxRecordAnswered(old, a, @"s-lead", nil, start - 8 * day, nil, nil);
    old = InboxRecordKeep(old, pip, shop, @"note", @"waiting 13 days", @"B.", start - 13 * day, &b, nil);
    old = InboxRecordKeep(old, pip, shop, @"note", @"waiting 15 days", @"C.", start - 15 * day, &c, nil);
    NSMutableArray *left = [NSMutableArray array];
    for (NSDictionary *message in InboxRecordPrune(old, start)[@"messages"]) [left addObject:message[@"about"]];
    say(@"Kept once the old go", [left componentsJoinedByString:@", "]);
    say(@"A damaged record", InboxRecordFrom(@{@"messages": @[@"not one", @{@"id": @"../x"}, @{}], @"weeks": @"no"}));
    return 0;
}

// A stand-in for an agent that records its sessions' messages, for --print-inbox-asks: what it's told to say, each a
// change of its own, and where the sessions it names listen.
@interface InboxStandInAgent : NSObject
@property (strong) NSMutableArray<NSArray *> *said;  // [change, message]
@property NSUInteger changes;
@property (copy) NSDictionary<NSString *, NSString *> *addresses;
@end

@implementation InboxStandInAgent
- (NSString *)name {
    return @"Stand-in";
}
- (void)say:(AgentMessage *)message {
    self.changes++;
    [self.said addObject:@[@(self.changes), message]];
}
- (void)messagesAfter:(double)since change:(NSUInteger)change
                 then:(void (^)(NSArray<AgentMessage *> *messages, NSUInteger now))then {
    NSMutableArray *messages = [NSMutableArray array];
    for (NSArray *one in self.said)
        if ([one[0] unsignedIntegerValue] > change && [one[1] sentAt] >= since) [messages addObject:one[1]];
    then(messages, self.changes);
}
- (NSString *)addressOfSession:(NSString *)sessionId {
    return self.addresses[sessionId];
}
@end

// `Whozmove --print-inbox-asks <phase> [socket seconds]`: the asks for the sessions in $HOME, where tests put Lead,
// Lead2, Pip, Chief, You and Lone, the shop's team led by Lead (phase `first`) or Lead2, a fresh lead (`fresh`), with
// a stand-in agent saying what became of their messages, or no agent at all (`none`). With a socket, it then listens
// there until `<socket>.done` is there or `seconds` have gone, for ask-panel.sh to be tried from inside a session's
// process. It changes Whozmove's folder in $HOME, so it refuses your own.
static int PrintInboxAsks(Core *core, NSArray<NSString *> *arguments) {
    NSString *phase = arguments.firstObject;
    if (![@[@"first", @"fresh", @"none"] containsObject:phase ?: @""]) return 2;
    if (HomeIsYourOwn()) {
        fprintf(stderr, "--print-inbox-asks changes Whozmove's folder in $HOME: give it a throwaway one\n");
        return 2;
    }
    InboxModule *module = nil;
    for (id each in core.modules.all)
        if ([each isKindOfClass:InboxModule.class]) module = each;
    NSMutableDictionary<NSString *, Row *> *named = [NSMutableDictionary dictionary];
    for (Row *row in SettledRows(core))
        if (row.name) named[row.name] = row;
    for (NSString *name in @[@"Lead", @"Lead2", @"Pip", @"Chief", @"You", @"Lone"])
        if (!named[name]) {
            fprintf(stderr, "--print-inbox-asks needs the session %s in $HOME\n", name.UTF8String);
            return 2;
        }
    Row *lead = named[[phase isEqual:@"fresh"] ? @"Lead2" : @"Lead"], *pip = named[@"Pip"];
    pip.team = @{@"role": @"member", @"name": @"Pip"};
    // The team as the team module gives it: the shop's project, its lead the session this phase names.
    NSString *shop = ProjectRoot(pip.cwd) ?: pip.cwd;
    module.teams = ^NSArray<NSDictionary *> *{
        return @[@{@"project": shop, @"lead": @{@"session": lead.sessionId, @"name": lead.name}}];
    };
    InboxStandInAgent *agent = nil;
    if (![phase isEqual:@"none"]) {
        agent = [InboxStandInAgent new];
        agent.said = [NSMutableArray array];
        agent.addresses = @{named[@"Lead"].sessionId: @"uds:/tmp/stand-in/lead.sock"};
    }
    module.agent = (id<AgentMessages>)agent;
    module.agentLooked = YES;
    module.listed = @{};

    void (^say)(NSString *, NSString *) = ^(NSString *what, NSString *said) {
        printf("%s: %s\n", what.UTF8String, [(said ?: @"(nothing)") stringByReplacingOccurrencesOfString:@"\n"
                                                                                               withString:@"\n  "].UTF8String);
    };
    NSString *(^ask)(NSDictionary *, Row *) = ^NSString *(NSDictionary *asked, Row *row) {
        NSData *json = [NSJSONSerialization dataWithJSONObject:asked options:0 error:nil];
        return [core.asks answer:[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] from:row.pid];
    };
    NSString *(^base64)(NSString *) = ^NSString *(NSString *words) {
        return [[words dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
    };
    NSDictionary *(^message)(NSString *, NSString *, NSString *) = ^NSDictionary *(NSString *priority, NSString *about,
                                                                                    NSString *text) {
        NSMutableDictionary *asked = [@{@"ask": @"message", @"to": @"lead", @"priority": priority,
                                        @"text64": base64(text)} mutableCopy];
        if (about) asked[@"about64"] = base64(about);
        return asked;
    };
    // The id a kept message's answer starts with.
    NSString *(^keptId)(NSString *) = ^NSString *(NSString *said) {
        return [said hasPrefix:@"kept "] ? [said substringWithRange:NSMakeRange(5, 8)] : nil;
    };

    if ([phase isEqual:@"first"]) {
        NSString *said = ask(message(@"question", @"J12", @"Which colour for the coupon button?\n\n🟢 or 🔵"), pip);
        say(@"Pip writes to its lead, a question", said);
        NSString *question = keptId(said);
        say(@"The chief writes to the lead, a note", ask(message(@"note", nil, @"Back at 9."),
                                                         named[@"Chief"]));
        say(@"Your own session writes, urgent", ask(message(@"urgent", @"stop", @"Stop the migration."), named[@"You"]));
        say(@"Lone, in a project with no team", ask(message(@"note", nil, @"Hello?"), named[@"Lone"]));
        say(@"The lead writes to itself", ask(message(@"note", nil, @"Me."), lead));
        say(@"Pip, with no priority", ask(@{@"ask": @"message", @"to": @"lead", @"text64": base64(@"Hi")}, pip));
        say(@"Pip, to someone else", ask(@{@"ask": @"message", @"to": @"s-other", @"priority": @"note",
                                           @"text64": base64(@"Hi")}, pip));
        NSString *key = [@"ghp_" stringByPaddingToLength:40 withString:@"a1B2" startingAtIndex:0];
        say(@"Pip, with a key in it", ask(message(@"report", nil, [@"Use " stringByAppendingString:key]), pip));
        say(@"Pip, 8,001 characters", ask(message(@"report", nil, [@"" stringByPaddingToLength:8001 withString:@"w"
                                                                                  startingAtIndex:0]), pip));
        say(@"Pip, words that aren't base64", ask(@{@"ask": @"message", @"to": @"lead", @"priority": @"note",
                                                     @"text64": @"not base64!"}, pip));
        say(@"Pip asks for the lead's inbox", ask(@{@"ask": @"inbox"}, pip));
        say(@"The lead's inbox", ask(@{@"ask": @"inbox"}, lead));
        // What the agent says of Pip's line: held, then expired; another session's line naming Pip's message counts
        // for nothing; and a plain message to the lead, lost.
        AgentMessage *(^line)(NSString *, Row *, NSString *, NSString *) =
            ^AgentMessage *(NSString *messageId, Row *from, NSString *text, NSString *delivery) {
            AgentMessage *one = [AgentMessage new];
            one.messageId = messageId;
            one.fromSession = from.sessionId;
            one.fromName = from.name;
            one.toSession = lead.sessionId;
            one.toName = lead.name;
            one.sentAt = Now();
            one.text = text;
            one.delivery = delivery;
            one.deliveryAt = Now();
            one.canAsk = YES;
            return one;
        };
        NSString *pipLine = [NSString stringWithFormat:@"Inbox %@ · question from Pip: Which colour", question];
        [agent say:line(@"msg-pip", pip, pipLine, @"held")];
        [agent say:line(@"msg-chief", named[@"Chief"], pipLine, @"expired")];
        [agent say:line(@"msg-plain", named[@"You"], @"Are you there?", @"expired")];
        [agent messagesAfter:Now() - kWindow change:module.seen then:^(NSArray<AgentMessage *> *taken,
                                                                       NSUInteger now) {
            [module took:taken as:now];
        }];
        say(@"The agent says Pip's line is held: the inbox", ask(@{@"ask": @"inbox"}, lead));
        say(@"…it keeps Pip's line", [module keeps:line(@"msg-pip", pip, pipLine, @"held")] ? @"yes" : @"no");
        say(@"…and the chief's naming Pip's message", [module keeps:line(@"msg-chief", named[@"Chief"], pipLine,
                                                                         @"held")] ? @"yes" : @"no");
        [agent say:line(@"msg-pip", pip, pipLine, @"expired")];
        [agent messagesAfter:Now() - kWindow change:module.seen then:^(NSArray<AgentMessage *> *taken,
                                                                       NSUInteger now) {
            [module took:taken as:now];
        }];
        say(@"…then expired: the week's counts", JSONLine(InboxWeekCounts(module.record, nil, Now())));
        NSString *first = ask(@{@"ask": @"inbox-next"}, lead);
        say(@"The lead reads the next", first);
        say(@"…and the next", ask(@{@"ask": @"inbox-next"}, lead));
        say(@"Pip asks for the next", ask(@{@"ask": @"inbox-next"}, pip));
        NSDictionary *read = AsRecord([NSJSONSerialization JSONObjectWithData:[first dataUsingEncoding:NSUTF8StringEncoding]
                                                                      options:0 error:nil]);
        NSString *urgentId = AsText(read[@"id"]) ?: @"";
        say(@"Pip marks the lead's urgent one answered", ask(@{@"ask": @"inbox-answered", @"id": urgentId}, pip));
        say(@"The lead marks it answered, with a note",
            ask(@{@"ask": @"inbox-answered", @"id": urgentId, @"note64": base64(@"Stopped it")}, lead));
        say(@"…by an id that's a path", ask(@{@"ask": @"inbox-answered", @"id": @"../x"}, lead));
        say(@"…by an id nobody kept", ask(@{@"ask": @"inbox-answered", @"id": @"m-000000"}, lead));
        say(@"The lead's inbox now", ask(@{@"ask": @"inbox"}, lead));
    } else if ([phase isEqual:@"fresh"]) {
        say(@"Pip writes to its lead, which isn't running", ask(message(@"report", @"J12", @"Done."), pip));
        say(@"The lead before asks for the inbox", ask(@{@"ask": @"inbox"}, named[@"Lead"]));
        say(@"The fresh lead's inbox", ask(@{@"ask": @"inbox"}, lead));
        say(@"…it reads the next, read before and not answered", ask(@{@"ask": @"inbox-next"}, lead));
    } else {
        say(@"With no agent to say where the lead listens, Pip writes", ask(message(@"note", nil, @"Hi."), pip));
    }
    dispatch_sync(module.writes, ^{});
    struct stat file;
    say(@"The record's file", stat(RecordPath().fileSystemRepresentation, &file) == 0
        ? [NSString stringWithFormat:@"mode %o", file.st_mode & 0777] : @"none");
    fflush(stdout);

    if (arguments.count < 3) return 0;
    NSString *socket = arguments[1], *done = [socket stringByAppendingString:@".done"];
    if (![core.asks listenAt:socket]) return 1;
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:arguments[2].doubleValue];
    while (until.timeIntervalSinceNow > 0 && ![NSFileManager.defaultManager fileExistsAtPath:done])
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    [core.asks stop];
    return 0;
}
