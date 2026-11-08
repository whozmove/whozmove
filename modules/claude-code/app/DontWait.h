// DontWait: the sessions you've told not to wait on you (Don't Wait on Me), for the permission hook: with it on, a
// question or a request for your OK that no one answers in kDontWaitMinutes goes by itself, turned down for now, so the
// session carries on and asks again later. A plan never goes. The switch is the core's (Allowed); this is the file
// the hook reads for each session it's on for, in Whozmove's own folder, never in the project.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Row;

// How long a request waits for an answer in a session with it on (the hook reads it from the session's file), and the
// switch's key and its line in the mode menu.
extern const NSInteger kDontWaitMinutes;
extern NSString *const kDontWaitKey;
NSString *DontWaitSays(NSInteger minutes);

// Writes the hook's file for a session, from now, or takes it away; NO if that couldn't be done (its id isn't one, or
// the file couldn't be written).
BOOL SetStopsWaiting(NSString *sessionId, BOOL on);
// How long a request waits for an answer in a session with it on, in ms, as its file says (`after`), or nil for one
// with none: the whole of the wait a request's card counts down.
NSNumber *DontWaitFor(NSString *sessionId);
// Takes away each session's file whose switch isn't kept for it (`kept`: a record of it, ended or not), as the menu
// shows the switch off, so the hook never lets its requests go. Returns the sessions whose file went.
NSArray<NSString *> *DropFilesWithoutSwitch(BOOL (^kept)(NSString *sessionId));
// How long since you last used the keyboard or the mouse, in seconds.
NSTimeInterval SecondsIdle(void);
// Whether you've used them lately: a request is held off only while you're there to answer it, so one pressed on its
// card and left there still goes.
BOOL ActiveAtTheMac(void);
// The requests held while you're in their session's tab, at the Mac and using it: Claude's own prompt there may be half
// answered, and the hook can't see it. One that goes by itself is held off from going; any is kept from a session you
// allow to answer it for you. `now` in ms; each row's `seenAt` says when you
// were last on it there (Focus); `idle`, SecondsIdle's.
NSArray<NSString *> *AsksToHold(NSArray<Row *> *rows, double now, NSTimeInterval idle);
