// Module: what each module fills in for the core. A module is a class that adopts it; the core finds every one itself
// at launch (Modules), so nothing lists them. Only the name and setting up are needed: a module fills in what it has.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>

@class Core, Row;

// The phases each read of the rows goes through on the main thread, in this order, once the sessions have been read on
// their queue (Rows, in the core). Each module adds its part of every row in the phase it belongs to.
typedef NS_ENUM(NSInteger, RowPhase) {
    RowPhaseCheckout,  // the state of the checkout each row is about (what its island shows)
    RowPhaseWork,      // each session's work: its PRs, writings, changes, compacting, picks not confirmed yet
    RowPhaseDetails,   // its agent's details: model, effort, mode, context
    RowPhaseListed,    // the rows are whole: what's kept by session, sent apart from them, or watched for
};

// Where in the pawn menu an item of a module's goes.
typedef NS_ENUM(NSInteger, MenuSection) {
    MenuSectionTop,       // above Show / Hide Panel
    MenuSectionFeatures,  // after the grouping, as Next Steps ▸, Spotify ▸ and Open With ▸ are
    MenuSectionWhozmove,  // in Working on Whozmove ▸, which shows only while ⌥ is held as the menu opens
};

// One of a module's items in the pawn menu, and where it goes: its section, and its order there (lower first).
@interface MenuEntry : NSObject
+ (instancetype)entryIn:(MenuSection)section order:(NSInteger)order item:(NSMenuItem *)item;
@property (readonly) MenuSection section;
@property (readonly) NSInteger order;
@property (readonly) NSMenuItem *item;
// Run each time the menu opens, for a title that changes or an item that shows only sometimes.
@property (copy) void (^willOpen)(void);
@end

// What a print run (for the tests) prints from its arguments, those after its flag; its result is the exit status.
typedef int (^PrintMode)(Core *core, NSArray<NSString *> *arguments);

@protocol Module <NSObject>
// Its name, as the routing table and the tests show it.
+ (NSString *)moduleName;
// Made once, with the core's services. Only data is set up here, as a print run makes every module too.
- (instancetype)initWithCore:(Core *)core;
@optional
// The app has started: windows, observers, timers and shortcuts start here, never in a print run.
- (void)launch;
// The page has loaded, at the start or again: it's told what the module knows.
- (void)pageLoaded;
// Each time the rows are read, once a second and whenever one has something new, before they're read: for what a
// module checks that often.
- (void)tick;
// Its part of the rows, in one of the phases each read goes through (RowPhase), on the main thread.
- (void)rows:(NSArray<Row *> *)rows phase:(RowPhase)phase;
// Whether it's still working out something that will show in the rows, off the main thread (a read, a count): a print
// run waits until nothing is.
- (BOOL)working;
// The page's messages the module answers, by type. Each type has one module.
- (NSDictionary<NSString *, void (^)(NSDictionary *message)> *)messages;
// Its items in the pawn menu.
- (NSArray<MenuEntry *> *)menuEntries;
// Its print modes, by flag ("--print-spotify"), for the tests.
+ (NSDictionary<NSString *, PrintMode> *)printModes;
@end
