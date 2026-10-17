// Trust: whether Claude may work in a folder, as Claude Code and Claude Desktop both record it, and recording your yes.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// Claude Code's state file holds much more than this, your account among it: only the one key is read, with a JSON
// parser, and it's never logged. It's written only for a folder you've said yes to on a card, and through
// JavaScript's own JSON, as Claude Code (Node) writes it, so everything else in it stays as it was, laid out the same.
#import "Trust.h"
#import <JavaScriptCore/JavaScriptCore.h>
#include <sys/stat.h>
#import "Files.h"
#import "Git.h"
#import "Log.h"
#import "ClaudeCodeFacts.h"

static NSString *StatePath(void) {
    return [Home() stringByAppendingPathComponent:kClaudeCodeState];
}

// The folders whose trust covers `folder`, by their real paths, as both apps key them: the folder itself, the checkout
// it's in and the repo that checkout belongs to (so a worktree is covered by its repo), and every folder above it.
static NSArray<NSString *> *Covering(NSString *folder) {
    NSMutableOrderedSet<NSString *> *paths = [NSMutableOrderedSet orderedSet];
    NSString *real = RealPath(folder);
    NSDictionary *git = GitInfo(real);
    for (NSString *path in @[real, git[@"root"] ?: @"", git[@"mainRoot"] ?: @""])
        if (path.length) [paths addObject:RealPath(path)];
    for (NSString *path = real.stringByDeletingLastPathComponent; path.length > 1;
         path = path.stringByDeletingLastPathComponent)
        [paths addObject:path];
    return paths.array;
}

BOOL FolderTrusted(NSString *folder) {
    if (!folder.isAbsolutePath) return NO;
    NSDictionary *state = ReadJSON(StatePath());
    NSDictionary *projects = [state isKindOfClass:NSDictionary.class] ? state[@"projects"] : nil;
    if (![projects isKindOfClass:NSDictionary.class]) return NO;
    for (NSString *path in Covering(folder)) {
        NSDictionary *project = projects[path];
        if ([project isKindOfClass:NSDictionary.class] && [project[kClaudeCodeTrustKey] isEqual:@YES]) return YES;
    }
    return NO;
}

// Takes the lock both apps take while they write the state file: the folder beside it that only one can make. Waits up
// to 5s for whoever has it; one 10s old or more was left by a writer that's gone (they mark theirs as they go), and is
// cleared. YES once it's ours.
static BOOL TakeLock(NSString *lock) {
    for (int tries = 0; tries < 50; tries++) {
        if (mkdir(lock.fileSystemRepresentation, 0700) == 0) return YES;
        if (errno != EEXIST) return NO;
        NSDate *marked = [NSFileManager.defaultManager attributesOfItemAtPath:lock error:nil].fileModificationDate;
        if (marked && -marked.timeIntervalSinceNow >= 10) [NSFileManager.defaultManager removeItemAtPath:lock error:nil];
        else usleep(100 * 1000);
    }
    return NO;
}

// The state file with the folder's project marked trusted (added with the defaults Claude starts a project with, if
// it isn't there yet), replacing the file in one step so neither app reads it half-written, and keeping who may read
// it. Nil once done or if it already was, else why not. Call with the lock held.
static NSString *WriteTrust(NSString *path, NSString *folder) {
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!text) return @"Claude Code hasn't been set up on this Mac yet: start it once first";
    JSContext *js = [JSContext new];
    JSValue *mark = [js evaluateScript:@"(function (text, folder, key, defaults) { const s = JSON.parse(text);"
                                        "  if (!s || typeof s !== 'object' || Array.isArray(s)) return undefined;"
                                        "  if (!s.projects || typeof s.projects !== 'object') s.projects = {};"
                                        "  const p = s.projects[folder];"
                                        "  if (p && typeof p === 'object' && p[key] === true) return null;"
                                        "  s.projects[folder] = { ...(p && typeof p === 'object' ? p : defaults),"
                                        "                         [key]: true };"
                                        "  return JSON.stringify(s, null, 2) + (text.endsWith('\\n') ? '\\n' : ''); })"];
    JSValue *marked = [mark callWithArguments:@[text, folder, kClaudeCodeTrustKey, ClaudeCodeProjectDefaults()]];
    if (js.exception || marked.isUndefined) return @"Claude Code's state file couldn't be read, so nothing was changed";
    if (marked.isNull) return nil;
    NSNumber *mode = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil][NSFilePosixPermissions];
    if (![[marked.toString dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path options:NSDataWritingAtomic error:nil])
        return @"Claude Code's state file couldn't be written";
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: mode ?: @0600} ofItemAtPath:path error:nil];
    return nil;
}

NSString *TrustFolder(NSString *folder) {
    if (!folder.isAbsolutePath) return @"That isn't a folder";
    NSString *path = StatePath(), *lock = [path stringByAppendingString:kClaudeCodeStateLock];
    if (!TakeLock(lock)) return @"Claude was busy saving its settings: try again";
    NSString *why = nil;
    @try {
        why = WriteTrust(path, RealPath(folder));
    } @finally {
        rmdir(lock.fileSystemRepresentation);
    }
    PanelLog(@"trust for %@: %@", RealPath(folder), why ?: @"recorded");
    return why;
}
