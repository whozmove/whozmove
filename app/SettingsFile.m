// SettingsFile: putting the /model and /effort defaults back in Claude Code's settings, key by key.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "SettingsFile.h"
#import <JavaScriptCore/JavaScriptCore.h>
#import "Log.h"
#import "Files.h"
#import "Upstream.h"

@interface SettingsFile ()
// The defaults as they were before the pending /model and /effort commands saved theirs: key -> its JSON, or
// NSNull if it wasn't set; and how many pending commands touch each key.
@property (strong) NSMutableDictionary<NSString *, id> *defaultsBefore;
@property (strong) NSCountedSet<NSString *> *defaultsPending;
@end

@implementation SettingsFile

- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.defaultsBefore = [NSMutableDictionary dictionary];
    self.defaultsPending = [NSCountedSet set];
    return self;
}

// The settings.json keys a command saves its default in: /model the model, /effort the effort level (overall and
// per model).
static NSArray<NSString *> *DefaultKeys(NSString *field) {
    return [field isEqual:@"model"] ? @[@"model"]
         : [field isEqual:@"effort"] ? @[@"effortLevel", @"modelSettings"] : @[];
}

// settings.json is read and written through JavaScript's own JSON, as Claude Code (Node) reads and writes
// it, so putting a key back leaves every other setting, their order and the file's layout as they were.
static NSString *SettingsPath(void) {
    return ClaudeDir(kClaudeCodeSettings).stringByResolvingSymlinksInPath;
}

// The current JSON of each key (NSNull: not set), or nil if the file can't be read.
static NSDictionary<NSString *, id> *ReadDefaults(NSString *path, NSArray<NSString *> *keys) {
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!text) return nil;
    JSContext *js = [JSContext new];
    JSValue *read = [js evaluateScript:@"(function (text, keys) { const s = JSON.parse(text), out = {};"
                                        "  for (const k of keys) out[k] = k in s ? JSON.stringify(s[k]) : null;"
                                        " return out; })"];
    JSValue *values = [read callWithArguments:@[text, keys]];
    return js.exception || !values.isObject ? nil : values.toDictionary;
}

// Sets each key back to its JSON (NSNull: not set), replacing the file in one step so Claude Code never
// reads it half-written. YES if anything changed.
static BOOL WriteDefaults(NSString *path, NSDictionary<NSString *, id> *values) {
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!text) return NO;
    JSContext *js = [JSContext new];
    JSValue *merge = [js evaluateScript:@"(function (text, values) { const s = JSON.parse(text); let changed = false;"
                                         "  for (const [k, v] of Object.entries(values)) {"
                                         "    if ((k in s ? JSON.stringify(s[k]) : null) === v) continue;"
                                         "    if (v === null) delete s[k]; else s[k] = JSON.parse(v);"
                                         "    changed = true;"
                                         "  }"
                                         "  return changed ? JSON.stringify(s, null, 2)"
                                         " + (text.endsWith('\\n') ? '\\n' : '') : null; })"];
    JSValue *merged = [merge callWithArguments:@[text, values]];
    if (js.exception || !merged.isString) return NO;
    NSNumber *mode = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil][NSFilePosixPermissions];
    if (![[merged.toString dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path options:NSDataWritingAtomic
                                                                         error:nil])
        return NO;
    if (mode) [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: mode} ofItemAtPath:path error:nil];
    return YES;
}

// `/model` and `/effort` also save the pick as the default for new sessions. A pick in the panel is for one
// session, so those keys go back to what they were before the first of the pending commands touching them. Only
// those keys go back, and only when a command did save, so no other change made meanwhile is undone.
- (void)holdDefaults:(NSString *)field {
    NSArray *keys = DefaultKeys(field);
    NSMutableArray *fresh = [NSMutableArray array];
    for (NSString *key in keys) if (![self.defaultsPending countForObject:key]) [fresh addObject:key];
    NSDictionary *now = fresh.count ? ReadDefaults(SettingsPath(), fresh) : nil;
    for (NSString *key in fresh) if (now[key]) self.defaultsBefore[key] = now[key];  // unreadable: never put back
    for (NSString *key in keys) [self.defaultsPending addObject:key];
}

- (void)releaseDefaults:(NSString *)field saved:(BOOL)saved {
    NSArray *keys = DefaultKeys(field);
    if (saved) {
        NSMutableDictionary *values = [NSMutableDictionary dictionary];
        for (NSString *key in keys) if (self.defaultsBefore[key]) values[key] = self.defaultsBefore[key];
        if (values.count && WriteDefaults(SettingsPath(), values))
            PanelLog(@"settings.json: put back your default %@", [values.allKeys componentsJoinedByString:@", "]);
    }
    for (NSString *key in keys) {
        [self.defaultsPending removeObject:key];
        if (![self.defaultsPending countForObject:key]) [self.defaultsBefore removeObjectForKey:key];
    }
}

@end
