// Files: where Whozmove's and Claude Code's files are, and reading them: JSON, JSONL lines, times.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Files.h"
#import "Upstream.h"

// The home folder: $HOME when it's set, else the account's own. NSHomeDirectory() alone ignores $HOME, which
// tests/rows.sh points at a sample home; launchd sets it to the account's own folder for the real app. Every path
// is built from it, many times a second, and the environment doesn't change while the app runs, so it's looked
// up once.
NSString *Home(void) {
    static NSString *home;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *set = NSProcessInfo.processInfo.environment[@"HOME"];
        home = set.isAbsolutePath ? set : NSHomeDirectory();
    });
    return home;
}

NSString *ClaudeDir(NSString *sub) {
    return [Home() stringByAppendingPathComponent:[kClaudeCodeFolder stringByAppendingPathComponent:sub]];
}

// Whozmove's own files (what the hooks record, requests waiting for your OK, the log), kept apart from any
// one agent's folder so other agents can be added beside Claude. The hooks write here too and spell the
// folder out themselves (ROOT in each); tests/hooks.sh takes it from this line, so if they ever disagree
// the tests fail rather than the panel quietly showing nothing.
NSString *AppDir(NSString *sub) {
    NSString *base = [Home() stringByAppendingPathComponent:@"Library/Application Support/Whozmove"];
    return sub.length ? [base stringByAppendingPathComponent:sub] : base;
}

// Set by the print modes (main.m): what tests/rows.sh prints mustn't depend on the Mac it runs on, so a file the
// whole Mac shares, like Claude Code's managed settings, is read from the home folder in $HOME instead.
BOOL MachineFilesInHome;

// A file the whole Mac shares, by its absolute path.
NSString *MachineFile(NSString *path) {
    return MachineFilesInHome ? [Home() stringByAppendingPathComponent:path] : path;
}

id ReadJSON(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    return data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
}

// The first `max` characters of a string, without splitting an emoji or accented letter in two (half of
// one makes a string JSON can't encode).
NSString *Clip(NSString *text, NSUInteger max) {
    if (text.length <= max) return text;
    return [text substringToIndex:[text rangeOfComposedCharacterSequenceAtIndex:max].location];
}

// A transcript timestamp (ISO 8601 in UTC, with milliseconds) in ms since 1970; 0 if there isn't one.
// Called from the main thread and the transcript queue alike, so the parser is made exactly once
// (two threads making it at once would free one while the other used it).
double TimestampMs(id iso) {
    static NSISO8601DateFormatter *parser;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        parser = [NSISO8601DateFormatter new];
        parser.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    });
    NSDate *date = [iso isKindOfClass:NSString.class] ? [parser dateFromString:iso] : nil;
    return date ? date.timeIntervalSince1970 * 1000 : 0;
}

// The JSON record on the line of a JSONL chunk that contains `location`, parsed (nil if it isn't valid JSON),
// looking no further than `end`. *line, if given, is set to that line, without its newline.
id JSONLineAt(NSData *chunk, NSUInteger location, NSUInteger end, NSRange *line) {
    NSData *newline = [@"\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSRange before = [chunk rangeOfData:newline options:NSDataSearchBackwards range:NSMakeRange(0, location)];
    NSRange after = [chunk rangeOfData:newline options:0 range:NSMakeRange(location, end - location)];
    NSUInteger start = before.location == NSNotFound ? 0 : NSMaxRange(before);
    NSUInteger stop = after.location == NSNotFound ? end : after.location;
    if (line) *line = NSMakeRange(start, stop - start);
    NSData *record = [chunk subdataWithRange:NSMakeRange(start, stop - start)];
    return [NSJSONSerialization JSONObjectWithData:record options:0 error:nil];
}
