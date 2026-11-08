// BoardModule: the team board's face for the core (Module): every job of a team that a session leads, by goal, beside
// the list, and Up next, every session working now and what waits. It reads the team module's teams (TeamFacts), never
// the team file itself, and writes nothing. Up next is for anyone whose session leads a team; the rest of the board is
// for people working on Whozmove until anyone can make a team: it shows only while Working on Whozmove ▸ Show Team
// Board is ticked.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import "Module.h"
#import "Core.h"
#import "Page.h"
#import "PanelWindow.h"
#import "Task.h"
#import "Printing.h"
#import "Row.h"
#import "Work.h"

// The Tools card's figures for a team (`team` as TeamFacts gives it): {figure, of, lines, actions}, as the board's own
// Glance has them: what's moving as its figure, and what needs you as a line, each a job under way by where the team
// module says it is (`underWay`), as the page's boardWhere goes by too; a job waiting its turn is neither.
static NSDictionary *BoardCard(NSDictionary *team) {
    if (!team) return nil;
    NSInteger needs = 0, moving = 0;
    for (NSDictionary *job in team[@"jobs"]) {
        if ([job[@"underWay"] isEqual:@"you"]) needs++;
        else if ([job[@"underWay"] isEqual:@"work"]) moving++;
    }
    NSString *you = !needs ? @"Nothing needs you" : needs == 1 ? @"1 needs you"
                  : [NSString stringWithFormat:@"%ld need you", (long)needs];
    return @{@"figure": moving ? [NSString stringWithFormat:@"%ld", (long)moving] : @"Nothing",
             @"of": @"moving",
             @"lines": @[you],
             @"actions": @[@{@"id": @"open", @"title": @"Open Team Board", @"main": @YES}]};
}

// Whether Working on Whozmove ▸ Show Team Board is ticked: off until it's pressed, and kept across launches.
static NSString *const kShowTeamBoard = @"showTeamBoard";
static BOOL BoardShown(void) {
    return [NSUserDefaults.standardUserDefaults boolForKey:kShowTeamBoard];
}

// The teams with a lead, by their project's folder, A to Z, as the team module gives them.
static NSArray<NSDictionary *> *LedTeams(NSArray<NSDictionary *> *teams) {
    return [teams filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *team, id _) {
        return team[@"lead"] != nil;
    }]];
}

@interface BoardModule : NSObject <Module>
@property (weak) Core *core;
// The teams the page was last told, by identity: the team module keeps the same array until the file is read again.
@property (strong) NSArray<NSDictionary *> *told;
// The sessions working now, by id, A to Z, as Work's SessionWorking counts them (the gear counts with it too): what
// Up next lists while the gear isn't known. The page is told again only when they change.
@property (copy) NSArray<NSString *> *working;
@end

@implementation BoardModule

+ (NSString *)moduleName {
    return @"board";
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    return self;
}

- (NSArray<NSDictionary *> *)teams {
    return [[self.core moduleThat:@protocol(TeamFacts)] teams] ?: @[];
}

- (NSArray<NSDictionary *> *)led {
    return LedTeams(self.teams);
}

// The page is told the teams and the kinds' words whenever the file has been read again, whether the rest of the
// board shows, and the sessions working now: Up next, the board, and what opens them on a chief's title line, draw from
// them. With Show Team Board off only Up next shows.
- (void)tell {
    self.told = self.teams;
    NSMutableArray *kinds = [NSMutableArray array];
    for (NSString *kind in TaskKinds) [kinds addObject:@{@"kind": kind, @"word": TaskKindWords[kind]}];
    [self.core.page call:@"setBoard" with:@[self.told, kinds, @(BoardShown()), self.working ?: @[]]];
}

// Who's working, once the rows are whole: busy and not asking you, compacting, at work in a copy, or with agents in the
// background, by the one rule the gear counts with, so Up next and the gear never disagree on who's at work.
- (void)rows:(NSArray<Row *> *)rows phase:(RowPhase)phase {
    if (phase != RowPhaseListed) return;
    NSMutableArray<NSString *> *working = [NSMutableArray array];
    for (Row *row in rows)
        if (row.sessionId && SessionWorking(row)) [working addObject:row.sessionId];
    [working sortUsingSelector:@selector(compare:)];
    if ([working isEqualToArray:self.working ?: @[]]) return;
    self.working = working;
    [self tell];
}

- (void)pageLoaded {
    [self tell];
}

- (void)tick {
    if (self.teams != self.told) [self tell];
}

// Team Board, among the tools on the panel's back while a session leads a team: how many of its jobs are moving and
// how many need you, and a button that opens the board on the first team, A to Z.
- (NSArray<AppEntry *> *)appEntries {
    __weak typeof(self) weakSelf = self;
    AppEntry *board = [AppEntry appWithId:@"board" name:@"Team Board"
                                     does:@"Shows the work of a team a session leads: what's moving, who's on what, "
                                           @"its goals and what's done."
                                    order:210];
    board.tool = YES;
    board.present = ^BOOL { return BoardShown() && weakSelf.led.count > 0; };
    board.card = ^NSDictionary * { return BoardCard(weakSelf.led.firstObject); };
    board.act = ^(NSString *action) {
        NSString *project = weakSelf.led.firstObject[@"project"];
        if (![action isEqualToString:@"open"] || !project) return;
        [weakSelf.core.window turnOver:NO then:^{ [weakSelf.core.page call:@"openBoard" with:@[project]]; }];
    };
    return @[board];
}

// Working on Whozmove ▸ Show Team Board: ticked while the board shows, and a press tells the page at once.
- (NSArray<MenuEntry *> *)menuEntries {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Show Team Board" action:@selector(toggleShown)
                                           keyEquivalent:@""];
    item.target = self;
    MenuEntry *entry = [MenuEntry entryIn:MenuSectionWhozmove order:40 item:item];
    entry.willOpen = ^{ item.state = BoardShown() ? NSControlStateValueOn : NSControlStateValueOff; };
    return @[entry];
}

- (void)toggleShown {
    [NSUserDefaults.standardUserDefaults setBool:!BoardShown() forKey:kShowTeamBoard];
    [self tell];
}

// The print run shows the Tools card whatever the switch says, so the tests check it on any Mac.
+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return @{
        // The Tools card for the team with a lead in the project named (the first, A to Z, without one), once the rows
        // have been read for the home folder in $HOME.
        @"--print-board-card": ^int(Core *core, NSArray<NSString *> *arguments) {
            SettledRows(core);
            NSArray *led = LedTeams([[core moduleThat:@protocol(TeamFacts)] teams] ?: @[]);
            NSDictionary *team = led.firstObject;
            for (NSDictionary *each in led)
                if (arguments.count && [each[@"project"] isEqual:arguments[0]]) team = each;
            return PrintJSON(BoardCard(team) ?: NSNull.null);
        },
    };
}

@end
