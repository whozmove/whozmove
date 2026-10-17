// Focus: the session you're on, and opening a session.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Focus.h"
#import <AppKit/AppKit.h>
#import "Core.h"
#import "Rows.h"
#import "Row.h"
#import "Log.h"
#import "Processes.h"

@interface Focus ()
@property (weak) Core *core;
// Of the apps that say which session they show, the one in front last (cameToFront:), and the session in the tab that
// terminal shows, as it last answered. Each session opened from here counts, so an answer that was on its way before
// one isn't taken. The app each terminal session runs in, by ProcessKey.
@property (copy) NSString *frontLast, *terminalShows;
@property (assign) NSUInteger openings;
@property (copy) NSDictionary<NSString *, NSString *> *sessionApps;
@end

@implementation Focus

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    return self;
}

- (void)start {
    __weak typeof(self) weakSelf = self;
    [self cameToFront:NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceDidActivateApplicationNotification
                                                                object:nil queue:NSOperationQueue.mainQueue
                                                            usingBlock:^(NSNotification *note) {
        [weakSelf cameToFront:[note.userInfo[NSWorkspaceApplicationKey] bundleIdentifier]];
    }];
}

// Whether a host says which of its sessions it shows: a terminal by its answer (whichShows:done:), or an app that keeps
// its sessions as conversations, whose record says which it shows (marked as the rows are read).
static BOOL SaysWhatItShows(id<Host> host) {
    return [host respondsToSelector:@selector(whichShows:done:)] || [host conformsToProtocol:@protocol(ConversationHost)];
}

// A terminal that says which session's tab it shows.
static BOOL AnswersWhichShows(id<Host> host) {
    return [host respondsToSelector:@selector(whichShows:done:)];
}

// The session you're on is marked in the list: in Claude Desktop, the conversation it shows (marked as the rows are
// read), and in a terminal, the session in the tab it shows. Whichever of the two apps was in front last wins, except
// that Claude Desktop's stays marked while the terminal's tab holds none of the sessions listed (a plain shell), and the
// mark stays where it is while the terminal can't tell. The terminal is asked on each read while it's in front: behind,
// its tab changes only when the one showing closes, and then the session that was marked has ended anyway. It answers
// after the rows have gone, so a different answer sends them again. A print run (the tests) asks no app anything.
- (void)mark:(NSArray<Row *> *)rows {
    if (self.core.printing) return;
    id<Host> terminal = [self.core hostFor:NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier];
    if (AnswersWhichShows(terminal)) [self ask:terminal whichShows:rows];
    if (!AnswersWhichShows([self.core hostFor:self.frontLast]) || !self.terminalShows
        || ![[rows valueForKey:@"sessionId"] containsObject:self.terminalShows]) return;
    for (Row *row in rows) row.focused = [row.sessionId isEqualToString:self.terminalShows];
}

// Asks the terminal in front which of the sessions running in it its tab holds, unless none runs in it. A session
// never moves app, so which one each runs in is worked out once.
- (void)ask:(id<Host>)terminal whichShows:(NSArray<Row *> *)rows {
    NSMutableDictionary<NSString *, NSString *> *apps = [NSMutableDictionary dictionary];
    NSMutableArray<Row *> *inIt = [NSMutableArray array];
    for (Row *row in rows) {
        if ([self.core hostHolding:row] || row.pid <= 0) continue;
        NSString *key = ProcessKey(row.pid, row.procStart);
        apps[key] = self.sessionApps[key] ?: OwningApp(row.pid).bundleIdentifier;
        if ([apps[key] isEqualToString:terminal.appId]) [inIt addObject:row];
    }
    self.sessionApps = apps;
    if (!inIt.count) return;
    NSUInteger openings = self.openings;
    [terminal whichShows:inIt done:^(Row *shown) {
        if (openings != self.openings) return;  // a session was opened from here meanwhile
        if (shown.sessionId == self.terminalShows || [shown.sessionId isEqualToString:self.terminalShows]) return;
        self.terminalShows = shown.sessionId;
        [self.core.rows refresh];
    }];
}

// An app that says which session it shows came to the front, as macOS reports each switch: it's the app you were in last
// until another of them comes, and the list shows its session as the one you're on at once.
- (void)cameToFront:(NSString *)app {
    if (!app || [app isEqualToString:self.frontLast]) return;
    if (!SaysWhatItShows([self.core hostFor:app])) return;
    self.frontLast = app;
    [self.core.rows refresh];
}

- (void)open:(NSDictionary *)message {
    Row *row = [[Row alloc] initWithFields:message];
    id<Host> own = [self.core hostHolding:row];
    if (own) {
        // That app is the one you're in from now: a terminal's session isn't the one you're on while it comes forward.
        self.frontLast = own.appId;
        [own open:row];
        return;
    }
    // Terminal session: bring forward the app that owns its process tree (Terminal, iTerm, Ghostty, VS Code…).
    NSRunningApplication *app = OwningApp([message[@"pid"] intValue]);
    if (!app) {
        PanelLog(@"open terminal session pid %@ -> no owning app found", message[@"pid"]);
        NSBeep();
        return;
    }
    // Only a terminal finds a session's tab; any other app that owns the process (Claude Desktop running a session
    // it doesn't hold as its own, say) is just brought forward.
    id<Host> terminal = [self.core hostFor:app.bundleIdentifier];
    if ([terminal conformsToProtocol:@protocol(TypingHost)] && [(id<TypingHost>)terminal open:row]) {
        // At the session's own tab, so it's the one you're on now, without waiting for the terminal's next answer.
        [self tabCameForward:terminal session:row.sessionId];
        [self.core.rows refresh];
        return;
    }
    [app activateWithOptions:NSApplicationActivateAllWindows];
    PanelLog(@"open terminal session pid %@ -> activated %@", message[@"pid"], app.localizedName);
}

- (void)tabCameForward:(id<Host>)host session:(NSString *)sessionId {
    self.frontLast = host.appId;
    self.terminalShows = sessionId;
    self.openings++;
}

@end
