// NoticeRules: what the notifications module keeps for the user: what they put away, and until when.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "NoticeRules.h"
#import "NoticeGathering.h"
#import "Files.h"
#import "Text.h"

static NSDictionary *Part(NSDictionary *record, NSString *name) {
    id part = record[name];
    return [part isKindOfClass:NSDictionary.class] ? part : @{};
}

// The record with `name` set to `value` (nil takes it out).
static NSDictionary *With(NSDictionary *record, NSString *name, id value) {
    NSMutableDictionary *next = [(record ?: @{}) mutableCopy];
    next[name] = value;
    return next;
}

// One of the record's parts with `key` set to `value` (nil takes it out).
static NSDictionary *WithIn(NSDictionary *record, NSString *name, NSString *key, id value) {
    NSMutableDictionary *part = [Part(record, name) mutableCopy];
    part[key] = value;
    return With(record, name, part);
}

NSString *NoticeId(Notice *notice) {
    return [NSString stringWithFormat:@"%@/%@", notice.from ?: @"", notice.key ?: @""];
}

BOOL NoticeKeptAway(NSDictionary *record, Notice *notice, double now) {
    NSDictionary *away = Part(record, @"away")[NoticeId(notice)];
    if (![away isKindOfClass:NSDictionary.class]) return NO;
    id since = away[@"since"];
    if (!(since == notice.since || [since isEqual:notice.since]) && !(since == NSNull.null && !notice.since)) return NO;
    double awayFor = [away[@"awayFor"] doubleValue], at = [away[@"at"] doubleValue];
    return awayFor <= 0 || now - at < awayFor * 1000;
}

NSDictionary *NoticePutAway(NSDictionary *record, Notice *notice, double now) {
    NSMutableDictionary *away = [@{@"since": notice.since ?: NSNull.null, @"at": @(now)} mutableCopy];
    if (notice.awayFor > 0) away[@"awayFor"] = @(notice.awayFor);
    return WithIn(record, @"away", NoticeId(notice), away);
}

NSDictionary *NoticePutAwayHere(NSDictionary *record, NSString *noticeId, NSString *since, NSTimeInterval awayFor,
                                double now) {
    if (!noticeId.length) return record;
    NSMutableDictionary *here = [Part(record, @"awayHere") mutableCopy];
    // Only what makes it new, as the page reads it, unless it's away for a while too.
    if (since && isfinite(awayFor) && awayFor > 0)
        here[noticeId] = @{@"since": since, @"at": @(now), @"awayFor": @(awayFor)};
    else if (since) here[noticeId] = since;
    else [here removeObjectForKey:noticeId];
    return With(record, @"awayHere", here);
}

BOOL NoticeQuietAt(NSInteger minute, BOOL on, NSInteger from, NSInteger to) {
    if (!on || from == to) return NO;
    return from < to ? minute >= from && minute < to : minute >= from || minute < to;
}

// What the seen record takes: a notice's id (its sender and key, "from/key"), and a since that's short.
static BOOL SeenId(NSString *noticeId) {
    NSArray *parts = [noticeId componentsSeparatedByString:@"/"];
    if (parts.count != 2) return NO;
    for (NSString *part in parts)
        if (!IsPlainId(part, 128)) return NO;
    return YES;
}

// The record's entries, by id, each { since, at }: its since from besideSeen, and when that was first seen from
// besideSeenAt, a time not kept there counting as long ago.
static NSDictionary *SeenEntries(NSDictionary *record) {
    NSDictionary *sinces = Part(record, @"besideSeen"), *ats = Part(record, @"besideSeenAt");
    NSMutableDictionary *entries = [NSMutableDictionary dictionary];
    for (id noticeId in sinces) {
        NSString *since = AsText(sinces[noticeId]);
        id at = [noticeId isKindOfClass:NSString.class] ? ats[noticeId] : nil;
        if (!since) continue;
        BOOL kept = [at isKindOfClass:NSNumber.class] && isfinite([at doubleValue]);
        entries[noticeId] = @{@"since": since, @"at": kept ? at : @0};
    }
    return entries;
}

// The entries the record keeps of these: only what it takes, and past 200, those seen latest.
static NSDictionary *SeenBounded(NSDictionary *entries) {
    NSMutableDictionary *taken = [NSMutableDictionary dictionary];
    for (id noticeId in entries) {
        NSString *since = entries[noticeId][@"since"];
        if (!SeenId(AsText(noticeId)) || !since.length || since.length > 200) continue;
        taken[noticeId] = entries[noticeId];
    }
    if (taken.count <= 200) return taken;
    NSArray *ids = [taken.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        double x = [taken[a][@"at"] doubleValue], y = [taken[b][@"at"] doubleValue];
        return x > y ? NSOrderedAscending : x < y ? NSOrderedDescending : [a compare:b];
    }];
    return [taken dictionaryWithValuesForKeys:[ids subarrayWithRange:NSMakeRange(0, 200)]];
}

// One field of each entry, by id.
static NSDictionary *SeenField(NSDictionary *entries, NSString *field) {
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    for (NSString *noticeId in entries) values[noticeId] = entries[noticeId][field];
    return values;
}

NSDictionary *NoticeSeen(NSDictionary *record, NSDictionary *seen, double now) {
    NSDictionary *before = SeenEntries(record);
    NSMutableDictionary *entries = [NSMutableDictionary dictionary];
    for (id noticeId in AsRecord(seen)) {
        NSString *since = AsText(seen[noticeId]);
        if (!since) continue;
        NSDictionary *was = [noticeId isKindOfClass:NSString.class] ? before[noticeId] : nil;
        entries[noticeId] = @{@"since": since, @"at": [was[@"since"] isEqualToString:since] ? was[@"at"] : @(now)};
    }
    NSDictionary *bounded = SeenBounded(entries);
    return With(With(record, @"besideSeen", SeenField(bounded, @"since")), @"besideSeenAt", SeenField(bounded, @"at"));
}

NSDictionary *NoticeSeenKept(NSDictionary *record) {
    NSDictionary *entries = SeenEntries(record);
    if (!AsRecord(record[@"besideSeen"])) return nil;
    NSDictionary *kept = SeenBounded(entries);
    // Entries none of which is a notice's are as none at all, so nothing there now is taken for new.
    return entries.count && !kept.count ? nil : SeenField(kept, @"since");
}

// ---- --print-notices ----

static Notice *Sent(NSString *from, Notice *notice) {
    notice.from = from;
    return notice;
}

static Notice *Disk(NSString *since) {
    Notice *notice = Sent(@"storage", [Notice noticeWithKey:@"disk" level:NoticeSoon
                                                       text:@"18 GB left on this Mac, full in about 3 days."]);
    notice.since = since;
    notice.awayFor = 86400;
    return notice;
}

static Notice *Update(NSString *version) {
    Notice *notice = Sent(@"install", [Notice noticeWithKey:@"update" level:NoticeSoon
        text:[NSString stringWithFormat:@"Whozmove %@ is out.", version]]);
    notice.since = version;
    return notice;
}

static NSString *Away(NSDictionary *record, Notice *notice, double now) {
    return NoticeKeptAway(record, notice, now) ? @"away" : @"shows";
}

// A record's part as one line of JSON, its keys in order.
static NSString *Line(id value) {
    NSJSONWritingOptions options = NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes;
    NSData *json = value ? [NSJSONSerialization dataWithJSONObject:value options:options error:nil] : nil;
    return json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"(none)";
}

int PrintNotices(NSArray<NSString *> *arguments) {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    void (^say)(NSString *, NSString *) = ^(NSString *what, NSString *result) {
        [lines addObject:[NSString stringWithFormat:@"%@: %@", what, result]];
    };
    const double t = 1790000000000, hour = 3600000;

    // What × puts away, and for how long.
    NSDictionary *record = NoticePutAway(nil, Disk(@"low:7"), t);
    say(@"the disk's line put away, the same a minute later", Away(record, Disk(@"low:7"), t + 60000));
    say(@"…the disk a tenth fuller (a new since)", Away(record, Disk(@"low:6"), t + 60000));
    say(@"…23 hours later, as it was", Away(record, Disk(@"low:7"), t + 23 * hour));
    say(@"…25 hours later, as it was (a day has passed)", Away(record, Disk(@"low:7"), t + 25 * hour));
    record = NoticePutAway(nil, Update(@"0.3.0"), t);
    say(@"a new version put away, the same a week later", Away(record, Update(@"0.3.0"), t + 168 * hour));
    say(@"…a newer version out", Away(record, Update(@"0.3.1"), t + hour));
    Notice *otherSender = Sent(@"usage", [Notice noticeWithKey:@"update" level:NoticeSoon text:@"Another."]);
    otherSender.since = @"0.3.0";
    say(@"…another sender's notice with the same key and since", Away(record, otherSender, t + hour));
    say(@"nothing put away", Away(nil, Disk(@"low:7"), t));
    Notice *noSince = Sent(@"install", [Notice noticeWithKey:@"tools" level:NoticeUrgent text:@"Install the tools."]);
    say(@"one with no since, put away, then listed again", Away(NoticePutAway(nil, noSince, t), noSince, t + hour));
    NSDictionary *here = NoticePutAwayHere(nil, @"one-task/waits", @"task:a#1", 0, t);
    say(@"a page sender's notice put away", Line(here[@"awayHere"]));
    say(@"…said another way", Line(NoticePutAwayHere(here, @"one-task/waits", @"task:a#2", 0, t)[@"awayHere"]));
    say(@"…forgotten", Line(NoticePutAwayHere(here, @"one-task/waits", nil, 0, t)[@"awayHere"]));
    say(@"one put away for a day", Line(NoticePutAwayHere(nil, @"storage/keys", @"k1", 86400, t)[@"awayHere"]));
    say(@"…for a time that isn't a number of seconds: only until it changes",
        Line(NoticePutAwayHere(nil, @"storage/keys", @"k1", INFINITY, t)[@"awayHere"]));
    NSDictionary *seen = NoticeSeen(nil, @{@"needs-you/s-1": @"ask:7", @"needs-you/s-2": @"reply:1790000000000",
        @"../x": @"ask:1", @"a/b/c": @"ask:2", @"s-4": @"ask:3",
        @"s-3": [@"" stringByPaddingToLength:201 withString:@"w" startingAtIndex:0]}, t);
    say(@"what's been seen beside the folded panel, kept for a restart (an id that isn't a notice's, and a since too "
        @"long, left out)", Line(seen[@"besideSeen"]));
    say(@"…and when each was first seen", Line(seen[@"besideSeenAt"]));
    NSDictionary *later = NoticeSeen(seen, @{@"needs-you/s-1": @"ask:7", @"needs-you/s-2": @"reply:1790000009000"},
                                     t + hour);
    say(@"…an hour later, one the same (kept from when it was first seen), one new", Line(later[@"besideSeenAt"]));
    say(@"…what the page has back as it loads", Line(NoticeSeenKept(later)));
    // A build that reads besideSeen alone, each since as text, as the page has them, finds them all there.
    NSMutableArray *read = [NSMutableArray array];
    NSDictionary *laterSinces = later[@"besideSeen"];
    for (NSString *noticeId in [laterSinces.allKeys sortedArrayUsingSelector:@selector(compare:)])
        if (AsText(laterSinces[noticeId]).length) [read addObject:noticeId];
    say(@"…what a build that reads only besideSeen, each a since as text, finds",
        [read componentsJoinedByString:@", "]);
    NSDictionary *untimed = @{@"besideSeen": @{@"x/s-1": @"ask:7", @"x/s-2": @"reply:1"}};
    say(@"…with no times kept: one the same taken as seen long ago, one new seen now",
        Line(NoticeSeen(untimed, @{@"x/s-1": @"ask:7", @"x/s-2": @"reply:2"}, t)[@"besideSeenAt"]));
    say(@"…one that keeps only ids that aren't a notice's: as none, so nothing there now is taken for new",
        Line(NoticeSeenKept(@{@"besideSeen": @{@"s-1": @"ask:7", @"s-2": @"reply:1"}})));
    say(@"…one that keeps nothing yet: nothing seen", Line(NoticeSeenKept(@{@"besideSeen": @{}})));
    say(@"…nothing kept yet (a first launch)", Line(NoticeSeenKept(@{})));
    NSMutableDictionary *many = [NSMutableDictionary dictionary], *sinces = [NSMutableDictionary dictionary],
                        *ats = [NSMutableDictionary dictionary];
    for (int i = 0; i < 205; i++) {
        NSString *noticeId = [NSString stringWithFormat:@"x/s-%03d", i];
        many[noticeId] = @"reply:1";
        sinces[noticeId] = @"reply:1";
        ats[noticeId] = @(t + i);
    }
    many[@"x/s-new"] = @"reply:2";
    NSDictionary *mostKept = NoticeSeen(@{@"besideSeen": sinces, @"besideSeenAt": ats}, many, t + hour)[@"besideSeen"];
    say(@"…past 200, those seen latest kept",
        [NSString stringWithFormat:@"%lu kept; the one seen now %@, the first seen %@, the last seen before %@",
         (unsigned long)mostKept.count, mostKept[@"x/s-new"] ? @"kept" : @"left out",
         mostKept[@"x/s-000"] ? @"kept" : @"left out", mostKept[@"x/s-204"] ? @"kept" : @"left out"]);

    // Quiet hours.
    NSString *(^night)(NSInteger, BOOL, NSInteger, NSInteger) = ^NSString *(NSInteger minute, BOOL on, NSInteger from,
                                                                             NSInteger to) {
        return NoticeQuietAt(minute, on, from, to) ? @"quiet" : @"said";
    };
    say(@"quiet hours off, at 23:00", night(23 * 60, NO, 22 * 60, 8 * 60));
    say(@"on, 22:00 to 08:00: at 21:59, 22:00, 03:00, 07:59 and 08:00",
        [@[night(21 * 60 + 59, YES, 22 * 60, 8 * 60), night(22 * 60, YES, 22 * 60, 8 * 60),
           night(3 * 60, YES, 22 * 60, 8 * 60), night(7 * 60 + 59, YES, 22 * 60, 8 * 60),
           night(8 * 60, YES, 22 * 60, 8 * 60)] componentsJoinedByString:@", "]);
    say(@"on, 13:00 to 14:30, not crossing midnight: at 12:59, 13:00, 14:29 and 14:30",
        [@[night(12 * 60 + 59, YES, 13 * 60, 14 * 60 + 30), night(13 * 60, YES, 13 * 60, 14 * 60 + 30),
           night(14 * 60 + 29, YES, 13 * 60, 14 * 60 + 30), night(14 * 60 + 30, YES, 13 * 60, 14 * 60 + 30)]
         componentsJoinedByString:@", "]);
    say(@"on, from and to the same: never quiet", night(22 * 60, YES, 22 * 60, 22 * 60));

    printf("%s\n", [lines componentsJoinedByString:@"\n"].UTF8String);
    return 0;
}
