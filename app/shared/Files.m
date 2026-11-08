// Files: where Whozmove's files are, and reading files: JSON, JSONL lines, times.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Files.h"
#import "Links.h"
#import <dirent.h>
#import <fcntl.h>
#import <pwd.h>
#import <sys/stat.h>
#import <unistd.h>

// The home folder: $HOME when it's set, else the account's own. NSHomeDirectory() alone ignores $HOME, which
// tests/rows.sh points at a sample home; launchd sets it to the account's own folder for the real app. Every path
// is built from it, many times a second, and the environment doesn't change while the app runs, so it's looked
// up once.
NSString *Home(void) {
    static NSString *home;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *set = NSProcessInfo.processInfo.environment[@"HOME"];
        home = set.isAbsolutePath ? set : NSHomeDirectory();
    });
    return home;
}

// The account's own home folder is the one its record names, as swap-in.sh reads it, whatever $HOME says: whether
// Home() is it (nil when the record can't be read).
static NSNumber *HomeIsTheAccounts(void) {
    struct passwd *account = getpwuid(getuid());
    if (!account || !account->pw_dir) return nil;
    NSString *own = [NSFileManager.defaultManager stringWithFileSystemRepresentation:account->pw_dir
                                                                              length:strlen(account->pw_dir)];
    return @([RealPath(Home()) isEqualToString:RealPath(own)]);
}

BOOL HomeIsYourOwn(void) {
    NSNumber *own = HomeIsTheAccounts();
    return own ? own.boolValue : YES;
}

BOOL HomeSurelyYourOwn(void) {
    return HomeIsTheAccounts().boolValue;
}

// Whozmove's own files (what the hooks record, requests waiting for your OK, the log), kept apart from any
// one agent's folder so other agents can be added beside Claude. The hooks write here too and spell the
// folder out themselves (ROOT in each); the Claude Code module's tests take it from this line, so if they ever
// disagree the tests fail rather than the panel quietly showing nothing.
NSString *AppDir(NSString *sub) {
    NSString *base = [Home() stringByAppendingPathComponent:@"Library/Application Support/Whozmove"];
    return sub.length ? [base stringByAppendingPathComponent:sub] : base;
}

// macOS's own record of what each app may do is readable only with Full Disk Access, and trying to read it never asks
// you anything: refused (or missing, in a sample home) is not allowed.
BOOL FullDiskAccess(void) {
    NSString *record = [Home() stringByAppendingPathComponent:@"Library/Application Support/com.apple.TCC/TCC.db"];
    int fd = open(record.fileSystemRepresentation, O_RDONLY);
    if (fd < 0) return NO;
    close(fd);
    return YES;
}

// Full Disk Access's list in System Settings shows an app only once macOS has refused it a folder that permission
// guards, and its own record above isn't one that counts. Safari's and Mail's folders are, and macOS refuses them
// without asking anything; a Mac may lack one, never both. So one of them is tried first.
void ShowFullDiskAccessSettings(void) {
    for (NSString *folder in @[@"Library/Safari", @"Library/Mail"]) {
        DIR *dir = opendir([Home() stringByAppendingPathComponent:folder].fileSystemRepresentation);
        if (dir) closedir(dir);
        if (dir || errno != ENOENT) break;
    }
    OpenLink(@"x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles");
}

// Set by the print modes (main.m): what tests/rows.sh prints mustn't depend on the Mac it runs on, so a file the
// whole Mac shares, like Claude Code's managed settings, is read from the home folder in $HOME instead.
BOOL MachineFilesInHome;

// A file the whole Mac shares, by its absolute path.
NSString *MachineFile(NSString *path) {
    return MachineFilesInHome ? [Home() stringByAppendingPathComponent:path] : path;
}

id ReadJSON(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    return data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
}

// What tells a file's version apart from the next: the file itself (a file replaced whole is a new one), its size and
// when it was written, to the nanosecond.
static NSString *Stamp(const struct stat *info) {
    return [NSString stringWithFormat:@"%llu %lld %ld.%09ld", (unsigned long long)info->st_ino,
                                      (long long)info->st_size, (long)info->st_mtimespec.tv_sec,
                                      info->st_mtimespec.tv_nsec];
}

// A file as `read` makes it of what's in it, kept by its path and `kind` with the stamp it was read at. Read from the
// rows' queue, the main thread and others, so what's kept is behind a lock; a file is read outside it.
static id Kept(NSString *path, NSString *kind, id (^read)(NSData *data)) {
    static NSMutableDictionary<NSString *, NSArray *> *kept;
    static NSLock *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        kept = [NSMutableDictionary dictionary];
        lock = [NSLock new];
    });
    if (!path.length) return nil;
    NSString *key = [kind stringByAppendingString:path];
    struct stat info;
    if (stat(path.fileSystemRepresentation, &info) != 0) {
        [lock lock];
        [kept removeObjectForKey:key];
        [lock unlock];
        return nil;
    }
    NSString *stamp = Stamp(&info);
    [lock lock];
    NSArray *was = kept[key];
    [lock unlock];
    if ([was[0] isEqualToString:stamp]) return was[1];
    NSData *data = [NSData dataWithContentsOfFile:path];
    id value = data ? read(data) : nil;
    [lock lock];
    // Files come and go (one per session), so what's kept is let go now and then rather than growing for good.
    if (kept.count > 4000) [kept removeAllObjects];
    if (value) kept[key] = @[stamp, value];
    else [kept removeObjectForKey:key];
    [lock unlock];
    return value;
}

id ReadJSONKept(NSString *path) {
    return Kept(path, @"json ", ^id(NSData *data) {
        return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    });
}

NSString *ReadTextKept(NSString *path) {
    return Kept(path, @"text ", ^id(NSData *data) {
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    });
}

double FileModifiedAt(NSString *path) {
    struct stat info;
    if (!path.length || stat(path.fileSystemRepresentation, &info) != 0) return 0;
    return info.st_mtimespec.tv_sec + info.st_mtimespec.tv_nsec / 1e9;
}

// A folder with any symlinks on the way resolved, as git names a repo by its real folder, so a checkout opened through a
// symlinked path is still the same project. As it is when it can't be resolved.
NSString *RealPath(NSString *path) {
    if (!path.length) return path;
    char *real = realpath(path.fileSystemRepresentation, NULL);
    NSString *resolved = real ? [NSFileManager.defaultManager stringWithFileSystemRepresentation:real
                                                                                          length:strlen(real)] : nil;
    free(real);
    return resolved ?: path;
}

BOOL PathWithin(NSString *path, NSString *folder) {
    if (!path.length || !folder.length) return NO;
    NSString *real = RealPath(path), *top = RealPath(folder);
    NSString *inside = [top hasSuffix:@"/"] ? top : [top stringByAppendingString:@"/"];
    return [real isEqualToString:top] || [real hasPrefix:inside];
}

// The first `max` characters of a string, without splitting an emoji or accented letter in two (half of
// one makes a string JSON can't encode).
NSString *Clip(NSString *text, NSUInteger max) {
    if (text.length <= max) return text;
    return [text substringToIndex:[text rangeOfComposedCharacterSequenceAtIndex:max].location];
}

NSString *AsText(id value) { return [value isKindOfClass:NSString.class] ? value : nil; }
NSNumber *AsNumber(id value) { return [value isKindOfClass:NSNumber.class] ? value : nil; }
NSArray *AsList(id value) { return [value isKindOfClass:NSArray.class] ? value : nil; }
NSDictionary *AsRecord(id value) { return [value isKindOfClass:NSDictionary.class] ? value : nil; }

// A transcript timestamp (ISO 8601 in UTC, with milliseconds) in ms since 1970; 0 if there isn't one. One without
// fractions of a second (a plan's usage resetting on the hour can come as `…T03:00:00Z`) is read too: the parser
// that takes fractions refuses it. Called from several threads, so the parsers are made exactly once (two threads
// making one at once would free it while the other used it).
double TimestampMs(id iso) {
    static NSISO8601DateFormatter *parser, *whole;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        parser = [NSISO8601DateFormatter new];
        parser.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
        whole = [NSISO8601DateFormatter new];
        whole.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    });
    if (![iso isKindOfClass:NSString.class]) return 0;
    // The same times are read every second (a session's last message, as its details are worked out), and parsing one
    // costs far more than finding it again, so each is kept, a few thousand at most.
    static NSMutableDictionary<NSString *, NSNumber *> *known;
    static NSLock *lock;
    static dispatch_once_t keeping;
    dispatch_once(&keeping, ^{
        known = [NSMutableDictionary dictionary];
        lock = [NSLock new];
    });
    [lock lock];
    NSNumber *was = known[iso];
    [lock unlock];
    if (was) return was.doubleValue;
    NSDate *date = [parser dateFromString:iso] ?: [whole dateFromString:iso];
    double ms = date ? date.timeIntervalSince1970 * 1000 : 0;
    [lock lock];
    if (known.count > 4000) [known removeAllObjects];
    known[iso] = @(ms);
    [lock unlock];
    return ms;
}

// The JSON record on the line of a JSONL chunk that contains `location`, parsed (nil if it isn't valid JSON),
// looking no further than `end`. *line, if given, is set to that line, without its newline.
id JSONLineAt(NSData *chunk, NSUInteger location, NSUInteger end, NSRange *line) {
    NSData *newline = [@"\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSRange before = [chunk rangeOfData:newline options:NSDataSearchBackwards range:NSMakeRange(0, location)];
    NSRange after = [chunk rangeOfData:newline options:0 range:NSMakeRange(location, end - location)];
    NSUInteger start = before.location == NSNotFound ? 0 : NSMaxRange(before);
    NSUInteger stop = after.location == NSNotFound ? end : after.location;
    if (line) *line = NSMakeRange(start, stop - start);
    NSData *record = [chunk subdataWithRange:NSMakeRange(start, stop - start)];
    return [NSJSONSerialization JSONObjectWithData:record options:0 error:nil];
}
