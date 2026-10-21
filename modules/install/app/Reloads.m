// Reloads: sessions that started before Whozmove's hooks went in, reloaded from the panel one at a time.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Reloads.h"
#import "Core.h"
#import "Rows.h"
#import "Row.h"
#import "Send.h"
#import "Page.h"
#import "Files.h"
#import "Log.h"
#import "Processes.h"

// What's been reloaded, by session, as when: the hooks stay in a session reloaded since its process started, until it
// ends, even if they're taken out and put back meanwhile, as it keeps running the copy it loaded.
static NSString *ReloadsFile(void) {
    return AppDir(@"reloads.json");
}

static NSNumber *NowMs(void) {
    return @((long long)(NSDate.date.timeIntervalSince1970 * 1000));
}

static NSString *NameOf(Row *row) {
    return row.name.length ? row.name : row.cwd.lastPathComponent ?: @"";
}

@interface Reloads ()
@property (weak) Core *core;
@property (weak) id<AgentInstall> agent;
@property (strong) NSMutableDictionary<NSString *, NSNumber *> *reloaded;
@property (strong) NSMutableOrderedSet<NSString *> *needs, *waiting;
@property (strong) NSSet<NSString *> *idle;  // of those that need it, the ones idle now
@property (copy) NSString *current;          // the one going in now
@property (assign) NSInteger done, total;    // since the last press
@property (strong) NSNumber *allSetAt;       // when a press reloaded the last of them, in ms
// The ones left for you to reload in their tabs, each {why, command, held}: the panel can't type into it (no terminal
// it types into, its tab not certain, open in another terminal too), or Claude Code held the reload back, as it would
// re-read the conversation. Try Again on its row puts it back in the queue.
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *byHand;
@property (strong) NSDictionary *firstByHand;  // the first of them listed, for the line
@property (strong) NSDictionary *names;        // sessionId -> its name, as its row shows it
@property (strong) NSDictionary *told;
@end

@implementation Reloads

- (instancetype)initWithCore:(Core *)core agent:(id<AgentInstall>)agent {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.agent = agent;
    NSMutableDictionary *kept = [NSMutableDictionary dictionary];
    [AsRecord(ReadJSON(ReloadsFile())) enumerateKeysAndObjectsUsingBlock:^(id sid, id at, BOOL *stop) {
        if (AsText(sid) && AsNumber(at)) kept[sid] = at;
    }];
    self.reloaded = kept;
    self.needs = [NSMutableOrderedSet orderedSet];
    self.waiting = [NSMutableOrderedSet orderedSet];
    self.idle = [NSSet set];
    self.byHand = [NSMutableDictionary dictionary];
    return self;
}

// A session needs it while it runs without the hooks, as its agent tells, once its first message is sent (before that,
// nothing it did would be recorded, and it has nowhere to write the command's result), unless the panel has reloaded
// it since it started. Its row says which: needed, waiting for its turn, going in, or left for you to reload in its
// tab, with why and the command to type.
- (void)mark:(NSArray<Row *> *)rows {
    NSMutableOrderedSet *needs = [NSMutableOrderedSet orderedSet];
    NSMutableSet *idle = [NSMutableSet set];
    NSMutableDictionary *names = [NSMutableDictionary dictionary];
    NSTimeInterval since = self.hooksAt.doubleValue / 1000;
    NSDictionary *firstByHand = nil;
    for (Row *row in rows) {
        NSString *sid = row.sessionId;
        if (!sid || !self.hooksAt || !row.messageAt || [self reloadedSinceItStarted:row]) continue;
        if (![self.agent runsWithoutHooks:row since:since]) continue;
        [needs addObject:sid];
        names[sid] = NameOf(row);
        if (![self atWork:row]) [idle addObject:sid];
        NSDictionary *hand = self.byHand[sid];
        if (hand) {
            row.reload = @{@"state": @"byHand", @"why": hand[@"why"], @"command": hand[@"command"],
                           @"held": hand[@"held"]};
            if (!firstByHand)
                firstByHand = @{@"sessionId": sid, @"name": NameOf(row), @"command": hand[@"command"],
                                @"held": hand[@"held"]};
            continue;
        }
        NSString *state = [sid isEqualToString:self.current] ? @"reloading"
                        : [self.waiting containsObject:sid] ? @"waiting" : @"needed";
        row.reload = @{@"state": state};
    }
    self.needs = needs;
    self.idle = idle;
    self.names = names;
    self.firstByHand = firstByHand;
    // One that needs it no more (it ended, or reloaded them itself) isn't waited for, nor left for you.
    [self.waiting intersectOrderedSet:needs];
    for (NSString *sid in self.byHand.allKeys)
        if (![needs containsObject:sid]) [self.byHand removeObjectForKey:sid];
    [self changed];
}

- (BOOL)reloadedSinceItStarted:(Row *)row {
    NSNumber *at = self.reloaded[row.sessionId];
    long long started = row.pid > 0 ? ProcessStartedAt(row.pid) : 0;  // microseconds since 1970
    return at && started > 0 && at.doubleValue / 1000 > started / 1e6;
}

- (BOOL)atWork:(Row *)row {
    return [row.status isEqualToString:@"busy"] || [row.status isEqualToString:@"waiting"] || row.ask.count > 0;
}

// The ones the panel can try now, in the list's order: those that need it, are idle, and aren't left for you; and how
// many need it that aren't left for you.
- (NSArray<NSString *> *)reloadableNow {
    NSMutableArray *ready = [NSMutableArray array];
    for (NSString *sid in self.needs)
        if ([self.idle containsObject:sid] && !self.byHand[sid]) [ready addObject:sid];
    return ready;
}

- (NSUInteger)reloadable {
    NSUInteger count = 0;
    for (NSString *sid in self.needs)
        if (!self.byHand[sid]) count++;
    return count;
}

// A row's press: Reload, or Try Again on one left for you, which puts it back in the queue. Only while it's idle: its
// row offers neither while its agent works.
- (void)reload:(NSString *)sessionId {
    if (!sessionId || ![self.needs containsObject:sessionId] || ![self.idle containsObject:sessionId]
        || [self.waiting containsObject:sessionId] || [sessionId isEqualToString:self.current])
        return;
    [self.byHand removeObjectForKey:sessionId];
    if (!self.waiting.count && !self.current) self.done = self.total = 0;
    self.total++;
    [self.waiting insertObject:sessionId atIndex:0];
    self.allSetAt = nil;
    PanelLog(@"install: reload pressed for %@", sessionId);
    [self tick];
    [self changed];
}

// Reload Them: the ones idle right now, one after another, as your press does them. One at work isn't queued for
// later, where it would go in by itself once it's done, maybe as you type there: its row offers Reload once it's idle.
- (void)reloadAll {
    NSInteger more = 0;
    if (!self.waiting.count && !self.current) self.done = self.total = 0;
    for (NSString *sid in self.reloadableNow)
        if (![self.waiting containsObject:sid] && ![sid isEqualToString:self.current]) {
            [self.waiting addObject:sid];
            more++;
        }
    if (!more) return;
    self.total += more;
    self.allSetAt = nil;
    PanelLog(@"install: Reload Them pressed for %ld session%@", (long)more, more == 1 ? @"" : @"s");
    [self tick];
    [self changed];
}

// The next one waiting goes in; one that has started working meanwhile is let go, and its row offers Reload again once
// it's done.
- (void)tick {
    if (self.current) return;
    for (NSString *sid in [self.waiting copy]) {
        Row *row = self.core.rows.byId[sid];
        [self.waiting removeObject:sid];
        if (!row) continue;
        if ([self atWork:row]) {
            PanelLog(@"install: %@ started working, so it isn't reloaded now", sid);
            self.total = MAX(self.done, self.total - 1);
            continue;
        }
        [self go:row];
        return;
    }
}

// Typed in as the panel's commands are, only while it's idle; once its result says it took, it's kept as reloaded.
- (void)go:(Row *)row {
    NSString *sid = row.sessionId;
    self.current = sid;
    [self changed];
    __weak typeof(self) weakSelf = self;
    [self.core.send run:self.agent.reloadCommand row:row here:@"reloaded from here" there:@"reload it there"
                   done:^(NSString *result, NSString *why) {
        typeof(self) me = weakSelf;
        if (!me) return;
        me.current = nil;
        if (result && [me.agent reloaded:result]) {
            me.reloaded[sid] = NowMs();
            [me keep];
            me.done++;
        } else {
            me.total = MAX(me.done, me.total - 1);
            [me refused:sid result:result why:why];
        }
        [me changed];
        [me tick];
    }];
}

// A result that says Claude Code held the reload back is left for you, in Claude Code's words, with the command that
// takes it anyway; so is one the panel can't type into (no terminal it types into, its tab not certain, open in another
// terminal too). Anything else passes (its agent started working, a change still going in, words in Claude Desktop's
// box): its row says why, with the button past a terminal's reason when there is one, and offers Reload again.
- (void)refused:(NSString *)sid result:(NSString *)result why:(NSString *)why {
    if (result) {
        self.byHand[sid] = @{@"why": Clip(result, 300), @"command": self.agent.forcedReloadCommand ?: @"",
                             @"held": @YES};
        return;
    }
    Row *row = self.core.rows.byId[sid];
    SessionReach *reach = row ? [self.core.send reachOf:row] : nil;
    NSString *way = reach && why ? WayPast(reach, why) : nil;
    BOOL lasting = reach && !reach.desktop && !way && !reach.changing
        && (!reach.terminal || !reach.hasTab || !reach.unique || reach.openTwice);
    if (lasting) {
        self.byHand[sid] = @{@"why": why ?: @"Whozmove can't type into it", @"command": self.agent.reloadCommand ?: @"",
                             @"held": @NO};
        return;
    }
    if (why) [self.core.page stepNote:sid text:why way:way];
}

// Kept only for sessions still listed.
- (void)keep {
    NSMutableDictionary *kept = [NSMutableDictionary dictionary];
    [self.reloaded enumerateKeysAndObjectsUsingBlock:^(NSString *sid, NSNumber *at, BOOL *stop) {
        if (self.core.rows.byId[sid]) kept[sid] = at;
    }];
    self.reloaded = kept;
    NSData *json = [NSJSONSerialization dataWithJSONObject:kept options:NSJSONWritingSortedKeys error:nil];
    if (![json writeToFile:ReloadsFile() atomically:YES]) LogProblem(@"install: couldn't keep what was reloaded");
}

// Nothing while the hooks aren't in: then no session counts as needing them, which isn't all being set.
- (NSDictionary *)summary {
    if (!self.hooksAt) return nil;
    if (self.needs.count) {
        NSMutableDictionary *summary = [@{@"open": @(self.reloadable), @"idle": @(self.reloadableNow.count),
                                          @"byHand": @(self.byHand.count),
                                          @"waiting": @(self.waiting.count + (self.current ? 1 : 0)),
                                          @"done": @(self.done), @"total": @(self.total),
                                          @"since": self.hooksAt} mutableCopy];
        if (self.firstByHand) summary[@"first"] = self.firstByHand;
        NSString *going = self.current ?: self.waiting.firstObject;
        if (going && self.names[going]) summary[@"going"] = self.names[going];
        return summary;
    }
    if (self.done && !self.allSetAt) self.allSetAt = NowMs();
    return self.done ? @{@"allSet": @YES, @"since": self.allSetAt} : nil;
}

- (void)changed {
    NSDictionary *summary = self.summary;
    if ((summary || self.told) && ![summary isEqual:self.told]) {
        self.told = summary;
        if (self.onChange) self.onChange();
    }
}

@end
