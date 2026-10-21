// ITerm2API: iTerm2's Python API, reached without Python: a WebSocket on its Unix socket, held open once made, through
// which text goes into one session only, past Broadcast Input (ITerm2Facts.h).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// What iTerm2 did with text sent to a session.
typedef NS_ENUM(NSInteger, ITerm2APIAnswer) {
    ITerm2APITaken,        // it went in
    ITerm2APISessionGone,  // iTerm2 has no such session now
    ITerm2APIFailed,       // no answer, or a refusal: the connection is closed
};

// The name iTerm2 is given for Whozmove's connections, which its Script Console shows.
extern NSString *const ITerm2APIClientName;

@interface ITerm2API : NSObject
// Whether a connection is open, looked at without waiting: it closes when iTerm2 quits or its API is switched off. On
// the main thread only.
@property (readonly) BOOL open;
// Connects in the background, unless a connection is open, being made, or was tried a moment ago. `cookie` gives a
// one-time cookie and key, as iTerm2's scripting says them ("<cookie> <key>"), or nil; it's asked on the main thread,
// and only once iTerm2's socket has taken the connection, as it does only while the API is on.
- (void)connectWithCookie:(NSString *(^)(void))cookie;
// Sends text into the session with that id, past Broadcast Input, and waits 2 seconds at most for iTerm2's answer. On
// the main thread only.
- (ITerm2APIAnswer)send:(NSString *)text toSession:(NSString *)sessionId;
@end

// For the tests (--print-iterm2-api): the request that opens a connection, given its cookie, its key and its
// Sec-WebSocket-Key; a binary frame as a client sends it, masked with `mask`; a send-text request with that id; and
// what a message from iTerm2 says about the request with that id (-1: it isn't its answer, a notification, say).
NSString *ITerm2APIHandshake(NSString *cookie, NSString *key, NSString *secKey);
NSData *ITerm2APIFrame(NSData *payload, uint32_t mask);
NSData *ITerm2APISendTextMessage(int64_t messageId, NSString *sessionId, NSString *text);
NSInteger ITerm2APIAnswerIn(NSData *message, int64_t messageId);
