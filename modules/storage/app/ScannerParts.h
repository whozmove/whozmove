// ScannerParts: what the map's own files share (Scanner.m, which measures the disk and moves what you collected to the
// Trash, and CleanUp.m, what comes back on its own): a part of the map, one measure of the disk, the Scanner's state,
// and the checks both make before anything goes.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Scanner.h"

@interface MapNode : NSObject
@property (copy) NSString *name, *path;
@property (copy) NSString *kind;          // the disk's own parts: system (macOS) or aside (what isn't counted)
@property (assign) long long size, restSize;
@property (assign) NSInteger restCount, nodeId;
@property (assign) uint64_t fileId;
@property (strong) NSMutableArray<MapNode *> *kids;  // nil for a file
@property (weak) MapNode *parent;
// What it can't look inside: one kept in the cloud, or one that refused it (`denied`), else one macOS protects.
@property (assign) BOOL unread, cloud, denied, repo;
// Below it: the first thing that can't go whatever happens (a folder it can't look inside, a tool's store), and the
// checkouts in it.
@property (copy) NSString *holds;
@property (strong) NSArray<MapNode *> *reposBelow;
// A folder the first pass measured already (Scanner's `usual`), left out of the whole measure: it takes the first
// pass's part once the measure is done, as it is by then.
@property (assign) BOOL later;
// A first pass's part in a checkout (the folder's name, or "your home folder"): kept until the whole measure, which
// asks git about that checkout, takes it in.
@property (copy) NSString *inCheckout;
@end

// One measure of the disk, as it goes: what's skipped, the files with more than one name counted once, how much is
// counted so far, and whether it's been stopped.
@interface Measure : NSObject
@property (strong) NSSet<NSString *> *protectedPaths, *cloudPaths;
// The folders the first pass measured, left out (each a part marked `later`).
@property (strong) NSSet<NSString *> *skipped;
@property (strong) NSMutableSet<NSNumber *> *linked;
@property (assign) BOOL fullDiskAccess;
@property (assign) long long counted;
@property (atomic) BOOL stopped;
@property (assign) CFAbsoluteTime toldAt;
@property (copy) void (^progress)(long long counted);
@end

@interface Scanner ()
@property (copy) NSString *file;
@property (strong) dispatch_queue_t queue, measuring;
// On the queue: the map, each part by its id, when it was measured, with Full Disk Access or not; the measure under
// way; the folders agents are at work in; and what git last said of each checkout.
@property (strong) MapNode *disk;
// Before the first map: Clean up's usual places, measured first so it lists them at once, each a part of a tree of
// their own, numbered below zero so no id names a part of a map, until the whole measure takes them in; and when they
// came, in ms since 1970.
@property (strong) MapNode *usual;
@property (assign) double usualAt;
@property (strong) NSMutableDictionary<NSNumber *, MapNode *> *nodes;
@property (assign) double scannedAt;
@property (assign) BOOL fullDiskAccess, loaded;
@property (strong) Measure *measure;
@property (copy) NSDictionary<NSString *, NSString *> *busyHere;
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *repos;
// Whether a checkout in the folder last shown waited for Apple's developer tools, so git wasn't asked about it.
@property (assign) BOOL toolsWanted;
// The id the next map's parts are numbered from, so no id names a part of two maps.
@property (assign) NSInteger idsFrom;
// Clean up's (CleanUp.m): the queue tools are asked and run on, so the map isn't held up while they work; and the
// checkouts the sessions are in, whose worktrees it looks at, set and read on the main thread.
@property (strong) dispatch_queue_t cleaning;
@property (copy) NSArray<NSString *> *sessionCheckouts;
// On the cleaning queue: what the tools last said, and when.
@property (strong) NSDictionary *toolsSaid;
@property (assign) NSTimeInterval toolsAt;
// A print run's: a folder of its own that stands for the Trash, as macOS's is your account's whatever HOME says; and
// asking and running no tool.
@property (copy) NSString *standInTrash;
@property (assign) BOOL noTools;

// On the queue: the map read from its file the first time it's needed; what git says of a checkout; which of `parts`
// git ignores; why a part can't go, as {kind, says}, or nil; why it can't go now, checked again just before it does
// (still there, the same item, nothing keeping it), or nil; and moving one to the Trash, which takes it off the map.
- (void)loadIfNeeded;
// Each part's path and id, and what's below each that keeps it, worked out once the map is new; and the same for the
// first pass's usual places.
- (void)index;
- (void)indexUsual;
// The whole measure's parts left out for the first pass, each taking its part as it is now.
- (void)takeUsualInto:(MapNode *)disk;
- (NSDictionary *)repoState:(NSString *)root;
- (NSSet<NSString *> *)ignoredAmong:(NSArray<MapNode *> *)parts;
- (NSDictionary *)lockOf:(MapNode *)n ignored:(NSSet<NSString *> *)ignored;
- (NSString *)whyNot:(MapNode *)n;
- (void)move:(MapNode *)n size:(long long *)size refused:(NSMutableArray *)refused;
@end

// Clean up's usual places (CleanUp.m), within the home folder: what it lists without the map's checkouts; and those
// there, measured as the map measures, under a tree of their own (Scanner.m), the first pass.
NSArray<NSString *> *CleanUpUsualPlaces(void);
MapNode *MeasureUsual(Measure *m);
// The folder at `path`, measured as the map measures (nil if it isn't one); whether a part is a checkout or holds one,
// and whether it holds a folder it can't look inside; whether a path is a folder or inside it; and the checkout a part
// is in.
MapNode *MeasureTop(NSString *path, NSString *name, Measure *m);
BOOL HoldsCheckout(MapNode *n);
BOOL HoldsUnread(MapNode *n);
BOOL Within(NSString *path, NSString *folder);
MapNode *RepoOf(MapNode *n);
// Whether a path in your home folder is reached through no link on the way, and on the home folder's disk.
BOOL ReachedFromHome(NSString *path);

// For the tests: a Scanner whose map is the folder in $HOME, measured as the map measures your home folder, given the
// folders agents are at work in ({folder: who}).
Scanner *ScannerOfHome(NSDictionary<NSString *, NSString *> *busy);
