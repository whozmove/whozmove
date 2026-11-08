// MCP: a session with a server, its tools listed and called, over Streamable HTTP.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "MCP.h"
#import "Files.h"

// The protocol's version this speaks, which the server answers with the one it will use.
static NSString *const kProtocolVersion = @"2025-06-18";

NSDictionary *MCPMessageInEvents(NSString *events, NSNumber *messageId) {
    // Each event is lines up to a blank one; its data is every `data:` line, joined.
    for (NSString *event in [[events stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"]
                             componentsSeparatedByString:@"\n\n"]) {
        NSMutableArray *data = [NSMutableArray array];
        for (NSString *line in [event componentsSeparatedByString:@"\n"])
            if ([line hasPrefix:@"data:"]) [data addObject:[[line substringFromIndex:5]
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]];
        if (!data.count) continue;
        NSDictionary *message = AsRecord([NSJSONSerialization JSONObjectWithData:
            [[data componentsJoinedByString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil]);
        if ([message[@"id"] isEqual:messageId]) return message;
    }
    return nil;
}

id MCPToolValue(NSDictionary *result) {
    if (AsRecord(result[@"structuredContent"])) return result[@"structuredContent"];
    NSMutableArray *texts = [NSMutableArray array];
    for (NSDictionary *part in AsList(result[@"content"]))
        if ([AsText(AsRecord(part)[@"type"]) isEqualToString:@"text"] && AsText(part[@"text"])) [texts addObject:part[@"text"]];
    NSString *text = [texts componentsJoinedByString:@"\n"];
    id json = text.length ? [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding]
                                                            options:0 error:nil] : nil;
    return json ?: text;
}

@interface MCPClient ()
@property (strong) NSURL *url;
@property (strong) NSURLSession *session;
@property (copy) NSString *name, *version, *sessionId, *spoken;
@property NSInteger lastId;
@property BOOL started;
@end

@implementation MCPClient

- (instancetype)initWithURL:(NSURL *)url session:(NSURLSession *)session name:(NSString *)name version:(NSString *)version {
    if (!(self = [super init])) return nil;
    self.url = url;
    self.session = session;
    self.name = name;
    self.version = version;
    return self;
}

- (void)reset {
    self.started = NO;
    self.sessionId = nil;
    self.spoken = nil;
}

// One JSON-RPC message sent (a request when it has an id, else a notification), and its answer for that id: the
// message, the HTTP status, and when to try again if the server said.
- (void)send:(NSDictionary *)message done:(void (^)(NSDictionary *answer, NSInteger status, NSDate *retryAt))done {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json, text/event-stream" forHTTPHeaderField:@"Accept"];
    if (self.accessToken.length)
        [request setValue:[@"Bearer " stringByAppendingString:self.accessToken] forHTTPHeaderField:@"Authorization"];
    if (self.sessionId) [request setValue:self.sessionId forHTTPHeaderField:@"Mcp-Session-Id"];
    if (self.spoken) [request setValue:self.spoken forHTTPHeaderField:@"MCP-Protocol-Version"];
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:message options:0 error:nil];
    NSNumber *messageId = message[@"id"];
    [[self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        NSString *type = [http valueForHTTPHeaderField:@"Content-Type"].lowercaseString ?: @"";
        NSDictionary *answer = nil;
        if (data.length && messageId) {
            if ([type hasPrefix:@"text/event-stream"])
                answer = MCPMessageInEvents([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], messageId);
            else answer = AsRecord([NSJSONSerialization JSONObjectWithData:data options:0 error:nil]);
        }
        NSString *given = [http valueForHTTPHeaderField:@"Mcp-Session-Id"];
        double wait = [[http valueForHTTPHeaderField:@"Retry-After"] doubleValue];
        NSDate *retryAt = http.statusCode == 429 ? [NSDate dateWithTimeIntervalSinceNow:wait > 0 ? wait : 60] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (given.length) self.sessionId = given;
            done(answer, error ? 0 : http.statusCode, retryAt);
        });
    }] resume];
}

// What an HTTP status means for a call, when it isn't an answer.
static MCPEnd EndFor(NSInteger status) {
    return status == 401 ? MCPEndSignIn : status == 403 ? MCPEndRefused : status == 429 ? MCPEndSlowDown : MCPEndFailed;
}
static NSString *WhyFor(MCPEnd end) {
    return end == MCPEndSignIn ? @"The sign-in has run out: sign in again"
        : end == MCPEndRefused ? @"The service turned Whozmove away"
        : end == MCPEndSlowDown ? @"The service asked Whozmove to slow down"
        : @"Couldn't reach the service just now";
}

- (void)start:(void (^)(MCPEnd end, NSDate *retryAt))done {
    if (self.started) return done(MCPEndAnswered, nil);
    self.sessionId = nil;
    self.spoken = nil;
    NSDictionary *hello = @{@"jsonrpc": @"2.0", @"id": @(++self.lastId), @"method": @"initialize",
                            @"params": @{@"protocolVersion": kProtocolVersion, @"capabilities": @{},
                                         @"clientInfo": @{@"name": self.name, @"version": self.version}}};
    [self send:hello done:^(NSDictionary *answer, NSInteger status, NSDate *retryAt) {
        NSDictionary *result = AsRecord(answer[@"result"]);
        if (status != 200 || !result) return done(status == 200 ? MCPEndFailed : EndFor(status), retryAt);
        self.spoken = AsText(result[@"protocolVersion"]) ?: kProtocolVersion;
        self.started = YES;
        [self send:@{@"jsonrpc": @"2.0", @"method": @"notifications/initialized"}
              done:^(NSDictionary *a, NSInteger s, NSDate *r) {}];
        done(MCPEndAnswered, nil);
    }];
}

// A request in the session, started first if need be, and once more if the server has ended the session (404).
- (void)request:(NSString *)method params:(NSDictionary *)params again:(BOOL)again
           done:(void (^)(NSDictionary *result, MCPEnd end, NSDate *retryAt))done {
    [self start:^(MCPEnd started, NSDate *retryAt) {
        if (started != MCPEndAnswered) return done(nil, started, retryAt);
        NSDictionary *message = @{@"jsonrpc": @"2.0", @"id": @(++self.lastId), @"method": method, @"params": params};
        [self send:message done:^(NSDictionary *answer, NSInteger status, NSDate *retry) {
            if (status == 404 && self.sessionId && !again) {
                [self reset];
                return [self request:method params:params again:YES done:done];
            }
            if (status == 401) [self reset];
            NSDictionary *result = AsRecord(answer[@"result"]);
            if (status == 200 && result) return done(result, MCPEndAnswered, nil);
            done(nil, status == 200 ? MCPEndFailed : EndFor(status), retry);
        }];
    }];
}

- (void)call:(NSString *)tool arguments:(NSDictionary *)arguments done:(MCPDone)done {
    [self request:@"tools/call" params:@{@"name": tool, @"arguments": arguments ?: @{}} again:NO
             done:^(NSDictionary *result, MCPEnd end, NSDate *retryAt) {
        if (end != MCPEndAnswered) return done(nil, end, WhyFor(end), retryAt);
        BOOL failed = [AsNumber(result[@"isError"]) boolValue];
        done(MCPToolValue(result), failed ? MCPEndToolFailed : MCPEndAnswered,
             failed ? @"The service couldn't do that just now" : nil, nil);
    }];
}

@end
