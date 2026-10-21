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
#import "Worktrees.h"

// How long a start is waited for before the page is told it didn't come (Claude may have to open first); how long once
// its words are left in Claude's box for you to press Send there; how long a terminal's new tab is waited for, as macOS
// may first ask you whether Whozmove may control the terminal; and the most words that go with one.
static const NSTimeInterval kStartWait = 45, kSendWait = 120, kTabWait = 300;
static const NSUInteger kWordsMax = 50000;

// A start that hasn't shown up yet: what it opened, where, and the Claude Desktop conversations already in that folder
// then, so the new one can be told apart.
@interface Start : NSObject
@property (copy) NSString *startId, *sessionId, *folder, *app, *wordsFile;
@property (strong) id<CommandHost> terminal;  // the one it starts in, when it's a terminal's
@property (assign) BOOL tabOpened;             // and whether its tab has opened there
@property (copy) NSString *conversation;  // the Claude Desktop conversation Claude's log says it became
@property (assign) NSTimeInterval at, until;  // when it was started, and when it's given up on
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
@property (strong) Worktrees *worktrees;
@end

@implementation Starts

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.queue = dispatch_queue_create("whozmove.starts", DISPATCH_QUEUE_SERIAL);
    self.waiting = [NSMutableDictionary dictionary];
    self.worktrees = [[Worktrees alloc] initWithCore:core];
    // Words left from starts the panel quit before seeing through go now: each start's are its own.
    dispatch_async(self.queue, ^{
        [NSFileManager.defaultManager removeItemAtPath:AppDir(@"starts") error:nil];
    });
    return self;
}

// The terminals a start can open in, and the one it opens in: the one you picked on the card's menu while it's on this
// Mac, else the first (the core's, as an ended session opens again there too).
- (NSArray<id<CommandHost>> *)terminals {
    return self.core.startTerminals;
}

- (id<CommandHost>)terminal {
    return self.core.startTerminal;
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
    BOOL desktop = self.desktop.tracked;
    return @{@"terminal": self.terminal.name ?: NSNull.null, @"desktop": @(desktop),
             @"choice": @((desktop ? 1 : 0) + self.terminals.count > 1)};
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

// What the card's folder's repo has, for its # list: its own folder, its worktrees, its branches with no folder, and
// the branch a new worktree starts from (branchesListed).
- (void)listBranches:(NSDictionary *)msg {
    NSString *folder = Folder(msg[@"folder"]);
    if (!folder) return;
    Worktrees *worktrees = self.worktrees;
    dispatch_async(self.queue, ^{
        NSDictionary *found = [worktrees listIn:folder];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.core.page call:@"branchesListed" with:@[msg[@"folder"], found]];
        });
    });
}

// Whether a new worktree on the card can be made, {folder, name, base}, asked as its name or base changes: answered
// with where it would go, or why it can't (worktreeNameChecked).
- (void)checkWorktreeName:(NSDictionary *)msg {
    NSString *folder = Folder(msg[@"folder"]), *name = AsText(msg[@"name"]), *base = AsText(msg[@"base"]);
    if (!folder || !name) return;
    Worktrees *worktrees = self.worktrees;
    NSDictionary *target = base ? @{@"kind": @"new", @"name": name, @"base": base} : @{@"kind": @"new", @"name": name};
    dispatch_async(self.queue, ^{
        NSDictionary *found = [worktrees check:target in:folder];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.core.page call:@"worktreeNameChecked" with:@[msg[@"folder"], name, found]];
        });
    });
}

// The card's small menus, opened from what was pressed: `app`, the app it starts in (Claude Desktop, while its
// sessions are tracked, or one of the terminals; a worktree starts in a terminal); `places`, where a repo's new
// worktrees go; `choose`, a folder chooser for any other folder.
- (void)menu:(NSDictionary *)msg {
    NSString *kind = AsText(msg[@"kind"]);
    if ([kind isEqual:@"choose"]) return [self choose:nil];
    NSMenu *menu = [NSMenu new];
    menu.autoenablesItems = NO;
    if ([kind isEqual:@"app"]) {
        BOOL worktree = [msg[@"worktree"] isEqual:@YES], desktop = self.desktop.tracked;
        NSArray<id<CommandHost>> *terminals = self.terminals;
        NSString *ticked = [msg[@"app"] isEqual:@"terminal"] || !desktop ? self.terminal.appId : @"desktop";
        NSMutableArray<NSArray *> *apps = [NSMutableArray array];
        if (desktop) [apps addObject:@[@"desktop", @"Claude Desktop"]];
        for (id<CommandHost> terminal in terminals) [apps addObject:@[terminal.appId, terminal.name]];
        SayInMenu(menu, @"Start It In");
        for (NSArray *app in apps) {
            NSMenuItem *item = [menu addItemWithTitle:app[1] action:@selector(pickApp:) keyEquivalent:@""];
            item.target = self;
            item.representedObject = app[0];
            item.enabled = !(worktree && [app[0] isEqual:@"desktop"]);
            if ([app[0] isEqual:ticked]) item.state = NSControlStateValueOn;
        }
        if (worktree && terminals.count)
            SayInMenu(menu, [NSString stringWithFormat:@"Worktrees start in %@",
                                                       terminals.count > 1 ? @"a terminal" : self.terminal.name]);
    } else if ([kind isEqual:@"places"]) {
        NSString *repo = Folder(msg[@"repo"]);
        if (!repo) return;
        [self addWorktreesMenuTo:menu for:repo];
    } else return;
    [self.core.window popUpMenu:menu atPagePoint:NSMakePoint([msg[@"x"] doubleValue], [msg[@"y"] doubleValue])];
}

// Claude Desktop or a terminal, picked on the card's menu. A terminal is where starts in a terminal open from now on,
// so the page is told its name first.
- (void)pickApp:(NSMenuItem *)item {
    NSString *app = item.representedObject ?: @"desktop";
    if (![app isEqual:@"desktop"]) {
        [self.core pickStartTerminal:app];
        [self.core.page call:@"setStartOptions" with:@[self.options]];
    }
    [self.core.page call:@"startAppChosen" with:@[[app isEqual:@"desktop"] ? @"desktop" : @"terminal"]];
}

// Where a repo's new worktrees go: the folder beside it, or a folder you chose, with the one in use ticked.
- (void)addWorktreesMenuTo:(NSMenu *)menu for:(NSString *)repo {
    SayInMenu(menu, [NSString stringWithFormat:@"New Worktrees of %@ Go In", Clip(repo.lastPathComponent, 60)]);
    NSString *chosen = [self.worktrees chosenFor:repo], *own = [Worktrees besideFolderFor:repo];
    for (NSString *folder in chosen ? @[own, chosen] : @[own]) {
        if (!folder) continue;
        NSMenuItem *item = [menu addItemWithTitle:[Worktrees shown:folder] action:@selector(placeWorktrees:)
                                    keyEquivalent:@""];
        item.target = self;
        item.representedObject = @{@"repo": repo, @"folder": folder == own ? @"" : folder};
        if (folder == (chosen ?: own)) item.state = NSControlStateValueOn;
    }
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *choose = [menu addItemWithTitle:@"Choose Folder…" action:@selector(chooseWorktrees:) keyEquivalent:@""];
    choose.target = self;
    choose.representedObject = repo;
}

- (void)placeWorktrees:(NSMenuItem *)item {
    NSString *repo = item.representedObject[@"repo"], *folder = item.representedObject[@"folder"];
    [self.worktrees choose:folder.length ? folder : nil for:repo];
    [self.core.page call:@"worktreesMoved" with:@[repo]];
}

- (void)chooseWorktrees:(NSMenuItem *)item {
    NSString *repo = item.representedObject;
    NSOpenPanel *open = [NSOpenPanel openPanel];
    open.canChooseDirectories = YES;
    open.canChooseFiles = NO;
    open.canCreateDirectories = YES;
    open.prompt = @"Put Them Here";
    open.message = [NSString stringWithFormat:@"Choose the folder new worktrees of %@ go in.", repo.lastPathComponent];
    [NSRunningApplication.currentApplication activateWithOptions:0];
    [open beginWithCompletionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK || !open.URL.path) return;
        [self.worktrees choose:open.URL.path for:repo];
        [self.core.page call:@"worktreesMoved" with:@[repo]];
    }];
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
    // Where in the repo it starts, unless in its own folder: a worktree that's there (open), a new worktree for a
    // branch that's there (branch), or for a new branch (new), made first. All in the terminal, as Claude Desktop
    // starts only in the folders it lists.
    NSDictionary *target = AsRecord(msg[@"target"]);
    NSString *kind = AsText(target[@"kind"]);
    if (target && ![@[@"open", @"branch", @"new"] containsObject:kind ?: @""]) return refuse(@"Whozmove can't start one there");
    if (target && !sessionId) return refuse(@"Worktrees start in the terminal");
    // A session is started, trusted and listed by its agent, and a conversation in Claude Desktop is that app's: with
    // either missing, or Claude Desktop's sessions not tracked, nothing starts, rather than waiting for a row that
    // can't come.
    if (!self.agent) return refuse(@"There's no agent here to start it with");
    if (!sessionId && !self.desktop.tracked) return refuse(@"Whozmove doesn't track Claude Desktop's sessions here");
    // A Claude Desktop conversation with no words only opens: it's Claude's to list once something is sent in it, so
    // there's nothing to wait for, and the page shows no row for it.
    BOOL watch = sessionId || words.length;
    Start *start = [Start new];
    start.startId = startId;
    start.sessionId = sessionId;
    start.folder = RealPath(folder);
    start.app = app;
    start.terminal = sessionId ? self.terminal : nil;
    start.at = NSDate.date.timeIntervalSince1970;
    start.until = start.at + kStartWait;
    NSMutableSet *known = [NSMutableSet set];
    // A conversation open in Claude Desktop and a terminal is known by its Claude copy too, whichever its row shows.
    for (Row *row in self.rows) {
        if (![RealPath(row.cwd ?: @"") isEqual:start.folder]) continue;
        if (row.hostSessionId) [known addObject:row.hostSessionId];
        for (NSDictionary *copy in row.alsoOpen)
            if (AsText(copy[@"hostSessionId"])) [known addObject:copy[@"hostSessionId"]];
    }
    start.known = known;
    self.waiting[startId] = start;
    PanelLog(@"start %@: %@ in %@%@%@", startId, app, folder, trust ? @", trusting it" : @"",
             kind ? [NSString stringWithFormat:@", in a worktree (%@ %@)", kind, AsText(target[@"name"]) ?: AsText(target[@"path"]) ?: @""] : @"");
    id<AgentStarts> agent = self.agent;
    Worktrees *worktrees = self.worktrees;
    dispatch_async(self.queue, ^{
        NSString *why = trust ? [agent trustFolder:folder] : nil;
        BOOL trusted = !why && (trust || [agent folderTrusted:folder]);
        NSDictionary *made = nil;
        if (!why && [kind isEqual:@"open"]) {
            NSString *path = [worktrees openPath:target[@"path"] in:folder];
            made = path ? @{@"path": path} : @{@"why": @"That worktree isn't there any more"};
        } else if (!why && kind) made = [worktrees make:target in:folder];
        if (made[@"why"]) why = made[@"why"];
        NSString *file = !why && sessionId && words.length ? [self keepWords:words for:sessionId] : nil;
        if (!why && sessionId && words.length && !file) why = @"Couldn't keep your words for the terminal";
        dispatch_async(dispatch_get_main_queue(), ^{
            if (why) return [self giveUp:startId why:why];
            start.wordsFile = file;
            // Making the worktree took its time (the repo's hooks run): the wait for the session starts now.
            if (made[@"path"]) {
                PanelLog(@"start %@: starts in %@", startId, made[@"path"]);
                start.folder = made[@"path"];
                start.until = NSDate.date.timeIntervalSince1970 + kStartWait;
            }
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

// The start's wait for its session begins once its tab has opened, as macOS may first ask you whether Whozmove may
// control the terminal, and until then its words are kept. A tab that didn't open says why at once, and only an open
// tab is taken for the one you're on.
- (void)openTerminal:(Start *)start {
    id<CommandHost> terminal = start.terminal;
    if (!terminal)
        return [self giveUp:start.startId
                        why:@"There's no terminal to start it in: Whozmove starts them in Ghostty or iTerm2"];
    NSString *command = [self.agent startCommand:start.sessionId wordsFile:start.wordsFile];
    if (!command) return [self giveUp:start.startId why:@"There's no agent here to start it with"];
    NSString *startId = start.startId;
    start.until = NSDate.date.timeIntervalSince1970 + kTabWait;
    [terminal newTabIn:start.folder running:command named:nil forward:YES done:^(NSString *why) {
        if (self.waiting[startId] != start) return;  // given up on meanwhile
        if (why) return [self giveUp:startId why:why];
        start.tabOpened = YES;
        start.until = NSDate.date.timeIntervalSince1970 + kStartWait;
        if (self.onTabForward) self.onTabForward(terminal, start.sessionId);
    }];
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
            NSString *terminal = start.terminal.name ?: @"the terminal";
            [self giveUp:start.startId why:![start.app isEqual:@"terminal"]
                ? @"Claude didn't start the conversation: look in Claude for why"
                : start.tabOpened ? [NSString stringWithFormat:@"Nothing started in %@: look there for what Claude "
                                                               @"Code says", terminal]
                : [NSString stringWithFormat:@"%@ didn't open a tab for it", terminal]];
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
