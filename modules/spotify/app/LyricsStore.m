// LyricsStore: what LRCLIB found about the songs played, kept on this Mac, so a song played again has its lyrics at once
// without asking LRCLIB.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// One file a song, in the folder it's given (Whozmove's own, which only you can read), named for its track. It keeps the
// last 1,000 songs: each time one is read or kept, it counts as just played, and once there are more, the ones played
// longest ago go. Lyrics.m decides what counts, and for how long. Its files are read and written on a queue of its own,
// never on the main thread.
#import "LyricsStore.h"
#import <CommonCrypto/CommonDigest.h>
#import "Files.h"

// How many songs are kept, and the most of a file read back (bytes): Lyrics.m keeps a song's lyrics far smaller.
static const NSUInteger kMostKept = 1000, kMostFile = 1024 * 1024;

NSString *LyricsKeptName(NSString *track) {
    NSData *bytes = [track dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(bytes.bytes, (CC_LONG)bytes.length, digest);
    NSMutableString *name = [NSMutableString string];
    for (int i = 0; i < 16; i++) [name appendFormat:@"%02x", digest[i]];
    return [name stringByAppendingPathExtension:@"json"];
}

// Once more songs are kept than kMostKept, the ones read or kept longest ago go.
static void KeepOnlyTheLast(NSString *folder) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSMutableArray<NSURL *> *kept = [NSMutableArray array];
    for (NSURL *file in [files contentsOfDirectoryAtURL:[NSURL fileURLWithPath:folder isDirectory:YES]
                             includingPropertiesForKeys:@[NSURLContentModificationDateKey]
                                                options:NSDirectoryEnumerationSkipsHiddenFiles error:nil])
        if ([file.pathExtension isEqual:@"json"]) [kept addObject:file];
    if (kept.count <= kMostKept) return;
    NSDate *(^when)(NSURL *) = ^NSDate *(NSURL *file) {
        NSDate *date = nil;
        [file getResourceValue:&date forKey:NSURLContentModificationDateKey error:nil];
        return date ?: NSDate.distantPast;
    };
    [kept sortUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) { return [when(a) compare:when(b)]; }];
    for (NSUInteger i = 0; i < kept.count - kMostKept; i++) [files removeItemAtURL:kept[i] error:nil];
}

@interface LyricsStore ()
@property (copy) NSString *folder;
@property (strong) dispatch_queue_t queue;
@end

@implementation LyricsStore

- (instancetype)initWithFolder:(NSString *)folder {
    if (!(self = [super init])) return nil;
    self.folder = folder;
    self.queue = dispatch_queue_create("whozmove.lyrics", DISPATCH_QUEUE_SERIAL);
    return self;
}

- (void)read:(NSString *)track then:(void (^)(NSDictionary *kept))then {
    NSString *path = [self.folder stringByAppendingPathComponent:LyricsKeptName(track)];
    dispatch_async(self.queue, ^{
        NSDictionary *kept = nil;
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (data.length && data.length <= kMostFile)
            kept = AsRecord([NSJSONSerialization JSONObjectWithData:data options:0 error:nil]);
        // Read again, it counts as just played, so it's kept longer than songs that haven't been.
        if (kept)
            [NSFileManager.defaultManager setAttributes:@{NSFileModificationDate: NSDate.date} ofItemAtPath:path
                                                  error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{ then(kept); });
    });
}

- (void)keep:(NSDictionary *)found {
    NSString *track = AsText(found[@"track"]);
    if (!track) return;
    NSMutableDictionary *record = [found mutableCopy];
    record[@"keptAt"] = @(round(NSDate.date.timeIntervalSince1970 * 1000));
    NSData *json = [NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingSortedKeys error:nil];
    NSString *folder = self.folder;
    dispatch_async(self.queue, ^{
        NSFileManager *files = NSFileManager.defaultManager;
        [files createDirectoryAtPath:folder withIntermediateDirectories:YES
                          attributes:@{NSFilePosixPermissions: @0700} error:nil];
        NSString *path = [folder stringByAppendingPathComponent:LyricsKeptName(track)];
        if (![json writeToFile:path options:NSDataWritingAtomic error:nil]) return;
        [files setAttributes:@{NSFilePosixPermissions: @0600} ofItemAtPath:path error:nil];
        KeepOnlyTheLast(folder);
    });
}

- (void)forgetAll {
    NSString *folder = self.folder;
    dispatch_async(self.queue, ^{ [NSFileManager.defaultManager removeItemAtPath:folder error:nil]; });
}

@end
