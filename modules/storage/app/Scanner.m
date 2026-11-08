// Scanner: the map of your disk (Scanner.h).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <AppKit/AppKit.h>
#import <sys/attr.h>
#import <sys/vnode.h>
#import <sys/mount.h>
#import <sys/stat.h>
#import <sys/resource.h>
#import <fcntl.h>
#import <unistd.h>
#import "ScannerParts.h"
#import "StorageFacts.h"
#import "Files.h"
#import "Git.h"
#import "Processes.h"

// Anything of 1 MB or more is kept on the map by itself, up to the 100 biggest in a folder; the rest is counted
// together, as its small items.
static const long long kKeepSize = 1000 * 1000;
static const NSUInteger kKeepMost = 100;
// The most checkouts below a folder git is asked about before it can go; a folder holding more is opened to choose.
static const NSUInteger kAskGitMost = 40;
// The outer rings show what's at least this share of the folder you're in: the rest is too thin to see.
static const double kThinnest = 0.004;
// How long what git says of a checkout is taken as known, in seconds.
static const NSTimeInterval kRepoFor = 60;
// How often how the measuring is going is told, in seconds.
static const CFAbsoluteTime kTellEvery = 0.4;
static const size_t kBuffer = 128 * 1024;
// The shape of what's kept in map.json: a map kept in another shape is measured again.
static const NSInteger kKeptShape = 2;



@implementation MapNode
@end

@implementation Measure

- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.fullDiskAccess = FullDiskAccess();
    NSMutableSet *protected = [NSMutableSet set], *cloud = [NSMutableSet set];
    for (NSString *each in kProtectedFolders) [protected addObject:[Home() stringByAppendingPathComponent:each]];
    for (NSString *each in kCloudFolders) [cloud addObject:[Home() stringByAppendingPathComponent:each]];
    self.protectedPaths = self.fullDiskAccess ? [NSSet set] : protected;
    self.cloudPaths = cloud;
    self.linked = [NSMutableSet set];
    return self;
}

@end

#pragma mark Measuring

typedef void (^EntryFound)(const char *name, fsobj_type_t type, uint64_t fileId, uint32_t links, off_t alloc,
                           dev_t dev);

// Everything in an open folder, read in bulk (getattrlistbulk): each one's name, kind, id, how many names it has, the
// space it takes on the disk, and the disk it's on. Each attribute comes only if it was returned, in the order of its
// bit, the error first; they're 4-byte aligned, so they're copied out rather than read in place.
static void ReadFolder(int fd, EntryFound found) {
    struct attrlist list = {0};
    list.bitmapcount = ATTR_BIT_MAP_COUNT;
    list.commonattr = ATTR_CMN_RETURNED_ATTRS | ATTR_CMN_NAME | ATTR_CMN_ERROR | ATTR_CMN_DEVID | ATTR_CMN_OBJTYPE
                    | ATTR_CMN_FILEID;
    list.fileattr = ATTR_FILE_LINKCOUNT | ATTR_FILE_ALLOCSIZE;
    char *buffer = malloc(kBuffer);
    if (!buffer) return;
    for (;;) {
        int count = getattrlistbulk(fd, &list, buffer, kBuffer, 0);
        if (count <= 0) break;
        char *entry = buffer;
        for (int i = 0; i < count; i++) {
            char *field = entry;
            uint32_t length;
            memcpy(&length, field, sizeof length);
            field += sizeof length;
            attribute_set_t returned;
            memcpy(&returned, field, sizeof returned);
            field += sizeof returned;
            uint32_t error = 0;
            if (returned.commonattr & ATTR_CMN_ERROR) {
                memcpy(&error, field, sizeof error);
                field += sizeof error;
            }
            const char *name = NULL;
            if (returned.commonattr & ATTR_CMN_NAME) {
                attrreference_t ref;
                memcpy(&ref, field, sizeof ref);
                name = field + ref.attr_dataoffset;
                field += sizeof ref;
            }
            dev_t dev = 0;
            if (returned.commonattr & ATTR_CMN_DEVID) {
                memcpy(&dev, field, sizeof dev);
                field += sizeof dev;
            }
            fsobj_type_t type = VNON;
            if (returned.commonattr & ATTR_CMN_OBJTYPE) {
                memcpy(&type, field, sizeof type);
                field += sizeof type;
            }
            uint64_t fileId = 0;
            if (returned.commonattr & ATTR_CMN_FILEID) {
                memcpy(&fileId, field, sizeof fileId);
                field += sizeof fileId;
            }
            uint32_t links = 1;
            off_t alloc = 0;
            if (type == VREG) {
                if (returned.fileattr & ATTR_FILE_LINKCOUNT) {
                    memcpy(&links, field, sizeof links);
                    field += sizeof links;
                }
                if (returned.fileattr & ATTR_FILE_ALLOCSIZE) {
                    memcpy(&alloc, field, sizeof alloc);
                    field += sizeof alloc;
                }
            }
            if (!error && name) found(name, type, fileId, links, alloc, dev);
            entry += length;
        }
    }
    free(buffer);
}

// Whether a part of the map is a checkout or holds one, among what's kept of it; and whether it holds a folder it can't
// look inside.
BOOL HoldsCheckout(MapNode *n) {
    if (n.repo) return YES;
    for (MapNode *kid in n.kids) if (kid.kids && HoldsCheckout(kid)) return YES;
    return NO;
}

BOOL HoldsUnread(MapNode *n) {
    for (MapNode *kid in n.kids) if (kid.unread || (kid.kids && HoldsUnread(kid))) return YES;
    return NO;
}

// Whether a part holds one the first pass measured, which takes its size once the measure is done.
static BOOL HoldsLater(MapNode *n) {
    for (MapNode *kid in n.kids) if (kid.later || (kid.kids && HoldsLater(kid))) return YES;
    return NO;
}

// Measures what's in a folder, and in each folder in it, staying on the disk it's on: a folder macOS protects isn't
// opened without Full Disk Access, one kept in the cloud never is, and one that refuses is one it can't look inside.
// Then the folder keeps its biggest things, and counts the rest together.
static void MeasureInto(MapNode *node, NSString *path, dev_t dev, Measure *m) {
    int fd = open(path.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0) {
        node.unread = node.denied = YES;
        return;
    }
    // Another disk mounted here isn't this one's: it's left out.
    struct stat opened;
    if (fstat(fd, &opened) != 0 || opened.st_dev != dev) {
        close(fd);
        return;
    }
    NSMutableArray<MapNode *> *kids = [NSMutableArray array];
    NSMutableArray<NSArray *> *folders = [NSMutableArray array];
    __block long long rest = 0;
    __block NSInteger restCount = 0;
    ReadFolder(fd, ^(const char *name, fsobj_type_t type, uint64_t fileId, uint32_t links, off_t alloc, dev_t on) {
        if (type == VDIR) {
            NSString *folder = [NSString stringWithUTF8String:name];
            if (on == dev && folder.length) [folders addObject:@[folder, @(fileId)]];
            return;
        }
        if (strcmp(name, ".git") == 0) node.repo = YES;  // a worktree's .git is a file
        long long size = alloc;
        if (type == VREG && links > 1) {
            NSNumber *key = @(fileId);
            if ([m.linked containsObject:key]) size = 0;
            else [m.linked addObject:key];
        }
        m.counted += size;
        NSString *fileName = size >= kKeepSize && type == VREG ? [NSString stringWithUTF8String:name] : nil;
        if (fileName) {
            MapNode *file = [MapNode new];
            file.name = fileName;
            file.size = size;
            file.fileId = fileId;
            [kids addObject:file];
        } else {
            rest += size;
            restCount++;
        }
    });
    close(fd);
    for (NSArray *each in folders) {
        if (m.stopped) return;
        NSString *name = each[0], *inside = [path stringByAppendingPathComponent:name];
        if ([name isEqualToString:@".git"]) node.repo = YES;
        MapNode *kid = [MapNode new];
        kid.name = name;
        kid.fileId = [each[1] unsignedLongLongValue];
        kid.kids = [NSMutableArray array];
        if ([m.cloudPaths containsObject:inside]) kid.unread = kid.cloud = YES;
        else if ([m.protectedPaths containsObject:inside]) kid.unread = YES;
        else if ([m.skipped containsObject:inside]) kid.later = YES;
        else MeasureInto(kid, inside, dev, m);
        [kids addObject:kid];
    }
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (m.progress && now - m.toldAt > kTellEvery) {
        m.toldAt = now;
        m.progress(m.counted);
    }
    long long size = rest;
    for (MapNode *kid in kids) size += kid.size;
    node.size = size;
    [kids sortUsingComparator:^NSComparisonResult(MapNode *a, MapNode *b) {
        return a.size == b.size ? [a.name compare:b.name] : a.size > b.size ? NSOrderedAscending : NSOrderedDescending;
    }];
    NSMutableArray<MapNode *> *kept = [NSMutableArray array];
    NSUInteger keptBig = 0;
    for (MapNode *kid in kids) {
        // A checkout stays on the map whatever its size, and so does a folder holding one, or one it can't look inside:
        // git is always asked about a checkout, and what holds either is seen to, before anything round it goes. So
        // does a folder the first pass measured, which takes its part once the measure is done, and one holding it.
        BOOL shown = kid.later || HoldsLater(kid) || HoldsCheckout(kid) || HoldsUnread(kid);
        if (kid.unread || shown || (kid.size >= kKeepSize && keptBig < kKeepMost)) {
            if (!kid.unread && !shown) keptBig++;
            kid.parent = node;
            [kept addObject:kid];
        } else {
            rest += kid.size;
            restCount += 1;
        }
    }
    node.kids = kept;
    node.restSize = rest;
    node.restCount = restCount;
}

MapNode *MeasureTop(NSString *path, NSString *name, Measure *m) {
    // What iCloud and other apps keep only in the cloud isn't fetched to be measured: on this thread, a folder or file
    // that's only in the cloud reads as one Whozmove can't look inside.
    setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD, IOPOL_MATERIALIZE_DATALESS_FILES_OFF);
    struct stat st;
    if (lstat(path.fileSystemRepresentation, &st) != 0 || !S_ISDIR(st.st_mode)) return nil;
    MapNode *node = [MapNode new];
    node.name = name;
    node.path = path;
    node.fileId = st.st_ino;
    node.kids = [NSMutableArray array];
    MeasureInto(node, path, st.st_dev, m);
    return node;
}

// Whether something in your home folder is where the whole measure would reach it: through no link on the way (it may
// be one itself) and on the home folder's disk, as that measure never follows a link or leaves the disk. A place
// reached through a link, or another disk mounted there, is somewhere else, and its Trash another disk's.
BOOL ReachedFromHome(NSString *path) {
    NSString *home = Home();
    if (!Within(path, home) || [path isEqualToString:home]) return YES;
    NSString *folder = path.stringByDeletingLastPathComponent;
    NSString *expected = [RealPath(home) stringByAppendingString:[folder substringFromIndex:home.length]];
    struct stat at, st;
    return [RealPath(folder) isEqualToString:expected] && stat(home.fileSystemRepresentation, &at) == 0
        && lstat(path.fileSystemRepresentation, &st) == 0 && st.st_dev == at.st_dev;
}

// The nearest folder holding a .git at or above `place`'s folder, from the home folder down: the checkout it's part
// of, which the first pass, measuring the place alone, doesn't see. Nil when there's none.
static NSString *CheckoutAbove(NSString *place) {
    NSString *found = nil, *folder = Home();
    NSArray<NSString *> *names = place.pathComponents;
    for (NSUInteger i = 0; i < names.count; i++) {
        struct stat st;
        if (lstat([folder stringByAppendingPathComponent:@".git"].fileSystemRepresentation, &st) == 0) found = folder;
        if (i + 1 < names.count) folder = [folder stringByAppendingPathComponent:names[i]];
    }
    return found;
}

// Clean up's usual places, the first pass: each one there measured as the map measures, a part of its own under a
// tree that stands for none of the disk. One reached through a link or on another disk is left to the whole measure,
// which leaves it out; one in a checkout is kept till then, as only the whole measure asks git about it.
MapNode *MeasureUsual(Measure *m) {
    MapNode *usual = [MapNode new];
    usual.name = @"usual";
    usual.kids = [NSMutableArray array];
    for (NSString *place in CleanUpUsualPlaces()) {
        if (m.stopped) return nil;
        NSString *path = [Home() stringByAppendingPathComponent:place];
        if (!ReachedFromHome(path)) continue;
        MapNode *each = MeasureTop(path, place.lastPathComponent, m);
        if (!each) continue;
        NSString *checkout = CheckoutAbove(place);
        if (checkout)
            each.inCheckout = [checkout isEqualToString:Home()] ? @"your home folder" : checkout.lastPathComponent;
        each.parent = usual;
        [usual.kids addObject:each];
        usual.size += each.size;
    }
    return usual;
}

// The space a volume's own files take. The volumes on a disk share its space, and statfs says only what the whole disk
// has in use.
static long long VolumeUsed(NSString *path) {
    struct attrlist list = {0};
    list.bitmapcount = ATTR_BIT_MAP_COUNT;
    list.volattr = ATTR_VOL_INFO | ATTR_VOL_SPACEUSED;
    struct { uint32_t length; off_t used; } __attribute__((packed)) answer;
    if (getattrlist(path.fileSystemRepresentation, &list, &answer, sizeof answer, 0) != 0) return 0;
    return answer.used;
}

// The whole disk: your home folder, Applications and the folders shared by every account, measured; macOS, which is
// every volume on the disk but the one your files are on (macOS's own, the one it starts from, its recovery and its
// swap); and what's left of the space in use, which isn't counted: other accounts, macOS's own records, Time Machine's
// snapshots, and what macOS keeps from Whozmove.
static MapNode *MeasureDisk(Measure *m) {
    NSDictionary *values = [[NSURL fileURLWithPath:Home() isDirectory:YES]
        resourceValuesForKeys:@[NSURLVolumeTotalCapacityKey, NSURLVolumeAvailableCapacityForImportantUsageKey]
                        error:nil];
    NSString *volume = [[NSURL fileURLWithPath:@"/" isDirectory:YES]
        resourceValuesForKeys:@[NSURLVolumeLocalizedNameKey] error:nil][NSURLVolumeLocalizedNameKey];
    long long total = AsNumber(values[NSURLVolumeTotalCapacityKey]).longLongValue;
    long long free = AsNumber(values[NSURLVolumeAvailableCapacityForImportantUsageKey]).longLongValue;
    struct statfs fs;
    long long inUse = statfs(Home().fileSystemRepresentation, &fs) == 0
        ? (long long)(fs.f_blocks - fs.f_bfree) * (long long)fs.f_bsize : 0;
    long long yours = VolumeUsed(Home());
    long long system = inUse > 0 && yours > 0 ? MAX(0, inUse - yours) : 0;
    MapNode *disk = [MapNode new];
    disk.name = volume.length ? volume : @"Your disk";
    disk.kids = [NSMutableArray array];
    MapNode *home = MeasureTop(Home(), Home().lastPathComponent, m);
    if (home) [disk.kids addObject:home];
    for (NSString *shared in kSharedFolders) {
        if (m.stopped) return nil;
        MapNode *each = MeasureTop(shared, [shared isEqualToString:@"/Applications"] ? @"Applications" : shared, m);
        if (each) [disk.kids addObject:each];
    }
    if (m.stopped) return nil;
    long long counted = 0;
    for (MapNode *kid in disk.kids) counted += kid.size;
    if (system > 0) {
        MapNode *macOS = [MapNode new];
        macOS.name = @"macOS";
        macOS.kind = @"system";
        macOS.size = system;
        [disk.kids addObject:macOS];
    }
    long long uncounted = total - free - counted - system;
    if (total > 0 && uncounted > 0) {
        MapNode *aside = [MapNode new];
        aside.name = m.fullDiskAccess ? @"Not counted" : @"Can't look inside";
        aside.kind = @"aside";
        aside.size = uncounted;
        [disk.kids addObject:aside];
    }
    long long size = 0;
    for (MapNode *kid in disk.kids) {
        kid.parent = disk;
        size += kid.size;
    }
    disk.size = size;
    [disk.kids sortUsingComparator:^NSComparisonResult(MapNode *a, MapNode *b) {
        return a.size == b.size ? NSOrderedSame : a.size > b.size ? NSOrderedAscending : NSOrderedDescending;
    }];
    return disk;
}

#pragma mark Keeping it

static NSDictionary *Kept(MapNode *n) {
    NSMutableDictionary *d = [@{@"n": n.name ?: @"", @"s": @(n.size), @"i": @(n.fileId)} mutableCopy];
    if (n.path && !n.parent.path) d[@"p"] = n.path;
    if (n.kind) d[@"t"] = n.kind;
    if (n.restSize || n.restCount) {
        d[@"r"] = @(n.restSize);
        d[@"c"] = @(n.restCount);
    }
    if (n.unread) d[@"u"] = @1;
    if (n.cloud) d[@"o"] = @1;
    if (n.denied) d[@"d"] = @1;
    if (n.repo) d[@"g"] = @1;
    if (n.kids) {
        NSMutableArray *kids = [NSMutableArray arrayWithCapacity:n.kids.count];
        for (MapNode *kid in n.kids) [kids addObject:Kept(kid)];
        d[@"k"] = kids;
    }
    return d;
}

static MapNode *FromKept(NSDictionary *d, MapNode *parent) {
    if (![d isKindOfClass:NSDictionary.class] || !AsText(d[@"n"])) return nil;
    MapNode *n = [MapNode new];
    n.name = d[@"n"];
    n.size = AsNumber(d[@"s"]).longLongValue;
    n.fileId = AsNumber(d[@"i"]).unsignedLongLongValue;
    n.path = AsText(d[@"p"]);
    n.kind = AsText(d[@"t"]);
    n.restSize = AsNumber(d[@"r"]).longLongValue;
    n.restCount = AsNumber(d[@"c"]).integerValue;
    n.unread = [AsNumber(d[@"u"]) boolValue];
    n.cloud = [AsNumber(d[@"o"]) boolValue];
    n.denied = [AsNumber(d[@"d"]) boolValue];
    n.repo = [AsNumber(d[@"g"]) boolValue];
    n.parent = parent;
    NSArray *kids = AsList(d[@"k"]);
    if (kids) {
        n.kids = [NSMutableArray arrayWithCapacity:kids.count];
        for (id each in kids) {
            MapNode *kid = FromKept(each, n);
            if (kid) [n.kids addObject:kid];
        }
    }
    return n;
}

#pragma mark The scanner

@implementation Scanner

- (instancetype)initWithFile:(NSString *)path {
    if (!(self = [super init])) return nil;
    self.file = path;
    self.queue = dispatch_queue_create("whozmove.storage.map", DISPATCH_QUEUE_SERIAL);
    self.measuring = dispatch_queue_create("whozmove.storage.measuring",
        dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
    self.nodes = [NSMutableDictionary dictionary];
    self.repos = [NSMutableDictionary dictionary];
    self.busyHere = @{};
    self.cleaning = dispatch_queue_create("whozmove.storage.cleaning",
        dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
    return self;
}

// On the queue: each part's path and id, and what's below each that keeps it, worked out once the map is new. The disk
// is always 0, and the rest are numbered on from the last map's, so an id the page had from an earlier map never names
// a part of this one.
- (void)index {
    [self.nodes removeAllObjects];
    self.idsFrom = [self index:self.disk from:MAX(1, self.idsFrom) step:1 into:self.nodes];
}

// The first pass's tree, its parts numbered down from -1, which no map's part ever is, and kept off the map's list of
// parts: what's below each that keeps it is worked out as for the map.
- (void)indexUsual {
    [self index:self.usual from:-1 step:-1 into:nil];
}

// Each part of a tree from `root` numbered from `from` on by `step` (the root itself 0), with its path and what's
// below it that keeps it, put in `nodes` by its id when given; the number after the last.
- (NSInteger)index:(MapNode *)root from:(NSInteger)from step:(NSInteger)step
              into:(NSMutableDictionary<NSNumber *, MapNode *> *)nodes {
    __block NSInteger next = from;
    __weak __block void (^walk)(MapNode *, NSString *);
    void (^each)(MapNode *, NSString *) = ^(MapNode *n, NSString *path) {
        n.nodeId = n == root ? 0 : next;
        if (n != root) next += step;
        nodes[@(n.nodeId)] = n;
        if (path) n.path = path;
        NSString *holds = nil;
        NSMutableArray<MapNode *> *repos = [NSMutableArray array];
        for (MapNode *kid in n.kids) {
            kid.parent = n;
            walk(kid, kid.path && !n.path ? kid.path : n.path ? [n.path stringByAppendingPathComponent:kid.name] : nil);
            if (!holds) holds = kid.unread || [self toolStoreSays:kid.path] ? kid.name : kid.holds;
            if (kid.repo) [repos addObject:kid];
            [repos addObjectsFromArray:kid.reposBelow ?: @[]];
        }
        n.holds = holds;
        n.reposBelow = repos.count > kAskGitMost ? [repos subarrayWithRange:NSMakeRange(0, kAskGitMost + 1)] : repos;
    };
    walk = each;
    each(root, nil);
    return next;
}

- (void)loadIfNeeded {
    if (self.loaded) return;
    self.loaded = YES;
    NSDictionary *kept = AsRecord(ReadJSON(self.file));
    if ([AsNumber(kept[@"version"]) integerValue] != kKeptShape) return;
    MapNode *disk = FromKept(kept[@"disk"], nil);
    if (!disk) return;
    self.disk = disk;
    self.scannedAt = AsNumber(kept[@"at"]).doubleValue;
    self.fullDiskAccess = [AsNumber(kept[@"fullDiskAccess"]) boolValue];
    [self index];
}

- (void)save {
    NSDictionary *kept = @{@"version": @(kKeptShape), @"at": @(self.scannedAt), @"fullDiskAccess": @(self.fullDiskAccess),
                           @"disk": Kept(self.disk)};
    NSData *json = [NSJSONSerialization dataWithJSONObject:kept options:0 error:nil];
    if (!json) return;
    NSFileManager *files = NSFileManager.defaultManager;
    [files createDirectoryAtPath:self.file.stringByDeletingLastPathComponent withIntermediateDirectories:YES
                      attributes:nil error:nil];
    // What's on your disk, folder by folder, is yours alone to read.
    if ([json writeToFile:self.file atomically:YES])
        [files setAttributes:@{NSFilePosixPermissions: @0600} ofItemAtPath:self.file error:nil];
}

// On the queue: how it's going, told on the main thread.
- (void)tell:(long long)counted {
    NSDictionary *state = @{@"scanning": @(self.measure != nil), @"counted": @(counted),
                            @"scannedAt": self.scannedAt ? @(self.scannedAt) : NSNull.null,
                            @"usualAt": self.usual ? @(self.usualAt) : NSNull.null,
                            @"fullDiskAccess": @(self.measure ? self.measure.fullDiskAccess : self.fullDiskAccess)};
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.onState) self.onState(state);
    });
}

- (void)measureIfOlderThan:(NSTimeInterval)age {
    dispatch_async(self.queue, ^{
        [self loadIfNeeded];
        double now = NSDate.date.timeIntervalSince1970 * 1000;
        if (self.measure) return;
        // Measured since, and Full Disk Access as it was: what's known still stands.
        if (self.disk && now - self.scannedAt < age * 1000 && self.fullDiskAccess == FullDiskAccess()) {
            [self tell:0];
            return;
        }
        Measure *m = [Measure new];
        __weak typeof(self) weakSelf = self;
        m.progress = ^(long long counted) {
            dispatch_async(weakSelf.queue, ^{ if (weakSelf.measure == m) [weakSelf tell:counted]; });
        };
        self.measure = m;
        [self tell:0];
        // With no map yet, Clean up's usual places go first, so it lists them in a few seconds, and they're left out
        // of the whole measure, which takes them as they are once it's done: cleaned meanwhile, they're gone.
        BOOL first = !self.disk;
        dispatch_async(self.measuring, ^{
            if (first) {
                MapNode *usual = MeasureUsual(m);
                NSMutableSet *skipped = [NSMutableSet set];
                for (MapNode *each in usual.kids) [skipped addObject:each.path];
                m.skipped = skipped;
                dispatch_async(self.queue, ^{
                    if (self.measure != m || !usual) return;
                    self.usual = usual;
                    self.usualAt = NSDate.date.timeIntervalSince1970 * 1000;
                    [self indexUsual];
                    [self tell:m.counted];
                });
            }
            MapNode *disk = MeasureDisk(m);
            dispatch_async(self.queue, ^{
                if (self.measure != m) return;  // stopped meanwhile
                self.measure = nil;
                if (disk) {
                    [self takeUsualInto:disk];
                    self.disk = disk;
                    self.scannedAt = NSDate.date.timeIntervalSince1970 * 1000;
                    self.fullDiskAccess = m.fullDiskAccess;
                    [self.repos removeAllObjects];
                    [self index];
                    [self save];
                }
                [self tell:0];
            });
        });
    });
}

// On the queue: each part the whole measure left out for the first pass takes that pass's part as it is now, and the
// folders above it grow by it; one cleaned meanwhile leaves the map. Then the first pass's tree is done with.
- (void)takeUsualInto:(MapNode *)disk {
    NSMutableDictionary<NSString *, MapNode *> *byPath = [NSMutableDictionary dictionary];
    for (MapNode *each in self.usual.kids) if (each.path) byPath[each.path] = each;
    __block long long taken = 0;
    __weak __block void (^walk)(MapNode *, NSString *);
    void (^each)(MapNode *, NSString *) = ^(MapNode *n, NSString *path) {
        for (MapNode *kid in [n.kids copy]) {
            NSString *inside = kid.path && !path ? kid.path
                             : path ? [path stringByAppendingPathComponent:kid.name] : nil;
            if (!kid.later) {
                if (kid.kids) walk(kid, inside);
                continue;
            }
            MapNode *usual = inside ? byPath[inside] : nil;
            NSUInteger at = [n.kids indexOfObject:kid];
            if (!usual) {
                [n.kids removeObjectAtIndex:at];
                continue;
            }
            usual.path = nil;
            usual.inCheckout = nil;
            usual.parent = n;
            n.kids[at] = usual;
            for (MapNode *above = n; above; above = above.parent) above.size += usual.size;
            taken += usual.size;
        }
    };
    walk = each;
    each(disk, nil);
    // What the disk didn't count was worked out without what the first pass measured: it's that much less.
    for (MapNode *kid in [disk.kids copy]) {
        if (![kid.kind isEqualToString:@"aside"]) continue;
        long long less = MIN(kid.size, taken);
        kid.size -= less;
        disk.size -= less;
        if (kid.size <= 0) [disk.kids removeObject:kid];
    }
    self.usual = nil;
}

- (void)forget {
    dispatch_async(self.queue, ^{
        self.measure.stopped = YES;
        self.measure = nil;
        self.usual = nil;
        self.usualAt = 0;
        self.disk = nil;
        self.scannedAt = 0;
        self.loaded = YES;
        [self.nodes removeAllObjects];
        [NSFileManager.defaultManager removeItemAtPath:self.file error:nil];
        [self tell:0];
    });
}

- (void)setBusy:(NSDictionary<NSString *, NSString *> *)busy {
    NSDictionary *copy = [busy copy] ?: @{};
    dispatch_async(self.queue, ^{ self.busyHere = copy; });
}

#pragma mark What can't go

- (NSString *)toolStoreSays:(NSString *)path {
    if (!path) return nil;
    for (NSString *store in kToolStores) {
        NSString *full = [Home() stringByAppendingPathComponent:store];
        if ([path isEqualToString:full] || [path hasPrefix:[full stringByAppendingString:@"/"]]) return kToolStores[store];
    }
    return nil;
}

BOOL Within(NSString *path, NSString *folder) {
    return [path isEqualToString:folder] || [path hasPrefix:[folder stringByAppendingString:@"/"]];
}

// git, asked about a checkout the map found, which may be any on the disk: never running a program its own settings
// name to watch its files (core.fsmonitor), and only the developer tools' own (RunGit), so nothing runs before Apple's
// developer tools are there; nil until then.
static NSDictionary *AskGit(NSString *root, NSArray<NSString *> *arguments) {
    return RunGit([@[@"--no-optional-locks", @"-c", @"core.fsmonitor=false", @"-c", @"core.quotePath=false", @"-C",
                     root] arrayByAddingObjectsFromArray:arguments]);
}

static NSString *GitOut(NSDictionary *run) {
    return run && [run[@"status"] intValue] == 0
        ? [[NSString alloc] initWithData:run[@"out"] encoding:NSUTF8StringEncoding] ?: @"" : nil;
}

// What git says of a checkout: whether it holds changes not committed yet, and whether it holds commits that are only
// on this Mac (`ahead`; `local` when it has no remote at all); nil when git can't say. A checkout's own .git holds every
// commit made in it, so any on no remote counts, on any branch, in a stash or on none; a worktree's are kept in its
// repo's, so only its own changes count. Kept a minute.
- (NSDictionary *)repoState:(NSString *)root {
    NSDictionary *known = self.repos[root];
    NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
    BOOL waited = [known[@"tools"] boolValue];
    if (known && now - [known[@"at"] doubleValue] < kRepoFor && !(waited && DeveloperToolsReady())) {
        if (waited) self.toolsWanted = YES;
        return known[@"state"] == NSNull.null ? nil : known[@"state"];
    }
    // Without Apple's developer tools, git isn't asked: the checkout keeps all it holds until they're in.
    if (!DeveloperToolsReady()) {
        self.toolsWanted = YES;
        self.repos[root] = @{@"at": @(now), @"state": NSNull.null, @"tools": @YES};
        return nil;
    }
    NSString *out = GitOut(AskGit(root, @[@"status", @"--porcelain=v1", @"--branch", @"--untracked-files=normal"]));
    NSDictionary *state = nil;
    if (out) {
        BOOL dirty = NO, ahead = NO, local = NO;
        for (NSString *line in [out componentsSeparatedByString:@"\n"]) {
            if ([line hasPrefix:@"## "]) ahead = [line containsString:@"[ahead "];
            else if (line.length) dirty = YES;
        }
        BOOL own = NO;
        BOOL found = [NSFileManager.defaultManager fileExistsAtPath:[root stringByAppendingPathComponent:@".git"]
                                                       isDirectory:&own];
        if (!own) ahead = NO;
        NSString *only = found && own ? GitOut(AskGit(root, @[@"rev-list", @"-n1", @"--all", @"--not", @"--remotes"]))
                                      : @"";
        if (!only) out = nil;
        else if (only.length) {
            ahead = YES;
            local = [GitOut(AskGit(root, @[@"remote"])) ?: @"x" stringByTrimmingCharactersInSet:
                     NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0;
        }
        if (out) state = @{@"dirty": @(dirty), @"ahead": @(ahead), @"local": @(local)};
    }
    self.repos[root] = @{@"at": @(now), @"state": state ?: NSNull.null};
    return state;
}

// Whether git wasn't asked about the checkout at `root` for want of Apple's developer tools, as repoState kept it.
- (BOOL)waitsForTools:(NSString *)root {
    return [self.repos[root][@"tools"] boolValue];
}

- (void)askGitAgain {
    dispatch_async(self.queue, ^{
        NSMutableArray *waited = [NSMutableArray array];
        for (NSString *root in self.repos) if ([self.repos[root][@"tools"] boolValue]) [waited addObject:root];
        [self.repos removeObjectsForKeys:waited];
    });
}

// Which of `paths` (within the checkout at `root`) git ignores: those can go though the checkout has changes.
static NSSet<NSString *> *Ignored(NSString *root, NSArray<NSString *> *paths, NSSet<NSString *> *folders) {
    NSMutableArray *relative = [NSMutableArray array];
    NSMutableDictionary *back = [NSMutableDictionary dictionary];
    for (NSString *path in paths) {
        if (!Within(path, root) || [path isEqualToString:root]) continue;
        NSString *rel = [path substringFromIndex:root.length + 1];
        // A folder is named as one, so a pattern for folders only matches it.
        if ([folders containsObject:path]) rel = [rel stringByAppendingString:@"/"];
        [relative addObject:rel];
        back[rel] = path;
    }
    if (!relative.count) return [NSSet set];
    NSDictionary *run = AskGit(root, [@[@"check-ignore", @"--"] arrayByAddingObjectsFromArray:relative]);
    NSString *out = run ? [[NSString alloc] initWithData:run[@"out"] encoding:NSUTF8StringEncoding] : nil;
    NSMutableSet *ignored = [NSMutableSet set];
    for (NSString *line in [out ?: @"" componentsSeparatedByString:@"\n"])
        if (back[line]) [ignored addObject:back[line]];
    return ignored;
}

// The checkout a part is in: the nearest folder at or above it that holds a .git.
MapNode *RepoOf(MapNode *n) {
    for (MapNode *each = n; each; each = each.parent)
        if (each.repo) return each;
    return nil;
}

// What git said a checkout holds that keeps it, in words: "changes not committed yet".
static NSString *Unsaved(NSDictionary *state, BOOL waits) {
    if (!state && waits) return @"what git can't read until Apple's developer tools are in";
    return !state ? @"what git couldn't read" : [state[@"dirty"] boolValue] ? @"changes not committed yet"
         : [state[@"local"] boolValue] ? @"history that's only on this Mac" : @"commits not pushed yet";
}

// Why a part of the map can't go to the Trash, as {kind, says}, or nil when it can. `ignored` holds the paths git
// ignores among those asked about together.
- (NSDictionary *)lockOf:(MapNode *)n ignored:(NSSet<NSString *> *)ignored {
    NSString *home = Home(), *path = n.path;
    if ([n.kind isEqualToString:@"system"]) return @{@"kind": @"system", @"says": @"macOS's own files"};
    if ([n.kind isEqualToString:@"aside"])
        return @{@"kind": @"aside", @"says": self.fullDiskAccess
            ? @"Other accounts, macOS's own records and Time Machine's snapshots"
            : @"Desktop, Documents, Downloads, other apps' data and other accounts: allow Full Disk Access to see them"};
    if (n.unread)
        return @{@"kind": @"unread", @"says": n.cloud ? @"Kept in the cloud by its app"
                 : n.denied ? @"Whozmove isn't allowed to look inside it"
                 : self.fullDiskAccess ? @"macOS keeps it from Whozmove" : @"Allow Full Disk Access to look inside"};
    if (!path) return @{@"kind": @"unread", @"says": @"Whozmove can't tell where it is"};
    // A checkout's .git is its history: it goes, if it goes, with the checkout, which is checked as a whole.
    if ([n.name isEqualToString:@".git"] || [path containsString:@"/.git/"])
        return @{@"kind": @"repo", @"says": @"Git's own record: move the whole checkout instead"};
    NSString *tool = [self toolStoreSays:path];
    if (tool) return @{@"kind": @"tool", @"says": tool};
    for (NSString *kept in kKeptFolders) {
        NSString *full = [kept hasPrefix:@"/"] ? kept : kept.length ? [home stringByAppendingPathComponent:kept] : home;
        if ([path isEqualToString:full])
            return @{@"kind": @"keep", @"says": [full isEqualToString:home] ? @"Your home folder: open it to choose"
                                                                            : @"Open it to choose what goes"};
    }
    if (!Within(path, home) && !Within(path, @"/Applications"))
        return @{@"kind": @"outside", @"says": @"Outside your home folder: Whozmove leaves it be"};
    for (NSString *folder in self.busyHere) {
        if (Within(path, folder) || Within(folder, path))
            return @{@"kind": @"agent", @"says": [NSString stringWithFormat:@"%@ is working in %@ now",
                                                  self.busyHere[folder], folder.lastPathComponent]};
    }
    if (n.holds) return @{@"kind": @"inside", @"says": [NSString stringWithFormat:@"Holds %@, which can't go: open it "
                                                        @"to choose", n.holds]};
    for (MapNode *each = n; each; each = each.parent)
        if (each.inCheckout)
            return @{@"kind": @"measuring", @"says": [NSString stringWithFormat:@"Part of the checkout in %@: git is "
                                                      @"asked about it once your disk is measured", each.inCheckout]};
    MapNode *repo = RepoOf(n);
    if (repo) {
        NSDictionary *state = [self repoState:repo.path];
        if (!state && [self waitsForTools:repo.path])
            return @{@"kind": @"repo", @"says": @"Git can't say what this checkout holds until Apple's developer tools "
                                                @"are in"};
        if (!state) return @{@"kind": @"repo", @"says": @"Git couldn't say what this checkout holds"};
        if (repo == n && [state[@"dirty"] boolValue]) return @{@"kind": @"repo", @"says": @"Changes not committed yet"};
        if (repo == n && [state[@"ahead"] boolValue])
            return @{@"kind": @"repo", @"says": [state[@"local"] boolValue] ? @"Its history is only on this Mac"
                                                                             : @"Commits not pushed yet"};
        if (repo != n && [state[@"dirty"] boolValue] && ![ignored containsObject:path])
            return @{@"kind": @"repo", @"says": [NSString stringWithFormat:@"Part of %@, which has changes not "
                                                 @"committed yet", repo.name]};
    }
    if (n.reposBelow.count > kAskGitMost)
        return @{@"kind": @"inside", @"says": [NSString stringWithFormat:@"Holds more than %lu checkouts: open it to choose",
                                                (unsigned long)kAskGitMost]};
    for (MapNode *below in n.reposBelow) {
        NSDictionary *state = [self repoState:below.path];
        if (!state || [state[@"dirty"] boolValue] || [state[@"ahead"] boolValue])
            return @{@"kind": @"inside", @"says": [NSString stringWithFormat:@"Holds %@, with %@: open it to choose",
                below.name, Unsaved(state, [self waitsForTools:below.path])]};
    }
    return nil;
}

// The paths git ignores among `parts`, asked of each checkout with changes they're in, all of a checkout's at once.
- (NSSet<NSString *> *)ignoredAmong:(NSArray<MapNode *> *)parts {
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *byRepo = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *folders = [NSMutableSet set];
    for (MapNode *n in parts) {
        MapNode *repo = RepoOf(n);
        if (!repo || repo == n || !n.path || ![[self repoState:repo.path][@"dirty"] boolValue]) continue;
        if (!byRepo[repo.path]) byRepo[repo.path] = [NSMutableArray array];
        [byRepo[repo.path] addObject:n.path];
        if (n.kids) [folders addObject:n.path];
    }
    NSMutableSet *ignored = [NSMutableSet set];
    for (NSString *root in byRepo) [ignored unionSet:Ignored(root, byRepo[root], folders)];
    return ignored;
}

#pragma mark For the page

static NSComparisonResult (^const BySize)(MapNode *, MapNode *) = ^NSComparisonResult(MapNode *a, MapNode *b) {
    if (a.unread != b.unread) return a.unread ? NSOrderedDescending : NSOrderedAscending;
    return a.size == b.size ? [a.name compare:b.name] : a.size > b.size ? NSOrderedAscending : NSOrderedDescending;
};

// Whether a part has the map's one way to allow Full Disk Access: one it couldn't look inside for want of it, and what
// isn't counted, which holds those.
- (BOOL)allows:(MapNode *)n {
    return !self.fullDiskAccess && ((n.unread && !n.cloud && !n.denied) || [n.kind isEqualToString:@"aside"]);
}

// A part as the page shows it, and what's inside it to two more levels, leaving out what's too thin to see.
- (NSDictionary *)item:(MapNode *)n depth:(int)depth whole:(long long)whole lock:(NSDictionary *)lock {
    NSMutableDictionary *d = [@{@"id": @(n.nodeId), @"name": n.name ?: @"", @"size": @(n.size),
                                @"folder": @(n.kids != nil)} mutableCopy];
    if (n.unread) d[@"unread"] = @YES;
    if (n.kind || n.unread) d[@"grey"] = @YES;
    if ([self allows:n]) d[@"allow"] = @YES;
    if (lock) d[@"lock"] = lock;
    if (depth < 3 && n.kids) {
        NSMutableArray *kids = [NSMutableArray array];
        for (MapNode *kid in [n.kids sortedArrayUsingComparator:BySize])
            if (kid.size >= whole * kThinnest) [kids addObject:[self item:kid depth:depth + 1 whole:whole lock:nil]];
        if (n.restSize >= whole * kThinnest) [kids addObject:[self restOf:n]];
        d[@"kids"] = kids;
    }
    return d;
}

- (NSDictionary *)restOf:(MapNode *)n {
    NSString *name = n.restCount == 1 ? @"1 small item" : [NSString stringWithFormat:@"%ld small items",
                                                                                        (long)n.restCount];
    return @{@"id": NSNull.null, @"name": name, @"size": @(n.restSize), @"rest": @YES};
}

- (NSDictionary *)viewOf:(MapNode *)focus {
    NSMutableArray *crumbs = [NSMutableArray array];
    for (MapNode *each = focus; each; each = each.parent)
        [crumbs insertObject:@{@"id": @(each.nodeId), @"name": each.name ?: @""} atIndex:0];
    NSArray<MapNode *> *kids = [focus.kids sortedArrayUsingComparator:BySize];
    self.toolsWanted = NO;
    NSSet *ignored = [self ignoredAmong:kids];
    NSMutableArray *items = [NSMutableArray array];
    for (MapNode *kid in kids)
        [items addObject:[self item:kid depth:1 whole:MAX(1, focus.size) lock:[self lockOf:kid ignored:ignored]]];
    if (focus.restSize > 0) [items addObject:[self restOf:focus]];
    return @{@"id": @(focus.nodeId), @"name": focus.name ?: @"", @"size": @(focus.size), @"path": crumbs,
             @"kids": items, @"scannedAt": @(self.scannedAt), @"fullDiskAccess": @(self.fullDiskAccess),
             @"tools": @(self.toolsWanted)};
}

- (void)folder:(NSInteger)nodeId done:(void (^)(NSDictionary *view))done {
    dispatch_async(self.queue, ^{
        [self loadIfNeeded];
        MapNode *n = self.nodes[@(nodeId)];
        NSDictionary *view = n.kids ? [self viewOf:n] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ done(view); });
    });
}

#pragma mark The Trash

// Each part you collected, checked again before it goes: it's still on the map and still where it was (the same item,
// not something put there since), nothing now keeps it, it's in your home folder or Applications, and a folder holds
// nothing now that the map didn't see (measured again first). A folder with parts you took back out of it (`keep`, by
// its id) isn't moved itself: what's in it goes, a part at a time, each checked the same way, and what you took out
// stays. Nothing goes if the map was measured again since what you collected was shown (`measuredAt`, 0 for any). What
// goes leaves the map, and the folders above it shrink.
- (void)trash:(NSArray<NSNumber *> *)ids keeping:(NSDictionary<NSNumber *, NSArray<NSNumber *> *> *)keep
   measuredAt:(double)measuredAt done:(void (^)(NSDictionary *result))done {
    dispatch_async(self.queue, ^{
        NSMutableArray *moved = [NSMutableArray array], *refused = [NSMutableArray array];
        __block long long size = 0;
        BOOL since = measuredAt && fabs(measuredAt - self.scannedAt) > 1;
        for (NSNumber *nodeId in ids) {
            MapNode *n = [nodeId isKindOfClass:NSNumber.class] ? self.nodes[nodeId] : nil;
            NSMutableSet<MapNode *> *kept = [NSMutableSet set];
            for (NSNumber *each in keep[nodeId] ?: @[])
                if ([each isKindOfClass:NSNumber.class] && self.nodes[each]) [kept addObject:self.nodes[each]];
            NSString *why = since ? @"The map was measured again since you collected it: collect it again"
                          : kept.count < keep[nodeId].count ? @"Part of what you took out of it isn't on the map now"
                          : [self whyNot:n] ?: (kept.count ? nil : [self whyNotNow:n]);
            if (why) {
                [refused addObject:@{@"name": n.name ?: @"It", @"why": why}];
                continue;
            }
            long long before = size;
            if (kept.count) [self empty:n keeping:kept size:&size refused:refused];
            else [self move:n size:&size refused:refused];
            // A folder emptied but for what you kept is named as what's collected says it: "Library but Caches".
            NSString *name = kept.count == 1 ? [NSString stringWithFormat:@"%@ but %@", n.name, kept.anyObject.name]
                           : kept.count ? [NSString stringWithFormat:@"%@ but %lu parts", n.name,
                                           (unsigned long)kept.count] : n.name;
            if (size > before) [moved addObject:name];
        }
        NSDictionary *result = @{@"moved": moved, @"size": @(size), @"refused": refused};
        dispatch_async(dispatch_get_main_queue(), ^{ done(result); });
    });
}

// On the queue: why a folder can't go as it is now, measured again just before it does, though the map says it can:
// it holds a checkout git calls unsaved, or a folder Whozmove can't look inside, that the map didn't see (made since
// it was measured). Nil for a file, or when nothing keeps it.
- (NSString *)whyNotNow:(MapNode *)n {
    if (!n.kids) return nil;
    MapNode *now = MeasureTop(n.path, n.name, [Measure new]);
    if (!now) return @"It's no longer there";
    return [self whyNotIn:now at:n.path];
}

- (NSString *)whyNotIn:(MapNode *)n at:(NSString *)path {
    if (n.repo) {
        [self.repos removeObjectForKey:path];
        NSDictionary *state = [self repoState:path];
        if (!state || [state[@"dirty"] boolValue] || [state[@"ahead"] boolValue])
            return [NSString stringWithFormat:@"Holds %@, with %@: open it to choose", n.name,
                    Unsaved(state, [self waitsForTools:path])];
    }
    for (MapNode *kid in n.kids) {
        if (!kid.kids) continue;
        if (kid.unread)
            return [NSString stringWithFormat:@"Holds %@, which Whozmove can't look inside: open it to choose", kid.name];
        NSString *why = [self whyNotIn:kid at:[path stringByAppendingPathComponent:kid.name]];
        if (why) return why;
    }
    return nil;
}

// On the queue: what's at `path` to the Trash, or in a print run, into the folder that stands for it.
- (BOOL)toTrash:(NSString *)path error:(NSError **)error {
    if (!self.standInTrash)
        return [NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:path] resultingItemURL:nil
                                                      error:error];
    [NSFileManager.defaultManager createDirectoryAtPath:self.standInTrash withIntermediateDirectories:YES attributes:nil
                                                  error:nil];
    NSString *to = [self.standInTrash stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ %@",
                                                                      NSUUID.UUID.UUIDString, path.lastPathComponent]];
    return [NSFileManager.defaultManager moveItemAtPath:path toPath:to error:error];
}

// On the queue: one part to the Trash, checked already; it leaves the map.
- (void)move:(MapNode *)n size:(long long *)size refused:(NSMutableArray *)refused {
    NSError *error = nil;
    if ([self toTrash:n.path error:&error]) {
        *size += n.size;
        [self leave:n];
        return;
    }
    [refused addObject:@{@"name": n.name ?: @"It", @"why": [@"macOS didn't move it: "
        stringByAppendingString:error.localizedDescription ?: @"no reason given"]}];
}

static BOOL Holds(MapNode *n, NSSet<MapNode *> *kept) {
    for (MapNode *kid in n.kids) if ([kept containsObject:kid] || Holds(kid, kept)) return YES;
    return NO;
}

// On the queue: what's in a folder to the Trash but what's kept, which stays with the folders it's in. A part holding
// something kept is emptied the same way; each other part is checked and moved; and what's too small to be on the
// map, each thing in the folder now that the map doesn't name, is checked as it is now and moved too.
- (void)empty:(MapNode *)n keeping:(NSSet<MapNode *> *)kept size:(long long *)size refused:(NSMutableArray *)refused {
    NSMutableSet<NSString *> *named = [NSMutableSet set];
    for (MapNode *kid in n.kids) [named addObject:kid.name];
    for (MapNode *kid in [n.kids copy]) {
        if ([kept containsObject:kid]) continue;
        if (Holds(kid, kept)) {
            [self empty:kid keeping:kept size:size refused:refused];
            continue;
        }
        NSString *why = [self whyNot:kid] ?: [self whyNotNow:kid];
        if (why) [refused addObject:@{@"name": kid.name, @"why": why}];
        else [self move:kid size:size refused:refused];
    }
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:n.path error:nil] ?: @[]) {
        if ([named containsObject:name]) continue;
        MapNode *small = [self smallPart:name in:n];
        NSString *why = small ? [self whyNot:small] : @"It's no longer there";
        if (why) {
            [refused addObject:@{@"name": name, @"why": why}];
            continue;
        }
        NSError *error = nil;
        if (![self toTrash:small.path error:&error]) {
            [refused addObject:@{@"name": name, @"why": [@"macOS didn't move it: "
                stringByAppendingString:error.localizedDescription ?: @"no reason given"]}];
            continue;
        }
        *size += small.size;
        n.restSize = MAX(0, n.restSize - small.size);
        n.restCount = MAX(0, n.restCount - 1);
        for (MapNode *each = n; each; each = each.parent) each.size -= small.size;
    }
}

// On the queue: something in a folder the map counts among its small items, as it is now: measured; a checkout if it
// holds a .git, so git is asked about it as about any other; and kept if it holds one further in, which the map
// shows once it's measured again. Nil if it's gone.
- (MapNode *)smallPart:(NSString *)name in:(MapNode *)folder {
    NSString *path = [folder.path stringByAppendingPathComponent:name];
    struct stat st;
    if (lstat(path.fileSystemRepresentation, &st) != 0) return nil;
    MapNode *small = [MapNode new];
    small.name = name;
    small.path = path;
    small.parent = folder;
    small.fileId = st.st_ino;
    if (S_ISDIR(st.st_mode)) {
        MapNode *measured = MeasureTop(path, name, [Measure new]);
        small.size = measured.size;
        small.repo = measured.repo;
        if (!measured.repo && HoldsCheckout(measured)) small.holds = @"a checkout";
        else if (HoldsUnread(measured)) small.holds = @"a folder Whozmove can't look inside";
        small.kids = [NSMutableArray array];
    } else small.size = (long long)st.st_blocks * 512;
    return small;
}

- (NSString *)whyNot:(MapNode *)n {
    if (!n || !n.parent || n.kind || !n.path) return @"It's no longer on the map: look again";
    struct stat st;
    if (lstat(n.path.fileSystemRepresentation, &st) != 0) return @"It's no longer there";
    if (st.st_ino != n.fileId || !ReachedFromHome(n.path)) return @"Something else is there now";
    MapNode *repo = RepoOf(n);
    if (repo) [self.repos removeObjectForKey:repo.path];
    for (MapNode *below in n.reposBelow) [self.repos removeObjectForKey:below.path];
    NSDictionary *lock = [self lockOf:n ignored:[self ignoredAmong:@[n]]];
    if (lock) return lock[@"says"];
    NSString *home = Home();
    if (!(Within(n.path, home) && ![n.path isEqualToString:home]) && !Within(n.path, @"/Applications"))
        return @"Outside your home folder";
    return nil;
}

- (void)leave:(MapNode *)n {
    MapNode *parent = n.parent;
    [parent.kids removeObject:n];
    for (MapNode *each = parent; each; each = each.parent) each.size -= n.size;
    NSMutableArray *gone = [NSMutableArray arrayWithObject:n];
    while (gone.count) {
        MapNode *each = gone.lastObject;
        [gone removeLastObject];
        [self.nodes removeObjectForKey:@(each.nodeId)];
        [gone addObjectsFromArray:each.kids ?: @[]];
    }
}

- (void)reveal:(NSInteger)nodeId {
    dispatch_async(self.queue, ^{
        NSString *path = self.nodes[@(nodeId)].path;
        if (!path || ![NSFileManager.defaultManager fileExistsAtPath:path]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:path]]];
        });
    });
}

#pragma mark For the tests

// Every part below the home folder, by its path within it: its size, what's counted together, whether it couldn't be
// looked inside (and has the way to allow Full Disk Access) or is a checkout, and what keeps it from going.
- (void)describe:(MapNode *)n into:(NSMutableDictionary *)out {
    NSSet *ignored = [self ignoredAmong:n.kids ?: @[]];
    for (MapNode *kid in n.kids) {
        NSString *rel = [kid.path substringFromIndex:MIN(kid.path.length, Home().length + 1)];
        NSMutableDictionary *d = [@{@"size": @(kid.size)} mutableCopy];
        if (kid.restSize || kid.restCount) d[@"small"] = [NSString stringWithFormat:@"%ld, %lld bytes",
                                                           (long)kid.restCount, kid.restSize];
        if (kid.unread) d[@"unread"] = @YES;
        if ([self allows:kid]) d[@"allow"] = @YES;
        if (kid.repo) d[@"checkout"] = @YES;
        NSDictionary *lock = [self lockOf:kid ignored:ignored];
        if (lock) d[@"lock"] = [NSString stringWithFormat:@"%@: %@", lock[@"kind"], lock[@"says"]];
        out[rel] = d;
        [self describe:kid into:out];
    }
}

@end

// As the app's first measure goes: Clean up's usual places first, then the rest, which takes them in.
Scanner *ScannerOfHome(NSDictionary<NSString *, NSString *> *busy) {
    Measure *m = [Measure new];
    Scanner *scanner = [[Scanner alloc] initWithFile:@"/dev/null"];
    scanner.usual = MeasureUsual(m);
    NSMutableSet *skipped = [NSMutableSet set];
    for (MapNode *each in scanner.usual.kids) [skipped addObject:each.path];
    m.skipped = skipped;
    MapNode *home = MeasureTop(Home(), @"home", m);
    if (!home) return nil;
    MapNode *disk = [MapNode new];
    disk.name = @"disk";
    disk.kids = [NSMutableArray arrayWithObject:home];
    home.parent = disk;
    disk.size = home.size;
    [scanner takeUsualInto:disk];
    scanner.disk = disk;
    scanner.fullDiskAccess = m.fullDiskAccess;
    scanner.busyHere = busy ?: @{};
    [scanner index];
    return scanner;
}

NSDictionary *MapOfHome(NSDictionary<NSString *, NSString *> *busy) {
    Scanner *scanner = ScannerOfHome(busy);
    MapNode *home = scanner.disk.kids.firstObject;
    if (!home) return nil;
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    out[@"(home)"] = @{@"size": @(home.size), @"small": [NSString stringWithFormat:@"%ld, %lld bytes",
                                                          (long)home.restCount, home.restSize],
                       @"lock": [[scanner lockOf:home ignored:[NSSet set]] objectForKey:@"says"] ?: NSNull.null};
    [scanner describe:home into:out];
    return out;
}
