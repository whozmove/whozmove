// GitHub: what gh says about pull requests and their checks.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "GitHub.h"
#import "Processes.h"
#import "Files.h"

// Set by `--print-rows`: rows printed for a test never depend on the network, so it acts as if gh isn't there.
BOOL NeverAskGitHub;

// Where gh is installed, or nil if it isn't (or mustn't be asked). gh runs git, so it waits for Apple's developer tools,
// as git does (DeveloperToolsReady).
NSString *GhPath(void) {
    if (NeverAskGitHub || !DeveloperToolsReady()) return nil;
    for (NSString *path in @[@"/opt/homebrew/bin/gh", @"/usr/local/bin/gh", @"/usr/bin/gh"])
        if ([NSFileManager.defaultManager isExecutableFileAtPath:path]) return path;
    return nil;
}

// The fields fetched for each PR; the hover card shows most of them. Its branch (headRefName) tells which branch's PR
// it is, for the next steps.
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

// What a waiting session's pull request has had: its state, with when it was merged or closed, and its comments and
// reviews, each with who wrote it and whether GitHub says they can change the repo. Asked only while a session waits on
// it (PRWakes), as comments can be many.
NSString *const kPRActivityFields = @"number,url,state,mergedAt,closedAt,comments,reviews";

NSDictionary *FetchPRActivity(NSString *gh, NSString *url) {
    NSDictionary *run = RunTool(gh, @[@"pr", @"view", url, @"--json", kPRActivityFields], nil);
    if (!run || [run[@"status"] intValue] != 0) return nil;
    NSDictionary *activity = [NSJSONSerialization JSONObjectWithData:run[@"out"] options:0 error:nil];
    return [activity isKindOfClass:NSDictionary.class] ? activity : nil;
}

// Whether a comment or review's author may wake a session: someone GitHub marks as able to change the repo (its owner,
// a member of its organisation or a collaborator), so a stranger's comment never starts an unattended turn. A bot is
// left out where gh's answer shows one: a login ending in "[bot]", or an author whose type is Bot (`__typename`, or
// `is_bot`, where its JSON has them). A bot account added to the repo as a collaborator, with neither mark, still
// passes, as GitHub then marks it as able to change the repo.
static BOOL MayWake(NSDictionary *item) {
    NSDictionary *author = [item[@"author"] isKindOfClass:NSDictionary.class] ? item[@"author"] : nil;
    NSString *login = [author[@"login"] isKindOfClass:NSString.class] ? author[@"login"] : nil;
    NSString *association = [item[@"authorAssociation"] isKindOfClass:NSString.class] ? item[@"authorAssociation"] : nil;
    BOOL bot = [author[@"is_bot"] isKindOfClass:NSNumber.class] && [author[@"is_bot"] boolValue];
    bot = bot || [author[@"__typename"] isEqual:@"Bot"] || [login hasSuffix:@"[bot]"];
    if (!login.length || bot) return NO;
    return [@[@"OWNER", @"MEMBER", @"COLLABORATOR"] containsObject:association ?: @""];
}

static NSString *LoginOf(NSDictionary *item) {
    NSDictionary *author = [item[@"author"] isKindOfClass:NSDictionary.class] ? item[@"author"] : nil;
    return [author[@"login"] isKindOfClass:NSString.class] ? author[@"login"] : nil;
}

static double WhenOf(id iso) {
    return [iso isKindOfClass:NSString.class] && [iso length] ? TimestampMs(iso) : 0;
}

NSArray<NSDictionary *> *PRActivityEvents(NSDictionary *activity) {
    NSMutableArray<NSDictionary *> *events = [NSMutableArray array];
    void (^add)(NSString *, NSString *, double) = ^(NSString *kind, NSString *by, double at) {
        if (at <= 0) return;
        NSMutableDictionary *event = [NSMutableDictionary dictionaryWithDictionary:@{@"kind": kind, @"at": @(at)}];
        if (by) event[@"by"] = by;
        [events addObject:event];
    };
    for (NSDictionary *comment in [activity[@"comments"] isKindOfClass:NSArray.class] ? activity[@"comments"] : @[])
        if ([comment isKindOfClass:NSDictionary.class] && MayWake(comment))
            add(@"commented", LoginOf(comment), WhenOf(comment[@"createdAt"]));
    NSDictionary *reviewKinds = @{@"APPROVED": @"approved", @"CHANGES_REQUESTED": @"changes", @"COMMENTED": @"commented"};
    for (NSDictionary *review in [activity[@"reviews"] isKindOfClass:NSArray.class] ? activity[@"reviews"] : @[]) {
        if (![review isKindOfClass:NSDictionary.class] || !MayWake(review)) continue;
        NSString *kind = [review[@"state"] isKindOfClass:NSString.class] ? reviewKinds[review[@"state"]] : nil;
        if (kind) add(kind, LoginOf(review), WhenOf(review[@"submittedAt"]));
    }
    if ([activity[@"state"] isEqual:@"MERGED"]) add(@"merged", nil, WhenOf(activity[@"mergedAt"]));
    if ([activity[@"state"] isEqual:@"CLOSED"]) add(@"closed", nil, WhenOf(activity[@"closedAt"]));
    [events sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"at" ascending:YES]]];
    return events;
}
