// Writings: what a session wrote for you to read (its plans, prototypes and notes), found in its transcript.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Writings.h"
#import "Files.h"
#import "ClaudeCodeFacts.h"

// How many writings a row lists, and the most read back for one: a page to read, not a data file.
static const NSUInteger kListed = 50;
static const unsigned long long kLargest = 2 * 1024 * 1024;

// What a file is, to the reader, by its name: a page Claude made to look at (a prototype), or notes; anything else
// isn't listed. Claude Code's own files (memory, settings, the plans it keeps for plan mode, which are listed as
// plans already) aren't the session's writing either.
static NSString *KindOfFile(NSString *path) {
    if (![path isKindOfClass:NSString.class] || !path.isAbsolutePath) return nil;
    if ([path hasPrefix:[ClaudeDir(@"") stringByAppendingString:@"/"]] || [path.pathComponents containsObject:@".claude"])
        return nil;
    NSString *ext = path.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"html"] || [ext isEqualToString:@"htm"]) return @"prototype";
    if ([ext isEqualToString:@"md"] || [ext isEqualToString:@"markdown"]) return @"notes";
    return nil;
}

// A Markdown text's first heading, or its first line; nil if it has neither.
static NSString *HeadingOf(NSString *text) {
    NSString *first = nil;
    for (NSString *raw in [text componentsSeparatedByString:@"\n"]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (!line.length) continue;
        if ([line hasPrefix:@"#"]) {
            NSString *title = [[line stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"# "]]
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if (title.length) return Clip(title, 120);
        }
        if (!first) first = Clip(line, 120);
    }
    return first;
}

// What a file is called, as its reader names it: an HTML page's <title> or a Markdown file's first heading, from the
// start of what was written, else the file's name.
static NSString *TitleOfFile(NSString *path, NSString *content) {
    NSString *start = [content isKindOfClass:NSString.class] ? Clip(content, 4000) : @"";
    if ([KindOfFile(path) isEqualToString:@"prototype"]) {
        NSRange open = [start rangeOfString:@"<title>" options:NSCaseInsensitiveSearch];
        NSRange close = open.location == NSNotFound ? open
            : [start rangeOfString:@"</title>" options:NSCaseInsensitiveSearch
                             range:NSMakeRange(NSMaxRange(open), start.length - NSMaxRange(open))];
        if (close.location != NSNotFound) {
            NSString *title = [[start substringWithRange:NSMakeRange(NSMaxRange(open), close.location - NSMaxRange(open))]
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (title.length) return Clip(title, 120);
        }
    } else if (start.length) {
        NSString *heading = HeadingOf(start);
        if (heading) return heading;
    }
    return path.lastPathComponent;
}

// A tool result's text: a plain string, or the text parts of a list.
static NSString *ResultText(id content) {
    if ([content isKindOfClass:NSString.class]) return content;
    NSMutableString *text = [NSMutableString string];
    for (id part in [content isKindOfClass:NSArray.class] ? content : @[])
        if ([part isKindOfClass:NSDictionary.class] && [part[@"text"] isKindOfClass:NSString.class])
            [text appendString:part[@"text"]];
    return text;
}

// The calls that write something to read: a plan presented for your OK (ExitPlanMode), a file written (Write), or
// a page published (Artifact). Their results come later, often in a later read, and say whether a plan was approved
// and whether a file was new: only files the session created are its writing, not ones it rewrote.
NSDictionary *WritingNews(NSData *chunk, NSUInteger end, unsigned long long base, NSSet<NSString *> *waiting) {
    NSMutableArray *calls = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSString *tool in @[@"ExitPlanMode", @"Write", @"Artifact"]) {
        NSData *marker = [[NSString stringWithFormat:@"\"name\":\"%@\"", tool] dataUsingEncoding:NSUTF8StringEncoding];
        NSUInteger cursor = 0;
        while (cursor < end) {
            NSRange hit = [chunk rangeOfData:marker options:0 range:NSMakeRange(cursor, end - cursor)];
            if (hit.location == NSNotFound) break;
            NSRange line;
            NSDictionary *entry = JSONLineAt(chunk, hit.location, end, &line);
            cursor = NSMaxRange(line) + 1;
            if (![entry isKindOfClass:NSDictionary.class] || ![entry[@"type"] isEqual:@"assistant"]) continue;
            // A sub-agent's plan isn't one you're asked about.
            if ([tool isEqualToString:@"ExitPlanMode"] && [entry[@"isSidechain"] boolValue]) continue;
            id message = entry[@"message"];
            id content = [message isKindOfClass:NSDictionary.class] ? message[@"content"] : nil;
            NSUInteger index = 0;
            for (NSDictionary *item in [content isKindOfClass:NSArray.class] ? content : @[]) {
                index++;
                if (![item isKindOfClass:NSDictionary.class] || ![item[@"type"] isEqual:@"tool_use"]
                    || ![item[@"name"] isEqual:tool] || ![item[@"id"] isKindOfClass:NSString.class]
                    || ![item[@"input"] isKindOfClass:NSDictionary.class] || [seen containsObject:item[@"id"]])
                    continue;
                [seen addObject:item[@"id"]];
                NSDictionary *input = item[@"input"];
                NSMutableDictionary *call = [@{@"id": item[@"id"], @"tool": tool,
                                               @"at": @(TimestampMs(entry[@"timestamp"])),
                                               @"offset": @(base + line.location),
                                               // where it is in the transcript, to order writings made together
                                               @"order": @((base + line.location) * 1000 + index)} mutableCopy];
                if ([tool isEqualToString:@"ExitPlanMode"]) {
                    call[@"title"] = HeadingOf([input[@"plan"] isKindOfClass:NSString.class] ? input[@"plan"] : @"")
                                     ?: @"Plan";
                    if ([input[@"planFilePath"] isKindOfClass:NSString.class]) call[@"path"] = input[@"planFilePath"];
                } else {
                    NSString *path = input[@"file_path"];
                    if (!KindOfFile(path)) continue;
                    call[@"path"] = path;
                    call[@"title"] = TitleOfFile(path, input[@"content"]);
                }
                [calls addObject:call];
            }
        }
    }
    [calls sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"order" ascending:YES]]];

    // The results, in one pass over the chunk: each place a call's result could be is checked against the calls asked
    // about, by the id that follows, before its line is read. Every place is checked, as other lines about a call (a
    // hook's, say) can name it before its result does.
    NSMutableDictionary *results = [NSMutableDictionary dictionary];
    NSMutableSet *ids = [waiting mutableCopy] ?: [NSMutableSet set];
    for (NSDictionary *call in calls) [ids addObject:call[@"id"]];
    NSData *marker = [@"\"tool_use_id\":\"" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *quote = [@"\"" dataUsingEncoding:NSUTF8StringEncoding];
    NSUInteger cursor = 0, lineRead = NSNotFound;
    while (ids.count && cursor < end) {
        NSRange hit = [chunk rangeOfData:marker options:0 range:NSMakeRange(cursor, end - cursor)];
        if (hit.location == NSNotFound) break;
        cursor = NSMaxRange(hit);
        NSRange close = [chunk rangeOfData:quote options:0 range:NSMakeRange(cursor, MIN(end - cursor, 200))];
        if (close.location == NSNotFound) continue;
        NSString *named = [[NSString alloc] initWithData:[chunk subdataWithRange:NSMakeRange(cursor,
                                                                    close.location - cursor)]
                                                encoding:NSUTF8StringEncoding];
        if (!named || ![ids containsObject:named]) continue;
        NSRange line;
        NSDictionary *entry = JSONLineAt(chunk, hit.location, end, &line);
        if (line.location == lineRead) continue;  // a line with several results is read once
        lineRead = line.location;
        id message = [entry isKindOfClass:NSDictionary.class] ? entry[@"message"] : nil;
        id content = [message isKindOfClass:NSDictionary.class] ? message[@"content"] : nil;
        for (NSDictionary *item in [content isKindOfClass:NSArray.class] ? content : @[]) {
            if (![item isKindOfClass:NSDictionary.class] || ![item[@"type"] isEqual:@"tool_result"]
                || ![item[@"tool_use_id"] isKindOfClass:NSString.class] || ![ids containsObject:item[@"tool_use_id"]])
                continue;
            NSString *callId = item[@"tool_use_id"];
            NSMutableDictionary *result = [@{@"ok": @(![item[@"is_error"] boolValue]),
                                             @"text": Clip(ResultText(item[@"content"]), 200)} mutableCopy];
            id published = entry[@"toolUseResult"];
            if ([published isKindOfClass:NSDictionary.class] && [published[@"url"] isKindOfClass:NSString.class]
                && [published[@"url"] hasPrefix:@"https://"])
                result[@"url"] = published[@"url"];
            results[callId] = result;
            [ids removeObject:callId];
        }
    }
    return @{@"calls": calls, @"results": results};
}

// Newest first: by when each was written, and for two written in the same second, by where they are in the transcript.
static NSArray<NSSortDescriptor *> *NewestFirst(void) {
    return @[[NSSortDescriptor sortDescriptorWithKey:@"at" ascending:NO],
             [NSSortDescriptor sortDescriptorWithKey:@"order" ascending:NO]];
}

// A call's result settles what it wrote: whether a plan was approved, and whether a file was new.
static void Settle(NSMutableDictionary *writings, NSDictionary *call, NSDictionary *result) {
    BOOL ok = [result[@"ok"] boolValue];
    if ([call[@"tool"] isEqualToString:@"ExitPlanMode"]) {
        writings[call[@"id"]][@"status"] = ok ? @"approved" : @"declined";
        return;
    }
    BOOL created = [call[@"tool"] isEqualToString:@"Artifact"]
        || [result[@"text"] hasPrefix:@"File created successfully"];
    if (!ok || !created) return;
    NSMutableDictionary *file = writings[call[@"path"]];
    if (!file) {
        file = [@{@"id": call[@"path"], @"kind": KindOfFile(call[@"path"]), @"title": call[@"title"],
                  @"path": call[@"path"], @"at": call[@"at"], @"order": call[@"order"]} mutableCopy];
        writings[call[@"path"]] = file;
    }
    if (result[@"url"]) file[@"url"] = result[@"url"];
}

// In the order they were written: the results of calls from earlier reads come before this read's calls, and each
// call's own result right after it, so a file written again later in the same read is known to be the session's.
void AddWritingNews(NSMutableDictionary *state, NSDictionary *news) {
    NSMutableDictionary *writings = state[@"writings"] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *waiting = state[@"waiting"] ?: [NSMutableDictionary dictionary];
    state[@"writings"] = writings;
    state[@"waiting"] = waiting;
    NSDictionary *results = news[@"results"];
    for (NSString *callId in waiting.allKeys) {
        if (!results[callId]) continue;
        Settle(writings, waiting[callId], results[callId]);
        [waiting removeObjectForKey:callId];
    }
    for (NSDictionary *call in news[@"calls"]) {
        if ([call[@"tool"] isEqualToString:@"ExitPlanMode"]) {
            // Each time Claude presents a plan is a version of it: the file holds only the latest, so each is
            // read back from its own call in the transcript.
            NSMutableDictionary *plan = [@{@"id": call[@"id"], @"kind": @"plan", @"title": call[@"title"],
                                           @"at": call[@"at"], @"offset": call[@"offset"], @"callId": call[@"id"],
                                           @"order": call[@"order"], @"status": @"waiting"} mutableCopy];
            if (call[@"path"]) plan[@"path"] = call[@"path"];
            writings[call[@"id"]] = plan;
        } else {
            NSMutableDictionary *known = writings[call[@"path"]];
            if (known) {  // written again: the reader shows it as it is now, and it moves up the list
                known[@"at"] = call[@"at"];
                known[@"order"] = call[@"order"];
                known[@"title"] = call[@"title"];
            }
            // Whether it's a new file is known from its result; a page published is listed whatever wrote it.
            if (known && ![call[@"tool"] isEqualToString:@"Artifact"]) continue;
        }
        if (results[call[@"id"]]) Settle(writings, call, results[call[@"id"]]);
        else waiting[call[@"id"]] = call;
    }
    // A long session keeps only its newest writings, and stops waiting on calls whose writing is gone.
    if (writings.count > kListed * 2) {
        NSArray *byAge = [writings.allValues sortedArrayUsingDescriptors:NewestFirst()];
        for (NSDictionary *old in [byAge subarrayWithRange:NSMakeRange(kListed, byAge.count - kListed)])
            [writings removeObjectForKey:old[@"id"]];
    }
    if (waiting.count > kListed * 2) [waiting removeAllObjects];
}

NSArray<NSDictionary *> *RowWritings(NSDictionary *state) {
    NSArray *byAge = [[state[@"writings"] allValues] sortedArrayUsingDescriptors:NewestFirst()];
    NSMutableArray *listed = [NSMutableArray array];
    for (NSDictionary *writing in byAge) {
        if (listed.count == kListed) break;
        NSMutableDictionary *shown = [writing mutableCopy];
        [shown removeObjectsForKeys:@[@"offset", @"callId", @"order"]];
        [listed addObject:shown];
    }
    return listed;
}

// A plan's text from the call that presented it, found again where the read left it.
static NSString *PlanText(NSString *transcriptPath, NSDictionary *plan) {
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:transcriptPath];
    if (!fh || ![plan[@"offset"] isKindOfClass:NSNumber.class]) return nil;
    [fh seekToFileOffset:[plan[@"offset"] unsignedLongLongValue]];
    NSData *chunk = [fh readDataOfLength:16 * 1024 * 1024];
    [fh closeFile];
    NSDictionary *entry = chunk.length ? JSONLineAt(chunk, 0, chunk.length, NULL) : nil;
    id message = [entry isKindOfClass:NSDictionary.class] ? entry[@"message"] : nil;
    id content = [message isKindOfClass:NSDictionary.class] ? message[@"content"] : nil;
    for (NSDictionary *item in [content isKindOfClass:NSArray.class] ? content : @[])
        if ([item isKindOfClass:NSDictionary.class] && [item[@"id"] isEqual:plan[@"callId"]]
            && [item[@"input"] isKindOfClass:NSDictionary.class] && [item[@"input"][@"plan"] isKindOfClass:NSString.class])
            return item[@"input"][@"plan"];
    return nil;
}

NSDictionary *ReadWriting(NSString *transcriptPath, NSDictionary *writing) {
    if ([writing[@"kind"] isEqual:@"plan"]) {
        NSString *text = transcriptPath ? PlanText(transcriptPath, writing) : nil;
        if (text) return @{@"text": text};
        // The transcript was rewritten since (compacted, say): the plan's file still has its latest version.
    }
    NSString *path = writing[@"path"];
    if (![path isKindOfClass:NSString.class]) return @{@"missing": @"This plan can't be found any more."};
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    if (!attributes) return @{@"missing": [NSString stringWithFormat:@"%@ isn't there any more.", path.lastPathComponent]};
    if (attributes.fileSize > kLargest)
        return @{@"missing": [NSString stringWithFormat:@"%@ is too large to show here (over 2 MB).",
                                                        path.lastPathComponent]};
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    return text ? @{@"text": text}
                : @{@"missing": [NSString stringWithFormat:@"%@ isn't text that can be shown.", path.lastPathComponent]};
}
