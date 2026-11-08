// WaitsModule: a session waiting on someone else, and waking it when that comes (WaitsModule.m says how). Its face
// for the core is Module's; what's here is for its print run (WaitsPrints.m), which drives it as the core would.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Module.h"
#import "Wake.h"

@class WaitState;

@interface WaitsModule : NSObject <Module, BackgroundWaits>
@property (weak) Core *core;
// The sources, as the core finds them (modulesThat: WakeSource), the gear, as the usage module keeps it (GearFacts),
// the time (ms since 1970), and the time the Mac has been awake (ms, which stops while it sleeps), unless a print run
// gives its own.
@property (copy) NSArray<id<WakeSource>> *givenSources;
@property (copy) NSDictionary *(^givenGear)(void);
@property (copy) double (^clock)(void);
@property (copy) double (^awakeClock)(void);
// Words said into a session by your press, as Send says them, unless a print run gives its own: `done` gets why they
// couldn't go in, and the button past that, or nil once they're in.
@property (copy) void (^givenSay)(NSString *words, Row *row, void (^done)(NSString *why, NSString *way));
// Each waiting session's wait, by its id.
@property (strong, readonly) NSMutableDictionary<NSString *, WaitState *> *waits;
// Waits are kept in this folder (AppDir/waits as it launches), and what's there is read, so a restart finds them.
- (void)keepIn:(NSString *)folder;
// What a session's wait command asks (`wait`, with {now, comments}), answered as the core would.
- (NSString *)wait:(NSDictionary *)asked from:(Row *)row;
// Your press of Resume on a row whose conversation runs again but hasn't asked (the page's `waitSay`).
- (void)sayResume:(NSString *)sessionId;
// What it does with the rows each second: ends the waits that are over, watches again after a restart, and finds what
// came and which wakes go with the gear as it is. Nothing before the rows have been read once (nil).
- (void)pass:(NSArray<Row *> *)rows;
@end

// Its print modes, for the tests (WaitsPrints.m).
NSDictionary<NSString *, PrintMode> *WaitsPrintModes(void);
