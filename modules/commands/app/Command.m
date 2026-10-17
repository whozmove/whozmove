// Command: one slash command sent from the panel to a session, from going in to its end.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Command.h"
#import "Row.h"

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

@end
