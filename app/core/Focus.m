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
// The session you're looking at (lookingAt:) and since when, and when you were last looking at each session you
// stayed on (noteSeen:).
@property (copy) NSString *looking;
@property (assign) double lookingSince;
@property (strong) NSMutableDictionary<NSString *, NSNumber *> *seenAt;
@end

// How long you stay on a session before it counts as seen: tabs passed on the way to another don't. And how long
// without the keyboard or the mouse until you're taken to be away from the Mac.
static const double kSeenAfterMs = 2000, kAwayAfterSeconds = 5 * 60;

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

// Whether you're at the Mac: your session on the screen, unlocked (macOS's record of the session says so in a key it
// doesn't document) and awake, and the keyboard or the mouse used in the last few minutes.
static BOOL AtTheMac(void) {
    NSDictionary *session = CFBridgingRelease(CGSessionCopyCurrentDictionary());
    if (![session[(__bridge NSString *)kCGSessionOnConsoleKey] boolValue]
        || [session[@"CGSSessionScreenIsLocked"] boolValue] || CGDisplayIsAsleep(CGMainDisplayID()))
        return NO;
    return CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateHIDSystemState, kCGAnyInputEventType)
        < kAwayAfterSeconds;
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
    if (AnswersWhichShows([self.core hostFor:self.frontLast]) && [self listed:self.terminalShows in:rows])
        for (Row *row in rows) row.focused = [row.sessionId isEqualToString:self.terminalShows];
    [self noteSeen:rows];
}

- (BOOL)listed:(NSString *)sessionId in:(NSArray<Row *> *)rows {
    return sessionId && [[rows valueForKey:@"sessionId"] containsObject:sessionId];
}

// When you last looked at each session, for the page to count what it replied before then as read: you stayed on it
// for a moment, in the app in front, while at the Mac. So a reply you watch come in counts, and so does one you
// switch to, but not one marked as the one you're on while you're somewhere else: Claude's conversation while the
// terminal in front shows a plain shell, or while you're in another app.
- (void)noteSeen:(NSArray<Row *> *)rows {
    NSString *on = [self lookingAt:rows];
    double now = NSDate.date.timeIntervalSince1970 * 1000;
    if (!(on == self.looking || [on isEqualToString:self.looking])) {
        self.looking = on;
        self.lookingSince = now;
    } else if (on && now - self.lookingSince >= kSeenAfterMs) {
        if (!self.seenAt) self.seenAt = [NSMutableDictionary dictionary];
        self.seenAt[on] = @(now);
    }
    for (Row *row in rows) row.seenAt = self.seenAt[row.sessionId];
}

// The session you're looking at, if any: the one the app in front shows (the session in the terminal's tab, or the
// conversation Claude Desktop shows), while you're at the Mac.
- (NSString *)lookingAt:(NSArray<Row *> *)rows {
    if (!AtTheMac()) return nil;
    id<Host> front = [self.core hostFor:NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier];
    if (!front || !SaysWhatItShows(front)) return nil;
    if (AnswersWhichShows(front)) return [self listed:self.terminalShows in:rows] ? self.terminalShows : nil;
    for (Row *row in rows)
        if (row.focused && [self.core hostHolding:row] == front) return row.sessionId;
    return nil;
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
