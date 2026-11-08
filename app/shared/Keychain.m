// Keychain: secrets in macOS's Keychain, or in a stand-in file while the home folder is a test's.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Keychain.h"
#import "Files.h"
#import "Log.h"
#import <Security/Security.h>

NSString *KeychainStandInPath(void) {
    return HomeIsYourOwn() ? nil : [Home() stringByAppendingPathComponent:@"keychain-stand-in.json"];
}

// The stand-in: one JSON file, {service: {account: base64}, "asks": [service], "others": [service], "builds": {service:
// build}}, written whole each time, readable only by you. "builds" is read as a service's accounts are, as a record.
static NSMutableDictionary *StandIn(void) {
    NSDictionary *kept = AsRecord(ReadJSON(KeychainStandInPath()));
    NSMutableDictionary *all = [NSMutableDictionary dictionary];
    for (NSString *service in kept) {
        if ([service isEqual:@"asks"] || [service isEqual:@"others"]) {
            if (AsList(kept[service])) all[service] = [AsList(kept[service]) mutableCopy];
            continue;
        }
        NSDictionary *accounts = AsRecord(kept[service]);
        if (accounts) all[service] = [accounts mutableCopy];
    }
    return all;
}
// The build the stand-in records for an entry this build kept afresh.
static NSString *const kStandInThisBuild = @"this build";
static BOOL KeepStandIn(NSDictionary *all) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:all options:NSJSONWritingSortedKeys error:nil];
    NSString *path = KeychainStandInPath();
    return data && [NSFileManager.defaultManager createFileAtPath:path contents:data
                                                       attributes:@{NSFilePosixPermissions: @0600}];
}

// What finds the one password kept for an account under a service.
static NSMutableDictionary *Query(NSString *service, NSString *account) {
    return [@{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
              (__bridge id)kSecAttrService: service, (__bridge id)kSecAttrAccount: account} mutableCopy];
}

void KeychainQuietly(void (^work)(void)) {
    // For the login keychain's entries, only this old call keeps macOS from asking: kSecUseAuthenticationUIFail doesn't
    // (checked on virtual Macs, macOS 15 and 26: its box came up all the same), and its replacement, an LAContext, is for
    // the newer kind of keychain. It holds for the whole app, so it's off only for `work`, put back on every path, and
    // for one at a time, on a queue of their own: none of them waits on a box.
    static dispatch_queue_t quietly;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ quietly = dispatch_queue_create("Whozmove: quiet Keychain calls", DISPATCH_QUEUE_SERIAL); });
    dispatch_sync(quietly, ^{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        Boolean allowed = true;
        SecKeychainGetUserInteractionAllowed(&allowed);
        SecKeychainSetUserInteractionAllowed(false);
        work();
        SecKeychainSetUserInteractionAllowed(allowed);
#pragma clang diagnostic pop
    });
}

// This build: its code's own hash (its cdhash, which any change to the app changes), as hex text, the way
// KeychainKeepAfresh records it in an entry's attributes. Nil when it can't be found, and then none is recorded, so the
// entry stands as another build's: a new build's, which macOS asks about, rather than one changed since.
static NSData *ThisBuild(void) {
    static NSData *build;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SecCodeRef me = NULL;
        CFDictionaryRef information = NULL;
        if (SecCodeCopySelf(kSecCSDefaultFlags, &me) == errSecSuccess)
            SecCodeCopySigningInformation(me, kSecCSDefaultFlags, &information);
        if (me) CFRelease(me);
        NSDictionary *signing = (__bridge_transfer NSDictionary *)information;
        NSData *hash = signing[(__bridge id)kSecCodeInfoUnique];
        if (![hash isKindOfClass:NSData.class] || !hash.length) return;
        NSMutableString *hex = [NSMutableString string];
        const unsigned char *bytes = hash.bytes;
        for (NSUInteger i = 0; i < hash.length; i++) [hex appendFormat:@"%02x", bytes[i]];
        build = [hex dataUsingEncoding:NSUTF8StringEncoding];
    });
    return build;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

// Whether `path` is this app: its bundle's, or its program's, with any links followed.
static BOOL IsThisApp(NSString *path) {
    NSString *given = path.stringByResolvingSymlinksInPath;
    for (NSString *mine in @[NSBundle.mainBundle.bundlePath ?: @"", NSBundle.mainBundle.executablePath ?: @""])
        if (mine.length && [given isEqualToString:mine.stringByResolvingSymlinksInPath]) return YES;
    return NO;
}

// Whether an access rule is about reading the secret (or taking it out), as opposed to changing the rule, say.
static BOOL AboutReading(SecACLRef rule) {
    NSArray *what = (__bridge_transfer NSArray *)SecACLCopyAuthorizations(rule);
    for (id kind in @[(__bridge id)kSecACLAuthorizationDecrypt, (__bridge id)kSecACLAuthorizationAny,
                      (__bridge id)kSecACLAuthorizationExportClear, (__bridge id)kSecACLAuthorizationExportWrapped])
        if ([what containsObject:kind]) return YES;
    return NO;
}

// Who the access of one kept entry lets read it: It when only this app, else Others. An entry macOS always asks about
// (no app named) lets no one in without you, so it counts as this app's.
static KeychainFound WhoReads(SecKeychainItemRef item) {
    SecAccessRef access = NULL;
    CFArrayRef list = NULL;
    OSStatus status = SecKeychainItemCopyAccess(item, &access);
    if (status == errSecSuccess) status = SecAccessCopyACLList(access, &list);
    if (access) CFRelease(access);
    NSArray *rules = (__bridge_transfer NSArray *)list;
    if (status != errSecSuccess) {
        LogProblem([NSString stringWithFormat:@"Couldn't see who may read an entry in the Keychain (%d)", (int)status]);
        return KeychainFoundFailed;
    }
    for (id rule in rules) {
        if (!AboutReading((__bridge SecACLRef)rule)) continue;
        CFArrayRef named = NULL;
        CFStringRef label = NULL;
        SecKeychainPromptSelector prompt;
        status = SecACLCopyContents((__bridge SecACLRef)rule, &named, &label, &prompt);
        if (label) CFRelease(label);
        NSArray *apps = (__bridge_transfer NSArray *)named;
        // A rule that isn't a plain list of apps can't be shown to be this app's alone.
        if (status == errSecACLNotSimple) return KeychainFoundOthers;
        if (status != errSecSuccess) {
            LogProblem([NSString stringWithFormat:@"Couldn't see who may read an entry in the Keychain (%d)", (int)status]);
            return KeychainFoundFailed;
        }
        // No list at all means every app.
        if (!apps) return KeychainFoundOthers;
        for (id app in apps) {
            CFDataRef data = NULL;
            // The app's path, as text ending in a NUL; a group, or an app that isn't this one, is another.
            status = SecTrustedApplicationCopyData((__bridge SecTrustedApplicationRef)app, &data);
            NSData *path = (__bridge_transfer NSData *)data;
            NSString *text = status == errSecSuccess && path
                ? [[NSString alloc] initWithBytes:path.bytes length:strnlen(path.bytes, path.length)
                                         encoding:NSUTF8StringEncoding] : nil;
            if (!IsThisApp(text)) return KeychainFoundOthers;
        }
    }
    return KeychainFoundIt;
}

// The look itself, for calls already inside KeychainQuietly: every entry kept for the account, and who reads each; and,
// in *thisBuild (when given), whether each one records this very build as the one that kept it. Attributes only, which
// macOS gives without asking: never the secret.
static KeychainFound Look(NSString *service, NSString *account, BOOL *thisBuild) {
    if (thisBuild) *thisBuild = NO;
    NSMutableDictionary *query = Query(service, account);
    query[(__bridge id)kSecReturnRef] = @YES;
    query[(__bridge id)kSecReturnAttributes] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitAll;
    CFTypeRef found = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &found);
    NSArray *entries = (__bridge_transfer NSArray *)found;
    if (status == errSecItemNotFound) return KeychainFoundNone;
    if (status != errSecSuccess) {
        LogProblem([NSString stringWithFormat:@"Couldn't look for %@ in the Keychain (%d)", service, (int)status]);
        return KeychainFoundFailed;
    }
    if (!entries.count) return KeychainFoundNone;
    NSData *build = ThisBuild();
    BOOL ours = build != nil;
    for (id entry in entries) {
        // Asked for its reference and its attributes, each entry comes as one record holding both.
        NSDictionary *attributes = AsRecord(entry);
        id item = attributes[(__bridge id)kSecValueRef];
        if (!item) {
            LogProblem([NSString stringWithFormat:@"Couldn't look for %@ in the Keychain (no entry given)", service]);
            return KeychainFoundFailed;
        }
        KeychainFound who = WhoReads((__bridge SecKeychainItemRef)item);
        if (who != KeychainFoundIt) return who;
        if (![attributes[(__bridge id)kSecAttrGeneric] isEqual:build]) ours = NO;
    }
    if (thisBuild) *thisBuild = ours;
    return KeychainFoundIt;
}

#pragma clang diagnostic pop

KeychainFound KeychainLook(NSString *service, NSString *account) {
    if (!service.length || !account.length) return KeychainFoundNone;
    if (KeychainStandInPath()) {
        NSMutableDictionary *all = StandIn();
        if (!AsText(all[service][account])) return KeychainFoundNone;
        return [all[@"others"] containsObject:service] ? KeychainFoundOthers : KeychainFoundIt;
    }
    __block KeychainFound who = KeychainFoundNone;
    KeychainQuietly(^{ who = Look(service, account, NULL); });
    return who;
}

BOOL KeychainHas(NSString *service, NSString *account) {
    return KeychainLook(service, account) == KeychainFoundIt;
}

// One read: with macOS allowed to ask you, or not, when it would (`quiet`). An entry other apps can read is looked at
// first and never read; one this very build kept is always read quietly, as macOS gives it without asking, so one it
// would ask about all the same was changed since, and macOS is never let ask for it.
static NSData *Read(NSString *service, NSString *account, BOOL quiet, KeychainFound *found) {
    KeychainFound none;
    if (!found) found = &none;
    *found = KeychainFoundNone;
    if (!service.length || !account.length) return nil;
    if (KeychainStandInPath()) {
        NSMutableDictionary *all = StandIn();
        NSString *kept = AsText(all[service][account]);
        if (!kept) return nil;
        if ([all[@"others"] containsObject:service]) return *found = KeychainFoundOthers, nil;
        if ([all[@"asks"] containsObject:service]) {
            if ([all[@"builds"][service] isEqual:kStandInThisBuild]) return *found = KeychainFoundChanged, nil;
            if (quiet) return *found = KeychainFoundAsks, nil;
            [all[@"asks"] removeObject:service];
            KeepStandIn(all);
        }
        *found = KeychainFoundIt;
        return [[NSData alloc] initWithBase64EncodedString:kept options:0];
    }
    NSMutableDictionary *query = Query(service, account);
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    __block KeychainFound who = KeychainFoundNone;
    __block BOOL thisBuild = NO;
    __block CFTypeRef data = NULL;
    __block OSStatus status = errSecSuccess;
    // The look never asks, so it's quiet either way, and so is the read of an entry this very build kept; the read that
    // may ask follows them, outside the quiet.
    KeychainQuietly(^{
        who = Look(service, account, &thisBuild);
        if (who == KeychainFoundIt && (quiet || thisBuild))
            status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &data);
    });
    if (who != KeychainFoundIt) return *found = who, nil;
    if (!quiet && !thisBuild) status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &data);
    if (status == errSecItemNotFound) return nil;
    if (status == errSecInteractionNotAllowed || status == errSecAuthFailed || status == errSecUserCanceled) {
        // macOS turns away a quiet read of an entry it would ask about with errSecAuthFailed (checked on a virtual Mac,
        // macOS 26: an entry another app rewrote since this build kept it). Only that counts as changed: anything else
        // says nothing about the entry. A locked keychain fails sooner, at the look, and stands as a problem.
        // This build's own entry refused for any other reason is a problem rather than one for Allow, as Allow reads
        // it the same quiet way.
        *found = !thisBuild ? KeychainFoundAsks : status == errSecAuthFailed ? KeychainFoundChanged : KeychainFoundFailed;
        if (thisBuild && status != errSecAuthFailed)
            LogProblem([NSString stringWithFormat:@"Couldn't read %@ from the Keychain (%d)", service, (int)status]);
        if (!quiet && !thisBuild)
            PanelLog(@"The Keychain didn't give %@: macOS asked, and it wasn't let (%d)", service, (int)status);
        return nil;
    }
    if (status != errSecSuccess) {
        *found = KeychainFoundFailed;
        LogProblem([NSString stringWithFormat:@"Couldn't read %@ from the Keychain (%d)", service, (int)status]);
        return nil;
    }
    *found = KeychainFoundIt;
    return (__bridge_transfer NSData *)data;
}

NSData *KeychainReadQuietly(NSString *service, NSString *account, KeychainFound *found) {
    return Read(service, account, YES, found);
}

NSData *KeychainRead(NSString *service, NSString *account, KeychainFound *found) {
    return Read(service, account, NO, found);
}

BOOL KeychainKeepAfresh(NSString *service, NSString *account, NSData *secret) {
    if (!service.length || !account.length || !secret) return NO;
    if (KeychainStandInPath()) {
        NSMutableDictionary *all = StandIn();
        all[service] = all[service] ?: [NSMutableDictionary dictionary];
        all[service][account] = [secret base64EncodedStringWithOptions:0];
        [all[@"asks"] removeObject:service];
        [all[@"others"] removeObject:service];
        all[@"builds"] = all[@"builds"] ?: [NSMutableDictionary dictionary];
        all[@"builds"][service] = kStandInThisBuild;
        return KeepStandIn(all);
    }
    // Whatever was kept goes first, as an entry changed in place keeps the access it had, which may let any app read it.
    // One that can't be cleared is left as it is, with nothing added beside it.
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)Query(service, account));
    if (status != errSecSuccess && status != errSecItemNotFound) {
        LogProblem([NSString stringWithFormat:@"Couldn't clear %@ in the Keychain (%d)", service, (int)status]);
        return NO;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    // The new entry names this build alone, so macOS gives it to no other app without asking you.
    SecTrustedApplicationRef me = NULL;
    SecAccessRef access = NULL;
    status = SecTrustedApplicationCreateFromPath(NULL, &me);
    if (status == errSecSuccess)
        status = SecAccessCreate((__bridge CFStringRef)service, (__bridge CFArrayRef)@[(__bridge id)me], &access);
    if (me) CFRelease(me);
#pragma clang diagnostic pop
    if (status == errSecSuccess) {
        NSMutableDictionary *add = Query(service, account);
        add[(__bridge id)kSecValueData] = secret;
        add[(__bridge id)kSecAttrLabel] = service;
        add[(__bridge id)kSecAttrAccess] = (__bridge id)access;
        // Which build kept it, so a read can tell an entry of this build's own that's been changed since (macOS would
        // ask for it, though it gives this build its own without asking) from a new build's, which macOS asks about.
        if (ThisBuild()) add[(__bridge id)kSecAttrGeneric] = ThisBuild();
        status = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    }
    if (access) CFRelease(access);
    if (status != errSecSuccess) {
        LogProblem([NSString stringWithFormat:@"Couldn't keep %@ in the Keychain (%d)", service, (int)status]);
        return NO;
    }
    return YES;
}

BOOL KeychainUpdateQuietly(NSString *service, NSString *account, NSData *secret) {
    if (!service.length || !account.length || !secret) return NO;
    if (KeychainStandInPath()) {
        NSMutableDictionary *all = StandIn();
        if (!AsText(all[service][account]) || [all[@"others"] containsObject:service]
            || [all[@"asks"] containsObject:service]) return NO;
        all[service][account] = [secret base64EncodedStringWithOptions:0];
        return KeepStandIn(all);
    }
    __block BOOL updated = NO;
    KeychainQuietly(^{
        // Only an entry that is this app's alone, and that this build is given without being asked.
        if (Look(service, account, NULL) != KeychainFoundIt) return;
        NSMutableDictionary *query = Query(service, account);
        query[(__bridge id)kSecReturnData] = @YES;
        query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
        CFTypeRef data = NULL;
        OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &data);
        if (data) CFRelease(data);
        if (status != errSecSuccess) return;
        status = SecItemUpdate((__bridge CFDictionaryRef)Query(service, account),
                               (__bridge CFDictionaryRef)@{(__bridge id)kSecValueData: secret});
        if (status != errSecSuccess)
            LogProblem([NSString stringWithFormat:@"Couldn't change %@ in the Keychain (%d)", service, (int)status]);
        updated = status == errSecSuccess;
    });
    return updated;
}

void KeychainForget(NSString *service, NSString *account) {
    if (!service.length || !account.length) return;
    if (KeychainStandInPath()) {
        NSMutableDictionary *all = StandIn();
        [all[service] removeObjectForKey:account];
        if (![all[service] count]) {
            [all removeObjectForKey:service];
            [all[@"builds"] removeObjectForKey:service];
        }
        KeepStandIn(all);
        return;
    }
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)Query(service, account));
    if (status != errSecSuccess && status != errSecItemNotFound)
        LogProblem([NSString stringWithFormat:@"Couldn't forget %@ in the Keychain (%d)", service, (int)status]);
}
