// Updates: a newer Whozmove out through Homebrew, said and never installed.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Updates.h"
#import "HomebrewFacts.h"
#import "Files.h"
#import "Log.h"
#import "Printing.h"

static const NSTimeInterval kLookEvery = 6 * 60 * 60;

static NSString *UpdatesFile(void) {
    return AppDir(@"updates.json");
}

BOOL VersionBefore(NSString *a, NSString *b) {
    return [a compare:b options:NSNumericSearch] == NSOrderedAscending;
}

static NSString *Text(NSString *path) {
    return path ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] : nil;
}

NSDictionary *NewerVersion(NSString *prefix, NSString *own, NSString *(^fetch)(NSURL *url), NSString **said) {
    NSDictionary *receipt = AsRecord(ReadJSON(HomebrewReceipt(prefix, kWhozmoveCask)));
    NSString *tap = AsText(AsRecord(receipt[@"source"])[@"tap"]);
    if (!tap || !TapCaskFile(prefix, tap, kWhozmoveCask)) {
        *said = @"not installed by Homebrew, so no new version is looked for";
        return nil;
    }
    // Homebrew has put a newer one in already (its quit of this copy was refused, say): this copy is to restart.
    NSString *installed = AsText(AsRecord(receipt[@"source"])[@"version"]);
    if (installed.length && VersionBefore(own, installed)) {
        *said = [NSString stringWithFormat:@"%@ is installed, and this is %@: restart it to use it", installed, own];
        return @{@"version": installed, @"tap": tap, @"installed": @YES};
    }
    NSString *here = CaskVersion(Text(TapCaskFile(prefix, tap, kWhozmoveCask)));
    NSURL *url = TapCaskOnGitHub(tap, kWhozmoveCask);
    NSString *there = url && fetch ? CaskVersion(fetch(url)) : nil;
    NSString *newest = !here ? there : !there ? here : VersionBefore(here, there) ? there : here;
    if (!newest) {
        *said = [NSString stringWithFormat:@"no version found in %@'s cask, on this Mac or on GitHub", tap];
        return nil;
    }
    if (!VersionBefore(own, newest)) {
        *said = [NSString stringWithFormat:@"%@ is the newest in %@", own, tap];
        return nil;
    }
    *said = [NSString stringWithFormat:@"%@ is out in %@ (this is %@)", newest, tap, own];
    return @{@"version": newest, @"tap": tap, @"command": BrewUpgradeCommand(tap, kWhozmoveCask)};
}

@interface Updates ()
@property (copy) NSString *prefix, *own;
@property (assign) BOOL fromCheckout;
@property (strong) dispatch_queue_t queue;
@property (assign) BOOL looking;
@property (assign) NSTimeInterval lookedAt;
@property (strong) NSDictionary *newer;    // the newer version out, as the last look found it
@property (copy) NSString *away;           // the version you put away
@property (copy) NSString *said;           // what the log said last, on the queue
@property (copy) NSString *lastFromGitHub; // GitHub's copy of the cask as it last answered, on the queue
@end

@implementation Updates

- (instancetype)initWithPrefix:(NSString *)prefix version:(NSString *)own fromCheckout:(BOOL)checkout {
    if (!(self = [super init])) return nil;
    self.prefix = prefix;
    self.own = own;
    self.fromCheckout = checkout;
    self.queue = dispatch_queue_create("whozmove.updates", DISPATCH_QUEUE_SERIAL);
    self.away = AsText(AsRecord(ReadJSON(UpdatesFile()))[@"putAway"]);
    return self;
}

- (NSDictionary *)found {
    NSString *version = self.newer[@"version"];
    if (!version || [version isEqualToString:self.away]) return nil;
    if ([self.newer[@"installed"] boolValue]) return @{@"version": version, @"installed": @YES};
    return @{@"version": version, @"command": self.newer[@"command"]};
}

// A build from a checkout updates with git, so it never looks. Each outcome is said in the log once, until it changes.
- (void)look {
    if (self.fromCheckout || self.looking || !self.own.length) return;
    self.looking = YES;
    self.lookedAt = NSDate.date.timeIntervalSince1970;
    // A look GitHub doesn't answer (no network, too slow) goes by its last answer, so a version found there doesn't
    // fold away while you're offline.
    NSString *(^fetch)(NSURL *) = self.fetch;
    NSString *(^fromGitHub)(NSURL *) = fetch ? ^NSString *(NSURL *url) {
        NSString *answer = fetch(url);
        if (answer) self.lastFromGitHub = answer;
        return answer ?: self.lastFromGitHub;
    } : nil;
    dispatch_async(self.queue, ^{
        NSString *said = nil;
        NSDictionary *newer = NewerVersion(self.prefix, self.own, fromGitHub, &said);
        if (![said isEqualToString:self.said]) {
            self.said = said;
            PanelLog(@"updates: %@", said);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.looking = NO;
            NSDictionary *before = self.found;
            self.newer = newer;
            if (![self.found isEqual:before] && (self.found || before) && self.onFound) self.onFound();
        });
    });
}

- (BOOL)working {
    return self.looking;
}

- (void)tick {
    if (NSDate.date.timeIntervalSince1970 - self.lookedAt >= kLookEvery) [self look];
}

- (void)putAway:(NSString *)version {
    if (!version.length || ![version isEqualToString:self.newer[@"version"]]) return;
    self.away = version;
    NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"putAway": version} options:0 error:nil];
    [NSFileManager.defaultManager createDirectoryAtPath:AppDir(nil) withIntermediateDirectories:YES
                                             attributes:@{NSFilePosixPermissions: @0700} error:nil];
    if (![json writeToFile:UpdatesFile() atomically:YES]) LogProblem(@"updates: couldn't keep the version put away");
    PanelLog(@"updates: %@ put away until a newer one", version);
    if (self.onFound) self.onFound();
}

@end

#pragma mark Print mode

// Each case: Homebrew's receipt (its tap, or none), the cask in Homebrew's copy of the tap and GitHub's (a version, a
// garbled file, or none: no answer), and this copy's version.
static NSDictionary<NSString *, NSDictionary *> *UpdateCases(void) {
    NSString *(^cask)(NSString *) = ^NSString *(NSString *version) {
        return [NSString stringWithFormat:@"cask \"whozmove\" do\n  version \"%@\"\n  sha256 \"0\"\nend\n", version];
    };
    return @{
        @"newer": @{@"tap": @"whozmove/tap", @"here": cask(@"0.2.1"), @"there": cask(@"0.2.1"), @"own": @"0.2.0"},
        @"same": @{@"tap": @"whozmove/tap", @"here": cask(@"0.2.0"), @"there": cask(@"0.2.0"), @"own": @"0.2.0"},
        @"older": @{@"tap": @"whozmove/tap", @"here": cask(@"0.1.9"), @"own": @"0.2.0"},
        @"newer-by-a-part": @{@"tap": @"whozmove/tap", @"here": cask(@"0.2.10"), @"own": @"0.2.9"},
        @"github-ahead": @{@"tap": @"whozmove/tap", @"here": cask(@"0.2.0"), @"there": cask(@"0.2.2"),
                           @"own": @"0.2.0"},
        @"github-behind": @{@"tap": @"whozmove/tap", @"here": cask(@"0.2.3"), @"there": cask(@"0.2.1"),
                            @"own": @"0.2.0"},
        @"no-network": @{@"tap": @"whozmove/tap", @"here": cask(@"0.2.1"), @"own": @"0.2.0"},
        @"tap-not-published": @{@"tap": @"whozmove/tap", @"own": @"0.2.0"},
        @"garbled-cask": @{@"tap": @"whozmove/tap", @"here": @"cask \"whozmove\" do\n  version :latest\nend\n",
                           @"there": @"<html>Not Found</html>", @"own": @"0.2.0"},
        @"another-tap": @{@"tap": @"someone/casks", @"here": cask(@"0.3.0"), @"own": @"0.2.0"},
        @"not-homebrew": @{@"own": @"0.2.0", @"there": cask(@"0.2.1")},
        @"strange-tap": @{@"tap": @"../../etc", @"here": cask(@"9.9.9"), @"own": @"0.2.0"},
        @"installed-not-restarted": @{@"tap": @"whozmove/tap", @"installed": @"0.2.1", @"here": cask(@"0.2.1"),
                                      @"own": @"0.2.0"},
        @"test-tap": @{@"tap": @"whozmove/test", @"here": cask(@"0.2.1"), @"own": @"0.2.0"},
        // Updates itself, look by look: what GitHub's copy says before each (null: no answer), your × and the panel
        // opening again.
        @"checkout-never-looks": @{@"tap": @"whozmove/tap", @"own": @"0.2.0", @"checkout": @YES,
                                   @"steps": @[@{@"there": cask(@"0.2.1")}, @"look"]},
        @"put-away-stays-away": @{@"tap": @"whozmove/tap", @"own": @"0.2.0",
                                  @"steps": @[@{@"there": cask(@"0.2.1")}, @"look", @"putAway", @"reopen", @"look"]},
        @"newer-after-put-away": @{@"tap": @"whozmove/tap", @"own": @"0.2.0",
                                   @"steps": @[@{@"there": cask(@"0.2.1")}, @"look", @"putAway",
                                               @{@"there": cask(@"0.2.2")}, @"look"]},
        @"offline-keeps-what-github-said": @{@"tap": @"whozmove/tap", @"here": cask(@"0.2.0"), @"own": @"0.2.0",
                                             @"steps": @[@{@"there": cask(@"0.2.1")}, @"look",
                                                         @{@"there": NSNull.null}, @"look"]},
    };
}

// Runs the main run loop until `updates` has no look under way, 10 seconds at most.
static void SettleUpdates(Updates *updates) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:10];
    while (updates.working && until.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

// A case's steps, through Updates itself: what each look found (the version, or "none"), and how often GitHub was
// asked.
static NSDictionary *RunSteps(NSDictionary *setup, NSString *prefix) {
    __block NSString *there = nil;
    __block NSInteger asked = 0;
    NSString *own = setup[@"own"];
    BOOL checkout = [setup[@"checkout"] boolValue];
    Updates *(^opening)(void) = ^Updates * {
        Updates *updates = [[Updates alloc] initWithPrefix:prefix version:own fromCheckout:checkout];
        updates.fetch = ^NSString *(NSURL *url) {
            @synchronized (setup) { asked++; return there; }
        };
        return updates;
    };
    Updates *updates = opening();
    NSMutableArray *looks = [NSMutableArray array];
    for (id step in setup[@"steps"]) {
        if ([step isKindOfClass:NSDictionary.class]) {
            id answer = step[@"there"];
            @synchronized (setup) { there = [answer isKindOfClass:NSString.class] ? answer : nil; }
        } else if ([step isEqual:@"look"]) {
            [updates look];
            SettleUpdates(updates);
            [looks addObject:updates.found[@"version"] ?: @"none"];
        } else if ([step isEqual:@"putAway"]) {
            [updates putAway:updates.found[@"version"]];
            [looks addObject:[@"put away, then " stringByAppendingString:updates.found[@"version"] ?: @"none"]];
        } else if ([step isEqual:@"reopen"]) {
            updates = opening();
        }
    }
    return @{@"looks": looks, @"asked GitHub": @(asked)};
}

int PrintUpdates(NSArray<NSString *> *cases) {
    if (HomeIsYourOwn()) {
        fprintf(stderr, "--print-updates writes into Whozmove's folder in $HOME: run it with a throwaway HOME, as "
                        "modules/install/tests/test.sh does\n");
        return 2;
    }
    NSDictionary *setups = UpdateCases();
    NSMutableArray *printed = [NSMutableArray array];
    for (NSString *name in cases) {
        NSDictionary *setup = setups[name];
        if (!setup) {
            fprintf(stderr, "no case named %s\n", name.UTF8String);
            return 2;
        }
        NSString *prefix = [NSTemporaryDirectory() stringByAppendingPathComponent:
                            [@"whozmove-updates-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        NSString *tap = setup[@"tap"];
        if (tap) {
            NSString *receipt = HomebrewReceipt(prefix, kWhozmoveCask);
            [NSFileManager.defaultManager createDirectoryAtPath:receipt.stringByDeletingLastPathComponent
                                    withIntermediateDirectories:YES attributes:nil error:nil];
            NSDictionary *record = @{@"source": @{@"tap": tap, @"version": setup[@"installed"] ?: setup[@"own"]}};
            [[NSJSONSerialization dataWithJSONObject:record options:0 error:nil] writeToFile:receipt atomically:YES];
            NSString *file = TapCaskFile(prefix, tap, kWhozmoveCask);
            if (file && setup[@"here"]) {
                [NSFileManager.defaultManager createDirectoryAtPath:file.stringByDeletingLastPathComponent
                                        withIntermediateDirectories:YES attributes:nil error:nil];
                [setup[@"here"] writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
            }
        }
        [NSFileManager.defaultManager removeItemAtPath:UpdatesFile() error:nil];
        if (setup[@"steps"]) {
            NSMutableDictionary *run = [RunSteps(setup, prefix) mutableCopy];
            run[@"case"] = name;
            [printed addObject:run];
            [NSFileManager.defaultManager removeItemAtPath:prefix error:nil];
            continue;
        }
        __block NSString *asked = nil;
        NSString *said = nil;
        NSDictionary *newer = NewerVersion(prefix, setup[@"own"], ^NSString *(NSURL *url) {
            asked = url.absoluteString;
            return setup[@"there"];
        }, &said);
        [printed addObject:@{@"case": name, @"found": newer ?: NSNull.null, @"said": said ?: NSNull.null,
                             @"asked GitHub": asked ?: NSNull.null}];
        [NSFileManager.defaultManager removeItemAtPath:prefix error:nil];
    }
    return PrintJSON(printed);
}
