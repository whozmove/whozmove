// InboxRecord: the inbox's record, as plain functions (InboxRecord.h).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "InboxRecord.h"
#import "Files.h"
#import "Text.h"

NSArray<NSString *> *const InboxPriorities = @[@"urgent", @"question", @"report", @"note"];
const NSUInteger InboxMostText = 8000, InboxMostAbout = 40, InboxMostNote = 400;
const NSUInteger InboxMostWaiting = 50;

static const double kDay = 24 * 60 * 60 * 1000.0;
// How long a message is kept: an answered one a week, one nobody answered two, so a lead back after a few days still
// finds it.
static const double kAnsweredKept = 7 * kDay, kWaitingKept = 14 * kDay;
static const NSUInteger kWeeksKept = 8;
// What a line's fate counts as in its week: each once.
static NSArray<NSString *> *const kCounted = @[@"held", @"expired", @"denied", @"dropped", @"failed"];

static NSDictionary *Empty(void) {
    return @{@"version": @1, @"messages": @[], @"weeks": @[]};
}

static NSArray<NSDictionary *> *RecordsIn(id list) {
    NSMutableArray *records = [NSMutableArray array];
    for (id each in AsList(list))
        if (AsRecord(each)) [records addObject:each];
    return records;
}

NSDictionary *InboxRecordFrom(id json) {
    NSDictionary *record = AsRecord(json);
    if (!record) return Empty();
    NSMutableArray *messages = [NSMutableArray array];
    for (NSDictionary *message in RecordsIn(record[@"messages"])) {
        // Only one with what every reader goes by: its id, its sender's session, its lead's project, its priority,
        // its time and its words.
        if (!IsPlainId(AsText(message[@"id"]), 16) || !AsText(AsRecord(message[@"from"])[@"session"])
            || !AsText(AsRecord(message[@"to"])[@"lead"]) || ![InboxPriorities containsObject:message[@"priority"] ?: @""]
            || !AsNumber(message[@"at"]) || !AsText(message[@"text"]))
            continue;
        [messages addObject:message];
    }
    return @{@"version": @1, @"messages": messages, @"weeks": RecordsIn(record[@"weeks"])};
}

NSString *InboxWhyNotWords(NSString *text, NSString *about) {
    if (![text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length)
        return @"give the message on stdin";
    if (text.length > InboxMostText)
        return [NSString stringWithFormat:@"a message may be %@ characters at most: put the rest in a file and give "
                                          @"its path", [NSNumberFormatter localizedStringFromNumber:@(InboxMostText)
                                                                                         numberStyle:NSNumberFormatterDecimalStyle]];
    if (LooksLikeSecret(text) || (about && LooksLikeSecret(about)))
        return @"it has something shaped like a key in it: take it out, and say where it's kept";
    return nil;
}

// A new id, m- and six hex digits, none the record has.
static NSString *NewId(NSArray<NSDictionary *> *messages) {
    NSSet *taken = [NSSet setWithArray:[messages valueForKey:@"id"]];
    NSString *messageId;
    do messageId = [NSString stringWithFormat:@"m-%06x", arc4random_uniform(0x1000000)];
    while ([taken containsObject:messageId]);
    return messageId;
}

static BOOL Answered(NSDictionary *message) {
    return AsNumber(message[@"answeredAt"]) != nil;
}

NSDictionary *InboxRecordKeep(NSDictionary *record, NSDictionary *from, NSString *project, NSString *priority,
                              NSString *about, NSString *text, double now, NSString **kept, NSString **why) {
    NSArray *messages = record[@"messages"] ?: @[];
    NSUInteger waiting = 0;
    for (NSDictionary *message in messages)
        if (!Answered(message) && [message[@"from"][@"session"] isEqual:from[@"session"]]) waiting++;
    if (waiting >= InboxMostWaiting) {
        if (why) *why = [NSString stringWithFormat:@"%lu of this session's messages wait unanswered already: wait for "
                                                   @"the lead to answer some", (unsigned long)waiting];
        return nil;
    }
    NSString *messageId = NewId(messages);
    NSMutableDictionary *message = [@{@"id": messageId, @"from": from, @"to": @{@"lead": project},
                                      @"priority": priority, @"at": @(now), @"text": text} mutableCopy];
    if (about.length) message[@"about"] = about;
    NSMutableDictionary *next = [record mutableCopy];
    next[@"messages"] = [messages arrayByAddingObject:message];
    if (kept) *kept = messageId;
    return next;
}

static NSArray<NSDictionary *> *Ordered(NSArray<NSDictionary *> *messages) {
    return [messages sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSDictionary *a,
                                                                                             NSDictionary *b) {
        NSUInteger ra = [InboxPriorities indexOfObject:a[@"priority"]], rb = [InboxPriorities indexOfObject:b[@"priority"]];
        if (ra != rb) return ra < rb ? NSOrderedAscending : NSOrderedDescending;
        return [AsNumber(a[@"at"]) compare:AsNumber(b[@"at"]) ?: @0];
    }];
}

NSArray<NSDictionary *> *InboxWaiting(NSDictionary *record, NSString *project) {
    NSMutableArray *waiting = [NSMutableArray array];
    for (NSDictionary *message in record[@"messages"])
        if (!Answered(message) && [message[@"to"][@"lead"] isEqual:project]) [waiting addObject:message];
    return Ordered(waiting);
}

NSDictionary *InboxNextFor(NSDictionary *record, NSString *project, NSString *reader) {
    for (NSDictionary *message in InboxWaiting(record, project))
        if (![message[@"readBy"] isEqual:reader]) return message;
    return nil;
}

NSDictionary *InboxMessage(NSDictionary *record, NSString *messageId) {
    for (NSDictionary *message in record[@"messages"])
        if ([message[@"id"] isEqual:messageId]) return message;
    return nil;
}

// The record with one message changed by `change`, or nil when it isn't there.
static NSDictionary *Changed(NSDictionary *record, NSString *messageId, void (^change)(NSMutableDictionary *message)) {
    NSMutableArray *messages = [record[@"messages"] mutableCopy];
    for (NSUInteger i = 0; i < messages.count; i++) {
        if (![messages[i][@"id"] isEqual:messageId]) continue;
        NSMutableDictionary *message = [messages[i] mutableCopy];
        change(message);
        messages[i] = message;
        NSMutableDictionary *next = [record mutableCopy];
        next[@"messages"] = messages;
        return next;
    }
    return nil;
}

NSDictionary *InboxRecordRead(NSDictionary *record, NSString *messageId, NSString *reader, double now) {
    return Changed(record, messageId, ^(NSMutableDictionary *message) {
        message[@"readAt"] = @(now);
        message[@"readBy"] = reader;
    }) ?: record;
}

NSDictionary *InboxRecordAnswered(NSDictionary *record, NSString *messageId, NSString *reader, NSString *note,
                                  double now, NSString **said, NSString **why) {
    NSDictionary *message = InboxMessage(record, messageId);
    if (!message) {
        if (why) *why = [NSString stringWithFormat:@"no message %@ is in this inbox: name one by the id inbox-next gave",
                                                   messageId];
        return nil;
    }
    if (Answered(message)) {
        if (said) *said = [NSString stringWithFormat:@"answered %@ already", messageId];
        return record;
    }
    if (said) *said = [@"answered " stringByAppendingString:messageId];
    return Changed(record, messageId, ^(NSMutableDictionary *changed) {
        changed[@"answeredAt"] = @(now);
        changed[@"answeredBy"] = reader;
        // Answered without reading it first, it counts as read then too.
        if (!changed[@"readAt"]) {
            changed[@"readAt"] = @(now);
            changed[@"readBy"] = reader;
        }
        if (note.length) changed[@"note"] = note;
    });
}

NSString *InboxLine(NSDictionary *message) {
    NSString *name = AsText(message[@"from"][@"name"]);
    return [NSString stringWithFormat:@"Inbox %@ · %@ from %@: %@", message[@"id"], message[@"priority"],
                                      name.length ? name : @"a session", PlainOneLine(message[@"text"], 80)];
}

NSString *InboxIdInLine(NSString *line) {
    static NSRegularExpression *start;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        start = [NSRegularExpression regularExpressionWithPattern:@"^Inbox (m-[0-9a-f]{6}) · " options:0 error:nil];
    });
    if (!line.length) return nil;
    NSTextCheckingResult *found = [start firstMatchInString:line options:0 range:NSMakeRange(0, MIN(line.length, 40u))];
    return found ? [line substringWithRange:[found rangeAtIndex:1]] : nil;
}

// The Monday a time's week starts on, in this Mac's time zone, as 2030-01-07.
static NSString *WeekOf(double at) {
    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierISO8601];
    calendar.timeZone = NSTimeZone.localTimeZone;
    NSDate *start = nil;
    [calendar rangeOfUnit:NSCalendarUnitWeekOfYear startDate:&start interval:NULL
                  forDate:[NSDate dateWithTimeIntervalSince1970:at / 1000]];
    NSDateComponents *day = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay
                                        fromDate:start];
    return [NSString stringWithFormat:@"%04ld-%02ld-%02ld", (long)day.year, (long)day.month, (long)day.day];
}

// The record with `what` counted once for a project's week, by `key`.
static NSDictionary *Counted(NSDictionary *record, NSString *project, NSString *what, NSString *key, double now) {
    NSString *week = WeekOf(now);
    NSMutableArray *weeks = [record[@"weeks"] ?: @[] mutableCopy];
    NSUInteger at = [weeks indexOfObjectPassingTest:^BOOL(NSDictionary *each, NSUInteger i, BOOL *stop) {
        return [each[@"week"] isEqual:week] && [each[@"project"] isEqual:project];
    }];
    NSMutableDictionary *counts = at == NSNotFound ? [@{@"week": week, @"project": project} mutableCopy]
                                                   : [weeks[at] mutableCopy];
    NSArray *seen = AsList(counts[@"seen"]) ?: @[];
    if ([seen containsObject:key]) return record;
    counts[@"seen"] = [seen arrayByAddingObject:key];
    counts[what] = @(AsNumber(counts[what]).integerValue + 1);
    if (at == NSNotFound) [weeks addObject:counts];
    else weeks[at] = counts;
    NSMutableDictionary *next = [record mutableCopy];
    next[@"weeks"] = weeks;
    return next;
}

NSDictionary *InboxRecordRing(NSDictionary *record, NSString *keptId, NSString *sender, NSString *lineId,
                              NSString *state, double at, double now) {
    NSDictionary *message = InboxMessage(record, keptId);
    if (!message || ![message[@"from"][@"session"] isEqual:sender] || !lineId.length || !state.length) return record;
    NSDictionary *told = @{@"messageId": lineId, @"state": state, @"at": @(at)};
    // The newest word on how the lead was told stands: a line sent again takes the first one's place.
    if ([AsRecord(message[@"told"]) isEqual:told]) return record;
    NSDictionary *next = Changed(record, keptId, ^(NSMutableDictionary *changed) { changed[@"told"] = told; });
    if ([kCounted containsObject:state])
        next = Counted(next, message[@"to"][@"lead"], state, [NSString stringWithFormat:@"%@:%@", lineId, state], now);
    return next;
}

NSDictionary *InboxRecordLost(NSDictionary *record, NSString *project, NSString *messageId, double now) {
    return Counted(record, project, @"lost", [@"lost:" stringByAppendingString:messageId], now);
}

NSDictionary *InboxWeekCounts(NSDictionary *record, NSString *project, double now) {
    NSString *week = WeekOf(now);
    NSMutableDictionary *counts = [NSMutableDictionary dictionary];
    for (NSString *what in [kCounted arrayByAddingObject:@"lost"]) counts[what] = @0;
    for (NSDictionary *each in record[@"weeks"]) {
        if (![each[@"week"] isEqual:week] || (project && ![each[@"project"] isEqual:project])) continue;
        for (NSString *what in counts.allKeys)
            counts[what] = @([counts[what] integerValue] + AsNumber(each[what]).integerValue);
    }
    return counts;
}

NSDictionary *InboxRecordPrune(NSDictionary *record, double now) {
    NSMutableArray *messages = [NSMutableArray array];
    for (NSDictionary *message in record[@"messages"]) {
        double at = AsNumber(message[@"at"]).doubleValue;
        double answered = AsNumber(message[@"answeredAt"]).doubleValue;
        if (answered ? now - answered < kAnsweredKept : now - at < kWaitingKept) [messages addObject:message];
    }
    // Only the last few weeks' counts, by the Monday each starts on, which sorts as its date does.
    NSArray *names = [[NSSet setWithArray:[record[@"weeks"] valueForKey:@"week"]].allObjects
                      sortedArrayUsingSelector:@selector(compare:)];
    NSUInteger keep = MIN(kWeeksKept, names.count);
    NSSet *recent = [NSSet setWithArray:[names subarrayWithRange:NSMakeRange(names.count - keep, keep)]];
    NSMutableArray *weeks = [NSMutableArray array];
    for (NSDictionary *each in record[@"weeks"])
        if ([recent containsObject:each[@"week"]]) [weeks addObject:each];
    if (messages.count == [record[@"messages"] count] && weeks.count == [record[@"weeks"] count]) return record;
    NSMutableDictionary *next = [record mutableCopy];
    next[@"messages"] = messages;
    next[@"weeks"] = weeks;
    return next;
}

NSDictionary *InboxSummary(NSDictionary *message) {
    NSMutableDictionary *summary = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"id", @"from", @"priority", @"about", @"at", @"readAt", @"readBy", @"told"])
        if (message[key]) summary[key] = message[key];
    return summary;
}
