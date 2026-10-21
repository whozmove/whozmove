// Modules: every module in the app, found at launch, and the page's messages routed to the one that answers each.
// A module is any class that adopts Module (contracts/Module.h): this asks the Objective-C runtime for each such class
// in the app and makes them in order of their names, so no file lists them.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Module.h"

@interface Modules : NSObject
- (instancetype)initWithCore:(Core *)core;
@property (readonly) NSArray<id<Module>> *all;
// A message from the page, to the core or the one module that answers its type. NO if none does.
- (BOOL)route:(NSString *)type message:(NSDictionary *)message;
// Each type, and who answers it ("core", or a module's name).
@property (readonly) NSDictionary<NSString *, NSString *> *routes;
// Each print mode's flag, and the module that has it.
@property (readonly) NSDictionary<NSString *, NSString *> *printModeOwners;
// Each message type, or print mode, more than one module claims, as "message type: first, second" or "print mode
// --print-x: first, second". The first by name keeps it; the tests fail on any.
@property (readonly) NSArray<NSString *> *clashes;
// Passed on to every module that has them.
- (void)launch;
- (void)pageLoaded;
- (void)tick;
- (void)rows:(NSArray<Row *> *)rows phase:(RowPhase)phase;
- (NSArray<MenuEntry *> *)menuEntries;
- (NSArray<AppEntry *> *)appEntries;
// Whether any module is still working something out (Module's working).
- (BOOL)working;
// The print mode with this flag, from the module that has it, or nil.
- (PrintMode)printMode:(NSString *)flag;
@end
