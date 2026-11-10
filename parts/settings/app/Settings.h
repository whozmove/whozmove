// Settings: the panel's own settings, which Settings on the panel's back shows before the modules' (the apps module
// lists them all): the look, grey, black or glass, and light, dark or as the Mac is; and whether rows show the
// conversation. Each is kept in the app's preferences, under the names it has always had.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>

@class PanelWindow, Page, SettingEntry;

@interface Settings : NSObject
// For the app; a print run makes one with neither, for its rows alone.
- (instancetype)initWithWindow:(PanelWindow *)window page:(Page *)page;
// Puts the look last picked on the panel and the app, and follows macOS's Reduce Transparency from now on.
- (void)start;
// Tells the page whether rows show the conversation (Show Conversation Text, on until it's turned off): a freshly
// loaded page, and the page each time the switch is pressed.
- (void)applySavedConversation;
// The panel's look as it is: the one picked (grey until another is), and grey for Glass while Reduce Transparency is
// on.
@property (readonly) NSString *look;
// Its rows in Settings, made afresh each time, as they say what's picked now.
@property (readonly) NSArray<SettingEntry *> *entries;
@end
