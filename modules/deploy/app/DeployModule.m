// DeployModule: Deploy's face for the core (Module): the round button's presses, its set-up card and its menu, each
// row's project and folder kept fresh, and the print modes the tests check.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Module.h"
#import "Core.h"
#import "Rows.h"
#import "Row.h"
#import "Printing.h"
#import "Deploys.h"
#import "DeployMenu.h"

// `Whozmove --print-deploys <folder>…`: for each folder, by its name, the command Whozmove suggests for Deploy there
// (null for none) and its last run as the page gets it (when it has one), as JSON, then quit. tests/rows.sh checks
// them against sample projects and runs.
static int PrintDeploys(NSArray<NSString *> *folders) {
    NSMutableDictionary *deploys = [NSMutableDictionary dictionary];
    for (NSString *folder in folders) {
        NSMutableDictionary *state = [@{@"suggested": SuggestDeploy(folder) ?: NSNull.null} mutableCopy];
        if (LastDeployRun(folder)) state[@"run"] = LastDeployRun(folder);
        deploys[folder.lastPathComponent] = state;
    }
    return PrintJSON(deploys);
}

// `Whozmove --print-deploy-checks <folder> <command>…`: what the set-up card would be told about each command in that
// folder (CheckDeploy), by command, as JSON, then quit.
static int PrintDeployChecks(NSArray<NSString *> *arguments) {
    if (!arguments.count) return 2;
    NSMutableDictionary *checks = [NSMutableDictionary dictionary];
    for (NSString *command in [arguments subarrayWithRange:NSMakeRange(1, arguments.count - 1)])
        checks[command] = CheckDeploy(arguments[0], command);
    return PrintJSON(checks);
}

@interface DeployModule : NSObject <Module>
@property (weak) Core *core;
@property (strong) Deploys *deploys;  // made as the app starts: what it reads and runs is the app's alone
@property (strong) DeployMenu *menu;
@end

@implementation DeployModule

+ (NSString *)moduleName {
    return @"deploy";
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    return self;
}

- (void)launch {
    self.deploys = [[Deploys alloc] initWithPage:self.core.page];
    self.menu = [[DeployMenu alloc] initWithCore:self.core deploys:self.deploys];
}

+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return @{
        @"--print-deploys": ^(Core *core, NSArray *a) { return PrintDeploys(a); },
        @"--print-deploy-checks": ^(Core *core, NSArray *a) { return PrintDeployChecks(a); },
    };
}

- (void)pageLoaded {
    [self.deploys resend];
}

- (NSDictionary<NSString *, void (^)(NSDictionary *)> *)messages {
    __weak typeof(self) weakSelf = self;
    Row *(^rowOf)(NSDictionary *) = ^Row *(NSDictionary *msg) { return weakSelf.core.rows.byId[msg[@"sessionId"]]; };
    return @{
        @"deploy": ^(NSDictionary *msg) {
            Row *row = rowOf(msg);
            if (row) [weakSelf.deploys deploy:row];
        },
        @"saveDeployCommand": ^(NSDictionary *msg) {
            Row *row = rowOf(msg);
            if (row) [weakSelf.deploys save:msg[@"command"] forRow:row thenDeploy:[msg[@"deployNow"] boolValue]];
        },
        @"checkDeployCommand": ^(NSDictionary *msg) {
            Row *row = rowOf(msg);
            if (row) [weakSelf.deploys check:msg[@"command"] forRow:row];
        },
        @"stepMenu": ^(NSDictionary *msg) { [weakSelf.menu menu:msg]; },
    };
}

// Each session's work: Deploy's runs and suggestions for its folder are read alongside, and sent when they change.
- (void)rows:(NSArray<Row *> *)rows phase:(RowPhase)phase {
    if (phase == RowPhaseWork) [self.deploys refreshFor:rows];
}

@end
