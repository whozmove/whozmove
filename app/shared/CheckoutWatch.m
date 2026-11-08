// CheckoutWatch: tells when something in a checkout may have changed, from macOS's file system events.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "CheckoutWatch.h"
#import <CoreServices/CoreServices.h>
#include <sys/mount.h>
#import "Files.h"
#import "Git.h"

// How long macOS gathers events before telling them, in seconds: a save or a commit is a burst of them. And how long a
// checkout no one asks for any more stays watched.
static const CFTimeInterval kLatency = 0.3;
static const NSTimeInterval kKeepWatching = 60;

// Two streams: one over the working trees, told by folder (a build writing thousands of files is one event a folder),
// and one over their git folders, told file by file, as which of a git folder's files changed says whose it is.
static FSEventStreamRef treeStream, gitStream;
static BOOL started, streaming;
// Each watcher's checkouts; when each checkout was last asked for; the ones to watch, and the ones watched now, each
// with its folders ({trees: the root, and its real path when that differs; own, common: GitFolders', as real paths;
// parents: FindFolders'}); and the counts each reader goes by: each checkout's files and refs, and each repo's (by its
// shared git folder).
static NSMutableDictionary<NSString *, NSSet<NSString *> *> *asked;
static NSMutableDictionary<NSString *, NSDate *> *askedAt;
static NSSet<NSString *> *watching;
static NSDictionary<NSString *, NSDictionary *> *folders;
static NSMutableDictionary<NSString *, NSNumber *> *fileCounts, *refCounts, *repoCounts;

// Whether `path` is `folder` or inside it.
static BOOL Inside(NSString *path, NSString *folder) {
    return folder.length && ([path isEqualToString:folder] || [path hasPrefix:[folder stringByAppendingString:@"/"]]);
}

// A path inside a folder, as its parts, past the folder's own.
static NSArray<NSString *> *PartsWithin(NSString *path, NSString *folder) {
    NSString *rest = path.length > folder.length ? [path substringFromIndex:folder.length + 1] : @"";
    return rest.length ? [rest componentsSeparatedByString:@"/"] : @[];
}

// What in a git folder changes without changing anything git says about the checkout: the objects a commit writes
// (the refs it moves are told), the reflogs, and the lock files git writes a file through. `parts` are within the git
// folder.
static BOOL Noise(NSArray<NSString *> *parts) {
    if (!parts.count) return NO;
    return [parts[0] isEqualToString:@"objects"] || [parts[0] isEqualToString:@"logs"]
        || [parts.lastObject hasSuffix:@".lock"];
}

// What a repo's checkouts share in its git folder: its branches and GitHub's copies of them, and its config.
static BOOL Shared(NSArray<NSString *> *parts) {
    return parts.count && [@[@"refs", @"packed-refs", @"config"] containsObject:parts[0]];
}

// Which of a repo's checkouts a change in what they share is theirs, `parts` being within the shared git folder
// `common`: a branch that moved (refs/heads/<name>) is the checkouts on it, and every one's when it's the local base
// branch they count their work from (BaseBranchInFiles); GitHub's copies (refs/remotes), the packed refs and the config
// are every one's (@""); the rest (tags, the stash, notes) no one's (nil). `base` is set when the change can have moved
// or made or removed the base, which what the checkouts keep of the repo goes by.
static NSString *SharedReach(NSArray<NSString *> *parts, NSString *common, BOOL *base) {
    *base = NO;
    if (!Shared(parts) || [parts.lastObject hasSuffix:@".lock"]) return nil;
    if (![parts[0] isEqualToString:@"refs"] || parts.count < 3 || [parts[1] isEqualToString:@"remotes"]) {
        *base = YES;
        return @"";
    }
    if (![parts[1] isEqualToString:@"heads"]) return nil;
    NSString *name = [[parts subarrayWithRange:NSMakeRange(2, parts.count - 2)] componentsJoinedByString:@"/"];
    BOOL local = NO;
    NSString *baseName = BaseBranchInFiles(common, &local);
    *base = !baseName || [name isEqualToString:baseName] || [@[@"main", @"master"] containsObject:name];
    return local && [name isEqualToString:baseName] ? @"" : name;
}

// The branch a checkout's HEAD is on, from its own git folder, or nil (a detached HEAD); read once for each batch of
// events macOS tells (`branches`, cleared as each comes).
static NSMutableDictionary<NSString *, id> *branches;
static NSString *BranchAt(NSString *own) {
    if (branches[own]) return branches[own] == NSNull.null ? nil : branches[own];
    NSString *head = [[NSString stringWithContentsOfFile:[own stringByAppendingPathComponent:@"HEAD"]
                                                encoding:NSUTF8StringEncoding error:nil]
                      stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *branch = [head hasPrefix:@"ref: refs/heads/"] ? [head substringFromIndex:16] : nil;
    if (!branches) branches = [NSMutableDictionary dictionary];
    branches[own] = branch ?: NSNull.null;
    return branch;
}

static void Bump(NSMutableDictionary<NSString *, NSNumber *> *counts, NSString *key) {
    if (key.length) counts[key] = @(counts[key].unsignedIntegerValue + 1);
}

// A submodule's changes show in the git status of the checkouts it's in (whose git folders hold its own), as changes
// to their files.
static void BumpParents(NSString *root) {
    for (NSString *parent in folders[root][@"parents"]) Bump(fileCounts, parent);
}

// Everything about a checkout may have changed.
static void BumpAll(NSString *root) {
    Bump(fileCounts, root);
    Bump(refCounts, root);
    Bump(repoCounts, folders[root][@"common"]);
}

// A change in a working tree is the deepest checkout's that holds it (a worktree inside another checkout is its own);
// one in a main checkout's .git is left to the git stream.
static void TreeChanged(NSString *path) {
    __block NSString *deepest = nil, *deepestTree = nil;
    [folders enumerateKeysAndObjectsUsingBlock:^(NSString *root, NSDictionary *f, BOOL *stop) {
        for (NSString *tree in f[@"trees"])
            if (Inside(path, tree) && tree.length > deepestTree.length) deepest = root, deepestTree = tree;
    }];
    if (!deepest || Inside(path, [deepestTree stringByAppendingPathComponent:@".git"])) return;
    Bump(fileCounts, deepest);
    BumpParents(deepest);
}

// A change in a checkout's own git folder is that checkout's (the deepest one's: a submodule's own folder is inside its
// parent repo's, under modules/): its index, what's staged, or else its HEAD. What a git folder holds for its linked
// worktrees and submodules (worktrees/, modules/) is theirs, watched or not. One in what a repo's checkouts share is
// theirs as SharedReach says.
static void GitChanged(NSString *path) {
    __block NSString *owner = nil, *ownerOwn = nil;
    NSMutableDictionary<NSString *, id> *reach = [NSMutableDictionary dictionary];  // each repo's SharedReach, or null
    NSMutableSet<NSString *> *bases = [NSMutableSet set];  // the repos where the base may have changed
    [folders enumerateKeysAndObjectsUsingBlock:^(NSString *root, NSDictionary *f, BOOL *stop) {
        NSString *own = f[@"own"], *common = f[@"common"];
        if (Inside(path, own) && own.length > ownerOwn.length) owner = root, ownerOwn = own;
        if (!Inside(path, common)) return;
        id to = reach[common];
        if (!to) {
            BOOL base = NO;
            to = reach[common] = SharedReach(PartsWithin(path, common), common, &base) ?: NSNull.null;
            if (base) [bases addObject:common];
        }
        if (to == NSNull.null || !([to isEqualToString:@""] || [to isEqualToString:BranchAt(own) ?: @""])) return;
        Bump(refCounts, root);
        BumpParents(root);
    }];
    // What the repo's checkouts keep of it (their remotes, the base branch) goes by what can change those.
    for (NSString *common in bases) Bump(repoCounts, common);
    if (!owner) return;
    NSArray *parts = PartsWithin(path, ownerOwn);
    if (Noise(parts) || Shared(parts) || (parts.count && [@[@"worktrees", @"modules"] containsObject:parts[0]])) return;
    if (parts.count == 1 && [parts[0] hasPrefix:@"index"]) Bump(fileCounts, owner);
    else Bump(refCounts, owner);
    BumpParents(owner);
}

// Events about a folder as a whole (macOS couldn't keep up under it, or a volume came or went there): every checkout
// with a folder under it or around it may have changed.
static void FolderChanged(NSString *path) {
    [folders enumerateKeysAndObjectsUsingBlock:^(NSString *root, NSDictionary *f, BOOL *stop) {
        for (NSString *folder in [f[@"trees"] arrayByAddingObjectsFromArray:@[f[@"own"], f[@"common"]]])
            if (Inside(path, folder) || Inside(folder, path)) { BumpAll(root); break; }
    }];
}

static void Told(ConstFSEventStreamRef stream, void *info, size_t count, void *paths,
                 const FSEventStreamEventFlags flags[], const FSEventStreamEventId ids[]) {
    char **each = paths;
    [branches removeAllObjects];  // checkouts' branches are read afresh for each batch
    for (size_t i = 0; i < count; i++) {
        FSEventStreamEventFlags flag = flags[i];
        if (flag & kFSEventStreamEventFlagHistoryDone) continue;
        // Events macOS dropped: anything anywhere may have changed.
        if (flag & (kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped
                    | kFSEventStreamEventFlagEventIdsWrapped)) {
            for (NSString *root in folders) BumpAll(root);
            continue;
        }
        NSString *path = [NSFileManager.defaultManager stringWithFileSystemRepresentation:each[i]
                                                                                   length:strlen(each[i])];
        while (path.length > 1 && [path hasSuffix:@"/"]) path = [path substringToIndex:path.length - 1];
        if (flag & (kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged
                    | kFSEventStreamEventFlagMount | kFSEventStreamEventFlagUnmount))
            FolderChanged(path);
        else if (stream == treeStream) TreeChanged(path);
        else GitChanged(path);
    }
}

// Stops a stream, giving the last event it had told, so the next one starts from there and nothing is missed between.
static FSEventStreamEventId Stop(FSEventStreamRef *stream) {
    if (!*stream) return 0;
    FSEventStreamEventId last = FSEventStreamGetLatestEventId(*stream);
    FSEventStreamStop(*stream);
    FSEventStreamInvalidate(*stream);
    FSEventStreamRelease(*stream);
    *stream = NULL;
    return last;
}

static FSEventStreamRef Start(NSArray<NSString *> *paths, FSEventStreamEventId since, FSEventStreamCreateFlags flags) {
    if (!paths.count) return NULL;
    FSEventStreamRef stream = FSEventStreamCreate(NULL, Told, NULL, (__bridge CFArrayRef)paths,
                                                  since ?: kFSEventStreamEventIdSinceNow, kLatency, flags);
    if (!stream) return NULL;
    FSEventStreamSetDispatchQueue(stream, dispatch_get_main_queue());
    if (!FSEventStreamStart(stream)) {
        FSEventStreamInvalidate(stream);
        FSEventStreamRelease(stream);
        return NULL;
    }
    return stream;
}

// Whether a folder is on a volume of this Mac's own, whose changes macOS tells (not a network share).
static BOOL OnThisMac(NSString *path) {
    struct statfs volume;
    return statfs(path.fileSystemRepresentation, &volume) == 0 && (volume.f_flags & MNT_LOCAL);
}

// Each checkout's folders, as the streams tell them ({trees, own, common, parents}), for these checkouts, and the paths
// the two streams watch. Only checkouts on this Mac's own volumes are in it. It reads the disk, so it's run off the
// main thread: a network share that has stopped answering can hold it up.
static NSDictionary *FindFolders(NSSet<NSString *> *roots) {
    NSMutableDictionary *found = [NSMutableDictionary dictionary];
    NSMutableSet *trees = [NSMutableSet set], *gits = [NSMutableSet set];
    for (NSString *root in roots) {
        if (!OnThisMac(root)) continue;
        NSString *real = RealPath(root);
        NSArray *both = real.length && ![real isEqualToString:root] ? @[root, real] : @[root];
        // Told as their real paths, as macOS names what changed.
        NSString *own = nil, *common = nil;
        if (GitFolders(root, &own, &common)) own = RealPath(own) ?: own, common = RealPath(common) ?: common;
        found[root] = @{@"trees": both, @"own": own ?: @"", @"common": common ?: @""};
        [trees addObject:root];
        if (own) [gits addObject:own];
        if (common) [gits addObject:common];
    }
    // Each submodule's parents: the checkouts whose own git folder holds its own.
    NSMutableDictionary *withParents = [NSMutableDictionary dictionary];
    for (NSString *root in found) {
        NSMutableArray *parents = [NSMutableArray array];
        for (NSString *other in found)
            if (![other isEqualToString:root] && [found[root][@"own"] length] && [found[other][@"own"] length]
                && [found[root][@"own"] hasPrefix:[found[other][@"own"] stringByAppendingString:@"/modules/"]])
                [parents addObject:other];
        NSMutableDictionary *f = [found[root] mutableCopy];
        f[@"parents"] = parents;
        withParents[root] = f;
    }
    return @{@"folders": withParents, @"trees": trees.allObjects, @"gits": gits.allObjects};
}

// Starts the streams again over the checkouts to watch now, once their folders are found, from where the last ones
// left off (which tell what changes meanwhile), unless a newer list has come by then.
static void Restream(NSSet<NSString *> *roots) {
    static dispatch_queue_t finding;
    static NSUInteger restreams;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ finding = dispatch_queue_create("whozmove.checkout-watch", DISPATCH_QUEUE_SERIAL); });
    watching = roots;
    NSUInteger asOf = ++restreams;
    dispatch_async(finding, ^{
        NSDictionary *found = FindFolders(roots);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (asOf != restreams) return;
            FSEventStreamEventId treeSince = Stop(&treeStream), gitSince = Stop(&gitStream);
            folders = found[@"folders"];
            treeStream = Start(found[@"trees"], treeSince, kFSEventStreamCreateFlagNone);
            gitStream = Start(found[@"gits"], gitSince, kFSEventStreamCreateFlagFileEvents);
            streaming = (treeStream || ![found[@"trees"] count]) && (gitStream || ![found[@"gits"] count]);
        });
    });
}

static void Setup(void) {
    if (asked) return;
    asked = [NSMutableDictionary dictionary];
    askedAt = [NSMutableDictionary dictionary];
    fileCounts = [NSMutableDictionary dictionary];
    refCounts = [NSMutableDictionary dictionary];
    repoCounts = [NSMutableDictionary dictionary];
    watching = [NSSet set];
}

void StartCheckoutWatch(void) {
    Setup();
    started = YES;
    Restream([NSSet setWithArray:askedAt.allKeys]);
}

void WatchCheckouts(NSString *watcher, NSSet<NSString *> *roots) {
    Setup();
    asked[watcher] = [roots copy] ?: [NSSet set];
    NSDate *now = NSDate.date;
    for (NSSet *some in asked.allValues)
        for (NSString *root in some) askedAt[root] = now;
    for (NSString *root in askedAt.allKeys)
        if ([now timeIntervalSinceDate:askedAt[root]] > kKeepWatching) [askedAt removeObjectForKey:root];
    NSSet *all = [NSSet setWithArray:askedAt.allKeys];
    if (started && ![all isEqualToSet:watching]) Restream(all);
}

BOOL CheckoutWatched(NSString *root) {
    return started && streaming && root && folders[root] != nil;
}

NSUInteger CheckoutFileChanges(NSString *root) {
    return root ? fileCounts[root].unsignedIntegerValue : 0;
}

NSUInteger CheckoutRefChanges(NSString *root) {
    return root ? refCounts[root].unsignedIntegerValue : 0;
}

NSTimeInterval CheckoutQuietEvery(NSString *root) {
    return 270 + (root.hash % 60);
}

NSUInteger CheckoutRepoChanges(NSString *root) {
    NSString *common = root ? folders[root][@"common"] : nil;
    return common.length ? repoCounts[common].unsignedIntegerValue : 0;
}
