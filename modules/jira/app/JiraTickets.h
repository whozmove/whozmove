// JiraTickets: Jira's answers, as Atlassian's server gives them, turned into the tickets every tracker gives (Ticket.h).
// Plain functions, so the tests check them with recorded answers. The server wraps Jira's own records in envelopes
// of its own (an issue under `data`, a search's under `issues.nodes`), which Atlassian has changed before, so each is
// looked for in every shape it has been seen in.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Ticket.h"

// The issue in an answer to getJiraIssue, or nil; the issues in an answer to a search.
NSDictionary *JiraIssueIn(id answer);
NSArray<NSDictionary *> *JiraIssuesIn(id answer);
// A ticket from an issue's record, on `site` (its host). Its address is made from the site and its key, never taken from
// the record. Nil without a key.
Ticket *JiraTicketFrom(NSDictionary *issue, NSString *site);
// The next steps in an answer to listJiraIssueTransitions: those Jira says the issue can take now, each with the fields
// its screen needs.
NSArray<TicketStep *> *JiraStepsIn(id answer);
// A step's fields, given as every tracker gives them (Ticket.h: text, a number, an option's name, or a list of those),
// in Jira's own shapes for that step's screen in the same answer; nil with why, in plain words, for one its screen
// doesn't have now or a value it doesn't take.
NSDictionary *JiraFieldsFor(id answer, NSString *stepId, NSDictionary *fields, NSString **why);
// The boards in an answer to listJiraBoards, as groups.
NSArray<TicketGroup *> *JiraBoardsIn(id answer);
// The Jira sites in an answer to getAccessibleAtlassianResources, as hosts, each once, in the order given.
NSArray<NSString *> *JiraSitesIn(id answer);
// An error a tool answered with, in its result rather than as a failure ({error: true, message, statusCode}): its
// status code, or 0 when the answer isn't one.
NSInteger JiraErrorIn(id answer);
// Whether that error's own words name a scope, as Jira's do for a token not allowed to do it ("scope does not match"),
// whatever its status code.
BOOL JiraErrorNamesScope(id answer);
