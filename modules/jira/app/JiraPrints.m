// JiraPrints: what Jira's tests compare.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "JiraPrints.h"
#import "Files.h"
#import "JiraCard.h"
#import "JiraFacts.h"
#import "JiraTickets.h"
#import "Keychain.h"
#import "OAuth.h"
#import "Tracker.h"

static void Say(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void Say(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    printf("%s\n", [[NSString alloc] initWithFormat:format arguments:args].UTF8String);
    va_end(args);
}

static NSString *JSON(id value) {
    if (!value) return @"null";
    NSData *data = [NSJSONSerialization dataWithJSONObject:value
                                                   options:NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes
                                                           | NSJSONWritingFragmentsAllowed
                                                     error:nil];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : [value description];
}

// The plain functions, over made-up samples kept with the tests (`samples`, a JSON file: keys and links, links to
// make, searches, kinds, well-known pages, sign-in services' metadata, and the sites the card shows).
static int Facts(NSString *samples) {
    NSDictionary *given = AsRecord(ReadJSON(samples));
    if (!given) {
        fprintf(stderr, "--print-jira facts: couldn't read %s\n", samples.UTF8String);
        return 2;
    }
    Say(@"== keys and links");
    for (NSString *text in AsList(given[@"keys"])) {
        NSString *site = nil;
        NSString *key = JiraKeyIn(text, &site);
        Say(@"%@ → %@%@", JSON(text), key ?: @"(none)", site ? [@" on " stringByAppendingString:site] : @"");
    }
    Say(@"== links made");
    for (NSArray *pair in AsList(given[@"links"]))
        Say(@"%@ on %@ → %@", JSON(pair[0]), pair[1], JiraLinkFor(pair[0], pair[1]) ?: @"(none)");
    Say(@"== searches");
    for (NSString *words in AsList(given[@"searches"])) Say(@"%@ → %@", JSON(words), JiraSearchFor(words));
    Say(@"== kinds");
    for (NSArray *pair in AsList(given[@"kinds"]))
        Say(@"%@ %@ → %@", pair[0], JSON(pair[1]), TicketKindWord(JiraKindOf(pair[0], pair[1])));
    Say(@"== sign-in");
    Say(@"scopes: %@", [JiraScopes() componentsJoinedByString:@" "]);
    for (NSArray *pair in AsList(given[@"wellKnown"]))
        Say(@"%@ of %@: %@", pair[1], pair[0], OAuthWellKnown([NSURL URLWithString:pair[0]], pair[1]));
    // RFC 7636's own example.
    Say(@"challenge: %@", OAuthChallenge(@"dBjftJeZ4CVP-mJ92K9mxEcO4ZIsqahuaa6U4PUFTTk"));
    Say(@"random: %lu characters, %@", (unsigned long)OAuthRandom(48).length,
        [OAuthRandom(48) isEqualToString:OAuthRandom(48)] ? @"the same twice" : @"new each time");
    for (NSDictionary *metadata in AsList(given[@"servers"])) {
        NSString *why = nil;
        Say(@"service: %@", [OAuthServer serverFromMetadata:metadata why:&why] ? @"usable" : why);
    }
    NSString *site = AsText(given[@"site"]);
    NSArray *sites = AsList(given[@"sites"]);
    Say(@"== the card on the panel's back");
    NSArray *states = @[@[@(TrackerSignedOut), @"signed out"], @[@(TrackerSigningIn), @"signing in"],
                        @[@(TrackerSignedIn), @"signed in"], @[@(TrackerSignInBlocked), @"blocked"],
                        @[@(TrackerSignInExpired), @"expired"], @[@(TrackerSignInAsksMac), @"macOS asks first"]];
    for (NSArray *state in states) {
        TrackerSignIn s = [state[0] integerValue];
        Say(@"%@: %@", state[1], JSON(JiraCard(s, site ? @[site] : @[], nil, NO, NO)));
    }
    Say(@"signed in, two sites: %@", JSON(JiraCard(TrackerSignedIn, sites, nil, NO, NO)));
    Say(@"signed in, reading only: %@", JSON(JiraCard(TrackerSignedIn, site ? @[site] : @[], nil, NO, YES)));
    Say(@"blocked, copied: %@", JSON(JiraCard(TrackerSignInBlocked, @[], nil, YES, NO)));
    return 0;
}

// Each recorded answer in `folder` (one JSON file a tool's answer, named for what it is), read as Jira's module reads it.
static int Answers(NSString *folder, NSString *site) {
    NSArray *names = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil]
                      sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *name in names) {
        if (![name hasSuffix:@".json"]) continue;
        id answer = ReadJSON([folder stringByAppendingPathComponent:name]);
        Say(@"== %@", name);
        if ([name hasPrefix:@"issue"]) Say(@"%@", JSON([JiraTicketFrom(JiraIssueIn(answer), site) json]));
        else if ([name hasPrefix:@"search"]) for (NSDictionary *issue in JiraIssuesIn(answer))
            Say(@"%@", JSON([JiraTicketFrom(issue, site) json]));
        else if ([name hasPrefix:@"transitions"]) {
            Ticket *holder = [Ticket new];
            holder.steps = JiraStepsIn(answer);
            Say(@"%@", JSON([holder json][@"steps"]));
            // Fields as every tracker gives them, in Jira's shapes for a step's screen, or why not.
            NSArray *samples = @[@[@"51", @{@"resolution": @"Won't Do", @"fixVersions": @[@"2.1", @"2.2"],
                                            @"customfield_10200": @3}],
                                 @[@"51", @{@"fixVersions": @"2.2"}], @[@"51", @{@"resolution": @"Fixed"}],
                                 @[@"51", @{@"resolution": @[@"Done"]}], @[@"51", @{@"customfield_10200": @"three"}],
                                 @[@"51", @{@"customfield_10100": @"Sam Rivera"}], @[@"31", @{@"resolution": @"Done"}]];
            for (NSArray *sample in samples) {
                NSString *why = nil;
                NSDictionary *shaped = JiraFieldsFor(answer, sample[0], sample[1], &why);
                Say(@"step %@ with %@: %@", sample[0], JSON(sample[1]), shaped ? JSON(shaped) : why);
            }
        } else if ([name hasPrefix:@"boards"]) for (TicketGroup *board in JiraBoardsIn(answer))
            Say(@"%@ %@ %@", board.groupId, board.kind, JSON(board.name));
        else if ([name hasPrefix:@"sites"]) Say(@"%@", JSON(JiraSitesIn(answer)));
        else if ([name hasPrefix:@"error"])
            Say(@"error %ld%@", (long)JiraErrorIn(answer), JiraErrorNamesScope(answer) ? @", naming a scope" : @"");
    }
    return 0;
}

int PrintJiraTalk(NSString *site, NSArray<NSString *> *steps);

void JiraStandInOpenAccess(NSString *service) {
    NSMutableDictionary *all = [AsRecord(ReadJSON(KeychainStandInPath())) mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableArray *others = [AsList(all[@"others"]) mutableCopy] ?: [NSMutableArray array];
    if (![others containsObject:service]) [others addObject:service];
    all[@"others"] = others;
    [[NSJSONSerialization dataWithJSONObject:all options:0 error:nil] writeToFile:KeychainStandInPath() atomically:YES];
}

void JiraStandInAsks(NSString *service, BOOL newBuild) {
    NSMutableDictionary *all = [AsRecord(ReadJSON(KeychainStandInPath())) mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableArray *asks = [AsList(all[@"asks"]) mutableCopy] ?: [NSMutableArray array];
    if (![asks containsObject:service]) [asks addObject:service];
    all[@"asks"] = asks;
    if (newBuild) {
        NSMutableDictionary *builds = [AsRecord(all[@"builds"]) mutableCopy] ?: [NSMutableDictionary dictionary];
        builds[service] = @"an older build";
        all[@"builds"] = builds;
    }
    [[NSJSONSerialization dataWithJSONObject:all options:0 error:nil] writeToFile:KeychainStandInPath() atomically:YES];
}

// What a read of the check entry found, in words.
static NSString *FoundWords(NSData *read, KeychainFound found, NSData *value, NSData *changed) {
    if (read) return [read isEqualToData:value] ? @"read it back" : [read isEqualToData:changed] ? @"read it back, changed"
                                                                                                 : @"read something else";
    switch (found) {
        case KeychainFoundAsks: return @"macOS would ask first, so not read";
        case KeychainFoundOthers: return @"kept, but other apps can read it, so not used";
        case KeychainFoundChanged: return @"kept by this build, but changed since, so not used";
        case KeychainFoundNone: return @"none kept";
        default: return @"couldn't read it";
    }
}

// The Keychain's own path, for a virtual Mac: a made-up entry under a service of its own (never the sign-in's), written
// afresh, looked for, read back quietly (never letting macOS ask) or as the app does after your press, changed quietly,
// or forgotten. Run by a new build after an old one wrote it, it shows what macOS asks of a new build. `write`,
// `update` and the stand-in's `open` (the entry now lets other apps read it), `newbuild` (an older build kept it, and
// macOS asks) and `rewritten` (macOS asks, though this build kept it) run only in a throwaway home, as writing afresh
// clears an entry for good.
static int KeychainCheck(NSString *what) {
    NSString *service = @"Whozmove: Keychain check", *account = @"check";
    NSData *value = [@"made-up check value" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *changed = [@"made-up changed value" dataUsingEncoding:NSUTF8StringEncoding];
    if (HomeIsYourOwn() && [@[@"write", @"open", @"update", @"newbuild", @"rewritten"] containsObject:what]) {
        fprintf(stderr, "--print-jira keychain %s runs only in a throwaway home\n", what.UTF8String);
        return 2;
    }
    KeychainFound found = KeychainFoundNone;
    if ([what isEqualToString:@"write"]) Say(@"%@", KeychainKeepAfresh(service, account, value) ? @"written" : @"couldn't write it");
    else if ([what isEqualToString:@"open"]) {
        JiraStandInOpenAccess(service);
        Say(@"opened to other apps");
    } else if ([what isEqualToString:@"newbuild"] || [what isEqualToString:@"rewritten"]) {
        JiraStandInAsks(service, [what isEqualToString:@"newbuild"]);
        Say(@"%@", [what isEqualToString:@"newbuild"] ? @"kept by an older build, which macOS asks about"
                                                      : @"changed by something else, which macOS asks about");
    } else if ([what isEqualToString:@"update"]) {
        Say(@"%@", KeychainUpdateQuietly(service, account, changed) ? @"updated" : @"not updated");
    } else if ([what isEqualToString:@"read"]) {
        NSData *read = KeychainRead(service, account, &found);
        Say(@"%@", read || found == KeychainFoundOthers || found == KeychainFoundChanged
                       ? FoundWords(read, found, value, changed) : @"couldn't read it");
    } else if ([what isEqualToString:@"quietly"]) {
        Say(@"%@", FoundWords(KeychainReadQuietly(service, account, &found), found, value, changed));
    } else if ([what isEqualToString:@"has"]) {
        found = KeychainLook(service, account);
        Say(@"%@", found == KeychainFoundIt ? @"one is kept" : FoundWords(nil, found, value, changed));
    } else if ([what isEqualToString:@"forget"]) {
        KeychainForget(service, account);
        Say(@"forgotten");
    } else return 2;
    Say(@"in %@", KeychainStandInPath() ? @"the stand-in file" : @"the Keychain");
    return 0;
}

int PrintJira(NSArray<NSString *> *arguments) {
    NSString *what = arguments.firstObject;
    if ([what isEqualToString:@"keychain"] && arguments.count > 1) return KeychainCheck(arguments[1]);
    if ([what isEqualToString:@"facts"] && arguments.count > 1) return Facts(arguments[1]);
    if ([what isEqualToString:@"answers"] && arguments.count > 2) return Answers(arguments[1], arguments[2]);
    if ([what isEqualToString:@"talk"]) {
        if (HomeIsYourOwn()) {
            fprintf(stderr, "--print-jira talk runs only in a throwaway home\n");
            return 2;
        }
        if (arguments.count < 2) return 2;
        return PrintJiraTalk(arguments[1], [arguments subarrayWithRange:NSMakeRange(2, arguments.count - 2)]);
    }
    fprintf(stderr, "Usage: --print-jira facts <samples> | answers <folder> <site> | talk <site> <steps…> | "
                    "keychain write|open|update|newbuild|rewritten (throwaway home only)|has|quietly|read|forget\n");
    return 2;
}
