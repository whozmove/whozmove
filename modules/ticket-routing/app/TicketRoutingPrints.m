// TicketRoutingPrints: --print-ticket-routing, the routing module driven as the card and Settings would drive it, step
// by step, with a made-up tracker ("Sample", its tickets' Team field), in a throwaway home only, against a made-up repo
// the test makes: the card's asks and their answers, each way set, what's kept and read back after a restart, a file
// changed by hand, Settings' page with each way's before and after and each option's folder, and panel.log, which
// names only the project whose way changed.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "TicketRoutingModule.h"
#import "Routes.h"
#import "Core.h"
#import "Files.h"
#import "Git.h"
#import "Printing.h"
#import "Row.h"
#include <sys/stat.h>

// A made-up tracker: each ticket's Team, by its key ("none" for no Team, "unread" for one it can't read), and the one
// field its tickets take an option of. Everything else a tracker does, it doesn't.
@interface RoutingSampleTracker : NSObject <Tracker>
@property (strong) NSMutableDictionary<NSString *, NSString *> *teams;
// Its Team field given as one looked up as you type: no options listed (`lookup`).
@property BOOL lookup;
@end

@implementation RoutingSampleTracker
- (NSString *)trackerName { return @"Sample"; }
- (NSString *)signInName { return @"Sample"; }
- (TrackerSignIn)signInState { return TrackerSignedIn; }
- (NSArray<NSString *> *)sites { return @[@"acme.example"]; }
- (void)findSites:(void (^)(NSArray<NSString *> *))done { done(self.sites); }
- (NSString *)signInWhy { return nil; }
- (NSString *)adminAsk { return nil; }
- (void)signIn:(void (^)(TrackerSignIn, NSString *))done { done(TrackerSignedIn, nil); }
- (void)cancelSignIn {}
- (void)signOut {}
- (NSString *)keyIn:(NSString *)text site:(NSString **)site { return nil; }
- (NSString *)linkFor:(NSString *)key site:(NSString *)site { return nil; }
- (void)search:(NSString *)words done:(TicketsDone)done { done(@[], [TrackerAnswer done]); }
- (void)take:(NSString *)stepId of:(NSString *)key site:(NSString *)site note:(NSString *)note
      fields:(NSDictionary *)fields done:(TicketDone)done { done(nil, [TrackerAnswer done]); }
- (void)addNote:(NSString *)note to:(NSString *)key site:(NSString *)site done:(void (^)(TrackerAnswer *))done {
    done([TrackerAnswer done]);
}
- (void)newTicketOptions:(NSString *)group site:(NSString *)site done:(void (^)(NSDictionary *, TrackerAnswer *))done {
    done(nil, [TrackerAnswer done]);
}
- (void)create:(NSDictionary *)draft site:(NSString *)site done:(TicketDone)done { done(nil, [TrackerAnswer done]); }

+ (NSDictionary *)teamIds {
    return @{@"checkout": @"10", @"billing": @"11", @"web": @"12"};
}

- (void)read:(NSString *)key site:(NSString *)site done:(TicketDone)done {
    NSString *team = self.teams[key];
    if ([team isEqual:@"unread"])
        return done(nil, [TrackerAnswer end:TrackerEndSignIn why:@"Sign in with Sample first"]);
    Ticket *ticket = [Ticket new];
    ticket.tracker = @"Sample";
    ticket.site = site;
    ticket.key = key;
    ticket.type = @"Task";
    TicketGroup *project = [TicketGroup new];
    project.groupId = @"PAY";
    ticket.groups = @[project];
    NSString *teamId = RoutingSampleTracker.teamIds[team ?: @""];
    ticket.values = teamId ? @{@"customfield_10001": @{@"id": teamId, @"name": team}} : @{};
    done(ticket, [TrackerAnswer done]);
}

- (void)optionFieldsOf:(Ticket *)ticket done:(void (^)(NSArray<TicketField *> *, TrackerAnswer *))done {
    TicketField *team = [TicketField new];
    team.fieldId = @"customfield_10001";
    team.name = @"Team";
    team.kind = @"option";
    team.options = self.lookup ? @[] : @[@"checkout", @"billing", @"web"];
    team.optionIds = self.lookup ? @[] : @[@"10", @"11", @"12"];
    team.kind = self.lookup ? @"text" : @"option";
    TicketField *size = [TicketField new];
    size.fieldId = @"customfield_10002";
    size.name = @"Size";
    size.kind = @"option";
    size.options = @[@"small", @"large"];
    size.optionIds = @[@"20", @"21"];
    done(@[size, team], [TrackerAnswer done]);
}
@end

// A path with the home folder and the test's own folder out of it, so what's printed is the same on every Mac.
static NSString *Plain(NSString *text, NSString *repo) {
    NSString *base = RealPath(repo).stringByDeletingLastPathComponent;
    return [[text stringByReplacingOccurrencesOfString:base withString:@"<repos>"]
            stringByReplacingOccurrencesOfString:Home() withString:@"~"];
}

static void Line(NSString *text, NSString *repo) {
    printf("%s\n", Plain(text, repo).UTF8String);
}

static NSString *JSONOf(id object) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object ?: NSNull.null
                                                   options:NSJSONWritingSortedKeys | NSJSONWritingFragmentsAllowed
                                                           | NSJSONWritingWithoutEscapingSlashes
                                                     error:nil];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"(not JSON)";
}

static void PrintGroups(NSArray<AppGroup *> *groups, NSString *in, NSString *repo);

// Settings' page as the back is sent it: each group's heading and Important, each choice with the one picked, and
// what picking each other way would change.
static void PrintSettings(TicketRoutingModule *module, NSString *repo) {
    SettingEntry *row = module.settingEntries.firstObject;
    Line([NSString stringWithFormat:@"Settings' row: %@, %@, shown %@", row.title, row.said(), row.shown() ? @"yes" : @"no"],
         repo);
    AppEntry *app = module.appEntries.firstObject;
    Line([NSString stringWithFormat:@"its page: %@ (shown %@): %@", app.name, app.present() ? @"yes" : @"no", app.does],
         repo);
    for (AppStatus *status in app.statuses) {
        NSDictionary *now = status.now();
        if (now) Line([NSString stringWithFormat:@"  [%@] %@ · %@ · %@", status.title, now[@"note"], now[@"said"],
                       now[@"button"]], repo);
    }
    PrintGroups(app.groups, @"  ", repo);
}

// Groups as the page shows them: each heading, Important, its rows, and a row's own page under it, further in.
static void PrintGroups(NSArray<AppGroup *> *groups, NSString *in, NSString *repo) {
    for (AppGroup *group in groups) {
        Line([NSString stringWithFormat:@"%@%@%@%@", in, group.title, group.important ? @" [Important]" : @"",
              group.foot ? [@": " stringByAppendingString:group.foot] : @""], repo);
        for (id row in group.rows) {
            if ([row isKindOfClass:AppPage.class]) {
                AppPage *page = row;
                Line([NSString stringWithFormat:@"%@  %@ · %@ ›", in, page.title, page.said ? page.said() : @""], repo);
                PrintGroups(page.groups(), [in stringByAppendingString:@"    "], repo);
                continue;
            }
            AppChoice *choice = row;
            NSString *picked = choice.picked();
            Line([NSString stringWithFormat:@"%@  %@%@%@", in, choice.key, choice.menu ? @" (a menu)" : @"",
                  choice.fixed ? [NSString stringWithFormat:@" (%@: %@)", choice.fixed[@"name"], choice.fixed[@"help"]]
                               : @""], repo);
            for (NSDictionary *each in choice.choices()) {
                NSDictionary *said = choice.confirm && ![each[@"id"] isEqual:picked] ? choice.confirm(each[@"id"]) : nil;
                Line([NSString stringWithFormat:@"%@    %@ %@ (%@)%@", in, [each[@"id"] isEqual:picked] ? @"✓" : @"·",
                      each[@"name"], each[@"help"], said ? [@" → " stringByAppendingString:JSONOf(said)] : @""], repo);
            }
        }
    }
}

// Every choice on the page, those on the pages its rows open too.
static NSArray<AppChoice *> *ChoicesIn(NSArray<AppGroup *> *groups) {
    NSMutableArray *out = [NSMutableArray array];
    for (AppGroup *group in groups)
        for (id row in group.rows) {
            if ([row isKindOfClass:AppChoice.class]) [out addObject:row];
            else if ([row isKindOfClass:AppPage.class]) [out addObjectsFromArray:ChoicesIn([row groups]())];
        }
    return out;
}

static int PrintRouting(Core *core, NSArray<NSString *> *steps) {
    if (HomeIsYourOwn()) {
        fprintf(stderr, "--print-ticket-routing runs only in a throwaway home\n");
        return 2;
    }
    if (steps.count < 1) {
        fprintf(stderr, "usage: Whozmove --print-ticket-routing <repo> <step>...\n");
        return 2;
    }
    NSString *repo = steps[0], *kept = [AppDir(@"ticket-routing") stringByAppendingPathComponent:@"routes.json"];
    RoutingSampleTracker *tracker = [RoutingSampleTracker new];
    tracker.teams = [NSMutableDictionary dictionary];
    TicketRoutingModule *(^made)(void) = ^TicketRoutingModule * {
        TicketRoutingModule *module = [[TicketRoutingModule alloc] initWithCore:core];
        module.givenTrackers = @[tracker];
        module.answered = ^(NSDictionary *answer) { Line([@"  → " stringByAppendingString:JSONOf(answer)], repo); };
        [module keepIn:kept];
        return module;
    };
    TicketRoutingModule *module = made();
    NSInteger asked = 0;
    for (NSString *step in [steps subarrayWithRange:NSMakeRange(1, steps.count - 1)]) {
        NSArray *words = [step componentsSeparatedByString:@" "];
        NSString *verb = words[0], *one = words.count > 1 ? words[1] : nil, *two = words.count > 2 ? words[2] : nil;
        Line([@"## " stringByAppendingString:step], repo);
        if ([verb isEqual:@"team"]) tracker.teams[one] = two;
        else if ([verb isEqual:@"lookup"]) tracker.lookup = YES;
        else if ([verb isEqual:@"ask"])  // ask KEY [folder]
            [module route:@{@"asked": @(++asked), @"folder": two ?: repo, @"tracker": @"Sample",
                            @"site": @"acme.example", @"key": one}];
        else if ([verb isEqual:@"set"])  // set own|folder|field [folder]
            [module setRoute:@{@"folder": two ?: repo, @"way": @{@"kind": one}}];
        else if ([verb isEqual:@"pick"]) {  // pick way <kind>, or pick option <id> <folder or own>
            for (AppChoice *choice in ChoicesIn(module.appEntries.firstObject.groups))
                    if ([choice.key hasPrefix:[one stringByAppendingString:@":"]]
                        && ([one isEqual:@"way"] || [choice.key hasSuffix:[@":" stringByAppendingString:words[2]]]))
                        choice.pick([one isEqual:@"way"] ? two : (words.count > 3 ? words[3] : @"own"));
        } else if ([verb isEqual:@"settings"]) PrintSettings(module, repo);
        else if ([verb isEqual:@"kept"]) {
            struct stat about;
            BOOL there = stat(kept.fileSystemRepresentation, &about) == 0;
            // When each was set changes from run to run: only that it's there is printed.
            NSMutableDictionary *routes = [AsRecord(ReadJSON(kept)) mutableCopy];
            for (NSString *project in routes.allKeys) {
                NSMutableDictionary *entry = [AsRecord(routes[project]) mutableCopy];
                if (entry[@"at"]) entry[@"at"] = @"(when)";
                routes[project] = entry;
            }
            Line([NSString stringWithFormat:@"routes.json (%@): %@", there ? [NSString stringWithFormat:@"%o",
                  about.st_mode & 0777] : @"none", routes ? JSONOf(routes) : @"none"], repo);
        } else if ([verb isEqual:@"relaunch"]) module = made();
        else if ([verb isEqual:@"busy"]) {  // busy KEY: a conversation working that ticket in the project's folder
            Row *row = [[Row alloc] initWithFields:@{@"sessionId": @"s1", @"cwd": RealPath(repo), @"status": @"idle",
                                                     @"pid": @(getpid())}];
            row.git = @{@"root": RealPath(repo)};
            row.ticket = @{@"bound": @{@"tracker": @"Sample", @"key": one}};
            module.rowsSeen = @[row];
        }
        else if ([verb isEqual:@"hand"]) {  // hand <folder>: the file changed by hand, a team's folder now that one
            NSMutableDictionary *routes = [AsRecord(ReadJSON(kept)) mutableCopy];
            NSString *project = RealPath(repo);
            NSMutableDictionary *entry = [routes[project] mutableCopy], *runs = [entry[@"runs"] mutableCopy];
            NSMutableDictionary *folders = [runs[@"folders"] mutableCopy];
            folders[@"11"] = @{@"name": @"billing", @"folder": one};
            runs[@"folders"] = folders;
            entry[@"runs"] = runs;
            routes[project] = entry;
            [[NSJSONSerialization dataWithJSONObject:routes options:0 error:nil] writeToFile:kept atomically:YES];
        } else if ([verb isEqual:@"elsewhere"]) {  // elsewhere <folder>: a way kept for a folder that's no project now
            NSMutableDictionary *routes = [AsRecord(ReadJSON(kept)) mutableCopy] ?: [NSMutableDictionary dictionary];
            routes[one] = @{@"runs": @{@"kind": @"own"}, @"at": @1};
            [[NSJSONSerialization dataWithJSONObject:routes options:0 error:nil] writeToFile:kept atomically:YES];
        } else if ([verb isEqual:@"forget"]) {  // Forget It on each project that has gone
            for (AppStatus *status in module.appEntries.firstObject.statuses) status.press();
        } else if ([verb isEqual:@"match"]) {  // the plain match, over this repo's folders
            Line(JSONOf(RouteMatch(RealPath(repo), @[@{@"id": @"10", @"name": @"Checkout"}, @{@"id": @"11", @"name":
                @"billing"}, @{@"id": @"12", @"name": @"Web Team"}], CheckoutsInFiles(repo))), repo);
            Line(JSONOf(CheckoutsInFiles(repo)), repo);
        } else if ([verb isEqual:@"logged"]) {
            NSString *log = [NSString stringWithContentsOfFile:AppDir(@"panel.log") encoding:NSUTF8StringEncoding
                                                         error:nil] ?: @"";
            for (NSString *line in [log componentsSeparatedByString:@"\n"])
                if ([line containsString:@"Ticket routing"]) {
                    NSRange from = [line rangeOfString:@"Ticket routing"];
                    Line([line substringFromIndex:from.location], repo);
                }
        } else Line(@"(a step it doesn't know)", repo);
    }
    return 0;
}

NSDictionary<NSString *, PrintMode> *TicketRoutingPrintModes(void) {
    return @{@"--print-ticket-routing": ^int(Core *core, NSArray<NSString *> *arguments) {
        return PrintRouting(core, arguments);
    }};
}
