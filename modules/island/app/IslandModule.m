// IslandModule: the island's face for the core (Module): each row's checkout read (git status, the extra stage, the
// branch's pull request) and its PRs, the menus behind its stages and the commits stage's card, the extra stage's
// question, and a PR opened.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import "Module.h"
#import "Core.h"
#import "Rows.h"
#import "MenuBar.h"
#import "Page.h"
#import "Row.h"
#import "Checkouts.h"
#import "Stages.h"
#import "NextSteps.h"
#import "PullRequests.h"
#import "GitHub.h"

@interface IslandModule : NSObject <Module>
@property (weak) Core *core;
@property (strong) Checkouts *checkouts;
@property (strong) Stages *stages;
@property (strong) NextSteps *nextSteps;
@property (strong) PullRequests *pullRequests;
@property (assign) NSTimeInterval lastChecked;  // when the PRs were last looked at
@property (copy) NSString *sentFiles;           // the checkouts' file lists the page was last given, as JSON
@end

@implementation IslandModule

+ (NSString *)moduleName {
    return @"island";
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    // What a print run prints never depends on the network.
    if (core.printing) NeverAskGitHub = YES;
    self.checkouts = [Checkouts new];
    self.checkouts.core = core;
    self.stages = [[Stages alloc] initWithCore:core checkouts:self.checkouts];
    self.nextSteps = [[NextSteps alloc] initWithCore:core stages:self.stages checkouts:self.checkouts];
    self.pullRequests = [PullRequests new];
    self.pullRequests.core = core;
    return self;
}

// A new PR link in a session's record has its state asked at once, rather than with the next check.
- (void)launch {
    __weak PullRequests *pullRequests = self.pullRequests;
    for (id<AgentWork> agent in [self.core agentsThat:@protocol(AgentWork)])
        agent.onPRLinks = ^{ [pullRequests check]; };
}

- (void)pageLoaded {
    self.sentFiles = nil;
}

- (NSDictionary<NSString *, void (^)(NSDictionary *)> *)messages {
    __weak typeof(self) weakSelf = self;
    return @{
        @"stageMenu": ^(NSDictionary *msg) { [weakSelf.nextSteps stageMenu:msg]; },
        @"stageCard": ^(NSDictionary *msg) { [weakSelf.nextSteps stageCard:msg]; },
        @"stageStep": ^(NSDictionary *msg) { [weakSelf.nextSteps takeStep:msg]; },
        @"stageTrust": ^(NSDictionary *msg) {
            Row *row = weakSelf.core.rows.byId[msg[@"sessionId"]];
            if (row) [weakSelf.stages trust:msg row:row];
        },
        @"openPR": ^(NSDictionary *msg) {
            NSURL *url = [NSURL URLWithString:msg[@"url"]];
            if ([url.scheme isEqualToString:@"https"]) [NSWorkspace.sharedWorkspace openURL:url];
        },
    };
}

#pragma mark The rows

- (void)rows:(NSArray<Row *> *)rows phase:(RowPhase)phase {
    switch (phase) {
        case RowPhaseCheckout: return [self checkoutsOf:rows];
        case RowPhaseWork:
            for (Row *row in rows) row.prs = [self.pullRequests prsFor:row];
            return;
        case RowPhaseDetails: return;
        case RowPhaseListed: return [self sendFilesOf:rows];
    }
}

- (BOOL)working {
    return self.checkouts.checking;
}

// The PRs due a check, every 10s; and each row's checkout, which what's counted of its changes goes by (the commits
// waiting, say). The git and gh reads run alongside; what they find shows in the rows from a later read on.
- (void)checkoutsOf:(NSArray<Row *> *)rows {
    self.pullRequests.rows = rows;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (now - self.lastChecked >= 10) {
        self.lastChecked = now;
        [self.pullRequests check];
    }
    // Extra stages run, and branches' PRs are looked up, only while the islands showing them are on (Show Next Steps).
    if (self.core.menuBar) self.checkouts.runsStages = self.core.menuBar.showsNextSteps;
    [self.checkouts refreshFor:rows];
    for (Row *row in rows) {
        NSString *root = (row.workGit ?: row.git)[@"root"];  // the checkout its row is about (Rows' addCheckoutTo:)
        if (root && [self.checkouts stateOf:root]) row.checkout = [self.checkouts stateOf:root];
    }
}

// The files in each listed checkout, by kind, for the lists the island's gauge shows on hover: the first 100 staged,
// partly staged (staged, then changed again) and unstaged, with the new files apart. Sent only when they change, not
// with the rows every second, as each session in a checkout would carry its own copy.
- (void)sendFilesOf:(NSArray<Row *> *)rows {
    NSMutableDictionary *files = [NSMutableDictionary dictionary];
    for (Row *row in rows) {
        NSString *root = (row.workGit ?: row.git)[@"root"];
        NSDictionary *details = root && !files[root] ? [self.checkouts detailsOf:root] : nil;
        if (details) files[root] = @{@"staged": details[@"stagedPaths"] ?: @[],
                                     @"partly": details[@"partlyPaths"] ?: @[],
                                     @"unstaged": details[@"unstagedPaths"] ?: @[],
                                     @"new": details[@"newPaths"] ?: @[]};
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:files options:NSJSONWritingSortedKeys error:nil];
    NSString *text = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : nil;
    if (!text || [text isEqualToString:self.sentFiles] || !self.core.page.ready) return;
    self.sentFiles = text;
    [self.core.page call:@"setCheckoutFiles" with:@[files]];
}

@end
