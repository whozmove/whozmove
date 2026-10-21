// main: starts Whozmove, or runs one of the print modes the tests check (PrintRun): --print-rows, --print-waits,
// --print-browsing, --print-edges and --print-routes here, and the modules' own.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "AppDelegate.h"
#import "Row.h"
#import "Files.h"
#import "Work.h"
#import "Core.h"
#import "Modules.h"
#import "Printing.h"
#import "Browser.h"
#import "PanelWindow.h"
#import "EdgeIcon.h"
#import "SideCat.h"

// `Whozmove --print-rows`: the rows the panel would get for the home folder in $HOME, as JSON, then quit.
// tests/rows.sh runs it against a sample home and compares with a recorded copy, so any change to how rows
// are built shows.
static int PrintRows(Core *core) {
    return PrintJSON([SettledRows(core) valueForKey:@"json"]);
}

// `Whozmove --print-waits`: for each listed session, why its next steps and its Deploy would wait now (null when
// they wouldn't), as JSON, then quit. tests/rows.sh checks it: a step taken while another agent works in the same
// checkout would act on files half-way through a change.
static int PrintWaits(Core *core) {
    NSArray<Row *> *rows = SettledRows(core);
    NSMutableDictionary *waits = [NSMutableDictionary dictionary];
    for (Row *row in rows)
        if (row.sessionId) waits[row.sessionId] = WhyStepsWait(row, rows, @"These wait") ?: NSNull.null;
    return PrintJSON(waits);
}

// `Whozmove --print-browsing <folder>`: where each kind of address goes from sample setups of a Browser (the web, a
// site and its links out, a folder's pages with and without the web's parts), the folders too wide to show a page
// from, the store each name's sign-ins are kept in, and how a Browser introduces itself, then quit. tests/browser.sh
// runs it on a sample folder: a page that could reach what it shouldn't, or a name kept in another store (which would
// sign you out), shows there.
static int PrintBrowsing(NSArray<NSString *> *arguments) {
    if (arguments.count != 1) {
        fprintf(stderr, "--print-browsing takes a folder\n");
        return 2;
    }
    NSString *top = arguments[0];
    BrowserSetup *folder = [BrowserSetup folder:[NSURL fileURLWithPath:top isDirectory:YES]];
    if (!folder) {
        fprintf(stderr, "%s can't be a page's folder\n", top.UTF8String);
        return 2;
    }
    BrowserSetup *web = [BrowserSetup web], *site = [BrowserSetup web];
    site.sites = @[@"google.com"];
    site.linksOut = YES;
    BrowserSetup *prototype = [folder copy], *parts = [folder copy];
    prototype.linksOut = parts.linksOut = YES;
    parts.webParts = YES;
    NSArray *setups = @[web, site, folder, prototype, parts];
    printf("Setups: [1] the web; [2] the web, staying on google.com, links out; [3] a folder; [4] a folder, links\n"
           "out; [5] a folder, links out, with the web's parts\n");
    NSString *file = [@"file://" stringByAppendingString:[NSURL fileURLWithPath:top].path];
    // Each: what it is, its address, as the page or a frame, and pressed or not.
    NSArray<NSArray *> *cases = @[
        @[@"the folder's page", [file stringByAppendingString:@"/page.html"], @YES, @NO],
        @[@"a # link on the same page", [file stringByAppendingString:@"/page.html#top"], @YES, @YES],
        @[@"a hash route", [file stringByAppendingString:@"/page.html#/settings/2"], @YES, @YES],
        @[@"a file beside it", [file stringByAppendingString:@"/beside.html"], @YES, @YES],
        @[@"a file in a folder in it", [file stringByAppendingString:@"/sub/inner.html"], @YES, @YES],
        @[@"a file that isn't there yet", [file stringByAppendingString:@"/later.html"], @YES, @NO],
        @[@"../ out of the folder", [file stringByAppendingString:@"/../outside/secret.html"], @YES, @YES],
        @[@"../ out of it, by itself", [file stringByAppendingString:@"/../outside/secret.html"], @YES, @NO],
        @[@"a link in it leading out", [file stringByAppendingString:@"/link/secret.html"], @YES, @YES],
        @[@"a folder named like it", [file stringByAppendingString:@"-other/page.html"], @YES, @YES],
        @[@"a file elsewhere, pressed", @"file:///etc/hosts", @YES, @YES],
        @[@"about:blank, a frame", @"about:blank", @NO, @NO],
        @[@"about:srcdoc, a frame", @"about:srcdoc", @NO, @NO],
        @[@"about:blank, a window", @"about:blank", @YES, @NO],
        @[@"data:, a frame", @"data:text/html,<p>hi</p>", @NO, @NO],
        @[@"data:, as the page", @"data:text/html,<p>hi</p>", @YES, @NO],
        @[@"blob:, a frame", @"blob:null/6f2c1a5e-0000-4000-8000-000000000001", @NO, @NO],
        @[@"javascript:, pressed", @"javascript:void(0)", @YES, @YES],
        @[@"a site, as the page", @"https://mail.google.com/mail/u/0/", @YES, @NO],
        @[@"a site's link to itself, pressed", @"https://mail.google.com/mail/u/0/#inbox", @YES, @YES],
        @[@"a link to another of its sites", @"https://accounts.google.com/Logout", @YES, @YES],
        @[@"a link to another site, pressed", @"https://news.example.com/story", @YES, @YES],
        @[@"a sign-in going to another site", @"https://login.example.com/oauth", @YES, @NO],
        @[@"a plain http site", @"http://example.com/", @YES, @NO],
        @[@"a frame of another site", @"https://www.youtube.com/embed/abc", @NO, @NO],
        @[@"an email link, pressed", @"mailto:someone@example.com", @YES, @YES],
        @[@"an email link, by itself", @"mailto:someone@example.com", @YES, @NO],
        @[@"an app's own link, pressed", @"zoommtg://zoom.us/join?confno=1", @YES, @YES],
        @[@"an address with no kind", @"example.com", @YES, @YES],
    ];
    NSDictionary<NSNumber *, NSString *> *words = @{@(BrowserLoads): @"loads", @(BrowserRefuses): @"refused",
                                                    @(BrowserOpensOutside): @"outside", @(BrowserAsksOwner): @"asks"};
    printf("%-34s %-8s %-8s %-8s %-8s %-8s %s\n", "", "[1]", "[2]", "[3]", "[4]", "[5]", "address (page or frame,"
           " pressed)");
    for (NSArray *each in cases) {
        NSURL *address = [NSURL URLWithString:each[1]];
        BOOL page = [each[2] boolValue], pressed = [each[3] boolValue];
        printf("%-34s", [each[0] UTF8String]);
        for (BrowserSetup *setup in setups)
            printf(" %-8s", words[@(BrowserWhereTo(setup, address, page, pressed))].UTF8String);
        printf(" %s (%s%s)\n", [each[1] UTF8String], page ? "page" : "frame", pressed ? ", pressed" : "");
    }
    printf("Whether a page can be shown from each folder (no: the disk's top, your home folder or one holding it, or\n"
           "no folder):\n");
    NSString *home = Home();
    for (NSString *path in @[@"/", home, home.stringByDeletingLastPathComponent, top, @"/no/such/folder",
                             [top stringByAppendingPathComponent:@"page.html"]]) {
        BrowserSetup *setup = [BrowserSetup folder:[NSURL fileURLWithPath:path]];
        printf("  %s: %s\n", path.UTF8String, setup ? "yes" : "no");
    }
    printf("The store each name's sign-ins are kept in:\n");
    for (NSString *name in @[@"Mailbox", @"Daybook", @"mailbox", @""])
        printf("  \"%s\": %s\n", name.UTF8String, BrowserStoreFor(name).UUIDString.UTF8String ?: "nothing kept");
    BrowserSetup *plain = [BrowserSetup web];
    plain.asSafari = NO;
    printf("Introduced to sites as:\n  Safari: %s\n  Safari, not found: %s\n  WebKit's own: %s\n",
           BrowserIntroduction(web, @"26.2").UTF8String, BrowserIntroduction(web, nil).UTF8String,
           BrowserIntroduction(plain, @"26.2").UTF8String ?: "(its own words)");
    return 0;
}

// `Whozmove --print-edges`: what the panel's edge does with sample panels and screens, then quit: the side the icons
// at its edge are on (EdgeSideFor), where the panel folds round Whozmove beside it (SideCatFoldAt), whether a
// two-finger swipe is the panel's and whether it flicks the panel (SwipeWay, SwipeFlicks), where a flicked panel goes
// and how much of it shows on its way (ParkedOrigin, ParkedShows), and which way what comes out of the folded cat goes,
// the room the window takes in for it, and where that takes a click (CatWayFor, CatRoomFrame, CatRoomTakes).
// tests/edges.sh compares it with a recorded copy.
static int PrintEdges(void) {
    NSRect screen = NSMakeRect(0, 0, 1440, 875), list = NSMakeRect(0, 0, 340, 600);
    printf("The side the icons are on, on a screen 1440 wide (its middle at 720, 40 either side before it changes):\n");
    struct { const char *what; CGFloat middle; NSString *current; } sides[] = {
        {"a panel at the left, at first", 200, nil}, {"at the right, at first", 1200, nil},
        {"its middle at 750, on the right", 750, @"right"}, {"…at 761", 761, @"right"},
        {"its middle at 690, on the left", 690, @"left"}, {"…at 679", 679, @"left"}};
    for (size_t i = 0; i < sizeof sides / sizeof *sides; i++)
        printf("  %s: %s\n", sides[i].what,
               EdgeSideFor(NSOffsetRect(list, sides[i].middle - 170, 0), screen, sides[i].current).UTF8String);
    printf("Where the folded glass's middle goes, from the list's top-left corner at (1000, 800), y running down:\n");
    struct { const char *what; NSPoint middle; CGFloat shift, lift; } folds[] = {
        {"the head 30 down at the panel's left edge, level", {1000, 770}, 0, 0},
        {"…dipped under the press, 2 up", {1000, 770}, 0, -2}, {"…turned 3.5 to the left", {1000, 770}, -3.5, 0},
        {"at the right edge, 9 out", {1349, 770}, 0, -2}};
    for (size_t i = 0; i < sizeof folds / sizeof *folds; i++) {
        NSPoint at = SideCatFoldAt(folds[i].middle, folds[i].shift, folds[i].lift, NSMakePoint(1000, 800));
        printf("  %s: (%.0f, %.0f)\n", folds[i].what, at.x, at.y);
    }
    printf("A two-finger swipe, the fingers gone so far (1 the panel's, -1 the list's, 0 too soon to say):\n");
    CGFloat swipes[][2] = {{3, 1}, {8, 1}, {-8, 3}, {8, 5}, {2, 9}, {0, -7}};
    for (size_t i = 0; i < sizeof swipes / sizeof *swipes; i++)
        printf("  %.0f across, %.0f down: %d\n", swipes[i][0], swipes[i][1], SwipeWay(swipes[i][0], swipes[i][1]));
    printf("Fingers lifting, at a speed in points a second, having gone so far across: whether they flick it:\n");
    CGFloat flicks[][2] = {{1200, 40}, {-1500, -60}, {500, 40}, {1200, -10}, {801, 5}};
    for (size_t i = 0; i < sizeof flicks / sizeof *flicks; i++)
        printf("  %.0f, gone %.0f: %s\n", flicks[i][0], flicks[i][1],
               SwipeFlicks(flicks[i][0], flicks[i][1]) ? "yes" : "no");
    NSRect room = NSMakeRect(0, 0, 1440, 875), panel = NSMakeRect(1000, 200, 340, 600);
    NSPoint right = ParkedOrigin(panel, room, YES), left = ParkedOrigin(panel, room, NO);
    printf("A panel at (1000, 200), 340 wide, flicked: to the right, to (%.0f, %.0f); to the left, to (%.0f, %.0f)\n",
           right.x, right.y, left.x, left.y);
    printf("How much shows on its way to the right, its left edge at 1000, 1100, 1270, 1355, 1440:");
    CGFloat lefts[] = {1000, 1100, 1270, 1355, 1440};
    for (size_t i = 0; i < sizeof lefts / sizeof *lefts; i++)
        printf(" %.3f", ParkedShows(NSMakeRect(lefts[i], 200, 340, 600), room));
    printf("\n");
    printf("Which way what comes out of the folded cat goes, its glass 76 across on a screen 1440 by 875:\n");
    struct { const char *what; CGFloat x, y; } ways[] = {
        {"at the top right", 1340, 780}, {"at the top left", 20, 780}, {"at the bottom right", 1340, 20},
        {"at the bottom left", 20, 20}, {"in the middle, a little low", 682, 380},
        {"at the very top, half off", 600, 840}};
    for (size_t i = 0; i < sizeof ways / sizeof *ways; i++) {
        CatWay way = CatWayFor(NSMakeRect(ways[i].x, ways[i].y, 76, 76), room);
        printf("  %s: %s and %s, %.0f across, %.0f tall\n", ways[i].what, way.right ? "right" : "left",
               way.up ? "up" : "down", way.across, way.tall);
    }
    NSRect box = NSMakeRect(1300, 700, 102, 102);
    NSArray<NSValue *> *chats = @[[NSValue valueWithRect:NSMakeRect(950, 640, 340, 160)],
                                  [NSValue valueWithRect:NSMakeRect(950, 470, 340, 160)]];
    NSRect frame = CatRoomFrame(box, chats, 18);
    printf("The cat's square at (1300, 700) with two chats to its left, 340 by 160 each, 10 apart: the window is "
           "(%.0f, %.0f) %.0f by %.0f\n", frame.origin.x, frame.origin.y, frame.size.width, frame.size.height);
    printf("…and with none: (%.0f, %.0f) %.0f by %.0f\n", CatRoomFrame(box, @[], 18).origin.x,
           CatRoomFrame(box, @[], 18).origin.y, CatRoomFrame(box, @[], 18).size.width,
           CatRoomFrame(box, @[], 18).size.height);
    printf("A press there, 6 points round each chat taking it (else it goes through to what's under the panel):\n");
    struct { const char *what; CGFloat x, y; } presses[] = {
        {"on the first chat", 1100, 700}, {"on the second", 1000, 500}, {"between them", 1100, 635},
        {"4 left of the first", 946, 700}, {"10 left of it", 940, 700}, {"under both", 1100, 450}};
    for (size_t i = 0; i < sizeof presses / sizeof *presses; i++)
        printf("  %s: %s\n", presses[i].what,
               CatRoomTakes(NSMakePoint(presses[i].x, presses[i].y), chats, 6) ? "taken" : "goes through");
    return 0;
}

// The print modes main.m runs itself, by flag, until each moves into the module it tests.
static NSDictionary<NSString *, PrintMode> *CorePrintModes(void) {
    return @{
        @"--print-rows": ^(Core *core, NSArray *a) { return PrintRows(core); },
        @"--print-waits": ^(Core *core, NSArray *a) { return PrintWaits(core); },
        @"--print-browsing": ^(Core *core, NSArray *a) { return PrintBrowsing(a); },
        @"--print-edges": ^(Core *core, NSArray *a) { return PrintEdges(); },
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
