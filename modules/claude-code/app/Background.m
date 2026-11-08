// Background: the jobs a session's agent still runs in the background after its turn, from its hook's record.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Background.h"
#import "Row.h"
#import "Files.h"
#import "Processes.h"
#import "ClaudeCodeFacts.h"
#import "Task.h"
#import "Log.h"
#import "Module.h"

// Whether one of the jobs the hook listed is plainly over, though no event has said so: it was last noted before the
// session's process started, so it was the earlier process's (a conversation carried on in a new one keeps its record,
// and Claude Code lists again at its next stop the jobs it carried on); a shell command, once the session is at its
// prompt and its registry no longer says one runs (while Claude works or asks you something, it says only that, so the
// hook's list stands until the turn's stop puts it right); or an agent whose own record says it has finished, read only
// for the agents listed, and parsed again only once it changes. `registered` is the process's file in the registry.
static BOOL Over(NSDictionary *job, NSString *jobId, NSDictionary *registered, NSString *transcript) {
    NSString *type = AsText(job[@"type"]);
    double noted = MAX(AsNumber(job[@"startedAt"]).doubleValue, AsNumber(job[@"listedAt"]).doubleValue);
    double began = AsNumber(registered[@"startedAt"]).doubleValue;
    if (began && noted < began) return YES;
    if ([type isEqual:kClaudeCodeJobShell]) return [registered[@"status"] isEqual:@"idle"];
    NSString *record = [type isEqual:kClaudeCodeJobAgent] ? ClaudeAgentRecordPath(transcript, jobId) : nil;
    return record && ClaudeAgentFinished(AsRecord(ReadJSONKept(record)));
}

// The script as the command names it: the plugin's root as Claude Code writes it, or one version's copy in `copies` by
// its real path (with ~ for the home folder), quoted or not; no for anything else. The shell reads each spelling its
// own way, so each is taken only where the shell would run that very file: `${CLAUDE_PLUGIN_ROOT}` isn't expanded in
// single quotes, and ~ only when it isn't quoted at all.
static BOOL IsOwnScript(NSString *word, NSString *copies) {
    unichar quote = 0;
    NSString *first = word.length > 1 ? [word substringToIndex:1] : @"";
    if (([first isEqual:@"\""] || [first isEqual:@"'"]) && [word hasSuffix:first]) {
        quote = [first characterAtIndex:0];
        word = [word substringWithRange:NSMakeRange(1, word.length - 2)];
    }
    NSCharacterSet *quotes = [NSCharacterSet characterSetWithCharactersInString:@"\"'"];
    if ([word rangeOfCharacterFromSet:quotes].location != NSNotFound) return NO;
    if ([word isEqualToString:[kClaudePluginRootWord stringByAppendingPathComponent:kWhozmoveAskScript]])
        return quote != '\'';
    if (!quote && [word hasPrefix:@"~/"]) word = [Home() stringByAppendingPathComponent:[word substringFromIndex:2]];
    if (!copies.length || ![word hasPrefix:[copies stringByAppendingString:@"/"]]) return NO;
    NSArray<NSString *> *rest = [[word substringFromIndex:copies.length + 1] componentsSeparatedByString:@"/"];
    NSArray<NSString *> *script = [kWhozmoveAskScript componentsSeparatedByString:@"/"];
    if (rest.count != script.count + 1) return NO;
    // A version's folder is named in plain characters, so nothing in it is expanded or climbs out of the copies.
    static NSCharacterSet *notPlain;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // ASCII letters and digits only, by their ranges, and the three marks a version's name may have.
        NSMutableCharacterSet *plain = [NSMutableCharacterSet characterSetWithCharactersInString:@"._-"];
        [plain addCharactersInRange:NSMakeRange('a', 26)];
        [plain addCharactersInRange:NSMakeRange('A', 26)];
        [plain addCharactersInRange:NSMakeRange('0', 10)];
        notPlain = plain.invertedSet;
    });
    NSString *version = rest.firstObject;
    if (!version.length || [version isEqual:@"."] || [version isEqual:@".."] ||
        [version rangeOfCharacterFromSet:notPlain].location != NSNotFound) return NO;
    return [[rest subarrayWithRange:NSMakeRange(1, script.count)] isEqualToArray:script];
}

// Each module's background waits, kept once given, for every read of the rows on their queue: under a lock, as the
// main thread gives them.
static NSArray<NSArray<NSString *> *> *KeptWaits;

void KeepOwnWaits(NSArray<id> *modules) {
    NSMutableArray<NSArray<NSString *> *> *waits = [NSMutableArray array];
    for (id<BackgroundWaits> module in modules) {
        if (![module conformsToProtocol:@protocol(BackgroundWaits)]) continue;
        for (NSArray<NSString *> *wait in [module backgroundWaits] ?: @[]) {
            // The ask's word, then only flags, so nothing in a wait names a program; a second command on a line of its
            // own is kept out by the hook's word that the command is recorded exactly (ClaudeJobIsOwnWait).
            BOOL flags = [wait isKindOfClass:NSArray.class] && wait.count > 0;
            for (NSUInteger i = 0; flags && i < wait.count; i++)
                flags = [wait[i] isKindOfClass:NSString.class] && [wait[i] length] > 0
                    && (i == 0 || ([wait[i] hasPrefix:@"--"] && [wait[i] length] > 2));
            if (flags) [waits addObject:[wait copy]];
            else PanelLog(@"a module's background wait isn't a word and flags, so it stays shown: %lu words",
                          (unsigned long)([wait isKindOfClass:NSArray.class] ? wait.count : 0));
        }
    }
    @synchronized(NSArray.class) {
        KeptWaits = [waits copy];
    }
}

NSArray<NSArray<NSString *> *> *OwnWaits(void) {
    @synchronized(NSArray.class) {
        return KeptWaits ?: @[];
    }
}

BOOL ClaudeJobIsOwnWait(NSString *command, BOOL exact, NSString *copies, NSArray<NSArray<NSString *> *> *waits) {
    // Just as written: the record joins a command's lines, so only its hook's word that it changed nothing shows there
    // was no second command.
    if (!command.length || !exact) return NO;
    // One plain command: nothing that runs a second one, pipes, redirects or substitutes.
    for (NSString *mark in @[@";", @"&", @"|", @"<", @">", @"`", @"$(", @"\n", @"\r", @"\\"])
        if ([command containsString:mark]) return NO;
    NSMutableArray<NSString *> *words = [NSMutableArray array];
    NSCharacterSet *blanks = [NSCharacterSet characterSetWithCharactersInString:@" \t"];
    for (NSString *word in [command componentsSeparatedByCharactersInSet:blanks])
        if (word.length) [words addObject:word];
    if (words.count < 2 || !IsOwnScript(words.firstObject, copies)) return NO;
    NSArray<NSString *> *rest = [words subarrayWithRange:NSMakeRange(1, words.count - 1)];
    // Nothing after the script may name anything else ($, quotes): only the wait words, word for word.
    for (NSArray<NSString *> *wait in waits)
        if ([wait isEqualToArray:rest]) return YES;
    return NO;
}

NSArray<NSDictionary *> *RunningBackground(Row *row, NSDictionary *record) {
    NSDictionary *jobs = AsRecord(record[@"background"]);
    // They end with the session's process. Its file in the registry is the one its row was read from this second, kept
    // as it was then (ReadJSONKept), so reading it again here costs nothing; it says what the row's status can't, as
    // that takes Claude Code's shell status as idle.
    if (!jobs.count || row.pid <= 0 || [row.status isEqual:@"closed"] || !ProcessAlive(row.pid)) return nil;
    NSString *file = [ClaudeDir(kClaudeCodeRegistry) stringByAppendingPathComponent:
                                                         [NSString stringWithFormat:@"%d.json", row.pid]];
    NSDictionary *registered = AsRecord(ReadJSONKept(file));
    if (![AsText(registered[@"sessionId"]) isEqual:row.sessionId]) return nil;
    NSString *transcript = AsText(record[@"transcriptPath"]);
    NSMutableArray<NSDictionary *> *running = [NSMutableArray array];
    NSString *copies = WhozmovePluginCopies();
    NSArray<NSArray<NSString *> *> *waits = OwnWaits();
    for (NSString *jobId in jobs) {
        NSDictionary *job = AsRecord(jobs[jobId]);
        NSString *type = AsText(job[@"type"]);
        // Claude Code's own housekeeping isn't the session's work. Its ids are plain (TaskIdPlain), as the hook keeps
        // them: one that isn't came from elsewhere.
        if (!job || !TaskIdPlain(jobId) || !ClaudeJobShown(type) || Over(job, jobId, registered, transcript)) continue;
        // Whozmove's own wait isn't the session's work either: its row says what it waits on instead.
        BOOL exact = [job[@"exact"] isEqual:@YES];
        if ([type isEqual:kClaudeCodeJobShell] && ClaudeJobIsOwnWait(AsText(job[@"command"]), exact, copies, waits))
            continue;
        NSMutableDictionary *shown = [@{@"what": AsText(job[@"what"]) ?: @"",
                                        @"startedAt": AsNumber(job[@"startedAt"]) ?: @0,
                                        @"holds": @(ClaudeJobHolds(type)), @"stop": kClaudeCodeStopJob} mutableCopy];
        if (AsText(job[@"step"])) shown[@"step"] = job[@"step"];
        if (AsText(job[@"command"])) shown[@"command"] = job[@"command"];
        [running addObject:shown];
    }
    [running sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"startedAt"] compare:b[@"startedAt"]];
    }];
    return running.count ? running : nil;
}
