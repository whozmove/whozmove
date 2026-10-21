// Transcripts: what's new in a session's transcript, read a little at a time.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Transcripts.h"
#import "Writings.h"
#import "Edits.h"
#import "Files.h"
#import "Log.h"
#import "ClaudeCodeFacts.h"

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

// The session's topic as Claude Code last named it, in a chunk of transcript up to `end`: its newest "aiTitle"
// record, or nil.
static NSString *NewestTitle(NSData *chunk, NSUInteger end) {
    NSData *key = [@"\"aiTitle\"" dataUsingEncoding:NSUTF8StringEncoding];
    NSRange hit = [chunk rangeOfData:key options:NSDataSearchBackwards range:NSMakeRange(0, end)];
    if (hit.location == NSNotFound) return nil;
    NSDictionary *entry = JSONLineAt(chunk, hit.location, end, NULL);
    id title = [entry isKindOfClass:NSDictionary.class] ? entry[@"aiTitle"] : nil;
    return [title isKindOfClass:NSString.class] ? title : nil;
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
static double LatestMessageAt(NSData *chunk, NSUInteger end) {
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
@end

@implementation TranscriptNews
@end

// The commands known to run git: those before, and those in this part.
static NSSet<NSString *> *GitCalls(NSSet *before, NSDictionary *shells) {
    return [(before ?: [NSSet set]) setByAddingObjectsFromArray:shells[@"git"] ?: @[]];
}

// Reads a transcript from `offset` up to its last complete line, and moves `offset` past what it read, so each
// call reads only what's new. The PR links are the "pr-link" records Claude Code writes when a session makes or
// works on a PR. Every prompt records the mode it was sent in, and a session records its mode when it starts.
// `waiting` are the calls whose results the session's writings still wait for (see Writings.h); `shellsSoFar` the
// session's transcript state, for where ShellNews left off.
static TranscriptNews *ReadTranscriptNews(NSString *path, unsigned long long *offset, NSSet *waiting,
                                          NSDictionary *shellsSoFar) {
    TranscriptNews *news = [TranscriptNews new];
    news.prLinks = @[];
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!fh) return news;
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
    news.title = NewestTitle(chunk, NSMaxRange(lastNewline));
    NSData *modeKey = [@"\"permissionMode\":\"" dataUsingEncoding:NSUTF8StringEncoding];
    NSRange modeAt = [chunk rangeOfData:modeKey options:NSDataSearchBackwards
                                  range:NSMakeRange(0, NSMaxRange(lastNewline))];
    if (modeAt.location != NSNotFound) {
        NSRange quote = [chunk rangeOfData:[@"\"" dataUsingEncoding:NSUTF8StringEncoding] options:0
                                     range:NSMakeRange(NSMaxRange(modeAt),
                                                       MIN(32, NSMaxRange(lastNewline) - NSMaxRange(modeAt)))];
        if (quote.location != NSNotFound)
            news.mode = [[NSString alloc]
                initWithData:[chunk subdataWithRange:NSMakeRange(NSMaxRange(modeAt),
                                                                 quote.location - NSMaxRange(modeAt))]
                    encoding:NSUTF8StringEncoding];
        NSDictionary *entry = JSONLineAt(chunk, modeAt.location, NSMaxRange(lastNewline), NULL);
        if ([entry isKindOfClass:NSDictionary.class]) news.modeAt = TimestampMs(entry[@"timestamp"]);
    }

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
// mode the session is in, `shellsSoFar` as ReadTranscriptNews takes it). `offsets` (file name -> where the last read
// of it ended) moves on as they're read.
static NSArray<NSDictionary *> *SubAgentEdits(NSString *path, NSMutableDictionary *offsets, NSDictionary *shellsSoFar,
                                              NSMutableArray *shells) {
    NSString *folder = [[path stringByDeletingPathExtension] stringByAppendingPathComponent:kClaudeCodeSubagents];
    NSData *newline = [@"\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableArray *edits = [NSMutableArray array];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil]) {
        if (![name.pathExtension isEqualToString:@"jsonl"]) continue;
        NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:[folder stringByAppendingPathComponent:name]];
        if (!fh) continue;
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
    }
    return edits;
}

@interface Transcripts ()
// sessionId -> what's been read for it, and whether a read is out. Touched on the main thread only; the files are
// read on the queue.
@property (strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *states;
@property (strong) dispatch_queue_t queue;
@end

@implementation Transcripts

- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.states = [NSMutableDictionary dictionary];
    self.queue = dispatch_queue_create("whozmove.transcripts", DISPATCH_QUEUE_SERIAL);
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
    NSDictionary *t = self.states[sessionId];
    if (t[@"path"]) return TitleSince(t[@"path"], [t[@"offset"] unsignedLongLongValue]) ?: t[@"title"];
    NSString *path = TranscriptPath(sessionId);
    return path ? TitleSince(path, 0) : nil;
}

- (NSString *)lastTopicOf:(NSString *)sessionId {
    return self.states[sessionId][@"title"];
}

// On the reads' queue, after any read that's out, so a plan's place in the file is where that read left it.
- (void)readWriting:(NSString *)writingId of:(NSString *)sessionId done:(void (^)(NSDictionary *read))done {
    NSDictionary *t = self.states[sessionId];
    NSDictionary *writing = [writingId isKindOfClass:NSString.class] ? [t[@"writings"][writingId] copy] : nil;
    NSString *path = t[@"path"];
    if (!writing) {
        done(@{@"missing": @"This isn't in the session's list any more."});
        return;
    }
    dispatch_async(self.queue, ^{
        NSDictionary *read = ReadWriting(path, writing);
        dispatch_async(dispatch_get_main_queue(), ^{ done(read); });
    });
}

- (BOOL)reading {
    return [[self.states.allValues valueForKey:@"reading"] containsObject:@YES];
}

// Picks up what's new in each listed session's transcript: PR links, the context in use, the permission mode,
// when the conversation last moved, and what it wrote for you to read.
- (void)readNew {
    for (NSString *sid in self.states.allKeys)
        if (![self.sessionIds containsObject:sid]) [self.states removeObjectForKey:sid];

    for (NSString *sid in self.sessionIds) {
        if (![sid isKindOfClass:NSString.class]) continue;
        NSMutableDictionary *t = self.states[sid];
        if (!t) self.states[sid] = t = [@{@"offset": @0, @"prs": [NSMutableDictionary dictionary]} mutableCopy];
        if ([t[@"reading"] boolValue]) continue;
        t[@"reading"] = @YES;
        NSString *knownPath = t[@"path"];
        unsigned long long start = [t[@"offset"] unsignedLongLongValue];
        NSSet *waiting = [NSSet setWithArray:[t[@"waiting"] allKeys] ?: @[]];
        NSMutableDictionary *subOffsets = [t[@"subOffsets"] mutableCopy] ?: [NSMutableDictionary dictionary];
        NSDictionary *shellsSoFar = @{@"shellMode": t[@"shellMode"] ?: @"", @"shellBase": t[@"shellBase"] ?: @"",
                                      @"gitCalls": [t[@"gitCalls"] set] ?: [NSSet set]};
        dispatch_async(self.queue, ^{
            NSString *path = knownPath ?: TranscriptPath(sid);
            unsigned long long offset = start;
            TranscriptNews *news = path ? ReadTranscriptNews(path, &offset, waiting, shellsSoFar) : nil;
            NSDictionary *writings = news.writings;
            NSArray *edits = news.edits;
            NSMutableArray *shells = [NSMutableArray arrayWithObjects:news.shells, nil];
            // Sub-agents start in the mode the session's own record has just left off in.
            NSDictionary *sessionNow = @{@"shellMode": news.shells[@"mode"] ?: shellsSoFar[@"shellMode"],
                                         @"shellBase": news.shells[@"base"] ?: shellsSoFar[@"shellBase"],
                                         @"gitCalls": GitCalls(shellsSoFar[@"gitCalls"], news.shells)};
            NSArray *subEdits = path ? SubAgentEdits(path, subOffsets, sessionNow, shells) : @[];
            NSArray *links = news.prLinks ?: @[];
            NSDictionary *usage = news.usage;
            NSString *mode = news.mode, *title = news.title;
            double modeAt = news.modeAt, messageAt = news.messageAt;
            dispatch_async(dispatch_get_main_queue(), ^{
                t[@"reading"] = @NO;
                if (path) t[@"path"] = path;
                t[@"offset"] = @(offset);
                // Later entries carry the newer timestamp.
                for (NSDictionary *link in links) t[@"prs"][link[@"url"]] = link;
                // After a compaction only the size changed: the model is still the one the last reply came from.
                if (usage[@"compacted"]) {
                    PanelLog(@"%@ -> compacted: %@ tokens in context now", sid, usage[@"tokens"]);
                    NSMutableDictionary *kept = [t[@"usage"] mutableCopy] ?: [NSMutableDictionary dictionary];
                    // The new size, and that reply's model if it was in this read.
                    [kept addEntriesFromDictionary:usage];
                    [kept removeObjectForKey:@"compacted"];
                    t[@"usage"] = kept;
                } else if (usage) t[@"usage"] = usage;
                // Timed by its record, not by when it was read: an older record read now mustn't outrank a
                // mode picked here since.
                if (mode.length) { t[@"mode"] = mode; t[@"modeAt"] = @(modeAt); }
                if (messageAt > [t[@"messageAt"] doubleValue]) t[@"messageAt"] = @(messageAt);
                if (title.length) t[@"title"] = title;
                if (writings) AddWritingNews(t, writings);
                AddEditNews(t, edits);
                AddEditNews(t, subEdits);
                for (NSDictionary *shell in shells) AddShellNews(t, shell);
                t[@"subOffsets"] = subOffsets;
                if (links.count && self.onPRLinks) self.onPRLinks();
            });
        });
    }
}

@end
