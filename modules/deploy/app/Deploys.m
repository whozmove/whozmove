// Deploys: Deploy, a next step for any project: the command you've set for each project, the one Whozmove suggests
// before you have, running it on this Mac, and how each folder's last run went.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// What Deploy runs is yours to say, once per project: the panel suggests a command from the project's own files, and
// you confirm it twice before it's saved (in deploy.json in Whozmove's own folder, never in the project, so nothing a
// repo or an agent writes can set it). Each run goes detached from the panel, with its output in a log and its exit
// status in a file beside it, under deploys/<folder's hash>/, so it carries on if it restarts the panel (as Whozmove's
// own deploy does), and the panel reads how it went whenever it looks.
#import "Deploys.h"
#import "Page.h"
#import "Row.h"
#import "Log.h"
#import "Files.h"
#import "Processes.h"
#import "Text.h"
#import "Work.h"
#include <signal.h>
#include <stdlib.h>
#include <unistd.h>

NSString *DeployProject(Row *row) {
    NSDictionary *git = row.workGit ?: row.git;
    return git[@"mainRoot"] ?: git[@"root"] ?: row.cwd;
}

NSString *DeployFolder(Row *row) {
    NSDictionary *git = row.workGit ?: row.git;
    return git[@"root"] ?: row.cwd;
}

#pragma mark What a command runs

// Whether text looks as if it could reach production: it names prod or production, or it's a deploy tool's command
// for a live site, a cluster, infrastructure, or a push. The one list: Whozmove never suggests a command that does
// (SuggestDeploy), and the set-up card asks the app (CheckDeploy) before it warns about one.
static BOOL LooksLikeProduction(NSString *text) {
    static NSArray<NSRegularExpression *> *patterns;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *compiled = [NSMutableArray array];
        for (NSString *pattern in @[@"(?i)\\bprod(uction)?\\b", @"\\bfly(ctl)?\\s+deploy\\b",
                                    @"\\bvercel\\b.*--prod\\b", @"\\bnetlify\\s+deploy\\b.*--prod\\b", @"\\bheroku\\b",
                                    @"\\b(kubectl|helm|terraform)\\b", @"\\bgit\\s+push\\b"])
            [compiled addObject:[NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil]];
        patterns = compiled;
    });
    for (NSRegularExpression *pattern in patterns)
        if (text.length && [pattern firstMatchInString:text options:0 range:NSMakeRange(0, text.length)]) return YES;
    return NO;
}

// A Makefile's rules, as far as what a target runs goes: {target: {deps, recipe}}, with the first target (the one
// make runs when it's given none) under @"". Lines continued with a backslash are read as one; a recipe line is one
// starting with a tab after a rule, or what follows a ";" on the rule's own line. No variables, includes or patterns.
static NSDictionary<NSString *, NSDictionary *> *MakeRules(NSString *makefile) {
    NSString *text = [makefile stringByReplacingOccurrencesOfString:@"\\\n" withString:@" "];
    NSRegularExpression *rule = [NSRegularExpression
        regularExpressionWithPattern:@"^([^\\s#:=][^#:=]*?)\\s*::?(?!=)([^;#]*)(?:;(.*)|#.*)?$" options:0 error:nil];
    NSMutableDictionary<NSString *, NSMutableDictionary *> *rules = [NSMutableDictionary dictionary];
    NSArray<NSString *> *current = nil;
    NSString *first = nil;
    NSCharacterSet *space = NSCharacterSet.whitespaceCharacterSet;
    void (^add)(NSArray<NSString *> *, NSString *) = ^(NSArray<NSString *> *targets, NSString *line) {
        line = [line stringByTrimmingCharactersInSet:space];
        if (line.length) for (NSString *target in targets) [rules[target][@"recipe"] addObject:line];
    };
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:@"\t"]) {
            if (current) add(current, line);
            continue;
        }
        NSString *trimmed = [line stringByTrimmingCharactersInSet:space];
        if (!trimmed.length || [trimmed hasPrefix:@"#"]) continue;  // a recipe goes on past these
        NSTextCheckingResult *match = [rule firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        if (!match) {
            current = nil;  // a variable, a directive: the recipe before it has ended
            continue;
        }
        NSPredicate *named = [NSPredicate predicateWithFormat:@"length > 0"];
        NSArray<NSString *> *targets = [[[line substringWithRange:[match rangeAtIndex:1]]
                                         componentsSeparatedByCharactersInSet:space] filteredArrayUsingPredicate:named];
        NSArray<NSString *> *deps = [[[line substringWithRange:[match rangeAtIndex:2]]
                                      componentsSeparatedByCharactersInSet:space] filteredArrayUsingPredicate:named];
        for (NSString *target in targets) {
            rules[target] = rules[target] ?: [@{@"deps": [NSMutableArray array], @"recipe": [NSMutableArray array]}
                                              mutableCopy];
            [rules[target][@"deps"] addObjectsFromArray:deps];
            if (!first && ![target hasPrefix:@"."]) first = target;
        }
        current = targets;
        NSRange sameLine = [match rangeAtIndex:3];  // a recipe after ";"
        if (sameLine.location != NSNotFound) add(targets, [line substringWithRange:sameLine]);
    }
    if (first) rules[@""] = rules[first];
    return rules;
}

// A target's recipe lines, after those of the targets it depends on (as make runs them), each target once.
static void AddRecipe(NSDictionary<NSString *, NSDictionary *> *rules, NSString *target, NSMutableSet *seen,
                      NSMutableArray<NSString *> *runs, NSUInteger depth) {
    NSDictionary *found = rules[target];
    if (!found || depth > 10 || [seen containsObject:target]) return;
    [seen addObject:target];
    for (NSString *dep in found[@"deps"]) AddRecipe(rules, dep, seen, runs, depth + 1);
    [runs addObjectsFromArray:found[@"recipe"]];
}

// What a command really runs, where it names package scripts (npm, pnpm, yarn or bun) or Makefile targets: each
// script (with npm's pre- and post- ones), or each target's recipe after those of the targets it depends on, one line
// each, in the order they'd run. Nil when it names neither. Commands are split at && || ; | and words at spaces, after
// any VAR=value words, which is as far as a deploy command needs reading. Blocking: it reads the project's files.
static NSString *ScriptRuns(NSString *folder, NSString *command) {
    NSDictionary *package = ReadJSON([folder stringByAppendingPathComponent:@"package.json"]);
    NSDictionary *scripts = [package isKindOfClass:NSDictionary.class]
        && [package[@"scripts"] isKindOfClass:NSDictionary.class] ? package[@"scripts"] : @{};
    NSDictionary<NSString *, NSDictionary *> *rules = nil;
    NSMutableArray<NSString *> *runs = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSRegularExpression *split = [NSRegularExpression regularExpressionWithPattern:@"&&|\\|\\||[;|&\\n]" options:0
                                                                             error:nil];
    NSString *marked = [split stringByReplacingMatchesInString:command ?: @"" options:0
                                                         range:NSMakeRange(0, command.length) withTemplate:@"\n"];
    for (NSString *segment in [marked componentsSeparatedByString:@"\n"]) {
        NSMutableArray<NSString *> *words = [[[segment componentsSeparatedByCharactersInSet:NSCharacterSet
            .whitespaceCharacterSet] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]]
            mutableCopy];
        while (words.count && [words[0] rangeOfString:@"^[A-Za-z_][A-Za-z0-9_]*=" options:NSRegularExpressionSearch]
                                  .location != NSNotFound)
            [words removeObjectAtIndex:0];
        if (!words.count) continue;
        NSString *tool = words[0].lastPathComponent;
        if ([@[@"npm", @"pnpm", @"yarn", @"bun"] containsObject:tool] && words.count > 1) {
            // `npm run x`, `yarn x`: the name after run (npm and bun need it), past any options.
            BOOL run = [@[@"run", @"run-script"] containsObject:words[1]];
            NSUInteger at = run ? 2 : [@[@"yarn", @"pnpm"] containsObject:tool] ? 1 : words.count;
            while (at < words.count && [words[at] hasPrefix:@"-"]) at++;
            NSString *name = at < words.count ? words[at] : nil;
            if (![scripts[name] isKindOfClass:NSString.class]) continue;
            NSArray *names = [tool isEqual:@"npm"] ? @[[@"pre" stringByAppendingString:name], name,
                                                       [@"post" stringByAppendingString:name]] : @[name];
            for (NSString *each in names)
                if ([scripts[each] isKindOfClass:NSString.class]) [runs addObject:scripts[each]];
        } else if ([@[@"make", @"gmake"] containsObject:tool]) {
            rules = rules ?: MakeRules([NSString stringWithContentsOfFile:[folder stringByAppendingPathComponent:
                                         @"Makefile"] encoding:NSUTF8StringEncoding error:nil] ?: @"");
            NSArray *targets = [[words subarrayWithRange:NSMakeRange(1, words.count - 1)] filteredArrayUsingPredicate:
                [NSPredicate predicateWithFormat:@"NOT (SELF BEGINSWITH '-') AND NOT (SELF CONTAINS '=')"]];
            for (NSString *target in targets.count ? targets : @[@""]) AddRecipe(rules, target, seen, runs, 0);
        }
    }
    return runs.count ? [runs componentsJoinedByString:@"\n"] : nil;
}

NSDictionary *CheckDeploy(NSString *folder, NSString *command) {
    NSString *runs = folder.length ? ScriptRuns(folder, command) : nil;
    NSMutableDictionary *check = [@{@"command": command ?: @"", @"production":
        LooksLikeProduction(command) || LooksLikeProduction(runs) ? @YES : @NO} mutableCopy];
    // As much of it as the card has room for.
    if (runs.length) {
        NSArray<NSString *> *lines = [runs componentsSeparatedByString:@"\n"];
        NSString *shown = [[lines subarrayWithRange:NSMakeRange(0, MIN(lines.count, (NSUInteger)12))]
                           componentsJoinedByString:@"\n"];
        check[@"runs"] = Clip(shown, 1000);
        if (lines.count > 12) check[@"more"] = @(lines.count - 12);
    }
    return check;
}

#pragma mark Suggestions

// The command a project's own files point to for putting it in place on this Mac, the first that fits: Whozmove's own
// build, a Compose file, a pm2 file, a package script or Makefile target named for a local install, a package with
// commands to install, a Rust binary, a Go program, a Python package with scripts. Only commands that do their job and
// finish, and none that looks as if it could reach production, by what it really runs (CheckDeploy). Nil when none
// fits: then the project gets no Deploy.
NSString *SuggestDeploy(NSString *folder) {
    if (!folder.length) return nil;
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL (^has)(NSString *) = ^BOOL(NSString *name) {
        return [fm fileExistsAtPath:[folder stringByAppendingPathComponent:name]];
    };
    NSString *(^read)(NSString *) = ^NSString *(NSString *name) {
        return [NSString stringWithContentsOfFile:[folder stringByAppendingPathComponent:name]
                                         encoding:NSUTF8StringEncoding error:nil];
    };
    BOOL (^local)(NSString *) = ^BOOL(NSString *command) {
        return ![CheckDeploy(folder, command)[@"production"] boolValue];
    };
    if (has(@"build.sh") && has(@"app/swap-in.sh")) return @"./build.sh --now";  // Whozmove itself
    for (NSString *compose in @[@"compose.yaml", @"compose.yml", @"docker-compose.yaml", @"docker-compose.yml"])
        if (has(compose)) return @"docker compose up -d --build";
    for (NSString *pm2 in @[@"ecosystem.config.js", @"ecosystem.config.cjs"])
        if (has(pm2)) return [@"pm2 startOrReload " stringByAppendingString:pm2];
    NSDictionary *package = ReadJSON([folder stringByAppendingPathComponent:@"package.json"]);
    if ([package isKindOfClass:NSDictionary.class]) {
        NSString *runner = has(@"pnpm-lock.yaml") ? @"pnpm" : has(@"yarn.lock") ? @"yarn"
                         : has(@"bun.lockb") || has(@"bun.lock") ? @"bun" : @"npm";
        NSDictionary *scripts = [package[@"scripts"] isKindOfClass:NSDictionary.class] ? package[@"scripts"] : @{};
        for (NSString *name in @[@"deploy:local", @"install:local"]) {
            NSString *command = [NSString stringWithFormat:@"%@ run %@", runner, name];
            if ([scripts[name] isKindOfClass:NSString.class] && local(command)) return command;
        }
    }
    NSString *makefile = read(@"Makefile");
    NSDictionary *rules = makefile ? MakeRules(makefile) : @{};
    for (NSString *target in @[@"install", @"deploy-local"]) {
        NSString *command = [@"make " stringByAppendingString:target];
        if (rules[target] && local(command)) return command;
    }
    if ([package isKindOfClass:NSDictionary.class] && package[@"bin"]) return @"npm install -g .";
    if (has(@"Cargo.toml") && (has(@"src/main.rs") || [read(@"Cargo.toml") containsString:@"[[bin]]"]))
        return @"cargo install --path .";
    if (has(@"go.mod") && (has(@"main.go") || has(@"cmd"))) return @"go install ./...";
    if ([read(@"pyproject.toml") containsString:@"[project.scripts]"]) return @"pipx install --force .";
    return nil;
}

#pragma mark Where things are kept

// The commands you've saved, by project, and each folder's last deploy and skip: {projects: {project: {command,
// savedAt}}, folders: {folder: {at, skippedAt}}}. Read and written on the queue only.
static NSMutableDictionary *ReadStore(void) {
    NSDictionary *saved = ReadJSON(AppDir(@"deploy.json"));
    NSMutableDictionary *store = [NSMutableDictionary dictionary];
    for (NSString *part in @[@"projects", @"folders"]) {
        id kept = [saved isKindOfClass:NSDictionary.class] ? saved[part] : nil;
        store[part] = [kept isKindOfClass:NSDictionary.class] ? [kept mutableCopy] : [NSMutableDictionary dictionary];
    }
    return store;
}

// The command saved for a project, or nil. Projects are saved by their real folder.
static NSString *SavedCommand(NSDictionary *store, NSString *project) {
    if (!project) return nil;
    NSDictionary *saved = store[@"projects"][RealPath(project)];
    if ([saved isKindOfClass:NSDictionary.class] && [saved[@"command"] isKindOfClass:NSString.class])
        return saved[@"command"];
    return nil;
}

static void WriteStore(NSDictionary *store) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:store
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:nil];
    [json writeToFile:AppDir(@"deploy.json") atomically:YES];
}

// The folder a folder's runs are kept in: deploys/<16 hex digits of its path's FNV-1a hash>.
static NSString *RunDir(NSString *folder) {
    return AppDir([NSString stringWithFormat:@"deploys/%016llx", HashBytes(folder.fileSystemRepresentation)]);
}

// The end of a run's log, its last 4KB, read from there: a long log isn't read whole every couple of seconds.
static NSString *LogTail(NSString *path) {
    NSFileHandle *file = [NSFileHandle fileHandleForReadingAtPath:path];
    unsigned long long size = 0;
    if (!file || ![file seekToEndReturningOffset:&size error:nil]) return @"";
    unsigned long long from = size > 4096 ? size - 4096 : 0;
    NSData *tail = [file seekToOffset:from error:nil] ? [file readDataToEndOfFileAndReturnError:nil] : nil;
    [file closeAndReturnError:nil];
    // Starting part-way through a letter, the bytes before the next whole one are left out, or none of it decodes.
    const uint8_t *bytes = tail.bytes;
    NSUInteger skip = 0;
    while (from > 0 && skip < tail.length && (bytes[skip] & 0xC0) == 0x80) skip++;
    NSData *whole = [tail subdataWithRange:NSMakeRange(skip, tail.length - skip)];
    return [[NSString alloc] initWithData:whole encoding:NSUTF8StringEncoding] ?: @"";
}

// The marker Stop Deploy leaves beside a run (stop:), a file of its own: the run's shell writes only its status, so it
// can't overwrite it.
static NSString *const kStopped = @"stopped";
// How long what a stopped run started has to end before it's made to (stop:).
static const int64_t kStopGrace = 2;

// A folder's last run: {startedAt, running}, and once it has ended, {ok, finishedAt}, with the log's last line if it
// failed, or {stopped} if you stopped it. Nil before its first. It's running for as long as its own process is,
// whatever its files say, so a run you've stopped reads as running until it has really ended; and only while that
// process is its own: one whose pid now belongs to a later process (told apart by when it started) has ended, so a
// run cut short, say by a restart of the Mac, can't look as if it runs forever. A run noted without when its process
// started is taken as ended: its pid alone could be anyone's now. Stopped, it runs on until what it started has ended
// too, for the few seconds that's given (stop:), so Deploy can't start a second run over one still stopping; after
// that, its group's id too could be a later process's. One that ended without writing its
// status was stopped some other way. When it finished is when its files last changed (the marker, the status, or, with
// neither, its log), so it reads the same every time it's looked at.
NSDictionary *LastDeployRun(NSString *folder) {
    NSString *dir = RunDir(folder);
    NSDictionary *run = ReadJSON([dir stringByAppendingPathComponent:@"run.json"]);
    if (![run isKindOfClass:NSDictionary.class] || ![run[@"folder"] isEqual:folder]) return nil;
    NSMutableDictionary *last = [@{@"startedAt": run[@"startedAt"] ?: @0} mutableCopy];
    pid_t pid = [run[@"pid"] intValue];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSDate *(^changed)(NSString *) = ^NSDate *(NSString *name) {
        return [fm attributesOfItemAtPath:[dir stringByAppendingPathComponent:name] error:nil].fileModificationDate;
    };
    BOOL known = pid > 0 && [run[@"processStart"] isKindOfClass:NSNumber.class];
    BOOL alive = known && ProcessStartedAt(pid) == [run[@"processStart"] longLongValue];
    if (!alive && known) {
        NSDate *stoppedAt = changed(kStopped);
        alive = stoppedAt && -stoppedAt.timeIntervalSinceNow < kStopGrace + 3 && killpg(pid, 0) == 0;
    }
    if (alive) {
        last[@"running"] = @YES;
        return last;
    }
    NSString *status = [[NSString stringWithContentsOfFile:[dir stringByAppendingPathComponent:@"status"]
                                                  encoding:NSUTF8StringEncoding error:nil]
                        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    BOOL stopped = [fm fileExistsAtPath:[dir stringByAppendingPathComponent:kStopped]];
    BOOL exited = status.length
        && [status rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound;
    NSDate *ended = stopped ? changed(kStopped) ?: changed(@"status") : exited ? changed(@"status") : nil;
    if (!ended) {
        NSDate *wrote = changed(@"log"), *began = changed(@"run.json");
        ended = wrote && began ? [wrote laterDate:began] : wrote ?: began;
    }
    last[@"running"] = @NO;
    last[@"ok"] = !stopped && exited && status.intValue == 0 ? @YES : @NO;
    last[@"finishedAt"] = ended ? @(floor(ended.timeIntervalSince1970 * 1000)) : last[@"startedAt"];
    if (stopped) {
        last[@"stopped"] = @YES;
    } else if (![last[@"ok"] boolValue]) {
        NSString *text = LogTail([dir stringByAppendingPathComponent:@"log"]);
        text = WithoutColours(text);
        NSString *line = nil;
        for (NSString *each in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet])
            if ([each stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length) line = each;
        last[@"lastLine"] = exited ? Clip(line ?: [NSString stringWithFormat:@"it ended with status %d",
                                                                             status.intValue], 200)
                                   : @"it stopped before it finished";
    }
    return last;
}

@interface Deploys ()
@property (strong) Page *page;
@property (strong) dispatch_queue_t queue;
@property (assign) BOOL reading;
@property (assign) NSTimeInterval readAt;
@property (copy) NSString *sent;  // what the page was last told, as JSON
// What was last read, on the main thread: what ▾'s menu goes by, so opening it never waits on the queue or the disk.
@property (copy) NSDictionary *known;
// The sessions listed last, on the main thread: who else is at work in a row's folder, which a deploy waits for.
@property (copy) NSArray<Row *> *rows;
// Suggestions by folder, with when each was worked out: on the queue only.
@property (strong) NSMutableDictionary<NSString *, NSArray *> *suggested;
@end

@implementation Deploys

- (instancetype)initWithPage:(Page *)page {
    if (!(self = [super init])) return nil;
    self.page = page;
    self.queue = dispatch_queue_create("whozmove.deploys", DISPATCH_QUEUE_SERIAL);
    self.suggested = [NSMutableDictionary dictionary];
    return self;
}

- (void)refreshFor:(NSArray<Row *> *)rows {
    self.rows = rows;
    if (self.reading || NSDate.date.timeIntervalSince1970 - self.readAt < 2) return;
    NSMutableDictionary<NSString *, NSString *> *projectOf = [NSMutableDictionary dictionary];  // folder -> project
    for (Row *row in rows)
        if (DeployFolder(row)) projectOf[DeployFolder(row)] = DeployProject(row);
    self.reading = YES;
    dispatch_async(self.queue, ^{
        NSDictionary *deploys = nil;
        @try {
            deploys = [self read:projectOf];
        } @catch (NSException *e) {
            LogProblem([NSString stringWithFormat:@"deploys not read: %@: %@", e.name, e.reason]);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.reading = NO;
            self.readAt = NSDate.date.timeIntervalSince1970;
            if (deploys) [self send:deploys];
        });
    });
}

- (void)resend {
    self.sent = nil;
    self.readAt = 0;
}

// On the queue: each project's saved command, and each folder's suggestion, last deploy, skip and last run. A run that
// ended well counts as the folder's last deploy.
- (NSDictionary *)read:(NSDictionary<NSString *, NSString *> *)projectOf {
    NSMutableDictionary *store = ReadStore();
    NSMutableDictionary *projects = [NSMutableDictionary dictionary], *folders = [NSMutableDictionary dictionary];
    BOOL changed = NO;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    for (NSString *folder in projectOf) {
        NSString *project = projectOf[folder];
        if (SavedCommand(store, project)) projects[project] = @{@"command": SavedCommand(store, project)};
        NSArray *cached = self.suggested[folder];
        if (!cached || now - [cached[0] doubleValue] > 30)
            self.suggested[folder] = cached = @[@(now), SuggestDeploy(folder) ?: NSNull.null];
        NSMutableDictionary *state = [NSMutableDictionary dictionary];
        if ([cached[1] isKindOfClass:NSString.class]) state[@"suggested"] = cached[1];
        id folderState = store[@"folders"][folder];
        NSDictionary *kept = [folderState isKindOfClass:NSDictionary.class] ? folderState : @{};
        NSDictionary *run = LastDeployRun(folder);
        if ([run[@"ok"] boolValue] && [run[@"finishedAt"] doubleValue] > [kept[@"at"] doubleValue]) {
            NSMutableDictionary *updated = [kept mutableCopy];
            updated[@"at"] = run[@"finishedAt"];
            store[@"folders"][folder] = kept = updated;
            changed = YES;
        }
        if (kept[@"at"]) state[@"at"] = kept[@"at"];
        if (kept[@"skippedAt"]) state[@"skippedAt"] = kept[@"skippedAt"];
        if (run) state[@"run"] = run;
        folders[folder] = state;
    }
    if (changed) WriteStore(store);
    return @{@"projects": projects, @"folders": folders};
}

- (void)send:(NSDictionary *)deploys {
    self.known = deploys;
    NSData *json = [NSJSONSerialization dataWithJSONObject:deploys options:NSJSONWritingSortedKeys error:nil];
    NSString *text = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : nil;
    if (!text || [text isEqualToString:self.sent] || !self.page.ready) return;
    self.sent = text;
    [self.page call:@"setDeploys" with:@[deploys]];
}

// What a deploy starts from: only what your terminal gets from macOS when it opens (who and where you are, the
// system's own folders for commands, your keychain's ssh agent), never the rest of this app's environment, which is an
// agent's if a build an agent ran restarted the panel (its tokens, where it sends requests, Claude Code's marks, which
// build.sh reads). Your login shell sets up everything else, as it does in your terminal.
static NSDictionary<NSString *, NSString *> *DeployEnvironment(void) {
    NSDictionary<NSString *, NSString *> *own = NSProcessInfo.processInfo.environment;
    NSMutableDictionary<NSString *, NSString *> *environment = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"HOME", @"USER", @"LOGNAME", @"TMPDIR", @"LANG", @"SSH_AUTH_SOCK",
                            @"__CF_USER_TEXT_ENCODING"])
        if (own[key].length) environment[key] = own[key];
    environment[@"HOME"] = environment[@"HOME"] ?: NSHomeDirectory();
    environment[@"USER"] = environment[@"USER"] ?: NSUserName();
    environment[@"LOGNAME"] = environment[@"LOGNAME"] ?: NSUserName();
    environment[@"SHELL"] = LoginShell();
    environment[@"PATH"] = @"/usr/bin:/bin:/usr/sbin:/sbin";
    return environment;
}

// Runs a project's saved command from a folder, detached, through your login shell (LoginShell) started from a clean
// environment (DeployEnvironment), with its output in the run's log and its exit status written beside it once it
// ends. Never a suggestion, only a command you saved; and one run at a time per folder: not while the last one's
// process is still there, even once it has been stopped. On the queue. Returns why it didn't start, for the row, or
// nil.
- (NSString *)runIn:(NSString *)folder project:(NSString *)project {
    NSString *command = SavedCommand(ReadStore(), project);
    if (!command.length) {
        PanelLog(@"deploy in %@: no command saved for %@", folder, project);
        return @"Deploy isn't set up for this project: set it up in ▾";
    }
    if ([LastDeployRun(folder)[@"running"] boolValue]) return nil;  // the row already shows it running
    NSString *dir = RunDir(folder);
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700}
                        error:nil];
    for (NSString *name in @[@"status", kStopped, @"log", @"run.json"])
        [fm removeItemAtPath:[dir stringByAppendingPathComponent:name] error:nil];
    NSString *status = [dir stringByAppendingPathComponent:@"status"];
    NSString *log = [dir stringByAppendingPathComponent:@"log"];
    NSNumber *startedAt = @(floor(NSDate.date.timeIntervalSince1970 * 1000));
    // Job control is off, as an interactive shell would otherwise put the command in a process group of its own,
    // out of reach of Stop Deploy (stop:).
    NSString *script = @"set +m; cd -- \"$1\" && eval \"$2\"; echo $? > \"$3\"";
    NSString *shell = LoginShell();
    // Once it ends, the panel looks again at once, rather than when it next would, so the check shows on time.
    __weak Deploys *weakSelf = self;
    pid_t pid = SpawnDetached(shell, @[@"-l", @"-i", @"-c", script, shell.lastPathComponent, folder, command, status],
                              DeployEnvironment(), log, ^{
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf resend]; });
    });
    if (!pid) {
        PanelLog(@"deploy in %@: couldn't start %@", folder, shell);
        [[NSString stringWithFormat:@"Couldn't start %@\n", shell] writeToFile:log atomically:YES
                                                                     encoding:NSUTF8StringEncoding error:nil];
        [@"1\n" writeToFile:status atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    // With when its process started, so a later process given the same pid isn't taken for it (LastDeployRun).
    long long processStart = ProcessStartedAt(pid);
    NSMutableDictionary *run = [@{@"folder": folder, @"command": command, @"startedAt": startedAt, @"pid": @(pid)}
                                mutableCopy];
    if (processStart) run[@"processStart"] = @(processStart);
    [[NSJSONSerialization dataWithJSONObject:run options:0 error:nil]
        writeToFile:[dir stringByAppendingPathComponent:@"run.json"] atomically:YES];
    PanelLog(@"deploy in %@: %@", folder, command);
    return nil;
}

// Why a deploy can't start from this row now, or nil: it waits while the row's agent works, asks something or
// compacts, or another agent does in the same folder (WhyStepsWait), so what's put in place isn't half-way through a
// change. The page dims the button then; this holds even if a press gets through.
- (NSString *)whyNotNow:(Row *)row {
    return WhyStepsWait(row, self.rows, @"Deploy waits");
}

- (void)deploy:(Row *)row {
    NSString *folder = DeployFolder(row), *project = DeployProject(row), *sid = row.sessionId;
    if (!folder || !project) return;
    NSString *wait = [self whyNotNow:row];
    if (wait) {
        [self.page stepNote:sid text:wait];
        return;
    }
    dispatch_async(self.queue, ^{
        NSString *why = [self runIn:folder project:project];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (why) [self.page stepNote:sid text:why];
            [self resend];
        });
    });
}

- (void)save:(NSString *)command forRow:(Row *)row thenDeploy:(BOOL)deploy {
    command = [command isKindOfClass:NSString.class]
        ? [command stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : nil;
    NSString *folder = DeployFolder(row), *project = DeployProject(row), *sid = row.sessionId;
    if (!folder || !project) return;
    // One line, as the card's box takes it (and no longer than it lets you type): a command saved here is run as
    // written. The card has closed by now, so the row says why one wasn't saved.
    BOOL oneLine = [command rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location == NSNotFound;
    if (!command.length || command.length > 1000 || !oneLine) {
        PanelLog(@"deploy command for %@ not saved: %lu characters, %@", project, (unsigned long)command.length,
                 oneLine ? @"one line" : @"several lines");
        [self.page stepNote:sid text:@"Not saved: a deploy command is one line of up to 1,000 characters"];
        return;
    }
    NSString *wait = deploy ? [self whyNotNow:row] : nil;  // saved all the same; it runs on the next press
    dispatch_async(self.queue, ^{
        NSMutableDictionary *store = ReadStore();
        store[@"projects"][RealPath(project)] = @{@"command": command,
                                                  @"savedAt": @(floor(NSDate.date.timeIntervalSince1970 * 1000))};
        WriteStore(store);
        PanelLog(@"deploy command for %@ set: %@", project, command);
        NSString *why = !deploy ? nil : wait ?: [self runIn:folder project:project];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (why) [self.page stepNote:sid text:why];
            [self resend];
        });
    });
}

- (void)skip:(Row *)row {
    NSString *folder = DeployFolder(row);
    if (!folder) return;
    dispatch_async(self.queue, ^{
        NSMutableDictionary *store = ReadStore();
        NSMutableDictionary *kept = [store[@"folders"][folder] isKindOfClass:NSDictionary.class]
            ? [store[@"folders"][folder] mutableCopy] : [NSMutableDictionary dictionary];
        kept[@"skippedAt"] = @(floor(NSDate.date.timeIntervalSince1970 * 1000));
        store[@"folders"][folder] = kept;
        WriteStore(store);
        dispatch_async(dispatch_get_main_queue(), ^{ [self resend]; });
    });
}

// Forget Deploy Command: the project goes back to having only Whozmove's suggestion, if it has one, offered after
// new work.
- (void)forget:(Row *)row {
    NSString *project = DeployProject(row);
    if (!project) return;
    dispatch_async(self.queue, ^{
        NSMutableDictionary *store = ReadStore();
        [store[@"projects"] removeObjectForKey:RealPath(project)];
        WriteStore(store);
        PanelLog(@"deploy command for %@ forgotten", project);
        dispatch_async(dispatch_get_main_queue(), ^{ [self resend]; });
    });
}

// Stops the folder's run, and whatever it started. The shell running the command is ended outright, so nothing more of
// the command starts: told to end, it would go on to the next part of it (an interactive shell takes no notice, and
// neither does one the command told to ignore it). The rest of the run's process group (SpawnDetached), what the
// command started, is told to end, so each part can finish cleanly, and anything still there 2s later is made to. The
// marker beside the run says you stopped it, whatever status its shell got to write.
- (void)stop:(Row *)row {
    NSString *folder = DeployFolder(row);
    if (!folder) return;
    dispatch_async(self.queue, ^{
        NSString *dir = RunDir(folder);
        NSDictionary *run = ReadJSON([dir stringByAppendingPathComponent:@"run.json"]);
        if (![LastDeployRun(folder)[@"running"] boolValue] || ![run isKindOfClass:NSDictionary.class]) return;
        pid_t pid = [run[@"pid"] intValue];
        if (pid <= 0) return;
        // Ended outright only while it's surely the run's own shell, by when it started: never a later process given
        // its pid. Stopped again while what it started is still ending, only that is told again.
        BOOL own = ProcessStartedAt(pid) == [run[@"processStart"] longLongValue];
        if (own) kill(pid, SIGKILL);
        if (killpg(pid, SIGTERM) != 0 && !own) {
            PanelLog(@"deploy in %@: couldn't stop it (%d)", folder, pid);
            return;
        }
        if (own) [kStopped writeToFile:[dir stringByAppendingPathComponent:kStopped] atomically:YES
                              encoding:NSUTF8StringEncoding error:nil];
        PanelLog(@"deploy in %@: stopped", folder);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kStopGrace * NSEC_PER_SEC), self.queue, ^{
            if (killpg(pid, 0) == 0) {
                killpg(pid, SIGKILL);
                PanelLog(@"deploy in %@: made to stop, as it went on after being told", folder);
            }
            // The row shows Deploy ready again once all of it has ended.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
                [self resend];
            });
        });
        dispatch_async(dispatch_get_main_queue(), ^{ [self resend]; });
    });
}

- (void)check:(NSString *)command forRow:(Row *)row {
    NSString *folder = DeployFolder(row), *sid = row.sessionId;
    if (![command isKindOfClass:NSString.class] || !sid) return;
    dispatch_async(self.queue, ^{
        NSDictionary *check = CheckDeploy(folder, command);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.page call:@"deployChecked" with:@[sid ?: @"", check ?: @{}]];
        });
    });
}

// From what was last read (known), so ▾ opens at once.
- (NSDictionary *)stateOf:(Row *)row {
    NSString *folder = DeployFolder(row), *project = DeployProject(row);
    NSDictionary *known = self.known;
    NSDictionary *saved = project ? known[@"projects"][project] : nil, *here = folder ? known[@"folders"][folder] : nil;
    NSMutableDictionary *state = [NSMutableDictionary dictionary];
    if (saved[@"command"]) state[@"command"] = saved[@"command"];
    if (here[@"suggested"]) state[@"suggested"] = here[@"suggested"];
    if (here[@"run"]) {
        state[@"running"] = here[@"run"][@"running"] ?: @NO;
        state[@"log"] = [RunDir(folder) stringByAppendingPathComponent:@"log"];
    }
    return state;
}

@end
