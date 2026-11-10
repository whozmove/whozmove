// TeamModule: the team's face for the core (Module): each row's place in the team the session leading it keeps, which
// the page can group the list by.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import "Module.h"
#import "Core.h"
#import "Row.h"
#import "Team.h"
#import "Printing.h"

// Whether Working on Whozmove ▸ Show Teams is ticked: off until it's pressed, and kept across launches, under the name
// it has always had. Every team surface comes from the file it lets be read, and teams are for people working on
// Whozmove until anyone can make one, so the file isn't read at all while it's off.
static NSString *const kShowTeams = @"readTeamFiles";
static BOOL ShowTeams(void) {
    return [NSUserDefaults.standardUserDefaults boolForKey:kShowTeams];
}

@interface TeamModule : NSObject <Module, TeamFacts>
@property (weak) Core *core;
@property (strong) Team *team;
// Set by the print run for the off state (`--switch-off`), so the tests never depend on this Mac's own settings.
@property (assign) BOOL printSwitchedOff;
@end

@implementation TeamModule

+ (NSString *)moduleName {
    return @"team";
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.team = [Team new];
    return self;
}

// Who each session is in the team, read again whenever the file changes, and who holds each member's seat now.
- (void)rows:(NSArray<Row *> *)rows phase:(RowPhase)phase {
    if (phase != RowPhaseWork) return;
    if (![self reading]) {
        for (Row *row in rows) row.team = nil;
        return;
    }
    [self.team refresh];
    NSArray *places = [self.team placesOf:rows];
    for (NSUInteger i = 0; i < rows.count; i++) {
        Row *row = rows[i];
        row.team = places[i] == NSNull.null ? nil : places[i];
    }
}

// Whether the file is read: while Show Teams is ticked, and in a print run whatever it says, unless the run asks for
// the off state.
- (BOOL)reading {
    return self.core.printing ? !self.printSwitchedOff : ShowTeams();
}

// Whether teams show now, for the modules that offer something only a team needs (TeamFacts).
- (BOOL)teamsShown {
    return [self reading];
}

- (BOOL)working {
    return [self reading] && self.team.working;
}

// Each team as a whole, for the team board (TeamFacts): none while the file isn't read.
- (NSArray<NSDictionary *> *)teams {
    return [self reading] ? self.team.teams : @[];
}

// Working on Whozmove ▸ Show Teams: ticked while the team file is read. A press takes effect with the next pass
// over the rows, which is every second.
- (NSArray<MenuEntry *> *)menuEntries {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Show Teams" action:@selector(toggleReading)
                                           keyEquivalent:@""];
    item.target = self;
    MenuEntry *entry = [MenuEntry entryIn:MenuSectionWhozmove order:35 item:item];
    entry.willOpen = ^{ item.state = ShowTeams() ? NSControlStateValueOn : NSControlStateValueOff; };
    return @[entry];
}

- (void)toggleReading {
    [NSUserDefaults.standardUserDefaults setBool:!ShowTeams() forKey:kShowTeams];
}

+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return @{
        // Each team as a whole, as the board gets it, once the file has been read for the rows; with `--switch-off`,
        // what there is while Show Teams is off.
        @"--print-teams": ^int(Core *core, NSArray<NSString *> *arguments) {
            TeamModule *module = (TeamModule *)[core moduleThat:@protocol(TeamFacts)];
            BOOL off = [arguments containsObject:@"--switch-off"];
            module.printSwitchedOff = off;
            NSArray<Row *> *rows = SettledRows(core);
            if (!off) return PrintJSON(module.teams ?: @[]);
            // Off: the teams and the rows that have a team, neither of which there should be.
            NSMutableArray *withTeam = [NSMutableArray array];
            for (Row *row in rows)
                if (row.team) [withTeam addObject:row.sessionId ?: @""];
            return PrintJSON(@{@"teams": module.teams ?: @[], @"rowsWithATeam": withTeam});
        },
        // Who holds a member's seat in its workspace (SeatOf), for sample cases.
        @"--print-seats": ^int(Core *core, NSArray<NSString *> *arguments) { return PrintSeats(arguments); },
    };
}

@end
