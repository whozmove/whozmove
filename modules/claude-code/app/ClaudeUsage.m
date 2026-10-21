// ClaudeUsage: your Claude plan's usage, asked of Claude Code itself.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// Claude Code knows your plan's usage (it's what its own /usage shows), so it's asked: the `claude` command is run for
// a moment, answers one request, and is told to finish. It signs in and asks Anthropic itself; Whozmove never reads
// your login. The page gets what the strip needs and nothing about your account.
#import "ClaudeUsage.h"
#import "Files.h"
#import "Processes.h"
#import "Log.h"
#import "Text.h"
#import "ClaudeCodeFacts.h"
#import "ClaudeCommand.h"

static NSString *const kRequestId = @"whozmove-usage";
// How long Claude Code has to answer.
static const NSTimeInterval kDeadline = 15;

NSString *UsageFolder(void) {
    return AppDir(@"usage");
}

NSDictionary *UsageFromReply(NSData *line) {
    NSDictionary *message = AsRecord([NSJSONSerialization JSONObjectWithData:line options:0 error:nil]);
    NSDictionary *response = AsRecord(message[@"response"]);
    if (![message[@"type"] isEqual:@"control_response"] || ![response[@"request_id"] isEqual:kRequestId]) return nil;
    if (![response[@"subtype"] isEqual:@"success"]) return @{@"error": AsText(response[@"error"]) ?: @"no answer"};
    NSDictionary *answer = AsRecord(response[@"response"]), *limits = AsRecord(answer[@"rate_limits"]);
    NSMutableDictionary *usage = [NSMutableDictionary dictionary];
    usage[@"available"] = @([answer[@"rate_limits_available"] isEqual:@YES]);
    if (AsText(answer[@"subscription_type"])) usage[@"plan"] = answer[@"subscription_type"];
    for (NSArray<NSString *> *window in @[@[@"five_hour", @"session"], @[@"seven_day", @"week"]]) {
        NSDictionary *each = AsRecord(limits[window[0]]);
        if (!AsNumber(each[@"utilization"])) continue;
        NSMutableDictionary *kept = [NSMutableDictionary dictionaryWithObject:each[@"utilization"] forKey:@"used"];
        double resetsAt = TimestampMs(each[@"resets_at"]);
        if (resetsAt > 0) kept[@"resetsAt"] = @(resetsAt);
        usage[window[1]] = kept;
    }
    // Claude's own bars, each with how worrying it is (severity): the strip colours its bars the same way.
    NSMutableArray *bars = [NSMutableArray array];
    for (id each in AsList(limits[@"limits"])) {
        NSDictionary *bar = AsRecord(each);
        if (!AsText(bar[@"kind"]) || !AsNumber(bar[@"percent"])) continue;
        NSMutableDictionary *kept = [NSMutableDictionary dictionaryWithDictionary:@{@"kind": bar[@"kind"],
                                                                                    @"percent": bar[@"percent"]}];
        if (AsText(bar[@"severity"])) kept[@"severity"] = bar[@"severity"];
        double resetsAt = TimestampMs(bar[@"resets_at"]);
        if (resetsAt > 0) kept[@"resetsAt"] = @(resetsAt);
        NSString *model = AsText(AsRecord(AsRecord(bar[@"scope"])[@"model"])[@"display_name"]);
        if (model) kept[@"model"] = model;
        [bars addObject:kept];
    }
    usage[@"limits"] = bars;
    usage[@"extraUsage"] = @([AsRecord(limits[@"extra_usage"])[@"is_enabled"] isEqual:@YES]);
    return usage;
}

NSString *AuthStateFrom(NSData *output) {
    NSDictionary *status = output.length ? AsRecord([NSJSONSerialization JSONObjectWithData:output options:0 error:nil])
                                         : nil;
    if (![status[@"loggedIn"] isKindOfClass:NSNumber.class]) return nil;  // not what `claude auth status` prints
    return [status[@"loggedIn"] boolValue] ? @"signedIn" : @"signedOut";
}

// The command that signs in the `claude` at this path, as typed in a terminal.
static NSString *SignInCommand(NSString *claude) {
    return [NSString stringWithFormat:@"%@ %@", ShellWord(claude),
                                      [ClaudeSignInArguments() componentsJoinedByString:@" "]];
}

@interface ClaudeUsage ()
// On the asking queue only: the `claude` that last answered (tried first), and whether your terminal's shell points
// Claude Code at an API key or another provider, as last found.
@property (copy) NSString *answered;
@property (assign) NSTimeInterval shellAskedAt;
@property (strong) NSNumber *shellUsesOther;
@end

@implementation ClaudeUsage

#pragma mark Asking

// Claude Code's answer, as {state, plan, session, week, limits, extraUsage, signIn}. state is "ok" (a Claude plan's
// numbers), "signedOut", "other" (signed in with an API key or another provider: no plan to show), "none" (no `claude`
// here) or "failed"; `signIn` is the command that signs in the `claude` that answered. A `claude` that can't answer
// (too old, broken) gives way to the next one. The check runs in a folder of its own, so its session (Claude Code
// registers one even for this) is told apart from yours, and its per-folder entry in Claude Code's own records stays
// one. Only you may read it, as with Whozmove's other files.
- (NSDictionary *)ask {
    [NSFileManager.defaultManager createDirectoryAtPath:UsageFolder() withIntermediateDirectories:YES
                                             attributes:@{NSFilePosixPermissions: @0700} error:nil];
    NSString *path = LoginPath();
    NSMutableArray<NSString *> *candidates = [ClaudeCandidates(path) mutableCopy];
    if (self.answered && [candidates containsObject:self.answered]) {
        [candidates removeObject:self.answered];
        [candidates insertObject:self.answered atIndex:0];
    }
    if (!candidates.count) return @{@"state": @"none"};
    NSDictionary *environment = ClaudeEnvironment(path);
    NSDictionary *request = @{@"type": @"control_request", @"request_id": kRequestId,
                              @"request": @{@"subtype": kClaudeUsageRequest, @"skip_behaviors": @YES}};
    NSMutableData *send = [[NSJSONSerialization dataWithJSONObject:request options:0 error:nil] mutableCopy];
    [send appendBytes:"\n" length:1];
    for (NSString *claude in candidates) {
        __block NSDictionary *answer = nil;
        NSDictionary *run = RunConversation(claude, ClaudeUsageArguments(), environment, UsageFolder(), send,
                                            ^BOOL(NSData *line) {
            answer = UsageFromReply(line);
            return answer != nil;
        }, kDeadline);
        if (!answer || answer[@"error"]) {
            LogProblem([NSString stringWithFormat:@"plan usage: %@ didn't answer (%@)", claude,
                        answer[@"error"] ?: (!run ? @"didn't start" : [run[@"timedOut"] boolValue] ? @"too slow"
                                                                   : @"no answer")]);
            continue;
        }
        self.answered = claude;
        NSMutableDictionary *found = [answer mutableCopy];
        [found removeObjectForKey:@"available"];
        found[@"signIn"] = SignInCommand(claude);
        if ([answer[@"available"] boolValue]) {
            found[@"state"] = @"ok";
            return found;
        }
        // No plan's numbers: signed out (when your terminal doesn't use an API key or another provider), or signed in
        // with something that has no plan.
        NSDictionary *status = RunBriefly(claude, ClaudeAuthStatusArguments(), environment, 10, 64 * 1024, NO);
        BOOL signedOut = [AuthStateFrom(status[@"out"]) isEqual:@"signedOut"] && ![self shellUsesOtherAuth];
        return @{@"state": signedOut ? @"signedOut" : @"other", @"signIn": SignInCommand(claude)};
    }
    return @{@"state": @"failed"};
}

// Whether your terminal's shell sets one of ClaudeOtherAuthVariables: then Claude Code there uses that rather than a
// sign-in, and Sign in would be wrong. Only whether one is set is printed, never what it holds. The answer is kept for
// 10 minutes, then asked again, so a variable you've since added or taken out counts without a restart. Asked only
// while Claude Code says you're signed out. On the queue.
- (BOOL)shellUsesOtherAuth {
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (now - self.shellAskedAt >= 600) {
        self.shellAskedAt = now;
        NSMutableString *set = [NSMutableString string];
        for (NSString *name in ClaudeOtherAuthVariables()) [set appendFormat:@"${%@:+set}", name];
        NSString *script = [NSString stringWithFormat:@"printf '\\n__whozmove_auth__%%s\\n' \"%@\"", set];
        NSDictionary *run = RunBriefly(LoginShell(), @[@"-l", @"-i", @"-c", script], nil, 5, 64 * 1024, NO);
        NSData *out = run[@"out"], *mark = [@"\n__whozmove_auth__" dataUsingEncoding:NSUTF8StringEncoding];
        NSRange at = out.length ? [out rangeOfData:mark options:NSDataSearchBackwards range:NSMakeRange(0, out.length)]
                                : NSMakeRange(NSNotFound, 0);
        if (at.location != NSNotFound) {
            NSData *rest = [out subdataWithRange:NSMakeRange(NSMaxRange(at), out.length - NSMaxRange(at))];
            NSString *line = [[[NSString alloc] initWithData:rest encoding:NSUTF8StringEncoding]
                              componentsSeparatedByString:@"\n"].firstObject;
            self.shellUsesOther = @(line.length > 0);
        }
    }
    return self.shellUsesOther.boolValue;
}

@end
