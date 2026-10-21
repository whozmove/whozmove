// DesktopNewConversation: a new conversation in Claude Desktop with your words as its first message: Claude's own link
// opens it with them in its message box (they're written in, through the Accessibility API, if they were too long for
// the link), the folder is chosen in Claude itself (its environment, or on its older screen its folder list), and Send
// is pressed once Claude has it ready, and again while the words are still there. They're never taken out of Claude's
// box.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>

@class Core, DesktopLog, DesktopMessageBox;

@interface DesktopNewConversation : NSObject
// The log says what Claude shows and starts, and the message box piece finds its boxes and Send. The panel's window
// gives the keyboard back to Claude.
- (instancetype)initWithCore:(Core *)core log:(DesktopLog *)log messageBox:(DesktopMessageBox *)messageBox;
// A new conversation in a folder with these words. `trusted`: Claude Code's record trusts the folder, so if Claude asks
// "Trust this workspace?" anyway, its button is pressed, as you've said yes already. `done` gets nil once it's sent (or
// at once with no words, for you to write them in Claude), or why it couldn't be.
- (void)startIn:(NSString *)folder words:(NSString *)words trusted:(BOOL)trusted done:(void (^)(NSString *why))done;
@end

// The link that opens a new conversation, with words for its message box when they fit (else none). It names no folder,
// as Claude loses one that comes in a link (ClaudeDesktopFacts.h): that's chosen in Claude itself.
NSURL *NewConversationLink(NSString *words);
