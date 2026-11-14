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
// Its record, with its dates where Jira gives them.
static NSDictionary *SprintRecordIn(NSDictionary *fields) {
    NSMutableArray *values = [NSMutableArray arrayWithArray:fields.allValues];
    [values addObjectsFromArray:AsRecord(fields[@"customFields"]).allValues ?: @[]];
    NSDictionary *coming = nil;
    for (id value in values) {
        NSArray *list = AsList(value) ?: AsList(AsRecord(value)[@"value"]);
        for (id item in list) {
            NSDictionary *sprint = AsRecord(item);
            NSString *state = AsText(sprint[@"state"]).lowercaseString, *name = AsText(sprint[@"name"]);
            if (!name.length || !state) continue;
            if ([state isEqualToString:@"active"]) return sprint;
            if ([state isEqualToString:@"future"]) coming = coming ?: sprint;
        }
    }
    return coming;
}

// Someone on an issue, by their account's id and the name Jira shows; nil for no one.
static TicketPerson *PersonIn(id value) {
    NSDictionary *record = AsRecord(value);
    NSString *personId = AsText(record[@"accountId"]), *name = AsText(record[@"displayName"]);
    if (!personId.length && !name.length) return nil;
    TicketPerson *person = [TicketPerson new];
    person.personId = personId;
    person.name = name;
    return person;
}

// The issues it's linked to, each with how, in Jira's words for that link from this end: an inward one ("is blocked
// by") or an outward one ("blocks").
static NSArray<TicketRef *> *LinksIn(id value) {
    NSMutableArray *links = [NSMutableArray array];
    for (id item in AsList(value)) {
        NSDictionary *link = AsRecord(item), *type = AsRecord(link[@"type"]);
        BOOL inward = AsRecord(link[@"inwardIssue"]) != nil;
        NSDictionary *other = AsRecord(link[inward ? @"inwardIssue" : @"outwardIssue"]);
        NSString *key = AsText(other[@"key"]), *how = AsText(type[inward ? @"inward" : @"outward"]);
        if (!JiraIsKey(key) || !how.length) continue;
        TicketRef *ref = [TicketRef new];
        ref.key = key;
        ref.how = how;
        ref.title = AsText(AsRecord(other[@"fields"])[@"summary"]);
        ref.type = NameOf(AsRecord(other[@"fields"])[@"issuetype"]);
        [links addObject:ref];
    }
    return links;
}

// An issue's options in its own fields that take one from a list: each custom field whose value is one option, {id,
// value} (a select list's) or {id, name}, by the field's id. A field holding a list (a sprint's, a multi-select's)
// holds several options, and each value here is one, so those are left out.
static NSString *IdOf(NSDictionary *record);
static NSDictionary *JiraValuesIn(NSDictionary *fields) {
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    for (NSString *fieldId in fields) {
        NSDictionary *option = AsRecord(fields[fieldId]);
        NSString *optionId = option ? IdOf(option) : nil;
        NSString *name = AsText(option[@"value"]) ?: AsText(option[@"name"]);
        if ([fieldId hasPrefix:@"customfield_"] && optionId.length && name.length)
            values[fieldId] = @{@"id": optionId, @"name": name};
    }
    return values;
}

// The plain text of a piece of Atlassian's document format: its text, a mention's or an emoji's own words, a link
// card's address, and a line ended after each block (a paragraph, a heading, a list's item, a code block), with each
// list item marked "- ". Marks (bold, links) and anything else it holds (media, a table's layout) are left out.
static void TextOfNode(id value, NSMutableString *text) {
    NSDictionary *node = AsRecord(value);
    if (!node) return;
    NSString *type = AsText(node[@"type"]);
    NSDictionary *attrs = AsRecord(node[@"attrs"]);
    if ([type isEqualToString:@"text"]) [text appendString:AsText(node[@"text"]) ?: @""];
    else if ([type isEqualToString:@"hardBreak"]) [text appendString:@"\n"];
    else if ([type isEqualToString:@"mention"] || [type isEqualToString:@"emoji"])
        [text appendString:AsText(attrs[@"text"]) ?: AsText(attrs[@"shortName"]) ?: @""];
    else if ([type isEqualToString:@"inlineCard"] || [type isEqualToString:@"blockCard"])
        [text appendString:AsText(attrs[@"url"]) ?: @""];
    if ([type isEqualToString:@"listItem"]) [text appendString:@"- "];
    for (id child in AsList(node[@"content"])) TextOfNode(child, text);
    if ([@[@"paragraph", @"heading", @"codeBlock", @"blockquote", @"rule", @"blockCard"] containsObject:type ?: @""]
        && ![text hasSuffix:@"\n"])
        [text appendString:@"\n"];
}

// A ticket's description as a session reads it: text as the answer gave it, or Atlassian's document format as its
// plain text; trimmed, and cut near kJiraAboutMost characters, at a word's end, with a line saying so. Nil when empty.
static NSString *AboutIn(id description) {
    NSString *about = AsText(description);
    if (!about && AsRecord(description)) {
        NSMutableString *text = [NSMutableString string];
        TextOfNode(description, text);
        about = text;
    }
    about = [about stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!about.length) return nil;
    if ((NSInteger)about.length <= kJiraAboutMost) return about;
    NSUInteger cut = [about rangeOfComposedCharacterSequenceAtIndex:kJiraAboutMost].location;
    // At the end of the last line or word before it, when there's one near enough, so no word is cut in two.
    NSRange space = [about rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet
                                           options:NSBackwardsSearch range:NSMakeRange(cut - 200, 200)];
    if (space.location != NSNotFound) cut = space.location;
    return [[about substringToIndex:cut] stringByAppendingFormat:@"\n\n%@", kJiraAboutCut];
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
                                 kind:JiraKindOf(JiraCategoryKey(status[@"statusCategory"]),
                                                 NameOf(fields[@"resolution"]))];
    ticket.priority = NameOf(fields[@"priority"]);
    ticket.assignee = NameOf(fields[@"assignee"]);
    ticket.assignedTo = PersonIn(fields[@"assignee"]);
    ticket.reporter = PersonIn(fields[@"reporter"]);
    NSMutableArray *labels = [NSMutableArray array];
    for (id label in AsList(fields[@"labels"])) if (AsText(label).length) [labels addObject:label];
    ticket.labels = labels;
    ticket.links = LinksIn(fields[@"issuelinks"]);
    ticket.updated = AsText(fields[@"updated"]);
    ticket.about = AboutIn(fields[@"description"]);
    NSDictionary *parent = AsRecord(fields[@"parent"]);
    if (JiraIsKey(AsText(parent[@"key"]))) {
        TicketRef *ref = [TicketRef new];
        ref.key = parent[@"key"];
        ref.title = AsText(AsRecord(parent[@"fields"])[@"summary"]);
        ref.type = NameOf(AsRecord(parent[@"fields"])[@"issuetype"]);
        ticket.parent = ref;
    }
    // Its project: as the answer names it, or else the one its key names, as every Jira key starts with its project's
    // (a view of an issue smaller than v2's full one leaves the project out).
    NSDictionary *project = AsRecord(fields[@"project"]);
    NSString *projectKey = AsText(project[@"key"]) ?: [key substringToIndex:[key rangeOfString:@"-"].location];
    if (projectKey.length) {
        TicketGroup *group = [TicketGroup new];
        group.groupId = projectKey;
        group.name = AsText(project[@"name"]) ?: projectKey;
        group.kind = @"project";
        NSDictionary *sprint = SprintRecordIn(fields);
        group.sprint = AsText(sprint[@"name"]);
        group.sprintStarts = AsText(sprint[@"startDate"]);
        group.sprintEnds = AsText(sprint[@"endDate"]);
        ticket.groups = @[group];
    }
    ticket.values = JiraValuesIn(fields);
    return ticket;
}

NSArray<TicketMoveMade *> *JiraMovesIn(NSDictionary *issue) {
    NSDictionary *changelog = AsRecord(issue[@"changelog"]);
    // No history in the answer isn't no moves: it's left unsaid.
    if (!AsList(changelog[@"histories"])) return nil;
    NSMutableArray *moves = [NSMutableArray array];
    for (id item in AsList(changelog[@"histories"])) {
        NSDictionary *history = AsRecord(item);
        for (id change in AsList(history[@"items"])) {
            NSDictionary *record = AsRecord(change);
            if (![AsText(record[@"field"]) isEqualToString:kJiraStatusField]) continue;
            TicketMoveMade *move = [TicketMoveMade new];
            move.from = AsText(record[@"fromString"]);
            move.to = AsText(record[@"toString"]);
            move.at = AsText(history[@"created"]);
            move.by = PersonIn(history[@"author"]);
            if (move.to.length) [moves addObject:move];
        }
    }
    // Oldest first, whichever way Jira listed them: by when, as Jira writes a time, which sorts as text.
    [moves sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(TicketMoveMade *a, TicketMoveMade *b) {
        return [a.at ?: @"" compare:b.at ?: @""];
    }];
    return moves;
}

BOOL JiraIsLastPage(id answer) {
    NSDictionary *record = AsRecord(answer), *data = AsRecord(record[@"data"]) ?: record;
    return [data[@"isLast"] isEqual:@YES];
}

NSString *JiraNextPageIn(id answer) {
    NSDictionary *record = AsRecord(answer), *data = AsRecord(record[@"data"]) ?: record;
    if ([data[@"isLast"] isEqual:@YES]) return nil;
    NSString *next = AsText(data[@"nextPageToken"]) ?: AsText(AsRecord(data[@"issues"])[@"nextPageToken"]);
    return next.length ? next : nil;
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
    NSMutableArray *options = [NSMutableArray array], *optionIds = [NSMutableArray array];
    for (id allowed in AsList(field[@"allowedValues"])) {
        if (!NameOf(allowed)) continue;
        [options addObject:NameOf(allowed)];
        NSString *optionId = AsRecord(allowed) ? IdOf(AsRecord(allowed)) : nil;
        if (optionId.length) [optionIds addObject:optionId];
    }
    f.options = options;
    f.optionIds = optionIds.count == options.count ? optionIds : @[];
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
                                kind:JiraKindOf(JiraCategoryKey(to[@"statusCategory"]), nil)];
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

// An id as Jira gives it, as text or a number.
static NSString *IdOf(NSDictionary *record) {
    return AsText(record[@"id"]) ?: [AsNumber(record[@"id"]) stringValue];
}

NSArray<NSDictionary *> *JiraTypesIn(id answer) {
    NSDictionary *record = AsRecord(answer), *data = AsRecord(record[@"data"]) ?: record;
    NSArray *list = AsList(data[@"issueTypes"]) ?: AsList(data[@"values"]) ?: AsList(record[@"data"]) ?: AsList(answer);
    NSMutableArray *types = [NSMutableArray array];
    for (id type in list) if (AsText(AsRecord(type)[@"name"])) [types addObject:type];
    return types;
}

NSString *JiraTypeIdIn(id answer, NSString *name) {
    // A site in another language names its types in it: Jira keeps the English name beside it, as untranslatedName.
    for (NSDictionary *type in JiraTypesIn(answer))
        for (NSString *named in @[AsText(type[@"untranslatedName"]) ?: @"", AsText(type[@"name"]) ?: @""])
            if ([named caseInsensitiveCompare:name] == NSOrderedSame && IdOf(type).length) return IdOf(type);
    return nil;
}

// A type's create fields, in each shape Jira has given them: a list (`fields`, `results` or `values`, a page of them),
// before that a record by field id, or a bare list.
static NSArray *CreateFieldsIn(id answer) {
    NSDictionary *record = AsRecord(answer), *data = AsRecord(record[@"data"]) ?: record;
    return AsList(data[@"fields"]) ?: AsList(data[@"results"]) ?: AsList(data[@"values"])
           ?: AsRecord(data[@"fields"]).allValues ?: AsList(answer) ?: @[];
}

NSArray<NSDictionary *> *JiraPrioritiesIn(id answer) {
    for (id each in CreateFieldsIn(answer)) {
        NSDictionary *field = AsRecord(each);
        NSString *system = AsText(AsRecord(field[@"schema"])[@"system"]);
        if (![AsText(field[@"fieldId"]) ?: AsText(field[@"key"]) ?: system ?: @"" isEqualToString:@"priority"])
            continue;
        NSMutableArray *order = [NSMutableArray array];
        for (id allowed in AsList(field[@"allowedValues"])) {
            NSString *priorityId = IdOf(AsRecord(allowed)), *name = NameOf(allowed);
            if (priorityId.length && name.length) [order addObject:@{@"id": priorityId, @"name": name}];
        }
        return order;
    }
    return @[];
}

NSArray<TicketField *> *JiraOptionFieldsIn(id answer) {
    NSMutableArray *found = [NSMutableArray array];
    for (id each in CreateFieldsIn(answer)) {
        NSDictionary *field = AsRecord(each);
        NSString *fieldId = AsText(field[@"fieldId"]) ?: AsText(field[@"key"]);
        if (![fieldId hasPrefix:@"customfield_"]) continue;
        TicketField *f = FieldFrom(fieldId, field);
        if (!f.many && [f.kind isEqualToString:@"option"] && f.optionIds.count) [found addObject:f];
    }
    return found;
}

NSString *JiraPriorityIdOf(NSDictionary *issue) {
    NSString *priorityId = IdOf(AsRecord(AsRecord(issue[@"fields"])[@"priority"]));
    return priorityId.length ? priorityId : nil;
}

BOOL JiraPlaceIn(Ticket *ticket, NSString *priorityId, NSArray<NSDictionary *> *order) {
    ticket.priorityAt = ticket.priorities = nil;
    if (!priorityId) return NO;
    for (NSUInteger at = 0; at < order.count; at++)
        if ([order[at][@"id"] isEqualToString:priorityId]) {
            ticket.priorityAt = @(at);
            ticket.priorities = @(order.count);
            return YES;
        }
    return NO;
}

NSString *JiraProjectNameIn(id answer, NSString *projectKey) {
    NSDictionary *record = AsRecord(answer);
    NSArray *list = AsList(record[@"values"]) ?: AsList(AsRecord(record[@"data"])[@"values"]) ?: @[];
    for (id item in list) {
        NSDictionary *location = AsRecord(AsRecord(item)[@"location"]);
        NSString *name = AsText(location[@"projectName"]);
        if (name.length && [AsText(location[@"projectKey"]) isEqualToString:projectKey]) return name;
    }
    return nil;
}

NSArray<NSString *> *JiraIssueTypesIn(id answer) {
    NSMutableArray *types = [NSMutableArray array];
    for (NSDictionary *type in JiraTypesIn(answer)) {
        NSString *name = AsText(type[@"name"]);
        if (name.length && ![types containsObject:name]) [types addObject:name];
    }
    return types;
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
    NSArray *list = AsList(answer) ?: AsList(record[@"data"]) ?: AsList(record[@"resources"])
                    ?: AsList(AsRecord(record[@"data"])[@"resources"]);
    NSMutableArray *sites = [NSMutableArray array];
    for (id item in list) {
        NSDictionary *r = AsRecord(item);
        NSString *host = [NSURL URLWithString:AsText(r[@"url"]) ?: @""].host.lowercaseString;
        // The same site can come once for Jira and once for Confluence, said by its scopes or by its products: only
        // one that can hold Jira counts, and one that says neither might.
        NSArray *scopes = AsList(r[@"scopes"]), *products = AsList(r[@"products"]);
        BOOL jira = !scopes.count && !products.count;
        for (id scope in scopes) if ([AsText(scope) containsString:kJiraScopeWord]) jira = YES;
        for (id product in products) if ([AsText(AsRecord(product)[@"id"]) isEqualToString:kJiraProductId]) jira = YES;
        if (JiraIsSite(host) && jira && ![sites containsObject:host]) [sites addObject:host];
    }
    return sites;
}

// The record an error is in: the answer itself ({error: true, message, statusCode}), or, as v2 turns a request away,
// its data ({data: {error: "TRANSITION_FAILED", message, problems, status}}).
static NSDictionary *ErrorRecord(id answer) {
    NSDictionary *record = AsRecord(answer), *data = AsRecord(record[@"data"]);
    if ([record[@"error"] isEqual:@YES]) return record;
    if ([data[@"error"] isEqual:@YES] || AsText(data[@"error"]).length) return data;
    return nil;
}

NSInteger JiraErrorIn(id answer) {
    NSDictionary *record = ErrorRecord(answer);
    if (!record) return 0;
    NSInteger status = 0;
    for (NSString *name in @[@"statusCode", @"status"]) {
        id given = record[name];
        NSString *digits = AsText(given);
        if (AsNumber(given)) status = [given integerValue];
        // v2 has been seen to give it as text, "400".
        else if (digits.length && [digits rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet]
                 .location == NSNotFound) status = digits.integerValue;
        if (status) break;
    }
    return status ? status : 500;
}

NSString *JiraErrorWords(id answer) {
    NSDictionary *record = ErrorRecord(answer);
    NSMutableArray *reasons = [NSMutableArray array];
    for (id problem in AsList(record[@"problems"])) {
        NSString *reason = AsText(AsRecord(problem)[@"reason"]);
        if (reason.length && ![reasons containsObject:reason]) [reasons addObject:reason];
    }
    NSString *words = reasons.count ? [reasons componentsJoinedByString:@" "] : AsText(record[@"message"]);
    return words.length ? Clip(words, 300) : nil;
}

BOOL JiraTurnedAway(id answer) {
    // A 4xx but those that say something else: a sign-in, an admin or a scope, no such ticket, or slowing down.
    NSInteger status = JiraErrorIn(answer);
    return status >= 400 && status < 500 && status != 401 && status != 403 && status != 404 && status != 429;
}

BOOL JiraErrorNamesScope(id answer) {
    if (!JiraErrorIn(answer)) return NO;
    NSString *message = AsText(ErrorRecord(answer)[@"message"]);
    return message && [message rangeOfString:@"scope" options:NSCaseInsensitiveSearch].location != NSNotFound;
}
