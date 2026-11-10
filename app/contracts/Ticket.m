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
@implementation TicketGroup
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
