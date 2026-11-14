// Git: a checkout's branch, worktree, status and how much its work changes, and which git only reads.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Git.h"
#import "Processes.h"
#import "Files.h"
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

// Runs git, as RunTool does, once Apple's developer tools are installed: their own git, never /usr/bin/git, which
// without them offers to install them each time it's run (DeveloperToolsGit). Until then nothing runs, and it's nil as
// for a tool that couldn't start.
NSDictionary *RunGit(NSArray<NSString *> *arguments) {
    NSString *git = DeveloperToolsGit();
    return git ? RunTool(git, arguments, nil) : nil;
}

NSArray<NSString *> *GitReadOnlyCommands(void) {
    return @[@"status", @"log", @"diff", @"show"];
}

NSArray<NSString *> *GitReadOnlyNeeds(NSString *command) {
    return [command isEqual:@"status"] ? @[] : @[@"--no-ext-diff", @"--no-textconv"];
}

// The options each command may take, written in full.
static NSSet<NSString *> *ReadOnlyOptions(NSString *command) {
    NSArray *shown = @[@"--no-ext-diff", @"--no-textconv", @"--stat", @"--shortstat", @"--numstat", @"--name-only",
                       @"--name-status", @"--patch", @"-p", @"--no-patch", @"--summary", @"--no-color",
                       @"--color=never", @"-w", @"--ignore-all-space", @"--ignore-space-change", @"--word-diff",
                       @"--no-renames", @"-M", @"--find-renames", @"--compact-summary", @"--raw", @"--abbrev-commit",
                       @"--oneline", @"--decorate", @"--no-decorate", @"--full-index", @"--binary"];
    if ([command isEqual:@"status"])
        return [NSSet setWithArray:@[@"--short", @"-s", @"--branch", @"-b", @"--porcelain", @"--porcelain=v1",
                                     @"--porcelain=v2", @"--long", @"--untracked-files=no", @"--untracked-files=normal",
                                     @"--untracked-files=all", @"-uno", @"-unormal", @"-uall", @"--ignored",
                                     @"--no-renames", @"--ahead-behind", @"--no-ahead-behind", @"-z"]];
    if ([command isEqual:@"diff"])
        return [NSSet setWithArray:[shown arrayByAddingObjectsFromArray:@[@"--cached", @"--staged"]]];
    if ([command isEqual:@"log"])
        return [NSSet setWithArray:[shown arrayByAddingObjectsFromArray:@[@"--graph", @"--all", @"--reverse",
                                                                         @"--first-parent", @"--merges",
                                                                         @"--no-merges", @"--follow", @"-s"]]];
    if ([command isEqual:@"show"]) return [NSSet setWithArray:[shown arrayByAddingObject:@"-s"]];
    return [NSSet set];
}

static BOOL Digits(NSString *text) {
    return text.length && [text rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location
        == NSNotFound;
}

// Whether an option with a value is one that only reads: a count, a time, a name to look for, a diff's context, or a
// format that never asks for a signature (%G, which would run gpg).
static BOOL ReadOnlyValuedOption(NSString *option, NSString *command) {
    if ([command isEqual:@"status"]) return NO;
    if (([option hasPrefix:@"-U"] || [option hasPrefix:@"-n"]) && Digits([option substringFromIndex:2])) return YES;
    if ([option hasPrefix:@"-"] && Digits([option substringFromIndex:1])) return YES;
    NSRange equals = [option rangeOfString:@"="];
    if (equals.location == NSNotFound) return NO;
    NSString *name = [option substringToIndex:equals.location], *value = [option substringFromIndex:NSMaxRange(equals)];
    if ([@[@"--unified", @"--max-count", @"--skip"] containsObject:name]) return Digits(value);
    if ([@[@"--format", @"--pretty"] containsObject:name]) return ![value containsString:@"%G"];
    if ([command isEqual:@"diff"]) return [name isEqual:@"--diff-filter"];
    return [@[@"--since", @"--after", @"--until", @"--before", @"--author", @"--committer", @"--grep", @"--date",
              @"--diff-filter"] containsObject:name];
}

NSString *GitReadOnlyWhyNot(NSArray<NSString *> *arguments) {
    NSString *command = arguments.firstObject ?: @"";
    if (![GitReadOnlyCommands() containsObject:command])
        return [NSString stringWithFormat:@"git %@ isn't one that only reads", command];
    NSSet *options = ReadOnlyOptions(command);
    NSMutableSet *given = [NSMutableSet set];
    for (NSString *word in [arguments subarrayWithRange:NSMakeRange(1, arguments.count - 1)]) {
        if ([word isEqual:@"--"]) break;
        if (![word hasPrefix:@"-"]) continue;
        [given addObject:word];
        if (![options containsObject:word] && !ReadOnlyValuedOption(word, command))
            return [NSString stringWithFormat:@"git %@ may not take %@ here", command, word];
    }
    NSArray *needs = GitReadOnlyNeeds(command);
    if (![[NSSet setWithArray:needs] isSubsetOfSet:given])
        return [NSString stringWithFormat:@"git %@ needs %@, before any --", command,
                                          [needs componentsJoinedByString:@" "]];
    return nil;
}

static NSArray<NSArray<NSString *> *> *ReadOnlySettings(void) {
    return @[
        @[@"core.fsmonitor", @"false"], @[@"core.hooksPath", @"/dev/null"], @[@"core.pager", @"cat"],
        @[@"diff.external", @""], @[@"log.showSignature", @"false"], @[@"gpg.program", @"/usr/bin/false"],
        @[@"gpg.ssh.program", @"/usr/bin/false"], @[@"gpg.x509.program", @"/usr/bin/false"],
        // Never online: a partial clone fetches what it lacks from its remote, with ssh or a credential helper.
        @[@"protocol.allow", @"never"]];
}

NSArray<NSString *> *GitReadOnlyArguments(void) {
    NSMutableArray<NSString *> *arguments = [NSMutableArray array];
    for (NSArray<NSString *> *setting in ReadOnlySettings())
        [arguments addObjectsFromArray:@[@"-c", [NSString stringWithFormat:@"%@=%@", setting[0], setting[1]]]];
    [arguments addObjectsFromArray:@[@"--no-optional-locks", @"--literal-pathspecs", @"--no-pager"]];
    return arguments;
}

// A diff's options that print what's in files (its patch, a word diff, a binary patch, or a patch's context), and
// those that print only names, counts or ids instead.
static BOOL PrintsPatch(NSString *option) {
    return [@[@"-p", @"--patch", @"--word-diff", @"--binary"] containsObject:option] || [option hasPrefix:@"-U"]
        || [option hasPrefix:@"--unified="];
}

static BOOL PrintsNoPatch(NSString *option) {
    return [@[@"--stat", @"--shortstat", @"--numstat", @"--name-only", @"--name-status", @"--summary",
              @"--compact-summary", @"--raw", @"--no-patch", @"-s"] containsObject:option];
}

// The options that choose which commits or changes are shown, rather than how: kept when git is asked which files
// a command shows, so it's asked about the same ones.
static BOOL Chooses(NSString *option) {
    if ([@[@"--cached", @"--staged", @"--all", @"--reverse", @"--first-parent", @"--merges", @"--no-merges",
           @"--follow"] containsObject:option])
        return YES;
    if ([option hasPrefix:@"-n"] && Digits([option substringFromIndex:2])) return YES;
    if (Digits([option substringFromIndex:1])) return YES;
    NSRange equals = [option rangeOfString:@"="];
    return equals.location != NSNotFound
        && [@[@"--max-count", @"--skip", @"--since", @"--after", @"--until", @"--before", @"--author", @"--committer",
              @"--grep", @"--diff-filter"] containsObject:[option substringToIndex:equals.location]];
}

NSString *GitReadOnlyNotCommit(NSArray<NSString *> *arguments, NSString *folder) {
    NSArray<NSString *> *base = [@[@"-C", folder ?: @""] arrayByAddingObjectsFromArray:GitReadOnlyArguments()];
    for (NSUInteger i = 1; i < arguments.count; i++) {
        NSString *word = arguments[i];
        if ([word isEqual:@"--"]) break;
        if ([word hasPrefix:@"-"]) continue;
        // A word with a colon names what's at a commit: a file (HEAD:src/app.js), shown as itself and named in the
        // word, or a folder (HEAD:, HEAD:src), which git diff would print whole, file by file.
        BOOL atCommit = [word containsString:@":"];
        // Each end of a range (a..b, a...b).
        for (NSString *end in [[word stringByReplacingOccurrencesOfString:@"..." withString:@".."]
                               componentsSeparatedByString:@".."]) {
            if (!end.length) continue;
            if ([end hasPrefix:@"-"]) return word;
            // What's at a commit is asked as written: a suffix (HEAD:^{object}) would be read as part of its path.
            if (atCommit) {
                NSDictionary *type = RunGit([base arrayByAddingObjectsFromArray:@[@"cat-file", @"-t", end]]);
                if (!type) return word;
                if ([type[@"status"] intValue] != 0) continue;  // nothing there: a path, shown only as a change
                NSString *said = [[[NSString alloc] initWithData:type[@"out"] encoding:NSUTF8StringEncoding]
                                  stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                if (![said isEqual:@"blob"] && ![said isEqual:@"commit"]) return word;
                continue;
            }
            NSDictionary *object = RunGit([base arrayByAddingObjectsFromArray:@[@"rev-parse", @"--verify", @"-q",
                                           [end stringByAppendingString:@"^{object}"]]]);
            if (!object) return word;
            if ([object[@"status"] intValue] != 0) continue;  // no object: a path, which git shows only as a change
            NSDictionary *commit = RunGit([base arrayByAddingObjectsFromArray:@[@"rev-parse", @"--verify", @"-q",
                                           [end stringByAppendingString:@"^{commit}"]]]);
            if (!commit || [commit[@"status"] intValue] != 0) return word;
        }
    }
    return nil;
}

NSArray<NSString *> *GitReadOnlyShownFiles(NSArray<NSString *> *arguments, NSString *folder) {
    NSString *command = arguments.firstObject;
    if (![@[@"diff", @"log", @"show"] containsObject:command]) return @[];
    NSUInteger end = [arguments indexOfObject:@"--"];
    if (end == NSNotFound) end = arguments.count;
    NSMutableArray<NSString *> *asked = [NSMutableArray arrayWithObject:command];
    BOOL patch = NO, noPatch = NO, commits = NO, filesAtCommits = NO;
    for (NSString *word in [arguments subarrayWithRange:NSMakeRange(1, end - 1)]) {
        if ([word hasPrefix:@"-"]) {
            if (PrintsPatch(word)) patch = YES;
            else if (PrintsNoPatch(word)) noPatch = YES;
            else if (Chooses(word)) [asked addObject:word];
        } else if ([word containsString:@":"] && [command isEqual:@"show"]) {
            filesAtCommits = YES;  // shown only as itself, as its name says
        } else {
            // diff and log are asked about the very words given, files at commits too.
            commits = YES;
            [asked addObject:word];
        }
    }
    // log prints a patch only when asked; diff and show unless only names, counts or ids are; show of only files at
    // commits prints those files alone.
    BOOL prints = [command isEqual:@"log"] ? patch : patch || !noPatch;
    if (!prints || ([command isEqual:@"show"] && filesAtCommits && !commits)) return @[];
    [asked addObjectsFromArray:@[@"--name-only", @"--no-renames", @"-z"]];
    if (![command isEqual:@"diff"]) [asked addObject:@"--format="];
    [asked addObjectsFromArray:[arguments subarrayWithRange:NSMakeRange(end, arguments.count - end)]];
    NSDictionary *ran = RunGit([[@[@"-C", folder ?: @""] arrayByAddingObjectsFromArray:GitReadOnlyArguments()]
                                arrayByAddingObjectsFromArray:asked]);
    if (!ran || [ran[@"status"] intValue] != 0) return nil;
    NSString *out = [[NSString alloc] initWithData:ran[@"out"] encoding:NSUTF8StringEncoding];
    if (!out) return nil;
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    for (NSString *line in [out componentsSeparatedByCharactersInSet:
                            [NSCharacterSet characterSetWithCharactersInString:@"\n\0"]])
        if (line.length) [files addObject:line];
    return files;
}

NSDictionary<NSString *, NSString *> *GitReadOnlyEnvironment(NSDictionary<NSString *, NSString *> *base) {
    NSMutableDictionary *environment = [base mutableCopy] ?: [NSMutableDictionary dictionary];
    NSArray<NSArray<NSString *> *> *settings = ReadOnlySettings();
    environment[@"GIT_CONFIG_COUNT"] = @(settings.count).stringValue;
    [settings enumerateObjectsUsingBlock:^(NSArray<NSString *> *setting, NSUInteger i, BOOL *stop) {
        environment[[NSString stringWithFormat:@"GIT_CONFIG_KEY_%lu", (unsigned long)i]] = setting[0];
        environment[[NSString stringWithFormat:@"GIT_CONFIG_VALUE_%lu", (unsigned long)i]] = setting[1];
    }];
    // As Whozmove's own status runs: a plain `git status` writes the index under its lock, which would fail a commit
    // made in that checkout at that moment.
    environment[@"GIT_OPTIONAL_LOCKS"] = @"0";
    environment[@"GIT_PAGER"] = @"cat";
    environment[@"GIT_NO_LAZY_FETCH"] = @"1";
    environment[@"GIT_TERMINAL_PROMPT"] = @"0";
    // A pathspec is the file it names, never a pattern ('*.env') or magic (':(glob)'), so what's shown is what's named.
    environment[@"GIT_LITERAL_PATHSPECS"] = @"1";
    return environment;
}

// One of ReadOnlySettings' entries as git's -c takes it, so a setting kept there has that one place.
static NSString *ReadOnlySetting(NSString *key) {
    for (NSArray<NSString *> *setting in ReadOnlySettings())
        if ([setting[0] isEqual:key]) return [NSString stringWithFormat:@"%@=%@", setting[0], setting[1]];
    return nil;
}

NSArray<NSString *> *GitReading(NSString *root) {
    return @[@"--no-optional-locks", @"-c", ReadOnlySetting(@"core.fsmonitor"), @"-C", root];
}

// The branch and worktree of the checkout that holds `cwd`, read straight from its .git, without running git:
// {branch or detached, root, worktree, worktreeOf, mainRoot}, or nil outside a repo. Asked for every row every second,
// so its .git pointer and HEAD are read again only once they've changed.
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
            NSString *pointer = ReadTextKept(dotGit);
            NSRange tag = [pointer rangeOfString:@"gitdir:"];
            if (tag.location == NSNotFound) return nil;
            gitDir = [[pointer substringFromIndex:NSMaxRange(tag)] stringByTrimmingCharactersInSet:space];
            if (!gitDir.isAbsolutePath) gitDir = [dir stringByAppendingPathComponent:gitDir];
            gitDir = gitDir.stringByStandardizingPath;
            linkedWorktree = [gitDir.stringByDeletingLastPathComponent.lastPathComponent isEqualToString:@"worktrees"];
        }

        NSString *head = [ReadTextKept([gitDir stringByAppendingPathComponent:@"HEAD"])
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

NSString *ProjectRoot(NSString *folder) {
    NSDictionary *git = folder.length ? GitInfo(folder) : nil;
    return git[@"mainRoot"] ?: git[@"root"];
}

NSDictionary<NSString *, NSString *> *CheckoutsInFiles(NSString *repo) {
    NSString *own = nil, *common = nil, *root = ProjectRoot(repo);
    if (!root || !GitFolders(root, &own, &common)) return @{};
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSCharacterSet *space = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    NSMutableArray *folders = [NSMutableArray arrayWithObject:root];
    // Each linked worktree's record names its folder's .git file (gitdir); a folder taken away leaves its record until
    // git prunes it, so only one still there, and still naming this repo as its own, counts.
    NSString *records = [common stringByAppendingPathComponent:@"worktrees"];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:records error:nil] ?: @[]) {
        NSString *gitdir = [ReadTextKept([[records stringByAppendingPathComponent:name]
                                          stringByAppendingPathComponent:@"gitdir"]) stringByTrimmingCharactersInSet:space];
        if (gitdir.isAbsolutePath) [folders addObject:gitdir.stringByDeletingLastPathComponent];
    }
    for (NSString *folder in folders) {
        NSDictionary *git = GitInfo(folder);
        NSString *real = RealPath(folder);
        if (!git || !real || ![RealPath(git[@"root"]) isEqualToString:real]
            || ![RealPath(ProjectRoot(folder)) isEqualToString:RealPath(root)]) continue;
        // A folder on no branch (detached) has none to start a conversation on, as git lists the repo's folders.
        if ([git[@"branch"] isKindOfClass:NSString.class] && [git[@"branch"] length]) out[real] = git[@"branch"];
    }
    return out;
}

BOOL GitFolders(NSString *root, NSString **own, NSString **common) {
    NSCharacterSet *space = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    NSString *dotGit = [root stringByAppendingPathComponent:@".git"];
    BOOL isDir = NO;
    if (!root.length || ![NSFileManager.defaultManager fileExistsAtPath:dotGit isDirectory:&isDir]) return NO;
    NSString *mine = dotGit;
    if (!isDir) {  // a linked worktree or a submodule: its ".git" is a file naming the real git folder
        NSString *pointer = [NSString stringWithContentsOfFile:dotGit encoding:NSUTF8StringEncoding error:nil];
        NSRange tag = [pointer rangeOfString:@"gitdir:"];
        if (tag.location == NSNotFound) return NO;
        mine = [[pointer substringFromIndex:NSMaxRange(tag)] stringByTrimmingCharactersInSet:space];
        if (!mine.isAbsolutePath) mine = [root stringByAppendingPathComponent:mine];
        mine = mine.stringByStandardizingPath;
    }
    // A linked worktree's git folder names the one it shares in its "commondir" ("../..").
    NSString *shared = mine;
    NSString *commondir = [[NSString stringWithContentsOfFile:[mine stringByAppendingPathComponent:@"commondir"]
                                                     encoding:NSUTF8StringEncoding error:nil]
                           stringByTrimmingCharactersInSet:space];
    if (commondir.length)
        shared = (commondir.isAbsolutePath ? commondir : [mine stringByAppendingPathComponent:commondir])
                     .stringByStandardizingPath;
    if (own) *own = mine;
    if (common) *common = shared;
    return YES;
}

// Whether a ref (refs/remotes/origin/main, say) is in a repo's shared git folder, loose or packed, without running git.
static BOOL RefInFiles(NSString *common, NSString *ref, NSString *packed) {
    BOOL isDir = YES;
    if ([NSFileManager.defaultManager fileExistsAtPath:[common stringByAppendingPathComponent:ref] isDirectory:&isDir]
        && !isDir) return YES;
    return [packed rangeOfString:[NSString stringWithFormat:@" %@\n", ref]].location != NSNotFound;
}

NSString *BaseBranchInFiles(NSString *common, BOOL *local) {
    NSString *packed = [[NSString stringWithContentsOfFile:[common stringByAppendingPathComponent:@"packed-refs"]
                                                  encoding:NSUTF8StringEncoding error:nil] ?: @""
                        stringByAppendingString:@"\n"];
    // origin/HEAD is a symbolic ref, always kept loose: "ref: refs/remotes/origin/<name>".
    NSString *origin = [common stringByAppendingPathComponent:@"refs/remotes/origin/HEAD"];
    NSString *head = [[NSString stringWithContentsOfFile:origin encoding:NSUTF8StringEncoding error:nil]
                      stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSArray *names = [head hasPrefix:@"ref: refs/remotes/origin/"] ? @[[head substringFromIndex:25]]
                                                                  : @[@"main", @"master"];
    for (NSString *name in names) {
        if (RefInFiles(common, [@"refs/remotes/origin/" stringByAppendingString:name], packed)) {
            if (local) *local = NO;
            return name;
        }
        if (RefInFiles(common, [@"refs/heads/" stringByAppendingString:name], packed)) {
            if (local) *local = YES;
            return name;
        }
    }
    return nil;
}

BOOL BranchOnRemote(NSString *root, NSString *branch) {
    NSString *common = nil;
    // When the repo can't be read here, it can't be told, so it's taken to be there.
    if (!branch.length || !GitFolders(root, NULL, &common)) return YES;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *remotes = [common stringByAppendingPathComponent:@"refs/remotes"];
    for (NSString *remote in [fm contentsOfDirectoryAtPath:remotes error:nil]) {
        BOOL isDir = YES;
        NSString *ref = [[remotes stringByAppendingPathComponent:remote] stringByAppendingPathComponent:branch];
        if ([fm fileExistsAtPath:ref isDirectory:&isDir] && !isDir) return YES;
    }
    // Refs git has packed into one file: "<hash> refs/remotes/<remote>/<branch>".
    NSString *packed = [NSString stringWithContentsOfFile:[common stringByAppendingPathComponent:@"packed-refs"]
                                                 encoding:NSUTF8StringEncoding error:nil];
    for (NSString *line in [packed componentsSeparatedByString:@"\n"]) {
        NSRange gap = [line rangeOfString:@" refs/remotes/"];
        if (gap.location == NSNotFound) continue;
        NSString *named = [line substringFromIndex:NSMaxRange(gap)];
        NSRange slash = [named rangeOfString:@"/"];
        if (slash.location != NSNotFound && [[named substringFromIndex:NSMaxRange(slash)] isEqualToString:branch])
            return YES;
    }
    return NO;
}

// A checkout's state from `git status --porcelain=v2 -z --branch`: {changes, ahead, behind, upstream, remotes}, and how
// the changed files split between staged and not (filesStaged: all their changes staged; filesPartly: staged, then
// changed again, so part of their changes are staged; filesUnstaged: none staged, or in conflict), or nil. The number
// of remotes matters because a commit in a repo with none has nowhere to go, so it's finished. Untracked files are left out here
// (FetchChangeCounts counts them), or build output and scratch files would make nearly every repo look like work in
// progress. It runs without optional locks: a plain `git status` refreshes the index under index.lock, and an agent
// committing at that moment would fail. `remoteNames` are the repo's remotes as RemoteNames last said them, which
// hardly ever change, or nil to ask git; they're given back in the state as `remoteNames`, to keep, unless git couldn't
// say them. Blocking.
NSDictionary *FetchCheckoutState(NSString *root, NSString *remoteNames) {
    NSArray *status = @[@"status", @"--porcelain=v2", @"-z", @"--branch", @"--untracked-files=no"];
    NSDictionary *run = RunGit([GitReading(root) arrayByAddingObjectsFromArray:status]);
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
    NSString *known = remoteNames ?: RemoteNames(root), *names = known ?: @"";
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
    NSMutableDictionary *state = [@{@"changes": @(changes), @"ahead": @(ahead), @"behind": @(behind),
                                    @"upstream": @(upstream), @"remotes": @(remotes), @"filesStaged": @(counted[0]),
                                    @"filesPartly": @(counted[1]), @"filesUnstaged": @(counted[2])} mutableCopy];
    if (known) state[@"remoteNames"] = known;
    return state;
}

NSString *RemoteNames(NSString *root) {
    NSDictionary *remote = RunGit([GitReading(root) arrayByAddingObject:@"remote"]);
    if (!remote || [remote[@"status"] intValue] != 0) return nil;
    return [[NSString alloc] initWithData:remote[@"out"] encoding:NSUTF8StringEncoding];
}

// What git answers in a checkout, trimmed, or nil when it says no (exits 1, as `--verify --quiet` does for a ref that
// isn't there) or fails; `failed` (if given) is set when it couldn't answer at all, there or in its answer.
static NSString *Answer(NSString *root, NSArray<NSString *> *arguments, BOOL *failed) {
    NSMutableArray *all = [GitReading(root) mutableCopy];
    [all addObjectsFromArray:arguments];
    NSDictionary *run = RunGit(all);
    int status = run ? [run[@"status"] intValue] : -1;
    if (status != 0 && status != 1 && failed) *failed = YES;
    if (status != 0) return nil;
    NSString *text = [[NSString alloc] initWithData:run[@"out"] encoding:NSUTF8StringEncoding];
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

NSArray<NSString *> *BaseBranch(NSString *root) {
    BOOL failed = NO;
    NSString *head = Answer(root, @[@"symbolic-ref", @"--quiet", @"--short", @"refs/remotes/origin/HEAD"], &failed);
    NSArray *names = [head hasPrefix:@"origin/"] ? @[[head substringFromIndex:7]] : @[@"main", @"master"];
    for (NSString *name in names)
        for (NSString *ref in @[[@"origin/" stringByAppendingString:name], name])
            if (Answer(root, @[@"rev-parse", @"--verify", @"--quiet", [ref stringByAppendingString:@"^{commit}"]],
                       &failed))
                return @[name, ref];
    return failed ? nil : @[];
}

// The repo's base branch as this Mac has it: the local branch named as GitHub's copy names its own (origin/HEAD), else
// main or master, else the branch its main checkout is on; nil with none. A new worktree starts from it and follows
// it, so it starts with everything there, committed here or not yet on GitHub. Blocking.
NSString *LocalBaseBranch(NSString *root) {
    NSString *(^git)(NSArray<NSString *> *) = ^NSString *(NSArray<NSString *> *arguments) {
        NSMutableArray *all = [GitReading(root) mutableCopy];
        [all addObjectsFromArray:arguments];
        NSDictionary *run = RunGit(all);
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

// A checkout's base branch, how many commits the branch has that the base doesn't, how many new files there are, and
// when its last commit was made (git's commit time, in seconds): {base, aheadOfBase, newFiles, headAt}, or nil. The
// base is the branch GitHub's copy points at (origin/HEAD), else main or master: GitHub's copy of it if there is one,
// else the local one. Without any, the work is measured from the last commit. `baseBranch` is BaseBranch's last answer,
// which hardly ever changes, or nil to ask git; it's given back as `baseBranch`, to keep, unless git couldn't say it,
// with the ref it names as `baseRef`. Blocking.
NSDictionary *FetchChangeCounts(NSString *root, NSArray<NSString *> *baseBranch) {
    // What git prints, as it prints it (a name that isn't UTF-8 read as Latin-1), or nil when it fails.
    NSString *(^output)(NSArray<NSString *> *) = ^NSString *(NSArray<NSString *> *arguments) {
        NSMutableArray *all = [GitReading(root) mutableCopy];
        [all addObjectsFromArray:arguments];
        NSDictionary *run = RunGit(all);
        if (!run || [run[@"status"] intValue] != 0) return nil;
        return [[NSString alloc] initWithData:run[@"out"] encoding:NSUTF8StringEncoding]
            ?: [[NSString alloc] initWithData:run[@"out"] encoding:NSISOLatin1StringEncoding];
    };
    // An answer, trimmed. A list of names (split on zero bytes) is read untrimmed, as a name can start with a space.
    NSString *(^git)(NSArray<NSString *> *) = ^NSString *(NSArray<NSString *> *arguments) {
        return [output(arguments) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    };
    NSArray *found = baseBranch ?: BaseBranch(root);
    NSString *base = found.count > 1 ? found[0] : nil, *baseRef = found.count > 1 ? found[1] : nil;
    // The last commit's time, which a code review's note on the row is measured against: a commit after it, and edits
    // after that, are new work. Without the signature check that git's log.showSignature would print before it.
    NSString *headAt = git(@[@"log", @"--no-show-signature", @"-1", @"--format=%ct", @"HEAD"]);
    if (!headAt.length) return nil;  // no commit yet, or not a checkout
    NSString *others = output(@[@"ls-files", @"--others", @"--exclude-standard", @"-z"]) ?: @"";
    NSInteger newFiles = 0;
    for (NSString *path in [others componentsSeparatedByString:@"\0"])
        if (path.length) newFiles++;
    NSMutableDictionary *counts = [@{@"newFiles": @(newFiles), @"headAt": @(headAt.longLongValue)} mutableCopy];
    if (found) counts[@"baseBranch"] = found;
    if (base) {
        counts[@"base"] = base;
        counts[@"baseRef"] = baseRef;
        counts[@"aheadOfBase"] = @([git(@[@"rev-list", @"--count", [baseRef stringByAppendingString:@"..HEAD"]])
                                    integerValue]);
    }
    return counts;
}

// The branches GitHub's copy of a checkout's repo has, as this Mac last fetched them (origin's), by name, sorted, or nil
// when git can't say. Blocking.
NSArray<NSString *> *RemoteBranches(NSString *root) {
    NSDictionary *run = RunGit([GitReading(root) arrayByAddingObjectsFromArray:@[@"for-each-ref",
                                                                                 @"--format=%(refname:short)",
                                                                                 @"refs/remotes/origin"]]);
    if (!run || [run[@"status"] intValue] != 0) return nil;
    NSString *text = [[NSString alloc] initWithData:run[@"out"] encoding:NSUTF8StringEncoding] ?: @"";
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByString:@"\n"])
        // origin/HEAD names the branch GitHub's copy points at, not one of its own.
        if ([line hasPrefix:@"origin/"] && ![line isEqualToString:@"origin/HEAD"])
            [names addObject:[line substringFromIndex:7]];
    return [names sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}
