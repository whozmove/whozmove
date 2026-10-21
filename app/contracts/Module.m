// Module: a module's item in the pawn menu, and its apps on the panel's back (the protocol itself is all in Module.h).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Module.h"

@interface MenuEntry ()
@property MenuSection section;
@property NSInteger order;
@property NSMenuItem *item;
@end

@implementation MenuEntry

+ (instancetype)entryIn:(MenuSection)section order:(NSInteger)order item:(NSMenuItem *)item {
    MenuEntry *entry = [self new];
    entry.section = section;
    entry.order = order;
    entry.item = item;
    return entry;
}

@end

@interface AppSwitch ()
@property (copy) NSString *key, *title, *help;
@property (copy) BOOL (^on)(void);
@property (copy) void (^set)(BOOL on);
@end

@implementation AppSwitch

+ (instancetype)switchWithKey:(NSString *)key title:(NSString *)title help:(NSString *)help on:(BOOL (^)(void))on
                          set:(void (^)(BOOL on))set {
    AppSwitch *each = [self new];
    each.key = key;
    each.title = title;
    each.help = help;
    each.on = on;
    each.set = set;
    return each;
}

@end

@interface AppEntry ()
@property (copy) NSString *appId, *name, *does;
@property NSInteger order;
@end

@implementation AppEntry

+ (instancetype)appWithId:(NSString *)appId name:(NSString *)name does:(NSString *)does order:(NSInteger)order {
    AppEntry *entry = [self new];
    entry.appId = appId;
    entry.name = name;
    entry.does = does;
    entry.order = order;
    entry.switches = @[];
    return entry;
}

+ (instancetype)switches:(NSArray<AppSwitch *> *)switches forApp:(NSString *)appId {
    AppEntry *entry = [self new];
    entry.appId = appId;
    entry.switches = switches;
    return entry;
}

@end
