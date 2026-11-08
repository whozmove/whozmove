// AppsModule: the panel's back, which the header's four squares turn the panel over to: Settings, the panel's own and
// each module's, and the apps Whozmove works with, each module's, and on each one's page what Whozmove does with it,
// its switches and what macOS lets Whozmove do with it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#import "Module.h"
#import "Core.h"
#import "Modules.h"
#import "Settings.h"
#import "PanelWindow.h"
#import "Page.h"
#import "Printing.h"
#import "AppleEvents.h"
#import "Links.h"
#import "Log.h"
#import "BackPage.h"
#import "Files.h"

// While the panel is turned over, what it shows is looked at again each tick (one a second), as the modules' cards
// change while it's open (Install pressed on one); what macOS lets Whozmove do with each app this often, in ticks, as
// it's changed in System Settings, not here, and asking can take a moment.
static const NSInteger kCheckEvery = 3;
// The size each app's icon is taken at, in pixels: twice the largest it's shown at on the back.
static const CGFloat kIconPixels = 96;
// How long where an app is on this Mac is taken as known, in seconds, as apps are installed and removed meanwhile (the
// core takes its own look as long).
static const NSTimeInterval kKnownFor = 30;

static NSString *PermissionKind(AppPermission permission) {
    return permission == AppPermissionAccessibility ? @"accessibility"
         : permission == AppPermissionAutomation ? @"automation"
         : permission == AppPermissionFullDiskAccess ? @"fullDiskAccess" : nil;
}

// How long a time picked from an AppTime's menu steps, in minutes: the day's half hours.
static const NSInteger kTimeStep = 30;
static const NSInteger kDay = 24 * 60;

// A time of day, `minutes` after midnight, as the Mac writes one where `locale` is: 22:00, or 10:00 PM.
static NSString *TimeWords(NSInteger minutes, NSLocale *locale) {
    NSDateFormatter *format = [NSDateFormatter new];
    format.locale = locale;
    format.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    [format setLocalizedDateFormatFromTemplate:@"jmm"];
    return [format stringFromDate:[NSDate dateWithTimeIntervalSince1970:((minutes % kDay) + kDay) % kDay * 60]];
}

// The times an AppTime's menu offers for one end, now at `now`: each of the day's half hours, and `now` too if it's
// between them, but the other end's time, `other`, as a part of the day can't end as it starts.
static NSArray<NSNumber *> *TimesToPick(NSInteger now, NSInteger other) {
    NSMutableArray<NSNumber *> *times = [NSMutableArray array];
    for (NSInteger minutes = 0; minutes < kDay; minutes += kTimeStep)
        if (minutes != other) [times addObject:@(minutes)];
    if (now != other && now % kTimeStep && now >= 0 && now < kDay) {
        [times addObject:@(now)];
        [times sortUsingSelector:@selector(compare:)];
    }
    return times;
}

// One app as the back lists it: its module's entry and those other modules add to it, and its switches, groups (in
// their order) and cards, with theirs among them.
@interface ListedApp : NSObject
@property (strong) AppEntry *entry;
@property (copy) NSArray<AppEntry *> *entries;
@property (copy) NSArray<AppSwitch *> *switches;
@property (copy) NSArray<AppGroup *> *groups;
@property (copy) NSArray<AppStatus *> *statuses;
@property (copy) NSArray<AppList *> *lists;
@end

@implementation ListedApp
@end

@interface AppsModule : NSObject <Module>
@property (weak) Core *core;
@property (strong) BackPage *back;
@property (copy) NSDictionary<NSString *, void (^)(NSDictionary *)> *answers;  // the back's messages, by type
// Each app's icon, as a data: address, by its id, once it has been found; where each app is on this Mac and when that
// was looked up, {url or NSNull, at}; and how each Automation permission stood when last checked, by app id, checked
// on a queue of its own, as asking macOS can take a moment.
@property (strong) NSMutableDictionary<NSString *, NSString *> *icons;
@property (strong) NSMutableDictionary<NSString *, NSArray *> *urls;
@property (strong) NSMutableDictionary<NSString *, NSString *> *automation;
@property (strong) dispatch_queue_t checks;
@property (assign) BOOL checking;
@property (assign) NSInteger ticks;
// What the back was last told, so it's told again only once that changes; where the glass is; where the pointer was
// last said to be on the back (nil for nowhere).
@property (copy) NSString *told;
@property (assign) NSRect glass;
@property (strong) NSDictionary *pointer;
// Settings… asked for while the panel was folded: it turns over once it has opened. And while it was turning back to
// its list: it turns over again once it has landed there.
@property (assign) BOOL settingsWhenOpen;
@property (assign) BOOL settingsWhenBack;
// The entries the apps and Settings' rows are made from: every module's, or a print run's own samples.
@property (copy) NSArray<AppEntry *> *samples;
@property (copy) NSArray<SettingEntry *> *sampleSettings;
@end

@implementation AppsModule

+ (NSString *)moduleName {
    return @"apps";
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.icons = [NSMutableDictionary dictionary];
    self.urls = [NSMutableDictionary dictionary];
    self.automation = [NSMutableDictionary dictionary];
    self.checks = dispatch_queue_create("whozmove.apps.checks", DISPATCH_QUEUE_SERIAL);
    return self;
}

// The back's page, held on the back of the glass; what it says is answered here, as the panel's page's messages
// would be, and it's told what's known once it has loaded. It's told again each time the panel starts turning over,
// so it's up to date as it comes round, and that it's out of sight once the panel is back on its list side.
- (void)launch {
    self.back = [BackPage new];
    __weak typeof(self) weakSelf = self;
    self.answers = [self messages];
    self.back.onMessage = ^(NSString *type, NSDictionary *message) {
        void (^answer)(NSDictionary *) = weakSelf.answers[type];
        if (answer) answer(message);
        else LogProblem([@"a message the panel's back sent that nothing answers: " stringByAppendingString:type]);
    };
    self.back.onLoad = ^{
        weakSelf.told = nil;
        weakSelf.pointer = nil;
        [weakSelf tell];
    };
    [self.back load];
    PanelWindow *window = self.core.window;
    [window holdBack:self.back.view];
    [window followTurn:^(BOOL turned) {
        if (turned) {
            [weakSelf tell];
            [weakSelf check];
        } else {
            [weakSelf.back call:@"turned" with:@[@NO]];
        }
    }];
    [window followGlass:^(NSRect glass, NSRect list, NSRect screen, NSTimeInterval duration) {
        weakSelf.glass = list;
    }];
    [window followPointer:^(NSPoint screen) { [weakSelf pointerAt:screen]; }];
    [window followFold:^(BOOL folded, BOOL done) {
        if (!done) return;
        if (!folded && weakSelf.settingsWhenOpen) [weakSelf turnToSettings];
        weakSelf.settingsWhenOpen = NO;
    }];
    // Settings… pressed while the panel turned back to its list: over again to Settings once it has landed there (or,
    // folding meanwhile, once it opens).
    [window followTurn:^(BOOL turned) {
        if (turned || !weakSelf.settingsWhenBack) return;
        weakSelf.settingsWhenBack = NO;
        if (weakSelf.core.window.folded) weakSelf.settingsWhenOpen = YES;
        else [weakSelf turnToSettings];
    }];
}

// Settings… in the pawn menu, in a group of its own after the panel's items.
- (NSArray<MenuEntry *> *)menuEntries {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Settings…" action:@selector(openSettings)
                                           keyEquivalent:@""];
    item.target = self;
    return @[[MenuEntry entryIn:MenuSectionFeatures order:10 item:item]];
}

// The panel comes up (if it was hidden, or back from the screen's edge) and turns over to Settings, on its back:
// folded, it opens first, and turns once it has; an open reader folds back first (the page's turnToApps); turned over
// already, the back goes to Settings from whichever page it shows; on its way back to the list, it turns over again
// once it's there, as the back it's leaving goes back to the apps as it lands.
- (void)openSettings {
    PanelWindow *window = self.core.window;
    if (!self.core.page.ready) return;
    [window bringUp];
    if (window.turningBack) {
        self.settingsWhenBack = YES;
    } else if (window.turned) {
        [self.back call:@"showSettings" with:@[]];
    } else if (window.folded) {
        self.settingsWhenOpen = YES;
        [self.core.page toggleCollapsed];
    } else {
        [self turnToSettings];
    }
}

// The back is put on Settings before the panel turns, so it's there as the back comes round, rather than the apps the
// four squares turn to.
- (void)turnToSettings {
    [self.back call:@"showSettings" with:@[]];
    [self.core.page call:@"turnToApps" with:@[]];
}

- (void)tick {
    if (!self.core.window.turned) return;
    [self tell];
    if (++self.ticks % kCheckEvery == 0) [self check];
}

#pragma mark The apps

// Every module's apps, in their order, each with its switches, groups and cards, and those other modules add to it.
- (NSArray<ListedApp *> *)listed {
    NSMutableArray<AppEntry *> *apps = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray<AppEntry *> *> *adding = [NSMutableDictionary dictionary];
    for (AppEntry *entry in self.samples ?: self.core.modules.appEntries) {
        if (entry.name) [apps addObject:entry];
        else if (entry.appId) {
            if (!adding[entry.appId]) adding[entry.appId] = [NSMutableArray array];
            [adding[entry.appId] addObject:entry];
        }
    }
    [apps sortUsingComparator:^NSComparisonResult(AppEntry *a, AppEntry *b) {
        if (a.order != b.order) return a.order < b.order ? NSOrderedAscending : NSOrderedDescending;
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];
    NSMutableArray<ListedApp *> *listed = [NSMutableArray array];
    for (AppEntry *app in apps) {
        ListedApp *each = [ListedApp new];
        each.entry = app;
        each.entries = [@[app] arrayByAddingObjectsFromArray:adding[app.appId] ?: @[]];
        NSMutableArray *switches = [NSMutableArray array], *groups = [NSMutableArray array];
        NSMutableArray *statuses = [NSMutableArray array], *lists = [NSMutableArray array];
        for (AppEntry *entry in each.entries) {
            [switches addObjectsFromArray:entry.switches ?: @[]];
            [groups addObjectsFromArray:entry.groups ?: @[]];
            [statuses addObjectsFromArray:entry.statuses ?: @[]];
            [lists addObjectsFromArray:entry.lists ?: @[]];
        }
        each.switches = switches;
        // By their order, and those with the same order as their modules listed them, the app's own first.
        each.groups = [groups sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(AppGroup *a,
                                                                                                       AppGroup *b) {
            return a.order < b.order ? NSOrderedAscending : a.order > b.order ? NSOrderedDescending : NSOrderedSame;
        }];
        each.statuses = statuses;
        each.lists = lists;
        [listed addObject:each];
    }
    return listed;
}

- (BOOL)isOnThisMac:(AppEntry *)app {
    if (app.present) return app.present();
    return [self urlOf:app] != nil;
}

- (NSURL *)urlOf:(AppEntry *)app {
    return [self urlFor:app.appId];
}

// Where the app with this id is on this Mac, or nil: for a tool that isn't an app (git), or one that isn't installed
// (Spotify). Asked of macOS again once kKnownFor has passed.
- (NSURL *)urlFor:(NSString *)appId {
    NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
    NSArray *known = self.urls[appId];
    if (known && now - [known[1] doubleValue] < kKnownFor) return known[0] == NSNull.null ? nil : known[0];
    NSURL *url = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:appId];
    self.urls[appId] = @[url ?: NSNull.null, @(now)];
    return url;
}

// What a row's or a group's `enabled` says now, as true or false for the page: nil is always. (A BOOL picked between
// with ?: is an int in C, which would go to the page as 1 or 0, and the page asks for false.)
static NSNumber *Says(BOOL (^enabled)(void)) {
    return enabled ? @(enabled()) : @YES;
}

// A switch as the back shows it, or nil while it isn't shown.
- (NSDictionary *)shownSwitch:(AppSwitch *)each {
    if (each.shown && !each.shown()) return nil;
    return @{@"kind": @"switch", @"key": each.key, @"title": each.title, @"help": each.help ?: @"", @"on": @(each.on()),
             @"enabled": Says(each.enabled), @"group": each.group ?: NSNull.null,
             @"isNew": @(each.isNew)};
}

// One of a group's rows as the back shows it, or nil while it isn't shown: a switch as the app's own are; a choice with
// its choices, the one picked and the row above them; a part of the day with its two ends, each in minutes and as the
// Mac writes it where you are (the print run's samples give their own place).
- (NSDictionary *)shownRow:(id)row locale:(NSLocale *)locale {
    if ([row isKindOfClass:AppSwitch.class]) return [self shownSwitch:row];
    if ([row isKindOfClass:AppChoice.class]) {
        AppChoice *each = row;
        if (each.shown && !each.shown()) return nil;
        NSMutableArray *choices = [NSMutableArray array];
        for (NSDictionary *choice in each.choices())
            [choices addObject:@{@"id": choice[@"id"], @"name": choice[@"name"], @"help": choice[@"help"] ?: @"",
                                 @"isNew": choice[@"isNew"] ?: @NO, @"enabled": choice[@"enabled"] ?: @YES}];
        NSDictionary *fixed = each.fixed[@"name"] ? @{@"name": each.fixed[@"name"], @"help": each.fixed[@"help"] ?: @""}
                                                  : nil;
        return @{@"kind": @"choice", @"key": each.key, @"title": each.title ?: @"", @"choices": choices,
                 @"value": each.picked() ?: NSNull.null, @"fixed": fixed ?: NSNull.null,
                 @"enabled": Says(each.enabled)};
    }
    if ([row isKindOfClass:AppTime.class]) {
        AppTime *each = row;
        if (each.shown && !each.shown()) return nil;
        NSInteger from = each.from(), to = each.to();
        return @{@"kind": @"time", @"key": each.key, @"title": each.title, @"help": each.help ?: @"", @"from": @(from),
                 @"to": @(to), @"fromSaid": TimeWords(from, locale), @"toSaid": TimeWords(to, locale),
                 @"enabled": Says(each.enabled)};
    }
    return nil;
}

// An app's groups as the back shows them: those showing now, each with its heading, its line, whether its rows can be
// pressed now, and its rows showing now.
- (NSArray<NSDictionary *> *)shownGroups:(ListedApp *)listed locale:(NSLocale *)locale {
    NSMutableArray *out = [NSMutableArray array];
    for (AppGroup *group in listed.groups) {
        if (group.shown && !group.shown()) continue;
        NSMutableArray *rows = [NSMutableArray array];
        for (id row in group.rows) {
            NSDictionary *shown = [self shownRow:row locale:locale];
            if (shown) [rows addObject:shown];
        }
        [out addObject:@{@"title": group.title ?: NSNull.null, @"foot": group.foot ?: NSNull.null,
                         @"enabled": Says(group.enabled), @"rows": rows}];
    }
    return out;
}

// Whether everything on an app's page is as recommended: what each entry for it says, those that say.
- (BOOL)isRecommended:(ListedApp *)listed {
    for (AppEntry *entry in listed.entries)
        if (entry.recommended && !entry.recommended()) return NO;
    return YES;
}

// What the back shows of each app on this Mac: its name, what Whozmove does with it, its icon, whether it opens, its
// switches and groups showing now, whether its page is as recommended, its cards with something to say now, as they
// stand, and its permission, as last checked.
- (NSArray<NSDictionary *> *)shown {
    NSMutableArray *out = [NSMutableArray array];
    for (ListedApp *listed in self.listed) {
        AppEntry *app = listed.entry;
        if (![self isOnThisMac:app]) continue;
        NSMutableArray *switches = [NSMutableArray array];
        for (AppSwitch *each in listed.switches) {
            NSDictionary *shown = [self shownSwitch:each];
            if (shown) [switches addObject:shown];
        }
        NSMutableArray *statuses = [NSMutableArray array];
        for (AppStatus *each in listed.statuses) {
            NSMutableDictionary *status = [(each.now ? each.now() : nil) mutableCopy];
            if (!status) continue;  // nothing to say now
            status[@"key"] = each.key;
            status[@"title"] = each.title;
            status[@"section"] = each.section ?: NSNull.null;
            [statuses addObject:status];
        }
        // What macOS lets Whozmove do with it only once it's installed (there's nothing to allow before), or for one
        // of Whozmove's own tools.
        // Its lists, each its row's title and count and the page it opens, as it stands now.
        NSMutableArray *lists = [NSMutableArray array];
        for (AppList *each in listed.lists) {
            NSMutableDictionary *list = [(each.now ? each.now() : nil) mutableCopy] ?: [NSMutableDictionary dictionary];
            list[@"key"] = each.key;
            list[@"title"] = each.title;
            [lists addObject:list];
        }
        NSString *kind = app.tool || [self urlOf:app] ? PermissionKind(app.permission) : nil;
        NSDictionary *permission = kind ? @{@"kind": kind, @"use": app.permissionFor ?: @"",
                                            @"state": [self permissionOf:app] ?: @"unknown"} : nil;
        [out addObject:@{@"id": app.appId, @"name": app.name, @"does": app.does ?: @"",
                         @"icon": [self iconOf:app] ?: NSNull.null, @"open": @([self urlOf:app] != nil),
                         @"switches": switches,
                         @"groups": [self shownGroups:listed locale:NSLocale.autoupdatingCurrentLocale],
                         @"recommended": @([self isRecommended:listed]), @"statuses": statuses, @"lists": lists,
                         @"permission": permission ?: NSNull.null,
                         @"tool": @(app.tool), @"card": (app.card ? app.card() : nil) ?: NSNull.null,
                         @"hint": (app.hint ? app.hint() : nil) ?: NSNull.null}];
    }
    return out;
}

#pragma mark Settings

// Settings' rows: the panel's own first, then each module's (or a print run's own samples), those showing now, by their
// card and their order on it.
- (NSArray<SettingEntry *> *)settings {
    NSArray *all = self.sampleSettings
                   ?: [self.core.settings.entries arrayByAddingObjectsFromArray:self.core.modules.settingEntries];
    NSPredicate *showing = [NSPredicate predicateWithBlock:^BOOL(SettingEntry *entry, NSDictionary *bindings) {
        return !entry.shown || entry.shown();
    }];
    return [[all filteredArrayUsingPredicate:showing] sortedArrayUsingComparator:^NSComparisonResult(SettingEntry *a,
                                                                                                      SettingEntry *b) {
        if (a.group != b.group) return a.group < b.group ? NSOrderedAscending : NSOrderedDescending;
        return a.order < b.order ? NSOrderedAscending : a.order > b.order ? NSOrderedDescending : NSOrderedSame;
    }];
}

static NSString *SettingKind(SettingEntry *entry) {
    return entry.isChoice ? @"choice" : entry.app ? @"page" : @"switch";
}

// What the back shows of each setting: its name, its tile's mark and its place; a switch's state, a choice's choices,
// each with its line, whether it's new, an app's with its icon, and the one picked; or the app whose page a row opens,
// and what it says there, while that app is listed.
- (NSArray<NSDictionary *> *)shownSettings {
    NSMutableArray *out = [NSMutableArray array];
    for (SettingEntry *entry in self.settings) {
        ListedApp *opens = entry.app ? [self appFor:entry.app] : nil;
        if (entry.app && !(opens && [self isOnThisMac:opens.entry])) continue;
        NSMutableDictionary *each = [@{@"key": entry.key, @"kind": SettingKind(entry),
            @"title": entry.title, @"glyph": entry.glyph ?: @"", @"group": @(entry.group), @"order": @(entry.order),
            @"page": entry.page ?: NSNull.null, @"style": entry.style ?: NSNull.null,
            @"foot": entry.foot ?: NSNull.null, @"button": entry.press ? entry.button ?: NSNull.null : NSNull.null}
            mutableCopy];
        if (entry.isChoice) {
            NSMutableArray *choices = [NSMutableArray array];
            for (NSDictionary *choice in entry.choices()) {
                NSString *appId = choice[@"appId"];
                [choices addObject:@{@"id": choice[@"id"], @"name": choice[@"name"], @"help": choice[@"help"] ?: @"",
                                     @"isNew": choice[@"isNew"] ?: @NO,
                                     @"icon": (appId ? [self iconFor:appId] : nil) ?: NSNull.null,
                                     @"enabled": choice[@"enabled"] ?: @YES}];
            }
            each[@"choices"] = choices;
            each[@"value"] = entry.picked() ?: NSNull.null;
        } else if (entry.app) {
            each[@"app"] = entry.app;
            each[@"said"] = (entry.said ? entry.said() : nil) ?: NSNull.null;
        } else {
            each[@"on"] = @(entry.on());
        }
        [out addObject:each];
    }
    return out;
}

// Told only once what it shows has changed.
- (void)tell {
    if (!self.back) return;
    NSArray *apps = self.shown, *settings = self.shownSettings;
    NSString *look = self.core.window.look ?: @"grey";
    NSData *json = [NSJSONSerialization dataWithJSONObject:@[apps, look, settings] options:0 error:nil];
    NSString *told = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : nil;
    if (!told || [told isEqualToString:self.told]) return;
    self.told = told;
    [self.back call:@"setApps" with:@[apps, look, settings]];
}

- (NSString *)iconOf:(AppEntry *)app {
    return [self iconFor:app.appId];
}

// The icon of the app with this id, at the back's sizes, as a data: address; nil without one, looked for again as the
// app is (an app installed since shows its own then).
- (NSString *)iconFor:(NSString *)appId {
    NSString *known = self.icons[appId];
    if (known) return known;
    NSURL *url = [self urlFor:appId];
    NSString *icon = nil;
    if (url) {
        NSImage *image = [NSWorkspace.sharedWorkspace iconForFile:url.path];
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:kIconPixels
            pixelsHigh:kIconPixels bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
            colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
        [image drawInRect:NSMakeRect(0, 0, kIconPixels, kIconPixels) fromRect:NSZeroRect
                operation:NSCompositingOperationCopy fraction:1];
        [NSGraphicsContext restoreGraphicsState];
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        if (png) icon = [@"data:image/png;base64," stringByAppendingString:[png base64EncodedStringWithOptions:0]];
    }
    if (icon) self.icons[appId] = icon;
    return icon;
}

#pragma mark What macOS lets Whozmove do

// How an app's permission stands: Accessibility is asked of macOS here, quietly; Automation as it was last checked
// (check), as macOS can take a moment to say.
- (NSString *)permissionOf:(AppEntry *)app {
    if (app.permission == AppPermissionAccessibility) return AXIsProcessTrusted() ? @"allowed" : @"denied";
    if (app.permission == AppPermissionAutomation) return self.automation[app.appId];
    if (app.permission == AppPermissionFullDiskAccess) return FullDiskAccess() ? @"allowed" : @"denied";
    return nil;
}

// Each Automation permission, asked of macOS without asking you anything, off the main thread: it can only say while
// the app is open. Once they're all back, the back is told what changed.
- (void)check {
    if (self.checking) return;
    NSMutableDictionary<NSString *, NSNumber *> *pids = [NSMutableDictionary dictionary];
    for (ListedApp *listed in self.listed) {
        AppEntry *app = listed.entry;
        if (app.permission != AppPermissionAutomation || ![self urlOf:app]) continue;
        NSRunningApplication *running = [NSRunningApplication runningApplicationsWithBundleIdentifier:app.appId]
                                            .firstObject;
        pids[app.appId] = @(running ? running.processIdentifier : 0);
    }
    if (!pids.count) return;
    self.checking = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.checks, ^{
        NSMutableDictionary<NSString *, NSString *> *states = [NSMutableDictionary dictionary];
        for (NSString *appId in pids) {
            pid_t pid = pids[appId].intValue;
            OSStatus status = pid > 0 ? AutomationPermission(pid, NO) : procNotFound;
            states[appId] = status == noErr ? @"allowed"
                          : status == errAEEventNotPermitted ? @"denied"
                          : status == errAEEventWouldRequireUserConsent ? @"ask" : @"closed";
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            AppsModule *me = weakSelf;
            me.checking = NO;
            [me.automation setDictionary:states];
            [me tell];
        });
    });
}

#pragma mark The pointer

// Where the pointer is on the back, from its top-left corner, while the panel is turned over and it's on the glass;
// told only as that changes, and once that it has gone.
- (void)pointerAt:(NSPoint)screen {
    NSDictionary *at = nil;
    if (self.core.window.turned && NSPointInRect(screen, self.glass))
        at = @{@"x": @(round(screen.x - NSMinX(self.glass))), @"y": @(round(NSMaxY(self.glass) - screen.y))};
    if ((!at && !self.pointer) || [at isEqual:self.pointer]) return;
    self.pointer = at;
    [self.back call:@"backPointer" with:@[at ?: NSNull.null]];
}

#pragma mark Its messages

// The back's presses: turning back to the list, the way round the side pressed pushes it, or back and then folding
// into the cat; a setting, and the button under one; an app's switch, one of its choices, either end of one of its
// parts of the day, and Use the Recommended Settings; a card's button; Open; and System Settings, at the pane where the
// app's permission is changed. And from the panel's page, an app's page to show as the panel turns
// over to its back (the page then asks to turn).
- (NSDictionary<NSString *, void (^)(NSDictionary *)> *)messages {
    __weak typeof(self) weakSelf = self;
    return @{
        @"appsShow": ^(NSDictionary *msg) {
            AppsModule *me = weakSelf;
            ListedApp *app = [me appFor:msg[@"app"]];
            if (!app || ![me isOnThisMac:app.entry]) return;
            [me tell];
            [me.back call:@"showApp" with:@[app.entry.appId]];
        },
        @"appsTurnBack": ^(NSDictionary *msg) {
            [weakSelf.core.window turnOver:NO left:[msg[@"side"] isEqual:@"left"] then:nil];
        },
        @"appsFold": ^(NSDictionary *msg) {
            [weakSelf.core.window turnOver:NO then:^{ [weakSelf.core.page toggleCollapsed]; }];
        },
        @"appsSetting": ^(NSDictionary *msg) { [weakSelf setting:msg]; },
        @"appsSettingButton": ^(NSDictionary *msg) {
            for (SettingEntry *entry in weakSelf.settings)
                if ([entry.key isEqual:msg[@"key"]] && entry.press) entry.press();
        },
        @"appsSwitch": ^(NSDictionary *msg) { [weakSelf flip:msg]; },
        @"appsChoice": ^(NSDictionary *msg) { [weakSelf choose:msg]; },
        @"appsTime": ^(NSDictionary *msg) { [weakSelf timeMenu:msg]; },
        @"appsUseRecommended": ^(NSDictionary *msg) { [weakSelf useRecommended:msg]; },
        @"appsAction": ^(NSDictionary *msg) { [weakSelf act:msg]; },
        @"appsList": ^(NSDictionary *msg) { [weakSelf listPressed:msg]; },
        @"appsOpen": ^(NSDictionary *msg) { [weakSelf open:msg]; },
        @"appsPrivacy": ^(NSDictionary *msg) { [weakSelf privacy:msg]; },
    };
}

- (ListedApp *)appFor:(id)appId {
    if (![appId isKindOfClass:NSString.class]) return nil;
    for (ListedApp *listed in self.listed)
        if ([listed.entry.appId isEqualToString:appId]) return listed;
    return nil;
}

// The switch, choice or part of the day with this key on an app's page, of this kind, while it can be pressed: shown,
// and enabled, in a group that's shown and enabled too, if it's in one; nil otherwise.
- (id)pressable:(id)key kind:(Class)kind in:(ListedApp *)app {
    if (!app || ![key isKindOfClass:NSString.class]) return nil;
    BOOL (^can)(id) = ^BOOL(id row) {
        if (![row isKindOfClass:kind]) return NO;
        NSString *its = nil;
        BOOL (^shown)(void) = nil, (^enabled)(void) = nil;
        if ([row isKindOfClass:AppSwitch.class]) {
            AppSwitch *each = row;
            its = each.key, shown = each.shown, enabled = each.enabled;
        } else if ([row isKindOfClass:AppChoice.class]) {
            AppChoice *each = row;
            its = each.key, shown = each.shown, enabled = each.enabled;
        } else if ([row isKindOfClass:AppTime.class]) {
            AppTime *each = row;
            its = each.key, shown = each.shown, enabled = each.enabled;
        }
        return [its isEqualToString:key] && (!shown || shown()) && (!enabled || enabled());
    };
    for (AppSwitch *each in app.switches)
        if (can(each)) return each;
    for (AppGroup *group in app.groups) {
        if ((group.shown && !group.shown()) || (group.enabled && !group.enabled())) continue;
        for (id row in group.rows)
            if (can(row)) return row;
    }
    return nil;
}

// A switch pressed: the module whose switch it is sets it, and the back is told how everything is now, the other
// switches in its group among it. Told even when nothing changed (a press refused, as Show Next Steps' while Apple's
// developer tools aren't in), as the page has already moved the switch and must be put right.
- (void)flip:(NSDictionary *)msg {
    AppSwitch *each = [self pressable:msg[@"key"] kind:AppSwitch.class in:[self appFor:msg[@"app"]]];
    id on = msg[@"on"];
    if (each && [on isKindOfClass:NSNumber.class] && !(each.group && each.on())) each.set([on boolValue]);
    self.told = nil;
    [self tell];
}

// One of an app's choices picked, one that can be picked now and isn't already: its module picks it, and the back is
// told how everything is now, put right if nothing changed.
- (void)choose:(NSDictionary *)msg {
    AppChoice *each = [self pressable:msg[@"key"] kind:AppChoice.class in:[self appFor:msg[@"app"]]];
    id value = msg[@"value"];
    if (each && [value isKindOfClass:NSString.class] && ![value isEqual:each.picked()])
        for (NSDictionary *choice in each.choices())
            if ([choice[@"id"] isEqual:value] && ![choice[@"enabled"] isEqual:@NO]) {
                each.pick(value);
                break;
            }
    self.told = nil;
    [self tell];
}

// One end of a part of the day pressed: a menu of the times it can be, the Mac's own, opened where its time is on the
// back (from the page's top-left corner), with the time it is now ticked and over it, as a pop-up button's menu opens.
- (void)timeMenu:(NSDictionary *)msg {
    ListedApp *app = [self appFor:msg[@"app"]];
    AppTime *time = [self pressable:msg[@"key"] kind:AppTime.class in:app];
    id end = msg[@"end"], x = msg[@"x"], y = msg[@"y"];
    if (!time || !([end isEqual:@"from"] || [end isEqual:@"to"]) || ![x isKindOfClass:NSNumber.class]
        || ![y isKindOfClass:NSNumber.class] || !self.back) return;
    BOOL start = [end isEqual:@"from"];
    NSInteger from = time.from(), to = time.to(), now = start ? from : to;
    NSMenu *menu = [[NSMenu alloc] initWithTitle:time.title];
    menu.autoenablesItems = NO;
    NSMenuItem *current = nil;
    for (NSNumber *minutes in TimesToPick(now, start ? to : from)) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:TimeWords(minutes.integerValue,
                                                                       NSLocale.autoupdatingCurrentLocale)
                                                      action:@selector(pickTime:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = @[app.entry.appId, time.key, start ? minutes : @(from), start ? @(to) : minutes];
        if (minutes.integerValue == now) {
            item.state = NSControlStateValueOn;
            current = item;
        }
        [menu addItem:item];
    }
    NSView *view = self.back.view;
    NSPoint at = NSMakePoint([x doubleValue], view.isFlipped ? [y doubleValue] : NSHeight(view.bounds) - [y doubleValue]);
    [menu popUpMenuPositioningItem:current atLocation:at inView:view];
}

// A time picked from that menu: its module sets the part of the day, if it can still be pressed (it can have been
// turned off meanwhile), and the back is told how it is now.
- (void)pickTime:(NSMenuItem *)item {
    NSArray *picked = item.representedObject;
    AppTime *time = [self pressable:picked[1] kind:AppTime.class in:[self appFor:picked[0]]];
    if (time) time.set([picked[2] integerValue], [picked[3] integerValue]);
    self.told = nil;
    [self tell];
}

// Use the Recommended Settings, at the foot of an app's page: each entry for it that isn't as recommended puts itself
// back, and the back is told how everything is now.
- (void)useRecommended:(NSDictionary *)msg {
    for (AppEntry *entry in [self appFor:msg[@"app"]].entries)
        if (entry.recommended && !entry.recommended() && entry.useRecommended) entry.useRecommended();
    self.told = nil;
    [self tell];
}

// A card's button pressed, one of an app's cards or one of a tool's own card's buttons (Storage's), named by its key:
// the module whose card it is does what it does, and the back is told how things stand, its button waiting while what
// the press set going is under way.
- (void)act:(NSDictionary *)msg {
    ListedApp *app = [self appFor:msg[@"app"]];
    id key = msg[@"key"];
    if (!app || ![key isKindOfClass:NSString.class]) return;
    AppStatus *pressed = nil;
    for (AppStatus *each in app.statuses) {
        if ([each.key isEqualToString:key]) { pressed = each; break; }
    }
    if (pressed.press) pressed.press();
    else if (!pressed && app.entry.act) app.entry.act(key);
    self.told = nil;
    [self tell];
}

// A press on one of an app's lists (its tray's button, an item's, or one under what the last press did), with the ids
// it's for: the module whose list it is does what it does, and the back is told how things stand.
- (void)listPressed:(NSDictionary *)msg {
    ListedApp *app = [self appFor:msg[@"app"]];
    NSString *listKey = AsText(msg[@"list"]), *key = AsText(msg[@"key"]);
    if (!app || !listKey || !key) return;
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    for (id each in AsList(msg[@"ids"])) if (AsText(each)) [ids addObject:each];
    for (AppList *each in app.lists)
        if ([each.key isEqualToString:listKey] && each.press) each.press(key, ids);
    self.told = nil;
    [self tell];
}

// A setting pressed: a switch turned on or off, or a choice picked (only one of its choices that can be picked now),
// by the one whose setting it is; then the back is told how everything is now, told even when nothing changed, as the
// page has already moved it and must be put right.
- (void)setting:(NSDictionary *)msg {
    id key = msg[@"key"], value = msg[@"value"];
    for (SettingEntry *entry in self.settings) {
        if (![key isKindOfClass:NSString.class] || ![entry.key isEqualToString:key]) continue;
        if (!entry.isChoice && !entry.app && [value isKindOfClass:NSNumber.class]) entry.set([value boolValue]);
        if (entry.isChoice && [value isKindOfClass:NSString.class] && ![value isEqual:entry.picked()])
            for (NSDictionary *choice in entry.choices())
                if ([choice[@"id"] isEqual:value] && ![choice[@"enabled"] isEqual:@NO]) entry.pick(value);
        break;
    }
    self.told = nil;
    [self tell];
}

- (void)open:(NSDictionary *)msg {
    AppEntry *app = [self appFor:msg[@"app"]].entry;
    NSURL *url = app ? [self urlOf:app] : nil;
    if (!url) return;
    [NSWorkspace.sharedWorkspace openApplicationAtURL:url configuration:[NSWorkspaceOpenConfiguration configuration]
                                    completionHandler:nil];
}

- (void)privacy:(NSDictionary *)msg {
    AppEntry *app = [self appFor:msg[@"app"]].entry;
    // Full Disk Access's list leaves Whozmove out until macOS has refused it something: that's seen to on the way.
    if (app.permission == AppPermissionFullDiskAccess) return ShowFullDiskAccessSettings();
    NSString *pane = app.permission == AppPermissionAccessibility ? @"Privacy_Accessibility"
                   : app.permission == AppPermissionAutomation ? @"Privacy_Automation" : nil;
    if (pane) OpenLink([@"x-apple.systempreferences:com.apple.preference.security?" stringByAppendingString:pane]);
}

#pragma mark For the tests

// A switch as --print-apps has it: what it says, and the group of switches it's one of, New where it's marked.
static NSDictionary *PrintedSwitch(AppSwitch *each) {
    NSMutableDictionary *printed = [@{@"key": each.key, @"title": each.title, @"help": each.help ?: @"",
                                      @"group": each.group ?: NSNull.null} mutableCopy];
    if (each.isNew) printed[@"isNew"] = @YES;
    return printed;
}

// An app's groups as --print-apps has them, in their order: each heading, line and order, whether it shows or can be
// pressed only sometimes, and its rows, each what it says (a choice its choices too), but not how each is set.
static NSArray *PrintedGroups(NSArray<AppGroup *> *groups) {
    NSMutableArray *out = [NSMutableArray array];
    for (AppGroup *group in groups) {
        NSMutableArray *rows = [NSMutableArray array];
        for (id row in group.rows) {
            if ([row isKindOfClass:AppSwitch.class]) {
                NSMutableDictionary *each = [PrintedSwitch(row) mutableCopy];
                each[@"kind"] = @"switch";
                [rows addObject:each];
            } else if ([row isKindOfClass:AppChoice.class]) {
                AppChoice *each = row;
                [rows addObject:@{@"kind": @"choice", @"key": each.key, @"title": each.title ?: @"",
                                  @"choices": each.choices() ?: @[], @"fixed": each.fixed ?: NSNull.null}];
            } else if ([row isKindOfClass:AppTime.class]) {
                AppTime *each = row;
                [rows addObject:@{@"kind": @"time", @"key": each.key, @"title": each.title, @"help": each.help ?: @""}];
            }
        }
        [out addObject:@{@"title": group.title ?: NSNull.null, @"foot": group.foot ?: NSNull.null,
                         @"order": @(group.order), @"shown": group.shown ? @"sometimes" : @"always",
                         @"enabled": group.enabled ? @"sometimes" : @"always", @"rows": rows}];
    }
    return out;
}

// `Whozmove --print-app-page`: what the panel's back is sent for a made-up tool's page with groups, one a made-up
// module adds to it, and a row in Settings opening it, then what each press makes of it: a choice picked, one that
// can't be, the tool turned off (its own groups dimmed, the other module's not), a time picked from each end's menu,
// and Use the Recommended Settings. The times are written as two places write them, as the Mac's own would differ.
static int PrintAppPage(Core *core) {
    NSMutableDictionary *st = [@{@"on": @YES, @"who": @"any", @"next": @"picks", @"why": @NO, @"quiet": @NO,
                                 @"from": @(22 * 60), @"to": @(8 * 60)} mutableCopy];
    NSDictionary *recommended = [st copy];
    BOOL (^on)(void) = ^BOOL { return [st[@"on"] boolValue]; };
    AppSwitch *(^flag)(NSString *, NSString *, NSString *) = ^AppSwitch *(NSString *key, NSString *title,
                                                                          NSString *help) {
        return [AppSwitch switchWithKey:key title:title help:help on:^BOOL { return [st[key] boolValue]; }
                                    set:^(BOOL value) { st[key] = @(value); }];
    };
    AppChoice *(^choice)(NSString *, NSString *, NSArray *) = ^AppChoice *(NSString *key, NSString *title,
                                                                           NSArray *choices) {
        return [AppChoice choiceWithKey:key title:title choices:^NSArray * { return choices; }
                                 picked:^NSString * { return st[key]; } pick:^(NSString *picked) { st[key] = picked; }];
    };

    AppEntry *tool = [AppEntry appWithId:@"sample-tool" name:@"Sample Tool" does:@"Hands you one thing at a time."
                                   order:200];
    tool.tool = YES;
    tool.present = ^BOOL { return YES; };
    AppGroup *head = [AppGroup groupWithTitle:nil rows:@[flag(@"on", @"Sample Tool", @"The one thing, beside the list.")]
                                         foot:@"Settings ▸ Sample Tool opens this page." order:10];
    AppGroup *who = [AppGroup groupWithTitle:@"Who may send" rows:@[choice(@"who", @"Who may send", @[
        @{@"id": @"any", @"name": @"Any session", @"help": @"Every agent can. Recommended."},
        @{@"id": @"lead", @"name": @"Only a team’s chief", @"help": @"The others are told why.", @"isNew": @YES},
        @{@"id": @"allowed", @"name": @"Only those you’ve allowed", @"help": @"Not yet.", @"enabled": @NO}])]
                                        foot:@"A session that may not is told so." order:20];
    AppChoice *next = choice(@"next", @"What comes first", @[
        @{@"id": @"picks", @"name": @"Then a chief’s picks", @"help": @"In its order."},
        @{@"id": @"oldest", @"name": @"Then the oldest", @"help": @"By how long it has waited."}]);
    next.fixed = @{@"name": @"Urgent ones, always", @"help": @"First, whatever else you choose."};
    AppSwitch *why = flag(@"why", @"Say why each is here", @"A line on why the one in front is first.");
    why.isNew = YES;
    AppGroup *first = [AppGroup groupWithTitle:@"What comes first" rows:@[next, why] foot:nil order:30];
    AppGroup *hidden = [AppGroup groupWithTitle:@"Shown only sometimes" rows:@[flag(@"never", @"Never", @"")] foot:nil
                                          order:40];
    hidden.shown = ^BOOL { return NO; };
    AppGroup *foot = [AppGroup groupWithTitle:nil rows:@[] foot:@"A change applies to what comes next." order:90];
    for (AppGroup *group in @[who, first]) group.enabled = on;
    tool.groups = @[head, who, first, hidden, foot];
    tool.recommended = ^BOOL {
        for (NSString *key in @[@"on", @"who", @"next", @"why"])
            if (![st[key] isEqual:recommended[key]]) return NO;
        return YES;
    };
    tool.useRecommended = ^{
        for (NSString *key in @[@"on", @"who", @"next", @"why"]) st[key] = recommended[key];
    };

    // Another module's group on the tool's page, between its own: a switch, and its times under it, pressable only
    // while it's on; and that module's own say on what's recommended.
    AppTime *hours = [AppTime timeWithKey:@"quietHours" title:@"Night" help:@"Only what's urgent is said."
                                     from:^NSInteger { return [st[@"from"] integerValue]; }
                                       to:^NSInteger { return [st[@"to"] integerValue]; }
                                      set:^(NSInteger from, NSInteger to) {
        if (from == to) return;
        st[@"from"] = @(from);
        st[@"to"] = @(to);
    }];
    hours.enabled = ^BOOL { return [st[@"quiet"] boolValue]; };
    AppEntry *quiet = [AppEntry groups:@[[AppGroup groupWithTitle:@"Quiet hours"
        rows:@[flag(@"quiet", @"Quiet hours", @"At night, only what's urgent."), hours]
        foot:@"The rest waits for the morning." order:25]] forApp:@"sample-tool"];
    quiet.recommended = ^BOOL { return ![st[@"quiet"] boolValue]; };
    quiet.useRecommended = ^{ st[@"quiet"] = @NO; };

    AppsModule *apps = [[AppsModule alloc] initWithCore:core];
    apps.samples = @[tool, quiet];
    SettingEntry *row = [SettingEntry pageWithKey:@"sampleTool" title:@"Sample Tool" app:@"sample-tool"];
    row.said = ^NSString * { return on() ? @"On" : @"Off"; };
    SettingEntry *gone = [SettingEntry pageWithKey:@"gone" title:@"An app not listed" app:@"com.example.gone"];
    apps.sampleSettings = @[row, gone];
    NSDictionary<NSString *, void (^)(NSDictionary *)> *press = apps.messages;
    NSLocale *here = [NSLocale localeWithLocaleIdentifier:@"en_GB"];

    // How the page stands after each press, said shortly: each group's heading and whether it can be pressed, how
    // each of its rows is set, and whether the page is as recommended.
    NSDictionary *page = @{@"groups": [apps shownGroups:[apps appFor:@"sample-tool"] locale:here],
                           @"recommended": @([apps isRecommended:[apps appFor:@"sample-tool"]])};
    NSMutableArray *steps = [NSMutableArray array];
    void (^after)(NSString *) = ^(NSString *what) {
        NSMutableArray *groups = [NSMutableArray array];
        for (NSDictionary *group in [apps shownGroups:[apps appFor:@"sample-tool"] locale:here]) {
            NSMutableArray *rows = [NSMutableArray array];
            for (NSDictionary *each in group[@"rows"]) {
                NSString *set = [each[@"kind"] isEqual:@"switch"] ? ([each[@"on"] boolValue] ? @"on" : @"off")
                              : [each[@"kind"] isEqual:@"choice"] ? each[@"value"]
                              : [NSString stringWithFormat:@"%@ to %@", each[@"fromSaid"], each[@"toSaid"]];
                [rows addObject:[NSString stringWithFormat:@"%@ %@%@", each[@"key"], set,
                                 [each[@"enabled"] boolValue] ? @"" : @" (can't be pressed)"]];
            }
            [groups addObject:[NSString stringWithFormat:@"%@%@: %@", group[@"title"] == NSNull.null ? @"(no heading)"
                               : group[@"title"], [group[@"enabled"] boolValue] ? @"" : @" (dimmed)",
                               rows.count ? [rows componentsJoinedByString:@", "] : @"only its line"]];
        }
        [steps addObject:@{@"after": what, @"groups": groups,
                           @"recommended": @([apps isRecommended:[apps appFor:@"sample-tool"]])}];
    };
    after(@"nothing pressed");
    press[@"appsChoice"](@{@"app": @"sample-tool", @"key": @"who", @"value": @"lead"});
    after(@"Only a team's chief picked");
    press[@"appsChoice"](@{@"app": @"sample-tool", @"key": @"who", @"value": @"allowed"});
    after(@"a choice that can't be picked now: nothing changes");
    press[@"appsChoice"](@{@"app": @"sample-tool", @"key": @"who", @"value": @"everyone"});
    after(@"a choice that isn't one: nothing changes");
    press[@"appsSwitch"](@{@"app": @"sample-tool", @"key": @"on", @"on": @NO});
    after(@"the tool turned off: its own groups dim, the other module's doesn't");
    press[@"appsChoice"](@{@"app": @"sample-tool", @"key": @"next", @"value": @"oldest"});
    press[@"appsSwitch"](@{@"app": @"sample-tool", @"key": @"why", @"on": @YES});
    after(@"a choice and a switch in a dimmed group: nothing changes");
    NSMenuItem *picked = [NSMenuItem new];
    picked.representedObject = @[@"sample-tool", @"quietHours", @(23 * 60), @(8 * 60)];
    [apps pickTime:picked];
    after(@"23:00 picked while quiet hours are off: nothing changes");
    press[@"appsSwitch"](@{@"app": @"sample-tool", @"key": @"quiet", @"on": @YES});
    [apps pickTime:picked];
    after(@"quiet hours on, and 23:00 picked for when they start");
    picked.representedObject = @[@"sample-tool", @"quietHours", @(23 * 60), @(6 * 60 + 30)];
    [apps pickTime:picked];
    after(@"06:30 picked for when they end");
    press[@"appsUseRecommended"](@{@"app": @"sample-tool"});
    after(@"Use the Recommended Settings: every entry for the page puts itself back");

    ListedApp *listed = [apps appFor:@"sample-tool"];
    NSArray *(^menu)(NSInteger, NSInteger) = ^NSArray *(NSInteger now, NSInteger other) {
        NSArray *times = TimesToPick(now, other);
        return @[@(times.count), TimeWords([times.firstObject integerValue], here),
                 TimeWords([times.lastObject integerValue], here),
                 [times containsObject:@(other)] ? @"has the other end's time" : @"leaves out the other end's time",
                 [times containsObject:@(now)] ? @"has the time it is now" : @"hasn't the time it is now"];
    };
    return PrintJSON(@{
        @"the groups, in their order": PrintedGroups(listed.groups),
        @"what the back is sent for the page, before any press": page,
        @"after each press": steps,
        @"Settings' rows": [apps shownSettings],
        @"each end's menu: how many times, the first and the last": @{
            @"from, at 22:00, ending at 08:00": menu(22 * 60, 8 * 60),
            @"to, at 08:00, starting at 22:00": menu(8 * 60, 22 * 60),
            @"from, at 22:15, between the half hours": menu(22 * 60 + 15, 8 * 60)},
        @"a time, as two places write it": @[TimeWords(22 * 60, here),
            TimeWords(22 * 60, [NSLocale localeWithLocaleIdentifier:@"en_US"]),
            TimeWords(0, here), TimeWords(-30, here), TimeWords(kDay + 30, here)],
    });
}

// The apps every module lists for the back, in their order, each with what it says, its permission, its switches and
// its cards, those other modules add among them: whether each is on this Mac, how each switch is set and what each
// card says now are left out, as they depend on the Mac. And Settings' rows, the panel's own and each module's, in
// their order, each with its name, its mark and its place: how each is set, and a choice's choices (the editors on
// this Mac), are left out the same way.
+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return @{@"--print-settings": ^int(Core *core, NSArray<NSString *> *arguments) {
        AppsModule *apps = [[AppsModule alloc] initWithCore:core];
        NSMutableArray *out = [NSMutableArray array];
        for (SettingEntry *entry in apps.settings) {
            NSMutableDictionary *each = [@{@"key": entry.key, @"kind": SettingKind(entry), @"title": entry.title,
                @"glyph": entry.glyph ?: @"", @"group": @(entry.group), @"order": @(entry.order),
                @"page": entry.page ?: NSNull.null, @"style": entry.style ?: NSNull.null} mutableCopy];
            if (entry.app) each[@"app"] = entry.app;
            [out addObject:each];
        }
        return PrintJSON(out);
    }, @"--print-app-page": ^int(Core *core, NSArray<NSString *> *arguments) {
        return PrintAppPage(core);
    }, @"--print-apps": ^int(Core *core, NSArray<NSString *> *arguments) {
        AppsModule *apps = [[AppsModule alloc] initWithCore:core];
        NSMutableArray *out = [NSMutableArray array];
        for (ListedApp *listed in apps.listed) {
            AppEntry *app = listed.entry;
            NSMutableArray *switches = [NSMutableArray array];
            for (AppSwitch *each in listed.switches) [switches addObject:PrintedSwitch(each)];
            NSMutableArray *statuses = [NSMutableArray array];
            for (AppStatus *each in listed.statuses)
                [statuses addObject:@{@"key": each.key, @"title": each.title,
                                      @"section": each.section ?: NSNull.null}];
            NSMutableDictionary *each = [@{@"id": app.appId, @"name": app.name, @"does": app.does ?: @"",
                @"order": @(app.order), @"permission": PermissionKind(app.permission) ?: NSNull.null,
                @"for": app.permissionFor ?: NSNull.null, @"listed": app.present ? @"always" : @"when on this Mac",
                @"tool": @(app.tool), @"card": @((BOOL)(app.card != nil)), @"switches": switches,
                @"statuses": statuses, @"lists": [listed.lists valueForKey:@"title"] ?: @[]} mutableCopy];
            if (listed.groups.count) each[@"groups"] = PrintedGroups(listed.groups);
            [out addObject:each];
        }
        return PrintJSON(out);
    }};
}

@end
