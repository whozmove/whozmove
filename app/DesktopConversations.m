// DesktopConversations: Claude Desktop's conversation files, and which one it shows now.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "DesktopConversations.h"
#import "Files.h"
#import "Upstream.h"

@interface DesktopConversations ()
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *cache;  // file -> {mtime, fields}
@property (assign) unsigned long long focusLogOffset;                       // how far the log has been read
@property (copy) NSString *loggedFocusId;
@property (assign) double loggedFocusAt;
@end

@implementation DesktopConversations

- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.cache = [NSMutableDictionary dictionary];
    return self;
}

// The session list (on its queue) and ClaudeDesktop (on the main thread) both catch up with the log, so they take
// turns, and each starts where the other left off.
- (void)readFocusLog {
    @synchronized (self) {
        [self catchUpWithLog];
    }
}

// Follows Claude Desktop's log for conversation switches ("setFocusedSession: sessionId=local_…", or
// "=null" when no conversation is showing), reading only what was appended since the last call.
- (void)catchUpWithLog {
    NSString *path = [Home() stringByAppendingPathComponent:kClaudeDesktopLog];
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!fh) return;
    unsigned long long size = [fh seekToEndOfFile];
    if (size < self.focusLogOffset) self.focusLogOffset = 0;  // the log was rotated
    BOOL midLine = NO;
    if (self.focusLogOffset == 0 && size > 512 * 1024) {  // the first read takes only the recent part
        self.focusLogOffset = size - 512 * 1024;
        midLine = YES;
    }
    [fh seekToFileOffset:self.focusLogOffset];
    NSData *chunk = [fh readDataToEndOfFile];
    [fh closeFile];
    // Starting partway through a line, perhaps partway through a character, so it skips to the next line or none
    // of it would decode.
    if (midLine) {
        NSRange first = [chunk rangeOfData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding] options:0
                                     range:NSMakeRange(0, chunk.length)];
        if (first.location == NSNotFound) return;
        self.focusLogOffset += NSMaxRange(first);
        chunk = [chunk subdataWithRange:NSMakeRange(NSMaxRange(first), chunk.length - NSMaxRange(first))];
    }
    NSRange lastNewline = [chunk rangeOfData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]
                                     options:NSDataSearchBackwards range:NSMakeRange(0, chunk.length)];
    if (lastNewline.location == NSNotFound) return;
    self.focusLogOffset += NSMaxRange(lastNewline);

    NSString *text = [[NSString alloc] initWithData:[chunk subdataWithRange:NSMakeRange(0, NSMaxRange(lastNewline))]
                                           encoding:NSUTF8StringEncoding];
    static NSDateFormatter *stamp;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        stamp = [NSDateFormatter new];
        stamp.dateFormat = kClaudeDesktopLogTimeFormat;  // the log's local time
        stamp.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    });
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSRange tag = [line rangeOfString:kClaudeDesktopFocusLine];
        if (tag.location == NSNotFound || line.length < 19) continue;
        NSDate *at = [stamp dateFromString:[line substringToIndex:19]];
        if (!at) continue;
        NSString *sid = [[line substringFromIndex:NSMaxRange(tag)] componentsSeparatedByString:@","].firstObject;
        sid = [sid stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        self.loggedFocusId = [sid hasPrefix:kClaudeDesktopConversationPrefix] ? sid : nil;
        self.loggedFocusAt = at.timeIntervalSince1970 * 1000;
    }
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
                    // Claude's own verdict on its last turn, kept only while it's about the latest reply, so an
                    // old "blocked" doesn't outlive the answer that unblocked it.
                    NSDictionary *summary = c[@"postTurnSummary"];
                    BOOL current = [c[@"postTurnSummaryFor"] isKindOfClass:NSString.class]
                                && [c[@"postTurnSummaryFor"] isEqual:c[@"lastAssistantUuid"]];
                    if (current && [summary isKindOfClass:NSDictionary.class]
                        && [summary[@"status_category"] isKindOfClass:NSString.class])
                        fields[@"summaryStatus"] = summary[@"status_category"];
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
