// AppleEvents: asking another app things, and telling it what to do, with Apple events of Whozmove's own rather than
// AppleScript, which may run only on the main thread. Plain helpers, any app's: each module keeps its app's own codes.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// A property of the app (`of` nil) or of one of its things, as an Apple event names it.
NSAppleEventDescriptor *AppleEventProperty(FourCharCode code, NSAppleEventDescriptor *of);
// Every element of a class in `of` (the app itself when nil), as an Apple event names them.
NSAppleEventDescriptor *AppleEventEvery(FourCharCode cls, NSAppleEventDescriptor *of);
// Asks the process `pid` for what `specifier` names, waiting `timeout` seconds at most, and never asking you anything:
// without your leave to control it (macOS asks the first time a script tells it something), there's just no answer.
// Its answer, or nil. It blocks only the thread it's on, so it can run off the main thread.
NSAppleEventDescriptor *AskQuietly(pid_t pid, NSAppleEventDescriptor *specifier, NSTimeInterval timeout);
// Asks the process `pid` the same way for a property of every element of a class in `of` (the app itself when nil):
// each as text, in their order, or nil without an answer.
NSArray<NSString *> *AskEvery(pid_t pid, FourCharCode cls, FourCharCode property, NSAppleEventDescriptor *of,
                              NSTimeInterval timeout);
// One Apple event to the process `pid`, waiting `timeout` seconds at most: its answer (the null descriptor when it
// gives none), or nil with why in `status`.
NSAppleEventDescriptor *SendAppleEvent(pid_t pid, AEEventClass eventClass, AEEventID eventId,
                                       NSAppleEventDescriptor *object, NSAppleEventDescriptor *data,
                                       NSTimeInterval timeout, OSStatus *status);
// Whether macOS lets Whozmove send `pid` Apple events: noErr, -1743 (not allowed) or, when `ask` is NO and you
// haven't been asked yet, errAEEventWouldRequireUserConsent. Asking waits for your answer.
OSStatus AutomationPermission(pid_t pid, BOOL ask);
