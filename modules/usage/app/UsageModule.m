// UsageModule: the usage card's face for the core (Module): your plan's usage asked of the agent when a check is due,
// the card behind the panel that shows it, its Sign in, and Working on Whozmove's Preview the Wait.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import "Module.h"
#import "Core.h"
#import "PanelWindow.h"
#import "Usage.h"
#import "UsageCard.h"

@interface UsageModule : NSObject <Module>
@property (weak) Core *core;
@property (strong) Usage *usage;  // made as the app starts: it watches the screens sleep and wake
@property (strong) UsageCard *card;
@property (copy) NSDictionary<NSString *, void (^)(NSDictionary *)> *answers;  // its page's messages, by type
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

// The card is held by the panel, over its shadow, following the glass and the pointer. Its page has a bridge of its own: what it
// says is answered here, as the panel's page's messages would be, and once it has loaded it's told what's known.
- (void)launch {
    self.card = [UsageCard new];
    self.usage = [[Usage alloc] initWithCard:self.card window:self.core.window
                                       agent:[self.core agentsThat:@protocol(AgentUsage)].firstObject];
    [self.core.window attachAbove:self.card.window];
    __weak typeof(self) weakSelf = self;
    [self.core.window followGlass:^(NSRect glass, NSRect list, NSRect screen, NSTimeInterval duration) {
        [weakSelf.card glassAt:glass list:list duration:duration];
    }];
    [self.core.window followPointer:^(NSPoint point) { [weakSelf.card pointerAt:point]; }];
    self.answers = [self messages];
    self.card.onMessage = ^(NSString *type, NSDictionary *message) {
        void (^answer)(NSDictionary *) = weakSelf.answers[type];
        if (answer) answer(message);
    };
    self.card.onLoad = ^{ [weakSelf.usage resend]; };
}

// The time is compared on every tick, so a Mac that slept through a check asks as it wakes.
- (void)tick {
    [self.usage pollIfDue];
}

// The card's page's messages (page/card.js).
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
        // Whether there's a card, and how much of it shows under the panel's edge.
        @"usageCard": ^(NSDictionary *msg) { [weakSelf.card took:msg]; },
    };
}

// The wait the card shows at the session limit, and its reset, played now: to try it without a limit.
- (NSArray<MenuEntry *> *)menuEntries {
    NSMenuItem *preview = [[NSMenuItem alloc] initWithTitle:@"Preview the Wait" action:@selector(previewWait)
                                              keyEquivalent:@""];
    preview.target = self;
    return @[[MenuEntry entryIn:MenuSectionWhozmove order:20 item:preview]];
}

- (void)previewWait {
    [self.card call:@"previewWait" with:@[]];
}

@end
