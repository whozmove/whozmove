// AsideReads: what a side question's copy may do, decided by Whozmove's own checker before each tool it reaches for.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "AsideReads.h"
#import <signal.h>
#import <unistd.h>
#import "Files.h"
#import "Git.h"
#import "ClaudeCodeFacts.h"

// How long the checker has to decide before it refuses by itself: the hook's own timeout is far longer
// (kClaudeAsideHookTimeout), as Claude Code runs the tool when a hook is still running at it.
static const unsigned kCheckWithin = 5;

// A path as it really is, links followed; nil when it isn't there, so nothing that can't be resolved is let through.
static NSString *Resolved(NSString *path) {
    if (!path.length) return nil;
    char *real = realpath(path.fileSystemRepresentation, NULL);
    if (!real) return nil;
    NSString *resolved = [NSFileManager.defaultManager stringWithFileSystemRepresentation:real length:strlen(real)];
    free(real);
    return resolved;
}

// Inside `folder` by whole path components, both already real.
static BOOL Inside(NSString *path, NSString *folder) {
    NSString *top = [folder hasSuffix:@"/"] ? folder : [folder stringByAppendingString:@"/"];
    return [path isEqualToString:folder] || [path hasPrefix:top];
}

// In one of the places in the home folder where keys are kept: Keys' own (KeyPlaces), and Claude Code's sign-in, its
// state and its settings, which are this module's.
static BOOL KeyPlace(NSString *path, NSString *home, id<KeyPlaces> keys) {
    if (!home.length) return NO;
    NSString *claude = [home stringByAppendingPathComponent:kClaudeCodeFolder];
    NSString *credentials = [kClaudeCodeFolder stringByAppendingPathComponent:kClaudeCodeCredentials];
    for (NSString *place in [@[kClaudeCodeState, credentials] arrayByAddingObjectsFromArray:keys.keyPlacesInHome])
        if (Inside(path, [home stringByAppendingPathComponent:place])) return YES;
    // Claude Code's own settings: settings.json and settings.local.json, and any other it may add beside them.
    NSString *name = path.lastPathComponent;
    return [path.stringByDeletingLastPathComponent isEqualToString:claude]
        && [name hasPrefix:kClaudeCodeSettings.stringByDeletingPathExtension] && [name hasSuffix:@".json"];
}

BOOL AsideKeyFile(NSString *path, NSString *home, id<KeyPlaces> keys) {
    if (!path.length) return NO;
    // Without Keys' list, no file can be told from one that holds keys, so every one counts.
    if (!keys) return YES;
    NSString *real = Resolved(path), *realHome = Resolved(home) ?: home;
    for (NSString *each in real ? @[path, real] : @[path])
        if ([keys isKeyFile:each] || KeyPlace(each, home, keys) || KeyPlace(each, realHome, keys)) return YES;
    return NO;
}

// A path a tool was given, as it really is, from the folder when it isn't a whole path; nil when it can't be resolved.
static NSString *Given(NSString *path, NSString *folder) {
    if ([path hasPrefix:@"~"]) return nil;
    return Resolved([path hasPrefix:@"/"] ? path : [folder stringByAppendingPathComponent:path]);
}

// Why a file git ignores can't be read: what a project keeps out of git is where its own secrets often are (a token in
// .npmrc, a deploy key), whatever their names. Asked from the session's own folder, even one inside a checkout (a
// package in a larger repository), whose .gitignore holds there too: check-ignore answers only yes or no about the
// ignore rules, so it reads nothing else of the checkout above, as git's other commands would. In no checkout, nothing
// is ignored; refused whenever else git can't say.
static NSString *IgnoredWhyNot(NSString *path, NSString *real, NSString *folder) {
    if ([real isEqualToString:folder]) return nil;
    NSDictionary *ran = RunGit(@[@"-C", folder, @"check-ignore", @"-q", @"--",
                                 [real substringFromIndex:folder.length + 1]]);
    NSNumber *status = ran[@"status"];
    if (status && status.intValue == 1) return nil;
    if (status && status.intValue == 128 && [ran[@"err"] containsString:@"not a git repository"]) return nil;
    return status && status.intValue == 0
        ? [NSString stringWithFormat:@"%@ is one git ignores, where a project keeps its own secrets", path]
        : [NSString stringWithFormat:@"Whozmove couldn't ask git whether it ignores %@", path];
}

// How many files a search over a folder is checked against at most, so the checker decides well within kCheckWithin.
static const NSUInteger kSearchChecksAtMost = 20000;

// The first file where keys are kept that a Grep over the folder `real` would search, as a path from `top`; @"" when
// there's none, and nil with why not in `why` when Whozmove can't tell. Over a folder, even a Grep that prints only
// which files match, or how many lines, says whether a key file holds what it looked for, and asked round after round
// that spells the key out. In a checkout, the files git lists as tracked or not ignored, as ripgrep keeps to the same
// ignore files (and leaves out more, never fewer); a folder git lists whole (a checkout inside it, not tracked), a
// folder in or under another checkout inside this one, and a folder in no checkout, every file in it, as Grep reads
// them, following no link. A link is checked as its name and as the file it leads to.
static NSString *KeyFileSearched(NSString *real, NSString *top, NSString *home, id<KeyPlaces> keys, NSString **why) {
    NSMutableArray<NSString *> *names = [NSMutableArray array], *folders = [NSMutableArray array];
    NSFileManager *files = NSFileManager.defaultManager;
    // In another checkout inside this one (one it doesn't track, or a submodule), this one's git lists nothing of what
    // ripgrep reads there by that checkout's own rules: so a folder at or under a .git below the top is walked whole.
    BOOL inner = NO;
    for (NSString *at = real; at.length > top.length && Inside(at, top); at = at.stringByDeletingLastPathComponent)
        if ([files fileExistsAtPath:[at stringByAppendingPathComponent:@".git"]]) inner = YES;
    NSMutableArray<NSString *> *arguments = [@[@"-C", top] mutableCopy];
    [arguments addObjectsFromArray:GitReadOnlyArguments()];
    // So git leaves out no more than ripgrep does: ripgrep matches ignore files' patterns case by case (a .ENV line in
    // .gitignore leaves .env to it), whatever the checkout's core.ignorecase says; and it reads no ignore file named
    // by core.excludesFile in the checkout's own config, the system's or one they include, only the one in the home
    // folder's, so git reads none, and lists what that one leaves out too.
    [arguments addObjectsFromArray:@[@"-c", @"core.ignorecase=false", @"-c", @"core.excludesFile=", @"ls-files", @"-z",
                                     @"--cached", @"--others", @"--exclude-standard", @"--"]];
    if (![real isEqualToString:top]) [arguments addObject:[real substringFromIndex:top.length + 1]];
    NSDictionary *ran = inner ? nil : RunGit(arguments);
    NSNumber *status = ran[@"status"];
    NSString *listed = status.intValue == 0 ? [[NSString alloc] initWithData:ran[@"out"] encoding:NSUTF8StringEncoding]
                                            : nil;
    if (inner) {
        [folders addObject:real];
    } else if (status && listed) {
        for (NSString *name in [listed componentsSeparatedByString:@"\0"])
            if (name.length) [names addObject:name];
    } else if (status && status.intValue == 128 && [ran[@"err"] containsString:@"not a git repository"]) {
        [folders addObject:real];
    } else {
        *why = @"Whozmove couldn't ask git which files that would search";
        return nil;
    }
    NSUInteger checked = 0;
    NSString *tooMany = @"that folder has too many files to check: search a folder further down";
    for (NSString *name in names) {
        NSString *path = [top stringByAppendingPathComponent:name];
        BOOL isFolder = NO;
        if ([name hasSuffix:@"/"] || ([files fileExistsAtPath:path isDirectory:&isFolder] && isFolder
                                      && ![[files attributesOfItemAtPath:path error:nil].fileType
                                           isEqual:NSFileTypeSymbolicLink])) {
            [folders addObject:path];
            continue;
        }
        if (++checked > kSearchChecksAtMost) { *why = tooMany; return nil; }
        if (AsideKeyFile(path, home, keys)) return name;
    }
    // A folder the checker can't read is skipped, as Grep, run as the same person, can't read it either.
    for (NSString *folder in folders) {
        NSDirectoryEnumerator<NSString *> *walk = [files enumeratorAtPath:folder];
        for (NSString *each in walk) {
            if ([walk.fileAttributes.fileType isEqual:NSFileTypeDirectory]) {
                if ([ClaudeGrepSkips() containsObject:each.lastPathComponent]) [walk skipDescendants];
                continue;
            }
            if (++checked > kSearchChecksAtMost) { *why = tooMany; return nil; }
            NSString *path = [folder stringByAppendingPathComponent:each];
            if (AsideKeyFile(path, home, keys)) return [path substringFromIndex:top.length + 1];
        }
    }
    return @"";
}

// Why a path a tool was given can't be read, or nil when it can; with `contents`, for a tool that reads what's in it.
static NSString *PathWhyNot(NSString *path, NSString *folder, NSString *home, id<KeyPlaces> keys, BOOL contents) {
    NSString *real = Given(path, folder);
    if (!real) return [NSString stringWithFormat:@"%@ isn't there, or isn't a path in the project's folder", path];
    if (!Inside(real, folder)) return [NSString stringWithFormat:@"%@ is outside the project's folder", path];
    // Git's own folder, whose config can hold a remote's address with a token in it: read only through git.
    if ([[real substringFromIndex:folder.length].pathComponents containsObject:@".git"])
        return [NSString stringWithFormat:@"%@ is git's own, read only through git", path];
    if (AsideKeyFile(path, home, keys) || AsideKeyFile(real, home, keys))
        return [NSString stringWithFormat:@"%@ is where keys are kept", path];
    return contents ? IgnoredWhyNot(path, real, folder) : nil;
}

NSString *AsideToolWhyNot(NSString *tool, NSDictionary *input, NSString *folder, NSString *home, id<KeyPlaces> keys) {
    if (!keys) return @"Whozmove couldn't find where keys are kept";
    NSString *top = Resolved(folder), *realHome = Resolved(home) ?: home;
    if (!top || ![folder hasPrefix:@"/"]) return @"the session's folder can't be found";
    if (realHome.length && Inside(realHome, top))
        return @"this session works in the home folder, or above it, so a side question reads nothing";
    input = [input isKindOfClass:NSDictionary.class] ? input : @{};
    id (^field)(NSString *) = ^id(NSString *name) { return input[name]; };
    if ([tool isEqual:kClaudeToolRead]) {
        NSString *file = AsText(field(kClaudeToolFilePath));
        return file.length ? PathWhyNot(file, top, home, keys, YES) : @"Read was given no file";
    }
    if ([tool isEqual:kClaudeToolGrep] || [tool isEqual:kClaudeToolGlob]) {
        id path = field(kClaudeToolPath);
        if (path && !AsText(path)) return @"its path isn't words";
        NSString *why = AsText(path).length ? PathWhyNot(path, top, home, keys, [tool isEqual:kClaudeToolGrep]) : nil;
        if (why) return why;
        // A Grep filter overrides the ignore files, so it would search a key file the project keeps out of git.
        if ([tool isEqual:kClaudeToolGrep] && field(kClaudeToolGrepFilter))
            return @"a Grep may not filter by file name here, as that searches the files git ignores";
        // Over a folder, Grep searches every file in it that git doesn't ignore, a key file the project keeps too, so
        // its matching lines come only from one file, which passes as a Read would; which files match, and how many
        // lines, only from a folder with no key file in it.
        id mode = field(kClaudeToolGrepMode);
        if ([tool isEqual:kClaudeToolGrep]) {
            if (mode && ![mode isEqual:kClaudeGrepFiles] && ![mode isEqual:kClaudeGrepCount]
                && ![mode isEqual:kClaudeGrepContent])
                return @"a Grep may only find files, count or show lines";
            BOOL isFolder = NO;
            NSString *real = AsText(path).length ? Given(path, top) : top;
            if (!real || ![NSFileManager.defaultManager fileExistsAtPath:real isDirectory:&isFolder])
                return @"its path isn't there";
            if (isFolder && [mode isEqual:kClaudeGrepContent])
                return @"a Grep shows matching lines only from one file here, as a folder can hold one where keys are "
                        "kept: find the files first, then search or read each";
            if (isFolder) {
                NSString *cant = nil, *key = KeyFileSearched(real, top, home, keys, &cant);
                if (!key) return cant;
                if (key.length)
                    return [NSString stringWithFormat:@"that folder holds %@, where keys are kept: search one file at "
                                                      "a time, or a folder without one", key];
            }
        }
        if ([tool isEqual:kClaudeToolGlob]) {
            NSString *pattern = AsText(field(kClaudeToolPattern));
            // Claude Code searches a whole path's own folder, whatever `path` says.
            if (!pattern.length || [pattern hasPrefix:@"/"] || [pattern hasPrefix:@"~"]
                || [pattern containsString:@".."])
                return @"a Glob pattern may only name files from the project's folder down";
        }
        return nil;
    }
    if ([tool isEqual:kClaudeToolBash]) {
        if ([field(kClaudeToolInBackground) isEqual:@YES]) return @"nothing may run in the background";
        NSString *command = AsText(field(kClaudeToolCommand));
        if (!command) return @"Bash was given no command";
        // Outside a checkout `git diff` compares any two files it's given, and from a folder inside one git reads the
        // whole checkout, above the folder too: so git runs only where the folder is a checkout's top.
        if (!Resolved([top stringByAppendingPathComponent:@".git"]))
            return @"git runs only for a session at the top of a checkout, and this one isn't";
        return AsideGitWhyNot(command, top, keys);
    }
    return [NSString stringWithFormat:@"%@ isn't for a side question, which only reads, with Read, Grep, Glob and git",
                                      tool.length ? tool : @"That tool"];
}

// The command's words, each with whether it was single-quoted, or nil when it isn't one plain command.
static NSArray<NSArray *> *Words(NSString *command) {
    NSCharacterSet *plain = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./:=@^~,+%{}"];
    NSMutableArray<NSArray *> *words = [NSMutableArray array];
    NSUInteger at = 0, length = command.length;
    while (at < length) {
        unichar c = [command characterAtIndex:at];
        if (c == ' ') { at++; continue; }
        if (c == '\'') {
            NSRange close = [command rangeOfString:@"'" options:0 range:NSMakeRange(at + 1, length - at - 1)];
            if (close.location == NSNotFound) return nil;
            NSString *inside = [command substringWithRange:NSMakeRange(at + 1, close.location - at - 1)];
            if ([inside rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\\\n\r"]].location
                != NSNotFound)
                return nil;
            // A whole word: nothing joined to its quotes.
            if (NSMaxRange(close) < length && [command characterAtIndex:NSMaxRange(close)] != ' ') return nil;
            [words addObject:@[inside, @YES]];
            at = NSMaxRange(close);
            continue;
        }
        NSUInteger start = at;
        while (at < length && [command characterAtIndex:at] != ' ') {
            if (![plain characterIsMember:[command characterAtIndex:at]]) return nil;
            at++;
        }
        [words addObject:@[[command substringWithRange:NSMakeRange(start, at - start)], @NO]];
    }
    return words;
}

NSString *AsideGitWhyNot(NSString *command, NSString *folder, id<KeyPlaces> keys) {
    NSString *only = @"only git status, log, diff and show may run";
    NSArray<NSArray *> *words = Words(command ?: @"");
    if (!words) return [only stringByAppendingString:@", as one command of plain words"];
    if (words.count < 2 || ![words[0][0] isEqual:@"git"] || [words[0][1] boolValue] || [words[1][1] boolValue]
        || ![GitReadOnlyCommands() containsObject:words[1][0]])
        return [only stringByAppendingString:@", with nothing between git and the command"];
    NSMutableArray<NSString *> *arguments = [NSMutableArray array];
    for (NSArray *each in [words subarrayWithRange:NSMakeRange(1, words.count - 1)]) {
        NSString *word = each[0];
        [arguments addObject:word];
        if ([word hasPrefix:@"/"] || [word hasPrefix:@"~"] || [word hasPrefix:@"="] || [word hasPrefix:@"../"]
            || [word isEqual:@".."] || [word containsString:@"/../"] || [word hasSuffix:@"/.."]
            || [word containsString:@":/"] || [word containsString:@":../"])
            return [NSString stringWithFormat:@"%@ names something outside the project's folder", word];
        // A file named as keys are, as a path or at a commit (HEAD:.env); every word, without Keys' list.
        if (!keys || [keys isKeyFile:word])
            return [NSString stringWithFormat:@"%@ is where keys are kept", word];
        // What the shell would turn into other words: a ~ after = or :, and braces with a list or range in them.
        if (![each[1] boolValue] && ([word containsString:@"=~"] || [word containsString:@":~"]
                                     || ([word containsString:@"{"] && ([word containsString:@","]
                                                                        || [word containsString:@".."]))))
            return [NSString stringWithFormat:@"%@ would be changed by the shell", word];
    }
    // Which options only read is git's own (GitReadOnlyWhyNot); the words, their paths and the shell are the copy's.
    NSString *why = GitReadOnlyWhyNot(arguments);
    if (why) return why;
    // What git would print of files the project tracks or once did, asked of git itself: a file or folder by its id
    // (from a patch's index line), whatever it holds; and a patch, which may hold a key file the project committed
    // (.mcp.json often is), even one removed since.
    NSString *object = GitReadOnlyNotCommit(arguments, folder);
    if (object)
        return [NSString stringWithFormat:@"%@ isn't a commit, and git would show the file or folder it names whole",
                                          object];
    NSArray<NSString *> *shown = GitReadOnlyShownFiles(arguments, folder);
    if (!shown) return @"Whozmove couldn't ask git which files that would show";
    for (NSString *file in shown)
        if ([keys isKeyFile:file])
            return [NSString stringWithFormat:@"it would show what's in %@, where keys are kept: name the files to "
                                              "show after --", file];
    return nil;
}

static void TooLong(int signal) {
    static const char said[] = "Whozmove couldn't check this in time, so it isn't run\n";
    write(STDERR_FILENO, said, sizeof said - 1);
    _exit(2);
}

NSString *AsideCheck(NSString *folder, NSData *input, NSString *home, id<KeyPlaces> keys) {
    NSDictionary *call = [input isKindOfClass:NSData.class]
        ? [NSJSONSerialization JSONObjectWithData:input options:0 error:nil] : nil;
    NSString *why = [call isKindOfClass:NSDictionary.class]
        ? AsideToolWhyNot(AsText(call[kClaudeHookToolName]), call[kClaudeHookToolInput], folder, home, keys)
        : @"Whozmove couldn't read what this tool was given";
    return why ? [NSString stringWithFormat:@"A side question can't do this: %@. Answer from what you have.", why] : nil;
}

int AsideCheckRun(NSString *folder, NSString *home, id<KeyPlaces> keys) {
    // From before its input is read, so a call that never ends is refused too.
    signal(SIGALRM, TooLong);
    alarm(kCheckWithin);
    NSData *input = [NSFileHandle.fileHandleWithStandardInput readDataUpToLength:1024 * 1024 error:nil];
    NSString *refused = AsideCheck(folder, input, home, keys);
    alarm(0);
    if (!refused) return 0;
    fprintf(stderr, "%s\n", refused.UTF8String);
    return 2;
}
