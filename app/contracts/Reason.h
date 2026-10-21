// Reason: why keys can't go into a session right now, as the log, a card and a row's button say it. What a host and an
// agent tell the core, and the core tells the panel.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// Why keys can't go into a session right now.
typedef NS_ENUM(NSInteger, ReasonKind) {
    ReasonSessionGone,     // Claude Code's registry doesn't list the session
    ReasonWorking,         // Claude is working
    ReasonAsking,          // Claude is asking something
    ReasonRequestWaiting,  // a permission request is waiting in the panel
    ReasonOtherStatus,     // the registry gives the session another status
    ReasonOpenTwice,       // its conversation runs in another terminal too
    ReasonPaused,          // it's paused in its terminal (Ctrl+Z)
};

// A reason prints (with %@) the way the log says it; `onCard` is how the Compact card says it.
@interface Reason : NSObject
+ (instancetype)kind:(ReasonKind)kind;
+ (instancetype)status:(id)status;  // for a session that isn't idle
@property (readonly) ReasonKind kind;
@property (readonly) NSString *onCard;
@property (readonly) NSString *onButton;  // and how a row's next-step button says it
@end
