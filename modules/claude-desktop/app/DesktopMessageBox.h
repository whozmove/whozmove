// DesktopMessageBox: a conversation's message box in Claude Desktop: finding it, writing a command in it and sending
// it, and putting the caret in it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>

@class DesktopLog;

@interface DesktopMessageBox : NSObject
// The log says which conversation Claude shows: only that one has a message box.
- (instancetype)initWithLog:(DesktopLog *)log;
// Claude's message boxes ("Prompt" text areas) in its windows now.
- (NSArray *)promptBoxes;
// Writes a command in a conversation's message box and sends it. `done` gets nil once it's sent, or why it wasn't, as
// the panel says it.
- (void)send:(NSString *)command toConversation:(NSString *)hostId done:(void (^)(NSString *why))done;
// Once Claude shows a conversation opened from its row, its message box gets the focus, so typing can start straight
// away.
- (void)focusBoxFor:(NSString *)hostId tries:(int)tries;
@end

// The composer's own Submit beside a message box, one that can be pressed now (none, or more than one, when it can't be
// told).
NSArray *DesktopSendButtons(id box);
// What's written in the message box, as panel.log says it: a slash command by its first word (only one shaped like
// a command, "/" then up to 31 small letters and dashes), other words, a path or a slash-led token among them, only as
// "words", each with its length, never the words themselves, which for /compact hold the focus you wrote and for a
// message what you typed: "/compact (57 characters)", "words (12 characters)".
NSString *DesktopWordsLogged(NSString *text);
