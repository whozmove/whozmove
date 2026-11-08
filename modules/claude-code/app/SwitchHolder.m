// SwitchHolder: which session may hold AnswerFor's switches kept for its folder.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "SwitchHolder.h"
#import "Core.h"
#import "Rows.h"
#import "Row.h"
#import "Files.h"
#import "Text.h"
#import "Processes.h"
#import "ClaudeSessions.h"
#import "ClaudeUsage.h"
#import "WhereSeenWorking.h"

// What to do about a session open in more than one place.
static NSString *const kOpenTwice = @"Open in more than one place: close the copy you don't use first, in its own "
                                    @"terminal";
// How long what the system says of a session's process is kept before it's asked again: the list of processes and the
// walk up a process's parents take a moment.
static const NSTimeInterval kCheckedFor = 1;

NSString *KeptFolderOf(Row *row) {
    NSString *root = AsText(row.git[@"root"]);
    NSString *folder = root.length ? RealPath(root) : row.cwd.length ? RealPath(row.cwd) : nil;
    return folder.length ? folder : nil;
}

pid_t StartedWalkStopsAt(BOOL printing) {
    return printing ? getpid() : 0;
}

@interface SwitchHolder ()
@property (weak) Core *core;
@property (copy) ClaudeProgram (^programOf)(pid_t pid);
@property (copy) BOOL (^mayBe)(NSString *name);
@property (copy) NSString *(^named)(Row *row);
// What was last decided for each session's process, by its pid, start and folder, with when.
@property (strong) NSMutableDictionary<NSString *, NSArray *> *checked;
@end

@implementation SwitchHolder

- (instancetype)initWithCore:(Core *)core program:(ClaudeProgram (^)(pid_t pid))programOf
                       mayBe:(BOOL (^)(NSString *name))mayBe named:(NSString *(^)(Row *row))named {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.programOf = programOf;
    self.mayBe = mayBe;
    self.named = named;
    self.checked = [NSMutableDictionary dictionary];
    return self;
}

- (void)forget {
    [self.checked removeAllObjects];
}

// A listed session's row by its process, or nil for one that isn't listed.
- (Row *)rowOfProcess:(pid_t)pid {
    for (Row *row in self.core.rows.byId.allValues)
        if (row.pid == pid) return row;
    return nil;
}

// A session in the way, as WhyNotHold takes it: {name, session} when it's listed, else empty.
- (NSDictionary *)inTheWay:(pid_t)pid {
    Row *its = [self rowOfProcess:pid];
    if (!its.sessionId) return @{};
    return @{@"name": self.named(its), @"session": its.sessionId};
}

// The Claude Code session a session was started inside, or nil: its process's parents, up to the system's own, as the
// system keeps them, each asked whether it's Claude Code's program (signed or from npm, by `programOf`, which no record
// or file can make so). No record, registry file or listing of sessions counts here, so one that rewrites or removes
// its own can't hide from it.
- (NSDictionary *)startedInside:(Row *)row {
    pid_t stop = StartedWalkStopsAt(self.core.printing);
    pid_t up = ProcessParent(row.pid);
    for (int steps = 0; up > 1 && up != stop && steps < 64; steps++, up = ProcessParent(up))
        if (self.programOf(up) != ClaudeProgramNone) return [self inTheWay:up];
    return nil;
}

// Another Claude Code process running in a folder, or one inside it, as the system says (never its records), other
// than `pid` and those it started, or nil: paused ones count; Whozmove's own copies asked a question on the side don't,
// nor do the team's members working in folders of their own inside it (worktrees a lead at the repository's top folder
// has under it), which are the ones its switches answer for.
- (NSDictionary *)otherIn:(NSString *)folder besides:(pid_t)pid {
    NSArray<NSDictionary *> *processes = YourProcesses();
    NSMutableDictionary<NSNumber *, NSNumber *> *parents = [NSMutableDictionary dictionary];
    for (NSDictionary *each in processes) parents[each[@"pid"]] = each[@"parent"];
    for (NSDictionary *each in processes) {
        pid_t other = [each[@"pid"] intValue];
        if (other == pid || other <= 0 || !self.mayBe(each[@"name"])) continue;
        BOOL started = NO;
        pid_t up = [parents[@(other)] intValue];
        for (int steps = 0; up > 1 && steps < 32 && !started; steps++, up = [parents[@(up)] intValue])
            started = up == pid;
        if (started || IsAsideCopy(other)) continue;
        NSString *where = ProcessFolder(other);
        // Whozmove's own check of your plan's usage, a Claude Code run of a second in its own folder, is never a
        // session.
        if (PathWithin(where, UsageFolder())) continue;
        if (!PathWithin(where, folder)) continue;
        Row *its = [self rowOfProcess:other];
        NSString *own = KeptFolderOf(its);
        // Only a folder inside this one, which the system says it really works in: a record naming a folder above it
        // would otherwise leave out any session here.
        if ([its.team[@"role"] isEqual:@"member"] && own && ![own isEqualToString:folder] && PathWithin(own, folder)
            && PathWithin(where, own))
            continue;
        if (self.programOf(other) != ClaudeProgramNone) return [self inTheWay:other];
    }
    return nil;
}

- (NSDictionary *)whyNot:(Row *)row {
    if (row.pid <= 0) return @{@"why": @"The session isn't running", @"kind": @"running"};
    NSString *folder = KeptFolderOf(row);
    long long started = ProcessStartedAt(row.pid);
    NSString *key = [NSString stringWithFormat:@"%d %lld %@", row.pid, started, folder ?: @""];
    NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
    NSArray *checked = self.checked[key];
    if (checked && now - [checked[0] doubleValue] < kCheckedFor) return checked[1];
    NSString *working = started ? ProcessFolder(row.pid) : nil;
    ClaudeProgram program = ClaudeProgramNone;
    NSString *programWhy = nil;
    NSArray<NSNumber *> *copies = @[];
    NSDictionary *startedInside = nil, *otherHere = nil;
    // The rest is read only once the process works in the folder: the rule asks no more of one that doesn't.
    if (folder && working && PathWithin(working, folder)) {
        program = self.programOf(row.pid);
        programWhy = AtSentenceStart(ClaudeProgramCause(row.pid, program));
        if (row.alsoOpen.count) copies = ClaudeCopiesOf(row.sessionId, row.pid, self.programOf);
        startedInside = [self startedInside:row];
        otherHere = [self otherIn:folder besides:row.pid];
    }
    NSDictionary *hold = WhyNotHold(folder, working, program, programWhy, row.alsoOpen.count > 0, copies,
                                    startedInside, otherHere);
    if (self.checked.count > 64) [self.checked removeAllObjects];
    self.checked[key] = @[@(now), hold];
    return hold;
}

@end

NSDictionary *WhyNotHold(NSString *folder, NSString *working, ClaudeProgram program, NSString *programWhy,
                         BOOL followsCopy, NSArray<NSNumber *> *copies, NSDictionary *startedInside,
                         NSDictionary *otherHere) {
    if (!folder) return @{@"why": @"Its folder can't be read", @"kind": @"folder"};
    if (!working) return @{@"why": @"The folder its process works in can't be read", @"kind": @"folder"};
    if (!PathWithin(working, folder))
        return @{@"why": [NSString stringWithFormat:@"Its process doesn't work in %@, whatever its record says",
                                                    folder.lastPathComponent], @"kind": @"folder"};
    // The row follows a copy of the conversation that isn't Claude Code's own (a record anything could write): there's
    // another copy to close, which is what the user can do about it.
    if (program != ClaudeProgramSigned && followsCopy) return @{@"why": kOpenTwice, @"kind": @"copy"};
    // Updating an older Claude Code from npm doesn't change the process that runs: only a session started again after
    // it can hold them, as a new one in the folder does by itself.
    if (program == ClaudeProgramByPath)
        return @{@"why": [programWhy ?: @"It runs an older Claude Code from npm: update Claude Code"
                             stringByAppendingString:@" and start it again"], @"kind": @"npm"};
    if (program != ClaudeProgramSigned)
        return @{@"why": programWhy ?: @"It isn't Claude Code's own program, signed by Anthropic", @"kind": @"program"};
    if (copies.count) return @{@"why": kOpenTwice, @"kind": @"copy"};
    NSString *(^named)(NSDictionary *) = ^NSString *(NSDictionary *who) {
        NSString *name = AsText(who[@"name"]);
        return name.length ? [NSString stringWithFormat:@"another Claude Code session, %@,", name]
                           : @"another Claude Code session";
    };
    NSMutableDictionary *refused = nil;
    if (startedInside) {
        // "…inside another Claude Code session, Rook: start it…", without the name's second comma before the colon.
        NSString *inside = [named(startedInside) stringByTrimmingCharactersInSet:
                            [NSCharacterSet characterSetWithCharactersInString:@","]];
        refused = [@{@"kind": @"started",
                     @"why": [NSString stringWithFormat:@"It was started inside %@: start it in a terminal of its own",
                                                        inside]} mutableCopy];
        if (AsText(startedInside[@"session"])) refused[@"other"] = startedInside[@"session"];
        return refused;
    }
    if (otherHere) {
        refused = [@{@"kind": @"other", @"why": [NSString stringWithFormat:@"%@ runs in %@ too: close it",
                                                 AtSentenceStart(named(otherHere)), folder.lastPathComponent]}
                   mutableCopy];
        if (AsText(otherHere[@"session"])) refused[@"other"] = otherHere[@"session"];
        return refused;
    }
    return @{};
}
