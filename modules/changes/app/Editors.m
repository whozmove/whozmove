// Editors: the editor a changed file opens in, chosen once and kept.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import "Editors.h"

static NSString *const kChoice = @"openWith";

// What Whozmove relies on about the editors it offers, which they could change: {id (the app's bundle id), name, line
// (a link that opens a file at a line, with the file's path and the line put in, for those that have one)}. The
// versions they were last checked with are in the README ("Tested with").
static NSArray<NSDictionary *> *KnownEditors(void) {
    return @[
        @{@"id": @"com.microsoft.VSCode", @"name": @"Visual Studio Code", @"line": @"vscode://file%@:%ld"},
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

NSDictionary *EditorChoices(void) {
    NSMutableArray *apps = [NSMutableArray array];
    for (NSDictionary *editor in KnownEditors())
        if ([NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:editor[@"id"]])
            [apps addObject:@{@"id": editor[@"id"], @"name": editor[@"name"]}];
    NSString *choice = [NSUserDefaults.standardUserDefaults stringForKey:kChoice];
    NSMutableDictionary *choices = [@{@"apps": apps} mutableCopy];
    if (Editor(choice)) choices[@"choice"] = choice;
    return choices;
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
    if (link) return [NSWorkspace.sharedWorkspace openURL:link];
    NSURL *app = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:editor[@"id"]];
    [NSWorkspace.sharedWorkspace openURLs:@[[NSURL fileURLWithPath:path]] withApplicationAtURL:app
                            configuration:[NSWorkspaceOpenConfiguration configuration] completionHandler:nil];
    return YES;
}
