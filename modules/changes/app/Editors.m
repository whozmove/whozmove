// Editors: the editor a file opens in, at a line, chosen once and kept (Editors.h).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import "Editors.h"
#import "Links.h"

static NSString *const kChoice = @"openWith";

// What Whozmove relies on about the editors it offers, which they could change: {id (the app's bundle id), name, line
// (a link that opens a file at a line, with the file's path and the line put in, for those that have one), get (its
// download page, for the one offered when none is on this Mac)}. The versions they were last checked with are in
// docs/using/install.md ("What it's tested with").
static NSArray<NSDictionary *> *KnownEditors(void) {
    return @[
        @{@"id": @"com.microsoft.VSCode", @"name": @"Visual Studio Code", @"line": @"vscode://file%@:%ld",
          @"get": @"https://code.visualstudio.com/download"},
        @{@"id": @"com.todesktop.230313mzl4w4u92", @"name": @"Cursor", @"line": @"cursor://file%@:%ld"},
        @{@"id": @"dev.zed.Zed", @"name": @"Zed"},
        @{@"id": @"com.apple.dt.Xcode", @"name": @"Xcode"},
        @{@"id": @"com.sublimetext.4", @"name": @"Sublime Text"},
        @{@"id": @"com.barebones.bbedit", @"name": @"BBEdit"},
    ];
}

static NSDictionary *Editor(NSString *editorId) {
    for (NSDictionary *editor in KnownEditors())
        if ([editor[@"id"] isEqualToString:editorId]
            && [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:editorId])
            return editor;
    return nil;
}

// The editors on this Mac, asked of macOS again only once the last answer is half a minute old: Settings asks every
// second while it shows, and an editor put in or taken out shows up soon enough.
static NSArray<NSDictionary *> *InstalledEditors(void) {
    static NSArray<NSDictionary *> *installed;
    static NSDate *askedAt;
    if (installed && askedAt.timeIntervalSinceNow > -30) return installed;
    NSMutableArray *apps = [NSMutableArray array];
    for (NSDictionary *editor in KnownEditors())
        if ([NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:editor[@"id"]]) [apps addObject:editor];
    installed = apps;
    askedAt = [NSDate date];
    return installed;
}

// The editor to get when none is on this Mac: the first that has a download page.
static NSDictionary *EditorToGet(void) {
    if (InstalledEditors().count) return nil;
    for (NSDictionary *editor in KnownEditors())
        if (editor[@"get"]) return editor;
    return nil;
}

NSDictionary *EditorChoices(void) {
    NSMutableArray *apps = [NSMutableArray array];
    for (NSDictionary *editor in InstalledEditors()) [apps addObject:@{@"id": editor[@"id"], @"name": editor[@"name"]}];
    NSString *choice = [NSUserDefaults.standardUserDefaults stringForKey:kChoice];
    NSMutableDictionary *choices = [@{@"apps": apps} mutableCopy];
    if (choice && [[apps valueForKey:@"id"] containsObject:choice]) choices[@"choice"] = choice;
    if (EditorToGet()) choices[@"get"] = EditorToGet()[@"name"];
    return choices;
}

BOOL GetEditor(void) {
    NSURL *page = [NSURL URLWithString:EditorToGet()[@"get"] ?: @""];
    return page.scheme && OpenInOtherApp(page);
}

NSArray<NSString *> *KnownEditorNames(void) {
    return [KnownEditors() valueForKey:@"name"];
}

void ChooseEditor(NSString *editorId) {
    if (editorId && Editor(editorId)) [NSUserDefaults.standardUserDefaults setObject:editorId forKey:kChoice];
    else [NSUserDefaults.standardUserDefaults removeObjectForKey:kChoice];
}

// By the editor's own link, which can name a line; else the file, handed to the editor as a double-click would.
BOOL OpenInEditor(NSString *path, NSInteger line) {
    NSDictionary *editor = Editor([NSUserDefaults.standardUserDefaults stringForKey:kChoice]);
    if (!editor || !path.isAbsolutePath) return NO;
    NSString *escaped = [path stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
    NSURL *link = editor[@"line"] && escaped
        ? [NSURL URLWithString:[NSString stringWithFormat:editor[@"line"], escaped, (long)MAX(line, 1)]] : nil;
    if (link) return OpenInOtherApp(link);
    NSURL *app = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:editor[@"id"]];
    return OpenInOtherAppWith(@[[NSURL fileURLWithPath:path]], app, [NSWorkspaceOpenConfiguration configuration], nil);
}
