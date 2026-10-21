// Modules: finding every module, and routing the page's messages to them.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Modules.h"
#import "Core.h"
#import "Log.h"
#import <objc/runtime.h>

// Every class in the app that adopts Module, in order of the modules' names. Only the app's own classes are looked
// at, and asking whether one adopts a protocol doesn't start it up.
static NSArray<Class> *ModuleClasses(void) {
    unsigned int count = 0;
    const char **names = objc_copyClassNamesForImage(class_getImageName(Modules.class), &count);
    NSMutableArray<Class> *found = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        Class cls = objc_getClass(names[i]);
        if (cls && class_conformsToProtocol(cls, @protocol(Module))) [found addObject:cls];
    }
    free(names);
    [found sortUsingComparator:^NSComparisonResult(id a, id b) {
        return [[(Class<Module>)a moduleName] compare:[(Class<Module>)b moduleName]];
    }];
    return found;
}

@interface Modules ()
@property (copy) NSArray<id<Module>> *all;
@property (copy) NSDictionary<NSString *, NSString *> *routes;
@property (copy) NSDictionary<NSString *, void (^)(NSDictionary *)> *handlers;
@property (copy) NSDictionary<NSString *, NSString *> *printModeOwners;
@property (copy) NSDictionary<NSString *, PrintMode> *printModes;
@property (copy) NSArray<NSString *> *clashes;
@end

@implementation Modules

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    NSMutableArray<id<Module>> *all = [NSMutableArray array];
    for (Class cls in ModuleClasses()) [all addObject:[(id<Module>)[cls alloc] initWithCore:core]];
    self.all = all;
    // The core's own messages first, then each module's: a type someone already answers stays theirs.
    NSMutableDictionary *routes = [NSMutableDictionary dictionary], *handlers = [NSMutableDictionary dictionary];
    NSMutableArray *clashes = [NSMutableArray array];
    void (^take)(NSString *, NSDictionary *) = ^(NSString *who, NSDictionary *messages) {
        for (NSString *type in messages) {
            if (routes[type]) {
                [clashes addObject:[NSString stringWithFormat:@"message %@: %@, %@", type, routes[type], who]];
                continue;
            }
            routes[type] = who;
            handlers[type] = messages[type];
        }
    };
    take(@"core", core.messages);
    for (id<Module> module in all)
        if ([module respondsToSelector:@selector(messages)])
            take([(Class<Module>)module.class moduleName], module.messages);
    // Each module's print modes, a flag someone already has staying theirs, as with messages.
    NSMutableDictionary *owners = [NSMutableDictionary dictionary], *modes = [NSMutableDictionary dictionary];
    for (id<Module> module in all) {
        Class<Module> cls = (Class<Module>)module.class;
        if (![cls respondsToSelector:@selector(printModes)]) continue;
        NSDictionary<NSString *, PrintMode> *theirs = [cls printModes];
        for (NSString *flag in theirs) {
            if (owners[flag]) {
                [clashes addObject:[NSString stringWithFormat:@"print mode %@: %@, %@", flag, owners[flag],
                                                             [cls moduleName]]];
                continue;
            }
            owners[flag] = [cls moduleName];
            modes[flag] = theirs[flag];
        }
    }
    self.routes = routes;
    self.handlers = handlers;
    self.printModeOwners = owners;
    self.printModes = modes;
    self.clashes = clashes;
    for (NSString *clash in clashes) LogProblem([@"claimed twice: " stringByAppendingString:clash]);
    return self;
}

- (BOOL)route:(NSString *)type message:(NSDictionary *)message {
    void (^handler)(NSDictionary *) = self.handlers[type];
    if (!handler) return NO;
    handler(message);
    return YES;
}

- (void)launch {
    for (id<Module> module in self.all)
        if ([module respondsToSelector:@selector(launch)]) [module launch];
}

- (void)pageLoaded {
    for (id<Module> module in self.all)
        if ([module respondsToSelector:@selector(pageLoaded)]) [module pageLoaded];
}

- (void)tick {
    for (id<Module> module in self.all)
        if ([module respondsToSelector:@selector(tick)]) [module tick];
}

- (void)rows:(NSArray<Row *> *)rows phase:(RowPhase)phase {
    for (id<Module> module in self.all)
        if ([module respondsToSelector:@selector(rows:phase:)]) [module rows:rows phase:phase];
}

- (BOOL)working {
    for (id<Module> module in self.all)
        if ([module respondsToSelector:@selector(working)] && [module working]) return YES;
    return NO;
}

- (NSArray<MenuEntry *> *)menuEntries {
    NSMutableArray *entries = [NSMutableArray array];
    for (id<Module> module in self.all)
        if ([module respondsToSelector:@selector(menuEntries)]) [entries addObjectsFromArray:module.menuEntries];
    return entries;
}

- (NSArray<AppEntry *> *)appEntries {
    NSMutableArray *entries = [NSMutableArray array];
    for (id<Module> module in self.all)
        if ([module respondsToSelector:@selector(appEntries)]) [entries addObjectsFromArray:module.appEntries];
    return entries;
}

- (PrintMode)printMode:(NSString *)flag {
    return self.printModes[flag];
}

@end
