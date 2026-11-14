// CheckoutWatch: tells when something in a checkout may have changed (a file in it, what's staged, a commit, a branch
// or GitHub's copy of one), from macOS's file system events, so git is run only for the checkouts that changed.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// Starts telling changes (the git module, as the app launches). Until then, and in a print run, which never starts it,
// no checkout is watched, so each is looked at on a timer. Main thread only.
void StartCheckoutWatch(void);
// Watches these checkouts (git roots) for `watcher`, alongside the ones other watchers asked for; the same list again
// costs nothing, and one left out stays watched for a minute, so a row missing for a moment doesn't restart anything.
// Main thread only.
void WatchCheckouts(NSString *watcher, NSSet<NSString *> *roots);
// Whether a checkout is being watched, so its changes are told: NO before it's asked for, before StartCheckoutWatch, on
// a volume that isn't this Mac's own (macOS can't tell its changes), or when macOS couldn't watch it; then it has to be
// looked at on a timer instead. Main thread only.
BOOL CheckoutWatched(NSString *root);
// How many times, since it was first watched, something may have changed in a checkout's files or what's staged
// (`CheckoutFileChanges`); in its HEAD, its own branch, GitHub's copies of the repo's branches, the local base branch,
// the packed refs or the config (`CheckoutRefChanges`); and in what its repo's checkouts keep of it
// (`CheckoutRepoChanges`: GitHub's copies, the base branch, the packed refs and the config). Each reader keeps the
// numbers it read at, taken as its read starts, and reads again once one it goes by has moved. Main thread only.
NSUInteger CheckoutFileChanges(NSString *root);
NSUInteger CheckoutRefChanges(NSString *root);
NSUInteger CheckoutRepoChanges(NSString *root);
// How long a reader leaves a checkout nothing seems to have changed in before it looks again anyway, in case an event
// was missed: half an hour at least, and up to ten minutes more, different for each checkout, so the checkouts read
// together as Whozmove starts don't all come round again at once. macOS says itself when it lost events, and then every
// checkout is read (CheckoutWatch), so this is only for a change it lost without saying, or one to a file outside the
// checkout that git reads too (your own list of files to ignore, a config file the repo's config includes).
extern const NSTimeInterval kCheckoutQuietLeast, kCheckoutQuietSpread;
NSTimeInterval CheckoutQuietEvery(NSString *root);
// When something in a checkout's files or refs last seemed to change, as macOS told it, in seconds since 1970, or 0
// before anything has. Main thread only.
NSTimeInterval CheckoutChangedAt(NSString *root);
// Whether a reader should read a checkout that has changed since its last read, `sinceChange` seconds after the latest
// change and `sinceFirstUnread` after the first it hasn't read: once nothing new has come for kCheckoutSettle seconds,
// or kCheckoutSettleMost after the first, whichever comes sooner. So a burst of edits (an agent at work) is read once
// it pauses, rather than at every look, and what a row shows still follows an edit within 10 seconds. Plain, for the
// tests.
extern const NSTimeInterval kCheckoutSettle, kCheckoutSettleMost;
BOOL CheckoutSettled(NSTimeInterval sinceChange, NSTimeInterval sinceFirstUnread);
