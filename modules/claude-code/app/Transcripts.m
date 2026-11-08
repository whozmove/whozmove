// Transcripts: what's new in a session's transcript, read a little at a time.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Transcripts.h"
#import "Writings.h"
#import "Edits.h"
#import "KeptSessions.h"
#import "Files.h"
#import "Text.h"
#import "Log.h"
#import "ClaudeCodeFacts.h"
#import <sys/stat.h>
#import <fcntl.h>

// ~/.claude/projects/<encoded cwd>/<sessionId>.jsonl, found by id so the cwd encoding doesn't matter.
static NSString *TranscriptPath(NSString *sessionId) {
    if (!sessionId.length) return nil;
    NSString *projects = ClaudeDir(kClaudeCodeTranscripts);
    NSString *file = [sessionId stringByAppendingPathExtension:@"jsonl"];
    for (NSString *dir in [NSFileManager.defaultManager contentsOfDirectoryAtPath:projects error:nil]) {
        NSString *path = [[projects stringByAppendingPathComponent:dir] stringByAppendingPathComponent:file];
        if ([NSFileManager.defaultManager fileExistsAtPath:path]) return path;
    }
    return nil;
}

// The newest record in a chunk of transcript up to `end` that has `field`, as that field's text, or nil.
static NSString *NewestField(NSData *chunk, NSUInteger end, NSString *field) {
    NSData *key = [[NSString stringWithFormat:@"\"%@\"", field] dataUsingEncoding:NSUTF8StringEncoding];
    NSRange hit = [chunk rangeOfData:key options:NSDataSearchBackwards range:NSMakeRange(0, end)];
    if (hit.location == NSNotFound) return nil;
    NSDictionary *entry = JSONLineAt(chunk, hit.location, end, NULL);
    id value = [entry isKindOfClass:NSDictionary.class] ? entry[field] : nil;
    return [value isKindOfClass:NSString.class] ? value : nil;
}

NSString *NewestTitle(NSData *chunk, NSUInteger end) {
    return NewestField(chunk, end, kClaudeCodeAITitle);
}

NSString *NewestCustomTitle(NSData *chunk, NSUInteger end) {
    return NewestField(chunk, end, kClaudeCodeCustomTitle);
}

// The newest "aiTitle" record written after `from`, looking back 4 MB at most.
static NSString *TitleSince(NSString *path, unsigned long long from) {
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!fh) return nil;
    unsigned long long size = [fh seekToEndOfFile];
    if (size < from) from = 0;  // rewritten or truncated
    [fh seekToFileOffset:MAX(from, size > 4000000 ? size - 4000000 : 0)];
    NSData *tail = [fh readDataToEndOfFile];
    [fh closeFile];
    return NewestTitle(tail, tail.length);
}

// The newest reply of the main conversation in a chunk of transcript, as {tokens, model, effort, at}. `tokens` is what
// Claude Code counts as context in use: input, cache creation and cache read. `effort` is the one the reply was made
// with, which Claude Code records on each reply's line (checked with 2.1.302), and the only record of a terminal
// session's effort. A sub-agent's replies don't count, as it has a context of its own.
static NSDictionary *LatestUsage(NSData *chunk, NSUInteger end, NSUInteger *at) {
    NSData *marker = [@"\"cache_read_input_tokens\"" dataUsingEncoding:NSUTF8StringEncoding];
    for (int tries = 0; end > 0 && tries < 50; tries++) {
        NSRange hit = [chunk rangeOfData:marker options:NSDataSearchBackwards range:NSMakeRange(0, end)];
        if (hit.location == NSNotFound) return nil;
        NSRange line;
        NSDictionary *entry = JSONLineAt(chunk, hit.location, end, &line);
        NSDictionary *message = [entry isKindOfClass:NSDictionary.class] ? entry[@"message"] : nil;
        NSDictionary *usage = [message isKindOfClass:NSDictionary.class] ? message[@"usage"] : nil;
        // An API error is recorded as a reply from the "<synthetic>" model, with no real usage.
        if ([entry[@"type"] isEqual:@"assistant"] && ![entry[@"isSidechain"] boolValue]
            && [usage isKindOfClass:NSDictionary.class] && ![message[@"model"] isEqual:@"<synthetic>"]) {
            *at = line.location;
            long long tokens = [usage[@"input_tokens"] longLongValue]
                             + [usage[@"cache_creation_input_tokens"] longLongValue]
                             + [usage[@"cache_read_input_tokens"] longLongValue];
            return @{@"tokens": @(tokens),
                     @"model": [message[@"model"] isKindOfClass:NSString.class] ? message[@"model"] : @"",
                     @"effort": [entry[@"effort"] isKindOfClass:NSString.class] ? entry[@"effort"] : @"",
                     @"at": [entry[@"timestamp"] isKindOfClass:NSString.class] ? entry[@"timestamp"] : @""};
        }
        end = line.location;
    }
    return nil;
}

// When the conversation last moved: the newest message in a chunk of transcript, yours or Claude's (tool calls
// and results count), in ms since 1970, or 0 if there's none. Slash commands (/model, /effort, …) leave records
// too, but changing a session's settings isn't activity, so they don't count, and nor does the summary a compaction
// leaves.
double LatestMessageAt(NSData *chunk, NSUInteger end) {
    NSData *newline = [@"\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *user = [@"\"type\":\"user\"" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *assistant = [@"\"type\":\"assistant\"" dataUsingEncoding:NSUTF8StringEncoding];
    NSUInteger cursor = end;  // just past a newline
    for (int lines = 0; cursor > 0 && lines < 400; lines++) {
        NSUInteger lineEnd = ((const char *)chunk.bytes)[cursor - 1] == '\n' ? cursor - 1 : cursor;
        NSRange previous = lineEnd > 0
            ? [chunk rangeOfData:newline options:NSDataSearchBackwards range:NSMakeRange(0, lineEnd)]
            : NSMakeRange(NSNotFound, 0);
        NSUInteger start = previous.location == NSNotFound ? 0 : NSMaxRange(previous);
        cursor = start;
        NSRange line = NSMakeRange(start, lineEnd - start);
        if ([chunk rangeOfData:user options:0 range:line].location == NSNotFound
            && [chunk rangeOfData:assistant options:0 range:line].location == NSNotFound) continue;
        NSDictionary *entry = [NSJSONSerialization JSONObjectWithData:[chunk subdataWithRange:line]
                                                              options:0 error:nil];
        if (![entry isKindOfClass:NSDictionary.class]
            || !([entry[@"type"] isEqual:@"user"] || [entry[@"type"] isEqual:@"assistant"])) continue;
        if ([entry[@"isSidechain"] boolValue] || [entry[@"isMeta"] boolValue]) continue;
        // The summary a compaction leaves is written as your message, but you sent nothing: the conversation didn't
        // move, so its row doesn't go to the top.
        if ([entry[@"isCompactSummary"] boolValue]) continue;
        id message = entry[@"message"];
        id content = [message isKindOfClass:NSDictionary.class] ? message[@"content"] : nil;
        if ([content isKindOfClass:NSString.class]
            && ([content hasPrefix:@"<command-name>"] || [content hasPrefix:@"<local-command-"])) continue;
        double at = TimestampMs(entry[@"timestamp"]);
        if (at > 0) return at;
    }
    return 0;
}

// The newest permission mode recorded in a chunk of transcript up to `end` (every prompt records the mode it was sent
// in, and a session records its mode when it starts), or nil; `at` is that record's time in ms since 1970 (0 for none).
static NSString *NewestMode(NSData *chunk, NSUInteger end, double *at) {
    NSData *modeKey = [@"\"permissionMode\":\"" dataUsingEncoding:NSUTF8StringEncoding];
    NSRange key = [chunk rangeOfData:modeKey options:NSDataSearchBackwards range:NSMakeRange(0, end)];
    if (key.location == NSNotFound) return nil;
    NSRange quote = [chunk rangeOfData:[@"\"" dataUsingEncoding:NSUTF8StringEncoding] options:0
                                 range:NSMakeRange(NSMaxRange(key), MIN(32, end - NSMaxRange(key)))];
    NSString *mode = quote.location == NSNotFound ? nil
        : [[NSString alloc] initWithData:[chunk subdataWithRange:NSMakeRange(NSMaxRange(key),
                                                                             quote.location - NSMaxRange(key))]
                                encoding:NSUTF8StringEncoding];
    NSDictionary *entry = JSONLineAt(chunk, key.location, end, NULL);
    *at = [entry isKindOfClass:NSDictionary.class] ? TimestampMs(entry[@"timestamp"]) : 0;
    return mode;
}

const NSUInteger kMostReply = 16 * 1024;
// How much of a transcript's end a reply is looked for in: a turn's lines, its tool results included, fit many times.
static const unsigned long long kReplyRead = 8 * 1024 * 1024;

// What a message line says in words: its text, or its text parts joined; nil for one with none (a tool's result, a
// tool call, thinking).
static NSString *WordsOf(NSDictionary *entry) {
    id message = entry[@"message"];
    id content = [message isKindOfClass:NSDictionary.class] ? message[@"content"] : nil;
    if ([content isKindOfClass:NSString.class]) return content;
    if (![content isKindOfClass:NSArray.class]) return nil;
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (id part in content) {
        if (![part isKindOfClass:NSDictionary.class]) continue;
        if ([part[@"type"] isEqual:@"tool_result"]) return nil;
        if ([part[@"type"] isEqual:@"text"] && [part[@"text"] isKindOfClass:NSString.class])
            [parts addObject:part[@"text"]];
    }
    return parts.count ? [parts componentsJoinedByString:@"\n\n"] : nil;
}

NSString *ReplyAfter(NSData *chunk, BOOL whole, NSString *prompt, double since) {
    NSCharacterSet *spaces = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    NSString *asked = [prompt stringByTrimmingCharactersInSet:spaces];
    if (!chunk.length || !asked.length) return nil;
    NSData *newline = [@"\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *user = [@"\"type\":\"user\"" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *assistant = [@"\"type\":\"assistant\"" dataUsingEncoding:NSUTF8StringEncoding];
    NSUInteger cursor = 0, end = chunk.length;
    if (!whole) {
        NSRange first = [chunk rangeOfData:newline options:0 range:NSMakeRange(0, end)];
        if (first.location == NSNotFound) return nil;
        cursor = NSMaxRange(first);
    }
    BOOL found = NO;
    NSString *reply = nil, *replyId = nil;
    while (cursor < end) {
        NSRange next = [chunk rangeOfData:newline options:0 range:NSMakeRange(cursor, end - cursor)];
        NSRange line = NSMakeRange(cursor, (next.location == NSNotFound ? end : next.location) - cursor);
        cursor = NSMaxRange(line) + 1;
        BOOL yours = [chunk rangeOfData:user options:0 range:line].location != NSNotFound;
        if (!yours && (!found || [chunk rangeOfData:assistant options:0 range:line].location == NSNotFound)) continue;
        NSDictionary *entry = [NSJSONSerialization JSONObjectWithData:[chunk subdataWithRange:line] options:0
                                                                error:nil];
        if (![entry isKindOfClass:NSDictionary.class] || [entry[@"isSidechain"] boolValue]
            || [entry[@"isMeta"] boolValue] || [entry[@"isCompactSummary"] boolValue])
            continue;
        NSString *words = WordsOf(entry);
        if ([entry[@"type"] isEqual:@"user"]) {
            if (!words) continue;  // a tool's result: the turn goes on
            if (TimestampMs(entry[@"timestamp"]) >= since
                && [[words stringByTrimmingCharactersInSet:spaces] isEqualToString:asked]) {
                found = YES;
                reply = replyId = nil;
            } else if (found && ![words hasPrefix:@"<command-name>"] && ![words hasPrefix:@"<local-command-"]) {
                found = NO;  // the next prompt you sent, not a slash command's record: that turn has ended
            }
        } else if ([entry[@"type"] isEqual:@"assistant"] && words.length) {
            // Claude Code writes each part of a reply as a line of its own, so parts of the same reply are joined.
            id message = entry[@"message"];
            NSString *messageId = [message isKindOfClass:NSDictionary.class] ? AsText(message[@"id"]) : nil;
            reply = reply && messageId && [messageId isEqual:replyId]
                ? [NSString stringWithFormat:@"%@\n\n%@", reply, words] : words;
            replyId = messageId;
        }
    }
    reply = [reply stringByTrimmingCharactersInSet:spaces];
    if (reply.length > kMostReply) {
        NSRange cut = [reply rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, kMostReply - 1)];
        reply = [[reply substringWithRange:cut] stringByAppendingString:@"…"];
    }
    return reply.length ? reply : nil;
}

NSDictionary *AfterHandedWords(NSData *chunk, BOOL whole, NSString *words, double since) {
    NSCharacterSet *spaces = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    if (!chunk.length || ![words isKindOfClass:NSString.class] || !words.length) return nil;
    NSData *newline = [@"\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *added = [@"\"type\":\"hook_additional_context\"" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *user = [@"\"type\":\"user\"" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *assistant = [@"\"type\":\"assistant\"" dataUsingEncoding:NSUTF8StringEncoding];
    NSUInteger cursor = 0, end = chunk.length;
    if (!whole) {
        NSRange first = [chunk rangeOfData:newline options:0 range:NSMakeRange(0, end)];
        if (first.location == NSNotFound) return nil;
        cursor = NSMaxRange(first);
    }
    double at = 0;
    NSString *how = nil, *reply = nil;
    BOOL ended = NO;
    while (cursor < end) {
        NSRange next = [chunk rangeOfData:newline options:0 range:NSMakeRange(cursor, end - cursor)];
        NSRange line = NSMakeRange(cursor, (next.location == NSNotFound ? end : next.location) - cursor);
        cursor = NSMaxRange(line) + 1;
        BOOL hook = !at && [chunk rangeOfData:added options:0 range:line].location != NSNotFound;
        BOOL talk = at && ([chunk rangeOfData:user options:0 range:line].location != NSNotFound
                           || [chunk rangeOfData:assistant options:0 range:line].location != NSNotFound);
        if (!hook && !talk) continue;
        NSDictionary *entry = [NSJSONSerialization JSONObjectWithData:[chunk subdataWithRange:line] options:0
                                                                error:nil];
        if (![entry isKindOfClass:NSDictionary.class] || [entry[@"isSidechain"] boolValue]) continue;
        if (hook) {
            // The hook's words, as Claude Code keeps what it added: each of its additional contexts whole.
            NSDictionary *attachment = AsRecord(entry[@"attachment"]);
            BOOL ours = NO;
            for (id part in AsList(attachment[@"content"])) ours = ours || [AsText(part) containsString:words];
            if (!ours || TimestampMs(entry[@"timestamp"]) < since) continue;
            at = TimestampMs(entry[@"timestamp"]);
            how = AsText(attachment[@"hookEvent"]) ?: @"";
            continue;
        }
        if ([entry[@"isMeta"] boolValue] || [entry[@"isCompactSummary"] boolValue]) continue;
        NSString *said = WordsOf(entry);
        if ([entry[@"type"] isEqual:@"user"]) {
            // A prompt you sent, not a tool's result nor a slash command's record: the turn they went into has ended.
            if (said && ![said hasPrefix:@"<command-name>"] && ![said hasPrefix:@"<local-command-"]) {
                ended = YES;
                break;
            }
        } else if (said.length) {
            // Claude Code writes each part of a reply as a line of its own: each, after the words, is kept, in order.
            reply = !reply ? said : [NSString stringWithFormat:@"%@\n\n%@", reply, said];
        }
    }
    if (!at) return nil;
    reply = [reply stringByTrimmingCharactersInSet:spaces];
    if (reply.length > kMostReply) {
        NSRange cut = [reply rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, kMostReply - 1)];
        reply = [[reply substringWithRange:cut] stringByAppendingString:@"…"];
    }
    NSMutableDictionary *found = [@{@"at": @(at), @"how": how, @"turnEnded": @(ended)} mutableCopy];
    if (reply.length) found[@"reply"] = reply;
    return found;
}

double StartOfToday(void) {
    return [NSCalendar.currentCalendar startOfDayForDate:[NSDate date]].timeIntervalSince1970 * 1000;
}

NSDictionary *SpentAdd(NSDictionary *was, NSData *chunk, NSUInteger end, BOOL fromStart, double today) {
    BOOL sameDay = !fromStart && [was[@"day"] doubleValue] == today;
    long long tokens = sameDay ? [was[@"tokens"] longLongValue] : 0;
    // A reply going on from the read before, or from before midnight, adds only what it grew by.
    NSString *lastId = fromStart ? nil : was[@"lastId"];
    long long lastTokens = fromStart ? 0 : [was[@"lastTokens"] longLongValue];
    NSData *marker = [@"\"cache_read_input_tokens\"" dataUsingEncoding:NSUTF8StringEncoding];
    NSUInteger cursor = 0;
    while (cursor < end) {
        NSRange hit = [chunk rangeOfData:marker options:0 range:NSMakeRange(cursor, end - cursor)];
        if (hit.location == NSNotFound) break;
        NSRange line;
        NSDictionary *entry = JSONLineAt(chunk, hit.location, end, &line);
        cursor = MAX(NSMaxRange(line) + 1, NSMaxRange(hit));
        NSDictionary *message = [entry isKindOfClass:NSDictionary.class] ? entry[@"message"] : nil;
        NSDictionary *usage = [message isKindOfClass:NSDictionary.class] ? message[@"usage"] : nil;
        NSString *replyId = [message isKindOfClass:NSDictionary.class] ? message[@"id"] : nil;
        // An API error is recorded as a reply from the "<synthetic>" model, with no real usage.
        if (![entry[@"type"] isEqual:@"assistant"] || ![usage isKindOfClass:NSDictionary.class]
            || ![replyId isKindOfClass:NSString.class] || [message[@"model"] isEqual:@"<synthetic>"]) continue;
        long long used = [usage[@"input_tokens"] longLongValue] + [usage[@"cache_creation_input_tokens"] longLongValue]
                       + [usage[@"cache_read_input_tokens"] longLongValue] + [usage[@"output_tokens"] longLongValue];
        if (![replyId isEqualToString:lastId ?: @""]) {
            lastId = replyId;
            lastTokens = 0;
        }
        if (TimestampMs(entry[@"timestamp"]) >= today) tokens += MAX(0, used - lastTokens);
        lastTokens = MAX(lastTokens, used);
    }
    return @{@"day": @(today), @"tokens": @(tokens), @"lastId": lastId ?: @"", @"lastTokens": @(lastTokens)};
}

long long SpentToday(NSDictionary *spent, double today) {
    long long tokens = 0;
    NSMutableArray *files = [NSMutableArray arrayWithObjects:spent[@"main"], nil];
    [files addObjectsFromArray:[spent[@"subs"] allValues] ?: @[]];
    for (NSDictionary *file in files)
        if ([file[@"day"] doubleValue] == today) tokens += [file[@"tokens"] longLongValue];
    return tokens;
}

// What ReadTranscriptNews found in the part of a transcript it hadn't read yet.
@interface TranscriptNews : NSObject
@property (copy) NSArray<NSDictionary *> *prLinks;  // {url, number, repo, at}, oldest first
@property (copy) NSDictionary *usage;                // {tokens, model, at}, or {tokens, compacted} after a compaction
@property (copy) NSString *mode;                     // the newest permission mode recorded
@property (assign) double modeAt;                    // the time of that record, in ms since 1970
@property (assign) double messageAt;                 // when the newest message was written, in ms since 1970
@property (copy) NSString *title;                    // the newest topic recorded
@property (copy) NSDictionary *writings;             // plans, prototypes and notes, as WritingNews found them
@property (copy) NSArray<NSDictionary *> *edits;      // the files changed and how, as EditNews found them
@property (copy) NSDictionary *shells;                // the shell commands run, as ShellNews found them
@property (copy) NSDictionary *spent;                 // what its replies used today, as SpentAdd keeps it
@end

@implementation TranscriptNews
@end

// The commands known to run git: those before, and those in this part.
static NSSet<NSString *> *GitCalls(NSSet *before, NSDictionary *shells) {
    return [(before ?: [NSSet set]) setByAddingObjectsFromArray:shells[@"git"] ?: @[]];
}

// The file a handle has open, by its inode: the same file however it's named, and another once it's replaced.
static unsigned long long InodeOf(NSFileHandle *fh) {
    struct stat info;
    return fstat(fh.fileDescriptor, &info) == 0 ? info.st_ino : 0;
}

// Reads a transcript from `offset` up to its last complete line, and moves `offset` past what it read, so each
// call reads only what's new; `inode` is the file read. The PR links are the "pr-link" records Claude Code writes when
// a session makes or works on a PR. Every prompt records the mode it was sent in, and a session records its mode when
// it starts. `waiting` are the calls whose results the session's writings still wait for (see Writings.h);
// `shellsSoFar` the session's transcript state, for where ShellNews left off.
static TranscriptNews *ReadTranscriptNews(NSString *path, unsigned long long *offset, unsigned long long *inode,
                                          NSSet *waiting, NSDictionary *shellsSoFar, NSDictionary *spentSoFar,
                                          double today) {
    TranscriptNews *news = [TranscriptNews new];
    news.prLinks = @[];
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!fh) return news;
    *inode = InodeOf(fh);
    unsigned long long size = [fh seekToEndOfFile];
    if (size < *offset) *offset = 0;  // rewritten or truncated
    if (size == *offset) { [fh closeFile]; return news; }
    unsigned long long base = *offset;
    [fh seekToFileOffset:*offset];
    NSData *chunk = [fh readDataToEndOfFile];
    [fh closeFile];
    NSData *newline = [@"\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSRange lastNewline = [chunk rangeOfData:newline options:NSDataSearchBackwards range:NSMakeRange(0, chunk.length)];
    if (lastNewline.location == NSNotFound) return news;
    *offset += NSMaxRange(lastNewline);
    NSUInteger usageAt = 0;
    NSDictionary *usage = LatestUsage(chunk, NSMaxRange(lastNewline), &usageAt);
    // A compaction after the newest reply ("Conversation compacted") leaves the context at the size it records,
    // until the next reply says otherwise.
    NSRange boundary = [chunk rangeOfData:[@"\"compact_boundary\"" dataUsingEncoding:NSUTF8StringEncoding]
                                  options:NSDataSearchBackwards range:NSMakeRange(0, NSMaxRange(lastNewline))];
    if (boundary.location != NSNotFound && (!usage || boundary.location > usageAt)) {
        NSDictionary *entry = JSONLineAt(chunk, boundary.location, NSMaxRange(lastNewline), NULL);
        id tokens = [entry isKindOfClass:NSDictionary.class]
            && [entry[@"compactMetadata"] isKindOfClass:NSDictionary.class]
            ? entry[@"compactMetadata"][@"postTokens"] : nil;
        if ([tokens isKindOfClass:NSNumber.class]) {
            // The reply's model and time stay, when the reply was in this read.
            NSMutableDictionary *compacted = [usage mutableCopy] ?: [NSMutableDictionary dictionary];
            compacted[@"tokens"] = tokens;
            compacted[@"compacted"] = @YES;
            usage = compacted;
        }
    }
    news.usage = usage;
    news.messageAt = LatestMessageAt(chunk, NSMaxRange(lastNewline));
    // Read again from its start (the first read, or the file rewritten): what it used is counted afresh.
    news.spent = SpentAdd(spentSoFar, chunk, NSMaxRange(lastNewline), base == 0, today);
    news.title = NewestTitle(chunk, NSMaxRange(lastNewline));
    double modeAt = 0;
    news.mode = NewestMode(chunk, NSMaxRange(lastNewline), &modeAt);
    news.modeAt = modeAt;

    NSData *marker = [@"\"pr-link\"" dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableArray *links = [NSMutableArray array];
    NSUInteger cursor = 0, end = NSMaxRange(lastNewline);
    while (cursor < end) {
        NSRange hit = [chunk rangeOfData:marker options:0 range:NSMakeRange(cursor, end - cursor)];
        if (hit.location == NSNotFound) break;
        NSRange line;
        NSDictionary *entry = JSONLineAt(chunk, hit.location, end, &line);
        if ([entry isKindOfClass:NSDictionary.class] && [entry[@"type"] isEqual:@"pr-link"]
            && [entry[@"prUrl"] hasPrefix:@"https://"])
            [links addObject:@{@"url": entry[@"prUrl"], @"number": entry[@"prNumber"] ?: @0,
                               @"repo": entry[@"prRepository"] ?: @"", @"at": entry[@"timestamp"] ?: @""}];
        cursor = NSMaxRange(line) + 1;  // past its newline
    }
    news.prLinks = links;
    news.writings = WritingNews(chunk, end, base, waiting);
    news.shells = ShellNews(chunk, end, shellsSoFar[@"shellMode"], shellsSoFar[@"shellBase"], shellsSoFar[@"gitCalls"]);
    news.edits = EditNews(chunk, end, GitCalls(shellsSoFar[@"gitCalls"], news.shells));
    return news;
}

// What a session's sub-agents edited since the last read: Claude Code keeps each sub-agent's record beside the
// session's transcript, in a folder named after it (<session>/subagents/, one file each), and their edits are the
// session's work, as are the shell commands they ran, added to `shells` (ShellNews, each sub-agent starting in the
// mode the session is in, `shellsSoFar` as ReadTranscriptNews takes it), as is what their replies used today (SpentAdd,
// in `spent`, by file name). `offsets` (file name -> where the last read of it ended), `inodes` (file name -> the file
// read) and `spent` move on as they're read.
static NSArray<NSDictionary *> *SubAgentEdits(NSString *path, NSMutableDictionary *offsets, NSMutableDictionary *inodes,
                                              NSDictionary *shellsSoFar, NSMutableArray *shells,
                                              NSMutableDictionary *spent, double today) {
    NSString *folder = [[path stringByDeletingPathExtension] stringByAppendingPathComponent:kClaudeCodeSubagents];
    NSData *newline = [@"\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableArray *edits = [NSMutableArray array];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil]) {
        if (![name.pathExtension isEqualToString:@"jsonl"]) continue;
        NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:[folder stringByAppendingPathComponent:name]];
        if (!fh) continue;
        inodes[name] = @(InodeOf(fh));
        unsigned long long size = [fh seekToEndOfFile], from = [offsets[name] unsignedLongLongValue];
        if (size < from) from = 0;  // rewritten or truncated
        if (size == from) { [fh closeFile]; continue; }
        [fh seekToFileOffset:from];
        NSData *chunk = [fh readDataToEndOfFile];
        [fh closeFile];
        NSRange last = [chunk rangeOfData:newline options:NSDataSearchBackwards range:NSMakeRange(0, chunk.length)];
        if (last.location == NSNotFound) continue;
        offsets[name] = @(from + NSMaxRange(last));
        NSMutableDictionary *news = [ShellNews(chunk, NSMaxRange(last), shellsSoFar[@"shellMode"],
                                               shellsSoFar[@"shellBase"], shellsSoFar[@"gitCalls"]) mutableCopy];
        // Where it leaves off is the sub-agent's, not the session's.
        [news removeObjectsForKeys:@[@"mode", @"base"]];
        [shells addObject:news];
        [edits addObjectsFromArray:EditNews(chunk, NSMaxRange(last), GitCalls(shellsSoFar[@"gitCalls"], news))];
        spent[name] = SpentAdd(spent[name], chunk, NSMaxRange(last), from == 0, today);
    }
    return edits;
}

// What a read starts from, out of a session's state: where the reads left off, and what they found that the next one
// needs. Taken on the main thread, or from a kept read on the queue.
static NSDictionary *ReadFrom(NSDictionary *t) {
    return @{@"offset": t[@"offset"] ?: @0, @"waiting": [NSSet setWithArray:[t[@"waiting"] allKeys] ?: @[]],
             @"subOffsets": [t[@"subOffsets"] copy] ?: @{}, @"subInodes": [t[@"subInodes"] copy] ?: @{},
             @"spent": [t[@"spent"] copy] ?: @{},
             @"shells": @{@"shellMode": t[@"shellMode"] ?: @"", @"shellBase": t[@"shellBase"] ?: @"",
                          @"gitCalls": [t[@"gitCalls"] set] ?: [NSSet set]}};
}

// What's new in a session's transcript and its sub-agents' records since `from` (ReadFrom's), read on the queue:
// {path, offset, inode, bytes (how many were read), news (a TranscriptNews), subEdits, shells (the session's and each
// sub-agent's ShellNews), subOffsets, subInodes, spent}.
static NSDictionary *ReadSession(NSString *path, NSDictionary *from, double today) {
    unsigned long long offset = [from[@"offset"] unsignedLongLongValue], inode = 0, before = offset;
    NSDictionary *shellsSoFar = from[@"shells"], *spentSoFar = from[@"spent"][@"main"];
    NSMutableDictionary *subOffsets = [from[@"subOffsets"] mutableCopy], *subInodes = [from[@"subInodes"] mutableCopy];
    NSMutableDictionary *subSpent = [from[@"spent"][@"subs"] mutableCopy] ?: [NSMutableDictionary dictionary];
    TranscriptNews *news = ReadTranscriptNews(path, &offset, &inode, from[@"waiting"], shellsSoFar, spentSoFar, today);
    NSMutableArray *shells = [NSMutableArray arrayWithObjects:news.shells, nil];
    // Sub-agents start in the mode the session's own record has just left off in.
    NSDictionary *sessionNow = @{@"shellMode": news.shells[@"mode"] ?: shellsSoFar[@"shellMode"],
                                 @"shellBase": news.shells[@"base"] ?: shellsSoFar[@"shellBase"],
                                 @"gitCalls": GitCalls(shellsSoFar[@"gitCalls"], news.shells)};
    NSArray *subEdits = SubAgentEdits(path, subOffsets, subInodes, sessionNow, shells, subSpent, today);
    unsigned long long bytes = offset >= before ? offset - before : offset;
    for (NSString *name in subOffsets) {
        unsigned long long now = [subOffsets[name] unsignedLongLongValue], was = [from[@"subOffsets"][name]
                                                                                  unsignedLongLongValue];
        bytes += now >= was ? now - was : now;
    }
    // What it used today: the transcript's own, kept only when this read found it, and its sub-agents'.
    return @{@"path": path, @"offset": @(offset), @"inode": @(inode), @"bytes": @(bytes), @"news": news,
             @"subEdits": subEdits, @"shells": shells, @"subOffsets": subOffsets, @"subInodes": subInodes,
             @"spent": @{@"main": news.spent ?: spentSoFar ?: @{}, @"subs": subSpent}};
}

// Adds what ReadSession found to a session's state, on the main thread.
static void AddSessionNews(NSString *sid, NSMutableDictionary *t, NSDictionary *read) {
    TranscriptNews *news = read[@"news"];
    t[@"path"] = read[@"path"];
    t[@"offset"] = read[@"offset"];
    t[@"inode"] = read[@"inode"];
    // Later entries carry the newer timestamp.
    for (NSDictionary *link in news.prLinks) t[@"prs"][link[@"url"]] = link;
    // After a compaction only the size changed: the model is still the one the last reply came from.
    NSDictionary *usage = news.usage;
    if (usage[@"compacted"]) {
        PanelLog(@"%@ -> compacted: %@ tokens in context now", sid, usage[@"tokens"]);
        NSMutableDictionary *kept = [t[@"usage"] mutableCopy] ?: [NSMutableDictionary dictionary];
        // The new size, and that reply's model if it was in this read.
        [kept addEntriesFromDictionary:usage];
        [kept removeObjectForKey:@"compacted"];
        t[@"usage"] = kept;
    } else if (usage) t[@"usage"] = usage;
    // Timed by its record, not by when it was read: an older record read now mustn't outrank a mode picked here since.
    if (news.mode.length) { t[@"mode"] = news.mode; t[@"modeAt"] = @(news.modeAt); }
    if (news.messageAt > [t[@"messageAt"] doubleValue]) t[@"messageAt"] = @(news.messageAt);
    if (news.title.length) t[@"title"] = news.title;
    if (news.writings) AddWritingNews(t, news.writings);
    AddEditNews(t, news.edits);
    AddEditNews(t, read[@"subEdits"]);
    for (NSDictionary *shell in read[@"shells"]) AddShellNews(t, shell);
    t[@"subOffsets"] = read[@"subOffsets"];
    t[@"subInodes"] = read[@"subInodes"];
    t[@"spent"] = read[@"spent"];
}

const NSInteger kReadsShape = 3;
// How many of a file's bytes, up to where it was read, make its mark: enough to tell it from another file, or from the
// same one written over.
static const NSUInteger kMarkBytes = 4096;

NSString *ReadsFolder(void) {
    return AppDir(@"reads");
}

// Where a sub-agent's record is, by its file's name: in the folder named for the session, beside its transcript.
static NSString *SubAgentFile(NSString *transcript, NSString *name) {
    return [[[transcript stringByDeletingPathExtension] stringByAppendingPathComponent:kClaudeCodeSubagents]
            stringByAppendingPathComponent:name];
}

// Bytes' mark: their FNV-1a hash, as 16 hex digits.
static NSString *MarkOf(const uint8_t *bytes, size_t length) {
    uint64_t hash = 14695981039346656037ULL;
    for (size_t i = 0; i < length; i++) hash = (hash ^ bytes[i]) * 1099511628211ULL;
    return [NSString stringWithFormat:@"%016llx", hash];
}

// A file as it is now, for a read that stopped at `offset`: {inode, size, and once it's that long, the mark of its last
// bytes before there}; nil when it isn't there.
static NSDictionary *FileNow(NSString *path, unsigned long long offset) {
    int fd = open(path.fileSystemRepresentation, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return nil;
    struct stat info;
    NSMutableDictionary *now = nil;
    if (fstat(fd, &info) == 0) {
        now = [@{@"inode": @(info.st_ino), @"size": @(info.st_size)} mutableCopy];
        size_t length = (size_t)MIN(offset, (unsigned long long)kMarkBytes);
        NSMutableData *bytes = [NSMutableData dataWithLength:length];
        if ((unsigned long long)info.st_size >= offset
            && pread(fd, bytes.mutableBytes, length, (off_t)(offset - length)) == (ssize_t)length)
            now[@"mark"] = MarkOf(bytes.bytes, length);
    }
    close(fd);
    return now;
}

NSDictionary *KeptReadFilesNow(NSDictionary *kept) {
    NSString *path = kept[@"path"];
    NSDictionary *files = kept[@"files"];
    NSMutableDictionary *now = [NSMutableDictionary dictionary], *subs = [NSMutableDictionary dictionary];
    now[@"main"] = FileNow(path, [files[@"main"][@"offset"] unsignedLongLongValue]) ?: @{};
    for (NSString *name in files[@"subs"])
        subs[name] = FileNow(SubAgentFile(path, name), [files[@"subs"][name][@"offset"] unsignedLongLongValue]) ?: @{};
    now[@"subs"] = subs;
    return now;
}

NSString *WhyNotGoOnFrom(NSDictionary *kept, NSDictionary *now, NSString *version) {
    if ([kept[@"shape"] integerValue] != kReadsShape) return @"it was kept in another shape";
    if (![kept[@"version"] isEqual:version]) return @"it was kept by another version of Whozmove";
    NSMutableArray *files = [NSMutableArray arrayWithObject:@[@"its transcript", kept[@"files"][@"main"],
                                                              now[@"main"] ?: @{}]];
    for (NSString *name in [[kept[@"files"][@"subs"] allKeys] sortedArrayUsingSelector:@selector(compare:)])
        [files addObject:@[[@"its sub-agent's record " stringByAppendingString:name], kept[@"files"][@"subs"][name],
                           now[@"subs"][name] ?: @{}]];
    for (NSArray *file in files) {
        NSDictionary *was = file[1], *is = file[2];
        if (!is[@"inode"]) return [file[0] stringByAppendingString:@" has gone"];
        if (![is[@"inode"] isEqual:was[@"inode"]]) return [file[0] stringByAppendingString:@" is another file now"];
        if ([is[@"size"] unsignedLongLongValue] < [was[@"offset"] unsignedLongLongValue])
            return [file[0] stringByAppendingString:@" is shorter than what was read"];
        if (![is[@"mark"] isEqual:was[@"mark"]]) return [file[0] stringByAppendingString:@" was written over"];
    }
    return nil;
}

// The parts of a session's state the reader keeps itself, besides its writings' and its edits', each the kind its reads
// make it. The mode, the topic and when the conversation last moved aren't among them, nor where they were found: what
// finds a session's tab, how many Shift+Tabs its mode menu types and whether it might bypass permissions go by those,
// so nothing kept may choose them. They're read again from the transcript (ReadBackFrom).
static NSArray<NSString *> *OwnParts(void) {
    return @[@"prs", @"usage", @"spent"];
}

NSDictionary *KeptRead(NSDictionary *t, NSString *sessionId, NSString *version) {
    if (!IsPlainId(sessionId, 64) || !AsText(t[@"path"]) || !AsNumber(t[@"inode"])) return nil;
    NSMutableDictionary *found = [NSMutableDictionary dictionary], *subs = [NSMutableDictionary dictionary];
    for (NSString *part in OwnParts())
        if (t[part]) found[part] = t[part];
    [found addEntriesFromDictionary:KeptWritings(t)];
    [found addEntriesFromDictionary:KeptEdits(t)];
    for (NSString *name in t[@"subOffsets"]) {
        if (!t[@"subInodes"][name]) return nil;
        subs[name] = @{@"inode": t[@"subInodes"][name], @"offset": t[@"subOffsets"][name]};
    }
    return @{@"shape": @(kReadsShape), @"version": version ?: @"", @"sessionId": sessionId, @"path": t[@"path"],
             @"files": @{@"main": @{@"inode": t[@"inode"], @"offset": t[@"offset"] ?: @0}, @"subs": subs},
             @"found": found};
}

// A file's place as kept: {inode, offset, mark}, each its kind; nil for anything else.
static NSDictionary *PlaceIn(id value) {
    NSDictionary *place = AsRecord(value);
    return place.count == 3 && AsNumber(place[@"inode"]) && AsNumber(place[@"offset"]) && AsText(place[@"mark"])
        ? place : nil;
}

// What a session's replies used, as SpentAdd keeps it, or none yet.
static BOOL SpentFits(id value) {
    NSDictionary *spent = AsRecord(value);
    return spent && (!spent.count || (spent.count == 4 && AsNumber(spent[@"day"]) && AsNumber(spent[@"tokens"])
                                      && AsText(spent[@"lastId"]) && AsNumber(spent[@"lastTokens"])));
}

// The reader's own parts as its reads make them: PR links (each https, by its address), the context in use and what was
// spent.
static BOOL OwnPartsFit(NSDictionary *found) {
    NSDictionary *prs = AsRecord(found[@"prs"]), *usage = found[@"usage"] ? AsRecord(found[@"usage"]) : @{};
    NSDictionary *spent = found[@"spent"] ? AsRecord(found[@"spent"]) : @{@"subs": @{}};
    if (!prs || !usage || !spent || (usage.count && !AsNumber(usage[@"tokens"])) || !SpentFits(spent[@"main"] ?: @{})
        || !AsRecord(spent[@"subs"]))
        return NO;
    for (NSString *key in usage)
        if (![@[@"tokens", @"model", @"effort", @"at"] containsObject:key]
            || (![key isEqual:@"tokens"] && !AsText(usage[key])))
            return NO;
    for (NSString *name in spent[@"subs"])
        if (!SpentFits(spent[@"subs"][name])) return NO;
    for (NSString *url in prs) {
        NSDictionary *link = AsRecord(prs[url]);
        if (link.count != 4 || ![url hasPrefix:@"https://"] || ![link[@"url"] isEqual:url] || !AsNumber(link[@"number"])
            || !AsText(link[@"repo"]) || !AsText(link[@"at"]))
            return NO;
    }
    return YES;
}

NSMutableDictionary *TakeBackRead(NSDictionary *kept, NSString *sessionId) {
    NSString *path = AsText(kept[@"path"]);
    NSDictionary *files = AsRecord(kept[@"files"]), *found = AsRecord(kept[@"found"]);
    NSDictionary *main = PlaceIn(files[@"main"]), *subs = AsRecord(files[@"subs"]);
    // Its transcript is where Claude Code keeps them, named for the session, as the reads find it.
    NSString *projects = ClaudeDir(kClaudeCodeTranscripts);
    if (!IsPlainId(sessionId, 64) || ![kept[@"sessionId"] isEqual:sessionId] || !AsNumber(kept[@"shape"])
        || !AsText(kept[@"version"])
        || ![path.lastPathComponent isEqualToString:[sessionId stringByAppendingPathExtension:@"jsonl"]]
        || ![path.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent isEqualToString:projects]
        || [path.stringByDeletingLastPathComponent.lastPathComponent hasPrefix:@"."] || !main || !subs || !found
        || !OwnPartsFit(found))
        return nil;
    NSMutableDictionary *state = [NSMutableDictionary dictionary], *offsets = [NSMutableDictionary dictionary];
    NSMutableDictionary *inodes = [NSMutableDictionary dictionary];
    for (NSString *name in subs) {
        NSDictionary *place = PlaceIn(subs[name]);
        if (!place || ![name isEqualToString:name.lastPathComponent] || [name hasPrefix:@"."]
            || ![name.pathExtension isEqualToString:@"jsonl"])
            return nil;
        offsets[name] = place[@"offset"];
        inodes[name] = place[@"inode"];
    }
    // Only the parts the readers keep: anything else (a mode, say) is refused, not passed over.
    NSMutableSet *parts = [NSMutableSet setWithArray:OwnParts()];
    [parts addObjectsFromArray:KeptWritings(@{}).allKeys];
    [parts addObjectsFromArray:[KeptEdits(@{}).allKeys arrayByAddingObjectsFromArray:@[@"shellMode", @"shellBase"]]];
    if (![[NSSet setWithArray:found.allKeys] isSubsetOfSet:parts]) return nil;
    if (!TakeBackWritings(found, state) || !TakeBackEdits(found, state)) return nil;
    for (NSString *part in OwnParts())
        if (found[part]) state[part] = found[part];
    state[@"prs"] = [found[@"prs"] mutableCopy];
    state[@"path"] = path;
    state[@"offset"] = main[@"offset"];
    state[@"inode"] = main[@"inode"];
    state[@"subOffsets"] = offsets;
    state[@"subInodes"] = inodes;
    return state;
}

// A kept read with each file's mark taken, the files as they are now; nil when one isn't the file read, or is shorter.
static NSDictionary *Marked(NSDictionary *kept) {
    NSDictionary *now = KeptReadFilesNow(kept);
    NSMutableDictionary *marked = [kept mutableCopy], *files = [NSMutableDictionary dictionary];
    NSMutableDictionary *subs = [NSMutableDictionary dictionary];
    NSDictionary *(^mark)(NSDictionary *, NSDictionary *) = ^NSDictionary *(NSDictionary *was, NSDictionary *is) {
        if (![is[@"inode"] isEqual:was[@"inode"]] || !is[@"mark"]) return nil;
        return @{@"inode": was[@"inode"], @"offset": was[@"offset"], @"mark": is[@"mark"]};
    };
    if (!(files[@"main"] = mark(kept[@"files"][@"main"], now[@"main"]))) return nil;
    for (NSString *name in kept[@"files"][@"subs"])
        if (!(subs[name] = mark(kept[@"files"][@"subs"][name], now[@"subs"][name]))) return nil;
    files[@"subs"] = subs;
    marked[@"files"] = files;
    return marked;
}

// A session's kept read, by its id.
static NSString *KeptReadFile(NSString *folder, NSString *sessionId) {
    return [folder stringByAppendingPathComponent:[sessionId stringByAppendingPathExtension:@"json"]];
}

BOOL KeepRead(NSString *folder, NSDictionary *kept) {
    NSString *sessionId = kept[@"sessionId"];
    if (!IsPlainId(sessionId, 64)) return NO;
    NSString *path = KeptReadFile(folder, sessionId);
    NSDictionary *marked = Marked(kept);
    NSData *json = marked ? [NSJSONSerialization dataWithJSONObject:marked options:NSJSONWritingSortedKeys error:nil]
                          : nil;
    if (!json) return NO;
    NSFileManager *files = NSFileManager.defaultManager;
    if (LooksLikeSecret([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding])) {
        PanelLog(@"%@'s read isn't kept: something in it is shaped like a key", sessionId);
        [files removeItemAtPath:path error:nil];
        return NO;
    }
    // Written beside it first, then moved in: a read at launch finds the whole of the old one or the new.
    [files createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700}
                           error:nil];
    NSString *writing = [path stringByAppendingPathExtension:@"writing"];
    int fd = open(writing.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
    BOOL whole = fd >= 0 && fchmod(fd, 0600) == 0 && write(fd, json.bytes, json.length) == (ssize_t)json.length;
    if (fd >= 0) close(fd);
    if (!whole || rename(writing.fileSystemRepresentation, path.fileSystemRepresentation) != 0) {
        [files removeItemAtPath:writing error:nil];
        return NO;
    }
    return YES;
}

// How far back from where a kept read stopped its transcript is read again at most: for the mode and the newest
// message, which every prompt and reply records, 16 MB; for the topic, which Claude Code writes again as the
// conversation goes, 256 KB.
static const unsigned long long kModeBack = 16 * 1024 * 1024, kTopicBack = 256 * 1024;

// The mode, the newest message's time and the topic as a read of the transcript up to where a kept read stopped finds
// them, read back from there a piece at a time, whole lines only: until the mode and the newest message are both found,
// kModeBack at most, with the topic found in the last kTopicBack, or none. NO when the mode or the newest message
// isn't found that far back. Nothing kept chooses where they come from.
static BOOL ReadBackFrom(NSString *path, NSMutableDictionary *state) {
    unsigned long long end = [state[@"offset"] unsignedLongLongValue];
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!fh) return NO;
    NSData *newline = [@"\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *mode = nil, *title = nil;
    double modeAt = 0, messageAt = 0;
    for (unsigned long long back = 64 * 1024;; back *= 2) {
        unsigned long long from = end > back ? end - back : 0;
        [fh seekToFileOffset:from];
        NSData *chunk = [fh readDataOfLength:(NSUInteger)(end - from)];
        NSUInteger start = 0;
        if (from > 0) {  // from the start of a line
            NSRange first = [chunk rangeOfData:newline options:0 range:NSMakeRange(0, chunk.length)];
            start = first.location == NSNotFound ? chunk.length : NSMaxRange(first);
        }
        NSData *lines = [chunk subdataWithRange:NSMakeRange(start, chunk.length - start)];
        mode = NewestMode(lines, lines.length, &modeAt);
        messageAt = LatestMessageAt(lines, lines.length);
        if (!title && back <= kTopicBack) title = NewestTitle(lines, lines.length);
        BOOL found = mode.length && messageAt > 0 && (title || back >= kTopicBack);
        if (found || from == 0 || back >= kModeBack) break;
    }
    [fh closeFile];
    if (!mode.length || messageAt <= 0) return NO;
    state[@"mode"] = mode;
    state[@"modeAt"] = @(modeAt);
    state[@"messageAt"] = @(messageAt);
    if (title.length) state[@"title"] = title;
    else state[@"topicFar"] = @YES;
    return YES;
}

NSMutableDictionary *GoOnFrom(NSDictionary *kept, NSString *sessionId, NSString *path, NSString *version,
                              NSString **why) {
    NSMutableDictionary *state = TakeBackRead(kept, sessionId);
    *why = !state ? @"it doesn't read back as it should"
         : ![state[@"path"] isEqualToString:path] ? @"its transcript has moved"
         : WhyNotGoOnFrom(kept, KeptReadFilesNow(kept), version);
    if (!*why && !ReadBackFrom(path, state)) *why = @"its mode or its newest message isn't near where it was read to";
    return *why ? nil : state;
}

// What was kept of a session's read, as a state to go on from, while it still applies to its files; else nil, and the
// session is read from its start, as the log says, and what was kept goes, as its next keeping would replace it. On the
// reads' queue.
static NSMutableDictionary *KeptFor(NSString *folder, NSString *sessionId, NSString *path, NSString *version) {
    if (!IsPlainId(sessionId, 64)) return nil;
    NSString *file = KeptReadFile(folder, sessionId);
    NSDictionary *kept = AsRecord(ReadJSON(file));
    if (!kept) return nil;
    NSString *why = nil;
    NSMutableDictionary *state = GoOnFrom(kept, sessionId, path, version, &why);
    if (why) {
        PanelLog(@"%@ read from its start, as what was kept of it can't be gone on from: %@", sessionId, why);
        [NSFileManager.defaultManager removeItemAtPath:file error:nil];
    }
    return state;
}

NSArray<NSString *> *KeptReadsToDrop(NSString *folder, NSSet<NSString *> *listed, NSTimeInterval at) {
    NSMutableArray<NSString *> *drop = [NSMutableArray array];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil]) {
        NSString *sessionId = name.stringByDeletingPathExtension, *file = [folder stringByAppendingPathComponent:name];
        NSString *transcript = [name.pathExtension isEqualToString:@"json"] && IsPlainId(sessionId, 64)
            ? TranscriptPath(sessionId) : nil;
        // One whose transcript is another file now, or shorter than it read, goes too: it holds lines that may not be
        // there any more.
        NSDictionary *main = transcript ? AsRecord(AsRecord(AsRecord(ReadJSON(file))[@"files"])[@"main"]) : nil;
        NSDictionary *now = main ? FileNow(transcript, 0) : nil;
        if (!transcript || ![now[@"inode"] isEqual:main[@"inode"]]
            || [now[@"size"] unsignedLongLongValue] < [main[@"offset"] unsignedLongLongValue]
            || (![listed containsObject:sessionId] && at - FileModifiedAt(file) > kKeptFor))
            [drop addObject:name];
    }
    return [drop sortedArrayUsingSelector:@selector(compare:)];
}

// The version of Whozmove that's running, as its kept reads are marked with: a new one may read differently.
static NSString *RunningVersion(void) {
    return AsText(NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"]) ?: @"";
}

// How often a session's state is kept at most while it changes, and how many are made each time the reads come round,
// as each is made on the main thread, where the states are. Each is the whole state, about a megabyte for a busy
// session, mostly its edits, so it's kept seldom: Whozmove quitting keeps it anyway, and a crash costs at most this
// long's new lines read again.
static const NSTimeInterval kKeepEvery = 1800;
static const NSUInteger kKeepAtOnce = 8;

@interface Transcripts ()
// sessionId -> what's been read for it, and whether a read is out. Touched on the main thread only; the files are
// read on the queue, one read at a time.
@property (strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *states;
@property (strong) dispatch_queue_t queue;
// Where a look someone's waiting on is made (a writing for the reader, a reply), each at once: never behind the reads,
// which take a while for every transcript read from its start (one with nothing kept that applies, as Whozmove opens).
@property (strong) dispatch_queue_t looks;
// Where what's read is kept across restarts, from launch on (nil in a print run), the version it's kept by, and the
// queue its files are written, checked and taken away on, one at a time; for each session, where its reads had got to
// when its state was last kept, and when ({where, at}); whether the kept reads have been pruned since launch; the
// hourly prune; and how many bytes the reads have read.
@property (copy) NSString *folder;
@property (copy) NSString *version;
@property (strong) dispatch_queue_t keeping;
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *keptAt;
@property (assign) BOOL pruned;
@property (strong) NSTimer *pruning;
@property (readwrite) unsigned long long bytesRead;
@end

@implementation Transcripts

- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.states = [NSMutableDictionary dictionary];
    self.queue = dispatch_queue_create("whozmove.transcripts", DISPATCH_QUEUE_SERIAL);
    self.looks = dispatch_queue_create("whozmove.transcripts.looks",
                                       dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_CONCURRENT,
                                                                               QOS_CLASS_USER_INITIATED, 0));
    return self;
}

- (NSDictionary *)stateOf:(NSString *)sessionId {
    return self.states[sessionId];
}

// Looked for among the project folders only for a session the reads haven't found a transcript for yet.
- (NSString *)pathOf:(NSString *)sessionId {
    return self.states[sessionId][@"path"] ?: TranscriptPath(sessionId);
}

// What the reads have been through is known already, so only what's been written since the last one is looked at:
// a few lines, usually. A session they haven't reached yet has the end of its transcript looked at instead.
- (NSString *)topicOf:(NSString *)sessionId {
    NSMutableDictionary *t = self.states[sessionId];
    NSString *topic = t[@"path"] ? TitleSince(t[@"path"], [t[@"offset"] unsignedLongLongValue]) ?: t[@"title"] : nil;
    // One gone on from what was kept, whose topic wasn't near where its reads had got to, has the end of its transcript
    // looked at once, as one they haven't reached yet does: else a tab found for it could be another session's that
    // has no topic either.
    if (!topic && [t[@"topicFar"] boolValue]) {
        [t removeObjectForKey:@"topicFar"];
        if ((topic = TitleSince(t[@"path"], 0))) t[@"title"] = topic;
    }
    if (t[@"path"]) return topic;
    NSString *path = TranscriptPath(sessionId);
    return path ? TitleSince(path, 0) : nil;
}

- (NSString *)lastTopicOf:(NSString *)sessionId {
    return self.states[sessionId][@"title"];
}

// Not after the reads: a plan is found again by its own call's id at the place a read noted, and a file is read as it
// is now, so a read that's out changes neither.
- (void)readWriting:(NSString *)writingId of:(NSString *)sessionId done:(void (^)(NSDictionary *read))done {
    NSDictionary *t = self.states[sessionId];
    NSDictionary *writing = [writingId isKindOfClass:NSString.class] ? [t[@"writings"][writingId] copy] : nil;
    NSString *path = t[@"path"];
    if (!writing) {
        done(@{@"missing": @"This isn't in the session's list any more."});
        return;
    }
    dispatch_async(self.looks, ^{
        NSDictionary *read = ReadWriting(path, writing);
        dispatch_async(dispatch_get_main_queue(), ^{ done(read); });
    });
}

- (void)replyTo:(NSString *)prompt of:(NSString *)sessionId since:(double)since done:(void (^)(NSString *reply))done {
    NSString *path = [prompt isKindOfClass:NSString.class] ? [self pathOf:sessionId] : nil;
    if (!path) {
        done(nil);
        return;
    }
    dispatch_async(self.looks, ^{
        NSFileHandle *file = [NSFileHandle fileHandleForReadingAtPath:path];
        unsigned long long size = [file seekToEndOfFile], from = size > kReplyRead ? size - kReplyRead : 0;
        [file seekToFileOffset:from];
        NSData *chunk = [file readDataOfLength:(NSUInteger)(size - from)];
        [file closeFile];
        NSString *reply = ReplyAfter(chunk, from == 0, prompt, since);
        dispatch_async(dispatch_get_main_queue(), ^{ done(reply); });
    });
}

- (void)afterWords:(NSString *)words of:(NSString *)sessionId since:(double)since
              done:(void (^)(NSDictionary *found))done {
    NSString *path = [words isKindOfClass:NSString.class] ? [self pathOf:sessionId] : nil;
    if (!path) {
        done(nil);
        return;
    }
    dispatch_async(self.looks, ^{
        NSFileHandle *file = [NSFileHandle fileHandleForReadingAtPath:path];
        unsigned long long size = [file seekToEndOfFile], from = size > kReplyRead ? size - kReplyRead : 0;
        [file seekToFileOffset:from];
        NSData *chunk = [file readDataOfLength:(NSUInteger)(size - from)];
        [file closeFile];
        NSDictionary *found = AfterHandedWords(chunk, from == 0, words, since);
        dispatch_async(dispatch_get_main_queue(), ^{ done(found); });
    });
}

- (BOOL)reading {
    return [[self.states.allValues valueForKey:@"reading"] containsObject:@YES];
}

- (void)keepIn:(NSString *)folder {
    self.folder = folder;
    self.version = RunningVersion();
    self.keeping = dispatch_queue_create("whozmove.transcripts.keeping", DISPATCH_QUEUE_SERIAL);
    self.keptAt = [NSMutableDictionary dictionary];
    __weak typeof(self) weakSelf = self;
    self.pruning = [NSTimer scheduledTimerWithTimeInterval:3600 repeats:YES block:^(NSTimer *timer) {
        [weakSelf prune];
    }];
    self.pruning.tolerance = 60;
}

// Where a session's reads have got to: its state has changed since it was kept when this has.
static NSDictionary *WhereReadTo(NSDictionary *t) {
    return @{@"offset": t[@"offset"] ?: @0, @"subOffsets": [t[@"subOffsets"] copy] ?: @{}};
}

// Each session's state whose reads have moved on since it was kept, with no read of it out, at most every kKeepEvery
// and kKeepAtOnce at a time; `now`, all of them at once, until `until` (seconds since 1970).
- (void)keepChanged:(BOOL)now until:(NSTimeInterval)until {
    if (!self.folder) return;
    NSString *folder = self.folder;
    NSTimeInterval at = NSDate.date.timeIntervalSince1970;
    NSUInteger made = 0;
    for (NSString *sid in [self.states.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSMutableDictionary *t = self.states[sid];
        NSDictionary *was = self.keptAt[sid], *where = WhereReadTo(t);
        if ([t[@"reading"] boolValue] || !t[@"path"] || [was[@"where"] isEqual:where]) continue;
        if (now ? NSDate.date.timeIntervalSince1970 > until
                : at - [was[@"at"] doubleValue] < kKeepEvery || made == kKeepAtOnce)
            continue;
        made++;
        self.keptAt[sid] = @{@"where": where, @"at": @(at)};
        NSDictionary *kept = KeptRead(t, sid, self.version);
        if (kept) dispatch_async(self.keeping, ^{ KeepRead(folder, kept); });
    }
}

// Within the 5 seconds a restart waits for Whozmove to stop.
- (void)keepNow {
    if (!self.keeping) return;
    NSTimeInterval started = NSDate.date.timeIntervalSince1970;
    [self keepChanged:YES until:started + 3];
    dispatch_block_t written = dispatch_block_create(0, ^{});
    dispatch_async(self.keeping, written);
    dispatch_block_wait(written, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)));
}

// The kept reads whose transcript has gone, or whose session hasn't been listed for kKeptFor, taken away on the queue,
// in turn with the writes. Only once the sessions listed now are known.
- (void)prune {
    if (!self.folder || !self.sessionIds) return;
    NSString *folder = self.folder;
    NSSet<NSString *> *listed = [NSSet setWithArray:self.sessionIds];
    dispatch_async(self.keeping, ^{
        for (NSString *name in KeptReadsToDrop(folder, listed, NSDate.date.timeIntervalSince1970)) {
            PanelLog(@"kept read %@ dropped: its transcript has gone, or it hasn't been listed for days", name);
            [NSFileManager.defaultManager removeItemAtPath:[folder stringByAppendingPathComponent:name] error:nil];
        }
    });
}

// Picks up what's new in each listed session's transcript: PR links, the context in use, the permission mode,
// when the conversation last moved, what it wrote for you to read, and what it used today. A session first read since
// launch goes on from what the last copy of Whozmove kept of it, while that still applies.
- (void)readNew {
    for (NSString *sid in self.states.allKeys)
        if (![self.sessionIds containsObject:sid]) [self.states removeObjectForKey:sid];
    [self keepChanged:NO until:0];
    if (self.folder && !self.pruned) {
        self.pruned = YES;
        [self prune];
    }
    NSString *folder = self.folder, *version = self.version;
    double today = self.dayStart ? self.dayStart() : StartOfToday();
    for (NSString *sid in self.sessionIds) {
        if (![sid isKindOfClass:NSString.class]) continue;
        NSMutableDictionary *t = self.states[sid];
        BOOL first = !t;
        if (!t) self.states[sid] = t = [@{@"offset": @0, @"prs": [NSMutableDictionary dictionary]} mutableCopy];
        if ([t[@"reading"] boolValue]) continue;
        t[@"reading"] = @YES;
        NSString *knownPath = t[@"path"];
        NSDictionary *from = ReadFrom(t);
        dispatch_async(self.queue, ^{
            NSString *path = knownPath ?: TranscriptPath(sid);
            NSMutableDictionary *kept = first && folder && path ? KeptFor(folder, sid, path, version) : nil;
            NSDictionary *read = path ? ReadSession(path, kept ? ReadFrom(kept) : from, today) : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                t[@"reading"] = @NO;
                if (kept) {
                    [t addEntriesFromDictionary:kept];
                    self.keptAt[sid] = @{@"where": WhereReadTo(kept), @"at": @(NSDate.date.timeIntervalSince1970)};
                }
                if (read) {
                    AddSessionNews(sid, t, read);
                    self.bytesRead += [read[@"bytes"] unsignedLongLongValue];
                }
                TranscriptNews *news = read[@"news"];
                if (([kept[@"prs"] count] || news.prLinks.count) && self.onPRLinks) self.onPRLinks();
            });
        });
    }
}

@end
