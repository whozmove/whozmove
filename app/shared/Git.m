// Git: a checkout's branch, worktree, status and how much its work changes.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Git.h"
#import "Processes.h"
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

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

// A checkout's state from `git status --porcelain=v2 -z --branch`: {changes, ahead, behind, upstream, remotes}, and how
// the changed files split between staged and not (filesStaged: all their changes staged; filesPartly: staged, then
// changed again, so part of their changes are staged; filesUnstaged: none staged, or in conflict), or nil. The number
// of remotes matters because a commit in a repo with none has nowhere to go, so it's finished. Untracked files are left out here
// (FetchChangeCounts counts them), or build output and scratch files would make nearly every repo look like work in
// progress. It runs without optional locks: a plain `git status` refreshes the index under index.lock, and an agent
// committing at that moment would fail. Blocking.
NSDictionary *FetchCheckoutState(NSString *root) {
    NSDictionary *run = RunTool(@"/usr/bin/git", @[@"--no-optional-locks", @"-C", root, @"status", @"--porcelain=v2",
                                                   @"-z", @"--branch", @"--untracked-files=no"],
                                nil);
    if (!run || [run[@"status"] intValue] != 0) return nil;
    // A name that isn't UTF-8 (one from another system) reads as Latin-1, rather than losing the whole checkout.
    NSString *text = [[NSString alloc] initWithData:run[@"out"] encoding:NSUTF8StringEncoding]
        ?: [[NSString alloc] initWithData:run[@"out"] encoding:NSISOLatin1StringEncoding];
    if (!text) return nil;
    NSInteger changes = 0, ahead = 0, behind = 0;
    BOOL upstream = NO;
    NSString *upstreamName = nil;
    // By kind: staged, partly (staged, then changed again), unstaged. The two letters after a line's kind say where its
    // changes are: the first in what's staged, the second in the file since; "." where there are none. A file in
    // conflict counts as unstaged, as it can't be committed until it's settled.
    NSInteger counted[3] = {0, 0, 0};
    NSArray<NSString *> *records = [text componentsSeparatedByString:@"\0"];
    for (NSUInteger i = 0; i < records.count; i++) {
        NSString *line = records[i];
        if ([line hasPrefix:@"# branch.upstream "]) {
            upstream = YES;
            upstreamName = [line substringFromIndex:18];
        }
        else if ([line hasPrefix:@"# branch.ab "]) {
            NSArray *counts = [[line substringFromIndex:12] componentsSeparatedByString:@" "];  // "+A -B"
            if (counts.count == 2) { ahead = [counts[0] integerValue]; behind = -[counts[1] integerValue]; }
        } else if (line.length && ![line hasPrefix:@"#"]) {
            if ([line hasPrefix:@"2 "]) i++;  // a renamed file's old path, the record after it, isn't a change of its own
            changes++;
            BOOL staged = line.length > 3 && [line characterAtIndex:2] != '.' && ![line hasPrefix:@"u "];
            BOOL since = line.length > 3 && ([line characterAtIndex:3] != '.' || [line hasPrefix:@"u "]);
            NSUInteger kind = staged && since ? 1 : staged ? 0 : 2;
            counted[kind]++;
        }
    }
    NSDictionary *remote = RunTool(@"/usr/bin/git", @[@"--no-optional-locks", @"-C", root, @"remote"], nil);
    NSString *names = [[NSString alloc] initWithData:remote[@"out"] ?: NSData.data encoding:NSUTF8StringEncoding];
    NSUInteger remotes = [[names stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
                             componentsSeparatedByString:@"\n"].count;
    if (![names stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length)
        remotes = 0;
    // An upstream counts only on a remote (origin/main): a branch made to follow a local one (with --track) has
    // nothing of it on GitHub, however far ahead of that branch it is.
    if (upstream) {
        BOOL onRemote = NO;
        for (NSString *name in [names componentsSeparatedByString:@"\n"])
            if (name.length && [upstreamName hasPrefix:[name stringByAppendingString:@"/"]]) onRemote = YES;
        if (!onRemote) upstream = NO, ahead = 0, behind = 0;
    }
    return @{@"changes": @(changes), @"ahead": @(ahead), @"behind": @(behind), @"upstream": @(upstream),
             @"remotes": @(remotes), @"filesStaged": @(counted[0]), @"filesPartly": @(counted[1]),
             @"filesUnstaged": @(counted[2])};
}

// Where a checkout's branch left its base branch (see FetchChangeCounts), as a commit id, with the base's name in
// `base` and the ref it was found as (GitHub's copy, else the local one) in `baseRef`; nil, with neither, when there's
// none to measure from. Blocking.
NSString *BranchStart(NSString *root, NSString **base, NSString **baseRef) {
    NSString *(^git)(NSArray<NSString *> *) = ^NSString *(NSArray<NSString *> *arguments) {
        NSMutableArray *all = [@[@"--no-optional-locks", @"-C", root] mutableCopy];
        [all addObjectsFromArray:arguments];
        NSDictionary *run = RunTool(@"/usr/bin/git", all, nil);
        if (!run || [run[@"status"] intValue] != 0) return nil;
        NSString *text = [[NSString alloc] initWithData:run[@"out"] encoding:NSUTF8StringEncoding];
        return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    };
    NSString *head = git(@[@"symbolic-ref", @"--quiet", @"--short", @"refs/remotes/origin/HEAD"]);
    NSArray *names = [head hasPrefix:@"origin/"] ? @[[head substringFromIndex:7]] : @[@"main", @"master"];
    for (NSString *name in names)
        for (NSString *ref in @[[@"origin/" stringByAppendingString:name], name])
            if (git(@[@"rev-parse", @"--verify", @"--quiet", [ref stringByAppendingString:@"^{commit}"]])) {
                if (base) *base = name;
                if (baseRef) *baseRef = ref;
                NSString *from = git(@[@"merge-base", ref, @"HEAD"]);
                return from.length ? from : nil;
            }
    return nil;
}

// The repo's base branch as this Mac has it: the local branch named as GitHub's copy names its own (origin/HEAD), else
// main or master, else the branch its main checkout is on; nil with none. A new worktree starts from it and follows
// it, so it starts with everything there, committed here or not yet on GitHub. Blocking.
NSString *LocalBaseBranch(NSString *root) {
    NSString *(^git)(NSArray<NSString *> *) = ^NSString *(NSArray<NSString *> *arguments) {
        NSMutableArray *all = [@[@"--no-optional-locks", @"-C", root] mutableCopy];
        [all addObjectsFromArray:arguments];
        NSDictionary *run = RunTool(@"/usr/bin/git", all, nil);
        if (!run || [run[@"status"] intValue] != 0) return nil;
        NSString *text = [[NSString alloc] initWithData:run[@"out"] encoding:NSUTF8StringEncoding];
        text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        return text.length ? text : nil;
    };
    NSString *head = git(@[@"symbolic-ref", @"--quiet", @"--short", @"refs/remotes/origin/HEAD"]);
    NSMutableArray *names = [NSMutableArray array];
    if ([head hasPrefix:@"origin/"]) [names addObject:[head substringFromIndex:7]];
    [names addObjectsFromArray:@[@"main", @"master"]];
    for (NSString *name in names)
        if (git(@[@"rev-parse", @"--verify", @"--quiet", [@"refs/heads/" stringByAppendingString:name]])) return name;
    NSDictionary *info = GitInfo(root);
    NSString *main = info[@"mainRoot"] ?: info[@"root"];
    return main ? GitInfo(main)[@"branch"] : nil;
}

// A checkout's base branch, how many commits the branch has that the base doesn't, and how many new files there are:
// {base, aheadOfBase, newFiles}, or nil. The base is the branch GitHub's copy points at (origin/HEAD), else main or
// master: GitHub's copy of it if there is one, else the local one. Without any, the work is measured from the last
// commit. Blocking.
NSDictionary *FetchChangeCounts(NSString *root) {
    // What git prints, as it prints it (a name that isn't UTF-8 read as Latin-1), or nil when it fails.
    NSString *(^output)(NSArray<NSString *> *) = ^NSString *(NSArray<NSString *> *arguments) {
        NSMutableArray *all = [@[@"--no-optional-locks", @"-C", root] mutableCopy];
        [all addObjectsFromArray:arguments];
        NSDictionary *run = RunTool(@"/usr/bin/git", all, nil);
        if (!run || [run[@"status"] intValue] != 0) return nil;
        return [[NSString alloc] initWithData:run[@"out"] encoding:NSUTF8StringEncoding]
            ?: [[NSString alloc] initWithData:run[@"out"] encoding:NSISOLatin1StringEncoding];
    };
    // An answer, trimmed. A list of names (split on zero bytes) is read untrimmed, as a name can start with a space.
    NSString *(^git)(NSArray<NSString *> *) = ^NSString *(NSArray<NSString *> *arguments) {
        return [output(arguments) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    };
    NSString *base = nil, *baseRef = nil;
    BranchStart(root, &base, &baseRef);
    if (!git(@[@"rev-parse", @"--verify", @"--quiet", @"HEAD"]).length) return nil;  // no commit yet, or not a checkout
    NSString *others = output(@[@"ls-files", @"--others", @"--exclude-standard", @"-z"]) ?: @"";
    NSInteger newFiles = 0;
    for (NSString *path in [others componentsSeparatedByString:@"\0"])
        if (path.length) newFiles++;
    NSMutableDictionary *counts = [@{@"newFiles": @(newFiles)} mutableCopy];
    if (base) {
        counts[@"base"] = base;
        counts[@"aheadOfBase"] = @([git(@[@"rev-list", @"--count", [baseRef stringByAppendingString:@"..HEAD"]])
                                    integerValue]);
    }
    return counts;
}

// The branches GitHub's copy of a checkout's repo has, as this Mac last fetched them (origin's), by name, sorted, or nil
// when git can't say. Blocking.
NSArray<NSString *> *RemoteBranches(NSString *root) {
    NSDictionary *run = RunTool(@"/usr/bin/git", @[@"--no-optional-locks", @"-C", root, @"for-each-ref",
                                                   @"--format=%(refname:short)", @"refs/remotes/origin"], nil);
    if (!run || [run[@"status"] intValue] != 0) return nil;
    NSString *text = [[NSString alloc] initWithData:run[@"out"] encoding:NSUTF8StringEncoding] ?: @"";
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByString:@"\n"])
        // origin/HEAD names the branch GitHub's copy points at, not one of its own.
        if ([line hasPrefix:@"origin/"] && ![line isEqualToString:@"origin/HEAD"])
            [names addObject:[line substringFromIndex:7]];
    return [names sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}
