// Deploys: Deploy, a next step for any project: the command you've set for each project, the one Whozmove suggests
// before you have, running it on this Mac, and how each folder's last run went.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// What Deploy runs is yours to say, once per project: the panel suggests a command from the project's own files, and
// you confirm it twice before it's saved (in deploy.json in Whozmove's own folder, never in the project, so nothing a
// repo or an agent writes can set it). Each run goes detached from the panel, with its output in a log and its exit
// status in a file beside it, under deploys/<folder's hash>/, so it carries on if it restarts the panel (as Whozmove's
// own deploy does), and the panel reads how it went whenever it looks. Each project's build in place, the last run
// that went through, is kept in in-place.json, for other modules to read (BuildsInPlace), and the port each checkout's
// build gets in $PORT in ports.json.
#import "Deploys.h"
#import "Page.h"
#import "Row.h"
#import "Log.h"
#import "Files.h"
#import "Git.h"
#import "Processes.h"
#import "Text.h"
#import "Work.h"
#import "Links.h"
#include <CommonCrypto/CommonDigest.h>
#include <fcntl.h>
#include <signal.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

NSString *DeployProject(Row *row) {
    NSDictionary *git = row.workGit ?: row.git;
    return git[@"mainRoot"] ?: git[@"root"] ?: row.cwd;
}

NSString *DeployFolder(Row *row) {
    NSDictionary *git = row.workGit ?: row.git;
    return git[@"root"] ?: row.cwd;
}

#pragma mark What a command runs

// Whether text looks as if it could reach production: it names prod or production, or it's a deploy tool's command
// for a live site, a cluster, infrastructure, or a push. The one list: Whozmove never suggests a command that does
// (SuggestDeploy), and the set-up card asks the app (CheckDeploy) before it warns about one.
static BOOL LooksLikeProduction(NSString *text) {
    static NSArray<NSRegularExpression *> *patterns;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *compiled = [NSMutableArray array];
        for (NSString *pattern in @[@"(?i)\\bprod(uction)?\\b", @"\\bfly(ctl)?\\s+deploy\\b",
                                    @"\\bvercel\\b.*--prod\\b", @"\\bnetlify\\s+deploy\\b.*--prod\\b", @"\\bheroku\\b",
                                    @"\\b(kubectl|helm|terraform)\\b", @"\\bgit\\s+push\\b"])
            [compiled addObject:[NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil]];
        patterns = compiled;
    });
    for (NSRegularExpression *pattern in patterns)
        if (text.length && [pattern firstMatchInString:text options:0 range:NSMakeRange(0, text.length)]) return YES;
    return NO;
}

// A Makefile's rules, as far as what a target runs goes: {target: {deps, recipe}}, with the first target (the one
// make runs when it's given none) under @"". Lines continued with a backslash are read as one; a recipe line is one
// starting with a tab after a rule, or what follows a ";" on the rule's own line. No variables, includes or patterns.
static NSDictionary<NSString *, NSDictionary *> *MakeRules(NSString *makefile) {
    NSString *text = [makefile stringByReplacingOccurrencesOfString:@"\\\n" withString:@" "];
    NSRegularExpression *rule = [NSRegularExpression
        regularExpressionWithPattern:@"^([^\\s#:=][^#:=]*?)\\s*::?(?!=)([^;#]*)(?:;(.*)|#.*)?$" options:0 error:nil];
    NSMutableDictionary<NSString *, NSMutableDictionary *> *rules = [NSMutableDictionary dictionary];
    NSArray<NSString *> *current = nil;
    NSString *first = nil;
    NSCharacterSet *space = NSCharacterSet.whitespaceCharacterSet;
    void (^add)(NSArray<NSString *> *, NSString *) = ^(NSArray<NSString *> *targets, NSString *line) {
        line = [line stringByTrimmingCharactersInSet:space];
        if (line.length) for (NSString *target in targets) [rules[target][@"recipe"] addObject:line];
    };
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:@"\t"]) {
            if (current) add(current, line);
            continue;
        }
        NSString *trimmed = [line stringByTrimmingCharactersInSet:space];
        if (!trimmed.length || [trimmed hasPrefix:@"#"]) continue;  // a recipe goes on past these
        NSTextCheckingResult *match = [rule firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        if (!match) {
            current = nil;  // a variable, a directive: the recipe before it has ended
            continue;
        }
        NSPredicate *named = [NSPredicate predicateWithFormat:@"length > 0"];
        NSArray<NSString *> *targets = [[[line substringWithRange:[match rangeAtIndex:1]]
                                         componentsSeparatedByCharactersInSet:space] filteredArrayUsingPredicate:named];
        NSArray<NSString *> *deps = [[[line substringWithRange:[match rangeAtIndex:2]]
                                      componentsSeparatedByCharactersInSet:space] filteredArrayUsingPredicate:named];
        for (NSString *target in targets) {
            rules[target] = rules[target] ?: [@{@"deps": [NSMutableArray array], @"recipe": [NSMutableArray array]}
                                              mutableCopy];
            [rules[target][@"deps"] addObjectsFromArray:deps];
            if (!first && ![target hasPrefix:@"."]) first = target;
        }
        current = targets;
        NSRange sameLine = [match rangeAtIndex:3];  // a recipe after ";"
        if (sameLine.location != NSNotFound) add(targets, [line substringWithRange:sameLine]);
    }
    if (first) rules[@""] = rules[first];
    return rules;
}

// A target's recipe lines, after those of the targets it depends on (as make runs them), each target once.
static void AddRecipe(NSDictionary<NSString *, NSDictionary *> *rules, NSString *target, NSMutableSet *seen,
                      NSMutableArray<NSString *> *runs, NSUInteger depth) {
    NSDictionary *found = rules[target];
    if (!found || depth > 10 || [seen containsObject:target]) return;
    [seen addObject:target];
    for (NSString *dep in found[@"deps"]) AddRecipe(rules, dep, seen, runs, depth + 1);
    [runs addObjectsFromArray:found[@"recipe"]];
}

// What's at a name, from a folder (`here`) within a checkout (`root`), as the check sees it: {state, path}, `state`
// being "file" (a regular file inside the checkout, links followed), "missing", "outside" (it leads out of the
// checkout), "other" (a folder, a pipe, a device) or "unreadable" (a link to nothing, say).
static NSDictionary *LookFrom(NSString *root, NSString *here, NSString *name) {
    if (!root.length || !here.length || !name.length) return @{@"state": @"missing"};
    NSString *path = [name isAbsolutePath] ? name : [here stringByAppendingPathComponent:name];
    struct stat info;
    if (lstat(path.fileSystemRepresentation, &info) != 0) return @{@"state": @"missing"};
    root = RealPath(root);
    NSString *real = RealPath(path);
    if (!root.length || ![real hasPrefix:[root stringByAppendingString:@"/"]]) return @{@"state": @"outside"};
    if (stat(real.fileSystemRepresentation, &info) != 0) return @{@"state": @"unreadable"};
    if (!S_ISREG(info.st_mode)) return @{@"state": @"other"};
    return @{@"state": @"file", @"path": real};
}

static NSDictionary *Look(NSString *folder, NSString *name) {
    return LookFrom(folder, folder, name);
}

// Opens a regular file to read, never blocking on what it turns out to be: -1 for anything else.
static int OpenFile(NSString *path) {
    int fd = open(path.fileSystemRepresentation, O_RDONLY | O_NONBLOCK);
    struct stat info;
    if (fd >= 0 && (fstat(fd, &info) != 0 || !S_ISREG(info.st_mode))) {
        close(fd);
        return -1;
    }
    return fd;
}

// The lock files a package runner keeps, each with the install that never rewrites it, in the order one is chosen
// when a checkout has several (npm takes npm-shrinkwrap.json over package-lock.json). One list, for what an install
// reads (WhatRuns) and what Install First runs (DeployInstallWords). Yarn 1 takes --frozen-lockfile (YarnOne).
static NSArray<NSArray<NSString *> *> *LockFiles(void) {
    return @[@[@"pnpm-lock.yaml", @"pnpm install --frozen-lockfile"], @[@"yarn.lock", @"yarn install --immutable"],
             @[@"bun.lock", @"bun install --frozen-lockfile"], @[@"bun.lockb", @"bun install --frozen-lockfile"],
             @[@"npm-shrinkwrap.json", @"npm ci"], @[@"package-lock.json", @"npm ci"]];
}

// Whether a yarn.lock is Yarn 1's, which says "# yarn lockfile v1" in its first lines: read as any project file is,
// never blocking (OpenFile), only its first 512 bytes. One that can't be read is taken for a later Yarn's.
static BOOL YarnOne(NSString *path) {
    int fd = OpenFile(path);
    if (fd < 0) return NO;
    char head[512];
    ssize_t got = read(fd, head, sizeof head);
    close(fd);
    if (got <= 0) return NO;
    // A character cut at the 512th byte would make it no UTF-8, so then it's read byte for byte.
    NSString *text = [[NSString alloc] initWithBytes:head length:(NSUInteger)got encoding:NSUTF8StringEncoding]
        ?: [[NSString alloc] initWithBytes:head length:(NSUInteger)got encoding:NSISOLatin1StringEncoding];
    return [text containsString:@"yarn lockfile v1"];
}

// A file's bytes as their SHA-256, read a piece at a time, however big; nil if it can't be read.
static NSString *FileHash(NSString *path) {
    int fd = OpenFile(path);
    if (fd < 0) return nil;
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    uint8_t piece[65536];
    ssize_t got;
    while ((got = read(fd, piece, sizeof piece)) > 0) CC_SHA256_Update(&context, piece, (CC_LONG)got);
    close(fd);
    if (got < 0) return nil;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    NSMutableString *hex = [NSMutableString string];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

// A file's text, to follow what it calls and look for production in it: up to 1MB, as UTF-8, or byte for byte as
// Latin-1 when it isn't. Nil when it's bigger, or can't be read.
static NSString *FileText(NSString *path) {
    int fd = OpenFile(path);
    if (fd < 0) return nil;
    NSMutableData *data = [NSMutableData dataWithLength:(1 << 20) + 1];
    ssize_t got = read(fd, data.mutableBytes, data.length), more;
    while (got >= 0 && (NSUInteger)got < data.length
           && (more = read(fd, (uint8_t *)data.mutableBytes + got, data.length - (NSUInteger)got)) > 0)
        got += more;
    close(fd);
    if (got < 0 || (NSUInteger)got > (1 << 20)) return nil;
    data.length = (NSUInteger)got;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
        ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
}

// A project's package scripts, {name: text}, from a package.json's text, or empty.
static NSDictionary<NSString *, NSString *> *ScriptsIn(NSString *text) {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *package = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSDictionary *scripts = [package isKindOfClass:NSDictionary.class] ? package[@"scripts"] : nil;
    NSMutableDictionary *found = [NSMutableDictionary dictionary];
    if ([scripts isKindOfClass:NSDictionary.class])
        for (NSString *name in scripts)
            if ([name isKindOfClass:NSString.class] && [scripts[name] isKindOfClass:NSString.class])
                found[name] = scripts[name];
    return found;
}

// A file in a folder, read as the suggestion reads it (a regular file inside the folder, up to 1MB), or nil.
static NSString *FileIn(NSString *folder, NSString *name) {
    NSDictionary *seen = Look(folder, name);
    return [seen[@"state"] isEqual:@"file"] ? FileText(seen[@"path"]) : nil;
}

// How deep scripts may call each other, and how much of what a command runs the card shows.
static const NSUInteger kRunsDepth = 6, kRunsShown = 20000;

// What a command really runs in a folder, as far as Whozmove can follow it, in the order it would run: {lines, files,
// texts, ran, unsure, others}. `lines` are each package script (as "name: text", with its pre- and post- scripts, for
// every runner, and npm's start, test, stop and restart, and the install scripts an install runs), each Makefile
// target's recipe after those it depends on, and each file in the folder it runs (a script run as written, sourced, or
// given to sh, node, python and the like, every word of which that's a file counts), with what each of those calls in
// turn, up to 6 deep, and what `sh -c` runs, each from the folder it runs in (after a cd, pushd or make -C into a folder
// of the checkout; one it can't follow, inside ( ) or in a sourced script ends what's followed of that line), a
// runner's package.json being the nearest at or above that folder, as the runner finds it. `files` is each file that
// decides it (package.json whenever a runner is
// named, with the runners' settings files and the yarn they name, and an install's lockfile; the Makefile make would
// read and all it includes; each file run), by name, as the SHA-256 of its bytes;
// `texts` the text of each file it runs, to look for production in. `unsure` says what it can't follow or can't check:
// a runner or make pointed at another folder or package, a runner's word it doesn't know, an include named by a
// variable, calls deeper than 6, and a file it depends on that's outside the checkout, isn't a plain file or can't be
// read, or a cd it can't follow. `others` are the programs it runs whose own files decide what they do, and what the
// files it gives an interpreter load, which aren't checked. Commands are split at && || ; | & ( ) and new lines, and
// words at spaces, outside quotes, redirections left out, after any VAR=value words, and env, exec, nohup, time,
// command and cross-env. Blocking: it reads the project's files.
static void Follow(NSString *folder, NSString *command, NSUInteger depth, NSMutableDictionary *what);

static void AddUnsure(NSMutableDictionary *what, NSString *why) {
    if (![what[@"unsure"] containsObject:why]) [what[@"unsure"] addObject:why];
}

// A file's name as the card says it: from the checkout's top folder (web/package.json), whichever folder it's named
// from.
static NSString *Label(NSDictionary *what, NSString *here, NSString *name) {
    // Its folder with links resolved, as the checkout's is, and its own name as written.
    NSString *path = [name isAbsolutePath] ? name : [here stringByAppendingPathComponent:name];
    NSString *within = RealPath(path.stringByDeletingLastPathComponent);
    path = within.length ? [within stringByAppendingPathComponent:path.lastPathComponent] : path;
    NSString *top = [what[@"root"] stringByAppendingString:@"/"];
    if ([path hasPrefix:top]) return [path substringFromIndex:top.length];
    return [name hasPrefix:@"./"] ? [name substringFromIndex:2] : name;
}

// Where `cd <target>` (or pushd, or make -C: `how`) goes from `here`: a folder inside the checkout, or nil, said in
// `unsure`, for anywhere else or anywhere the check can't tell (a variable, `-`, home, a folder out of the checkout).
static NSString *Enter(NSMutableDictionary *what, NSString *here, NSString *how, NSString *target) {
    if (target.length && ![target hasPrefix:@"-"] && ![target hasPrefix:@"~"] && ![target containsString:@"$"]
        && ![target containsString:@"`"]) {
        NSString *path = RealPath([target isAbsolutePath] ? target : [here stringByAppendingPathComponent:target]);
        BOOL folder = NO;
        if (path.length && ([path isEqual:what[@"root"]] || [path hasPrefix:[what[@"root"] stringByAppendingString:@"/"]])
            && [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&folder] && folder)
            return path;
    }
    AddUnsure(what, [NSString stringWithFormat:@"it runs %@ %@, and Whozmove can't follow it there", how,
                                               target ?: @""]);
    return nil;
}

// A file the command depends on, checked: its bytes' SHA-256 kept under `label`, and its text returned to follow
// (@"" when it's too big to follow). Nil, with nothing kept, when there's nothing there; nil, and said in `unsure`,
// when there's something there the check can't read.
static NSString *Track(NSString *here, NSString *name, NSString *label, NSMutableDictionary *what) {
    label = label ?: Label(what, here, name);
    NSDictionary *seen = LookFrom(what[@"root"], here, name);
    NSString *state = seen[@"state"];
    if ([state isEqual:@"missing"]) return nil;
    NSString *hash = [state isEqual:@"file"] ? FileHash(seen[@"path"]) : nil;
    if (!hash) {
        NSString *why = [state isEqual:@"outside"] ? @"is outside this checkout"
            : [state isEqual:@"other"] ? @"isn't a plain file" : @"can't be read";
        AddUnsure(what, [NSString stringWithFormat:@"%@ %@, so Whozmove can't check it", label, why]);
        return nil;
    }
    what[@"files"][label] = hash;
    NSString *text = FileText(seen[@"path"]);
    if (!text) {
        AddUnsure(what, [NSString stringWithFormat:@"%@ is over 1MB, so Whozmove checks it but doesn't follow what it "
                                                   @"calls", label]);
        return @"";
    }
    return text;
}

// A command split as a shell would split it, as far as the check needs: its commands, each a list of words, quotes
// taken off, comments and redirections (`> log`, `2>&1`, `&> log`, `< in`) left out, and where a ( opens and a )
// closes marked, each as a command of its own. A `$(…)` or a backquoted part stays in its word, whole.
static NSArray<NSArray<NSString *> *> *Segments(NSString *command) {
    NSMutableArray<NSArray<NSString *> *> *segments = [NSMutableArray array];
    NSMutableArray<NSString *> *words = [NSMutableArray array];
    __block NSMutableString *word = nil;
    __block BOOL redirected = NO;  // the next word is where output goes, or input comes from
    void (^endWord)(void) = ^{
        if (word && !redirected) [words addObject:word];
        if (word) redirected = NO;
        word = nil;
    };
    void (^endSegment)(void) = ^{
        endWord();
        redirected = NO;
        if (words.count) [segments addObject:[words copy]];
        [words removeAllObjects];
    };
    unichar quote = 0;
    NSUInteger length = command.length;
    for (NSUInteger i = 0; i < length; i++) {
        unichar c = [command characterAtIndex:i];
        if (quote) {
            if (c == quote) quote = 0;
            else if (c == '\\' && quote == '"' && i + 1 < length) [word appendFormat:@"%C", [command characterAtIndex:++i]];
            else [word appendFormat:@"%C", c];
            continue;
        }
        if (c == '\'' || c == '"') {
            quote = c;
            word = word ?: [NSMutableString string];
        } else if (c == '\\' && i + 1 < length) {
            word = word ?: [NSMutableString string];
            [word appendFormat:@"%C", [command characterAtIndex:++i]];
        } else if ((c == '$' && i + 1 < length && [command characterAtIndex:i + 1] == '(') || c == '`') {
            // Kept whole: what it runs isn't followed, but it's in the script's text, which is checked.
            word = word ?: [NSMutableString string];
            NSUInteger depth = 0, start = i;
            for (; i < length; i++) {
                unichar d = [command characterAtIndex:i];
                if (c == '`' && i > start && d == '`') break;
                if (c != '`' && d == '(') depth++;
                if (c != '`' && d == ')' && --depth == 0) break;
            }
            [word appendString:[command substringWithRange:NSMakeRange(start, MIN(i, length - 1) - start + 1)]];
        } else if (c == '#' && !word) {
            // A comment, to the line's end (a script's first line too).
            while (i + 1 < length && [command characterAtIndex:i + 1] != '\n') i++;
        } else if (c == '<' || c == '>' || (c == '&' && i + 1 < length && [command characterAtIndex:i + 1] == '>')) {
            // A redirection: the file descriptor before it (2>) goes, and so does the word after it, unless it's
            // another descriptor (>&1).
            if (word && [word rangeOfString:@"^[0-9]+$" options:NSRegularExpressionSearch].location != NSNotFound)
                word = nil;
            endWord();
            while (i + 1 < length && [@"<>&" containsString:[command substringWithRange:NSMakeRange(i + 1, 1)]]) i++;
            unichar last = [command characterAtIndex:i];
            if (last == '&' && i + 1 < length && isdigit([command characterAtIndex:i + 1])) {
                while (i + 1 < length && isdigit([command characterAtIndex:i + 1])) i++;
            } else {
                redirected = YES;
            }
        } else if (c == ' ' || c == '\t') {
            endWord();
        } else if (c == '\n' || c == ';' || c == '&' || c == '|' || c == '(' || c == ')') {
            endSegment();
            if (c == '(' || c == ')') [segments addObject:@[[NSString stringWithFormat:@"%C", c]]];
        } else {
            word = word ?: [NSMutableString string];
            [word appendFormat:@"%C", c];
        }
    }
    endSegment();
    return segments;
}

// A package runner's script, with what it calls: once each.
static void AddScript(NSString *folder, NSDictionary<NSString *, NSString *> *scripts, NSString *name,
                      NSUInteger depth, NSMutableDictionary *what) {
    NSString *key = [NSString stringWithFormat:@"script %@ %@", folder, name];  // each package's own
    if (!scripts[name] || [what[@"seen"] containsObject:key]) return;
    [what[@"seen"] addObject:key];
    // A package in a folder below the top one says which ("dev in web: next dev").
    NSString *package = Label(what, folder, @"package.json").stringByDeletingLastPathComponent;
    [what[@"lines"] addObject:[NSString stringWithFormat:@"%@%@: %@", name,
                               package.length ? [@" in " stringByAppendingString:package] : @"", scripts[name]]];
    Follow(folder, scripts[name], depth + 1, what);
}

// A file in the checkout a command runs (`with` the interpreter it's given to, or nil when it's run as written):
// checked, whole, and for a shell script (sh, bash or zsh, by the interpreter, its first line or its name), followed.
static void AddFile(NSString *folder, NSString *path, NSString *with, NSUInteger depth, NSMutableDictionary *what) {
    NSString *name = Label(what, folder, path);
    if ([what[@"ran"] containsObject:name]) return;
    [what[@"ran"] addObject:name];
    NSString *text = Track(folder, path, name, what);
    if (!text) return;
    what[@"texts"][name] = text;
    NSUInteger lines = [text componentsSeparatedByString:@"\n"].count - ([text hasSuffix:@"\n"] ? 1 : 0);
    [what[@"lines"] addObject:[NSString stringWithFormat:@"%@%@ (the file, %lu line%@)",
                               with ? [with stringByAppendingString:@" "] : @"", name, (unsigned long)lines,
                               lines == 1 ? @"" : @"s"]];
    NSString *first = [text componentsSeparatedByString:@"\n"][0];
    BOOL shell = with ? [@[@"sh", @"bash", @"zsh", @"source"] containsObject:with]
                      : [name hasSuffix:@".sh"] || ([first hasPrefix:@"#!"]
                                                    && [first rangeOfString:@"\\b(ba|z)?sh\\b"
                                                                    options:NSRegularExpressionSearch].location
                                                           != NSNotFound);
    if (!shell) return;
    BOOL sourced = [with isEqual:@"source"];
    if (sourced) what[@"sourced"] = @([what[@"sourced"] intValue] + 1);
    Follow(folder, text, depth + 1, what);
    if (sourced) what[@"sourced"] = @([what[@"sourced"] intValue] - 1);
}

// What a package runner (npm, pnpm, yarn, bun) runs from its words after the runner's own name. Its package.json is
// checked whole whatever it runs, so a change to any script asks again.
static void FollowRunner(NSString *folder, NSString *tool, NSArray<NSString *> *words, NSUInteger depth,
                         NSMutableDictionary *what) {
    // The nearest package.json at or above the folder, as the runners find it: within the checkout, or said when the
    // nearest is above it, which isn't checked.
    NSString *root = what[@"root"], *package = folder;
    while (package && [LookFrom(root, package, @"package.json")[@"state"] isEqual:@"missing"])
        package = [package isEqual:root] || ![package hasPrefix:root] ? nil : package.stringByDeletingLastPathComponent;
    if (!package) {
        for (NSString *up = root.stringByDeletingLastPathComponent; up.length > 1; up = up.stringByDeletingLastPathComponent)
            if ([NSFileManager.defaultManager fileExistsAtPath:[up stringByAppendingPathComponent:@"package.json"]]) {
                AddUnsure(what, [NSString stringWithFormat:@"the package.json %@ would read is outside this checkout",
                                                           tool]);
                return;
            }
    }
    NSDictionary<NSString *, NSString *> *scripts = package ? ScriptsIn(Track(package, @"package.json", nil, what)) : @{};
    NSString *packageLabel = package ? Label(what, package, @"package.json") : nil;
    // What the runners read besides package.json that changes what they run, where they look for it, the package's
    // folder and the checkout's top: their settings (.npmrc, which can set node's options or the shell scripts run in;
    // .yarnrc; bunfig.toml), pnpm's hooks, yarn's Plug'n'Play loaders, and pnpm's workspace at the top; .yarnrc.yml in
    // each folder from the package's up to the top, as yarn reads them all; and the files those name to run: the yarn
    // that yarnPath or yarn-path names, yarn's plugins, and bun's preloads. Anything else they may read, the card says
    // isn't checked.
    NSArray<NSString *> *places = [[NSOrderedSet orderedSetWithArray:@[package ?: folder, root]] array];
    NSMutableArray<NSString *> *upward = [NSMutableArray array];
    for (NSString *at = package ?: folder; at; at = [at isEqual:root] || ![at hasPrefix:root] ? nil
                                                    : at.stringByDeletingLastPathComponent)
        [upward addObject:at];
    NSMutableArray<NSArray *> *settings = [NSMutableArray array];  // [folder, name]
    for (NSString *at in places)
        for (NSString *name in @[@".npmrc", @".yarnrc", @".pnpmfile.cjs", @".pnp.cjs", @".pnp.loader.mjs",
                                 @"bunfig.toml"])
            [settings addObject:@[at, name]];
    for (NSString *at in upward) [settings addObject:@[at, @".yarnrc.yml"]];
    [settings addObject:@[root, @"pnpm-workspace.yaml"]];
    // What a settings file names to run: one path on a line (yarnPath, yarn-path, a plugin's path), or bun's preloads,
    // each in quotes.
    NSRegularExpression *onePath = [NSRegularExpression regularExpressionWithPattern:
        @"^[ \\t-]*(?:yarnPath:|yarn-path|path:)[ \\t]*[\"']?([^\"'\\s#]+)"
                                                                             options:NSRegularExpressionAnchorsMatchLines
                                                                               error:nil];
    NSRegularExpression *preload = [NSRegularExpression regularExpressionWithPattern:@"^[ \\t]*preload[ \\t]*=(.*)$"
                                                                             options:NSRegularExpressionAnchorsMatchLines
                                                                               error:nil];
    NSRegularExpression *quoted = [NSRegularExpression regularExpressionWithPattern:@"[\"']([^\"']+)[\"']" options:0
                                                                              error:nil];
    for (NSArray *each in settings) {
        NSString *at = each[0], *name = each[1];
        NSString *text = Track(at, name, nil, what);
        if (!text.length) continue;
        NSMutableArray<NSString *> *named = [NSMutableArray array];
        if ([@[@".yarnrc", @".yarnrc.yml"] containsObject:name])
            for (NSTextCheckingResult *match in [onePath matchesInString:text options:0 range:NSMakeRange(0, text.length)])
                [named addObject:[text substringWithRange:[match rangeAtIndex:1]]];
        if ([name isEqual:@"bunfig.toml"])
            for (NSTextCheckingResult *line in [preload matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
                NSString *list = [text substringWithRange:[line rangeAtIndex:1]];
                for (NSTextCheckingResult *one in [quoted matchesInString:list options:0
                                                                    range:NSMakeRange(0, list.length)])
                    [named addObject:[list substringWithRange:[one rangeAtIndex:1]]];
            }
        for (NSString *file in named) {
            if ([LookFrom(root, at, file)[@"state"] isEqual:@"missing"])
                AddUnsure(what, [NSString stringWithFormat:@"%@ names %@, which isn't in this checkout",
                                                           Label(what, at, name), file]);
            else Track(at, file, nil, what);
        }
    }
    what[@"runnerFiles"] = @YES;  // the other files npm, pnpm, yarn or bun may read: said by the card
    NSArray *elsewhere = @[@"--prefix", @"-C", @"--dir", @"--cwd", @"-w", @"--workspace", @"--workspaces", @"-ws",
                           @"--filter", @"-F", @"-r", @"--recursive", @"workspace", @"workspaces"];
    NSMutableArray<NSString *> *args = [NSMutableArray array];
    for (NSString *word in words) {
        NSString *flag = [word componentsSeparatedByString:@"="][0];
        if ([elsewhere containsObject:flag]) {
            AddUnsure(what, [NSString stringWithFormat:@"%@ %@ runs scripts in another folder or package", tool, flag]);
            return;
        }
        if (![word hasPrefix:@"-"]) [args addObject:word];
    }
    // The word after `run` names the script, whatever options come first (`npm --loglevel silent run dev`).
    NSUInteger run = [args indexOfObjectPassingTest:^BOOL(NSString *arg, NSUInteger i, BOOL *stop) {
        return [@[@"run", @"run-script"] containsObject:arg];
    }];
    NSString *first = run != NSNotFound ? @"run" : args.firstObject ?: ([tool isEqual:@"yarn"] ? @"install" : @"");
    NSArray *installs = @[@"install", @"i", @"ci", @"add", @"rebuild", @"install-test", @"it"];
    NSArray *fetches = @[@"exec", @"x", @"dlx", @"create", @"init"];  // a package's program, not the project's
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    if ([first isEqual:@"run"]) {
        if (run + 1 < args.count) [names addObject:args[run + 1]];
    } else if ([installs containsObject:first]) {
        [names addObjectsFromArray:@[@"preinstall", @"install", @"postinstall", @"preprepare", @"prepare",
                                     @"postprepare"]];
    } else if ([@[@"start", @"test", @"t", @"tst", @"stop"] containsObject:first]) {
        [names addObject:[@[@"t", @"tst"] containsObject:first] ? @"test" : first];
    } else if ([first isEqual:@"restart"]) {
        [names addObjectsFromArray:@[@"restart", @"stop", @"start"]];
    } else if (![tool isEqual:@"npm"] && scripts[first]) {
        [names addObject:first];  // pnpm, yarn and bun run a script by its bare name
    } else if ([tool isEqual:@"bun"] && ![LookFrom(what[@"root"], folder, first)[@"state"] isEqual:@"missing"]) {
        AddFile(folder, first, @"bun", depth, what);  // bun runs a file too
        [what[@"others"] addObject:[NSString stringWithFormat:@"what %@ loads", Label(what, folder, first)]];
        return;
    } else if ([fetches containsObject:first]) {
        [what[@"others"] addObject:[NSString stringWithFormat:@"%@ %@", tool, first]];
        return;
    } else {
        AddUnsure(what, [NSString stringWithFormat:@"Whozmove doesn't know what %@ %@ runs", tool, first]);
        return;
    }
    // A script the command names that isn't there: what runs instead (npm start's server.js, a package above) isn't
    // checked, so the card says so. An install's scripts are there only if the package has them; an install also
    // reads the lockfile, which says which packages go in, and their own install scripts run, which aren't checked.
    BOOL lifecycle = [installs containsObject:first];
    if (lifecycle) {
        for (NSString *at in [NSOrderedSet orderedSetWithArray:@[package ?: folder, root]])
            for (NSArray<NSString *> *lock in LockFiles()) Track(at, lock[0], nil, what);
        what[@"packagesRun"] = @YES;  // its packages' own install scripts run too: said by the card
    }
    BOOL none = [names indexOfObjectPassingTest:^BOOL(NSString *name, NSUInteger i, BOOL *stop) {
        return scripts[name] != nil;
    }] == NSNotFound;
    BOOL unread = package && ![LookFrom(root, package, @"package.json")[@"state"] isEqual:@"file"];  // said already
    // `bun run x.ts` runs the file when there's no script of that name.
    if ([tool isEqual:@"bun"] && [first isEqual:@"run"] && names.count == 1 && !scripts[names[0]]
        && ![LookFrom(root, folder, names[0])[@"state"] isEqual:@"missing"]) {
        AddFile(folder, names[0], @"bun", depth, what);
        [what[@"others"] addObject:[NSString stringWithFormat:@"what %@ loads", Label(what, folder, names[0])]];
        return;
    }
    if (!lifecycle && names.count && none && !unread)
        AddUnsure(what, packageLabel ? [NSString stringWithFormat:@"there's no %@ script in %@", names[0], packageLabel]
                                     : [NSString stringWithFormat:@"there's no package.json for %@ %@", tool, names[0]]);
    for (NSString *name in names) {
        if ([name hasPrefix:@"pre"] || [name hasPrefix:@"post"]) {
            AddScript(package, scripts, name, depth, what);
            continue;
        }
        AddScript(package, scripts, [@"pre" stringByAppendingString:name], depth, what);
        AddScript(package, scripts, name, depth, what);
        AddScript(package, scripts, [@"post" stringByAppendingString:name], depth, what);
    }
}

// What make runs: the Makefile it would read (-f, else the first of GNUmakefile, makefile and Makefile it can open, as
// make does, which on a disk that doesn't tell case apart finds them by any case: labelled as the folder lists it) and
// every file that includes, all checked whole, and the targets' recipes, after those they depend on, with what each
// calls.
static void FollowMake(NSString *folder, NSArray<NSString *> *words, NSUInteger depth, NSMutableDictionary *what) {
    NSString *named = nil;
    NSMutableArray<NSString *> *targets = [NSMutableArray array];
    for (NSUInteger i = 0; i < words.count; i++) {
        NSString *word = words[i];
        // make -C (or --directory) reads its Makefile and runs its recipes from that folder.
        NSString *into = nil;
        if ([@[@"-C", @"--directory"] containsObject:word] && i + 1 < words.count) into = words[++i];
        else if ([word hasPrefix:@"--directory="]) into = [word substringFromIndex:12];
        else if ([word hasPrefix:@"-C"] && word.length > 2) into = [word substringFromIndex:2];
        if (into) {
            folder = Enter(what, folder, @"make -C", into);
            if (!folder) return;
            continue;
        }
        if ([@[@"-f", @"--file", @"--makefile"] containsObject:word] && i + 1 < words.count) named = words[++i];
        else if ([word hasPrefix:@"--file="] || [word hasPrefix:@"--makefile="])
            named = [word substringFromIndex:[word rangeOfString:@"="].location + 1];
        else if ([word hasPrefix:@"-f"] && word.length > 2) named = [word substringFromIndex:2];
        else if (![word hasPrefix:@"-"] && ![word containsString:@"="]) [targets addObject:word];
    }
    NSString *makefile = named, *label = named;
    if (!makefile) {
        NSArray<NSString *> *listed = [NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil] ?: @[];
        for (NSString *each in @[@"GNUmakefile", @"makefile", @"Makefile"]) {
            if ([LookFrom(what[@"root"], folder, each)[@"state"] isEqual:@"missing"]) continue;
            makefile = label = each;
            for (NSString *name in listed)
                if ([name caseInsensitiveCompare:each] == NSOrderedSame) label = name;
            break;
        }
    }
    NSString *text = makefile ? Track(folder, makefile, Label(what, folder, label), what) : nil;
    if (!text) {
        if (named && [LookFrom(what[@"root"], folder, named)[@"state"] isEqual:@"missing"])
            AddUnsure(what, [NSString stringWithFormat:@"make reads %@, which isn't in this checkout", named]);
        return;
    }
    // Every file it includes, whole, as any line of them can change what a recipe runs.
    NSMutableString *all = [text mutableCopy];
    NSMutableArray<NSString *> *pending = [@[text] mutableCopy];
    NSRegularExpression *include = [NSRegularExpression regularExpressionWithPattern:
        @"^[ \\t]*-?(?:include|sinclude)[ \\t]+(.+)$" options:NSRegularExpressionAnchorsMatchLines error:nil];
    for (NSUInteger at = 0; at < pending.count && at < 20; at++) {
        NSString *source = pending[at];
        for (NSTextCheckingResult *match in [include matchesInString:source options:0
                                                                range:NSMakeRange(0, source.length)]) {
            NSString *names = [[source substringWithRange:[match rangeAtIndex:1]] componentsSeparatedByString:@"#"][0];
            for (NSString *name in [names componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]) {
                if (!name.length || what[@"files"][name] || [what[@"seen"] containsObject:[@"make " stringByAppendingString:name]])
                    continue;
                [what[@"seen"] addObject:[@"make " stringByAppendingString:name]];
                if ([name containsString:@"$"] || [name containsString:@"*"]) {
                    AddUnsure(what, @"its Makefile includes a file it names with a variable or a pattern");
                    continue;
                }
                NSString *included = Track(folder, name, nil, what);
                if (!included) continue;
                [all appendFormat:@"\n%@", included];
                [pending addObject:included];
            }
        }
    }
    NSDictionary<NSString *, NSDictionary *> *rules = MakeRules(all);
    NSMutableArray<NSString *> *runs = [NSMutableArray array];
    for (NSString *target in targets.count ? targets : @[@""])
        AddRecipe(rules, target, what[@"seen"], runs, 0);
    for (NSString *line in runs) {
        [what[@"lines"] addObject:line];
        Follow(folder, line, depth + 1, what);
    }
}

static void Follow(NSString *folder, NSString *command, NSUInteger depth, NSMutableDictionary *what) {
    if (depth > kRunsDepth) {
        AddUnsure(what, @"its scripts call each other more deeply than Whozmove follows");
        return;
    }
    // Where the command is, as it goes: cd and pushd move it for the rest of the line (popd back), and once it's gone
    // where the check can't follow, nothing more of the line is.
    NSMutableArray<NSString *> *was = [NSMutableArray array];
    NSInteger inside = 0;  // how many ( ) the command is in, each a shell of its own
    BOOL unpaired = NO;    // a ) without its ( (a case pattern's): from then on, how many it's in can't be told
    for (NSArray<NSString *> *segment in Segments(command)) {
        if (!folder) break;
        if ([segment isEqual:@[@"("]] || [segment isEqual:@[@")"]]) {
            inside += [segment[0] isEqual:@"("] ? 1 : -1;
            unpaired = unpaired || inside < 0;
            continue;
        }
        // A cd inside ( ) is undone at the ), and one in a script that's sourced moves the line that sourced it: rather
        // than follow either, the card says it can't tell where the rest runs.
        BOOL sourced = [what[@"sourced"] intValue] > 0;
        if ([@[@"cd", @"pushd", @"popd"] containsObject:segment[0]] && (inside != 0 || unpaired || sourced)) {
            AddUnsure(what, !sourced ? @"it runs cd inside ( ), and Whozmove can't tell where the rest of it runs"
                                       : @"a script it sources runs cd, and Whozmove can't tell where the rest runs");
            break;
        }
        if ([@[@"cd", @"pushd"] containsObject:segment[0]]) {
            if ([segment[0] isEqual:@"pushd"]) [was addObject:folder];
            NSArray *targets = [segment subarrayWithRange:NSMakeRange(1, segment.count - 1)];
            folder = Enter(what, folder, segment[0], [targets componentsJoinedByString:@" "]);
            continue;
        }
        if ([segment[0] isEqual:@"popd"]) {
            folder = was.lastObject;
            if (folder) [was removeLastObject];
            else AddUnsure(what, @"it runs popd, and Whozmove can't follow it there");
            continue;
        }
        NSMutableArray<NSString *> *words = [segment mutableCopy];
        // What only sets the scene for the program: VAR=value words, and env, exec, nohup, time, command and
        // cross-env; and a make recipe's marks (@ quiet, - carry on after an error, + run anyway).
        while (words.count && ([words[0] rangeOfString:@"^[A-Za-z_][A-Za-z0-9_]*=" options:NSRegularExpressionSearch]
                                   .location != NSNotFound
                               || [@[@"env", @"exec", @"nohup", @"time", @"cross-env", @"command"]
                                      containsObject:words[0]]))
            [words removeObjectAtIndex:0];
        while (words.count && words[0].length && [@"@-+" containsString:[words[0] substringToIndex:1]]) {
            words[0] = [words[0] substringFromIndex:1];
            if (!words[0].length) [words removeObjectAtIndex:0];
        }
        if (!words.count) continue;
        NSString *tool = words[0].lastPathComponent;
        NSArray<NSString *> *rest = [words subarrayWithRange:NSMakeRange(1, words.count - 1)];
        if ([@[@"npm", @"pnpm", @"yarn", @"bun"] containsObject:tool]) {
            FollowRunner(folder, tool, rest, depth, what);
        } else if ([@[@"make", @"gmake"] containsObject:tool] || [@[@"$(MAKE)", @"${MAKE}"] containsObject:words[0]]) {
            FollowMake(folder, rest, depth, what);
        } else if ([@[@"source", @"."] containsObject:words[0]]) {
            if (rest.count) AddFile(folder, rest[0], @"source", depth, what);  // a shell script run in this shell
        } else if ([@[@"sh", @"bash", @"zsh"] containsObject:tool]) {
            // `sh -c '…'` runs its text; otherwise the first word that isn't an option is the script.
            NSUInteger c = [rest indexOfObjectPassingTest:^BOOL(NSString *word, NSUInteger i, BOOL *stop) {
                return [word hasPrefix:@"-"] && ![word hasPrefix:@"--"] && [word containsString:@"c"];
            }];
            if (c != NSNotFound && c + 1 < rest.count) Follow(folder, rest[c + 1], depth + 1, what);
            else
                for (NSString *word in rest)
                    if (![word hasPrefix:@"-"]) {
                        AddFile(folder, word, tool, depth, what);
                        break;
                    }
        } else if ([words[0] containsString:@"/"] && ![LookFrom(what[@"root"], folder, words[0])[@"state"] isEqual:@"missing"]) {
            AddFile(folder, words[0], nil, depth, what);  // a file in the checkout it runs, as written
        } else if ([@[@"node", @"python", @"python3", @"ruby", @"perl", @"deno", @"tsx", @"ts-node"]
                       containsObject:tool]) {
            // Every word given to the interpreter that's a file in the checkout: the program and what it loads first
            // (`node -r ./hook.js server.js`).
            // What those files load in turn (the packages they import) is the program's to decide, and isn't checked.
            BOOL any = NO;
            for (NSString *word in rest)
                if (![word hasPrefix:@"-"] && ![LookFrom(what[@"root"], folder, word)[@"state"] isEqual:@"missing"]) {
                    AddFile(folder, word, tool, depth, what);
                    [what[@"others"] addObject:[NSString stringWithFormat:@"what %@ loads", Label(what, folder, word)]];
                    any = YES;
                }
            if (!any) [what[@"others"] addObject:tool];
        } else if (![@[@"cd", @"echo", @"printf", @"true", @"false", @"test", @"[", @"export", @"set", @"exit", @"case",
                        @"esac", @"if", @"then", @"elif", @"else", @"fi", @"for", @"while", @"until", @"do", @"done",
                        @"in", @"{", @"}"] containsObject:tool]) {
            [what[@"others"] addObject:tool];
        }
    }
}

static NSDictionary *WhatRuns(NSString *folder, NSString *command) {
    NSMutableDictionary *what = [@{@"lines": [NSMutableArray array], @"files": [NSMutableDictionary dictionary],
                                   @"texts": [NSMutableDictionary dictionary], @"unsure": [NSMutableArray array],
                                   @"others": [NSMutableOrderedSet orderedSet], @"seen": [NSMutableSet set],
                                   @"ran": [NSMutableSet set]} mutableCopy];
    if (folder.length) {
        what[@"root"] = RealPath(folder);
        Follow(what[@"root"], command, 0, what);
    }
    return what;
}

// All that decides what a command runs in a folder, as one text: what it runs, each file that decides it (by the
// SHA-256 of its bytes), and what can't be followed or checked. A command that names none of these has none (""). What
// you confirmed is kept as this text's SHA-256, and checked against it before every run.
static NSString *CheckText(NSDictionary *what) {
    NSMutableString *text = [[what[@"lines"] componentsJoinedByString:@"\n"] mutableCopy];
    for (NSString *name in [[what[@"files"] allKeys] sortedArrayUsingSelector:@selector(compare:)])
        [text appendFormat:@"\n== %@ %@", name, what[@"files"][name]];
    for (NSString *why in what[@"unsure"]) [text appendFormat:@"\n?? %@", why];
    return text;
}

static NSString *TextHash(NSString *text) {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString string];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

NSString *DeployCheckText(NSString *folder, NSString *command) {
    return CheckText(WhatRuns(folder, command));
}

NSString *DeployRunsHash(NSString *folder, NSString *command) {
    return TextHash(DeployCheckText(folder, command));
}

// CheckDeploy, with what's kept as it's confirmed (CheckText) worked out from the same reading, so what's kept is
// exactly what the card showed.
static NSDictionary *CheckDeployKeeping(NSString *folder, NSString *command, NSString **kept) {
    NSDictionary *what = WhatRuns(folder, command);
    if (kept) *kept = CheckText(what);
    NSString *runs = [what[@"lines"] componentsJoinedByString:@"\n"];
    BOOL production = LooksLikeProduction(command) || LooksLikeProduction(runs);
    // Only what runs counts: a Makefile's other targets, or a package's other scripts, don't.
    for (NSString *name in what[@"texts"]) production = production || LooksLikeProduction(what[@"texts"][name]);
    NSMutableDictionary *check = [@{@"command": command ?: @"", @"production": @(production)} mutableCopy];
    // All of it, for the card to scroll through, unless there's more than it can sensibly hold.
    if (runs.length) {
        check[@"runs"] = runs.length > kRunsShown ? [runs substringToIndex:kRunsShown] : runs;
        if (runs.length > kRunsShown) check[@"cut"] = @YES;
    }
    NSArray *files = [[what[@"files"] allKeys] sortedArrayUsingSelector:@selector(compare:)];
    if (files.count) check[@"files"] = files;
    if ([what[@"unsure"] count]) check[@"unsure"] = what[@"unsure"];
    // What isn't checked: the programs and files named, and, marked for the card to say in its own words, an install's
    // packages' own install scripts and the other files a package runner may read.
    NSArray *others = [what[@"others"] array];
    if (others.count) check[@"others"] = others;
    if (what[@"packagesRun"]) check[@"packagesRun"] = @YES;
    if (what[@"runnerFiles"]) check[@"runnerFiles"] = @YES;
    return check;
}

NSDictionary *CheckDeploy(NSString *folder, NSString *command) {
    return CheckDeployKeeping(folder, command, NULL);
}

#pragma mark Suggestions

// The command a project's own files point to for putting it in place on this Mac, the first that fits: Whozmove's own
// build, a Compose file, a pm2 file, a package script or Makefile target named for a local install, a package with
// commands to install, a Rust binary, a Go program, a Python package with scripts. Only commands that do their job and
// finish, and none that looks as if it could reach production, by what it really runs (CheckDeploy). Nil when none
// fits: then the project gets no Deploy.
NSString *SuggestDeploy(NSString *folder) {
    if (!folder.length) return nil;
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL (^has)(NSString *) = ^BOOL(NSString *name) {
        return [fm fileExistsAtPath:[folder stringByAppendingPathComponent:name]];
    };
    NSString *(^read)(NSString *) = ^NSString *(NSString *name) { return FileIn(folder, name); };
    BOOL (^local)(NSString *) = ^BOOL(NSString *command) {
        return ![CheckDeploy(folder, command)[@"production"] boolValue];
    };
    if (has(@"build.sh") && has(@"app/swap-in.sh")) return @"./build.sh --now";  // Whozmove itself
    for (NSString *compose in @[@"compose.yaml", @"compose.yml", @"docker-compose.yaml", @"docker-compose.yml"])
        if (has(compose)) return @"docker compose up -d --build";
    for (NSString *pm2 in @[@"ecosystem.config.js", @"ecosystem.config.cjs"])
        if (has(pm2)) return [@"pm2 startOrReload " stringByAppendingString:pm2];
    NSData *packageText = [read(@"package.json") dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *package = packageText ? [NSJSONSerialization JSONObjectWithData:packageText options:0 error:nil] : nil;
    if ([package isKindOfClass:NSDictionary.class]) {
        NSString *runner = has(@"pnpm-lock.yaml") ? @"pnpm" : has(@"yarn.lock") ? @"yarn"
                         : has(@"bun.lockb") || has(@"bun.lock") ? @"bun" : @"npm";
        NSDictionary *scripts = ScriptsIn(read(@"package.json"));
        for (NSString *name in @[@"deploy:local", @"install:local"]) {
            NSString *command = [NSString stringWithFormat:@"%@ run %@", runner, name];
            if ([scripts[name] isKindOfClass:NSString.class] && local(command)) return command;
        }
    }
    NSString *makefile = read(@"GNUmakefile") ?: read(@"makefile") ?: read(@"Makefile");
    NSDictionary *rules = makefile ? MakeRules(makefile) : @{};
    for (NSString *target in @[@"install", @"deploy-local"]) {
        NSString *command = [@"make " stringByAppendingString:target];
        if (rules[target] && local(command)) return command;
    }
    if ([package isKindOfClass:NSDictionary.class] && package[@"bin"]) return @"npm install -g .";
    if (has(@"Cargo.toml") && (has(@"src/main.rs") || [read(@"Cargo.toml") containsString:@"[[bin]]"]))
        return @"cargo install --path .";
    if (has(@"go.mod") && (has(@"main.go") || has(@"cmd"))) return @"go install ./...";
    if ([read(@"pyproject.toml") containsString:@"[project.scripts]"]) return @"pipx install --force .";
    return nil;
}

#pragma mark Where things are kept

// The commands you've saved, by project, and each folder's last deploy and skip: {projects: {project: {command,
// savedAt}}, folders: {folder: {at, skippedAt}}}. Read and written on the queue only.
static NSMutableDictionary *ReadStore(void) {
    NSDictionary *saved = ReadJSON(AppDir(@"deploy.json"));
    NSMutableDictionary *store = [NSMutableDictionary dictionary];
    for (NSString *part in @[@"projects", @"folders"]) {
        id kept = [saved isKindOfClass:NSDictionary.class] ? saved[part] : nil;
        store[part] = [kept isKindOfClass:NSDictionary.class] ? [kept mutableCopy] : [NSMutableDictionary dictionary];
    }
    return store;
}

// What's saved for a project, {command, savedAt, ports, runs}, or nil. Projects are saved by their real folder.
static NSDictionary *SavedEntry(NSDictionary *store, NSString *project) {
    if (!project) return nil;
    NSDictionary *saved = store[@"projects"][RealPath(project)];
    return [saved isKindOfClass:NSDictionary.class] && [saved[@"command"] isKindOfClass:NSString.class] ? saved : nil;
}

// The command saved for a project, or nil.
static NSString *SavedCommand(NSDictionary *store, NSString *project) {
    return SavedEntry(store, project)[@"command"];
}

// Whether the command was confirmed on a card that said each checkout gets its own port in $PORT: only then does a run
// get one. A command confirmed before runs as it was.
static BOOL SavedWithPorts(NSDictionary *store, NSString *project) {
    return [SavedEntry(store, project)[@"ports"] boolValue];
}

// Saves what Deploy keeps, whole and at once: why macOS refused it (out of space, say), or nil once it's saved.
static NSString *WriteStore(NSDictionary *store) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:store
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:nil];
    if (!json) return @"it couldn't be written as JSON";
    NSError *refused = nil;
    if ([json writeToFile:AppDir(@"deploy.json") options:NSDataWritingAtomic error:&refused]) return nil;
    return refused.localizedDescription ?: @"the save didn't go through";
}

// The port each checkout's build gets in $PORT, kept in ports.json: {projects: {project: {base, folders: {folder:
// port}}}}, by real paths. A folder gets its project's first port (3000), or the next one no other folder in the record
// has, the first time it deploys, and keeps it, so each checkout of each project has its own and their builds run side
// by side. A folder that's gone (a removed worktree) gives its port back. Read and written on the queue only.
static NSString *PortsPath(void) {
    return AppDir(@"ports.json");
}
static const long kFirstPort = 3000;

// The next port no checkout in the record has and nothing on this Mac is listening on, from the project's first, or
// nil. Blocking: it looks at every process for each it tries.
static NSNumber *NextFreePort(NSString *project, NSSet<NSNumber *> *busy) {
    NSDictionary *saved = ReadJSON(PortsPath());
    NSDictionary *projects = [saved isKindOfClass:NSDictionary.class] && [saved[@"projects"] isKindOfClass:NSDictionary.class]
        ? saved[@"projects"] : @{};
    NSMutableSet<NSNumber *> *taken = [busy mutableCopy] ?: [NSMutableSet set];
    for (NSString *each in projects) {
        NSDictionary *folders = [projects[each] isKindOfClass:NSDictionary.class] ? projects[each][@"folders"] : nil;
        if ([folders isKindOfClass:NSDictionary.class])
            for (NSString *path in folders) if ([folders[path] isKindOfClass:NSNumber.class]) [taken addObject:folders[path]];
    }
    id base = projects[RealPath(project ?: @"")][@"base"];
    long start = [base isKindOfClass:NSNumber.class] ? [base longValue] : kFirstPort;
    // Up to 2,000 ports on, and 50 that something might be listening on, each looked for.
    int looked = 0;
    for (long port = start; port <= 65535 && port < start + 2000 && looked < 50; port++) {
        if ([taken containsObject:@(port)]) continue;
        looked++;
        if (!PortHolder((int)port)) return @(port);
    }
    return nil;
}

// Keeps a port for a folder from now on, as Use Port asks (DeployPort reads it back).
static void KeepDeployPort(NSString *project, NSString *folder, NSNumber *port) {
    NSDictionary *saved = ReadJSON(PortsPath());
    NSMutableDictionary *projects = [saved isKindOfClass:NSDictionary.class]
        && [saved[@"projects"] isKindOfClass:NSDictionary.class] ? [saved[@"projects"] mutableCopy]
                                                                  : [NSMutableDictionary dictionary];
    NSMutableDictionary *entry = [projects[RealPath(project)] mutableCopy] ?: [@{@"base": @(kFirstPort)} mutableCopy];
    NSMutableDictionary *folders = [entry[@"folders"] mutableCopy] ?: [NSMutableDictionary dictionary];
    folders[RealPath(folder)] = port;
    entry[@"folders"] = folders;
    projects[RealPath(project)] = entry;
    [[NSJSONSerialization dataWithJSONObject:@{@"projects": projects}
                                     options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil]
        writeToFile:PortsPath() atomically:YES];
}

NSNumber *DeployPort(NSString *project, NSString *folder, BOOL keep) {
    if (!project.length || !folder.length) return nil;
    project = RealPath(project);
    folder = RealPath(folder);
    NSDictionary *saved = ReadJSON(PortsPath());
    NSMutableDictionary *projects = [saved isKindOfClass:NSDictionary.class]
        && [saved[@"projects"] isKindOfClass:NSDictionary.class] ? [saved[@"projects"] mutableCopy]
                                                                  : [NSMutableDictionary dictionary];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableSet<NSNumber *> *taken = [NSMutableSet set];
    NSNumber *found = nil;
    BOOL changed = NO;
    for (NSString *each in projects.allKeys) {
        NSDictionary *entry = [projects[each] isKindOfClass:NSDictionary.class] ? projects[each] : @{};
        NSMutableDictionary *folders = [entry[@"folders"] isKindOfClass:NSDictionary.class]
            ? [entry[@"folders"] mutableCopy] : [NSMutableDictionary dictionary];
        for (NSString *path in folders.allKeys) {
            long port = [folders[path] isKindOfClass:NSNumber.class] ? [folders[path] longValue] : 0;
            if (port < 1024 || port > 65535 || ![fm fileExistsAtPath:path]) {
                [folders removeObjectForKey:path];
                changed = YES;
                continue;
            }
            [taken addObject:@(port)];
            if ([each isEqual:project] && [path isEqual:folder]) found = @(port);
        }
        NSMutableDictionary *updated = [entry mutableCopy];
        updated[@"folders"] = folders;
        projects[each] = updated;
    }
    if (!found) {
        // The project's first port is kept for its main checkout, so main has it whichever checkout deploys first.
        NSDictionary *entry = projects[project];
        long port = [entry[@"base"] isKindOfClass:NSNumber.class] ? [entry[@"base"] longValue] : kFirstPort;
        if (![folder isEqual:project]) [taken addObject:@(port)];
        while ([taken containsObject:@(port)] && port < 65535) port++;
        found = @(port);
        NSMutableDictionary *updated = [entry mutableCopy] ?: [@{@"base": @(kFirstPort)} mutableCopy];
        NSMutableDictionary *folders = [updated[@"folders"] mutableCopy] ?: [NSMutableDictionary dictionary];
        folders[folder] = found;
        updated[@"folders"] = folders;
        projects[project] = updated;
        changed = YES;
    }
    if (keep && changed) {
        NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"projects": projects}
                                                       options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                         error:nil];
        [json writeToFile:PortsPath() atomically:YES];
    }
    return found;
}

// Each project's build in place: {projects: {project: {folder, commit, uncommitted, at, by, before}}}, kept apart from
// deploy.json, as forgetting a project's command doesn't forget what's running. Read and written on the queue only.
static NSString *InPlacePath(void) {
    return AppDir(@"in-place.json");
}

// The build in place for each of these folders' projects, by project (its real path): each folder's last run that
// went through becomes its project's, the one there before kept as `before`, unless one that ended later is there
// already, so of two checkouts' runs the last to end is in place whichever is read first; one that ended between the
// two becomes `before`. A run from before Deploy noted commits goes in without one. Written back when anything changed
// and `keep` (a print run only looks). Blocking.
static NSDictionary *BuildsInPlace(NSDictionary<NSString *, NSString *> *projectOf, BOOL keep) {
    NSDictionary *saved = ReadJSON(InPlacePath());
    id kept = [saved isKindOfClass:NSDictionary.class] ? saved[@"projects"] : nil;
    NSMutableDictionary *builds = [kept isKindOfClass:NSDictionary.class] ? [kept mutableCopy]
                                                                         : [NSMutableDictionary dictionary];
    BOOL changed = NO;
    for (NSString *folder in projectOf) {
        // A run that finished well is in place once it has; a server, once it's up.
        NSDictionary *run = LastDeployRun(folder);
        NSNumber *upAt = run[@"up"][@"at"];
        BOOL done = [run[@"ok"] boolValue] && ![run[@"running"] boolValue];
        if (!done && !upAt) continue;
        NSNumber *when = done ? run[@"finishedAt"] : upAt;
        NSString *project = RealPath(projectOf[folder]);
        NSDictionary *now = [builds[project] isKindOfClass:NSDictionary.class] ? builds[project] : nil;
        NSDictionary *before = [now[@"before"] isKindOfClass:NSDictionary.class] ? now[@"before"] : nil;
        double at = when.doubleValue;
        if (at <= [before[@"at"] doubleValue] || at == [now[@"at"] doubleValue]) continue;
        NSMutableDictionary *build = [@{@"folder": folder, @"at": when} mutableCopy];
        for (NSString *key in @[@"commit", @"uncommitted", @"by"])
            if (run[key]) build[key] = run[key];
        NSMutableDictionary *updated;
        if (at > [now[@"at"] doubleValue]) {
            updated = build;
            if (now) {
                NSMutableDictionary *replaced = [now mutableCopy];
                [replaced removeObjectForKey:@"before"];
                updated[@"before"] = replaced;
            }
        } else {
            updated = [now mutableCopy];
            updated[@"before"] = build;
        }
        builds[project] = updated;
        changed = YES;
    }
    if (changed && keep) {
        NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"projects": builds}
                                                       options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                         error:nil];
        [json writeToFile:InPlacePath() atomically:YES];
    }
    return builds;
}

NSDictionary *BuildsInPlaceSeen(NSDictionary<NSString *, NSString *> *projectOf) {
    return BuildsInPlace(projectOf, NO);
}

// What a deploy from `folder` starts from, noted with its run: the checkout's commit, and how many of its files aren't
// committed, counted as the row's numbers count them (changed files, and new ones git doesn't ignore). Empty outside
// git, or before the first commit. Read only, without optional locks (Git.h), so an agent committing at that moment
// can't fail; and nothing at all before Apple's developer tools are there (RunGit). Blocking.
NSDictionary *BuildNow(NSString *folder) {
    if (!GitInfo(folder)) return @{};
    NSDictionary *head = RunGit(@[@"--no-optional-locks", @"-C", folder, @"rev-parse", @"--verify", @"--quiet", @"HEAD"]);
    NSString *commit = [[[NSString alloc] initWithData:head[@"out"] ?: NSData.data encoding:NSUTF8StringEncoding]
                        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([head[@"status"] intValue] != 0 || !commit.length) return @{};
    NSInteger uncommitted = [FetchCheckoutState(folder, nil)[@"changes"] integerValue]
                          + [FetchChangeCounts(folder, nil)[@"newFiles"] integerValue];
    return @{@"commit": commit, @"uncommitted": @(uncommitted)};
}

// The folder a folder's runs are kept in: deploys/<16 hex digits of its path's FNV-1a hash>.
static NSString *RunDir(NSString *folder) {
    return AppDir([NSString stringWithFormat:@"deploys/%016llx", HashBytes(folder.fileSystemRepresentation)]);
}

NSString *DeployLogPath(NSString *folder) {
    return [RunDir(folder) stringByAppendingPathComponent:@"log"];
}

NSDictionary *DeployInstallWords(NSString *folder) {
    // Each lock file only as a regular file inside the checkout (Look), as every project file Deploy reads.
    for (NSArray<NSString *> *lock in LockFiles()) {
        NSDictionary *seen = Look(folder, lock[0]);
        if (![seen[@"state"] isEqual:@"file"]) continue;
        NSString *words = [lock[0] isEqual:@"yarn.lock"] && YarnOne(seen[@"path"]) ? @"yarn install --frozen-lockfile"
                                                                                   : lock[1];
        return @{@"words": words, @"lockfile": lock[0]};
    }
    return @{@"words": @"npm install", @"makesLockfile": @YES};
}

NSString *DeployInstallCommand(NSString *folder) {
    return DeployInstallWords(folder)[@"words"];
}

NSDictionary *DeployInstallCheck(NSString *folder) {
    // Followed as a confirmed command is (CheckDeployKeeping): the project's own install scripts, the lock file and the
    // settings the runner reads, fingerprinted the same way, so Install First runs only what its card showed.
    NSMutableDictionary *check = [DeployInstallWords(folder) mutableCopy];
    NSString *kept = nil;
    [check addEntriesFromDictionary:CheckDeployKeeping(folder, check[@"words"], &kept)];
    check[@"hash"] = TextHash(kept ?: @"");
    return check;
}

// The end of a run's log, its last 4KB, read from there: a long log isn't read whole every couple of seconds.
static NSString *LogTail(NSString *path) {
    NSFileHandle *file = [NSFileHandle fileHandleForReadingAtPath:path];
    unsigned long long size = 0;
    if (!file || ![file seekToEndReturningOffset:&size error:nil]) return @"";
    unsigned long long from = size > 4096 ? size - 4096 : 0;
    NSData *tail = [file seekToOffset:from error:nil] ? [file readDataToEndOfFileAndReturnError:nil] : nil;
    [file closeAndReturnError:nil];
    // Starting part-way through a letter, the bytes before the next whole one are left out, or none of it decodes.
    const uint8_t *bytes = tail.bytes;
    NSUInteger skip = 0;
    while (from > 0 && skip < tail.length && (bytes[skip] & 0xC0) == 0x80) skip++;
    NSData *whole = [tail subdataWithRange:NSMakeRange(skip, tail.length - skip)];
    return [[NSString alloc] initWithData:whole encoding:NSUTF8StringEncoding] ?: @"";
}

// A log's text as a card can show it: terminal control codes (colours, cursor moves, titles) and the marks that turn
// text's direction taken out, so nothing in it can change how the card reads, or what it seems to say.
static NSString *PlainLogText(NSString *text) {
    if (!text.length) return text ?: @"";
    NSArray<NSString *> *patterns = @[
        @"\\x1b\\[[0-?]*[ -/]*[@-~]|\\x1b\\][^\\x07\\x1b]*(?:\\x07|\\x1b\\\\)|\\x1b[@-_]",  // control sequences
        @"[\\u202a-\\u202e\\u2066-\\u2069\\u200e\\u200f\\u061c]",                          // direction marks
        @"[\\x00-\\x08\\x0b\\x0c\\x0e-\\x1f\\x7f]",                                          // other controls
    ];
    NSString *plain = text;
    for (NSString *pattern in patterns)
        plain = [plain stringByReplacingOccurrencesOfString:pattern withString:@"" options:NSRegularExpressionSearch
                                                      range:NSMakeRange(0, plain.length)];
    return plain;
}

// The marker Stop Deploy leaves beside a run (stop:), a file of its own: the run's shell writes only its status, so it
// can't overwrite it.
static NSString *const kStopped = @"stopped";
// How long what a stopped run started has to end before it's made to (stop:).
static const int64_t kStopGrace = 2;

// The members of a run's process group seen so far, each {pid, start}: what Stop Deploy signals once the run's own
// shell has gone, and what keeps the run counting as running then. Kept beside the run, in members.json.
static NSArray<NSDictionary *> *NotedMembers(NSString *dir) {
    NSArray *noted = ReadJSON([dir stringByAppendingPathComponent:@"members.json"]);
    NSMutableArray *found = [NSMutableArray array];
    if ([noted isKindOfClass:NSArray.class])
        for (NSDictionary *each in noted)
            if ([each isKindOfClass:NSDictionary.class] && [each[@"pid"] intValue] > 0
                && [each[@"start"] isKindOfClass:NSNumber.class])
                [found addObject:each];
    return found;
}

// Which of these are still the processes they were (pid and start time): never a later one given the same pid.
static NSArray<NSDictionary *> *StillThere(NSArray<NSDictionary *> *members) {
    NSMutableArray *live = [NSMutableArray array];
    for (NSDictionary *each in members)
        if (ProcessStartedAt([each[@"pid"] intValue]) == [each[@"start"] longLongValue]) [live addObject:each];
    return live;
}

static NSArray<NSDictionary *> *LiveMembers(NSString *dir) {
    return StillThere(NotedMembers(dir));
}

// While a folder's run goes on, what its process group is and listens on (GroupMembers, ListeningOf), noted beside the run: its
// members as they're seen (members.json, up to 256), and once it listens, `up` (up.json: {port, at, every, also}):
// $PORT's port if it listens there, else the lowest it does, whether that's on every address (so other devices on the
// network can reach it), and the other ports it listens on. `at` is when it was first seen listening, kept as the rest
// changes. The group is the run's shell's (SpawnDetached starts it in a session of its own), read while its shell runs
// or, once that has gone, while a member noted before still does. On the queue.
void NoteRunUp(NSString *folder) {
    NSString *dir = RunDir(folder);
    NSDictionary *run = ReadJSON([dir stringByAppendingPathComponent:@"run.json"]);
    pid_t pid = [run isKindOfClass:NSDictionary.class] ? [run[@"pid"] intValue] : 0;
    if (pid <= 0) return;
    // The group is read only while the run's shell is surely its own (pid and start time): once that has gone, a
    // server that left it (a daemon's setsid) can leave it empty, and its number could then be anyone's. Then only the
    // members noted before are looked at, each while it's still the process it was, and no new one is noted.
    BOOL own = ProcessStartedAt(pid) == [run[@"processStart"] longLongValue];
    NSArray<NSDictionary *> *group = own ? GroupMembers(pid) : @[];
    NSArray<NSDictionary *> *live = own ? group : LiveMembers(dir);
    if (!live.count) return;
    NSMutableArray *members = [NotedMembers(dir) mutableCopy];
    BOOL more = NO;
    for (NSDictionary *each in group)
        if (![members containsObject:each] && members.count < 256) {
            [members addObject:each];
            more = YES;
        }
    if (more)
        [[NSJSONSerialization dataWithJSONObject:members options:0 error:nil]
            writeToFile:[dir stringByAppendingPathComponent:@"members.json"] atomically:YES];
    NSArray<NSDictionary *> *listening = ListeningOf(live);
    if (!listening.count) return;
    NSDictionary *main = listening[0];
    for (NSDictionary *each in listening)
        if ([each[@"port"] isEqual:run[@"port"]]) main = each;
    NSMutableArray *also = [NSMutableArray array];
    for (NSDictionary *each in listening)
        if (each != main) [also addObject:each[@"port"]];
    NSString *path = [dir stringByAppendingPathComponent:@"up.json"];
    NSDictionary *was = ReadJSON(path);
    NSNumber *at = [was isKindOfClass:NSDictionary.class] && [was[@"at"] isKindOfClass:NSNumber.class]
        ? was[@"at"] : @(floor(NSDate.date.timeIntervalSince1970 * 1000));
    NSDictionary *up = @{@"port": main[@"port"], @"at": at, @"every": main[@"every"] ?: @NO, @"also": also};
    if (![up isEqual:was]) {
        [[NSJSONSerialization dataWithJSONObject:up options:0 error:nil] writeToFile:path atomically:YES];
        if (![was isKindOfClass:NSDictionary.class])
            PanelLog(@"deploy in %@: up at port %@", folder, main[@"port"]);
    }
}

// A folder's last run: {startedAt, running}, and once it has ended, {ok, finishedAt}, with the log's last line if it
// failed, or {stopped} if you stopped it. Nil before its first. It's running for as long as its own process is,
// whatever its files say, so a run you've stopped reads as running until it has really ended; and only while that
// process is its own: one whose pid now belongs to a later process (told apart by when it started) has ended, so a
// run cut short, say by a restart of the Mac, can't look as if it runs forever. A run noted without when its process
// started is taken as ended: its pid alone could be anyone's now. Stopped, it runs on until what it started has ended
// too, for the few seconds that's given (stop:), so Deploy can't start a second run over one still stopping; after
// that, its group's id too could be a later process's. One that ended without writing its
// status was stopped some other way. When it finished is when its files last changed (the marker, the status, or, with
// neither, its log), so it reads the same every time it's looked at.
NSDictionary *LastDeployRun(NSString *folder) {
    NSString *dir = RunDir(folder);
    NSDictionary *run = ReadJSON([dir stringByAppendingPathComponent:@"run.json"]);
    if (![run isKindOfClass:NSDictionary.class] || ![run[@"folder"] isEqual:folder]) return nil;
    NSMutableDictionary *last = [@{@"startedAt": run[@"startedAt"] ?: @0} mutableCopy];
    if (AsText(run[@"by"])) last[@"by"] = run[@"by"];
    if (AsText(run[@"commit"])) last[@"commit"] = run[@"commit"];
    if ([run[@"uncommitted"] isKindOfClass:NSNumber.class]) last[@"uncommitted"] = run[@"uncommitted"];
    if ([run[@"port"] isKindOfClass:NSNumber.class]) last[@"port"] = run[@"port"];
    // Installing the packages first (Install First), until that has gone through and the command runs.
    BOOL installing = AsText(run[@"installs"]) && ![NSFileManager.defaultManager
        fileExistsAtPath:[dir stringByAppendingPathComponent:@"installed"]];
    pid_t pid = [run[@"pid"] intValue];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSDate *(^changed)(NSString *) = ^NSDate *(NSString *name) {
        return [fm attributesOfItemAtPath:[dir stringByAppendingPathComponent:name] error:nil].fileModificationDate;
    };
    NSDictionary *up = ReadJSON([dir stringByAppendingPathComponent:@"up.json"]);
    if ([up isKindOfClass:NSDictionary.class] && [up[@"port"] isKindOfClass:NSNumber.class]) last[@"up"] = up;
    BOOL known = pid > 0 && [run[@"processStart"] isKindOfClass:NSNumber.class];
    BOOL alive = known && ProcessStartedAt(pid) == [run[@"processStart"] longLongValue];
    if (!alive && known) {
        NSDate *stoppedAt = changed(kStopped);
        alive = stoppedAt && -stoppedAt.timeIntervalSinceNow < kStopGrace + 3 && killpg(pid, 0) == 0;
    }
    // A server its shell left running (started in the background, say) keeps the run going, while it's still the
    // process noted.
    if (!alive && known) alive = LiveMembers(dir).count > 0;
    if (alive) {
        last[@"running"] = @YES;
        if (installing) last[@"installing"] = run[@"installs"];
        // Once the packages are in, the command's own start: what a server's 2 minutes without a port count from.
        NSDate *installed = AsText(run[@"installs"]) && !installing ? changed(@"installed") : nil;
        if (installed) last[@"installedAt"] = @(floor(installed.timeIntervalSince1970 * 1000));
        return last;
    }
    NSString *status = [[NSString stringWithContentsOfFile:[dir stringByAppendingPathComponent:@"status"]
                                                  encoding:NSUTF8StringEncoding error:nil]
                        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    BOOL stopped = [fm fileExistsAtPath:[dir stringByAppendingPathComponent:kStopped]];
    BOOL exited = status.length
        && [status rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound;
    NSDate *ended = stopped ? changed(kStopped) ?: changed(@"status") : exited ? changed(@"status") : nil;
    if (!ended) {
        NSDate *wrote = changed(@"log"), *began = changed(@"run.json");
        ended = wrote && began ? [wrote laterDate:began] : wrote ?: began;
    }
    last[@"running"] = @NO;
    // A run that was up (a server) and has ended didn't finish its job: it stopped, whatever its shell's status.
    last[@"ok"] = !stopped && exited && status.intValue == 0 && !last[@"up"] ? @YES : @NO;
    last[@"finishedAt"] = ended ? @(floor(ended.timeIntervalSince1970 * 1000)) : last[@"startedAt"];
    if (stopped) {
        last[@"stopped"] = @YES;
    } else if (![last[@"ok"] boolValue]) {
        NSString *text = PlainLogText(LogTail([dir stringByAppendingPathComponent:@"log"]));
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        for (NSString *each in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet])
            if ([each stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length) [lines addObject:each];
        NSString *line = lines.lastObject;
        last[@"lastLine"] = exited ? Clip(line ?: [NSString stringWithFormat:@"it ended with status %d",
                                                                             status.intValue], 200)
                                   : @"it stopped before it finished";
        // Its last lines whole, for the card that says what happened: the last five, each up to 300 letters.
        NSMutableArray<NSString *> *shown = [NSMutableArray array];
        for (NSString *each in [lines subarrayWithRange:NSMakeRange(lines.count > 5 ? lines.count - 5 : 0,
                                                                    MIN(lines.count, (NSUInteger)5))])
            [shown addObject:Clip(each, 300)];
        if (shown.count) last[@"lastLines"] = shown;
        // A server that was up and stopped by itself, rather than one that never came up.
        if (last[@"up"]) last[@"endedItself"] = @YES;
        // Packages not installed: the runner's program or a package not found, in a checkout with a package.json and
        // no node_modules (a new worktree starts without them).
        NSFileManager *files = NSFileManager.defaultManager;
        NSString *folderPath = run[@"folder"];
        BOOL missing = [text rangeOfString:@"(command not found|Cannot find module|ERR_MODULE_NOT_FOUND|"
                                           @"MODULE_NOT_FOUND)" options:NSRegularExpressionSearch].location != NSNotFound;
        // Install First's install that didn't go through, so the command never ran: its own state, never taken for the
        // command's failure, nor offered Install First again as if nothing had been tried.
        if (installing) {
            last[@"installFailed"] = run[@"installs"];
        } else if (missing && !last[@"up"]
                   && [files fileExistsAtPath:[folderPath stringByAppendingPathComponent:@"package.json"]]
                   && ![files fileExistsAtPath:[folderPath stringByAppendingPathComponent:@"node_modules"]]) {
            last[@"noPackages"] = @YES;
            NSDictionary *install = DeployInstallWords(folderPath);
            last[@"install"] = install[@"words"];
            if (install[@"lockfile"]) last[@"lockfile"] = install[@"lockfile"];
        }
    }
    return last;
}

@interface Deploys ()
@property (strong) Page *page;
@property (strong) dispatch_queue_t queue;
@property (assign) BOOL reading;
@property (assign) NSTimeInterval readAt;
@property (copy) NSString *sent;  // what the page was last told, as JSON
@property (copy) NSDictionary<NSString *, NSDictionary *> *asked;  // the deploys sessions asked for, waiting, by folder
@property (copy) NSDictionary<NSString *, NSDictionary *> *keptShown;  // your presses kept while an agent works, by folder
// What was last read, on the main thread: what ▾'s menu goes by, so opening it never waits on the queue or the disk.
@property (copy) NSDictionary *known;
// The sessions listed last, on the main thread: who else is at work in a row's folder, which a deploy waits for.
@property (copy) NSArray<Row *> *rows;
// Suggestions by folder, with when each was worked out: on the queue only.
@property (strong) NSMutableDictionary<NSString *, NSArray *> *suggested;
// What the set-up card was last shown a command runs on each row, {command, runs}, in full: on the queue only.
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *shown;
// Deploy's card for each folder, when a press didn't run as it was (a port another build or program holds): on the
// queue only, sent with the folder (read:).
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *cards;
// For each folder, the port a session's ask took in place of one that was held, {port, from}: on the main thread only,
// for the ask's status to say.
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *moved;
// For each folder, the deploy waiting there for a run to end (Restart, Stop It and Deploy), by a token of its own: on
// the queue only. Stop Deploy pressed there takes it away, so the wait ends without deploying, and a later one
// replaces it.
@property (strong) NSMutableDictionary<NSString *, NSUUID *> *waiting;
@end

@implementation Deploys

- (instancetype)initWithPage:(Page *)page {
    if (!(self = [super init])) return nil;
    self.page = page;
    self.queue = dispatch_queue_create("whozmove.deploys", DISPATCH_QUEUE_SERIAL);
    self.suggested = [NSMutableDictionary dictionary];
    self.shown = [NSMutableDictionary dictionary];
    self.cards = [NSMutableDictionary dictionary];
    self.moved = [NSMutableDictionary dictionary];
    self.waiting = [NSMutableDictionary dictionary];
    self.restartTries = 20;
    return self;
}

- (void)refreshFor:(NSArray<Row *> *)rows {
    self.rows = rows;
    if (self.reading || NSDate.date.timeIntervalSince1970 - self.readAt < 2) return;
    NSMutableDictionary<NSString *, NSString *> *projectOf = [NSMutableDictionary dictionary];  // folder -> project
    for (Row *row in rows)
        if (DeployFolder(row)) projectOf[DeployFolder(row)] = DeployProject(row);
    self.reading = YES;
    dispatch_async(self.queue, ^{
        NSDictionary *deploys = nil;
        @try {
            deploys = [self read:projectOf];
        } @catch (NSException *e) {
            LogProblem([NSString stringWithFormat:@"deploys not read: %@: %@", e.name, e.reason]);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.reading = NO;
            self.readAt = NSDate.date.timeIntervalSince1970;
            if (deploys) [self send:deploys];
        });
    });
}

- (void)resend {
    self.sent = nil;
    self.readAt = 0;
}

// On the queue: each project's saved command, and each folder's suggestion, last deploy, skip and last run. A run that
// ended well counts as the folder's last deploy, and as its project's build in place (BuildsInPlace), which is kept for
// every project Deploy has put one in place for, and never sent to the page.
- (NSDictionary *)read:(NSDictionary<NSString *, NSString *> *)projectOf {
    NSDictionary *inPlace = BuildsInPlace(projectOf, YES);
    NSMutableDictionary *store = ReadStore();
    NSMutableDictionary *projects = [NSMutableDictionary dictionary], *folders = [NSMutableDictionary dictionary];
    BOOL changed = NO;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    for (NSString *folder in projectOf) {
        NSString *project = projectOf[folder];
        if (SavedCommand(store, project)) projects[project] = @{@"command": SavedCommand(store, project)};
        NSArray *cached = self.suggested[folder];
        if (!cached || now - [cached[0] doubleValue] > 30)
            self.suggested[folder] = cached = @[@(now), SuggestDeploy(folder) ?: NSNull.null];
        NSMutableDictionary *state = [NSMutableDictionary dictionary];
        if ([cached[1] isKindOfClass:NSString.class]) state[@"suggested"] = cached[1];
        id folderState = store[@"folders"][folder];
        NSDictionary *kept = [folderState isKindOfClass:NSDictionary.class] ? folderState : @{};
        NSDictionary *run = LastDeployRun(folder);
        if ([run[@"running"] boolValue]) {
            NoteRunUp(folder);  // what it's seen listening on, every couple of seconds while it runs
            run = LastDeployRun(folder);
        }
        if ([run[@"ok"] boolValue] && [run[@"finishedAt"] doubleValue] > [kept[@"at"] doubleValue]) {
            NSMutableDictionary *updated = [kept mutableCopy];
            updated[@"at"] = run[@"finishedAt"];
            store[@"folders"][folder] = kept = updated;
            changed = YES;
        }
        // The port a deploy here gets in $PORT, for the set-up card to say before you confirm: kept nothing by reading.
        NSNumber *port = DeployPort(project, folder, NO);
        if (port) state[@"port"] = port;
        if (kept[@"at"]) state[@"at"] = kept[@"at"];
        if (self.cards[folder]) state[@"card"] = self.cards[folder];
        if (kept[@"skippedAt"]) state[@"skippedAt"] = kept[@"skippedAt"];
        if (run) state[@"run"] = run;
        folders[folder] = state;
    }
    if (changed) WriteStore(store);
    return @{@"projects": projects, @"folders": folders, @"inPlace": inPlace};
}

- (NSDictionary *)buildInPlaceFor:(NSString *)project {
    return project ? self.known[@"inPlace"][RealPath(project)] : nil;
}

// The page gets what was read, with the deploys sessions asked for, and your presses kept, added to their folders.
- (void)send:(NSDictionary *)deploys {
    self.known = deploys;
    NSMutableDictionary *folders = [deploys[@"folders"] mutableCopy] ?: [NSMutableDictionary dictionary];
    for (NSString *folder in self.asked) {
        NSMutableDictionary *state = [folders[folder] mutableCopy] ?: [NSMutableDictionary dictionary];
        state[@"asked"] = self.asked[folder];
        folders[folder] = state;
    }
    for (NSString *folder in self.keptShown) {
        NSMutableDictionary *state = [folders[folder] mutableCopy] ?: [NSMutableDictionary dictionary];
        state[@"kept"] = self.keptShown[folder];
        folders[folder] = state;
    }
    NSDictionary *shown = @{@"projects": deploys[@"projects"] ?: @{}, @"folders": folders};
    NSData *json = [NSJSONSerialization dataWithJSONObject:shown options:NSJSONWritingSortedKeys error:nil];
    NSString *text = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : nil;
    if (!text || [text isEqualToString:self.sent] || !self.page.ready) return;
    self.sent = text;
    [self.page call:@"setDeploys" with:@[shown]];
}

- (void)showAsked:(NSDictionary<NSString *, NSDictionary *> *)asked {
    if ([asked isEqual:self.asked] || (!asked.count && !self.asked.count)) return;
    self.asked = asked;
    if (self.known) [self send:self.known];
}

- (void)showKept:(NSDictionary<NSString *, NSDictionary *> *)kept {
    if ([kept isEqual:self.keptShown] || (!kept.count && !self.keptShown.count)) return;
    self.keptShown = kept;
    if (self.known) [self send:self.known];
}

- (Row *)listedRow:(NSString *)sessionId {
    for (Row *each in self.rows)
        if ([each.sessionId isEqual:sessionId]) return each;
    return nil;
}

// What a deploy starts from: only what your terminal gets from macOS when it opens (who and where you are, the
// system's own folders for commands, your keychain's ssh agent), never the rest of this app's environment, which is an
// agent's if a build an agent ran restarted the panel (its tokens, where it sends requests, Claude Code's marks, which
// build.sh reads). Your login shell sets up everything else, as it does in your terminal.
static NSDictionary<NSString *, NSString *> *DeployEnvironment(void) {
    NSDictionary<NSString *, NSString *> *own = NSProcessInfo.processInfo.environment;
    NSMutableDictionary<NSString *, NSString *> *environment = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"HOME", @"USER", @"LOGNAME", @"TMPDIR", @"LANG", @"SSH_AUTH_SOCK",
                            @"__CF_USER_TEXT_ENCODING"])
        if (own[key].length) environment[key] = own[key];
    environment[@"HOME"] = environment[@"HOME"] ?: Home();
    environment[@"USER"] = environment[@"USER"] ?: NSUserName();
    environment[@"LOGNAME"] = environment[@"LOGNAME"] ?: NSUserName();
    environment[@"SHELL"] = LoginShell();
    environment[@"PATH"] = @"/usr/bin:/bin:/usr/sbin:/sbin";
    return environment;
}

// Runs a project's saved command from a folder, detached, through your login shell (LoginShell) started from a clean
// environment (DeployEnvironment), with its output in the run's log and its exit status written beside it once it
// ends. Never a suggestion, only a command you saved; and one run at a time per folder: not while the last one's
// process is still there, even once it has been stopped. One a session asked for runs only while the command is still
// the one its switch was turned on for (`expecting`), and is noted with its name (`by`). It runs only while all that
// decides what it runs in this folder (DeployCheckText: its package scripts, the Makefile and what that includes, the
// files it runs) is what you confirmed (kept as its SHA-256, `runsHash`): changed since, by a branch or an agent, it
// doesn't run, and `reconfirm` says to show you the set-up card again; a session's ask is refused. A command confirmed
// before that was kept is confirmed once more the same way, unless it names nothing of these. A command confirmed with
// ports gets its folder's port in $PORT (DeployPort). On the queue. Returns why it didn't start, for the row, or nil.
- (NSString *)runIn:(NSString *)folder project:(NSString *)project expecting:(NSString *)expecting by:(NSString *)by
          reconfirm:(BOOL *)reconfirm {
    return [self runIn:folder project:project expecting:expecting by:by reconfirm:reconfirm install:nil];
}

- (NSString *)runIn:(NSString *)folder project:(NSString *)project expecting:(NSString *)expecting by:(NSString *)by
          reconfirm:(BOOL *)reconfirm install:(NSDictionary *)install {
    NSMutableDictionary *store = ReadStore();
    NSDictionary *saved = SavedEntry(store, project);
    NSString *command = saved[@"command"];
    if (!command.length) {
        PanelLog(@"deploy in %@: no command saved for %@", folder, project);
        return @"Deploy isn't set up for this project: set it up in ▾";
    }
    if (expecting && ![command isEqualToString:expecting]) {
        PanelLog(@"deploy in %@ asked by %@: not run, as the command changed", folder, by);
        return @"Couldn't deploy: the project's Deploy command changed since it was asked for";
    }
    if ([LastDeployRun(folder)[@"running"] boolValue]) return nil;  // the row already shows it running
    NSString *runs = DeployCheckText(folder, command), *confirmed = AsText(saved[@"runsHash"]);
    if (!confirmed && !runs.length) {
        // Nothing it runs is checked (a program whose own files decide what it does): nothing to confirm again.
        NSMutableDictionary *kept = [saved mutableCopy];
        kept[@"runsHash"] = TextHash(runs);
        store[@"projects"][RealPath(project)] = kept;
        WriteStore(store);
    } else if (![confirmed isEqualToString:TextHash(runs)]) {
        PanelLog(@"deploy in %@%@: not run, as %@", folder, by ? [NSString stringWithFormat:@" asked by %@", by] : @"",
                 confirmed ? @"what it runs there changed since it was confirmed" : @"what it runs wasn't confirmed yet");
        if (reconfirm) *reconfirm = !by;
        NSString *named = Clip(command, 60);
        if (!confirmed)
            return by ? [NSString stringWithFormat:@"Couldn't deploy: %@ needs confirming once more, as Deploy now checks "
                                                    @"what it runs, and only you can confirm it", named]
                      : [NSString stringWithFormat:@"Deploy now checks what %@ runs before each run: confirm it once "
                                                    @"more to deploy", named];
        return by ? [NSString stringWithFormat:@"Couldn't deploy: what %@ runs here has changed since it was confirmed, "
                                                @"and only you can confirm it again", named]
                  : [NSString stringWithFormat:@"What %@ runs here has changed since you confirmed it: confirm it "
                                                @"again to deploy", named];
    }
    // Install First's install, only as its card showed it: the same words, and all they run (the project's install
    // scripts, its lock file, the runner's settings) unchanged since. Else nothing runs, and the card's second step shows
    // what it runs now, to look at again.
    NSString *installs = nil;
    if (install) {
        NSDictionary *now = DeployInstallCheck(folder);
        if (![now[@"words"] isEqual:install[@"words"]] || ![now[@"hash"] isEqual:install[@"hash"]]) {
            PanelLog(@"deploy in %@: not run, as what Install First runs there changed since its card showed it", folder);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.page call:@"deployInstallChecked" with:@[folder, now, @YES]];
            });
            return @"What Install First runs here has changed since its card showed it: look at it again";
        }
        installs = now[@"words"];
    }
    NSNumber *port = SavedWithPorts(store, project) ? DeployPort(project, folder, YES) : nil;
    // What it puts in place, noted before it starts, so nothing the command does is taken for it.
    NSDictionary *build = BuildNow(folder);
    NSString *dir = RunDir(folder);
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700}
                        error:nil];
    for (NSString *name in @[@"status", kStopped, @"log", @"run.json", @"members.json", @"up.json", @"installed"])
        [fm removeItemAtPath:[dir stringByAppendingPathComponent:name] error:nil];
    NSString *status = [dir stringByAppendingPathComponent:@"status"];
    NSString *log = [dir stringByAppendingPathComponent:@"log"];
    NSNumber *startedAt = @(floor(NSDate.date.timeIntervalSince1970 * 1000));
    // Job control is off, as an interactive shell would otherwise put the command in a process group of its own,
    // out of reach of Stop Deploy (stop:). Install First's words, when given, run first, said at the log's start, and
    // the command only once they've gone through, which the marker beside the run notes (LastDeployRun).
    NSString *script = @"set +m; cd -- \"$1\" && { [ -z \"$4\" ] || { printf 'Installing packages first: %s\\n' \"$4\""
                       @" && eval \"$4\" && : > \"$5\"; }; } && eval \"$2\"; echo $? > \"$3\"";
    NSString *installed = [dir stringByAppendingPathComponent:@"installed"];
    NSString *shell = LoginShell();
    // Once it ends, the panel looks again at once, rather than when it next would, so the check shows on time.
    __weak Deploys *weakSelf = self;
    NSMutableDictionary *environment = [DeployEnvironment() mutableCopy];
    if (port) environment[@"PORT"] = port.stringValue;
    pid_t pid = SpawnDetached(shell, @[@"-l", @"-i", @"-c", script, shell.lastPathComponent, folder, command, status,
                                       installs ?: @"", installed],
                              environment, log, ^{
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf resend]; });
    });
    if (!pid) {
        PanelLog(@"deploy in %@: couldn't start %@", folder, shell);
        [[NSString stringWithFormat:@"Couldn't start %@\n", shell] writeToFile:log atomically:YES
                                                                     encoding:NSUTF8StringEncoding error:nil];
        [@"1\n" writeToFile:status atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    // With when its process started, so a later process given the same pid isn't taken for it (LastDeployRun).
    long long processStart = ProcessStartedAt(pid);
    NSMutableDictionary *run = [@{@"folder": folder, @"command": command, @"startedAt": startedAt, @"pid": @(pid)}
                                mutableCopy];
    if (processStart) run[@"processStart"] = @(processStart);
    if (by) run[@"by"] = by;
    if (port) run[@"port"] = port;
    if (installs) run[@"installs"] = installs;
    [run addEntriesFromDictionary:build];
    [[NSJSONSerialization dataWithJSONObject:run options:0 error:nil]
        writeToFile:[dir stringByAppendingPathComponent:@"run.json"] atomically:YES];
    // The command's words never go in the log, as one may carry a token: only where it ran, and how long it is. Install
    // First's install is one of a few fixed commands (DeployInstallWords), never text from the project, so it's named,
    // as what starts now: the command runs only if it goes through.
    NSString *askedBy = by ? [NSString stringWithFormat:@", asked by “%@”", by] : @"";
    if (installs)
        PanelLog(@"deploy in %@ of %@%@: installs its packages with %@, then runs the command you confirmed (%lu "
                 @"characters)", folder, project, askedBy, installs, (unsigned long)command.length);
    else
        PanelLog(@"deploy in %@ of %@%@: ran the command you confirmed (%lu characters)", folder, project, askedBy,
                 (unsigned long)command.length);
    return nil;
}

// Why a deploy can't start from this row now, or nil: it waits while the row's agent works, asks something or
// compacts, or another agent does in the same folder (WhyStepsWait), so what's put in place isn't half-way through a
// change. The page dims the button then; this holds even if a press gets through.
- (NSString *)whyNotNow:(Row *)row {
    return WhyStepsWait(row, self.rows, @"Deploy waits");
}

- (void)deploy:(Row *)row {
    [self deploy:row install:nil];
}

- (void)installAndDeploy:(Row *)row as:(NSDictionary *)shown {
    if (![shown isKindOfClass:NSDictionary.class] || !AsText(shown[@"words"]) || !AsText(shown[@"hash"])) return;
    [self deploy:row install:@{@"words": shown[@"words"], @"hash": shown[@"hash"]}];
}

- (void)checkInstallOf:(Row *)row {
    NSString *folder = DeployFolder(row);
    if (!folder) return;
    dispatch_async(self.queue, ^{
        NSDictionary *check = DeployInstallCheck(folder);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.page call:@"deployInstallChecked" with:@[folder, check, @NO]];
        });
    });
}

// A press, with Install First's install before the command when `install` gives what its card showed ({words, hash}),
// which runIn: checks is still what it runs.
- (void)deploy:(Row *)row install:(NSDictionary *)install {
    NSString *folder = DeployFolder(row), *project = DeployProject(row), *sid = row.sessionId;
    if (!folder || !project) return;
    NSString *wait = [self whyNotNow:row];
    if (wait) {
        [self.page stepNote:sid text:wait];
        return;
    }
    NSArray<NSDictionary *> *sessions = [self listedSessions];
    dispatch_async(self.queue, ^{
        // The port it would listen on, checked first: held by another build or program, a card says what, and what you
        // can do, and nothing runs yet.
        [self.cards removeObjectForKey:folder];
        NSDictionary *card = [self portCheckIn:folder project:project sessions:sessions];
        if (card) {
            // Install and Deploy's card remembers the install as its card showed it, so Use Port and Stop It and
            // Deploy do it too, checked again then.
            NSMutableDictionary *kept = [card mutableCopy];
            if (install) kept[@"install"] = install;
            self.cards[folder] = kept;
            dispatch_async(dispatch_get_main_queue(), ^{ [self resend]; });
            return;
        }
        BOOL reconfirm = NO;
        NSString *why = [self runIn:folder project:project expecting:nil by:nil reconfirm:&reconfirm
                            install:install];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (why) [self.page stepNote:sid text:why];
            // What the command runs has changed: the set-up card shows it again, to confirm before it runs.
            if (reconfirm) [self.page call:@"openDeploySetup" with:@[sid, @"deploy"]];
            [self resend];
        });
    });
}

// A row's folder's last run's log, opened as Open Log in the menu opens it.
- (void)openLogOf:(Row *)row {
    NSString *folder = DeployFolder(row);
    NSString *log = folder ? DeployLogPath(folder) : nil;
    if (log && [NSFileManager.defaultManager fileExistsAtPath:log])
        OpenInOtherApp([NSURL fileURLWithPath:log]);
}

// Worked out on the queue, as it reads the checkout's lock file, then copied on the main thread.
- (void)copyInstallOf:(Row *)row {
    NSString *folder = DeployFolder(row);
    if (!folder) return;
    dispatch_async(self.queue, ^{
        NSString *words = DeployInstallCommand(folder);
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSPasteboard.generalPasteboard clearContents];
            [NSPasteboard.generalPasteboard setString:words forType:NSPasteboardTypeString];
        });
    });
}

// Deploy's card for a folder, from what was last read (read:), or nil.
- (NSDictionary *)cardIn:(NSString *)folder {
    return folder ? AsRecord(self.known[@"folders"][folder][@"card"]) : nil;
}

// The sessions listed, as the port check names them: {sid, name, pid, start}, read on the main thread.
- (NSArray<NSDictionary *> *)listedSessions {
    NSMutableArray *sessions = [NSMutableArray array];
    for (Row *each in self.rows) {
        long long start = each.pid > 0 ? ProcessStartedAt(each.pid) : 0;
        if (start && each.sessionId)
            [sessions addObject:@{@"sid": each.sessionId, @"name": each.name.length ? each.name
                                                                                     : each.cwd.lastPathComponent ?: @"",
                                  @"pid": @(each.pid), @"start": @(start)}];
    }
    return sessions;
}

// Before a press runs, the port the build would listen on, and what holds it now, if anything: nil when it's free, or
// can't be told; else the card to show. The port is the checkout's own ($PORT, for a command confirmed with ports), or
// the one its last run listened on when that wasn't its $PORT (a server that picks its own), or for a command confirmed
// before ports, its last run's, or another of the project's builds' (they all take the server's own); the one any of
// the project's runs listened on when that wasn't its $PORT, for a server that picks its own. Held by another
// of Deploy's builds (its shell, or a member noted, by pid and start time): `clash`, naming that checkout, with the
// next free port when the server takes $PORT. Held by anything else: `held`, named only by its process name, with how
// long it has run, and the listed session that started it (walking its parents to a session's process that started
// before it), if any. On the queue.
- (NSDictionary *)portCheckIn:(NSString *)folder project:(NSString *)project sessions:(NSArray<NSDictionary *> *)sessions {
    NSDictionary *store = ReadStore();
    BOOL ports = SavedWithPorts(store, project);
    // What a run of the command confirmed now showed: one of another command says nothing of this one.
    NSString *command = SavedCommand(store, project);
    BOOL (^same)(NSString *) = ^BOOL(NSString *each) {
        NSDictionary *run = ReadJSON([RunDir(each) stringByAppendingPathComponent:@"run.json"]);
        return [run isKindOfClass:NSDictionary.class] && [run[@"command"] isEqual:command];
    };
    NSDictionary *last = same(folder) ? LastDeployRun(folder) : nil;
    NSNumber *lastUp = last[@"up"][@"port"], *given = last[@"port"];
    // A server that listens on a port of its own, whatever $PORT says, as this checkout's or another of the project's
    // runs of it showed: every checkout's takes that one.
    NSDictionary *folders = self.known[@"folders"] ?: @{};
    NSNumber *own = lastUp && given && ![lastUp isEqual:given] ? lastUp : nil, *running = nil;
    for (NSString *other in folders) {
        NSDictionary *run = folders[other][@"run"];
        if ([other isEqual:folder] || ![RealPath(ProjectRoot(other) ?: other) isEqual:RealPath(project)]) continue;
        if (!own && run[@"up"][@"port"] && run[@"port"] && ![run[@"up"][@"port"] isEqual:run[@"port"]] && same(other))
            own = run[@"up"][@"port"];
        if ([run[@"running"] boolValue] && run[@"up"][@"port"]) running = run[@"up"][@"port"];
    }
    BOOL fixed = own != nil;
    NSNumber *port = own ?: ports ? DeployPort(project, folder, NO) : running ?: lastUp;
    if (!port) return nil;
    NSDictionary *holder = PortHolder(port.intValue);
    if (!holder) return nil;
    for (NSString *other in folders) {
        if ([other isEqual:folder] || ![folders[other][@"run"][@"running"] boolValue]) continue;
        NSString *dir = RunDir(other);
        NSDictionary *run = ReadJSON([dir stringByAppendingPathComponent:@"run.json"]);
        NSMutableArray *theirs = [NotedMembers(dir) mutableCopy];
        if ([run[@"pid"] intValue] > 0 && run[@"processStart"])
            [theirs addObject:@{@"pid": run[@"pid"], @"start": run[@"processStart"]}];
        NSDictionary *who = @{@"pid": holder[@"pid"], @"start": holder[@"start"]};
        if (![theirs containsObject:who]) continue;
        NSMutableDictionary *card = [@{@"kind": @"clash", @"port": port, @"other": other.lastPathComponent,
                                       @"otherFolder": other} mutableCopy];
        if (fixed) card[@"fixed"] = @YES;
        if (!ports) card[@"old"] = @YES;
        NSNumber *next = ports && !fixed ? NextFreePort(project, [NSSet setWithObject:port]) : nil;
        if (next) card[@"next"] = next;
        return card;
    }
    NSMutableDictionary *card = [@{@"kind": @"held", @"port": port, @"name": holder[@"name"] ?: @"",
        @"minutes": @((long)((NSDate.date.timeIntervalSince1970 * 1e6 - [holder[@"start"] doubleValue]) / 60e6))}
        mutableCopy];
    NSNumber *next = ports && !fixed ? NextFreePort(project, [NSSet setWithObject:port]) : nil;
    if (next) card[@"next"] = next;
    // The listed session it descends from, if that session's process started before it.
    for (pid_t up = ProcessParent([holder[@"pid"] intValue]); up > 1; up = ProcessParent(up))
        for (NSDictionary *each in sessions)
            if ([each[@"pid"] intValue] == up && [each[@"start"] longLongValue] < [holder[@"start"] longLongValue]
                && ProcessStartedAt(up) == [each[@"start"] longLongValue]) {
                card[@"session"] = each[@"sid"];
                card[@"sessionName"] = each[@"name"];
                return card;
            }
    return card;
}

// What a press on Deploy's card does (the page's `deployCard`): close or cancel puts it away; `ports` opens the set-up
// card to confirm the command again with ports; `next` runs on the next free port, kept from now on, found again here
// (the page never names it), and if that's changed since the card showed it, the card shows the new one instead;
// `replace` stops the other of Deploy's builds on the port, then deploys here once it has ended, with the waits checked
// again then.
- (void)cardAct:(NSString *)act forRow:(Row *)row {
    NSString *folder = DeployFolder(row), *project = DeployProject(row), *sid = row.sessionId;
    if (!folder || !project || ![act isKindOfClass:NSString.class]) return;
    NSString *wait = [act isEqual:@"next"] || [act isEqual:@"replace"] ? [self whyNotNow:row] : nil;
    dispatch_async(self.queue, ^{
        NSDictionary *card = self.cards[folder];
        if (!card) return;
        if (wait) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self.page stepNote:sid text:wait]; });
            return;
        }
        if ([act isEqual:@"close"] || [act isEqual:@"cancel"]) {
            [self.cards removeObjectForKey:folder];
        } else if ([act isEqual:@"ports"] && card[@"old"]) {
            [self.cards removeObjectForKey:folder];
            dispatch_async(dispatch_get_main_queue(), ^{ [self.page call:@"openDeploySetup" with:@[sid, @"deploy"]]; });
        } else if ([act isEqual:@"next"] && card[@"next"]) {
            NSNumber *next = NextFreePort(project, [NSSet setWithObject:card[@"port"]]);
            if (!next) return;
            if (![next isEqual:card[@"next"]]) {
                NSMutableDictionary *again = [card mutableCopy];
                again[@"next"] = next;
                self.cards[folder] = again;
            } else {
                // The port settled (finding it can take a while), what a press waits for is checked again, on the
                // row as it's listed now, as Restart does: if it waits, the row says so and the card stays.
                dispatch_async(dispatch_get_main_queue(), ^{
                    Row *listed = nil;
                    for (Row *each in self.rows)
                        if ([each.sessionId isEqual:sid]) listed = each;
                    NSString *now = listed ? [self whyNotNow:listed] : @"its session is no longer listed";
                    if (now) {
                        PanelLog(@"deploy in %@: Not deployed on port %@: %@", folder, next, now);
                        [self.page stepNote:sid text:now];
                        [self resend];
                        return;
                    }
                    dispatch_async(self.queue, ^{
                        [self.cards removeObjectForKey:folder];
                        KeepDeployPort(project, folder, next);
                        PanelLog(@"deploy in %@: port %@ kept, as %@ was held", folder, next, card[@"port"]);
                        BOOL reconfirm = NO;
                        NSString *why = [self runIn:folder project:project expecting:nil by:nil reconfirm:&reconfirm
                                            install:AsRecord(card[@"install"])];
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (why) [self.page stepNote:sid text:why];
                            if (reconfirm) [self.page call:@"openDeploySetup" with:@[sid, @"deploy"]];
                            [self resend];
                        });
                    });
                });
            }
        } else if ([act isEqual:@"replace"] && card[@"otherFolder"]) {
            [self.cards removeObjectForKey:folder];
            [self stopIn:card[@"otherFolder"]];
            NSUUID *token = [NSUUID UUID];
            self.waiting[folder] = token;
            [self deployOnceEnded:row watching:card[@"otherFolder"] token:token install:AsRecord(card[@"install"])
                            tries:0];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ [self resend]; });
    });
}

- (void)deployAsked:(Row *)row in:(NSString *)folder expecting:(NSString *)command by:(NSString *)by {
    NSString *project = DeployProject(row), *sid = row.sessionId;
    if (!folder || !project || !command) return;
    NSArray<NSDictionary *> *sessions = [self listedSessions];
    dispatch_async(self.queue, ^{
        // The port checked first, as for a press. Held, by another of Deploy's builds or by a program, while the server
        // takes $PORT: the next free port, kept from now on, as Use Port does, and nothing of another's is stopped.
        // Otherwise (a server that picks its own port, a command confirmed before ports, or no free port) the card
        // waits for you, and the ask's status says so.
        [self.cards removeObjectForKey:folder];
        NSDictionary *card = [self portCheckIn:folder project:project sessions:sessions];
        NSNumber *next = card[@"next"];
        if (card && !next) {
            NSMutableDictionary *kept = [card mutableCopy];
            kept[@"asked"] = by ?: @"";
            self.cards[folder] = kept;
            PanelLog(@"deploy in %@ asked by “%@”: waits on its card, as port %@ is held", folder, by, card[@"port"]);
            dispatch_async(dispatch_get_main_queue(), ^{ [self resend]; });
            return;
        }
        if (next) {
            KeepDeployPort(project, folder, next);
            PanelLog(@"deploy in %@ asked by “%@”: port %@ kept, as %@ was held", folder, by, next, card[@"port"]);
        }
        NSString *why = [self runIn:folder project:project expecting:command by:by reconfirm:NULL];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (next && !why) self.moved[folder] = @{@"port": next, @"from": card[@"port"]};
            if (why) [self.page stepNote:sid text:why];
            [self resend];
        });
    });
}

- (NSDictionary *)movedIn:(NSString *)folder {
    return folder ? self.moved[folder] : nil;
}

- (void)save:(NSString *)command forRow:(Row *)row thenDeploy:(BOOL)deploy {
    command = [command isKindOfClass:NSString.class]
        ? [command stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : nil;
    NSString *folder = DeployFolder(row), *project = DeployProject(row), *sid = row.sessionId;
    if (!folder || !project) return;
    // One line, as the card's box takes it (and no longer than it lets you type): a command saved here is run as
    // written. The card has closed by now, so the row says why one wasn't saved.
    BOOL oneLine = [command rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location == NSNotFound;
    if (!command.length || command.length > 1000 || !oneLine) {
        PanelLog(@"deploy command for %@ not saved: %lu characters, %@", project, (unsigned long)command.length,
                 oneLine ? @"one line" : @"several lines");
        [self.page stepNote:sid text:@"Not saved: a deploy command is one line of up to 1,000 characters"];
        return;
    }
    NSString *wait = deploy ? [self whyNotNow:row] : nil;  // saved all the same; it runs on the next press
    dispatch_async(self.queue, ^{
        // With what it runs here, only if that's all as the card showed it (check:, for this row, this command), and
        // that the card said each checkout gets its own port, the one it showed being kept. Changed while the card was
        // open (or not shown at all), nothing is saved: the card shows it again.
        NSString *runs = DeployCheckText(folder, command);
        NSDictionary *shown = self.shown[sid];
        [self.shown removeObjectForKey:sid];
        if (![shown[@"command"] isEqual:command] || ![shown[@"runs"] isEqual:runs]) {
            PanelLog(@"deploy command for %@ not saved: what it runs isn't what the card showed", project);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.page stepNote:sid text:@"Not saved: what it runs changed while the card was open, so look again"];
                [self.page call:@"openDeploySetup" with:@[sid, deploy ? @"deploy" : @"save"]];
            });
            return;
        }
        NSMutableDictionary *store = ReadStore();
        store[@"projects"][RealPath(project)] = @{@"command": command, @"ports": @YES, @"runsHash": TextHash(runs),
                                                  @"savedAt": @(floor(NSDate.date.timeIntervalSince1970 * 1000))};
        // Refused by macOS, nothing is kept and nothing runs: the row says why, and the card opens again with the
        // command in it, saying why too for as long as it's open, to confirm once that's put right. The command goes
        // back only to the page that sent it. macOS's sentence goes after "Not saved:", without its full stop.
        NSString *refused = WriteStore(store);
        if (refused) {
            PanelLog(@"deploy command for %@ not saved: %@", project, refused);
            NSString *why = [refused hasSuffix:@"."] ? [refused substringToIndex:refused.length - 1] : refused;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.page stepNote:sid text:[@"Not saved: " stringByAppendingString:why]];
                [self.page call:@"openDeploySetup" with:@[sid, deploy ? @"deploy" : @"save", command, why]];
            });
            return;
        }
        DeployPort(project, folder, YES);
        PanelLog(@"deploy command for %@ set (%lu characters)", project, (unsigned long)command.length);
        NSString *why = !deploy ? nil : wait ?: [self runIn:folder project:project expecting:nil by:nil reconfirm:NULL];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (why) [self.page stepNote:sid text:why];
            [self resend];
        });
    });
}

- (void)skip:(Row *)row {
    NSString *folder = DeployFolder(row);
    if (!folder) return;
    dispatch_async(self.queue, ^{
        NSMutableDictionary *store = ReadStore();
        NSMutableDictionary *kept = [store[@"folders"][folder] isKindOfClass:NSDictionary.class]
            ? [store[@"folders"][folder] mutableCopy] : [NSMutableDictionary dictionary];
        kept[@"skippedAt"] = @(floor(NSDate.date.timeIntervalSince1970 * 1000));
        store[@"folders"][folder] = kept;
        WriteStore(store);
        dispatch_async(dispatch_get_main_queue(), ^{ [self resend]; });
    });
}

// Forget Deploy Command: the project goes back to having only Whozmove's suggestion, if it has one, offered after
// new work.
- (void)forget:(Row *)row {
    NSString *project = DeployProject(row);
    if (!project) return;
    dispatch_async(self.queue, ^{
        NSMutableDictionary *store = ReadStore();
        [store[@"projects"] removeObjectForKey:RealPath(project)];
        WriteStore(store);
        PanelLog(@"deploy command for %@ forgotten", project);
        dispatch_async(dispatch_get_main_queue(), ^{ [self resend]; });
    });
}

// Stops the folder's run, and whatever it started. The shell running the command is ended outright, so nothing more of
// the command starts: told to end, it would go on to the next part of it (an interactive shell takes no notice, and
// neither does one the command told to ignore it). The rest of the run's process group (SpawnDetached), what the
// command started, is told to end, so each part can finish cleanly, and what was in it as you stopped it, still there
// 2s later, is made to, one by one, by pid and start time. Once the shell has gone (a server it left running in the
// background, say), the group's id could be anyone's: then only the members noted while it ran (NoteRunUp) are told,
// each while it's still the process it was. The marker beside the run says you stopped it, whatever status its shell
// got to write.
- (void)stop:(Row *)row {
    NSString *folder = DeployFolder(row);
    if (!folder) return;
    dispatch_async(self.queue, ^{
        // Stopped: a Restart waiting for the run before to end no longer deploys.
        if (self.waiting[folder]) PanelLog(@"deploy in %@: the restart waiting there called off", folder);
        [self.waiting removeObjectForKey:folder];
        [self stopIn:folder];
    });
}

// Stop Deploy for a folder's run, on the queue.
- (void)stopIn:(NSString *)folder {
    {
        NSString *dir = RunDir(folder);
        NSDictionary *run = ReadJSON([dir stringByAppendingPathComponent:@"run.json"]);
        if (![LastDeployRun(folder)[@"running"] boolValue] || ![run isKindOfClass:NSDictionary.class]) return;
        pid_t pid = [run[@"pid"] intValue];
        if (pid <= 0) return;
        // Ended outright only while it's surely the run's own shell, by when it started: never a later process given
        // its pid.
        BOOL own = ProcessStartedAt(pid) == [run[@"processStart"] longLongValue];
        // What's made to stop 2 seconds later is only what's here now, each by its pid and start time, never a later
        // run's or a stranger's: the members noted, and while its shell is its own, all its group has as you stop it.
        NSArray<NSDictionary *> *members = LiveMembers(dir);
        NSMutableArray<NSDictionary *> *targets = [members mutableCopy];
        if (own) {
            for (NSDictionary *each in GroupMembers(pid))
                if (![targets containsObject:each]) [targets addObject:each];
            kill(pid, SIGKILL);
            killpg(pid, SIGTERM);
        } else if (members.count) {
            for (NSDictionary *member in members) kill([member[@"pid"] intValue], SIGTERM);
        } else {
            PanelLog(@"deploy in %@: couldn't stop it (%d)", folder, pid);
            return;
        }
        [kStopped writeToFile:[dir stringByAppendingPathComponent:kStopped] atomically:YES
                     encoding:NSUTF8StringEncoding error:nil];
        PanelLog(@"deploy in %@: stopped%@", folder, own ? @"" : @", what its shell left running");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kStopGrace * NSEC_PER_SEC), self.queue, ^{
            BOOL went = NO;
            for (NSDictionary *member in StillThere(targets)) {
                kill([member[@"pid"] intValue], SIGKILL);
                went = YES;
            }
            if (went) PanelLog(@"deploy in %@: made to stop, as it went on after being told", folder);
            // The row shows Deploy ready again once all of it has ended.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
                [self resend];
            });
        });
        dispatch_async(dispatch_get_main_queue(), ^{ [self resend]; });
    }
}

- (void)check:(NSString *)command forRow:(Row *)row {
    NSString *folder = DeployFolder(row), *sid = row.sessionId;
    if (![command isKindOfClass:NSString.class] || !sid) return;
    dispatch_async(self.queue, ^{
        // What the card is shown, and in full what's kept as it's confirmed, worked out once, which saving it checks
        // against (save:).
        NSString *kept = nil;
        NSDictionary *check = CheckDeployKeeping(folder, command, &kept);
        self.shown[sid] = @{@"command": command, @"runs": kept ?: @""};
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.page call:@"deployChecked" with:@[sid ?: @"", check ?: @{}]];
        });
    });
}

- (NSString *)commandFor:(Row *)row {
    NSString *project = DeployProject(row);
    return project ? AsText(self.known[@"projects"][project][@"command"]) : nil;
}

- (NSDictionary *)runIn:(NSString *)folder {
    return folder ? AsRecord(self.known[@"folders"][folder][@"run"]) : nil;
}

- (void)settle {
    dispatch_sync(self.queue, ^{});
}

- (void)readNowFor:(NSArray<Row *> *)rows {
    self.rows = rows;
    NSMutableDictionary<NSString *, NSString *> *projectOf = [NSMutableDictionary dictionary];
    for (Row *row in rows)
        if (DeployFolder(row)) projectOf[DeployFolder(row)] = DeployProject(row);
    self.known = [self read:projectOf];
}

// From what was last read (known), so ▾ opens at once.
- (NSDictionary *)stateOf:(Row *)row {
    NSString *folder = DeployFolder(row), *project = DeployProject(row);
    NSDictionary *known = self.known;
    NSDictionary *saved = project ? known[@"projects"][project] : nil, *here = folder ? known[@"folders"][folder] : nil;
    NSMutableDictionary *state = [NSMutableDictionary dictionary];
    if (saved[@"command"]) state[@"command"] = saved[@"command"];
    if (here[@"suggested"]) state[@"suggested"] = here[@"suggested"];
    if (here[@"run"]) {
        state[@"running"] = here[@"run"][@"running"] ?: @NO;
        state[@"log"] = [RunDir(folder) stringByAppendingPathComponent:@"log"];
        if ([here[@"run"][@"running"] boolValue] && here[@"run"][@"up"]) state[@"up"] = here[@"run"][@"up"];
    }
    return state;
}

// The address of a row's folder's build that's up, made only from the port Deploy read it listening on (never from the
// page, or the log): http://localhost:<port>, or nil.
- (NSURL *)addressOf:(Row *)row {
    NSString *folder = DeployFolder(row);
    NSDictionary *run = folder ? self.known[@"folders"][folder][@"run"] : nil;
    NSNumber *port = [run[@"running"] boolValue] && [run[@"up"] isKindOfClass:NSDictionary.class] ? run[@"up"][@"port"]
                                                                                                 : nil;
    if (![port isKindOfClass:NSNumber.class] || port.intValue < 1 || port.intValue > 65535) return nil;
    return [NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%d", port.intValue]];
}

- (void)openAddress:(Row *)row {
    NSURL *address = [self addressOf:row];
    if (!address) return;
    if (!OpenInWebBrowser(address)) [self.page stepNote:row.sessionId text:@"Couldn't open it: no app opens web pages"];
}

// Restart: Stop Deploy, then, once that run has ended (what it started given its 2 seconds), the same deploy a press
// makes, with the same waits, checked before it stops and again before it starts.
- (void)restart:(Row *)row {
    NSString *folder = DeployFolder(row), *project = DeployProject(row), *sid = row.sessionId;
    if (!folder || !project) return;
    NSString *wait = [self whyNotNow:row];
    if (wait) {
        [self.page stepNote:sid text:wait];
        return;
    }
    NSUUID *token = [NSUUID UUID];
    dispatch_async(self.queue, ^{
        self.waiting[folder] = token;
        [self stopIn:folder];
    });
    [self deployOnceEnded:row watching:folder token:token install:nil tries:0];
}

- (BOOL)deployWaitsIn:(NSString *)folder {
    __block BOOL waits = NO;
    dispatch_sync(self.queue, ^{ waits = self.waiting[folder] != nil; });
    return waits;
}

// On the queue: whether the deploy waiting in a folder is still this one (not called off by Stop Deploy, nor replaced),
// and, as it ends, its place given up.
- (BOOL)stillWaits:(NSString *)folder token:(NSUUID *)token {
    return [self.waiting[folder] isEqual:token];
}

- (void)endWait:(NSString *)folder token:(NSUUID *)token {
    if ([self.waiting[folder] isEqual:token]) [self.waiting removeObjectForKey:folder];
}

// Every half second, on the queue, for up to 10 seconds (restartTries looks): once the folder's run has ended, everything a press waits for
// is checked again (an agent may have started work there meanwhile), on the main thread, and only then does it deploy
// there. If it waits now, or the run before is still stopping after 10 seconds, the row says so, and the build stays
// stopped for the next press. Called off (Stop Deploy pressed there, or another taking its place: `token` is no longer
// the folder's waiting one), it ends there, at any of its steps. `install`: Stop It and Deploy from a card Install and
// Deploy met, so the checkout's packages go in first, as Install First's card showed them ({words, hash}, checked again
// by runIn:).
- (void)deployOnceEnded:(Row *)row watching:(NSString *)watched token:(NSUUID *)token install:(NSDictionary *)install
                  tries:(int)tries {
    NSString *folder = DeployFolder(row), *project = DeployProject(row), *sid = row.sessionId;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), self.queue, ^{
        if (![self stillWaits:folder token:token]) return;
        if ([LastDeployRun(watched)[@"running"] boolValue]) {
            if (tries < self.restartTries) {
                [self deployOnceEnded:row watching:watched token:token install:install tries:tries + 1];
                return;
            }
            [self endWait:folder token:token];
            PanelLog(@"deploy in %@: Not restarted: the build before is still stopping", folder);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.page stepNote:sid text:@"Not restarted: the build before is still stopping"];
                [self resend];
            });
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            // The row as it's listed now, not as it was at the press: its own session may have started a turn, or an
            // agent in the background, meanwhile. One no longer listed isn't restarted.
            Row *listed = nil;
            for (Row *each in self.rows)
                if ([each.sessionId isEqual:sid]) listed = each;
            NSString *wait = listed ? [self whyNotNow:listed] : @"its session is no longer listed";
            if (wait) {
                PanelLog(@"deploy in %@: Not restarted: %@", folder, wait);
                [self.page stepNote:sid text:[NSString stringWithFormat:@"Not restarted: %@", wait]];
                [self resend];
                dispatch_async(self.queue, ^{ [self endWait:folder token:token]; });
                return;
            }
            dispatch_async(self.queue, ^{
                // Stop Deploy may have been pressed while the main thread checked.
                if (![self stillWaits:folder token:token]) return;
                [self endWait:folder token:token];
                BOOL reconfirm = NO;
                NSString *why = [self runIn:folder project:project expecting:nil by:nil reconfirm:&reconfirm
                                    install:install];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (why) [self.page stepNote:sid text:why];
                    if (reconfirm) [self.page call:@"openDeploySetup" with:@[sid, @"deploy"]];
                    [self resend];
                });
            });
        });
    });
}

@end
