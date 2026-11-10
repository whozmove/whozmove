// JiraTickets: Jira's answers, as Atlassian's server gives them, turned into the tickets every tracker gives (Ticket.h).
// Plain functions, so the tests check them with recorded answers. The server wraps Jira's own records in envelopes
// of its own (each under `data`; a search's issues once under `issues.nodes`), which Atlassian has changed before, so
// each is looked for in every shape it has been seen in.
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
// A project's issue types in an answer to listJiraProjectIssueTypesMetadata, as Jira's own records; and the id of the
// one named `name` among them, or nil.
NSArray<NSDictionary *> *JiraTypesIn(id answer);
NSString *JiraTypeIdIn(id answer, NSString *name);
// A project's priorities in an answer to getJiraIssueTypeMetaWithFields (JiraFacts), in its scheme's order, the most
// pressing first, each {id, name}: the priority field's allowed values, wherever that answer lists its fields. Empty
// when it has no priority field, or none with an id.
NSArray<NSDictionary *> *JiraPrioritiesIn(id answer);
// The fields in an answer to getJiraIssueTypeMetaWithFields that take one option from a list, among a project's own
// (custom) fields, each with its options and their ids, wherever that answer lists its fields.
NSArray<TicketField *> *JiraOptionFieldsIn(id answer);
// The id of an issue's priority, as Jira gave it, or nil for none.
NSString *JiraPriorityIdOf(NSDictionary *issue);
// A ticket's place among its project's priorities (`order`, as JiraPrioritiesIn gives them), matched by Jira's id: its
// priorityAt and priorities set, and YES; or left without them, and NO, when the id isn't among them (a priority given
// since the list was read, or none at all).
BOOL JiraPlaceIn(Ticket *ticket, NSString *priorityId, NSArray<NSDictionary *> *order);
// The boards in an answer to listJiraBoards, as groups; and the name it gives the project by that key, if it does.
NSArray<TicketGroup *> *JiraBoardsIn(id answer);
NSString *JiraProjectNameIn(id answer, NSString *projectKey);
// The names of the types in an answer to listJiraProjectIssueTypesMetadata, each once.
NSArray<NSString *> *JiraIssueTypesIn(id answer);
// The Jira sites in an answer to getAccessibleAtlassianResources, as hosts, each once, in the order given.
NSArray<NSString *> *JiraSitesIn(id answer);
// An error a tool answered with, in its result rather than as a failure ({error: true, message, statusCode}, or as v2
// turns a request away, {data: {error: "…", message, problems, status}}): its status code, given as a number or as its
// digits in text, 500 when it gives none, or 0 when the answer isn't one.
NSInteger JiraErrorIn(id answer);
// Whether that error's own words name a scope, as Jira's do for a token not allowed to do it ("scope does not match"),
// whatever its status code.
BOOL JiraErrorNamesScope(id answer);
// That error's own words, why Jira turned it away (each of its problems' reasons, else its message), clipped; nil when
// the answer isn't one or says nothing.
NSString *JiraErrorWords(id answer);
// Whether that error turns the request away as it is, which trying again won't change: a 4xx that isn't a sign-in's, an
// admin's, no such ticket or slowing down, whether or not it says why. A 5xx is Jira not managing it just then, even
// with reasons given.
BOOL JiraTurnedAway(id answer);
