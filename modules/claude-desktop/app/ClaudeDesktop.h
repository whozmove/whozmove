// ClaudeDesktop: Claude Desktop, the app that keeps sessions as conversations of its own (contracts/Host.h): its
// conversations in the rows, opening one, writing in its message box and pressing Send, a new conversation with your
// words, and answering "Switch model?", through its links and the Accessibility API.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import "Module.h"
#import "Host.h"

@interface ClaudeDesktop : NSObject <Module, ConversationHost>
@end
