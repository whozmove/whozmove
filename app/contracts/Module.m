// Module: a module's item in the pawn menu, its apps and settings on the panel's back, and what a session may do
// once you allow it (the protocol itself is all in Module.h).
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

@interface AppChoice ()
@property (copy) NSString *key, *title;
@property (copy) NSArray<NSDictionary *> *(^choices)(void);
@property (copy) NSString *(^picked)(void);
@property (copy) void (^pick)(NSString *choice);
@end

@implementation AppChoice

+ (instancetype)choiceWithKey:(NSString *)key title:(NSString *)title choices:(NSArray<NSDictionary *> *(^)(void))choices
                       picked:(NSString *(^)(void))picked pick:(void (^)(NSString *choice))pick {
    AppChoice *each = [self new];
    each.key = key;
    each.title = title;
    each.choices = choices;
    each.picked = picked;
    each.pick = pick;
    return each;
}

@end

@interface AppTime ()
@property (copy) NSString *key, *title, *help;
@property (copy) NSInteger (^from)(void);
@property (copy) NSInteger (^to)(void);
@property (copy) void (^set)(NSInteger from, NSInteger to);
@end

@implementation AppTime

+ (instancetype)timeWithKey:(NSString *)key title:(NSString *)title help:(NSString *)help from:(NSInteger (^)(void))from
                         to:(NSInteger (^)(void))to set:(void (^)(NSInteger from, NSInteger to))set {
    AppTime *each = [self new];
    each.key = key;
    each.title = title;
    each.help = help;
    each.from = from;
    each.to = to;
    each.set = set;
    return each;
}

@end

@interface AppPage ()
@property (copy) NSString *key, *title;
@property (copy) NSArray<AppGroup *> *(^groups)(void);
@end

@implementation AppPage

+ (instancetype)pageWithKey:(NSString *)key title:(NSString *)title groups:(NSArray<AppGroup *> *(^)(void))groups {
    AppPage *page = [self new];
    page.key = key;
    page.title = title;
    page.groups = groups;
    return page;
}

@end

@interface AppGroup ()
@property (copy) NSString *title, *foot;
@property (copy) NSArray *rows;
@property NSInteger order;
@end

@implementation AppGroup

+ (instancetype)groupWithTitle:(NSString *)title rows:(NSArray *)rows foot:(NSString *)foot order:(NSInteger)order {
    AppGroup *group = [self new];
    group.title = title;
    group.rows = rows ?: @[];
    group.foot = foot;
    group.order = order;
    return group;
}

@end

@interface AppStatus ()
@property (copy) NSString *key, *title;
@property (copy) NSDictionary *(^now)(void);
@property (copy) void (^press)(void);
@end

@implementation AppStatus

+ (instancetype)statusWithKey:(NSString *)key title:(NSString *)title now:(NSDictionary *(^)(void))now
                        press:(void (^)(void))press {
    AppStatus *each = [self new];
    each.key = key;
    each.title = title;
    each.now = now;
    each.press = press;
    return each;
}

@end

@interface AppList ()
@property (copy) NSString *key, *title;
@property (copy) NSDictionary *(^now)(void);
@property (copy) void (^press)(NSString *key, NSArray<NSString *> *ids);
@end

@implementation AppList

+ (instancetype)listWithKey:(NSString *)key title:(NSString *)title now:(NSDictionary *(^)(void))now
                      press:(void (^)(NSString *key, NSArray<NSString *> *ids))press {
    AppList *each = [self new];
    each.key = key;
    each.title = title;
    each.now = now;
    each.press = press;
    return each;
}

@end

@interface SettingEntry ()
@property (copy) NSString *key, *title, *glyph;
@property BOOL isChoice;
@property (copy) NSString *app;
@property (copy) BOOL (^on)(void);
@property (copy) void (^set)(BOOL on);
@property (copy) NSArray<NSDictionary *> *(^choices)(void);
@property (copy) NSString *(^picked)(void);
@property (copy) void (^pick)(NSString *choice);
@end

@implementation SettingEntry

+ (instancetype)switchWithKey:(NSString *)key title:(NSString *)title glyph:(NSString *)glyph on:(BOOL (^)(void))on
                          set:(void (^)(BOOL on))set {
    SettingEntry *entry = [self new];
    entry.key = key;
    entry.title = title;
    entry.glyph = glyph;
    entry.on = on;
    entry.set = set;
    return entry;
}

+ (instancetype)choiceWithKey:(NSString *)key title:(NSString *)title glyph:(NSString *)glyph
                      choices:(NSArray<NSDictionary *> *(^)(void))choices picked:(NSString *(^)(void))picked
                         pick:(void (^)(NSString *choice))pick {
    SettingEntry *entry = [self new];
    entry.key = key;
    entry.title = title;
    entry.glyph = glyph;
    entry.isChoice = YES;
    entry.choices = choices;
    entry.picked = picked;
    entry.pick = pick;
    return entry;
}

+ (instancetype)pageWithKey:(NSString *)key title:(NSString *)title app:(NSString *)appId {
    SettingEntry *entry = [self new];
    entry.key = key;
    entry.title = title;
    entry.app = appId;
    return entry;
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
    entry.groups = @[];
    entry.statuses = @[];
    entry.lists = @[];
    return entry;
}

+ (instancetype)switches:(NSArray<AppSwitch *> *)switches forApp:(NSString *)appId {
    AppEntry *entry = [self new];
    entry.appId = appId;
    entry.switches = switches;
    entry.groups = @[];
    entry.statuses = @[];
    return entry;
}

+ (instancetype)groups:(NSArray<AppGroup *> *)groups forApp:(NSString *)appId {
    AppEntry *entry = [self new];
    entry.appId = appId;
    entry.switches = @[];
    entry.groups = groups;
    entry.statuses = @[];
    entry.lists = @[];
    return entry;
}

+ (instancetype)statuses:(NSArray<AppStatus *> *)statuses forApp:(NSString *)appId {
    AppEntry *entry = [self new];
    entry.appId = appId;
    entry.switches = @[];
    entry.groups = @[];
    entry.statuses = statuses;
    entry.lists = @[];
    return entry;
}

+ (instancetype)lists:(NSArray<AppList *> *)lists forApp:(NSString *)appId {
    AppEntry *entry = [self new];
    entry.appId = appId;
    entry.switches = @[];
    entry.statuses = @[];
    entry.lists = lists;
    return entry;
}

@end

@interface SessionSwitch ()
@property (copy) NSString *key, *title, *line;
@property SwitchLasts lasts;
@end

@implementation SessionSwitch

+ (instancetype)switchWithKey:(NSString *)key title:(NSString *)title line:(NSString *)line lasts:(SwitchLasts)lasts {
    SessionSwitch *each = [self new];
    each.key = key;
    each.title = title;
    each.line = line;
    each.lasts = lasts;
    return each;
}

@end

@interface SessionAsk ()
@property (copy) NSArray<NSString *> *switchKeys;
@property BOOL showsOnly;
@property (copy) NSString *(^answer)(Row *row, pid_t process, NSDictionary *asked);
@end

@implementation SessionAsk

+ (instancetype)askNeeding:(NSString *)switchKey
                    answer:(NSString *(^)(Row *row, pid_t process, NSDictionary *asked))answer {
    return [self askNeedingAny:@[switchKey] answer:answer];
}

+ (instancetype)askNeedingAny:(NSArray<NSString *> *)switchKeys
                       answer:(NSString *(^)(Row *row, pid_t process, NSDictionary *asked))answer {
    SessionAsk *ask = [self new];
    ask.switchKeys = switchKeys;
    ask.answer = answer;
    return ask;
}

+ (instancetype)askShowing:(NSString *(^)(Row *row, pid_t process, NSDictionary *asked))answer {
    SessionAsk *ask = [self askNeedingAny:@[] answer:answer];
    ask.showsOnly = YES;
    return ask;
}

@end
