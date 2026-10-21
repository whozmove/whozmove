// LoginItem: the login item's file, what it holds, and what launchctl says of its job.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "LoginItem.h"
#import "Files.h"
#import "LaunchdFacts.h"

NSString *LoginItemPath(NSString *label) {
    return [[Home() stringByAppendingPathComponent:kLaunchAgentsFolder]
            stringByAppendingPathComponent:[label stringByAppendingPathExtension:@"plist"]];
}

NSDictionary *LoginItemContents(NSString *label, NSString *program) {
    return @{@"Label": label, @"ProgramArguments": @[program], @"RunAtLoad": @YES, @"KeepAlive": @{@"Crashed": @YES},
             @"LimitLoadToSessionType": @"Aqua", @"ProcessType": @"Interactive",
             @"AssociatedBundleIdentifiers": @[label]};
}

NSString *KeepLoginItem(NSString *label, NSString *program, BOOL *wrote) {
    *wrote = NO;
    NSString *path = LoginItemPath(label);
    NSDictionary *contents = LoginItemContents(label, program);
    if ([[NSDictionary dictionaryWithContentsOfFile:path] isEqual:contents]) return nil;
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent
                            withIntermediateDirectories:YES attributes:nil error:nil];
    NSData *xml = [NSPropertyListSerialization dataWithPropertyList:contents format:NSPropertyListXMLFormat_v1_0
                                                            options:0 error:nil];
    if (![xml writeToFile:path atomically:YES]) return @"couldn't write the login item";
    *wrote = YES;
    return nil;
}

BOOL RemoveLoginItem(NSString *label) {
    return [NSFileManager.defaultManager removeItemAtPath:LoginItemPath(label) error:nil];
}

// `launchctl print` names the job's process on a line of its own, "pid = 123", while it runs one.
pid_t LoginJobPid(NSString *printed) {
    for (NSString *line in [printed componentsSeparatedByString:@"\n"]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([trimmed hasPrefix:kLaunchctlPidLine])
            return (pid_t)[trimmed substringFromIndex:kLaunchctlPidLine.length].intValue;
    }
    return 0;
}
