// main: starts Whozmove, or runs one of the print modes the tests check (PrintRun): --print-rows, --print-waits,
// --print-browsing, --print-edges, --print-edit-keys, --print-talking, --print-on-top, --print-other-apps and
// --print-routes here, and the modules' own.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "AppDelegate.h"
#import "Processes.h"
#import "Allowed.h"
#import "Row.h"
#import "Files.h"
#import "AppleEvents.h"
#import "AppleScript.h"
#import "Accessibility.h"
#import "Work.h"
#import "Core.h"
#import "Modules.h"
#import "Printing.h"
#import "Browser.h"
#import "EditKeys.h"
#import "Focus.h"
#import "PanelWindow.h"
#import "Talking.h"
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

// `Whozmove --print-edges`: what the panel's edge does with sample panels and screens, then quit: the side the icons at
// its edge are on (EdgeSideFor), where the panel folds round Whozmove beside it (SideCatFoldAt), whether a two-finger
// swipe is the panel's and whether it flicks the panel (SwipeWay, SwipeFlicks), where a flicked panel goes and how much
// of it shows on its way (ParkedOrigin, ParkedShows), how far a swipe on Whozmove at the screen's edge pulls the panel
// back out, whether it then comes back, and how far it pushes Whozmove in (SwipePulled, PullBrings, SideCatPushed),
// which way what comes out of the folded cat goes, the room the window takes in for it, and where that takes a click
// (CatWayFor, CatRoomFrame, CatRoomTakes), and the room the window asks for to turn over, where macOS keeps it at the
// top of the screen and how far that moves it (TurnRoom, PageFrameIn), and how tall the header and the list may get on
// a screen and the open panel where it is, with room kept for what hangs below it and for the lines under the header
// (ListLimitFor, RoomFor), and how tall it opens out of the folded panel (OpenedHeight). tests/edges.sh compares it
// with a recorded copy.
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
    printf("Pulled back out, 300 from where it was, the fingers gone 0, 100, 300, 340, 600, 2000 toward the middle: "
           "out");
    CGFloat pulls[] = {0, 100, 300, 340, 600, 2000};
    for (size_t i = 0; i < sizeof pulls / sizeof *pulls; i++) printf(" %.1f", SwipePulled(pulls[i], 300));
    printf("\n");
    printf("Fingers lifting, the panel 340 wide, so far out, at a speed toward the middle: whether it comes back:\n");
    CGFloat lets[][2] = {{113, 200}, {114, 200}, {200, -799}, {200, -801}, {20, 801}, {20, 799}, {0, 1500}};
    for (size_t i = 0; i < sizeof lets / sizeof *lets; i++)
        printf("  %.0f out, at %.0f: %s\n", lets[i][0], lets[i][1],
               PullBrings(lets[i][0], 340, lets[i][1]) ? "yes" : "no");
    printf("Whozmove pushed into the edge, the fingers gone 0, 10, 30, 60, 150, 1000 toward it: in");
    CGFloat pushes[] = {0, 10, 30, 60, 150, 1000};
    for (size_t i = 0; i < sizeof pushes / sizeof *pushes; i++) printf(" %.1f", SideCatPushed(pushes[i]));
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
    // macOS keeps the window it turns in under the menu bar, so near the top of the screen's room it's lower than the
    // room asked for: the list stays where the panel is only when the page is placed by where the window is kept, and
    // placed by the room asked for, it would be as much lower.
    printf("Turning over, the panel 340 by 600 under the top of a screen whose room is 1440 by 875: the room the "
           "window asks for, where macOS keeps it, and the list's top-left on the screen as the turn starts, the page "
           "placed by where the window is kept, and by the room asked for:\n");
    struct { const char *what; CGFloat top; } turns[] = {
        {"16 under the top", 859}, {"at the very top", 875}, {"200 under the top", 675}};
    for (size_t i = 0; i < sizeof turns / sizeof *turns; i++) {
        NSRect panel = NSMakeRect(1084, turns[i].top - 600, 340, 600), room = TurnRoom(panel);
        NSRect window = NSOffsetRect(room, 0, MIN(0, NSMaxY(screen) - NSMaxY(room)));
        NSRect clip = NSOffsetRect(panel, -NSMinX(window), -NSMinY(window));
        // The list's top-left on the screen, in the window where it's kept, with the page placed by `by`.
        NSPoint (^listBy)(NSRect) = ^NSPoint(NSRect by) {
            NSRect page = PageFrameIn(NSMakePoint(NSMinX(panel), NSMaxY(panel)), NSHeight(panel), by, clip);
            return NSMakePoint(NSMinX(window) + NSMinX(clip) + NSMinX(page) + (NSWidth(page) - NSWidth(panel)) / 2,
                               NSMinY(window) + NSMinY(clip) + NSMinY(page) + NSHeight(panel));
        };
        NSPoint kept = listBy(window), asked = listBy(room);
        printf("  %s, the list at (%.0f, %.0f): (%.0f, %.0f) %.0f by %.0f, kept at (%.0f, %.0f); (%.0f, %.0f), "
               "(%.0f, %.0f)\n", turns[i].what, NSMinX(panel), NSMaxY(panel), NSMinX(room), NSMinY(room),
               NSWidth(room), NSHeight(room), NSMinX(window), NSMinY(window), kept.x, kept.y, asked.x, asked.y);
    }
    printf("The most the header and the list take, on screens whose room under the menu bar is so tall:\n");
    CGFloat screens[] = {600, 775, 875, 923, 945, 1080, 1164, 1415};
    for (size_t i = 0; i < sizeof screens / sizeof *screens; i++)
        printf("  %.0f: %.0f\n", screens[i], ListLimitFor(screens[i]));
    printf("How tall the open panel can grow, on a screen whose room starts 0 up, its top edge so high, with nothing "
           "hanging below it, and with a card 200 below it:\n");
    CGFloat tops[] = {929, 600, 470, 300, 200};
    for (size_t i = 0; i < sizeof tops / sizeof *tops; i++)
        printf("  %.0f: %.0f; %.0f\n", tops[i], RoomFor(tops[i], 0, 0, 0), RoomFor(tops[i], 0, 200, 0));
    printf("…on a screen whose room starts 70 up, above a Dock along its foot, its top edge at 929: %.0f; %.0f\n",
           RoomFor(929, 70, 0, 0), RoomFor(929, 70, 200, 0));
    // Dragged so low that the card's room would cut into the lines under the header, the card gives way first.
    printf("…with a card 200 below and a notice 101 tall under the header, its top edge so high (the notice whole, with "
           "the header and a row, where the screen has that much):\n");
    CGFloat lows[] = {600, 470, 300, 200};
    for (size_t i = 0; i < sizeof lows / sizeof *lows; i++)
        printf("  %.0f: %.0f\n", lows[i], RoomFor(lows[i], 0, 200, 101));
    // Folded at 741 on a 1415pt display, the cat taken to a 945pt screen: the page, told that screen's limit, asks 741.
    CGFloat there = RoomFor(929, 0, 200, 101);
    printf("Opening out of the folded panel, kept 741 tall as it folded on a screen 1415 tall, then taken to one 945 "
           "tall, its top at 929 with a card kept and a notice 101 tall: the page asking %.0f there, it opens at %.0f; "
           "had it not asked, at %.0f; and with nothing known, at %.0f\n", ListLimitFor(945) + 101,
           OpenedHeight(741, ListLimitFor(945) + 101, there), OpenedHeight(741, 0, there), OpenedHeight(0, 0, there));
    return 0;
}

// `Whozmove --print-edit-keys`: the edit each sample key does in a web view that has the keyboard, and that it does
// none in one that hasn't (EditFor), then quit. tests/keys.sh compares it with a recorded copy: a key left unmapped
// does nothing at all. Whether a view has the keyboard is DoEditKey's to say, from its window, which this doesn't run.
static int PrintEditKeys(void) {
    const NSEventModifierFlags cmd = NSEventModifierFlagCommand, shift = NSEventModifierFlagShift;
    // Each: the key's letter with what's held, and without it (bare) when that's another.
    struct { const char *what; NSString *key, *bare; NSEventModifierFlags mods; NSEventType type; BOOL typing; }
        keys[] = {
        {"⌘V", @"v", nil, cmd, NSEventTypeKeyDown, YES}, {"⌘C", @"c", nil, cmd, NSEventTypeKeyDown, YES},
        {"⌘X", @"x", nil, cmd, NSEventTypeKeyDown, YES}, {"⌘A", @"a", nil, cmd, NSEventTypeKeyDown, YES},
        {"⌘Z", @"z", nil, cmd, NSEventTypeKeyDown, YES}, {"⇧⌘Z", @"Z", @"z", cmd | shift, NSEventTypeKeyDown, YES},
        {"⌘V with Caps Lock on", @"V", nil, cmd | NSEventModifierFlagCapsLock, NSEventTypeKeyDown, YES},
        {"⌘V with fn still held (a dictation app's key)", @"v", nil, cmd | NSEventModifierFlagFunction,
         NSEventTypeKeyDown, YES},
        {"⌘V on a Russian layout (м without ⌘)", @"v", @"м", cmd, NSEventTypeKeyDown, YES},
        {"⌘V on Dvorak – QWERTY ⌘ (. without ⌘)", @"v", @".", cmd, NSEventTypeKeyDown, YES},
        {"⌘. on Dvorak (V's key on QWERTY)", @".", @".", cmd, NSEventTypeKeyDown, YES},
        {"⌘V let go", @"v", nil, cmd, NSEventTypeKeyUp, YES},
        {"⌘V, in a view without the keyboard", @"v", nil, cmd, NSEventTypeKeyDown, NO},
        {"⌘A, in a view without the keyboard", @"a", nil, cmd, NSEventTypeKeyDown, NO},
        {"⇧⌘V", @"V", @"v", cmd | shift, NSEventTypeKeyDown, YES},
        {"⌥⌘V", @"√", @"v", cmd | NSEventModifierFlagOption, NSEventTypeKeyDown, YES},
        {"⌃V", @"\x16", @"v", NSEventModifierFlagControl, NSEventTypeKeyDown, YES},
        {"v", @"v", nil, 0, NSEventTypeKeyDown, YES}, {"⌘W", @"w", nil, cmd, NSEventTypeKeyDown, YES},
        {"⌘Return", @"\r", nil, cmd, NSEventTypeKeyDown, YES}};
    printf("The edit each key does in a web view that has the keyboard:\n");
    for (size_t i = 0; i < sizeof keys / sizeof *keys; i++) {
        NSEvent *event = [NSEvent keyEventWithType:keys[i].type location:NSZeroPoint modifierFlags:keys[i].mods
                                         timestamp:0 windowNumber:0 context:nil characters:keys[i].key
                       charactersIgnoringModifiers:keys[i].bare ?: keys[i].key isARepeat:NO keyCode:0];
        SEL edit = EditFor(event, keys[i].typing);
        printf("  %s: %s\n", keys[i].what, edit ? NSStringFromSelector(edit).UTF8String : "none");
    }
    return 0;
}

// `Whozmove --print-talking <file>…`: for each JSON file, by its name, why a recording counts as talking to an agent
// (Talking's whyCounts:then:rows:), or null when it doesn't, from {recording, then, rows}: the recording process, what
// was in front as it began, and the sessions listed, each {sessionId, pid}. tests/rows.sh compares it with a recorded
// copy.
static int PrintTalking(Core *core, NSArray<NSString *> *files) {
    NSMutableDictionary *found = [NSMutableDictionary dictionary];
    for (NSString *file in files) {
        NSData *data = [NSData dataWithContentsOfFile:file] ?: NSData.data;
        NSDictionary *sample = AsRecord([NSJSONSerialization JSONObjectWithData:data options:0 error:nil]);
        NSMutableArray<Row *> *rows = [NSMutableArray array];
        for (id fields in AsList(sample[@"rows"]))
            if (AsRecord(fields)) [rows addObject:[[Row alloc] initWithFields:fields]];
        found[file.lastPathComponent.stringByDeletingPathExtension] =
            [core.talking whyCounts:AsRecord(sample[@"recording"]) ?: @{} then:AsRecord(sample[@"then"]) ?: @{}
                               rows:rows] ?: NSNull.null;
    }
    return PrintJSON(found);
}

// A window as CGWindowListCopyWindowInfo lists it, of process `pid`, at `layer`, with its alpha and its place.
static NSDictionary *SampleWindow(pid_t pid, int layer, double alpha, CGRect bounds) {
    return @{(__bridge NSString *)kCGWindowOwnerPID: @(pid), (__bridge NSString *)kCGWindowLayer: @(layer),
             (__bridge NSString *)kCGWindowAlpha: @(alpha),
             (__bridge NSString *)kCGWindowBounds: CFBridgingRelease(CGRectCreateDictionaryRepresentation(bounds))};
}

// `Whozmove --print-on-top`: for sample windows on the screen, whether a terminal's window is on top
// (FrontWindowOnTop), then quit. A press on the row of the session its tab shows leaves it be only then; otherwise
// the terminal is told to show the tab, which brings its window up. tests/rows.sh compares it with a recorded copy.
static int PrintOnTop(void) {
    const pid_t terminal = 100, other = 200, own = 300;
    const CGRect front = CGRectMake(100, 100, 800, 600), beside = CGRectMake(1000, 100, 400, 400);
    struct { const char *what; NSArray *windows; } cases[] = {
        {"alone", @[SampleWindow(terminal, 0, 1, front)]},
        {"under another app's window", @[SampleWindow(other, 0, 1, CGRectMake(200, 150, 400, 400)),
                                         SampleWindow(terminal, 0, 1, front)]},
        {"with another app's window above it, beside it", @[SampleWindow(other, 0, 1, beside),
                                                           SampleWindow(terminal, 0, 1, front)]},
        {"over another app's window", @[SampleWindow(terminal, 0, 1, front), SampleWindow(other, 0, 1, beside)]},
        {"under Whozmove's own windows", @[SampleWindow(own, 3, 1, CGRectMake(150, 150, 300, 600)),
                                           SampleWindow(own, 0, 1, CGRectMake(150, 150, 1, 1)),
                                           SampleWindow(terminal, 0, 1, front)]},
        {"under the menu bar and another app's window that floats over every app",
         @[SampleWindow(other, 24, 1, CGRectMake(0, 0, 1440, 25)),
           SampleWindow(other, 3, 1, CGRectMake(200, 150, 400, 400)), SampleWindow(terminal, 0, 1, front)]},
        {"under a window that can't be seen", @[SampleWindow(other, 0, 0, CGRectMake(0, 0, 1440, 900)),
                                                SampleWindow(terminal, 0, 1, front)]},
        {"with its own window that floats over every app on top, over another app's window",
         @[SampleWindow(terminal, 3, 1, CGRectMake(0, 25, 1440, 875)), SampleWindow(other, 0, 1, beside),
           SampleWindow(terminal, 0, 1, front)]},
        {"with only its window that floats over every app on the screen",
         @[SampleWindow(terminal, 3, 1, CGRectMake(0, 25, 1440, 875)), SampleWindow(other, 0, 1, beside)]},
        {"with no window on the screen", @[SampleWindow(other, 0, 1, beside)]},
        {"in a list macOS couldn't give", @[]}};
    for (size_t i = 0; i < sizeof cases / sizeof *cases; i++)
        printf("%s: %s\n", cases[i].what, FrontWindowOnTop(cases[i].windows, terminal, own) ? "yes" : "no");
    return 0;
}

// `Whozmove --print-other-apps`: what each way Whozmove acts on another app gives from a home that isn't your own (a
// test's), and what panel.log says: nothing is pressed, typed or sent, so a test or a print run never drives your apps.
// Each is aimed at Whozmove itself, or at no element, so nothing else would be touched even if one did act. It refuses
// your own home, where they would act. tests/rows.sh compares it with a recorded copy.
static int PrintOtherApps(void) {
    if (HomeIsYourOwn()) {
        fprintf(stderr, "--print-other-apps acts on other apps from your own home: give it a throwaway one\n");
        return 2;
    }
    // The log starts empty, in a folder of its own: made with a plain write, which any sandbox a test runs in allows.
    [NSFileManager.defaultManager createDirectoryAtPath:AppDir(nil) withIntermediateDirectories:YES attributes:nil
                                                  error:nil];
    FILE *log = fopen(AppDir(@"panel.log").fileSystemRepresentation, "w");
    if (log) fclose(log);
    pid_t own = getpid();
    OSStatus status = noErr;
    NSString *script = RunAppleScript(@"return 1");
    NSAppleEventDescriptor *sent = SendAppleEvent(own, kAECoreSuite, kAEGetData, nil, nil, 2, &status);
    printf("RunAppleScript: %s\n", script ? script.UTF8String : "nothing");
    printf("SendAppleEvent: %s, status %d\n", sent ? "an answer" : "nothing", (int)status);
    printf("AskQuietly: %s\n", AskQuietly(own, AppleEventProperty(pName, nil), 2) ? "an answer" : "nothing");
    printf("AutomationPermission: %d\n", (int)AutomationPermission(own, NO));
    // No element at all: one that acted would only be told its argument is wrong (-25201), not refused (-25211).
    printf("PressElement: %d\n", (int)PressElement(NULL, kAXRaiseAction));
    printf("SetElementAttribute: %d\n", (int)SetElementAttribute(NULL, kAXFrontmostAttribute, kCFBooleanTrue));
    // An empty event (kCGEventNull), which needs no window server to make and does nothing if posted.
    CGEventRef empty = CGEventCreate(NULL);
    printf("PostEventTo: %s\n", PostEventTo(own, empty) ? "posted" : "nothing");
    CFRelease(empty);
    NSString *logged = [NSString stringWithContentsOfFile:AppDir(@"panel.log") encoding:NSUTF8StringEncoding error:nil];
    NSString *said = @"Whozmove pressed, typed, opened and sent nothing in other apps: this run's home isn't your own";
    NSUInteger times = 0;
    for (NSString *line in [logged componentsSeparatedByString:@"\n"])
        if ([line hasSuffix:said]) times++;
    printf("panel.log says \"%s\": %lu time%s\n", said.UTF8String, (unsigned long)times, times == 1 ? "" : "s");
    return 0;
}

// `Whozmove --print-file-reads`: a file read every second (ReadJSONKept, ReadTextKept), written, rewritten and read in
// turn, so it's seen to be read again only once it has changed (its size, or only its date), never kept while it can't
// be read (caught half-written) or once it's gone; and a file's date from stat (FileModifiedAt). In a folder of the
// home in $HOME, so it refuses to run in your own. tests/rows.sh compares it with a recorded copy.
static int PrintFileReads(void) {
    if (HomeIsYourOwn()) {
        fprintf(stderr, "--print-file-reads writes files in $HOME: run it with a throwaway HOME, as tests/rows.sh "
                        "does\n");
        return 2;
    }
    NSString *folder = [Home() stringByAppendingPathComponent:@"file-reads"];
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil
                                                  error:nil];
    NSString *path = [folder stringByAppendingPathComponent:@"record.json"];
    __block double at = 1700000000;
    void (^write)(NSString *) = ^(NSString *text) {
        [text writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:nil];
        struct timeval times[2] = {{(time_t)at, 0}, {(time_t)at, 0}};
        utimes(path.fileSystemRepresentation, times);
        at += 1;
    };
    void (^say)(NSString *, id) = ^(NSString *what, id read) {
        id n = AsRecord(read)[@"n"];
        printf("%s: %s\n", what.UTF8String, n ? [n description].UTF8String : "nothing");
    };
    write(@"{\"n\": 1}");
    id first = ReadJSONKept(path);
    say(@"written", first);
    printf("read again, unchanged: %s\n", ReadJSONKept(path) == first ? "the same, not read again" : "read again");
    write(@"{\"n\": 22}");
    say(@"rewritten, a new size", ReadJSONKept(path));
    write(@"{\"n\": 33}");
    say(@"rewritten, the same size, a new date", ReadJSONKept(path));
    write(@"{\"n\": 4");
    say(@"caught half-written", ReadJSONKept(path));
    write(@"{\"n\": 44}");
    say(@"written whole", ReadJSONKept(path));
    [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    say(@"gone", ReadJSONKept(path));
    write(@"ref: refs/heads/main\n");
    printf("text: %s", ReadTextKept(path).UTF8String ?: "nothing\n");
    write(@"ref: refs/heads/topic\n");
    printf("text rewritten: %s", ReadTextKept(path).UTF8String ?: "nothing\n");
    printf("its date: %.0f\n", FileModifiedAt(path));
    printf("a missing file's date: %.0f\n", FileModifiedAt([folder stringByAppendingPathComponent:@"none"]));
    [NSFileManager.defaultManager removeItemAtPath:folder error:nil];
    return 0;
}

// `Whozmove --print-ticked <step>…` runs each step in turn, as one copy of the panel would, against the switches in
// ticked.json in $HOME's Whozmove folder, and says what each did, with switches of its own (Allowed's
// printingSwitches): three kept while Whozmove runs (runA, runB, runC) and two kept for a folder (keptOne, keptTwo). A
// step is words: `row <session> <pid> [member] [twice] [in=<folder>]` (a sample session: its team's lead unless it's a
// member, open in a second place if it's `twice`, working in that folder; a row named again is replaced), `block` and
// `unblock <session>` (it may not hold a switch kept for its folder, or may again), `held <session>` (which session
// each switch kept for its folder was ticked in), `askfrom <session> <key> <pid>` (why it's off for an ask from that
// process), `start` (this copy begins, reading ticked.json into what waits), `on` and `off <session> <key>` (your press
// on a switch), `count <session> <key>` (it answered for you), `list` (the rows are listed), `back <session>` (what
// Turn Back On would bring back, and why not, before the press), `bring <session>` (your press on Turn Back On), `ask
// <session> <key>` (why the switch is off), `show`, `file`, `lock` and `unlock` (Whozmove's folder can't be written, or
// can again), `quit` and `restart` (the copy ends as a Quit or a restart ends it). Without `start` nothing is written,
// as in any print run. It refuses your own home. tests/ticked.sh runs it.
static int PrintTicked(Core *core, NSArray<NSString *> *arguments) {
    if (HomeIsYourOwn()) {
        fprintf(stderr, "--print-ticked acts on Whozmove's folder in $HOME: give it a throwaway home folder\n");
        return 2;
    }
    NSFileManager *files = NSFileManager.defaultManager;
    [files createDirectoryAtPath:AppDir(nil) withIntermediateDirectories:YES
                      attributes:@{NSFilePosixPermissions: @0700} error:nil];
    NSString *ticked = AppDir(@"ticked.json");
    NSMutableArray<Row *> *rows = [NSMutableArray array];
    // The switches it tries, its own, so these rules are tried apart from any module's checks: three kept while
    // Whozmove runs and two kept for a folder, which a session `block`ed can't hold, each shown only on a lead's row.
    NSMutableSet<NSString *> *blocked = [NSMutableSet set];
    NSString *(^whyNot)(Row *) = ^NSString *(Row *row) {
        if (row.pid <= 0) return @"The session isn't running";
        if (row.alsoOpen.count) return @"Open in more than one place";
        if ([blocked containsObject:row.sessionId ?: @""]) return @"Another session runs in its folder";
        return nil;
    };
    NSMutableArray<SessionSwitch *> *standIns = [NSMutableArray array];
    for (NSArray<NSString *> *one in @[@[@"runA", @"Switch A"], @[@"runB", @"Switch B"], @[@"runC", @"Switch C"],
                                       @[@"keptOne", @"Kept One"], @[@"keptTwo", @"Kept Two"]]) {
        BOOL kept = [one[0] hasPrefix:@"kept"];
        SessionSwitch *each = [SessionSwitch switchWithKey:one[0] title:one[1] line:@"A stand-in"
                                                     lasts:kept ? SwitchLastsWorkspace : SwitchLastsWhileRunning];
        each.shown = ^BOOL(Row *row) { return [row.team[@"role"] isEqual:@"lead"]; };
        each.hiddenSays = @"this session isn't its team's lead";
        each.whyNot = whyNot;
        if (kept) each.workspace = ^NSString *(Row *row) { return row.cwd.length ? row.cwd : nil; };
        [standIns addObject:each];
    }
    core.allowed.printingSwitches = standIns;
    Row *(^rowOf)(NSString *) = ^Row *(NSString *sessionId) {
        for (Row *row in rows)
            if ([row.sessionId isEqual:sessionId]) return row;
        return nil;
    };
    for (NSString *step in arguments) {
        NSArray<NSString *> *w = [step componentsSeparatedByString:@" "];
        NSString *what = w[0], *sessionId = w.count > 1 ? w[1] : nil, *key = w.count > 2 ? w[2] : nil;
        Row *row = rowOf(sessionId);
        printf("> %s\n", step.UTF8String);
        if ([what isEqual:@"row"] && w.count >= 3) {
            Row *made = [[Row alloc] initWithFields:@{@"sessionId": sessionId, @"pid": @(w[2].intValue)}];
            made.team = @{@"role": [w containsObject:@"member"] ? @"member" : @"lead"};
            if ([w containsObject:@"twice"]) made.alsoOpen = @[@{@"entrypoint": @"cli"}];
            for (NSString *word in w)
                if ([word hasPrefix:@"in="]) made.cwd = [word substringFromIndex:3];
            Row *was = rowOf(sessionId);
            if (was) [rows removeObject:was];
            [rows addObject:made];
        } else if (([what isEqual:@"block"] || [what isEqual:@"unblock"]) && sessionId) {
            if ([what isEqual:@"block"]) [blocked addObject:sessionId];
            else [blocked removeObject:sessionId];
        } else if ([what isEqual:@"held"] && row) {
            for (SessionSwitch *each in core.allowed.switches) {
                NSDictionary *ticked = [core.allowed tickedIn:each.key for:row];
                if (ticked) printf("%s: ticked in %s\n", each.key.UTF8String, [ticked[@"session"] UTF8String]);
            }
        } else if ([what isEqual:@"start"]) {
            printf("waiting: %ld\n", (long)[core.allowed keepTickedAt:ticked]);
        } else if (([what isEqual:@"on"] || [what isEqual:@"off"]) && row && key) {
            printf("%s\n", [core.allowed set:key for:row on:[what isEqual:@"on"]] ? what.UTF8String : "not changed");
        } else if ([what isEqual:@"count"] && key) {
            [core.allowed countUp:key session:sessionId];
        } else if ([what isEqual:@"list"]) {
            [core.allowed rowsListed:rows];
        } else if ([what isEqual:@"bring"] && row) {
            NSString *why = nil;
            NSArray<SessionSwitch *> *brought = [core.allowed bringBack:row why:&why];
            if (!brought.count) printf("refused: %s\n", why.UTF8String);
            for (SessionSwitch *each in brought)
                printf("on: %s, %ld\n", each.title.UTF8String, (long)[core.allowed count:each.key session:sessionId]);
        } else if ([what isEqual:@"back"] && row) {
            // What Turn Back On would say before the press: what waits, what one press brings back, and why not.
            NSArray<SessionSwitch *> *waiting = [core.allowed waitingFor:row];
            NSString *why = nil;
            NSArray<SessionSwitch *> *able = [core.allowed bringableFor:row among:waiting why:&why];
            NSMutableArray<NSString *> *keys = [NSMutableArray array];
            for (SessionSwitch *each in able) [keys addObject:each.key];
            printf("waiting %lu, brings back [%s], why: %s\n", (unsigned long)waiting.count,
                   [keys componentsJoinedByString:@" "].UTF8String, (why ?: @"none").UTF8String);
        } else if ([what isEqual:@"askfrom"] && row && key && w.count > 3) {
            printf("%s\n", ([core.allowed whyOff:key for:row from:w[3].intValue] ?: @"on").UTF8String);
        } else if ([what isEqual:@"ask"] && row && key) {
            printf("%s\n", ([core.allowed whyOff:key for:row] ?: @"on").UTF8String);
        } else if ([what isEqual:@"show"]) {
            NSDictionary *written = AsRecord(ReadJSON(ticked)) ?: @{};
            for (Row *each in rows) {
                NSMutableArray *on = [NSMutableArray array], *waiting = [NSMutableArray array];
                for (SessionSwitch *one in core.allowed.switches)
                    if ([core.allowed isOn:one.key for:each])
                        [on addObject:[NSString stringWithFormat:@"%@ %ld", one.key,
                                       (long)[core.allowed count:one.key session:each.sessionId]]];
                // A waiting switch's count is the file's: it is only in the file until it is brought back.
                NSDictionary *records = AsRecord(written[each.sessionId]);
                NSArray<SessionSwitch *> *offered = [core.allowed waitingFor:each];
                for (SessionSwitch *one in offered)
                    [waiting addObject:[NSString stringWithFormat:@"%@ %ld", one.key,
                                        (long)AsNumber(AsRecord(records[one.key])[@"count"]).integerValue]];
                NSString *item = offered.count ? [@", item: Turn Back On " stringByAppendingString:
                                                  [Allowed namesOf:offered]] : @"";
                // Kept for its folder but off for it now: the menu's dash, which stops keeping it.
                NSMutableArray *keptOff = [NSMutableArray array];
                for (SessionSwitch *one in core.allowed.switches)
                    if ([core.allowed keptFolder:one.key for:each] && ![core.allowed isOn:one.key for:each])
                        [keptOff addObject:one.key];
                NSString *kept = keptOff.count ? [NSString stringWithFormat:@", kept but off [%@]",
                                                  [keptOff componentsJoinedByString:@", "]] : @"";
                printf("%s: on [%s], waiting [%s]%s%s\n", each.sessionId.UTF8String,
                       [on componentsJoinedByString:@", "].UTF8String,
                       [waiting componentsJoinedByString:@", "].UTF8String, item.UTF8String, kept.UTF8String);
            }
        } else if ([what isEqual:@"file"]) {
            printf("ticked.json: %s\n", [files fileExistsAtPath:ticked] ? "there" : "gone");
            NSDictionary *attributes = [files attributesOfItemAtPath:ticked error:nil];
            if (attributes) printf("mode: %o\n", (unsigned)(attributes.filePosixPermissions & 0777));
        } else if ([what isEqual:@"lock"] || [what isEqual:@"unlock"]) {
            [files setAttributes:@{NSFilePosixPermissions: [what isEqual:@"lock"] ? @0500 : @0700}
                    ofItemAtPath:AppDir(nil) error:nil];
        } else if ([what isEqual:@"quit"] || [what isEqual:@"restart"]) {
            [core.allowed endRun:[what isEqual:@"restart"]];
        } else {
            fprintf(stderr, "no such step: %s\n", step.UTF8String);
            return 2;
        }
    }
    return 0;
}

// The print modes main.m runs itself, by flag, until each moves into the module it tests.
static NSDictionary<NSString *, PrintMode> *CorePrintModes(void) {
    return @{
        @"--print-rows": ^(Core *core, NSArray *a) { return PrintRows(core); },
        @"--print-waits": ^(Core *core, NSArray *a) { return PrintWaits(core); },
        @"--print-browsing": ^(Core *core, NSArray *a) { return PrintBrowsing(a); },
        @"--print-edges": ^(Core *core, NSArray *a) { return PrintEdges(); },
        @"--print-edit-keys": ^(Core *core, NSArray *a) { return PrintEditKeys(); },
        @"--print-talking": ^(Core *core, NSArray *a) { return PrintTalking(core, a); },
        @"--print-on-top": ^(Core *core, NSArray *a) { return PrintOnTop(); },
        @"--print-file-reads": ^(Core *core, NSArray *a) { return PrintFileReads(); },
        @"--print-other-apps": ^(Core *core, NSArray *a) { return PrintOtherApps(); },
        @"--print-ticked": ^(Core *core, NSArray *a) { return PrintTicked(core, a); },
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

// A helper run: one of the app's own one-file jobs, from the module that has it, given the arguments after the flag.
// The app runs it as a process of its own; it's never for the tests (print runs are). Every module is made, as for a
// print run, but none starts, and anything two claim fails it.
static int HelperRunFor(NSString *flag, NSArray<NSString *> *arguments) {
    Core *core = [Core forPrinting];
    NSArray<NSString *> *clashes = Clashes(core);
    for (NSString *clash in clashes) fprintf(stderr, "Claimed twice: %s\n", clash.UTF8String);
    if (clashes.count) return 1;
    HelperRun run = [core.modules helperRun:flag];
    if (run) return run(core, arguments);
    fprintf(stderr, "There's no helper run %s\n", flag.UTF8String);
    return 2;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
        // A helper run's flag is the first argument that starts with --helper-, looked for first; a print run's, the
        // first that starts with --print-. The ones after it are its own.
        NSUInteger helper = [arguments indexOfObjectPassingTest:^BOOL(NSString *argument, NSUInteger i, BOOL *stop) {
            return i > 0 && [argument hasPrefix:@"--helper-"];
        }];
        if (helper != NSNotFound)
            return HelperRunFor(arguments[helper],
                                [arguments subarrayWithRange:NSMakeRange(helper + 1, arguments.count - helper - 1)]);
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
