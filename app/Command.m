// Command: one slash command sent from the panel to a session, from going in to its end; and why one can't go in.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Command.h"
#import "Row.h"
#import "Files.h"
#import "Asks.h"
#import "Upstream.h"

@implementation Command

- (instancetype)initWithText:(NSString *)text field:(NSString *)field value:(NSString *)value
                      forRow:(Row *)row {
    if (!(self = [super init])) return nil;
    _text = [text copy];
    _field = [field copy];
    _value = [value copy];
    _sessionId = [row.sessionId copy];
    _pid = row.pid;
    _stage = CommandGoingIn;
    return self;
}

- (BOOL)ended {
    return self.stage == CommandDone || self.stage == CommandAbandoned;
}

- (BOOL)inClaudeDesktop {
    return self.conversation != nil;
}

@end

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
        default: return [NSString stringWithFormat:@"session is %@", _status ?: @"not idle"];
    }
}

- (NSString *)onCard {
    switch (self.kind) {
        case ReasonWorking: return @"Claude is working: compact it when it's done";
        case ReasonAsking:
        case ReasonRequestWaiting: return @"Claude is waiting for your answer";
        default: return @"This session isn't running";
    }
}

@end

// Keys go into a terminal session only while it sits at its prompt: idle by Claude Code's own registry, read now
// (a row is up to a second old), with no permission request pending. In a permission prompt Enter would answer
// yes, and Shift+Tab would allow all edits for the rest of the session.
Reason *WhyNotTypeInto(NSString *sessionId, pid_t pid) {
    NSDictionary *live = ReadJSON(ClaudeDir([kClaudeCodeRegistry
        stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.json", pid]]));
    if (![live isKindOfClass:NSDictionary.class] || ![live[@"sessionId"] isEqual:sessionId])
        return [Reason kind:ReasonSessionGone];
    if (![live[@"status"] isEqual:@"idle"]) return [Reason status:live[@"status"]];
    if (PendingAsks()[sessionId]) return [Reason kind:ReasonRequestWaiting];
    return nil;
}

// A Claude Desktop conversation gets a command only while it sits idle, when it's running at all (one that isn't
// is opened first). While it works, the command would go in as a message; while it waits, Claude is asking
// something in that conversation.
Reason *WhyNotSendTo(Row *row) {
    return row.pid > 0 ? WhyNotTypeInto(row.sessionId, row.pid) : nil;
}
