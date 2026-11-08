// ClaudeProgram: Claude Code's own program, told by its signature.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "ClaudeProgram.h"
#import "ClaudeCodeFacts.h"
#import "Processes.h"
#import "ClaudeSessions.h"
#import "Signature.h"

// Whether a signature says it's Claude Code's, by its identifier and team: what it says, not yet that it's true.
static BOOL NamesClaudeCode(NSDictionary *signature) {
    return [signature[@"identifier"] isEqual:kClaudeCodeSigningIdentifier]
        && [signature[@"team"] isEqual:kClaudeCodeTeam];
}

// Claude Code's own build, signed by Anthropic with Apple's Developer ID, as the system keeps its signature while it
// runs. It's read from that copy, not the program's file: an update deletes the version a session was started with,
// and the session goes on running it.
static BOOL SignedByAnthropic(pid_t pid) {
    NSDictionary *signature = RunningSignature(pid);
    return [signature[@"valid"] boolValue] && [signature[@"developerID"] boolValue] && NamesClaudeCode(signature);
}

ClaudeProgram ClaudeProgramFrom(NSString *path, NSArray<NSString *> *arguments, BOOL hasRecord, BOOL signedByAnthropic,
                                NSString *standIn) {
    if (standIn.length && [path isEqualToString:standIn]) return ClaudeProgramSigned;
    if ([path.lastPathComponent isEqualToString:kClaudeCodeNodeProgram]) {
        for (NSString *argument in arguments)
            if ([argument hasSuffix:kClaudeCodeNodeEntry]) return ClaudeProgramByPath;
        // An older one sets its title over its arguments as it starts, so its own record in the registry tells it
        // instead. Anything can write one, but counting a process as this only ever refuses or holds back: npm's Node
        // never asks.
        return hasRecord ? ClaudeProgramByPath : ClaudeProgramNone;
    }
    return signedByAnthropic ? ClaudeProgramSigned : ClaudeProgramNone;
}

// What the system says of a process, read only as far as ClaudeProgramFrom needs it. `keep` says whether the answer
// holds for the process's life: one told by a record, which may come later, doesn't.
static ClaudeProgram ProgramNow(pid_t pid, NSString *standIn, BOOL *keep) {
    NSString *path = ProcessPath(pid);
    BOOL node = [path.lastPathComponent isEqualToString:kClaudeCodeNodeProgram];
    NSArray<NSString *> *arguments = node ? ProcessArguments(pid) : @[];
    BOOL byArguments = NO;
    for (NSString *argument in arguments) byArguments = byArguments || [argument hasSuffix:kClaudeCodeNodeEntry];
    *keep = !node || byArguments;
    BOOL standing = standIn.length && [path isEqualToString:standIn];
    return ClaudeProgramFrom(path, arguments, node && !byArguments && SessionOfProcess(pid) != nil,
                             !node && !standing && SignedByAnthropic(pid), standIn);
}

ClaudeProgram ClaudeProgramOf(pid_t pid, NSString *standIn) {
    static NSMutableDictionary<NSString *, NSNumber *> *known;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ known = [NSMutableDictionary dictionary]; });
    long long started = pid > 0 ? ProcessStartedAt(pid) : 0;
    if (!started) return ClaudeProgramNone;
    NSString *key = [NSString stringWithFormat:@"%d %lld %@", pid, started, standIn ?: @""];
    @synchronized (known) {
        if (known[key]) return known[key].integerValue;
    }
    BOOL keep = YES;
    ClaudeProgram program = ProgramNow(pid, standIn, &keep);
    // Kept only while it's the process it was, before and after: a later one given its pid is never taken for it.
    if (ProcessStartedAt(pid) != started) return ClaudeProgramNone;
    if (!keep) return program;
    @synchronized (known) {
        if (known.count > 512) [known removeAllObjects];
        known[key] = @(program);
    }
    return program;
}

// The cause, and whether it's the last case, any other program, which the ask's reason says more of.
static NSString *CauseOf(pid_t pid, ClaudeProgram program, BOOL *other) {
    *other = NO;
    if (program == ClaudeProgramSigned) return nil;
    if (program == ClaudeProgramByPath)
        return [NSString stringWithFormat:@"it runs an older Claude Code from npm, run by Node, which no signature can "
                                          @"check: update Claude Code (npm's is its own signed build from %@ on)",
                                          kClaudeCodeNpmSignedSince];
    NSDictionary *signature = RunningSignature(pid);
    if (NamesClaudeCode(signature))
        return [NSString stringWithFormat:@"its signature names Claude Code, but Whozmove couldn't prove it's "
                                          @"Anthropic's (%@): if it's Claude Code's own build, Whozmove may need "
                                          @"updating", signature[@"why"] ?: @"not checked"];
    *other = YES;
    return @"it isn't Claude Code's own program, signed by Anthropic";
}

NSString *ClaudeProgramCause(pid_t pid, ClaudeProgram program) {
    BOOL other = NO;
    return CauseOf(pid, program, &other);
}

NSString *ClaudeProgramWhyNot(pid_t pid, ClaudeProgram program) {
    BOOL other = NO;
    NSString *cause = CauseOf(pid, program, &other);
    if (program == ClaudeProgramByPath) return [cause stringByAppendingString:@", then ask again"];
    return other ? [cause stringByAppendingString:@": only Claude Code itself can ask"] : cause;
}

BOOL ClaudeProgramMayBe(NSString *name, NSString *standIn) {
    if ([@[kClaudeCodeProgram, kClaudeCodeNpmProgram, kClaudeCodeNodeProgram] containsObject:name]) return YES;
    if ([name rangeOfString:kClaudeCodeVersionName options:NSRegularExpressionSearch].location != NSNotFound) return YES;
    // The system keeps 16 letters of a name.
    NSString *stand = standIn.lastPathComponent;
    return stand.length && [name isEqualToString:stand.length > 16 ? [stand substringToIndex:16] : stand];
}
