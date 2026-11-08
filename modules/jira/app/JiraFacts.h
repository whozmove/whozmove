// JiraFacts: what Whozmove relies on about Jira and Atlassian that Atlassian could change. When it does, the fix goes
// here. As Atlassian's own docs describe its server for AI tools, the Rovo MCP server, v2.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Ticket.h"

// Atlassian's server for AI tools (the Rovo MCP server, v2), which Whozmove calls Jira's tools through, and the address
// its sign-in is for (the `resource` of RFC 8707). A test's throwaway home may name a stand-in for it on this Mac
// (WHOZMOVE_JIRA_SERVER), so no test reaches Atlassian; your own home never can.
NSURL *JiraServer(void);
NSString *JiraResource(void);
// What Whozmove asks to be allowed, as Atlassian names it: Jira's reads, searches and writes through the server (never
// deleting or managing), staying signed in (offline_access), and who you are and which sites you're on (read:me,
// read:account, which getAccessibleAtlassianResources needs). The write scope on its own, which a sign-in kept before
// Whozmove asked for it lacks.
NSArray<NSString *> *JiraScopes(void);
extern NSString *const kJiraWriteScope;

// The tools Whozmove calls, by their names in v2. The sites you're on, search, an issue, taking a transition, a comment
// and creating are listed directly; the others are called through v2's deferred calls (kJiraExecuteRead,
// kJiraExecuteWrite: {name, cloudId, inputs}, with inputs one flat object, where a wrongly named one is silently
// dropped). Every Jira tool takes the site as `cloudId`, given as the site's address. Only plain Jira tools: never
// Teamwork Graph's enriched reads, which use a site's Rovo credits.
extern NSString *const kJiraToolSites, *const kJiraToolSearch, *const kJiraToolIssue, *const kJiraToolTransitions,
                *const kJiraToolTransition, *const kJiraToolComment, *const kJiraToolCreate,
                *const kJiraToolIssueTypes, *const kJiraToolBoards, *const kJiraExecuteRead,
                *const kJiraExecuteWrite;

// Whether a tool writes to Jira (taking a step, a comment, a new ticket, or v2's deferred writes), and so needs the
// write scope.
BOOL JiraToolWrites(NSString *tool);

// The site as Atlassian's tools take it (`cloudId`): its address.
NSString *JiraCloudId(NSString *site);
// How many tickets one site's search asks for: Atlassian's server has given at most five a page.
extern const NSInteger kJiraSearchMost;

// The fields Whozmove reads of an issue, and of each issue a search finds: what the row, its card and a session need,
// never the description or the comments (a session reads those itself, once it has the ticket).
NSArray<NSString *> *JiraIssueFields(void);
NSArray<NSString *> *JiraSearchFields(void);

// What Whozmove talks to Atlassian with: no cookies, no cache, and a timeout; and the version it says it is.
NSURLSession *JiraSession(NSTimeInterval timeout);
NSString *JiraVersion(void);

// A Jira key as people write it: the project's key (a capital letter, then capitals, digits or _), a hyphen, a number.
// Plain functions: the key in `text` when it's a key alone or a link to a ticket on an Atlassian site
// (https://<site>.atlassian.net/browse/KEY, or a board's link with ?selectedIssue=KEY), with the site's host in *site
// for a link; and a ticket's address, made from its site and key, never taken from what a tracker sends.
BOOL JiraIsKey(NSString *text);
NSString *JiraKeyIn(NSString *text, NSString **site);
NSString *JiraLinkFor(NSString *key, NSString *site);
// Whether a host is an Atlassian Cloud site's (<name>.atlassian.net, or <name>.jira.com from before).
BOOL JiraIsSite(NSString *host);

// A status's category, as Jira names it (its key: new, indeterminate, done), as one of the four kinds. Jira has no
// category for dropped: a status whose resolution says so (Won't Do, Duplicate, Cannot Reproduce) is done, as Jira
// counts it, unless the resolution names it dropped.
TicketKind JiraKindOf(NSString *categoryKey, NSString *resolution);

// The search for words typed on the card, as JQL: a key finds that ticket; words, tickets whose text has them, most
// recently changed first, done ones last. The words are quoted for JQL, so nothing typed changes the query.
NSString *JiraSearchFor(NSString *words);

// What to tell an admin who has turned this sign-in off, and why the panel says it can't sign in.
NSString *JiraBlockedWords(void);
NSString *JiraWhatToAsk(void);
