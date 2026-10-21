// NextSteps: the steps a row's checkout has to take, as git sees it (Commit and its ways, Push, Publish, Create PR into
// the branch you pick), each asked of the session's agent in fixed words; and the branches GitHub's copy has, for
// Create PR's card.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "NextSteps.h"
#import "Core.h"
#import "Rows.h"
#import "Send.h"
#import "Work.h"
#import "Page.h"
#import "PanelWindow.h"
#import "Git.h"
#import "Menus.h"
#import "Row.h"

// What a step asks the session's agent, by step, in the words you'd type. The page names only the step: these are the
// only words that go in this way, with one of the repo's own branch names in a pull request's (wordsFor:into:row:). A
// commit takes only what's staged when something is, as git's own does.
static NSString *StepRequest(NSString *step) {
    if (![step isKindOfClass:NSString.class]) return nil;
    return @{@"commit": @"Commit the changes.",
             @"commitPush": @"Commit the changes and push them.",
             @"commitPR": @"Commit the changes, push the branch and open a pull request.",
             @"commitStaged": @"Commit the staged changes.",
             @"commitPushStaged": @"Commit the staged changes and push them.",
             @"commitPRStaged": @"Commit the staged changes, push the branch and open a pull request.",
             @"push": @"Push the commits.",
             @"publish": @"Publish this branch: push it to GitHub.",
             @"pr": @"Push this branch and open a pull request.",
             @"draftPR": @"Push this branch and open a draft pull request.",
             @"prInto": @"Push this branch and open a pull request into %@.",
             @"draftPRInto": @"Push this branch and open a draft pull request into %@."}[step];
}

@interface NextSteps ()
@property (weak) Core *core;
// Each checkout's branches on GitHub as last read for Create PR's card, by root: what a pull request may go into.
@property (strong) NSMutableDictionary<NSString *, NSArray<NSString *> *> *branches;
@end

@implementation NextSteps

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.branches = [NSMutableDictionary dictionary];
    return self;
}

// Why the steps wait, or nil: anything that asks the agent or acts on its files waits while it works, asks something or
// compacts, or another agent does in the same folder (WhyStepsWait).
- (NSString *)whyNotNow:(Row *)row what:(NSString *)what {
    return WhyStepsWait(row, self.core.rows.byId.allValues, what);
}

// Whether a step waits for another agent that has started work in the row's folder: the row says so. The row's own
// agent is seen to by what the step does (Send's ask:).
- (BOOL)othersAtWork:(Row *)row {
    NSArray<Row *> *rows = self.core.rows.byId.allValues;
    if (!OthersAtWork(row, rows).count) return NO;
    NSBeep();
    [self.core.page stepNote:row.sessionId text:WhyStepsWait(row, rows, @"This waits")];
    return YES;
}

// The ways to commit, [step, title], as their menu offers them for this row: the ones that push only with a remote to
// push to.
- (NSArray<NSArray<NSString *> *> *)commitWays:(Row *)row {
    BOOL remote = [row.checkout[@"remotes"] integerValue] > 0;
    NSMutableArray *ways = [NSMutableArray arrayWithObject:@[@"commit", @"Commit"]];
    if (remote) [ways addObjectsFromArray:@[@[@"commitPush", @"Commit and Push"],
                                            @[@"commitPR", @"Commit and Open a Pull Request"]]];
    return ways;
}

// The words a step asks in, for this row's checkout as it stands: a commit's take only what's staged when something is;
// a pull request's name the branch it goes into, when one is given.
- (NSString *)wordsFor:(NSString *)step into:(NSString *)into row:(Row *)row {
    NSDictionary *c = row.checkout;
    BOOL staged = [c[@"filesStaged"] integerValue] + [c[@"filesPartly"] integerValue] > 0;
    if (staged && [@[@"commit", @"commitPush", @"commitPR"] containsObject:step])
        return StepRequest([step stringByAppendingString:@"Staged"]);
    if (into.length && ([step isEqual:@"pr"] || [step isEqual:@"draftPR"]))
        return [NSString stringWithFormat:StepRequest([step stringByAppendingString:@"Into"]), into];
    return StepRequest(step);
}

// Whether a step can be taken in the row's checkout as it last read: a commit while something isn't committed (one that
// pushes only with a remote); Push while the branch is ahead of its upstream; Publish while a branch never pushed has
// commits, with a remote to push to; a pull request once a branch other than the base is pushed with nothing waiting,
// and has none open.
- (BOOL)offers:(NSString *)step row:(Row *)row {
    NSDictionary *c = row.checkout;
    BOOL remote = [c[@"remotes"] integerValue] > 0, upstream = [c[@"upstream"] boolValue];
    if ([step isEqual:@"commit"]) return [c[@"changes"] integerValue] + [c[@"newFiles"] integerValue] > 0;
    if ([step isEqual:@"commitPush"] || [step isEqual:@"commitPR"]) return remote && [self offers:@"commit" row:row];
    if ([step isEqual:@"push"]) return remote && upstream && [c[@"ahead"] integerValue] > 0;
    if ([step isEqual:@"publish"]) return remote && !upstream && [c[@"aheadOfBase"] integerValue] > 0;
    if ([step isEqual:@"pr"] || [step isEqual:@"draftPR"]) {
        NSString *branch = (row.workGit ?: row.git)[@"branch"];
        NSDictionary *pr = [c[@"pr"] isKindOfClass:NSDictionary.class] ? c[@"pr"] : nil;
        return remote && upstream && branch && ![branch isEqual:c[@"base"]] && [c[@"ahead"] integerValue] == 0
            && [c[@"aheadOfBase"] integerValue] > 0 && ![pr[@"state"] isEqual:@"OPEN"];
    }
    return NO;
}

- (void)takeStep:(NSDictionary *)msg {
    Row *row = self.core.rows.byId[msg[@"sessionId"]];
    NSString *step = msg[@"step"];
    if (!row || ![step isKindOfClass:NSString.class] || ![self offers:step row:row]) return;
    // A pull request goes into the repo's default branch, or one of its branches on GitHub as last read for the card:
    // never a name the page made up.
    NSString *root = (row.workGit ?: row.git)[@"root"], *into = nil;
    if ([step isEqual:@"pr"] || [step isEqual:@"draftPR"]) {
        into = [msg[@"into"] isKindOfClass:NSString.class] ? msg[@"into"] : row.checkout[@"base"];
        if (into && ![into isEqual:row.checkout[@"base"]] && ![self.branches[root ?: @""] containsObject:into]) return;
    }
    NSString *wait = [self whyNotNow:row what:@"This waits"];
    if (wait) {
        NSBeep();
        [self.core.page stepNote:row.sessionId text:wait];
        return;
    }
    NSString *words = [self wordsFor:step into:into row:row];
    if (words && ![self othersAtWork:row]) [self.core.send ask:words row:row];
}

- (void)commitMenu:(NSDictionary *)msg {
    Row *row = self.core.rows.byId[msg[@"sessionId"]];
    if (!row || ![self offers:@"commit" row:row]) return;
    NSString *wait = [self whyNotNow:row what:@"These wait"];
    NSMenu *menu = [NSMenu new];
    menu.autoenablesItems = NO;
    for (NSArray<NSString *> *way in [self commitWays:row]) {
        NSMenuItem *item = [menu addItemWithTitle:way[1] action:@selector(ask:) keyEquivalent:@""];
        item.target = self;
        item.enabled = !wait;
        item.representedObject = @{@"sessionId": row.sessionId ?: @"", @"step": way[0]};
        item.toolTip = [NSString stringWithFormat:@"Asks the agent: “%@”", [self wordsFor:way[0] into:nil row:row]];
    }
    if (wait) {
        [menu addItem:NSMenuItem.separatorItem];
        SayInMenu(menu, wait);
    }
    [self.core.window popUpMenu:menu atPagePoint:NSMakePoint([msg[@"x"] doubleValue], [msg[@"y"] doubleValue])];
}

// A way to commit picked from its menu, in its fixed words.
- (void)ask:(NSMenuItem *)item {
    Row *row = self.core.rows.byId[item.representedObject[@"sessionId"]];
    NSString *words = row ? [self wordsFor:item.representedObject[@"step"] into:nil row:row] : nil;
    if (row && words && ![self othersAtWork:row]) [self.core.send ask:words row:row];
}

- (void)branchesFor:(NSDictionary *)msg {
    Row *row = self.core.rows.byId[msg[@"sessionId"]];
    NSString *root = (row.workGit ?: row.git)[@"root"], *sid = row.sessionId, *base = row.checkout[@"base"];
    if (!root || !sid) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSArray<NSString *> *names = RemoteBranches(root) ?: @[];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.branches[root] = names;
            [self.core.page call:@"setPRBranches" with:@[sid, @{@"base": base ?: NSNull.null, @"branches": names}]];
        });
    });
}

@end
