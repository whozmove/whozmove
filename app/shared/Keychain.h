// Keychain: a secret kept in macOS's Keychain, as a password under a service and an account, never in a file Whozmove
// writes or a log. Only the build of the app that stored it reads it back without macOS asking you first, and an entry
// that lets any other app read it, or that something else changed since this very build kept it, is never trusted, nor
// read.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// What a look or a read found: the secret; none kept; one macOS would ask you about first (it gives an entry only to the
// build of the app that kept it, so a new build asks once: Always Allow lets that build in); one kept that lets an app
// other than this one read it (open to every app, or naming another), which is never trusted; one that names this app
// alone and says this very build kept it, yet macOS won't give it without asking, so something else changed it since,
// which is never trusted either; or a problem, logged.
typedef NS_ENUM(NSInteger, KeychainFound) {
    KeychainFoundIt,
    KeychainFoundNone,
    KeychainFoundAsks,
    KeychainFoundOthers,
    KeychainFoundFailed,
    KeychainFoundChanged,
};

// Whether one is kept for `account` under `service`, and whose, from its attributes and who may read it alone, never
// its secret: It (this app's alone), None, Others (another app can read it too) or Failed. macOS never asks about it.
KeychainFound KeychainLook(NSString *service, NSString *account);
// Whether a secret is kept for `account` under `service` that only this app can read: KeychainLook says It.
BOOL KeychainHas(NSString *service, NSString *account);
// The secret, read only if macOS gives it without asking you; else nil, with why in *found. An entry other apps can read
// is not read: nil, with *found Others. One this very build kept that macOS would ask about: nil, with *found Changed.
NSData *KeychainReadQuietly(NSString *service, NSString *account, KeychainFound *found);
// The secret, with macOS asking you first if it must: only after your press, and never on the main thread, as it
// waits for your answer. Nil when there's none, or you didn't let it, or other apps can read it, with why in *found.
// An entry this very build kept is read without asking, and when macOS would ask for it all the same, macOS isn't let
// ask: nil, with *found Changed (refused for anything but that, Failed).
NSData *KeychainRead(NSString *service, NSString *account, KeychainFound *found);
// Runs `work` with macOS kept from asking about any entry, so what in it would ask fails instead (a forget of an entry
// another build kept). Not on the main thread for long: it waits only for calls that don't ask. `work` must not call
// it again.
void KeychainQuietly(void (^work)(void));
// Keeps `secret` for `account` under `service` as a new entry that names only this build, in place of every one kept
// before, whoever kept it and whatever its access was, and records which build kept it (its code's own hash, in the
// entry's attributes, which aren't secret), so a read can tell this build's entry changed from another build's.
// macOS may ask you first, so only after your press, and off the main thread. NO, with the problem logged, if it
// couldn't: an entry that couldn't be cleared is left, and nothing is added beside it.
BOOL KeychainKeepAfresh(NSString *service, NSString *account, NSData *secret);
// Changes the secret of the entry kept for `account` under `service`, and only an entry that KeychainLook calls this
// app's alone and that this build reads without macOS asking: else NO, with nothing written. The build it records
// stays as it was. Never adds one, never asks, and so may be called on any thread.
BOOL KeychainUpdateQuietly(NSString *service, NSString *account, NSData *secret);
// Forgets what's kept for `account` under `service`, if anything is. macOS may ask you first, for an entry another
// build kept, so only after your press, and off the main thread.
void KeychainForget(NSString *service, NSString *account);
// Where the secrets are kept while the home folder isn't your own (a test's throwaway home): a file of its own in that
// home, readable only by you, so a test never reads or writes your login keychain. Nil while it's your own. A service
// its "asks" list names stands for an entry macOS would ask about, until a read that may ask reads it; one its "others"
// list names, for an entry other apps can read, until it's kept afresh. Its "builds" record says which build kept each
// service's entry: "this build" once this one kept it afresh, so one its "asks" list names too stands for an entry
// something else changed since, as macOS gives this build its own entry without asking.
NSString *KeychainStandInPath(void);
