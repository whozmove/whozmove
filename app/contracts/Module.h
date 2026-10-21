// Module: what each module fills in for the core. A module is a class that adopts it; the core finds every one itself
// at launch (Modules), so nothing lists them. Only the name and setting up are needed: a module fills in what it has.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>

@class Core, Row;

// The phases each read of the rows goes through on the main thread, in this order, once the sessions have been read on
// their queue (Rows, in the core). Each module adds its part of every row in the phase it belongs to.
typedef NS_ENUM(NSInteger, RowPhase) {
    RowPhaseCheckout,  // the state of the checkout each row is about (what its next steps go by)
    RowPhaseWork,      // each session's work: its PRs, writings, changes, compacting, picks not confirmed yet
    RowPhaseDetails,   // its agent's details: model, effort, mode, context
    RowPhaseListed,    // the rows are whole: what's kept by session, sent apart from them, or watched for
};

// Where in the pawn menu an item of a module's goes.
typedef NS_ENUM(NSInteger, MenuSection) {
    MenuSectionTop,       // above Show / Hide Panel
    MenuSectionFeatures,  // after the grouping, as Open With ▸ is
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

// What macOS has to let Whozmove do for it to work with an app, which the app's page on the panel's back shows.
typedef NS_ENUM(NSInteger, AppPermission) {
    AppPermissionNone,           // nothing to allow
    AppPermissionAccessibility,  // Privacy & Security ▸ Accessibility: its windows read, and its buttons pressed
    AppPermissionAutomation,     // Privacy & Security ▸ Automation: asked things, and told what to do
};

// One of the switches on an app's page on the panel's back: its name, a line on what it does, whether it's on now, and
// what turning it on or off does. Switches in a group are a choice of one among apps (the terminal new conversations
// open in): pressed, it's the one, and the others in its group go off; pressed again, it stays.
@interface AppSwitch : NSObject
+ (instancetype)switchWithKey:(NSString *)key title:(NSString *)title help:(NSString *)help on:(BOOL (^)(void))on
                          set:(void (^)(BOOL on))set;
@property (readonly, copy) NSString *key, *title, *help;
@property (readonly, copy) BOOL (^on)(void);
@property (readonly, copy) void (^set)(BOOL on);
// Shown only while `shown` says so (Lyrics, while the song shows), and pressable only while `enabled` does (Show Next
// Steps, while Apple's developer tools are in); nil for always.
@property (copy) BOOL (^shown)(void);
@property (copy) BOOL (^enabled)(void);
@property (copy) NSString *group;
@end

// One of the cards on an app's page on the panel's back, under its switches: how something Whozmove needs there stands
// (Apple's command line developer tools, on Git's page), with a button for what you can do about it. Its heading is
// fixed; `now`, read as the back is drawn, says the rest: {said, note, ok, button, busy}, where said is a word or two
// on its right ("Installed"), note a line under its heading, ok whether all's well (its tick), button its button's
// title, if it has one now, and busy whether what a press set going is still under way (the button waits meanwhile);
// or nil while it has nothing to say, which leaves the card out. A press runs `press`.
@interface AppStatus : NSObject
+ (instancetype)statusWithKey:(NSString *)key title:(NSString *)title now:(NSDictionary *(^)(void))now
                        press:(void (^)(void))press;
@property (readonly, copy) NSString *key, *title;
@property (readonly, copy) NSDictionary *(^now)(void);
@property (readonly, copy) void (^press)(void);
// The heading over its card, where it needs telling apart from the switches above it ("Developer tools"); nil for none.
@property (copy) NSString *section;
@end

// One of the apps a module works with, as the panel's back lists it (the apps module): its id (the app's bundle id, or
// a name of Whozmove's own for a tool that isn't an app, as git), its name, a line on what Whozmove does with it, its
// place among the others (lower first), what macOS has to allow, its switches and its cards. An entry made with only an
// app's id and switches or cards adds them to the app another module lists: starts adds "Open new conversations here"
// to each terminal, and install the developer tools' card to Git's page.
@interface AppEntry : NSObject
+ (instancetype)appWithId:(NSString *)appId name:(NSString *)name does:(NSString *)does order:(NSInteger)order;
+ (instancetype)switches:(NSArray<AppSwitch *> *)switches forApp:(NSString *)appId;
+ (instancetype)statuses:(NSArray<AppStatus *> *)statuses forApp:(NSString *)appId;
@property (readonly, copy) NSString *appId, *name, *does;
@property (readonly) NSInteger order;
@property AppPermission permission;
// What it needs that permission for, in a few words: "Finds each session's tab, and types into it".
@property (copy) NSString *permissionFor;
@property (copy) NSArray<AppSwitch *> *switches;
@property (copy) NSArray<AppStatus *> *statuses;
// Whether it's listed, for a tool that isn't an app (git) or an app listed whether it's installed or not (Spotify,
// whose token offers to get it); nil for an app listed while macOS finds it by its id.
@property (copy) BOOL (^present)(void);
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
// The apps it works with, as the panel's back lists them, and the switches it adds to other modules' apps.
- (NSArray<AppEntry *> *)appEntries;
// Its print modes, by flag ("--print-spotify"), for the tests.
+ (NSDictionary<NSString *, PrintMode> *)printModes;
@end
