// Scanner: the map of your disk. It measures your home folder, Applications and the folders shared by every account,
// off the main thread, keeping anything of 1 MB or more, every checkout and every folder it can't look inside, and what
// holds them (what's smaller is counted together), and keeps what it found in Whozmove's folder, so the map opens at
// once. It shows the page a folder at a time, three levels down, says what can't go to the Trash and why, and moves what
// you collected to the Trash, each checked again first.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@interface Scanner : NSObject
// What it found is kept in the file at `path`, readable by you alone.
- (instancetype)initWithFile:(NSString *)path;
// Measures the disk again, unless what's known is newer than `age` seconds (read from its file the first time).
- (void)measureIfOlderThan:(NSTimeInterval)age;
// Stops a measure under way, and deletes what's kept, once Storage is turned off.
- (void)forget;
// How the measuring is going, on the main thread: {scanning, counted (bytes so far), scannedAt (ms since 1970, or
// null), usualAt (when the first pass's usual places came, while the first map is measured, or null), fullDiskAccess}.
// With no map yet, a measure measures Clean up's usual places first, so it can list them in a few seconds.
@property (copy) void (^onState)(NSDictionary *state);
// The folders agents are at work in now, each with who's working there ({folder: who}), as the rows last said: what's
// in them can't go.
- (void)setBusy:(NSDictionary<NSString *, NSString *> *)busy;
// A folder for the page, by its id (0, the disk itself), three levels down, with what can't go and why; nil once it's
// gone from the map.
- (void)folder:(NSInteger)nodeId done:(void (^)(NSDictionary *view))done;
// What you collected moved to the Trash, by id, each checked again first; of a folder with parts taken back out of it
// (`keep`: its id to theirs), what's in it but those; nothing if the map was measured again since `measuredAt` (the
// map's scannedAt the page had; 0 for any): {moved: [names], size, refused: [{name, why}]}.
- (void)trash:(NSArray<NSNumber *> *)ids keeping:(NSDictionary<NSNumber *, NSArray<NSNumber *> *> *)keep
   measuredAt:(double)measuredAt done:(void (^)(NSDictionary *result))done;
// Finder shows it.
- (void)reveal:(NSInteger)nodeId;
// Apple's developer tools are in: the checkouts git wasn't asked about for want of them are asked again, as they're
// shown next.
- (void)askGitAgain;
@end

// Clean up (CleanUp.m): what comes back on its own, found on the map.
@interface Scanner (CleanUp)
// The list, on the main thread, or nil before anything's measured; from the first pass alone while the first map is
// measured (`usual`): {groups: [{id, title, says, items: [{id, name, where, size, on (ticked to start with), lock:
// {says}, command, waits (while a tool can't say yet), open: {app, name} (an app to open for it)}]}], scannedAt, tools,
// usual}. The tools are asked what they can free. Items are named by where they are, so the same place keeps its id
// from one map to the next.
- (void)cleanUp:(void (^)(NSDictionary *list))done;
// What you ticked, by id, cleaned, each found again in the list as it is now: folders to the Trash, each checked again
// first, and each tool's own command run as your terminal would, with a time limit; nothing if the map was measured
// again since `measuredAt` (the list's scannedAt; 0 for any). Each step told as it goes, on the main thread: {id,
// state (moving, trashed, running, done or stayed), why, then (what to do about one that stayed)}; and at the end:
// {freed (bytes), trashed (of them, in the Trash), cleaned: [names], failed: [{id, name, why, then}], ran (how many
// tools' commands ran)}.
- (void)clean:(NSArray<NSString *> *)ids measuredAt:(double)measuredAt
     progress:(void (^)(NSDictionary *step))progress done:(void (^)(NSDictionary *result))done;
// The checkouts the sessions are in now, whose repos' worktrees it looks at. On the main thread.
- (void)noteCheckouts:(NSArray<NSString *> *)checkouts;
@end

// For the tests: the folder in $HOME measured as the map measures your home folder, each item with what keeps it from
// going, if anything, given the folders agents are at work in ({folder: who}).
NSDictionary *MapOfHome(NSDictionary<NSString *, NSString *> *busy);
// For the tests: Clean up's list for the folder in $HOME, measured as the map measures your home folder, given the
// folders agents are at work in and the checkouts the sessions are in; and as it is from the first pass alone, before
// the first map, the usual places only. No tool is asked anything.
NSDictionary *CleanUpOfHome(NSDictionary<NSString *, NSString *> *busy, NSArray<NSString *> *checkouts);
NSDictionary *UsualCleanUpOfHome(NSDictionary<NSString *, NSString *> *busy);
// For the tests: what cleaning those ids of that list does, step by step and at the end ({steps, result}), moving into
// the folder `standIn` in place of the Trash, and running no tool; `stale` as if the map were measured again since,
// and `linked`, a folder in $HOME moved aside once the map is measured and a link to it put in its place.
NSDictionary *CleanOfHome(NSString *standIn, NSDictionary<NSString *, NSString *> *busy, NSArray<NSString *> *ids,
                          BOOL stale, NSString *linked);
