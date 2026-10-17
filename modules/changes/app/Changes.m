// Changes: what each session changed in its checkout, line by line: what isn't committed yet, and its commits not on
// GitHub yet.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Changes.h"
#import "Files.h"
#import "Git.h"
#import "Processes.h"
#import "Row.h"
#import "Text.h"
#import "Core.h"

// How often a checkout is looked at again, at most; the biggest new file read whole; the most a diff is read for (a
// checkout changing more than that isn't counted line by line); the longest line kept; the most lines a changes view
// is sent, the files past that listed with their counts only; and the most new files read.
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
    NSDictionary *run = RunTool(@"/usr/bin/git", all, nil);
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

// What isn't committed in a checkout, credited, as `git diff HEAD` and git status see it: every change since the last
// commit, staged or not, new files included (`others`, git's list of them, NUL-separated), each file saying whether
// it's staged whole (`saved`: nothing in it is left unstaged). `owners` are {path: [{sid, at, added, removed}]}. Nil
// when git can't say, or says too much.
static NSDictionary *CreditCheckout(NSString *root, NSDictionary *owners, NSString *others) {
    // Before the first commit there's no HEAD: everything is against nothing (git's empty tree).
    NSString *head = Git(root, @[@"rev-parse", @"--quiet", @"--verify", @"HEAD"]).length ? @"HEAD"
                                                                                        : @"4b825dc642cb6eb9a060e54bf8d69288fbee4904";
    NSString *all = Git(root, @[@"diff", @"--no-ext-diff", @"--no-textconv", @"--no-color", @"-U3", @"-M", head]);
    // The files with changes not staged yet: only their names are needed.
    NSString *unstaged = Git(root, @[@"diff", @"--name-only", @"-z"]);
    if (!all || !unstaged || !others) return nil;
    NSMutableSet *notStaged = [NSMutableSet setWithArray:[unstaged componentsSeparatedByString:@"\0"]];
    NSMutableArray *files = [ParseDiff(all) mutableCopy];
    NSArray *newPaths = [others componentsSeparatedByString:@"\0"];
    for (NSString *path in [newPaths subarrayWithRange:NSMakeRange(0, MIN(newPaths.count, kNewFiles))]) {
        NSDictionary *file = path.length ? NewFile(root, path) : nil;
        if (!file) continue;
        [files addObject:file];
        [notStaged addObject:path];
    }
    NSMutableArray *credited = [NSMutableArray array];
    NSMutableDictionary *parts = [NSMutableDictionary dictionary];
    for (NSDictionary *file in files) {
        NSMutableDictionary *done = [Credit(file, owners[file[@"path"]] ?: @[]) mutableCopy];
        done[@"saved"] = [notStaged containsObject:file[@"path"]] ? @NO : @YES;
        [credited addObject:done];
        AddParts(parts, done[@"counts"]);
    }
    return @{@"files": credited, @"parts": parts};
}

// What the commits not on GitHub yet changed, from `from` (where GitHub's copy is, as the island counts them) to
// HEAD, as ParseDiff gives it, for CreditCommits; kept for as long as the commits are the same. Nil when git can't
// say.
static NSArray *ReadCommits(NSString *root, NSString *from) {
    NSString *all = Git(root, @[@"diff", @"--no-ext-diff", @"--no-textconv", @"--no-color", @"-U3", @"-M",
                                [from stringByAppendingString:@"...HEAD"]]);
    return all ? ParseDiff(all) : nil;
}

// Those commits' changes, credited: each line with whose it is.
static NSDictionary *CreditCommits(NSArray *read, NSDictionary *owners) {
    NSMutableArray *credited = [NSMutableArray array];
    NSMutableDictionary *parts = [NSMutableDictionary dictionary];
    for (NSDictionary *file in read) {
        NSMutableDictionary *done = [Credit(file, owners[file[@"path"]] ?: @[]) mutableCopy];
        done[@"saved"] = @YES;
        [credited addObject:done];
        AddParts(parts, done[@"counts"]);
    }
    return @{@"files": credited, @"parts": parts};
}

// A full path as it is in a checkout, or nil if it's outside it.
static NSString *Within(NSString *path, NSString *root) {
    NSString *prefix = [root stringByAppendingString:@"/"];
    if ([path hasPrefix:prefix]) return [path substringFromIndex:prefix.length];
    // The real path (symlinks resolved) is asked for once per path: it's asked about every second.
    static NSCache *reals;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ reals = [NSCache new]; reals.countLimit = 5000; });
    NSString *real = [reals objectForKey:path];
    if (!real) [reals setObject:(real = RealPath(path) ?: @"") forKey:path];
    return [real hasPrefix:prefix] ? [real substringFromIndex:prefix.length] : nil;
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

// A file's hunks with only one session's changes in them, for its own view, so the rest of the file's lines aren't
// sent. Another's lines put in are in the file now, so they stay as unchanged lines; another's taken out aren't, so
// they go. What's left is cut down to the session's changes with three lines around each. The old side counts from the
// file as it would be without this session's changes, so its numbers still run on.
static NSArray *OwnHunks(NSArray *hunks, NSString *sid) {
    static const NSInteger around = 3;
    NSMutableArray *out = [NSMutableArray array];
    NSInteger shift = 0;
    for (NSDictionary *hunk in hunks) {
        NSInteger old = [hunk[@"oldStart"] integerValue] + shift, now = [hunk[@"newStart"] integerValue];
        NSMutableArray *lines = [NSMutableArray array];  // [line, old, now]
        for (NSArray *line in hunk[@"lines"]) {
            BOOL theirs = ![line[0] isEqualToString:@" "] && ![line[2] isEqual:sid];
            if (theirs && [line[0] isEqualToString:@"-"]) { shift--; continue; }
            if (theirs) shift++;
            [lines addObject:@[theirs ? @[@" ", line[1]] : line, @(old), @(now)]];
            NSString *sign = theirs ? @" " : line[0];
            if (![sign isEqualToString:@"+"]) old++;
            if (![sign isEqualToString:@"-"]) now++;
        }
        NSMutableArray<NSNumber *> *mine = [NSMutableArray array];
        for (NSUInteger k = 0; k < lines.count; k++)
            if (![lines[k][0][0] isEqualToString:@" "]) [mine addObject:@(k)];
        NSUInteger k = 0;
        while (k < mine.count) {
            NSInteger from = MAX(0, mine[k].integerValue - around), to = mine[k].integerValue;
            while (k + 1 < mine.count && mine[k + 1].integerValue - to <= 2 * around) to = mine[++k].integerValue;
            k++;
            NSRange part = NSMakeRange((NSUInteger)from, (NSUInteger)MIN((NSInteger)lines.count, to + around + 1) - from);
            NSArray *window = [lines subarrayWithRange:part];
            NSMutableArray *kept = [NSMutableArray arrayWithCapacity:window.count];
            for (NSArray *one in window) [kept addObject:one[0]];
            [out addObject:@{@"oldStart": window[0][1], @"newStart": window[0][2], @"lines": kept}];
        }
    }
    return out;
}

// Files as a view sends them: each saying whether whose its lines are is all known (none is while `allInDoubt`, nor in a
// file a command's record left out, `doubts`), and past the most a view is sent, listed with their counts and without
// their lines.
static NSArray *Shown(NSArray *files, BOOL allInDoubt, NSSet *doubts) {
    NSUInteger sent = 0;
    NSMutableArray *shown = [NSMutableArray array];
    for (NSDictionary *file in files) {
        NSUInteger lines = 0;
        for (NSDictionary *hunk in file[@"hunks"]) lines += [hunk[@"lines"] count];
        NSMutableDictionary *one = [file mutableCopy];
        one[@"complete"] = allInDoubt || [doubts containsObject:file[@"path"]] ? @NO : @YES;
        if (sent + lines > kViewLines) { one[@"hunks"] = @[]; one[@"cut"] = @YES; }
        else sent += lines;
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

// A session's view (Changes.h, viewOf:scope:), from its checkout's counted `result` (nil before the first count, or in
// a checkout no listed session edited in, which isn't `counted`); `unknown`, whether the session's changes aren't
// known. Plain, so it can be built off the main thread.
static NSDictionary *BuildView(NSDictionary *result, NSString *sessionId, NSString *scope, BOOL counted, BOOL unknown,
                               BOOL allInDoubt, NSSet *doubts) {
    // A checkout no listed session edited in isn't counted: as far as its sessions go, there's nothing to commit.
    if (!result && !counted)
        return @{@"scope": [scope isEqualToString:@"branch"] ? @"branch" : @"session", @"v": @0, @"files": @[],
                 @"complete": @YES};
    if (!result) return nil;
    if (result[@"tooMuch"]) return @{@"missing": @"Too many changes to count here."};
    // A session whose changes aren't known has only the checkout's to show.
    BOOL branch = [scope isEqualToString:@"branch"] || unknown;
    NSMutableArray *mine = [NSMutableArray array];
    for (NSDictionary *file in result[@"files"]) {
        if (!branch && !file[@"counts"][sessionId]) continue;
        // Its own view has only its own changes, so only they're sent.
        if (branch) [mine addObject:file];
        else {
            NSMutableDictionary *own = [file mutableCopy];
            own[@"hunks"] = OwnHunks(file[@"hunks"], sessionId);
            [mine addObject:own];
        }
    }
    // Complete when every session in the checkout is known, and no command's record left out lines here: only then
    // is a line no one's edits explain no listed session's. Each file says so for itself too.
    return @{@"scope": branch ? @"branch" : @"session", @"v": result[@"v"], @"files": Shown(mine, allInDoubt, doubts),
             @"complete": @(Complete(result[@"files"], allInDoubt, doubts))};
}

@interface Changes ()
@property (strong) dispatch_queue_t queue;
// Kept on the main thread: each session's checkout, each checkout's credited branch ({files, parts, v}) and what it was
// worked out from, when it was last looked at, and the ones being worked out now.
@property (strong) NSMutableDictionary<NSString *, NSString *> *roots;
// Each listed session's row, and each checkout's commits view as last worked out (with what it was worked out from,
// `source`, and for opening its files), for the commits view, worked out only when it's asked for.
@property (strong) NSMutableDictionary<NSString *, Row *> *rows;
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *commits;
@property (strong) NSMutableSet<NSString *> *commitsBusy;
@property (strong) NSMutableDictionary<NSString *, NSNumber *> *commitsLookedAt;
// The checkouts being counted now, and each session's checkouts edited (rootsEditedBy:).
@property (strong) NSSet<NSString *> *counted;
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *edited;
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *results;
@property (strong) NSMutableDictionary<NSString *, NSString *> *sources;
@property (strong) NSMutableDictionary<NSString *, NSNumber *> *lookedAt;
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
    self.busy = [NSMutableSet set];
    self.rows = [NSMutableDictionary dictionary];
    self.commits = [NSMutableDictionary dictionary];
    self.commitsBusy = [NSMutableSet set];
    self.commitsLookedAt = [NSMutableDictionary dictionary];
    self.edited = [NSMutableDictionary dictionary];
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
    // Each checkout's editors: the sessions running in it that edited files, and any other listed session that edited
    // files in it from elsewhere, whose lines there are as much its own. Those, and the sessions running in it, are
    // the ones whose changes have to be known for it to be complete.
    NSMutableDictionary<NSString *, NSMutableArray<Row *> *> *editors = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *unknown = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *doubts = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *failing = [NSMutableDictionary dictionary];
    for (NSString *root in checkouts) {
        for (Row *row in editing)
            if ([self.roots[row.sessionId] isEqualToString:root] || [[self rootsEditedBy:row] containsObject:root])
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
            for (NSString *path in edits[@"doubts"]) {
                NSString *inside = Within(path, root);
                if (inside) [doubts[root] ?: (doubts[root] = [NSMutableSet set]) addObject:inside];
            }
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
    self.counted = [NSSet setWithArray:editors.allKeys];
    for (NSString *root in self.results.allKeys)
        if (!editors[root]) {
            [self.results removeObjectForKey:root];
            [self.sources removeObjectForKey:root];
        }
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    // A checkout's commits not on GitHub yet are worked out ahead, while it has some (as the island counts them).
    for (NSString *sid in self.rows) {
        Row *row = self.rows[sid];
        NSString *root = self.roots[sid];
        NSDictionary *c = row.checkout;
        NSInteger waiting = [c[@"remotes"] integerValue] > 0
            ? [c[[c[@"upstream"] boolValue] ? @"ahead" : @"aheadOfBase"] integerValue] : 0;
        if (waiting <= 0 || now - [self.commitsLookedAt[root] doubleValue] < kEvery) continue;
        self.commitsLookedAt[root] = @(now);
        [self workCommitsAt:root row:row done:nil];
    }
    [editors enumerateKeysAndObjectsUsingBlock:^(NSString *root, NSArray<Row *> *rows, BOOL *stop) {
        if ([self.busy containsObject:root] || now - [self.lookedAt[root] doubleValue] < kEvery) return;
        self.lookedAt[root] = @(now);
        // The files they edited in this checkout, each with whose edits and their lines, newest edit first: copied,
        // only when a count is due, as they're read on the queue.
        NSDictionary *byPath = [self ownersAt:root rows:rows];
        NSString *edits = OwnersSource(byPath), *known = self.sources[root];
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
    }];
}

// The checkouts a session edited files in, from its edits, worked out again only when they or the checkouts change.
- (NSSet<NSString *> *)rootsEditedBy:(Row *)row {
    NSDictionary *edits = [self editsOf:row];
    NSArray *roots = [[NSSet setWithArray:self.roots.allValues].allObjects sortedArrayUsingSelector:@selector(compare:)];
    NSString *key = [NSString stringWithFormat:@"%lu %@", [edits[@"count"] unsignedLongValue],
                     [roots componentsJoinedByString:@"\n"]];
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
    if (!result) return nil;
    NSString *sid = row.sessionId;
    // Not known: the whole checkout's count, which is certain, and nothing said to be the session's.
    if ([self.unknown[root] containsObject:sid]) {
        NSInteger added = 0, removed = 0;
        for (NSArray *part in [result[@"parts"] allValues]) {
            added += [part[0] integerValue];
            removed += [part[1] integerValue];
        }
        return @{@"known": @NO, @"added": @(added), @"removed": @(removed), @"files": @[], @"parts": @{},
                 @"v": result[@"v"]};
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
             @"complete": @(Complete(result[@"files"], [self allInDoubt:root], self.doubts[root])), @"v": result[@"v"]};
}

- (NSDictionary *)viewOf:(NSString *)sessionId scope:(NSString *)scope {
    NSString *root = self.roots[sessionId];
    return BuildView(root ? self.results[root] : nil, sessionId, scope, !root || [self.counted containsObject:root],
                     [self.unknown[root] containsObject:sessionId], [self allInDoubt:root], self.doubts[root]);
}

- (void)viewOf:(NSString *)sessionId scope:(NSString *)scope done:(void (^)(NSString *json))done {
    NSString *root = self.roots[sessionId];
    BOOL allInDoubt = [self allInDoubt:root];
    NSSet *doubts = self.doubts[root];
    void (^send)(NSDictionary *) = ^(NSDictionary *view) {
        NSArray *said = @[sessionId ?: @"", scope ?: @"session", view ?: @{@"missing": @"Still counting the changes."}];
        NSData *data = [NSJSONSerialization dataWithJSONObject:said options:0 error:nil];
        NSString *json = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ if (json) done(json); });
    };
    if ([scope isEqualToString:@"commits"]) {
        [self workCommitsAt:root row:self.rows[sessionId] done:^(NSDictionary *commits) {
            dispatch_async(self.views, ^{
                send(commits ? @{@"scope": @"commits", @"v": commits[@"v"],
                                 @"files": Shown(commits[@"files"], allInDoubt, doubts),
                                 @"complete": @(Complete(commits[@"files"], allInDoubt, doubts))}
                             : @{@"missing": @"Couldn't read the commits."});
            });
        }];
        return;
    }
    // What it's built from, as it is now; then built, and made JSON, off the main thread.
    NSDictionary *result = [(root ? self.results[root] : nil) copy];
    BOOL counted = !root || [self.counted containsObject:root], unknown = [self.unknown[root] containsObject:sessionId];
    dispatch_async(self.views, ^{
        send(BuildView(result, sessionId, scope, counted, unknown, allInDoubt, doubts));
    });
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

- (void)commitsOf:(NSString *)sessionId done:(void (^)(NSDictionary *view))done {
    Row *row = self.rows[sessionId];
    NSString *root = self.roots[sessionId];
    if (!row || !root) { done(nil); return; }
    [self workCommitsAt:root row:row done:^(NSDictionary *now) {
        BOOL allInDoubt = [self allInDoubt:root];
        done(now ? @{@"scope": @"commits", @"v": now[@"v"], @"files": Shown(now[@"files"], allInDoubt, self.doubts[root]),
                     @"complete": @(Complete(now[@"files"], allInDoubt, self.doubts[root]))} : nil);
    }];
}

// Works out a checkout's commits not on GitHub yet, credited (CreditCommits), unless the last ones still stand; `done`
// (if any) gets them on the main thread, or nil. Also done ahead, every few seconds while there are commits waiting,
// so the island's commits stage opens them at once.
- (void)workCommitsAt:(NSString *)root row:(Row *)row done:(void (^)(NSDictionary *commits))done {
    // A session whose checkout couldn't be read this time round (git failed for a moment) has none to work out.
    if (!root) {
        if (done) dispatch_async(dispatch_get_main_queue(), ^{ done(nil); });
        return;
    }
    if ([self.commitsBusy containsObject:root]) {
        // One is being worked out: this waits for it.
        dispatch_async(self.queue, ^{ dispatch_async(dispatch_get_main_queue(), ^{
            if (done) done(self.commits[root]);
        }); });
        return;
    }
    [self.commitsBusy addObject:root];
    // As the island counts them (unpushedCommits in panel/scripts/whose-move.js): past the upstream when there is
    // one, else past the base branch's GitHub copy; none without a remote.
    BOOL remote = [row.checkout[@"remotes"] integerValue] > 0, upstream = [row.checkout[@"upstream"] boolValue];
    // Every listed session's edits that are in this checkout, wherever it runs.
    NSDictionary *owners = [self ownersAt:root rows:self.rows.allValues];
    NSString *edits = OwnersSource(owners);
    NSDictionary *last = self.commits[root];
    dispatch_async(self.queue, ^{
        NSString *baseRef = nil;
        if (!upstream) BranchStart(root, NULL, &baseRef);
        NSString *from = !remote ? nil : upstream ? @"@{upstream}" : baseRef;
        // The same commits, from the same place: what they changed still stands; with the same edits to credit them by
        // too, so does the whole view.
        NSString *commits = [NSString stringWithFormat:@"%@ %@", Git(root, @[@"rev-parse", @"HEAD"]),
                             from ? Git(root, @[@"rev-parse", from]) : @""];
        NSString *source = [commits stringByAppendingFormat:@"\n%@", edits];
        NSArray *read = [last[@"read source"] isEqualToString:commits] ? last[@"read"]
                           : from ? ReadCommits(root, from) : @[];
        NSDictionary *credited = [last[@"source"] isEqualToString:source] ? last
                               : read ? CreditCommits(read, owners) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.commitsBusy removeObject:root];
            if (!credited) { if (done) done(nil); return; }
            if (credited != last) {
                NSMutableDictionary *kept = [credited mutableCopy];
                kept[@"source"] = source;
                kept[@"read"] = read;
                kept[@"read source"] = commits;
                kept[@"v"] = @(++self.version);
                self.commits[root] = kept;
            }
            if (done) done(self.commits[root]);
        });
    });
}


- (NSString *)fileOf:(NSString *)sessionId path:(NSString *)path {
    NSString *root = self.roots[sessionId];
    if (!root || ![path isKindOfClass:NSString.class]) return nil;
    for (NSArray *files in @[self.results[root][@"files"] ?: @[], self.commits[root][@"files"] ?: @[]])
        for (NSDictionary *file in files)
            if ([file[@"path"] isEqualToString:path]) return [root stringByAppendingPathComponent:path];
    return nil;
}

@end
