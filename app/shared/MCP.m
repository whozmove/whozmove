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

NSString *MCPHowItFailed(NSError *error, NSInteger status, NSDictionary *answer, BOOL toolFailed, NSTimeInterval limit) {
    if (error) {
        if ([error.domain isEqualToString:NSURLErrorDomain]) switch (error.code) {
            case NSURLErrorTimedOut: return [NSString stringWithFormat:@"no answer in %.0fs", limit];
            case NSURLErrorNotConnectedToInternet: return @"no connection: this Mac is offline";
            case NSURLErrorCannotFindHost:
            case NSURLErrorDNSLookupFailed: return @"no connection: the server's name wasn't found";
            case NSURLErrorCannotConnectToHost: return @"no connection: the server didn't take it";
            case NSURLErrorNetworkConnectionLost: return @"no connection: it was lost on the way";
            case NSURLErrorSecureConnectionFailed:
            case NSURLErrorServerCertificateUntrusted:
            case NSURLErrorServerCertificateHasBadDate:
            case NSURLErrorServerCertificateHasUnknownRoot:
            case NSURLErrorServerCertificateNotYetValid: return @"no connection: macOS didn't trust its certificate";
            default: break;
        }
        return [NSString stringWithFormat:@"no connection (error %ld)", (long)error.code];
    }
    if (status != 200) return [NSString stringWithFormat:@"HTTP %ld", (long)status];
    NSNumber *code = AsNumber(AsRecord(answer[@"error"])[@"code"]);
    if (code) return [NSString stringWithFormat:@"the server's error %ld", code.longValue];
    if (!AsRecord(answer[@"result"])) return @"an answer it couldn't read";
    return toolFailed ? @"the tool said it failed" : nil;
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
// message, the HTTP status, when to try again if the server said, and how it failed, if it did (MCPHowItFailed).
- (void)send:(NSDictionary *)message
        done:(void (^)(NSDictionary *answer, NSInteger status, NSDate *retryAt, NSString *how))done {
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
        NSString *how = messageId ? MCPHowItFailed(error, http.statusCode, answer, NO,
                                                   self.session.configuration.timeoutIntervalForRequest) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (given.length) self.sessionId = given;
            done(answer, error ? 0 : http.statusCode, retryAt, how);
        });
    }] resume];
}

// What an HTTP status means for a call, when it isn't an answer.
static MCPEnd EndFor(NSInteger status) {
    return status == 401 ? MCPEndSignIn : status == 403 ? MCPEndRefused : status == 429 ? MCPEndSlowDown : MCPEndFailed;
}

- (void)start:(void (^)(MCPEnd end, NSDate *retryAt, NSString *how))done {
    if (self.started) return done(MCPEndAnswered, nil, nil);
    self.sessionId = nil;
    self.spoken = nil;
    NSDictionary *hello = @{@"jsonrpc": @"2.0", @"id": @(++self.lastId), @"method": @"initialize",
                            @"params": @{@"protocolVersion": kProtocolVersion, @"capabilities": @{},
                                         @"clientInfo": @{@"name": self.name, @"version": self.version}}};
    [self send:hello done:^(NSDictionary *answer, NSInteger status, NSDate *retryAt, NSString *how) {
        NSDictionary *result = AsRecord(answer[@"result"]);
        if (status != 200 || !result)
            return done(status == 200 ? MCPEndFailed : EndFor(status), retryAt, [@"starting: " stringByAppendingString:how ?: @"an answer it couldn't read"]);
        self.spoken = AsText(result[@"protocolVersion"]) ?: kProtocolVersion;
        self.started = YES;
        [self send:@{@"jsonrpc": @"2.0", @"method": @"notifications/initialized"}
              done:^(NSDictionary *a, NSInteger s, NSDate *r, NSString *h) {}];
        done(MCPEndAnswered, nil, nil);
    }];
}

// A request in the session, started first if need be, and once more if the server has ended the session (404).
- (void)request:(NSString *)method params:(NSDictionary *)params again:(BOOL)again
           done:(void (^)(NSDictionary *result, MCPEnd end, NSDate *retryAt, NSString *how))done {
    [self start:^(MCPEnd started, NSDate *retryAt, NSString *how) {
        if (started != MCPEndAnswered) return done(nil, started, retryAt, how);
        NSDictionary *message = @{@"jsonrpc": @"2.0", @"id": @(++self.lastId), @"method": method, @"params": params};
        [self send:message done:^(NSDictionary *answer, NSInteger status, NSDate *retry, NSString *how) {
            if (status == 404 && self.sessionId && !again) {
                [self reset];
                return [self request:method params:params again:YES done:done];
            }
            if (status == 401) [self reset];
            NSDictionary *result = AsRecord(answer[@"result"]);
            if (status == 200 && result) return done(result, MCPEndAnswered, nil, nil);
            done(nil, status == 200 ? MCPEndFailed : EndFor(status), retry, how);
        }];
    }];
}

- (void)call:(NSString *)tool arguments:(NSDictionary *)arguments done:(MCPDone)done {
    [self request:@"tools/call" params:@{@"name": tool, @"arguments": arguments ?: @{}} again:NO
             done:^(NSDictionary *result, MCPEnd end, NSDate *retryAt, NSString *how) {
        if (end != MCPEndAnswered) return done(nil, end, how, retryAt);
        BOOL failed = [AsNumber(result[@"isError"]) boolValue];
        done(MCPToolValue(result), failed ? MCPEndToolFailed : MCPEndAnswered,
             failed ? MCPHowItFailed(nil, 200, @{@"result": result}, YES, 0) : nil, nil);
    }];
}

@end
