// Routes: where a project's tickets open (Routes.h says what each function answers).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Routes.h"
#import "Files.h"
#import "Git.h"

BOOL RouteFolderOfProject(NSString *project, NSString *folder) {
    NSString *real = RealPath(folder), *root = RealPath(project);
    if (!real || !root) return NO;
    // As git has it, so a folder moved away or made by hand in the worktrees' place doesn't count.
    return CheckoutsInFiles(root)[real] != nil;
}

// A way in one of its shapes, with what it carries checked, or nil. A field's folders keep only those that are still
// the project's own; one let go is said in `dropped`.
static NSDictionary *WayChecked(NSString *project, id given, NSMutableArray<NSString *> *dropped) {
    NSDictionary *way = AsRecord(given);
    NSString *kind = AsText(way[@"kind"]);
    if ([kind isEqual:@"own"] || [kind isEqual:@"folder"]) return @{@"kind": kind};
    if (![kind isEqual:@"field"]) return nil;
    NSDictionary *field = AsRecord(way[@"field"]);
    NSString *fieldId = AsText(field[@"id"]), *fieldName = AsText(field[@"name"]);
    NSString *tracker = AsText(way[@"tracker"]), *site = AsText(way[@"site"]);
    if (!fieldId.length || !fieldName.length || !tracker.length || !site.length) return nil;
    NSMutableDictionary *folders = [NSMutableDictionary dictionary];
    NSDictionary *givenFolders = AsRecord(way[@"folders"]) ?: @{};
    for (NSString *optionId in givenFolders) {
        NSDictionary *option = AsRecord(givenFolders[optionId]);
        NSString *name = AsText(option[@"name"]), *folder = AsText(option[@"folder"]);
        if (!optionId.length || !name.length) continue;
        // A folder that's there but isn't the project's own is let go. One that isn't there any more is kept, so the
        // card and Settings can say it has gone (RoutePlace), and nothing starts in it.
        BOOL there = folder.isAbsolutePath && [NSFileManager.defaultManager fileExistsAtPath:folder];
        if (folder && (!folder.isAbsolutePath || (there && !RouteFolderOfProject(project, folder)))) {
            [dropped addObject:[NSString stringWithFormat:@"%@: a folder that isn't one of the project's own was let go",
                                project.lastPathComponent]];
            folder = nil;
        }
        folders[optionId] = @{@"name": name, @"folder": !folder ? NSNull.null : there ? RealPath(folder)
                                                                         : folder.stringByStandardizingPath};
    }
    return @{@"kind": @"field", @"tracker": tracker, @"site": site, @"field": @{@"id": fieldId, @"name": fieldName},
             @"folders": folders};
}

NSDictionary *RoutesChecked(id json, NSMutableArray<NSString *> *dropped) {
    NSMutableDictionary *routes = [NSMutableDictionary dictionary];
    NSDictionary *given = AsRecord(json) ?: @{};
    for (NSString *project in given) {
        NSDictionary *entry = AsRecord(given[project]);
        // Kept by its main folder: a worktree's, or a folder that's no repo's main checkout now, isn't a project's.
        NSString *root = project.isAbsolutePath ? ProjectRoot(project) : nil;
        if (!root || ![RealPath(root) isEqualToString:RealPath(project)]) {
            [dropped addObject:[NSString stringWithFormat:@"%@: not a project's main folder now",
                                project.lastPathComponent]];
            continue;
        }
        NSDictionary *way = WayChecked(project, entry[@"runs"], dropped);
        if (!way) {
            [dropped addObject:[NSString stringWithFormat:@"%@: a way it doesn't know", project.lastPathComponent]];
            continue;
        }
        routes[project] = @{@"runs": way, @"at": AsNumber(entry[@"at"]) ?: @0};
    }
    return routes;
}

NSDictionary *RoutesRead(NSString *path, NSMutableArray<NSString *> *dropped) {
    return RoutesChecked(ReadJSON(path), dropped);
}

BOOL RoutesWrite(NSString *path, NSDictionary *routes) {
    NSString *folder = path.stringByDeletingLastPathComponent;
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES
                                             attributes:@{NSFilePosixPermissions: @0700} error:nil];
    NSData *data = [NSJSONSerialization dataWithJSONObject:routes ?: @{}
                                                   options:NSJSONWritingSortedKeys | NSJSONWritingPrettyPrinted
                                                     error:nil];
    if (!data) return NO;
    // Written beside it first, then moved into place, so a read never finds it half-written.
    NSString *fresh = [path stringByAppendingString:@".new"];
    [NSFileManager.defaultManager removeItemAtPath:fresh error:nil];
    if (![NSFileManager.defaultManager createFileAtPath:fresh contents:data
                                             attributes:@{NSFilePosixPermissions: @0600}]) return NO;
    return rename(fresh.fileSystemRepresentation, path.fileSystemRepresentation) == 0;
}

NSDictionary *RoutePlace(NSString *project, NSDictionary *way, NSDictionary<NSString *, NSDictionary *> *values) {
    NSString *kind = AsText(way[@"kind"]);
    if ([kind isEqual:@"folder"]) return @{@"kind": @"here"};
    if (![kind isEqual:@"field"]) return @{@"kind": @"own"};
    if (!values) return @{@"kind": @"own", @"why": @"unread"};
    NSString *fieldId = AsText(AsRecord(way[@"field"])[@"id"]);
    NSDictionary *value = AsRecord(values[fieldId]);
    NSString *optionId = AsText(value[@"id"]);
    if (!optionId.length) return @{@"kind": @"own", @"why": @"noValue"};
    NSDictionary *option = AsRecord(AsRecord(way[@"folders"])[optionId]);
    NSDictionary *named = @{@"id": optionId, @"name": AsText(value[@"name"]) ?: AsText(option[@"name"]) ?: @""};
    NSString *folder = AsText(option[@"folder"]);
    if (!folder) return @{@"kind": @"own", @"why": @"noFolder", @"value": named};
    if (!RouteFolderOfProject(project, folder)) return @{@"kind": @"own", @"why": @"gone", @"value": named,
                                                          @"folder": folder};
    if ([RealPath(folder) isEqualToString:RealPath(project)]) return @{@"kind": @"here", @"value": named};
    return @{@"kind": @"folder", @"folder": RealPath(folder), @"value": named};
}

// A name as the match compares it: lower case, without spaces, dashes or underscores.
static NSString *Squeezed(NSString *name) {
    NSMutableString *out = [NSMutableString string];
    NSCharacterSet *gone = [NSCharacterSet characterSetWithCharactersInString:@" \t-_"];
    for (NSUInteger i = 0; i < name.length; i++) {
        unichar c = [name characterAtIndex:i];
        if (![gone characterIsMember:c]) [out appendFormat:@"%C", c];
    }
    return out.lowercaseString;
}

NSDictionary *RouteMatch(NSString *project, NSArray<NSDictionary *> *options, NSDictionary<NSString *, NSString *> *checkouts) {
    NSString *projectName = Squeezed(project.lastPathComponent ?: @"");
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    // The folders in the same order each time, so a name two of them match goes to the same one.
    NSArray *folders = [checkouts.allKeys sortedArrayUsingSelector:@selector(compare:)];
    for (NSDictionary *option in options) {
        NSString *optionId = AsText(option[@"id"]), *name = AsText(option[@"name"]);
        if (!optionId.length || !name.length) continue;
        NSString *want = Squeezed(name), *found = nil;
        for (NSString *folder in folders) {
            NSString *base = Squeezed(folder.lastPathComponent), *branch = Squeezed(checkouts[folder] ?: @"");
            if ([branch isEqualToString:want] || [base isEqualToString:want]
                || [base isEqualToString:[projectName stringByAppendingString:want]]) {
                found = folder;
                break;
            }
        }
        out[optionId] = @{@"name": name, @"folder": found ?: NSNull.null};
    }
    return out;
}

NSString *RouteWayName(NSString *project, NSDictionary *way) {
    NSString *kind = AsText(way[@"kind"]);
    if ([kind isEqual:@"folder"]) return [NSString stringWithFormat:@"In %@ itself", project.lastPathComponent];
    if ([kind isEqual:@"field"])
        return [NSString stringWithFormat:@"By its %@ field", AsText(AsRecord(way[@"field"])[@"name"]) ?: @""];
    return @"Its own worktree";
}

NSString *RouteGoesTo(NSString *project, NSDictionary *way) {
    NSString *kind = AsText(way[@"kind"]);
    if ([kind isEqual:@"folder"]) return project.lastPathComponent;
    if ([kind isEqual:@"field"])
        return [NSString stringWithFormat:@"its %@'s folder", AsText(AsRecord(way[@"field"])[@"name"]) ?: @""];
    return @"its own worktree";
}

NSDictionary *RouteBeforeAfter(NSString *project, NSDictionary *was, NSDictionary *now, NSArray<NSString *> *busy) {
    NSString *after = RouteGoesTo(project, now);
    BOOL here = [AsText(now[@"kind"]) isEqual:@"folder"];
    if (here && busy.count) after = [after stringByAppendingFormat:@", beside %@", busy.firstObject];
    return @{@"before": [@"A new ticket → " stringByAppendingString:RouteGoesTo(project, was)],
             @"after": [@"A new ticket → " stringByAppendingString:after],
             @"warn": here && busy.count ? @"Two tickets in one folder can clash." : NSNull.null,
             @"keep": @"Tickets started already keep their folders."};
}
