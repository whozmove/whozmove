// DesktopLog: following Claude Desktop's log.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "DesktopLog.h"
#import "ClaudeDesktopFacts.h"
#import "Files.h"

@interface DesktopLog ()
@property (assign) unsigned long long focusLogOffset;  // how far the log has been read
@property (copy) NSString *loggedFocusId;
@property (assign) double loggedFocusAt, loggedStartAt;
@property (copy) NSArray<NSDictionary *> *loggedStarts;
@property (assign) double startPendingAt;  // when a new conversation's start was logged, while the line saying which
                                           // is still to come (0: none)
@end

@implementation DesktopLog

// The session list (on its queue) and the rest (on the main thread) both catch up with the log, so they take turns, and
// each starts where the other left off.
- (void)catchUp {
    @synchronized (self) {
        [self catchUpWithLog];
    }
}

// Follows Claude Desktop's log for conversation switches ("setFocusedSession: sessionId=local_…", or
// "=null" when no conversation is showing) and new conversations ("LocalSessions.start:", then "Starting local session
// local_… in <folder>"), reading only what was appended since the last call.
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
        if (line.length < 19) continue;
        NSRange tag = [line rangeOfString:kClaudeDesktopFocusLine];
        BOOL start = tag.location == NSNotFound && [line containsString:kClaudeDesktopStartLine];
        NSRange session = tag.location == NSNotFound && !start ? [line rangeOfString:kClaudeDesktopSessionLine]
                                                               : NSMakeRange(NSNotFound, 0);
        if (tag.location == NSNotFound && !start && session.location == NSNotFound) continue;
        NSDate *at = [stamp dateFromString:[line substringToIndex:19]];
        if (!at) continue;
        if (start) {
            self.startPendingAt = at.timeIntervalSince1970 * 1000;
            continue;
        }
        if (session.location != NSNotFound) {
            // The line after a new conversation's start (in the same second, so far) says which it is, and where
            // Claude started it, which needn't be the folder it was asked for. Claude logs that line for one it
            // carries on as well, with no start.
            double pending = self.startPendingAt;
            self.startPendingAt = 0;
            if (!pending || at.timeIntervalSince1970 * 1000 - pending > 10000) continue;
            NSString *rest = [line substringFromIndex:NSMaxRange(session)];
            NSRange in = [rest rangeOfString:@" in "];
            if (in.location == NSNotFound || ![rest hasPrefix:kClaudeDesktopConversationPrefix]) continue;
            self.loggedStartAt = at.timeIntervalSince1970 * 1000;
            NSMutableArray *starts = [NSMutableArray arrayWithArray:self.loggedStarts ?: @[]];
            [starts addObject:@{@"id": [rest substringToIndex:in.location],
                                @"folder": [[rest substringFromIndex:NSMaxRange(in)]
                                            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet],
                                @"at": @(self.loggedStartAt)}];
            if (starts.count > 10) [starts removeObjectAtIndex:0];
            self.loggedStarts = starts;
            continue;
        }
        NSString *sid = [[line substringFromIndex:NSMaxRange(tag)] componentsSeparatedByString:@","].firstObject;
        sid = [sid stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        self.loggedFocusId = [sid hasPrefix:kClaudeDesktopConversationPrefix] ? sid : nil;
        self.loggedFocusAt = at.timeIntervalSince1970 * 1000;
    }
}

@end
