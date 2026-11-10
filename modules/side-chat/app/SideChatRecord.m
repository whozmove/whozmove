// What a side chat keeps for one session, as plain functions over its record.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "SideChatRecord.h"
#import "Files.h"
#import "Text.h"

const NSUInteger SideChatMost = 600;
NSArray<NSString *> *const SideChatBackStates = @[@"takenBack", @"refused", @"ended", @"restarted"];

static NSArray<NSDictionary *> *Says(NSDictionary *record) {
    return AsList(record[@"says"]) ?: @[];
}

// The record with the words said at `at` changed by `change`, the keys it sets to NSNull taken out.
static NSDictionary *Changed(NSDictionary *record, double at, NSDictionary *change) {
    NSMutableArray *says = [NSMutableArray array];
    BOOL found = NO;
    for (NSDictionary *said in Says(record)) {
        if (found || AsNumber(said[@"at"]).doubleValue != at) {
            [says addObject:said];
            continue;
        }
        found = YES;
        NSMutableDictionary *one = [said mutableCopy];
        [change enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
            if (value == NSNull.null) [one removeObjectForKey:key];
            else one[key] = value;
        }];
        [says addObject:one];
    }
    if (!found) return record;
    NSMutableDictionary *next = [record mutableCopy];
    next[@"says"] = says;
    return next;
}

NSDictionary *SideChatRecordAt(NSDictionary *record, double at) {
    for (NSDictionary *said in Says(record))
        if (AsNumber(said[@"at"]).doubleValue == at) return said;
    return nil;
}

NSDictionary *SideChatRecordSaid(NSDictionary *record, NSString *words, double at, pid_t pid, long long started) {
    NSMutableDictionary *next = [record mutableCopy] ?: [NSMutableDictionary dictionary];
    next[@"pid"] = @(pid);
    next[@"processStart"] = @(started);
    next[@"says"] = [Says(record) arrayByAddingObject:@{@"at": @(at), @"words": words, @"state": @"held"}];
    return next;
}

NSDictionary *SideChatRecordProgress(NSDictionary *record, double at, NSDictionary *change) {
    NSString *now = AsText(SideChatRecordAt(record, at)[@"state"]), *state = AsText(change[@"state"]);
    if (!now || !state || [@[@"read", @"replied", @"noReply", @"copied"] containsObject:now]
        || [SideChatBackStates containsObject:now])
        return record;
    NSMutableDictionary *edit = [@{@"state": state, @"late": NSNull.null} mutableCopy];
    if ([state isEqual:@"typed"] || [state isEqual:@"read"]) edit[@"doneAt"] = AsNumber(change[@"at"]) ?: NSNull.null;
    if ([state isEqual:@"read"]) edit[@"how"] = AsText(change[@"how"]) ?: @"step";
    if ([state isEqual:@"refused"])
        for (NSString *key in @[@"why", @"way", @"where"]) edit[key] = AsText(change[key]) ?: NSNull.null;
    return Changed(record, at, edit);
}

NSDictionary *SideChatRecordTakeBack(NSDictionary *record, double at, NSString *late) {
    if (!SideChatRecordAt(record, at)) return record;
    return Changed(record, at, late ? @{@"late": late} : @{@"state": @"takenBack"});
}

NSDictionary *SideChatRecordCopied(NSDictionary *record, double at, double now) {
    if (![AsText(SideChatRecordAt(record, at)[@"state"]) isEqual:@"held"]) return record;
    return Changed(record, at, @{@"state": @"copied", @"doneAt": @(now), @"late": NSNull.null});
}

NSDictionary *SideChatRecordReplied(NSDictionary *record, double at, BOOL replied, double repliedAt) {
    if (![AsText(SideChatRecordAt(record, at)[@"state"]) isEqual:@"read"]) return record;
    return Changed(record, at, replied ? @{@"state": @"replied", @"repliedAt": @(repliedAt)} : @{@"state": @"noReply"});
}

NSDictionary *SideChatRecordRestarted(NSDictionary *record) {
    NSDictionary *next = record;
    for (NSDictionary *said in Says(record))
        if ([@[@"held", @"typing", @"handed"] containsObject:AsText(said[@"state"]) ?: @""])
            next = Changed(next, AsNumber(said[@"at"]).doubleValue, @{@"state": @"restarted"});
    return next;
}

NSDictionary *SideChatRecordPutBack(NSDictionary *record, double at) {
    NSDictionary *said = SideChatRecordAt(record, at);
    if (![SideChatBackStates containsObject:AsText(said[@"state"]) ?: @""]) return record;
    NSMutableArray *says = [Says(record) mutableCopy];
    [says removeObject:said];
    NSMutableDictionary *next = [record mutableCopy];
    next[@"says"] = says;
    return next;
}

#pragma mark - Asked on the side

static NSString *const kAsking = @"asking";

NSArray<NSDictionary *> *SideChatAsideAsked(NSArray<NSDictionary *> *asides, NSString *question, double at) {
    for (NSDictionary *aside in asides)
        if ([aside[@"state"] isEqual:kAsking]) return nil;
    return [(asides ?: @[]) arrayByAddingObject:@{@"at": @(at), @"question": question ?: @"", @"state": kAsking}];
}

const NSUInteger SideChatStepMost = 120;

NSArray<NSDictionary *> *SideChatAsideToStep(NSArray<NSDictionary *> *asides, double at, NSString *step) {
    NSString *words = PlainOneLine(step, SideChatStepMost);
    if (!words.length) return asides;
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *aside in asides) {
        if (AsNumber(aside[@"at"]).doubleValue != at || ![aside[@"state"] isEqual:kAsking]) {
            [out addObject:aside];
            continue;
        }
        NSMutableDictionary *one = [aside mutableCopy];
        one[@"step"] = words;
        [out addObject:one];
    }
    return out;
}

NSArray<NSDictionary *> *SideChatAsideNotAsked(NSArray<NSDictionary *> *asides, NSString *question, double at) {
    return [(asides ?: @[]) arrayByAddingObject:@{@"at": @(at), @"question": question ?: @"", @"state": @"notAsked"}];
}

NSArray<NSDictionary *> *SideChatAsideAnswered(NSArray<NSDictionary *> *asides, double at, NSDictionary *answer,
                                               double now) {
    NSArray *states = @[@"answered", @"tooSlow", @"noAnswer", @"apiError", @"wantedTool", @"limit", @"signedOut",
                        @"tooLong", @"noCommand", @"stopped"];
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *aside in asides) {
        if (AsNumber(aside[@"at"]).doubleValue != at || ![aside[@"state"] isEqual:kAsking]) {
            [out addObject:aside];
            continue;
        }
        NSMutableDictionary *one = [aside mutableCopy];
        NSString *state = [states containsObject:AsText(answer[@"state"]) ?: @""] ? answer[@"state"] : @"noAnswer";
        NSString *text = AsText(answer[@"text"]);
        NSArray *parts = [state isEqual:@"answered"] ? ReplyParts(text) : @[];
        if ([state isEqual:@"answered"] && !parts.count) state = @"noAnswer";
        one[@"state"] = state;
        [one removeObjectForKey:@"step"];
        if (parts.count) {
            one[@"text"] = text;
            one[@"answer"] = parts;
            one[@"answeredAt"] = @(now);
            if (AsNumber(answer[@"remembered"])) one[@"remembered"] = answer[@"remembered"];
        }
        if ([state isEqual:@"limit"] && AsNumber(answer[@"resetsAt"])) one[@"resetsAt"] = answer[@"resetsAt"];
        if ([state isEqual:@"signedOut"] && AsText(answer[@"signIn"])) one[@"signIn"] = answer[@"signIn"];
        [out addObject:one];
    }
    return out;
}

NSDictionary *SideChatAsideSendable(NSArray<NSDictionary *> *asides, double at) {
    NSDictionary *aside = SideChatAsideAt(asides, at);
    NSString *state = AsText(aside[@"state"]);
    return !aside || aside[@"sentAt"] || [state isEqual:kAsking] || [state isEqual:@"answered"] ? nil : aside;
}

// The asides with the one asked at `at` given `sentAt`, or without it when that's nil.
static NSArray<NSDictionary *> *WithSentAt(NSArray<NSDictionary *> *asides, double at, NSNumber *sentAt) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *aside in asides) {
        if (AsNumber(aside[@"at"]).doubleValue != at) {
            [out addObject:aside];
            continue;
        }
        NSMutableDictionary *one = [aside mutableCopy];
        one[@"sentAt"] = sentAt;
        [out addObject:one];
    }
    return out;
}

NSArray<NSDictionary *> *SideChatAsideSent(NSArray<NSDictionary *> *asides, double at, double sentAt) {
    return SideChatAsideSendable(asides, at) ? WithSentAt(asides, at, @(sentAt)) : asides;
}

NSArray<NSDictionary *> *SideChatAsideUnsent(NSArray<NSDictionary *> *asides, double at) {
    return SideChatAsideAt(asides, at)[@"sentAt"] ? WithSentAt(asides, at, nil) : asides;
}

NSArray<NSDictionary *> *SideChatAsidesShown(NSArray<NSDictionary *> *asides) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *aside in asides) {
        NSMutableDictionary *one = [aside mutableCopy];
        [one removeObjectsForKeys:@[@"text", @"signIn"]];
        [out addObject:one];
    }
    return out;
}

NSArray<NSDictionary *> *SideChatAsidesEarlier(NSArray<NSDictionary *> *asides, double at) {
    NSMutableArray *earlier = [NSMutableArray array];
    for (NSDictionary *aside in asides) {
        double asked = AsNumber(aside[@"at"]).doubleValue;
        NSString *text = AsText(aside[@"text"]);
        if (asked < at && [aside[@"state"] isEqual:@"answered"] && text.length)
            [earlier addObject:@{@"question": AsText(aside[@"question"]) ?: @"", @"text": text, @"at": @(asked)}];
    }
    return earlier;
}

NSDictionary *SideChatAsideAt(NSArray<NSDictionary *> *asides, double at) {
    for (NSDictionary *aside in asides)
        if (AsNumber(aside[@"at"]).doubleValue == at) return aside;
    return nil;
}
