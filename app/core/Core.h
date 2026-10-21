// Core: the services the core gives modules, the page, the panel's window and the module registry, and the page's
// messages the core answers itself (the panel's height and size, the keyboard, the pawn's count).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import "Host.h"
#import "Agent.h"

@class Page, PanelWindow, MenuBar, Modules, Rows, Focus, Send, Row, Browser, BrowserSetup;
@protocol BrowserOwner;

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
// The host a session runs in: one that holds it as its own, else the one whose app is up its process tree, else, with
// no app there, one that says it runs the process (Host's runsProcess:); nil when that's an app no module knows.
- (id<Host>)hostOf:(Row *)row;
// The app a session's process runs in, found the same way: the first ordinary app up its process tree, else the app of
// the host that says it runs the process, while it's running; nil when there's neither.
- (NSRunningApplication *)appOf:(pid_t)pid;
// The hosts that can do what `capability` says (TypingHost, CommandHost, ConversationHost), in the modules' order.
- (NSArray *)hostsThat:(Protocol *)capability;
// Whether a row is a terminal session that has ended: no process, and no app keeps it as a conversation of its own
// (Claude Desktop's are its own). A press opens it again in a new tab, and nothing goes into it till then.
- (BOOL)hasEnded:(Row *)row;
// Whether a host's app is on this Mac. In a print run every host's is, so what it prints never depends on the Mac.
- (BOOL)hasApp:(id<Host>)host;
// The terminals new sessions start in from the panel (New Conversation's) and ended ones open again in when the one
// they ran in can't: those on this Mac that run a command in a new tab and say which tab they show, so the panel can
// tell which tab shows the session it opened, in the modules' order (Ghostty, then iTerm2). The one used is the one
// picked on New Conversation's menu while it's on this Mac, else the first; a print run follows no pick.
@property (readonly) NSArray<id<CommandHost>> *startTerminals;
@property (readonly) id<CommandHost> startTerminal;
- (void)pickStartTerminal:(NSString *)appId;
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
// Web pages that aren't the panel's own, for a module to show in the panel's window (Browser.h): a Browser of this
// setup, which tells `owner` what changes and asks it what only you can answer. Nil in a print run.
- (Browser *)browserWith:(BrowserSetup *)setup owner:(id<BrowserOwner>)owner;
// The page's messages the core itself answers, by type: the panel's size, turning it over, the keyboard, the pawn's
// count, and opening a
// session.
- (NSDictionary<NSString *, void (^)(NSDictionary *message)> *)messages;
@end
