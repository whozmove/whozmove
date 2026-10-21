// ITerm2Settings: iTerm2's own Settings window, through the Accessibility API. Each step waits for what the one before
// pressed to show, a few seconds at most, as iTerm2 lays its Settings out as they open, and as a pane or a tab is
// chosen.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "ITerm2Settings.h"
#import "ITerm2Facts.h"
#import "Accessibility.h"

// How long a step waits for what it pressed to show, and how often it looks meanwhile; and how long the box's press
// waits for iTerm2, which holds it while it asks you.
static const NSTimeInterval kShowsWithin = 3, kLookEvery = 0.1, kBoxWaits = 0.5;

BOOL ITerm2APIOn(void) {
    CFStringRef app = (__bridge CFStringRef)kITerm2AppId;
    CFPreferencesAppSynchronize(app);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)kITerm2APISetting, app));
    return [value respondsToSelector:@selector(boolValue)] && [value boolValue];
}

// The first element from `root` down of one of `roles` that's called `label` on screen, or nil.
static id Named(AXUIElementRef root, NSArray<NSString *> *roles, NSString *label) {
    NSMutableArray *found = [NSMutableArray array];
    CollectElements(root, 0, ^BOOL(AXUIElementRef el) {
        return !found.count && [roles containsObject:ElementText(el, kAXRoleAttribute) ?: @""]
            && [ElementLabel(el) isEqualToString:label];
    }, found);
    return found.firstObject;
}

static BOOL Press(id element) {
    return AXUIElementPerformAction((__bridge AXUIElementRef)element, kAXPressAction) == kAXErrorSuccess;
}

// What `find` finds, once it shows, kShowsWithin at most.
static id Waiting(id (^find)(void)) {
    id found = find();
    for (NSTimeInterval waited = 0; !found && waited < kShowsWithin; waited += kLookEvery) {
        [NSThread sleepForTimeInterval:kLookEvery];
        found = find();
    }
    return found;
}

// What a pane's button and a tab are, as the Accessibility API gives them.
static NSArray<NSString *> *Choices(void) {
    return @[@"AXButton", @"AXRadioButton", @"AXTab"];
}

// Its Settings window, if it's open: the one whose toolbar has both General and Profiles.
static id SettingsWindow(AXUIElementRef app) {
    CFTypeRef windows = NULL;
    AXUIElementCopyAttributeValue(app, kAXWindowsAttribute, &windows);
    for (id window in (__bridge_transfer NSArray *)windows) {
        AXUIElementRef el = (__bridge AXUIElementRef)window;
        if (Named(el, Choices(), kITerm2GeneralPane) && Named(el, Choices(), kITerm2ProfilesPane)) return window;
    }
    return nil;
}

// The app menu's item that opens its Settings.
static id SettingsItem(AXUIElementRef app) {
    CFTypeRef bar = NULL;
    if (AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute, &bar) != kAXErrorSuccess || !bar) return nil;
    NSArray *names = [NSArray arrayWithObjects:kITerm2SettingsItems
                                         count:sizeof(kITerm2SettingsItems) / sizeof(*kITerm2SettingsItems)];
    NSMutableArray *found = [NSMutableArray array];
    CollectElements(bar, 0, ^BOOL(AXUIElementRef el) {
        return !found.count && [ElementText(el, kAXRoleAttribute) isEqual:@"AXMenuItem"]
            && [names containsObject:ElementLabel(el) ?: @""];
    }, found);
    CFRelease(bar);
    return found.firstObject;
}

NSString *ITerm2SetAPI(pid_t pid, BOOL on, BOOL *already) {
    *already = NO;
    AXUIElementRef app = AXUIElementCreateApplication(pid);
    if (!app) return @"iTerm2";
    AXUIElementSetMessagingTimeout(app, 2);
    id window = SettingsWindow(app);
    if (!window) {
        id item = SettingsItem(app);
        if (item && Press(item)) window = Waiting(^id { return SettingsWindow(app); });
    }
    CFRelease(app);
    if (!window) return @"its Settings";
    AXUIElementRef settings = (__bridge AXUIElementRef)window;
    id general = Named(settings, Choices(), kITerm2GeneralPane);
    if (!general || !Press(general)) return @"General in its Settings";
    id magic = Waiting(^id { return Named(settings, Choices(), kITerm2MagicTab); });
    if (!magic || !Press(magic)) return @"Magic in its General settings";
    id box = Waiting(^id { return Named(settings, @[@"AXCheckBox"], kITerm2APIBox); });
    if (!box) return @"Enable Python API in its Magic settings";
    CFTypeRef value = NULL;
    AXUIElementCopyAttributeValue((__bridge AXUIElementRef)box, kAXValueAttribute, &value);
    id ticked = CFBridgingRelease(value);
    if ([ticked respondsToSelector:@selector(boolValue)] && [ticked boolValue] == on) {
        *already = YES;
        return nil;
    }
    // iTerm2 holds the press while it asks you, so the press may wait out its time: it has gone in all the same.
    AXUIElementSetMessagingTimeout((__bridge AXUIElementRef)box, kBoxWaits);
    AXError pressed = AXUIElementPerformAction((__bridge AXUIElementRef)box, kAXPressAction);
    return pressed == kAXErrorSuccess || pressed == kAXErrorCannotComplete ? nil : @"a way to press Enable Python API";
}
