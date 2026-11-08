// OAuth: signing in on a service's own page, with PKCE, a checked state and a one-time listener on 127.0.0.1.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "OAuth.h"
#import "Files.h"
#import "Log.h"
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>
#import <arpa/inet.h>
#import <netinet/in.h>
#import <sys/socket.h>

// How long the listener waits for the service's page to send you back.
static const NSTimeInterval kSignInWait = 10 * 60;
// The most of one request the listener reads: a browser's request line and headers.
static const NSUInteger kMostAsked = 16 * 1024;

static NSString *Base64URL(NSData *data) {
    NSString *s = [data base64EncodedStringWithOptions:0];
    s = [s stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    s = [s stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    return [s stringByReplacingOccurrencesOfString:@"=" withString:@""];
}

NSString *OAuthRandom(NSUInteger bytes) {
    NSMutableData *data = [NSMutableData dataWithLength:bytes];
    if (SecRandomCopyBytes(kSecRandomDefault, bytes, data.mutableBytes) != errSecSuccess) return nil;
    return Base64URL(data);
}

NSString *OAuthChallenge(NSString *verifier) {
    NSData *plain = [verifier dataUsingEncoding:NSASCIIStringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(plain.bytes, (CC_LONG)plain.length, digest);
    return Base64URL([NSData dataWithBytes:digest length:sizeof digest]);
}

// A form's body, each value escaped as a form wants it.
static NSData *FormBody(NSDictionary<NSString *, NSString *> *fields) {
    NSMutableCharacterSet *plain = [NSCharacterSet.alphanumericCharacterSet mutableCopy];
    [plain addCharactersInString:@"-._~"];
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *key in [fields.allKeys sortedArrayUsingSelector:@selector(compare:)])
        [parts addObject:[NSString stringWithFormat:@"%@=%@", key,
                          [fields[key] stringByAddingPercentEncodingWithAllowedCharacters:plain]]];
    return [[parts componentsJoinedByString:@"&"] dataUsingEncoding:NSUTF8StringEncoding];
}

// An https address from the metadata; anything else counts as missing, so nothing is ever sent unencrypted, but to a
// test's stand-in on 127.0.0.1 while the home folder is a test's.
static NSURL *SecureURL(id value) {
    NSURL *url = AsText(value) ? [NSURL URLWithString:value] : nil;
    if ([url.scheme isEqualToString:@"http"] && [url.host isEqualToString:@"127.0.0.1"] && !HomeIsYourOwn()) return url;
    return [url.scheme isEqualToString:@"https"] && url.host.length ? url : nil;
}

NSURL *OAuthWellKnown(NSURL *address, NSString *name) {
    NSURLComponents *at = [NSURLComponents componentsWithURL:address resolvingAgainstBaseURL:YES];
    NSString *path = [at.path isEqualToString:@"/"] ? @"" : at.path ?: @"";
    at.path = [NSString stringWithFormat:@"/.well-known/%@%@", name, path];
    at.query = nil;
    at.fragment = nil;
    return at.URL;
}

@implementation OAuthServer

+ (instancetype)serverFromMetadata:(NSDictionary *)metadata why:(NSString **)why {
    OAuthServer *server = [OAuthServer new];
    server->_authorize = SecureURL(metadata[@"authorization_endpoint"]);
    server->_token = SecureURL(metadata[@"token_endpoint"]);
    server->_registration = SecureURL(metadata[@"registration_endpoint"]);
    NSArray *methods = AsList(metadata[@"code_challenge_methods_supported"]);
    NSArray *auth = AsList(metadata[@"token_endpoint_auth_methods_supported"]);
    NSString *missing = !server.authorize || !server.token ? @"its sign-in addresses"
        : !server.registration ? @"a way for apps to register themselves"
        : ![methods containsObject:@"S256"] ? @"PKCE with S256"
        : ![auth containsObject:@"none"] ? @"sign-in for apps with no secret" : nil;
    if (missing) {
        if (why) *why = [NSString stringWithFormat:@"The service doesn't offer %@ any more", missing];
        return nil;
    }
    return server;
}

@end

@implementation OAuthTokens
@end

// The service's answer, as JSON, with its HTTP status; why in plain words when there's no answer at all.
typedef void (^Answered)(NSDictionary *json, NSInteger status, NSString *why);
static void Ask(NSURLSession *session, NSURLRequest *request, Answered done) {
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSString *why = error ? @"Couldn't reach the service just now" : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ done(AsRecord(json), status, why); });
    }] resume];
}

static NSURLRequest *JSONRequest(NSURL *url) {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    return request;
}

void OAuthDiscover(NSURLSession *session, NSURL *resource, void (^done)(OAuthServer *, NSString *)) {
    Ask(session, JSONRequest(OAuthWellKnown(resource, @"oauth-protected-resource")),
        ^(NSDictionary *page, NSInteger status, NSString *why) {
        NSURL *issuer = SecureURL(AsList(page[@"authorization_servers"]).firstObject);
        if (why || status != 200 || !issuer) return done(nil, why ?: @"The service didn't say how to sign in");
        Ask(session, JSONRequest(OAuthWellKnown(issuer, @"oauth-authorization-server")),
            ^(NSDictionary *json, NSInteger status, NSString *why) {
            if (why || status != 200 || !json) return done(nil, why ?: @"The service didn't say how to sign in");
            NSString *missing = nil;
            OAuthServer *server = [OAuthServer serverFromMetadata:json why:&missing];
            done(server, missing);
        });
    });
}

// The tokens in a token endpoint's answer, keeping the refresh token given before when it gives none.
static OAuthTokens *TokensFrom(NSDictionary *json, NSString *clientId, NSString *refresh) {
    NSString *access = AsText(json[@"access_token"]);
    if (!access.length) return nil;
    OAuthTokens *tokens = [OAuthTokens new];
    tokens.access = access;
    tokens.refresh = AsText(json[@"refresh_token"]) ?: refresh;
    tokens.clientId = clientId;
    double lasts = AsNumber(json[@"expires_in"]).doubleValue;
    tokens.expires = [NSDate dateWithTimeIntervalSinceNow:lasts > 0 ? lasts : 3600];
    return tokens;
}

static NSMutableURLRequest *TokenRequest(OAuthServer *server, NSDictionary *fields) {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:server.token];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    request.HTTPBody = FormBody(fields);
    return request;
}

void OAuthRefresh(NSURLSession *session, OAuthServer *server, NSString *clientId, NSString *refresh, NSString *resource,
                  OAuthDone done) {
    NSMutableDictionary *fields = [@{@"grant_type": @"refresh_token", @"refresh_token": refresh ?: @"",
                                     @"client_id": clientId ?: @""} mutableCopy];
    if (resource) fields[@"resource"] = resource;
    Ask(session, TokenRequest(server, fields), ^(NSDictionary *json, NSInteger status, NSString *why) {
        OAuthTokens *tokens = status == 200 ? TokensFrom(json, clientId, refresh) : nil;
        if (tokens) return done(tokens, OAuthEndSignedIn, nil);
        if (why) return done(nil, OAuthEndFailed, why);
        // A refresh token, or a client, the service no longer takes (run out, taken back in your account, or not one it
        // gave: a sign-in kept that something else replaced): only signing in again brings one. Its own refusal is any
        // answer short of slowing down or failing itself; only those are tried again later.
        BOOL again = status >= 400 && status < 500 && status != 429;
        done(nil, again ? OAuthEndSignInAgain : OAuthEndFailed,
             again ? @"The sign-in has run out: sign in again" : @"The service didn't give a new sign-in just now");
    });
}

// The page your browser shows once it's sent back: a word, and nothing more, as it's served by the app itself.
static NSData *ReturnPage(NSString *words, BOOL found) {
    NSString *body = [NSString stringWithFormat:@"<!doctype html><meta charset=\"utf-8\"><title>Whozmove</title>"
                      "<body style=\"font: 15px -apple-system, sans-serif; margin: 3em\"><p>%@</p></body>", words];
    NSData *html = [body dataUsingEncoding:NSUTF8StringEncoding];
    NSString *head = [NSString stringWithFormat:@"HTTP/1.1 %@\r\nContent-Type: text/html; charset=utf-8\r\n"
                      "Content-Length: %lu\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n",
                      found ? @"200 OK" : @"404 Not Found", (unsigned long)html.length];
    NSMutableData *all = [[head dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [all appendData:html];
    return all;
}

@interface OAuthSignIn ()
@property (strong) OAuthServer *server;
@property (copy) NSString *name, *resource, *verifier, *state, *path, *clientId;
@property (copy) NSArray<NSString *> *scopes;
@property (strong) NSURLSession *session;
@property (copy) OAuthDone done;
@property (strong) dispatch_source_t listener, timer;
@property (strong) dispatch_queue_t queue;
@property (strong, readwrite) NSURL *returnAddress;
@end

@implementation OAuthSignIn

- (instancetype)initWithServer:(OAuthServer *)server name:(NSString *)name resource:(NSString *)resource
                        scopes:(NSArray<NSString *> *)scopes session:(NSURLSession *)session {
    if (!(self = [super init])) return nil;
    self.server = server;
    self.name = name;
    self.resource = resource;
    self.scopes = scopes;
    self.session = session;
    self.queue = dispatch_queue_create("Whozmove sign-in", DISPATCH_QUEUE_SERIAL);
    return self;
}

- (void)startOpening:(void (^)(NSURL *))open done:(OAuthDone)done {
    self.done = done;
    self.verifier = OAuthRandom(48);
    self.state = OAuthRandom(24);
    self.path = [@"/whozmove-" stringByAppendingString:OAuthRandom(12) ?: @""];
    if (!self.verifier || !self.state || ![self listen]) return [self end:nil as:OAuthEndFailed
                                                                      why:@"Couldn't start signing in on this Mac"];
    // Registered for this sign-in's own address, as the listener's port is new each time.
    NSDictionary *client = @{@"client_name": self.name, @"redirect_uris": @[self.returnAddress.absoluteString],
                             @"grant_types": @[@"authorization_code", @"refresh_token"],
                             @"response_types": @[@"code"], @"token_endpoint_auth_method": @"none"};
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.server.registration];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:client options:0 error:nil];
    __weak OAuthSignIn *weak = self;
    Ask(self.session, request, ^(NSDictionary *json, NSInteger status, NSString *why) {
        OAuthSignIn *me = weak;
        if (!me || !me.done) return;
        NSString *clientId = (status == 200 || status == 201) ? AsText(json[@"client_id"]) : nil;
        if (!clientId.length) {
            // A service whose admin allows only some apps' addresses turns the registration away for this one.
            NSString *error = AsText(json[@"error"]);
            BOOL blocked = [error isEqualToString:@"invalid_redirect_uri"] || status == 403;
            return [me end:nil as:blocked ? OAuthEndBlocked : OAuthEndFailed
                       why:why ?: blocked ? @"The service's admin hasn't allowed apps on this Mac to sign in"
                                          : @"The service didn't let Whozmove register just now"];
        }
        me.clientId = clientId;
        open([me page]);
    });
}

// The service's page for you: who's asking, for what, how it comes back, and the challenge for the verifier.
- (NSURL *)page {
    NSURLComponents *page = [NSURLComponents componentsWithURL:self.server.authorize resolvingAgainstBaseURL:NO];
    NSMutableArray *items = [NSMutableArray arrayWithArray:page.queryItems ?: @[]];
    NSDictionary *fields = @{@"response_type": @"code", @"client_id": self.clientId,
                             @"redirect_uri": self.returnAddress.absoluteString, @"state": self.state,
                             @"code_challenge": OAuthChallenge(self.verifier), @"code_challenge_method": @"S256"};
    for (NSString *key in [fields.allKeys sortedArrayUsingSelector:@selector(compare:)])
        [items addObject:[NSURLQueryItem queryItemWithName:key value:fields[key]]];
    if (self.resource) [items addObject:[NSURLQueryItem queryItemWithName:@"resource" value:self.resource]];
    if (self.scopes.count)
        [items addObject:[NSURLQueryItem queryItemWithName:@"scope" value:[self.scopes componentsJoinedByString:@" "]]];
    page.queryItems = items;
    return page.URL;
}

// The listener: 127.0.0.1 only, a port macOS picks, one connection at a time, for ten minutes at most.
- (BOOL)listen {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return NO;
    struct sockaddr_in at = {.sin_len = sizeof at, .sin_family = AF_INET, .sin_port = 0};
    at.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    socklen_t length = sizeof at;
    if (bind(fd, (struct sockaddr *)&at, sizeof at) != 0 || listen(fd, 4) != 0
        || getsockname(fd, (struct sockaddr *)&at, &length) != 0) {
        close(fd);
        return NO;
    }
    self.returnAddress = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%d%@",
                                               ntohs(at.sin_port), self.path]];
    self.listener = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, self.queue);
    __weak OAuthSignIn *weak = self;
    dispatch_source_set_event_handler(self.listener, ^{
        int client = accept(fd, NULL, NULL);
        if (client >= 0) [weak take:client];
    });
    dispatch_source_set_cancel_handler(self.listener, ^{ close(fd); });
    dispatch_resume(self.listener);
    self.timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(self.timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSignInWait * NSEC_PER_SEC)),
                              DISPATCH_TIME_FOREVER, NSEC_PER_SEC);
    dispatch_source_set_event_handler(self.timer, ^{
        [weak end:nil as:OAuthEndCancelled why:@"Sign-in wasn't finished"];
    });
    dispatch_resume(self.timer);
    return YES;
}

// One request to the listener, on its queue: only its own path counts, with the state it was given; anything else is
// answered "not here" and the listener waits on.
- (void)take:(int)client {
    struct timeval wait = {.tv_sec = 5};
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &wait, sizeof wait);
    setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &(int){1}, sizeof(int));
    NSMutableData *asked = [NSMutableData data];
    char buffer[2048];
    while (asked.length < kMostAsked) {
        ssize_t n = read(client, buffer, sizeof buffer);
        if (n <= 0) break;
        [asked appendBytes:buffer length:(NSUInteger)n];
        if ([asked rangeOfData:[@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding] options:0
                         range:NSMakeRange(0, asked.length)].location != NSNotFound) break;
    }
    NSString *text = [[NSString alloc] initWithData:asked encoding:NSUTF8StringEncoding] ?: @"";
    NSArray *line = [[text componentsSeparatedByString:@"\r\n"].firstObject componentsSeparatedByString:@" "];
    NSURLComponents *at = line.count >= 2 && [line[0] isEqualToString:@"GET"]
        ? [NSURLComponents componentsWithString:[@"http://127.0.0.1" stringByAppendingString:line[1]]] : nil;
    if (![at.path isEqualToString:self.path]) {
        NSData *page = ReturnPage(@"Nothing here.", NO);
        write(client, page.bytes, page.length);
        close(client);
        return;
    }
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in at.queryItems) if (item.value) query[item.name] = item.value;
    BOOL stateRight = [query[@"state"] isEqualToString:self.state];
    NSString *code = stateRight ? query[@"code"] : nil;
    NSString *refused = AsText(query[@"error"]);
    NSData *page = ReturnPage(code ? @"Signed in. You can close this tab."
                              : @"Not signed in. You can close this tab, and try again from Whozmove.", YES);
    write(client, page.bytes, page.length);
    close(client);
    dispatch_async(dispatch_get_main_queue(), ^{
        [self stopListening];
        if (code) return [self exchange:code];
        // The page sends you back with an error when you said no, or an admin's rules said no for you.
        BOOL blocked = [refused isEqualToString:@"unauthorized_client"]
            || ([refused isEqualToString:@"access_denied"]
                && [AsText(query[@"error_description"]).lowercaseString containsString:@"admin"]);
        [self end:nil as:!stateRight ? OAuthEndFailed : blocked ? OAuthEndBlocked : OAuthEndCancelled
              why:!stateRight ? @"The sign-in came back without what Whozmove sent, so it wasn't taken"
                  : blocked ? @"The service's admin hasn't allowed apps on this Mac to sign in"
                  : @"Not signed in"];
    });
}

- (void)exchange:(NSString *)code {
    NSMutableDictionary *fields = [@{@"grant_type": @"authorization_code", @"code": code,
                                     @"redirect_uri": self.returnAddress.absoluteString, @"client_id": self.clientId,
                                     @"code_verifier": self.verifier} mutableCopy];
    if (self.resource) fields[@"resource"] = self.resource;
    __weak OAuthSignIn *weak = self;
    Ask(self.session, TokenRequest(self.server, fields), ^(NSDictionary *json, NSInteger status, NSString *why) {
        OAuthSignIn *me = weak;
        OAuthTokens *tokens = status == 200 ? TokensFrom(json, me.clientId, nil) : nil;
        [me end:tokens as:tokens ? OAuthEndSignedIn : OAuthEndFailed
            why:tokens ? nil : why ?: @"The service didn't finish signing in"];
    });
}

- (void)stopListening {
    if (self.listener) dispatch_source_cancel(self.listener);
    if (self.timer) dispatch_source_cancel(self.timer);
    self.listener = self.timer = nil;
}

- (void)end:(OAuthTokens *)tokens as:(OAuthEnd)end why:(NSString *)why {
    [self stopListening];
    OAuthDone done = self.done;
    self.done = nil;
    if (done) done(tokens, end, why);
}

- (void)cancel {
    [self end:nil as:OAuthEndCancelled why:@"Not signed in"];
}

@end
