// SessionsModule: Sessions, on each host's page on the panel's back (Ghostty's, iTerm2's, Terminal's, Claude's): every
// conversation the agent keeps on this Mac, by project, where those you tick go to the Trash, each on its own, ended
// first while it's open, with Undo, and Put Back from In the Trash. The agent says what each is (AgentConversations),
// a host which it keeps itself (keptConversations: deleted there, never here), and Trashed where each file went.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Module.h"

@interface SessionsModule : NSObject <Module>
@end
