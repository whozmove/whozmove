// AgentMessages: the messages an agent's sessions send each other, as the agent records them, and whether each reached
// the session it was for. An agent that records them adopts it beside Agent, and a module that shows them finds it with
// the core's agentsThat:. KeptMessages, beside it, is what a module that keeps messages itself offers the agent, so the
// agent never reads another module's words.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Agent.h"

// How a message stands, each of these words: arrived (it's in the receiving session's conversation; one held and then
// let in is arrived too), held (it waits in the receiving session's tab for the user to let it in), denied (turned
// down there), expired (held until it expired, unread), dropped (the agent didn't deliver it), failed (no session
// listened at its address) or sent (sent, and not seen anywhere since).
extern NSArray<NSString *> *const AgentMessageDeliveries;
// The most of a message's words an agent hands on; the rest is cut, and the message says so (`cut`).
extern const NSUInteger AgentMessageMostText;

// One message between two sessions. The agent makes it; everyone else only reads it.
@interface AgentMessage : NSObject
// The agent's own id for it, the same on both sides.
@property (copy) NSString *messageId;
// Who sent it: its session's id, its name as the agent shows it (or nil), and the address it was sent from.
@property (copy) NSString *fromSession, *fromName, *fromAddress;
// Whom it was for, the same way. `toSession` is nil when it never arrived and its address names no session the agent
// knows.
@property (copy) NSString *toSession, *toName, *toAddress;
// When it was sent, in ms since 1970.
@property double sentAt;
// Its words as sent, AgentMessageMostText characters at most, and whether it was cut there.
@property (copy) NSString *text;
@property BOOL cut;
// How it stands (one of AgentMessageDeliveries) and since when, in ms since 1970.
@property (copy) NSString *delivery;
@property double deliveryAt;
// For a held one: whether the receiving session's tab can ask the user to let it in (a terminal's can; another app's
// or a background session's may not, so there it waits until it expires).
@property BOOL canAsk;
@end

@protocol AgentMessages <Agent>
// The messages sent from `since` (ms since 1970) that were added, or whose delivery changed, after `change` (a count
// `changes` gave; 0 for every one), oldest first, and the count they're as of. How far back is the reader's to say: the
// agent reads its sessions' records from `since` once, the first time, and later calls cost only what's new. `then` is
// called on the agent's own queue, never the main thread.
- (void)messagesAfter:(double)since change:(NSUInteger)change
                 then:(void (^)(NSArray<AgentMessage *> *messages, NSUInteger now))then;
// A count that goes up whenever a message is added or its delivery changes, so a reader asks only then. Read on the
// main thread.
@property (readonly) NSUInteger changes;
// Where a message to that session goes now, as the agent addresses it ("uds:…"), or nil when it isn't running.
- (NSString *)addressOfSession:(NSString *)sessionId;
@end

// What a module that keeps messages itself offers (the inbox, which keeps each message before the line that tells the
// receiver about it is sent): the core finds it with moduleThat:. The agent asks it before it makes anything of a
// message, such as a held one being the user's move, and never reads the module's words.
@protocol KeptMessages <NSObject>
// Whether `message` only tells its receiver of words this module keeps, and will see read: YES, and holding it asks
// nothing of the user.
- (BOOL)keeps:(AgentMessage *)message;
@end
