// Conversations: every conversation Claude Code keeps on this Mac (Conversations.h).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Conversations.h"
#import <sys/stat.h>
#import "ClaudeCodeFacts.h"
#import "Transcripts.h"
#import "ClaudeSessions.h"
#import "KeptSessions.h"
#import "Files.h"

// How much of a transcript is read for its folder (its first records), and for its titles and its last message (its
// last part, which almost always holds them all, as Claude Code writes its title again as it goes on; more of it only
// when that finds no title), so the first look at hundreds of long conversations stays small. A name you gave it with
// /rename is found while it's in that part (kClaudeCodeCustomTitle), so a long one renamed early shows Claude's title.
static const NSUInteger kHeadRead = 64 * 1024;
static const unsigned long long kTailRead = 256 * 1024, kTailReadMore = 4 * 1024 * 1024;

// A conversation's id is a UUID; the project folders hold other files too (its memory, say).
static BOOL IsConversationId(NSString *name) {
    return [[NSUUID alloc] initWithUUIDString:name] != nil;
}

// The folder the conversation started in: the first record that names one.
static NSString *FolderIn(NSData *head) {
    for (NSString *line in [[[NSString alloc] initWithData:head encoding:NSUTF8StringEncoding]
                            componentsSeparatedByString:@"\n"]) {
        if (![line containsString:@"\"cwd\""]) continue;
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *record = AsRecord([NSJSONSerialization JSONObjectWithData:data options:0 error:nil]);
        NSString *folder = AsText(record[@"cwd"]);
        if ([folder hasPrefix:@"/"]) return folder;
    }
    return nil;
}

// What Whozmove kept of the session once it ended (KeptSessions): the terminal it ran in, when it saw it run; and the
// hook's record of it (ClaudeSessions).
static NSString *KeptNotePath(NSString *conversationId) {
    return [KeptFolder() stringByAppendingPathComponent:[conversationId stringByAppendingPathExtension:@"json"]];
}

static NSString *HookNotePath(NSString *conversationId) {
    return HookRecordPath(conversationId);
}

// One conversation, read from its transcript: its folder, its title (the name you gave it over Claude Code's), when it
// last moved (its newest message, else the file's date) and where it ran, as far as Whozmove saw.
static NSDictionary *Read(NSString *path, NSString *conversationId, double modified) {
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!fh) return nil;
    NSData *head = [fh readDataOfLength:kHeadRead];
    unsigned long long size = [fh seekToEndOfFile];
    [fh seekToFileOffset:size > kTailRead ? size - kTailRead : 0];
    NSData *tail = [fh readDataToEndOfFile];
    NSString *title = NewestCustomTitle(tail, tail.length) ?: NewestTitle(tail, tail.length);
    if (!title && size > kTailRead) {
        [fh seekToFileOffset:size > kTailReadMore ? size - kTailReadMore : 0];
        NSData *more = [fh readDataToEndOfFile];
        title = NewestCustomTitle(more, more.length) ?: NewestTitle(more, more.length);
    }
    [fh closeFile];
    NSMutableDictionary *conversation = [@{@"id": conversationId} mutableCopy];
    NSString *folder = FolderIn(head);
    if (folder) conversation[@"folder"] = folder;
    if (title.length) conversation[@"title"] = title;
    double moved = LatestMessageAt(tail, tail.length);
    conversation[@"movedAt"] = @(moved > 0 ? moved : modified * 1000);
    // Only a note named for the session it holds is taken, as KeptSessions takes one.
    NSDictionary *kept = AsRecord(ReadJSON(KeptNotePath(conversationId)));
    NSString *ranIn = [kept[@"sessionId"] isEqual:conversationId] ? AsText(kept[@"terminal"]) : nil;
    if (ranIn.length) conversation[@"ranIn"] = ranIn;
    return conversation;
}

@interface Conversations ()
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *known;  // path -> {size, modified, conversation}
@end

@implementation Conversations

- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.known = [NSMutableDictionary dictionary];
    return self;
}

- (NSArray<NSDictionary *> *)all {
    @synchronized (self) {
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *projects = ClaudeDir(kClaudeCodeTranscripts);
        NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
        NSMutableSet<NSString *> *seen = [NSMutableSet set];
        for (NSString *project in [fm contentsOfDirectoryAtPath:projects error:nil]) {
            NSString *folder = [projects stringByAppendingPathComponent:project];
            struct stat place;
            BOOL linked = lstat(folder.fileSystemRepresentation, &place) == 0 && S_ISLNK(place.st_mode);
            for (NSString *file in [fm contentsOfDirectoryAtPath:folder error:nil]) {
                NSString *conversationId = file.stringByDeletingPathExtension;
                if (![file.pathExtension isEqualToString:@"jsonl"] || !IsConversationId(conversationId)) continue;
                NSString *path = [folder stringByAppendingPathComponent:file];
                struct stat info;
                if (lstat(path.fileSystemRepresentation, &info) != 0 || !S_ISREG(info.st_mode)) continue;
                double modified = info.st_mtimespec.tv_sec + info.st_mtimespec.tv_nsec / 1e9;
                NSDictionary *was = self.known[path];
                NSDictionary *conversation = was && [was[@"size"] longLongValue] == info.st_size
                    && [was[@"modified"] doubleValue] == modified ? was[@"conversation"] : nil;
                if (!conversation) {
                    conversation = Read(path, conversationId, modified);
                    if (!conversation) continue;
                    self.known[path] = @{@"size": @(info.st_size), @"modified": @(modified),
                                         @"conversation": conversation};
                }
                [seen addObject:path];
                if (linked) {
                    NSMutableDictionary *kept = [conversation mutableCopy];
                    kept[@"linked"] = @YES;
                    conversation = kept;
                }
                [out addObject:conversation];
            }
        }
        for (NSString *path in self.known.allKeys)
            if (![seen containsObject:path]) [self.known removeObjectForKey:path];
        [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            double x = [a[@"movedAt"] doubleValue], y = [b[@"movedAt"] doubleValue];
            return x > y ? NSOrderedAscending : x < y ? NSOrderedDescending : [a[@"id"] compare:b[@"id"]];
        }];
        return out;
    }
}

@end

NSArray<NSString *> *ConversationFiles(NSString *conversationId) {
    if (!IsConversationId(conversationId)) return @[];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    NSString *projects = ClaudeDir(kClaudeCodeTranscripts);
    for (NSString *project in [fm contentsOfDirectoryAtPath:projects error:nil]) {
        NSString *folder = [projects stringByAppendingPathComponent:project];
        NSString *transcript = [folder
            stringByAppendingPathComponent:[conversationId stringByAppendingPathExtension:@"jsonl"]];
        if (![fm fileExistsAtPath:transcript]) continue;
        [files addObject:transcript];
        NSString *beside = [folder stringByAppendingPathComponent:conversationId];
        if ([fm fileExistsAtPath:beside]) [files addObject:beside];
    }
    for (NSString *path in @[[ClaudeDir(kClaudeCodeEditCopies) stringByAppendingPathComponent:conversationId],
                             HookNotePath(conversationId), KeptNotePath(conversationId)])
        if ([fm fileExistsAtPath:path]) [files addObject:path];
    return files;
}

// A path with the folders above it resolved and its last part as it is; nil when they can't be.
static NSString *ResolvedAbove(NSString *path) {
    char *real = realpath(path.stringByDeletingLastPathComponent.fileSystemRepresentation, NULL);
    if (!real) return nil;
    NSString *folder = [NSFileManager.defaultManager stringWithFileSystemRepresentation:real length:strlen(real)];
    free(real);
    return [folder stringByAppendingPathComponent:path.lastPathComponent];
}

// Only the folders the files are kept in are resolved (Claude Code's folder kept somewhere else through a link is still
// its own), and nothing under them, so a project folder that's a link to somewhere else isn't taken for one. Whether
// the file is there isn't asked: the folder beside a transcript is still its conversation's once the transcript has
// gone to the Trash.
BOOL IsConversationPlace(NSString *path) {
    NSString *name = path.lastPathComponent, *conversationId = name;
    if ([@[@"jsonl", @"json"] containsObject:name.pathExtension]) conversationId = name.stringByDeletingPathExtension;
    NSString *resolved = ResolvedAbove(path);
    if (!resolved || !IsConversationId(conversationId)) return NO;
    // Where it would be in its own folder, that folder resolved.
    NSString *(^in)(NSString *) = ^NSString *(NSString *place) {
        NSString *folder = RealPath(place.stringByDeletingLastPathComponent);
        return [folder stringByAppendingPathComponent:place.lastPathComponent];
    };
    NSString *project = [RealPath(ClaudeDir(kClaudeCodeTranscripts))
                         stringByAppendingPathComponent:path.stringByDeletingLastPathComponent.lastPathComponent];
    NSArray<NSString *> *places = @[
        [project stringByAppendingPathComponent:[conversationId stringByAppendingPathExtension:@"jsonl"]],
        [project stringByAppendingPathComponent:conversationId],
        in([ClaudeDir(kClaudeCodeEditCopies) stringByAppendingPathComponent:conversationId]),
        in(HookNotePath(conversationId)), in(KeptNotePath(conversationId))];
    return [places containsObject:resolved];
}
