// Stages: a checkout's extra stage, between your edits and your commits on its row's island. A command the checkout's
// own git config names (whozmove.stage) says what the stage holds and what can be done with it; Whozmove runs it only
// once you've allowed it in the panel, and asks again whenever it changes (docs/reference/stages.md).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// Whozmove runs the command itself, every time it reads the checkout, outside Claude Code's permissions, so what it
// runs is yours to allow: the answer is kept in stages.json in Whozmove's own folder, never in the project, against
// the exact command. A repo's local config isn't cloned or pushed, and git already runs what that file names.
#import "Stages.h"
#import "Work.h"
#import "Checkouts.h"
#import "Core.h"
#import "Page.h"
#import "Row.h"
#import "Log.h"
#import "Files.h"
#import "Git.h"
#import "Processes.h"
#import "Text.h"

#pragma mark Running a command

// The command a checkout's own git config names for its extra stage (whozmove.stage, shared by all its worktrees),
// trimmed, or nil. The config is the repo's local one, which is never cloned or pushed. Blocking.
static NSString *FetchStageCommand(NSString *root) {
    NSDictionary *run = RunTool(@"/usr/bin/git", @[@"--no-optional-locks", @"-C", root, @"config", @"--local", @"--get",
                                                   @"whozmove.stage"], nil);
    if (!run || [run[@"status"] intValue] != 0) return nil;
    NSString *command = [[[NSString alloc] initWithData:run[@"out"] encoding:NSUTF8StringEncoding]
                         stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return command.length ? command : nil;
}

// Text the command gave, for one line of the panel or a menu: control characters (newlines among them) become spaces,
// and it's cut at `max`. Nil for anything but text, or text that's left empty.
static NSString *Line(id value, NSUInteger max) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *text = [[[value componentsSeparatedByCharactersInSet:NSCharacterSet.controlCharacterSet]
                       componentsJoinedByString:@" "]
                      stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    return text.length ? Clip(text, max) : nil;
}

// A whole number from 0 to a million, and not true or false (which JSON numbers also read as).
static BOOL IsCount(id value) {
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID())
        return NO;
    double number = [value doubleValue];
    return number == floor(number) && number >= 0 && number <= 1e6;
}

// The files outside the stage it names (editFiles), each by its path from the top of the checkout, or nil: only when
// they're all the files it counts there (edits), so they can be split as git sees them and add up to its count (the
// files stage's gauge, SplitNamed in Checkouts.m). A name that isn't one line of plain text isn't taken, and nor is
// the list then. Up to 1,000.
static NSArray<NSString *> *NamedEdits(id given, NSNumber *edits) {
    if (![given isKindOfClass:NSArray.class] || !edits || [given count] > 1000) return nil;
    NSMutableOrderedSet<NSString *> *named = [NSMutableOrderedSet orderedSet];
    for (id path in given) {
        BOOL plain = [path isKindOfClass:NSString.class] && [path length] && [path length] <= 1024
            && [path rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location == NSNotFound;
        if (!plain) return nil;
        [named addObject:path];
    }
    return named.count == edits.unsignedIntegerValue ? named.array : nil;
}

// What the command printed, checked: a JSON object with at least a count, and only the fields of the right kinds and
// sizes kept (docs/reference/stages.md says which). {stage, menu, named}, or {problem}.
static NSDictionary *ParseStage(NSData *out) {
    id json = out.length ? [NSJSONSerialization JSONObjectWithData:out options:0 error:nil] : nil;
    if (![json isKindOfClass:NSDictionary.class]) return @{@"problem": @"its command didn't print a JSON object"};
    if (!IsCount(json[@"count"])) return @{@"problem": @"its JSON has no count, a whole number from 0"};
    NSMutableDictionary *stage = [@{@"count": @([json[@"count"] integerValue])} mutableCopy];
    if (Line(json[@"label"], 24)) stage[@"label"] = Line(json[@"label"], 24);
    if (IsCount(json[@"edits"])) stage[@"edits"] = @([json[@"edits"] integerValue]);
    NSArray<NSString *> *named = NamedEdits(json[@"editFiles"], stage[@"edits"]);
    NSMutableDictionary *menu = [NSMutableDictionary dictionary];
    if (Line(json[@"header"], 80)) menu[@"header"] = Line(json[@"header"], 80);
    NSArray *given = [json[@"items"] isKindOfClass:NSArray.class] ? json[@"items"] : @[];
    NSMutableArray *items = [NSMutableArray array];
    NSUInteger shown = 0;  // the items that are text, all of them, so "and N more" counts only what's left out
    for (id item in given) {
        NSString *line = Line(item, 80);
        if (!line) continue;
        shown++;
        if (items.count < 10) [items addObject:line];
    }
    menu[@"items"] = items;
    if (shown > items.count) menu[@"more"] = @(shown - items.count);
    NSMutableArray *actions = [NSMutableArray array];
    for (id action in [json[@"actions"] isKindOfClass:NSArray.class] ? json[@"actions"] : @[]) {
        if (actions.count >= 8 || ![action isKindOfClass:NSDictionary.class]) continue;
        NSString *title = Line(action[@"title"], 40), *ask = Line(action[@"ask"], NSUIntegerMax);
        // A command runs as it's written, so one over a line long isn't taken rather than joined into one.
        BOOL oneLine = [action[@"run"] isKindOfClass:NSString.class] &&
            [action[@"run"] rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location == NSNotFound &&
            [action[@"run"] length] <= 1000;
        NSString *run = oneLine ? Line(action[@"run"], 1000) : nil;
        if (!title || (!run) == (!ask)) continue;  // each either runs a command or asks the agent
        // Words for the agent go in whole or not at all, as cut short they could leave out what they ask; and only as
        // words: ones starting the way Claude Code's own commands do (/ a command, ! its shell, # its memory) would run
        // as those, a /model saving a new default for every session.
        if (ask && (ask.length > 300 || [@[@"/", @"!", @"#"] containsObject:[ask substringToIndex:1]])) continue;
        NSMutableDictionary *kept = [@{@"title": title} mutableCopy];
        if (run) kept[@"run"] = run;
        else kept[@"ask"] = ask;
        if ([action[@"in"] isEqual:@"edits"]) kept[@"in"] = @"edits";
        [actions addObject:kept];
    }
    menu[@"actions"] = actions;
    return named ? @{@"stage": stage, @"menu": menu, @"named": named} : @{@"stage": stage, @"menu": menu};
}

#pragma mark What you've allowed

// Your answers, by project (its real folder): {projects: {project: {command, allowedAt} or {command, notNowAt}}}.
static NSMutableDictionary *ReadTrust(void) {
    NSDictionary *saved = ReadJSON(AppDir(@"stages.json"));
    id projects = [saved isKindOfClass:NSDictionary.class] ? saved[@"projects"] : nil;
    return [@{@"projects": [projects isKindOfClass:NSDictionary.class] ? [projects mutableCopy]
                                                                       : [NSMutableDictionary dictionary]} mutableCopy];
}

// Written whole at once, so a read on the checkouts' queue never finds half of it.
static void WriteTrust(NSDictionary *store) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:store
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:nil];
    [json writeToFile:AppDir(@"stages.json") atomically:YES];
}

NSDictionary *ReadStage(NSString *root, NSString *project, NSArray<NSString *> *marks) {
    NSString *command = FetchStageCommand(root);
    if (!command) return nil;
    // One line of plain text, as the card shows it whole: a line break, or a character that doesn't show or turns the
    // text around (which could make the card read differently from what runs), isn't taken.
    NSMutableCharacterSet *hidden = [NSCharacterSet.controlCharacterSet mutableCopy];
    [hidden formUnionWithCharacterSet:NSCharacterSet.newlineCharacterSet];
    if (command.length > 1000 || [command rangeOfCharacterFromSet:hidden].location != NSNotFound)
        return @{@"problem": @"whozmove.stage isn't one line of up to 1,000 plain characters"};
    NSDictionary *answer = ReadTrust()[@"projects"][RealPath(project)];
    if (![answer isKindOfClass:NSDictionary.class] || ![answer[@"command"] isEqual:command])
        return @{@"stage": @{@"ask": command}};
    if (!answer[@"allowedAt"]) return @{@"declined": command};
    NSDictionary *run = RunInCheckout(command, root, 3, NO, marks);
    if (!run) return @{@"problem": @"its command couldn't start"};
    if ([run[@"timedOut"] boolValue]) return @{@"slow": @YES, @"problem": @"its command took more than 3 seconds"};
    if ([run[@"status"] intValue] != 0)
        return @{@"problem": [NSString stringWithFormat:@"its command ended with status %@", run[@"status"]]};
    if ([run[@"clipped"] boolValue]) return @{@"problem": @"its command printed more than 64KB"};
    return ParseStage(run[@"out"]);
}

#pragma mark Answers and actions

static NSString *RootOf(Row *row) {
    return (row.workGit ?: row.git)[@"root"];
}

static NSString *ProjectOf(Row *row) {
    NSDictionary *git = row.workGit ?: row.git;
    return git[@"mainRoot"] ?: git[@"root"];
}

static NSNumber *Now(void) {
    return @(floor(NSDate.date.timeIntervalSince1970 * 1000));
}

// The last line a command printed with something on it, without colour codes, or nil.
static NSString *LastLine(NSData *out) {
    NSString *text = [[NSString alloc] initWithData:out ?: NSData.data encoding:NSUTF8StringEncoding] ?: @"";
    text = WithoutColours(text);
    NSString *last = nil;
    for (NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (trimmed.length) last = trimmed;
    }
    return last;
}

// Why an action can't run from this row now, or nil: as with Deploy, it waits while the agent works, asks something
// or compacts, so it never acts on files half-way through a change.
static NSString *WhyNotRunNow(Row *row) {
    return AgentAtWork(row) ? @"This waits until the agent is done" : nil;
}

@interface Stages ()
@property (weak) Core *core;
@property (strong) Checkouts *checkouts;
@property (strong) dispatch_queue_t queue;    // writes to stages.json
// Actions run side by side across checkouts (one at a time in each: `running`), so one starts as it's picked, while
// its agent is still idle, rather than waiting behind another checkout's.
@property (strong) dispatch_queue_t actions;
@property (strong) NSMutableDictionary<NSString *, NSString *> *running;  // checkout -> title; main thread only
@end

@implementation Stages

- (instancetype)initWithCore:(Core *)core checkouts:(Checkouts *)checkouts {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.checkouts = checkouts;
    self.queue = dispatch_queue_create("whozmove.stages", DISPATCH_QUEUE_SERIAL);
    self.actions = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    self.running = [NSMutableDictionary dictionary];
    return self;
}

// Keeps (or with nil forgets) your answer for a project, then has its checkout read again soon, so the row shows the
// answer's effect within a second or two.
- (void)keep:(NSDictionary *(^)(NSDictionary *before))answer for:(Row *)row {
    NSString *root = RootOf(row), *project = ProjectOf(row);
    if (!root || !project) return;
    dispatch_async(self.queue, ^{
        NSMutableDictionary *store = ReadTrust();
        NSString *key = RealPath(project);
        NSDictionary *before = [store[@"projects"][key] isKindOfClass:NSDictionary.class] ? store[@"projects"][key] : nil;
        NSDictionary *after = answer(before);
        if (after) store[@"projects"][key] = after;
        else [store[@"projects"] removeObjectForKey:key];
        WriteTrust(store);
        PanelLog(@"extra stage for %@: %@", project, after ?: @"forgotten");
        dispatch_async(dispatch_get_main_queue(), ^{ [self.checkouts readSoon:root]; });
    });
}

- (void)trust:(NSDictionary *)msg row:(Row *)row {
    NSString *command = msg[@"command"], *root = RootOf(row);
    if (![command isKindOfClass:NSString.class] || !root) return;
    // Only the command the card showed is answered for: one changed since is asked about afresh.
    if (![[self.checkouts stateOf:root][@"stage"][@"ask"] isEqual:command]) {
        PanelLog(@"extra stage in %@: an answer for a command that's no longer set, ignored", root);
        return;
    }
    BOOL allow = [msg[@"allow"] boolValue];
    [self keep:^NSDictionary *(NSDictionary *before) {
        return @{@"command": command, (allow ? @"allowedAt" : @"notNowAt"): Now()};
    } for:row];
}

- (void)stop:(Row *)row {
    [self keep:^NSDictionary *(NSDictionary *before) {
        return before[@"command"] ? @{@"command": before[@"command"], @"notNowAt": Now()} : before;
    } for:row];
}

- (void)askAgain:(Row *)row {
    [self keep:^NSDictionary *(NSDictionary *before) { return nil; } for:row];
}

- (NSString *)runningIn:(NSString *)root {
    return root ? self.running[root] : nil;
}

// Runs the action's command from the checkout (RunInCheckout, for 30 seconds at most), and says on the row how it
// went: its last line when it worked, quietly; why when it didn't. The checkout is read again straight after.
- (void)run:(NSDictionary *)action row:(Row *)row {
    NSString *root = RootOf(row), *sid = row.sessionId, *title = action[@"title"], *command = action[@"run"];
    if (!root || ![command isKindOfClass:NSString.class] || ![title isKindOfClass:NSString.class]) return;
    NSString *why = WhyNotRunNow(row)
        ?: self.running[root] ? [NSString stringWithFormat:@"Still running: %@", self.running[root]] : nil;
    if (why) {
        [self.core.page stepNote:sid text:why quiet:NO];
        return;
    }
    self.running[root] = title;
    [self.core.page stepNote:sid text:[title stringByAppendingString:@"…"] quiet:YES];
    PanelLog(@"extra stage action in %@: %@", root, command);
    NSArray<NSString *> *marks = self.core.agentMarks;
    dispatch_async(self.actions, ^{
        NSDictionary *result = RunInCheckout(command, root, 30, YES, marks);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.running removeObjectForKey:root];
            NSString *line = LastLine(result[@"out"]);
            BOOL ok = result && ![result[@"timedOut"] boolValue] && [result[@"status"] intValue] == 0;
            NSString *note = !result ? [NSString stringWithFormat:@"Couldn't start %@", title]
                : [result[@"timedOut"] boolValue] ? [NSString stringWithFormat:@"%@ took too long, so it was stopped",
                                                                              title]
                : ok ? line ?: [title stringByAppendingString:@": done"]
                : [NSString stringWithFormat:@"%@ didn't go through: %@", title,
                   line ?: [NSString stringWithFormat:@"it ended with status %@", result[@"status"]]];
            PanelLog(@"extra stage action in %@: %@", root, note);
            [self.core.page stepNote:sid text:Clip(note, 200) quiet:ok];
            [self.checkouts readSoon:root];
        });
    });
}

@end
