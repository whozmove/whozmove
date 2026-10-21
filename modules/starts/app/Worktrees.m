// Worktrees: a worktree of its own for a new conversation, as Worktrees.h describes it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// A worktree is made with `git worktree add --track -b <name> <folder>/<name> <base>`, from the main checkout, through
// your shell with your PATH and without agents' marks (RunInCheckout), so the repo's own hooks run as they would for
// you. Its branch follows the local base branch, so it starts with everything there, whether it's on GitHub yet or not.
#import "Worktrees.h"
#import "Core.h"
#import "Files.h"
#import "Git.h"
#import "Processes.h"
#import "Text.h"

// How long git may take to make one (the repo's hooks run as it does), and the most of a name.
static const NSTimeInterval kMakeWait = 60;
static const NSUInteger kNameMax = 60;

@interface Worktrees ()
@property (weak) Core *core;
@property (strong) NSMutableDictionary<NSString *, NSString *> *chosen;  // by the repo's real path; loaded once
@end

@implementation Worktrees

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    return self;
}

+ (NSString *)nameFrom:(id)value {
    NSString *name = AsText(value);
    if (!name.length || name.length > kNameMax || [name hasSuffix:@".lock"]) return nil;
    NSCharacterSet *other = [NSCharacterSet characterSetWithCharactersInString:
                             @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"].invertedSet;
    NSCharacterSet *first = [NSCharacterSet alphanumericCharacterSet];
    if ([name rangeOfCharacterFromSet:other].location != NSNotFound) return nil;
    if (![first characterIsMember:[name characterAtIndex:0]] || [name containsString:@".."]) return nil;
    return name;
}

#pragma mark Where they go

- (NSMutableDictionary *)store {
    @synchronized (self) {
        if (!self.chosen) {
            self.chosen = [NSMutableDictionary dictionary];
            NSDictionary *saved = AsRecord(AsRecord(ReadJSON(AppDir(@"worktrees.json")))[@"repos"]);
            for (NSString *repo in saved) {
                NSString *folder = AsText(AsRecord(saved[repo])[@"folder"]);
                if (folder.isAbsolutePath) self.chosen[repo] = folder;
            }
        }
        return self.chosen;
    }
}

- (NSString *)chosenFor:(NSString *)repo {
    @synchronized (self) {
        return [self store][RealPath(repo)];
    }
}

+ (NSString *)besideFolderFor:(NSString *)repo {
    return [repo.stringByDeletingLastPathComponent
            stringByAppendingPathComponent:[repo.lastPathComponent stringByAppendingString:@"-worktrees"]];
}

- (void)choose:(NSString *)folder for:(NSString *)repo {
    @synchronized (self) {
        NSMutableDictionary *store = [self store];
        store[RealPath(repo)] = folder.isAbsolutePath ? folder : nil;
        NSMutableDictionary *repos = [NSMutableDictionary dictionary];
        for (NSString *key in store) repos[key] = @{@"folder": store[key]};
        NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"repos": repos}
                                                       options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                         error:nil];
        [json writeToFile:AppDir(@"worktrees.json") atomically:YES];
    }
}

// The folder a repo's worktrees go in: yours, else the one beside it.
- (NSString *)folderFor:(NSString *)repo {
    return [self chosenFor:repo] ?: [Worktrees besideFolderFor:repo];
}

#pragma mark What a repo has, checking and making one

// What git says, trimmed, or nil when it fails. Asking (unlike making one) runs no hooks, so it needn't go as you.
static NSString *Ask(NSString *root, NSArray<NSString *> *arguments) {
    NSMutableArray *all = [@[@"--no-optional-locks", @"-C", root] mutableCopy];
    [all addObjectsFromArray:arguments];
    NSDictionary *run = RunGit(all);
    if (!run || [run[@"status"] intValue] != 0) return nil;
    return [[[NSString alloc] initWithData:run[@"out"] encoding:NSUTF8StringEncoding]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

+ (NSString *)shown:(NSString *)path {
    NSString *home = Home();
    return [path hasPrefix:[home stringByAppendingString:@"/"]]
        ? [@"~" stringByAppendingString:[path substringFromIndex:home.length]] : path;
}

// The repo's main checkout, for a folder in it (or in one of its worktrees), or nil outside git.
static NSString *RepoOf(NSString *folder) {
    NSDictionary *info = GitInfo(folder);
    return info[@"mainRoot"] ?: info[@"root"];
}

// Each folder a repo's branches are checked out in, as git lists them: {path: branch}, the main checkout among them.
// A folder on no branch (detached) has none.
static NSDictionary<NSString *, NSString *> *CheckedOut(NSString *repo) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSString *path = nil;
    for (NSString *line in [Ask(repo, @[@"worktree", @"list", @"--porcelain"]) componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:@"worktree "]) path = [line substringFromIndex:9];
        else if ([line hasPrefix:@"branch refs/heads/"] && path) out[RealPath(path)] = [line substringFromIndex:18];
    }
    return out;
}

- (NSDictionary *)listIn:(NSString *)folder {
    NSString *repo = RepoOf(folder);
    if (!repo) return @{@"none": @YES, @"where": [Worktrees shown:RealPath(folder)]};
    NSDictionary *checkedOut = CheckedOut(repo), *git = GitInfo(folder);
    NSString *here = RealPath(git[@"root"] ?: folder);
    NSMutableArray *worktrees = [NSMutableArray array];
    for (NSString *path in [checkedOut.allKeys sortedArrayUsingSelector:@selector(compare:)])
        if (![path isEqual:here])
            [worktrees addObject:@{@"branch": checkedOut[path], @"path": path, @"where": [Worktrees shown:path]}];
    NSSet *taken = [NSSet setWithArray:checkedOut.allValues];
    NSMutableArray *branches = [NSMutableArray array];
    for (NSString *name in [Ask(repo, @[@"for-each-ref", @"--format=%(refname:short)", @"refs/heads"])
                            componentsSeparatedByString:@"\n"])
        if (name.length && ![taken containsObject:name]) [branches addObject:name];
    NSString *base = LocalBaseBranch(repo);
    // Its own branch comes from its .git too, so it's still named when git can't be asked (before Apple's developer
    // tools are installed), though its worktrees and branches can't be listed then.
    return @{@"here": @{@"path": here, @"where": [Worktrees shown:here],
                        @"branch": checkedOut[here] ?: git[@"branch"] ?: NSNull.null},
             @"worktrees": worktrees, @"branches": branches, @"base": base ?: NSNull.null,
             @"folder": [Worktrees shown:[self folderFor:repo]], @"folderPath": [self folderFor:repo]};
}

- (NSString *)openPath:(id)path in:(NSString *)folder {
    NSString *repo = RepoOf(folder), *real = AsText(path).isAbsolutePath ? RealPath(path) : nil;
    return repo && real && CheckedOut(repo)[real] ? real : nil;
}

// A local branch, by its name: nil unless the repo has one so named.
static NSString *LocalBranch(NSString *repo, id value) {
    NSString *name = AsText(value);
    if (!name.length || [name hasPrefix:@"-"] || !Ask(repo, @[@"check-ref-format", @"--branch", name])) return nil;
    return Ask(repo, @[@"rev-parse", @"--verify", @"--quiet", [@"refs/heads/" stringByAppendingString:name]]) ? name : nil;
}

- (NSDictionary *)check:(NSDictionary *)target in:(NSString *)folder {
    // Making one runs git from your shell, which without Apple's developer tools offers to install them instead, and
    // the checks below ask git too, so they'd fail for the wrong reason.
    if (!DeveloperToolsReady())
        return @{@"why": @"Making a worktree needs Apple's command line developer tools: install them first"};
    NSString *repo = RepoOf(folder);
    if (!repo) return @{@"why": [NSString stringWithFormat:@"%@ isn't in a git repository", folder.lastPathComponent]};
    NSString *kind = AsText(target[@"kind"]), *name = nil, *base = nil;
    if ([kind isEqual:@"branch"]) {
        // A branch that's there, with no folder yet: a worktree for it, named for it.
        if (!(name = LocalBranch(repo, target[@"name"])))
            return @{@"why": [NSString stringWithFormat:@"There's no branch named %@ here", AsText(target[@"name"]) ?: @""]};
        if ([CheckedOut(repo).allValues containsObject:name])
            return @{@"why": [NSString stringWithFormat:@"%@ is checked out in a folder already: start there", name]};
    } else {
        if (!(name = [Worktrees nameFrom:target[@"name"]])) return @{@"why": @"A worktree's name takes letters, digits and dashes"};
        base = target[@"base"] ? LocalBranch(repo, target[@"base"]) : LocalBaseBranch(repo);
        if (!base) return @{@"why": target[@"base"] ? [NSString stringWithFormat:@"There's no branch named %@ to start it from",
                                                       AsText(target[@"base"]) ?: @""]
                                                    : @"There's no branch here to start a worktree from"};
        if (!Ask(repo, @[@"check-ref-format", @"--branch", name]))
            return @{@"why": [NSString stringWithFormat:@"Git can't name a branch %@: rename it", name]};
        if (LocalBranch(repo, name))
            return @{@"why": [NSString stringWithFormat:@"There's a branch named %@ already: pick it with #%@, or rename this one",
                              name, name]};
    }
    NSString *path = [[self folderFor:repo] stringByAppendingPathComponent:
                      [name stringByReplacingOccurrencesOfString:@"/" withString:@"-"]];
    if ([NSFileManager.defaultManager fileExistsAtPath:path])
        return @{@"why": [NSString stringWithFormat:@"Something's in %@ already", [Worktrees shown:path]]};
    return @{@"path": path, @"where": [Worktrees shown:path], @"name": name, @"base": base ?: NSNull.null};
}

- (NSDictionary *)make:(NSDictionary *)target in:(NSString *)folder {
    NSDictionary *free = [self check:target in:folder];
    if (free[@"why"]) return free;
    NSString *repo = RepoOf(folder), *path = free[@"path"], *name = free[@"name"], *base = AsText(free[@"base"]);
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent
                            withIntermediateDirectories:YES attributes:nil error:nil];
    // A new branch follows the one it starts from; a branch that's there keeps what it follows.
    NSString *command = base
        ? [NSString stringWithFormat:@"git worktree add --track -b %@ %@ %@", ShellWord(name), ShellWord(path), ShellWord(base)]
        : [NSString stringWithFormat:@"git worktree add %@ %@", ShellWord(path), ShellWord(name)];
    NSDictionary *run = RunInCheckout(command, repo, kMakeWait, YES, self.core.agentMarks);
    if (!run) return @{@"why": @"Git couldn't be run to make the worktree"};
    if ([run[@"timedOut"] boolValue]) return @{@"why": @"Git took too long to make the worktree"};
    if ([run[@"status"] intValue] != 0) {
        // Git says why in its last words: the line that starts "fatal:" or "error:", else its last line.
        NSString *said = [[NSString alloc] initWithData:run[@"out"] encoding:NSUTF8StringEncoding] ?: @"";
        NSString *why = nil, *last = nil;
        for (NSString *line in [said componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
            NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            for (NSString *prefix in @[@"fatal: ", @"error: "])
                if ([trimmed hasPrefix:prefix]) why = [trimmed substringFromIndex:prefix.length];
            if (trimmed.length) last = trimmed;
        }
        why = why ?: last;
        return @{@"why": [NSString stringWithFormat:@"Git didn't make the worktree%@", why.length
                          ? [@": " stringByAppendingString:Clip(why, 160)] : @""]};
    }
    return @{@"path": RealPath(path), @"where": [Worktrees shown:path], @"name": name, @"base": base ?: NSNull.null};
}

@end
