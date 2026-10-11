// Command: one slash command sent from the panel to a session, from going in to its end; and why one can't go in.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Row;
@protocol Terminal;

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
// Where it goes in: a terminal's tab, or a Claude Desktop conversation.
@property (strong) id<Terminal> terminal;
@property (copy) NSString *tab;
@property (copy) NSString *conversation;
@property (readonly) BOOL inClaudeDesktop;
// Whether it holds the /model or /effort defaults it may overwrite (SettingsFile), until it lets them go.
@property (assign) BOOL holdsDefaults;
// Where its result will show: the session's transcript, after the length it had when the command went in.
@property (copy) NSString *transcript;
@property (assign) unsigned long long from;
// The pick as its row showed it before this command (showPickOf:), to put back if the command doesn't happen.
@property (assign) BOOL showsPick;
@property (strong) id pickBefore, pickBeforeAt;  // NSNull when there was none
@property (assign) SwitchAnswer switchAnswer;
@property (assign) BOOL switchAnswerGiven;      // passed on to Claude's box
// Why it didn't go through, as the panel says it.
@property (copy) NSString *why;
@end

// Why keys can't go into a session right now.
typedef NS_ENUM(NSInteger, ReasonKind) {
    ReasonSessionGone,     // Claude Code's registry doesn't list the session
    ReasonWorking,         // Claude is working
    ReasonAsking,          // Claude is asking something
    ReasonRequestWaiting,  // a permission request is waiting in the panel
    ReasonOtherStatus,     // the registry gives the session another status
};

// A reason prints (with %@) the way the log says it; `onCard` is how the Compact card says it.
@interface Reason : NSObject
+ (instancetype)kind:(ReasonKind)kind;
+ (instancetype)status:(id)status;  // for a session that isn't idle
@property (readonly) ReasonKind kind;
@property (readonly) NSString *onCard;
@end

// Why keys can't go into a terminal session right now, or nil when it's safe.
Reason *WhyNotTypeInto(NSString *sessionId, pid_t pid);
// The same for a Claude Desktop conversation, which can take a command when it isn't running at all.
Reason *WhyNotSendTo(Row *row);
