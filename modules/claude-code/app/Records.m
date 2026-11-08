// Records: where Claude Code keeps what its sessions were told and read (Records.h).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <sys/stat.h>
#import "Records.h"
#import "ClaudeCodeFacts.h"
#import "Files.h"
#import "Text.h"
#import "Files.h"

// The most files an instruction folder (a project's skills, say) is looked through for, and the largest instruction
// file read for its imports.
static const NSUInteger kMostInFolder = 500, kLargestToImport = 256 * 1024;

// A path with its . and .. worked out, as it's written: never with /private taken off it, as NSString's own
// standardizing does, so it's the same path as the home folder's own, and a file found two ways is one.
static NSString *Plain(NSString *path) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *part in [path componentsSeparatedByString:@"/"]) {
        if (!part.length || [part isEqualToString:@"."]) continue;
        if ([part isEqualToString:@".."]) [parts removeLastObject];
        else [parts addObject:part];
    }
    return [@"/" stringByAppendingString:[parts componentsJoinedByString:@"/"]];
}

// A regular file, or a link to one: never a device or a pipe (an import of /dev/zero, a FIFO in a skills folder), which
// reading would never finish.
static BOOL IsFile(NSString *path) {
    struct stat info;
    return stat(path.fileSystemRepresentation, &info) == 0 && S_ISREG(info.st_mode);
}

// The folder each project's sessions ran in, as its newest transcript's first lines say (its `cwd`).
static NSArray<NSString *> *SessionFolders(void) {
    NSString *projects = ClaudeDir(kClaudeCodeTranscripts);
    NSMutableOrderedSet<NSString *> *folders = [NSMutableOrderedSet orderedSet];
    NSFileManager *files = NSFileManager.defaultManager;
    for (NSString *project in [files contentsOfDirectoryAtPath:projects error:nil] ?: @[]) {
        NSString *newest = nil;
        NSDate *newestAt = nil;
        NSString *inside = [projects stringByAppendingPathComponent:project];
        for (NSString *name in [files contentsOfDirectoryAtPath:inside error:nil] ?: @[]) {
            if (![name.pathExtension isEqualToString:@"jsonl"]) continue;
            NSString *path = [inside stringByAppendingPathComponent:name];
            NSDate *at = [files attributesOfItemAtPath:path error:nil].fileModificationDate;
            if (!newestAt || [at compare:newestAt] == NSOrderedDescending) newest = path, newestAt = at;
        }
        NSFileHandle *handle = newest ? [NSFileHandle fileHandleForReadingAtPath:newest] : nil;
        NSData *start = [handle readDataUpToLength:64 * 1024 error:nil];
        [handle closeFile];
        NSString *text = start ? [[NSString alloc] initWithData:start encoding:NSUTF8StringEncoding] : nil;
        for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
            id record = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0
                                                          error:nil];
            NSString *cwd = [record isKindOfClass:NSDictionary.class] ? record[@"cwd"] : nil;
            if ([cwd isKindOfClass:NSString.class] && [cwd hasPrefix:@"/"]) {
                [folders addObject:cwd];
                break;
            }
        }
    }
    return folders.array;
}

// Every file in an instruction folder, at any depth, up to the most worth looking through.
static void FilesIn(NSString *folder, NSMutableOrderedSet<NSString *> *into) {
    NSUInteger count = 0;
    for (NSURL *url in [NSFileManager.defaultManager enumeratorAtURL:[NSURL fileURLWithPath:folder]
                            includingPropertiesForKeys:nil options:0 errorHandler:nil]) {
        if (!IsFile(url.path)) continue;
        [into addObject:url.path];
        if (++count >= kMostInFolder) return;
    }
}

// What Claude Code reads as instructions for sessions in these folders, beyond what's in ClaudeDir: the instruction
// files in each folder and every one above it, AGENTS.md only where there's no CLAUDE.md, the instruction folders in
// each one's kClaudeCodeProjectFolder, and what any of them imports, kClaudeCodeImportHops deep.
static NSArray<NSString *> *InstructionsFor(NSArray<NSString *> *folders) {
    NSMutableOrderedSet<NSString *> *files = [NSMutableOrderedSet orderedSet];
    NSString *mine = Plain(ClaudeDir(@""));
    for (NSString *folder in folders) {
        NSMutableArray<NSString *> *above = [NSMutableArray array];
        for (NSString *at = Plain(folder); at.length > 1; at = at.stringByDeletingLastPathComponent)
            [above addObject:at];
        BOOL claude = NO;
        for (NSString *at in above)
            for (NSString *name in kClaudeCodeInstructions) {
                NSString *path = [at stringByAppendingPathComponent:name];
                if (IsFile(path) && ![Plain(path) hasPrefix:[mine stringByAppendingString:@"/"]]) {
                    [files addObject:path];
                    claude = YES;
                }
            }
        for (NSString *at in above) {
            if (!claude)
                for (NSString *name in kClaudeCodeAgentsInstructions) {
                    NSString *path = [at stringByAppendingPathComponent:name];
                    if (IsFile(path)) [files addObject:path];
                }
            NSString *own = [at stringByAppendingPathComponent:kClaudeCodeProjectFolder];
            if ([Plain(own) isEqualToString:Plain(mine)]) continue;
            for (NSString *each in kClaudeCodeInstructionFolders)
                FilesIn([own stringByAppendingPathComponent:each], files);
        }
    }
    // Their imports: an `@path` at a word's start, from the importing file's folder, absolute or from ~; never a
    // folder's.
    static NSRegularExpression *import;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        import = [NSRegularExpression regularExpressionWithPattern:@"(?:^|\\s)@([~./A-Za-z0-9_][^\\s`]*)" options:0
                                                             error:nil];
    });
    NSArray<NSString *> *hop = files.array;
    for (NSInteger depth = 0; depth < kClaudeCodeImportHops && hop.count; depth++) {
        NSMutableArray<NSString *> *next = [NSMutableArray array];
        for (NSString *file in hop) {
            NSDictionary *info = [NSFileManager.defaultManager attributesOfItemAtPath:file error:nil];
            if (info.fileSize > kLargestToImport) continue;
            NSString *text = [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil];
            for (NSTextCheckingResult *match in [import matchesInString:text ?: @"" options:0
                                                                 range:NSMakeRange(0, text.length)]) {
                NSString *path = [text substringWithRange:[match rangeAtIndex:1]];
                path = [path hasPrefix:@"~/"] ? [Home() stringByAppendingPathComponent:[path substringFromIndex:2]]
                     : [path hasPrefix:@"/"] ? path
                     : [file.stringByDeletingLastPathComponent stringByAppendingPathComponent:path];
                path = Plain(path);
                if (IsFile(path) && ![files containsObject:path]) {
                    [files addObject:path];
                    [next addObject:path];
                }
            }
        }
        hop = next;
    }
    return files.array;
}

NSArray<NSDictionary *> *ClaudeRecords(void) {
    NSString *projects = ClaudeDir(kClaudeCodeTranscripts);
    NSMutableArray *records = [@[
        @{@"path": projects, @"kind": @"conversation", @"format": @"jsonl", @"deep": @YES},
        // A tool's long output is a file of its own in the folder named for it, beside its session's transcript.
        @{@"path": projects, @"kind": @"conversation", @"format": @"text", @"deep": @YES, @"within": kClaudeCodeToolResults},
        @{@"path": ClaudeDir(kClaudeCodePromptHistory), @"kind": @"prompts", @"format": @"jsonl", @"deep": @NO},
        @{@"path": ClaudeDir(kClaudeCodePastes), @"kind": @"pastes", @"format": @"text", @"deep": @YES},
        @{@"path": ClaudeDir(kClaudeCodeEditCopies), @"kind": @"edits", @"format": @"text", @"deep": @YES},
        // What it reads into sessions as their instructions: yours, your organisation's, each project's memory, and
        // your plugins'.
        @{@"path": ClaudeDir(kClaudeCodeUserInstructions), @"kind": @"instructions", @"format": @"text", @"deep": @NO},
        @{@"path": kClaudeCodeManagedInstructions, @"kind": @"instructions", @"format": @"text", @"deep": @NO},
        @{@"path": projects, @"kind": @"instructions", @"format": @"text", @"deep": @YES, @"within": kClaudeCodeMemory},
    ] mutableCopy];
    for (NSString *each in kClaudeCodeInstructionFolders)
        [records addObject:@{@"path": ClaudeDir(each), @"kind": @"instructions", @"format": @"text", @"deep": @YES}];
    for (NSString *each in @[@"skills", @"agents", @"commands"])
        [records addObject:@{@"path": ClaudeDir(kClaudeCodePluginCache), @"kind": @"instructions", @"format": @"text",
                             @"deep": @YES, @"within": each}];
    // And those of the folders its sessions ran in, and up from them.
    for (NSString *file in InstructionsFor(SessionFolders()))
        [records addObject:@{@"path": file, @"kind": @"instructions", @"format": @"text", @"deep": @NO}];
    return records;
}

// The session a file's folder names, as Claude Code keeps them: a transcript is <project>/<session>.jsonl, what's
// beside it in <project>/<session>/ (its sub-agents' and its tools' long outputs), and the copies of edited files are
// in file-history/<session>/.
static NSString *SessionOf(NSString *path) {
    NSArray<NSString *> *parts = path.pathComponents;
    NSString *projects = ClaudeDir(kClaudeCodeTranscripts), *copies = ClaudeDir(kClaudeCodeEditCopies);
    NSString *session = nil;
    if ([path hasPrefix:[projects stringByAppendingString:@"/"]]) {
        NSUInteger at = projects.pathComponents.count;  // the project's folder; the session comes after it
        if (parts.count == at + 2) session = parts[at + 1].stringByDeletingPathExtension;
        else if (parts.count > at + 2) session = parts[at + 1];
    } else if ([path hasPrefix:[copies stringByAppendingString:@"/"]] && parts.count > copies.pathComponents.count + 1)
        session = parts[copies.pathComponents.count];
    // A session's id is a UUID, which tells it from the project's other folders (its memory, say).
    return session && [[NSUUID alloc] initWithUUIDString:session] ? session : nil;
}

// The file a copy in kClaudeCodeEditCopies/<session>/ is of, as the session's transcript names it in its snapshot
// lines, a path from the folder the session ran in worked out from there; nil when it doesn't say. Each transcript is
// read again only once it has grown, and only the names and paths are kept, in memory.
static NSString *CopiedFile(NSString *path) {
    NSString *session = SessionOf(path), *copies = ClaudeDir(kClaudeCodeEditCopies);
    if (!session || ![path.stringByDeletingLastPathComponent isEqualToString:
                      [copies stringByAppendingPathComponent:session]])
        return nil;
    static NSMutableDictionary<NSString *, NSDictionary *> *read;  // session: {transcript, size, files: {name: path}}
    static dispatch_once_t once;
    dispatch_once(&once, ^{ read = [NSMutableDictionary dictionary]; });
    @synchronized (read) {
        NSString *transcript = read[session][@"transcript"];
        if (!transcript) {
            NSString *projects = ClaudeDir(kClaudeCodeTranscripts), *name = [session stringByAppendingString:@".jsonl"];
            for (NSString *project in [NSFileManager.defaultManager contentsOfDirectoryAtPath:projects error:nil] ?: @[])
                if (IsFile([[projects stringByAppendingPathComponent:project] stringByAppendingPathComponent:name])) {
                    transcript = [[projects stringByAppendingPathComponent:project] stringByAppendingPathComponent:name];
                    break;
                }
        }
        if (!transcript) return nil;
        struct stat info;
        if (stat(transcript.fileSystemRepresentation, &info) != 0) return nil;
        if ([read[session][@"size"] longLongValue] != info.st_size) {
            NSData *data = [NSData dataWithContentsOfFile:transcript options:NSDataReadingMappedIfSafe error:nil];
            NSMutableDictionary<NSString *, NSString *> *files = [NSMutableDictionary dictionary];
            NSString *folder = nil;
            const char *bytes = data.bytes, *end = bytes + data.length, *at = bytes;
            const char *mark = kClaudeCodeSnapshotLine.UTF8String;
            while (at < end) {
                const char *next = memchr(at, '\n', (size_t)(end - at)) ?: end;
                // Only a snapshot line, and the first that says where the session ran, are read as JSON.
                BOOL snapshot = memmem(at, (size_t)(next - at), mark, strlen(mark)) != NULL;
                if (snapshot || !folder) {
                    @autoreleasepool {
                        NSData *one = [NSData dataWithBytesNoCopy:(void *)at length:(NSUInteger)(next - at)
                                                     freeWhenDone:NO];
                        NSDictionary *line = AsRecord([NSJSONSerialization JSONObjectWithData:one options:0 error:nil]);
                        id cwd = line[@"cwd"];
                        if (!folder && [cwd isKindOfClass:NSString.class] && [cwd hasPrefix:@"/"]) folder = cwd;
                        NSDictionary *backups = [line[@"type"] isEqual:kClaudeCodeSnapshotLine]
                            ? AsRecord(AsRecord(line[@"snapshot"])[@"trackedFileBackups"]) : nil;
                        for (NSString *file in backups) {
                            id copy = AsRecord(backups[file])[@"backupFileName"];
                            if ([copy isKindOfClass:NSString.class] && [file isKindOfClass:NSString.class])
                                files[copy] = file;
                        }
                    }
                }
                at = next + 1;
            }
            NSMutableDictionary<NSString *, NSString *> *whole = [NSMutableDictionary dictionary];
            for (NSString *copy in files) {
                NSString *file = files[copy];
                if (![file hasPrefix:@"/"]) file = folder ? [folder stringByAppendingPathComponent:file] : nil;
                if (file) whole[copy] = Plain(file);
            }
            read[session] = @{@"transcript": transcript, @"size": @(info.st_size), @"files": whole};
        }
        return read[session][@"files"][path.lastPathComponent];
    }
}

NSDictionary *ClaudeRecordAbout(NSString *path, NSDictionary *line) {
    NSMutableDictionary *about = [NSMutableDictionary dictionary];
    NSString *session = SessionOf(path);
    if (session) about[@"session"] = session;
    if ([path hasPrefix:[ClaudeDir(kClaudeCodePastes) stringByAppendingString:@"/"]]) about[@"how"] = @"sent";
    if ([path hasPrefix:[ClaudeDir(kClaudeCodeEditCopies) stringByAppendingString:@"/"]]
        || [path.pathComponents containsObject:kClaudeCodeToolResults])
        about[@"how"] = @"read";
    NSString *copied = line ? nil : CopiedFile(path);
    if (copied) about[@"copyOf"] = copied;
    if (![line isKindOfClass:NSDictionary.class]) return about;
    // A transcript's line names its session and the folder it ran in; one of the prompts you typed, the project's.
    id said = line[@"sessionId"], folder = line[@"cwd"] ?: line[@"project"];
    if ([said isKindOfClass:NSString.class] && [[NSUUID alloc] initWithUUIDString:said]) about[@"session"] = said;
    if ([folder isKindOfClass:NSString.class] && [folder hasPrefix:@"/"]) about[@"folder"] = folder;
    if ([path isEqualToString:ClaudeDir(kClaudeCodePromptHistory)]) about[@"how"] = @"sent";
    // A transcript's message: Claude's (assistant), or one sent to it (user): a tool's result when it carries one, a
    // line you ran with ! (and what it printed, read), a sub-agent's prompt (on its sidechain: the agent's own words),
    // else what you wrote; a compaction's summary (marked) and what Claude Code added (meta), on a sidechain as
    // anywhere else, say nobody's.
    id type = line[@"type"], message = line[@"message"];
    id content = [message isKindOfClass:NSDictionary.class] ? message[@"content"] : nil;
    if ([type isEqual:@"assistant"]) about[@"how"] = @"wrote";
    else if ([type isEqual:@"user"]) {
        BOOL result = line[@"toolUseResult"] != nil;
        if ([content isKindOfClass:NSArray.class])
            for (id part in content)
                if ([part isKindOfClass:NSDictionary.class] && [part[@"type"] isEqual:@"tool_result"]) result = YES;
        // A picture or a document in it, one you pasted or a tool returned (in its result's own parts).
        if ([content isKindOfClass:NSArray.class])
            for (id part in content) {
                if (![part isKindOfClass:NSDictionary.class]) continue;
                NSArray *inside = [part[@"content"] isKindOfClass:NSArray.class] ? part[@"content"] : @[];
                for (id each in [inside arrayByAddingObject:part])
                    if ([each isKindOfClass:NSDictionary.class] && [each[@"type"] isKindOfClass:NSString.class]
                        && [kClaudeCodePictureParts containsObject:each[@"type"]])
                        about[@"picture"] = @YES;
            }
        // What it says as text, for the lines Claude Code marks as yours though they aren't messages.
        NSMutableString *text = [NSMutableString string];
        if ([content isKindOfClass:NSString.class]) [text appendString:content];
        else if ([content isKindOfClass:NSArray.class])
            for (id part in content)
                if ([part isKindOfClass:NSDictionary.class] && [part[@"text"] isKindOfClass:NSString.class])
                    [text appendString:part[@"text"]];
        // Claude Code puts its marks at the start: a mark anywhere else is only words about one.
        NSString *start = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        BOOL output = NO;
        for (NSString *mark in kClaudeCodeShellOutputs) if ([start hasPrefix:mark]) output = YES;
        BOOL sidechain = [line[@"isSidechain"] boolValue], summary = [line[@"isCompactSummary"] boolValue];
        // A compaction's summary carries what came before: never where anything was first said.
        if (summary) about[@"summary"] = @YES;
        if (result) about[@"how"] = @"read";
        else if ([start hasPrefix:kClaudeCodeShellInput]) about[@"how"] = @"sent";  // a line you ran with !
        else if (output) about[@"how"] = @"read";
        else if (sidechain && !summary && ![line[@"isMeta"] boolValue]) {
            about[@"how"] = @"wrote";  // a sub-agent's prompt: the agent's own words
            about[@"toAgent"] = @YES;
        }
        else if (!summary && ![line[@"isMeta"] boolValue]) about[@"how"] = @"sent";
    } else if ([type isEqual:kClaudeCodeAttachmentLine]) {
        // What you typed while Claude worked, kept as an attachment until it's sent with the next turn: yours, unless
        // it came from somewhere else (another session, a task finishing, a plugin) or Claude Code added it (meta).
        NSDictionary *attached = AsRecord(line[@"attachment"]);
        id origin = AsRecord(attached[@"origin"])[@"kind"];
        if ([attached[@"type"] isEqual:kClaudeCodeQueuedAttachment] && ![attached[@"isMeta"] boolValue]
            && (!attached[@"origin"] || [origin isEqual:kClaudeCodeTypedOrigin]))
            about[@"how"] = @"sent";
    }
    return about;
}

NSString *ClaudeClearCommand(NSString *folder) {
    if (![folder hasPrefix:@"/"]) return nil;
    return [NSString stringWithFormat:@"%@ %@ %@", kClaudeCodeCommand, kClaudeCodeClearCommand, ShellWord(folder)];
}
