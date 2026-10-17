// Core: the services the core gives modules, the page, the panel's window and the module registry, and the page's
// messages the core answers itself (the panel's height and size, the keyboard, the pawn's count).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import "Host.h"
#import "Agent.h"

@class Page, PanelWindow, MenuBar, Modules, Rows, Focus, Send, Row;

@interface Core : NSObject
// For the app, once its page, window and menu bar are made; then its modules are found and made.
- (instancetype)initWithPage:(Page *)page window:(PanelWindow *)window menuBar:(MenuBar *)menuBar;
// For a print run (the tests): no page, window or menu bar, and modules only set up their data.
+ (instancetype)forPrinting;
@property (readonly) Page *page;
@property (readonly) PanelWindow *window;
@property (readonly) MenuBar *menuBar;
@property (readonly) BOOL printing;
@property (readonly) Modules *modules;
// The rows the panel shows: read, phase by phase, and sent (Rows).
@property (readonly) Rows *rows;
// The session you're on, and opening a session (Focus).
@property (readonly) Focus *focus;
// Words into a session, through its host and its agent, and why they can't go in now (Send).
@property (readonly) Send *send;
// The hosts sessions run in (the modules that adopt Host), in the modules' order.
@property (readonly) NSArray<id<Host>> *hosts;
// The host with this app id, or nil.
- (id<Host>)hostFor:(NSString *)appId;
// The host that holds a session as its own (a conversation of Claude Desktop's), or nil.
- (id<Host>)hostHolding:(Row *)row;
// The host a session runs in: one that holds it as its own, else the one whose app owns its process; nil when that's an
// app no module knows.
- (id<Host>)hostOf:(Row *)row;
// The hosts that can do what `capability` says (TypingHost, CommandHost, ConversationHost), in the modules' order.
- (NSArray *)hostsThat:(Protocol *)capability;
// The agents that run sessions (the modules that adopt Agent), in the modules' order.
@property (readonly) NSArray<id<Agent>> *agents;
// The agent that runs a session. Every session listed is Claude Code's for now, the one agent there is; another would
// come with a way to tell its rows apart.
- (id<Agent>)agentOf:(Row *)row;
// The agents that can do what `capability` says (AgentWork, AgentCommands, …), in the modules' order.
- (NSArray *)agentsThat:(Protocol *)capability;
// The marks every agent puts on the commands its sessions run (Agent's environmentMarks), to take off a command that's
// yours; nil with no agent to say, so nothing that must be yours runs before they're known.
@property (readonly) NSArray<NSString *> *agentMarks;
// The page's messages the core itself answers, by type: the panel's size, the keyboard, the pawn's count, and opening a
// session.
- (NSDictionary<NSString *, void (^)(NSDictionary *message)> *)messages;
@end
