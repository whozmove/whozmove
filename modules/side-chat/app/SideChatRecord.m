// What a side chat keeps for one session, as plain functions over its record.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "SideChatRecord.h"
#import "Files.h"
#import "Text.h"

const NSUInteger SideChatMost = 600;
const NSUInteger SideChatMostOpening = 200;
NSString *const SideChatAccessibilityWay = @"Open Accessibility Settings";
NSArray<NSString *> *const SideChatBackStates = @[@"takenBack", @"refused", @"ended", @"restarted", @"notSent"];

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

NSString *SideChatOpening(NSString *opening) {
    if (!opening.length) return @"";
    NSString *plain = PlainOneLine(opening, SideChatMostOpening + 1);
    // Only a line that is already plain, ending in its one space before your words, and starting with a letter, so
    // what you saw under the box is exactly what goes in, and it never starts as a command does.
    if (!plain.length || opening.length > SideChatMostOpening || ![opening isEqual:[plain stringByAppendingString:@" "]]
        || ![NSCharacterSet.letterCharacterSet characterIsMember:[plain characterAtIndex:0]])
        return nil;
    return opening;
}

NSDictionary *SideChatToGo(NSString *words, NSString *opening, NSDictionary *aside) {
    NSString *said = aside ? AsText(aside[@"question"]) : AsText(words);
    if (!said.length) return nil;
    // A side question goes with the words that opened it where it was asked, wherever its press is; your own words
    // with the view's, as it gives them.
    NSString *open = aside ? AsText(aside[@"opening"]) ?: @"" : SideChatOpening(opening);
    if (!open) return @{@"words": said, @"why": @"What this is about couldn't go with your words from here: send them "
                                                 "from its Side Chat"};
    if (open.length + said.length > SideChatMost)
        return @{@"words": said, @"why": @"Too long to go with what it's about: shorten it and send it again"};
    return @{@"words": said, @"opening": open, @"line": [open stringByAppendingString:said]};
}

NSString *SideChatCopyLine(NSDictionary *said, NSString *words, NSString *opening) {
    if (said) return PlainOneLine(SideChatLine(said), SideChatMost);
    NSString *open = SideChatOpening(opening);
    return open ? PlainOneLine([open stringByAppendingString:AsText(words) ?: @""], SideChatMost) : nil;
}

NSDictionary *SideChatRefusedWay(NSDictionary *change, BOOL desktop, BOOL mayControl) {
    if (![change[@"state"] isEqual:@"refused"] || AsText(change[@"way"]) || !desktop || mayControl) return change;
    NSMutableDictionary *more = [change mutableCopy];
    more[@"way"] = SideChatAccessibilityWay;
    more[@"permission"] = @YES;
    return more;
}

NSString *SideChatLine(NSDictionary *said) {
    return AsText(said[@"line"]) ?: AsText(said[@"words"]) ?: @"";
}

NSDictionary *SideChatRecordSaid(NSDictionary *record, NSString *words, NSString *opening, double at, pid_t pid,
                                 long long started) {
    NSMutableDictionary *next = [record mutableCopy] ?: [NSMutableDictionary dictionary];
    next[@"pid"] = @(pid);
    next[@"processStart"] = @(started);
    NSString *line = [(opening ?: @"") stringByAppendingString:words];
    NSMutableDictionary *said = [@{@"at": @(at), @"words": words, @"line": line, @"state": @"held"} mutableCopy];
    if (opening.length) said[@"opening"] = opening;
    next[@"says"] = [Says(record) arrayByAddingObject:said];
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
    if ([state isEqual:@"refused"] || [state isEqual:@"notSent"]) {
        for (NSString *key in @[@"why", @"way", @"where"]) edit[key] = AsText(change[key]) ?: NSNull.null;
        edit[@"permission"] = [change[@"permission"] isEqual:@YES] ? @YES : NSNull.null;
    }
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

// A side question as kept, with the words that opened it where it was asked, if any: what Ask Again and Send's words
// send it with, wherever they're pressed.
static NSDictionary *Aside(NSString *question, NSString *opening, double at, NSString *state) {
    NSMutableDictionary *aside = [@{@"at": @(at), @"question": question ?: @"", @"state": state} mutableCopy];
    if (opening.length) aside[@"opening"] = opening;
    return aside;
}

NSString *SideChatAsideLine(NSDictionary *aside) {
    return [(AsText(aside[@"opening"]) ?: @"") stringByAppendingString:AsText(aside[@"question"]) ?: @""];
}

NSArray<NSDictionary *> *SideChatAsideAsked(NSArray<NSDictionary *> *asides, NSString *question, NSString *opening,
                                            double at) {
    for (NSDictionary *aside in asides)
        if ([aside[@"state"] isEqual:kAsking]) return nil;
    return [(asides ?: @[]) arrayByAddingObject:Aside(question, opening, at, kAsking)];
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

NSArray<NSDictionary *> *SideChatAsideNotAsked(NSArray<NSDictionary *> *asides, NSString *question, NSString *opening,
                                               double at) {
    return [(asides ?: @[]) arrayByAddingObject:Aside(question, opening, at, @"notAsked")];
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
            [earlier addObject:@{@"question": SideChatAsideLine(aside), @"text": text, @"at": @(asked)}];
    }
    return earlier;
}

NSDictionary *SideChatAsideAt(NSArray<NSDictionary *> *asides, double at) {
    for (NSDictionary *aside in asides)
        if (AsNumber(aside[@"at"]).doubleValue == at) return aside;
    return nil;
}
