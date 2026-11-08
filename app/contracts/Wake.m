// Wake: what came for a session that waits, and what a source would wake it on (Wake.h).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Wake.h"

@implementation Wake
+ (instancetype)wakeFrom:(NSString *)source kind:(NSString *)kind says:(NSString *)says at:(double)at
                   facts:(NSDictionary *)facts {
    Wake *wake = [self new];
    wake.source = source;
    wake.kind = kind;
    wake.says = says;
    wake.at = at;
    wake.facts = facts;
    return wake;
}
@end

@implementation WaitOn
+ (instancetype)waitOn:(NSDictionary *)on says:(NSString *)says spoken:(NSString *)spoken {
    WaitOn *wait = [self new];
    wait.on = on;
    wait.says = says;
    wait.spoken = spoken;
    return wait;
}
@end
