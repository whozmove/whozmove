// PluginInstall: Whozmove's hooks put into Claude Code, as its plugin, and kept up to date there.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// Sessions run Claude Code's own copy of the plugin, which it makes from the folder its marketplace reads
// (PluginFolder, in Whozmove's own folder), one copy per version: the hooks this app carries go there first, then
// Claude Code is told with its own commands, run as the usage check runs `claude`. Nothing here edits Claude Code's
// settings itself.
#import "PluginInstall.h"
#import <stdio.h>
#import "ClaudeCommand.h"
#import "ClaudeCodeFacts.h"
#import "Files.h"
#import "Log.h"
#import "Processes.h"

// How long one `claude plugin` command may take: about half a second each, but one can fetch.
static const NSTimeInterval kCommandTime = 60;

NSString *PluginFolder(void) {
    return AppDir(@"plugin");
}

// The version a copy of the plugin says it is, which names its hooks' contents (plugin.sh).
static NSString *VersionOf(NSString *plugin) {
    NSString *manifest = [plugin stringByAppendingPathComponent:@".claude-plugin/plugin.json"];
    return AsText(AsRecord(ReadJSON(manifest))[@"version"]);
}

// The copy Claude Code reads, made again from `hooks` when its version differs or it has gone (which also clears the
// "failed to load" Claude Code lists a plugin with while its folder is missing): copied beside it, then swapped in, so
// Claude Code never reads half of one. Whozmove's folder is yours alone, as Claude Code's own is. Nil once it's there,
// else why not.
static NSString *CopyHooks(NSString *hooks) {
    NSString *plugin = PluginFolder(), *want = VersionOf(hooks);
    if (!want) return @"This copy of Whozmove carries no hooks";
    if ([VersionOf(plugin) isEqualToString:want]) return nil;
    NSFileManager *files = NSFileManager.defaultManager;
    [files createDirectoryAtPath:AppDir(nil) withIntermediateDirectories:YES
                      attributes:@{NSFilePosixPermissions: @0700} error:nil];
    NSString *beside = [plugin stringByAppendingString:@".new"];
    [files removeItemAtPath:beside error:nil];
    if (![files copyItemAtPath:hooks toPath:beside error:nil]) return @"Couldn't copy the hooks into Whozmove's folder";
    BOOL swapped = [files fileExistsAtPath:plugin]
        ? renamex_np(beside.fileSystemRepresentation, plugin.fileSystemRepresentation, RENAME_SWAP) == 0
        : rename(beside.fileSystemRepresentation, plugin.fileSystemRepresentation) == 0;
    [files removeItemAtPath:beside error:nil];  // the copy that was there before, once swapped
    if (!swapped) return @"Couldn't put the hooks in Whozmove's folder";
    PanelLog(@"plugin: hooks %@ copied into Whozmove's folder", want);
    return nil;
}

// One `claude plugin` command, briefly, with what `claude` runs with (ClaudeEnvironment): {status, out, timedOut}, or
// nil if it couldn't start. `errors` puts what it says on its error output into `out` too.
static NSDictionary *Claude(NSString *claude, NSArray<NSString *> *arguments, NSDictionary *environment, BOOL errors) {
    NSDictionary *run = RunBriefly(claude, arguments, environment, kCommandTime, 256 * 1024, errors);
    PanelLog(@"plugin: claude %@ -> %@", [arguments componentsJoinedByString:@" "],
             !run ? @"didn't start" : [run[@"timedOut"] boolValue] ? @"too slow" : run[@"status"]);
    return run;
}

static BOOL Succeeded(NSDictionary *run) {
    return run && ![run[@"timedOut"] boolValue] && [run[@"status"] intValue] == 0;
}

// What a command that didn't work said last: the last line of what it printed that isn't empty, as the line shows it.
static NSString *LastLine(NSDictionary *run) {
    if (!run) return @"Claude Code didn't start";
    if ([run[@"timedOut"] boolValue]) return @"Claude Code took too long to answer";
    NSString *text = [[NSString alloc] initWithData:run[@"out"] encoding:NSUTF8StringEncoding] ?: @"";
    for (NSString *line in [text componentsSeparatedByString:@"\n"].reverseObjectEnumerator) {
        NSString *said = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (said.length) return Clip(said, 200);
    }
    return [NSString stringWithFormat:@"Claude Code stopped with %@", run[@"status"]];
}

// Claude Code's plugins, from `claude plugin list --json` (checked with 2.1.302): a list of entries, each with its id,
// version and whether it's enabled, and `errors` while it can't load. Read from the first [ to the last ], so a line it
// prints around the list can't hide it. Nil when that can't be read.
static NSArray<NSDictionary *> *Listed(NSDictionary *run) {
    if (!Succeeded(run)) return nil;
    NSData *out = run[@"out"];
    NSData *open = [@"[" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *close = [@"]" dataUsingEncoding:NSUTF8StringEncoding];
    NSRange from = out.length ? [out rangeOfData:open options:0 range:NSMakeRange(0, out.length)]
                              : NSMakeRange(NSNotFound, 0);
    NSRange to = out.length ? [out rangeOfData:close options:NSDataSearchBackwards range:NSMakeRange(0, out.length)]
                            : NSMakeRange(NSNotFound, 0);
    if (from.location == NSNotFound || to.location == NSNotFound || to.location < from.location) return nil;
    NSData *list = [out subdataWithRange:NSMakeRange(from.location, NSMaxRange(to) - from.location)];
    NSArray *entries = AsList([NSJSONSerialization JSONObjectWithData:list options:0 error:nil]);
    if (!entries) return nil;
    NSMutableArray *plugins = [NSMutableArray array];
    for (id entry in entries)
        if (AsRecord(entry)) [plugins addObject:entry];
    return plugins;
}

NSDictionary *ConnectPlugin(NSString *answer, BOOL before, NSString *hooks, NSString *path) {
    NSString *why = CopyHooks(hooks);
    if (why) return @{@"state": @"failed", @"detail": why};
    NSString *want = VersionOf(PluginFolder());
    NSArray<NSString *> *candidates = ClaudeCandidates(path);
    if (!candidates.count) return @{@"state": @"noCommand"};
    NSDictionary *environment = ClaudeEnvironment(path);
    // The first `claude` that lists its plugins: one that can't (too old, broken) gives way to the next, as for the
    // usage check.
    NSString *claude = nil;
    NSArray<NSDictionary *> *plugins = nil;
    NSDictionary *first = nil;
    for (NSString *each in candidates) {
        NSDictionary *run = Claude(each, PluginListArguments(), environment, NO);
        plugins = Listed(run);
        if (plugins) {
            claude = each;
            break;
        }
        if (!first) first = Claude(each, PluginListArguments(), environment, YES);  // again, for what it says
    }
    if (!claude) return @{@"state": @"failed", @"detail": LastLine(first)};

    NSDictionary *mine = nil;
    BOOL another = NO;
    for (NSDictionary *plugin in plugins) {
        NSString *pluginId = AsText(plugin[@"id"]);
        if ([pluginId isEqualToString:kWhozmovePlugin]) mine = plugin;
        else if ([pluginId hasPrefix:[kWhozmoveMarketplace stringByAppendingString:@"@"]]) another = YES;
    }
    if (!mine) {
        // A copy of Whozmove's plugin from a marketplace of your own is left as it is, with no second one beside it.
        if (another) {
            PanelLog(@"plugin: another marketplace's whozmove is installed, so it's left as it is");
            return @{@"state": @"ready"};
        }
        // Taken out since it was put in: left out, unless you ask for it back on the line.
        if (before && ![answer isEqualToString:@"addBack"]) return @{@"state": @"removed"};
        NSDictionary *run = Claude(claude, PluginMarketplaceAddArguments(PluginFolder()), environment, YES);
        if (Succeeded(run)) run = Claude(claude, PluginInstallArguments(), environment, YES);
        if (!Succeeded(run)) return @{@"state": @"failed", @"detail": LastLine(run)};
        return @{@"state": @"added"};
    }
    BOOL turnedOn = NO;
    if (![mine[@"enabled"] isEqual:@YES]) {
        if (![answer isEqualToString:@"turnOn"]) return @{@"state": @"turnedOff"};
        NSDictionary *run = Claude(claude, PluginEnableArguments(), environment, YES);
        if (!Succeeded(run)) return @{@"state": @"failed", @"detail": LastLine(run)};
        turnedOn = YES;
    }
    if (![AsText(mine[@"version"]) isEqualToString:want]) {
        NSDictionary *run = Claude(claude, PluginMarketplaceUpdateArguments(), environment, YES);
        if (Succeeded(run)) run = Claude(claude, PluginUpdateArguments(), environment, YES);
        if (!Succeeded(run)) return @{@"state": @"failed", @"detail": LastLine(run)};
        return @{@"state": turnedOn ? @"added" : @"updated"};
    }
    NSString *error = AsText(AsList(mine[@"errors"]).firstObject);
    if (error) return @{@"state": @"failed", @"detail": Clip(error, 200)};
    return @{@"state": turnedOn ? @"added" : @"ready"};
}
