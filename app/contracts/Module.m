// Module: a module's item in the pawn menu (the protocol itself is all in Module.h).
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
