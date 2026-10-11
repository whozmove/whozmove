// Git: a checkout's branch, worktree and status.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Git.h"
#import "Processes.h"

// The branch and worktree of the checkout that holds `cwd`, read straight from its .git, without running git:
// {branch or detached, root, worktree, worktreeOf, mainRoot}, or nil outside a repo.
NSDictionary *GitInfo(NSString *cwd) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSCharacterSet *space = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    for (NSString *dir = cwd; dir.length > 1; dir = dir.stringByDeletingLastPathComponent) {
        NSString *dotGit = [dir stringByAppendingPathComponent:@".git"];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:dotGit isDirectory:&isDir]) continue;

        NSString *gitDir = dotGit;
        BOOL linkedWorktree = NO;
        if (!isDir) {  // a linked worktree or a submodule: its ".git" is a file naming the real git folder
            NSString *pointer = [NSString stringWithContentsOfFile:dotGit encoding:NSUTF8StringEncoding error:nil];
            NSRange tag = [pointer rangeOfString:@"gitdir:"];
            if (tag.location == NSNotFound) return nil;
            gitDir = [[pointer substringFromIndex:NSMaxRange(tag)] stringByTrimmingCharactersInSet:space];
            if (!gitDir.isAbsolutePath) gitDir = [dir stringByAppendingPathComponent:gitDir];
            gitDir = gitDir.stringByStandardizingPath;
            linkedWorktree = [gitDir.stringByDeletingLastPathComponent.lastPathComponent isEqualToString:@"worktrees"];
        }

        NSString *head = [[NSString stringWithContentsOfFile:[gitDir stringByAppendingPathComponent:@"HEAD"]
                                                    encoding:NSUTF8StringEncoding error:nil]
                          stringByTrimmingCharactersInSet:space];
        if (!head.length) return nil;
        NSMutableDictionary *info = [@{@"root": dir} mutableCopy];
        if ([head hasPrefix:@"ref: refs/heads/"]) info[@"branch"] = [head substringFromIndex:16];
        else if ([head hasPrefix:@"ref: "]) info[@"branch"] = [head substringFromIndex:5];
        else info[@"detached"] = [head substringToIndex:MIN((NSUInteger)7, head.length)];

        if (linkedWorktree) {
            // <repo>/.git/worktrees/<name>: the main checkout is the folder that holds that .git (for a bare
            // repo, the "<repo>.git" folder itself).
            NSString *common = gitDir.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent;
            NSString *mainRoot = [common.lastPathComponent isEqualToString:@".git"]
                ? common.stringByDeletingLastPathComponent : common;
            info[@"worktree"] = dir.lastPathComponent;
            info[@"worktreeOf"] = mainRoot.lastPathComponent.stringByDeletingPathExtension;
            info[@"mainRoot"] = mainRoot;
        }
        return info;
    }
    return nil;
}

// A checkout's state from `git status --porcelain=v2 --branch`: {changes, ahead, behind, upstream, remotes}, or
// nil. The number of remotes matters because a commit in a repo with none has nowhere to go, so it's finished.
// Untracked files are left out, or build output and scratch files would make nearly every repo look like work in
// progress. It runs without optional locks: a plain `git status` refreshes the index under index.lock, and an
// agent committing at that moment would fail. Blocking.
NSDictionary *FetchCheckoutState(NSString *root) {
    NSDictionary *run = RunTool(@"/usr/bin/git", @[@"--no-optional-locks", @"-C", root, @"status", @"--porcelain=v2",
                                                   @"--branch", @"--untracked-files=no"], nil);
    if (!run || [run[@"status"] intValue] != 0) return nil;
    NSString *text = [[NSString alloc] initWithData:run[@"out"] encoding:NSUTF8StringEncoding];
    if (!text) return nil;
    NSInteger changes = 0, ahead = 0, behind = 0;
    BOOL upstream = NO;
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:@"# branch.upstream "]) upstream = YES;
        else if ([line hasPrefix:@"# branch.ab "]) {
            NSArray *counts = [[line substringFromIndex:12] componentsSeparatedByString:@" "];  // "+A -B"
            if (counts.count == 2) { ahead = [counts[0] integerValue]; behind = -[counts[1] integerValue]; }
        } else if (line.length && ![line hasPrefix:@"#"]) changes++;
    }
    NSDictionary *remote = RunTool(@"/usr/bin/git", @[@"--no-optional-locks", @"-C", root, @"remote"], nil);
    NSString *names = [[NSString alloc] initWithData:remote[@"out"] ?: NSData.data encoding:NSUTF8StringEncoding];
    NSUInteger remotes = [[names stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
                             componentsSeparatedByString:@"\n"].count;
    if (![names stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length)
        remotes = 0;
    return @{@"changes": @(changes), @"ahead": @(ahead), @"behind": @(behind), @"upstream": @(upstream),
             @"remotes": @(remotes)};
}
