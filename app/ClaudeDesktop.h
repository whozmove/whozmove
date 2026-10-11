// ClaudeDesktop: Claude Desktop through its links and the Accessibility API: opening a conversation, writing in
// its message box, pressing Send, and answering "Switch model?".
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>

@class DesktopConversations, PanelWindow, Row;

@interface ClaudeDesktop : NSObject
- (instancetype)initWithConversations:(DesktopConversations *)conversations window:(PanelWindow *)window;

// Opens a conversation in Claude, with its message box ready to type in.
- (void)open:(Row *)row;
// Makes sure Claude shows a conversation, in front: opened if Claude shows another one, else brought forward.
- (void)show:(Row *)row;
// Brings Claude forward.
- (void)activate;
// A new conversation in a folder, as Claude's own "new session in folder" makes.
- (void)newConversationIn:(NSString *)folder;

// Whether Whozmove may control Claude; when it may not, macOS is asked to offer the Accessibility permission.
- (BOOL)mayControl;
// Writes a command in a conversation's message box and sends it. `done` gets nil once it's sent, or why it wasn't,
// as the panel says it.
- (void)send:(NSString *)command toConversation:(NSString *)hostId done:(void (^)(NSString *why))done;
// Whether a conversation's own record (as its row last read it) says a setting is now the value picked.
- (BOOL)shows:(NSString *)value as:(NSString *)field inRecord:(NSDictionary *)record;

// "Switch model?": whether Claude would ask it for this conversation; never again, once "Don't ask again" is
// chosen; whether Claude's own box is up; and answering that box (NO if it isn't up).
- (BOOL)mayAskToSwitch:(Row *)row;
- (void)stopAskingToSwitch;
- (BOOL)showsSwitchBox;
- (BOOL)answerSwitchBox:(BOOL)switchModel dontAskAgain:(BOOL)dontAskAgain;
@end
