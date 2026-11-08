// ClaudeSessions: Claude Code's running sessions, and its hooks' records.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "ClaudeSessions.h"
#import "Row.h"
#import "Files.h"
#import "Processes.h"
#import "ClaudeCodeFacts.h"
#import "ClaudeUsage.h"
#import "Background.h"
#import <signal.h>

// The check that asks Claude Code for your plan's usage (ClaudeUsage.m) is a session for the second it runs, registered
// like any other, in a folder kept for it. It isn't one of yours, so it's never a row. Asked of every session each
// second, so the folder's real path is found once it's there, and only a session in a folder of the same name is looked
// at further. On the sessions' queue, on the main thread as a session asks the panel something, and on the hook's line's
// queue as a hook asks (SessionOfProcess): the most a race can do is find the real path twice.
static BOOL IsUsageCheck(NSDictionary *session) {
    NSString *cwd = [session[@"cwd"] isKindOfClass:NSString.class] ? session[@"cwd"] : nil;
    if (![cwd.lastPathComponent isEqualToString:UsageFolder().lastPathComponent]) return NO;
    static NSString *real;
    if (!real && [NSFileManager.defaultManager fileExistsAtPath:UsageFolder()]) real = RealPath(UsageFolder());
    NSString *folder = real ?: UsageFolder();
    return [cwd isEqualToString:folder] || [RealPath(cwd) isEqualToString:folder];
}

static pid_t PidOf(NSDictionary *session) {
    return AsNumber(session[@"pid"]).intValue;
}

// The copies of a session's conversation asked a question on the side (ClaudeAside.m), by their process, while each
// runs. Each registers like any session, in its session's folder, as long as it runs. None is one of yours, so none is
// a row, a copy of its session to close or end, a process a hook belongs to, or another agent at work in that folder.
// Noted as each starts, before it can register, and let go as it ends; read on the rows' queue, the hook's line's and
// the main thread, so kept under a lock.
static NSMutableSet<NSNumber *> *AsideProcesses(void) {
    static NSMutableSet<NSNumber *> *processes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ processes = [NSMutableSet set]; });
    return processes;
}

void NoteAsideProcess(pid_t pid, BOOL running) {
    NSMutableSet<NSNumber *> *processes = AsideProcesses();
    @synchronized (processes) {
        if (running) [processes addObject:@(pid)];
        else [processes removeObject:@(pid)];
    }
}

static BOOL IsAsideProcess(pid_t pid) {
    NSMutableSet<NSNumber *> *processes = AsideProcesses();
    @synchronized (processes) {
        return [processes containsObject:@(pid)];
    }
}

BOOL IsAsideCopy(pid_t pid) {
    return IsAsideProcess(pid);
}

// Whether a process runs as you, as every Claude Code session does. A crash can leave a session's file behind, and its
// number can go to another process later, most often one of the system's.
static BOOL RunsAsYou(pid_t pid) {
    return pid > 0 && kill(pid, 0) == 0;
}

// The session a running process of Claude Code's is, from the process's own file in the registry: only while that file
// is the process's, started within a minute of it, so a later process given the pid of an ended one whose file stayed
// isn't taken for it.
NSString *SessionOfProcess(pid_t pid) {
    if (!RunsAsYou(pid)) return nil;
    NSString *file = [ClaudeDir(kClaudeCodeRegistry) stringByAppendingPathComponent:
                                                        [NSString stringWithFormat:@"%d.json", pid]];
    NSDictionary *s = AsRecord(ReadJSON(file));
    if (!s || PidOf(s) != pid || IsUsageCheck(s) || IsAsideProcess(pid)) return nil;
    double started = AsNumber(s[@"startedAt"]).doubleValue, began = ProcessStartedAt(pid) / 1000.0;
    if (!started || !began || fabs(started - began) > 60000) return nil;
    return AsText(s[@"sessionId"]);
}

NSString *SessionAbove(pid_t pid, pid_t *found) {
    for (int up = 0; pid > 1 && up < 32; up++, pid = ProcessParent(pid)) {
        NSString *sessionId = SessionOfProcess(pid);
        if (!sessionId) continue;
        if (found) *found = pid;
        return sessionId;
    }
    return nil;
}

// The processes Claude Code's registry lists that still run (paused ones too), each as its file has it. Read every
// second for the rows, so each file is parsed again only once it has changed; `fresh` reads them all, for closing a
// copy, which goes by what each says now.
static NSArray<NSDictionary *> *RegisteredProcesses(BOOL fresh) {
    NSString *registry = ClaudeDir(kClaudeCodeRegistry);
    NSMutableArray<NSDictionary *> *found = [NSMutableArray array];
    for (NSString *file in [NSFileManager.defaultManager contentsOfDirectoryAtPath:registry error:nil]) {
        if (![file.pathExtension isEqualToString:@"json"]) continue;
        NSString *path = [registry stringByAppendingPathComponent:file];
        NSDictionary *s = fresh ? ReadJSON(path) : ReadJSONKept(path);
        if ([s isKindOfClass:NSDictionary.class] && RunsAsYou(PidOf(s)) && !IsAsideProcess(PidOf(s)))
            [found addObject:s];
    }
    return found;
}

// A process's record with its status as Whozmove takes it (ClaudeStatus), for its row.
static NSDictionary *AsRowRecord(NSDictionary *s) {
    NSMutableDictionary *record = [s mutableCopy];
    record[@"status"] = ClaudeStatus(s[@"status"]);
    return record;
}

// How much a process's state calls for you: asking you something, then at work, then the rest.
static int Urgency(NSDictionary *session) {
    id status = session[@"status"];
    return [status isEqual:@"waiting"] ? 2 : [status isEqual:@"busy"] ? 1 : 0;
}

static double TimeIn(NSDictionary *session, NSString *key) {
    return AsNumber(session[key]).doubleValue;
}

// One process registered for a conversation open in more than one (resumed in a second tab while it still runs, open
// in Claude Desktop and a terminal, or paused with Ctrl+Z in one), with what's asked of it more than once.
@interface Copy : NSObject
@property (strong) NSDictionary *record;
@property (copy) NSString *key;
@property BOOL stopped;
@property BOOL untracked;  // in an app whose sessions you don't track (Claude Desktop, its switch off)
@end

@implementation Copy
@end

// Whether one copy speaks for the conversation rather than another: one in an app whose sessions you track over one in
// an app you don't, so turning that off never takes a terminal's copy out of the list with it; one that runs over one
// paused in its terminal, then the one that needs you most, then the one the row followed already, so it doesn't move
// to a copy only because it started; and when the row is new, the one whose state changed last, then the one started
// last.
static BOOL Outranks(Copy *one, Copy *other, NSString *followed) {
    if (one.untracked != other.untracked) return other.untracked;
    if (one.stopped != other.stopped) return other.stopped;
    if (Urgency(one.record) != Urgency(other.record)) return Urgency(one.record) > Urgency(other.record);
    BOOL oneFollowed = [one.key isEqual:followed], otherFollowed = [other.key isEqual:followed];
    if (oneFollowed != otherFollowed) return oneFollowed;
    double oneAt = TimeIn(one.record, @"statusUpdatedAt"), otherAt = TimeIn(other.record, @"statusUpdatedAt");
    if (oneAt != otherAt) return oneAt > otherAt;
    return TimeIn(one.record, @"startedAt") > TimeIn(other.record, @"startedAt");
}

// Running sessions from Claude Code's registry: one file per process. A conversation open in more than one process has
// a file for each; it's one session, so it's one row, the copy that outranks the others, which it names, untracked ones
// among them, as typing into one copy still has to know of the others.
NSArray<Row *> *RunningSessions(BOOL (^untracked)(Row *copy)) {
    // The copy each row followed last time, by its process (its number and when it started). Only the rows' queue
    // reads the sessions, so it's never asked from two places at once.
    static NSDictionary<NSString *, NSString *> *followed;
    NSMutableArray<NSMutableArray<Copy *> *> *found = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray<Copy *> *> *bySession = [NSMutableDictionary dictionary];
    for (NSDictionary *registered in RegisteredProcesses(NO)) {
        if (IsUsageCheck(registered)) continue;
        NSDictionary *s = AsRowRecord(registered);
        Copy *copy = [Copy new];
        copy.record = s;
        copy.key = ProcessKey(PidOf(s), AsText(s[@"procStart"]));
        copy.stopped = ProcessStopped(PidOf(s));
        copy.untracked = untracked && untracked([[Row alloc] initWithFields:s]);
        NSString *sessionId = AsText(s[@"sessionId"]);
        NSMutableArray<Copy *> *copies = sessionId ? bySession[sessionId] : nil;
        if (copies) {
            [copies addObject:copy];
            continue;
        }
        copies = [NSMutableArray arrayWithObject:copy];
        if (sessionId) bySession[sessionId] = copies;
        [found addObject:copies];
    }
    NSDictionary<NSString *, NSString *> *before = followed;
    NSMutableDictionary<NSString *, NSString *> *now = [NSMutableDictionary dictionary];
    NSMutableArray<Row *> *out = [NSMutableArray array];
    for (NSArray<Copy *> *copies in found) {
        NSString *sessionId = AsText(copies.firstObject.record[@"sessionId"]);
        Copy *speaks = copies.firstObject;
        for (Copy *c in copies)
            if (c != speaks && Outranks(c, speaks, sessionId ? before[sessionId] : nil)) speaks = c;
        if (sessionId) now[sessionId] = speaks.key;
        Row *row = [[Row alloc] initWithFields:speaks.record];
        NSMutableArray<NSDictionary *> *others = [NSMutableArray array];
        for (Copy *c in copies) {
            if (c == speaks) continue;
            NSMutableDictionary *other = [@{@"entrypoint": AsText(c.record[@"entrypoint"]) ?: @"",
                                            @"paused": @(c.stopped),
                                            @"busy": @((BOOL)(!c.stopped && [c.record[@"status"] isEqual:@"busy"]))}
                                          mutableCopy];
            if (AsText(c.record[@"hostSessionId"])) other[@"hostSessionId"] = c.record[@"hostSessionId"];
            [others addObject:other];
        }
        if (others.count) row.alsoOpen = others;
        [out addObject:row];
    }
    followed = now;
    return out;
}

NSArray<NSDictionary *> *RegisteredCopies(void) {
    NSMutableArray<NSDictionary *> *copies = [NSMutableArray array];
    for (NSDictionary *s in RegisteredProcesses(NO)) {
        NSString *sessionId = AsText(s[@"sessionId"]);
        if (sessionId && !IsUsageCheck(s)) [copies addObject:@{@"pid": @(PidOf(s)), @"sessionId": sessionId}];
    }
    return copies;
}

NSArray<NSNumber *> *OtherCopiesOf(NSString *sessionId, pid_t pid) {
    NSMutableArray<NSNumber *> *others = [NSMutableArray array];
    for (NSDictionary *s in RegisteredProcesses(YES))
        if (PidOf(s) != pid && [s[@"sessionId"] isEqual:sessionId]) [others addObject:@(PidOf(s))];
    return others;
}

BOOL InAnotherTerminal(NSString *sessionId, pid_t pid) {
    NSString *registry = ClaudeDir(kClaudeCodeRegistry);
    for (NSString *file in [NSFileManager.defaultManager contentsOfDirectoryAtPath:registry error:nil]) {
        if (![file.pathExtension isEqualToString:@"json"]) continue;
        pid_t other = file.stringByDeletingPathExtension.intValue;
        if (other == pid || !RunsAsYou(other) || ProcessStopped(other) || IsAsideProcess(other)) continue;
        NSString *path = [registry stringByAppendingPathComponent:file];
        NSDictionary *s = ReadJSON(path);
        // Claude Code rewrites a session's file in place, so it can be caught half-written: read again, and if it's
        // still unreadable, it may be a copy, so nothing goes in.
        if (![s isKindOfClass:NSDictionary.class]) s = ReadJSON(path);
        if (![s isKindOfClass:NSDictionary.class]) return YES;
        if ([s[@"sessionId"] isEqual:sessionId] && [s[@"entrypoint"] isEqual:kClaudeCodeTerminalEntrypoint])
            return YES;
    }
    return NO;
}

// What keeps a running copy of a session from being ended now, by its registry file: it's somewhere other than a
// terminal (Claude Desktop keeps its own, and an SDK's is its program's), paused (it can't shut down until it's brought
// back), working, running a command Claude started (ending it would stop the command, so this reads the registry's own
// status, not ClaudeStatus), or asking something; or nothing.
typedef NS_ENUM(NSInteger, CopyHold) { CopyFree, CopyElsewhere, CopyPaused, CopyWorking, CopyCommand, CopyAsking };
static CopyHold HoldOf(NSDictionary *s) {
    if (![s[@"entrypoint"] isEqual:kClaudeCodeTerminalEntrypoint]) return CopyElsewhere;
    if (ProcessStopped(PidOf(s))) return CopyPaused;
    if ([s[@"status"] isEqual:@"busy"]) return CopyWorking;
    if ([s[@"status"] isEqual:kClaudeCodeStatusBackground]) return CopyCommand;
    if (![s[@"status"] isEqual:@"idle"]) return CopyAsking;
    return CopyFree;
}

NSString *CloseOtherCopies(NSString *sessionId, pid_t keep, BOOL requestWaiting, NSUInteger *closed) {
    *closed = 0;
    NSMutableArray<NSNumber *> *closing = [NSMutableArray array];
    for (NSDictionary *s in RegisteredProcesses(YES)) {
        pid_t pid = PidOf(s);
        if (pid == keep || ![s[@"sessionId"] isEqual:sessionId]) continue;
        switch (HoldOf(s)) {
            case CopyElsewhere: case CopyPaused: continue;
            case CopyWorking: return @"Claude is working in the other copy: close it when it's done";
            case CopyCommand:
                return @"A command Claude started is still running in the other copy: close it when that's done";
            case CopyAsking: return @"The other copy is asking you something: answer it first";
            case CopyFree: break;
        }
        [closing addObject:@(pid)];
    }
    if (!closing.count) return @"There's no other copy in a terminal to close";
    // Which copy a request came from can't be told, so none is closed while one waits.
    if (requestWaiting) return @"A request is waiting in this conversation: answer it first";
    // Claude Code shuts down on SIGTERM as when its tab is closed, so the tab is left at its shell's prompt.
    for (NSNumber *pid in closing)
        if (kill(pid.intValue, SIGTERM) == 0) (*closed)++;
    return *closed ? nil : @"The other copy couldn't be closed";
}

NSString *WhyNotEndConversation(NSString *sessionId, BOOL *open) {
    *open = NO;
    for (NSDictionary *s in RegisteredProcesses(YES)) {
        if (![s[@"sessionId"] isEqual:sessionId]) continue;
        *open = YES;
        switch (HoldOf(s)) {
            case CopyElsewhere: return @"Open in another app";
            case CopyPaused: return @"Paused in its terminal: bring it back first";
            case CopyWorking: return @"Working: stop it first";
            case CopyCommand: return @"A command Claude started is still running";
            case CopyAsking: return @"Waiting on you: answer it first";
            case CopyFree: break;
        }
    }
    return nil;
}

NSArray<NSNumber *> *EndConversation(NSString *sessionId, NSString **why) {
    NSMutableArray<NSNumber *> *ending = [NSMutableArray array];
    for (NSDictionary *s in RegisteredProcesses(YES)) {
        if (![s[@"sessionId"] isEqual:sessionId]) continue;
        pid_t pid = PidOf(s);
        if (HoldOf(s) != CopyFree) {
            if (why) *why = @"It started something since: look again";
            return nil;
        }
        // Only a process that's still this session's own, by its start time against its file's, so a pid handed on to
        // another process since is never sent anything, and nothing is.
        if (![SessionOfProcess(pid) isEqual:sessionId]) {
            if (why) *why = @"Whozmove can't be sure which process it is: end it in its terminal";
            return nil;
        }
        [ending addObject:@(pid)];
    }
    // Claude Code shuts down on SIGTERM as when its tab is closed, saving what it has.
    for (NSNumber *pid in ending) kill(pid.intValue, SIGTERM);
    return ending;
}

NSString *HookRecordPath(NSString *sessionId) {
    return [AppDir(@"sessions") stringByAppendingPathComponent:[sessionId stringByAppendingPathExtension:@"json"]];
}

// The session that sent a message from `address` (its process's messaging socket, `/tmp/cc-socks/<pid>.sock`) at
// `sentAt`: the one that process runs, as the registry says, only if it started before the message came, so a later
// process given the same number isn't taken for it, and only if the registry gives it that address, so a socket named
// otherwise finds none rather than another session. Looked up once, the first time it's seen, and kept, as who sent a
// message doesn't change while it stays the last prompt (a row is read every second).
static NSString *SenderOf(NSString *address, NSNumber *sentAt) {
    static NSMutableDictionary<NSString *, id> *known;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ known = [NSMutableDictionary dictionary]; });
    NSString *key = [NSString stringWithFormat:@"%@ %@", address, sentAt];
    id kept = known[key];
    if (kept) return kept == NSNull.null ? nil : kept;
    NSString *socket = address.lastPathComponent;
    pid_t pid = [socket.pathExtension isEqualToString:@"sock"] ? socket.stringByDeletingPathExtension.intValue : 0;
    NSString *session = pid > 0 && sentAt && ProcessStartedAt(pid) / 1000.0 <= sentAt.doubleValue
        ? SessionOfProcess(pid) : nil;
    NSString *file = [ClaudeDir(kClaudeCodeRegistry) stringByAppendingPathComponent:
                                                    [NSString stringWithFormat:@"%d.json", pid]];
    NSDictionary *registered = session ? AsRecord(ReadJSON(file)) : nil;
    if (![AsText(registered[@"messagingSocketPath"]) isEqualToString:address]) session = nil;
    if (known.count > 500) [known removeAllObjects];
    known[key] = session ?: NSNull.null;
    return session;
}

// A message another Claude Code session sent this one comes in as its prompt, in Claude Code's wrapper (as 2.1.304
// writes it): `<cross-session-message from="uds:…" from-name="…" …>` the message `</cross-session-message>`, cut short
// by the hook, often inside a tag. The row shows the message, with the sender's name where yours would be, and keeps
// who sent it: its address (`from`, without `uds:`) and its session (SenderOf). The name and the address both come from
// the prompt's text, which anyone typing into that session can write: they're fit for marking a reply as read, and
// never for anything that lets a session do more.
static void ShowWhoSent(Row *row) {
    static NSRegularExpression *wrapper, *sender, *address;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        wrapper = [NSRegularExpression regularExpressionWithPattern:
            @"^\\s*<cross-session-message\\b([^>]*)(?:>\\s*(.*?))?\\s*"
            @"(?:</cross-session-message>.*|</[a-z-]*…?)?$"
            options:NSRegularExpressionDotMatchesLineSeparators error:nil];
        sender = [NSRegularExpression regularExpressionWithPattern:@"\\bfrom-name=\"([^\"]*)\"" options:0 error:nil];
        address = [NSRegularExpression regularExpressionWithPattern:@"\\bfrom=\"(?:uds:)?([^\"]+)\"" options:0
                                                              error:nil];
    });
    NSString *prompt = row.lastPrompt;
    if (!prompt.length) return;
    NSTextCheckingResult *match = [wrapper firstMatchInString:prompt options:0 range:NSMakeRange(0, prompt.length)];
    if (!match) return;
    NSString *tag = [prompt substringWithRange:[match rangeAtIndex:1]];
    NSRange said = [match rangeAtIndex:2];
    NSTextCheckingResult *named = [sender firstMatchInString:tag options:0 range:NSMakeRange(0, tag.length)];
    NSString *name = named ? [[tag substringWithRange:[named rangeAtIndex:1]]
                                 stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] : @"";
    row.promptFrom = name.length ? name : @"Another session";
    NSTextCheckingResult *from = [address firstMatchInString:tag options:0 range:NSMakeRange(0, tag.length)];
    if (from) {
        row.promptFromAddress = [tag substringWithRange:[from rangeAtIndex:1]];
        row.promptFromSession = SenderOf(row.promptFromAddress, row.lastPromptAt);
    }
    NSString *message = said.location == NSNotFound ? @"" : [prompt substringWithRange:said];
    row.lastPrompt = message.length ? message : @"…";  // cut short before the message began
}

// Adds what the hook recorded (last prompt / reply / notice, and when it last edited files where they landed), and
// when it last wrote it. Asked for every row every second, so the record is parsed again only once the hook has
// written it.
void AddHookRecord(Row *row) {
    if (!row.sessionId.length) return;
    NSString *path = HookRecordPath(row.sessionId);
    NSDictionary *record = ReadJSONKept(path);
    if (![record isKindOfClass:NSDictionary.class]) return;
    [row takeHookRecord:record];
    row.workEditedAt = row.workRoot.length ? ClaudeEditedAt(row.editedAt, row.outcome, row.outcomeAt) : 0;
    row.background = RunningBackground(row, record);
    ShowWhoSent(row);
    double written = FileModifiedAt(path);
    if (written) row.hookRecordedAt = @(written);
}
