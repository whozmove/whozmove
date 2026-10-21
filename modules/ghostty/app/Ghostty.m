// Ghostty: finding a session's Ghostty tab, bringing it forward and typing into it, through AppleScript, and which
// tab it shows, through its Apple events.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Ghostty.h"
#import "GhosttyFacts.h"
#import <AppKit/AppKit.h>
#import "Row.h"
#import "Log.h"
#import "AppleEvents.h"
#import "AppleScript.h"
#import "Core.h"

// While the same tab shows, every terminal's folder and title are asked for again this often, as the titles follow
// their sessions' topics; at once when another tab shows.
static const NSTimeInterval kTerminalsKeptFor = 5;

// Drop Claude Code's status glyph ("✳ ", spinner characters) from the front of a tab title.
static NSString *BareTitle(NSString *title) {
    NSUInteger i = 0;
    while (i < title.length && ![NSCharacterSet.alphanumericCharacterSet characterIsMember:[title characterAtIndex:i]])
        i++;
    return [[title substringFromIndex:i] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

// What a property of every terminal in `container` (all of Ghostty's when nil) holds, in their order, or nil without
// an answer. Ghostty is asked with Apple events of Whozmove's own (AskEvery): to its process, so a Ghostty that has
// just quit isn't started again, as AppleScript's `tell` would, and never asking you anything: until you've let Whozmove
// control Ghostty (macOS asks the first time a row is clicked) there's just no answer. Each waits a second at most, and
// blocks only the thread it's on, so it can run off the main thread, which AppleScript isn't promised to.
static NSArray<NSString *> *AskEveryTerminal(pid_t pid, OSType property, NSAppleEventDescriptor *container) {
    return AskEvery(pid, kGhosttyTerminalClass, property, container, 1);
}

// Every terminal, as [its id, its folder, its bare title, its whole title], or nil without an answer. The lists are
// asked for one after another, and a terminal opened or closed meanwhile would shift them against each other, so
// they're used only if the ids are the same at the end as at the start.
static NSArray<NSArray<NSString *> *> *AskTerminals(pid_t pid) {
    NSArray<NSString *> *ids = AskEveryTerminal(pid, kGhosttyTerminalId, nil),
                        *folders = AskEveryTerminal(pid, kGhosttyWorkingDirectory, nil),
                        *titles = AskEveryTerminal(pid, kGhosttyTitle, nil);
    if (!ids || folders.count != ids.count || titles.count != ids.count
        || ![AskEveryTerminal(pid, kGhosttyTerminalId, nil) isEqualToArray:ids]) return nil;
    NSMutableArray *terminals = [NSMutableArray array];
    for (NSUInteger i = 0; i < ids.count; i++)
        [terminals addObject:@[ids[i], folders[i], BareTitle(titles[i]), titles[i]]];
    return terminals;
}

@interface Ghostty ()
// A session's tab is told by the title its agent gives it (Agent's titleOf:now:), which Claude Code puts in the tab's
// title.
@property (weak) Core *core;
// Asking which tab Ghostty shows (whichShows:done:). The queue's own: the terminals in the tab it last said, and
// every terminal, as last asked for and when (by the Mac's uptime, which a change of the clock doesn't move).
@property (strong) dispatch_queue_t queue;
@property (copy) NSArray<NSString *> *askedTab;
@property (copy) NSArray<NSArray<NSString *> *> *askedTerminals;
@property (assign) NSTimeInterval askedAt;
@property (assign) BOOL asking;  // an answer is on its way; on the main thread only
@end

@implementation Ghostty

+ (NSString *)moduleName {
    return @"ghostty";
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.queue = dispatch_queue_create("whozmove.ghostty", DISPATCH_QUEUE_SERIAL);
    return self;
}

// The title the agent gives a session: read again now (`now`), or as the rows last had it.
- (NSString *)titleOf:(Row *)row now:(BOOL)now {
    return [[self.core agentOf:row] titleOf:row now:now];
}

- (NSString *)appId {
    return kGhosttyAppId;
}

- (NSString *)name {
    return kGhosttyName;
}

// Every terminal, as [its id, its folder, its bare title, its whole title]. Each list is asked for at once, rather
// than each terminal's id, folder and title one by one, which took nearly half a second with a few tabs open; they're
// used only if the ids are the same at the end as at the start (AskTerminals says why).
- (NSArray<NSArray<NSString *> *> *)terminalsNow {
    // `sep` is bound outside the tell block: inside it, `tab` names Ghostty's tab class, not the character.
    NSString *list = RunAppleScript(@"set sep to tab\n"
                                    @"tell application \"Ghostty\"\n"
                                    @"  set ids to id of terminals\n"
                                    @"  set dirs to working directory of terminals\n"
                                    @"  set titles to name of terminals\n"
                                    @"  if (id of terminals) is not ids then return \"\"\n"
                                    @"end tell\n"
                                    @"set out to \"\"\n"
                                    @"repeat with i from 1 to count of ids\n"
                                    @"  set out to out & (item i of ids) & sep & (item i of dirs) & sep"
                                    @" & (item i of titles) & linefeed\n"
                                    @"end repeat\n"
                                    @"return out");
    NSMutableArray *terminals = [NSMutableArray array];
    for (NSString *line in [list componentsSeparatedByString:@"\n"]) {
        NSArray *fields = [line componentsSeparatedByString:@"\t"];
        if (fields.count >= 3) [terminals addObject:@[fields[0], fields[1], BareTitle(fields[2]), fields[2]]];
    }
    return terminals;
}

// Ghostty's scripting exposes each terminal's title and working directory but not its tty, so the session is
// matched by folder, then by the tab title Claude Code sets (its topic, else its name, else "Claude Code"): the
// terminals that fit it best, as [id, folder, bare title, whole title]. More than one fit as well when a conversation
// is open in two tabs, or two sessions in one folder have the same title.
- (NSArray<NSArray<NSString *> *> *)tabsFor:(Row *)row topic:(NSString *)topic
                                      among:(NSArray<NSArray<NSString *> *> *)terminals {
    NSMutableArray<NSArray<NSString *> *> *sameFolder = [NSMutableArray array];
    for (NSArray<NSString *> *terminal in terminals)
        if ([terminal[1] isEqualToString:row.cwd]) [sameFolder addObject:terminal];

    NSMutableArray *wanted = [NSMutableArray array];
    if (topic.length) [wanted addObject:topic];
    if ([row.name length]) [wanted addObject:row.name];
    if (!topic.length) [wanted addObject:@"Claude Code"];

    NSCharacterSet *notId =
        [[NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEFabcdef-"] invertedSet];
    for (NSString *title in wanted) {
        NSArray *hits = [sameFolder filteredArrayUsingPredicate:
                             [NSPredicate predicateWithBlock:^BOOL(NSArray<NSString *> *t, id _) {
            return [t[2] isEqualToString:title] && t[0].length
                && [t[0] rangeOfCharacterFromSet:notId].location == NSNotFound;
        }]];
        if (hits.count) return hits;
    }
    return sameFolder.count == 1 && [sameFolder[0][0] rangeOfCharacterFromSet:notId].location == NSNotFound
        ? sameFolder : @[];
}

// The session's tab: *unique says whether nothing else in that folder fits as well, which typing into it requires. Of
// tabs that fit as well, as a conversation open in two tabs does, the one whose title says its agent works as the row
// does goes first (titleShowsWork:), so the row brings forward the copy it shows.
- (NSString *)tabFor:(Row *)row topic:(NSString *)topic among:(NSArray<NSArray<NSString *> *> *)terminals
              unique:(BOOL *)unique {
    NSArray<NSArray<NSString *> *> *hits = [self tabsFor:row topic:topic among:terminals];
    *unique = hits.count == 1;
    if (hits.count > 1) {
        id<Agent> agent = [self.core agentOf:row];
        BOOL working = [row.status isEqual:@"busy"];
        for (NSArray<NSString *> *t in hits)
            if ([agent titleShowsWork:t[3]] == working) return t[0];
    }
    return hits.firstObject[0];
}

// How many tabs a session's conversation can be in: its own, and one for each other copy that runs in a terminal (one
// paused there may still have its tab's title). Claude Desktop's copies have none.
- (NSUInteger)tabsOpenFor:(Row *)row {
    NSUInteger tabs = 1;
    for (NSDictionary *copy in row.alsoOpen)
        if (![self.core hostHolding:[[Row alloc] initWithFields:copy]]) tabs++;
    return tabs;
}

- (NSString *)tabFor:(Row *)row unique:(BOOL *)unique {
    NSString *topic = [self titleOf:row now:YES];
    NSString *match = [self tabFor:row topic:topic among:[self terminalsNow] unique:unique];
    if (!match) PanelLog(@"terminal session pid %d -> no Ghostty tab matched (topic %@)", row.pid, topic);
    return match;
}

- (BOOL)open:(Row *)row {
    BOOL unique;
    NSString *match = [self tabFor:row unique:&unique];
    if (!match) return NO;
    // Ghostty's `focus` brings a terminal's tab forward only a moment after it answers, and `activate` brings back the
    // tab that was showing, so which of the two ended up in front was a race. So its tab is selected and its window
    // brought forward first, which Ghostty does before it answers; `focus` then only picks its split in the tab. The
    // window and tab are held by what Ghostty answers with, its ids for them, as selecting a tab can reorder windows.
    // It went through only if the script got to its end: a tab closed meanwhile stops it before Ghostty comes forward.
    NSString *done = RunAppleScript([NSString stringWithFormat:@"tell application \"Ghostty\"\n"
                                              @"  set found to id of terminals of tabs of windows\n"
                                              @"  repeat with i from 1 to count of found\n"
                                              @"    repeat with j from 1 to count of item i of found\n"
                                              @"      if item j of item i of found contains \"%@\" then\n"
                                              @"        set w to window i\n"
                                              @"        set t to tab j of w\n"
                                              @"        select tab t\n"
                                              @"        activate window w\n"
                                              @"      end if\n"
                                              @"    end repeat\n"
                                              @"  end repeat\n"
                                              @"  focus (first terminal whose id is \"%@\")\n"
                                              @"  activate\n"
                                              @"end tell\n"
                                              @"return \"focused\"", match, match]);
    if (![done isEqualToString:@"focused"]) {
        PanelLog(@"open terminal session pid %d -> Ghostty terminal %@ not brought forward", row.pid, match);
        return NO;
    }
    PanelLog(@"open terminal session pid %d -> focused Ghostty terminal %@", row.pid, match);
    return YES;
}

// The panel asks this on every tick while Ghostty is in front, so the answer is waited for on a queue of Ghostty's
// own: the terminals in its front window's selected tab, and when the tab is split, the one with the keyboard. Every
// terminal's folder and title are asked for again only when another tab shows, or every few seconds.
- (void)whichShows:(NSArray<Row *> *)rows done:(void (^)(Row *row))done {
    pid_t pid =
        [NSRunningApplication runningApplicationsWithBundleIdentifier:kGhosttyAppId].firstObject.processIdentifier;
    if (pid <= 0 || self.asking) return;
    self.asking = YES;
    dispatch_async(self.queue, ^{
        NSAppleEventDescriptor *tab =
            AppleEventProperty(kGhosttySelectedTab, AppleEventProperty(kGhosttyFrontWindow, nil));
        NSArray<NSString *> *inTab = AskEveryTerminal(pid, kGhosttyTerminalId, tab);
        NSString *focused = inTab.count > 1
            ? AskQuietly(pid, AppleEventProperty(kGhosttyTerminalId, AppleEventProperty(kGhosttyFocusedTerminal, tab)),
                         1).stringValue
            : inTab.firstObject;
        NSMutableSet<NSString *> *listed = [NSMutableSet set];
        for (NSArray<NSString *> *terminal in self.askedTerminals) [listed addObject:terminal[0]];
        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        if (inTab.count && (![inTab isEqualToArray:self.askedTab] || ![[NSSet setWithArray:inTab] isSubsetOfSet:listed]
                            || now - self.askedAt >= kTerminalsKeptFor)) {
            self.askedTerminals = AskTerminals(pid);
            self.askedAt = now;
        }
        self.askedTab = inTab;
        NSArray<NSArray<NSString *> *> *terminals = self.askedTerminals;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.asking = NO;
            Row *row = nil;
            if ([self tell:&row among:rows inTab:inTab focused:focused terminals:terminals]) done(row);
        });
    });
}

// Whether it can be told which of these sessions is in the tab holding the terminals `inTab` (`focused` has the
// keyboard), and if so, which: *row, or nil when it's certainly none of them. Only a session in one of those
// terminals' folders can be in it. Each is matched to its tab the way a click finds it, but by the title the rows last
// had for it, as a transcript isn't to be read here, on the main thread. A session that matches no tab
// for sure, or two that match the same one, leave it untold, unless another session is certainly in it.
- (BOOL)tell:(Row **)row among:(NSArray<Row *> *)rows inTab:(NSArray<NSString *> *)inTab focused:(NSString *)focused
   terminals:(NSArray<NSArray<NSString *> *> *)terminals {
    *row = nil;
    NSMutableSet<NSString *> *folders = [NSMutableSet set];
    NSUInteger listed = 0;
    for (NSArray<NSString *> *terminal in terminals)
        if ([inTab containsObject:terminal[0]]) {
            [folders addObject:terminal[1]];
            listed++;
        }
    if (!inTab.count || listed < inTab.count) return NO;  // no answer, or a tab newer than the list

    NSMutableDictionary<NSString *, Row *> *found = [NSMutableDictionary dictionary];  // terminal in the tab -> session
    NSMutableSet<NSString *> *claimedTwice = [NSMutableSet set];
    BOOL unsure = NO;
    for (Row *candidate in rows) {
        if (![folders containsObject:candidate.cwd]) continue;
        NSArray<NSArray<NSString *> *> *hits = [self tabsFor:candidate topic:[self titleOf:candidate now:NO]
                                                       among:terminals];
        // Tabs that fit as well are all this session's when there are no more of them than tabs its conversation is
        // open in: then whichever is in front, it's this one.
        if (!hits.count || hits.count > [self tabsOpenFor:candidate]) {
            unsure = YES;
            continue;
        }
        NSString *tab = nil;
        for (NSArray<NSString *> *t in hits)
            if ([inTab containsObject:t[0]] && (!tab || [t[0] isEqual:focused])) tab = t[0];
        if (!tab) continue;  // certainly in another tab
        if (found[tab]) [claimedTwice addObject:tab];
        else found[tab] = candidate;
    }
    [found removeObjectsForKeys:claimedTwice.allObjects];
    if (focused && [claimedTwice containsObject:focused]) return NO;
    *row = (focused ? found[focused] : nil) ?: (found.count == 1 ? found.allValues.firstObject : nil);
    return *row || (!found.count && !claimedTwice.count && !unsure);
}

// Runs AppleScript in Ghostty with `t` set to the tab.
- (void)run:(NSString *)body inTab:(NSString *)tab {
    RunAppleScript([NSString stringWithFormat:@"tell application \"Ghostty\"\n"
                                              @"  set t to first terminal whose id is \"%@\"\n"
                                              @"%@\n"
                                              @"end tell", tab, body]);
}

// Typed in as the tab's first input; Ghostty shows no name for it.
- (void)newTabIn:(NSString *)folder running:(NSString *)command named:(NSString *)name forward:(BOOL)forward
            done:(void (^)(NSString *why))done {
    // `nl` is bound outside the tell block, where `linefeed` can't be shadowed by Ghostty's terms. It went through only
    // if the script got to its end.
    NSString *opened = RunAppleScript([NSString stringWithFormat:@"set nl to linefeed\n"
                                                                 @"tell application \"Ghostty\"\n"
                                                                 @"  set cfg to new surface configuration\n"
                                                                 @"  set initial working directory of cfg to \"%@\"\n"
                                                                 @"  set initial input of cfg to \"%@\" & nl\n"
                                                                 @"  if (count of windows) > 0 then\n"
                                                                 @"    new tab in front window with configuration cfg\n"
                                                                 @"  else\n"
                                                                 @"    new window with configuration cfg\n"
                                                                 @"  end if\n"
                                                                 @"%@"
                                                                 @"end tell\n"
                                                                 @"return \"opened\"", AppleScriptText(folder),
                                                                 AppleScriptText(command),
                                                                 forward ? @"  activate\n" : @""]);
    if (!opened) {
        PanelLog(@"new terminal session in %@ -> Ghostty didn't open a tab for it", folder);
        return done(@"Ghostty didn't open a tab for it");
    }
    PanelLog(@"new terminal session in %@", folder);
    done(nil);
}

- (void)type:(NSString *)text inTab:(NSString *)tab {
    // A /compact's focus is free text, so its quotes and backslashes are escaped.
    [self run:[NSString stringWithFormat:@"input text \"%@\" to t", AppleScriptText(text)] inTab:tab];
}

- (void)press:(TerminalKey)key times:(NSInteger)times inTab:(NSString *)tab {
    NSString *once = key == TerminalKeyReturn ? @"send key \"enter\" to t"
                   : key == TerminalKeyBackspace ? @"send key \"backspace\" to t"
                   : key == TerminalKeyShiftTab ? @"send key \"tab\" modifiers \"shift\" to t"
                   : @"perform action \"text:\\\\x13\" on t";  // Ctrl+S, sent as its control character
    [self run:times == 1 ? once : [NSString stringWithFormat:@"repeat %ld times\n"
                                                            @"  %@\n"
                                                            @"  delay 0.05\n"
                                                            @"end repeat", (long)times, once]
        inTab:tab];
}

#pragma mark On the panel's back

// Ghostty on the panel's back: what Whozmove does with it, and macOS's Automation, which finding its tabs and typing
// into them needs.
- (NSArray<AppEntry *> *)appEntries {
    AppEntry *ghostty = [AppEntry appWithId:self.appId name:self.name
                                       does:@"Lists the Claude Code sessions in its tabs and opens them, types the "
                                            @"panel's commands while a session waits at its prompt, and starts new "
                                            @"conversations in a new tab."
                                      order:20];
    ghostty.permission = AppPermissionAutomation;
    ghostty.permissionFor = @"Finds each session's tab, and types into it";
    return @[ghostty];
}

@end
