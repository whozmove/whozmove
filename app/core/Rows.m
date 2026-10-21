// Rows: reading the rows, phase by phase, and sending them.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Rows.h"
#import "Core.h"
#import "Modules.h"
#import "Focus.h"
#import "Page.h"
#import "Row.h"
#import "Log.h"
#import "Git.h"

@interface Rows ()
@property (weak) Core *core;
@property (copy) NSDictionary<NSString *, Row *> *byId;
@property (assign) BOOL reading;    // the rows are being read now
@property (assign) BOOL readAgain;  // and a refresh came meanwhile
@property (strong) NSTimer *timer;
@property (strong) dispatch_queue_t queue;  // where the sessions are read
@end

@implementation Rows

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.queue = dispatch_queue_create("whozmove.sessions", DISPATCH_QUEUE_SERIAL);
    return self;
}

- (void)start {
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) { [weakSelf refresh]; }];
    self.timer.tolerance = 0.3;
}

// Once a second, and whenever a row has something new to show. The rows are read alongside and sent once they're
// back; a refresh that comes while they're being read waits for them, then reads again. Each module's tick comes first,
// with every refresh.
- (void)refresh {
    if (!self.core.page.ready) return;
    [self.core.modules tick];
    if (self.reading) {
        self.readAgain = YES;
        return;
    }
    self.reading = YES;
    [self read:^(NSArray<Row *> *rows) {
        self.reading = NO;
        if (rows && self.core.page.ready) [self send:rows];
        if (self.readAgain) {
            self.readAgain = NO;
            [self refresh];
        }
    }];
}

- (void)send:(NSArray<Row *> *)rows {
    NSArray *json = [rows valueForKey:@"json"];
    NSError *error = nil;
    NSData *data = [NSJSONSerialization isValidJSONObject:json]
        ? [NSJSONSerialization dataWithJSONObject:json options:0 error:&error] : nil;
    if (!data) {
        LogProblem([@"rows not sent: " stringByAppendingString:error.localizedDescription ?: @"not JSON"]);
        return;
    }
    [self.core.page update:data];
}

// The sessions are read on their own queue, and the modules add their parts here. An exception left to escape would
// end the app, so one is logged instead, and the next refresh tries again.
- (void)read:(void (^)(NSArray<Row *> *rows))done {
    dispatch_async(self.queue, ^{
        NSArray<Row *> *sessions = nil;
        @try {
            sessions = [self sessions];
        } @catch (NSException *e) {
            LogProblem([NSString stringWithFormat:@"sessions not read: %@: %@", e.name, e.reason]);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            NSArray<Row *> *rows = nil;
            @try {
                if (sessions) rows = [self complete:sessions];
            } @catch (NSException *e) {
                LogProblem([NSString stringWithFormat:@"rows not built: %@: %@", e.name, e.reason]);
            }
            done(rows);
        });
    });
}

// On the queue: each agent's running sessions; then what the apps that keep sessions as conversations of their own add
// (Claude Desktop: its own record of each conversation, which goes on the row before the agent's hooks', and its
// conversations that aren't running, which come back with status "closed"); then each agent's terminal sessions that
// have ended, which come back the same way, after those, so a conversation the app keeps is listed once, as its; then
// what each session's agent's hooks recorded and the checkout it runs in; and the requests waiting on them.
- (NSArray<Row *> *)sessions {
    NSMutableArray<Row *> *rows = [NSMutableArray array];
    for (id<Agent> agent in self.core.agents) [rows addObjectsFromArray:[agent readSessions]];
    NSArray<Row *> *running = [rows copy];
    for (id<ConversationHost> host in [self.core hostsThat:@protocol(ConversationHost)])
        [rows addObjectsFromArray:[host readRows:running]];
    NSArray<Row *> *listed = [rows copy];
    for (id<Agent> agent in self.core.agents) [rows addObjectsFromArray:[agent readEndedSessions:listed]];
    for (Row *row in rows) {
        [[self.core agentOf:row] addRecordTo:row];
        [self addCheckoutTo:row];
    }
    for (id<Agent> agent in self.core.agents) [agent addRequestsTo:rows];
    return rows;
}

// The checkout's branch and worktree. A row is about the checkout its session runs in, whatever it edits elsewhere: its
// numbers, next steps and Deploy are that checkout's. Only one that runs outside any checkout (opened in the folder
// above some, say) goes by the checkout it last edited files in (from its hooks).
- (void)addCheckoutTo:(Row *)row {
    if (row.cwd) row.git = GitInfo(row.cwd);
    if (!row.git && row.workRoot) {
        NSDictionary *workGit = GitInfo(row.workRoot);
        if (workGit) row.workGit = workGit;
    }
}

// Each phase in turn, every module's part of it in the modules' order. Once the rows are whole, they're kept by id,
// before the last phase, whose parts act on them as they are; then each ended session's row says where a press opens
// it again, and the session you're on is marked.
- (NSArray<Row *> *)complete:(NSArray<Row *> *)rows {
    for (RowPhase phase = RowPhaseCheckout; phase < RowPhaseListed; phase++) [self.core.modules rows:rows phase:phase];
    NSMutableDictionary *byId = [NSMutableDictionary dictionary];
    for (Row *row in rows)
        if (row.sessionId) byId[row.sessionId] = row;
    self.byId = byId;
    [self.core.modules rows:rows phase:RowPhaseListed];
    [self.core.focus nameReopens:rows];
    [self.core.focus mark:rows];
    return rows;
}

@end
