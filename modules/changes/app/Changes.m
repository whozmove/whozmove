// Changes: what isn't committed in each listed checkout, line by line, as git splits it (not staged, new files
// included, and staged), with each changed line credited to the session that wrote it; and the commits not on GitHub
// yet, one by one.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Changes.h"
#import "Files.h"
#import "Git.h"
#import "CheckoutWatch.h"
#import "Processes.h"
#import "Row.h"
#import "Text.h"
#import "Core.h"

// How often a checkout is looked at again, at most (and, while nothing in it seems to have changed, as macOS's file
// system events tell it, CheckoutQuietEvery); the biggest new file read whole; the most a diff is read for (a checkout
// changing more than that isn't counted line by line); the longest line kept; the most lines a changes view is sent,
// the files past that listed with their counts only; and the most new files read.
static const NSTimeInterval kEvery = 3;
static const unsigned long long kNewFileLargest = 1024 * 1024;
static const NSUInteger kDiffLargest = 32 * 1024 * 1024, kLineLongest = 2000, kViewLines = 30000, kNewFiles = 500;

// A parsed diff line's LineKey (ParseDiff keeps the whole text's), or nil for a blank one.
static NSNumber *KeyOf(NSArray *line) {
    if (line.count > 2) return [line[2] isKindOfClass:NSNumber.class] ? line[2] : nil;
    return LineKey(line[1]);
}

// A count, as [added, removed].
static NSMutableArray *Count(void) { return [@[@0, @0] mutableCopy]; }
static void Tally(NSMutableDictionary *counts, NSString *who, NSString *sign) {
    NSMutableArray *count = counts[who] ?: (counts[who] = Count());
    NSUInteger at = [sign isEqualToString:@"+"] ? 0 : 1;
    count[at] = @([count[at] integerValue] + 1);
}

// A path as git prints it, quoted only when it has unusual characters (core.quotePath is off).
static NSString *Unquoted(NSString *name) {
    if ([name hasPrefix:@"\""] && [name hasSuffix:@"\""] && name.length > 1) {
        name = [name substringWithRange:NSMakeRange(1, name.length - 2)];
        name = [name stringByReplacingOccurrencesOfString:@"\\\"" withString:@"\""];
        name = [name stringByReplacingOccurrencesOfString:@"\\\\" withString:@"\\"];
    }
    return name;
}

// "a/path" or "b/path" on a "---" or "+++" line, without its side's prefix.
static NSString *DiffPath(NSString *name) {
    name = Unquoted(name);
    return [name hasPrefix:@"a/"] || [name hasPrefix:@"b/"] ? [name substringFromIndex:2] : name;
}

// A hunk's header, "@@ -12,3 +12,5 @@": where it starts on each side and how many lines it has there.
static BOOL HunkHeader(NSString *line, NSInteger *oldStart, NSInteger *oldLines, NSInteger *newStart, NSInteger *newLines) {
    NSScanner *scan = [NSScanner scannerWithString:line];
    if (![scan scanString:@"@@ -" intoString:NULL] || ![scan scanInteger:oldStart]) return NO;
    *oldLines = 1;
    if ([scan scanString:@"," intoString:NULL] && ![scan scanInteger:oldLines]) return NO;
    if (![scan scanString:@"+" intoString:NULL] || ![scan scanInteger:newStart]) return NO;
    *newLines = 1;
    if ([scan scanString:@"," intoString:NULL] && ![scan scanInteger:newLines]) return NO;
    return YES;
}

NSArray<NSDictionary *> *ParseDiff(NSString *diff) {
    NSMutableArray *files = [NSMutableArray array];
    NSMutableDictionary *file = nil;
    NSMutableArray *lines = nil;
    // What's left of the hunk being read, on each side: its lines are told from the file's next header by count, as a
    // removed line can itself start "--- ".
    NSInteger oldLeft = 0, newLeft = 0;
    for (NSString *line in [diff componentsSeparatedByString:@"\n"]) {
        if (lines && (oldLeft > 0 || newLeft > 0)) {
            if ([line hasPrefix:@"\\"]) continue;  // "\ No newline at end of file"
            NSString *sign = line.length ? [line substringToIndex:1] : @" ";
            if (![sign isEqualToString:@"+"] && ![sign isEqualToString:@"-"]) sign = @" ";
            NSString *text = line.length ? [line substringFromIndex:1] : @"";
            // Told by its whole text, as the edits are: a long line is cut short to show, not to match.
            [lines addObject:@[sign, Clip(text, kLineLongest), LineKey(text) ?: [NSNull null]]];
            if (![sign isEqualToString:@"+"]) oldLeft--;
            if (![sign isEqualToString:@"-"]) newLeft--;
            continue;
        }
        if ([line hasPrefix:@"diff "] && ![line hasPrefix:@"diff --git "]) {
            // Another kind of diff (`diff --cc`, a file in conflict): not read, and not taken for the file before.
            file = nil;
            lines = nil;
        } else if ([line hasPrefix:@"diff --git "]) {
            file = [@{@"path": @"", @"status": @"changed", @"hunks": [NSMutableArray array]} mutableCopy];
            [files addObject:file];
            lines = nil;
            // The new side's name, until the lines below say it better (a name with a space makes this a guess).
            NSRange b = [line rangeOfString:@" b/" options:NSBackwardsSearch];
            if (b.location != NSNotFound) file[@"path"] = [line substringFromIndex:b.location + 3];
        } else if (!file) {
            continue;
        } else if ([line hasPrefix:@"new file mode"]) {
            file[@"status"] = @"new";
        } else if ([line hasPrefix:@"deleted file mode"]) {
            file[@"status"] = @"gone";
        } else if ([line hasPrefix:@"rename from "]) {
            file[@"status"] = @"renamed";
        } else if ([line hasPrefix:@"rename to "]) {
            file[@"path"] = Unquoted([line substringFromIndex:10]);  // "rename to" names it with no side's prefix
        } else if ([line hasPrefix:@"+++ "]) {
            NSString *name = [line substringFromIndex:4];
            if (![name isEqualToString:@"/dev/null"]) file[@"path"] = DiffPath(name);
        } else if ([line hasPrefix:@"--- "]) {
            NSString *name = [line substringFromIndex:4];
            if (![name isEqualToString:@"/dev/null"] && [file[@"status"] isEqualToString:@"gone"])
                file[@"path"] = DiffPath(name);
        } else if ([line hasPrefix:@"Binary files "]) {
            file[@"binary"] = @YES;
        } else if ([line hasPrefix:@"@@ "]) {
            NSInteger oldStart, oldLines, newStart, newLines;
            if (!HunkHeader(line, &oldStart, &oldLines, &newStart, &newLines)) continue;
            lines = [NSMutableArray array];
            [file[@"hunks"] addObject:@{@"oldStart": @(oldStart), @"newStart": @(newStart), @"lines": lines}];
            oldLeft = oldLines;
            newLeft = newLines;
        }
    }
    return files;
}

// A file git doesn't know yet, as a diff of it whole, or nil if it's too big or not text.
static NSDictionary *NewFile(NSString *root, NSString *path) {
    NSString *full = [root stringByAppendingPathComponent:path];
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:full error:nil];
    if (![attributes.fileType isEqualToString:NSFileTypeRegular] || attributes.fileSize > kNewFileLargest) return nil;
    NSData *data = [NSData dataWithContentsOfFile:full];
    if (!data || memchr(data.bytes, 0, data.length)) return nil;
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) return nil;
    // An empty file has no lines, as git counts it.
    if (!text.length) return @{@"path": path, @"status": @"new", @"hunks": @[]};
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByString:@"\n"])
        [lines addObject:@[@"+", Clip(line, kLineLongest), LineKey(line) ?: [NSNull null]]];
    if ([text hasSuffix:@"\n"]) [lines removeLastObject];
    return @{@"path": path, @"status": @"new", @"hunks": lines.count ? @[@{@"oldStart": @0, @"newStart": @1,
                                                                            @"lines": lines}] : @[]};
}

// What git says, or nil when it fails or says too much.
static NSString *Git(NSString *root, NSArray *arguments) {
    // Your git settings can't change how a diff names its files (with other prefixes, or none) or which files it covers.
    NSMutableArray *all = [@[@"--no-optional-locks", @"-c", @"core.quotePath=false", @"-c", @"diff.noprefix=false",
                             @"-c", @"diff.mnemonicPrefix=false", @"-c", @"diff.relative=false", @"-C", root] mutableCopy];
    [all addObjectsFromArray:arguments];
    NSDictionary *run = RunGit(all);
    if (!run || [run[@"status"] intValue] != 0 || [run[@"out"] length] > kDiffLargest) return nil;
    return [[NSString alloc] initWithData:run[@"out"] encoding:NSUTF8StringEncoding]
        ?: [[NSString alloc] initWithData:run[@"out"] encoding:NSISOLatin1StringEncoding];
}

// A line too plain to say whose it is by itself ("}", "", "end"): it goes with the lines it sits among.
static BOOL Plain(NSString *text) {
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length <= 3;
}

// Whose a changed line is: the session whose edits put it in (or took it out), its shell commands' included, the one
// that edited the file last if several did; else "unknown" (no session's record has it: your own edits, a session
// that has closed, a command Claude Code didn't record, or work brought in from elsewhere), which Credit names by how
// far it has got. `owners` are {sid, at, added, removed} for this file, newest first.
static NSString *Whose(NSString *sign, NSNumber *key, NSArray *owners) {
    NSString *way = [sign isEqualToString:@"+"] ? @"added" : @"removed";
    if (key) for (NSDictionary *owner in owners)
        if ([owner[way] containsObject:key]) return owner[@"sid"];
    return @"unknown";
}

// Credits each changed line of a file with whose it is, and counts them by whose. A plain line takes the nearest telling
// line's in the same run of changes, before it if there's one; with none, it's "short", no one's. A line no session's
// record has is "outside" these sessions.
static NSDictionary *Credit(NSDictionary *file, NSArray *owners) {
    NSMutableDictionary *counts = [NSMutableDictionary dictionary];
    NSMutableArray *hunks = [NSMutableArray array];
    // Whose a line is is told by its text, so a text the file's changes have more than once (`return nil;` put in
    // twice) can't say which of them is whose: such a line goes with the lines around it, as a plain one does.
    NSCountedSet *texts = [NSCountedSet set];
    for (NSDictionary *hunk in file[@"hunks"])
        for (NSArray *line in hunk[@"lines"])
            if (![line[0] isEqualToString:@" "]) [texts addObject:[NSString stringWithFormat:@"%@%@", line[0], KeyOf(line)]];
    for (NSDictionary *hunk in file[@"hunks"]) {
        NSArray *lines = hunk[@"lines"];
        NSMutableArray *whose = [NSMutableArray arrayWithCapacity:lines.count];
        for (NSArray *line in lines) {
            BOOL telling = ![line[0] isEqualToString:@" "] && !Plain(line[1])
                && [texts countForObject:[NSString stringWithFormat:@"%@%@", line[0], KeyOf(line)]] <= 1;
            [whose addObject:telling ? Whose(line[0], KeyOf(line), owners) : [NSNull null]];
        }
        // The nearest telling line's in line i's run of changes, before it first.
        NSString *(^near)(NSUInteger) = ^NSString *(NSUInteger i) {
            if (whose[i] != [NSNull null]) return whose[i];
            for (NSInteger j = (NSInteger)i - 1; j >= 0 && ![lines[j][0] isEqualToString:@" "]; j--)
                if (whose[j] != [NSNull null]) return whose[j];
            for (NSUInteger j = i + 1; j < lines.count && ![lines[j][0] isEqualToString:@" "]; j++)
                if (whose[j] != [NSNull null]) return whose[j];
            return nil;
        };
        NSMutableArray *credited = [NSMutableArray arrayWithCapacity:lines.count];
        for (NSUInteger i = 0; i < lines.count; i++) {
            NSArray *line = lines[i];
            if ([line[0] isEqualToString:@" "]) { [credited addObject:@[line[0], line[1]]]; continue; }
            // A short or repeated line with nothing around it to go by (a blank line put in alone): its text can't
            // say whose it is.
            NSString *who = near(i) ?: @"short";
            if ([who isEqualToString:@"unknown"]) who = @"outside";
            [credited addObject:@[line[0], line[1], who]];
            Tally(counts, who, line[0]);
        }
        [hunks addObject:@{@"oldStart": hunk[@"oldStart"], @"newStart": hunk[@"newStart"], @"lines": credited}];
    }
    NSMutableDictionary *credited = [file mutableCopy];
    credited[@"hunks"] = hunks;
    credited[@"counts"] = counts;
    return credited;
}

// Adds files' credited counts into the whole's `parts` ({who: [added, removed]}).
static void AddParts(NSMutableDictionary *parts, NSDictionary *counts) {
    [counts enumerateKeysAndObjectsUsingBlock:^(NSString *who, NSArray *count, BOOL *stop) {
        NSMutableArray *part = parts[who] ?: (parts[who] = Count());
        part[0] = @([part[0] integerValue] + [count[0] integerValue]);
        part[1] = @([part[1] integerValue] + [count[1] integerValue]);
    }];
}

// Files as the changes view shows them, as git does: each line only [sign, text], with no one named.
static NSArray *Bare(NSArray *files) {
    NSMutableArray *bare = [NSMutableArray arrayWithCapacity:files.count];
    for (NSDictionary *file in files) {
        NSMutableArray *hunks = [NSMutableArray array];
        for (NSDictionary *hunk in file[@"hunks"]) {
            NSMutableArray *lines = [NSMutableArray arrayWithCapacity:[hunk[@"lines"] count]];
            for (NSArray *line in hunk[@"lines"]) [lines addObject:@[line[0], line[1]]];
            [hunks addObject:@{@"oldStart": hunk[@"oldStart"], @"newStart": hunk[@"newStart"], @"lines": lines}];
        }
        NSMutableDictionary *one = [file mutableCopy];
        one[@"hunks"] = hunks;
        [bare addObject:one];
    }
    return bare;
}

// How many files and lines: {files, added, removed}.
static NSDictionary *Tallied(NSArray *files) {
    NSInteger added = 0, removed = 0;
    for (NSDictionary *file in files)
        for (NSDictionary *hunk in file[@"hunks"])
            for (NSArray *line in hunk[@"lines"]) {
                if ([line[0] isEqualToString:@"+"]) added++;
                else if ([line[0] isEqualToString:@"-"]) removed++;
            }
    return @{@"files": @(files.count), @"added": @(added), @"removed": @(removed)};
}

// What isn't committed in a checkout, as git status splits it, and credited. `files`: every change since the last
// commit, staged or not, new files included (`others`, git's list of them, NUL-separated), credited by whose each line
// is, each file saying whether it's staged whole (`saved`: nothing in it is left unstaged); with `parts`, that by
// whose. `unstaged`: what `git diff` shows, then the new files (`untracked`), each saying whether it has staged changes
// too (`alsoStaged`); `staged`: what `git diff --cached` shows, each saying whether it was changed again since
// (`alsoUnstaged`), as git status lists such a file under both. `owners` are {path: [{sid, at, added, removed}]}. Nil
// when git can't say, or says too much.
static NSDictionary *CreditCheckout(NSString *root, NSDictionary *owners, NSString *others) {
    // Before the first commit there's no HEAD: everything is against nothing (git's empty tree).
    NSString *head = Git(root, @[@"rev-parse", @"--quiet", @"--verify", @"HEAD"]).length ? @"HEAD"
                                                                                        : @"4b825dc642cb6eb9a060e54bf8d69288fbee4904";
    NSArray *diff = @[@"diff", @"--no-ext-diff", @"--no-textconv", @"--no-color", @"-U3"];
    NSString *all = Git(root, [diff arrayByAddingObjectsFromArray:@[@"-M", head]]);
    NSString *staged = Git(root, [diff arrayByAddingObjectsFromArray:@[@"-M", @"--cached"]]);
    NSString *tree = Git(root, diff);
    if (!all || !staged || !tree || !others) return nil;
    NSMutableArray *unstagedFiles = [Bare(ParseDiff(tree)) mutableCopy], *stagedFiles = [Bare(ParseDiff(staged)) mutableCopy];
    NSMutableSet *notStaged = [NSMutableSet set], *inStaged = [NSMutableSet set];
    for (NSDictionary *file in unstagedFiles) [notStaged addObject:file[@"path"]];
    for (NSDictionary *file in stagedFiles) [inStaged addObject:file[@"path"]];
    NSMutableArray *files = [ParseDiff(all) mutableCopy];
    NSArray *newPaths = [others componentsSeparatedByString:@"\0"];
    for (NSString *path in [newPaths subarrayWithRange:NSMakeRange(0, MIN(newPaths.count, kNewFiles))]) {
        NSDictionary *file = path.length ? NewFile(root, path) : nil;
        if (!file) continue;
        [files addObject:file];
        NSMutableDictionary *untracked = [Bare(@[file])[0] mutableCopy];
        untracked[@"untracked"] = @YES;
        [unstagedFiles addObject:untracked];
        [notStaged addObject:path];
    }
    for (NSMutableDictionary *file in unstagedFiles)
        if ([inStaged containsObject:file[@"path"]]) file[@"alsoStaged"] = @YES;
    for (NSUInteger i = 0; i < stagedFiles.count; i++) {
        if (![notStaged containsObject:stagedFiles[i][@"path"]]) continue;
        NSMutableDictionary *file = [stagedFiles[i] mutableCopy];
        file[@"alsoUnstaged"] = @YES;
        stagedFiles[i] = file;
    }
    NSMutableArray *credited = [NSMutableArray array];
    NSMutableDictionary *parts = [NSMutableDictionary dictionary];
    for (NSDictionary *file in files) {
        NSMutableDictionary *done = [Credit(file, owners[file[@"path"]] ?: @[]) mutableCopy];
        done[@"saved"] = [notStaged containsObject:file[@"path"]] ? @NO : @YES;
        [credited addObject:done];
        AddParts(parts, done[@"counts"]);
    }
    return @{@"files": credited, @"parts": parts, @"unstaged": unstagedFiles, @"staged": stagedFiles,
             @"unstagedCount": Tallied(unstagedFiles), @"stagedCount": Tallied(stagedFiles)};
}

// The most commits the Outgoing view reads one by one; past that, it says how many more.
static const NSUInteger kOutgoingCommits = 50;

// The commits from `from` (where GitHub's copy is, as a row's ↑N counts them) to HEAD, newest first, as git log lists
// them, each with what it changed, as git show has it: {commits: [{hash, short, subject, at (ms), files}], more}. Nil
// when git can't say. A commit never changes, so one already read (`shown`: what each listed commit changed, by its
// hash, from the lists held now) isn't shown again, however often HEAD moves on a branch dozens of commits ahead.
static NSDictionary *ReadOutgoing(NSString *root, NSString *from, NSDictionary<NSString *, NSArray *> *shown) {
    NSString *range = [from stringByAppendingString:@"..HEAD"];
    NSString *log = Git(root, @[@"log", @"--no-color", @"--format=%H%x1f%h%x1f%ct%x1f%s",
                                [NSString stringWithFormat:@"-n%lu", (unsigned long)kOutgoingCommits], range]);
    NSString *count = Git(root, @[@"rev-list", @"--count", range]);
    if (!log || !count) return nil;
    NSMutableArray *commits = [NSMutableArray array];
    for (NSString *line in [log componentsSeparatedByString:@"\n"]) {
        NSArray *f = [line componentsSeparatedByString:@"\x1f"];
        if (f.count < 4) continue;
        NSArray *files = shown[f[0]];
        if (!files) {
            NSString *diff = Git(root, @[@"show", @"--no-ext-diff", @"--no-textconv", @"--no-color", @"-U3", @"-M",
                                         @"--format=", f[0]]);
            files = diff ? Bare(ParseDiff(diff)) : @[];
        }
        [commits addObject:@{@"hash": f[0], @"short": f[1], @"at": @([f[2] doubleValue] * 1000),
                             @"subject": [[f subarrayWithRange:NSMakeRange(3, f.count - 3)] componentsJoinedByString:@"\x1f"],
                             @"files": files}];
    }
    NSInteger all = [[count stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] integerValue];
    return @{@"commits": commits, @"more": @(MAX(0, all - (NSInteger)commits.count))};
}

// A path as it is in a folder, or nil if it isn't in it.
static NSString *InFolder(NSString *path, NSString *folder) {
    NSUInteger length = folder.length;
    if (path.length <= length + 1 || [path characterAtIndex:length] != '/' || ![path hasPrefix:folder]) return nil;
    return [path substringFromIndex:length + 1];
}

// A full path as it is in a checkout, or nil if it's outside it. It's asked of every edited file for every checkout,
// every second, so the real path (symlinks resolved) is found once per path, and kept as null when it's the path
// itself, as most are, which then needs no second look.
static NSString *Within(NSString *path, NSString *root) {
    NSString *inside = InFolder(path, root);
    if (inside || !path.length) return inside;
    static NSMutableDictionary<NSString *, id> *reals;
    static NSLock *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        reals = [NSMutableDictionary dictionary];
        lock = [NSLock new];
    });
    [lock lock];
    id real = reals[path];
    [lock unlock];
    if (!real) {
        NSString *found = RealPath(path);
        real = !found.length || [found isEqualToString:path] ? NSNull.null : found;
        [lock lock];
        if (reals.count > 5000) [reals removeAllObjects];
        reals[path] = real;
        [lock unlock];
    }
    return real == NSNull.null ? nil : InFolder(real, root);
}

// What a checkout's owners were worked out from, to tell when that's changed: each session's edits of each file, by
// how many lines.
static NSString *OwnersSource(NSDictionary *byPath) {
    NSMutableArray *edited = [NSMutableArray array];
    for (NSString *path in byPath)
        for (NSDictionary *owner in byPath[path])
            [edited addObject:[NSString stringWithFormat:@"%@ %@ %lu %lu", owner[@"sid"], path,
                               (unsigned long)[owner[@"added"] count], (unsigned long)[owner[@"removed"] count]]];
    [edited sortUsingSelector:@selector(compare:)];
    return [edited componentsJoinedByString:@"\n"];
}

// Files as a view sends them: past the most a view is sent (`sent`, counted across the calls of one view), listed with
// their counts and without their lines.
static NSArray *Capped(NSArray *files, NSUInteger *sent) {
    NSMutableArray *shown = [NSMutableArray array];
    for (NSDictionary *file in files) {
        NSUInteger lines = 0;
        for (NSDictionary *hunk in file[@"hunks"]) lines += [hunk[@"lines"] count];
        NSMutableDictionary *one = [file mutableCopy];
        if (*sent + lines > kViewLines) {
            NSDictionary *tally = Tallied(@[file]);
            one[@"hunks"] = @[];
            one[@"cut"] = @YES;
            one[@"added"] = tally[@"added"];
            one[@"removed"] = tally[@"removed"];
        } else *sent += lines;
        [shown addObject:one];
    }
    return shown;
}

// Whether every line of these files no one's edits explain is no listed session's.
static BOOL Complete(NSArray *files, BOOL allInDoubt, NSSet *doubts) {
    if (allInDoubt) return NO;
    for (NSDictionary *file in files)
        if ([doubts containsObject:file[@"path"]]) return NO;
    return YES;
}

@interface Changes ()
@property (strong) dispatch_queue_t queue;
// Kept on the main thread: each session's checkout, each checkout's counted changes ({files, parts, unstaged, staged,
// v}: CreditCheckout's) and what they were worked out from, when it was last looked at, and the ones being worked out
// now.
@property (strong) NSMutableDictionary<NSString *, NSString *> *roots;
// Each listed session's row, and each checkout's commits not on GitHub yet as last read (ReadOutgoing's, with what
// they were read from, `source`, and for opening their files), read ahead while there are some.
@property (strong) NSMutableDictionary<NSString *, Row *> *rows;
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *outgoing;
@property (strong) NSMutableSet<NSString *> *outgoingBusy;
@property (strong) NSMutableDictionary<NSString *, NSNumber *> *outgoingLookedAt;
// What each checkout's commits not on GitHub were last read from (its CheckoutRefChanges, and the upstream or base
// branch they're ahead of), and its CheckoutFileChanges and CheckoutRefChanges as its changes were last counted.
@property (strong) NSMutableDictionary<NSString *, NSString *> *outgoingSeen;
@property (strong) NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *changesSeen;
// Each session's checkouts edited (rootsEditedBy:), and its lines edited in each checkout, by the version of its edits
// they were counted at (linesOf:in:).
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *edited;
@property (strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *linesIn;
// Each session's files in doubt (a shell command changed them, its record leaving out which lines), as they are within
// each checkout, by the version of its edits they were worked out at (doubtsOf:in:).
@property (strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *doubtsIn;
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *results;
@property (strong) NSMutableDictionary<NSString *, NSString *> *sources;
@property (strong) NSMutableDictionary<NSString *, NSNumber *> *lookedAt;
// Each checkout's editors' lines edited there as its last count was started with, so new ones are counted at once.
@property (strong) NSMutableDictionary<NSString *, NSString *> *ownersSeen;
@property (strong) NSMutableSet<NSString *> *busy;
@property (assign) NSInteger version;
// What each session edited, as its agent said it this refresh (editsOf:), by session.
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *edits;
// Each checkout's sessions whose changes aren't known (their agent's editsOf: says), kept as rows are.
@property (strong) NSDictionary<NSString *, NSArray<NSString *> *> *unknown;
// Each checkout's files a shell command changed whose lines Claude Code's record left out (ShellNews' doubts), within
// the checkout: no one's lines there are called unknown, as they may be that command's.
@property (strong) NSDictionary<NSString *, NSSet<NSString *> *> *doubts;
// Each checkout's sessions with a shell command that failed (ShellNews' failed), which nothing records the changes of.
@property (strong) NSDictionary<NSString *, NSSet<NSString *> *> *failing;
// Where views are built and made JSON, apart from where changes are counted, so a view doesn't wait on a count.
@property (strong) dispatch_queue_t views;
@end

@implementation Changes

- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.queue = dispatch_queue_create("whozmove.changes", DISPATCH_QUEUE_SERIAL);
    self.views = dispatch_queue_create("whozmove.changes.views", DISPATCH_QUEUE_SERIAL);
    self.roots = [NSMutableDictionary dictionary];
    self.results = [NSMutableDictionary dictionary];
    self.sources = [NSMutableDictionary dictionary];
    self.lookedAt = [NSMutableDictionary dictionary];
    self.ownersSeen = [NSMutableDictionary dictionary];
    self.busy = [NSMutableSet set];
    self.rows = [NSMutableDictionary dictionary];
    self.outgoing = [NSMutableDictionary dictionary];
    self.outgoingBusy = [NSMutableSet set];
    self.outgoingLookedAt = [NSMutableDictionary dictionary];
    self.outgoingSeen = [NSMutableDictionary dictionary];
    self.changesSeen = [NSMutableDictionary dictionary];
    self.edited = [NSMutableDictionary dictionary];
    self.linesIn = [NSMutableDictionary dictionary];
    self.doubtsIn = [NSMutableDictionary dictionary];
    self.unknown = @{};
    self.doubts = @{};
    self.failing = @{};
    return self;
}

- (BOOL)working {
    return self.busy.count > 0;
}

// What a session edited, as its agent says (AgentWork's editsOf:), asked once a refresh: never nil, so a session it
// knows nothing of has edited nothing, and everything it changed is known.
- (NSDictionary *)editsOf:(Row *)row {
    NSString *sid = row.sessionId ?: @"";
    if (self.edits[sid]) return self.edits[sid];
    id agent = [self.core agentOf:row];
    NSDictionary *edits = [agent conformsToProtocol:@protocol(AgentWork)]
        ? [agent editsOf:row] : @{@"files": @{}, @"count": @0, @"known": @YES};
    if (!self.edits) self.edits = [NSMutableDictionary dictionary];
    self.edits[sid] = edits;
    return edits;
}

- (void)refreshFor:(NSArray<Row *> *)sessions {
    [self.roots removeAllObjects];
    [self.rows removeAllObjects];
    [self.edits removeAllObjects];
    // Lines counted and files in doubt worked out for sessions no longer listed are let go.
    if (self.linesIn.count > sessions.count || self.doubtsIn.count > sessions.count) {
        NSSet *listed = [NSSet setWithArray:[sessions valueForKey:@"sessionId"]];
        for (NSString *sid in self.linesIn.allKeys)
            if (![listed containsObject:sid]) [self.linesIn removeObjectForKey:sid];
        for (NSString *sid in self.doubtsIn.allKeys)
            if (![listed containsObject:sid]) [self.doubtsIn removeObjectForKey:sid];
    }
    // Every checkout a listed session runs in, and the sessions that edited files anywhere.
    NSMutableSet<NSString *> *checkouts = [NSMutableSet set];
    NSMutableArray<Row *> *editing = [NSMutableArray array];
    for (Row *row in sessions) {
        NSString *root = (row.workGit ?: row.git)[@"root"];
        if (!root || !row.sessionId) continue;
        self.roots[row.sessionId] = root;
        self.rows[row.sessionId] = row;
        [checkouts addObject:root];
        if ([[self editsOf:row][@"files"] count]) [editing addObject:row];
    }
    WatchCheckouts(@"changes", checkouts);
    // Each checkout's editors: the sessions running in it that edited files, and any other listed session that edited
    // files in it from elsewhere, whose lines there are as much its own. Those, and the sessions running in it, are
    // the ones whose changes have to be known for it to be complete. Who edited only says whose a line is: every
    // listed checkout is counted, as git counts it, unless its last git status found nothing to commit there.
    NSMutableSet<NSString *> *pending = [NSMutableSet set];
    for (Row *row in sessions) {
        NSString *root = self.roots[row.sessionId ?: @""];
        NSDictionary *c = row.checkout;
        if (root && (!c || [c[@"changes"] integerValue] + [c[@"newFiles"] integerValue] > 0)) [pending addObject:root];
    }
    NSMutableDictionary<NSString *, NSMutableArray<Row *> *> *editors = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *unknown = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *doubts = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *failing = [NSMutableDictionary dictionary];
    // Each editing session's checkouts are worked out once a refresh, not once for every checkout: with dozens of each,
    // that was thousands of times a second.
    NSArray<NSString *> *sortedRoots = [checkouts.allObjects sortedArrayUsingSelector:@selector(compare:)];
    NSString *rootsKey = [sortedRoots componentsJoinedByString:@"\n"];
    NSMutableDictionary<NSString *, NSSet<NSString *> *> *editedBy = [NSMutableDictionary dictionary];
    for (Row *row in editing) editedBy[row.sessionId] = [self rootsEditedBy:row among:sortedRoots key:rootsKey];
    for (NSString *root in checkouts) {
        for (Row *row in editing)
            if ([self.roots[row.sessionId] isEqualToString:root] || [editedBy[row.sessionId] containsObject:root])
                [editors[root] ?: (editors[root] = [NSMutableArray array]) addObject:row];
        for (Row *row in sessions) {
            if (!row.sessionId || !self.roots[row.sessionId]) continue;
            if (![self.roots[row.sessionId] isEqualToString:root] && ![editors[root] containsObject:row]) continue;
            NSDictionary *edits = [self editsOf:row];
            if (![edits[@"known"] boolValue])
                [unknown[root] ?: (unknown[root] = [NSMutableArray array]) addObject:row.sessionId];
            // A shell command of its failed, with no record of what it changed first: no line here can be said to be
            // no listed session's.
            if ([edits[@"failed"] integerValue] > 0)
                [failing[root] ?: (failing[root] = [NSMutableSet set]) addObject:row.sessionId];
            NSSet<NSString *> *inside = [self doubtsOf:row in:root];
            if (inside.count) [doubts[root] ?: (doubts[root] = [NSMutableSet set]) unionSet:inside];
        }
    }
    // Which sessions' changes are known goes into what the page is sent, so it's told when that changes.
    for (NSString *root in self.results.allKeys)
        if (![(unknown[root] ?: @[]) isEqualToArray:self.unknown[root] ?: @[]]
            || ![(doubts[root] ?: [NSSet set]) isEqualToSet:self.doubts[root] ?: [NSSet set]]
            || ![(failing[root] ?: [NSSet set]) isEqualToSet:self.failing[root] ?: [NSSet set]])
            ((NSMutableDictionary *)self.results[root])[@"v"] = @(++self.version);
    self.unknown = [unknown copy];
    self.doubts = [doubts copy];
    self.failing = [failing copy];
    for (NSString *root in checkouts)
        if (editors[root]) [pending addObject:root];
    for (NSString *root in self.results.allKeys)
        if (![pending containsObject:root]) {
            [self.results removeObjectForKey:root];
            [self.sources removeObjectForKey:root];
            [self.ownersSeen removeObjectForKey:root];
            [self.changesSeen removeObjectForKey:root];
        }
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    // A checkout's commits not on GitHub yet are read ahead, while it has some (as a row's ↑N counts them).
    for (NSString *sid in self.rows) {
        Row *row = self.rows[sid];
        NSString *root = self.roots[sid];
        NSDictionary *c = row.checkout;
        NSInteger waiting = [c[@"remotes"] integerValue] > 0
            ? [c[[c[@"upstream"] boolValue] ? @"ahead" : @"aheadOfBase"] integerValue] : 0;
        NSTimeInterval since = now - [self.outgoingLookedAt[root] doubleValue];
        // Nothing they're read from has changed since (no commit, no branch moved, the same branch they're ahead of):
        // they still stand.
        NSString *from = [NSString stringWithFormat:@"%lu %@ %@", (unsigned long)CheckoutRefChanges(root),
                          c[@"upstream"], c[@"baseRef"]];
        BOOL quiet = CheckoutWatched(root) && [self.outgoingSeen[root] isEqualToString:from]
            && since < CheckoutQuietEvery(root);
        if (waiting <= 0 || since < kEvery || quiet) continue;
        self.outgoingLookedAt[root] = @(now);
        self.outgoingSeen[root] = from;
        [self workOutgoingAt:root row:row done:nil];
    }
    for (NSString *root in pending) {
        if ([self.busy containsObject:root]) continue;
        // New edits are counted at once, rather than a few seconds on, as they say whose lines are whose (they come in
        // after the checkout's first count, as transcripts are read). Whether there are any is told by how many lines
        // each editor's edits put in or took out in this checkout, which an edit's result can change after its request
        // came, rather than by working out whose each line is every second (ownersAt).
        NSMutableArray *counted = [NSMutableArray array];
        for (Row *row in editors[root])
            [counted addObject:[NSString stringWithFormat:@"%@ %lu", row.sessionId,
                                                         (unsigned long)[self linesOf:row in:root]]];
        NSString *editsAt = [[counted sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@"\n"];
        NSTimeInterval since = now - [self.lookedAt[root] doubleValue];
        // Nor while nothing in it has changed, as macOS tells it: git would say what it said last time.
        NSArray *changes = @[@(CheckoutFileChanges(root)), @(CheckoutRefChanges(root))];
        BOOL quiet = CheckoutWatched(root) && [self.changesSeen[root] isEqualToArray:changes]
            && since < CheckoutQuietEvery(root);
        if ((since < kEvery || quiet) && [editsAt isEqualToString:self.ownersSeen[root]]) continue;
        // The files its sessions edited in this checkout, each with whose edits and their lines, newest edit first:
        // copied, as they're read on the queue.
        NSDictionary *byPath = [self ownersAt:root rows:editors[root] ?: @[]];
        NSString *edits = OwnersSource(byPath), *known = self.sources[root];
        self.lookedAt[root] = @(now);
        self.changesSeen[root] = changes;
        self.ownersSeen[root] = editsAt;
        [self.busy addObject:root];
        dispatch_async(self.queue, ^{
            // What it would be worked out from: the commit, what's staged, each changed file's size and time,
            // and the sessions' edits. Unchanged, the last count stands.
            NSString *names = Git(root, @[@"diff", @"--name-only", @"-z", @"HEAD"]) ?: @"";
            NSString *others = Git(root, @[@"ls-files", @"--others", @"--exclude-standard", @"-z"]);
            // Staging changes only git's index, so its time is part of it too.
            NSString *index = [Git(root, @[@"rev-parse", @"--path-format=absolute", @"--git-path", @"index"])
                               stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            NSDate *indexAt = index.length ? [NSFileManager.defaultManager attributesOfItemAtPath:index error:nil]
                                                 .fileModificationDate : nil;
            NSMutableString *source = [NSMutableString stringWithFormat:@"%@\n%f\n%@\n", Git(root, @[@"rev-parse", @"HEAD"]),
                                       indexAt.timeIntervalSince1970, edits];
            for (NSString *name in [[NSString stringWithFormat:@"%@\0%@", names, others] componentsSeparatedByString:@"\0"]) {
                if (!name.length) continue;
                NSDictionary *a = [NSFileManager.defaultManager attributesOfItemAtPath:
                                   [root stringByAppendingPathComponent:name] error:nil];
                [source appendFormat:@"%@ %llu %f\n", name, a.fileSize, a.fileModificationDate.timeIntervalSince1970];
            }
            BOOL same = [source isEqualToString:known];
            NSDictionary *credited = same || !others ? nil : CreditCheckout(root, byPath, others);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.busy removeObject:root];
                if (same) return;
                // Too much to count (or git couldn't say): nothing is said, rather than the last count, and it isn't
                // tried again until something changes.
                NSMutableDictionary *result = [credited mutableCopy]
                    ?: [@{@"files": @[], @"parts": @{}, @"tooMuch": @YES} mutableCopy];
                result[@"v"] = @(++self.version);
                self.results[root] = result;
                self.sources[root] = source;
            });
        });
    }
}

// A session's files in doubt, as they are within a checkout. Asked of every session in every checkout each second, so
// they're worked out again only once its edits have moved on (their version, which files newly in doubt move on too)
// or for a checkout not asked about yet; every time when the agent gives no version.
- (NSSet<NSString *> *)doubtsOf:(Row *)row in:(NSString *)root {
    NSDictionary *edits = [self editsOf:row];
    id all = edits[@"doubts"];
    if (![all count]) return nil;
    NSNumber *version = AsNumber(edits[@"version"]);
    NSString *sid = row.sessionId ?: @"";
    NSMutableDictionary *known = self.doubtsIn[sid];
    if (version && ![known[@"version"] isEqual:version])
        self.doubtsIn[sid] = known = [NSMutableDictionary dictionaryWithObject:version forKey:@"version"];
    NSSet *found = version ? known[root] : nil;
    if (found) return found;
    NSMutableSet *inside = [NSMutableSet set];
    for (NSString *path in all) {
        NSString *within = Within(path, root);
        if (within) [inside addObject:within];
    }
    if (version) known[root] = inside;
    return inside;
}

// How many lines a session's edits put in or took out in a checkout. Asked of every editor in every checkout each
// second, so it's counted again only once the edits have moved on (their version) or for a checkout not counted yet;
// every time when the agent gives no version.
- (NSUInteger)linesOf:(Row *)row in:(NSString *)root {
    NSDictionary *edits = [self editsOf:row];
    NSNumber *version = AsNumber(edits[@"version"]);
    NSString *sid = row.sessionId ?: @"";
    NSMutableDictionary *known = self.linesIn[sid];
    if (version && ![known[@"version"] isEqual:version])
        self.linesIn[sid] = known = [NSMutableDictionary dictionaryWithObject:version forKey:@"version"];
    NSNumber *counted = version ? known[root] : nil;
    if (counted) return counted.unsignedIntegerValue;
    NSUInteger lines = 0;
    for (NSDictionary *file in [edits[@"files"] allValues])
        if (Within(file[@"path"], root)) lines += [file[@"added"] count] + [file[@"removed"] count];
    if (version) known[root] = @(lines);
    return lines;
}

// The checkouts a session edited files in, from its edits, worked out again only when they or the checkouts change.
// `roots` are the listed checkouts, sorted, and `rootsKey` them as one string.
- (NSSet<NSString *> *)rootsEditedBy:(Row *)row among:(NSArray<NSString *> *)roots key:(NSString *)rootsKey {
    NSDictionary *edits = [self editsOf:row];
    NSString *key = [NSString stringWithFormat:@"%lu %@", [edits[@"count"] unsignedLongValue], rootsKey];
    NSDictionary *known = self.edited[row.sessionId];
    if ([known[@"key"] isEqualToString:key]) return known[@"roots"];
    NSMutableSet *edited = [NSMutableSet set];
    for (NSDictionary *file in [edits[@"files"] allValues])
        for (NSString *root in roots)
            if (Within(file[@"path"], root)) [edited addObject:root];
    self.edited[row.sessionId] = @{@"key": key, @"roots": edited};
    return edited;
}

- (NSDictionary *)rowChangesOf:(Row *)row {
    NSString *root = self.roots[row.sessionId];
    NSDictionary *result = root ? self.results[root] : nil;
    if (!result || result[@"tooMuch"]) return nil;
    NSString *sid = row.sessionId;
    // The checkout's, as git counts them: everything not committed (each file once), what isn't staged (new files
    // included) and what's staged.
    NSInteger allAdded = 0, allRemoved = 0;
    for (NSArray *part in [result[@"parts"] allValues]) {
        allAdded += [part[0] integerValue];
        allRemoved += [part[1] integerValue];
    }
    NSDictionary *all = @{@"added": @(allAdded), @"removed": @(allRemoved), @"files": @([result[@"files"] count]),
                          @"unstaged": result[@"unstagedCount"], @"staged": result[@"stagedCount"]};
    // Not known: the whole checkout's count, which is certain, and nothing said to be the session's.
    if ([self.unknown[root] containsObject:sid]) {
        NSInteger added = 0, removed = 0;
        for (NSArray *part in [result[@"parts"] allValues]) {
            added += [part[0] integerValue];
            removed += [part[1] integerValue];
        }
        return @{@"known": @NO, @"added": @(added), @"removed": @(removed), @"files": @[], @"parts": @{},
                 @"all": all, @"v": result[@"v"]};
    }
    NSDictionary *edits = [self editsOf:row][@"files"];
    NSMutableDictionary *editsByPath = [NSMutableDictionary dictionary];
    for (NSDictionary *file in edits.allValues) {
        NSString *path = Within(file[@"path"], root);
        if (path) editsByPath[path] = file;
    }
    NSInteger added = 0, removed = 0;
    NSMutableArray *files = [NSMutableArray array];
    for (NSDictionary *file in result[@"files"]) {
        NSArray *mine = file[@"counts"][sid];
        if (!mine) continue;
        added += [mine[0] integerValue];
        removed += [mine[1] integerValue];
        NSDictionary *edit = editsByPath[file[@"path"]];
        NSMutableDictionary *listed = [@{@"path": file[@"path"], @"added": mine[0], @"removed": mine[1],
                                         @"edits": edit[@"edits"] ?: @0, @"at": edit[@"at"] ?: @0,
                                         @"created": edit[@"created"] ?: @NO,
                                         @"saved": file[@"saved"]} mutableCopy];
        // Shared: someone else's lines are in it too (a lone short line is no one's).
        for (NSString *who in file[@"counts"])
            if (![who isEqualToString:sid] && ![who isEqualToString:@"short"]) listed[@"shared"] = @YES;
        [files addObject:listed];
    }
    [files sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"at" ascending:NO]]];
    return @{@"known": @YES, @"added": @(added), @"removed": @(removed), @"files": files, @"parts": result[@"parts"],
             @"complete": @(Complete(result[@"files"], [self allInDoubt:root], self.doubts[root])), @"all": all,
             @"v": result[@"v"]};
}

- (void)view:(NSString *)sessionId scope:(NSString *)scope done:(void (^)(NSDictionary *view))done {
    NSString *root = self.roots[sessionId];
    if ([scope isEqualToString:@"outgoing"]) {
        [self workOutgoingAt:root row:self.rows[sessionId] done:^(NSDictionary *read) {
            if (!read) { done(@{@"missing": @"Couldn't read the commits."}); return; }
            NSUInteger sent = 0;
            NSMutableArray *commits = [NSMutableArray array];
            for (NSDictionary *commit in read[@"commits"]) {
                NSMutableDictionary *one = [commit mutableCopy];
                one[@"files"] = Capped(commit[@"files"], &sent);
                [commits addObject:one];
            }
            done(@{@"scope": @"outgoing", @"v": read[@"v"], @"upstream": read[@"upstream"] ?: NSNull.null,
                   @"commits": commits, @"more": read[@"more"] ?: @0});
        }];
        return;
    }
    NSDictionary *result = root ? self.results[root] : nil;
    if (!result) {
        // Not counted: git is still at it (the page says so, and asks again once the numbers come in), or its last
        // git status found nothing to commit, which leaves nothing to show.
        NSDictionary *c = self.rows[sessionId].checkout;
        BOOL clean = c && [c[@"changes"] integerValue] + [c[@"newFiles"] integerValue] == 0;
        done(root && !clean ? @{@"counting": @YES} : @{@"scope": scope, @"v": @0, @"files": @[]});
        return;
    }
    if (result[@"tooMuch"]) { done(@{@"missing": @"Too many changes to count here."}); return; }
    NSUInteger sent = 0;
    done(@{@"scope": scope, @"v": result[@"v"], @"files": Capped(result[scope] ?: @[], &sent)});
}

- (void)viewOf:(NSString *)sessionId scope:(NSString *)scope done:(void (^)(NSString *json))done {
    [self view:sessionId scope:scope done:^(NSDictionary *view) {
        // Made JSON off the main thread: a large view would hold up everything else.
        dispatch_async(self.views, ^{
            NSData *data = [NSJSONSerialization dataWithJSONObject:@[sessionId ?: @"", scope ?: @"", view] options:0
                                                             error:nil];
            NSString *json = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
            dispatch_async(dispatch_get_main_queue(), ^{ if (json) done(json); });
        });
    }];
}

// Whether no line in a checkout can be said to be no listed session's: one of its sessions isn't known, or had a shell
// command fail.
- (BOOL)allInDoubt:(NSString *)root {
    return self.unknown[root].count || self.failing[root].count;
}

// The edits of the sessions in a checkout, by file within it: {path: [{sid, at, added, removed}]}, newest first.
- (NSDictionary *)ownersAt:(NSString *)root rows:(NSArray<Row *> *)rows {
    NSMutableDictionary *byPath = [NSMutableDictionary dictionary];
    for (Row *row in rows)
        for (NSDictionary *file in [[self editsOf:row][@"files"] allValues]) {
            NSString *path = Within(file[@"path"], root);
            if (!path) continue;
            [byPath[path] ?: (byPath[path] = [NSMutableArray array]) addObject:@{
                @"sid": row.sessionId, @"at": file[@"at"] ?: @0,
                @"added": [file[@"added"] copy], @"removed": [file[@"removed"] copy]}];
        }
    for (NSString *path in byPath)
        [byPath[path] sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"at" ascending:NO]]];
    return byPath;
}

// Reads a checkout's commits not on GitHub yet (ReadOutgoing), unless the last ones still stand; `done` (if any) gets
// them on the main thread, with the upstream they're ahead of (or none, a branch never published), or nil. Also done
// ahead, every few seconds while there are commits waiting, so Outgoing opens at once.
- (void)workOutgoingAt:(NSString *)root row:(Row *)row done:(void (^)(NSDictionary *read))done {
    // A session whose checkout couldn't be read this time round (git failed for a moment) has none to read.
    if (!root) {
        if (done) dispatch_async(dispatch_get_main_queue(), ^{ done(nil); });
        return;
    }
    if ([self.outgoingBusy containsObject:root]) {
        // One is being read: this waits for it.
        dispatch_async(self.queue, ^{ dispatch_async(dispatch_get_main_queue(), ^{
            if (done) done(self.outgoing[root]);
        }); });
        return;
    }
    [self.outgoingBusy addObject:root];
    // As a row's ↑N counts them (unpushedCommits in parts/list/page/whose-move.js): past the upstream when there is
    // one, else past the base branch's GitHub copy; none without a remote.
    // The base branch's ref is the checkout's, as its last read found it (Checkouts).
    BOOL remote = [row.checkout[@"remotes"] integerValue] > 0, upstream = [row.checkout[@"upstream"] boolValue];
    NSString *baseRef = [row.checkout[@"baseRef"] isKindOfClass:NSString.class] ? row.checkout[@"baseRef"] : nil;
    NSDictionary *last = self.outgoing[root];
    // What each commit listed now changed, by its hash: a commit's diff is the same in every checkout of its repo.
    NSMutableDictionary<NSString *, NSArray *> *shown = [NSMutableDictionary dictionary];
    for (NSDictionary *read in self.outgoing.allValues)
        for (NSDictionary *commit in read[@"commits"]) shown[commit[@"hash"]] = commit[@"files"];
    dispatch_async(self.queue, ^{
        NSString *from = !remote ? nil : upstream ? @"@{upstream}" : baseRef;
        // The same commits, from the same place: what they changed still stands.
        NSString *source = [NSString stringWithFormat:@"%@ %@", Git(root, @[@"rev-parse", @"HEAD"]),
                            from ? Git(root, @[@"rev-parse", from]) : @""];
        NSString *name = upstream ? [Git(root, @[@"rev-parse", @"--abbrev-ref", @"@{upstream}"])
                                     stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : nil;
        NSDictionary *read = [last[@"source"] isEqualToString:source] ? last
                           : from ? ReadOutgoing(root, from, shown) : @{@"commits": @[], @"more": @0};
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.outgoingBusy removeObject:root];
            if (!read) { if (done) done(nil); return; }
            if (read != last) {
                NSMutableDictionary *kept = [read mutableCopy];
                kept[@"source"] = source;
                if (name.length) kept[@"upstream"] = name;
                kept[@"v"] = @(++self.version);
                self.outgoing[root] = kept;
            }
            if (done) done(self.outgoing[root]);
        });
    });
}

- (NSString *)fileOf:(NSString *)sessionId path:(NSString *)path {
    NSString *root = self.roots[sessionId];
    if (!root || ![path isKindOfClass:NSString.class]) return nil;
    NSMutableArray *lists = [@[self.results[root][@"files"] ?: @[], self.results[root][@"unstaged"] ?: @[],
                               self.results[root][@"staged"] ?: @[]] mutableCopy];
    for (NSDictionary *commit in self.outgoing[root][@"commits"]) [lists addObject:commit[@"files"] ?: @[]];
    for (NSArray *files in lists)
        for (NSDictionary *file in files)
            if ([file[@"path"] isEqualToString:path]) return [root stringByAppendingPathComponent:path];
    return nil;
}

@end
