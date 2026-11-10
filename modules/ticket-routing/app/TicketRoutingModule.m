// TicketRoutingModule: where a ticket given to a new conversation starts. The card's routing part asks, for its project
// and ticket, and is answered with the project's way and where the ticket goes by it (Routes.m), or, the first time in
// a git project, the guide's choices, each with where this ticket would open. Your press of Start on the guide, or of
// Change in Settings ▸ Tickets after its before and after, sets a project's way; nothing else does. By a field, the
// ticket's own option is read from its tracker as you pick it, and each option has its folder, matched by name as the
// way is set and changed in Settings. Kept in AppDir/ticket-routing/routes.json, checked again whenever it's read.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "TicketRoutingModule.h"
#import "Routes.h"
#import "Core.h"
#import "Row.h"
#import "Page.h"
#import "Files.h"
#import "Git.h"
#import "Log.h"

static NSString *const kAppId = @"ticket-routing";

// A path as the card and Settings show it, with ~ for the home folder.
static NSString *Shown(NSString *path) {
    NSString *home = Home();
    return [path hasPrefix:[home stringByAppendingString:@"/"]]
        ? [@"~" stringByAppendingString:[path substringFromIndex:home.length]] : path;
}

// A field's options as {id, name}, from a tracker's field.
static NSArray<NSDictionary *> *OptionsOf(TicketField *field) {
    NSMutableArray *options = [NSMutableArray array];
    for (NSUInteger i = 0; i < field.options.count && i < field.optionIds.count; i++)
        [options addObject:@{@"id": field.optionIds[i], @"name": field.options[i]}];
    return options;
}

// Why a tracker's answer didn't read the ticket, as the card words it: a sign-in wanted, asked to slow down, or else.
static NSDictionary *ProblemOf(TrackerAnswer *answer) {
    NSString *kind = answer.end == TrackerEndSignIn || answer.end == TrackerEndAsksMac ? @"signIn"
        : answer.end == TrackerEndSlowDown ? @"slow" : @"failed";
    return @{@"kind": kind, @"why": answer.why ?: @""};
}

@interface TicketRoutingModule ()
@property (strong, readwrite) NSMutableDictionary<NSString *, NSDictionary *> *routes;
@property (copy) NSString *keptPath;
// The fields the guide last offered for a project, {field: {id, name}, tracker, site, options: [{id, name}]}: setting
// the way by that field matches its options to the project's folders.
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *offered;
// The projects whose way was kept but whose folder isn't a project's any more, as they were read: Settings says so,
// with Forget It, rather than letting them go unsaid.
@property (strong) NSMutableArray<NSString *> *gone;
@property (copy) NSDictionary *goneKept;  // what was kept for each, written back as it was until Forget It
@end

@implementation TicketRoutingModule

+ (NSString *)moduleName {
    return @"ticket-routing";
}

+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return TicketRoutingPrintModes();
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.routes = [NSMutableDictionary dictionary];
    self.offered = [NSMutableDictionary dictionary];
    return self;
}

- (void)launch {
    [self keepIn:[AppDir(@"ticket-routing") stringByAppendingPathComponent:@"routes.json"]];
}

- (void)keepIn:(NSString *)path {
    self.keptPath = path;
    NSMutableArray *dropped = [NSMutableArray array];
    self.routes = [RoutesRead(path, dropped) mutableCopy];
    for (NSString *line in dropped) PanelLog(@"Ticket routing: %@", line);
    self.gone = [NSMutableArray array];
    NSDictionary *read = AsRecord(ReadJSON(path));
    NSMutableDictionary *kept = [NSMutableDictionary dictionary];
    for (NSString *project in read)
        if (project.isAbsolutePath && !self.routes[project] && AsRecord(read[project])) {
            [self.gone addObject:project];
            kept[project] = read[project];
        }
    self.goneKept = kept;
}

// The ways written back, with those of projects whose folder has gone as they were, until you forget them.
- (void)keep {
    NSMutableDictionary *all = [self.routes mutableCopy];
    for (NSString *project in self.gone) if (self.goneKept[project]) all[project] = self.goneKept[project];
    if (self.keptPath && !RoutesWrite(self.keptPath, all)) PanelLog(@"Ticket routing: couldn't keep the ways");
}

- (NSArray<id<Tracker>> *)trackers {
    return self.givenTrackers ?: [self.core modulesThat:@protocol(Tracker)];
}

- (id<Tracker>)tracker:(NSString *)name {
    for (id<Tracker> tracker in self.trackers) if ([tracker.trackerName isEqualToString:name]) return tracker;
    return nil;
}

- (void)rows:(NSArray<Row *> *)rows phase:(RowPhase)phase {
    if (phase == RowPhaseListed) self.rowsSeen = rows;
}

- (NSDictionary<NSString *, void (^)(NSDictionary *)> *)messages {
    __weak typeof(self) weakSelf = self;
    return @{
        @"ticketRoute": ^(NSDictionary *msg) { [weakSelf route:msg]; },
        @"ticketRouteSet": ^(NSDictionary *msg) { [weakSelf setRoute:msg]; },
        @"ticketRouteSignIn": ^(NSDictionary *msg) { [weakSelf signIn:msg]; },
    };
}

- (void)answer:(NSDictionary *)answer {
    if (self.answered) return self.answered(answer);
    [self.core.page call:@"ticketRouted" with:@[answer]];
}

#pragma mark The card's asks

// The card's ask for a ticket ({asked, folder, tracker, site, key}): answered at once with what's kept, then, where
// the ticket's own fields count (a way by a field, or the guide, which may offer one), again once they're read.
- (void)route:(NSDictionary *)msg {
    NSNumber *asked = AsNumber(msg[@"asked"]);
    NSString *folder = AsText(msg[@"folder"]), *key = AsText(msg[@"key"]);
    NSString *trackerName = AsText(msg[@"tracker"]), *site = AsText(msg[@"site"]);
    if (!asked || !folder.isAbsolutePath || !key.length) return;
    NSString *project = RealPath(ProjectRoot(folder));
    NSMutableDictionary *answer = [@{@"asked": asked, @"key": key} mutableCopy];
    if (!project) {
        answer[@"git"] = @NO;
        return [self answer:answer];
    }
    NSDictionary *way = AsRecord(self.routes[project][@"runs"]);
    [answer addEntriesFromDictionary:@{@"git": @YES, @"project": project, @"name": project.lastPathComponent,
                                       @"way": way ? [self wayShown:way] : NSNull.null}];
    BOOL byField = [AsText(way[@"kind"]) isEqual:@"field"];
    if (way && !byField) {
        answer[@"place"] = [self placeShown:RoutePlace(project, way, nil)];
        return [self answer:answer];
    }
    id<Tracker> tracker = [self tracker:trackerName];
    if (byField) answer[@"place"] = @{@"kind": @"own", @"reading": @YES};
    else answer[@"guide"] = @{@"reading": tracker ? @YES : @NO};
    [self answer:answer];
    if (!tracker) {
        if (byField) [self answer:[self with:answer place:RoutePlace(project, way, nil) problem:nil]];
        return;
    }
    [tracker read:key site:site done:^(Ticket *ticket, TrackerAnswer *read) {
        if (byField) {
            return [self answer:[self with:answer place:RoutePlace(project, way, ticket ? ticket.values ?: @{} : nil)
                                   problem:ticket ? nil : ProblemOf(read)]];
        }
        if (!ticket || ![tracker respondsToSelector:@selector(optionFieldsOf:done:)])
            return [self answer:[self with:answer guide:@{}]];
        [tracker optionFieldsOf:ticket done:^(NSArray<TicketField *> *fields, TrackerAnswer *found) {
            NSDictionary *offer = [self offerFor:project fields:fields ?: @[] ticket:ticket tracker:trackerName site:site];
            [self answer:[self with:answer guide:offer ? @{@"field": offer} : @{}]];
        }];
    }];
}

- (NSDictionary *)with:(NSDictionary *)answer place:(NSDictionary *)place problem:(NSDictionary *)problem {
    NSMutableDictionary *out = [answer mutableCopy];
    out[@"place"] = [self placeShown:place];
    if (problem) out[@"problem"] = problem;
    return out;
}

- (NSDictionary *)with:(NSDictionary *)answer guide:(NSDictionary *)guide {
    NSMutableDictionary *out = [answer mutableCopy];
    out[@"guide"] = guide;
    return out;
}

// The field the guide offers for a project, of those its tickets take one option of: the one with most options
// matched to the project's folders by name, if any is; with this ticket's own option and its folder, if it has them.
- (NSDictionary *)offerFor:(NSString *)project fields:(NSArray<TicketField *> *)fields ticket:(Ticket *)ticket
                   tracker:(NSString *)tracker site:(NSString *)site {
    NSDictionary *checkouts = CheckoutsInFiles(project);
    TicketField *best = nil;
    NSDictionary *bestMatch = nil;
    NSUInteger most = 0;
    for (TicketField *field in fields) {
        NSDictionary *match = RouteMatch(project, OptionsOf(field), checkouts);
        NSUInteger matched = 0;
        for (NSDictionary *option in match.allValues) if (AsText(option[@"folder"])) matched++;
        if (matched > most) {
            most = matched;
            best = field;
            bestMatch = match;
        }
    }
    if (!best) return nil;
    self.offered[project] = @{@"field": @{@"id": best.fieldId, @"name": best.name}, @"tracker": tracker,
                              @"site": site ?: @"", @"options": OptionsOf(best)};
    NSDictionary *value = AsRecord(ticket.values[best.fieldId]);
    NSString *folder = AsText(AsRecord(bestMatch[AsText(value[@"id"]) ?: @""])[@"folder"]);
    return @{@"id": best.fieldId, @"name": best.name, @"value": AsText(value[@"name"]) ?: NSNull.null,
             @"path": folder ?: NSNull.null, @"folder": folder ? Shown(folder) : NSNull.null,
             @"here": @([folder isEqualToString:project])};
}

// A way as the page has it: its kind, and a field's name.
- (NSDictionary *)wayShown:(NSDictionary *)way {
    if (![AsText(way[@"kind"]) isEqual:@"field"]) return @{@"kind": AsText(way[@"kind"]) ?: @"own"};
    return @{@"kind": @"field", @"field": AsRecord(way[@"field"]) ?: @{}};
}

// Where it goes, as the page has it: a folder by its path, and as it's shown.
- (NSDictionary *)placeShown:(NSDictionary *)place {
    NSMutableDictionary *out = [place mutableCopy];
    NSString *folder = AsText(place[@"folder"]);
    if (folder) out[@"where"] = Shown(folder);
    return out;
}

// Sign In, on a line whose ticket couldn't be read for want of one ({tracker}): the tracker's own sign-in, then the
// card asks about its ticket afresh.
- (void)signIn:(NSDictionary *)msg {
    id<Tracker> tracker = [self tracker:AsText(msg[@"tracker"])];
    __weak typeof(self) weakSelf = self;
    [tracker signIn:^(TrackerSignIn state, NSString *why) {
        if (!weakSelf.answered) [weakSelf.core.page call:@"ticketRouteAgain" with:@[]];
    }];
}

#pragma mark Setting a way

// The guide's Start ({folder, way: {kind, field}}): the project's way, kept. By a field, only the one the guide
// offered for it, its options matched to the project's folders.
- (void)setRoute:(NSDictionary *)msg {
    NSString *folder = AsText(msg[@"folder"]);
    NSString *project = folder.isAbsolutePath ? RealPath(ProjectRoot(folder)) : nil;
    NSDictionary *way = [self wayFor:project given:AsRecord(msg[@"way"])];
    if (!way) return;
    [self set:way of:project];
}

- (NSDictionary *)wayFor:(NSString *)project given:(NSDictionary *)given {
    NSString *kind = AsText(given[@"kind"]);
    if (!project) return nil;
    if ([kind isEqual:@"own"] || [kind isEqual:@"folder"]) return @{@"kind": kind};
    if (![kind isEqual:@"field"]) return nil;
    NSDictionary *offered = self.offered[project], *field = offered[@"field"];
    NSDictionary *kept = AsRecord(self.routes[project][@"runs"]);
    // The field it's by already, as kept, keeps its folders.
    if ([AsText(kept[@"kind"]) isEqual:@"field"]
        && (!AsText(given[@"field"]) || [AsText(AsRecord(kept[@"field"])[@"id"]) isEqual:AsText(given[@"field"])]))
        return kept;
    if (!field || (AsText(given[@"field"]) && ![field[@"id"] isEqual:AsText(given[@"field"])])) return nil;
    return @{@"kind": @"field", @"tracker": offered[@"tracker"], @"site": offered[@"site"], @"field": field,
             @"folders": RouteMatch(project, offered[@"options"], CheckoutsInFiles(project))};
}

- (void)set:(NSDictionary *)way of:(NSString *)project {
    NSMutableArray *dropped = [NSMutableArray array];
    NSDictionary *checked = RoutesChecked(@{project: @{@"runs": way, @"at": @(NSDate.date.timeIntervalSince1970)}},
                                          dropped)[project];
    if (!checked) return;
    self.routes[project] = checked;
    [self keep];
    // Only which project's way changed: never a ticket, a field's options or a folder.
    PanelLog(@"Ticket routing: %@'s way changed", project.lastPathComponent);
}

#pragma mark Settings ▸ Tickets

// Settings' Tickets row, once a project's way is set: it opens the page below, saying how many projects have one.
- (NSArray<SettingEntry *> *)settingEntries {
    __weak typeof(self) weakSelf = self;
    SettingEntry *page = [SettingEntry pageWithKey:@"ticketRouting" title:@"Tickets" app:kAppId];
    page.said = ^NSString * {
        NSUInteger n = weakSelf.routes.count;
        return n == 1 ? @"1 project" : [NSString stringWithFormat:@"%lu projects", (unsigned long)n];
    };
    page.shown = ^BOOL { return weakSelf.routes.count > 0 || weakSelf.gone.count > 0; };
    page.group = 20;
    page.order = 40;
    return @[page];
}

// The keys of the tickets the project's own conversations work in its own folder, now: what a way putting new tickets
// there would put them beside.
- (NSArray<NSString *> *)ticketsWorkedIn:(NSString *)project {
    NSMutableArray *keys = [NSMutableArray array];
    for (Row *row in self.rowsSeen) {
        NSString *key = AsText(AsRecord(row.ticket[@"bound"])[@"key"]), *root = AsText(row.git[@"root"]);
        if (key && root && [RealPath(root) isEqualToString:project] && ![self.core hasEnded:row]
            && ![keys containsObject:key]) [keys addObject:key];
    }
    return keys;
}

// The page: a heading marked Important, over a row for each project, saying its way and opening the project's own
// page; and a card for each project whose folder isn't there any more, with Forget It.
- (NSArray<AppEntry *> *)appEntries {
    __weak typeof(self) weakSelf = self;
    AppEntry *app = [AppEntry appWithId:kAppId name:@"Tickets"
                                   does:@"Where a ticket you give a new conversation starts, in each project where "
                                        @"you've started one: its own worktree, the project's folder, or a folder for "
                                        @"each option of one of its fields." order:80];
    app.tool = YES;
    app.glyph = @"ticket";
    app.present = ^BOOL { return weakSelf.routes.count > 0 || weakSelf.gone.count > 0; };
    // A project whose folder isn't there any more: said, with Forget It, which lets its way go.
    NSMutableArray *statuses = [NSMutableArray array];
    for (NSString *project in self.gone)
        [statuses addObject:[AppStatus statusWithKey:[@"gone:" stringByAppendingString:project] title:project.lastPathComponent
                                                 now:^NSDictionary * {
            return [weakSelf.gone containsObject:project]
                ? @{@"said": @"Not there", @"note": [NSString stringWithFormat:@"%@ isn't there any more",
                                                    project.lastPathComponent], @"button": @"Forget It"} : nil;
        } press:^{
            [weakSelf.gone removeObject:project];
            [weakSelf keep];
            PanelLog(@"Ticket routing: %@'s way forgotten", project.lastPathComponent);
        }]];
    app.statuses = statuses;
    NSArray *projects = [self.routes.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [a.lastPathComponent localizedCaseInsensitiveCompare:b.lastPathComponent];
    }];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSString *project in projects) {
        AppPage *page = [AppPage pageWithKey:project title:project.lastPathComponent
                                      groups:^NSArray<AppGroup *> * { return [weakSelf groupsFor:project]; }];
        page.said = ^NSString * {
            return RouteWayName(project, AsRecord(weakSelf.routes[project][@"runs"]) ?: @{});
        };
        [rows addObject:page];
    }
    AppGroup *head = [AppGroup groupWithTitle:@"How tickets open" rows:rows
                                         foot:@"A change counts for new tickets: tickets started already keep their "
                                              @"folders." order:0];
    head.important = YES;
    app.groups = @[head];
    return @[app];
}

// A project's page: its way, picked after its before and after; and for a way by a field, each option's folder, one
// row each, picked from the Mac's menu.
- (NSArray<AppGroup *> *)groupsFor:(NSString *)project {
    __weak typeof(self) weakSelf = self;
    NSString *name = project.lastPathComponent;
    NSDictionary *(^runs)(void) = ^NSDictionary * { return AsRecord(weakSelf.routes[project][@"runs"]) ?: @{}; };
    NSArray *(^ways)(void) = ^NSArray * {
        NSMutableArray *out = [@[@{@"id": @"own", @"name": @"Its own worktree",
                                   @"help": @"A new worktree for each ticket, named after its key"},
                                 @{@"id": @"folder", @"name": [NSString stringWithFormat:@"In %@ itself", name],
                                   @"help": @"Every ticket in the project's folder, with your other work"}] mutableCopy];
        NSDictionary *field = AsRecord(runs()[@"field"]) ?: weakSelf.offered[project][@"field"];
        if (field) [out addObject:@{@"id": @"field", @"name": RouteWayName(project, @{@"kind": @"field", @"field": field}),
                                    @"help": @"Each option's own folder, as its name matches"}];
        return out;
    };
    AppChoice *way = [AppChoice choiceWithKey:[@"way:" stringByAppendingString:project] title:name choices:ways
                                       picked:^NSString * { return AsText(runs()[@"kind"]); }
                                         pick:^(NSString *choice) {
        NSDictionary *chosen = [weakSelf wayFor:project given:@{@"kind": choice}];
        if (chosen) [weakSelf set:chosen of:project];
    }];
    way.confirm = ^NSDictionary *(NSString *choice) {
        NSDictionary *chosen = [weakSelf wayFor:project given:@{@"kind": choice}];
        return chosen ? RouteBeforeAfter(project, runs(), chosen, [weakSelf ticketsWorkedIn:project]) : nil;
    };
    NSMutableArray *groups = [NSMutableArray arrayWithObject:[AppGroup groupWithTitle:@"Its tickets open" rows:@[way]
                                                                                foot:nil order:0]];
    NSDictionary *folders = [AsText(runs()[@"kind"]) isEqual:@"field"] ? AsRecord(runs()[@"folders"]) : nil;
    if (folders.count) {
        // The project's folders, read once for the page as it's drawn, not once for each option.
        NSDictionary *checkouts = CheckoutsInFiles(project);
        NSMutableArray *rows = [NSMutableArray array];
        for (NSString *optionId in [folders.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
                 return [AsText(folders[a][@"name"]) localizedCaseInsensitiveCompare:AsText(folders[b][@"name"])];
             }])
            [rows addObject:[self optionRow:optionId of:project checkouts:checkouts]];
        NSString *fieldName = AsText(AsRecord(runs()[@"field"])[@"name"]) ?: @"option";
        [groups addObject:[AppGroup groupWithTitle:[NSString stringWithFormat:@"Each %@'s folder", fieldName] rows:rows
                                              foot:@"Matched by name as the way was set. An option with no folder "
                                                   @"gives each of its tickets its own worktree." order:1]];
    }
    return groups;
}

// One of a field's options, one row: its name over where its tickets open, and that folder on a button opening the
// Mac's menu of the project's folders, or its own worktree. A folder that has gone says so.
- (AppChoice *)optionRow:(NSString *)optionId of:(NSString *)project
               checkouts:(NSDictionary<NSString *, NSString *> *)checkouts {
    __weak typeof(self) weakSelf = self;
    NSDictionary *(^option)(void) = ^NSDictionary * {
        return AsRecord(AsRecord(AsRecord(weakSelf.routes[project][@"runs"])[@"folders"])[optionId]);
    };
    NSArray *(^folders)(void) = ^NSArray * {
        NSMutableArray *out = [NSMutableArray array];
        for (NSString *path in [checkouts.allKeys sortedArrayUsingSelector:@selector(compare:)])
            [out addObject:@{@"id": path, @"name": path.lastPathComponent, @"help": Shown(path)}];
        [out addObject:@{@"id": @"own", @"name": @"Its own worktree", @"help": @"Until it has a folder"}];
        return out;
    };
    NSString *folder = AsText(option()[@"folder"]);
    BOOL gone = folder && !checkouts[folder];
    AppChoice *row = [AppChoice choiceWithKey:[NSString stringWithFormat:@"option:%@:%@", project, optionId]
                                        title:AsText(option()[@"name"]) ?: @"" choices:folders
                                       picked:^NSString * {
        // A folder that has gone is still the one kept, so none of the menu's choices is ticked, and Its Own Worktree
        // can be picked in its place.
        return AsText(option()[@"folder"]) ?: @"own";
    } pick:^(NSString *choice) {
        NSMutableDictionary *runs = [AsRecord(weakSelf.routes[project][@"runs"]) mutableCopy];
        NSMutableDictionary *all = [AsRecord(runs[@"folders"]) mutableCopy];
        if (!all[optionId]) return;
        all[optionId] = @{@"name": AsText(all[optionId][@"name"]) ?: @"",
                          @"folder": [choice isEqual:@"own"] ? NSNull.null : choice};
        runs[@"folders"] = all;
        [weakSelf set:runs of:project];
    }];
    row.menu = YES;
    row.fixed = @{@"name": row.title, @"help": gone
        ? [NSString stringWithFormat:@"%@ has gone: its tickets get their own worktree until you pick another", Shown(folder)]
        : folder ? Shown(folder) : @"Its own worktree for each ticket"};
    return row;
}

@end
