// Asks: permission requests waiting in the panel, asked by the permission hook over its line, and the answers given
// there.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Asks.h"
#import "HookLine.h"
#import "ClaudeSessions.h"
#import "PluginInstall.h"
#import "Log.h"
#import "DontWait.h"
#import "Files.h"
#import "Processes.h"

// How much of each text in a request its card shows. The page gets every row once a second, so a huge file being
// written can't go in whole; this is several times longer than any widget, command or edit seen in practice.
static const NSUInteger ShownLength = 100000;

// A tool's input for showing on its card, with very long text cut short; *cut is set if any was, and then the
// card says the content is too large to show in full. Allow once still allows all of it, as in Claude's prompt.
static id ShownInput(id value, BOOL *cut) {
    if ([value isKindOfClass:NSString.class]) {
        if ([value length] <= ShownLength) return value;
        *cut = YES;
        return [Clip(value, ShownLength) stringByAppendingString:@"\n…"];
    }
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray *items = [NSMutableArray array];
        for (id item in value) [items addObject:ShownInput(item, cut)];
        return items;
    }
    if ([value isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *fields = [NSMutableDictionary dictionary];
        [value enumerateKeysAndObjectsUsingBlock:^(id key, id item, BOOL *stop) {
            fields[key] = ShownInput(item, cut);
        }];
        return fields;
    }
    return value;
}

// A request an old hook left in the asks folder of Whozmove's own folder, to show, never to answer: only while its
// hook runs, in the session it names, and that session started before the hooks asked over their line, so a request
// written there for a session that asks over its line shows nothing. One whose hook is gone is cleared away.
static NSDictionary *LegacyAsk(NSString *path) {
    NSDictionary *ask = AsRecord(ReadJSON(path));
    NSString *sessionId = AsText(ask[@"sessionId"]);
    pid_t hook = AsNumber(ask[@"pid"]).intValue;
    if (!sessionId) return nil;
    if (!ProcessAlive(hook)) {
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        return nil;
    }
    if ([HookLine shared].printing) return ask;
    // Since when the hooks have asked over their line is remembered as it was first seen, as the other parts are, so a
    // later copy of the hooks doesn't make a session that asks over it look older than it is.
    pid_t session = 0;
    if (![SessionAbove(hook, &session) isEqual:sessionId] || SessionHasHookPart(session, HookPartHookLine, YES))
        return nil;
    NSMutableDictionary *shown = [ask mutableCopy];
    shown[@"legacy"] = @YES;
    return shown;
}

// Permission requests waiting in the panel, the oldest per session: those asked over the hook's line, and, from
// sessions that started before it, those their hooks leave in files.
NSDictionary<NSString *, NSDictionary *> *PendingAsks(void) {
    NSMutableArray<NSDictionary *> *asks = [[HookLine shared].requests.allValues mutableCopy];
    NSString *dir = AppDir(@"asks");
    for (NSString *file in [NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:nil]) {
        if (![file.pathExtension isEqualToString:@"json"] || [file hasSuffix:@".answer.json"]) continue;
        NSDictionary *ask = LegacyAsk([dir stringByAppendingPathComponent:file]);
        if (ask) [asks addObject:ask];
    }
    NSMutableDictionary *bySession = [NSMutableDictionary dictionary];
    for (NSDictionary *ask in asks) {
        if (![ask[@"sessionId"] isKindOfClass:NSString.class]) continue;
        NSMutableDictionary *shown = [ask mutableCopy];
        BOOL cut = NO;
        shown[@"input"] = [ask[@"input"] isKindOfClass:NSDictionary.class] ? ShownInput(ask[@"input"], &cut) : @{};
        shown[@"truncated"] = @(cut);
        // One that goes by itself if no one answers carries its session's whole wait, which its card counts down.
        if (ask[@"expiresAt"]) shown[@"waits"] = DontWaitFor(ask[@"sessionId"]);
        NSDictionary *older = bySession[ask[@"sessionId"]];
        if (!older || [ask[@"at"] doubleValue] < [older[@"at"] doubleValue]) bySession[ask[@"sessionId"]] = shown;
    }
    return bySession;
}

BOOL AskShownCut(NSDictionary *request) {
    BOOL cut = NO;
    if ([request[@"input"] isKindOfClass:NSDictionary.class]) ShownInput(request[@"input"], &cut);
    return cut;
}

NSString *AskId(id value) {
    NSCharacterSet *notHex = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet];
    if (![value isKindOfClass:NSString.class] || ![value length] || [value length] > 64
        || [value rangeOfCharacterFromSet:notHex].location != NSNotFound)
        return nil;
    return value;
}

NSDictionary *AskReply(NSDictionary *msg) {
    NSString *behavior = [msg[@"allow"] boolValue] ? @"allow" : @"deny";
    NSMutableDictionary *reply = [@{@"behavior": behavior} mutableCopy];
    if ([msg[@"answers"] isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *answers = [NSMutableDictionary dictionary];
        [msg[@"answers"] enumerateKeysAndObjectsUsingBlock:^(id question, id answer, BOOL *stop) {
            if ([question isKindOfClass:NSString.class] && [answer isKindOfClass:NSString.class] && answers.count < 4)
                answers[question] = Clip(answer, 10000);
        }];
        reply[@"answers"] = answers;
    }
    if (![msg[@"allow"] boolValue] && [msg[@"message"] isKindOfClass:NSString.class])
        reply[@"message"] = Clip(msg[@"message"], 10000);
    if (![msg[@"allow"] boolValue] && [msg[@"stop"] boolValue]) reply[@"stop"] = @YES;
    if (![msg[@"allow"] boolValue] && [msg[@"clarify"] boolValue]) reply[@"clarify"] = @YES;
    return reply;
}

BOOL SendAnswer(NSString *askId, NSDictionary *reply) {
    BOOL sent = [[HookLine shared] answer:askId with:reply];
    PanelLog(@"permission %@ -> %@%@", askId, reply[@"behavior"], sent ? @"" : @" (gone, or answered already)");
    return sent;
}

// An answer given in the panel, for the hook to pass on: allow this once, or deny. For Claude's questions it also
// carries the answers (question text -> answer), or that you'd like to chat about them (`clarify`, with the answers
// picked so far), and for a plan your notes or that you stopped it, which the hook passes on only for those tools. Only
// down the request's own line, once: the first answer stands, and a request from an old hook, in a file, isn't answered
// from here.
void AnswerAsk(NSDictionary *msg) {
    NSString *askId = AskId(msg[@"id"]);
    if (askId) SendAnswer(askId, AskReply(msg));
}

// A hold is kept for every request, so a session you allow doesn't answer one you're answering; for one that goes by
// itself it goes down the request's line too, and the hook waits at least a minute past now. A hold only ever puts off
// its going by itself, and never answers it.
void HoldAsk(NSString *askId) {
    askId = AskId(askId);
    if (askId) [[HookLine shared] hold:askId at:floor(NSDate.date.timeIntervalSince1970 * 1000)];
}
