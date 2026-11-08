// BringForwardModule: holding two keys, Fn + Option until you pick others, brings a session you pick in Settings
// forward from any app, as a press on its row does (its terminal tab, or its conversation in Claude Desktop). Nothing
// more: speak with your dictation app's own keys, and it types what you say into the app in front, the session.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import "Module.h"
#import "Core.h"
#import "Focus.h"
#import "Send.h"
#import "Page.h"
#import "Row.h"
#import "Rows.h"
#import "Log.h"
#import "Links.h"
#import "Notice.h"
#import "HeldKeys.h"

// How often the keys are looked at while a session is picked, and how late a look may be: soon enough after they
// come down, and each look costs a few microseconds.
static const NSTimeInterval kLookEvery = 0.05, kLookLeeway = 0.01;
// How long a notice of why a hold brought nothing forward, with no row to say it on, stays on the line under the
// header, unless it's put right or put away first.
static const NSTimeInterval kNoticeFor = 60;

// What's picked, kept in the app's preferences: the session ("" for none, The Chief's, or "session:<its id>"), its name
// as it was when picked, for when it isn't listed, and the keys. The Chief is kept as "chief", the value its choice has
// always been saved as, so a pick of it holds whatever the session leading a team is called.
static NSString *const kSession = @"bringForwardSession", *const kName = @"bringForwardName",
                *const kKeys = @"bringForwardKeys", *const kSessionPrefix = @"session:", *const kLead = @"chief";

// Whether a saved pick is The Chief's, whichever session leads the team then.
static BOOL PicksLead(NSString *picked) {
    return [picked isEqualToString:kLead];
}

// A saved pick as it's read: The Chief's, a session's, or "" for none. Any other value (edited by hand, say) reads as
// none, so Settings shows Off and the keys aren't watched, rather than a hold that only beeps with nothing to say why.
static NSString *PickAsRead(NSString *saved) {
    BOOL known = PicksLead(saved) || ([saved hasPrefix:kSessionPrefix] && saved.length > kSessionPrefix.length);
    return known ? saved : @"";
}

// The keys that can be picked, Fn + Option until another is. Each has Fn, so ⌘, ⌥ and ⌃ alone, and the shortcuts made
// with them, are left to the apps; VoiceOver's ⌃⌥ isn't among them, nor Fn + Control, which dictation apps listen on.
static const struct { const char *key, *name; CGEventFlags flags; } kPairs[] = {
    {"fn-option", "Fn + Option", kCGEventFlagMaskSecondaryFn | kCGEventFlagMaskAlternate},
    {"fn-shift", "Fn + Shift", kCGEventFlagMaskSecondaryFn | kCGEventFlagMaskShift},
};

// A session's name as its row shows it: its name, else its folder's.
static NSString *NameOf(Row *row) {
    return row.name.length ? row.name : row.cwd.lastPathComponent.length ? row.cwd.lastPathComponent : @"A session";
}

#pragma mark For the tests

// One look at the keys in a sample hold: from this twentieth of a second on, these modifier keys are down, and macOS
// has counted this many keys pressed.
typedef struct { int tick; CGEventFlags flags; uint32_t presses; } Look;

// When a sample hold of `keys` counts, looked at every twentieth of a second as the app does, each look held until the
// next, the last one the end: "at 0.35s", "at 0.30s and 0.85s", or "never".
static NSString *HeldGoes(const Look *looks, size_t count, CGEventFlags keys) {
    Hold hold = {0};
    NSMutableArray *at = [NSMutableArray array];
    for (size_t i = 0; i + 1 < count; i++)
        for (int tick = looks[i].tick; tick < looks[i + 1].tick; tick++)
            if (HoldLooked(&hold, looks[i].flags, looks[i].presses, tick * 0.05, keys))
                [at addObject:[NSString stringWithFormat:@"%.2fs", tick * 0.05]];
    return at.count ? [@"at " stringByAppendingString:[at componentsJoinedByString:@" and "]] : @"never";
}

// `Whozmove --print-held-keys`: what each saved pick reads as (The Chief, a session, or Off), and when sample holds of
// each pair of keys Settings offers count. The module's tests check it: a shortcut typed with the keys (⌥fn⌫), ⌘ held
// with them, a paste with fn held, or Fn + Control, which is left to dictation apps, must bring nothing forward.
static int PrintHeldKeys(void) {
    printf("A saved pick:\n");
    struct { const char *what; NSString *saved; } saved[] = {
        {"The Chief, as its choice has always been saved", @"chief"}, {"a session", @"session:s-1"},
        {"a session named lead", @"session:lead"}, {"another word", @"lead"}, {"a session with no id", @"session:"},
        {"none", @""}};
    for (size_t i = 0; i < sizeof saved / sizeof *saved; i++) {
        NSString *read = PickAsRead(saved[i].saved);
        printf("  %s: %s\n", saved[i].what, PicksLead(read) ? "The Chief" : read.length ? "that session" : "Off");
    }
    const CGEventFlags fn = kCGEventFlagMaskSecondaryFn, cmd = kCGEventFlagMaskCommand,
                       caps = kCGEventFlagMaskAlphaShift;
    // Each with its right-hand key's own bit, which macOS sets beside the key's (NX_DEVICERALTKEYMASK and the like).
    struct { const char *name, *other, *otherName; CGEventFlags with, right, otherPair; } pairs[] = {
        {"Fn + Option", "Option", "Fn + Control", kCGEventFlagMaskAlternate, 0x40, fn | kCGEventFlagMaskControl},
        {"Fn + Shift", "Shift", "Fn + Option", kCGEventFlagMaskShift, 0x04, fn | kCGEventFlagMaskAlternate}};
    for (size_t p = 0; p < sizeof pairs / sizeof *pairs; p++) {
        CGEventFlags k = fn | pairs[p].with, m = pairs[p].with;
        printf("%s:\n", pairs[p].name);
        struct { const char *what; Look looks[6]; size_t count; } cases[] = {
            {"Fn, then KEY, held half a second", {{0, 0, 0}, {1, fn, 0}, {2, k, 0}, {12, 0, 0}, {13, 0, 0}}, 5},
            {"KEY, then Fn, held half a second", {{0, 0, 0}, {1, m, 0}, {2, k, 0}, {12, 0, 0}, {13, 0, 0}}, 5},
            {"both, the right-hand KEY", {{0, 0, 0}, {1, k | pairs[p].right, 0}, {12, 0, 0}, {13, 0, 0}}, 4},
            {"both, let go after 0.2s", {{0, 0, 0}, {1, k, 0}, {5, 0, 0}, {6, 0, 0}}, 4},
            {"both, with Caps Lock on", {{0, caps, 0}, {1, k | caps, 0}, {12, caps, 0}, {13, caps, 0}}, 4},
            {"both, with ⌘ held too", {{0, 0, 0}, {1, k | cmd, 0}, {12, 0, 0}, {13, 0, 0}}, 4},
            {"both, down to them from ⌘ held too, as ⌘ is let go",
             {{0, 0, 0}, {1, k | cmd, 0}, {3, k, 0}, {14, 0, 0}, {15, 0, 0}}, 5},
            {"both, with ⌘ pressed and let go while they stay held",
             {{0, 0, 0}, {1, k, 0}, {3, k | cmd, 0}, {4, k, 0}, {14, 0, 0}, {15, 0, 0}}, 6},
            {"both, with a key pressed after 0.1s (a shortcut, as ⌥fn⌫ is)",
             {{0, 0, 40}, {1, k, 40}, {3, k, 41}, {12, 0, 41}, {13, 0, 41}}, 5},
            {"both, with a key pressed as they came down (an arrow, if it sets Fn's bit)",
             {{0, 0, 40}, {1, k, 41}, {12, 0, 41}, {13, 0, 41}}, 4},
            {"⌘V pasted with fn held (a dictation app's paste)",
             {{0, 0, 40}, {1, fn | cmd, 40}, {2, fn | cmd, 41}, {12, 0, 41}, {13, 0, 41}}, 5},
            {"both, held three seconds", {{0, 0, 0}, {1, k, 0}, {61, 0, 0}, {62, 0, 0}}, 4},
            {"both, let go, then held again", {{0, 0, 0}, {1, k, 0}, {10, 0, 0}, {12, k, 0}, {22, 0, 0}, {23, 0, 0}},
             6},
            {"only Fn", {{0, 0, 0}, {1, fn, 0}, {12, 0, 0}, {13, 0, 0}}, 4},
            {"OTHERS held instead", {{0, 0, 0}, {1, pairs[p].otherPair, 0}, {12, 0, 0}, {13, 0, 0}}, 4}};
        for (size_t i = 0; i < sizeof cases / sizeof *cases; i++) {
            NSString *what = [[@(cases[i].what) stringByReplacingOccurrencesOfString:@"KEY"
                                                                          withString:@(pairs[p].other)]
                              stringByReplacingOccurrencesOfString:@"OTHERS" withString:@(pairs[p].otherName)];
            printf("  %s: %s\n", what.UTF8String, HeldGoes(cases[i].looks, cases[i].count, k).UTF8String);
        }
    }
    return 0;
}

#pragma mark The module

@interface BringForwardModule : NSObject <Module> {
    Hold _hold;
}
@property (weak) Core *core;
@property (strong) NSTimer *timer;
@property (assign) BOOL launched, asleep, away;
// What the line under the header says of the last hold that brought nothing forward with no row to say it on, and when:
// The Chief's pick, or "session" for one picked that isn't listed; nil for nothing.
@property (copy) NSString *noticeFor;
@property (assign) CFAbsoluteTime noticeAt;
@end

@implementation BringForwardModule

+ (NSString *)moduleName {
    return @"bring-forward";
}

+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return @{@"--print-held-keys": ^(Core *core, NSArray *a) { return PrintHeldKeys(); }};
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    return self;
}

- (void)launch {
    self.launched = YES;
    // Fn + Control was once offered, and is now left to the apps: a pick of it becomes Fn + Option, once.
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([[defaults stringForKey:kKeys] isEqualToString:@"fn-control"])
        [defaults setObject:@(kPairs[0].key) forKey:kKeys];
    NSNotificationCenter *center = NSWorkspace.sharedWorkspace.notificationCenter;
    [center addObserver:self selector:@selector(screensSlept) name:NSWorkspaceScreensDidSleepNotification object:nil];
    [center addObserver:self selector:@selector(screensWoke) name:NSWorkspaceScreensDidWakeNotification object:nil];
    [center addObserver:self selector:@selector(sessionLeft) name:NSWorkspaceSessionDidResignActiveNotification
                 object:nil];
    [center addObserver:self selector:@selector(sessionBack) name:NSWorkspaceSessionDidBecomeActiveNotification
                 object:nil];
    [self follow];
}

- (void)screensSlept { self.asleep = YES; [self follow]; }
- (void)screensWoke { self.asleep = NO; [self follow]; }
- (void)sessionLeft { self.away = YES; [self follow]; }
- (void)sessionBack { self.away = NO; [self follow]; }

#pragma mark The sessions

// The sessions that can be picked, by id, among the rows as last read: running in a terminal the panel can type into,
// or Claude Desktop's own conversations. Worked out only when asked (a hold, or Settings drawn), never on each read.
- (NSDictionary<NSString *, Row *> *)pickable {
    NSMutableDictionary *pickable = [NSMutableDictionary dictionary];
    for (Row *row in self.core.rows.byId.allValues)
        if ([self canPick:row]) pickable[row.sessionId] = row;
    return pickable;
}

- (BOOL)canPick:(Row *)row {
    if (row.pid <= 0 || [self.core hasEnded:row]) return NO;
    id<ConversationHost> conversations = [self.core.send conversationHostOf:row];
    return conversations ? [self ownConversation:row in:conversations] : [self.core.send terminalOf:row] != nil;
}

// Whether the app that keeps a conversation knows it by its own id, which it opens: without one, Claude Desktop opens
// its last conversation instead.
- (BOOL)ownConversation:(Row *)row in:(id<ConversationHost>)conversations {
    return row.hostSessionId.length && [conversations isOwnId:row.hostSessionId];
}

// The row of the session leading the team (the team module gives each row its place), running or not, or nil.
- (Row *)leadRow {
    Row *lead = nil;
    for (Row *row in self.core.rows.byId.allValues)
        if ([row.team[@"role"] isEqual:@"lead"] && (!lead || lead.pid <= 0)) lead = row;
    return lead;
}

// The session picked, as listed: its own row, or the lead's; running or not, or nil.
- (Row *)listedPicked {
    NSString *picked = self.picked;
    if (PicksLead(picked)) return [self leadRow];
    if ([picked hasPrefix:kSessionPrefix])
        return self.core.rows.byId[[picked substringFromIndex:kSessionPrefix.length]];
    return nil;
}

// Why a session picked can't be brought forward though it's listed, as its row says it: it isn't running, or it runs
// somewhere Bring Forward can't reach.
- (NSString *)whyCantPick:(Row *)row {
    if (row.pid <= 0 || [self.core hasEnded:row]) return @"It isn't running: press its row to open it again, then "
                                                         @"hold the keys";
    if ([self.core.send conversationHostOf:row])
        return @"Claude Desktop can't open this conversation by itself: open it there";
    return @"It runs where Bring Forward can't bring it forward: only sessions in Ghostty, iTerm2 and Claude Desktop "
           @"can be";
}

#pragma mark The keys

// Looks at the keys while a session is picked and you're at the screen, and at nothing otherwise: not while the
// screens sleep, nor while another user's session is on them.
- (void)follow {
    BOOL wanted = self.launched && self.picked.length && !self.asleep && !self.away;
    if (wanted == (self.timer != nil)) return;
    [self.timer invalidate];
    self.timer = nil;
    _hold = (Hold){0};
    if (!wanted) return;
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:kLookEvery repeats:YES block:^(NSTimer *timer) {
        [weakSelf look];
    }];
    self.timer.tolerance = kLookLeeway;
}

// Which modifier keys are down, and how many keys macOS has counted pressed: neither needs a permission, and neither
// says which key you type. Only looked at: the keys go on to the apps as they would without Whozmove, so a dictation
// app listening on them still hears them.
- (void)look {
    CGEventFlags now = CGEventSourceFlagsState(kCGEventSourceStateHIDSystemState);
    uint32_t presses = CGEventSourceCounterForEventType(kCGEventSourceStateHIDSystemState, kCGEventKeyDown);
    if (HoldLooked(&_hold, now, presses, CFAbsoluteTimeGetCurrent(), self.keys)) [self bring];
}

// The session picked comes forward as a press on its row brings it (Focus's open:), and that's all. Nothing to bring
// forward: a beep, at once, and its row, or the line under the header when there's none, says why.
- (void)bring {
    if (!OnTheScreen()) return;
    Row *listed = [self listedPicked];
    NSString *name = listed ? NameOf(listed) : self.pickedName;
    NSString *log = [NSString stringWithFormat:@"bring forward %@ (%@ held): not now", name, self.keysName];
    if (!listed) {
        // No row to say it on: the line under the header says it (notices).
        [self noticeOf:PicksLead(self.picked) ? kLead : kSession];
        NSBeep();
        PanelLog(@"%@: it isn't listed", log);
        return;
    }
    if (![self canPick:listed]) {
        NSString *why = [self whyCantPick:listed];
        NSBeep();
        PanelLog(@"%@: %@", log, why);
        [self.core.page stepNote:listed.sessionId text:why];
        return;
    }
    PanelLog(@"bring forward %@ (%@ held)", name, self.keysName);
    [self.core.focus open:@{@"sessionId": listed.sessionId, @"pid": @(listed.pid)}];
}

// The line under the header says it from now, for a while (notices).
- (void)noticeOf:(NSString *)what {
    self.noticeFor = what;
    self.noticeAt = CFAbsoluteTimeGetCurrent();
}

// What the line under the header says of the last hold, for a minute, while it's still so: the session picked no longer
// listed, or no session leading a team; neither has a row to say it on.
- (NSArray<Notice *> *)notices {
    NSString *what = self.noticeFor;
    if (!what || CFAbsoluteTimeGetCurrent() - self.noticeAt > kNoticeFor) return @[];
    NSString *text;
    if ([what isEqualToString:kLead]) {
        if (!PicksLead(self.picked) || [self leadRow]) return @[];
        text = [NSString stringWithFormat:@"No session is leading a team, so %@ brought nothing forward: pick "
                                          @"another in Settings ▸ Bring Forward.", self.keysName];
    } else {
        if (![self.picked hasPrefix:kSessionPrefix] || [self listedPicked]) return @[];
        text = [NSString stringWithFormat:@"%@ isn't listed any more, so %@ brought nothing forward: pick another in "
                                          @"Settings ▸ Bring Forward.", self.pickedName, self.keysName];
    }
    // Its key is the one it has always had, so one you've put away stays away.
    Notice *notice = [Notice noticeWithKey:[what isEqualToString:kLead] ? @"no-chief" : @"session-gone"
                                     level:NoticeSoon text:text];
    notice.title = @"Bring Forward";
    notice.since = [NSString stringWithFormat:@"%.0f", self.noticeAt];
    notice.closes = YES;
    // It says why holding the keys brought nothing forward, so it's said at once, at night too.
    notice.answersYou = YES;
    return @[notice];
}

- (NSString *)keysKey {
    NSString *key = [NSUserDefaults.standardUserDefaults stringForKey:kKeys];
    for (size_t i = 0; i < sizeof kPairs / sizeof *kPairs; i++)
        if ([key isEqualToString:@(kPairs[i].key)]) return key;
    return @(kPairs[0].key);
}

- (size_t)pair {
    NSString *key = self.keysKey;
    for (size_t i = 0; i < sizeof kPairs / sizeof *kPairs; i++)
        if ([key isEqualToString:@(kPairs[i].key)]) return i;
    return 0;
}

- (CGEventFlags)keys {
    return kPairs[self.pair].flags;
}

- (NSString *)keysName {
    return @(kPairs[self.pair].name);
}

#pragma mark The picks

- (NSString *)picked {
    return PickAsRead([NSUserDefaults.standardUserDefaults stringForKey:kSession] ?: @"");
}

- (NSString *)pickedName {
    return [NSUserDefaults.standardUserDefaults stringForKey:kName] ?: @"The session picked";
}

- (void)pickSession:(NSString *)choice {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([choice isEqualToString:@"off"]) {
        [defaults removeObjectForKey:kSession];
        [defaults removeObjectForKey:kName];
    } else {
        [defaults setObject:choice forKey:kSession];
        Row *row = [self listedPicked];
        [defaults setObject:PicksLead(choice) ? @"The Chief" : row ? NameOf(row) : self.pickedName
                     forKey:kName];
    }
    [self picksChanged];
}

// A pick changed: the keys are looked at afresh, and only while a session is picked.
- (void)picksChanged {
    _hold = (Hold){0};
    [self follow];
}

// The sessions that can be picked, by their names A to Z; two of the same name each with its folder.
- (NSArray<NSDictionary *> *)sessionChoices:(NSDictionary<NSString *, Row *> *)pickable {
    NSCountedSet<NSString *> *names = [NSCountedSet set];
    for (Row *row in pickable.allValues) [names addObject:NameOf(row)];
    NSMutableArray<NSDictionary *> *choices = [NSMutableArray array];
    for (Row *row in pickable.allValues) {
        NSString *name = NameOf(row);
        if ([names countForObject:name] > 1 && row.cwd.length)
            name = [NSString stringWithFormat:@"%@ (%@)", name, row.cwd.lastPathComponent];
        [choices addObject:@{@"id": [kSessionPrefix stringByAppendingString:row.sessionId], @"name": name}];
    }
    return [choices sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedStandardCompare:b[@"name"]];
    }];
}

#pragma mark In Settings

// Bring Forward, a page of two choices after New Conversation's ⌃⌥N: the session (Off until one is picked; The Chief,
// while a session is leading a team; the sessions that can be picked; and the one picked, greyed, while it can't be),
// and the keys.
- (NSArray<SettingEntry *> *)settingEntries {
    __weak typeof(self) weakSelf = self;
    NSString *picked = self.picked.length ? self.picked : @"off";
    NSDictionary<NSString *, Row *> *pickable = self.pickable;
    NSMutableArray<NSDictionary *> *sessions = [@[@{@"id": @"off", @"name": @"Off"}] mutableCopy];
    Row *lead = [self leadRow];
    BOOL leadPickable = lead && pickable[lead.sessionId];
    BOOL pickedLead = PicksLead(picked);
    if (leadPickable) [sessions addObject:@{@"id": kLead, @"name": @"The Chief"}];
    else if (pickedLead || lead)
        [sessions addObject:@{@"id": kLead, @"enabled": @NO,
                              @"name": lead && lead.pid > 0 ? @"The Chief (where it can't be brought forward)"
                                                            : @"The Chief (not running)"}];
    NSArray<NSDictionary *> *running = [self sessionChoices:pickable];
    [sessions addObjectsFromArray:running];
    NSString *gone = nil;
    if (pickedLead && !leadPickable)
        gone = !lead ? @"No session is leading a team now. Pick another, or Off."
             : lead.pid > 0 ? @"The session leading your team is in an app Bring Forward can't bring forward. "
                              @"Pick another, or Off."
             : @"The session leading your team isn't running. Pick another, or press its row to open it again.";
    if ([picked hasPrefix:kSessionPrefix] && ![[running valueForKey:@"id"] containsObject:picked]) {
        [sessions addObject:@{@"id": picked, @"name": [self.pickedName stringByAppendingString:@" (not running)"],
                              @"enabled": @NO}];
        gone = [NSString stringWithFormat:@"%@ isn't running. Pick another, or press its row to open it again.",
                                          self.pickedName];
    }
    SettingEntry *session = [SettingEntry choiceWithKey:@"bringForwardSession" title:@"Session" glyph:@"keys"
        choices:^NSArray<NSDictionary *> * { return sessions; }
        picked:^NSString * { return picked; }
        pick:^(NSString *choice) { [weakSelf pickSession:choice]; }];
    session.page = @"Bring Forward";
    NSString *what = @"Hold the keys to bring this session forward from any app, its terminal tab or its conversation "
                     @"in Claude Desktop, as a press on its row does. Sessions in Ghostty, iTerm2 and Claude Desktop "
                     @"can be picked.";
    session.foot = gone ? [NSString stringWithFormat:@"%@ %@", gone, what] : what;
    // Claude Desktop's conversation comes forward only once Whozmove may control Claude Desktop: the way there. Looked
    // at without asking macOS to offer the permission, as Settings is drawn every second while it shows.
    Row *row = [self listedPicked];
    if (row && [self.core.send conversationHostOf:row] && !AXIsProcessTrusted()) {
        session.foot = [@"Whozmove needs the Accessibility permission to bring a Claude Desktop conversation forward. "
                        stringByAppendingString:session.foot];
        session.button = @"Open Accessibility Settings";
        session.press = ^{
            OpenLink(@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility");
        };
    }
    session.group = 20;
    session.order = 20;
    SettingEntry *keys = [SettingEntry choiceWithKey:@"bringForwardKeys" title:@"Keys" glyph:@"keys"
        choices:^NSArray<NSDictionary *> * {
            NSMutableArray *pairs = [NSMutableArray array];
            for (size_t i = 0; i < sizeof kPairs / sizeof *kPairs; i++)
                [pairs addObject:@{@"id": @(kPairs[i].key), @"name": @(kPairs[i].name)}];
            return pairs;
        }
        picked:^NSString * { return weakSelf.keysKey; }
        pick:^(NSString *choice) {
            [NSUserDefaults.standardUserDefaults setObject:choice forKey:kKeys];
            [weakSelf picksChanged];
        }];
    keys.page = @"Bring Forward";
    keys.foot = @"Held a moment with no other key pressed, so a shortcut typed with them, such as ⌥fn⌫, brings "
                @"nothing forward. Once the session is forward, speak with your dictation app's own keys, "
                @"and your words go into it. Fn is sent by Apple's keyboards (the Globe "
                @"key); many others keep it to themselves, and then the keys do nothing.";
    keys.group = 20;
    keys.order = 21;
    return @[session, keys];
}

@end
