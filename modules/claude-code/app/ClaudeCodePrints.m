// ClaudeCodePrints: the Claude Code module's print modes, which the tests check: --print-mode-moves, --print-typing,
// --print-results, --print-usage, --print-trust, --print-kept and --print-plugin-install.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "ClaudeCode.h"
#import "Core.h"
#import "Modules.h"
#import "Row.h"
#import "Files.h"
#import "Printing.h"
#import "ClaudeCodeFacts.h"
#import "AgentDetails.h"
#import "ClaudeUsage.h"
#import "ClaudeCommand.h"
#import "PluginInstall.h"
#import "Prompt.h"
#import "Results.h"
#import "Trust.h"
#import "Transcripts.h"
#import "KeptSessions.h"

// The module in a print run's core.
static ClaudeCode *AgentIn(Core *core) {
    for (id module in core.modules.all)
        if ([module isKindOfClass:ClaudeCode.class]) return module;
    return nil;
}

// `Whozmove --print-mode-moves`: for each terminal session in $HOME, why keys can't go into it now (null when they
// can), why the one Backspace a request may press while Claude works can't go in now (WhyNotEditDraft), and the
// Shift+Tabs its mode menu would type to reach each mode (null where it offers none), as JSON, then quit.
// tests/rows.sh checks them: a wrong answer types into a session that isn't safe to type into, and a wrong count
// lands a session in another mode.
static int PrintModeMoves(Core *core) {
    ClaudeCode *agent = AgentIn(core);
    NSMutableDictionary *sessions = [NSMutableDictionary dictionary];
    for (Row *row in SettledRows(core)) {
        if ([core hostHolding:row] || !row.sessionId)  // a conversation an app keeps (Claude Desktop's) has no tab
            continue;
        NSArray *cycles = [agent.details modeCyclesFor:row];
        NSMutableDictionary *moves = [NSMutableDictionary dictionary];
        for (NSArray<NSString *> *choice in ModeChoices()) {
            NSInteger presses = [agent.details shiftTabsFrom:row.agent[@"mode"] to:choice[0] cycles:cycles];
            moves[choice[0]] = presses > 0 ? @(presses) : NSNull.null;
        }
        Reason *why = WhyNotTypeInto(row.sessionId, row.pid), *edit = WhyNotEditDraft(row.sessionId, row.pid);
        sessions[row.sessionId] = @{@"mode": row.agent[@"mode"] ?: @"", @"possibleCycles": cycles,
                                        @"presses": moves,
                                        @"whyNotType": why ? @{@"log": why.description, @"card": why.onCard}
                                                           : NSNull.null,
                                        @"whyNotEditDraft": edit ? edit.description : NSNull.null};
    }
    return PrintJSON(sessions);
}

// A terminal that writes down every key it's asked to put in, for --print-typing, and refuses keys once it has been
// asked for `refuseAt` of them (0: never), as a terminal says when it didn't take one.
@interface RecordingTerminal : NSObject <TypingHost>
@property (strong) NSMutableArray<NSString *> *keys;
@property NSUInteger refuseAt;
@end

@implementation RecordingTerminal
- (NSString *)appId { return @"test"; }
- (NSString *)name { return @"Test"; }
- (NSString *)tabFor:(Row *)row unique:(BOOL *)unique { *unique = YES; return @"tab"; }
- (BOOL)open:(Row *)row { return YES; }
- (void)type:(NSString *)text inTab:(NSString *)tab { [self.keys addObject:[@"text " stringByAppendingString:text]]; }
- (void)press:(TerminalKey)key times:(NSInteger)times inTab:(NSString *)tab {
    NSString *name = @[@"Return", @"Backspace", @"Shift+Tab", @"Ctrl+S"][key];
    [self.keys addObject:[NSString stringWithFormat:@"%@ ×%ld", name, (long)times]];
}
- (NSString *)whyNotTypeIn:(NSString *)tab {
    return self.refuseAt && self.keys.count >= self.refuseAt ? @"It didn't take the last key" : nil;
}
@end

// `Whozmove --print-typing`: the keys a slash command is typed with, once into a session that stays at its prompt,
// once into one that turns busy after two keys, and once through a terminal that refuses the last key, the Return, as
// JSON, then quit. tests/rows.sh checks them: a key out of place, or one more after the session has moved on, could
// answer a prompt, and a refused Return taken for a command gone in would leave it waiting in the prompt.
static int PrintTyping(void) {
    NSMutableDictionary *runs = [NSMutableDictionary dictionary];
    NSArray *names = @[@"stays at its prompt", @"turns busy after two keys", @"its terminal refuses the Return"];
    for (NSString *run in names) {
        RecordingTerminal *terminal = [RecordingTerminal new];
        terminal.keys = [NSMutableArray array];
        if ([run hasPrefix:@"its terminal"]) terminal.refuseAt = 4;
        __block NSUInteger checked = 0;
        NSUInteger safe = [run hasPrefix:@"turns busy"] ? 2 : NSUIntegerMax;
        TypeCommand(terminal, @"tab", @"/model claude-opus-5-5",
                    ^{ return checked++ < safe ? nil : [Reason status:@"busy"]; },
                    ^(Reason *why, NSUInteger typed, NSUInteger steps) {
            if (!why) DeleteFiller(terminal, @"tab");
            runs[run] = @{@"keys": terminal.keys, @"stopped": why ? why.description : NSNull.null};
        });
    }
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (deadline.timeIntervalSinceNow > 0 && runs.count < names.count)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    return PrintJSON(runs);
}

// `Whozmove --print-results <command> <transcript>…`: for each pair, by the transcript's name, what's read from it as
// the command's result, all of it being new (CommandResult), and what the panel takes that result to say: the value
// now in effect for the field the command changes (null: it changed nothing), whether the pick was saved as the default
// for new sessions, and for /compact, what its card says (null: it compacted). As JSON, then quit. tests/rows.sh
// checks them against results written the way Claude Code writes them.
static int PrintResults(NSArray<NSString *> *arguments) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i + 1 < arguments.count; i += 2) {
        NSString *command = arguments[i], *file = arguments[i + 1];
        NSString *name = [[command componentsSeparatedByString:@" "].firstObject substringFromIndex:1];
        NSString *rest = [command substringFromIndex:MIN(command.length, name.length + 2)];
        NSString *field = [name isEqual:@"plan"] ? @"mode" : name, *value = [name isEqual:@"plan"] ? @"plan" : rest;
        NSString *result = CommandResult(file, 0, command);
        NSMutableDictionary *read = [@{@"command": command, @"result": result ?: NSNull.null,
                                       @"applies": ResultApplies(field, value, result) ?: NSNull.null,
                                       @"savedDefault": @(ResultSavedDefault(result))} mutableCopy];
        if ([field isEqual:@"compact"]) read[@"compactNote"] = CompactNote(result) ?: NSNull.null;
        out[file.lastPathComponent] = read;
    }
    return PrintJSON(out);
}

// `Whozmove --print-usage <file>…`: for each file, by its name, what the usage strip would take from it as Claude
// Code's output (the usage request's answer, read line by line, or null) and as `claude auth status`'s (signedIn,
// signedOut or null); then where `claude` is looked for, for the PATH in $USAGE_PATH and the home folder in $HOME; as
// JSON, then quit. tests/rows.sh checks them against recorded answers and sample installs.
static int PrintUsage(NSArray<NSString *> *files) {
    MachineFilesInHome = YES;
    NSMutableDictionary *read = [NSMutableDictionary dictionary];
    for (NSString *file in files) {
        NSData *data = [NSData dataWithContentsOfFile:file] ?: NSData.data;
        id usage = NSNull.null;
        for (NSString *line in [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                                componentsSeparatedByString:@"\n"]) {
            NSDictionary *answer = line.length ? UsageFromReply([line dataUsingEncoding:NSUTF8StringEncoding]) : nil;
            if (answer) {
                usage = answer;
                break;
            }
        }
        read[file.lastPathComponent] = @{@"usage": usage, @"auth": AuthStateFrom(data) ?: NSNull.null};
    }
    NSString *path = NSProcessInfo.processInfo.environment[@"USAGE_PATH"] ?: @"";
    NSMutableArray *candidates = [NSMutableArray array];  // from the home folder, so they read the same everywhere
    for (NSString *claude in ClaudeCandidates(path))
        [candidates addObject:[claude hasPrefix:Home()]
                                  ? [@"~" stringByAppendingString:[claude substringFromIndex:Home().length]]
                                  : claude];
    return PrintJSON(@{@"files": read, @"candidates": candidates});
}

// `Whozmove --print-trust [--trust <folder>] <folder>…`: whether Claude may work in each folder, as Claude Code's state
// file in $HOME has it, as JSON, then quit. With --trust, it's recorded for that folder first, and the result shows as
// "trusting": null once done, else why not.
static int PrintTrust(NSArray<NSString *> *arguments) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSMutableArray *folders = [arguments mutableCopy];
    NSUInteger at = [folders indexOfObject:@"--trust"];
    if (at != NSNotFound && at + 1 < folders.count) {
        out[@"trusting"] = TrustFolder(folders[at + 1]) ?: NSNull.null;
        [folders removeObjectsInRange:NSMakeRange(at, 2)];
    }
    for (NSString *folder in folders) out[folder] = @(FolderTrusted(folder));
    return PrintJSON(out);
}

// `Whozmove --print-kept`: what would be kept of each running terminal session in $HOME, so its row stays once it ends,
// with a stand-in for the terminal it runs in ("sample"), so it reads the same on every Mac; then which of the sessions
// kept there would be dropped, as their process has gone on to another conversation (`left`) or they've gone
// (`stale`), as JSON, then quit. Nothing is written: a print run keeps nothing. tests/rows.sh checks it.
static int PrintKept(Core *core) {
    ClaudeCode *agent = AgentIn(core);
    NSArray<Row *> *rows = SettledRows(core);
    NSMutableDictionary *keeps = [NSMutableDictionary dictionary];
    for (Row *row in rows) {
        NSDictionary *record = KeptRecord(row, [agent.transcripts stateOf:row.sessionId][@"path"], @"sample");
        if (record) keeps[row.sessionId] = record;
    }
    NSDictionary *kept = KeptIn(KeptFolder());
    return PrintJSON(@{@"keeps": keeps, @"left": LeftBehind(kept, rows),
                       @"stale": Stale(kept, [NSSet setWithArray:keeps.allKeys], NSDate.date.timeIntervalSince1970)});
}

// `Whozmove --print-plugin-install [--answer <press>] [--before] <hooks>`: puts the hooks in the folder `hooks` into
// Claude Code as the app does as it opens (ConnectPlugin), with `claude` looked for on $INSTALL_PATH first and in the
// home folder in $HOME, and prints what it reached, as JSON, then quits. `--answer` is your press on the line (addBack
// or turnOn), `--before` that they were put in once already. modules/claude-code/tests/test.sh runs it for each case,
// with a stand-in claude that writes down what it's asked. It changes Whozmove's folder there and runs the `claude` it
// finds, so it refuses to run in your own home folder.
static int PrintPluginInstall(NSArray<NSString *> *arguments) {
    if (HomeIsYourOwn()) {
        fprintf(stderr, "--print-plugin-install changes Claude Code in $HOME: run it with a throwaway HOME, as "
                        "modules/claude-code/tests/test.sh does\n");
        return 2;
    }
    MachineFilesInHome = YES;
    NSMutableArray<NSString *> *rest = [arguments mutableCopy];
    NSString *answer = nil;
    NSUInteger at = [rest indexOfObject:@"--answer"];
    if (at != NSNotFound && at + 1 < rest.count) {
        answer = rest[at + 1];
        [rest removeObjectsInRange:NSMakeRange(at, 2)];
    }
    BOOL before = [rest containsObject:@"--before"];
    [rest removeObject:@"--before"];
    if (rest.count != 1) {
        fprintf(stderr, "usage: --print-plugin-install [--answer addBack|turnOn] [--before] <hooks>\n");
        return 2;
    }
    NSString *path = NSProcessInfo.processInfo.environment[@"INSTALL_PATH"] ?: @"";
    return PrintJSON(ConnectPlugin(answer, before, rest[0], path));
}

NSDictionary<NSString *, PrintMode> *ClaudeCodePrintModes(void) {
    return @{
        @"--print-kept": ^(Core *core, NSArray *a) { return PrintKept(core); },
        @"--print-mode-moves": ^(Core *core, NSArray *a) { return PrintModeMoves(core); },
        @"--print-typing": ^(Core *core, NSArray *a) { return PrintTyping(); },
        @"--print-results": ^(Core *core, NSArray *a) { return PrintResults(a); },
        @"--print-usage": ^(Core *core, NSArray *a) { return PrintUsage(a); },
        @"--print-trust": ^(Core *core, NSArray *a) { return PrintTrust(a); },
        @"--print-plugin-install": ^(Core *core, NSArray *a) { return PrintPluginInstall(a); },
    };
}
