// TerminalApp: macOS's Terminal, as a host that only runs a command (CommandHost): the usage strip's Sign in, on a Mac
// without a terminal the panel types into. A session in it opens by bringing Terminal forward, as any other app's.
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
- (void)newTabIn:(NSString *)folder running:(NSString *)command named:(NSString *)name forward:(BOOL)forward {
    NSString *dir = AppDir(@"terminal");
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES
                                             attributes:@{NSFilePosixPermissions: @0700} error:nil];
    NSString *title = [[(name.length ? name : @"Whozmove") stringByReplacingOccurrencesOfString:@"/" withString:@"-"]
                       stringByReplacingOccurrencesOfString:@":" withString:@"-"];
    NSString *file = [dir stringByAppendingPathComponent:[title stringByAppendingPathExtension:@"command"]];
    NSString *script = [NSString stringWithFormat:@"#!/bin/sh\n# Opened by Whozmove: %@.\ncd -- %@ || exit\n%@\n",
                                                  title, ShellWord(folder), command];
    if (![script writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil]) return;
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0700} ofItemAtPath:file error:nil];
    NSURL *url = [NSURL fileURLWithPath:file];
    if (forward) {
        [NSWorkspace.sharedWorkspace openURL:url];
        return;
    }
    NSWorkspaceOpenConfiguration *behind = [NSWorkspaceOpenConfiguration configuration];
    behind.activates = NO;
    NSURL *app = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:kTerminalAppId];
    if (app) [NSWorkspace.sharedWorkspace openURLs:@[url] withApplicationAtURL:app configuration:behind
                                 completionHandler:nil];
}

@end
