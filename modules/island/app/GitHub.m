// GitHub: what gh says about pull requests and their checks.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "GitHub.h"
#import "Processes.h"

// Set by `--print-rows`: rows printed for a test never depend on the network, so it acts as if gh isn't there.
BOOL NeverAskGitHub;

// Where gh is installed, or nil if it isn't (or mustn't be asked).
NSString *GhPath(void) {
    if (NeverAskGitHub) return nil;
    for (NSString *path in @[@"/opt/homebrew/bin/gh", @"/usr/local/bin/gh", @"/usr/bin/gh"])
        if ([NSFileManager.defaultManager isExecutableFileAtPath:path]) return path;
    return nil;
}

// The fields fetched for each PR; the hover card shows most of them. Its branch (headRefName) tells which branch's PR
// it is, for the island.
NSString *const kPRFields = @"number,title,state,isDraft,url,author,additions,deletions,changedFiles,createdAt,"
                            @"reviewDecision,statusCheckRollup,headRefName";

// `gh pr view <url> --json <kPRFields>`, or nil. Blocking; call it off the main thread.
NSDictionary *FetchPRStatus(NSString *gh, NSString *url) {
    NSDictionary *run = RunTool(gh, @[@"pr", @"view", url, @"--json", kPRFields], nil);
    if (!run || [run[@"status"] intValue] != 0) return nil;
    NSDictionary *status = [NSJSONSerialization JSONObjectWithData:run[@"out"] options:0 error:nil];
    return [status isKindOfClass:NSDictionary.class] ? status : nil;
}

// What a PR's checks add up to: failing (any failed), running (any still going), passing, or none.
NSString *ChecksState(NSArray *rollup) {
    if (![rollup isKindOfClass:NSArray.class]) return @"none";
    NSString *checks = @"none";
    for (NSDictionary *check in rollup) {
        if (![check isKindOfClass:NSDictionary.class]) continue;
        NSString *outcome = [check[@"conclusion"] isKindOfClass:NSString.class] && [check[@"conclusion"] length]
            ? check[@"conclusion"] : check[@"state"];
        NSString *progress = [check[@"status"] isKindOfClass:NSString.class] ? check[@"status"] : @"";
        if ([@[@"FAILURE", @"ERROR", @"TIMED_OUT", @"CANCELLED", @"ACTION_REQUIRED", @"STARTUP_FAILURE"]
                containsObject:outcome ?: @""]) {
            return @"failing";
        }
        if ([@[@"QUEUED", @"IN_PROGRESS", @"PENDING", @"WAITING", @"REQUESTED"] containsObject:progress]
            || [outcome isEqual:@"PENDING"])
            checks = @"running";
        else if ([checks isEqual:@"none"]) checks = @"passing";
    }
    return checks;
}

// The PR for a branch, reduced to {number, url, state, isDraft, review, checks: failing | running | passing | none}.
// *found is NO when gh couldn't answer (offline, not signed in), so the caller keeps what it knew; a branch
// without a PR comes back as NSNull. Blocking.
id FetchBranchPR(NSString *gh, NSString *root, NSString *branch, BOOL *found) {
    *found = NO;
    NSString *fields = @"number,url,state,isDraft,reviewDecision,statusCheckRollup";
    // `gh pr view 123` means PR #123, so a branch named only with digits is looked up by name instead.
    BOOL digits = branch.length
        && [branch rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound;
    NSDictionary *run = RunTool(gh, digits ? @[@"pr", @"list", @"--head", branch, @"--state", @"all", @"--limit", @"1",
                                               @"--json", fields]
                                           : @[@"pr", @"view", branch, @"--json", fields], root);
    if (!run) return nil;
    if ([run[@"status"] intValue] != 0) {
        *found = [run[@"err"] rangeOfString:@"no pull requests found"].location != NSNotFound;
        return NSNull.null;
    }
    id pr = [NSJSONSerialization JSONObjectWithData:run[@"out"] options:0 error:nil];
    if (digits && [pr isKindOfClass:NSArray.class]) {
        if (![pr count]) { *found = YES; return NSNull.null; }
        pr = [pr firstObject];
    }
    if (![pr isKindOfClass:NSDictionary.class]) return nil;
    NSString *checks = ChecksState(pr[@"statusCheckRollup"]);
    *found = YES;
    return @{@"number": pr[@"number"] ?: @0, @"url": pr[@"url"] ?: @"", @"state": pr[@"state"] ?: @"",
             @"isDraft": pr[@"isDraft"] ?: @NO, @"review": pr[@"reviewDecision"] ?: @"", @"checks": checks};
}
