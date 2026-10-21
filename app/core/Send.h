// Send: words into a session, through the app it runs in (its host) and the agent that runs it: typed into its terminal
// tab while keeping your draft, or written in its conversation's message box; and why they can't go in now, as the
// panel says it. What the panel's menus, cards and steps share.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Host.h"
#import "Agent.h"

@class Core, Row, Reason, Send;

// Where words for a session would go, as a menu, a card or a step words why they can't go in now. Each answer is found
// only when the wording first asks for it, in the order it asks (a terminal's tab is looked for only once it's needed).
@protocol Reach <NSObject>
// The session is a conversation an app keeps as its own (Claude Desktop's), and Whozmove may control that app.
@property (readonly) BOOL desktop;
@property (readonly) BOOL mayControl;
// Its first message is sent: it has a transcript.
@property (readonly) BOOL started;
// It ran in a terminal and has ended: nothing goes in until it's opened again from its row.
@property (readonly) BOOL ended;
// Its conversation runs in another process as well, not paused (the row's alsoOpen); and one of those runs in a
// terminal while this one does too, where a key for one could land in the other's tab, so nothing goes in.
@property (readonly) BOOL openElsewhere;
@property (readonly) BOOL openTwice;
// Else the terminal it runs in, by name, if the panel can type into it (nil when it can't), and the terminals it can
// type into, by name; whether the session's tab there is found, and whether it's certainly its.
@property (readonly, copy) NSString *terminal;
@property (readonly, copy) NSString *terminals;
@property (readonly) BOOL hasTab;
@property (readonly) BOOL unique;
// The terminal's own reason keys can't go into that tab now, or why it found none, as the panel says it, or nil
// (TypingHost's whyNotTypeIn:).
@property (readonly, copy) NSString *tabWhyNot;
// What a button for the terminal's way past that reason says, when it has one the panel can take (TypingHost's
// wayPastIn:), or nil.
@property (readonly, copy) NSString *wayPast;
// A change from the panel is still going into it (the row's goingIn, or its switchAsk): nothing more goes in until
// it's done, as a key meant for the next command could answer what Claude asks about that one.
@property (readonly) BOOL changing;
// Why keys can't go into it now, or nil.
@property (readonly) Reason *whyNotType;
@end

// A row's reach as the app finds it: from the hosts and the session's agent, each once, when the wording first asks for
// it. What it found is kept for the words that then go in.
@interface SessionReach : NSObject <Reach>
- (instancetype)initWithRow:(Row *)row send:(Send *)send;
@property (readonly) id<ConversationHost> conversations;  // the app that keeps the session as a conversation, or nil
@property (readonly) id<TypingHost> typing;               // else the terminal it runs in, if the panel can type into it
@property (readonly) NSString *tab;                       // and its tab there, or nil
@end

@interface Send : NSObject
- (instancetype)initWithCore:(Core *)core;
// A session's reach, found as it's asked.
- (SessionReach *)reachOf:(Row *)row;
// The agent that runs a session, if words can be put into its prompt; the terminal it runs in, if it's one the panel
// can type into; the app that keeps it as a conversation of its own (Claude Desktop), or nil; and the terminals the
// panel can type into, by name ("Ghostty or iTerm2").
- (id<AgentPrompt>)agentOf:(Row *)row;
- (id<TypingHost>)terminalOf:(Row *)row;
- (id<ConversationHost>)conversationHostOf:(Row *)row;
@property (readonly) NSString *terminalNames;
// Whether a session ran in a terminal and has ended (the core's hasEnded:, which a press on its row goes by too).
- (BOOL)hasEnded:(Row *)row;
// The session's agent asked in words, as you'd type them, while it's idle: one of a row's next steps. The row says
// it's asking, or why they can't go in (stepNote).
- (void)ask:(NSString *)words row:(Row *)row;
// A press on the button past a terminal's reason (WayPast), on a menu, a card or a step's note, `{sessionId}`: the
// terminal takes it, if it's still that reason, and the row says how it went, or what's left to do.
- (void)takeWayPast:(NSDictionary *)msg;
@end

// Why no words can be typed into the session's tab: it has ended, there's no terminal the panel can type into, its tab
// isn't found, its conversation is open in another terminal too, another tab fits as well, or the terminal has a reason
// of its own. `here` and `there` end the sentences ("can be changed here", "change it there").
NSString *WhyNoTab(id<Reach> reach, NSString *here, NSString *there);
// The terminal's own reason keys can't go into a tab now, or nil: what the last check before a key goes in asks, and
// each key typed after it, as a terminal that refused one refuses the rest.
Reason *WhyTerminalRefuses(id<TypingHost> terminal, NSString *tab);
// What a button beside `why` says, when `why` is the terminal's own reason and it has a way past it the panel can take
// (the reach's wayPast), else nil: what a menu, a card or a step's note offers, so you're never left with only a reason.
NSString *WayPast(id<Reach> reach, NSString *why);
// Why nothing more goes into a session while a change from the panel is still going in, as the panel says it.
extern NSString *const kStillChanging;
// Why its agent can't be asked in words now, as the row's note says it, or nil.
NSString *WhyNoAsk(id<Reach> reach);
// Why a command can't go into a Claude Desktop conversation now, or nil: one that runs takes it only while it sits
// idle, by what its agent says, and one that doesn't run can take one at any time (it's opened first).
Reason *WhyNotSendTo(id<AgentPrompt> agent, Row *row);
