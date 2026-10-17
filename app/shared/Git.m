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

// The path a `git status --porcelain=v2 -z` record is about: what follows its fixed fields (8 for a changed file, 9
// for a renamed one, whose old path is the record after it, 10 for one with conflicts), or nil. With -z a name comes
// as it is, quotes, backslashes and tabs included.
static NSString *StatusPath(NSString *line) {
    NSUInteger fields = [line hasPrefix:@"1 "] ? 8 : [line hasPrefix:@"2 "] ? 9 : [line hasPrefix:@"u "] ? 10 : 0;
    NSUInteger at = 0;
    for (NSUInteger seen = 0; fields && seen < fields; seen++) {
        NSRange space = [line rangeOfString:@" " options:0 range:NSMakeRange(at, line.length - at)];
        if (space.location == NSNotFound) return nil;
        at = NSMaxRange(space);
    }
    if (!fields || at >= line.length) return nil;
    return [line substringFromIndex:at];
}

// A checkout's state from `git status --porcelain=v2 -z --branch`: {changes, ahead, behind, upstream, remotes}, how the
// changed files split between staged and not (filesStaged: all their changes staged; filesPartly: staged, then changed
// again, so part of their changes are staged; filesUnstaged: none staged, or in conflict), the first 10 changed files
// (files) and the first 100 of each kind (stagedPaths, partlyPaths, unstagedPaths), and each changed file's kind, 0 to
// 2 in that order (kindOf, for the checkouts' queue only), or nil. The number of remotes
// matters because a commit in a repo with none has nowhere to go, so it's finished. Untracked files are left out here
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
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    // By kind: staged, partly (staged, then changed again), unstaged. The two letters after a line's kind say where its
    // changes are: the first in what's staged, the second in the file since; "." where there are none. A file in
    // conflict counts as unstaged, as it can't be committed until it's settled.
    NSArray<NSMutableArray<NSString *> *> *kinds = @[[NSMutableArray array], [NSMutableArray array],
                                                     [NSMutableArray array]];
    NSInteger counted[3] = {0, 0, 0};
    NSMutableDictionary<NSString *, NSNumber *> *kindOf = [NSMutableDictionary dictionary];  // every changed file's
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
            NSString *path = StatusPath(line);
            if (files.count < 10 && path) [files addObject:path];
            BOOL staged = line.length > 3 && [line characterAtIndex:2] != '.' && ![line hasPrefix:@"u "];
            BOOL since = line.length > 3 && ([line characterAtIndex:3] != '.' || [line hasPrefix:@"u "]);
            NSUInteger kind = staged && since ? 1 : staged ? 0 : 2;
            counted[kind]++;
            if (path && kinds[kind].count < 100) [kinds[kind] addObject:path];
            if (path) kindOf[path] = @(kind);
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
             @"remotes": @(remotes), @"files": files, @"filesStaged": @(counted[0]), @"filesPartly": @(counted[1]),
             @"filesUnstaged": @(counted[2]), @"stagedPaths": kinds[0], @"partlyPaths": kinds[1],
             @"unstagedPaths": kinds[2], @"kindOf": kindOf};
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

// A checkout's base branch, how many commits the branch has that the base doesn't, and how many new files there are:
// {base, aheadOfBase, newFiles}, with the first 100 new files (newPaths), all of them (untracked, for the checkouts'
// queue only) and, given the checkout's
// `state` (FetchCheckoutState), the subjects of the first 10 commits not on GitHub yet (commits), or nil. The base is
// the branch GitHub's copy points at (origin/HEAD), else main or master: GitHub's copy of it if there is one, else the
// local one. Without any, the work is measured from the last commit. Blocking.
NSDictionary *FetchChangeCounts(NSString *root, NSDictionary *state) {
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
    NSArray<NSString *> *paths = [others componentsSeparatedByString:@"\0"];
    NSMutableArray<NSString *> *newPaths = [NSMutableArray array];
    NSInteger newFiles = 0;
    for (NSUInteger i = 0; i < paths.count; i++) {
        if (!paths[i].length) continue;
        newFiles++;
        if (newPaths.count < 100) [newPaths addObject:paths[i]];
    }
    NSMutableDictionary *counts = [@{@"newFiles": @(newFiles), @"newPaths": newPaths,
                                     @"untracked": [NSSet setWithArray:paths]} mutableCopy];
    NSInteger aheadOfBase = 0;
    if (base) {
        counts[@"base"] = base;
        counts[@"aheadOfBase"] = @(aheadOfBase = [git(@[@"rev-list", @"--count",
                                                         [baseRef stringByAppendingString:@"..HEAD"]]) integerValue]);
    }
    // The commits not on GitHub yet, by subject, for the commits stage's menu: past the upstream when there is one,
    // else past the base (unpushedCommits in panel/scripts/whose-move.js goes by the same rule, so keep them in step).
    BOOL upstream = [state[@"upstream"] boolValue];
    NSInteger unpushed = upstream ? [state[@"ahead"] integerValue] : aheadOfBase;
    if ([state[@"remotes"] integerValue] > 0 && unpushed > 0 && (upstream || baseRef)) {
        NSString *range = upstream ? @"@{upstream}..HEAD" : [baseRef stringByAppendingString:@"..HEAD"];
        NSString *log = git(@[@"log", @"--no-color", @"--format=%s", @"-n", @"10", range]);
        NSArray *subjects = [log componentsSeparatedByString:@"\n"];
        if (log.length) counts[@"commits"] = subjects;
    }
    return counts;
}
