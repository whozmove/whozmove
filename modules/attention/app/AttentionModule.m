// AttentionModule: while Working on Whozmove ▸ Keep App Switches is on, keeps on this Mac what you turn to, for
// measuring how much of you your agents take: each app that comes to the front (only whether it's one Whozmove works
// with, a terminal it knows or Claude Desktop), when you go away from the Mac and come back, and when you look at a
// session. Each day's lines are kept 14 days, and
// nothing is sent anywhere.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import "Module.h"
#import "Core.h"
#import "Focus.h"
#import "Row.h"
#import "Rows.h"
#import "Files.h"
#import "Menus.h"
#import "Log.h"
#import "Attention.h"

// The switch, kept in the app's preferences: off until you press it.
static NSString *const kKeep = @"keepAppSwitches";

static double Now(void) {
    return NSDate.date.timeIntervalSince1970;
}

@interface AttentionModule : NSObject <Module>
@property (weak) Core *core;
@property (copy) NSString *folder;
// Whether you were at the Mac as last kept (nil until the first tick with the switch on), each session's seenAt as
// last kept and as last seen (in ms), and the day old files were last taken away on. And whether a line has failed
// this launch (said once) and whether the last one did (the item says so).
@property (strong) NSNumber *atTheMac;
@property (strong) NSMutableDictionary<NSString *, NSNumber *> *seenKept, *seenLast;
@property (copy) NSString *forgotOn;
@property BOOL failed, failing;
@end

@implementation AttentionModule

+ (NSString *)moduleName {
    return @"attention";
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.folder = AppDir(@"attention");
    self.seenKept = [NSMutableDictionary dictionary];
    self.seenLast = [NSMutableDictionary dictionary];
    return self;
}

- (void)launch {
    [self forgetOld:Now()];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(cameToFront:)
                                                           name:NSWorkspaceDidActivateApplicationNotification
                                                         object:nil];
}

- (void)cameToFront:(NSNotification *)note {
    if (!SwitchedOn(kKeep)) return;
    NSRunningApplication *app = note.userInfo[NSWorkspaceApplicationKey];
    [self front:app.bundleIdentifier at:Now()];
}

// Each refresh ticks the modules before the focus part marks the rows (Rows.m), so this reads the marks of the read
// before: a look you've begun is kept within a second or two.
- (void)tick {
    double now = Now();
    [self forgetOld:now];
    if (!SwitchedOn(kKeep)) {
        self.atTheMac = nil;
        [self.seenKept removeAllObjects];
        [self.seenLast removeAllObjects];
        return;
    }
    if (!self.atTheMac) {
        NSMutableDictionary *seenAts = [NSMutableDictionary dictionary];
        for (Row *row in self.core.rows.byId.allValues)
            if (row.sessionId.length && row.seenAt) seenAts[row.sessionId] = row.seenAt;
        [self start:seenAts front:NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier at:now];
    }
    [self presence:AtTheMac() at:now];
    for (Row *row in self.core.rows.byId.allValues) [self seen:row.sessionId at:row.seenAt now:now];
}

// ---- What each event keeps: the same steps for the app and for the print run ----

// Just ticked: the looks the focus part has kept since Whozmove started are taken as kept, so none made while it was
// off is written, and the record starts with the app in front (whether you're at the Mac follows on the same tick).
- (void)start:(NSDictionary<NSString *, NSNumber *> *)seenAts front:(NSString *)appId at:(double)now {
    [self.seenKept setDictionary:seenAts];
    [self.seenLast setDictionary:seenAts];
    [self front:appId at:now];
}

- (void)front:(NSString *)appId at:(double)now {
    [self keep:AttentionFront(now, appId.length && [self.core hostFor:appId] != nil) now:now];
}

- (void)presence:(BOOL)here at:(double)now {
    if (self.atTheMac && self.atTheMac.boolValue == here) return;
    self.atTheMac = @(here);
    [self keep:AttentionPresence(now, here) now:now];
}

- (void)seen:(NSString *)sessionId at:(NSNumber *)seenAt now:(double)now {
    if (!sessionId.length || !seenAt || [self.seenLast[sessionId] isEqual:seenAt]) return;
    BOOL due = AttentionSeenDue(self.seenKept[sessionId], self.seenLast[sessionId], seenAt.doubleValue);
    self.seenLast[sessionId] = seenAt;
    if (!due) return;
    self.seenKept[sessionId] = seenAt;
    [self keep:AttentionSeen(seenAt.doubleValue / 1000, sessionId) now:now];
}

- (void)keep:(NSDictionary *)line now:(double)now {
    self.failing = !AttentionAppend(self.folder, line, now);
    if (!self.failing || self.failed) return;
    self.failed = YES;  // said once a launch, not every second; each line after it is still tried
    LogProblem(@"attention: couldn't keep a line in its folder (said once a launch)");
}

// Each day's file goes once it has had its 14 days, whether the switch is on or off.
- (void)forgetOld:(double)now {
    NSString *today = AttentionFileFor(now);
    if ([self.forgotOn isEqualToString:today]) return;
    self.forgotOn = today;
    NSFileManager *files = NSFileManager.defaultManager;
    NSArray *names = [files contentsOfDirectoryAtPath:self.folder error:nil] ?: @[];
    for (NSString *name in AttentionExpired(names, now))
        [files removeItemAtPath:[self.folder stringByAppendingPathComponent:name] error:nil];
}

// ---- Working on Whozmove ▸ Keep App Switches ----

// Ticked while it keeps; while its last line couldn't be written, it says so, rather than look as if it kept them.
- (NSArray<MenuEntry *> *)menuEntries {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Keep App Switches" action:@selector(flip)
                                           keyEquivalent:@""];
    item.target = self;
    MenuEntry *entry = [MenuEntry entryIn:MenuSectionWhozmove order:50 item:item];
    __weak AttentionModule *weakSelf = self;
    entry.willOpen = ^{
        BOOL on = SwitchedOn(kKeep);
        item.state = on ? NSControlStateValueOn : NSControlStateValueOff;
        BOOL failing = on && weakSelf.failing;
        item.title = failing ? @"Keep App Switches: Can't Write" : @"Keep App Switches";
        item.toolTip = failing ? @"Whozmove can't write to attention/ in its folder in Application Support: panel.log "
                                 @"says when it started" : nil;
    };
    return @[entry];
}

- (void)flip {
    FlipSwitch(kKeep);
    PanelLog(@"Keep App Switches turned %@", SwitchedOn(kKeep) ? @"on" : @"off");
}

// ---- Print run ----

// --print-attention <events.json>: made-up events taken in turn as the module takes them, into this home's attention
// folder, then each file there with its lines. An event is {"at": seconds, "front": an app's id}, {"at", "atTheMac":
// true or false}, {"at", "seen": a session's id, "seenAt": ms}, {"at", "start": true, "front", "seenAts": {id: ms}},
// as the switch is ticked, or {"at", "forget": true}, which takes away the days past their 14; "files" makes empty
// files of those names first. It writes in the home, so it refuses your own.
static int PrintAttention(Core *core, NSArray *args) {
    if (HomeIsYourOwn()) {
        fprintf(stderr, "--print-attention writes in its home: give it a throwaway one\n");
        return 2;
    }
    NSData *data = args.count ? [NSData dataWithContentsOfFile:args[0]] : nil;
    NSDictionary *given = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![given isKindOfClass:NSDictionary.class]) {
        fprintf(stderr, "--print-attention needs a file of events\n");
        return 2;
    }
    AttentionModule *module = [[AttentionModule alloc] initWithCore:core];
    [NSFileManager.defaultManager createDirectoryAtPath:module.folder withIntermediateDirectories:YES
                                             attributes:@{NSFilePosixPermissions: @0700} error:nil];
    for (NSString *name in given[@"files"])
        [NSFileManager.defaultManager createFileAtPath:[module.folder stringByAppendingPathComponent:name]
                                              contents:NSData.data attributes:@{NSFilePosixPermissions: @0600}];
    for (NSDictionary *e in given[@"events"]) {
        double at = [e[@"at"] doubleValue];
        if (e[@"start"]) [module start:e[@"seenAts"] ?: @{} front:e[@"front"] at:at];
        else if (e[@"front"]) [module front:e[@"front"] at:at];
        if (e[@"atTheMac"]) [module presence:[e[@"atTheMac"] boolValue] at:at];
        if (e[@"seen"]) [module seen:e[@"seen"] at:e[@"seenAt"] now:at];
        if (e[@"forget"]) [module forgetOld:at];
    }
    NSFileManager *files = NSFileManager.defaultManager;
    for (NSString *name in [[files contentsOfDirectoryAtPath:module.folder error:nil]
                               sortedArrayUsingSelector:@selector(compare:)]) {
        NSString *path = [module.folder stringByAppendingPathComponent:name];
        NSNumber *mode = [files attributesOfItemAtPath:path error:nil][NSFilePosixPermissions];
        printf("%s (%o)\n", name.UTF8String, mode.intValue);
        NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        for (NSString *line in [text componentsSeparatedByString:@"\n"])
            if (line.length) printf("  %s\n", line.UTF8String);
    }
    NSNumber *mode = [files attributesOfItemAtPath:module.folder error:nil][NSFilePosixPermissions];
    printf("the folder (%o)\n", mode.intValue);
    return 0;
}

+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return @{@"--print-attention": ^(Core *core, NSArray *a) { return PrintAttention(core, a); }};
}

@end
