// Install: Whozmove setting itself up as it opens, a step at a time (Install.h).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Install.h"
#import "Files.h"
#import "Log.h"
#import "Printing.h"

// How often it looks again while it waits for the agent or for Apple's developer tools, which macOS is asked about at
// most every 5 minutes (DeveloperToolsGit).
static const NSTimeInterval kLookAgain = 10;

BOOL InApplications(NSString *app) {
    NSString *path = app.stringByStandardizingPath;
    for (NSString *folder in @[@"/Applications", [Home() stringByAppendingPathComponent:@"Applications"]])
        if ([path hasPrefix:[folder stringByAppendingString:@"/"]]) return YES;
    return NO;
}

// Notes where this app runs from, in Whozmove's folder (`app`), where the hooks read it: written whole, beside it and
// then moved in, and only when it changed. Nil once it's there, else why not.
static NSString *NoteApp(NSString *app) {
    NSString *file = AppDir(@"app"), *line = [app stringByAppendingString:@"\n"];
    NSString *noted = [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil];
    if ([noted isEqualToString:line]) return nil;
    [NSFileManager.defaultManager createDirectoryAtPath:AppDir(nil) withIntermediateDirectories:YES
                                             attributes:@{NSFilePosixPermissions: @0700} error:nil];
    return [line writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil]
        ? nil : @"couldn't note where Whozmove runs from";
}

// The module's own record, in Whozmove's folder (install.json) rather than the app's preferences, which a print run's
// $HOME doesn't reach: when the hooks were first found in the agent, so ones you take out later aren't put back.
static NSDictionary *Record(void) {
    return AsRecord(ReadJSON(AppDir(@"install.json"))) ?: @{};
}

static void KeepRecord(NSDictionary *record) {
    [NSFileManager.defaultManager createDirectoryAtPath:AppDir(nil) withIntermediateDirectories:YES
                                             attributes:@{NSFilePosixPermissions: @0700} error:nil];
    NSData *json = [NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingSortedKeys error:nil];
    if (![json writeToFile:AppDir(@"install.json") atomically:YES]) LogProblem(@"install: couldn't keep its record");
}

@interface Install ()
@property (copy) NSString *app, *hooks;
@property (assign) BOOL agentBuild;
@property (copy) BOOL (^agentHere)(void);
@property (copy) BOOL (^tools)(void);
@property (copy) ConnectHooks connect;
@property (strong) dispatch_queue_t queue;
@property (assign) NSInteger queued;  // checks queued or under way, counted on the main thread
@property (strong) NSDictionary *found;
@property (assign) NSTimeInterval checkedAt;
@property (copy) NSString *said;  // the outcome last said in the log, on the queue
@end

@implementation Install

- (instancetype)initWithApp:(NSString *)app builtByAgent:(BOOL)agentBuild agentHere:(BOOL (^)(void))agentHere
                      tools:(BOOL (^)(void))tools connect:(ConnectHooks)connect hooks:(NSString *)hooks {
    if (!(self = [super init])) return nil;
    self.app = app;
    self.agentBuild = agentBuild;
    self.agentHere = agentHere;
    self.tools = tools;
    self.connect = connect;
    self.hooks = hooks;
    self.queue = dispatch_queue_create("whozmove.install", DISPATCH_QUEUE_SERIAL);
    return self;
}

- (BOOL)working {
    return self.queued > 0;
}

- (void)check:(NSString *)answer {
    self.queued++;
    dispatch_async(self.queue, ^{
        NSDictionary *found = [self go:answer];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.queued--;
            self.found = found;
            self.checkedAt = NSDate.date.timeIntervalSince1970;
            if (self.onFound) self.onFound(found);
        });
    });
}

- (void)tick {
    NSString *state = self.found[@"state"];
    if (self.queued || !([state isEqualToString:@"noTools"] || [state isEqualToString:@"noCommand"])) return;
    if (NSDate.date.timeIntervalSince1970 - self.checkedAt < kLookAgain) return;
    [self check:nil];
}

// On the queue: each step in turn, as the module's README lays them out, each one's outcome said in the log. A copy
// running from anywhere but an Applications folder changes nothing, as it may be gone tomorrow and the hooks would
// record nothing then; the agent is looked for before Apple's developer tools, which only its sessions need; and
// nothing of Whozmove's runs the agent before the tools are in, as it may run git.
- (NSDictionary *)go:(NSString *)answer {
    if (!InApplications(self.app)) {
        [self say:[NSString stringWithFormat:@"install: running from %@, not an Applications folder, so nothing is "
                                              "set up", self.app]];
        return @{@"state": @"notInApplications"};
    }
    NSString *why = NoteApp(self.app);
    if (why) LogProblem([@"install: " stringByAppendingString:why]);
    if (!self.agentHere()) {
        [self say:@"install: waiting for the agent, which isn't on this Mac"];
        return @{@"state": @"noCommand"};
    }
    if (!self.tools()) {
        [self say:@"install: waiting for Apple's command line developer tools"];
        return @{@"state": @"noTools"};
    }
    if (self.agentBuild) {
        [self say:@"install: an agent made this build, so its hooks are left as they are"];
        return @{@"state": @"agentBuild"};
    }
    NSMutableDictionary *record = [Record() mutableCopy];
    BOOL before = record[@"connectedAt"] != nil;
    NSDictionary *found = (self.connect ? self.connect(answer, before, self.hooks) : nil)
        ?: @{@"state": @"failed", @"detail": @"There's no agent to put the hooks into"};
    NSString *state = AsText(found[@"state"]) ?: @"failed";
    if (!before && [@[@"ready", @"added", @"updated", @"turnedOff"] containsObject:state]) {
        record[@"connectedAt"] = @((long long)(NSDate.date.timeIntervalSince1970 * 1000));
        KeepRecord(record);
    }
    NSString *detail = AsText(found[@"detail"]);
    [self say:[NSString stringWithFormat:@"install: hooks %@%@", state,
                                         detail ? [@": " stringByAppendingString:detail] : @""]];
    return found;
}

// An outcome in the log, unless it's the one said last: while it waits, it looks every 10 seconds, and the log is
// cleared once it's full (Log.m), with everything else in it.
- (void)say:(NSString *)line {
    if ([line isEqualToString:self.said]) return;
    self.said = line;
    PanelLog(@"%@", line);
}

@end

#pragma mark The print mode

// What each case sets up: where the app runs from (~ for $HOME), whether an agent made it, the answers in turn (the
// last one standing) to whether the agent is on this Mac (`here`) and the developer tools are, and the agent's own,
// whether the hooks went in before, how many times it looks in all (the ticks' looks after the first), and your
// presses on the line, made one straight after the other.
static NSDictionary<NSString *, NSDictionary *> *InstallCases(void) {
    return @{
        @"applications": @{@"app": @"~/Applications/Whozmove.app", @"agent": @[@"added"]},
        @"nested": @{@"app": @"/Applications/Tools/Whozmove.app", @"agent": @[@"ready"]},
        @"downloads": @{@"app": @"~/Downloads/Whozmove.app"},
        @"disk-image": @{@"app": @"/Volumes/Whozmove/Whozmove.app"},
        @"translocated": @{@"app": @"/private/var/folders/zz/T/AppTranslocation/0A1B2C/d/Whozmove.app"},
        @"build-folder": @{@"app": @"~/Applications/../whozmove/build/Whozmove.app"},
        @"agent-build": @{@"app": @"~/Applications/Whozmove.app", @"agentBuild": @YES},
        @"no-agent-yet": @{@"app": @"~/Applications/Whozmove.app", @"here": @[@NO, @YES], @"agent": @[@"added"],
                           @"looks": @2},
        @"tools-later": @{@"app": @"~/Applications/Whozmove.app", @"tools": @[@NO, @YES], @"agent": @[@"added"],
                          @"looks": @2},
        @"neither-yet": @{@"app": @"~/Applications/Whozmove.app", @"here": @[@NO, @YES], @"tools": @[@NO, @YES],
                          @"agent": @[@"added"], @"looks": @3},
        @"no-command-yet": @{@"app": @"~/Applications/Whozmove.app", @"agent": @[@"noCommand", @"added"],
                             @"looks": @2},
        @"taken-out": @{@"app": @"~/Applications/Whozmove.app", @"before": @YES, @"agent": @[@"removed"]},
        @"turned-off": @{@"app": @"~/Applications/Whozmove.app", @"agent": @[@"turnedOff"]},
        @"presses": @{@"app": @"~/Applications/Whozmove.app", @"before": @YES,
                      @"agent": @[@"removed", @"added", @"ready"], @"presses": @[@"addBack", @"retry"]},
    };
}

// Runs the main run loop until `install` has no check queued or under way, 10 seconds at most.
static void Settle(Install *install) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:10];
    while (install.working && until.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

// `Whozmove --print-install <case>…`: each case set up with stand-ins for where the app runs from, whether an agent
// made it, the agent and Apple's developer tools, and checked as the app checks as it opens; then, as JSON, what each
// look found, what the agent was asked, in order (each call's start and end, so two never overlap), and what was
// noted in Whozmove's folder in $HOME, which each case starts without. modules/install/tests/test.sh checks it. It
// writes in Whozmove's folder there, so it refuses to run in your own home folder.
int PrintInstall(NSArray<NSString *> *cases) {
    if (HomeIsYourOwn()) {
        fprintf(stderr, "--print-install writes into Whozmove's folder in $HOME: run it with a throwaway HOME, as "
                        "modules/install/tests/test.sh does\n");
        return 2;
    }
    NSDictionary<NSString *, NSDictionary *> *setups = InstallCases();
    NSMutableArray *printed = [NSMutableArray array];
    for (NSString *name in cases) {
        NSDictionary *setup = setups[name];
        if (!setup) {
            fprintf(stderr, "no case named %s\n", name.UTF8String);
            return 2;
        }
        [NSFileManager.defaultManager removeItemAtPath:AppDir(@"app") error:nil];
        [NSFileManager.defaultManager removeItemAtPath:AppDir(@"install.json") error:nil];
        if ([setup[@"before"] boolValue]) KeepRecord(@{@"connectedAt": @1});
        NSMutableArray *here = [setup[@"here"] ?: @[@YES] mutableCopy];
        NSMutableArray *tools = [setup[@"tools"] ?: @[@YES] mutableCopy];
        NSMutableArray *answers = [setup[@"agent"] ?: @[] mutableCopy];
        NSMutableArray *asked = [NSMutableArray array], *looks = [NSMutableArray array];
        NSObject *lock = [NSObject new];
        NSString *app = setup[@"app"];
        if ([app hasPrefix:@"~/"]) app = [Home() stringByAppendingPathComponent:[app substringFromIndex:2]];
        Install *install = [[Install alloc] initWithApp:app builtByAgent:[setup[@"agentBuild"] boolValue]
            agentHere:^BOOL {
                BOOL there = [here.firstObject boolValue];
                if (here.count > 1) [here removeObjectAtIndex:0];
                return there;
            }
            tools:^BOOL {
                BOOL ready = [tools.firstObject boolValue];
                if (tools.count > 1) [tools removeObjectAtIndex:0];
                return ready;
            }
            connect:^NSDictionary *(NSString *answer, BOOL before, NSString *hooks) {
                NSString *call = [NSString stringWithFormat:@"%@, before %@", answer ?: @"at launch",
                                                            before ? @"yes" : @"no"];
                @synchronized (lock) { [asked addObject:[@"start: " stringByAppendingString:call]]; }
                [NSThread sleepForTimeInterval:0.05];
                NSString *state = answers.firstObject ?: @"ready";
                if (answers.count > 1) [answers removeObjectAtIndex:0];
                @synchronized (lock) { [asked addObject:[@"end: " stringByAppendingString:call]]; }
                return @{@"state": state};
            }
            hooks:@"<the hooks this app carries>"];
        install.onFound = ^(NSDictionary *found) { [looks addObject:found[@"state"]]; };
        [install check:nil];
        for (NSString *press in setup[@"presses"] ?: @[]) [install check:press];
        Settle(install);
        for (NSInteger more = [setup[@"looks"] integerValue] - 1; more > 0; more--) {
            [install check:nil];
            Settle(install);
        }
        NSString *noted = [NSString stringWithContentsOfFile:AppDir(@"app") encoding:NSUTF8StringEncoding error:nil];
        noted = [[noted stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
                 stringByReplacingOccurrencesOfString:Home() withString:@"~"];
        NSDictionary *record = Record();
        [printed addObject:@{@"case": name, @"found": looks, @"asked": asked,
                             @"noted": noted ?: NSNull.null,
                             @"connected": record[@"connectedAt"] ? @"recorded" : @"not recorded"}];
    }
    return PrintJSON(printed);
}
