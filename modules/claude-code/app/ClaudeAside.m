// ClaudeAside: a question asked on the side of one of Claude Code's sessions, answered by a throwaway copy of its
// conversation.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "ClaudeAside.h"
#import <signal.h>
#import "Files.h"
#import "Log.h"
#import "Processes.h"
#import "ClaudeCodeFacts.h"
#import "ClaudeCommand.h"
#import "ClaudeSessions.h"
#import "ClaudeUsage.h"

// How long a side question has to answer, and the most of its answer that's kept.
static const NSTimeInterval kAsideDeadline = 180;
static const NSUInteger kAsideMost = 16384;

static NSString *Cut(NSString *text) {
    if (text.length <= kAsideMost) return text;
    return [text substringToIndex:[text rangeOfComposedCharacterSequenceAtIndex:kAsideMost].location];
}

NSDictionary *ClaudeAsideAnswer(NSArray<NSData *> *lines, BOOL timedOut, BOOL stopped) {
    NSMutableArray<NSString *> *said = [NSMutableArray array];
    NSDictionary *result = nil;
    BOOL reached = NO;
    double resetsAt = 0;
    for (NSData *line in lines) {
        NSDictionary *message = AsRecord([NSJSONSerialization JSONObjectWithData:line options:0 error:nil]);
        NSString *type = AsText(message[@"type"]);
        if ([type isEqual:@"assistant"]) {
            for (id each in AsList(AsRecord(message[@"message"])[@"content"])) {
                NSDictionary *block = AsRecord(each);
                if ([block[@"type"] isEqual:@"tool_use"]) reached = YES;
                else if ([block[@"type"] isEqual:@"text"] && AsText(block[@"text"]).length) [said addObject:block[@"text"]];
            }
        } else if ([type isEqual:@"rate_limit_event"]) {
            // Seconds since 1970, as Claude Code passes on Anthropic's own.
            double at = AsNumber(AsRecord(message[@"rate_limit_info"])[@"resetsAt"]).doubleValue;
            if (at > 0) resetsAt = at * 1000;
        } else if ([type isEqual:@"result"]) {
            result = message;
        }
    }
    NSMutableDictionary *answer = [NSMutableDictionary dictionary];
    NSDictionary *usage = AsRecord(result[@"usage"]);
    NSDictionary *counts = @{@"cacheRead": @"cache_read_input_tokens", @"fresh": @"input_tokens",
                             @"written": @"cache_creation_input_tokens", @"output": @"output_tokens"};
    [counts enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *field, BOOL *stop) {
        if (AsNumber(usage[field])) answer[key] = usage[field];
    }];
    if (AsNumber(result[@"api_error_status"])) answer[@"status"] = result[@"api_error_status"];
    NSString *subtype = AsText(result[@"subtype"]), *words = AsText(result[@"result"]);
    // An error Claude Code passes on, by the words it uses for each (checked with 2.1.304).
    NSString *error = [[NSString stringWithFormat:@"%@ %@", words ?: @"", AsText(result[@"api_error_status"]) ?: @""]
                       lowercaseString];
    if (stopped) answer[@"state"] = @"stopped";
    else if (!result) answer[@"state"] = timedOut ? @"tooSlow" : @"noAnswer";
    else if ([subtype isEqual:@"error_max_turns"]) answer[@"state"] = reached ? @"wantedTool" : @"noAnswer";
    else if (![result[@"is_error"] isEqual:@YES] && [subtype isEqual:@"success"]) {
        NSString *text = words.length ? words : [said componentsJoinedByString:@"\n\n"];
        answer[@"state"] = text.length ? @"answered" : @"noAnswer";
        if (text.length) answer[@"text"] = Cut(text);
    } else if ([error containsString:@"too long"] || [error containsString:@"context limit"]
               || [error containsString:@"context window"]) {
        // Before the plan's limit: a conversation too long for its model says "limit" too.
        answer[@"state"] = @"tooLong";
    } else if ([error containsString:@"401"] || [error containsString:@"/login"] || [error containsString:@"log in"]
               || [error containsString:@"authentication"]) {
        answer[@"state"] = @"signedOut";
    } else if ([error containsString:@"limit"] || [error containsString:@"429"]) {
        // "You've hit your limit", or Anthropic's own words passed on as they are.
        answer[@"state"] = @"limit";
        if (resetsAt > 0) answer[@"resetsAt"] = @(resetsAt);
    } else if (answer[@"status"] || [error hasPrefix:@"api error"]) {
        // Any other error the API sent back ("API Error: 400 …"): said as one, not as no answer.
        answer[@"state"] = @"apiError";
    } else {
        answer[@"state"] = @"noAnswer";
    }
    return answer;
}

NSString *ClaudeAsideModel(NSString *model, NSString *flagModel, NSInteger tokens) {
    if (!model.length) return flagModel.length ? flagModel : nil;
    if ([model containsString:@"["]) return model;
    NSString *flagCanonical = [flagModel componentsSeparatedByString:@"["].firstObject;
    // Over 200k, the long context, but never for a model whose own window is already the long one (ClaudeContextWindow):
    // a "[1m]" on its name makes Claude Code send a beta flag the session's own requests never do.
    BOOL longOne = ([flagModel containsString:@"[1m]"] && [flagCanonical isEqual:model])
        || (tokens > 200000 && ClaudeContextWindow(model, 0) < 1000000);
    return longOne ? [model stringByAppendingString:@"[1m]"] : model;
}

NSString *ClaudeAsideProgram(NSString *running, NSArray<NSString *> *candidates) {
    NSString *real = running.length ? RealPath(running) : nil;
    for (NSString *candidate in candidates)
        if (real && [RealPath(candidate) isEqual:real]) return candidate;
    return candidates.firstObject;
}

// An ask while it runs: its process, once started, told apart from a later one given the same pid by its start; and
// whether Stop was pressed.
@interface AsideRun : NSObject
@property (assign) pid_t pid;
@property (assign) long long started;
@property (assign) BOOL stopped;
@end

@implementation AsideRun
@end

@interface ClaudeAside ()
@property (strong) NSMutableDictionary<NSString *, AsideRun *> *runs;  // by ask id; under its own lock
@end

@implementation ClaudeAside

- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.runs = [NSMutableDictionary dictionary];
    return self;
}

// Its process and everything it started, ended, only while it's still the one this ask started.
static void EndRun(AsideRun *run) {
    if (run.pid > 0 && run.started && ProcessStartedAt(run.pid) == run.started) killpg(run.pid, SIGTERM);
}

- (NSString *)ask:(NSString *)question running:(NSString *)running sessionId:(NSString *)sessionId
            model:(NSString *)model effort:(NSString *)effort folder:(NSString *)folder
             done:(void (^)(NSDictionary *answer))done {
    NSArray *arguments = ClaudeAsideArguments(sessionId, model, effort);
    if (!arguments) return nil;
    NSString *askId = NSUUID.UUID.UUIDString;
    AsideRun *run = [AsideRun new];
    @synchronized (self.runs) {
        self.runs[askId] = run;
    }
    NSString *words = [NSString stringWithFormat:@"%@\n\n%@", kClaudeAsideLine, question];
    NSDictionary *line = @{@"type": @"user", @"message": @{@"role": @"user", @"content": words}};
    NSMutableData *send = [[NSJSONSerialization dataWithJSONObject:line options:0 error:nil] mutableCopy];
    [send appendBytes:"\n" length:1];
    NSMutableDictionary *runs = self.runs;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // Where Claude Code is comes from your login shell's PATH, which can take a moment the first time.
        NSString *path = LoginPath();
        NSString *claude = ClaudeAsideProgram(running, ClaudeCandidates(path));
        if (!claude) {
            @synchronized (runs) {
                [runs removeObjectForKey:askId];
            }
            dispatch_async(dispatch_get_main_queue(), ^{ done(@{@"state": @"noCommand"}); });
            return;
        }
        NSDictionary *environment = ClaudeEnvironment(path);
        NSMutableArray<NSData *> *lines = [NSMutableArray array];
        __block NSUInteger kept = 0;
        NSDictionary *ran = RunConversation(claude, arguments, environment, folder, send, ^BOOL(NSData *each) {
            // Every line is kept until the result's, but no more than an answer needs.
            if (kept < 4 * 1024 * 1024) {
                [lines addObject:each];
                kept += each.length;
            }
            NSDictionary *message = AsRecord([NSJSONSerialization JSONObjectWithData:each options:0 error:nil]);
            return [message[@"type"] isEqual:@"result"];
        }, kAsideDeadline, ^(pid_t pid) {
            // Kept out of the rows before it can register, and ended at once if Stop came first.
            NoteAsideProcess(pid, YES);
            @synchronized (runs) {
                run.pid = pid;
                run.started = ProcessStartedAt(pid);
                if (run.stopped) EndRun(run);
            }
        });
        BOOL stopped;
        @synchronized (runs) {
            stopped = run.stopped;
            [runs removeObjectForKey:askId];
        }
        if (run.pid > 0) NoteAsideProcess(run.pid, NO);
        NSMutableDictionary *answer = [(ran ? ClaudeAsideAnswer(lines, [ran[@"timedOut"] boolValue], stopped)
                                            : @{@"state": stopped ? @"stopped" : @"noAnswer"}) mutableCopy];
        if ([answer[@"state"] isEqual:@"signedOut"]) answer[@"signIn"] = ClaudeSignInCommand(claude);
        if (!ran) LogProblem([NSString stringWithFormat:@"side question: %@ didn't start", claude]);
        dispatch_async(dispatch_get_main_queue(), ^{ done(answer); });
    });
    return askId;
}

- (void)stop:(NSString *)askId {
    @synchronized (self.runs) {
        AsideRun *run = askId ? self.runs[askId] : nil;
        if (!run || run.stopped) return;
        run.stopped = YES;
        EndRun(run);
    }
}

- (void)stopAll {
    @synchronized (self.runs) {
        for (AsideRun *run in self.runs.allValues) {
            run.stopped = YES;
            EndRun(run);
        }
    }
}

@end
