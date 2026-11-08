// Allowed: what each session may do by itself, as you've allowed it, one session at a time: the switches modules
// register (SessionSwitch in Module.h), set only by your press at the foot of a session's mode menu.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// Each session's are kept in Whozmove's own folder, allowed/<session>.json, only you may read or write them, as with
// its other files; any program running as you could change them, as it could Deploy's command (deploy.json). A switch
// that lasts only while Whozmove runs (SwitchLastsWhileRunning) is kept in the panel's memory instead, so nothing
// written anywhere turns it on. It is also written to ticked.json, whenever one changes, only for the next copy to
// offer back: a restart that stops Whozmove as a Deploy does, or a crash, leaves the file, and the copy that starts
// reads it into `waiting`, never into the switches that are on. Your one press at the foot of the session's mode menu
// (bringBack:) turns those on again, with every check ticking makes. A Quit forgets them. A switch kept for a
// folder (SwitchLastsWorkspace) is kept in memory by the folder you ticked it in, not by session: on for whichever
// session there its module's whyNot lets hold it, and ended by your untick, or once no session there has held it for 7
// days. ticked.json names only its folder and switch, and when, to be offered back after a restart or a Quit, for one
// press on any session there that may hold it.
#import <Foundation/Foundation.h>
#import "Module.h"

@class Core, Row;

@interface Allowed : NSObject
- (instancetype)initWithCore:(Core *)core;
// Every module's switches, in the modules' order; those a row's menu has (`shown`).
@property (readonly) NSArray<SessionSwitch *> *switches;
- (NSArray<SessionSwitch *> *)switchesFor:(Row *)row;
- (SessionSwitch *)switchWithKey:(NSString *)key;
// Whether a switch is on for a row's session: turned on, shown for it, and not ended since (its process gone, for one
// that lasts for the process, or what it was given for changed). And why it isn't, in plain words, or nil while it is.
// Asked for what one of the session's processes asks (`process`), one that lasts for the process is on only for that
// very process, the one it was turned on in, not a copy of the conversation resumed elsewhere. One that went off as
// Whozmove restarted says so, and that one press in the mode menu brings it back.
- (BOOL)isOn:(NSString *)key for:(Row *)row;
- (NSString *)whyOff:(NSString *)key for:(Row *)row;
- (NSString *)whyOff:(NSString *)key for:(Row *)row from:(pid_t)process;
// Turns a switch on, from now, or off, for a row's session, and tells its module (`changed`). Only the mode menu's own
// items call it. NO if it couldn't be: its session id isn't one, it can't be turned on for the row now (`whyNot`), or
// its file couldn't be written. An untick of a switch kept in memory is always YES: ticked.json failing to save it
// doesn't keep it on.
- (BOOL)set:(NSString *)key for:(Row *)row on:(BOOL)on;
// Whether a session has a record of a switch, ended or not, by its id: a module keeping a file of its own for a switch
// takes it away when there's none.
- (BOOL)has:(NSString *)key session:(NSString *)sessionId;
// The rows are whole: each time, a switch that ends once it's hidden (`endsHidden`) and is hidden for its session's row
// goes, and so does one kept in memory that has ended, or whose session isn't listed; and about once an hour, the
// switches kept in files that have ended go, and so do the files of sessions not listed any more
// (running, or kept once they've ended), but for one changed in the last day, whose row may not be listed yet. Their
// modules are told. The switches waiting to be brought back go here too, once they can't be: their session's process
// has ended, what they were given for changed, the switch isn't shown for the row, or the session isn't listed (not in
// the first minute, while the sessions are still being listed); one kept for a folder waits until its folder has gone.
- (void)rowsListed:(NSArray<Row *> *)rows;
// What a switch kept in memory has done for its session so far, which its line says (`says`): counted up by its
// module each time, and gone with the switch; for one kept for a folder, by each session that held it, kept while
// Whozmove runs.
- (void)countUp:(NSString *)key session:(NSString *)sessionId;
- (NSInteger)count:(NSString *)key session:(NSString *)sessionId;
// Starts keeping ticked.json at `path` (the app's own: AppDir/ticked.json, only the app calls it) and reads what the
// copy before this one left there into the switches waiting to be brought back: how many are. Only a switch kept in
// memory, of a session whose id is plain, whose process still runs and started when its record says, waits, and one
// kept for a folder named by its whole real path that's there; the file is written again without the rest. Until it is
// called nothing is written, so a print run that sets a switch never
// touches your own file; one run in a throwaway home may be given a path in it. Never in your own home while printing.
- (NSInteger)keepTickedAt:(NSString *)path;
// The switches that went off as Whozmove restarted and wait for a press, for a row: those its session had on, shown for
// its row now, in the very process it was ticked in (the row's, started when the record says), and those kept for its
// folder, for any session there it's shown for, in the modules' order. Ticking one by hand, or its session or process
// ending (for one kept for a folder, its folder going), takes it from the list.
- (NSArray<SessionSwitch *> *)waitingFor:(Row *)row;
// Your press: turns on again, with their counts, the switches waiting for the row's session that can be turned on now
// (shown for the row, in the process they were ticked in, or for one kept for a folder any session there, given in the
// row pressed on, what they were given for unchanged, and `whyNot` saying nothing), and returns them. None: empty, and
// `why` says why, in plain words, for one offered for the row. Only the mode menu's own item calls it.
- (NSArray<SessionSwitch *> *)bringBack:(Row *)row why:(NSString **)why;
// What bringBack: would turn on for the row now, of `switches` (nil for all), by its very checks, changing nothing: so
// the menu's item and a notice never promise what the press refuses. Only those offered for the row (waitingFor:)
// count; `why` is the first reason one of them can't come back, or that none waits; nil when all can.
- (NSArray<SessionSwitch *> *)bringableFor:(Row *)row among:(NSArray<SessionSwitch *> *)switches
                                        why:(NSString **)why;
// The app is closing: a Quit (`restarting` NO) forgets what one session had, and leaves in ticked.json only what's
// kept for folders, to be offered by the next copy (the file goes, or is emptied, if it can't be written); a restart (a
// build put in place, a crash) leaves it all for the copy that starts.
- (void)endRun:(BOOL)restarting;
// The folder a switch kept by folder is kept for, on or waiting for a press, when it's the row's: so its menu can say
// it's kept, and let you stop keeping it, whatever the row may hold. Nil for none, or a switch of another kind.
- (NSString *)keptFolder:(NSString *)key for:(Row *)row;
// The session and process ({session, pid}) a switch kept for the row's folder was ticked in, or brought back on: so its
// module can say when another session holds it. Nil while it isn't kept there.
- (NSDictionary *)tickedIn:(NSString *)key for:(Row *)row;
// A print run's own switches in place of the modules', so the tests try these rules on their own (tests/ticked.sh).
// Used only in a print run, never in the app.
@property (copy) NSArray<SessionSwitch *> *printingSwitches;
// Switches' titles in plain English, "May Answer Questions and May Approve Plans".
+ (NSString *)namesOf:(NSArray<SessionSwitch *> *)switches;
@end
