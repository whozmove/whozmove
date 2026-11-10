// ProcessNotesModule: how a project works, kept as a note only by your Keep It (ProcessNotesModule.m says how). Its face
// for the core is Module's; what's here is for its print run (ProcessNotesPrints.m), which drives it as the core and
// the page would.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Module.h"

@interface ProcessNotesModule : NSObject <Module, ProjectWay>
@property (weak) Core *core;
// The time now, in ms since 1970, unless a print run gives a clock of its own; and whether a session's process still
// runs, unless a print run says.
@property (copy) double (^clock)(void);
@property (copy) BOOL (^givenRuns)(Row *row);
// Notes are kept in this folder (AppDir/process-notes as it launches), and what's there is read.
- (void)keepIn:(NSString *)folder;
// What a session asks (process-draft), and your answer on its card (keep or notNow, for the draft that card showed, by
// when it was asked); `done` is told once Keep It has written the note, or couldn't.
- (NSString *)draft:(NSDictionary *)asked from:(Row *)row;
- (void)answer:(NSString *)act for:(NSString *)sessionId at:(NSNumber *)at done:(void (^)(void))done;
// Its part of the rows, as the core asks it each read.
- (void)rows:(NSArray<Row *> *)rows phase:(RowPhase)phase;
@end

// Its print modes, for the tests (ProcessNotesPrints.m).
NSDictionary<NSString *, PrintMode> *ProcessNotesPrintModes(void);
