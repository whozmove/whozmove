// JiraFacts: Atlassian's addresses and tools, Jira's keys and links, and its status categories.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "JiraFacts.h"
#import "Files.h"

static NSString *const kJiraServer = @"https://mcp.atlassian.com/v2/mcp";

// A stand-in on this Mac, named by a test's throwaway home only: http on 127.0.0.1 alone.
static NSURL *StandIn(void) {
    if (HomeIsYourOwn()) return nil;
    NSString *named = NSProcessInfo.processInfo.environment[@"WHOZMOVE_JIRA_SERVER"];
    NSURL *url = named.length ? [NSURL URLWithString:named] : nil;
    return [url.host isEqualToString:@"127.0.0.1"] ? url : nil;
}

NSURL *JiraServer(void) {
    return StandIn() ?: [NSURL URLWithString:kJiraServer];
}
NSString *JiraResource(void) {
    return JiraServer().absoluteString;
}
NSString *const kJiraWriteScope = @"write:jira:agent-interface";
NSString *const kJiraProductId = @"jira", *const kJiraScopeWord = @"jira";
NSArray<NSString *> *JiraScopes(void) {
    // Writing too, as a session moves its ticket and adds its note there; never deleting or managing.
    return @[@"read:jira:agent-interface", @"search:jira:agent-interface", kJiraWriteScope, @"offline_access",
             @"read:me", @"read:account"];
}

NSString *const kJiraToolSites = @"getAccessibleAtlassianResources";
NSString *const kJiraToolSearch = @"searchJiraIssuesUsingJql";
NSString *const kJiraToolIssue = @"getJiraIssue";
NSString *const kJiraToolTransitions = @"listJiraIssueTransitions";
NSString *const kJiraToolTransition = @"transitionJiraIssue";
NSString *const kJiraToolComment = @"addOrEditJiraIssueComment";
NSString *const kJiraToolCreate = @"createJiraIssue";
NSString *const kJiraToolIssueTypes = @"listJiraProjectIssueTypesMetadata";
NSString *const kJiraToolBoards = @"listJiraBoards";
NSString *const kJiraToolTypeFields = @"getJiraIssueTypeMetaWithFields";
NSString *const kJiraPriorityType = @"Task";
const NSInteger kJiraFieldsMost = 200;
NSString *const kJiraExecuteRead = @"executeRead";
NSString *const kJiraExecuteWrite = @"executeWrite";

BOOL JiraToolWrites(NSString *tool) {
    return [@[kJiraToolTransition, kJiraToolComment, kJiraToolCreate, kJiraExecuteWrite] containsObject:tool];
}

NSString *JiraCloudId(NSString *site) {
    return [@"https://" stringByAppendingString:site ?: @""];
}
const NSInteger kJiraSearchMost = 5;

NSString *const kJiraReadView = @"full";
const NSInteger kJiraAboutMost = 20000;
NSString *const kJiraAboutCut = @"(Cut short here: the rest is on the ticket's own page.)";
const NSInteger kJiraEveryMost = 200;
NSString *const kJiraHistoryExpand = @"changelog";
NSString *const kJiraStatusField = @"status";

NSString *JiraEveryJQL(NSDate *since) {
    // A minute more than asked, rounded up, so nothing changed on the edge is missed.
    if (since) return [NSString stringWithFormat:@"updated >= -%ldm ORDER BY updated DESC",
                       (long)MAX(1, ceil(-since.timeIntervalSinceNow / 60) + 1)];
    return @"project IS NOT EMPTY ORDER BY updated DESC";
}

NSURLSession *JiraSession(NSTimeInterval timeout) {
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicyNever;
    configuration.HTTPShouldSetCookies = NO;
    configuration.URLCache = nil;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    configuration.timeoutIntervalForRequest = timeout;
    configuration.timeoutIntervalForResource = timeout * 2;
    return [NSURLSession sessionWithConfiguration:configuration];
}
NSString *JiraVersion(void) {
    return AsText(NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"]) ?: @"0";
}

static NSRegularExpression *Pattern(NSString *pattern) {
    return [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
}

BOOL JiraIsKey(NSString *text) {
    static NSRegularExpression *key;
    key = key ?: Pattern(@"^[A-Z][A-Z0-9_]*-[1-9][0-9]{0,9}$");
    return text.length && [key numberOfMatchesInString:text options:0 range:NSMakeRange(0, text.length)] == 1;
}

BOOL JiraIsSite(NSString *host) {
    host = host.lowercaseString;
    for (NSString *end in @[@".atlassian.net", @".jira.com"])
        if ([host hasSuffix:end] && host.length > end.length
            && [[host substringToIndex:host.length - end.length] rangeOfString:@"."].location == NSNotFound) return YES;
    return NO;
}

NSString *JiraKeyIn(NSString *text, NSString **site) {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (site) *site = nil;
    if (JiraIsKey(trimmed)) return trimmed;
    NSURLComponents *link = [NSURLComponents componentsWithString:trimmed];
    if (![link.scheme isEqualToString:@"https"] || !JiraIsSite(link.host)) return nil;
    NSString *key = nil;
    NSArray *parts = [link.path componentsSeparatedByString:@"/"];
    NSUInteger browse = [parts indexOfObject:@"browse"];
    if (browse != NSNotFound && browse + 1 < parts.count) key = parts[browse + 1];
    for (NSURLQueryItem *item in link.queryItems) if ([item.name isEqualToString:@"selectedIssue"]) key = item.value;
    if (!JiraIsKey(key)) return nil;
    if (site) *site = link.host.lowercaseString;
    return key;
}

NSString *JiraLinkFor(NSString *key, NSString *site) {
    if (!JiraIsKey(key) || !JiraIsSite(site)) return nil;
    return [NSString stringWithFormat:@"https://%@/browse/%@", site.lowercaseString, key];
}

NSString *JiraCategoryKey(id category) {
    NSDictionary *record = AsRecord(category);
    NSString *key = AsText(record[@"key"]);
    if (key.length) return key;
    // Jira's own three categories, as an issue read through v2 names them, with no key.
    return @{@"to do": @"new", @"in progress": @"indeterminate", @"done": @"done"}
        [AsText(record[@"name"]).lowercaseString ?: @""];
}

TicketKind JiraKindOf(NSString *categoryKey, NSString *resolution) {
    if ([categoryKey isEqualToString:@"indeterminate"]) return TicketKindUnderWay;
    if (![categoryKey isEqualToString:@"done"]) return TicketKindToDo;
    NSString *r = resolution.lowercaseString ?: @"";
    for (NSString *dropped in @[@"won't do", @"won’t do", @"duplicate", @"cannot reproduce", @"declined", @"won't fix"])
        if ([r isEqualToString:dropped]) return TicketKindDropped;
    return TicketKindDone;
}

// Text for a JQL string: in double quotes, its own quotes and backslashes escaped.
static NSString *Quoted(NSString *text) {
    NSString *s = [text stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    return [NSString stringWithFormat:@"\"%@\"", [s stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
}

NSString *JiraSearchFor(NSString *words) {
    NSString *trimmed = [words stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *key = JiraKeyIn(trimmed, NULL);
    // Quoted, as a project's key can be a word JQL keeps for itself (GO, IN, OR).
    if (key) return [NSString stringWithFormat:@"key = %@", Quoted(key)];
    if (!trimmed.length) return @"assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC";
    return [NSString stringWithFormat:@"text ~ %@ ORDER BY statusCategory ASC, updated DESC",
            Quoted(Clip(trimmed, 200))];
}

NSString *JiraBlockedWords(void) {
    return @"Your Jira admin hasn't let apps sign in from this Mac yet. They can allow it once, for everyone.";
}
NSString *JiraWhatToAsk(void) {
    return @"Please allow Whozmove to sign in to our Jira. In Atlassian Administration, under the Rovo MCP server's "
           @"settings, allow the Atlassian-supported domains (they include http://127.0.0.1, where Whozmove signs in "
           @"from), or add http://127.0.0.1 to our own.";
}
