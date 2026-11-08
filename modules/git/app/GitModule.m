// GitModule: the next steps' face for the core (Module): each row's checkout read (git status, the branch's pull
// request) and its PRs, the steps pressed on a row or in the changes view, the branches a pull request can go into,
// and a PR opened. And a waiting session's pull request, for the waits module (WakeSource, contracts/Wake.h).
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
#import "PRWakes.h"
#import "Wake.h"
#import "GitHub.h"
#import "Processes.h"
#import "CheckoutWatch.h"
#import "Printing.h"
#import "Git.h"
#import "Links.h"
#import "Files.h"

@interface GitModule : NSObject <Module, WakeSource>
@property (weak) Core *core;
@property (strong) PRWakes *prWakes;
@property (strong) Checkouts *checkouts;
@property (strong) NextSteps *nextSteps;
@property (strong) PullRequests *pullRequests;
@property (assign) NSTimeInterval lastChecked;  // when the PRs were last looked at
@end

// `Whozmove --print-watched <root>…`: starts telling those checkouts' changes (CheckoutWatch), then reads its standard
// input a line at a time. Each line names a change the test has just made; once macOS has told what it changed, it
// notes which checkouts' counts moved since the line before (files, refs, repo), each named by its last path component.
// Each line after one reading "branches", "<root>\t<branch>", notes whether that branch is on a remote
// (BranchOnRemote). Then when a git status read is due for sample states (CheckoutReadDue). As JSON, then quit.
static int PrintWatched(NSArray<NSString *> *roots) {
    StartCheckoutWatch();
    WatchCheckouts(@"print", [NSSet setWithArray:roots]);
    void (^settle)(NSTimeInterval) = ^(NSTimeInterval seconds) {
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
    };
    settle(1);
    NSMutableArray *watched = [NSMutableArray array], *steps = [NSMutableArray array];
    NSMutableArray *branches = [NSMutableArray array];
    for (NSString *root in roots) [watched addObject:@[root.lastPathComponent, @(CheckoutWatched(root))]];
    NSArray *(^counts)(void) = ^NSArray * {
        NSMutableArray *all = [NSMutableArray array];
        for (NSString *root in roots)
            [all addObject:@[@(CheckoutFileChanges(root)), @(CheckoutRefChanges(root)), @(CheckoutRepoChanges(root))]];
        return all;
    };
    NSArray *before = counts();
    BOOL branchLines = NO;
    char buffer[4096];
    while (fgets(buffer, sizeof buffer, stdin)) {
        NSString *line = [@(buffer) stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet];
        NSArray *f = [line componentsSeparatedByString:@"\t"];
        if ([line isEqualToString:@"branches"]) { branchLines = YES; continue; }
        if (branchLines) {
            if (f.count >= 2) [branches addObject:@[[f[0] lastPathComponent], f[1], @(BranchOnRemote(f[0], f[1]))]];
            continue;
        }
        if (!line.length) continue;
        settle(1.5);
        NSArray *after = counts();
        NSMutableArray *moved = [NSMutableArray array];
        for (NSUInteger i = 0; i < roots.count; i++) {
            NSMutableArray *which = [NSMutableArray array];
            NSArray *names = @[@"files", @"refs", @"repo"];
            for (NSUInteger k = 0; k < 3; k++)
                if ([after[i][k] unsignedIntegerValue] > [before[i][k] unsignedIntegerValue])
                    [which addObject:names[k]];
            if (which.count)
                [moved addObject:[NSString stringWithFormat:@"%@: %@", [roots[i] lastPathComponent],
                                                            [which componentsJoinedByString:@" "]]];
        }
        [steps addObject:@[line, moved]];
        before = after;
    }
    // Watched or not, changed or not, a few seconds and minutes after the last read, with a session active there since.
    NSMutableArray *due = [NSMutableArray array];
    for (NSArray *c in @[@[@NO, @NO, @3, @YES], @[@NO, @NO, @3, @NO], @[@NO, @NO, @21, @NO], @[@YES, @NO, @21, @YES],
                         @[@YES, @YES, @1, @YES], @[@YES, @YES, @3, @YES], @[@YES, @YES, @3, @NO],
                         @[@YES, @YES, @21, @NO], @[@YES, @NO, @299, @NO], @[@YES, @NO, @301, @NO]])
        [due addObject:@[[NSString stringWithFormat:@"%@, %@, %@s, %@", [c[0] boolValue] ? @"watched" : @"not watched",
                          [c[1] boolValue] ? @"changed" : @"unchanged", c[2],
                          [c[3] boolValue] ? @"active since" : @"quiet"],
                         @(CheckoutReadDue([c[0] boolValue], [c[1] boolValue], [c[2] doubleValue], [c[3] boolValue],
                                           300))]];
    return PrintJSON(@{@"watched": watched, @"steps": steps, @"onRemote": branches, @"due": due});
}

// `Whozmove --print-pr-wakes <activity.json> <since>`: what a waiting session would be woken by on a pull request, from
// gh's answer as the file gives it, for a wait begun at `since` (ISO 8601): the events kept from it, then the wakes
// without comments and with them, and what the row says it waits on. As JSON, then quit.
static int PrintPRWakes(NSArray<NSString *> *arguments) {
    NSDictionary *activity = arguments.count ? AsRecord(ReadJSON(arguments[0])) : nil;
    double since = arguments.count > 1 ? TimestampMs(arguments[1]) : 0;
    if (!activity || !AsText(activity[@"url"])) {
        fprintf(stderr, "--print-pr-wakes: give gh's answer as a JSON file, with its url, and when the wait began\n");
        return 2;
    }
    NSMutableArray *(^listed)(NSArray<Wake *> *) = ^NSMutableArray *(NSArray<Wake *> *wakes) {
        NSMutableArray *out = [NSMutableArray array];
        for (Wake *wake in wakes)
            [out addObject:@{@"kind": wake.kind, @"says": wake.says, @"facts": wake.facts, @"at": @(wake.at)}];
        return out;
    };
    PRWakes *wakes = [PRWakes new];
    Row *row = [Row new];
    row.sessionId = @"s-sample";
    row.checkout = @{@"pr": @{@"url": activity[@"url"] ?: @"", @"number": activity[@"number"] ?: @0, @"state": @"OPEN"}};
    [wakes watch:row since:since options:@{}];
    [wakes took:activity for:activity[@"url"] ?: @""];
    NSArray *without = listed([wakes wakesFor:row.sessionId]);
    [wakes watch:row since:since options:@{@"comments": @YES}];
    [wakes took:activity for:activity[@"url"] ?: @""];
    NSArray *with = listed([wakes wakesFor:row.sessionId]);
    WaitOn *on = [wakes waitsOn:row];
    Row *closed = [Row new];
    closed.sessionId = @"s-merged";
    NSURL *sibling = [[[NSURL URLWithString:activity[@"url"]] URLByDeletingLastPathComponent]
                      URLByAppendingPathComponent:@"9"];
    closed.checkout = @{@"pr": @{@"url": sibling.absoluteString ?: @"", @"number": @9, @"state": @"MERGED"}};
    return PrintJSON(@{@"events": PRActivityEvents(activity), @"wakes": without, @"wakes with comments": with,
                       @"waits on": @{@"says": on.says ?: NSNull.null, @"spoken": on.spoken ?: NSNull.null,
                                      @"on": on.on ?: NSNull.null, @"cant": on.cant ?: NSNull.null},
                       @"waits on a merged one": [wakes waitsOn:closed] ? @"yes" : @"nothing"});
}

@implementation GitModule

+ (NSString *)moduleName {
    return @"git";
}

+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return @{@"--print-watched": ^(Core *core, NSArray *a) { return PrintWatched(a); },
             @"--print-pr-wakes": ^(Core *core, NSArray *a) { return PrintPRWakes(a); }};
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
    self.prWakes = [PRWakes new];
    self.prWakes.pullRequests = self.pullRequests;
    return self;
}

// A new PR link in a session's record has its state asked at once, rather than with the next check. And each listed
// checkout's changes are told from now on, so git runs only for the ones that changed (CheckoutWatch).
- (void)launch {
    StartCheckoutWatch();
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
            if ([url.scheme isEqualToString:@"https"]) OpenInOtherApp(url);
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

#pragma mark Waking a session that waits

// Its watched pull requests asked of gh once a minute each, as long as a session waits on them.
- (void)tick {
    if (!self.core.printing) [self.prWakes check];
}

- (WaitOn *)waitsOn:(Row *)row {
    return [self.prWakes waitsOn:row];
}

- (BOOL)watch:(Row *)row since:(double)since options:(NSDictionary *)options {
    return [self.prWakes watch:row since:since options:options];
}

- (void)unwatch:(NSString *)sessionId {
    [self.prWakes unwatch:sessionId];
}

- (NSArray<Wake *> *)wakesFor:(NSString *)sessionId {
    return [self.prWakes wakesFor:sessionId];
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
