// Reason: why keys can't go into a session right now, said three ways.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Reason.h"

@implementation Reason {
    id _status;
}

+ (instancetype)kind:(ReasonKind)kind {
    Reason *reason = [self new];
    reason->_kind = kind;
    return reason;
}

+ (instancetype)status:(id)status {
    Reason *reason = [self kind:[status isEqual:@"busy"] ? ReasonWorking
                              : [status isEqual:@"waiting"] ? ReasonAsking : ReasonOtherStatus];
    reason->_status = status;
    return reason;
}

- (NSString *)description {
    switch (self.kind) {
        case ReasonSessionGone: return @"session not found";
        case ReasonRequestWaiting: return @"a request is waiting for an answer";
        case ReasonOpenTwice: return @"session is open more than once";
        case ReasonPaused: return @"session is paused";
        default: return [NSString stringWithFormat:@"session is %@", _status ?: @"not idle"];
    }
}

- (NSString *)onCard {
    switch (self.kind) {
        case ReasonWorking: return @"Claude is working: compact it when it's done";
        case ReasonAsking:
        case ReasonRequestWaiting: return @"Claude is waiting for your answer";
        case ReasonOpenTwice: return @"It's open more than once: close all but one first";
        case ReasonPaused: return @"It's paused in its terminal: bring it back with fg first";
        default: return @"This session isn't running";
    }
}

- (NSString *)onButton {
    return self.kind == ReasonWorking ? @"Claude is working: ask again when it's done" : self.onCard;
}

@end
