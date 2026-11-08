// CleanUp: what comes back on its own, found on the map of your disk (Scanner.h): what builds and installs make again
// in your checkouts, your tools' caches, what only a tool should clean (by its own command), worktrees you're done
// with, and models; and cleaning what you ticked. Everything here is checked as anything on the map is before it goes.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <sys/stat.h>
#import "ScannerParts.h"
#import "CleanUpFacts.h"
#import "StorageFacts.h"
#import "Files.h"
#import "Git.h"
#import "Processes.h"

// Built folders in a checkout not changed for this long start ticked; a worktree is done with once it's merged and
// hasn't changed for this long. In days.
static const double kBuiltOld = 14, kWorktreeDone = 7;
// Anything smaller than this isn't worth listing.
static const long long kWorthIt = 1000 * 1000;
// How long a tool may take to say what it can free, and to clean, in seconds; how long what the tools said is taken
// as known (the list is asked for again every few seconds while Docker is being opened); and how much of what a tool
// says is kept: a cleaning command's last words, or all of a list it gives.
static const NSTimeInterval kToolSays = 10, kToolCleans = 600, kToolsFor = 8;
static const NSUInteger kToolOutput = 16 * 1024, kToolList = 4 * 1024 * 1024;
static const double kDay = 24 * 3600;

#pragma mark Asking tools

// A tool by its name, where your terminal would find it (your login shell's PATH), or nil.
static NSString *ToolPath(NSString *name) {
    for (NSString *folder in [LoginPath() componentsSeparatedByString:@":"]) {
        NSString *path = [folder stringByAppendingPathComponent:name];
        if (folder.length && [NSFileManager.defaultManager isExecutableFileAtPath:path]) return path;
    }
    return nil;
}

// What a tool runs with: your terminal's PATH and your home folder, and nothing else of the app's.
static NSDictionary<NSString *, NSString *> *ToolEnvironment(void) {
    NSDictionary *mine = NSProcessInfo.processInfo.environment;
    NSMutableDictionary *environment = [@{@"PATH": LoginPath(), @"HOME": Home(), @"LANG": @"en_US.UTF-8"} mutableCopy];
    for (NSString *key in @[@"USER", @"LOGNAME", @"TMPDIR"]) if (mine[key]) environment[key] = mine[key];
    return environment;
}

// A command (its tool by name, then its arguments) run as your terminal would find it, for `seconds` at most, keeping
// `cap` bytes of what it says: RunBriefly's answer, or nil when the tool isn't there.
static NSDictionary *RunAsYourTerminal(NSArray<NSString *> *command, NSTimeInterval seconds, NSUInteger cap) {
    NSString *tool = ToolPath(command.firstObject);
    if (!tool) return nil;
    return RunBriefly(tool, [command subarrayWithRange:NSMakeRange(1, command.count - 1)], ToolEnvironment(), seconds,
                      cap, NO);
}

// What a tool said: its output, or its errors when it said nothing else (RunTool keeps them apart).
static NSString *Said(NSDictionary *run) {
    NSString *out = [[NSString alloc] initWithData:run[@"out"] ?: NSData.data encoding:NSUTF8StringEncoding] ?: @"";
    NSString *trimmed = [out stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed.length || ![run[@"err"] isKindOfClass:NSString.class] ? out : run[@"err"];
}

// A size as Docker says it ("12.3GB (54%)"), in bytes.
static long long DockerSize(NSString *said) {
    NSScanner *scanner = [NSScanner scannerWithString:said];
    double number = 0;
    if (![scanner scanDouble:&number]) return 0;
    NSString *unit = @"";
    [scanner scanCharactersFromSet:NSCharacterSet.letterCharacterSet intoString:&unit];
    NSDictionary *units = @{@"B": @1, @"kB": @1e3, @"KB": @1e3, @"MB": @1e6, @"GB": @1e9, @"TB": @1e12};
    return (long long)(number * [units[unit] ?: @0 doubleValue]);
}

// What the tools say, asked off the map's queue: whether Homebrew is there; what Docker can free, or why it can't say
// (`docker` a number, or "off" while it isn't running, or "slow" when it didn't answer in time; missing without
// Docker); and the simulators no longer available, by id.
static NSDictionary *AskTools(void) {
    NSMutableDictionary *tools = [NSMutableDictionary dictionary];
    if (ToolPath(kBrewCleanup.firstObject)) tools[@"brew"] = @YES;
    if (ToolPath(kDockerSays.firstObject)) {
        NSDictionary *run = RunAsYourTerminal(kDockerSays, kToolSays, kToolOutput);
        long long free = 0;
        for (NSString *line in [Said(run) componentsSeparatedByString:@"\n"]) {
            NSArray<NSString *> *parts = [line componentsSeparatedByString:@"\t"];
            if (parts.count == 2 && [kDockerKinds containsObject:parts[0]]) free += DockerSize(parts[1]);
        }
        tools[@"docker"] = [run[@"timedOut"] boolValue] ? @"slow" : run && [run[@"status"] intValue] == 0 ? @(free)
                                                                                                        : @"off";
    }
    // xcrun is one of macOS's stand-ins for a developer tool, which offer to install them when they aren't there: it's
    // asked only once they are (simulators come with Xcode, which brings them).
    NSDictionary *run = DeveloperToolsReady() ? RunAsYourTerminal(kSimulatorsGone, kToolSays, kToolList) : nil;
    NSData *json = [run[@"status"] intValue] == 0 && ![run[@"clipped"] boolValue] ? run[@"out"] : nil;
    NSDictionary *devices = AsRecord(AsRecord(json ? [NSJSONSerialization JSONObjectWithData:json options:0 error:nil]
                                                   : nil)[@"devices"]);
    NSMutableArray *gone = [NSMutableArray array];
    for (NSString *runtime in devices)
        for (id device in AsList(devices[runtime]) ?: @[])
            if (AsText(AsRecord(device)[@"udid"])) [gone addObject:AsRecord(device)[@"udid"]];
    if (gone.count) tools[@"simulators"] = gone;
    return tools;
}

#pragma mark Worktrees

// git in a repo the sessions are in, never running a program its own settings name to watch its files, and only the
// developer tools' own (RunGit): until Apple's developer tools are there, nothing runs and no worktree is done with.
static NSString *GitSays(NSString *folder, NSArray<NSString *> *arguments, int *status) {
    NSDictionary *run = RunGit([@[@"--no-optional-locks", @"-c", @"core.fsmonitor=false", @"-C", folder]
                                arrayByAddingObjectsFromArray:arguments]);
    if (status) *status = run ? [run[@"status"] intValue] : -1;
    return [Said(run) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

// When a folder last changed: the folder itself, or `also` (a checkout's index), whichever is later; 0 if neither is
// there.
static NSTimeInterval ChangedAt(NSString *folder, NSString *also) {
    NSTimeInterval at = 0;
    for (NSString *path in @[folder ?: @"", also ?: @""]) {
        struct stat st;
        if (path.length && lstat(path.fileSystemRepresentation, &st) == 0) at = MAX(at, st.st_mtimespec.tv_sec);
    }
    return at;
}

// "changed today", "changed 9 days ago", "not changed in 5 months", "not changed in over a year".
static NSString *Changed(NSTimeInterval at, NSTimeInterval now) {
    double days = floor((now - at) / kDay);
    if (days < 1) return @"changed today";
    if (days < 2) return @"changed yesterday";
    if (days < 45) return [NSString stringWithFormat:@"changed %.0f days ago", days];
    if (days < 365) return [NSString stringWithFormat:@"not changed in %.0f months", round(days / 30.4)];
    return @"not changed in over a year";
}

// A worktree of a checkout the sessions are in, if you're done with it: merged into its repo's main branch, nothing in
// it not committed (new files too), no session listed there, and not changed for a week. {path, main, base, changedAt}.
static NSDictionary *DoneWith(NSString *path, NSString *head, NSString *main, NSString *base,
                              NSSet<NSString *> *listed, NSTimeInterval now) {
    for (NSString *checkout in listed) if (Within(checkout, path) || Within(path, checkout)) return nil;
    int status = 0;
    GitSays(main, @[@"merge-base", @"--is-ancestor", head, base], &status);
    if (status != 0) return nil;
    NSString *changes = GitSays(path, @[@"status", @"--porcelain", @"--untracked-files=normal"], &status);
    if (status != 0 || changes.length) return nil;
    NSString *index = GitSays(path, @[@"rev-parse", @"--path-format=absolute", @"--git-path", @"index"], &status);
    NSTimeInterval at = ChangedAt(path, status == 0 ? index : nil);
    if (!at || now - at < kWorktreeDone * kDay) return nil;
    return @{@"path": path, @"main": main, @"base": base, @"changedAt": @(at)};
}

// The worktrees you're done with, of the repos the sessions' checkouts are in. Each repo's main checkout is never one.
static NSArray<NSDictionary *> *DoneWorktrees(NSArray<NSString *> *checkouts, NSTimeInterval now) {
    NSMutableArray *done = [NSMutableArray array];
    NSMutableSet *mains = [NSMutableSet set];
    NSSet *listed = [NSSet setWithArray:checkouts ?: @[]];
    for (NSString *checkout in checkouts) {
        int status = 0;
        NSString *common = GitSays(checkout, @[@"rev-parse", @"--path-format=absolute", @"--git-common-dir"], &status);
        if (status != 0 || ![common.lastPathComponent isEqualToString:@".git"]) continue;
        NSString *main = common.stringByDeletingLastPathComponent;
        if ([mains containsObject:main]) continue;
        [mains addObject:main];
        NSString *base = GitSays(main, @[@"symbolic-ref", @"--short", @"refs/remotes/origin/HEAD"], &status);
        if (status != 0 || !base.length) {
            GitSays(main, @[@"show-ref", @"--verify", @"--quiet", @"refs/heads/main"], &status);
            base = status == 0 ? @"main" : @"master";
        }
        NSString *path = nil, *head = nil;
        for (NSString *line in [[GitSays(main, @[@"worktree", @"list", @"--porcelain"], &status)
                                 stringByAppendingString:@"\n"] componentsSeparatedByString:@"\n"]) {
            if ([line hasPrefix:@"worktree "]) path = [line substringFromIndex:9];
            else if ([line hasPrefix:@"HEAD "]) head = [line substringFromIndex:5];
            else if (!line.length && path) {
                NSDictionary *one = [path isEqualToString:main] || !head ? nil
                                  : DoneWith(path, head, main, base, listed, now);
                if (one) [done addObject:one];
                path = head = nil;
            }
        }
    }
    return done;
}

#pragma mark The list

NSArray<NSString *> *CleanUpUsualPlaces(void) {
    NSMutableArray *places = [NSMutableArray arrayWithObjects:kDerivedData, kDeviceSupport, kSimulatorDevices,
                                                              kBrewDownloads, nil];
    for (NSDictionary *each in [kCaches arrayByAddingObjectsFromArray:kModels]) [places addObject:each[@"path"]];
    return places;
}

@implementation Scanner (CleanUp)

// On the queue: the part of the map at a path, or nil; before the first map, of the first pass's usual places. A path
// git gave, with its links followed, is found too.
- (MapNode *)nodeAt:(NSString *)path {
    NSString *home = Home(), *real = RealPath(home);
    if (![real isEqualToString:home] && Within(path, real))
        path = [home stringByAppendingString:[path substringFromIndex:real.length]];
    for (MapNode *top in self.disk ? self.disk.kids : self.usual.kids) {
        if (!top.path || !Within(path, top.path)) continue;
        MapNode *n = top;
        NSString *rest = [path substringFromIndex:MIN(path.length, top.path.length + 1)];
        for (NSString *name in rest.length ? [rest componentsSeparatedByString:@"/"] : @[]) {
            MapNode *found = nil;
            for (MapNode *kid in n.kids) if ([kid.name isEqualToString:name]) { found = kid; break; }
            if (!(n = found)) return nil;
        }
        return n;
    }
    return nil;
}

// The folders a build or an install makes again in a checkout: by name wherever they are in it (but inside one another,
// or in a checkout of its own within it), by their path within one of its folders, and Rust's target beside its
// Cargo.toml.
static void FindBuilt(MapNode *n, NSMutableArray<MapNode *> *found) {
    for (MapNode *kid in n.kids) {
        if (!kid.kids || kid.unread || kid.repo) continue;
        NSString *within = [n.name stringByAppendingPathComponent:kid.name];
        BOOL built = [kBuiltNames containsObject:kid.name] || [kBuiltPaths containsObject:within]
            || ([kid.name isEqualToString:kCargoTarget] && [NSFileManager.defaultManager
                   fileExistsAtPath:[n.path stringByAppendingPathComponent:kCargoManifest]]);
        if (built) [found addObject:kid];
        else FindBuilt(kid, found);
    }
}

// An item of the list: what the page shows, and what cleaning it takes (its parts on the map, or a tool's commands).
static NSMutableDictionary *Item(NSString *itemId, NSString *name, NSString *where, long long size, BOOL on) {
    return [@{@"id": itemId, @"name": name, @"where": where ?: @"", @"size": @(size), @"on": @(on)} mutableCopy];
}

// On the queue: what keeps any of an item's parts on the map, said of the first that can't go.
- (NSDictionary *)lockOfParts:(NSArray<MapNode *> *)parts {
    NSSet *ignored = [self ignoredAmong:parts];
    for (MapNode *n in parts) {
        NSDictionary *lock = [self lockOf:n ignored:ignored];
        if (lock) return lock;
    }
    return nil;
}

// On the queue: an item of folders on the map, or nil when they're too small to bother with.
- (NSMutableDictionary *)folders:(NSArray<MapNode *> *)parts id:(NSString *)itemId name:(NSString *)name
                           where:(NSString *)where on:(BOOL)on {
    long long size = 0;
    for (MapNode *n in parts) size += n.size;
    if (size < kWorthIt) return nil;
    NSMutableDictionary *item = Item(itemId, name, where, size, on);
    item[@"parts"] = parts;
    NSDictionary *lock = [self lockOfParts:parts];
    if (lock) item[@"lock"] = @{@"says": lock[@"says"], @"kind": lock[@"kind"]};
    return item;
}

// On the queue: everything that comes back on its own, from the map and what the tools said, in its groups:
// {groups: [{id, title, says, items}], items: {id: item}}. Each item is {id, name, where, size, on, lock, command},
// with `parts` (its folders on the map) or `run` (its commands) for cleaning it.
- (NSDictionary *)cleanUpWith:(NSDictionary *)tools worktrees:(NSArray<NSDictionary *> *)worktrees
                          now:(NSTimeInterval)now {
    NSString *home = Home();
    NSMutableArray *built = [NSMutableArray array], *caches = [NSMutableArray array], *own = [NSMutableArray array],
                   *trees = [NSMutableArray array], *models = [NSMutableArray array];
    NSMutableDictionary *item;

    // Built files: Xcode's; then, once the map has found them, each checkout's, biggest first.
    MapNode *derived = [self nodeAt:[home stringByAppendingPathComponent:kDerivedData]];
    if (derived && (item = [self folders:@[derived] id:[@"folder:" stringByAppendingString:derived.path]
                                    name:@"Xcode's built files" where:@"DerivedData, for every project Xcode has built"
                                      on:YES])) [built addObject:item];
    NSMutableArray *checkouts = [NSMutableArray array];
    for (MapNode *n in self.nodes.allValues) {
        if (!n.repo || !n.path || !Within(n.path, home)) continue;
        NSMutableArray<MapNode *> *found = [NSMutableArray array];
        FindBuilt(n, found);
        if (!found.count) continue;
        NSMutableOrderedSet *names = [NSMutableOrderedSet orderedSet];
        for (MapNode *part in found) [names addObject:[kBuiltNames containsObject:part.name] ? part.name
                                                       : [part.parent.name stringByAppendingPathComponent:part.name]];
        NSString *what = names.count == 1 ? names.firstObject : [NSString stringWithFormat:@"%@ and %@",
            [[names.array subarrayWithRange:NSMakeRange(0, names.count - 1)] componentsJoinedByString:@", "],
            names.lastObject];
        NSTimeInterval at = ChangedAt(n.path, [n.path stringByAppendingPathComponent:@".git/index"]);
        item = [self folders:found id:[@"built:" stringByAppendingString:n.path] name:what
                       where:[NSString stringWithFormat:@"%@ · %@", n.name, Changed(at, now)]
                          on:now - at >= kBuiltOld * kDay];
        if (item) [checkouts addObject:item];
    }
    [checkouts sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"size"] compare:a[@"size"]];
    }];

    // Your tools' caches, and models, as their folders.
    for (NSDictionary *cache in kCaches) {
        MapNode *n = [self nodeAt:[home stringByAppendingPathComponent:cache[@"path"]]];
        if (n && (item = [self folders:@[n] id:[@"folder:" stringByAppendingString:n.path]
                                  name:cache[@"name"] where:cache[@"where"] on:YES])) [caches addObject:item];
    }
    for (NSDictionary *model in kModels) {
        MapNode *n = [self nodeAt:[home stringByAppendingPathComponent:model[@"path"]]];
        if (n && (item = [self folders:@[n] id:[@"folder:" stringByAppendingString:n.path]
                                  name:model[@"name"] where:model[@"where"] on:NO])) [models addObject:item];
    }

    // What only a tool should clean, by its own command; and Xcode's support files for older iOS versions, which go
    // with the caches, as Xcode fetches them again.
    if (tools[@"brew"]) {
        MapNode *downloads = [self nodeAt:[home stringByAppendingPathComponent:kBrewDownloads]];
        item = Item(@"brew", @"Homebrew's old downloads and versions", @"Homebrew takes them out itself",
                    downloads.size, YES);
        item[@"command"] = [kBrewCleanup componentsJoinedByString:@" "];
        item[@"run"] = @[kBrewCleanup];
        [own addObject:item];
    }
    id docker = tools[@"docker"];
    if (docker) {
        item = Item(@"docker", @"Docker's unused images and build cache",
                    @"Containers, running or stopped, and their images stay",
                    [docker isKindOfClass:NSNumber.class] ? [docker longLongValue] : 0, NO);
        NSMutableArray *said = [NSMutableArray array];
        for (NSArray *command in kDockerPrune) [said addObject:[command componentsJoinedByString:@" "]];
        item[@"command"] = [said componentsJoinedByString:@"\n"];
        item[@"run"] = kDockerPrune;
        // While Docker can't say, the list is asked for again every few seconds (`waits`), and Open Docker is offered
        // when it isn't running.
        if (![docker isKindOfClass:NSNumber.class]) {
            BOOL off = [docker isEqual:@"off"];
            item[@"lock"] = @{@"says": off ? @"Docker isn't running: open it, and this looks again by itself"
                                           : @"Docker didn't answer in time: this looks again by itself"};
            item[@"waits"] = @YES;
            if (off) item[@"open"] = @{@"app": @"docker", @"name": @"Docker"};
        }
        if (item[@"lock"] || [item[@"size"] longLongValue] >= kWorthIt) [own addObject:item];
    }
    NSArray *gone = tools[@"simulators"];
    if (gone.count) {
        long long size = 0;
        for (NSString *udid in gone)
            size += [self nodeAt:[[home stringByAppendingPathComponent:kSimulatorDevices]
                                    stringByAppendingPathComponent:udid]].size;
        item = Item(@"simulators", gone.count == 1 ? @"A simulator that's no longer available"
                    : [NSString stringWithFormat:@"%lu simulators that are no longer available", (unsigned long)gone.count],
                    @"For iOS versions Xcode no longer has", size, YES);
        item[@"command"] = [kSimulatorsDelete componentsJoinedByString:@" "];
        item[@"run"] = @[kSimulatorsDelete];
        if (size >= kWorthIt) [own addObject:item];
    }
    MapNode *support = [self nodeAt:[home stringByAppendingPathComponent:kDeviceSupport]];
    NSMutableArray<MapNode *> *versions = [NSMutableArray array];
    for (MapNode *kid in support.kids) if (kid.kids) [versions addObject:kid];
    [versions sortUsingComparator:^NSComparisonResult(MapNode *a, MapNode *b) {
        return [@(ChangedAt(b.path, nil)) compare:@(ChangedAt(a.path, nil))];
    }];
    if (versions.count > 1) {
        NSArray *older = [versions subarrayWithRange:NSMakeRange(1, versions.count - 1)];
        NSMutableArray *named = [NSMutableArray array];
        for (MapNode *n in older) [named addObject:n.name];
        item = [self folders:older id:@"support" name:@"Support files for older iOS versions"
                       where:[NSString stringWithFormat:@"%@ · Xcode adds them again when a phone on one connects",
                              [named componentsJoinedByString:@", "]] on:YES];
        if (item) [caches addObject:item];
    }

    // Worktrees you're done with: each folder goes to the Trash, ignored files and all, checked as any part of the map
    // is; git then forgets it, and its branch stays.
    for (NSDictionary *tree in worktrees) {
        MapNode *n = [self nodeAt:tree[@"path"]];
        if (!n) continue;
        item = [self folders:@[n] id:[@"worktree:" stringByAppendingString:n.path] name:n.name
                       where:[NSString stringWithFormat:@"Merged into %@ · %@", tree[@"base"],
                              Changed([tree[@"changedAt"] doubleValue], now)] on:YES];
        if (!item) continue;
        item[@"worktree"] = tree;
        [trees addObject:item];
    }

    // What the map finds (each project's built files, and worktrees you're done with) comes last, so it joins the list
    // at its foot once the disk is measured, and what's there already stays where it is.
    NSArray *groups = @[
        @{@"id": @"built", @"title": @"Xcode's built files", @"says": @"Built again the next time you build",
          @"items": built},
        @{@"id": @"caches", @"title": @"Your tools' caches", @"says": @"Downloaded again when they're needed",
          @"items": caches},
        @{@"id": @"tools", @"title": @"Space your tools clean up",
          @"says": @"With the tool's own command, shown here before it runs", @"items": own},
        @{@"id": @"models", @"title": @"Models", @"says": @"Downloaded again the next time you use one",
          @"items": models},
        @{@"id": @"projects", @"title": @"Your projects' built files", @"says": @"Built again the next time you build",
          @"items": checkouts},
        @{@"id": @"worktrees", @"title": @"Worktrees you're done with",
          @"says": @"Their branches are merged: the folder goes to the Trash, and the branch stays", @"items": trees},
    ];
    NSMutableDictionary *byId = [NSMutableDictionary dictionary];
    for (NSDictionary *group in groups) for (NSDictionary *each in group[@"items"]) byId[each[@"id"]] = each;
    return @{@"groups": groups, @"items": byId};
}

// What the page is sent of the list: each group with its items, without what cleaning them takes; whether worktrees
// wait for Apple's developer tools (`tools`); and whether it's only the usual places so far (`usual`), the map still
// being measured.
static NSDictionary *ForThePage(NSDictionary *list, double scannedAt, BOOL tools, BOOL usual) {
    NSMutableArray *groups = [NSMutableArray array];
    for (NSDictionary *group in list[@"groups"]) {
        NSMutableArray *items = [NSMutableArray array];
        for (NSDictionary *item in group[@"items"]) {
            NSMutableDictionary *shown = [item mutableCopy];
            [shown removeObjectsForKeys:@[@"parts", @"run", @"worktree"]];
            [items addObject:shown];
        }
        if (items.count) [groups addObject:@{@"id": group[@"id"], @"title": group[@"title"], @"says": group[@"says"],
                                             @"items": items}];
    }
    return @{@"groups": groups, @"scannedAt": scannedAt ? @(scannedAt) : NSNull.null, @"tools": @(tools),
             @"usual": @(usual)};
}

// The list, worked out on the map's queue once the tools have been asked (on their own queue, what they said taken as
// known for a few seconds) and the worktrees looked at.
- (void)cleanUpAskingTools:(BOOL)ask then:(void (^)(NSDictionary *list))then {
    NSArray *checkouts = self.sessionCheckouts;
    dispatch_async(self.cleaning, ^{
        NSTimeInterval now = NSDate.date.timeIntervalSince1970;
        if (ask && (!self.toolsSaid || now - self.toolsAt > kToolsFor)) {
            self.toolsSaid = AskTools();
            self.toolsAt = now;
        }
        NSDictionary *tools = ask ? self.toolsSaid : @{};
        NSArray *worktrees = DoneWorktrees(checkouts, now);
        dispatch_async(self.queue, ^{
            [self loadIfNeeded];
            then(self.disk || self.usual ? [self cleanUpWith:tools worktrees:worktrees now:now] : nil);
        });
    });
}

- (void)cleanUp:(void (^)(NSDictionary *list))done {
    [self cleanUpAskingTools:YES then:^(NSDictionary *list) {
        // Whether worktrees wait for Apple's developer tools: git isn't run before they're there.
        BOOL tools = self.sessionCheckouts.count && !DeveloperToolsReady();
        NSDictionary *shown = list ? ForThePage(list, self.scannedAt, tools, !self.disk) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ done(shown); });
    }];
}

#pragma mark Cleaning

// What to do about something that stayed, said after why, so every "stayed" says how to get it to go: by what kept it
// (a lock's kind), or what went wrong as it went. Nil where why says it already, or there's nothing to do.
NSString *CleanUpThen(NSString *kind, NSString *why) {
    if ([kind isEqualToString:@"agent"]) return @"Clean Up again once it's done";
    if ([kind isEqualToString:@"measuring"]) return @"Clean Up again once your disk is measured";
    if ([kind isEqualToString:@"repo"])
        return [why containsString:@"developer tools"] ? @"Install them, then Clean Up again"
                                                       : @"Commit and push it, then Clean Up again";
    if ([kind isEqualToString:@"unread"]) return @"Allow Full Disk Access, then Clean Up again";
    if ([why hasPrefix:@"macOS didn't move it"]) return @"Move it to the Trash yourself, in Finder";
    if ([why hasSuffix:@" isn't there"]) return @"Install it, or untick it";
    if ([kind isEqualToString:@"tool"]) return @"Run its command in Terminal to see why";
    return nil;
}

// What you ticked, found again in the list as it is now, so nothing goes that isn't on it, or that something keeps
// now; nothing at all if the map was measured again since the list you ticked was worked out (`measuredAt`). Folders
// go to the Trash on the map's queue, each checked again first, a worktree once its being done with is checked again
// too, and git then forgets the worktrees that went; then each tool's commands run, one at a time, off the map's queue.
// Each step is told as it goes (`progress`, on the main thread): {id, state: moving, trashed, running, done or stayed,
// why, then}.
- (void)clean:(NSArray<NSString *> *)ids measuredAt:(double)measuredAt
     progress:(void (^)(NSDictionary *step))progress done:(void (^)(NSDictionary *result))done {
    NSSet *listed = [NSSet setWithArray:self.sessionCheckouts ?: @[]];
    void (^tell)(NSString *, NSString *, NSString *, NSString *) = ^(NSString *itemId, NSString *state, NSString *why,
                                                                     NSString *then) {
        NSMutableDictionary *step = [@{@"id": itemId, @"state": state} mutableCopy];
        if (why) step[@"why"] = why;
        if (then) step[@"then"] = then;
        if (progress) dispatch_async(dispatch_get_main_queue(), ^{ progress(step); });
    };
    [self cleanUpAskingTools:!self.noTools then:^(NSDictionary *list) {
        NSMutableArray *cleaned = [NSMutableArray array], *failed = [NSMutableArray array],
                       *commands = [NSMutableArray array];
        NSMutableSet<NSString *> *forget = [NSMutableSet set];
        long long freed = 0;
        BOOL since = measuredAt && fabs(measuredAt - self.scannedAt) > 1;
        void (^stayed)(NSString *, NSString *, NSString *, NSString *) = ^(NSString *itemId, NSString *name,
                                                                          NSString *why, NSString *then) {
            [failed addObject:then ? @{@"id": itemId, @"name": name, @"why": why, @"then": then}
                                   : @{@"id": itemId, @"name": name, @"why": why}];
            tell(itemId, @"stayed", why, then);
        };
        for (NSString *itemId in ids) {
            if (![itemId isKindOfClass:NSString.class]) continue;
            NSDictionary *item = list[@"items"][itemId];
            if (!item) {
                tell(itemId, @"stayed", @"It isn't on the list now", @"Look at the list again");
                continue;
            }
            NSString *why = since ? @"The map was measured again since: look at the list again" : item[@"lock"][@"says"];
            NSString *kind = since ? nil : item[@"lock"][@"kind"];
            NSDictionary *tree = item[@"worktree"];
            if (!why && tree && !DoneWith(tree[@"path"], GitSays(tree[@"path"], @[@"rev-parse", @"HEAD"], NULL),
                                          tree[@"main"], tree[@"base"], listed, NSDate.date.timeIntervalSince1970))
                why = @"It's changed since: look again";
            if (why) {
                stayed(itemId, item[@"name"], why, CleanUpThen(kind, why));
                continue;
            }
            if (item[@"run"]) {
                [commands addObject:item];
                continue;
            }
            tell(itemId, @"moving", nil, nil);
            long long before = freed;
            NSMutableArray *refused = [NSMutableArray array];
            for (MapNode *n in item[@"parts"]) {
                NSString *partWhy = [self whyNot:n];
                if (partWhy) [refused addObject:@{@"name": n.name, @"why": partWhy}];
                else [self move:n size:&freed refused:refused];
            }
            if (freed > before) {
                [cleaned addObject:item[@"name"]];
                if (tree) [forget addObject:tree[@"main"]];
            }
            // What went, and what of it stayed, if anything: it says why, and what to do.
            for (NSDictionary *each in refused)
                [failed addObject:@{@"id": itemId, @"name": each[@"name"], @"why": each[@"why"],
                                    @"then": CleanUpThen(nil, each[@"why"]) ?: NSNull.null}];
            NSString *first = [refused.firstObject objectForKey:@"why"];
            if (freed > before) tell(itemId, @"trashed", first, first ? CleanUpThen(nil, first) : nil);
            else tell(itemId, @"stayed", first ?: @"Nothing of it went", first ? CleanUpThen(nil, first) : nil);
        }
        dispatch_async(self.cleaning, ^{
            for (NSString *main in forget) GitSays(main, @[@"worktree", @"prune"], NULL);
            long long byTools = 0;
            for (NSDictionary *item in commands) {
                tell(item[@"id"], @"running", nil, nil);
                NSString *why = nil;
                for (NSArray<NSString *> *command in item[@"run"]) {
                    NSDictionary *run = self.noTools ? nil : RunAsYourTerminal(command, kToolCleans, kToolOutput);
                    if (!run) why = [NSString stringWithFormat:@"%@ isn't there", command.firstObject];
                    else if ([run[@"timedOut"] boolValue]) why = @"It didn't finish in 10 minutes";
                    else if ([run[@"status"] intValue] != 0) {
                        NSArray *lines = [[Said(run) stringByTrimmingCharactersInSet:
                                           NSCharacterSet.whitespaceAndNewlineCharacterSet]
                                          componentsSeparatedByString:@"\n"];
                        why = [lines.lastObject length] ? lines.lastObject : @"It stopped with an error";
                    }
                    if (why) break;
                }
                if (why) stayed(item[@"id"], item[@"name"], why, CleanUpThen(@"tool", why));
                else {
                    [cleaned addObject:item[@"name"]];
                    byTools += [item[@"size"] longLongValue];
                    tell(item[@"id"], @"done", nil, nil);
                }
            }
            self.toolsSaid = nil;
            NSDictionary *result = @{@"freed": @(freed + byTools), @"trashed": @(freed), @"cleaned": cleaned,
                                     @"failed": failed, @"ran": @(commands.count)};
            dispatch_async(dispatch_get_main_queue(), ^{ done(result); });
        });
    }];
}

- (void)noteCheckouts:(NSArray<NSString *> *)checkouts {
    self.sessionCheckouts = checkouts ?: @[];
}

@end

#pragma mark For the tests

NSDictionary *UsualCleanUpOfHome(NSDictionary<NSString *, NSString *> *busy) {
    Scanner *scanner = [[Scanner alloc] initWithFile:@"/dev/null"];
    Measure *m = [Measure new];
    scanner.usual = MeasureUsual(m);
    scanner.fullDiskAccess = m.fullDiskAccess;
    scanner.busyHere = busy ?: @{};
    [scanner indexUsual];
    NSDictionary *list = [scanner cleanUpWith:@{} worktrees:@[] now:NSDate.date.timeIntervalSince1970];
    NSMutableDictionary *shown = [ForThePage(list, 0, NO, YES) mutableCopy];
    [shown removeObjectForKey:@"scannedAt"];
    return shown;
}

NSDictionary *CleanOfHome(NSString *standIn, NSDictionary<NSString *, NSString *> *busy, NSArray<NSString *> *ids,
                          BOOL stale, NSString *linked) {
    Scanner *scanner = ScannerOfHome(busy);
    if (!scanner) return nil;
    // What the map found, reached through a link by the time it's cleaned: the same folder, somewhere else now.
    if (linked && Within(linked, Home()) && ![linked isEqualToString:Home()]) {
        NSString *aside = [linked stringByAppendingString:@" elsewhere"];
        if (![NSFileManager.defaultManager moveItemAtPath:linked toPath:aside error:nil]
            || ![NSFileManager.defaultManager createSymbolicLinkAtPath:linked withDestinationPath:aside error:nil])
            return nil;
    }
    scanner.standInTrash = standIn;
    scanner.noTools = YES;
    NSMutableArray *steps = [NSMutableArray array];
    __block NSDictionary *result = nil;
    // A map measured again since: the list was worked out from another than this one.
    [scanner clean:ids measuredAt:stale ? 1000 : 0 progress:^(NSDictionary *step) { [steps addObject:step]; }
              done:^(NSDictionary *done) { result = done; }];
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:30];
    while (!result && until.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
    return @{@"steps": steps, @"result": result ?: NSNull.null};
}

NSDictionary *CleanUpOfHome(NSDictionary<NSString *, NSString *> *busy, NSArray<NSString *> *checkouts) {
    Scanner *scanner = ScannerOfHome(busy);
    if (!scanner) return nil;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSDictionary *list = [scanner cleanUpWith:@{} worktrees:DoneWorktrees(checkouts, now) now:now];
    NSMutableDictionary *shown = [ForThePage(list, 0, checkouts.count && !DeveloperToolsReady(), NO) mutableCopy];
    [shown removeObjectForKey:@"scannedAt"];
    return shown;
}
