// Updates: whether a newer Whozmove is out, for a copy Homebrew installed (its receipt says from which tap), read from
// that tap's cask, Homebrew's copy on this Mac and GitHub's, the newer counting, against the app's own version. A
// build from a checkout never looks. It only says so: it never installs anything, and never runs brew. Looked at as
// the app opens and every 6 hours after, off the main thread, one look at a time.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@interface Updates : NSObject
// Homebrew's folder, the app's own version (Info.plist's), and whether it's a build from a checkout (its build.json).
- (instancetype)initWithPrefix:(NSString *)prefix version:(NSString *)own fromCheckout:(BOOL)checkout;
// Reading GitHub's copy of the cask: one web request, with no sign-in and nothing of yours in it; nil for no answer.
@property (copy) NSString *(^fetch)(NSURL *url);
- (void)look;
// Whether a look is under way: its print mode waits until none is.
@property (readonly) BOOL working;
// Each tick: it looks again 6 hours after the last look.
- (void)tick;
// What it found, on the main thread: {version, command}, a newer version and the command that updates to it; or
// {version, installed}, when Homebrew has put that newer one in already and this copy is still the older one (its quit
// was refused), so it's to restart; or nil (none newer, not Homebrew's, no answer, or you put this version away).
// `onFound` hears when it changes.
@property (readonly) NSDictionary *found;
@property (copy) void (^onFound)(void);
// Your × on its line: that version stays away, kept in Whozmove's folder (updates.json); a newer one shows again.
- (void)putAway:(NSString *)version;
@end

// Whether version `a` comes before `b`, part by part (0.2.10 after 0.2.9).
BOOL VersionBefore(NSString *a, NSString *b);
// The newer version out for a copy at `own`, {version, tap, command}, or {version, tap, installed} when Homebrew's
// receipt already has a newer one in, or nil, with what it found in *said, for the log.
NSDictionary *NewerVersion(NSString *prefix, NSString *own, NSString *(^fetch)(NSURL *url), NSString **said);
// `Whozmove --print-updates <case>…`, for the install module's tests: sample Homebrew folders and casks, and GitHub's
// copy from the case, for each what it finds.
int PrintUpdates(NSArray<NSString *> *cases);
