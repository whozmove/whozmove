// AppsModule: the panel's back, which the header's four squares turn the panel over to: the apps Whozmove works with,
// each module's, and on each one's page what Whozmove does with it, its switches and what macOS lets Whozmove do with
// it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#import "Module.h"
#import "Core.h"
#import "Modules.h"
#import "PanelWindow.h"
#import "Page.h"
#import "Printing.h"
#import "AppleEvents.h"
#import "Links.h"
#import "Log.h"
#import "BackPage.h"

// While the panel is turned over, what macOS lets Whozmove do with each app is looked at again this often, in ticks
// (one a second), as it's changed in System Settings, not here.
static const NSInteger kCheckEvery = 3;
// The size each app's icon is taken at, in pixels: twice the largest it's shown at on the back.
static const CGFloat kIconPixels = 96;
// How long where an app is on this Mac is taken as known, in seconds, as apps are installed and removed meanwhile (the
// core takes its own look as long).
static const NSTimeInterval kKnownFor = 30;

static NSString *PermissionKind(AppPermission permission) {
    return permission == AppPermissionAccessibility ? @"accessibility"
         : permission == AppPermissionAutomation ? @"automation" : nil;
}

// One app as the back lists it: its module's entry, and its switches, with those other modules add to it.
@interface ListedApp : NSObject
@property (strong) AppEntry *entry;
@property (copy) NSArray<AppSwitch *> *switches;
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
}

- (void)tick {
    if (!self.core.window.turned || ++self.ticks % kCheckEvery) return;
    [self tell];
    [self check];
}

#pragma mark The apps

// Every module's apps, in their order, each with its switches and those other modules add to it.
- (NSArray<ListedApp *> *)listed {
    NSMutableArray<AppEntry *> *apps = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray<AppSwitch *> *> *added = [NSMutableDictionary dictionary];
    for (AppEntry *entry in self.core.modules.appEntries) {
        if (entry.name) [apps addObject:entry];
        else if (entry.appId) {
            if (!added[entry.appId]) added[entry.appId] = [NSMutableArray array];
            [added[entry.appId] addObjectsFromArray:entry.switches ?: @[]];
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
        each.switches = [app.switches ?: @[] arrayByAddingObjectsFromArray:added[app.appId] ?: @[]];
        [listed addObject:each];
    }
    return listed;
}

- (BOOL)isOnThisMac:(AppEntry *)app {
    if (app.present) return app.present();
    return [self urlOf:app] != nil;
}

// Where the app is on this Mac, or nil: for a tool that isn't an app (git), or one that isn't installed (Spotify). Asked
// of macOS again once kKnownFor has passed.
- (NSURL *)urlOf:(AppEntry *)app {
    NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
    NSArray *known = self.urls[app.appId];
    if (known && now - [known[1] doubleValue] < kKnownFor) return known[0] == NSNull.null ? nil : known[0];
    NSURL *url = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:app.appId];
    self.urls[app.appId] = @[url ?: NSNull.null, @(now)];
    return url;
}

// What the back shows of each app on this Mac: its name, what Whozmove does with it, its icon, whether it opens, its
// switches showing now, and its permission, as last checked.
- (NSArray<NSDictionary *> *)shown {
    NSMutableArray *out = [NSMutableArray array];
    for (ListedApp *listed in self.listed) {
        AppEntry *app = listed.entry;
        if (![self isOnThisMac:app]) continue;
        NSMutableArray *switches = [NSMutableArray array];
        for (AppSwitch *each in listed.switches) {
            if (each.shown && !each.shown()) continue;
            [switches addObject:@{@"key": each.key, @"title": each.title, @"help": each.help ?: @"",
                                  @"on": @(each.on()), @"enabled": @(each.enabled ? each.enabled() : YES),
                                  @"group": each.group ?: NSNull.null}];
        }
        // What macOS lets Whozmove do with it only once it's installed: there's nothing to allow before.
        NSString *kind = [self urlOf:app] ? PermissionKind(app.permission) : nil;
        NSDictionary *permission = kind ? @{@"kind": kind, @"use": app.permissionFor ?: @"",
                                            @"state": [self permissionOf:app] ?: @"unknown"} : nil;
        [out addObject:@{@"id": app.appId, @"name": app.name, @"does": app.does ?: @"",
                         @"icon": [self iconOf:app] ?: NSNull.null, @"open": @([self urlOf:app] != nil),
                         @"switches": switches, @"permission": permission ?: NSNull.null}];
    }
    return out;
}

// Told only once what it shows has changed.
- (void)tell {
    if (!self.back) return;
    NSArray *apps = self.shown;
    NSString *look = self.core.window.look ?: @"grey";
    NSData *json = [NSJSONSerialization dataWithJSONObject:@[apps, look] options:0 error:nil];
    NSString *told = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : nil;
    if (!told || [told isEqualToString:self.told]) return;
    self.told = told;
    [self.back call:@"setApps" with:@[apps, look]];
}

// An app's own icon, at the back's sizes, as a data: address; nil without one, looked for again as the app is (an app
// installed since shows its own then).
- (NSString *)iconOf:(AppEntry *)app {
    NSString *known = self.icons[app.appId];
    if (known) return known;
    NSURL *url = [self urlOf:app];
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
    if (icon) self.icons[app.appId] = icon;
    return icon;
}

#pragma mark What macOS lets Whozmove do

// How an app's permission stands: Accessibility is asked of macOS here, quietly; Automation as it was last checked
// (check), as macOS can take a moment to say.
- (NSString *)permissionOf:(AppEntry *)app {
    if (app.permission == AppPermissionAccessibility) return AXIsProcessTrusted() ? @"allowed" : @"denied";
    if (app.permission == AppPermissionAutomation) return self.automation[app.appId];
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

// The back's presses: turning back to the list, or back and then folding into the cat; a switch; Open; and System
// Settings, at the pane where the app's permission is changed.
- (NSDictionary<NSString *, void (^)(NSDictionary *)> *)messages {
    __weak typeof(self) weakSelf = self;
    return @{
        @"appsTurnBack": ^(NSDictionary *msg) { [weakSelf.core.window turnOver:NO then:nil]; },
        @"appsFold": ^(NSDictionary *msg) {
            [weakSelf.core.window turnOver:NO then:^{ [weakSelf.core.page toggleCollapsed]; }];
        },
        @"appsSwitch": ^(NSDictionary *msg) { [weakSelf flip:msg]; },
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

// A switch pressed: the module whose switch it is sets it, and the back is told how everything is now, the other
// switches in its group among it. Told even when nothing changed (a press refused, as Show Deploy's while the next
// steps are off), as the page has already moved the switch and must be put right.
- (void)flip:(NSDictionary *)msg {
    ListedApp *app = [self appFor:msg[@"app"]];
    id key = msg[@"key"], on = msg[@"on"];
    if (!app || ![key isKindOfClass:NSString.class] || ![on isKindOfClass:NSNumber.class]) return;
    for (AppSwitch *each in app.switches) {
        if (![each.key isEqualToString:key]) continue;
        if ((each.shown && !each.shown()) || (each.enabled && !each.enabled())) break;
        if (!(each.group && each.on())) each.set([on boolValue]);
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
    NSString *pane = app.permission == AppPermissionAccessibility ? @"Privacy_Accessibility"
                   : app.permission == AppPermissionAutomation ? @"Privacy_Automation" : nil;
    if (pane) OpenLink([@"x-apple.systempreferences:com.apple.preference.security?" stringByAppendingString:pane]);
}

#pragma mark For the tests

// The apps every module lists for the back, in their order, each with what it says, its permission and its switches,
// those other modules add among them: whether each is on this Mac, and how each switch is set, are left out, as they
// depend on the Mac.
+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return @{@"--print-apps": ^int(Core *core, NSArray<NSString *> *arguments) {
        AppsModule *apps = [[AppsModule alloc] initWithCore:core];
        NSMutableArray *out = [NSMutableArray array];
        for (ListedApp *listed in apps.listed) {
            AppEntry *app = listed.entry;
            NSMutableArray *switches = [NSMutableArray array];
            for (AppSwitch *each in listed.switches)
                [switches addObject:@{@"key": each.key, @"title": each.title, @"help": each.help ?: @"",
                                      @"group": each.group ?: NSNull.null}];
            [out addObject:@{@"id": app.appId, @"name": app.name, @"does": app.does ?: @"", @"order": @(app.order),
                             @"permission": PermissionKind(app.permission) ?: NSNull.null,
                             @"for": app.permissionFor ?: NSNull.null,
                             @"listed": app.present ? @"always" : @"when on this Mac",
                             @"switches": switches}];
        }
        return PrintJSON(out);
    }};
}

@end
