// main: starts Whozmove, or runs one of the print modes the tests check (PrintRun): --print-rows, --print-waits and
// --print-routes here, and the modules' own.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "AppDelegate.h"
#import "Row.h"
#import "Files.h"
#import "Work.h"
#import "Core.h"
#import "Modules.h"
#import "Printing.h"

// `Whozmove --print-rows`: the rows the panel would get for the home folder in $HOME, as JSON, then quit.
// tests/rows.sh runs it against a sample home and compares with a recorded copy, so any change to how rows
// are built shows.
static int PrintRows(Core *core) {
    return PrintJSON([SettledRows(core) valueForKey:@"json"]);
}

// `Whozmove --print-waits`: for each listed session, why its island's steps and its Deploy would wait now (null when
// they wouldn't), as JSON, then quit. tests/rows.sh checks it: a step taken while another agent works in the same
// checkout would act on files half-way through a change.
static int PrintWaits(Core *core) {
    NSArray<Row *> *rows = SettledRows(core);
    NSMutableDictionary *waits = [NSMutableDictionary dictionary];
    for (Row *row in rows)
        if (row.sessionId) waits[row.sessionId] = WhyStepsWait(row, rows, @"These wait") ?: NSNull.null;
    return PrintJSON(waits);
}

// The print modes main.m runs itself, by flag, until each moves into the module it tests.
static NSDictionary<NSString *, PrintMode> *CorePrintModes(void) {
    return @{
        @"--print-rows": ^(Core *core, NSArray *a) { return PrintRows(core); },
        @"--print-waits": ^(Core *core, NSArray *a) { return PrintWaits(core); },
        @"--print-routes": ^(Core *core, NSArray *a) { return 0; },  // PrintRun runs it, before checking for clashes
    };
}

// Whatever two claim: the messages and print modes two modules claim (Modules), and any of the core's own print
// modes a module claims too.
static NSArray<NSString *> *Clashes(Core *core) {
    NSMutableArray *clashes = [core.modules.clashes mutableCopy];
    NSDictionary *own = CorePrintModes();
    for (NSString *flag in core.modules.printModeOwners)
        if (own[flag])
            [clashes addObject:[NSString stringWithFormat:@"print mode %@: core, %@", flag,
                                                         core.modules.printModeOwners[flag]]];
    return clashes;
}

// `Whozmove --print-routes`: who answers each of the page's messages and who has each print mode, the core or a module,
// and whatever two claim, as JSON, then quit. tests/checks.sh holds them against the messages the page sends.
static int PrintRoutes(Core *core) {
    NSMutableDictionary *printModes = [core.modules.printModeOwners mutableCopy];
    for (NSString *flag in CorePrintModes()) printModes[flag] = printModes[flag] ?: @"core";
    return PrintJSON(@{@"routes": core.modules.routes, @"printModes": printModes, @"clashes": Clashes(core)});
}

// A print run, for the tests: the mode `flag` names, from the module that has it or from here, given the arguments
// after the flag. Every module is made, as the app makes them, but none starts. Anything two claim fails every run but
// the routes', which says what.
static int PrintRun(NSString *flag, NSArray<NSString *> *arguments) {
    Core *core = [Core forPrinting];
    if ([flag isEqual:@"--print-routes"]) return PrintRoutes(core);
    NSArray<NSString *> *clashes = Clashes(core);
    for (NSString *clash in clashes) fprintf(stderr, "Claimed twice: %s\n", clash.UTF8String);
    if (clashes.count) return 1;
    PrintMode mode = [core.modules printMode:flag];
    if (mode) return mode(core, arguments);
    PrintMode own = CorePrintModes()[flag];
    if (own) return own(core, arguments);
    fprintf(stderr, "There's no print mode %s\n", flag.UTF8String);
    return 2;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        // A print run's flag is the first argument that starts with --print-; the ones after it are its own.
        NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
        NSUInteger at = [arguments indexOfObjectPassingTest:^BOOL(NSString *argument, NSUInteger i, BOOL *stop) {
            return i > 0 && [argument hasPrefix:@"--print-"];
        }];
        if (at != NSNotFound)
            return PrintRun(arguments[at], [arguments subarrayWithRange:NSMakeRange(at + 1, arguments.count - at - 1)]);
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
