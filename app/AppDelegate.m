// AppDelegate: the app itself. It creates the pieces and wires them together, runs the 1-second tick and opens
// sessions.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "AppDelegate.h"
#import "Log.h"
#import "Files.h"
#import "Processes.h"
#import "Asks.h"
#import "Row.h"
#import "DesktopConversations.h"
#import "Sessions.h"
#import "Transcripts.h"
#import "PullRequests.h"
#import "Checkouts.h"
#import "AgentDetails.h"
#import "Page.h"
#import "PanelWindow.h"
#import "MenuBar.h"
#import "Terminal.h"
#import "Ghostty.h"
#import "ClaudeDesktop.h"
#import "Commands.h"

@interface AppDelegate ()
// What's listed, and what's known about it. These are all a test run needs, so they're made with the delegate.
@property (strong) DesktopConversations *conversations;
@property (strong) Sessions *sessions;
@property (strong) Transcripts *transcripts;
@property (strong) PullRequests *pullRequests;
@property (strong) Checkouts *checkouts;
@property (strong) AgentDetails *agentDetails;
@property (assign) NSTimeInterval lastRead;  // when the transcripts were last read
@property (assign) BOOL reading;             // the rows are being read now
@property (assign) BOOL readAgain;           // and a tick came meanwhile
// What's on screen, and what acts on sessions: made once the app has started.
@property (strong) Page *page;
@property (strong) PanelWindow *window;
@property (strong) MenuBar *menuBar;
@property (copy) NSArray<id<Terminal>> *terminals;  // the ones the panel can type into
@property (strong) ClaudeDesktop *claudeDesktop;
@property (strong) Commands *commands;
@property (strong) NSTimer *timer;
@end

@implementation AppDelegate

- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.conversations = [DesktopConversations new];
    self.sessions = [[Sessions alloc] initWithConversations:self.conversations];
    self.transcripts = [Transcripts new];
    self.pullRequests = [[PullRequests alloc] initWithTranscripts:self.transcripts];
    __weak PullRequests *pullRequests = self.pullRequests;
    self.transcripts.onPRLinks = ^{ [pullRequests check]; };
    self.checkouts = [Checkouts new];
    self.agentDetails = [AgentDetails new];
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    // Whozmove's folder holds the prompts, Claude's replies and the requests waiting for an answer (with what a
    // tool would write), so only its owner may read it, as with Claude Code's own files. The hooks make it too,
    // but the panel may start first.
    NSString *home = AppDir(nil);
    [NSFileManager.defaultManager createDirectoryAtPath:home withIntermediateDirectories:YES
                                             attributes:@{NSFilePosixPermissions: @0700} error:nil];
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0700} ofItemAtPath:home error:nil];
    // The permission hook asks here only while the panel runs; this tells it the panel does.
    [[NSString stringWithFormat:@"%d", getpid()] writeToFile:AppDir(@"panel.pid") atomically:YES
                                                 encoding:NSUTF8StringEncoding error:nil];
    self.page = [Page new];
    self.window = [[PanelWindow alloc] initWithPage:self.page];
    self.menuBar = [[MenuBar alloc] initWithWindow:self.window page:self.page];
    self.terminals = @[[[Ghostty alloc] initWithTranscripts:self.transcripts]];
    self.claudeDesktop = [[ClaudeDesktop alloc] initWithConversations:self.conversations window:self.window];
    self.commands = [[Commands alloc] initWithPage:self.page window:self.window agentDetails:self.agentDetails
                                       transcripts:self.transcripts terminals:self.terminals
                                     claudeDesktop:self.claudeDesktop];
    __weak typeof(self) weakSelf = self;
    self.commands.onChange = ^{ [weakSelf refresh]; };
    self.page.onLoad = ^{ [weakSelf pageLoaded]; };
    self.page.onMessage = ^(NSString *type, NSDictionary *msg) { [weakSelf page:type said:msg]; };
    [self.page load];
    [self.window show];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(refresh)
                                                userInfo:nil repeats:YES];
    self.timer.tolerance = 0.3;
}

- (void)applicationWillTerminate:(NSNotification *)note {
    NSString *pidFile = AppDir(@"panel.pid");
    if ([[NSString stringWithContentsOfFile:pidFile encoding:NSUTF8StringEncoding error:nil] intValue] == getpid())
        [NSFileManager.defaultManager removeItemAtPath:pidFile error:nil];
}

#pragma mark The page

// A freshly loaded page (at the start, or after a reload) learns how tall it can grow and how it's grouped, and
// gets its rows at once.
- (void)pageLoaded {
    [self.window resendRoom];
    [self.menuBar applySavedGrouping];
    [self refresh];
}

// Each of the page's messages, to the piece that handles it.
- (void)page:(NSString *)type said:(NSDictionary *)msg {
    if ([type isEqualToString:@"height"]) {
        [self.window fitHeight:[msg[@"value"] doubleValue]];
    } else if ([type isEqualToString:@"open"]) {
        [self openSession:msg];
    } else if ([type isEqualToString:@"newSession"]) {
        [self newSessionIn:msg[@"folder"] inTerminal:[msg[@"terminal"] boolValue]];
    } else if ([type isEqualToString:@"pick"]) {
        [self.commands pick:msg];
    } else if ([type isEqualToString:@"compact"]) {
        [self.commands compact:msg];
    } else if ([type isEqualToString:@"switchAnswer"]) {
        [self.commands answerSwitch:msg];
    } else if ([type isEqualToString:@"answerAsk"]) {
        AnswerAsk(msg);
    } else if ([type isEqualToString:@"openPR"]) {
        NSURL *url = [NSURL URLWithString:msg[@"url"]];
        if ([url.scheme isEqualToString:@"https"]) [NSWorkspace.sharedWorkspace openURL:url];
    } else if ([type isEqualToString:@"keyboard"]) {
        [self.window takeKeyboard:[msg[@"on"] boolValue]];
    } else if ([type isEqualToString:@"badge"]) {
        [self.menuBar showCount:[msg[@"value"] integerValue]];
    }
}

#pragma mark The tick

// Once a second, and whenever a row has something new to show. The rows are read alongside and sent once they're
// back; a tick that comes while they're being read waits for them, then reads again.
- (void)refresh {
    if (!self.page.ready) return;
    if (self.reading) {
        self.readAgain = YES;
        return;
    }
    self.reading = YES;
    [self readRows:^(NSArray<Row *> *rows) {
        self.reading = NO;
        if (rows && self.page.ready) [self sendRows:rows];
        if (self.readAgain) {
            self.readAgain = NO;
            [self refresh];
        }
    }];
}

- (void)sendRows:(NSArray<Row *> *)rows {
    NSArray *json = [rows valueForKey:@"json"];
    NSError *error = nil;
    NSData *data = [NSJSONSerialization isValidJSONObject:json]
        ? [NSJSONSerialization dataWithJSONObject:json options:0 error:&error] : nil;
    if (!data) {
        LogProblem([@"rows not sent: " stringByAppendingString:error.localizedDescription ?: @"not JSON"]);
        return;
    }
    [self.page update:data];
}

// The sessions' files are read on Sessions' queue, and what the other pieces know is added here. An exception
// left to escape would end the app, so one is logged instead, and the next tick tries again.
- (void)readRows:(void (^)(NSArray<Row *> *rows))done {
    [self.sessions read:^(NSArray<Row *> *sessions) {
        NSArray<Row *> *rows = nil;
        @try {
            if (sessions) rows = [self completed:sessions];
        } @catch (NSException *e) {
            LogProblem([NSString stringWithFormat:@"rows not built: %@: %@", e.name, e.reason]);
        }
        done(rows);
    }];
}

// Each session's transcript, PRs, checkout, a compaction sent from the panel, and its agent's details. Also starts
// the transcript, git and gh reads that run alongside; what they find shows in the rows from a later call on.
- (NSArray<Row *> *)completed:(NSArray<Row *> *)sessions {
    self.transcripts.sessionIds = [sessions valueForKey:@"sessionId"];
    // Every 10s: what's new in the transcripts, then the PRs due a check.
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (now - self.lastRead >= 10) {
        self.lastRead = now;
        [self.transcripts readNew];
        [self.pullRequests check];
    }
    [self.checkouts refreshFor:sessions];
    for (Row *row in sessions) {
        NSString *sid = row.sessionId;
        NSDictionary *transcript = [self.transcripts stateOf:sid];
        row.prs = [self.pullRequests prsFor:sid];
        NSString *root = (row.workGit ?: row.git)[@"root"];  // where its work is
        if (root && [self.checkouts stateOf:root]) row.checkout = [self.checkouts stateOf:root];
        if (transcript[@"messageAt"]) row.messageAt = transcript[@"messageAt"];
        if ([self.commands compactingSince:sid]) row.compacting = [self.commands compactingSince:sid];
        [self.agentDetails describe:row transcript:transcript chosen:[self.commands chosenFor:sid]];
    }
    NSMutableDictionary *byId = [NSMutableDictionary dictionary];
    for (Row *row in sessions)
        if (row.sessionId) byId[row.sessionId] = row;
    self.commands.rowsById = byId;
    [self.commands keepPicksOf:sessions];
    [self.agentDetails keepFlagsOf:sessions];
    return sessions;
}

#pragma mark Opening sessions

// A row the page sent back, when it was clicked.
- (void)openSession:(NSDictionary *)msg {
    Row *row = [[Row alloc] initWithFields:msg];
    if ([row.entrypoint isEqualToString:@"claude-desktop"]) {
        [self.claudeDesktop open:row];
        return;
    }
    // Terminal session: bring forward the app that owns its process tree (Terminal, iTerm, Ghostty, VS Code…).
    NSRunningApplication *app = OwningApp([msg[@"pid"] intValue]);
    if (!app) {
        PanelLog(@"open terminal session pid %@ -> no owning app found", msg[@"pid"]);
        NSBeep();
        return;
    }
    if ([TerminalFor(self.terminals, app.bundleIdentifier) focus:row]) return;  // at the session's own tab
    [app activateWithOptions:NSApplicationActivateAllWindows];
    PanelLog(@"open terminal session pid %@ -> activated %@", msg[@"pid"], app.localizedName);
}

// The ＋ on a project group: a new Claude Desktop session in that folder (the same link as Claude's own
// "new session in folder"), or with ⌥, a new tab there running `claude`, in the first terminal the panel knows.
- (void)newSessionIn:(NSString *)folder inTerminal:(BOOL)terminal {
    if (![folder isKindOfClass:NSString.class] || !folder.isAbsolutePath) return;
    if (terminal) [self.terminals.firstObject newTabIn:folder];
    else [self.claudeDesktop newConversationIn:folder];
}

@end
