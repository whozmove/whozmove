// JiraTickets: Jira's issues, transitions, boards and sites, read from the server's answers.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "JiraTickets.h"
#import "JiraFacts.h"
#import "Files.h"

// Whether a record is an issue: a key, and its fields.
static BOOL IsIssue(id value) {
    NSDictionary *record = AsRecord(value);
    return AsText(record[@"key"]).length && AsRecord(record[@"fields"]);
}

NSDictionary *JiraIssueIn(id answer) {
    NSDictionary *record = AsRecord(answer);
    for (id candidate in @[record ?: @{}, record[@"data"] ?: @{}, record[@"issue"] ?: @{}])
        if (IsIssue(candidate)) return candidate;
    return JiraIssuesIn(answer).firstObject;
}

NSArray<NSDictionary *> *JiraIssuesIn(id answer) {
    NSDictionary *record = AsRecord(answer);
    NSDictionary *data = AsRecord(record[@"data"]) ?: record;
    id issues = data[@"issues"];
    NSArray *list = AsList(AsRecord(issues)[@"nodes"]) ?: AsList(issues) ?: AsList(data[@"nodes"]) ?: AsList(answer);
    NSMutableArray *found = [NSMutableArray array];
    for (id issue in list) if (IsIssue(issue)) [found addObject:issue];
    return found;
}

static NSString *NameOf(id value) {
    NSDictionary *record = AsRecord(value);
    return AsText(record[@"name"]) ?: AsText(record[@"displayName"]) ?: AsText(record[@"value"]) ?: AsText(value);
}

// The sprint the issue is in now: a field whose value is a list of sprints ({name, state}), the active one first, else
// the next one coming. Jira keeps it in a custom field whose id differs from site to site, so it's found by its shape.
static NSString *SprintIn(NSDictionary *fields) {
    NSMutableArray *values = [NSMutableArray arrayWithArray:fields.allValues];
    [values addObjectsFromArray:AsRecord(fields[@"customFields"]).allValues ?: @[]];
    NSString *coming = nil;
    for (id value in values) {
        NSArray *list = AsList(value) ?: AsList(AsRecord(value)[@"value"]);
        for (id item in list) {
            NSDictionary *sprint = AsRecord(item);
            NSString *state = AsText(sprint[@"state"]).lowercaseString, *name = AsText(sprint[@"name"]);
            if (!name.length || !state) continue;
            if ([state isEqualToString:@"active"]) return name;
            if ([state isEqualToString:@"future"]) coming = coming ?: name;
        }
    }
    return coming;
}

Ticket *JiraTicketFrom(NSDictionary *issue, NSString *site) {
    NSString *key = AsText(issue[@"key"]);
    if (!JiraIsKey(key)) return nil;
    NSDictionary *fields = AsRecord(issue[@"fields"]) ?: @{};
    NSDictionary *status = AsRecord(fields[@"status"]);
    Ticket *ticket = [Ticket new];
    ticket.tracker = @"Jira";
    ticket.site = site;
    ticket.key = key;
    ticket.ticketId = AsText(issue[@"id"]);
    ticket.title = AsText(fields[@"summary"]);
    ticket.link = JiraLinkFor(key, site);
    ticket.type = NameOf(fields[@"issuetype"]);
    ticket.state = [TicketState named:NameOf(status) ?: @""
                                 kind:JiraKindOf(AsText(AsRecord(status[@"statusCategory"])[@"key"]),
                                                 NameOf(fields[@"resolution"]))];
    ticket.priority = NameOf(fields[@"priority"]);
    ticket.assignee = NameOf(fields[@"assignee"]);
    NSDictionary *parent = AsRecord(fields[@"parent"]);
    if (JiraIsKey(AsText(parent[@"key"]))) {
        TicketRef *ref = [TicketRef new];
        ref.key = parent[@"key"];
        ref.title = AsText(AsRecord(parent[@"fields"])[@"summary"]);
        ref.type = NameOf(AsRecord(parent[@"fields"])[@"issuetype"]);
        ticket.parent = ref;
    }
    NSDictionary *project = AsRecord(fields[@"project"]);
    if (AsText(project[@"key"])) {
        TicketGroup *group = [TicketGroup new];
        group.groupId = project[@"key"];
        group.name = AsText(project[@"name"]) ?: project[@"key"];
        group.kind = @"project";
        group.sprint = SprintIn(fields);
        ticket.groups = @[group];
    }
    return ticket;
}

// A field's schema type in Jira, and whether it takes a list ("array", its items' type then the one that counts).
static NSString *SchemaType(NSDictionary *field, BOOL *many) {
    NSDictionary *schema = AsRecord(field[@"schema"]);
    *many = [AsText(schema[@"type"]) isEqualToString:@"array"];
    return (*many ? AsText(schema[@"items"]) : AsText(schema[@"type"])) ?: @"string";
}

// A field a transition's screen has: its name, its kind in every tracker's words (Ticket.h) from Jira's schema type,
// whether it's required, whether it takes a list, and the values it takes, when it takes only some.
static TicketField *FieldFrom(NSString *fieldId, NSDictionary *field) {
    TicketField *f = [TicketField new];
    f.fieldId = AsText(field[@"key"]) ?: fieldId;
    f.name = AsText(field[@"name"]) ?: fieldId;
    BOOL many = NO;
    NSString *type = SchemaType(field, &many);
    f.many = many;
    f.required = [AsNumber(field[@"required"]) boolValue];
    NSMutableArray *options = [NSMutableArray array];
    for (id allowed in AsList(field[@"allowedValues"])) if (NameOf(allowed)) [options addObject:NameOf(allowed)];
    f.options = options;
    f.kind = options.count ? @"option" : [type isEqualToString:@"number"] ? @"number"
        : [@[@"date", @"datetime"] containsObject:type] ? @"date" : [type isEqualToString:@"user"] ? @"person" : @"text";
    return f;
}

// The transitions in an answer to listJiraIssueTransitions, as Jira's own records.
static NSArray *TransitionsIn(id answer) {
    NSDictionary *record = AsRecord(answer);
    return AsList(record[@"transitions"]) ?: AsList(AsRecord(record[@"data"])[@"transitions"])
           ?: AsList(record[@"data"]) ?: AsList(answer) ?: @[];
}

static NSString *TransitionId(NSDictionary *t) {
    return AsText(t[@"id"]) ?: [AsNumber(t[@"id"]) stringValue];
}

NSArray<TicketStep *> *JiraStepsIn(id answer) {
    NSMutableArray *steps = [NSMutableArray array];
    for (id item in TransitionsIn(answer)) {
        NSDictionary *t = AsRecord(item);
        NSString *stepId = TransitionId(t);
        NSDictionary *to = AsRecord(t[@"to"]);
        if (!stepId.length || !to || [t[@"isAvailable"] isEqual:@NO]) continue;
        TicketStep *step = [TicketStep new];
        step.stepId = stepId;
        step.name = AsText(t[@"name"]) ?: NameOf(to);
        step.to = [TicketState named:NameOf(to) ?: @""
                                kind:JiraKindOf(AsText(AsRecord(to[@"statusCategory"])[@"key"]), nil)];
        NSMutableArray *needs = [NSMutableArray array];
        NSDictionary *fields = AsRecord(t[@"fields"]);
        for (NSString *fieldId in [fields.allKeys sortedArrayUsingSelector:@selector(compare:)])
            if (AsRecord(fields[fieldId])) [needs addObject:FieldFrom(fieldId, fields[fieldId])];
        step.needs = needs;
        [steps addObject:step];
    }
    return steps;
}

// One value in Jira's own shape for a field: text and dates as text, a number as a number, and an option (a
// resolution, a priority, a version, a select's choice) by the id Jira gave it among the field's allowed values,
// found by its name. Nil for a value it doesn't take, or a kind a name can't give (a person, whom Jira knows only by
// an account id).
static id JiraValueOf(NSDictionary *field, NSString *type, id value) {
    NSArray *allowed = AsList(field[@"allowedValues"]);
    if ([@[@"string", @"date", @"datetime"] containsObject:type]) return AsText(value).length ? value : nil;
    if ([type isEqualToString:@"number"])
        return AsNumber(value) && CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID() ? value : nil;
    for (id each in allowed) {
        NSDictionary *option = AsRecord(each);
        if (!option || !AsText(value) || ![NameOf(option) isEqualToString:value]) continue;
        NSString *optionId = AsText(option[@"id"]) ?: [AsNumber(option[@"id"]) stringValue];
        if (optionId.length) return @{@"id": optionId};
        return AsText(option[@"value"]) ? @{@"value": value} : @{@"name": value};
    }
    return nil;
}

NSDictionary *JiraFieldsFor(id answer, NSString *stepId, NSDictionary *fields, NSString **why) {
    NSDictionary *screen = nil;
    for (id item in TransitionsIn(answer))
        if ([TransitionId(AsRecord(item)) isEqualToString:stepId]) screen = AsRecord(AsRecord(item)[@"fields"]) ?: @{};
    NSMutableDictionary *shaped = [NSMutableDictionary dictionary];
    for (NSString *fieldId in [fields.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSDictionary *field = AsRecord(screen[fieldId]);
        for (NSString *each in screen)
            if (!field && [AsText(AsRecord(screen[each])[@"key"]) isEqualToString:fieldId]) field = screen[each];
        NSString *name = AsText(field[@"name"]) ?: fieldId;
        if (!field) {
            *why = [NSString stringWithFormat:@"This step doesn't set %@ now", name];
            return nil;
        }
        BOOL many = NO;
        NSString *type = SchemaType(field, &many);
        NSArray *given = many ? (AsList(fields[fieldId]) ?: @[fields[fieldId]]) : @[fields[fieldId]];
        NSMutableArray *each = [NSMutableArray array];
        for (id value in given) {
            id jira = AsList(value) ? nil : JiraValueOf(field, type, value);
            if (!jira) {
                *why = [type isEqualToString:@"user"]
                    ? [NSString stringWithFormat:@"%@ is a person to pick in Jira itself, so move it there", name]
                    : [NSString stringWithFormat:@"%@ doesn't take that now", name];
                return nil;
            }
            [each addObject:jira];
        }
        shaped[fieldId] = many ? each : each.firstObject;
    }
    return shaped;
}

NSArray<TicketGroup *> *JiraBoardsIn(id answer) {
    NSDictionary *record = AsRecord(answer);
    NSArray *list = AsList(record[@"values"]) ?: AsList(AsRecord(record[@"data"])[@"values"])
                    ?: AsList(record[@"boards"]) ?: AsList(answer);
    NSMutableArray *boards = [NSMutableArray array];
    for (id item in list) {
        NSDictionary *b = AsRecord(item);
        NSString *name = AsText(b[@"name"]);
        if (!name.length) continue;
        TicketGroup *group = [TicketGroup new];
        group.groupId = AsText(b[@"id"]) ?: [AsNumber(b[@"id"]) stringValue];
        group.name = name;
        group.kind = @"board";
        [boards addObject:group];
    }
    return boards;
}

NSArray<NSString *> *JiraSitesIn(id answer) {
    NSDictionary *record = AsRecord(answer);
    NSArray *list = AsList(answer) ?: AsList(record[@"data"]) ?: AsList(record[@"resources"]);
    NSMutableArray *sites = [NSMutableArray array];
    for (id item in list) {
        NSDictionary *r = AsRecord(item);
        NSString *host = [NSURL URLWithString:AsText(r[@"url"]) ?: @""].host.lowercaseString;
        // The same site comes once for Jira's scopes and once for Confluence's: only one that can hold Jira counts.
        NSArray *scopes = AsList(r[@"scopes"]);
        BOOL jira = !scopes.count;
        for (id scope in scopes) if ([AsText(scope) containsString:@"jira"]) jira = YES;
        if (JiraIsSite(host) && jira && ![sites containsObject:host]) [sites addObject:host];
    }
    return sites;
}

NSInteger JiraErrorIn(id answer) {
    NSDictionary *record = AsRecord(answer);
    if (![record[@"error"] isEqual:@YES]) return 0;
    NSInteger status = [AsNumber(record[@"statusCode"]) integerValue];
    return status ? status : 500;
}

BOOL JiraErrorNamesScope(id answer) {
    if (!JiraErrorIn(answer)) return NO;
    NSString *message = AsText(AsRecord(answer)[@"message"]);
    return message && [message rangeOfString:@"scope" options:NSCaseInsensitiveSearch].location != NSNotFound;
}
