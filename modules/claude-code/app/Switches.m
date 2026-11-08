// Switches: the panel's note of a model switch it's making, <session>.panel.json, the one file left between the panel
// and the hook for it (a note written by anyone else only makes the switch the panel's business, which the panel still
// answers itself); the question and its answer go over the hook's line. The folder is only yours to read.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Switches.h"
#import "Files.h"
#import "Text.h"
#import "Log.h"
#import "Processes.h"
#import "HookLine.h"

// A session's file of that kind, or nil for an id that isn't one (plain, as the hook takes them).
static NSString *SwitchFile(NSString *sessionId, NSString *kind) {
    if (!IsPlainId(sessionId, 128)) return nil;
    return [AppDir(@"switches") stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@.json", sessionId,
                                                                                          kind]];
}

static BOOL WriteSwitchFile(NSString *path, NSDictionary *value) {
    if (!path) return NO;
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent
                            withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700} error:nil];
    NSData *json = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    return json && [json writeToFile:path atomically:YES];
}

// How long a note counts for, as the hook takes it (NOTE_LASTS in the hook): long enough for Claude Code to check the
// model with its servers before it runs its hooks.
static const NSTimeInterval kNoteLasts = 20;

// Notes a session's hook never took (one started before the hook was, or a switch Claude Code didn't make) go once
// they're past counting, as the hook would no longer take them.
void NoteSwitch(NSString *sessionId, NSString *model) {
    NSString *folder = AppDir(@"switches");
    NSFileManager *files = NSFileManager.defaultManager;
    if (!model.length) {
        NSString *note = SwitchFile(sessionId, @"panel");
        if (note) [files removeItemAtPath:note error:nil];
        return;
    }
    for (NSString *name in [files contentsOfDirectoryAtPath:folder error:nil]) {
        NSString *path = [folder stringByAppendingPathComponent:name];
        NSDate *made = [files attributesOfItemAtPath:path error:nil].fileModificationDate;
        if ([name hasSuffix:@".panel.json"] && made && -made.timeIntervalSinceNow > kNoteLasts)
            [files removeItemAtPath:path error:nil];
    }
    if (!WriteSwitchFile(SwitchFile(sessionId, @"panel"), @{@"to": model, @"at": @((long long)(NSDate.date
                                                                    .timeIntervalSince1970 * 1000))}))
        PanelLog(@"%@ -> no note of the panel's switch to %@ for its hook", sessionId, model);
}

// A question whose hook has gone (answered in time by someone else, or stopped by Claude Code) is no question: its line
// has closed.
NSDictionary *SwitchQuestion(NSString *sessionId) {
    NSDictionary *asked = [[HookLine shared] switchQuestionFor:sessionId];
    if (!asked) return nil;
    return @{@"from": AsText(asked[@"from"]) ?: @"", @"to": AsText(asked[@"to"]) ?: @"",
             @"tokens": AsNumber(asked[@"tokens"]) ?: NSNull.null};
}

void AnswerSwitch(NSString *sessionId, BOOL allow) {
    BOOL sent = [[HookLine shared] answerSwitch:sessionId allow:allow];
    PanelLog(@"%@ -> \"Switch model?\" answered for its hook: %@%@", sessionId, allow ? @"switch" : @"keep the model",
             sent ? @"" : @" (its hook has gone)");
}
