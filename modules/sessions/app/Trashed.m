// Trashed: the conversations Sessions moved to the Trash (Trashed.h).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Trashed.h"
#import <sys/stat.h>
#import <sys/mount.h>
#import "Files.h"
#import "Processes.h"

@interface Trashed ()
@property (copy) NSString *folder, *helper, *standIn;
@property (copy) BOOL (^isPlace)(NSString *path);
- (void)renameBack:(NSDictionary *)item of:(NSString *)conversationId;
@end

@implementation Trashed

- (instancetype)initWithFolder:(NSString *)folder helper:(NSString *)helper standIn:(NSString *)standIn
                       isPlace:(BOOL (^)(NSString *path))isPlace {
    if (!(self = [super init])) return nil;
    self.isPlace = isPlace;
    self.folder = folder;
    self.helper = helper;
    self.standIn = standIn;
    return self;
}

- (NSString *)notePath:(NSString *)conversationId {
    return [self.folder stringByAppendingPathComponent:[conversationId stringByAppendingPathExtension:@"json"]];
}

// A note, written whole or not at all, only yours to read, in a folder only yours to open.
- (BOOL)keep:(NSDictionary *)note for:(NSString *)conversationId {
    [NSFileManager.defaultManager createDirectoryAtPath:self.folder withIntermediateDirectories:YES
                                             attributes:@{NSFilePosixPermissions: @0700} error:nil];
    NSData *data = [NSJSONSerialization dataWithJSONObject:note options:NSJSONWritingSortedKeys error:nil];
    NSString *path = [self notePath:conversationId];
    NSString *temporary = [path stringByAppendingFormat:@".%d.tmp", getpid()];
    if (![data writeToFile:temporary atomically:NO]) return NO;
    chmod(temporary.fileSystemRepresentation, 0600);
    return rename(temporary.fileSystemRepresentation, path.fileSystemRepresentation) == 0;
}

// One file to the Trash, and where it went: macOS's, or the stand-in folder, under a name of its own there. Nil if it
// didn't go, with why (`why`), or with no why when it went somewhere it didn't say.
- (NSString *)toTrash:(NSString *)path why:(NSString **)why {
    NSFileManager *fm = NSFileManager.defaultManager;
    *why = @"macOS didn't move it";
    if (self.standIn && !self.helper) {
        [fm createDirectoryAtPath:self.standIn withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *to = [self.standIn stringByAppendingPathComponent:path.lastPathComponent];
        for (int n = 2; [fm fileExistsAtPath:to]; n++)
            to = [self.standIn stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ %d%@",
                path.lastPathComponent.stringByDeletingPathExtension, n,
                path.pathExtension.length ? [@"." stringByAppendingString:path.pathExtension] : @""]];
        return [fm moveItemAtPath:path toPath:to error:nil] ? to : nil;
    }
    // A run of the app's own for each file: macOS records where an item came from, which is what Finder's Put Back
    // reads, only for the first item a process moves to the Trash.
    NSDictionary *ran = RunBriefly(self.helper, @[@"--helper-trash-item", path],
                                   @{@"HOME": Home(), @"PATH": @"/usr/bin:/bin"}, 10, 64 * 1024, NO);
    NSDictionary *said = AsRecord([NSJSONSerialization JSONObjectWithData:ran[@"out"] ?: NSData.data options:0
                                                                    error:nil]);
    NSString *to = AsText(said[@"to"]);
    struct stat info;
    if (lstat(path.fileSystemRepresentation, &info) == 0) {
        *why = AsText(said[@"why"]) ?: [ran[@"timedOut"] boolValue] ? @"it took more than 10 seconds"
                                                                      : @"macOS didn't move it";
        return nil;
    }
    // Gone: where the run says it went counts, though it may not have finished (cut off by its time, say), so it comes
    // back with the rest if another can't go. Gone without saying where, it's somewhere in the Trash.
    if ([self is:to inTrashFor:path] && lstat(to.fileSystemRepresentation, &info) == 0) return to;
    *why = nil;
    return nil;
}

// Whether a place is in the Trash a file goes to (the stand-in one, in a print run), the Trash of the file's folder,
// which is still there once the file has gone.
- (BOOL)is:(NSString *)to inTrashFor:(NSString *)from {
    NSString *trash = self.standIn ?: TrashFolderFor(from.stringByDeletingLastPathComponent);
    return PlainPath(to) && trash.length && [to hasPrefix:[trash stringByAppendingString:@"/"]];
}

// A file back where it was, only while it's still where it went and nothing has taken its place.
static BOOL MoveBack(NSDictionary *item) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *from = item[@"from"], *to = item[@"to"];
    struct stat info;
    if (lstat(to.fileSystemRepresentation, &info) != 0 || lstat(from.fileSystemRepresentation, &info) == 0) return NO;
    [fm createDirectoryAtPath:from.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil
                        error:nil];
    return [fm moveItemAtPath:to toPath:from error:nil];
}

- (NSString *)trash:(NSString *)conversationId files:(NSArray<NSString *> *)files about:(NSDictionary *)about
              stuck:(NSString **)stuck lost:(BOOL *)lost {
    // One after another, each its own run (toTrash:): runs side by side can each write the Trash's record of where
    // an item came from at once, and one of them is lost.
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    for (NSString *path in files) {
        NSString *why = nil, *to = [self toTrash:path why:&why];
        if (!to) {
            // All of it or none: what went comes back.
            for (NSDictionary *item in items.reverseObjectEnumerator) MoveBack(item);
            *stuck = why ? path : nil;
            *lost = !why;
            return why ? [NSString stringWithFormat:@"one of its files couldn't be moved, as %@", why]
                       : @"one of its files went to the Trash without saying where, so it's there, and the rest came "
                         @"back";
        }
        [items addObject:@{@"from": path, @"to": to}];
    }
    NSMutableDictionary *note = [@{@"id": conversationId, @"items": items,
                                   @"at": @(NSDate.date.timeIntervalSince1970 * 1000)} mutableCopy];
    for (NSString *field in @[@"title", @"folder"]) if (AsText(about[field])) note[field] = about[field];
    if (![self keep:note for:conversationId]) {
        for (NSDictionary *item in items.reverseObjectEnumerator) MoveBack(item);
        return @"Whozmove couldn't keep where its files went";
    }
    return nil;
}

- (NSDictionary *)noteOf:(NSString *)conversationId {
    return AsRecord(ReadJSON([self notePath:conversationId]));
}

// Worked out from HOME, never asked of macOS, which answers for your own home folder whatever HOME says: the home
// folder's .Trash on its disk, and on another disk that disk's .Trashes/<your id>, where macOS puts what's moved there.
NSString *TrashFolderFor(NSString *folder) {
    struct stat here, home;
    if (stat(folder.fileSystemRepresentation, &here) != 0 || stat(Home().fileSystemRepresentation, &home) != 0)
        return nil;
    if (here.st_dev == home.st_dev) return [Home() stringByAppendingPathComponent:@".Trash"];
    struct statfs disk;
    if (statfs(folder.fileSystemRepresentation, &disk) != 0) return nil;
    return [NSString stringWithFormat:@"%s/.Trashes/%u", disk.f_mntonname, getuid()];
}

BOOL PlainPath(NSString *path) {
    return [path hasPrefix:@"/"] && ![path.pathComponents containsObject:@".."]
        && ![path.pathComponents containsObject:@"."];
}

// Whether a note's item is one this conversation's could be: from one of its own files' places (each is named by its
// id, as <id>.jsonl, <id>/ or <id>.json, in a folder Claude Code or Whozmove keeps them in), to a place in the Trash
// (the stand-in one, in a print run). Anything else running as you could have written the note, so nothing is moved
// anywhere it says otherwise.
- (BOOL)item:(NSDictionary *)item isOf:(NSString *)conversationId {
    NSString *from = AsText(item[@"from"]), *to = AsText(item[@"to"]);
    if (!PlainPath(from) || ![from.lastPathComponent.stringByDeletingPathExtension isEqual:conversationId]) return NO;
    return (!self.isPlace || self.isPlace(from)) && [self is:to inTrashFor:from];
}

- (NSString *)putBack:(NSString *)conversationId {
    NSDictionary *note = [self noteOf:conversationId];
    NSArray *items = AsList(note[@"items"]);
    if (!items.count) return @"It isn't in the Trash any more";
    // Each file is checked before any moves, so it comes back whole or not at all. One Finder has put back already is
    // left where it is (given its own name first, if the Trash gave it another), and the rest follow it.
    struct stat info;
    NSMutableArray<NSDictionary *> *going = [NSMutableArray array];
    for (id each in items) {
        NSDictionary *item = AsRecord(each);
        if (![self item:item isOf:conversationId]) return @"put it back from the Trash in Finder";
        [self renameBack:item of:conversationId];
        BOOL there = lstat([AsText(item[@"from"]) fileSystemRepresentation], &info) == 0;
        BOOL inTrash = lstat([AsText(item[@"to"]) fileSystemRepresentation], &info) == 0;
        if (there && inTrash) return @"there's a conversation file there again";
        if (!there && !inTrash) return @"some of it isn't in the Trash any more";
        if (inTrash) [going addObject:item];
    }
    // One that won't move back sends those that did back to the Trash, so the note still says where all of it is.
    NSMutableArray<NSDictionary *> *back = [NSMutableArray array];
    for (NSDictionary *item in going) {
        if (MoveBack(item)) {
            [back addObject:item];
            continue;
        }
        for (NSDictionary *done in back.reverseObjectEnumerator)
            [NSFileManager.defaultManager moveItemAtPath:done[@"from"] toPath:done[@"to"] error:nil];
        return [NSString stringWithFormat:@"%@ couldn't be moved", [AsText(item[@"to"]) lastPathComponent]];
    }
    [NSFileManager.defaultManager removeItemAtPath:[self notePath:conversationId] error:nil];
    return nil;
}

// Finder's Put Back brings a file back under the name it has in the Trash, and two of a conversation's files share a
// name (its transcript's folder and its edited files' copies, or Whozmove's two notes, each its id), so the Trash
// renames one ("<id> 10-00-00-000"): once that one is back beside its own place, with nothing there, it's given its own
// name again. Only for a note's item that could be this conversation's, and only a plain file or folder whose name is
// the Trash's way of renaming its own (a space, then only digits and dashes, before its extension): anything running as
// you could have written the note, so it can't name any other file to be renamed.
- (void)renameBack:(NSDictionary *)item of:(NSString *)conversationId {
    NSString *from = AsText(item[@"from"]), *to = AsText(item[@"to"]);
    if (![self item:item isOf:conversationId]) return;
    NSString *stem = from.lastPathComponent.stringByDeletingPathExtension, *name = to.lastPathComponent;
    NSString *extension = from.pathExtension.length ? [@"." stringByAppendingString:from.pathExtension] : @"";
    if (name.length <= stem.length + 1 + extension.length || ![name hasPrefix:[stem stringByAppendingString:@" "]]
        || (extension.length && ![name hasSuffix:extension]))
        return;
    NSString *mark = [name substringWithRange:NSMakeRange(stem.length + 1,
                                                          name.length - stem.length - 1 - extension.length)];
    NSCharacterSet *notTime = [NSCharacterSet characterSetWithCharactersInString:@"0123456789-"].invertedSet;
    if ([mark rangeOfCharacterFromSet:notTime].location != NSNotFound) return;
    NSString *back = [from.stringByDeletingLastPathComponent stringByAppendingPathComponent:name];
    struct stat info;
    if (lstat(to.fileSystemRepresentation, &info) == 0 || lstat(from.fileSystemRepresentation, &info) == 0
        || lstat(back.fileSystemRepresentation, &info) != 0 || !(S_ISREG(info.st_mode) || S_ISDIR(info.st_mode)))
        return;
    rename(back.fileSystemRepresentation, from.fileSystemRepresentation);
}

- (NSArray<NSDictionary *> *)now {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    for (NSString *file in [fm contentsOfDirectoryAtPath:self.folder error:nil]) {
        if (![file.pathExtension isEqualToString:@"json"]) continue;
        NSString *conversationId = file.stringByDeletingPathExtension;
        NSDictionary *note = [self noteOf:conversationId];
        for (NSDictionary *item in AsList(note[@"items"])) [self renameBack:AsRecord(item) of:conversationId];
        BOOL left = NO;
        for (id item in AsList(note[@"items"]))
            if ([fm fileExistsAtPath:AsText(AsRecord(item)[@"to"]) ?: @""]) left = YES;
        // The Trash emptied: nothing of it is left to put back, so the note goes too.
        if (!left) {
            [fm removeItemAtPath:[self.folder stringByAppendingPathComponent:file] error:nil];
            continue;
        }
        NSMutableDictionary *each = [@{@"id": conversationId, @"at": AsNumber(note[@"at"]) ?: @0} mutableCopy];
        for (NSString *field in @[@"title", @"folder"]) if (AsText(note[field])) each[field] = note[field];
        [out addObject:each];
    }
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"at"] compare:a[@"at"]];
    }];
    return out;
}

- (NSArray<NSString *> *)placesOf:(NSString *)conversationId {
    NSMutableArray<NSString *> *places = [NSMutableArray array];
    for (id item in AsList([self noteOf:conversationId][@"items"])) {
        NSString *to = AsText(AsRecord(item)[@"to"]);
        if (to && [NSFileManager.defaultManager fileExistsAtPath:to]) [places addObject:to];
    }
    return places;
}

@end
