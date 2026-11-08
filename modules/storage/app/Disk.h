// Disk: how full this Mac's disk is, looked at every minute, and whether it's running low. A sample of its free space
// is kept each hour for two weeks, to say how fast it's filling, with when the line above the list was last put away.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// A size as people read it, in the units Finder uses: 18 GB, 4.4 GB, 820 MB, 12 KB.
NSString *DiskSize(double bytes);

// What's said of the disk, from what's known of it at `now` (ms since 1970): `known` is {total, free, samples: [[at,
// free]…], closed: {at, free, severe}}, sizes in bytes, the samples oldest first and the line's last × in `closed`.
// It says {free, total, used (a fraction), tone (low or severe, or null), show (whether the line shows), head and sub
// (the line's two parts), fullInDays (null while not known, or not filling), and lines (what Storage's card on the
// panel's back says under its figures)}.
NSDictionary *DiskSays(NSDictionary *known, double now);

// How long a map stays fresh, in seconds: what Clean up frees, worked out from an older one, says how old it is.
extern const NSTimeInterval kMapFreshFor;
// How long ago a time was (ms since 1970), as of `now`: "6 hours ago", as Storage's page says it (storageAgo).
NSString *DiskAgo(double at, double now);

// The line's second part once Storage is on, from what's said of the disk (`said`), what Clean up would clean as it
// starts (`cleanable`, in bytes, -1 while it isn't known), worked out from the map measured at `cleanableAt` (ms since
// 1970, 0 for none), and what it moved to the Trash that's still there (`inTrash`): first, that the space is in the
// Trash until it's emptied; then how much can be cleaned, on the nearly-out line as what to do now, with when the
// map was measured once it isn't fresh ("· measured 6 hours ago", as of `now`); with nothing to clean, to see what's using the disk (the nearly-out line
// keeps its warning); and until it's known, `said`.
NSString *DiskLineSub(NSString *said, BOOL severe, long long cleanable, double cleanableAt, long long inTrash,
                      double now);

@interface Disk : NSObject
// Looks at the disk now, off the main thread, keeps a sample if an hour has passed since the last, and calls onChange
// on the main thread with what's said of it. Its samples and its × are kept in the file at `path`.
- (instancetype)initWithFile:(NSString *)path;
- (void)look;
// The line's ×: it stays away until the disk is a tenth fuller, or runs out, or a day has passed.
- (void)closeNote;
@property (copy) void (^onChange)(NSDictionary *said);
// What was last said of the disk, or nil before its first look.
@property (readonly, copy) NSDictionary *said;
@end
