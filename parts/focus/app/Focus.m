// Focus: the session you're on, and opening a session.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Focus.h"
#import <AppKit/AppKit.h>
#import "Core.h"
#import "PanelWindow.h"
#import "Page.h"
#import "Rows.h"
#import "Files.h"
#import "Row.h"
#import "Log.h"
#import "Processes.h"
#import "Module.h"
#import "Send.h"

// An ended session being opened again from here: the terminal it opens in, whether that has opened its tab yet, and
// since and until when it's waited for, first for the tab, then for its agent to be running in it.
@interface Reopening : NSObject
@property (copy) NSString *where;
@property (assign) BOOL tabOpened;
@property (assign) NSTimeInterval since, until;
@end

@implementation Reopening
@end

@interface Focus ()
@property (weak) Core *core;
// Of the apps that say which session they show, the one in front last (cameToFront:), and the session in the tab each
// terminal shows, as it last answered, by its app id: "" for none of those listed, and nothing until it has answered.
// Each session opened from here counts, so an answer that was on its way before one isn't taken. The app of the host
// each terminal session runs in, by ProcessKey ("" for none).
@property (copy) NSString *frontLast;
@property (copy) NSDictionary<NSString *, NSString *> *terminalShows;
@property (assign) NSUInteger openings;
@property (copy) NSDictionary<NSString *, NSString *> *sessionApps;
// The session last brought forward from here, in which app, and until when it's taken to be starting there: a session
// just started isn't listed yet, so its terminal can't name it, and "none" from it isn't taken meanwhile.
@property (copy) NSString *openedApp, *openedSession;
@property (assign) NSTimeInterval openedUntil;
// The ended sessions being opened again from here, by session id; and a running session's row pressed as it was
// ending, until when its row is waited for to turn grey.
@property (strong) NSMutableDictionary<NSString *, Reopening *> *reopening;
@property (copy) NSString *pressedEnding, *pressedEndingIn;  // and the name of the terminal it was in
@property (assign) NSTimeInterval pressedEndingUntil;
// Each press that brings a terminal's tab forward counts, so only the last one's keyboard is checked (keyboardTo:).
@property (assign) NSUInteger tabPresses;
// The session you're looking at (lookingAt:) and since when, and when you were last looking at each session you
// stayed on (noteSeen:).
@property (copy) NSString *looking;
@property (assign) double lookingSince;
@property (strong) NSMutableDictionary<NSString *, NSNumber *> *seenAt;
@end

// How long you stay on a session before it counts as seen: tabs passed on the way to another don't. And how long
// without the keyboard or the mouse until you're taken to be away from the Mac.
static const double kSeenAfterMs = 2000, kAwayAfterSeconds = 5 * 60;
// How long a session just brought forward from here is waited for to be listed, as one just started takes a while; how
// long a terminal's new tab is, as macOS may first ask you whether Whozmove may control that terminal; how long an ended
// session is then waited for to be running again in it, as a long conversation takes Claude Code a while to load; and
// how long a row pressed as its session was ending is waited for to turn grey: a read or two, as Claude Code shuts down.
static const NSTimeInterval kListedWithin = 60, kTabWithin = 300, kResumeWithin = 30, kEndingWithin = 5;
// How long after a press brings a terminal's tab forward the terminal should have the keyboard, and how many times
// it's then given to it, at most, before the log says it still doesn't.
static const NSTimeInterval kKeyboardWithin = 0.5;
static const NSUInteger kKeyboardTries = 2;

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
    [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceDidTerminateApplicationNotification
                                                                object:nil queue:NSOperationQueue.mainQueue
                                                            usingBlock:^(NSNotification *note) {
        [weakSelf quit:[note.userInfo[NSWorkspaceApplicationKey] bundleIdentifier]];
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

// Above the app in front, another app's normal window is one that came there without its app coming to the front (as
// Arc's single-page windows do), and it can have the keyboard, beside the app's window as much as over it; so any of
// them counts, overlapping or not. Windows above the normal ones (the menu bar, the Dock, a panel that floats over
// every app, as Whozmove's does) stay on top whatever comes forward, so they don't, unless they're the app's own (a
// terminal's window that drops down from the top of the screen, or one that floats over every app).
BOOL FrontWindowOnTop(NSArray<NSDictionary *> *windows, pid_t pid, pid_t own) {
    for (NSDictionary *window in windows) {
        pid_t owner = [window[(__bridge NSString *)kCGWindowOwnerPID] intValue];
        if (owner == own || [window[(__bridge NSString *)kCGWindowAlpha] doubleValue] <= 0) continue;
        if (owner == pid) return YES;
        if ([window[(__bridge NSString *)kCGWindowLayer] integerValue] == 0) return NO;
    }
    return NO;
}

// The windows on the screen now, front first. Their owners and places need no permission; only their titles would.
static NSArray<NSDictionary *> *WindowsOnScreen(void) {
    return CFBridgingRelease(CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID)) ?: @[];
}

// Whether you're at the Mac: your session on the screen, unlocked (macOS's record of the session says so in a key it
// doesn't document) and awake, and the keyboard or the mouse used in the last few minutes.
BOOL AtTheMac(void) {
    NSDictionary *session = CFBridgingRelease(CGSessionCopyCurrentDictionary());
    if (![session[(__bridge NSString *)kCGSessionOnConsoleKey] boolValue]
        || [session[@"CGSSessionScreenIsLocked"] boolValue] || CGDisplayIsAsleep(CGMainDisplayID()))
        return NO;
    return CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateHIDSystemState, kCGAnyInputEventType)
        < kAwayAfterSeconds;
}

// The session you're on is marked in the list: in Claude Desktop, the conversation it shows (marked as the rows are
// read), and in a terminal, the session in the tab it shows, as that terminal last said. Whichever of those apps was in
// front last wins, except that Claude Desktop's stays marked while the terminal's tab holds none of the sessions
// listed (a plain shell), and the mark stays where it is while the terminal can't tell. The terminal is asked on each
// read while it's in front: behind, its tab changes only when the one showing closes, and then the session that was
// marked has ended anyway. It answers after the rows have gone, so a different answer sends them again. A print run
// (the tests) asks no app anything.
- (void)mark:(NSArray<Row *> *)rows {
    if (self.core.printing) return;
    id<Host> terminal = [self.core hostFor:NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier];
    if (AnswersWhichShows(terminal)) [self ask:terminal whichShows:rows];
    NSString *shows = self.frontLast ? self.terminalShows[self.frontLast] : nil;
    if (AnswersWhichShows([self.core hostFor:self.frontLast]) && [self listed:shows in:rows])
        for (Row *row in rows) row.focused = [row.sessionId isEqualToString:shows];
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
    if (AnswersWhichShows(front)) return [self sessionShownBy:front among:rows];
    for (Row *row in rows)
        if (row.focused && [self.core hostHolding:row] == front) return row.sessionId;
    return nil;
}

- (NSString *)terminalSessionInFront {
    id<Host> front = [self.core hostFor:NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier];
    return AnswersWhichShows(front) ? [self sessionShownBy:front among:self.core.rows.byId.allValues] : nil;
}

// The session in the tab a terminal shows, as it last said, while it's among `rows`.
- (NSString *)sessionShownBy:(id<Host>)terminal among:(NSArray<Row *> *)rows {
    NSString *shows = self.terminalShows[terminal.appId];
    return [self listed:shows in:rows] ? shows : nil;
}

// Asks the terminal in front which of the sessions running in it its tab holds. With none running in it, that's
// certainly none of them, without asking; but not while a session just started there from here isn't listed yet, which
// it shows though it can't name it. A session never moves host, so which one each runs in is worked out once,
// by its host rather than its app, which can be gone while its sessions live on (iTerm2's, under its server).
- (void)ask:(id<Host>)terminal whichShows:(NSArray<Row *> *)rows {
    NSMutableDictionary<NSString *, NSString *> *apps = [NSMutableDictionary dictionary];
    NSMutableArray<Row *> *inIt = [NSMutableArray array];
    for (Row *row in rows) {
        if ([self.core hostHolding:row] || row.pid <= 0) continue;
        NSString *key = ProcessKey(row.pid, row.procStart);
        apps[key] = self.sessionApps[key] ?: [self.core hostOf:row].appId ?: @"";
        if ([apps[key] isEqualToString:terminal.appId]) [inIt addObject:row];
    }
    self.sessionApps = apps;
    NSString *app = terminal.appId;  // the answer is this terminal's, whichever is in front when it comes
    BOOL starting = [app isEqualToString:self.openedApp] && NSDate.date.timeIntervalSince1970 < self.openedUntil;
    // Listed now, running: an ended session opened again is listed all along, as its row with no process.
    for (Row *row in rows)
        if (starting && row.pid > 0 && [row.sessionId isEqualToString:self.openedSession]) starting = NO;
    if (!inIt.count) {
        if (!starting) [self terminal:app said:nil];
        return;
    }
    NSUInteger openings = self.openings;
    [terminal whichShows:inIt done:^(Row *shown) {
        if (openings != self.openings) return;  // a session was opened from here meanwhile
        if (!shown && starting) return;         // one it can't name yet
        [self terminal:app said:shown.sessionId];
    }];
}

// What a terminal said its tab shows: a session's id, or nil for none of those listed. Its first answer makes it the
// app you were in last, if it's still in front: until it can tell, the mark stays where it was (cameToFront:).
- (void)terminal:(NSString *)app said:(NSString *)sessionId {
    NSString *shows = sessionId ?: @"", *was = self.terminalShows[app];
    if ([shows isEqualToString:was]) return;
    BOOL first = !was && ![app isEqualToString:self.frontLast]
        && [NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier isEqualToString:app];
    [self terminal:app shows:shows];
    if (first) self.frontLast = app;
    [self.core.rows refresh];
}

// Records the session in the tab a terminal shows ("" for none of those listed, nil to forget what it said).
- (void)terminal:(NSString *)app shows:(NSString *)sessionId {
    NSMutableDictionary<NSString *, NSString *> *shows =
        [NSMutableDictionary dictionaryWithDictionary:self.terminalShows];
    shows[app] = sessionId;
    self.terminalShows = shows;
}

// An app that says which session it shows came to the front, as macOS reports each switch: it's the app you were in last
// until another of them comes, and the list shows its session as the one you're on at once. A terminal that hasn't said
// yet which tab it shows (it can't before you've let Whozmove control it) becomes it once it does (terminal:said:).
- (void)cameToFront:(NSString *)app {
    if (!app || [app isEqualToString:self.frontLast]) return;
    id<Host> host = [self.core hostFor:app];
    if (!SaysWhatItShows(host) || (AnswersWhichShows(host) && !self.terminalShows[app])) return;
    self.frontLast = app;
    [self.core.rows refresh];
}

// An app quit. A terminal's sessions can outlive it (iTerm2's, under its server), but none of them is in a tab you can
// see now, so what it said it shows is forgotten, and it's no longer the app you were in last.
- (void)quit:(NSString *)app {
    if (!app || !self.terminalShows[app]) return;
    [self terminal:app shows:nil];
    if ([app isEqualToString:self.frontLast]) self.frontLast = nil;
    [self.core.rows refresh];
}

- (void)open:(NSDictionary *)message {
    // A press kept from a session that was ending gives way to this one, so its tab can't come forward over it.
    self.pressedEnding = nil;
    // The row as listed, with its state, which a terminal goes by to tell two tabs of one conversation apart; the
    // page's own word for one it hasn't been sent yet. An ended session's row pressed as it came back to life is the
    // running session's now.
    Row *listed = AsText(message[@"sessionId"]) ? self.core.rows.byId[message[@"sessionId"]] : nil;
    pid_t pressed = [AsNumber(message[@"pid"]) intValue];
    Row *row = listed && (listed.pid == pressed || (pressed <= 0 && listed.pid > 0))
        ? listed : [[Row alloc] initWithFields:message];
    // Whether the press means to carry it on (its row's own press, a Resume), when a module's words for it go in; a press
    // only to look at it (Take Me There, Keys') opens it as any is opened.
    BOOL carryOn = [AsNumber(message[@"carryOn"]) boolValue];
    id<Host> own = [self.core hostHolding:row];
    if (own) {
        // That app is the one you're in from now: a terminal's session isn't the one you're on while it comes forward.
        self.frontLast = own.appId;
        // A module's words for it go in as you'd send them, by this press, which shows the conversation first; where
        // they can't, the row says why, and the conversation is shown as a press shows it.
        NSString *words = carryOn ? [self wordsOnReopen:row] : nil;
        if (words.length) {
            __weak typeof(self) weakSelf = self;
            [self.core.send say:words row:row here:@"sent from here" there:@"send them there" done:^(NSString *why,
                                                                                                        NSString *way) {
                if (!why) return;
                PanelLog(@"open conversation %@ -> its words didn't go in: %@", row.sessionId, why);
                // With the button past what stopped them, where there's one (Accessibility's, say).
                if (way) [weakSelf.core.page stepNote:row.sessionId text:why way:way];
                else [weakSelf.core.page stepNote:row.sessionId text:why];
                if ([own respondsToSelector:@selector(open:)]) [own open:row];
            }];
            return;
        }
        if ([own respondsToSelector:@selector(open:)]) [own open:row];
        return;
    }
    if ([self.core hasEnded:row]) return [self reopen:row carryOn:carryOn];
    // Terminal session: bring forward the app it runs in (Terminal, Ghostty, iTerm2, VS Code…), as the core finds it.
    // The panel gives the keyboard back first, as one of its boxes may have it (the new conversation card's, say).
    [self.core.window releaseKeyboard];
    NSRunningApplication *app = [self.core appOf:row.pid];
    id<Host> terminal = [self.core hostOf:row];
    NSRunningApplication *front = NSWorkspace.sharedWorkspace.frontmostApplication;
    // The session you're on already, in the terminal with the keyboard, its window on top: there's nothing to bring
    // forward, and a terminal told to show the tab it shows can lose the keyboard over it. Another app's window can
    // come above the terminal's without that app coming to the front, though (Arc's single-page windows do), and take
    // the keyboard; then the terminal is told to show its tab after all, which brings its window up and the keyboard
    // with it.
    BOOL onIt = terminal && [front.bundleIdentifier isEqualToString:terminal.appId]
        && [self.terminalShows[terminal.appId] isEqualToString:row.sessionId];
    if (onIt && FrontWindowOnTop(WindowsOnScreen(), front.processIdentifier, getpid())) {
        PanelLog(@"open terminal session pid %d -> already on its tab in %@", row.pid, terminal.name);
        [self keyboardTo:front tries:0];
        return;
    }
    if (onIt) PanelLog(@"open terminal session pid %d -> on its tab in %@, but its window isn't on top",
                       row.pid, terminal.name);
    if (!app) {
        // Its process has gone, as its session ended a moment ago, and its row isn't grey yet: the press opens it again
        // once it is.
        if (row.pid > 0 && !ProcessAlive(row.pid)) {
            PanelLog(@"open terminal session pid %d -> it has just ended", row.pid);
            [self pressedAsItEnds:row in:[self.core hostFor:self.sessionApps[ProcessKey(row.pid, row.procStart)]]];
            return;
        }
        // A terminal's sessions can outlive the app, under a server of its own (after a crash, say), and it takes them
        // back as it starts: the press starts it, as a press on a Claude Desktop row starts Claude.
        NSURL *url = terminal ? [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:terminal.appId]
                              : nil;
        if (url) {
            [NSWorkspace.sharedWorkspace openApplicationAtURL:url
                                                configuration:[NSWorkspaceOpenConfiguration configuration]
                                            completionHandler:nil];
            PanelLog(@"open terminal session pid %d -> starting %@", row.pid, terminal.name);
            return;
        }
        PanelLog(@"open terminal session pid %d -> no owning app found", row.pid);
        NSBeep();
        return;
    }
    // Only a terminal finds a session's tab. Any other app that owns the process (Claude Desktop running a session it
    // doesn't hold as its own, say) is just brought forward: an app that keeps conversations opens only those it holds.
    BOOL findsTabs = [terminal respondsToSelector:@selector(open:)]
        && ![terminal conformsToProtocol:@protocol(ConversationHost)];
    if (findsTabs && [terminal open:row]) {
        [self keyboardTo:app tries:0];
        // At the session's own tab, so it's the one you're on now, without waiting for the terminal's next answer.
        [self tabCameForward:terminal session:row.sessionId];
        [self.core.rows refresh];
        return;
    }
    // Its tab isn't there: it may have just been closed, its session ending. If its row turns grey in a moment, the
    // press opens it again then.
    if (findsTabs) [self pressedAsItEnds:row in:terminal];
    [app activateWithOptions:NSApplicationActivateAllWindows];
    PanelLog(@"open terminal session pid %d -> activated %@", row.pid, app.localizedName);
}

// A moment after a press brought a terminal's tab forward, the terminal should have the keyboard. If the panel still
// has it, though nothing in the panel asks for it, it gives it back again; if another app is in front (macOS can turn a
// terminal down as it asks to come forward), the terminal is brought forward; and the log says who had it. A later
// press takes over.
- (void)keyboardTo:(NSRunningApplication *)app tries:(NSUInteger)tries {
    NSUInteger press = tries ? self.tabPresses : ++self.tabPresses;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kKeyboardWithin * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        Focus *focus = weakSelf;
        if (!focus || press != focus.tabPresses || app.terminated) return;
        BOOL kept = [focus.core.window keptKeyboard];
        NSRunningApplication *front = NSWorkspace.sharedWorkspace.frontmostApplication;
        if (!kept && front.processIdentifier == app.processIdentifier) return;
        NSString *had = kept ? @"the panel" : front.localizedName ?: @"no app";
        if (tries == kKeyboardTries) {
            PanelLog(@"open in %@: it still doesn't have the keyboard (%@ has it)", app.localizedName, had);
            return;
        }
        PanelLog(@"open in %@: it didn't have the keyboard after the press (%@ had it), so it's given to it",
                 app.localizedName, had);
        if (kept) [focus.core.window releaseKeyboard];
        else [app activateWithOptions:0];
        [focus keyboardTo:app tries:tries + 1];
    });
}

#pragma mark Ended sessions

// The terminal an ended session ran in, while it's on this Mac and opens tabs, else nil.
- (id<CommandHost>)ranIn:(Row *)row {
    id ran = row.ranIn ? [self.core hostFor:row.ranIn] : nil;
    return [ran conformsToProtocol:@protocol(CommandHost)] && [self.core hasApp:ran] ? ran : nil;
}

// Where an ended session opens again when the terminal it ran in can't: the one new conversations start in, else any
// on this Mac that runs a command in a new tab (macOS's Terminal, which every Mac has).
- (id<CommandHost>)fallbackTerminal {
    id<CommandHost> start = self.core.startTerminal;
    if (start) return start;
    for (id<CommandHost> terminal in [self.core hostsThat:@protocol(CommandHost)])
        if (![terminal conformsToProtocol:@protocol(ConversationHost)] && [self.core hasApp:terminal]) return terminal;
    return nil;
}

- (id<CommandHost>)terminalToReopen:(Row *)row {
    return [self ranIn:row] ?: [self fallbackTerminal];
}

- (void)nameReopens:(NSArray<Row *> *)rows {
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (self.pressedEnding && now > self.pressedEndingUntil) {
        // Still running: it wasn't ending, its tab just couldn't be found. The row says so, over "Opening it…".
        for (Row *row in rows)
            if (row.pid > 0 && [row.sessionId isEqualToString:self.pressedEnding])
                [self.core.page stepNote:row.sessionId text:[NSString stringWithFormat:@"Couldn't find its tab in %@",
                                                             self.pressedEndingIn ?: @"its terminal"]];
        self.pressedEnding = nil;
    }
    // The terminal a row opens in when its own can't is the same for every row, so it's found once, if one needs it.
    id<CommandHost> fallback = nil;
    BOOL lookedForFallback = NO;
    NSMutableSet<NSString *> *running = [NSMutableSet set];
    for (Row *row in rows) {
        if ([self.core hasEnded:row]) {
            id<CommandHost> ran = [self ranIn:row];
            if (!ran && !lookedForFallback) {
                fallback = [self fallbackTerminal];
                lookedForFallback = YES;
            }
            row.opensIn = (ran ?: fallback).name;
            // Pressed as it was ending: now that its row is grey, the press opens it, once the rows have gone.
            if ([row.sessionId isEqualToString:self.pressedEnding]) {
                self.pressedEnding = nil;
                // Pressed while it still ran, it wasn't one closed while it waited: no module's words for it.
                dispatch_async(dispatch_get_main_queue(), ^{ [self reopen:row carryOn:NO]; });
            }
        } else if (row.pid > 0 && row.sessionId) {
            [running addObject:row.sessionId];
        }
    }
    // One opened again from here is running again, or has had its time: then the row says what went wrong. Nothing is
    // tried again by itself: a press on the row does that.
    for (NSString *sessionId in self.reopening.allKeys) {
        Reopening *opening = self.reopening[sessionId];
        if ([running containsObject:sessionId]) {
            PanelLog(@"open ended session %@ -> running again after %.0fs", sessionId, now - opening.since);
            [self.reopening removeObjectForKey:sessionId];
        } else if (opening.until < now) {
            [self.reopening removeObjectForKey:sessionId];
            NSString *why = opening.tabOpened
                ? [NSString stringWithFormat:@"It didn't open again in %@: look there for what Claude Code says",
                                             opening.where]
                : [NSString stringWithFormat:@"%@ didn't open a tab for it", opening.where];
            PanelLog(@"open ended session %@ -> %@", sessionId, why);
            [self.core.page stepNote:sessionId text:why];
        }
    }
}

// A running session's row pressed as its session was ending (its tab closing, or its process gone), before its row
// turned grey: the press is kept for a moment, and opens it again once its row is grey, as a press there would. The
// row says it's opening from the press on, as Claude Code can take a few seconds to shut down.
- (void)pressedAsItEnds:(Row *)row in:(id<Host>)terminal {
    self.pressedEnding = row.sessionId;
    self.pressedEndingIn = terminal.name;
    self.pressedEndingUntil = NSDate.date.timeIntervalSince1970 + kEndingWithin;
    NSString *note = terminal ? [NSString stringWithFormat:@"Opening it in %@…", terminal.name] : @"Opening it again…";
    [self.core.page stepNote:row.sessionId text:note quiet:YES];
    [self.core.rows refresh];
}

// A new tab in its terminal, in its folder, carries its conversation on under the same id, so its row turns into the
// running session's once that's listed, as the one you're on. The row says it's opening, or why it couldn't; and a
// second press while it's opening opens nothing more, as a second tab would run the conversation twice: the row says
// it's opening again. With `carryOn` (its row's own press, a Resume), a module's words for it go in as its first
// message.
- (void)reopen:(Row *)row carryOn:(BOOL)carryOn {
    NSString *sid = row.sessionId;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    Reopening *already = self.reopening[sid];
    if (already && already.until > now) {
        PanelLog(@"open ended session %@ -> opening already", sid);
        [self.core.page stepNote:sid text:[NSString stringWithFormat:@"Opening it in %@…", already.where] quiet:YES];
        return;
    }
    id<CommandHost> terminal = [self terminalToReopen:row];
    id agent = [self.core agentOf:row];
    BOOL starts = [agent conformsToProtocol:@protocol(AgentStarts)];
    NSString *command = starts ? [agent resumeCommand:sid wordsFile:nil] : nil;
    BOOL folder = NO;
    NSString *why = !terminal ? @"There's no terminal on this Mac to open it in"
        : !command ? @"It can't be opened again from here"
        : !(row.cwd && [NSFileManager.defaultManager fileExistsAtPath:row.cwd isDirectory:&folder] && folder)
            ? @"Its folder isn't there any more" : nil;
    if (why) {
        PanelLog(@"open ended session %@ -> %@", sid, why);
        NSBeep();
        [self.core.page stepNote:sid text:why];
        return;
    }
    // It's opening from this press on, so a second press finds it so, even while its words are being kept.
    NSString *where = terminal.name;
    Reopening *opening = [Reopening new];
    opening.where = where;
    opening.since = now;
    opening.until = now + kTabWithin;
    if (!self.reopening) self.reopening = [NSMutableDictionary dictionary];
    self.reopening[sid] = opening;
    PanelLog(@"open ended session %@ -> in a new tab in %@", sid, where);
    [self.core.page stepNote:sid text:[NSString stringWithFormat:@"Opening it in %@…", where] quiet:YES];
    // A module's words for the conversation opened again (a closed one that waited, told what to do first), as its
    // first message: read from a file only you can read, made off the main thread, gone once the tab has read it.
    NSString *words = carryOn ? [self wordsOnReopen:row] : nil;
    if (words.length) {
        NSString *file = [AppDir(@"reopen") stringByAppendingPathComponent:[sid stringByAppendingPathExtension:@"txt"]];
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [NSFileManager.defaultManager createDirectoryAtPath:file.stringByDeletingLastPathComponent
                                    withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700}
                                                          error:nil];
            BOOL kept = [NSFileManager.defaultManager createFileAtPath:file
                                                              contents:[words dataUsingEncoding:NSUTF8StringEncoding]
                                                            attributes:@{NSFilePosixPermissions: @0600}];
            dispatch_async(dispatch_get_main_queue(), ^{
                // Without its words it's opened as a press opens any ended session, and panel.log says so.
                if (!kept) PanelLog(@"open ended session %@ -> its words couldn't be kept; opened without them", sid);
                [weakSelf reopen:row in:terminal running:kept ? [agent resumeCommand:sid wordsFile:file] : command
                           words:kept ? file : nil opening:opening];
            });
        });
        return;
    }
    [self reopen:row in:terminal running:command words:nil opening:opening];
}

// The first module's words for a conversation opened again from its row, or nil (ReopenWords, contracts/Module.h).
- (NSString *)wordsOnReopen:(Row *)row {
    for (id<ReopenWords> module in [self.core modulesThat:@protocol(ReopenWords)]) {
        NSString *words = [module wordsOnReopen:row];
        if (words.length) return words;
    }
    return nil;
}

// Opens it in a new tab of `terminal`, running `command`, as `opening`, with its words' file (`file`) taken away once
// the tab has had time to read it, or at once when it couldn't open.
- (void)reopen:(Row *)row in:(id<CommandHost>)terminal running:(NSString *)command words:(NSString *)file
       opening:(Reopening *)opening {
    NSString *sid = row.sessionId;
    void (^dropWords)(NSTimeInterval) = ^(NSTimeInterval after) {
        if (!file) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(after * NSEC_PER_SEC)),
                       dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            [NSFileManager.defaultManager removeItemAtPath:file error:nil];
        });
    };
    // The press may have been a moment ago (its words were being kept): one that has been opened another way since
    // isn't opened twice.
    if (self.reopening[sid] != opening) return dropWords(0);
    [self.core.window releaseKeyboard];
    // Terminal names the file it runs for what it carries on.
    NSString *named = Clip([@"Resume " stringByAppendingString:row.name ?: row.cwd.lastPathComponent], 60);
    __weak typeof(self) weakSelf = self;
    [terminal newTabIn:row.cwd running:command named:named forward:YES done:^(NSString *tabWhy) {
        if (tabWhy) {
            dropWords(0);
            if (weakSelf.reopening[sid] == opening) [weakSelf.reopening removeObjectForKey:sid];
            PanelLog(@"open ended session %@ -> %@", sid, tabWhy);
            NSBeep();
            [weakSelf.core.page stepNote:sid text:tabWhy];
            return;
        }
        opening.tabOpened = YES;
        opening.until = NSDate.date.timeIntervalSince1970 + kResumeWithin;
        dropWords(kResumeWithin + 60);
        if (AnswersWhichShows(terminal)) [weakSelf tabCameForward:terminal session:sid];
        [weakSelf.core.rows refresh];
    }];
}

- (void)tabCameForward:(id<Host>)host session:(NSString *)sessionId {
    self.frontLast = host.appId;
    [self terminal:host.appId shows:sessionId];
    self.openings++;
    self.openedApp = host.appId;
    self.openedSession = sessionId;
    self.openedUntil = NSDate.date.timeIntervalSince1970 + kListedWithin;
}

@end
