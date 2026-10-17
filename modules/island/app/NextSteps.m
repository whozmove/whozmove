// NextSteps: the menus behind a row's island, one per stage: what the stage holds, and the ways to take its next step;
// and the commits stage's card.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "NextSteps.h"
#import "Core.h"
#import "Rows.h"
#import "Send.h"
#import "Stages.h"
#import "Work.h"
#import "Checkouts.h"
#import "Page.h"
#import "PanelWindow.h"
#import "Files.h"
#import "Menus.h"
#import "Row.h"

// What a step on a row's island asks the session's agent, by step, in the words you'd type. The page names only the
// step: these, and the words an extra stage you've allowed gives its own actions, are the only words that go in this
// way.
static NSString *StepRequest(NSString *step) {
    if (![step isKindOfClass:NSString.class]) return nil;
    return @{@"commit": @"Commit the changes.",
             @"commitPush": @"Commit the changes and push them.",
             @"commitPR": @"Commit the changes, push the branch and open a pull request.",
             @"push": @"Push the commits.",
             @"pr": @"Push this branch and open a pull request.",
             @"draftPR": @"Push this branch and open a draft pull request."}[step];
}

@interface NextSteps ()
@property (weak) Core *core;
@property (strong) Stages *stages;
@property (strong) Checkouts *checkouts;
// The commits stage's card last sent for each row, [step, card], so one asked for again is sent only when it changes.
@property (strong) NSMutableDictionary<NSString *, NSArray *> *cardsSent;
@end

@implementation NextSteps

- (instancetype)initWithCore:(Core *)core stages:(Stages *)stages checkouts:(Checkouts *)checkouts {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.stages = stages;
    self.checkouts = checkouts;
    self.cardsSent = [NSMutableDictionary dictionary];
    return self;
}

// What a menu is about, at its top: a section header where macOS has them.
static void Heading(NSMenu *menu, NSString *text) {
    if (@available(macOS 14.0, *)) [menu addItem:[NSMenuItem sectionHeaderWithTitle:text]];
    else SayInMenu(menu, text);
}

// What a stage holds, a line each, the first 10; and how many more there are.
static void List(NSMenu *menu, NSArray *lines, NSInteger more) {
    for (id line in lines)
        if ([line isKindOfClass:NSString.class]) SayInMenu(menu, Clip(line, 60));
    if (more > 0) SayInMenu(menu, [NSString stringWithFormat:@"and %ld more", (long)more]);
}

static NSString *Count(NSInteger n, NSString *one, NSString *many) {
    return [NSString stringWithFormat:@"%ld %@", (long)n, n == 1 ? one : many];
}

// Why the island's steps wait, or nil: anything that asks the agent or acts on its files waits while it works, asks
// something or compacts, or another agent does in the same folder (WhyStepsWait). Its menus still open, to show what
// each stage holds, with the steps there but not to be picked, and why.
- (NSString *)whyNotNow:(Row *)row {
    return WhyStepsWait(row, self.core.rows.byId.allValues, @"These wait");
}

// Whether a step picked from a menu waits for another agent that has started work in the row's folder since the menu
// opened: the row says so. The row's own agent is seen to by what the step does (Send's ask:, Stages' run:).
- (BOOL)othersAtWork:(Row *)row {
    NSArray<Row *> *rows = self.core.rows.byId.allValues;
    if (!OthersAtWork(row, rows).count) return NO;
    NSBeep();
    [self.core.page stepNote:row.sessionId text:WhyStepsWait(row, rows, @"This waits")];
    return YES;
}

// A stage on a row's island: what it holds, then what can be done with it. {stage, step, count, pr, sessionId, x, y}:
// files (changed files), extra (the checkout's extra stage, Stages), commits (not on GitHub yet), github (the branch's
// pull request, or none yet). The lists come from the checkout's last read (Checkouts), so the menu opens at once.
- (void)stageMenu:(NSDictionary *)msg {
    Row *row = self.core.rows.byId[msg[@"sessionId"]];
    NSString *root = (row.workGit ?: row.git)[@"root"];
    if (!row || !root) return;
    NSDictionary *details = [self.checkouts detailsOf:root], *extra = details[@"menu"];
    NSString *stage = msg[@"stage"], *step = msg[@"step"], *wait = [self whyNotNow:row];
    NSInteger count = [msg[@"count"] integerValue];
    NSMenu *menu = [NSMenu new];
    menu.autoenablesItems = NO;
    if ([stage isEqual:@"files"]) {
        Heading(menu, [Count(count, @"file", @"files") stringByAppendingString:@" changed"]);
        // When the extra stage counts the files itself (some are in it), git's list would say otherwise, unless it
        // names the ones it counts, which are then what's listed (SplitNamed in Checkouts.m); an empty stage holds
        // none of them, so git's list is right then.
        NSDictionary *inStage = row.checkout[@"stage"];
        BOOL named = inStage[@"parts"] != nil;
        if (named || !inStage[@"edits"] || ![inStage[@"count"] integerValue]) {
            NSMutableArray *files = [NSMutableArray arrayWithArray:details[@"files"] ?: @[]];
            for (NSString *path in details[@"newPaths"] ?: @[]) [files addObject:[path stringByAppendingString:@" (new)"]];
            NSInteger all = named ? [inStage[@"edits"] integerValue]
                                  : [row.checkout[@"changes"] integerValue] + [row.checkout[@"newFiles"] integerValue];
            List(menu, [files subarrayWithRange:NSMakeRange(0, MIN(files.count, (NSUInteger)10))],
                 all - (NSInteger)MIN(files.count, (NSUInteger)10));
        }
        // Its steps only while there are files to take them with: an empty stage's dot opens to say so.
        if (count > 0) {
            [menu addItem:NSMenuItem.separatorItem];
            [self addActions:extra[@"actions"] forFiles:YES to:menu row:row enabled:!wait];
            [self addWaysTo:menu step:@"commit" row:row enabled:!wait];
        }
        if (details[@"declined"]) {
            [menu addItem:NSMenuItem.separatorItem];
            [self add:@"Ask About the Extra Stage Again" to:menu action:@selector(askAgain:) row:row];
        }
    } else if ([stage isEqual:@"extra"]) {
        Heading(menu, extra[@"header"] ?: Count(count, row.checkout[@"stage"][@"label"] ?: @"pending",
                                               row.checkout[@"stage"][@"label"] ?: @"pending"));
        List(menu, extra[@"items"], [extra[@"more"] integerValue]);
        NSString *running = [self.stages runningIn:root];
        if (running) SayInMenu(menu, [@"Running: " stringByAppendingString:running]);
        if ([extra[@"actions"] count]) [menu addItem:NSMenuItem.separatorItem];
        [self addActions:extra[@"actions"] forFiles:NO to:menu row:row enabled:!wait && !running];
        [menu addItem:NSMenuItem.separatorItem];
        [self add:@"Stop This Stage" to:menu action:@selector(stopStage:) row:row];
    } else if ([stage isEqual:@"commits"]) {
        Heading(menu, [Count(count, @"commit", @"commits") stringByAppendingString:@" not on GitHub yet"]);
        List(menu, details[@"commits"], count - (NSInteger)[details[@"commits"] count]);
        if (count > 0) {
            [menu addItem:NSMenuItem.separatorItem];
            [self addWaysTo:menu step:step row:row enabled:!wait];
        }
    } else if ([stage isEqual:@"github"]) {
        NSString *url = [self urlOfPR:msg[@"pr"] row:row];
        if (url) {
            NSMenuItem *open = [self add:[NSString stringWithFormat:@"Open PR #%@", msg[@"pr"]] to:menu
                                  action:@selector(openPR:) row:row];
            open.representedObject = url;
        } else if ([step isEqual:@"pr"]) {
            Heading(menu, @"Pushed, with no pull request yet");
            [self addWaysTo:menu step:step row:row enabled:!wait];
        } else {
            SayInMenu(menu, @"Nothing on GitHub yet");
        }
    }
    if (wait) {
        [menu addItem:NSMenuItem.separatorItem];
        SayInMenu(menu, wait);
    }
    [self.core.window popUpMenu:menu atPagePoint:NSMakePoint([msg[@"x"] doubleValue], [msg[@"y"] doubleValue])];
}

// The pull request numbered `number` for this row's branch: its own, or one the session raised. https only.
- (NSString *)urlOfPR:(id)number row:(Row *)row {
    NSMutableArray *prs = [NSMutableArray arrayWithArray:row.prs ?: @[]];
    if ([row.checkout[@"pr"] isKindOfClass:NSDictionary.class]) [prs insertObject:row.checkout[@"pr"] atIndex:0];
    for (NSDictionary *pr in prs) {
        if (![pr isKindOfClass:NSDictionary.class] || ![pr[@"number"] isEqual:number]) continue;
        NSURL *url = [NSURL URLWithString:pr[@"url"]];
        if ([url.scheme isEqualToString:@"https"]) return pr[@"url"];
    }
    return nil;
}

- (void)openPR:(NSMenuItem *)item {
    NSURL *url = [NSURL URLWithString:item.representedObject];
    if ([url.scheme isEqualToString:@"https"]) [NSWorkspace.sharedWorkspace openURL:url];
}

// The extra stage's own ways, each either a command it runs or words it asks the agent, with that as its tooltip:
// those for the files stage (in: "edits"), or the rest, for its own.
- (void)addActions:(NSArray *)actions forFiles:(BOOL)forFiles to:(NSMenu *)menu row:(Row *)row enabled:(BOOL)enabled {
    for (NSDictionary *action in [actions isKindOfClass:NSArray.class] ? actions : @[]) {
        if ([action[@"in"] isEqual:@"edits"] != forFiles) continue;
        BOOL runs = action[@"run"] != nil;
        NSMenuItem *item = [menu addItemWithTitle:action[@"title"]
                                           action:runs ? @selector(runAction:) : @selector(askAction:)
                                    keyEquivalent:@""];
        item.target = self;
        item.enabled = enabled;
        item.representedObject = @{@"sessionId": row.sessionId ?: @"", @"action": action};
        item.toolTip = runs ? [@"Runs: " stringByAppendingString:action[@"run"]]
                            : [NSString stringWithFormat:@"Asks the agent: “%@”", action[@"ask"]];
    }
}

- (void)runAction:(NSMenuItem *)item {
    Row *row = self.core.rows.byId[item.representedObject[@"sessionId"]];
    if (row && ![self othersAtWork:row]) [self.stages run:item.representedObject[@"action"] row:row];
}

- (void)askAction:(NSMenuItem *)item {
    Row *row = self.core.rows.byId[item.representedObject[@"sessionId"]];
    if (row && ![self othersAtWork:row]) [self.core.send ask:item.representedObject[@"action"][@"ask"] row:row];
}

- (void)stopStage:(NSMenuItem *)item {
    Row *row = self.core.rows.byId[item.representedObject];
    if (row) [self.stages stop:row];
}

- (void)askAgain:(NSMenuItem *)item {
    Row *row = self.core.rows.byId[item.representedObject];
    if (row) [self.stages askAgain:row];
}

- (NSMenuItem *)add:(NSString *)title to:(NSMenu *)menu action:(SEL)action row:(Row *)row {
    NSMenuItem *item = [menu addItemWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
    item.representedObject = row.sessionId;
    return item;
}

// The ways to take a step, [step, title], as its menu offers them for this row: the commit ways that push only with a
// remote to push to.
- (NSArray<NSArray<NSString *> *> *)waysFor:(NSString *)step row:(Row *)row {
    NSArray<NSArray<NSString *> *> *ways =
        [step isEqual:@"commit"] ? @[@[@"commit", @"Commit"], @[@"commitPush", @"Commit and Push"],
                                     @[@"commitPR", @"Commit and Open a Pull Request"]]
      : [step isEqual:@"pr"] ? @[@[@"pr", @"Create PR"], @[@"draftPR", @"Create Draft PR"]]
      : [step isEqual:@"push"] ? @[@[@"push", @"Push"]] : @[];
    BOOL remote = [row.checkout[@"remotes"] integerValue] > 0;
    NSMutableArray *offered = [NSMutableArray array];
    for (NSArray<NSString *> *way in ways)
        if (![way[0] hasPrefix:@"commit"] || [way[0] isEqual:@"commit"] || remote) [offered addObject:way];
    return offered;
}

// The ways to take a step that asks the agent, the step's own first, each with the words it sends as its tooltip.
- (void)addWaysTo:(NSMenu *)menu step:(NSString *)step row:(Row *)row enabled:(BOOL)enabled {
    for (NSArray<NSString *> *way in [self waysFor:step row:row]) {
        NSMenuItem *item = [menu addItemWithTitle:way[1] action:@selector(ask:) keyEquivalent:@""];
        item.target = self;
        item.enabled = enabled;
        item.representedObject = @{@"sessionId": row.sessionId ?: @"", @"step": way[0]};
        item.toolTip = [NSString stringWithFormat:@"Asks the agent: “%@”", StepRequest(way[0])];
    }
}

- (void)stageCard:(NSDictionary *)msg {
    Row *row = self.core.rows.byId[msg[@"sessionId"]];
    NSString *root = (row.workGit ?: row.git)[@"root"];
    if (!row || !root || ![msg[@"stage"] isEqual:@"commits"]) return;
    NSDictionary *details = [self.checkouts detailsOf:root];
    NSString *wait = [self whyNotNow:row];
    NSInteger count = [msg[@"count"] integerValue];
    NSArray *items = [details[@"commits"] isKindOfClass:NSArray.class] ? details[@"commits"] : @[];
    NSMutableArray *steps = [NSMutableArray array];
    if (count > 0)
        for (NSArray<NSString *> *way in [self waysFor:msg[@"step"] row:row])
            [steps addObject:@{@"step": way[0], @"title": way[1],
                               @"tip": [NSString stringWithFormat:@"Asks the agent: “%@”", StepRequest(way[0])]}];
    NSDictionary *card = @{
        @"heading": [Count(count, @"commit", @"commits") stringByAppendingString:@" not on GitHub yet"],
        @"items": items, @"more": @(MAX(0, count - (NSInteger)items.count)), @"steps": steps,
        @"enabled": @(!wait), @"wait": wait ?: @""};
    NSString *step = [msg[@"step"] isKindOfClass:NSString.class] ? msg[@"step"] : @"";
    // Asked again with every update, so the page has it ready (`quiet`): sent only when it has changed.
    NSArray *said = @[step, card];
    if ([msg[@"quiet"] boolValue] && [self.cardsSent[row.sessionId] isEqual:said]) return;
    self.cardsSent[row.sessionId] = said;
    [self.core.page call:@"showStageCard" with:@[row.sessionId ?: @"", card, step]];
}

- (void)takeStep:(NSDictionary *)msg {
    Row *row = self.core.rows.byId[msg[@"sessionId"]];
    if (!row || [self whyNotNow:row]) return;
    for (NSArray<NSString *> *way in [self waysFor:msg[@"from"] row:row]) {
        if (![way[0] isEqual:msg[@"step"]]) continue;
        NSString *words = StepRequest(way[0]);
        if (words && ![self othersAtWork:row]) [self.core.send ask:words row:row];
        return;
    }
}

// A step that asks the agent, in its fixed words (StepRequest): the page only ever names the step.
- (void)ask:(NSMenuItem *)item {
    Row *row = self.core.rows.byId[item.representedObject[@"sessionId"]];
    NSString *words = StepRequest(item.representedObject[@"step"]);
    if (row && words && ![self othersAtWork:row]) [self.core.send ask:words row:row];
}

@end
