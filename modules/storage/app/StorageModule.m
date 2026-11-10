// StorageModule: Storage's face for the core (Module). It looks at the disk every minute once the app has started, tells
// the page what the line above the list says (setDisk), puts the line away when its × is pressed, and has Storage among
// the tools on the panel's back: what the disk holds, Map My Disk (which turns the map on and opens Clean up), and its
// switches. Once Storage is on, it measures the disk for the map (Scanner), tells it the folders agents are at work in,
// answers the map's presses, and has the print modes the tests check. It offers where keys are kept (KeyPlaces) to a
// module that must never read one.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Module.h"
#import "Core.h"
#import "Page.h"
#import "PanelWindow.h"
#import "Rows.h"
#import "Focus.h"
#import "Row.h"
#import "Agent.h"
#import "Work.h"
#import "Files.h"
#import "Menus.h"
#import "Printing.h"
#import "Processes.h"
#import "Disk.h"
#import "Scanner.h"
#import "CleanUpFacts.h"
#import "KeyFacts.h"
#import "KeyScan.h"

// Its switches on its page on the panel's back, kept in the app's preferences: Storage itself (the map), off until you
// turn it on; and the line above the list, on until turned off.
static NSString *const kStorageOn = @"storageOn", *const kStorageWarn = @"storageWarn";
// How often the disk is looked at, in seconds; how old the map may be before it's measured again as the map opens or
// Storage is turned on; and as the app starts, when nobody's asked: a day, as measuring reads the whole disk.
static const NSTimeInterval kLookEvery = 60, kMeasureAfter = 3600, kMeasureAtLaunch = 24 * 3600;
// How long Keys' last look stands before the next, in seconds, and how long after launch its first look waits for the
// rows (the checkouts it looks in).
static const NSTimeInterval kKeysLookAfter = 24 * 3600, kKeysFirstLook = 30;

// `Whozmove --print-disk <file>…`: for each JSON file, by its name, what would be said of the disk, as JSON, then quit.
// Each is {total, free, samples: [[hoursAgo, free]…], closed: {hoursAgo, free, severe}, cleanable (what Clean up would
// clean, once Storage is on), measuredHoursAgo (how old the map is it was worked out from), inTrash (what it moved to
// the Trash, still there)}, sizes in GB, hours before now.
// modules/storage/tests/test.sh checks them against recorded ones.
static int PrintDisk(NSArray<NSString *> *files) {
    NSMutableDictionary *said = [NSMutableDictionary dictionary];
    double now = NSDate.date.timeIntervalSince1970 * 1000, hour = 3600 * 1000.0, gb = 1e9;
    for (NSString *file in files) {
        NSDictionary *json = AsRecord(ReadJSON(file));
        NSMutableDictionary *known = [NSMutableDictionary dictionary];
        known[@"total"] = @(AsNumber(json[@"total"]).doubleValue * gb);
        known[@"free"] = @(AsNumber(json[@"free"]).doubleValue * gb);
        NSMutableArray *samples = [NSMutableArray array];
        for (id sample in AsList(json[@"samples"])) {
            NSArray *pair = AsList(sample);
            if (pair.count == 2)
                [samples addObject:@[@(now - [AsNumber(pair[0]) doubleValue] * hour), @([AsNumber(pair[1]) doubleValue] * gb)]];
        }
        known[@"samples"] = samples;
        NSDictionary *closed = AsRecord(json[@"closed"]);
        if (closed)
            known[@"closed"] = @{@"at": @(now - AsNumber(closed[@"hoursAgo"]).doubleValue * hour),
                                 @"free": @(AsNumber(closed[@"free"]).doubleValue * gb),
                                 @"severe": @([AsNumber(closed[@"severe"]) boolValue])};
        NSMutableDictionary *shown = [DiskSays(known, now) mutableCopy];
        // With what Clean up would clean (in GB), the line's second part as it is once Storage is on.
        if ((AsNumber(json[@"cleanable"]) || AsNumber(json[@"inTrash"])) && shown)
            shown[@"sub"] = DiskLineSub(shown[@"sub"], [shown[@"tone"] isEqual:@"severe"],
                                        AsNumber(json[@"cleanable"]) ? (long long)([json[@"cleanable"] doubleValue] * gb) : -1,
                                        AsNumber(json[@"measuredHoursAgo"])
                                            ? now - [json[@"measuredHoursAgo"] doubleValue] * hour : 0,
                                        (long long)(AsNumber(json[@"inTrash"]).doubleValue * gb), now);
        // Rounded, so a case reads the same on every run.
        id days = shown[@"fullInDays"];
        if ([days isKindOfClass:NSNumber.class])
            shown[@"fullInDays"] = [NSString stringWithFormat:@"%.1f", [days doubleValue]];
        if (shown) shown[@"used"] = [NSString stringWithFormat:@"%.3f", [shown[@"used"] doubleValue]];
        said[file.lastPathComponent] = shown ?: NSNull.null;
    }
    return PrintJSON(said);
}

// `Whozmove --print-keys [--full-disk-access] <betterleaks> [<checkout>…]`: what Keys' look finds in the home folder in
// $HOME and those checkouts, with that Betterleaks, as JSON, with the way to get Whozmove again where that's what puts
// it right (`again`); `--full-disk-access` looks in Downloads and Desktop and Documents as Full Disk Access would let
// it. It writes in Whozmove's folder there and masks keys in its records, so it refuses your own home folder.
// modules/storage/tests/keys.sh checks it against a sample home.
static NSDictionary *KeysForPage(KeyScan *keys, NSSet<NSString *> *listed);

static int PrintKeys(Core *core, NSArray<NSString *> *arguments) {
    if (HomeIsYourOwn()) {
        fprintf(stderr, "--print-keys changes Whozmove's folder in $HOME: give it a throwaway home folder\n");
        return 2;
    }
    NSMutableArray *rest = [arguments mutableCopy];
    BOOL access = [rest containsObject:@"--full-disk-access"];
    [rest removeObject:@"--full-disk-access"];
    // A look stopped once it has read and kept so many records, as a restart would stop it (for the tests).
    NSUInteger keepEvery = 0, stopAfter = 0;
    for (NSString *option in @[@"--keep-every", @"--stop-after"]) {
        NSUInteger at = [rest indexOfObject:option];
        if (at == NSNotFound || at + 1 >= rest.count) continue;
        NSUInteger value = (NSUInteger)MAX([rest[at + 1] integerValue], 0);
        if ([option isEqualToString:@"--keep-every"]) keepEvery = value;
        else stopAfter = value;
        [rest removeObjectsInRange:NSMakeRange(at, 2)];
    }
    if (!rest.count) {
        fprintf(stderr, "usage: --print-keys [--full-disk-access] [--keep-every <n> --stop-after <n>] <betterleaks> "
                        "[<checkout>…]\n");
        return 2;
    }
    KeyScan *scan = [[KeyScan alloc] initWithFolder:AppDir(@"keys")];
    scan.scanner = rest[0];
    scan.fullDiskAccess = access;
    // A sample look is checked for what it finds, never for how fast a busy Mac runs it: an hour for each run.
    scan.runFor = 3600;
    if (keepEvery) scan.keepEvery = keepEvery;
    if (stopAfter) {
        scan.stopAfter = stopAfter;
        scan.stopped = ^(NSUInteger read) {
            PrintJSON(@{@"stoppedAfter": @(read)});
            exit(0);
        };
    }
    scan.agents = [core agentsThat:@protocol(AgentRecords)];
    // It looks as the app's looks go (lookIn:, told on the main thread as each place is read), and what the page would
    // be shown as it goes is kept: how many places it had read, how many keys it had found and how many counted, as
    // shown, through the same KeysForPage as tellKeys's.
    NSMutableArray *steps = [NSMutableArray array];
    __weak KeyScan *looking = scan;
    scan.onChange = ^(NSDictionary *told) {
        NSDictionary *shown = KeysForPage(looking, nil), *soFar = AsRecord(shown[@"soFar"]);
        if ([shown[@"looking"] boolValue] && [soFar[@"read"] integerValue] > 0)
            [steps addObject:@{@"read": soFar[@"read"], @"of": soFar[@"of"], @"found": soFar[@"found"],
                               @"keys": @(AsList(shown[@"keys"]).count)}];
    };
    [scan lookIn:[rest subarrayWithRange:NSMakeRange(1, rest.count - 1)]];
    while (scan.looking) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:NSDate.distantFuture];
    NSMutableDictionary *found = [KeysForPage(scan, nil) mutableCopy];
    found[@"soFar"] = steps;
    found[@"recordsRead"] = @(scan.recordsRead);
    // The way to get Whozmove again is the install module's, which reads Homebrew's record from $HOME here.
    MachineFilesInHome = YES;
    id<WhozmoveAgain> again = [core moduleThat:@protocol(WhozmoveAgain)];
    if ([found[@"getAgain"] boolValue] && again) found[@"again"] = again.wayToGetWhozmoveAgain;
    return PrintJSON(found);
}

// `Whozmove --print-keys-act <action> <id> [<place> [<busy folder>…]]`: one of a found key's actions, or of one of its
// places, as the last look in $HOME found them, with agents at work in those folders (only `private`, `trash`,
// `ignore`, `replaced` and `undo`: the others open an app); then why it didn't, or what's listed after it.
static int PrintKeysAct(NSArray<NSString *> *arguments) {
    NSSet *allowed = [NSSet setWithArray:@[@"private", @"trash", @"ignore", @"replaced", @"undo"]];
    if (HomeIsYourOwn() || arguments.count < 2 || ![allowed containsObject:arguments[0]]) {
        fprintf(stderr, "usage, in a throwaway home: --print-keys-act private|trash|ignore|replaced|undo <id> "
                        "[<place> [<busy>…]]\n");
        return 2;
    }
    KeyScan *scan = [[KeyScan alloc] initWithFolder:AppDir(@"keys")];
    NSInteger place = arguments.count > 2 ? arguments[2].integerValue : -1;
    NSArray *busy = arguments.count > 3 ? [arguments subarrayWithRange:NSMakeRange(3, arguments.count - 3)] : @[];
    NSString *why = [scan act:arguments[0] on:arguments[1] place:place file:nil busy:busy];
    return PrintJSON(@{@"why": why ?: NSNull.null, @"ids": [AsList(scan.found[@"keys"]) valueForKey:@"id"] ?: @[]});
}

@interface StorageModule : NSObject <Module, KeyPlaces>
@property (weak) Core *core;
@property (strong) Disk *disk;
@property (strong) Scanner *scanner;
@property (strong) KeyScan *keys;                              // Keys: what's left where it shouldn't be
@property (strong) NSTimer *looking;
@property (copy) NSDictionary *measuring;                 // how the measuring is going, as the scanner last said
@property (copy) NSDictionary<NSString *, NSString *> *busy;  // the folders agents are at work in, as last told
@property (copy) NSArray<NSString *> *checkouts;               // the checkouts the sessions are in, as last told
@property (assign) double busyAt;                              // when the folders agents are at work in last changed,
                                                               // or Apple's developer tools came in
@property (assign) BOOL toolsMissing;                          // whether they weren't there at the last look
// A measure you're waiting for (you turned Storage on, opened the map or pressed Measure Again), and, once it's done,
// that its map is ready and you haven't opened it since.
@property (assign) BOOL waiting, ready;
// Whether Keys' first look, a moment after launch, has started: none comes sooner.
@property (assign) BOOL keysStarted;
// What Clean up's list would clean as it starts (what's ticked to start with), for the line above the list: -1 until
// it's known.
@property (assign) long long cleanable;
@property (assign) double cleanableAt;  // when the map that was measured, in ms since 1970 (0 for the first pass's)
// What Clean up moved to the Trash, the disk's free space then, and when: the space comes back once the Trash is
// emptied, which shows as that much more free space (the Trash itself is never looked in: macOS keeps it from apps).
// Said on the line for a day at most.
@property (assign) long long trashed;
@property (assign) double trashedFree, trashedAt;
// The sessions listed now that a key was found in the conversation of, as last told: only those open from Keys.
@property (copy) NSSet<NSString *> *keysListed;
@end

@implementation StorageModule

+ (NSString *)moduleName {
    return @"storage";
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    [NSUserDefaults.standardUserDefaults registerDefaults:@{kStorageOn: @NO, kStorageWarn: @YES}];
    self.disk = [[Disk alloc] initWithFile:[AppDir(@"storage") stringByAppendingPathComponent:@"disk.json"]];
    self.scanner = [[Scanner alloc] initWithFile:[AppDir(@"storage") stringByAppendingPathComponent:@"map.json"]];
    self.cleanable = -1;
    self.keys = [[KeyScan alloc] initWithFolder:AppDir(@"keys")];
    self.keys.scanner = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:kBetterleaksInBundle];
    // A key's file opens at its line in the editor you chose, the changes module's.
    __weak typeof(self) weakSelf = self;
    self.keys.openAtLine = ^BOOL(NSString *path, NSInteger line) {
        return [[weakSelf.core moduleThat:@protocol(FilesAtLines)] openFile:path atLine:line];
    };
    // A conversation a key was found in opens as a press on its row does, while it's listed.
    self.keys.openConversation = ^NSString *(NSString *sessionId) {
        StorageModule *me = weakSelf;
        if (!me.core.rows.byId[sessionId]) return @"That conversation isn't in the list now, so it can't be opened here.";
        [me.core.focus open:@{@"sessionId": sessionId}];
        return nil;
    };
    return self;
}

// The disk is looked at now and every minute after, and measured for the map if Storage is on: only here, so a print
// run reads nothing of this Mac's disk.
- (void)launch {
    __weak typeof(self) weakSelf = self;
    self.disk.onChange = ^(NSDictionary *said) { [weakSelf tell]; };
    self.scanner.onState = ^(NSDictionary *state) {
        StorageModule *me = weakSelf;
        NSDictionary *was = me.measuring;
        me.measuring = state;
        // Measured anew, not stopped: the line above the list says the map you were waiting for is ready. The one the
        // app starts by itself as it launches says nothing.
        BOOL done = [was[@"scanning"] boolValue] && ![state[@"scanning"] boolValue]
                 && ![state[@"scannedAt"] isEqual:was[@"scannedAt"]] && state[@"scannedAt"] != NSNull.null;
        if (done && me.waiting) me.ready = YES;
        if (![state[@"scanning"] boolValue]) me.waiting = NO;
        // The first pass's usual places, or a new map: what Clean up can clean is worked out again, for the line.
        BOOL usual = state[@"usualAt"] != NSNull.null && ![state[@"usualAt"] isEqual:was[@"usualAt"]];
        if (usual || done || (!was && state[@"scannedAt"] != NSNull.null)) [me noteCleanUp];
        [me tellStorage];
    };
    [self.disk look];
    self.looking = [NSTimer scheduledTimerWithTimeInterval:kLookEvery repeats:YES block:^(NSTimer *timer) {
        [weakSelf.disk look];
        [weakSelf noticeAccess];
        [weakSelf noticeTools];
        [weakSelf keysLookIfDue];
        // While the line says how old the map is, it's told again, so its words keep up.
        StorageModule *me = weakSelf;
        if (me.cleanableAt > 0 && NSDate.date.timeIntervalSince1970 * 1000 - me.cleanableAt > kMapFreshFor * 1000)
            [me tell];
    }];
    self.looking.tolerance = 10;
    if (SwitchedOn(kStorageOn)) [self.scanner measureIfOlderThan:kMeasureAtLaunch];
    // Keys looks by itself, from the first launch: once the rows have been read, a moment after launch, and then once a
    // day. A look that couldn't look at all is tried again then, as the app may have just been installed again to put
    // that right. It looks in the agents' records too.
    self.keys.agents = [self.core agentsThat:@protocol(AgentRecords)];
    self.keys.onChange = ^(NSDictionary *found) { [weakSelf tellKeys]; };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kKeysFirstLook * NSEC_PER_SEC)), dispatch_get_main_queue(),
                   ^{
        StorageModule *me = weakSelf;
        me.keysStarted = YES;
        if (!me.keys.looking && me.keys.found[@"stopped"]) [me keysLook];
        else [me keysLookIfDue];
    });
}

- (void)pageLoaded {
    [self tell];
    [self tellStorage];
    [self tellKeys];
}

#pragma mark Keys

// Where keys are kept, from KeyFacts, the one list Keys looks in by.
- (NSArray<NSString *> *)keyPlacesInHome {
    return KeyPlacesInHome();
}

- (BOOL)isKeyFile:(NSString *)path {
    return KeyFileByName(path);
}

// The ⌄ beside a key's fix: the rest of what can be done about it, in a menu under it, as its ways name them, each
// done at once, and the page told how it went (keysActed); but moving a file to the Trash, which is asked first.
- (void)keysMenu:(NSString *)keyId at:(NSPoint)point {
    NSDictionary *key = nil;
    for (NSDictionary *each in AsList([self keysShown][@"keys"]))
        if ([each[@"id"] isEqual:keyId]) key = each;
    NSArray *ways = AsList(key[@"ways"]);
    if (ways.count < 2) return;
    NSMenu *menu = [NSMenu new];
    menu.autoenablesItems = NO;
    for (NSDictionary *way in [ways subarrayWithRange:NSMakeRange(1, ways.count - 1)]) {
        if ([@[@"trash", @"replaced", @"ignore"] containsObject:way[@"action"]])
            if (menu.itemArray.count && !menu.itemArray.lastObject.isSeparatorItem) [menu addItem:NSMenuItem.separatorItem];
        NSMenuItem *item = [menu addItemWithTitle:way[@"menu"] action:@selector(keysChose:) keyEquivalent:@""];
        item.target = self;
        NSInteger index = [way[@"place"] integerValue];
        NSString *file = index >= 0 && index < (NSInteger)[key[@"places"] count] ? key[@"places"][index][@"file"] : nil;
        item.representedObject = @{@"id": keyId, @"action": way[@"action"], @"place": way[@"place"],
                                   @"file": file ?: NSNull.null};
    }
    [self.core.window popUpMenu:menu atPagePoint:point];
}

- (void)keysChose:(NSMenuItem *)item {
    NSDictionary *way = item.representedObject;
    // Moving a file to the Trash is asked first, on the file's own line (keysAsk), and done only once it's confirmed
    // there.
    if ([way[@"action"] isEqual:@"trash"]) {
        [self.core.page call:@"keysAsk" with:@[way[@"id"], way[@"place"], way[@"file"]]];
        return;
    }
    NSString *why = [self.keys act:way[@"action"] on:way[@"id"] place:[way[@"place"] integerValue]
                              file:AsText(way[@"file"]) busy:self.busy.allKeys ?: @[]];
    [self.core.page call:@"keysActed" with:@[way[@"id"], why ?: NSNull.null]];
}

// A look a day; and one as soon as what the last one waited for is there: Apple's developer tools, for the projects,
// or Full Disk Access, allowed or taken back since. Never before the first look's moment after launch.
- (void)keysLookIfDue {
    NSDictionary *found = self.keys.found;
    if (self.keys.looking || !self.keysStarted) return;
    double lookedAt = [found[@"lookedAt"] doubleValue], now = NSDate.date.timeIntervalSince1970 * 1000;
    BOOL waited = ([found[@"tools"] boolValue] && DeveloperToolsReady())
               || (found[@"fullDiskAccess"] && [found[@"fullDiskAccess"] boolValue] != FullDiskAccess());
    if (!found || now - lookedAt > kKeysLookAfter * 1000 || waited) [self keysLook];
}

- (void)keysLook {
    self.keysStarted = YES;
    self.keys.fullDiskAccess = FullDiskAccess();
    [self.keys lookIn:self.checkouts ?: @[]];
}

// What Keys tells, as it's shown: while it looks, the keys as they're found and how far it has got (its `soFar`), and
// a key's conversation opened from it only while that session is listed (every one, for `listed` nil).
static NSDictionary *KeysShown(NSDictionary *found, NSSet<NSString *> *listed) {
    if (!found) return nil;
    NSMutableArray *keys = [NSMutableArray array];
    for (NSDictionary *key in AsList(found[@"keys"])) {
        NSIndexSet *gone = [AsList(key[@"ways"]) indexesOfObjectsPassingTest:^BOOL(NSDictionary *way, NSUInteger i,
                                                                                  BOOL *stop) {
            return listed && [way[@"action"] isEqual:@"conversation"] && ![listed containsObject:way[@"session"]];
        }];
        if (!gone.count) {
            [keys addObject:key];
            continue;
        }
        NSMutableDictionary *shown = [key mutableCopy];
        NSMutableArray *ways = [key[@"ways"] mutableCopy];
        [ways removeObjectsAtIndexes:gone];
        shown[@"ways"] = ways;
        // Nor from the line of a place of that conversation's.
        NSMutableArray *places = [NSMutableArray array];
        for (NSDictionary *place in AsList(key[@"places"])) {
            if (!listed || !AsText(place[@"session"]) || [listed containsObject:place[@"session"]]) {
                [places addObject:place];
                continue;
            }
            NSMutableDictionary *quiet = [place mutableCopy];
            NSMutableArray *can = [AsList(place[@"can"]) mutableCopy];
            [can removeObject:@"conversation"];
            quiet[@"can"] = can;
            [places addObject:quiet];
        }
        shown[@"places"] = places;
        [keys addObject:shown];
    }
    NSMutableDictionary *shown = [found mutableCopy];
    shown[@"keys"] = keys;
    return shown;
}

// What the page is shown of Keys, tellKeys's and the print run's alike: what Keys tells now, as it's shown.
static NSDictionary *KeysForPage(KeyScan *keys, NSSet<NSString *> *listed) {
    return KeysShown([keys told], listed);
}

- (NSDictionary *)keysShown {
    return KeysForPage(self.keys, self.keysListed);
}

// The page is told what Keys found ({lookedAt, keys, problem, stopped, tools, skipped, fullDiskAccess}), whether it's
// looking, which keys the line above the list was put away for (`closed`), whether Full Disk Access is allowed now,
// and, when what stopped it is put right by getting Whozmove again, the way to (`again`, the install module's).
- (void)tellKeys {
    NSMutableDictionary *told = [[self keysShown] mutableCopy] ?: [NSMutableDictionary dictionary];
    told[@"closed"] = AsList(ReadJSON([AppDir(@"keys") stringByAppendingPathComponent:@"closed.json"])) ?: @[];
    told[@"access"] = @(FullDiskAccess());
    id<WhozmoveAgain> again = [self.core moduleThat:@protocol(WhozmoveAgain)];
    if ([told[@"getAgain"] boolValue] && again) told[@"again"] = again.wayToGetWhozmoveAgain;
    [self.core.page call:@"setKeys" with:@[told]];
}

// The page is told what the line says: that it doesn't show while its switch is off; and once Storage is on, how much
// Clean up would clean as it starts, where its press goes (DiskLineSub), or, with nothing there, to see what's using
// the disk.
- (void)tell {
    NSMutableDictionary *said = [self.disk.said mutableCopy];
    if (!said) return;
    BOOL on = SwitchedOn(kStorageOn);
    said[@"on"] = @(on);
    if (!SwitchedOn(kStorageWarn)) said[@"show"] = @NO;
    long long inTrash = on ? [self inTrash:[said[@"free"] doubleValue]] : 0;
    said[@"sub"] = DiskLineSub(said[@"sub"], [said[@"tone"] isEqual:@"severe"], on ? self.cleanable : -1,
                               self.cleanableAt, inTrash, NSDate.date.timeIntervalSince1970 * 1000);
    said[@"cleanable"] = on && self.cleanable > 0 ? @(self.cleanable) : NSNull.null;
    [self.core.page call:@"setDisk" with:@[said]];
}

// What Clean up moved to the Trash that's still there, by the disk's free space now: once it's grown by half of it, or
// a day has passed, the Trash has been emptied (or it's no longer worth saying), and it's forgotten.
- (long long)inTrash:(double)free {
    if (self.trashed <= 0) return 0;
    if (free >= self.trashedFree + self.trashed / 2.0 || NSDate.date.timeIntervalSince1970 - self.trashedAt > 24 * 3600)
        self.trashed = 0;
    return self.trashed;
}

// Clean up's list worked out with nobody looking, for what the line says it would clean.
- (void)noteCleanUp {
    __weak typeof(self) weakSelf = self;
    [self.scanner cleanUp:^(NSDictionary *list) { [weakSelf noteCleanable:list]; }];
}

// What a list cleans as it starts: what's ticked to start with and nothing keeps; and the line says so.
- (void)noteCleanable:(NSDictionary *)list {
    long long cleanable = list ? 0 : -1;
    for (NSDictionary *group in AsList(list[@"groups"]))
        for (NSDictionary *item in AsList(group[@"items"]))
            if ([item[@"on"] boolValue] && !item[@"lock"]) cleanable += [AsNumber(item[@"size"]) longLongValue];
    double at = [AsNumber(list[@"scannedAt"]) doubleValue];
    if (cleanable == self.cleanable && at == self.cleanableAt) return;
    self.cleanable = cleanable;
    self.cleanableAt = at;
    [self tell];
}

// The map is told whether Storage is on, how its measuring is going, and whether the map you were waiting for is
// ready.
- (void)tellStorage {
    NSMutableDictionary *state = [self.measuring mutableCopy] ?: [NSMutableDictionary dictionary];
    BOOL on = SwitchedOn(kStorageOn);
    state[@"on"] = @(on);
    state[@"ready"] = @(on && self.ready);
    state[@"busyAt"] = @(self.busyAt);
    [self.core.page call:@"setStorage" with:@[state]];
}

// Clean up's list, worked out from the map and what the tools say, told to the page, and to the line.
- (void)tellCleanUp {
    __weak typeof(self) weakSelf = self;
    [self.scanner cleanUp:^(NSDictionary *list) {
        [weakSelf.core.page call:@"showCleanUp" with:@[list ?: NSNull.null]];
        [weakSelf noteCleanable:list];
    }];
}

// Full Disk Access allowed, or taken back, since the map was measured: it's measured again, and the line says when
// it's ready. Looked at each minute, with the disk.
// Apple's developer tools, come in since the last look: git is asked again about the checkouts that waited for them,
// and the page asks again for what it shows, as when agents start or stop work.
- (void)noticeTools {
    BOOL ready = DeveloperToolsReady();
    if (ready && self.toolsMissing) {
        [self.scanner askGitAgain];
        self.busyAt = NSDate.date.timeIntervalSince1970 * 1000;
        [self tellStorage];
    }
    self.toolsMissing = !ready;
}

- (void)noticeAccess {
    if (!SwitchedOn(kStorageOn) || !self.measuring || [self.measuring[@"scanning"] boolValue]) return;
    if ([self.measuring[@"fullDiskAccess"] boolValue] == FullDiskAccess()) return;
    [self measureAsked:kMeasureAfter];
}

// A measure you asked for, or watched start: the line says once it's done.
- (void)measureAsked:(NSTimeInterval)age {
    self.waiting = YES;
    [self.scanner measureIfOlderThan:age];
}

// Turning Storage on measures the disk; turning it off stops, and deletes what the map knew.
- (void)turn:(BOOL)on {
    SetSwitch(kStorageOn, on);
    self.ready = NO;
    self.cleanable = -1;
    if (on) [self measureAsked:kMeasureAfter];
    else [self.scanner forget];
    [self tell];
    [self tellStorage];
}

// The folders agents are at work in (as Deploy and the next steps wait for them), each with the agent's name: what's
// in them can't go to the Trash. And the checkouts the sessions are in, whose repos' worktrees Clean up looks at.
- (void)rows:(NSArray<Row *> *)rows phase:(RowPhase)phase {
    if (phase != RowPhaseListed) return;
    // The conversations Keys found a key in that are listed now: the page is told again when that changes.
    NSMutableSet<NSString *> *named = [NSMutableSet set], *listed = [NSMutableSet set];
    for (NSDictionary *key in AsList(self.keys.found[@"keys"]))
        for (NSDictionary *way in AsList(key[@"ways"]))
            if (AsText(way[@"session"])) [named addObject:way[@"session"]];
    for (Row *row in rows)
        if (row.sessionId && [named containsObject:row.sessionId]) [listed addObject:row.sessionId];
    if (![listed isEqualToSet:self.keysListed ?: [NSSet set]]) {
        self.keysListed = listed;
        [self tellKeys];
    }
    NSMutableDictionary<NSString *, NSString *> *busy = [NSMutableDictionary dictionary];
    NSMutableOrderedSet<NSString *> *checkouts = [NSMutableOrderedSet orderedSet];
    for (Row *row in rows) {
        for (NSString *root in @[row.git[@"root"] ?: @"", row.workGit[@"root"] ?: @""])
            if (root.length > 1) [checkouts addObject:root];
        // Anything it runs in the background counts, a command left running among them: a build or an install there
        // writes files too.
        if (!AgentAtWork(row) && !row.background.count) continue;
        NSString *who = [self.core agentOf:row].name ?: @"An agent";
        for (NSString *folder in @[row.git[@"root"] ?: @"", row.workGit[@"root"] ?: @"", row.cwd ?: @"",
                                   row.workRoot ?: @""])
            if (folder.length > 1) busy[folder] = who;
    }
    if (![checkouts.array isEqualToArray:self.checkouts ?: @[]]) {
        self.checkouts = checkouts.array;
        [self.scanner noteCheckouts:checkouts.array];
    }
    if ([busy isEqualToDictionary:self.busy ?: @{}]) return;
    self.busy = busy;
    [self.scanner setBusy:busy];
    // The page asks again for what it shows, so a lock on a folder an agent has left goes, and one it's started in
    // comes.
    self.busyAt = NSDate.date.timeIntervalSince1970 * 1000;
    [self tellStorage];
}

// The line's ×, and the map's presses: a folder to show (measured again first if it's an hour old and the map is just
// opening), Measure Again, what you collected moved to the Trash, an item shown in Finder, and Allow Access (a row's,
// or Keys'); and Clean up's: what comes back on its own, and cleaning what you ticked of it.
- (NSDictionary<NSString *, void (^)(NSDictionary *)> *)messages {
    __weak typeof(self) weakSelf = self;
    return @{
        @"storageNoteClosed": ^(NSDictionary *msg) {
            StorageModule *me = weakSelf;
            if (![msg[@"ready"] boolValue]) return [me.disk closeNote];
            me.ready = NO;
            [me tellStorage];
        },
        @"storageFolder": ^(NSDictionary *msg) {
            StorageModule *me = weakSelf;
            if (!SwitchedOn(kStorageOn)) return;
            NSInteger nodeId = [AsNumber(msg[@"id"]) integerValue];
            // The disk is asked for as the map opens: the map is seen, so the line about it goes.
            if (nodeId == 0) {
                if (me.ready) {
                    me.ready = NO;
                    [me tellStorage];
                }
                [me measureAsked:kMeasureAfter];
            }
            [me.scanner folder:nodeId done:^(NSDictionary *view) {
                [weakSelf.core.page call:@"showFolder" with:@[@(nodeId), view ?: NSNull.null]];
            }];
        },
        @"storageTrash": ^(NSDictionary *msg) {
            if (!SwitchedOn(kStorageOn)) return;
            NSMutableArray<NSNumber *> *ids = [NSMutableArray array];
            for (id each in AsList(msg[@"ids"])) if (AsNumber(each)) [ids addObject:each];
            // A folder's parts taken back out of it, by the folder's id (a JSON object's keys are words).
            NSMutableDictionary<NSNumber *, NSArray<NSNumber *> *> *keep = [NSMutableDictionary dictionary];
            NSDictionary *asked = AsRecord(msg[@"keep"]);
            for (NSString *key in asked) {
                NSMutableArray<NSNumber *> *parts = [NSMutableArray array];
                for (id each in AsList(asked[key])) if (AsNumber(each)) [parts addObject:each];
                if ([key isKindOfClass:NSString.class] && parts.count) keep[@(key.integerValue)] = parts;
            }
            [weakSelf.scanner trash:ids keeping:keep measuredAt:[AsNumber(msg[@"measuredAt"]) doubleValue]
                               done:^(NSDictionary *result) {
                [weakSelf.core.page call:@"storageTrashed" with:@[result]];
            }];
        },
        @"storageMeasure": ^(NSDictionary *msg) {
            if (SwitchedOn(kStorageOn)) [weakSelf measureAsked:0];
        },
        @"storageReveal": ^(NSDictionary *msg) {
            if (SwitchedOn(kStorageOn) && AsNumber(msg[@"id"])) [weakSelf.scanner reveal:[msg[@"id"] integerValue]];
        },
        @"storageAllow": ^(NSDictionary *msg) { ShowFullDiskAccessSettings(); },
        // Keys': Look Again; one of a key's actions, or one of a place's, by its index in the key's places (never where
        // an agent is at work); the line above the list put away until another key is found, by the keys it named; and
        // getting Whozmove again, the install module's way, when that's what puts Keys right.
        @"keysLook": ^(NSDictionary *msg) {
            if (!weakSelf.keys.looking) [weakSelf keysLook];
        },
        @"keysAction": ^(NSDictionary *msg) {
            StorageModule *me = weakSelf;
            NSString *id = AsText(msg[@"id"]), *action = AsText(msg[@"action"]);
            if (!id || !action) return;
            NSNumber *place = AsNumber(msg[@"place"]);
            NSString *why = [me.keys act:action on:id place:place ? place.integerValue : -1 file:AsText(msg[@"file"])
                                    busy:me.busy.allKeys ?: @[]];
            [me.core.page call:@"keysActed" with:@[id, why ?: NSNull.null]];
        },
        @"keysMenu": ^(NSDictionary *msg) {
            [weakSelf keysMenu:AsText(msg[@"id"]) at:NSMakePoint([AsNumber(msg[@"x"]) doubleValue],
                                                                 [AsNumber(msg[@"y"]) doubleValue])];
        },
        @"keysClosed": ^(NSDictionary *msg) {
            NSMutableArray *ids = [NSMutableArray array];
            for (id each in AsList(msg[@"ids"])) if (AsText(each)) [ids addObject:each];
            NSString *path = [AppDir(@"keys") stringByAppendingPathComponent:@"closed.json"];
            NSData *data = [NSJSONSerialization dataWithJSONObject:ids options:0 error:nil];
            if (data) [data writeToFile:path atomically:YES];
            [weakSelf tellKeys];
        },
        @"keysAgain": ^(NSDictionary *msg) {
            StorageModule *me = weakSelf;
            if (![me.keys.found[@"getAgain"] boolValue]) return;
            [[me.core moduleThat:@protocol(WhozmoveAgain)] getWhozmoveAgain];
        },
        // An app Clean up offers to open, by the word its list gave (Docker, so it can say what it can free).
        @"storageOpen": ^(NSDictionary *msg) {
            NSString *bundle = [msg[@"app"] isEqual:@"docker"] ? kDockerApp : nil;
            NSURL *url = bundle ? [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:bundle] : nil;
            if (url) [NSWorkspace.sharedWorkspace openApplicationAtURL:url
                                                         configuration:[NSWorkspaceOpenConfiguration configuration]
                                                     completionHandler:nil];
        },
        // The low-disk line's press while Storage is off, or Map My Disk beside the list: that press is the yes.
        // Storage turns on and opens beside the list on its tab (Clean up, or the map), saying it turned on; Turn Off,
        // there, turns it off again.
        @"storageOn": ^(NSDictionary *msg) {
            StorageModule *me = weakSelf;
            if (!SwitchedOn(kStorageOn)) [me turn:YES];
            [me.core.page call:@"openStorage" with:@[[msg[@"view"] isEqual:@"map"] ? @"map" : @"clean", @YES]];
        },
        @"storageOff": ^(NSDictionary *msg) {
            if (SwitchedOn(kStorageOn)) [weakSelf turn:NO];
        },
        @"storageCleanUp": ^(NSDictionary *msg) {
            if (SwitchedOn(kStorageOn)) [weakSelf tellCleanUp];
        },
        @"storageClean": ^(NSDictionary *msg) {
            if (!SwitchedOn(kStorageOn)) return;
            NSMutableArray<NSString *> *ids = [NSMutableArray array];
            for (id each in AsList(msg[@"ids"])) if (AsText(each)) [ids addObject:each];
            // Each step as it goes, for its row; and what went to the Trash, for the line until it's emptied.
            [weakSelf.scanner clean:ids measuredAt:[AsNumber(msg[@"measuredAt"]) doubleValue]
                           progress:^(NSDictionary *step) { [weakSelf.core.page call:@"cleanProgress" with:@[step]]; }
                               done:^(NSDictionary *result) {
                StorageModule *me = weakSelf;
                long long trashed = [AsNumber(result[@"trashed"]) longLongValue];
                if (trashed > 0) {
                    if (me.trashed <= 0) me.trashedFree = [me.disk.said[@"free"] doubleValue];
                    me.trashed += trashed;
                    me.trashedAt = NSDate.date.timeIntervalSince1970;
                }
                [me.core.page call:@"storageCleaned" with:@[result]];
                // A tool's command frees space the map can't see go: it's measured again, and the line says when.
                if ([result[@"ran"] integerValue]) [me measureAsked:0];
                [me tellCleanUp];
                [me.disk look];
            }];
        },
    };
}

// Storage, among the tools on the panel's back, its page leading with what it does: what the disk holds now and how
// fast it's filling, then Map My Disk, which turns the map on and opens Clean up beside the list, or once it's on,
// Clean Up with how much it would clean, and Open the Map. Full Disk Access is asked for only on the map's rows it
// couldn't look inside for want of it, never here. Its switches: Storage itself, once it's on, to turn it off again, and the line's.
- (NSArray<AppEntry *> *)appEntries {
    __weak typeof(self) weakSelf = self;
    AppEntry *storage = [AppEntry appWithId:@"storage" name:@"Storage"
                                       does:@"Shows what fills your disk, tells you before it's full, and finds keys "
                                             @"left where they shouldn't be."
                                      order:200];
    storage.tool = YES;
    storage.present = ^BOOL { return YES; };
    storage.permission = AppPermissionFullDiskAccess;
    storage.permissionFor = @"Lets the map look inside Desktop, Documents, Downloads and other apps' folders";
    storage.card = ^NSDictionary * {
        StorageModule *me = weakSelf;
        NSDictionary *said = me.disk.said;
        if (!said) return nil;
        BOOL on = SwitchedOn(kStorageOn);
        NSString *clean = me.cleanable > 0 ? [@"Clean Up " stringByAppendingString:DiskSize(me.cleanable)]
                                           : @"Clean Up";
        NSArray *lines = on ? said[@"lines"] : [said[@"lines"] arrayByAddingObject:
                                                   @"Map My Disk takes a minute or two, and stays on this Mac."];
        // How old what Clean Up says it frees is, once the map it comes from isn't fresh, as the line says it.
        double now = NSDate.date.timeIntervalSince1970 * 1000;
        if (on && me.cleanable > 0 && me.cleanableAt > 0 && now - me.cleanableAt > kMapFreshFor * 1000)
            lines = [lines arrayByAddingObject:[NSString stringWithFormat:@"What Clean Up frees is from the map measured "
                                                @"%@.", DiskAgo(me.cleanableAt, now)]];
        return @{
            @"figure": [DiskSize([said[@"free"] doubleValue]) stringByAppendingString:@" free"],
            @"of": [@"of " stringByAppendingString:DiskSize([said[@"total"] doubleValue])],
            @"bar": said[@"used"], @"tone": said[@"tone"], @"lines": lines,
            @"actions": on ? @[@{@"id": @"clean", @"title": clean, @"main": @YES},
                               @{@"id": @"map", @"title": @"Open the Map"}]
                           : @[@{@"id": @"on", @"title": @"Map My Disk", @"main": @YES}]};
    };
    // Map My Disk turns Storage on and opens Clean up beside the list once the panel has turned back to it, saying it
    // turned on; Clean Up opens it on what comes back on its own, and Open the Map on the map.
    storage.act = ^(NSString *action) {
        StorageModule *me = weakSelf;
        BOOL turned = [action isEqualToString:@"on"] && !SwitchedOn(kStorageOn);
        if (turned) [me turn:YES];
        else if (!([action isEqualToString:@"map"] || [action isEqualToString:@"clean"]) || !SwitchedOn(kStorageOn))
            return;
        NSString *view = [action isEqualToString:@"map"] ? @"map" : @"clean";
        [me.core.window turnOver:NO then:^{ [weakSelf.core.page call:@"openStorage" with:@[view, @(turned)]]; }];
    };
    AppSwitch *on = [AppSwitch switchWithKey:@"on" title:@"Know your storage"
                                        help:@"Keeps a map of what fills your disk. Turned off, the map is deleted."
                                          on:^BOOL { return SwitchedOn(kStorageOn); }
                                         set:^(BOOL on) { [weakSelf turn:on]; }];
    on.shown = ^BOOL { return SwitchedOn(kStorageOn); };
    storage.switches = @[
        on,
        [AppSwitch switchWithKey:@"warn" title:@"Tell me when space runs low"
                            help:@"A line above your sessions, under 25 GB free, or under 50 GB and a week from full"
                              on:^BOOL { return SwitchedOn(kStorageWarn); }
                             set:^(BOOL on) {
                                 SetSwitch(kStorageWarn, on);
                                 [weakSelf tell];
                             }],
    ];
    return @[storage];
}

// `Whozmove --print-map [<busy.json>]`: the folder in $HOME measured as the map measures your home folder, each part
// with what keeps it from going, given the folders agents are at work in ({folder: who}), as JSON. Nothing is moved.
// `Whozmove --print-cleanup [<busy.json> [<checkout>…]]`: Clean up's list for it, given the checkouts the sessions are
// in too; no tool is asked anything, and nothing is cleaned. `--print-cleanup-usual [<busy.json>]`: the list from the
// first pass alone, before the first map: the usual places only. `--print-cleanup-clean <stand-in Trash> <busy.json>
// [--stale] [--linked <folder>] <id>…`: what cleaning those does, step by step, moving into the stand-in folder, never
// the Trash, and running no tool, `--linked` a folder put behind a link once the map is measured; it moves files in
// $HOME, so it refuses your own.
+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return @{
        @"--print-disk": ^int(Core *core, NSArray<NSString *> *arguments) { return PrintDisk(arguments); },
        @"--print-keys": ^int(Core *core, NSArray<NSString *> *arguments) { return PrintKeys(core, arguments); },
        @"--print-keys-act": ^int(Core *core, NSArray<NSString *> *arguments) { return PrintKeysAct(arguments); },
        // `Whozmove --print-keys-judge <cases.json>`: each case {rule, line, match} as Keys judges it (KeyJudged), by
        // its line's own words, never the line.
        @"--print-keys-judge": ^int(Core *core, NSArray<NSString *> *arguments) {
            NSMutableArray *judged = [NSMutableArray array];
            for (NSDictionary *each in AsList(ReadJSON(arguments.firstObject ?: @"")))
                [judged addObject:KeyJudged(AsText(each[@"rule"]) ?: @"", AsText(each[@"line"]) ?: @"",
                                            AsText(each[@"match"]) ?: @"")];
            return PrintJSON(judged);
        },
        @"--print-map": ^int(Core *core, NSArray<NSString *> *arguments) {
            NSDictionary *busy = arguments.count ? AsRecord(ReadJSON(arguments[0])) : @{};
            return PrintJSON(MapOfHome(busy) ?: NSNull.null);
        },
        @"--print-cleanup": ^int(Core *core, NSArray<NSString *> *arguments) {
            NSDictionary *busy = arguments.count ? AsRecord(ReadJSON(arguments[0])) : @{};
            NSArray *checkouts = arguments.count > 1 ? [arguments subarrayWithRange:NSMakeRange(1, arguments.count - 1)]
                                                     : @[];
            return PrintJSON(CleanUpOfHome(busy, checkouts) ?: NSNull.null);
        },
        @"--print-cleanup-clean": ^int(Core *core, NSArray<NSString *> *arguments) {
            NSMutableArray *rest = [arguments mutableCopy];
            BOOL stale = [rest containsObject:@"--stale"];
            [rest removeObject:@"--stale"];
            NSString *linked = nil;
            NSUInteger at = [rest indexOfObject:@"--linked"];
            if (at != NSNotFound && at + 1 < rest.count) {
                linked = rest[at + 1];
                [rest removeObjectsInRange:NSMakeRange(at, 2)];
            }
            if (HomeIsYourOwn() || rest.count < 2) {
                fprintf(stderr, "usage, in a throwaway home: --print-cleanup-clean <stand-in Trash> <busy.json> "
                                "[--stale] [--linked <folder>] <id>…\n");
                return 2;
            }
            NSDictionary *busy = AsRecord(ReadJSON(rest[1])) ?: @{};
            return PrintJSON(CleanOfHome(rest[0], busy, [rest subarrayWithRange:NSMakeRange(2, rest.count - 2)],
                                         stale, linked) ?: NSNull.null);
        },
        @"--print-cleanup-usual": ^int(Core *core, NSArray<NSString *> *arguments) {
            NSDictionary *busy = arguments.count ? AsRecord(ReadJSON(arguments[0])) : @{};
            return PrintJSON(UsualCleanUpOfHome(busy) ?: NSNull.null);
        },
    };
}

@end
