// HeldKeys: a hold of two keys told apart, and whether you're at the Mac's screen.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "HeldKeys.h"

const double kHeldFor = 0.25;

const CGEventFlags kHeldModifiers = kCGEventFlagMaskSecondaryFn | kCGEventFlagMaskControl | kCGEventFlagMaskAlternate
    | kCGEventFlagMaskShift | kCGEventFlagMaskCommand;

BOOL HoldLooked(Hold *hold, CGEventFlags now, uint32_t presses, double at, CGEventFlags keys) {
    CGEventFlags mods = now & kHeldModifiers, before = hold->last & kHeldModifiers;
    BOOL pressedSince = hold->looked && presses != hold->lastPresses;
    hold->last = now;
    hold->lastPresses = presses;
    hold->looked = YES;
    if (mods != keys) {
        hold->holding = hold->done = NO;
        return NO;
    }
    if (!hold->holding) {
        // Down to these from more keys, as one of a bigger shortcut's is let go, or with a key pressed since the look
        // before: not a hold of these.
        hold->holding = YES;
        hold->done = (before & ~keys) != 0 || pressedSince;
        hold->since = at;
        hold->presses = presses;
        return NO;
    }
    if (hold->done) return NO;
    if (presses != hold->presses) {
        hold->done = YES;
        return NO;
    }
    if (at - hold->since < kHeldFor) return NO;
    hold->done = YES;
    return YES;
}

BOOL OnTheScreen(void) {
    NSDictionary *session = CFBridgingRelease(CGSessionCopyCurrentDictionary());
    return [session[(__bridge NSString *)kCGSessionOnConsoleKey] boolValue]
        && ![session[@"CGSSessionScreenIsLocked"] boolValue];
}
