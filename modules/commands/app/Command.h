// Command: one slash command sent from the panel to a session, from going in to its end.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Agent.h"

@class Row;
@protocol TypingHost, ConversationHost;

// Where a command is in its life.
typedef NS_ENUM(NSInteger, CommandStage) {
    CommandAsking,     // waiting on "Switch model?", asked in the panel before the command goes in
    CommandGoingIn,    // being typed into its tab, or written in Claude Desktop's message box
    CommandWaiting,    // in, and waiting for its result
    CommandDone,       // its result came
    CommandAbandoned,  // it didn't go through, or no result came in time
};

// The answer to "Switch model?" given in the panel, for Claude's own box if it asks.
typedef NS_ENUM(NSInteger, SwitchAnswer) {
    SwitchUnanswered,
    SwitchCancel,
    SwitchYes,
    SwitchYesDontAskAgain,
};

@interface Command : NSObject
- (instancetype)initWithText:(NSString *)text field:(NSString *)field value:(NSString *)value
                      forRow:(Row *)row;
@property (readonly, copy) NSString *text;   // what goes in: "/model claude-opus-5-5", "/plan", "/compact …"
@property (readonly, copy) NSString *field;  // model, effort, mode or compact
@property (readonly, copy) NSString *value;  // the pick, or the compaction's focus
@property (readonly, copy) NSString *sessionId;
@property (readonly) pid_t pid;
@property (assign) CommandStage stage;
@property (readonly) BOOL ended;              // done or abandoned
// Where it goes in: a terminal's tab, or a conversation in the app that keeps it (Claude Desktop), by that app's id
// for it.
@property (strong) id<TypingHost> terminal;
@property (copy) NSString *tab;
@property (strong) id<ConversationHost> conversationHost;
@property (copy) NSString *conversation;
// The session's agent: the command's words are its, and so are its result's.
@property (strong) id<AgentCommands, AgentPrompt> agent;
// Whether it holds the /model or /effort defaults it may overwrite (the agent's holdDefaults:), until it lets them go.
@property (assign) BOOL holdsDefaults;
// Where its result will be written, marked as it went in (the agent's markResultsOf:), or nil when there's nowhere.
@property (strong) id resultsMark;
// The pick as its row showed it before this command (showPickOf:), to put back if the command doesn't happen.
@property (assign) BOOL showsPick;
@property (strong) id pickBefore, pickBeforeAt;  // NSNull when there was none
@property (assign) SwitchAnswer switchAnswer;
@property (assign) BOOL switchAnswerGiven;      // passed on to Claude's box, or to its agent's hook
@property (assign) BOOL askedInPanel;           // its agent's hook asked "Switch model?" in the panel
@property (assign) BOOL hookAsks;               // its session's hook asks "Switch model?" in the panel
// Why it didn't go through, as the panel says it.
@property (copy) NSString *why;
@property (copy) NSString *way;  // the words of a button past its terminal's refusal (TypingHost's wayPastIn:), if any
@end
