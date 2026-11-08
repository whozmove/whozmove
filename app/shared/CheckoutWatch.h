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
// was missed: about 5 minutes, a little different for each checkout, so they don't all come at once.
NSTimeInterval CheckoutQuietEvery(NSString *root);
