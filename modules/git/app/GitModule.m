// GitModule: the next steps' face for the core (Module): each row's checkout read (git status, the branch's pull
// request) and its PRs, the steps pressed on a row or in the changes view, the branches a pull request can go into,
// and a PR opened.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import "Module.h"
#import "Core.h"
#import "MenuBar.h"
#import "Page.h"
#import "Row.h"
#import "Checkouts.h"
#import "NextSteps.h"
#import "PullRequests.h"
#import "GitHub.h"
#import "Processes.h"

@interface GitModule : NSObject <Module>
@property (weak) Core *core;
@property (strong) Checkouts *checkouts;
@property (strong) NextSteps *nextSteps;
@property (strong) PullRequests *pullRequests;
@property (assign) NSTimeInterval lastChecked;  // when the PRs were last looked at
@end

@implementation GitModule

+ (NSString *)moduleName {
    return @"git";
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    // What a print run prints never depends on the network.
    if (core.printing) NeverAskGitHub = YES;
    self.checkouts = [Checkouts new];
    self.nextSteps = [[NextSteps alloc] initWithCore:core];
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

- (NSDictionary<NSString *, void (^)(NSDictionary *)> *)messages {
    __weak typeof(self) weakSelf = self;
    return @{
        @"gitStep": ^(NSDictionary *msg) { [weakSelf.nextSteps takeStep:msg]; },
        @"gitWays": ^(NSDictionary *msg) { [weakSelf.nextSteps commitMenu:msg]; },
        @"prBranches": ^(NSDictionary *msg) { [weakSelf.nextSteps branchesFor:msg]; },
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
        case RowPhaseListed: return;
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
    // Branches' PRs are looked up only while the next steps, which go by them, are on (Show Next Steps).
    if (self.core.menuBar) self.checkouts.looksUpPRs = self.core.menuBar.showsNextSteps;
    [self.checkouts refreshFor:rows];
    for (Row *row in rows) {
        NSString *root = (row.workGit ?: row.git)[@"root"];  // the checkout its row is about (Rows' addCheckoutTo:)
        if (root && [self.checkouts stateOf:root]) row.checkout = [self.checkouts stateOf:root];
    }
}

#pragma mark On the panel's back

// Git on the panel's back: what Whozmove does with it, and whether each row shows its next steps (Deploy adds its own
// switch, and install the card for Apple's developer tools). It's always listed, as every session's checkout is read
// with it. Its switch waits for the developer tools, as git does (DeveloperToolsReady).
- (NSArray<AppEntry *> *)appEntries {
    __weak typeof(self) weakSelf = self;
    AppEntry *git = [AppEntry appWithId:@"git" name:@"Git"
                                   does:@"Reads each session's checkout: what's changed, committed and on GitHub, for "
                                        @"the next steps on its row, the changes view and Deploy; and makes worktrees "
                                        @"for new conversations."
                                  order:60];
    git.present = ^BOOL { return YES; };
    AppSwitch *steps = [AppSwitch switchWithKey:@"nextSteps" title:@"Show Next Steps"
                                           help:@"On each row: what's changed, committed and on GitHub, and the step "
                                                @"that's next"
                                             on:^BOOL { return weakSelf.core.menuBar.showsNextSteps; }
                                            set:^(BOOL on) { weakSelf.core.menuBar.showsNextSteps = on; }];
    steps.enabled = ^BOOL { return DeveloperToolsReady(); };
    git.switches = @[steps];
    return @[git];
}

@end
