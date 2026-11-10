// Settings: the panel's look and whether rows show the conversation, kept, put on the panel and the page, and listed
// for Settings on the panel's back.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Settings.h"
#import "PanelWindow.h"
#import "Page.h"
#import "Module.h"
#import "Appearance.h"
#import "Links.h"

// The panel's look: grey until Black (white on the light panel) or Glass is picked, and light or dark as the Mac is
// until Light or Dark is. While macOS's Reduce Transparency is on, Glass is grey, and can't be picked, as macOS's own
// Liquid Glass choice can't. Whether rows show the conversation: on until Show Conversation Text is turned off. (The
// list has one view for everyone, so there's no choice of order: `groupBy`, the key that kept it, is never used again
// for another choice.)
static NSString *const kPanelLook = @"panelLook", *const kAppearance = @"appearance",
                *const kShowConversation = @"showConversationText";

@interface Settings ()
@property (strong) PanelWindow *window;
@property (strong) Page *page;
// Show Conversation Text: kept, and told to the page as it's set.
@property (nonatomic) BOOL showsConversation;
@end

@implementation Settings

- (instancetype)initWithWindow:(PanelWindow *)window page:(Page *)page {
    if (!(self = [super init])) return nil;
    self.window = window;
    self.page = page;
    [NSUserDefaults.standardUserDefaults registerDefaults:@{kShowConversation: @YES}];
    return self;
}

- (void)start {
    [self applySavedLook];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(applySavedLook)
        name:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification object:nil];
}

#pragma mark The look

- (void)save:(NSString *)choice as:(NSString *)key {
    [NSUserDefaults.standardUserDefaults setObject:choice forKey:key];
    [self applySavedLook];
}

// The look last picked, on the panel and the app's other windows (the page's colours follow, panel/styles/tokens.css);
// asked again when macOS's display settings change, for Reduce Transparency. Whatever follows the panel's look is told
// (PanelWindow's followLook:).
- (void)applySavedLook {
    NSString *appearance = self.appearance;
    NSApp.appearance = [appearance isEqual:@"light"] ? [NSAppearance appearanceNamed:NSAppearanceNameAqua]
                     : [appearance isEqual:@"dark"] ? [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua] : nil;
    self.window.look = self.look;
}

- (NSString *)look {
    NSString *look = self.pickedLook;
    if ([look isEqual:@"glass"] && NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceTransparency)
        look = @"grey";
    return look;
}

// The look picked, Glass even while Reduce Transparency makes it grey: Appearance ticks it, so Grey can still be picked
// in its place.
- (NSString *)pickedLook {
    NSString *look = [NSUserDefaults.standardUserDefaults stringForKey:kPanelLook];
    return [look isEqual:@"black"] || [look isEqual:@"glass"] ? look : @"grey";
}

// Light, dark, or as the Mac is ("system") until one is picked.
- (NSString *)appearance {
    NSString *appearance = [NSUserDefaults.standardUserDefaults stringForKey:kAppearance];
    return [appearance isEqual:@"light"] || [appearance isEqual:@"dark"] ? appearance : @"system";
}

#pragma mark The conversation on rows

- (BOOL)showsConversation {
    return [NSUserDefaults.standardUserDefaults boolForKey:kShowConversation];
}

- (void)applySavedConversation {
    [self.page call:@"setConversationShown" with:@[@(self.showsConversation)]];
}

- (void)setShowsConversation:(BOOL)on {
    [NSUserDefaults.standardUserDefaults setBool:on forKey:kShowConversation];
    [self applySavedConversation];
}

#pragma mark In Settings

// Appearance, a page of two choices: the look, each drawn as a small panel (Black is White on the light panel, as the
// app looks now, and Glass can't be picked while Reduce Transparency is on, with the way to turn it off under it), and
// light or dark. Then whether rows show the conversation.
- (NSArray<SettingEntry *> *)entries {
    __weak typeof(self) weakSelf = self;
    BOOL plain = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceTransparency;
    SettingEntry *look = [SettingEntry choiceWithKey:@"look" title:@"Look" glyph:@"look"
        choices:^NSArray<NSDictionary *> * {
            return @[@{@"id": @"grey", @"name": @"Grey"},
                     @{@"id": @"black", @"name": IsDark(NSApp.effectiveAppearance) ? @"Black" : @"White"},
                     @{@"id": @"glass", @"name": @"Glass", @"enabled": @(!plain)}];
        }
        picked:^NSString * { return weakSelf.pickedLook; }
        pick:^(NSString *choice) { [weakSelf save:choice as:kPanelLook]; }];
    look.page = @"Appearance";
    look.style = @"looks";
    if (plain) {
        look.foot = @"Glass shows as Grey while Reduce Transparency is on, in System Settings ▸ Accessibility ▸ Display.";
        look.button = @"Open Display Settings";
        look.press = ^{ OpenLink(@"x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_Display"); };
    }
    look.group = 10;
    look.order = 10;
    SettingEntry *scheme = [SettingEntry choiceWithKey:@"appearance" title:@"Light or Dark" glyph:@"look"
        choices:^NSArray<NSDictionary *> * {
            return @[@{@"id": @"system", @"name": @"Match the Mac"}, @{@"id": @"light", @"name": @"Light"},
                     @{@"id": @"dark", @"name": @"Dark"}];
        }
        picked:^NSString * { return weakSelf.appearance; }
        pick:^(NSString *choice) { [weakSelf save:choice as:kAppearance]; }];
    scheme.page = @"Appearance";
    scheme.foot = @"Match the Mac follows System Settings ▸ Appearance.";
    scheme.group = 10;
    scheme.order = 11;
    SettingEntry *conversation = [SettingEntry switchWithKey:kShowConversation title:@"Show Conversation Text"
        glyph:@"chat" on:^BOOL { return weakSelf.showsConversation; }
        set:^(BOOL on) { weakSelf.showsConversation = on; }];
    conversation.foot = @"Off, no one's words show: in the list, not Claude's line on a reply you haven't read or a "
                        @"question it asks; beside the folded panel, not your message, its reply or what it's working "
                        @"on. What needs you stays.";
    conversation.group = 10;
    conversation.order = 25;
    return @[look, scheme, conversation];
}

@end
