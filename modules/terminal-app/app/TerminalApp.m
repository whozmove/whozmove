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

// Files of commands left from windows that never ran them go as the app opens, once they're a minute old: one for a
// window still opening as the panel restarts is still wanted.
- (void)launch {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSFileManager *manager = NSFileManager.defaultManager;
        NSString *files = AppDir(@"terminal");
        for (NSString *name in [manager contentsOfDirectoryAtPath:files error:nil]) {
            NSString *path = [files stringByAppendingPathComponent:name];
            NSDate *made = [manager attributesOfItemAtPath:path error:nil].fileModificationDate;
            if (made && -made.timeIntervalSinceNow > 60) [manager removeItemAtPath:path error:nil];
        }
    });
}

// Terminal opens a file of commands (.command) as a new window running them, so no Apple Events are sent and no new
// permission is asked for. The file is named for what it runs, which Terminal shows, made one line: a line break in a
// session's name would end the comment the name is in, and run the rest. Each file is in a folder of its own, in one
// only you may read, so two opened at once never write over each other; it takes itself away as it starts.
- (void)newTabIn:(NSString *)folder running:(NSString *)command named:(NSString *)name forward:(BOOL)forward
            done:(void (^)(NSString *why))done {
    NSString *dir = [AppDir(@"terminal") stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES
                                             attributes:@{NSFilePosixPermissions: @0700} error:nil];
    // At most 60 characters, so its file name fits in the 255 bytes macOS allows, whatever it's written in.
    NSString *title = [[OneLine(name.length ? name : @"Whozmove", 60) stringByReplacingOccurrencesOfString:@"/"
                                                                                                withString:@"-"]
                       stringByReplacingOccurrencesOfString:@":" withString:@"-"];
    NSString *file = [dir stringByAppendingPathComponent:[title stringByAppendingPathExtension:@"command"]];
    NSString *script = [NSString stringWithFormat:@"#!/bin/sh\n# Opened by Whozmove: %@.\nrm -rf -- %@\n"
                                                  @"cd -- %@ || exit\n%@\n",
                                                  title, ShellWord(dir), ShellWord(folder), command];
    void (^finish)(NSString *) = ^(NSString *why) {
        if (why) [NSFileManager.defaultManager removeItemAtPath:dir error:nil];
        done(why);
    };
    if (![script writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil])
        return finish(@"Couldn't write what Terminal would run");
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0700} ofItemAtPath:file error:nil];
    NSURL *url = [NSURL fileURLWithPath:file];
    if (forward) return finish([NSWorkspace.sharedWorkspace openURL:url] ? nil : @"Terminal didn't open it");
    NSWorkspaceOpenConfiguration *behind = [NSWorkspaceOpenConfiguration configuration];
    behind.activates = NO;
    NSURL *app = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:kTerminalAppId];
    if (!app) return finish(@"Terminal isn't on this Mac");
    [NSWorkspace.sharedWorkspace openURLs:@[url] withApplicationAtURL:app configuration:behind
                        completionHandler:^(NSRunningApplication *opened, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ finish(opened ? nil : @"Terminal didn't open it"); });
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
