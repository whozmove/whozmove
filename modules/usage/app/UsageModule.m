// UsageModule: the usage strip's face for the core (Module): your plan's usage asked of the agent when a check is due,
// the strip's Sign in, and Working on Whozmove's Preview the Wait.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import "Module.h"
#import "Core.h"
#import "Page.h"
#import "Usage.h"

@interface UsageModule : NSObject <Module>
@property (weak) Core *core;
@property (strong) Usage *usage;  // made as the app starts: it watches the screens sleep and wake
@end

@implementation UsageModule

+ (NSString *)moduleName {
    return @"usage";
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    return self;
}

- (void)launch {
    self.usage = [[Usage alloc] initWithPage:self.core.page window:self.core.window
                                       agent:[self.core agentsThat:@protocol(AgentUsage)].firstObject];
}

// The time is compared on every tick, so a Mac that slept through a check asks as it wakes.
- (void)tick {
    [self.usage pollIfDue];
}

- (void)pageLoaded {
    [self.usage resend];
}

- (NSDictionary<NSString *, void (^)(NSDictionary *)> *)messages {
    __weak typeof(self) weakSelf = self;
    return @{
        // In the first terminal on this Mac that runs a command in a new tab: Ghostty, else macOS's Terminal.
        @"usageSignIn": ^(NSDictionary *msg) {
            id<CommandHost> terminal = nil;
            for (id<CommandHost> host in [weakSelf.core hostsThat:@protocol(CommandHost)])
                if ([NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:host.appId]) {
                    terminal = host;
                    break;
                }
            [weakSelf.usage signInWith:terminal];
        },
    };
}

// The wait the strip shows at the session limit, and its reset, played now: to try it without a limit.
- (NSArray<MenuEntry *> *)menuEntries {
    NSMenuItem *preview = [[NSMenuItem alloc] initWithTitle:@"Preview the Wait" action:@selector(previewWait)
                                              keyEquivalent:@""];
    preview.target = self;
    return @[[MenuEntry entryIn:MenuSectionWhozmove order:20 item:preview]];
}

- (void)previewWait {
    [self.core.page call:@"previewWait" with:@[]];
}

@end
