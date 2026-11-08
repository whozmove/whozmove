// Builds: the build of Whozmove running now, as build.sh recorded it, for the header's line (Show Build in Header).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Builds.h"
#import "Files.h"

// What build.sh records, checked for its kind: anything else in build.json is left out.
static NSDictionary *Recorded(id info) {
    if (![info isKindOfClass:NSDictionary.class]) return nil;
    NSMutableDictionary *build = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"root", @"worktree", @"worktreeOf", @"mainRoot", @"branch", @"detached", @"commit"])
        if ([info[key] isKindOfClass:NSString.class]) build[key] = info[key];
    if ([info[@"builtAt"] isKindOfClass:NSNumber.class]) build[@"builtAt"] = info[@"builtAt"];
    if ([info[@"changes"] isKindOfClass:NSNumber.class]) build[@"changes"] = @([info[@"changes"] boolValue]);
    if ([info[@"agent"] isKindOfClass:NSNumber.class]) build[@"agent"] = @([info[@"agent"] boolValue]);
    return build[@"root"] ? build : nil;
}

NSDictionary *RunningBuild(void) {
    static NSDictionary *running;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        running = Recorded(ReadJSON([NSBundle.mainBundle pathForResource:@"build" ofType:@"json"]));
    });
    return running;
}

NSString *RunningBuildTip(void) {
    NSDictionary *b = RunningBuild();
    if (!b) return @"This build doesn't say where it came from: build it again with ./build.sh";
    NSString *name = b[@"worktree"] ?: b[@"branch"] ?: [b[@"root"] lastPathComponent];
    NSMutableArray *lines = [NSMutableArray arrayWithObjects:
                             [@"Running the build of " stringByAppendingString:name], b[@"root"], nil];
    NSString *at = b[@"branch"] ? [@"branch " stringByAppendingString:b[@"branch"]] : nil;
    if ([b[@"commit"] length] >= 7) {
        NSString *commit = [NSString stringWithFormat:@"commit %@%@", [b[@"commit"] substringToIndex:7],
                                                      [b[@"changes"] boolValue] ? @", with uncommitted changes" : @""];
        at = at ? [NSString stringWithFormat:@"%@ · %@", at, commit] : commit;
    }
    if (at) [lines addObject:at];
    if (b[@"builtAt"]) {
        NSDate *built = [NSDate dateWithTimeIntervalSince1970:[b[@"builtAt"] doubleValue] / 1000];
        [lines addObject:[@"Built " stringByAppendingString:
                          [NSDateFormatter localizedStringFromDate:built dateStyle:NSDateFormatterMediumStyle
                                                         timeStyle:NSDateFormatterShortStyle]]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

BOOL BuiltByAgent(void) {
    return [RunningBuild()[@"agent"] boolValue];
}
