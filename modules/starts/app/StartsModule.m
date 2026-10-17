// StartsModule: new conversations' face for the core (Module): the card's messages, the starts still waiting matched to
// the sessions they became, New Conversation and ⌃⌥N in the pawn menu, and the print mode the tests check.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import "Module.h"
#import "Core.h"
#import "Focus.h"
#import "Page.h"
#import "PanelWindow.h"
#import "Files.h"
#import "Menus.h"
#import "Printing.h"
#import "Starts.h"
#import "Shortcut.h"

// ⌃⌥N from any app, on until unticked.
static NSString *const kNewShortcut = @"newConversationShortcut";

// `Whozmove --print-starts`: what sample starts would run, as JSON, then quit: a terminal start's command, with and
// without words, and the link the app that keeps conversations opens a new one with (Claude Desktop's), with words of
// every kind (quotes, a new line, the characters a link's query gives meaning to) and with words too long for a link,
// which go into its box another way.
static int PrintStarts(Core *core) {
    NSString *sid = @"0b6f6b9e-3c0f-4f53-8e2a-6e1f0d8b2c11";
    NSString *file = [AppDir(@"starts") stringByAppendingPathComponent:[sid stringByAppendingPathExtension:@"txt"]];
    NSString *words = @"Fix the \"login\" page's loop: 50% of tickets & = + # it\nthen test it";
    id<ConversationHost> desktop = [core hostsThat:@protocol(ConversationHost)].firstObject;
    id<AgentStarts> agent = [core agentsThat:@protocol(AgentStarts)].firstObject;
    NSString *long_ = [@"" stringByPaddingToLength:desktop.linkWordsMax + 1 withString:@"x" startingAtIndex:0];
    return PrintJSON(@{@"terminal, no words": [agent startCommand:sid wordsFile:nil] ?: NSNull.null,
                       @"terminal, words": [agent startCommand:sid wordsFile:file] ?: NSNull.null,
                       @"desktop, no words": [desktop newConversationLink:@""].absoluteString ?: NSNull.null,
                       @"desktop, words": [desktop newConversationLink:words].absoluteString ?: NSNull.null,
                       @"desktop, words too long for a link":
                           [desktop newConversationLink:long_].absoluteString ?: NSNull.null});
}

@interface StartsModule : NSObject <Module>
@property (weak) Core *core;
@property (strong) Starts *starts;      // made as the app starts: it clears the words left from earlier starts
@property (strong) Shortcut *shortcut;
@property (strong) NSMenuItem *shortcutItem;
@end

@implementation StartsModule

+ (NSString *)moduleName {
    return @"starts";
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    [NSUserDefaults.standardUserDefaults registerDefaults:@{kNewShortcut: @YES}];
    return self;
}

+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return @{@"--print-starts": ^(Core *core, NSArray *a) { return PrintStarts(core); }};
}

- (void)launch {
    self.starts = [[Starts alloc] initWithCore:self.core];
    // A conversation started in a terminal tab that comes forward is opened from here: an answer about the tab before
    // it, already on its way, isn't taken, and the new session is the one you're on once it's listed.
    __weak Core *core = self.core;
    self.starts.onTabForward = ^(id<Host> terminal, NSString *sessionId) {
        [core.focus tabCameForward:terminal session:sessionId];
    };
    __weak typeof(self) weakSelf = self;
    self.shortcut = [[Shortcut alloc] initWithAction:^{ [weakSelf openStart]; }];
    self.shortcut.on = SwitchedOn(kNewShortcut);
}

- (void)pageLoaded {
    if (self.starts) [self.core.page call:@"setStartOptions" with:@[self.starts.options ?: @{}]];
}

- (NSDictionary<NSString *, void (^)(NSDictionary *)> *)messages {
    __weak typeof(self) weakSelf = self;
    return @{
        @"start": ^(NSDictionary *msg) { [weakSelf.starts start:msg]; },
        @"checkFolder": ^(NSDictionary *msg) { [weakSelf.starts checkFolder:msg]; },
        @"startMenu": ^(NSDictionary *msg) { [weakSelf.starts menu:msg]; },
    };
}

// Each session's work: the starts still waiting are matched to the sessions they became, or given up on.
- (void)rows:(NSArray<Row *> *)rows phase:(RowPhase)phase {
    if (phase == RowPhaseWork) [self.starts watch:rows];
}

#pragma mark New Conversation

// New Conversation (with ⌃⌥N shown beside it) at the top of the pawn menu, and whether ⌃⌥N works from any app.
- (NSArray<MenuEntry *> *)menuEntries {
    NSMenuItem *start = [[NSMenuItem alloc] initWithTitle:@"New Conversation" action:@selector(openStart)
                                            keyEquivalent:@"n"];
    start.keyEquivalentModifierMask = NSEventModifierFlagControl | NSEventModifierFlagOption;
    start.target = self;
    self.shortcutItem = [[NSMenuItem alloc] initWithTitle:@"Use ⌃⌥N in Any App" action:@selector(toggleShortcut)
                                            keyEquivalent:@""];
    self.shortcutItem.target = self;
    self.shortcutItem.state = SwitchedOn(kNewShortcut) ? NSControlStateValueOn : NSControlStateValueOff;
    return @[[MenuEntry entryIn:MenuSectionTop order:10 item:start],
             [MenuEntry entryIn:MenuSectionTop order:20 item:self.shortcutItem]];
}

- (void)toggleShortcut {
    FlipSwitch(kNewShortcut);
    self.shortcutItem.state = SwitchedOn(kNewShortcut) ? NSControlStateValueOn : NSControlStateValueOff;
    self.shortcut.on = SwitchedOn(kNewShortcut);
}

// New Conversation in the pawn menu, or ⌃⌥N from any app: the panel comes up (if it was hidden), with the keyboard,
// and opens its box for a new conversation. You give the keyboard back as you start it or close the box.
- (void)openStart {
    if (!self.core.page.ready) return;
    [self.core.window bringUp];
    [self.core.window takeKeyboard:YES];
    [self.core.page call:@"openStart" with:@[NSNull.null, NSNull.null]];
}

@end
