// DeployAsks: the deploys sessions have asked for, waiting in memory only, one per folder, and running them.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "DeployAsks.h"
#import "Deploys.h"
#import "Core.h"
#import "Rows.h"
#import "Allowed.h"
#import "PanelWindow.h"
#import "Row.h"
#import "Work.h"
#import "Git.h"
#import "Files.h"
#import "Log.h"

NSString *const kLetItDeploy = @"deploy";
// How long you must have been off the panel for an ask to run.
static const NSTimeInterval kOffThePanelFor = 5;

NSString *AskWaits(Row *row, NSArray<Row *> *rows, BOOL panelInUse, BOOL running) {
    if (running) return @"waits for the deploy running there now";
    // Whoever else is at work in the checkout, as a row that stands for it, no session's: a formatter, a rebase or
    // another agent's edits may be half-way through there. Not the asking session, though its turn goes on: it asks
    // once what it changed is ready, and changes nothing there after asking.
    Row *there = [[Row alloc] initWithFields:@{@"cwd": DeployFolder(row) ?: @""}];
    NSArray<Row *> *others = [rows filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(Row *other, NSDictionary *bindings) {
            return ![other.sessionId isEqual:row.sessionId];
        }]];
    NSString *agents = WhyStepsWait(there, others, @"waits");
    if (agents) return agents;
    if (panelInUse) return @"waits until you've stepped off the panel";
    return nil;
}

BOOL AskRestarts(NSDictionary *run) {
    return [run[@"running"] boolValue] && [run[@"up"] isKindOfClass:NSDictionary.class];
}

// How long an ask that stopped its checkout's build waits for it to have stopped before it's dropped: Stop Deploy gives
// what it stops 2 seconds, then ends it.
static const NSTimeInterval kStoppingFor = 20;

NSString *DeployCheckoutIn(NSString *folder, NSString *project, NSString **why) {
    NSString *name = folder.lastPathComponent;
    BOOL isFolder = NO;
    if (!folder.isAbsolutePath || ![NSFileManager.defaultManager fileExistsAtPath:folder isDirectory:&isFolder]
        || !isFolder) {
        if (why) *why = [NSString stringWithFormat:@"there's no folder at %@", Clip(folder, 120)];
        return nil;
    }
    NSDictionary *git = GitInfo(RealPath(folder));
    NSString *root = git[@"root"] ?: RealPath(folder), *of = git[@"mainRoot"] ?: root;
    if (!project || ![RealPath(of) isEqual:RealPath(project)]) {
        if (why) *why = [NSString stringWithFormat:@"%@ isn't a checkout of this session's project, %@", name,
                                                   project.lastPathComponent];
        return nil;
    }
    // A worktree, as the repo itself lists it: its .git file names a folder in the repo's worktrees, which names it
    // back. A folder whose .git only points at the repo isn't one of its checkouts.
    if (git[@"mainRoot"]) {
        NSString *dotGit = [root stringByAppendingPathComponent:@".git"];
        NSString *pointer = [NSString stringWithContentsOfFile:dotGit encoding:NSUTF8StringEncoding error:nil];
        NSRange tag = [pointer rangeOfString:@"gitdir:"];
        NSString *gitDir = tag.location == NSNotFound ? nil
            : [[pointer substringFromIndex:NSMaxRange(tag)]
                  stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (gitDir && !gitDir.isAbsolutePath) gitDir = [root stringByAppendingPathComponent:gitDir];
        NSString *back = gitDir ? [[NSString stringWithContentsOfFile:[gitDir stringByAppendingPathComponent:@"gitdir"]
                                                             encoding:NSUTF8StringEncoding error:nil]
                                    stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
                                 : nil;
        if (!back || ![RealPath(back) isEqual:RealPath(dotGit)]) {
            if (why) *why = [NSString stringWithFormat:@"%@ isn't one of %@'s worktrees, as its repo lists them", name,
                                                       project.lastPathComponent];
            return nil;
        }
    }
    return root;
}

NSString *SessionTitle(Row *row) {
    return Clip(row.name.length ? row.name : row.cwd.lastPathComponent ?: @"", 40);
}

@interface DeployAsks ()
@property (weak) Core *core;
@property (strong) Deploys *deploys;
// By folder: {sessionId, pid (the session's own process it was asked from), by, at (ms), waits}.
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *waiting;
@property (copy) NSDictionary<NSString *, NSString *> *decided;
@end

@implementation DeployAsks

- (instancetype)initWithCore:(Core *)core deploys:(Deploys *)deploys {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.deploys = deploys;
    self.waiting = [NSMutableDictionary dictionary];
    return self;
}

- (NSArray<Row *> *)rows {
    return self.core.rows.byId.allValues ?: @[];
}

// The checkout an ask is about: the session's own, the one its row is about, whether it's named or not. Its row is
// where the ask shows while it waits, with Not This Time, so any other checkout is refused, with `elsewhere` as why.
- (NSString *)folderOf:(Row *)row named:(NSString *)named elsewhere:(NSString *)elsewhere why:(NSString **)why {
    NSString *own = DeployFolder(row);
    if (!named) return own;
    NSString *folder = DeployCheckoutIn(named, DeployProject(row), why);
    if (!folder) return nil;
    if (!own || ![RealPath(folder) isEqual:RealPath(own)]) {
        if (why) *why = elsewhere;
        return nil;
    }
    return own;
}

// The switch being on for the row already says its project's command is the one it was turned on for.
- (NSString *)ask:(Row *)row from:(pid_t)process folder:(NSString *)named {
    NSString *why = nil, *command = [self.deploys commandFor:row];
    NSString *folder = [self folderOf:row named:named
                            elsewhere:@"Deploy can only be asked for in this session's own checkout" why:&why];
    // Logged here, never by the core (logsItself), so its lines are Deploy's own, saying the folder and who asked.
    if (!folder) {
        why = why ?: @"this session isn't in a project";
        PanelLog(@"deploy asked for by %@: refused, as %@", row.sessionId, why);
        return [@"refused: " stringByAppendingString:why];
    }
    if (!command) {
        PanelLog(@"deploy in %@ asked by “%@”: refused, as its project's Deploy isn't set up", folder,
                 SessionTitle(row));
        return @"refused: this project's Deploy isn't set up";
    }
    self.waiting[folder] = @{@"sessionId": row.sessionId, @"pid": @(process), @"by": SessionTitle(row),
                             @"at": @(floor(NSDate.date.timeIntervalSince1970 * 1000))};
    PanelLog(@"deploy in %@ asked by “%@”: kept", folder, SessionTitle(row));
    [self tick];
    // The answer goes into the session's conversation, and so wherever that is sent, so it names the project and
    // folder (the folder only when it's another checkout than the project's own), never the command's words, which
    // may carry a token.
    NSString *project = DeployProject(row).lastPathComponent, *name = folder.lastPathComponent;
    NSString *where = [name isEqualToString:project] ? project : [NSString stringWithFormat:@"%@ in %@", project, name];
    // Its build up already: restarted, so the reply says so.
    NSString *does = AskRestarts([self.deploys runIn:folder])
        ? [NSString stringWithFormat:@"Deploy restarts the build of %@ that's up, running the command you confirmed "
                                     @"again,", where]
        : [NSString stringWithFormat:@"Deploy runs the command you confirmed for %@", where];
    return [NSString stringWithFormat:@"asked: %@ once no other agent is at work there and you've stepped off the "
                                      @"panel, without waiting for your turn to end, so change nothing there until it "
                                      @"has run; ask for status to see how it went", does];
}

- (NSString *)status:(Row *)row folder:(NSString *)named {
    NSString *why = nil;
    NSString *folder = [self folderOf:row named:named
                            elsewhere:@"Deploy's status is only for this session's own checkout" why:&why];
    // Logged here, as the answer can quote the run's last line, which a command that prints a token would carry.
    if (!folder) {
        why = why ?: @"this session isn't in a project";
        PanelLog(@"deploy status asked for by %@: refused, as %@", row.sessionId, why);
        return [@"refused: " stringByAppendingString:why];
    }
    PanelLog(@"deploy in %@: status asked by “%@”", folder, SessionTitle(row));
    NSDictionary *asked = folder ? self.waiting[folder] : nil, *run = [self.deploys runIn:folder];
    if (asked) return [NSString stringWithFormat:@"status: asked by “%@”, it %@", asked[@"by"],
                                                 asked[@"waits"] ?: @"runs now"];
    // Its port held when it would have run, by a server that picks its own port or one confirmed before ports: it
    // waits on the card for you. Only the port is said, never what holds it.
    NSDictionary *card = [self.deploys cardIn:folder];
    if (AsText(card[@"asked"]) && card[@"port"])
        return [NSString stringWithFormat:@"status: asked by “%@”, it waits on its card for you, as port %@ is in use "
                                          @"and this server can't take another", card[@"asked"], card[@"port"]];
    if (!run) return @"status: no deploy has run here yet";
    NSString *by = AsText(run[@"by"]) ? [NSString stringWithFormat:@" (asked by “%@”)", run[@"by"]] : @"";
    if ([run[@"running"] boolValue]) {
        // The port it's up on, and when an ask took the next free one, the one it took it in place of.
        NSNumber *port = run[@"up"][@"port"];
        NSDictionary *moved = [self.deploys movedIn:folder];
        NSString *on = !port ? @""
            : [moved[@"port"] isEqual:port] && [moved[@"port"] isEqual:run[@"port"]]
            ? [NSString stringWithFormat:@", up on port %@, the next free one, as %@ was in use; it keeps %@ from now on",
                                         port, moved[@"from"], port]
            : [NSString stringWithFormat:@", up on port %@", port];
        return [NSString stringWithFormat:@"status: running%@%@", by, on];
    }
    if ([run[@"stopped"] boolValue]) return [@"status: the last deploy here was stopped" stringByAppendingString:by];
    if ([run[@"ok"] boolValue]) return [@"status: the last deploy here went through" stringByAppendingString:by];
    return [NSString stringWithFormat:@"status: the last deploy here didn't go through%@: %@", by,
                                      AsText(run[@"lastLine"]) ?: @""];
}

- (void)tick {
    if (!self.waiting.count) {
        [self.deploys showAsked:@{}];
        return;
    }
    NSMutableDictionary<NSString *, NSString *> *decided = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSDictionary *> *shown = [NSMutableDictionary dictionary];
    BOOL inUse = !self.core.printing && [self.core.window inUseWithin:kOffThePanelFor];
    for (NSString *folder in self.waiting.allKeys) {
        NSDictionary *ask = self.waiting[folder], *run = [self.deploys runIn:folder];
        Row *row = self.core.rows.byId[ask[@"sessionId"]];
        // A deploy that started after it was asked for, pressed or asked again, has done what it asked.
        NSString *gone = [run[@"startedAt"] doubleValue] > [ask[@"at"] doubleValue] ? @"a deploy ran there since"
            : !row ? @"its session isn't listed any more"
            : ![folder isEqual:DeployFolder(row)] ? @"its session's row is about another checkout now"
            : [self.core.allowed whyOff:kLetItDeploy for:row from:[ask[@"pid"] intValue]];
        if (gone) {
            PanelLog(@"deploy in %@ asked by %@: dropped, as %@", folder, ask[@"by"], gone);
            decided[folder] = [@"dropped, as " stringByAppendingString:gone];
            [self.waiting removeObjectForKey:folder];
            continue;
        }
        // Its own build up (a server, which runs till you stop it): restarted rather than waited on. Once nothing
        // else holds it up, Stop Deploy stops it and the ask stays, saying so, until the build has stopped; then it
        // runs as any ask does, with every wait checked again here. Anything else still running there is waited on.
        BOOL restart = AskRestarts(run), running = [run[@"running"] boolValue];
        NSNumber *stopping = ask[@"stoppingAt"];
        if (stopping && running && NSDate.date.timeIntervalSince1970 - stopping.doubleValue > kStoppingFor) {
            PanelLog(@"deploy in %@ asked by %@: dropped, as its build there didn't stop", folder, ask[@"by"]);
            decided[folder] = @"dropped, as its build there didn't stop";
            [self.waiting removeObjectForKey:folder];
            continue;
        }
        NSString *waits = stopping && running ? @"waits for its build there to stop"
            : AskWaits(row, self.rows, inUse, running && !restart);
        if (!waits && restart) {
            NSMutableDictionary *now = [ask mutableCopy];
            now[@"stoppingAt"] = @(NSDate.date.timeIntervalSince1970);
            now[@"waits"] = @"waits for its build there to stop";
            self.waiting[folder] = now;
            shown[folder] = @{@"by": ask[@"by"], @"waits": now[@"waits"], @"restart": @YES};
            decided[folder] = @"stops its build now, to restart it";
            if (self.core.printing) continue;
            PanelLog(@"deploy in %@ asked by %@: stops its build, which is up, to restart it", folder, ask[@"by"]);
            [self.deploys stop:row];
            continue;
        }
        if (waits) {
            NSMutableDictionary *now = [ask mutableCopy];
            now[@"waits"] = waits;
            self.waiting[folder] = now;
            shown[folder] = @{@"by": ask[@"by"], @"waits": waits, @"restart": @(restart || stopping != nil)};
            decided[folder] = waits;
            continue;
        }
        [self.waiting removeObjectForKey:folder];
        decided[folder] = @"would run now";
        if (!self.core.printing)
            [self.deploys deployAsked:row in:folder expecting:[self.deploys commandFor:row] by:ask[@"by"]];
    }
    self.decided = decided;
    [self.deploys showAsked:shown];
}

- (NSDictionary *)askedIn:(NSString *)folder {
    return folder ? self.waiting[folder] : nil;
}

- (void)dropIn:(NSString *)folder {
    if (!folder || !self.waiting[folder]) return;
    PanelLog(@"deploy in %@ asked by %@: dropped, Not This Time", folder, self.waiting[folder][@"by"]);
    [self.waiting removeObjectForKey:folder];
    self.decided = @{folder: @"dropped: Not This Time"};
    [self tick];
}

- (void)dropFrom:(NSString *)sessionId {
    NSMutableDictionary *decided = [NSMutableDictionary dictionary];
    for (NSString *folder in self.waiting.allKeys) {
        if (![self.waiting[folder][@"sessionId"] isEqual:sessionId]) continue;
        PanelLog(@"deploy in %@ asked by %@: dropped, as Let It Deploy went off", folder, self.waiting[folder][@"by"]);
        [self.waiting removeObjectForKey:folder];
        decided[folder] = @"dropped, as Let It Deploy went off for its session";
    }
    self.decided = decided;
    [self tick];
}

@end
