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
// How the list of your sites says a site has Jira: the product's id it lists for it, or the word in a scope it lists.
extern NSString *const kJiraProductId, *const kJiraScopeWord;

// The tools Whozmove calls, by their names in v2. The sites you're on, search, an issue, taking a transition, a comment
// and creating are listed directly; the others are called through v2's deferred calls (kJiraExecuteRead,
// kJiraExecuteWrite: {name, cloudId, inputs}, with inputs one flat object, where a wrongly named one is silently
// dropped). Every Jira tool takes the site as `cloudId`, given as the site's address. Only plain Jira tools: never
// Teamwork Graph's enriched reads, which use a site's Rovo credits.
extern NSString *const kJiraToolSites, *const kJiraToolSearch, *const kJiraToolIssue, *const kJiraToolTransitions,
                *const kJiraToolTransition, *const kJiraToolComment, *const kJiraToolCreate,
                *const kJiraToolIssueTypes, *const kJiraToolBoards, *const kJiraToolTypeFields,
                *const kJiraExecuteRead, *const kJiraExecuteWrite;

// A project's priorities in their scheme's order, the most pressing first, each with Jira's id: the priority field's
// allowed values among the create fields of one of the project's types (kJiraToolTypeFields, through executeRead, its
// inputs the project and the type's id). Priority schemes are per project, so the list is too. Only some types' create
// fields list priority (a Task's and a Story's do; a Bug's, an Epic's and a Subtask's have been seen without it, though
// each holds a priority), so the order is read from the project's type named kJiraPriorityType, never each ticket's
// own; a project without one has no order, and its tickets no place. Its inputs are named as Jira's own create fields
// read names them, and its answer is looked for in each shape Jira has given those fields in (JiraPrioritiesIn). The
// same read, for a ticket's own type, gives the fields its tickets take one option of (JiraOptionFieldsIn).
extern NSString *const kJiraPriorityType;
// How many of a type's create fields one read asks for: Jira gives them a page at a time, 50 unless asked, and the
// priority field must be on the page read, however many fields of its own a project's screen has.
extern const NSInteger kJiraFieldsMost;

// Whether a tool writes to Jira (taking a step, a comment, a new ticket, or v2's deferred writes), and so needs the
// write scope.
BOOL JiraToolWrites(NSString *tool);

// The site as Atlassian's tools take it (`cloudId`): its address.
NSString *JiraCloudId(NSString *site);
// How many tickets one site's search asks for: Atlassian's server has given at most five a page.
extern const NSInteger kJiraSearchMost;

// How Whozmove asks for an issue, read or searched: as the server's full view, the only one whose answer has the
// priority's id, the status category's key, the parent and the resolution. A list of fields, or a smaller view, gives
// the first two by their names alone and leaves the others out, whatever it names. The full view brings the comments
// too; Whozmove takes only what the row, its card and a session need, and keeps none of them.
extern NSString *const kJiraReadView;

// The most of a ticket's description handed to a session, in characters, and the line put at the end of one cut
// there. Text is taken as it comes, in the format the answer names (appliedContentFormat: Markdown in the full view);
// Atlassian's document format, the tree of nodes Jira's own API gives a description as, is turned into its plain text.
extern const NSInteger kJiraAboutMost;
extern NSString *const kJiraAboutCut;

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
// A statusCategory's key: its own, or, when it comes by its name alone (an issue in a view smaller than v2's full one), the key of Jira's
// category by that name; nil for one it doesn't name.
NSString *JiraCategoryKey(id category);

// The search for words typed on the card, as JQL: a key finds that ticket; words, tickets whose text has them, most
// recently changed first, done ones last. The words are quoted for JQL, so nothing typed changes the query.
NSString *JiraSearchFor(NSString *words);

// What to tell an admin who has turned this sign-in off, and why the panel says it can't sign in.
NSString *JiraBlockedWords(void);
NSString *JiraWhatToAsk(void);
