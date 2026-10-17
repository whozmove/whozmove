// Edits: the files a session changed with Claude's edit tools and its shell commands, and the lines it wrote and took
// out, found in its transcript.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Edits.h"
#import "Files.h"
#import "Text.h"
#import "ClaudeCodeFacts.h"

// The most files a session's edits are kept for, and the most lines kept for each file, both ways: enough for a long
// session, and a bound on what one that rewrites everything can hold.
static const NSUInteger kFiles = 300, kLines = 20000;
// The most commands that run git kept, to know their results by.
static const NSUInteger kGitCalls = 500;

// A record's list, number or flag, as it should be, or nothing: a value of another kind (a null, say) is read as none
// rather than taken for what it isn't.
static NSArray *ListIn(NSDictionary *record, NSString *key) {
    id value = [record isKindOfClass:NSDictionary.class] ? record[key] : nil;
    return [value isKindOfClass:NSArray.class] ? value : @[];
}
static NSInteger NumberIn(NSDictionary *record, NSString *key) {
    id value = [record isKindOfClass:NSDictionary.class] ? record[key] : nil;
    return [value isKindOfClass:NSNumber.class] ? [value integerValue] : 0;
}
static BOOL FlagIn(NSDictionary *record, NSString *key) {
    id value = [record isKindOfClass:NSDictionary.class] ? record[key] : nil;
    return [value isKindOfClass:NSNumber.class] && [value boolValue];
}

// The lines a patch put in and took out ("+" and "-" lines), as LineKeys.
static void PatchLines(id patch, NSMutableArray *added, NSMutableArray *removed) {
    for (NSDictionary *hunk in [patch isKindOfClass:NSArray.class] ? patch : @[]) {
        id lines = [hunk isKindOfClass:NSDictionary.class] ? hunk[@"lines"] : nil;
        for (NSString *line in [lines isKindOfClass:NSArray.class] ? lines : @[]) {
            if (![line isKindOfClass:NSString.class] || !line.length) continue;
            unichar sign = [line characterAtIndex:0];
            NSNumber *key = sign == '+' || sign == '-' ? LineKey([line substringFromIndex:1]) : nil;
            if (key) [sign == '+' ? added : removed addObject:key];
        }
    }
}

// A text's lines, as LineKeys, into `lines`.
static void TextLines(id text, NSMutableArray *lines) {
    if (![text isKindOfClass:NSString.class]) return;
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSNumber *key = LineKey(line);
        if (key) [lines addObject:key];
    }
}

// The lines one replacement puts in and takes out: those of its new text that its old text doesn't have, and the other
// way round, so the lines it only repeats to say where it goes aren't counted.
static void ReplacementLines(id old, id new, NSMutableArray *added, NSMutableArray *removed) {
    NSMutableArray *before = [NSMutableArray array], *after = [NSMutableArray array];
    TextLines(old, before);
    TextLines(new, after);
    NSCountedSet *was = [[NSCountedSet alloc] initWithArray:before], *is = [[NSCountedSet alloc] initWithArray:after];
    for (NSNumber *key in after) {
        if ([was countForObject:key]) [was removeObject:key];
        else [added addObject:key];
    }
    for (NSNumber *key in before) {
        if ([is countForObject:key]) [is removeObject:key];
        else [removed addObject:key];
    }
}

// Whether an edited file is the session's work: a full path, and not one of Claude Code's own files in its folder in
// the home folder (memory, settings, the plans it keeps for plan mode). A project's own `.claude` folder, and the
// worktrees Claude Code makes in one, are work like any other.
static BOOL Counted(id path) {
    if (![path isKindOfClass:NSString.class] || ![path isAbsolutePath]) return NO;
    return ![[path stringByStandardizingPath] hasPrefix:[ClaudeDir(@"") stringByAppendingString:@"/"]];
}

// The lines a request asks to put in and take out: a Write's whole text, an Edit's or a MultiEdit's replacements.
// NO for any other tool.
static BOOL RequestLines(NSDictionary *item, NSMutableArray *added, NSMutableArray *removed) {
    NSDictionary *input = item[@"input"];
    if (![input isKindOfClass:NSDictionary.class]) return NO;
    if ([item[@"name"] isEqual:@"Write"]) {
        TextLines(input[@"content"], added);
        return YES;
    }
    if ([item[@"name"] isEqual:@"Edit"]) {
        ReplacementLines(input[@"old_string"], input[@"new_string"], added, removed);
        return YES;
    }
    if (![item[@"name"] isEqual:@"MultiEdit"] || ![input[@"edits"] isKindOfClass:NSArray.class]) return NO;
    for (NSDictionary *one in input[@"edits"])
        if ([one isKindOfClass:NSDictionary.class])
            ReplacementLines(one[@"old_string"], one[@"new_string"], added, removed);
    return YES;
}

// What a shell command's result says it changed, as edits: one for each file Claude Code recorded with its lines.
static NSArray<NSDictionary *> *ShellEdits(id content, id result, NSNumber *at, NSSet<NSString *> *git) {
    NSMutableArray *edits = [NSMutableArray array];
    id diff = [result isKindOfClass:NSDictionary.class] ? result[@"bashEditDiff"] : nil;
    if (![diff isKindOfClass:NSDictionary.class] || ![diff[@"files"] isKindOfClass:NSArray.class]) return edits;
    // Recorded while another process changed files in the checkout too: whose its lines are can't be told.
    if (FlagIn(diff, @"shared")) return edits;
    for (NSDictionary *item in [content isKindOfClass:NSArray.class] ? content : @[]) {
        if (![item isKindOfClass:NSDictionary.class] || ![item[@"type"] isEqual:@"tool_result"]) continue;
        id callId = item[@"tool_use_id"];
        if (![callId isKindOfClass:NSString.class] || [git containsObject:callId]) continue;
        for (NSDictionary *file in diff[@"files"]) {
            if (![file isKindOfClass:NSDictionary.class] || !Counted(file[@"filePath"])) continue;
            NSMutableArray *added = [NSMutableArray array], *removed = [NSMutableArray array];
            PatchLines(file[@"hunks"], added, removed);
            NSString *path = [file[@"filePath"] stringByStandardizingPath];
            [edits addObject:@{@"id": [NSString stringWithFormat:@"%@ %@", callId, path], @"path": path, @"at": at,
                               @"created": @(FlagIn(file, @"created")), @"added": added, @"removed": removed}];
        }
    }
    return edits;
}

// Each edit, from both places it's written down, as either can be missing: the request (Edit, MultiEdit and Write
// calls, with the text they put in) and its result, where Claude Code leaves the file's path and the patch it made
// (`structuredPatch`; a new file's is empty, and its content is all it put in). A turn that was interrupted or rewound
// can leave a request with no result, though the file was written; a result says exactly which lines changed. Both
// carry the call's id, so the edit counts once. A shell command's result carries what Claude Code recorded it changed
// (`bashEditDiff`), file by file, each counted as an edit of its own.
NSArray<NSDictionary *> *EditNews(NSData *chunk, NSUInteger end, NSSet<NSString *> *git) {
    NSMutableArray *edits = [NSMutableArray array];
    for (NSString *marker in @[@"\"structuredPatch\":", @"\"name\":\"Write\"", @"\"name\":\"Edit\"",
                               @"\"name\":\"MultiEdit\"", @"\"bashEditDiff\":", @"\"is_error\":true"]) {
        NSData *bytes = [marker dataUsingEncoding:NSUTF8StringEncoding];
        BOOL results = [marker hasPrefix:@"\"structuredPatch"], shell = [marker hasPrefix:@"\"bashEditDiff"];
        BOOL failures = [marker hasPrefix:@"\"is_error"];
        NSUInteger cursor = 0;
        while (cursor < end) {
            NSRange hit = [chunk rangeOfData:bytes options:0 range:NSMakeRange(cursor, end - cursor)];
            if (hit.location == NSNotFound) break;
            NSRange line;
            NSDictionary *entry = JSONLineAt(chunk, hit.location, end, &line);
            cursor = NSMaxRange(line) + 1;
            if (![entry isKindOfClass:NSDictionary.class]) continue;
            id message = entry[@"message"];
            id content = [message isKindOfClass:NSDictionary.class] ? message[@"content"] : nil;
            NSNumber *at = @(TimestampMs(entry[@"timestamp"]));
            NSDictionary *result = entry[@"toolUseResult"];
            if (shell) {
                [edits addObjectsFromArray:ShellEdits(content, result, at, git)];
                continue;
            }
            // A call that failed, or that you turned down: its request changed nothing, so what it asked for goes.
            if (failures) {
                for (NSDictionary *item in [content isKindOfClass:NSArray.class] ? content : @[])
                    if ([item isKindOfClass:NSDictionary.class] && [item[@"type"] isEqual:@"tool_result"]
                        && FlagIn(item, @"is_error") && [item[@"tool_use_id"] isKindOfClass:NSString.class])
                        [edits addObject:@{@"id": item[@"tool_use_id"], @"failed": @YES}];
                continue;
            }
            for (NSDictionary *item in [content isKindOfClass:NSArray.class] ? content : @[]) {
                if (![item isKindOfClass:NSDictionary.class]) continue;
                NSMutableArray *added = [NSMutableArray array], *removed = [NSMutableArray array];
                id callId, path;
                BOOL created = NO;
                if (results) {
                    if (![item[@"type"] isEqual:@"tool_result"] || FlagIn(item, @"is_error")
                        || ![result isKindOfClass:NSDictionary.class]
                        || ![result[@"structuredPatch"] isKindOfClass:NSArray.class])
                        continue;
                    callId = item[@"tool_use_id"];
                    path = result[@"filePath"];
                    created = [result[@"type"] isEqual:@"create"];
                    if (created) TextLines(result[@"content"], added);
                    else PatchLines(result[@"structuredPatch"], added, removed);
                } else {
                    if (![item[@"type"] isEqual:@"tool_use"] || !RequestLines(item, added, removed)) continue;
                    callId = item[@"id"];
                    path = item[@"input"][@"file_path"];
                }
                if (![callId isKindOfClass:NSString.class] || !Counted(path)) continue;
                [edits addObject:@{@"id": callId, @"path": [path stringByStandardizingPath], @"at": at,
                                   @"created": @(created), @"added": added, @"removed": removed}];
            }
        }
    }
    return edits;
}

void AddEditNews(NSMutableDictionary *state, NSArray<NSDictionary *> *news) {
    if (!news.count) return;
    NSMutableDictionary *files = state[@"edits"] ?: [NSMutableDictionary dictionary];
    NSMutableSet *ids = state[@"editIds"] ?: [NSMutableSet set], *failed = state[@"failedIds"] ?: [NSMutableSet set];
    // What each edit put into its file's lines, so an edit found to have failed can be taken back out.
    NSMutableDictionary *byEdit = state[@"editLines"] ?: [NSMutableDictionary dictionary];
    state[@"edits"] = files;
    state[@"editIds"] = ids;
    state[@"failedIds"] = failed;
    state[@"editLines"] = byEdit;
    for (NSDictionary *edit in news) {
        if ([edit[@"failed"] boolValue]) {
            [failed addObject:edit[@"id"]];
            NSDictionary *gone = byEdit[edit[@"id"]];
            NSMutableDictionary *file = gone ? files[gone[@"path"]] : nil;
            if (!file) continue;
            for (NSString *way in @[@"added", @"removed"])
                for (NSNumber *key in gone[way]) [file[way] removeObject:key];
            file[@"edits"] = @(MAX(0, [file[@"edits"] integerValue] - 1));
            [byEdit removeObjectForKey:edit[@"id"]];
            continue;
        }
        if ([failed containsObject:edit[@"id"]]) continue;
        NSMutableDictionary *file = files[edit[@"path"]];
        if (!file) {
            if (files.count >= kFiles) continue;
            // Counted, so the same line put in by two edits stays while either does.
            file = [@{@"path": edit[@"path"], @"edits": @0, @"created": @NO,
                      @"added": [NSCountedSet set], @"removed": [NSCountedSet set]} mutableCopy];
            files[edit[@"path"]] = file;
        }
        // An edit's request and its result each add the lines they name; it counts as one edit.
        if (![ids containsObject:edit[@"id"]]) file[@"edits"] = @([file[@"edits"] integerValue] + 1);
        [ids addObject:edit[@"id"]];
        if ([edit[@"created"] boolValue]) file[@"created"] = @YES;
        // A sub-agent's record is read after the session's own, so its edits can come in out of order.
        if ([edit[@"at"] doubleValue] > [file[@"at"] doubleValue]) file[@"at"] = edit[@"at"];
        NSMutableDictionary *mine = byEdit[edit[@"id"]] ?: (byEdit[edit[@"id"]] = [@{@"path": edit[@"path"],
            @"added": [NSMutableArray array], @"removed": [NSMutableArray array]} mutableCopy]);
        for (NSString *way in @[@"added", @"removed"]) {
            NSCountedSet *lines = file[way];
            for (NSNumber *key in edit[way]) {
                if (lines.count >= kLines) break;
                [lines addObject:key];
                [mine[way] addObject:key];
            }
        }
    }
}

// How a shell command uses git. A git command is found anywhere it starts a command (at the start, after a separator,
// as `cd … && git …`), after settings for it (`GIT_EDITOR=true git …`), behind the commands that run another (`env`,
// `command`, `exec`, `sudo`, `xargs`, `time`, `nice`, `nohup`, with their options), or by its path (`/usr/bin/git`);
// the text a command hands a program in a here-document (`<<'EOF'` … `EOF`) isn't run by the shell, so a "git"
// written there doesn't count. `brings`: one of them brings in work that's there already (a merge, a rebase, a
// checkout, a stash, or a git command Whozmove doesn't know, an alias, say), so what the command changed isn't the
// session's. `only`: it's git commands alone (with `cd`, and output read through `head`, `grep` and the like), which
// change no file but by git's own steps.
typedef struct { BOOL brings, only; } GitUse;
static GitUse UsesGit(id command) {
    GitUse use = {NO, NO};
    if (![command isKindOfClass:NSString.class]) return use;
    static NSRegularExpression *git, *hereDocument, *cd, *reader;
    static NSSet *keeps;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *start = @"(\\w+=\\S*\\s+)*((sudo|env|command|exec|xargs|time|nice|nohup)(\\s+-\\S+)*\\s+"
                          @"(\\w+=\\S*\\s+)*)*(\\S*/)?git(\\s+|$)";
        git = [NSRegularExpression regularExpressionWithPattern:[@"(^|[;&|(\\n`{]|\\$\\()\\s*" stringByAppendingString:start]
                                                        options:0 error:nil];
        hereDocument = [NSRegularExpression regularExpressionWithPattern:
                        @"<<-?\\s*(['\"]?)(\\w+)\\1[^\\n]*\\n.*?\\n\\s*\\2(?=\\s|$)"
                                                                 options:NSRegularExpressionDotMatchesLineSeparators
                                                                   error:nil];
        cd = [NSRegularExpression regularExpressionWithPattern:@"^\\s*(cd(\\s.*)?)?$" options:0 error:nil];
        reader = [NSRegularExpression regularExpressionWithPattern:
                  @"^\\s*(head|tail|grep|wc|cut|sort|uniq|cat|less|more|tr|column)(\\s|$)" options:0 error:nil];
        // The git commands that change no file, or change one as the session's own step (adding, removing, moving or
        // applying a patch it wrote): the rest bring in work from elsewhere.
        keeps = [NSSet setWithArray:@[@"status", @"diff", @"log", @"show", @"grep", @"blame", @"rev-parse", @"ls-files",
                                      @"ls-tree", @"branch", @"remote", @"config", @"describe", @"shortlog", @"cat-file",
                                      @"rev-list", @"reflog", @"fetch", @"add", @"commit", @"push", @"rm", @"mv",
                                      @"apply", @"clean", @"tag", @"init", @"help", @"version", @"notes", @"for-each-ref",
                                      @"symbolic-ref", @"show-ref", @"name-rev", @"merge-base", @"var", @"check-ignore",
                                      @"count-objects", @"whatchanged", @"show-branch", @"archive", @"format-patch"]];
    });
    NSString *run = [hereDocument stringByReplacingMatchesInString:command options:0
                                                             range:NSMakeRange(0, [command length]) withTemplate:@"<<"];
    NSArray<NSTextCheckingResult *> *found = [git matchesInString:run options:0 range:NSMakeRange(0, run.length)];
    if (!found.count) return use;
    for (NSTextCheckingResult *hit in found) {
        // Its command: the first word after git's own options (`-C dir`, `-c name=value`, `--no-pager`, …).
        NSArray *words = [[run substringFromIndex:NSMaxRange(hit.range)]
                          componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *verb = nil;
        for (NSUInteger i = 0; i < words.count && !verb; i++) {
            NSString *word = words[i];
            if (!word.length) continue;
            if ([word isEqualToString:@"-C"] || [word isEqualToString:@"-c"] || [word isEqualToString:@"--git-dir"]
                || [word isEqualToString:@"--work-tree"] || [word isEqualToString:@"--namespace"]) { i++; continue; }
            if ([word hasPrefix:@"-"]) continue;
            verb = [word stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@";&|)`'\""]];
        }
        if (verb.length && ![keeps containsObject:verb]) use.brings = YES;
    }
    // Git alone: every part of the command is git, a `cd`, or a reader of what git printed.
    use.only = YES;
    for (NSString *part in [run componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@";&|\n"]]) {
        NSRange all = NSMakeRange(0, part.length);
        if ([cd firstMatchInString:part options:0 range:all] || [reader firstMatchInString:part options:0 range:all]) continue;
        NSTextCheckingResult *hit = [git firstMatchInString:part options:0 range:all];
        if (!hit || [[part substringToIndex:hit.range.location] stringByTrimmingCharactersInSet:
                     NSCharacterSet.whitespaceCharacterSet].length) { use.only = NO; break; }
    }
    return use;
}

// What a shell command's record leaves out. A command that changed more files than Claude Code records with their
// lines names the rest (`changedFiles`), so only those are in doubt, added to `doubts`; so are the files of a record
// made while another process changed files too (`shared`), whose lines aren't credited. 1 when it can't say which files
// (it names fewer than it changed, or none at all where it couldn't record), so any could be.
static NSUInteger ShellDoubts(NSDictionary *diff, NSMutableSet *doubts) {
    NSArray *files = ListIn(diff, @"files"), *named = ListIn(diff, @"changedFiles");
    BOOL shared = FlagIn(diff, @"shared") && files.count;
    NSInteger more = NumberIn(diff, @"moreFiles");
    if (!more && !FlagIn(diff, @"unavailable") && !shared) return 0;
    if (more && named.count < files.count + more) return 1;
    if (!more && !shared && !named.count) return 1;
    // This command's own: what it names without its lines (or, shared, everything it names), added to what's in doubt
    // already, so one command's record never clears another's doubt.
    NSMutableSet *lined = [NSMutableSet set], *mine = [NSMutableSet set];
    for (NSDictionary *file in files)
        if ([file isKindOfClass:NSDictionary.class] && [file[@"filePath"] isKindOfClass:NSString.class])
            [lined addObject:[file[@"filePath"] stringByStandardizingPath]];
    for (NSString *path in named)
        if ([path isKindOfClass:NSString.class]) [mine addObject:[path stringByStandardizingPath]];
    if (shared) [mine unionSet:lined];
    else [mine minusSet:lined];
    [doubts unionSet:mine];
    return 0;
}

NSDictionary *ShellNews(NSData *chunk, NSUInteger end, NSString *mode, NSString *base, NSSet<NSString *> *git) {
    NSMutableDictionary *modes = [NSMutableDictionary dictionary];
    NSMutableArray *gitCalls = [NSMutableArray array];
    NSMutableSet *runsGit = [git mutableCopy] ?: [NSMutableSet set];
    NSUInteger partial = 0, failed = 0;
    NSMutableSet *doubts = [NSMutableSet set];
    // The lines that name a mode, a shell command or a shell command's record, in the order they were written, so each
    // command is in the mode it ran in.
    NSMutableIndexSet *starts = [NSMutableIndexSet indexSet];
    NSData *newline = [@"\n" dataUsingEncoding:NSUTF8StringEncoding];
    for (NSString *marker in @[@"\"permissionMode\":\"", @"\"name\":\"Bash\"", @"\"bashEditDiff\":",
                               @"\"is_error\":true"]) {
        NSData *bytes = [marker dataUsingEncoding:NSUTF8StringEncoding];
        NSUInteger cursor = 0;
        while (cursor < end) {
            NSRange hit = [chunk rangeOfData:bytes options:0 range:NSMakeRange(cursor, end - cursor)];
            if (hit.location == NSNotFound) break;
            NSRange before = [chunk rangeOfData:newline options:NSDataSearchBackwards range:NSMakeRange(0, hit.location)];
            NSUInteger start = before.location == NSNotFound ? 0 : NSMaxRange(before);
            [starts addIndex:start];
            NSRange after = [chunk rangeOfData:newline options:0 range:NSMakeRange(hit.location, end - hit.location)];
            cursor = after.location == NSNotFound ? end : NSMaxRange(after);
        }
    }
    for (NSUInteger start = starts.firstIndex; start != NSNotFound; start = [starts indexGreaterThanIndex:start]) {
        NSDictionary *entry = JSONLineAt(chunk, start, end, NULL);
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        if ([entry[@"permissionMode"] isKindOfClass:NSString.class]) {
            mode = entry[@"permissionMode"];
            if (![mode isEqualToString:@"plan"]) base = mode;
        }
        id message = entry[@"message"];
        id content = [message isKindOfClass:NSDictionary.class] ? message[@"content"] : nil;
        id diff = [entry[@"toolUseResult"] isKindOfClass:NSDictionary.class] ? entry[@"toolUseResult"][@"bashEditDiff"] : nil;
        for (NSDictionary *item in [content isKindOfClass:NSArray.class] ? content : @[]) {
            if (![item isKindOfClass:NSDictionary.class]) continue;
            if ([item[@"type"] isEqual:@"tool_use"] && [item[@"name"] isEqual:@"Bash"]
                && [item[@"id"] isKindOfClass:NSString.class]) {
                id input = item[@"input"];
                // A git command that brings in work that's there already: what the command changed isn't the
                // session's, so its record isn't credited. Run beside other things (`./fix.sh && git stash pop`), the
                // files it names can't be told apart, so they're in doubt (marked "~").
                GitUse use = UsesGit([input isKindOfClass:NSDictionary.class] ? input[@"command"] : nil);
                if (use.brings) {
                    [gitCalls addObject:item[@"id"]];
                    [runsGit addObject:item[@"id"]];
                    if (!use.only) {
                        NSString *mixed = [@"~" stringByAppendingString:item[@"id"]];
                        [gitCalls addObject:mixed];
                        [runsGit addObject:mixed];
                    }
                }
                // Git alone changes no file but by its own steps, so it doesn't count toward whether every command
                // was recorded, nor does its failing ("=").
                if (use.only) {
                    NSString *alone = [@"=" stringByAppendingString:item[@"id"]];
                    [gitCalls addObject:alone];
                    [runsGit addObject:alone];
                    continue;
                }
                NSString *ran = [mode isEqualToString:@"plan"] ? base ?: mode : mode ?: @"";
                modes[ran] = @([modes[ran] integerValue] + 1);
            }
            if (![item[@"type"] isEqual:@"tool_result"]) continue;
            NSString *callId = [item[@"tool_use_id"] isKindOfClass:NSString.class] ? item[@"tool_use_id"] : @"";
            // A shell command that failed has no record of what it changed, though it may have changed files before
            // it failed: which lines, nothing says.
            id said = entry[@"toolUseResult"];
            if (FlagIn(item, @"is_error") && [said isKindOfClass:NSString.class] && [said hasPrefix:kClaudeCodeShellFailure]
                && ![runsGit containsObject:[@"=" stringByAppendingString:callId]])
                failed++;
            if (![diff isKindOfClass:NSDictionary.class]) continue;
            if ([runsGit containsObject:[@"~" stringByAppendingString:callId]]) {
                for (NSDictionary *file in ListIn(diff, @"files"))
                    if ([file isKindOfClass:NSDictionary.class] && [file[@"filePath"] isKindOfClass:NSString.class])
                        [doubts addObject:[file[@"filePath"] stringByStandardizingPath]];
                for (NSString *path in ListIn(diff, @"changedFiles"))
                    if ([path isKindOfClass:NSString.class]) [doubts addObject:[path stringByStandardizingPath]];
                // Naming fewer files than it changed, any file could be one.
                NSInteger more = NumberIn(diff, @"moreFiles");
                if (more > 0 && (NSInteger)ListIn(diff, @"changedFiles").count < (NSInteger)ListIn(diff, @"files").count + more)
                    partial++;
            } else if (![runsGit containsObject:callId]) {
                partial += ShellDoubts(diff, doubts);
            }
        }
    }
    NSMutableDictionary *news = [@{@"modes": modes, @"git": gitCalls, @"partial": @(partial), @"failed": @(failed),
                                   @"doubts": doubts.allObjects} mutableCopy];
    if (mode) news[@"mode"] = mode;
    if (base) news[@"base"] = base;
    return news;
}

void AddShellNews(NSMutableDictionary *state, NSDictionary *news) {
    NSMutableDictionary *modes = state[@"shellModes"] ?: [NSMutableDictionary dictionary];
    state[@"shellModes"] = modes;
    [news[@"modes"] enumerateKeysAndObjectsUsingBlock:^(NSString *mode, NSNumber *count, BOOL *stop) {
        modes[mode] = @([modes[mode] integerValue] + count.integerValue);
    }];
    state[@"shellPartial"] = @([state[@"shellPartial"] integerValue] + [news[@"partial"] integerValue]);
    state[@"shellFailed"] = @([state[@"shellFailed"] integerValue] + [news[@"failed"] integerValue]);
    NSMutableSet *doubts = state[@"shellDoubts"] ?: [NSMutableSet set];
    state[@"shellDoubts"] = doubts;
    [doubts addObjectsFromArray:news[@"doubts"]];
    NSMutableOrderedSet *git = state[@"gitCalls"] ?: [NSMutableOrderedSet orderedSet];
    state[@"gitCalls"] = git;
    [git addObjectsFromArray:news[@"git"]];
    if (git.count > kGitCalls) [git removeObjectsInRange:NSMakeRange(0, git.count - kGitCalls)];
    if (news[@"mode"]) state[@"shellMode"] = news[@"mode"];
    if (news[@"base"]) state[@"shellBase"] = news[@"base"];
}

// Whether what a session changed is all known: every shell command it ran was in a mode Claude Code records them in
// (ClaudeRecordsShellChanges, with `setting`), and recorded whole. A command that wasn't could have changed any line,
// and nothing says which, so then none of the session's changes is known for certain, nor whose an unknown line is.
BOOL SessionKnown(NSDictionary *transcript, id setting) {
    if ([transcript[@"shellPartial"] integerValue] > 0) return NO;
    for (NSString *mode in transcript[@"shellModes"])
        if (!ClaudeRecordsShellChanges(mode, setting)) return NO;
    return YES;
}

// The setting that turns Claude Code's records of shell commands on or off for a session in `project` (the folder it
// runs in), as Claude Code goes by it: the machine's, else the project's own (its local file, then the shared one),
// else yours, else nil.
id ShellDiffSetting(NSString *project) {
    NSMutableArray<NSString *> *files = [NSMutableArray arrayWithObject:MachineFile(kClaudeCodeManagedSettings)];
    if (project.length) {
        NSString *folder = [project stringByAppendingPathComponent:kClaudeCodeFolder];
        [files addObject:[folder stringByAppendingPathComponent:kClaudeCodeLocalSettings]];
        [files addObject:[folder stringByAppendingPathComponent:kClaudeCodeSettings]];
    }
    [files addObject:ClaudeDir(kClaudeCodeSettings)];
    for (NSString *file in files) {
        NSDictionary *settings = ReadJSON(file);
        id setting = [settings isKindOfClass:NSDictionary.class] ? settings[kClaudeCodeShellDiffSetting] : nil;
        if ([setting isKindOfClass:NSNumber.class]) return setting;
    }
    return nil;
}
