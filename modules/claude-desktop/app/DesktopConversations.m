// DesktopConversations: Claude Desktop's conversation files.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "DesktopConversations.h"
#import "ClaudeDesktopFacts.h"
#import "Files.h"

@interface DesktopConversations ()
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *cache;  // file -> {mtime, fields}
@end

@implementation DesktopConversations

- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.cache = [NSMutableDictionary dictionary];
    return self;
}

// Claude Desktop keeps one file per conversation, running or not:
// ~/Library/Application Support/Claude/claude-code-sessions/<account>/<org>/local_<id>.json.
// Files run to a few hundred KB, so each is parsed only when its modification date changes.
- (NSArray<NSDictionary *> *)all {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *root = [Home() stringByAppendingPathComponent:kClaudeDesktopConversations];
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *present = [NSMutableSet set];
    for (NSString *account in [fm contentsOfDirectoryAtPath:root error:nil]) {
        NSString *accountDir = [root stringByAppendingPathComponent:account];
        for (NSString *org in [fm contentsOfDirectoryAtPath:accountDir error:nil]) {
            NSString *orgDir = [accountDir stringByAppendingPathComponent:org];
            for (NSString *file in [fm contentsOfDirectoryAtPath:orgDir error:nil]) {
                if (![file hasPrefix:kClaudeDesktopConversationPrefix] || ![file.pathExtension isEqualToString:@"json"])
                    continue;
                NSString *path = [orgDir stringByAppendingPathComponent:file];
                NSDate *mtime = [fm attributesOfItemAtPath:path error:nil].fileModificationDate;
                NSDictionary *cached = self.cache[path];
                if (!cached || ![cached[@"mtime"] isEqual:mtime]) {
                    NSDictionary *c = ReadJSON(path);
                    if (![c isKindOfClass:NSDictionary.class]) continue;
                    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
                    for (NSString *key in @[@"sessionId", @"cliSessionId", @"title", @"cwd", @"originCwd",
                                            @"isArchived", @"lastActivityAt", @"lastFocusedAt", @"permissionMode",
                                            @"model", @"effort"])
                        if (c[key] && c[key] != NSNull.null) fields[key] = c[key];
                    fields[@"savedAt"] = @(mtime.timeIntervalSince1970 * 1000);  // when Claude last wrote it
                    cached = @{@"mtime": mtime ?: NSDate.distantPast, @"fields": fields};
                    self.cache[path] = cached;
                }
                [present addObject:path];
                [out addObject:cached[@"fields"]];
            }
        }
    }
    for (NSString *path in self.cache.allKeys)
        if (![present containsObject:path]) [self.cache removeObjectForKey:path];
    return out;
}

@end
