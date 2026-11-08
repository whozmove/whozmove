// AgentMessages: how a message between sessions can stand, and one message as an agent records it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "AgentMessages.h"

NSArray<NSString *> *const AgentMessageDeliveries =
    @[@"arrived", @"held", @"denied", @"expired", @"dropped", @"failed", @"sent"];

const NSUInteger AgentMessageMostText = 8000;

@implementation AgentMessage
@end
