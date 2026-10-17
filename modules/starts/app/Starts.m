// Starts: new conversations started from the panel's card, in Claude Desktop or a terminal. The folder's trust is
// checked first (and recorded once you've said yes on the card), the session is opened with your words, and it's
// watched for until it's listed, when the page's pending row becomes its row.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// A terminal start runs Claude Code with a session id the page chose, so its row has that id from the start, and the
// page's pending row already has the row's key. Claude Desktop picks its own id: its log says which new conversation it
// started, and where, and the first since the start is the start's, wherever Claude put it (it can start one with "No
// folder", in a folder of its own). Without that line, it's the first conversation that shows up in the folder after
// the start, among those running. Either way the page is told its id.
#import "Starts.h"
#import "Page.h"
#import "PanelWindow.h"
#import "Core.h"
#import "Row.h"
#import "Files.h"
#import "Menus.h"
#import "Log.h"

// How long a start is waited for before the page is told it didn't come (Claude may have to open first); how long once
// its words are left in Claude's box for you to press Send there; and the most words that go with one.
static const NSTimeInterval kStartWait = 45, kSendWait = 120;
static const NSUInteger kWordsMax = 50000;

// A start that hasn't shown up yet: what it opened, where, and the Claude Desktop conversations already in that folder
// then, so the new one can be told apart.
@interface Start : NSObject
@property (copy) NSString *startId, *sessionId, *folder, *app, *wordsFile;
@property (copy) NSString *conversation;  // the Claude Desktop conversation Claude's log says it became
@property (assign) NSTimeInterval at, until;  // when it was started, and when it's given up on
@property (assign) BOOL stay;  // started with ⌘Return: the card for the next one is up, and keeps the keyboard
@property (copy) NSSet<NSString *> *known;
@end

@implementation Start
@end

// An id the page made up for a start: letters, digits and dashes, and short.
static NSString *StartId(id value) {
    if (![value isKindOfClass:NSString.class] || ![value length] || [value length] > 64) return nil;
    NSCharacterSet *other = [NSCharacterSet characterSetWithCharactersInString:
                             @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"].invertedSet;
    return [value rangeOfCharacterFromSet:other].location == NSNotFound ? value : nil;
}

// A folder the page names: an absolute path to a folder that's there.
static NSString *Folder(id value) {
    BOOL folder = NO;
    if (![value isKindOfClass:NSString.class] || ![value isAbsolutePath]) return nil;
    return [NSFileManager.defaultManager fileExistsAtPath:value isDirectory:&folder] && folder ? value : nil;
}

@interface Starts ()
@property (weak) Core *core;
@property (strong) dispatch_queue_t queue;
@property (strong) NSMutableDictionary<NSString *, Start *> *waiting;  // by start id
@property (copy) NSArray<Row *> *rows;                                // as the last tick had them
@end

@implementation Starts

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.queue = dispatch_queue_create("whozmove.starts", DISPATCH_QUEUE_SERIAL);
    self.waiting = [NSMutableDictionary dictionary];
    // Words left from starts the panel quit before seeing through go now: each start's are its own.
    dispatch_async(self.queue, ^{
        [NSFileManager.defaultManager removeItemAtPath:AppDir(@"starts") error:nil];
    });
    return self;
}

// The terminal a start can open in: the first on this Mac that runs a command in a new tab and that the panel can type
// into, so it can tell which tab shows the session it started.
- (id<CommandHost>)terminal {
    for (id terminal in [self.core hostsThat:@protocol(CommandHost)])
        if ([terminal conformsToProtocol:@protocol(TypingHost)]
            && [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:[terminal appId]])
            return terminal;
    return nil;
}

// The agent a start runs (Claude Code): its command in a terminal, and whether it may work in the folder.
- (id<AgentStarts>)agent {
    return [self.core agentsThat:@protocol(AgentStarts)].firstObject;
}

// The app that keeps conversations of its own a start can open in (Claude Desktop), or nil.
- (id<ConversationHost>)desktop {
    return [self.core hostsThat:@protocol(ConversationHost)].firstObject;
}

- (NSDictionary *)options {
    return @{@"terminal": self.terminal.name ?: NSNull.null};
}

#pragma mark The card

- (void)checkFolder:(NSDictionary *)msg {
    NSString *folder = Folder(msg[@"folder"]);
    if (!folder) {
        if ([msg[@"folder"] isKindOfClass:NSString.class])
            [self.core.page call:@"folderChecked" with:@[msg[@"folder"], @{@"gone": @YES}]];
        return;
    }
    id<AgentStarts> agent = self.agent;
    dispatch_async(self.queue, ^{
        BOOL trusted = [agent folderTrusted:folder];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.core.page call:@"folderChecked" with:@[folder, @{@"trusted": @(trusted)}]];
        });
    });
}

// The folders a card can start in, as the page lists them (the projects of the sessions it shows, newest first), with
// the card's own ticked, and Choose Folder… for any other.
- (void)menu:(NSDictionary *)msg {
    NSMenu *menu = [NSMenu new];
    menu.autoenablesItems = NO;
    SayInMenu(menu, @"Start It In");
    NSArray *projects = [msg[@"projects"] isKindOfClass:NSArray.class] ? msg[@"projects"] : @[];
    for (NSDictionary *project in [projects subarrayWithRange:NSMakeRange(0, MIN(projects.count, 15))]) {
        if (![project isKindOfClass:NSDictionary.class] || !Folder(project[@"folder"])) continue;
        NSString *name = [project[@"name"] isKindOfClass:NSString.class] ? Clip(project[@"name"], 80)
                                                                          : [project[@"folder"] lastPathComponent];
        NSMenuItem *item = [menu addItemWithTitle:name action:@selector(pick:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = project[@"folder"];
        item.toolTip = project[@"folder"];
        if ([project[@"folder"] isEqual:msg[@"current"]]) item.state = NSControlStateValueOn;
    }
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItemWithTitle:@"Choose Folder…" action:@selector(choose:) keyEquivalent:@""].target = self;
    [self.core.window popUpMenu:menu atPagePoint:NSMakePoint([msg[@"x"] doubleValue], [msg[@"y"] doubleValue])];
}

- (void)pick:(NSMenuItem *)item {
    [self.core.page call:@"startProject" with:@[item.representedObject ?: @""]];
}

- (void)choose:(NSMenuItem *)item {
    NSOpenPanel *open = [NSOpenPanel openPanel];
    open.canChooseDirectories = YES;
    open.canChooseFiles = NO;
    open.canCreateDirectories = YES;
    open.prompt = @"Start Here";
    open.message = @"Choose the folder the new conversation starts in.";
    // The panel never takes the app forward; a folder chooser needs it in front.
    [NSRunningApplication.currentApplication activateWithOptions:0];
    [open beginWithCompletionHandler:^(NSModalResponse response) {
        if (response == NSModalResponseOK && open.URL.path)
            [self.core.page call:@"startProject" with:@[open.URL.path]];
    }];
}

#pragma mark Starting

- (void)start:(NSDictionary *)msg {
    NSString *startId = StartId(msg[@"startId"]), *folder = Folder(msg[@"folder"]), *app = msg[@"app"];
    if (!startId || self.waiting[startId]) return;
    // The page shows the start as a row until it hears how it went, so it hears even when nothing can start.
    void (^refuse)(NSString *) = ^(NSString *why) {
        PanelLog(@"start %@: didn't start: %@", startId, why);
        [self.core.page call:@"startUpdate" with:@[startId ?: @"", @{@"why": why}]];
    };
    if (!folder) return refuse(@"That folder isn't there any more");
    if (![@[@"desktop", @"terminal"] containsObject:app ?: @""]) return refuse(@"Whozmove can't start one there");
    NSString *sessionId = nil;
    if ([app isEqual:@"terminal"]) {
        // The id the page chose for the session, as Claude Code writes ids: a UUID, in lower case.
        sessionId = [msg[@"sessionId"] isKindOfClass:NSString.class] ? msg[@"sessionId"] : nil;
        if (![[NSUUID alloc] initWithUUIDString:sessionId ?: @""]) return refuse(@"Whozmove can't start one there");
        sessionId = sessionId.lowercaseString;
    }
    NSString *words = [msg[@"words"] isKindOfClass:NSString.class]
        ? Clip([msg[@"words"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet], kWordsMax)
        : @"";
    BOOL trust = [msg[@"trust"] isEqual:@YES];
    // A session is started, trusted and listed by its agent, and a conversation in Claude Desktop is that app's: with
    // either missing, nothing starts, rather than waiting for a row that can't come.
    if (!self.agent) return refuse(@"There's no agent here to start it with");
    if (!sessionId && !self.desktop) return refuse(@"There's no Claude Desktop here to start it in");
    // A Claude Desktop conversation with no words only opens: it's Claude's to list once something is sent in it, so
    // there's nothing to wait for, and the page shows no row for it.
    BOOL watch = sessionId || words.length;
    Start *start = [Start new];
    start.startId = startId;
    start.sessionId = sessionId;
    start.folder = RealPath(folder);
    start.app = app;
    start.at = NSDate.date.timeIntervalSince1970;
    start.until = start.at + kStartWait;
    start.stay = [msg[@"stay"] isEqual:@YES];
    NSMutableSet *known = [NSMutableSet set];
    for (Row *row in self.rows)
        if (row.hostSessionId && [RealPath(row.cwd ?: @"") isEqual:start.folder]) [known addObject:row.hostSessionId];
    start.known = known;
    self.waiting[startId] = start;
    PanelLog(@"start %@: %@ in %@%@", startId, app, folder, trust ? @", trusting it" : @"");
    id<AgentStarts> agent = self.agent;
    dispatch_async(self.queue, ^{
        NSString *why = trust ? [agent trustFolder:folder] : nil;
        BOOL trusted = !why && (trust || [agent folderTrusted:folder]);
        NSString *file = !why && sessionId && words.length ? [self keepWords:words for:sessionId] : nil;
        if (!why && sessionId && words.length && !file) why = @"Couldn't keep your words for the terminal";
        dispatch_async(dispatch_get_main_queue(), ^{
            if (why) return [self giveUp:startId why:why];
            start.wordsFile = file;
            if (sessionId) return [self openTerminal:start];
            if (!watch) [self.waiting removeObjectForKey:startId];
            [self.desktop startConversationIn:folder words:words trusted:trusted done:^(NSString *note) {
                if (!watch) {
                    if (note) [self.core.page call:@"startUpdate" with:@[startId ?: @"", @{@"why": note}]];
                    return;
                }
                // Claude may still start it (once you press Send there, say), so the start keeps waiting, long
                // enough for that; the pending row says why meanwhile.
                if (note && self.waiting[startId]) {
                    start.until = NSDate.date.timeIntervalSince1970 + kSendWait;
                    [self.core.page call:@"startUpdate" with:@[startId ?: @"", @{@"note": note}]];
                }
                // Claude came forward to send it; with the next card up, the keyboard comes back to that.
                if (!note && start.stay) [self.core.window takeKeyboard:YES];
            }];
        });
    });
}

// The words for a terminal start, kept in a file of their own in Whozmove's folder, which only you can read, until the
// session has started. Its path, or nil if it couldn't be written.
- (NSString *)keepWords:(NSString *)words for:(NSString *)sessionId {
    NSString *folder = AppDir(@"starts"), *path = [folder stringByAppendingPathComponent:
                                                  [sessionId stringByAppendingPathExtension:@"txt"]];
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES
                                             attributes:@{NSFilePosixPermissions: @0700} error:nil];
    if (![NSFileManager.defaultManager createFileAtPath:path contents:[words dataUsingEncoding:NSUTF8StringEncoding]
                                             attributes:@{NSFilePosixPermissions: @0600}])
        return nil;
    return path;
}

- (void)openTerminal:(Start *)start {
    id<CommandHost> terminal = self.terminal;
    if (!terminal) return [self giveUp:start.startId why:@"There's no terminal to start it in: Whozmove starts them in Ghostty"];
    NSString *command = [self.agent startCommand:start.sessionId wordsFile:start.wordsFile];
    if (!command) return [self giveUp:start.startId why:@"There's no agent here to start it with"];
    [terminal newTabIn:start.folder running:command named:nil forward:!start.stay];
    if (!start.stay && self.onTabForward) self.onTabForward(terminal, start.sessionId);
}

- (void)giveUp:(NSString *)startId why:(NSString *)why {
    Start *start = self.waiting[startId];
    if (!start) return;
    [self.waiting removeObjectForKey:startId];
    [self dropWords:start];
    PanelLog(@"start %@: didn't start: %@", startId, why);
    [self.core.page call:@"startUpdate" with:@[startId ?: @"", @{@"why": why}]];
}

- (void)dropWords:(Start *)start {
    if (!start.wordsFile) return;
    NSString *file = start.wordsFile;
    dispatch_async(self.queue, ^{ [NSFileManager.defaultManager removeItemAtPath:file error:nil]; });
}

- (void)watch:(NSArray<Row *> *)rows {
    self.rows = rows;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSArray<Start *> *waiting = [self.waiting.allValues sortedArrayUsingComparator:^(Start *a, Start *b) {
        return [@(a.at) compare:@(b.at)];
    }];
    // Each start in Claude Desktop takes the first new conversation Claude's log says it started since then (to the
    // second, as the log has it) that no earlier start has taken.
    NSMutableSet *taken = [NSMutableSet set];
    for (Start *start in waiting)
        if (start.conversation) [taken addObject:start.conversation];
    NSArray<NSDictionary *> *started = nil;
    for (Start *start in waiting) {
        if (start.sessionId || start.conversation) continue;
        if (!started) started = [self.desktop startedConversations] ?: @[];
        for (NSDictionary *conversation in started) {
            if ([conversation[@"at"] doubleValue] < floor(start.at) * 1000 || [taken containsObject:conversation[@"id"]])
                continue;
            start.conversation = conversation[@"id"];
            [taken addObject:start.conversation];
            PanelLog(@"start %@: Claude started %@ in %@", start.startId, start.conversation, conversation[@"folder"]);
            break;
        }
    }
    id<ConversationHost> desktop = self.desktop;
    for (Start *start in waiting) {
        Row *found = nil;
        for (Row *row in rows) {
            // A Claude Desktop conversation's row goes by Claude's own id until its Claude Code session is known, and
            // changes to that one then, so the start waits for it: its row keeps the id it's given.
            BOOL ours = start.sessionId ? [row.sessionId isEqual:start.sessionId]
                : start.conversation ? [row.hostSessionId isEqual:start.conversation] && ![desktop isOwnId:row.sessionId]
                : row.pid > 0 && [desktop holds:row] && row.hostSessionId
                  && ![start.known containsObject:row.hostSessionId] && [RealPath(row.cwd ?: @"") isEqual:start.folder];
            if (ours && row.sessionId) { found = row; break; }
        }
        if (found) {
            [self.waiting removeObjectForKey:start.startId];
            [self dropWords:start];
            PanelLog(@"start %@: started as %@", start.startId, found.sessionId);
            [self.core.page call:@"startUpdate" with:@[start.startId ?: @"", @{@"sessionId": found.sessionId}]];
            NSString *elsewhere = [self whereElse:found for:start];
            if (elsewhere) [self.core.page stepNote:found.sessionId text:elsewhere];
        } else if (now > start.until) {
            [self giveUp:start.startId why:[start.app isEqual:@"terminal"]
                ? [NSString stringWithFormat:@"Nothing started in %@: look there for what Claude Code says", self.terminal.name ?: @"the terminal"]
                : @"Claude didn't start the conversation: look in Claude for why"];
        }
    }
}

// Where Claude started a conversation, when it isn't the folder it was opened in: in words for under its row, which has
// moved to that folder's group. The app it started in says how one it started with no folder of yours is put.
- (NSString *)whereElse:(Row *)row for:(Start *)start {
    NSString *folder = RealPath(row.cwd ?: @""), *asked = start.folder.lastPathComponent;
    if (!folder.length || [folder isEqual:start.folder]) return nil;
    return [self.desktop startedWithoutFolder:folder asked:asked]
        ?: [NSString stringWithFormat:@"Claude started it in %@, not in %@", folder.lastPathComponent, asked];
}

@end
