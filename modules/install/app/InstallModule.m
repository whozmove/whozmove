// InstallModule: the install module's face for the core (contracts/Module.h): Whozmove setting itself up as it opens
// (Install), looked at again while it waits, and its print mode.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Module.h"
#import "Agent.h"
#import "Core.h"
#import "Builds.h"
#import "Processes.h"
#import "Install.h"

@interface InstallModule : NSObject <Module>
@property (weak) Core *core;
@property (strong) Install *install;
@end

@implementation InstallModule

+ (NSString *)moduleName {
    return @"install";
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    return self;
}

// Made here, not in setting up, as a print run never sets itself up: the agent is found once every module is made.
- (void)launch {
    id<AgentInstall> agent = [self.core agentsThat:@protocol(AgentInstall)].firstObject;
    NSString *hooks = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"plugin"];
    self.install = [[Install alloc] initWithApp:NSBundle.mainBundle.bundlePath builtByAgent:BuiltByAgent()
        agentHere:^BOOL { return agent.onThisMac; }
        tools:^BOOL { return DeveloperToolsReady(); }
        connect:^NSDictionary *(NSString *answer, BOOL before, NSString *from) {
            return [agent connect:answer before:before from:from];
        }
        hooks:hooks];
    [self.install check:nil];
}

- (void)tick {
    [self.install tick];
}

+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return @{@"--print-install": ^(Core *core, NSArray<NSString *> *arguments) { return PrintInstall(arguments); }};
}

@end
