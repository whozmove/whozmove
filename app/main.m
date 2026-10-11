// main: starts Whozmove. With --print-rows, --print-mode-moves or --print-typing it prints what tests/rows.sh checks.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "AppDelegate.h"
#import "Row.h"
#import "Checkouts.h"
#import "Transcripts.h"
#import "AgentDetails.h"
#import "Command.h"
#import "Terminal.h"
#import "Files.h"
#import "GitHub.h"
#import "Upstream.h"

static int PrintJSON(id object) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:object
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:nil];
    if (!json) return 1;
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    return 0;
}

// The rows read once, the way the panel reads them, waited for on the main run loop (10 seconds at most).
static NSArray *ReadRows(AppDelegate *delegate) {
    __block NSArray *rows = nil;
    [delegate readRows:^(NSArray<Row *> *read) {
        rows = read ?: @[];
    }];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!rows && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    return rows ?: @[];
}

// The rows for the home folder in $HOME, once the reads that run alongside (transcripts, git) have reported
// back: those finish on their own queues and report on the main run loop, which runs until none is left
// (10 seconds at most). GitHub is never asked, and files the whole Mac shares are read from that home folder
// too, so the rows depend on neither the network nor the Mac.
static NSArray *SettledRows(AppDelegate *delegate) {
    NeverAskGitHub = YES;
    MachineFilesInHome = YES;
    ReadRows(delegate);
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (deadline.timeIntervalSinceNow > 0 && (delegate.checkouts.checking || delegate.transcripts.reading))
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    return ReadRows(delegate);
}

// `Whozmove --print-rows`: the rows the panel would get for the home folder in $HOME, as JSON, then quit.
// tests/rows.sh runs it against a sample home and compares with a recorded copy, so any change to how rows
// are built shows.
static int PrintRows(void) {
    return PrintJSON([SettledRows([AppDelegate new]) valueForKey:@"json"]);
}

// `Whozmove --print-mode-moves`: for each terminal session in $HOME, why keys can't go into it now (null when they
// can), and the Shift+Tabs its mode menu would type to reach each mode (null where it offers none), as JSON, then
// quit. tests/rows.sh checks them: a wrong answer types into a session that isn't safe to type into, and a wrong
// count lands a session in another mode.
static int PrintModeMoves(void) {
    AppDelegate *delegate = [AppDelegate new];
    NSMutableDictionary *sessions = [NSMutableDictionary dictionary];
    for (Row *row in SettledRows(delegate)) {
        if ([row.entrypoint isEqual:@"claude-desktop"] || !row.sessionId)
            continue;
        NSArray *cycles = [delegate.agentDetails modeCyclesFor:row];
        NSMutableDictionary *moves = [NSMutableDictionary dictionary];
        for (NSArray<NSString *> *choice in ModeChoices()) {
            NSInteger presses = [delegate.agentDetails shiftTabsFrom:row.agent[@"mode"] to:choice[0]
                                                               cycles:cycles];
            moves[choice[0]] = presses > 0 ? @(presses) : NSNull.null;
        }
        Reason *why = WhyNotTypeInto(row.sessionId, row.pid);
        sessions[row.sessionId] = @{@"mode": row.agent[@"mode"] ?: @"", @"possibleCycles": cycles,
                                        @"presses": moves,
                                        @"whyNotType": why ? @{@"log": why.description, @"card": why.onCard}
                                                           : NSNull.null};
    }
    return PrintJSON(sessions);
}

// A terminal that writes down every key it's asked to put in, for --print-typing.
@interface RecordingTerminal : NSObject <Terminal>
@property (strong) NSMutableArray<NSString *> *keys;
@end

@implementation RecordingTerminal
- (NSString *)appId { return @"test"; }
- (NSString *)name { return @"Test"; }
- (NSString *)tabFor:(Row *)row unique:(BOOL *)unique { *unique = YES; return @"tab"; }
- (BOOL)focus:(Row *)row { return YES; }
- (void)newTabIn:(NSString *)folder {}
- (void)type:(NSString *)text inTab:(NSString *)tab { [self.keys addObject:[@"text " stringByAppendingString:text]]; }
- (void)press:(TerminalKey)key times:(NSInteger)times inTab:(NSString *)tab {
    NSString *name = @[@"Return", @"Backspace", @"Shift+Tab", @"Ctrl+S"][key];
    [self.keys addObject:[NSString stringWithFormat:@"%@ ×%ld", name, (long)times]];
}
@end

// `Whozmove --print-typing`: the keys a slash command is typed with, once into a session that stays at its prompt
// and once into one that turns busy after two keys, as JSON, then quit. tests/rows.sh checks them: a key out of
// place, or one more after the session has moved on, could answer a prompt.
static int PrintTyping(void) {
    NSMutableDictionary *runs = [NSMutableDictionary dictionary];
    for (NSString *run in @[@"stays at its prompt", @"turns busy after two keys"]) {
        RecordingTerminal *terminal = [RecordingTerminal new];
        terminal.keys = [NSMutableArray array];
        __block NSUInteger checked = 0;
        NSUInteger safe = [run hasPrefix:@"stays"] ? NSUIntegerMax : 2;
        TypeCommand(terminal, @"tab", @"/model claude-opus-5-5",
                    ^{ return checked++ < safe ? nil : [Reason status:@"busy"]; },
                    ^(Reason *why, NSUInteger typed, NSUInteger steps) {
            if (!why) DeleteFiller(terminal, @"tab");
            runs[run] = @{@"keys": terminal.keys, @"stopped": why ? why.description : NSNull.null};
        });
    }
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (deadline.timeIntervalSinceNow > 0 && runs.count < 2)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    return PrintJSON(runs);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if ([NSProcessInfo.processInfo.arguments containsObject:@"--print-rows"]) return PrintRows();
        if ([NSProcessInfo.processInfo.arguments containsObject:@"--print-mode-moves"]) return PrintModeMoves();
        if ([NSProcessInfo.processInfo.arguments containsObject:@"--print-typing"]) return PrintTyping();
        NSApplication *app = NSApplication.sharedApplication;
        // launchd starts the panel at login; a second copy (opened from Finder, say) bows out.
        for (NSRunningApplication *other in
                 [NSRunningApplication runningApplicationsWithBundleIdentifier:NSBundle.mainBundle.bundleIdentifier])
            if (other.processIdentifier != getpid()) return 0;
        app.activationPolicy = NSApplicationActivationPolicyAccessory;
        AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
