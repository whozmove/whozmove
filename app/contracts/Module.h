// Module: what each module fills in for the core. A module is a class that adopts it; the core finds every one itself
// at launch (Modules), so nothing lists them. Only the name and setting up are needed: a module fills in what it has.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>

@class Core, Notice, Row;

// The phases each read of the rows goes through on the main thread, in this order, once the sessions have been read on
// their queue (Rows, the list part's). Each module adds its part of every row in the phase it belongs to.
typedef NS_ENUM(NSInteger, RowPhase) {
    RowPhaseCheckout,  // the state of the checkout each row is about (what its next steps go by)
    RowPhaseWork,      // each session's work: its PRs, writings, changes, compacting, picks not confirmed yet
    RowPhaseDetails,   // its agent's details: model, effort, mode, context
    RowPhaseListed,    // the rows are whole: what's kept by session, sent apart from them, or watched for
};

// Where in the pawn menu an item of a module's goes.
typedef NS_ENUM(NSInteger, MenuSection) {
    MenuSectionTop,       // above Show / Hide Panel
    MenuSectionFeatures,  // after the panel's own items
    MenuSectionWhozmove,  // in Working on Whozmove ▸, which shows only while ⌥ is held as the menu opens
    MenuSectionApp,       // at the end, just above Quit Whozmove: Whozmove itself, as Open at Login
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
    AppPermissionFullDiskAccess, // Privacy & Security ▸ Full Disk Access: what macOS keeps from apps, read
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
// New after its title, for one that works differently from before (One Task's Say Why Each Is Here).
@property BOOL isNew;
@end

// A choice of one among a few, in one of the groups on an app's page (AppGroup): who may hand you tasks, on One Task's.
// Each choice is a row with its name over a line on what it does, and a tick on the one picked, as a choice on one of
// Settings' pages is. The choices are {id, name, help}, with `isNew` YES for one that's new and `enabled` NO for one that
// can't be picked now; `picked` is the id of the one picked, and `pick` what picking another does. Its title isn't
// drawn, as its group's heading says it: it names the choices to VoiceOver and the tests.
@interface AppChoice : NSObject
+ (instancetype)choiceWithKey:(NSString *)key title:(NSString *)title choices:(NSArray<NSDictionary *> *(^)(void))choices
                       picked:(NSString *(^)(void))picked pick:(void (^)(NSString *choice))pick;
@property (readonly, copy) NSString *key, *title;
@property (readonly, copy) NSArray<NSDictionary *> *(^choices)(void);
@property (readonly, copy) NSString *(^picked)(void);
@property (readonly, copy) void (^pick)(NSString *choice);
// A row above its choices that can't be pressed, for what holds whichever is picked: {name, help} ("Urgent tasks,
// always"), or nil for none.
@property (copy) NSDictionary *fixed;
// Shown only while `shown` says so, and pressable only while `enabled` does; nil for always.
@property (copy) BOOL (^shown)(void);
@property (copy) BOOL (^enabled)(void);
@end

// A part of the day, in one of the groups on an app's page (quiet hours, from 22:00 to 08:00): its name over a line on
// what it does, and on its right the time it starts and the time it ends, each pressed for a menu of the day's half
// hours, in the Mac's own way of writing a time. `from` and `to` give minutes after midnight, and `set` takes both, as
// either end picked from its menu changes them together; that menu leaves out the other end's time.
@interface AppTime : NSObject
+ (instancetype)timeWithKey:(NSString *)key title:(NSString *)title help:(NSString *)help from:(NSInteger (^)(void))from
                         to:(NSInteger (^)(void))to set:(void (^)(NSInteger from, NSInteger to))set;
@property (readonly, copy) NSString *key, *title, *help;
@property (readonly, copy) NSInteger (^from)(void);
@property (readonly, copy) NSInteger (^to)(void);
@property (readonly, copy) void (^set)(NSInteger from, NSInteger to);
// Shown only while `shown` says so, and pressable only while `enabled` does (quiet hours' times, while they're on);
// nil for always.
@property (copy) BOOL (^shown)(void);
@property (copy) BOOL (^enabled)(void);
@end

// One of the groups on an app's page, under its plain switches (One Task's Who May Hand You Tasks): a heading over a
// card of its rows, each an AppSwitch, an AppChoice or an AppTime, and a line under the card; a group with no rows is
// only its line. Its place among the page's groups is its order (lower first), with those other modules add to the
// app among them. Shown only while `shown` says so; while `enabled` says NO, its rows are dimmed and can't be pressed
// (One Task's own, while it's off). Each nil for always, as are the heading and the line for none.
@interface AppGroup : NSObject
+ (instancetype)groupWithTitle:(NSString *)title rows:(NSArray *)rows foot:(NSString *)foot order:(NSInteger)order;
@property (readonly, copy) NSString *title, *foot;
@property (readonly, copy) NSArray *rows;
@property (readonly) NSInteger order;
@property (copy) BOOL (^shown)(void);
@property (copy) BOOL (^enabled)(void);
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

// A list on an app's page on the panel's back, opening a page of its own (Sessions, on each terminal's page and
// Claude's): its row, with its title and a count, and the page it opens, asked each time the back is told, as `now`
// gives it: {count, intro, loading, empty, sections, tray, said}.
// - `intro`, `loading` and `empty`: a line under its title, what it says while it's being read (given only then), and
//   what it says with nothing in it.
// - `sections`: each {title, tickable, foot, items: [{id, title, line, marks, why, way: {key, title}, buttons: [{key,
//   title}]}]}. A tickable section's items have a box to tick, but one with `why` (why it can't be ticked now, said on
//   its line instead, and more fully when pressed, with `way`, the button for the way forward). `marks` are what the
//   tray's question counts.
// - `tray`: what its foot offers for what's ticked, {hint (with nothing ticked), action, actionKey, pick: {mark, title
//   (with {n}, how many have the mark), untitle}, ask: {one, many (each with {name} or {n}), lead: {one, many}, notes:
//   [{mark, alone, one, many}], last}}, the question the action asks first, a note for each mark the ticked ones have
//   (`alone` when it's the one ticked).
// - `said`: what the last press did, {text, buttons: [{key, title}], at}, which the foot shows for a while.
// A press runs `press` with the button's key and the ids it's for (the ticked ones, or the one its item is).
@interface AppList : NSObject
+ (instancetype)listWithKey:(NSString *)key title:(NSString *)title now:(NSDictionary *(^)(void))now
                      press:(void (^)(NSString *key, NSArray<NSString *> *ids))press;
@property (readonly, copy) NSString *key, *title;
@property (readonly, copy) NSDictionary *(^now)(void);
@property (readonly, copy) void (^press)(NSString *key, NSArray<NSString *> *ids);
@end

// One of the apps a module works with, as the panel's back lists it (the apps module): its id (the app's bundle id, or
// a name of Whozmove's own for a tool that isn't an app, as git), its name, a line on what Whozmove does with it, its
// place among the others (lower first), what macOS has to allow, its switches, its groups, its cards and its lists. An
// entry made with only an app's id and switches, groups, cards or lists adds them to the app another module lists:
// starts adds "Open new conversations here" to each terminal, install the developer tools' card to Git's page, and
// sessions its Sessions to each host's.
@interface AppEntry : NSObject
+ (instancetype)appWithId:(NSString *)appId name:(NSString *)name does:(NSString *)does order:(NSInteger)order;
+ (instancetype)switches:(NSArray<AppSwitch *> *)switches forApp:(NSString *)appId;
+ (instancetype)groups:(NSArray<AppGroup *> *)groups forApp:(NSString *)appId;
+ (instancetype)statuses:(NSArray<AppStatus *> *)statuses forApp:(NSString *)appId;
+ (instancetype)lists:(NSArray<AppList *> *)lists forApp:(NSString *)appId;
@property (readonly, copy) NSString *appId, *name, *does;
@property (readonly) NSInteger order;
@property AppPermission permission;
// What it needs that permission for, in a few words: "Finds each session's tab, and types into it".
@property (copy) NSString *permissionFor;
@property (copy) NSArray<AppSwitch *> *switches;
@property (copy) NSArray<AppGroup *> *groups;
@property (copy) NSArray<AppStatus *> *statuses;
// Whether what it has on the page is as recommended, and what putting it back that way does: while any entry for the
// page says NO, the page ends with Use the Recommended Settings, which runs each one's. Both nil for none.
@property (copy) BOOL (^recommended)(void);
@property (copy) void (^useRecommended)(void);
@property (copy) NSArray<AppList *> *lists;
// Whether it's listed, for a tool that isn't an app (git) or an app listed whether it's installed or not (Spotify,
// whose token offers to get it); nil for an app listed while macOS finds it by its id.
@property (copy) BOOL (^present)(void);
// A tool of Whozmove's own rather than an app it works with (Storage): the back lists it under Tools, after the apps,
// and its page leads with what it does. Its permission has no section there: its card can say when it needs it (need),
// though no tool does now (Storage asks on its map's rows instead).
@property BOOL tool;
// What its page shows above its switches, asked each time the back is told: {figure, of, bar (how full, 0 to 1), tone
// (low or severe, or null), lines, actions: [{id, title, main}], need (what it can't do now without its permission, with
// a button to allow it, or nil; no tool sends one now)}, or nil for nothing; and what pressing one of its actions does.
@property (copy) NSDictionary *(^card)(void);
@property (copy) void (^act)(NSString *action);
// A few words under its name on its tile, inviting you to turn it on ("Know your storage"), or nil.
@property (copy) NSString *(^hint)(void);
@end

// One of the rows of Settings on the panel's back (the apps module), a choice you make once and come back to now and
// then: a switch, a choice of one among a few, or a row opening an app's page, where its choices are. Each has its
// key, its name, the mark on its tile (a name the back's page draws: look, list, keys, file, chat, gauge), and its
// place: the card it's on (`group`, lower first) and its order there.
@interface SettingEntry : NSObject
+ (instancetype)switchWithKey:(NSString *)key title:(NSString *)title glyph:(NSString *)glyph on:(BOOL (^)(void))on
                          set:(void (^)(BOOL on))set;
// The choices are {id, name}, with `help` for a line under its name, `isNew` YES for one that's new, `appId` for one
// that's an app (its icon shows beside it) and `enabled` NO for one that can't be picked now; `picked` is the id of the
// one picked.
+ (instancetype)choiceWithKey:(NSString *)key title:(NSString *)title glyph:(NSString *)glyph
                      choices:(NSArray<NSDictionary *> *(^)(void))choices picked:(NSString *(^)(void))picked
                         pick:(void (^)(NSString *choice))pick;
// A row opening the page of one of the apps on the panel's back (One Task's, a tool's), with that app's own tile, which
// says how it's set in a word or two (`said`, nil for nothing); ‹ there goes back to Settings. It's left out while that
// app isn't listed.
+ (instancetype)pageWithKey:(NSString *)key title:(NSString *)title app:(NSString *)appId;
@property (readonly, copy) NSString *key, *title, *glyph;
@property (readonly) BOOL isChoice;
@property (readonly, copy) NSString *app;
@property (copy) NSString *(^said)(void);
@property (readonly, copy) BOOL (^on)(void);
@property (readonly, copy) void (^set)(BOOL on);
@property (readonly, copy) NSArray<NSDictionary *> *(^choices)(void);
@property (readonly, copy) NSString *(^picked)(void);
@property (readonly, copy) void (^pick)(NSString *choice);
@property NSInteger group, order;
// The page a choice is on, by its name, with the other choices on that page: its row on Settings has that name and
// says what's picked on it ("Grey · Match the Mac"); nil for a choice on a page of its own, named by its title.
@property (copy) NSString *page;
// How its choices are drawn: nil for a list with a tick on the one picked, or "looks", each a small panel.
@property (copy) NSString *style;
// A line under its card, or under its choices on its page, and a button under it, for a way forward when the line
// says why something can't be picked ("Open Display Settings"): its name, and what pressing it does. Both nil for none.
@property (copy) NSString *foot;
@property (copy) NSString *button;
@property (copy) void (^press)(void);
// Shown only while `shown` says so; nil for always.
@property (copy) BOOL (^shown)(void);
@end

// How long one of a session's switches lasts once you've turned it on: for its conversation, kept by its id (carried on
// with --resume, it's still on), or for its process, so it ends as that session does, and a resumed one is allowed
// again; or for its process only while Whozmove runs, kept in the panel's memory, so nothing written anywhere can
// turn it on: a restart that stops Whozmove as a Deploy does leaves it off, with one press at the foot of the session's
// mode menu to turn on again what was ticked (Allowed's ticked.json only offers it), and a Quit forgets it; or for the
// folder its session works in (`workspace`) while Whozmove runs, kept in the panel's memory by that folder, so any
// session there the module's `whyNot` lets hold it has it on, a new one or a cleared one, until you untick it, or until
// no session there has held it for 7 days: a restart or a Quit leaves it off, with one press to turn it on again, as for
// one kept while Whozmove runs.
typedef NS_ENUM(NSInteger, SwitchLasts) {
    SwitchLastsConversation,
    SwitchLastsProcess,
    SwitchLastsWhileRunning,
    SwitchLastsWorkspace,
};

// One of the things a session may do by itself once you allow it, one session at a time (Don't Wait on Me, Let It
// Deploy): a switch at the foot of that session's mode menu, which only your press there sets, kept by the core
// (Allowed). Its name and a line on what it does; whether a row's menu has it (`shown`, nil for every row's: one that
// isn't shown counts as off, as `hiddenSays` says, so nothing you can't see or turn off goes on working, and with
// `endsHidden` it ends there and then, so showing it again doesn't bring it back); why it can't be turned on for a row
// now (`whyNot`, nil when it can: the menu greys it and says why, with `way`, a press that does something about it,
// when there is one, titled `wayTitle`, or `wayTitleFor` the row when it depends on the reason, nil for none; turning
// it off always can be); what it's given for (`bound`: it ends once that's changed, and `boundSays` says how, as a
// refused ask says it); and what the module does as it goes on or off for a session, by its id (`changed`), which comes
// too as the core takes away one that has ended. While it's on, its line may say more for a row (`says`, nil for its
// line as it is): what it has done so far. One kept for a folder (SwitchLastsWorkspace) has the folder a row works in
// from `workspace` (nil for none), as a real path, and is on only while `whyNot` says nothing for the row, asked each
// time: which session in the folder may hold it is the module's to say. One kept for a folder gives in `whyNot` the
// cause alone, starting with a plain word, never another program's name, as where it's said adds what to do next, at a
// sentence's start or after a colon (AfterColon); other switches' reasons are said whole.
@interface SessionSwitch : NSObject
+ (instancetype)switchWithKey:(NSString *)key title:(NSString *)title line:(NSString *)line lasts:(SwitchLasts)lasts;
@property (readonly, copy) NSString *key, *title, *line;
@property (readonly) SwitchLasts lasts;
@property (copy) BOOL (^shown)(Row *row);
@property (copy) NSString *hiddenSays;
@property BOOL endsHidden;
@property (copy) NSString *(^whyNot)(Row *row);
@property (copy) NSString *wayTitle;
@property (copy) NSString *(^wayTitleFor)(Row *row);
@property (copy) void (^way)(Row *row);
@property (copy) NSString *(^bound)(Row *row);
@property (copy) NSString *boundSays;
@property (copy) void (^changed)(NSString *sessionId, BOOL on);
@property (copy) NSString *(^says)(Row *row);
@property (copy) NSString *(^workspace)(Row *row);
@end

// One thing a session may ask the panel to do itself (with ask-panel.sh, in every build), and the switch that session
// needs on for it. The core finds which session asks from the process that connects (SessionAsks), never from what it
// sends, checks the switch, and only then asks `answer`, on the main thread, for what to say back: one line, in plain
// words. It's given the session's row, its own process the ask came from (`process`), which the switch was checked
// for, and what was asked (as ask-panel.sh sends it: {ask, folder}, or {ask, id, note64}), which never says who
// asks. One may need any one of several switches on (`askNeedingAny:`, its `switchKeys`), and none is never let through,
// but for an ask that only shows the user something (`askShowing:`, a task to do), or reads back what they gave it
// (their answer, its ticket), and does nothing in the session's name: that needs no switch, as asking someone something
// gives no one more power. One that acts only once a switch is on, and otherwise shows the user what it would do for
// their press (moving a ticket), is one too: its answer checks that switch itself, for the process that asks
// (Allowed's whyOff:for:from:).
@interface SessionAsk : NSObject
+ (instancetype)askNeeding:(NSString *)switchKey
                    answer:(NSString *(^)(Row *row, pid_t process, NSDictionary *asked))answer;
+ (instancetype)askNeedingAny:(NSArray<NSString *> *)switchKeys
                       answer:(NSString *(^)(Row *row, pid_t process, NSDictionary *asked))answer;
+ (instancetype)askShowing:(NSString *(^)(Row *row, pid_t process, NSDictionary *asked))answer;
@property (readonly, copy) NSArray<NSString *> *switchKeys;
@property (readonly) BOOL showsOnly;
@property (readonly, copy) NSString *(^answer)(Row *row, pid_t process, NSDictionary *asked);
// The core logs each ask and its answer to panel.log. One whose module logs what's worth keeping itself (one asked again
// and again while it waits, or whose answer carries what the user wrote) has only the core's refusals logged.
@property BOOL logsItself;
@end

// What a print run (for the tests) prints from its arguments, those after its flag; its result is the exit status.
typedef int (^PrintMode)(Core *core, NSArray<NSString *> *arguments);
// A helper run: one of the app's own one-file jobs, which the app runs itself as a process of its own, never for the
// tests. It acts on your real files, so each refuses whatever it isn't for. Given its arguments, those after its flag;
// its result is the exit status.
typedef int (^HelperRun)(Core *core, NSArray<NSString *> *arguments);

// Compacting a session from the panel, which the commands module offers to a feature that compacts sessions by itself
// (Compact at Breaks). It goes in as the Compact card's does: the same checks right before each key, the draft in its
// prompt kept, its result watched. The core finds it (moduleThat:).
// How a compaction that went in by itself ended: it compacted; it didn't, and why (refused before a key, or its result
// said so); `stillMay` said no before any key went in (left for you); or it stopped after some of its keys were in.
typedef NS_ENUM(NSInteger, CompactEnd) {
    CompactEndCompacted,
    CompactEndFailed,
    CompactEndLeftForYou,
    CompactEndStoppedPartWay,
};

@protocol SessionCompacting <NSObject>
// Why it can't be compacted by itself now, as the Compact card would say it, with its tab looked for (so it's asked of
// one session at a time), or nil; and the words of the card's button past that, when its terminal has one.
- (NSString *)whyNotCompact:(Row *)row wayPast:(NSString **)way;
// Compacts it with `focus`, by itself: never a beep or the Compact card, only into a terminal and never one also open
// elsewhere, and each key, and the filler taken out after its result, only while `stillMay` says it may. `whenOver` is
// told how it ended, and why when it didn't compact.
- (void)compact:(Row *)row focus:(NSString *)focus stillMay:(BOOL (^)(void))stillMay
       whenOver:(void (^)(CompactEnd end, NSString *why))whenOver;
// Whether a compaction from the panel is going into any session now.
@property (readonly) BOOL compactingAny;
@end

// Opening a file at a line in the editor you chose (the pawn menu's Open With), which the changes module keeps: other
// modules open their files with it (Keys, a key's line), each having checked first that it's a file of theirs to open.
// The core finds it (moduleThat:).
@protocol FilesAtLines <NSObject>
// NO while no editor is chosen, or if it didn't open.
- (BOOL)openFile:(NSString *)path atLine:(NSInteger)line;
@end

// Getting this copy of Whozmove again, the way it came, for a part of it that's missing or won't run (the Betterleaks
// Keys looks with): the install module offers it, and the core finds it (moduleThat:). For a copy Homebrew installed,
// its button copies the command that installs it again, as the update line's copies its command; else it opens the
// page Whozmove is downloaded from.
@protocol WhozmoveAgain <NSObject>
// {title, says}: the button's words, and a line on what it does.
- (NSDictionary *)wayToGetWhozmoveAgain;
// What the button does.
- (void)getWhozmoveAgain;
@end

// Each team in the team file as a whole, for a module that shows all of one (the team board), which the team module
// keeps: [{project, lead, chief, goals, queue, jobs}], plain data (docs/reference/team.md, "Each team as a whole"),
// the chief being the session you talk to, else the lead. Each job under way says where it is (`underWay`: `you`,
// `waiting` or `work`), the team module's one rule for it, which every module counts by rather than working it out.
// It's the same array until the file is read again, so a module tells a change by it alone. The core finds it
// (moduleThat:).
@protocol TeamFacts <NSObject>
- (NSArray<NSDictionary *> *)teams;
// Whether teams show in this Whozmove now (Working on Whozmove ▸ Show Teams, the team module's own switch): while they
// don't, `teams` is empty and no row has a team, so a module offers nothing that needs one.
- (BOOL)teamsShown;
@end

// What Deploy last put in place for a project, which the deploy module keeps: other modules read it as plain data, to
// say what a build has in it. The core finds it (moduleThat:).
@protocol BuildsInPlace <NSObject>
// For a project, its repo's main checkout (or its folder outside git), as {folder, commit, uncommitted, at, by,
// before}: the checkout the last deploy that went through ran from, the commit it started from (none outside git, nor
// for a deploy from before commits were noted), how many files there weren't committed then, when it ended (ms since
// 1970), the session that asked for it (none for your press), and the build in place before it, the same way. A
// worktree removed since has the same commits in the project's main checkout. nil before Deploy has put one in place,
// or before it has read the project's folders since Whozmove started.
- (NSDictionary *)buildInPlaceFor:(NSString *)project;
@end

// Your gear, which the usage module keeps: how many sessions are working on your plan, how many it can carry to the
// week's end, and the gear you set, for what shows it or follows it beyond the card. Plain data, numbers only (ms since
// 1970), or nil until the usage has first been found, and while Usage Gear is off in Settings: {gear (NSNull until your first press), atWork, counted (the ids
// of the sessions working), over (the ids beyond the gear, those whose turn began last first), room (how many more the
// gear lets work, never below 0; NSNull until your first press), recommended (NSNull
// while the week can't be measured), notYet (why not: {reason: rise|hours|watched, rise, hours}), limit (the session
// at its limit), bound (week|session: which window sets the recommendation), forecast ({gear, ends (percent),
// runsOutAt, sessionRunsOutAt, resetsAt}), checkedAt}. Only your press on a seat of the card's changes the gear; every
// word for it is the usage module's (core.gear on the page). The core finds it (moduleThat:).
@protocol GearFacts <NSObject>
- (NSDictionary *)gear;
@end

// The ask-panel.sh commands a module's asks wait with, which a session may leave running in the background while it
// waits on the panel: each as the words after ask-panel.sh, word for word ({"wait", "--comments"}), with only flags
// after its first word, so nothing in it names a program. The agent's module gathers every module's (modulesThat:)
// and doesn't list such a job as the session's work, only when its whole command, recorded just as written, is one
// of them; each module's words are its own, as are its asks, and its tests check them against ask-panel.sh.
@protocol BackgroundWaits <NSObject>
- (NSArray<NSArray<NSString *> *> *)backgroundWaits;
@end

// A module with words for a conversation that's opened again from its row to carry it on (the row's own press, a
// Resume on it), which go in as its first message: fixed words only, never anything from outside. A press only to look
// at it (Take Me There) takes none. The core finds them (modulesThat:), and the first with words for the row gives
// them; nil for none. Focus asks it as it opens a conversation again.
@protocol ReopenWords <NSObject>
- (NSString *)wordsOnReopen:(Row *)row;
@end

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
// What it has to tell you now (contracts/Notice.h), asked each time the rows are read: the notifications module
// decides what shows, when and where. One stays while it's listed, and goes from every place once it isn't.
- (NSArray<Notice *> *)notices;
// The apps it works with, as the panel's back lists them, and the switches it adds to other modules' apps.
- (NSArray<AppEntry *> *)appEntries;
// Its rows in Settings on the panel's back.
- (NSArray<SettingEntry *> *)settingEntries;
// What a session may do once you allow it (SessionSwitch), and what one may ask the panel to do, by the word it asks
// with ("put-in-place"); each word has one module.
- (NSArray<SessionSwitch *> *)sessionSwitches;
- (NSDictionary<NSString *, SessionAsk *> *)sessionAsks;
// A start from the new conversation card carried something for this module (what its part of the card gave, under the
// module's name: core.startCardParts on the page), and it has become this session: the module takes it from there.
// Your press of Start is what gave it.
- (void)started:(NSString *)sessionId with:(id)with;
// Its print modes, by flag ("--print-spotify"), for the tests.
+ (NSDictionary<NSString *, PrintMode> *)printModes;
// Its helper runs, by flag ("--helper-trash-item"): jobs of the app's own that it runs as a process of its own
// (HelperRun).
+ (NSDictionary<NSString *, HelperRun> *)helperRuns;
@end
