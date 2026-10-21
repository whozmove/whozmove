// Switches: the files the panel and the permission hook pass a model switch through, one set per session, named for
// it: <session>.panel.json (the panel's note), <session>.ask.json (the hook's question, with its pid) and
// <session>.answer.json (the panel's answer). The folder is only yours to read.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Switches.h"
#import "Files.h"
#import "Log.h"
#import "Processes.h"

// A session's file of that kind, or nil for an id that isn't one (letters, digits and dashes, as the hook takes them).
static NSString *SwitchFile(NSString *sessionId, NSString *kind) {
    NSCharacterSet *other = [NSCharacterSet characterSetWithCharactersInString:
                                 @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-"].invertedSet;
    if (!sessionId.length || sessionId.length > 128 || [sessionId rangeOfCharacterFromSet:other].location != NSNotFound)
        return nil;
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
// Since when the hooks in Whozmove's folder have had the switch part, as first seen there (the app's own defaults).
static NSString *const kSwitchHookSince = @"switchHookSince";

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

// A question whose hook has gone (answered in time by someone else, or stopped by Claude Code) is no question.
NSDictionary *SwitchQuestion(NSString *sessionId) {
    NSString *path = SwitchFile(sessionId, @"ask");
    NSDictionary *asked = path ? AsRecord(ReadJSON(path)) : nil;
    if (![AsText(asked[@"sessionId"]) isEqualToString:sessionId] || !ProcessAlive(AsNumber(asked[@"pid"]).intValue))
        return nil;
    return @{@"from": AsText(asked[@"from"]) ?: @"", @"to": AsText(asked[@"to"]) ?: @"",
             @"tokens": AsNumber(asked[@"tokens"]) ?: NSNull.null};
}

// The hooks are put in place as the app is restarted after them, so the time of the first copy with the switch part
// the app sees is when that part went in; a later copy's time is kept back from it.
BOOL SessionAsksSwitches(pid_t pid) {
    NSString *path = [AppDir(@"plugin") stringByAppendingPathComponent:@"hooks/hooks.json"];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (!AsRecord(AsRecord(ReadJSON(path))[@"hooks"])[@"PreModelSwitch"]) {
        [defaults removeObjectForKey:kSwitchHookSince];
        return NO;
    }
    NSDate *placed = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil].fileModificationDate;
    double since = [defaults doubleForKey:kSwitchHookSince];
    if (placed && (!since || placed.timeIntervalSince1970 < since)) {
        since = placed.timeIntervalSince1970;
        [defaults setDouble:since forKey:kSwitchHookSince];
    }
    long long started = ProcessStartedAt(pid);  // microseconds since 1970
    return since > 0 && started > 0 && started / 1e6 > since;
}

void AnswerSwitch(NSString *sessionId, BOOL allow) {
    BOOL written = WriteSwitchFile(SwitchFile(sessionId, @"answer"), @{@"allow": @(allow)});
    PanelLog(@"%@ -> \"Switch model?\" answered for its hook: %@%@", sessionId, allow ? @"switch" : @"keep the model",
             written ? @"" : @" (couldn't write the answer)");
}
