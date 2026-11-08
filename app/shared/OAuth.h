// OAuth: signing in on a service's own page in your browser, for an app that can't keep a secret. OAuth 2.1: the app
// registers itself with the service (dynamic registration), the code is proven with PKCE (S256 only, never plain), a
// random `state` is checked on its way back, and the way back to the app is a one-time listener on 127.0.0.1 alone,
// which takes one request on a path of its own and closes after it, or after ten minutes. It knows no service: every
// address comes from what the service publishes about itself: the resource's page (RFC 9728) names its sign-in
// service, whose own page (RFC 8414) gives the rest.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// How a sign-in or a refresh ended, when it didn't give tokens: you closed it, the service's admin turned this kind of
// sign-in away, the service wants you to sign in again (a refresh token it no longer takes), or anything else (the
// network, the service's own answer), each with its why in plain words.
typedef NS_ENUM(NSInteger, OAuthEnd) {
    OAuthEndSignedIn,
    OAuthEndCancelled,
    OAuthEndBlocked,
    OAuthEndSignInAgain,
    OAuthEndFailed,
};

// A service's addresses for signing in, from its published metadata, checked for what this needs: a registration
// address, S256, and an app with no secret (`none`). Nil, with why, when it hasn't them.
@interface OAuthServer : NSObject
+ (instancetype)serverFromMetadata:(NSDictionary *)metadata why:(NSString **)why;
@property (readonly) NSURL *authorize, *token, *registration;
@end

// What a sign-in or a refresh gives: the access token (kept only in memory by whoever asked), when it runs out, the
// refresh token (kept in the Keychain by whoever asked), and the client id the app registered as, which a refresh needs.
@interface OAuthTokens : NSObject
@property (copy) NSString *access, *refresh, *clientId;
@property (strong) NSDate *expires;
@end

typedef void (^OAuthDone)(OAuthTokens *tokens, OAuthEnd end, NSString *why);

// Finds how to sign in for `resource` (an address tokens are for): its page at /.well-known/oauth-protected-resource
// names its sign-in service, whose page at /.well-known/oauth-authorization-server gives its addresses. Each address
// must be https, but for 127.0.0.1 while the home folder is a test's. `done` on the main thread.
void OAuthDiscover(NSURLSession *session, NSURL *resource, void (^done)(OAuthServer *server, NSString *why));
// Plain function, for the tests: where a well-known page is for an address (RFC 8414's and RFC 9728's way: the
// well-known path goes before the address's own path).
NSURL *OAuthWellKnown(NSURL *address, NSString *name);

// One sign-in: started once, ended once (tokens, or why not), on the main thread.
@interface OAuthSignIn : NSObject
// `name` is what the service's page calls the app; `resource`, the address the tokens are for (RFC 8707), or nil;
// `scopes`, nil for the service's own.
- (instancetype)initWithServer:(OAuthServer *)server name:(NSString *)name resource:(NSString *)resource
                        scopes:(NSArray<NSString *> *)scopes session:(NSURLSession *)session;
// Registers, starts the listener, and hands `open` the service's page for you, in your browser; `done` once the page has
// sent you back, or it ended without.
- (void)startOpening:(void (^)(NSURL *page))open done:(OAuthDone)done;
// Ends it now, as cancelled, closing the listener.
- (void)cancel;
// For the tests: where the listener waits, once started (http://127.0.0.1:<port>/<path>).
@property (readonly) NSURL *returnAddress;
@end

// A new access token for a refresh token. The service may give a new refresh token too, which then takes the old one's
// place; the caller keeps whichever comes back.
void OAuthRefresh(NSURLSession *session, OAuthServer *server, NSString *clientId, NSString *refresh, NSString *resource,
                  OAuthDone done);

// Plain functions, for the tests: a random token of `bytes` random bytes, base64url without padding, and the S256
// challenge for a verifier (RFC 7636).
NSString *OAuthRandom(NSUInteger bytes);
NSString *OAuthChallenge(NSString *verifier);
