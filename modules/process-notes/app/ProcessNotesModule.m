// ProcessNotesModule: how a project works, beside the project's own pages: what those pages don't say (what you told a
// session, what one found the hard way), kept as a note for the project, shared by its worktrees, and handed to each
// session on it (ProjectWay). A session drafts it with `ask-panel.sh process-draft`; the draft waits on its row, whole,
// for your Keep It or Not Now, and only Keep It writes it. A draft again is shown against the note as kept, each line
// added or taken out marked, so Keep It changes exactly what the card shows. After Not Now, a draft shows again only
// with a change the declined one didn't make, so you're never asked twice for the same lines, unless the session you
// said it to drafts it again, which it does only when you ask.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "ProcessNotesModule.h"
#import "ProcessNotes.h"
#import "Core.h"
#import "Rows.h"
#import "Row.h"
#import "Files.h"
#import "Log.h"
#import "Processes.h"
#include <stdio.h>

@interface ProcessNotesModule ()
// Each session's draft waiting on its row, and how its last one went once it no longer waits (notNow,
// keptElsewhere), by session id.
@property (strong) NSMutableDictionary<NSString *, ProcessDraft *> *drafts;
@property (strong) NSMutableDictionary<NSString *, NSString *> *outcomes;
// What you said Not Now to last, by project: {lines, at, by}, `by` the session whose card it was. Only in the panel's
// memory.
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *declined;
// Each project's note as kept, by project: its record, read at launch and written only by Keep It.
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *records;
@property (copy) NSString *folder;
@property (strong) dispatch_queue_t queue;
@end

static NSString *ProcessWrite(NSDictionary *record, NSString *folder, NSString *file);

@implementation ProcessNotesModule

+ (NSString *)moduleName { return @"process-notes"; }

+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return ProcessNotesPrintModes();
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    _core = core;
    _drafts = [NSMutableDictionary dictionary];
    _outcomes = [NSMutableDictionary dictionary];
    _declined = [NSMutableDictionary dictionary];
    _records = [NSMutableDictionary dictionary];
    _queue = dispatch_queue_create("whozmove.process-notes", DISPATCH_QUEUE_SERIAL);
    return self;
}

- (void)launch {
    [self keepIn:AppDir(@"process-notes")];
}

- (double)now {
    return self.clock ? self.clock() : floor(NSDate.date.timeIntervalSince1970 * 1000);
}

// Notes are kept in `folder`, one file a project, only you able to read them; what's there is read once, as a few
// small files, and after that only Keep It changes them.
- (void)keepIn:(NSString *)folder {
    self.folder = folder;
    [self.records removeAllObjects];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil]) {
        if (![name.pathExtension isEqual:@"json"]) continue;
        NSDictionary *record = AsRecord(ReadJSON([folder stringByAppendingPathComponent:name]));
        NSString *project = AsText(record[@"project"]);
        // Only a record in the file its project names: one copied under another's name is never read as that one's.
        if (project.length && [ProcessRecordName(project) isEqual:name] && ProcessKeptLines(record, project, NULL))
            self.records[project] = record;
    }
}

- (NSArray<NSString *> *)keptFor:(NSString *)project at:(double *)keptAt {
    return ProcessKeptLines(self.records[project], project, keptAt);
}

// Whether a session's process still runs: a draft waits only while it does.
- (BOOL)runs:(Row *)row {
    if (self.givenRuns) return self.givenRuns(row);
    return row.pid > 0 && ![self.core hasEnded:row] && ProcessAlive(row.pid);
}

#pragma mark What a session asks

- (NSDictionary<NSString *, SessionAsk *> *)sessionAsks {
    __weak typeof(self) weakSelf = self;
    // A draft only shows on the row, for your Keep It.
    SessionAsk *draft = [SessionAsk askShowing:^NSString *(Row *row, pid_t process, NSDictionary *asked) {
        return [weakSelf draft:asked from:row];
    }];
    // It logs the project's short name and how it went itself, never a word of the note.
    draft.logsItself = YES;
    return @{@"process-draft": draft};
}

static NSString *Decoded(id base64) {
    NSString *text = AsText(base64);
    NSData *data = text ? [[NSData alloc] initWithBase64EncodedString:text options:0] : nil;
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}

// process-draft: how the session's project works, as it drafted it, shown on its row for your Keep It, in place of any
// draft of its own waiting there; or not shown, saying why.
- (NSString *)draft:(NSDictionary *)asked from:(Row *)row {
    NSString *sessionId = row.sessionId, *why = nil;
    NSString *project = ProcessProject(row.git, row.cwd), *name = ProcessProjectName(project);
    if (!project) {
        PanelLog(@"%@ asked process-draft: refused, no folder", sessionId);
        return @"refused: this session has no folder, so it works on no project";
    }
    NSString *text = Decoded(asked[@"note64"]);
    NSArray<NSString *> *lines = text ? ProcessDraftLines(text, &why) : nil;
    if (!lines) {
        PanelLog(@"%@ asked process-draft for %@: refused", sessionId, name);
        return [NSString stringWithFormat:@"refused: %@: draft it again", why ?: @"it couldn't be read"];
    }
    if (self.drafts[sessionId].keeping) {
        PanelLog(@"%@ asked process-draft for %@: refused, the last is being kept", sessionId, name);
        return @"refused: the user's Keep It is saving your last draft just now: draft again in a moment if you "
               @"still have something new";
    }
    NSArray<NSString *> *kept = [self keptFor:project at:NULL];
    if ([kept isEqual:lines]) {
        [self.drafts removeObjectForKey:sessionId];
        [self.outcomes removeObjectForKey:sessionId];
        PanelLog(@"%@ asked process-draft for %@: the same as kept", sessionId, name);
        [self.core.rows refresh];
        return [NSString stringWithFormat:@"nothing new: it's %@'s note as kept already", name];
    }
    // After Not Now, another session's draft of the same changes isn't shown. The session you said it to may show it
    // again: it drafts again only when you ask it to, as when you change your mind.
    NSDictionary *declined = self.declined[project];
    if (declined && ![declined[@"by"] isEqual:sessionId] && !ProcessHoldsNew(lines, declined[@"lines"], kept)) {
        [self.drafts removeObjectForKey:sessionId];
        self.outcomes[sessionId] = @"notNow";
        PanelLog(@"%@ asked process-draft for %@: not shown, nothing new since Not Now", sessionId, name);
        [self.core.rows refresh];
        return [NSString stringWithFormat:@"not shown: the user said Not Now to these same changes on another "
                @"session's row. Work by %@'s own pages, and draft again only once you learn something they don't say",
                name];
    }
    ProcessDraft *draft = [ProcessDraft new];
    draft.project = project;
    draft.name = name;
    draft.lines = lines;
    draft.at = [self now];
    BOOL again = self.drafts[sessionId] != nil;
    self.drafts[sessionId] = draft;
    [self.outcomes removeObjectForKey:sessionId];
    PanelLog(@"%@ asked process-draft for %@: %lu lines, shown on its row%@", sessionId, name,
             (unsigned long)lines.count, again ? @" in place of its last" : @"");
    [self.core.rows refresh];
    return [NSString stringWithFormat:@"shown on your row: “%@ how %@ works?”, for the user's Keep It. Carry on "
            @"meanwhile, by %@'s own pages%@", kept ? @"Keep the change to" : @"Keep this as", name, name,
            kept ? @" and its note as kept" : @""];
}

#pragma mark Your answer on its row

- (void)answer:(NSString *)act for:(NSString *)sessionId at:(NSNumber *)at done:(void (^)(void))done {
    ProcessDraft *draft = sessionId ? self.drafts[sessionId] : nil;
    // Only for the draft the card showed, by when it was asked, and never twice while one is being kept.
    if (!draft || draft.keeping || !at || at.doubleValue != draft.at) {
        if (done) done();
        return;
    }
    if ([act isEqual:@"notNow"]) {
        self.declined[draft.project] = @{@"lines": draft.lines, @"at": @([self now]), @"by": sessionId};
        [self.drafts removeObjectForKey:sessionId];
        self.outcomes[sessionId] = @"notNow";
        // Another session's card for the project that changes nothing this one didn't goes too, so you aren't asked
        // the same thing again on the next row.
        NSArray<NSString *> *kept = [self keptFor:draft.project at:NULL];
        NSUInteger others = 0;
        for (NSString *other in self.drafts.allKeys) {
            ProcessDraft *each = self.drafts[other];
            if (![each.project isEqual:draft.project] || each.keeping || ProcessHoldsNew(each.lines, draft.lines, kept))
                continue;
            [self.drafts removeObjectForKey:other];
            self.outcomes[other] = @"notNow";
            others++;
        }
        PanelLog(@"%@: Not Now for how %@ works%@", sessionId, draft.name,
                 others ? [NSString stringWithFormat:@", %lu other draft%@ of the same taken back", (unsigned long)others,
                                                     others == 1 ? @"" : @"s"] : @"");
        [self.core.rows refresh];
        if (done) done();
        return;
    }
    if (![act isEqual:@"keep"]) {
        if (done) done();
        return;
    }
    draft.keeping = YES;
    draft.problem = nil;
    [self.core.rows refresh];
    double keptAt = [self now];
    NSDictionary *record = ProcessRecord(draft.project, draft.lines, keptAt);
    NSString *folder = self.folder, *file = ProcessRecordName(draft.project);
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.queue, ^{
        NSString *problem = ProcessWrite(record, folder, file);
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf kept:draft for:sessionId record:record problem:problem];
            if (done) done();
        });
    });
}

// The note written, only you able to read it: whole or not at all, as it's written beside its place and then moved
// there. Why it couldn't be, in plain words, or nil.
static NSString *ProcessWrite(NSDictionary *record, NSString *folder, NSString *file) {
    if (!folder.length) return @"there's nowhere on this Mac to keep it";
    NSError *error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES
                                                  attributes:@{NSFilePosixPermissions: @0700} error:&error])
        return @"its folder for notes couldn't be made on this Mac";
    NSData *data = [NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingPrettyPrinted error:nil];
    NSString *path = [folder stringByAppendingPathComponent:file];
    NSString *beside = [path stringByAppendingString:@".new"];
    if (!data || ![NSFileManager.defaultManager createFileAtPath:beside contents:data
                                                      attributes:@{NSFilePosixPermissions: @0600}])
        return @"its folder for notes on this Mac may be full or locked";
    if (rename(beside.fileSystemRepresentation, path.fileSystemRepresentation) != 0) {
        [NSFileManager.defaultManager removeItemAtPath:beside error:nil];
        return @"its folder for notes on this Mac may be full or locked";
    }
    return nil;
}

// Keep It's write came back: the note is the project's now, and every other draft waiting for the project is taken
// back, as it was drafted against the note before; or the draft waits on, saying why, for Try Again.
- (void)kept:(ProcessDraft *)draft for:(NSString *)sessionId record:(NSDictionary *)record problem:(NSString *)problem {
    if (self.drafts[sessionId] != draft) return;
    draft.keeping = NO;
    if (problem) {
        draft.problem = problem;
        PanelLog(@"%@: Keep It for how %@ works: couldn't keep it", sessionId, draft.name);
        [self.core.rows refresh];
        return;
    }
    self.records[draft.project] = record;
    [self.declined removeObjectForKey:draft.project];
    [self.drafts removeObjectForKey:sessionId];
    [self.outcomes removeObjectForKey:sessionId];
    NSUInteger others = 0;
    for (NSString *other in self.drafts.allKeys) {
        if (![self.drafts[other].project isEqual:draft.project] || self.drafts[other].keeping) continue;
        [self.drafts removeObjectForKey:other];
        self.outcomes[other] = @"keptElsewhere";
        others++;
    }
    PanelLog(@"%@: Keep It for how %@ works: kept, %lu lines%@", sessionId, draft.name,
             (unsigned long)draft.lines.count,
             others ? [NSString stringWithFormat:@", %lu other draft%@ taken back", (unsigned long)others,
                                                 others == 1 ? @"" : @"s"] : @"");
    [self.core.rows refresh];
}

- (NSDictionary<NSString *, void (^)(NSDictionary *message)> *)messages {
    __weak typeof(self) weakSelf = self;
    return @{
        // Keep It (or Try Again) or Not Now on a draft's card, for the draft that card showed.
        @"processAnswer": ^(NSDictionary *msg) {
            [weakSelf answer:AsText(msg[@"act"]) for:AsText(msg[@"sessionId"]) at:AsNumber(msg[@"at"]) done:nil];
        },
    };
}

#pragma mark The rows

- (void)rows:(NSArray<Row *> *)rows phase:(RowPhase)phase {
    if (phase != RowPhaseListed) return;
    for (Row *row in rows) {
        NSString *sessionId = row.sessionId;
        if (!sessionId) continue;
        ProcessDraft *draft = self.drafts[sessionId];
        // A session that has ended takes its draft with it, unless Keep It is writing it already.
        if (![self runs:row]) {
            if (draft && !draft.keeping) {
                [self.drafts removeObjectForKey:sessionId];
                PanelLog(@"%@: its draft of how %@ works was taken back, as its session ended", sessionId, draft.name);
                draft = nil;
            }
            [self.outcomes removeObjectForKey:sessionId];
        }
        double keptAt = 0;
        NSArray<NSString *> *kept = draft ? [self keptFor:draft.project at:&keptAt] : nil;
        // "You said Not Now" only on a draft that changes something the declined one didn't, as the card says so.
        NSDictionary *declined = draft ? self.declined[draft.project] : nil;
        BOOL holdsNew = declined && ProcessHoldsNew(draft.lines, declined[@"lines"], kept);
        row.processDraft = ProcessDraftShown(draft, kept, keptAt,
                                             holdsNew ? AsNumber(declined[@"at"]).doubleValue : 0);
    }
}

#pragma mark How a project works, for other modules

- (NSDictionary *)wayFor:(Row *)row {
    NSString *project = ProcessProject(row.git, row.cwd);
    if (!project) return nil;
    double keptAt = 0;
    NSArray<NSString *> *kept = [self keptFor:project at:&keptAt];
    NSString *state = self.drafts[row.sessionId ?: @""] ? @"waiting" : self.outcomes[row.sessionId ?: @""];
    NSArray<NSString *> *pages = ProcessPages(ProcessCheckout(row.git, row.cwd),
                                              [self.core agentOf:row].instructionPages);
    return ProcessWay(ProcessProjectName(project), pages, kept, keptAt, state);
}

@end
