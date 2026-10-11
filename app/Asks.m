// Asks: permission requests waiting in the panel, left by the permission hook, and the answers given there.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Asks.h"
#import "Log.h"
#import "Files.h"
#import "Processes.h"

// A tool's input for showing on its card, with long text (a file being written) cut short; *cut is set if
// any was, and then the card doesn't offer to allow what it can't show in full.
static id ShownInput(id value, BOOL *cut) {
    if ([value isKindOfClass:NSString.class]) {
        if ([value length] <= 4000) return value;
        *cut = YES;
        return [Clip(value, 4000) stringByAppendingString:@"\n…"];
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

// Permission requests waiting in the panel, the oldest per session. hooks/whozmove-claude-permission.py leaves them
// in the asks folder of Whozmove's own folder. One whose hook is gone (answered in Claude, or timed out) is
// cleared away.
NSDictionary<NSString *, NSDictionary *> *PendingAsks(void) {
    NSString *dir = AppDir(@"asks");
    NSMutableDictionary *bySession = [NSMutableDictionary dictionary];
    for (NSString *file in [NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:nil]) {
        if (![file.pathExtension isEqualToString:@"json"] || [file hasSuffix:@".answer.json"]) continue;
        NSString *path = [dir stringByAppendingPathComponent:file];
        NSDictionary *ask = ReadJSON(path);
        if (![ask isKindOfClass:NSDictionary.class] || ![ask[@"sessionId"] isKindOfClass:NSString.class]) continue;
        if (!ProcessAlive([ask[@"pid"] intValue])) {
            [NSFileManager.defaultManager removeItemAtPath:path error:nil];
            continue;
        }
        NSMutableDictionary *shown = [ask mutableCopy];
        BOOL cut = NO;
        shown[@"input"] = [ask[@"input"] isKindOfClass:NSDictionary.class] ? ShownInput(ask[@"input"], &cut) : @{};
        shown[@"truncated"] = @(cut);
        NSDictionary *older = bySession[ask[@"sessionId"]];
        if (!older || [ask[@"at"] doubleValue] < [older[@"at"] doubleValue]) bySession[ask[@"sessionId"]] = shown;
    }
    return bySession;
}

// An answer given in the panel, for the hook to pass on: allow this once, or deny. For Claude's questions it also
// carries the answers (question text -> answer), which the hook passes on only for that tool.
void AnswerAsk(NSDictionary *msg) {
    NSString *askId = msg[@"id"];
    NSCharacterSet *notHex = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet];
    if (![askId isKindOfClass:NSString.class] || !askId.length
        || [askId rangeOfCharacterFromSet:notHex].location != NSNotFound)
        return;
    NSString *behavior = [msg[@"allow"] boolValue] ? @"allow" : @"deny";
    NSString *path = [AppDir(@"asks") stringByAppendingPathComponent:[askId stringByAppendingString:@".answer.json"]];
    if ([NSFileManager.defaultManager fileExistsAtPath:path]) {  // answered already: the first answer stands
        PanelLog(@"permission %@: already answered; %@ ignored", askId, behavior);
        return;
    }
    // Only what the card could show in full can be allowed; otherwise its Allow once is hidden.
    if ([behavior isEqual:@"allow"]) {
        NSDictionary *ask = ReadJSON([AppDir(@"asks")
                                      stringByAppendingPathComponent:[askId stringByAppendingPathExtension:@"json"]]);
        BOOL cut = NO;
        if ([ask isKindOfClass:NSDictionary.class]) ShownInput(ask[@"input"], &cut);
        if (cut && ![ask[@"tool"] isEqual:@"AskUserQuestion"]) {
            PanelLog(@"permission %@: not allowed from the panel, too long to show in full", askId);
            return;
        }
    }
    NSMutableDictionary *reply = [@{@"behavior": behavior} mutableCopy];
    if ([msg[@"answers"] isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *answers = [NSMutableDictionary dictionary];
        [msg[@"answers"] enumerateKeysAndObjectsUsingBlock:^(id question, id answer, BOOL *stop) {
            if ([question isKindOfClass:NSString.class] && [answer isKindOfClass:NSString.class] && answers.count < 4)
                answers[question] = Clip(answer, 10000);
        }];
        reply[@"answers"] = answers;
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:reply options:0 error:nil];
    if (!json) {
        PanelLog(@"permission %@: answer not written (not JSON)", askId);
        return;
    }
    BOOL written = [json writeToFile:path atomically:YES];
    PanelLog(@"permission %@ -> %@%@", askId, behavior, written ? @"" : @" (couldn't write the answer)");
}
