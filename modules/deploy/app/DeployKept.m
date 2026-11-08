// DeployKept: a press of Deploy kept while an agent works in its checkout, in memory only, one per folder, and running
// it once that's done.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "DeployKept.h"
#import "Deploys.h"
#import "Core.h"
#import "MenuBar.h"
#import "Row.h"
#import "Log.h"

@interface DeployKept ()
@property (weak) Core *core;
@property (strong) Deploys *deploys;
// The presses kept, by folder, on the main thread.
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *kept;
@property (readwrite, copy) NSDictionary<NSString *, NSString *> *decided;
@end

@implementation DeployKept

- (instancetype)initWithCore:(Core *)core deploys:(Deploys *)deploys {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.deploys = deploys;
    self.kept = [NSMutableDictionary dictionary];
    self.decided = @{};
    return self;
}

- (BOOL)keep:(Row *)row {
    NSString *folder = DeployFolder(row), *command = [self.deploys commandFor:row];
    if (!folder || !command || !row.sessionId) return NO;
    self.kept[folder] = @{@"sessionId": row.sessionId, @"command": command,
                          @"at": @(floor(NSDate.date.timeIntervalSince1970 * 1000))};
    PanelLog(@"deploy in %@: kept until %@", folder, [self.deploys whyNotNow:row] ?: @"it can run");
    [self tick];
    return YES;
}

- (void)tick {
    if (!self.kept.count) {
        [self.deploys showKept:@{}];
        return;
    }
    NSMutableDictionary<NSString *, NSString *> *decided = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSDictionary *> *shown = [NSMutableDictionary dictionary];
    BOOL hidden = !self.core.printing && !(self.core.menuBar.showsDeploy && self.core.menuBar.showsNextSteps);
    for (NSString *folder in self.kept.allKeys) {
        NSDictionary *press = self.kept[folder], *run = [self.deploys runIn:folder];
        Row *row = [self.deploys listedRow:press[@"sessionId"]];
        // The row as it's listed now, its project's command as it's saved now: a press is for what you confirmed.
        NSString *gone = [run[@"startedAt"] doubleValue] > [press[@"at"] doubleValue] ? @"a deploy ran there since"
            : !row ? @"its session isn't listed any more"
            : ![NSFileManager.defaultManager fileExistsAtPath:folder] ? @"its checkout isn't there any more"
            : ![DeployFolder(row) isEqual:folder] ? @"its session isn't in that checkout now"
            : ![[self.deploys commandFor:row] isEqual:press[@"command"]] ? @"the project's Deploy command changed"
            : hidden ? @"Deploy is hidden" : nil;
        if (gone) {
            PanelLog(@"deploy in %@: the press kept there dropped, as %@", folder, gone);
            decided[folder] = [@"dropped, as " stringByAppendingString:gone];
            [self.kept removeObjectForKey:folder];
            continue;
        }
        NSString *wait = [self.deploys whyNotNow:row];
        if (wait) {
            shown[folder] = @{@"sessionId": press[@"sessionId"]};
            decided[folder] = wait;
            continue;
        }
        [self.kept removeObjectForKey:folder];
        decided[folder] = @"would run now";
        PanelLog(@"deploy in %@: the press kept there runs, as nothing holds it up now", folder);
        [self.deploys deploy:row];
    }
    self.decided = decided;
    [self.deploys showKept:shown];
}

- (NSDictionary *)keptIn:(NSString *)folder {
    return folder ? self.kept[folder] : nil;
}

- (void)dropIn:(NSString *)folder {
    if (!folder || !self.kept[folder]) return;
    PanelLog(@"deploy in %@: the press kept there dropped, Don't Deploy", folder);
    [self.kept removeObjectForKey:folder];
    [self tick];
}

@end
