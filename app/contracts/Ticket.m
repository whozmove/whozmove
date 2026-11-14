// Ticket: one ticket, the same for every tracker.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Ticket.h"

NSString *TicketKindWord(TicketKind kind) {
    switch (kind) {
        case TicketKindToDo: return @"todo";
        case TicketKindUnderWay: return @"doing";
        case TicketKindDone: return @"done";
        case TicketKindDropped: return @"dropped";
    }
    return @"todo";
}

@implementation TicketState
+ (instancetype)named:(NSString *)name kind:(TicketKind)kind {
    TicketState *state = [self new];
    state->_name = [name copy];
    state->_kind = kind;
    return state;
}
- (NSDictionary *)json {
    return @{@"name": self.name ?: @"", @"kind": TicketKindWord(self.kind)};
}
@end

@implementation TicketRef
@end
@implementation TicketPerson
@end
@implementation TicketGroup
@end
@implementation TicketMoveMade
@end
@implementation TicketField
@end
@implementation TicketStep
@end

// A record with only what's there: no nulls for the page or a session to trip on.
static void Put(NSMutableDictionary *into, NSString *key, id value) {
    if (value) into[key] = value;
}

@implementation Ticket

- (NSDictionary *)json {
    NSMutableDictionary *json = [NSMutableDictionary dictionary];
    Put(json, @"tracker", self.tracker);
    Put(json, @"site", self.site);
    Put(json, @"key", self.key);
    Put(json, @"id", self.ticketId);
    Put(json, @"title", self.title);
    Put(json, @"link", self.link);
    Put(json, @"type", self.type);
    Put(json, @"state", [self.state json]);
    Put(json, @"priority", self.priority);
    if (self.priorityAt && self.priorities) {
        json[@"priorityAt"] = self.priorityAt;
        json[@"priorities"] = self.priorities;
    }
    Put(json, @"assignee", self.assignee);
    if (self.parent.key) {
        NSMutableDictionary *parent = [NSMutableDictionary dictionary];
        Put(parent, @"key", self.parent.key);
        Put(parent, @"title", self.parent.title);
        Put(parent, @"type", self.parent.type);
        json[@"parent"] = parent;
    }
    NSMutableArray *groups = [NSMutableArray array];
    for (TicketGroup *g in self.groups) {
        NSMutableDictionary *group = [NSMutableDictionary dictionary];
        Put(group, @"id", g.groupId);
        Put(group, @"name", g.name);
        Put(group, @"kind", g.kind);
        Put(group, @"sprint", g.sprint);
        [groups addObject:group];
    }
    json[@"groups"] = groups;
    NSMutableArray *steps = [NSMutableArray array];
    for (TicketStep *s in self.steps) {
        NSMutableArray *needs = [NSMutableArray array];
        for (TicketField *f in s.needs) {
            NSMutableDictionary *field = [NSMutableDictionary dictionary];
            Put(field, @"id", f.fieldId);
            Put(field, @"name", f.name);
            Put(field, @"kind", f.kind);
            field[@"required"] = @(f.required);
            if (f.many) field[@"many"] = @YES;
            Put(field, @"options", f.options.count ? f.options : nil);
            [needs addObject:field];
        }
        NSMutableDictionary *step = [NSMutableDictionary dictionary];
        Put(step, @"id", s.stepId);
        Put(step, @"name", s.name);
        Put(step, @"to", [s.to json]);
        step[@"needs"] = needs;
        [steps addObject:step];
    }
    json[@"steps"] = steps;
    return json;
}

- (NSDictionary *)jsonWhole {
    NSMutableDictionary *json = [[self json] mutableCopy];
    Put(json, @"assigneeId", self.assignedTo.personId);
    if (self.reporter.personId || self.reporter.name) {
        NSMutableDictionary *reporter = [NSMutableDictionary dictionary];
        Put(reporter, @"id", self.reporter.personId);
        Put(reporter, @"name", self.reporter.name);
        json[@"reporter"] = reporter;
    }
    if (self.labels.count) json[@"labels"] = self.labels;
    if (self.links.count) {
        NSMutableArray *links = [NSMutableArray array];
        for (TicketRef *l in self.links) {
            NSMutableDictionary *link = [NSMutableDictionary dictionary];
            Put(link, @"how", l.how);
            Put(link, @"key", l.key);
            Put(link, @"title", l.title);
            Put(link, @"type", l.type);
            [links addObject:link];
        }
        json[@"links"] = links;
    }
    Put(json, @"updated", self.updated);
    NSMutableArray *groups = [NSMutableArray array];
    for (NSUInteger i = 0; i < [json[@"groups"] count]; i++) {
        NSMutableDictionary *group = [json[@"groups"][i] mutableCopy];
        TicketGroup *g = i < self.groups.count ? self.groups[i] : nil;
        Put(group, @"sprintStarts", g.sprintStarts);
        Put(group, @"sprintEnds", g.sprintEnds);
        [groups addObject:group];
    }
    json[@"groups"] = groups;
    if (self.moves) {
        NSMutableArray *moves = [NSMutableArray array];
        for (TicketMoveMade *m in self.moves) {
            NSMutableDictionary *move = [NSMutableDictionary dictionary];
            Put(move, @"from", m.from);
            Put(move, @"to", m.to);
            Put(move, @"at", m.at);
            if (m.by.personId || m.by.name) {
                NSMutableDictionary *by = [NSMutableDictionary dictionary];
                Put(by, @"id", m.by.personId);
                Put(by, @"name", m.by.name);
                move[@"by"] = by;
            }
            [moves addObject:move];
        }
        json[@"moves"] = moves;
    }
    return json;
}

@end

@implementation TrackerAnswer
+ (instancetype)done {
    return [self end:TrackerEndDone why:nil];
}
+ (instancetype)end:(TrackerEnd)end why:(NSString *)why {
    TrackerAnswer *answer = [self new];
    answer->_end = end;
    answer->_why = [why copy];
    return answer;
}
- (BOOL)ok {
    return self.end == TrackerEndDone;
}
@end
