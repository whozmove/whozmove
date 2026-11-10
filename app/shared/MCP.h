// MCP: a small client for a server that speaks the Model Context Protocol over HTTP (Streamable HTTP), for an app that
// calls a service's tools itself: it starts a session with the server, lists its tools and calls one, each a JSON-RPC
// request whose answer comes back whole or as a stream of events. It knows no server: the address, the token and the
// tools' names are its caller's.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// How a call ended: answered (the tool's result, which may still say the tool failed), the server wants a sign-in (no
// token, or one it no longer takes), it refused (not allowed, for you or from here), it asked to slow down (with when
// to try again), or it couldn't be reached or answered something this doesn't read.
typedef NS_ENUM(NSInteger, MCPEnd) {
    MCPEndAnswered,
    MCPEndToolFailed,
    MCPEndSignIn,
    MCPEndRefused,
    MCPEndSlowDown,
    MCPEndFailed,
};

// A tool's result: its structured content when it gives it, else its text, read as JSON when it is JSON; and its text,
// whole, as it came. `retryAt` is when the server said to try again, after a slow-down. `why`, when it isn't
// answered or the tool failed, says how, in this client's own words (MCPHowItFailed), never the server's text, which
// may hold what a tool read, so it can go into a log.
typedef void (^MCPDone)(id result, MCPEnd end, NSString *why, NSDate *retryAt);

@interface MCPClient : NSObject
- (instancetype)initWithURL:(NSURL *)url session:(NSURLSession *)session name:(NSString *)name version:(NSString *)version;
// The access token sent with each request, as `Authorization: Bearer`; set by whoever signed in.
@property (copy) NSString *accessToken;
// Calls `tool` with `arguments`, starting the server's session first when there's none (or it has ended); `done` on the
// main thread.
- (void)call:(NSString *)tool arguments:(NSDictionary *)arguments done:(MCPDone)done;
// Forgets the server's session, as after signing out.
- (void)reset;
@end

// Plain functions, for the tests: the JSON-RPC message with `id` in an answer that came as a stream of server-sent
// events, or nil; and a tool result's value, as `done` gives it.
NSDictionary *MCPMessageInEvents(NSString *events, NSNumber *messageId);
id MCPToolValue(NSDictionary *result);
// How a request failed, in this client's own words and numbers, never the server's: "no answer in 30s" (`limit`, the
// session's time for a request), no connection and why, as macOS names its error ("no connection: the server's name
// wasn't found"), "HTTP 502", "the server's error -32603" (a JSON-RPC error's code), "an answer it couldn't read", or,
// for a tool's result that says it failed, "the tool said it failed". Nil when it was answered.
NSString *MCPHowItFailed(NSError *error, NSInteger status, NSDictionary *answer, BOOL toolFailed, NSTimeInterval limit);
