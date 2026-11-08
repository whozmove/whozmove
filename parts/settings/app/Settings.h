// Settings: the panel's own settings, which Settings on the panel's back shows before the modules' (the apps module
// lists them all): the look, grey, black or glass, and light, dark or as the Mac is; the list's order; and whether rows
// show the conversation. Each is kept in the app's preferences, under the names it has always had.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>

@class PanelWindow, Page, SettingEntry;

@interface Settings : NSObject
// For the app; a print run makes one with neither, for its rows alone.
- (instancetype)initWithWindow:(PanelWindow *)window page:(Page *)page;
// Puts the look last picked on the panel and the app, and follows macOS's Reduce Transparency from now on.
- (void)start;
// Tells a freshly loaded page the order last chosen (newest first until another is).
- (void)applySavedGrouping;
// Tells the page whether rows show the conversation (Show Conversation Text, on until it's turned off): a freshly
// loaded page, and the page each time the switch is pressed.
- (void)applySavedConversation;
// A module's way to group the list, offered in Session List after Newest First and Group by Project: the page's word
// for it (its core.groupings), its name, a line on it under the choices, and whether it's offered now (Group by Team
// only while one of the team is listed). Added as the module is made, before the order last chosen is told.
- (void)addGrouping:(NSString *)word name:(NSString *)name foot:(NSString *)foot shown:(BOOL (^)(void))shown;
// The panel's look as it is: the one picked (grey until another is), and grey for Glass while Reduce Transparency is
// on.
@property (readonly) NSString *look;
// Its rows in Settings, made afresh each time, as they say what's picked now.
@property (readonly) NSArray<SettingEntry *> *entries;
@end
