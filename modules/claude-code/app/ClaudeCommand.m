// ClaudeCommand: where Claude Code's command may be, and what it runs with when the panel runs it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "ClaudeCommand.h"
#import "Files.h"
#import "ClaudeCodeFacts.h"

NSArray<NSString *> *ClaudeCandidates(NSString *path) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSMutableArray<NSString *> *found = [NSMutableArray array];
    void (^add)(NSString *) = ^(NSString *command) {
        if ([files isExecutableFileAtPath:command] && ![found containsObject:command]) [found addObject:command];
    };
    for (NSString *folder in [path componentsSeparatedByString:@":"])
        if (folder.isAbsolutePath) add([folder stringByAppendingPathComponent:@"claude"]);
    for (NSString *folder in ClaudeCommandFolders())  // the Mac's own folders are read from $HOME in the print modes
        add([(folder.isAbsolutePath ? MachineFile(folder) : [Home() stringByAppendingPathComponent:folder])
             stringByAppendingPathComponent:@"claude"]);
    NSString *desktop = [Home() stringByAppendingPathComponent:kClaudeDesktopCommands];
    NSArray *versions = [[files contentsOfDirectoryAtPath:desktop error:nil]
                         sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [b compare:a options:NSNumericSearch];  // newest first: 2.1.10 before 2.1.9
    }];
    for (NSString *version in versions) {
        NSString *folder = [desktop stringByAppendingPathComponent:version];
        for (NSString *build in [[files contentsOfDirectoryAtPath:folder error:nil]
                                 sortedArrayUsingSelector:@selector(compare:)])
            add([[folder stringByAppendingPathComponent:build]
                    stringByAppendingPathComponent:kClaudeDesktopCommandInBuild]);
    }
    return found;
}

BOOL ClaudeCodeOnThisMac(void) {
    return ClaudeCandidates(@"").count > 0
        || [NSFileManager.defaultManager fileExistsAtPath:ClaudeDir(kClaudeCodeRegistry)];
}

NSDictionary<NSString *, NSString *> *ClaudeEnvironment(NSString *path) {
    NSDictionary *own = NSProcessInfo.processInfo.environment;
    NSMutableDictionary *environment = [NSMutableDictionary dictionaryWithDictionary:@{@"PATH": path, @"HOME": Home()}];
    for (NSString *key in @[@"USER", @"LOGNAME", @"TMPDIR", @"LANG"])
        if (own[key]) environment[key] = own[key];
    return environment;
}
