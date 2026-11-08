// SessionsModule: Sessions, on each host's page on the panel's back (SessionsModule.h).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "SessionsModule.h"
#import <AppKit/AppKit.h>
#import <sys/stat.h>
#import "Core.h"
#import "Agent.h"
#import "Host.h"
#import "Row.h"
#import "Rows.h"
#import "Modules.h"
#import "Focus.h"
#import "PanelWindow.h"
#import "Work.h"
#import "Files.h"
#import "Printing.h"
#import "Trashed.h"
#import "Links.h"

// How often the conversations are read again while the back is turned over, and as it starts to turn.
static const NSTimeInterval kReadEvery = 5;
// How long what the page shows is kept once built: the back is told every host's page at once, and each shows it.
static const NSTimeInterval kShownFor = 0.25;
// How often, in ticks (about a second each), a file Finder put back under the name the Trash gave it is looked for.
static const NSUInteger kRenameEvery = 5;

// How long ago, in a few words: "just now", "25 min ago", "3 h ago", "yesterday", "9 days ago".
static NSString *Ago(double at, double now) {
    double minutes = (now - at) / 60000, hours = minutes / 60, days = hours / 24;
    if (minutes < 1) return @"just now";
    if (minutes < 60) return [NSString stringWithFormat:@"%.0f min ago", floor(minutes)];
    if (hours < 24) return [NSString stringWithFormat:@"%.0f h ago", floor(hours)];
    if (days < 2) return @"yesterday";
    return [NSString stringWithFormat:@"%.0f days ago", floor(days)];
}

// A project's name, as its folder's.
static NSString *ProjectOf(NSString *folder) {
    return folder.length ? folder.lastPathComponent : @"Other";
}

@interface SessionsModule ()
@property (weak) Core *core;
@property (strong) Trashed *trashed;
@property (strong) AppList *list;
@property (strong) dispatch_queue_t queue;
@property (copy) NSArray<NSDictionary *> *conversations;  // as last read; nil until the first read is back
@property (copy) NSDictionary<NSString *, NSArray *> *keptElsewhere;  // id -> [the host's app id, its own id]
@property (copy) NSDictionary<NSString *, NSString *> *open;  // open ones: id -> why it can't be ended now, or ""
@property (copy) NSArray<NSDictionary *> *inTrash;
@property (copy) NSSet<NSString *> *unread;  // listed sessions with a reply you haven't read, as the page counts them
@property (copy) NSDictionary *said;  // what the last press did
// While a press moves conversations, how each is getting on, said on its row in Clean up's words.
@property (strong) NSMutableDictionary<NSString *, NSString *> *steps;
// The file each conversation that couldn't go left where it was, for Show in Finder (none: one gone into the Trash).
@property (strong) NSMutableDictionary<NSString *, NSString *> *stuck;
@property (assign) NSUInteger ticks;
@property (copy) NSDictionary *shownCache;
@property (assign) NSTimeInterval shownAt;
// Told each step a row takes as a press moves conversations (a print run's, which keeps them to print).
@property (copy) void (^stepped)(NSString *sessionId, NSString *words);
@property (copy) NSArray<NSString *> *lastMoved;
@property (assign) NSTimeInterval readAt;
@property (assign) BOOL reading, moving;
@end

@implementation SessionsModule

+ (NSString *)moduleName {
    return @"sessions";
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    __weak typeof(self) weakSelf = self;
    self.trashed = [[Trashed alloc] initWithFolder:AppDir(@"trashed") helper:NSBundle.mainBundle.executablePath
                                           standIn:nil isPlace:^BOOL(NSString *path) {
        return [weakSelf.agent isPlaceOfConversation:path];
    }];
    self.queue = dispatch_queue_create("whozmove.sessions", DISPATCH_QUEUE_SERIAL);
    self.unread = [NSSet set];
    self.list = [AppList listWithKey:@"sessions" title:@"Sessions"
                                 now:^NSDictionary *{ return [weakSelf shown]; }
                               press:^(NSString *key, NSArray<NSString *> *ids) { [weakSelf press:key ids:ids]; }];
    return self;
}

- (void)launch {
    __weak typeof(self) weakSelf = self;
    [self.core.window followTurn:^(BOOL turned) { if (turned) [weakSelf read]; }];
    // What Finder put back since, given its own name again, without waiting for the back to turn over.
    Trashed *trashed = self.trashed;
    dispatch_async(self.queue, ^{ [trashed now]; });
}

// Its list on every host's page: each terminal's and Claude's, and any added later.
- (NSArray<AppEntry *> *)appEntries {
    NSMutableArray *entries = [NSMutableArray array];
    for (id<Host> host in self.core.hosts) [entries addObject:[AppEntry lists:@[self.list] forApp:host.appId]];
    return entries;
}

- (NSDictionary<NSString *, void (^)(NSDictionary *)> *)messages {
    __weak typeof(self) weakSelf = self;
    return @{@"sessionsUnread": ^(NSDictionary *message) {
        NSMutableSet *ids = [NSMutableSet set];
        for (id each in AsList(message[@"ids"])) if (AsText(each)) [ids addObject:each];
        weakSelf.unread = ids;
    }};
}

- (BOOL)working {
    return self.reading || self.moving;
}

#pragma mark Reading

- (id<AgentConversations>)agent {
    return [self.core agentsThat:@protocol(AgentConversations)].firstObject;
}

// The rows by id, as the panel has them now.
- (NSDictionary<NSString *, Row *> *)rows {
    return self.core.rows.byId ?: @{};
}

// The conversations read again, off the main thread: what the agent keeps, which a host keeps itself, which of those
// listed as running are open and whether they can be ended now, and what's in the Trash.
- (void)read {
    // Not while a press moves conversations: one whose transcript has gone would leave the list, and its row's words
    // with it. It's read again once they've moved.
    if (self.reading || self.moving) return;
    self.reading = YES;
    NSMutableArray<NSString *> *running = [NSMutableArray array];
    [self.rows enumerateKeysAndObjectsUsingBlock:^(NSString *sessionId, Row *row, BOOL *stop) {
        if (row.pid > 0) [running addObject:sessionId];
    }];
    dispatch_async(self.queue, ^{
        NSDictionary *read = [self readNow:running];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self take:read];
            self.reading = NO;
        });
    });
}

- (NSDictionary *)readNow:(NSArray<NSString *> *)running {
    id<AgentConversations> agent = self.agent;
    NSArray *conversations = agent.conversations ?: @[];
    NSMutableDictionary *kept = [NSMutableDictionary dictionary];
    for (id<ConversationHost> host in [self.core hostsThat:@protocol(ConversationHost)])
        [[host keptConversations] enumerateKeysAndObjectsUsingBlock:^(NSString *agents, NSString *own, BOOL *stop) {
            kept[agents] = @[host.appId, own];
        }];
    NSMutableDictionary *open = [NSMutableDictionary dictionary];
    for (NSString *sessionId in running)
        if ([agent conversationIsOpen:sessionId]) open[sessionId] = [agent whyNotEnd:sessionId] ?: @"";
    return @{@"conversations": conversations, @"kept": kept, @"open": open, @"trash": [self.trashed now]};
}

- (void)take:(NSDictionary *)read {
    // Rows keep their steps until the list read after a move takes their place.
    if (!self.moving) self.steps = nil;
    self.shownCache = nil;
    self.conversations = read[@"conversations"];
    self.keptElsewhere = read[@"kept"];
    self.open = read[@"open"];
    self.inTrash = read[@"trash"];
    self.readAt = NSDate.timeIntervalSinceReferenceDate;
}

#pragma mark What the page shows

// Why a conversation can't go now, in a few words, and the way past it ({key, title}), from what the panel knows of it;
// nil when it can.
- (NSDictionary *)whyNot:(NSDictionary *)conversation {
    NSString *sessionId = conversation[@"id"];
    Row *row = self.rows[sessionId];
    NSDictionary *go = @{@"key": @"go", @"title": @"Take me there"};
    NSArray *kept = self.keptElsewhere[sessionId];
    if (kept) {
        NSString *name = [self hostNamed:kept[0]];
        return @{@"why": [NSString stringWithFormat:@"Delete it in %@", name],
                 @"way": @{@"key": @"keeper", @"title": [NSString stringWithFormat:@"Open in %@", name]}};
    }
    if ([conversation[@"linked"] boolValue])
        return @{@"why": @"Kept through a link to another folder: move it in Finder",
                 @"way": @{@"key": @"show", @"title": @"Show in Finder"}};
    if (row.focused) return @{@"why": @"You're looking at it"};
    if (row && AgentAsksYou(row)) return @{@"why": @"Waiting on you: answer it first", @"way": go};
    if (row && AgentAtWork(row)) return @{@"why": @"Working: stop it first", @"way": go};
    if (row && BackgroundAtWork(row)) return @{@"why": @"Its agents are still at work", @"way": go};
    NSString *open = self.open[sessionId];
    if (open.length) return @{@"why": open, @"way": go};
    return nil;
}

// A host that keeps conversations itself, by its name in full ("Claude Desktop").
- (NSString *)hostNamed:(NSString *)appId {
    for (id<ConversationHost> host in [self.core hostsThat:@protocol(ConversationHost)])
        if ([host.appId isEqual:appId]) return host.fullName;
    return @"its app";
}

- (NSString *)titleOf:(NSDictionary *)conversation {
    return AsText(conversation[@"title"]) ?: self.rows[conversation[@"id"]].name ?: @"Untitled conversation";
}

// One conversation's line: when it ended and where it ran, or, still open, where and when it last replied; with a reply
// you haven't read.
- (NSString *)lineOf:(NSDictionary *)conversation now:(double)now {
    NSString *sessionId = conversation[@"id"];
    Row *row = self.rows[sessionId];
    double moved = [conversation[@"movedAt"] doubleValue];
    NSMutableString *line = [NSMutableString string];
    if (self.open[sessionId]) {
        NSString *where = [self.core hostOf:row].name ?: row.ranIn ?: @"a terminal";
        [line appendFormat:@"Running in %@ · last reply %@", where, Ago(row.lastReplyAt.doubleValue ?: moved, now)];
    } else {
        [line appendFormat:@"Ended %@", Ago(moved, now)];
        NSString *ranIn = AsText(conversation[@"ranIn"]);
        if (ranIn.length) [line appendFormat:@" · ran in %@", ranIn];
    }
    if ([self.unread containsObject:sessionId]) [line appendString:@" · a reply you haven't read"];
    return line;
}

- (NSDictionary *)shown {
    // Read only while the back is turned (and then every few seconds): never at launch, when the back's page is first
    // told what it shows, so nothing is read for one who never turns the panel over.
    if (self.core.window.turned
        && (!self.conversations || NSDate.timeIntervalSinceReferenceDate - self.readAt >= kReadEvery))
        [self read];
    // Built once for every host's page that shows it as the back is told.
    double built = NSDate.timeIntervalSinceReferenceDate;
    if (self.shownCache && built - self.shownAt < kShownFor) return self.shownCache;
    id<AgentConversations> agent = self.agent;
    NSMutableDictionary *page = [@{
        @"intro": [NSString stringWithFormat:@"Every conversation %@ keeps on this Mac, wherever it ran. Tick what you "
                                             @"want to move to the Trash.", agent.name ?: @"your agent"],
        @"empty": @"No conversations kept on this Mac yet. They'll be listed here once you've had one.",
        @"tray": @{@"hint": @"None ticked", @"action": @"Move to Trash",
                   @"actionKey": @"trash",
                   @"pick": @{@"mark": @"ended", @"title": @"Tick All Ended ({n})", @"untitle": @"Untick Ended"},
                   @"ask": @{@"one": @"Move {name} to the Trash?", @"many": @"Move {n} conversations to the Trash?",
                             @"lead": @{@"one": @"It goes to the Trash, so you can put it back from there until you "
                                                @"empty it.",
                                        @"many": @"Each goes to the Trash on its own, so you can put any one back "
                                                 @"from there until you empty it."},
                             // Ending one also loses anything typed at its prompt and not sent, so that's said too.
                             @"notes": @[@{@"mark": @"open",
                                           @"alone": @"It's still open, so it's ended first: anything typed in it and "
                                                     @"not sent goes. Undo brings it back ended.",
                                           @"one": @"1 still open is ended first: anything typed in it and not sent "
                                                   @"goes. Undo brings it back ended.",
                                           @"many": @"{n} still open are ended first: anything typed in them and not "
                                                    @"sent goes. Undo brings them back ended."},
                                         @{@"mark": @"unread", @"alone": @"It has a reply you haven't read.",
                                           @"one": @"1 has a reply you haven't read.",
                                           @"many": @"{n} have replies you haven't read."}],
                             @"last": agent.whatStaysOfConversations ?: @""}},
    } mutableCopy];
    if (!self.conversations) {
        page[@"loading"] = @"Reading the conversations on this Mac…";
        page[@"count"] = @0;
        page[@"sections"] = @[];
        return page;
    }
    double now = NSDate.date.timeIntervalSince1970 * 1000;
    NSMutableSet<NSString *> *trashed = [NSMutableSet set];
    for (NSDictionary *each in self.inTrash) [trashed addObject:each[@"id"]];
    NSMutableArray<NSString *> *projects = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray *> *byProject = [NSMutableDictionary dictionary];
    NSUInteger count = 0;
    for (NSDictionary *conversation in self.conversations) {
        NSString *sessionId = conversation[@"id"];
        if ([trashed containsObject:sessionId]) continue;
        count++;
        NSString *project = ProjectOf(AsText(conversation[@"folder"]));
        if (!byProject[project]) {
            byProject[project] = [NSMutableArray array];
            [projects addObject:project];
        }
        NSMutableDictionary *item = [@{@"id": sessionId, @"title": [self titleOf:conversation],
                                       @"line": self.steps[sessionId] ?: [self lineOf:conversation now:now]}
                                     mutableCopy];
        NSDictionary *whyNot = [self whyNot:conversation];
        if (whyNot) [item addEntriesFromDictionary:whyNot];
        NSMutableArray *marks = [NSMutableArray arrayWithObject:self.open[sessionId] ? @"open" : @"ended"];
        if ([self.unread containsObject:sessionId]) [marks addObject:@"unread"];
        item[@"marks"] = marks;
        [byProject[project] addObject:item];
    }
    NSMutableArray *sections = [NSMutableArray array];
    for (NSString *project in projects)
        [sections addObject:@{@"title": project, @"tickable": @YES, @"items": byProject[project]}];
    if (self.inTrash.count) {
        NSMutableArray *items = [NSMutableArray array];
        for (NSDictionary *each in self.inTrash)
            [items addObject:@{@"id": each[@"id"], @"title": AsText(each[@"title"]) ?: @"Untitled conversation",
                               @"line": [NSString stringWithFormat:@"%@ · moved %@", ProjectOf(AsText(each[@"folder"])),
                                         Ago([each[@"at"] doubleValue], now)],
                               @"buttons": @[@{@"key": @"putback", @"title": @"Put Back"},
                                             @{@"key": @"reveal", @"title": @"Show in Finder"}]}];
        [sections addObject:@{@"title": @"In the Trash", @"tickable": @NO, @"items": items,
                              @"foot": self.inTrash.count == 1 ? @"It stays here until you empty the Trash."
                                                               : @"They stay here until you empty the Trash."}];
    }
    page[@"count"] = @(count);
    page[@"sections"] = sections;
    if (self.said) page[@"said"] = self.said;
    self.shownCache = page;
    self.shownAt = built;
    return page;
}

#pragma mark Presses

// Of the ids a press names, those the app itself moved or found in the Trash: a note is only ever looked for by one.
- (NSArray<NSString *> *)inTrashOf:(NSArray<NSString *> *)ids {
    NSMutableSet<NSString *> *known = [NSMutableSet setWithArray:self.lastMoved ?: @[]];
    for (NSDictionary *each in self.inTrash) [known addObject:each[@"id"]];
    return [ids filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id each, NSDictionary *bindings) {
        return [known containsObject:each];
    }]];
}

- (void)press:(NSString *)key ids:(NSArray<NSString *> *)ids {
    if ([key isEqual:@"trash"]) return [self move:ids done:nil];
    // Undo and Show in Finder are for what the last press moved (a print run, which has no last press, names them).
    if ([key isEqual:@"undo"]) return [self putBack:[self inTrashOf:ids.count ? ids : self.lastMoved ?: @[]]];
    if ([key isEqual:@"finder"]) return [self reveal:[self inTrashOf:ids.count ? ids : self.lastMoved ?: @[]]];
    if ([key isEqual:@"putback"]) return [self putBack:[self inTrashOf:ids]];
    if ([key isEqual:@"reveal"]) return [self reveal:[self inTrashOf:ids]];
    NSString *sessionId = ids.firstObject;
    if (!sessionId) return;
    if ([key isEqual:@"go"]) return [self.core.focus open:@{@"sessionId": sessionId}];
    if ([key isEqual:@"show"]) return [self showFilesOf:sessionId];
    if ([key isEqual:@"stuck"]) return [self showStuck:sessionId];
    if ([key isEqual:@"keeper"]) {
        NSArray *kept = self.keptElsewhere[sessionId];
        for (id<ConversationHost> host in [self.core hostsThat:@protocol(ConversationHost)]) {
            if (![host.appId isEqual:kept[0]]) continue;
            Row *row = [Row new];
            row.sessionId = sessionId;
            row.hostSessionId = kept[1];
            // Its link only (open:), as show: reads its log, which isn't read while its sessions aren't tracked.
            [host open:row];
        }
    }
}

- (void)say:(NSString *)text buttons:(NSArray *)buttons {
    self.shownCache = nil;
    self.said = @{@"text": text, @"buttons": buttons ?: @[], @"at": @(NSDate.date.timeIntervalSince1970 * 1000)};
}

// Moving them: anything that can't go now is left out, saying why; those still open are ended first; then each one's
// files go to the Trash, all of it or none. What it did is said, with Undo and Show in Finder.
- (void)move:(NSArray<NSString *> *)ids done:(void (^)(void))done {
    if (!ids.count) return;
    if (self.moving) {
        [self say:@"Still moving the others to the Trash: press Move to Trash again once they've gone." buttons:nil];
        return;
    }
    NSMutableArray<NSDictionary *> *leftOut = [NSMutableArray array], *going = [NSMutableArray array];
    for (NSDictionary *conversation in self.conversations) {
        if (![ids containsObject:conversation[@"id"]]) continue;
        NSDictionary *whyNot = [self whyNot:conversation];
        if (whyNot) [leftOut addObject:@{@"id": conversation[@"id"], @"title": [self titleOf:conversation],
                                         @"why": whyNot[@"why"], @"way": whyNot[@"way"] ?: NSNull.null}];
        else [going addObject:@{@"id": conversation[@"id"], @"title": [self titleOf:conversation],
                                @"folder": AsText(conversation[@"folder"]) ?: @""}];
    }
    self.moving = YES;
    self.steps = [NSMutableDictionary dictionary];
    for (NSDictionary *each in going) {
        self.steps[each[@"id"]] = @"Waiting";
        if (self.stepped) self.stepped(each[@"id"], @"Waiting");
    }
    NSUInteger opened = 0;
    for (NSDictionary *each in going) if (self.open[each[@"id"]]) opened++;
    if (opened) [self say:[NSString stringWithFormat:@"Ending %lu open session%@…", (unsigned long)opened,
                           opened == 1 ? @"" : @"s"] buttons:nil];
    id<AgentConversations> agent = self.agent;
    Trashed *trashed = self.trashed;
    void (^step)(NSString *, NSString *) = ^(NSString *sessionId, NSString *words) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.steps[sessionId] = words;
            self.shownCache = nil;
            if (self.stepped) self.stepped(sessionId, words);
        });
    };
    dispatch_async(self.queue, ^{
        NSMutableArray<NSDictionary *> *moved = [NSMutableArray array], *failed = [NSMutableArray array];
        for (NSDictionary *each in going) {
            NSString *sessionId = each[@"id"];
            // Checked again as it acts: one open now that couldn't be ended is left out.
            if ([agent conversationIsOpen:sessionId]) {
                NSString *why = [agent whyNotEnd:sessionId];
                if (!why) {
                    step(sessionId, @"Ending it…");
                    dispatch_semaphore_t ended = dispatch_semaphore_create(0);
                    __block NSString *endWhy = nil;
                    [agent endConversation:sessionId done:^(NSString *w) {
                        endWhy = w;
                        dispatch_semaphore_signal(ended);
                    }];
                    // Its done comes on the main thread, never this queue, so waiting here holds up nothing it needs.
                    dispatch_semaphore_wait(ended, DISPATCH_TIME_FOREVER);
                    why = endWhy;
                }
                if (why) {
                    [leftOut addObject:@{@"id": sessionId, @"title": each[@"title"], @"why": why,
                                         @"way": @{@"key": @"go", @"title": @"Take me there"}}];
                    step(sessionId, [@"Stayed: " stringByAppendingString:why]);
                    continue;
                }
            }
            step(sessionId, @"Moving to the Trash…");
            NSString *stuck = nil;
            BOOL lost = NO;
            NSString *why = [trashed trash:sessionId files:[agent filesOfConversation:sessionId] about:each
                                     stuck:&stuck lost:&lost];
            if (why) {
                [failed addObject:@{@"id": sessionId, @"title": each[@"title"], @"why": why, @"lost": @(lost),
                                    @"stuck": stuck ?: NSNull.null}];
                step(sessionId, lost ? @"In the Trash in part" : @"Stayed: one of its files couldn't be moved");
            } else {
                [moved addObject:each];
                step(sessionId, @"In the Trash");
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self said:moved leftOut:leftOut failed:failed];
            self.moving = NO;
            [self read];
            if (done) done();
        });
    });
}

- (void)said:(NSArray<NSDictionary *> *)moved leftOut:(NSArray<NSDictionary *> *)leftOut
      failed:(NSArray<NSDictionary *> *)failed {
    NSMutableArray<NSString *> *words = [NSMutableArray array];
    NSMutableArray *buttons = [NSMutableArray array];
    if (moved.count) {
        [words addObject:moved.count == 1 ? [NSString stringWithFormat:@"Moved %@ to the Trash.", moved[0][@"title"]]
                         : [NSString stringWithFormat:@"Moved %lu conversations to the Trash.",
                                                      (unsigned long)moved.count]];
        [buttons addObjectsFromArray:@[@{@"key": @"undo", @"title": @"Undo"},
                                       @{@"key": @"finder", @"title": @"Show in Finder"}]];
    }
    for (NSDictionary *each in leftOut)
        [words addObject:[NSString stringWithFormat:@"%@ is left out. %@.", each[@"title"], each[@"why"]]];
    if (leftOut.count == 1 && leftOut[0][@"way"] != NSNull.null) {
        NSDictionary *way = leftOut[0][@"way"];
        [buttons addObject:@{@"key": way[@"key"], @"title": way[@"title"], @"ids": @[leftOut[0][@"id"]]}];
    }
    self.stuck = [NSMutableDictionary dictionary];
    for (NSDictionary *each in failed) {
        [words addObject:[each[@"lost"] boolValue]
            ? [NSString stringWithFormat:@"%@ went to the Trash in part: one of its files is there, the rest stayed.",
                                         each[@"title"]]
            : [NSString stringWithFormat:@"%@ couldn't go to the Trash: %@. Nothing of it was moved.", each[@"title"],
                                         each[@"why"]]];
        if (each[@"stuck"] != NSNull.null) self.stuck[each[@"id"]] = each[@"stuck"];
    }
    // The way past one that couldn't go: the file that stayed, or the Trash, where one went.
    if (failed.count == 1)
        [buttons addObject:@{@"key": @"stuck", @"title": @"Show in Finder", @"ids": @[failed[0][@"id"]]}];
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    for (NSDictionary *each in moved) [ids addObject:each[@"id"]];
    self.lastMoved = ids;
    if (words.count) [self say:[words componentsJoinedByString:@" "] buttons:buttons];
    else self.said = nil;
}

- (void)putBack:(NSArray<NSString *> *)ids {
    NSMutableArray<NSString *> *words = [NSMutableArray array];
    for (NSString *sessionId in ids) {
        NSString *why = [self.trashed putBack:sessionId];
        if (!why) continue;
        NSString *title = @"It";
        for (NSDictionary *each in self.inTrash)
            if ([each[@"id"] isEqual:sessionId]) title = AsText(each[@"title"]) ?: title;
        [words addObject:[NSString stringWithFormat:@"%@ can't go back: %@.", title, why]];
    }
    if ([ids isEqualToArray:self.lastMoved ?: @[]]) self.lastMoved = nil;
    if (words.count) [self say:[words componentsJoinedByString:@" "]
                       buttons:@[@{@"key": @"reveal", @"title": @"Show in Finder", @"ids": ids}]];
    else if (self.moving)
        [self say:@"Put back. It's listed again once the others have gone to the Trash." buttons:nil];
    else self.said = nil;
    // In the Trash says at once what's still there (while a press moves others, the list waits for it).
    self.inTrash = [self.trashed now];
    self.shownCache = nil;
    [self read];
}

// A conversation's files in Finder, for one that can't go from here: kept through a link to another folder.
- (void)showFilesOf:(NSString *)sessionId {
    id<AgentConversations> agent = self.agent;
    dispatch_async(self.queue, ^{
        NSMutableArray<NSURL *> *urls = [NSMutableArray array];
        for (NSString *file in [agent filesOfConversation:sessionId]) [urls addObject:[NSURL fileURLWithPath:file]];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (urls.count) [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:urls];
        });
    });
}

// The file that stayed when a conversation couldn't go, or the Trash, where one went without saying where.
- (void)showStuck:(NSString *)sessionId {
    NSString *file = self.stuck[sessionId];
    struct stat info;
    if (file && lstat(file.fileSystemRepresentation, &info) == 0)
        return [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:file]]];
    NSString *trash = TrashFolderFor(Home());
    if (trash) OpenInOtherApp([NSURL fileURLWithPath:trash]);
}

// Every few seconds, what Finder put back since under the name the Trash gave it gets its own name back (Trashed's
// now), so a conversation resumed before Sessions is looked at again finds its files where they were.
- (void)tick {
    if (++self.ticks % kRenameEvery || self.reading || self.moving) return;
    Trashed *trashed = self.trashed;
    dispatch_async(self.queue, ^{ [trashed now]; });
}

- (void)reveal:(NSArray<NSString *> *)ids {
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    for (NSString *sessionId in ids)
        for (NSString *place in [self.trashed placesOf:sessionId]) [urls addObject:[NSURL fileURLWithPath:place]];
    if (urls.count) [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:urls];
}

#pragma mark Helper runs

+ (NSDictionary<NSString *, HelperRun> *)helperRuns {
    return @{@"--helper-trash-item": ^int(Core *core, NSArray<NSString *> *arguments) {
        return HelperTrashItem(core, arguments);
    }};
}

// Why a path may not go to the Trash from --helper-trash-item, in a few words, or nil when it may: only a whole path
// that's there and isn't a link, in a place the agent says is one of a conversation's (with only the folders they're
// kept in resolved), and only in a home folder that's surely yours, as macOS's Trash is your account's whatever HOME
// says, so a test's throwaway home never sends a file there.
static NSString *WhyNotTrashItem(NSString *path, id<AgentConversations> agent) {
    struct stat info;
    if (!PlainPath(path)) return @"it isn't a whole path";
    if (lstat(path.fileSystemRepresentation, &info) != 0) return @"it isn't there";
    if (S_ISLNK(info.st_mode)) return @"it's a link";
    if (![agent isPlaceOfConversation:path]) return @"it isn't one of a conversation's files";
    if (!HomeSurelyYourOwn()) return @"HOME isn't your own home folder";
    return nil;
}

// `Whozmove --helper-trash-item <path>`: one of a conversation's files moved to your Trash, printing where it went
// ({to}), or why not ({why}, exiting 1). Sessions runs it for each file it moves, one after another: macOS records
// where an item came from, which Finder's Put Back reads, only for the first item a process moves to the Trash.
static int HelperTrashItem(Core *core, NSArray<NSString *> *arguments) {
    id<AgentConversations> agent = [core agentsThat:@protocol(AgentConversations)].firstObject;
    NSString *path = arguments.count == 1 ? arguments[0] : nil;
    NSString *why = WhyNotTrashItem(path, agent);
    NSURL *went = nil;
    if (!why && (![NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:path] resultingItemURL:&went
                                                         error:nil] || !went.path))
        why = @"macOS didn't move it";
    if (why) {
        PrintJSON(@{@"why": why});
        return 1;
    }
    return PrintJSON(@{@"to": went.path});
}

#pragma mark Print runs

+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return @{@"--print-sessions": ^int(Core *core, NSArray<NSString *> *arguments) {
        return PrintSessions(core, arguments);
    }};
}

// `Whozmove --print-sessions <stand-in Trash> [--helper <program>] [<key> <id>…]`: Sessions for the home folder in
// $HOME, as its page would show it, after a press when one is given (trash, with each row's steps as it went; undo;
// putback), moving files into the stand-in Trash rather than macOS's own, which is your account's whatever HOME says:
// by `program` run as --helper-trash-item would be, when given, else itself. `tick` ticks the module as the app would,
// till it looks for files Finder put back, and prints nothing of the page. It changes Whozmove's folder and Claude
// Code's in $HOME, so it refuses your own.
static int PrintSessions(Core *core, NSArray<NSString *> *given) {
    if (!given.count) return 2;
    NSMutableArray<NSString *> *arguments = [given mutableCopy];
    NSString *helper = nil;
    if (arguments.count > 2 && [arguments[1] isEqual:@"--helper"]) {
        helper = arguments[2];
        [arguments removeObjectsInRange:NSMakeRange(1, 2)];
    }
    if (HomeIsYourOwn()) {
        fprintf(stderr, "--print-sessions changes the agent's folder in $HOME: give it a throwaway one\n");
        return 2;
    }
    SessionsModule *module = nil;
    for (id each in core.modules.all) if ([each isKindOfClass:SessionsModule.class]) module = each;
    module.trashed = [[Trashed alloc] initWithFolder:AppDir(@"trashed") helper:helper standIn:arguments[0]
                                             isPlace:^BOOL(NSString *path) {
        return [module.agent isPlaceOfConversation:path];
    }];
    if (arguments.count > 1 && [arguments[1] isEqual:@"tick"]) {
        for (NSUInteger i = 0; i < kRenameEvery; i++) [module tick];
        dispatch_sync(module.queue, ^{});
        return PrintJSON(@{@"ticked": @(kRenameEvery)});
    }
    NSArray<Row *> *rows = SettledRows(core);
    NSMutableArray<NSString *> *running = [NSMutableArray array];
    for (Row *row in rows) if (row.pid > 0 && row.sessionId) [running addObject:row.sessionId];
    [module take:[module readNow:running]];
    NSDictionary *stepsSeen = nil;
    if (arguments.count > 1) {
        NSString *key = arguments[1];
        NSArray *ids = [arguments subarrayWithRange:NSMakeRange(2, arguments.count - 2)];
        NSMutableDictionary<NSString *, NSMutableArray *> *steps = [NSMutableDictionary dictionary];
        if ([key isEqual:@"trash"]) {
            module.stepped = ^(NSString *sessionId, NSString *words) {
                if (!steps[sessionId]) steps[sessionId] = [NSMutableArray array];
                [steps[sessionId] addObject:words];
            };
            __block BOOL finished = NO;
            [module move:ids done:^{ finished = YES; }];
            NSDate *until = [NSDate dateWithTimeIntervalSinceNow:15];
            while (!finished && [until timeIntervalSinceNow] > 0)
                [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode
                                    beforeDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
        } else [module press:key ids:ids];
        while (module.reading)
            [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
        [module take:[module readNow:running]];
        stepsSeen = steps;
    }
    NSMutableDictionary *shown = [[module shown] mutableCopy];
    if (stepsSeen.count) shown[@"steps"] = stepsSeen;
    if (shown[@"said"]) {
        NSMutableDictionary *said = [shown[@"said"] mutableCopy];
        [said removeObjectForKey:@"at"];
        shown[@"said"] = said;
    }
    return PrintJSON(shown);
}

@end
