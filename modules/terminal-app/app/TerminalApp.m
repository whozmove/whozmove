// TerminalApp: macOS's Terminal, as a host that only runs a command (CommandHost): the usage card's Sign in, on a Mac
// without Ghostty or iTerm2. A session in it opens by bringing Terminal forward, as any other app's.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import "Module.h"
#import "Host.h"
#import "Files.h"
#import "Text.h"

// Its app id, which macOS gives it on every Mac.
static NSString *const kTerminalAppId = @"com.apple.Terminal";

@interface TerminalApp : NSObject <Module, CommandHost>
@end

@implementation TerminalApp

+ (NSString *)moduleName {
    return @"terminal-app";
}

- (instancetype)initWithCore:(Core *)core {
    return [super init];
}

- (NSString *)appId {
    return kTerminalAppId;
}

- (NSString *)name {
    return @"Terminal";
}

// Terminal opens a file of commands (.command) as a new window running them, so no Apple Events are sent and no new
// permission is asked for. The file is named for what it runs, which Terminal shows, and kept in a folder of its own,
// which only you may read.
- (void)newTabIn:(NSString *)folder running:(NSString *)command named:(NSString *)name forward:(BOOL)forward
            done:(void (^)(NSString *why))done {
    NSString *dir = AppDir(@"terminal");
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES
                                             attributes:@{NSFilePosixPermissions: @0700} error:nil];
    NSString *title = [[(name.length ? name : @"Whozmove") stringByReplacingOccurrencesOfString:@"/" withString:@"-"]
                       stringByReplacingOccurrencesOfString:@":" withString:@"-"];
    NSString *file = [dir stringByAppendingPathComponent:[title stringByAppendingPathExtension:@"command"]];
    NSString *script = [NSString stringWithFormat:@"#!/bin/sh\n# Opened by Whozmove: %@.\ncd -- %@ || exit\n%@\n",
                                                  title, ShellWord(folder), command];
    if (![script writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil])
        return done(@"Couldn't write what Terminal would run");
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0700} ofItemAtPath:file error:nil];
    NSURL *url = [NSURL fileURLWithPath:file];
    if (forward) return done([NSWorkspace.sharedWorkspace openURL:url] ? nil : @"Terminal didn't open it");
    NSWorkspaceOpenConfiguration *behind = [NSWorkspaceOpenConfiguration configuration];
    behind.activates = NO;
    NSURL *app = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:kTerminalAppId];
    if (!app) return done(@"Terminal isn't on this Mac");
    [NSWorkspace.sharedWorkspace openURLs:@[url] withApplicationAtURL:app configuration:behind
                        completionHandler:^(NSRunningApplication *opened, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ done(opened ? nil : @"Terminal didn't open it"); });
    }];
}

// Terminal on the panel's back: what Whozmove does with it. It needs nothing of macOS: it's never sent Apple Events.
- (NSArray<AppEntry *> *)appEntries {
    return @[[AppEntry appWithId:kTerminalAppId name:self.name
                            does:@"Brings a session that runs in it forward. On a Mac without Ghostty or iTerm2, it "
                                 @"runs Sign in, and carries on a conversation that has ended, in a new window."
                           order:40]];
}

@end
