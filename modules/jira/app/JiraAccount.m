// JiraAccount: the sign-in with Atlassian, kept in the Keychain.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "JiraAccount.h"
#import "JiraFacts.h"
#import "Files.h"
#import "Keychain.h"
#import "Log.h"
#import "OAuth.h"

// Where the sign-in is kept: one Keychain entry holding the refresh token and the client id it was given for.
static NSString *const kKeptService = @"Whozmove: Atlassian sign-in";
static NSString *const kKeptAccount = @"atlassian";
// How long before an access token runs out it's refreshed.
static const NSTimeInterval kRefreshEarly = 60;

@interface JiraAccount ()
@property (strong) NSURLSession *session;
@property (strong) OAuthServer *server;
@property (strong) OAuthSignIn *signIn;
@property (strong) OAuthTokens *tokens;  // in memory only; the refresh token and client id are kept in the Keychain
@property (assign, readwrite) TrackerSignIn state;
@property (copy, readwrite) NSString *why;
@property (strong) NSMutableArray *waiting;  // calls waiting for a refresh already on its way
// What the Keychain kept, {refresh, client, scopes}, once it's been read: read at most once a launch, and kept up to
// date. `scopes` are those its sign-in asked for, which a sign-in kept before Whozmove wrote to Jira doesn't have.
@property (copy) NSDictionary *held;
// Atlassian refused a write for this sign-in's scope, so it reads only until you sign in again.
@property (assign) BOOL refusedWrites;
// Where what may wait on macOS's box runs (Allow's read, forgetting on Sign Out): off the main thread, one at a time.
@property (strong) dispatch_queue_t keychain;
// Which sign-in this is: one more each time you sign in or out, so a refresh that was under way then is let go.
@property (assign) NSUInteger generation;
@end

// Why a new build waits for your press before it has the sign-in.
static NSString *const kAsksMac = @"Whozmove was updated, so macOS asks once before it hands over your Atlassian "
                                  @"sign-in.";
// Why a sign-in kept where other apps can read it isn't used.
static NSString *const kOthersRead = @"The sign-in kept on this Mac could be read by other apps, so Whozmove won't "
                                     @"use it.";
// Why a sign-in this build kept, that macOS won't give it without asking now, isn't used.
static NSString *const kChanged = @"The sign-in kept on this Mac was changed by another app, so Whozmove won't use "
                                  @"it.";
NSString *const kJiraSignInToWrite = @"Sign in again to let Whozmove move tickets";
NSString *const kJiraReadsOnly = @"This sign-in may only read tickets";

@implementation JiraAccount

- (instancetype)initWithSession:(NSURLSession *)session {
    if (!(self = [super init])) return nil;
    self.session = session;
    self.keychain = dispatch_queue_create("Whozmove: Atlassian sign-in", DISPATCH_QUEUE_SERIAL);
    // Only whether there's one, and whether it's ours alone: the secret is read when it's first needed, so a new build,
    // which macOS asks you about first, never asks as it starts.
    switch (KeychainLook(kKeptService, kKeptAccount)) {
        case KeychainFoundIt:
            self.state = TrackerSignedIn;
            break;
        case KeychainFoundOthers:
            [self untrusted:KeychainFoundOthers];
            break;
        default:
            self.state = TrackerSignedOut;
    }
    return self;
}

// The Keychain's entry could be read by other apps (something else made it, or changed who may read it), or it was
// changed since this build kept it (`found` Changed): it's never used, and signing in again makes a new one that names
// only this build.
- (void)untrusted:(KeychainFound)found {
    BOOL changed = found == KeychainFoundChanged;
    self.held = nil;
    self.state = TrackerSignInExpired;
    self.why = changed ? kChanged : kOthersRead;
    PanelLog(changed ? @"Jira: the sign-in kept in the Keychain was changed since this build kept it, so it isn't used"
                     : @"Jira: the sign-in kept in the Keychain can be read by other apps, so it isn't used");
}

static NSDictionary *KeptIn(NSData *data) {
    NSDictionary *kept = data ? AsRecord([NSJSONSerialization JSONObjectWithData:data options:0 error:nil]) : nil;
    return AsText(kept[@"refresh"]).length && AsText(kept[@"client"]).length ? kept : nil;
}

// What the Keychain keeps, {refresh, client, scopes}, or nil: read only if macOS gives it without asking you (*asks says when
// it would).
- (NSDictionary *)keptQuietly:(BOOL *)asks {
    if (self.held) return self.held;
    KeychainFound found;
    self.held = KeptIn(KeychainReadQuietly(kKeptService, kKeptAccount, &found));
    if (asks) *asks = found == KeychainFoundAsks;
    if (found == KeychainFoundOthers || found == KeychainFoundChanged) [self untrusted:found];
    return self.held;
}
- (BOOL)readsOnly {
    return self.refusedWrites || (self.held && ![AsList(self.held[@"scopes"]) containsObject:kJiraWriteScope]);
}
- (void)writesRefused {
    self.refusedWrites = YES;
}
- (BOOL)keepsSignIn {
    __block BOOL has = NO;
    dispatch_sync(self.keychain, ^{ has = KeychainHas(kKeptService, kKeptAccount); });
    return has;
}
// Keeps the sign-in, off the main thread. After your sign-in it's a new entry naming only this build, in place of any
// kept before (macOS may ask, for one another build kept); a refresh's is kept `quietly`, never asking, and only in an
// entry this build already reads that way: if it isn't, the new refresh token lives in memory only, and once Whozmove
// starts again the one kept has run out, so the panel says to sign in again.
- (void)keep:(OAuthTokens *)tokens quietly:(BOOL)quietly {
    // A refresh keeps the scopes its sign-in asked for; a new sign-in asked for Jira's own.
    NSArray *scopes = quietly ? AsList(self.held[@"scopes"]) : JiraScopes();
    NSMutableDictionary *held = [@{@"refresh": tokens.refresh ?: @"", @"client": tokens.clientId ?: @""} mutableCopy];
    if (scopes) held[@"scopes"] = scopes;
    self.held = held;
    NSData *data = [NSJSONSerialization dataWithJSONObject:self.held options:0 error:nil];
    dispatch_async(self.keychain, ^{
        BOOL kept = quietly ? KeychainUpdateQuietly(kKeptService, kKeptAccount, data)
                            : KeychainKeepAfresh(kKeptService, kKeptAccount, data);
        if (!kept) PanelLog(@"Jira: the new sign-in is kept in memory only: the Keychain didn't take it");
    });
}

// Your press of Allow: the sign-in, read with macOS asking you first, off the main thread, as it waits for your answer.
// What it gave is kept afresh at once, never asking again, so the entry names this build alone and says this build
// kept it: from then on, macOS asking for it means something else changed it.
- (void)allow:(void (^)(TrackerSignIn, NSString *))done {
    self.why = nil;
    dispatch_async(self.keychain, ^{
        KeychainFound found;
        NSData *data = KeychainRead(kKeptService, kKeptAccount, &found);
        NSDictionary *kept = KeptIn(data);
        __block BOOL afresh = NO;
        if (kept) KeychainQuietly(^{ afresh = KeychainKeepAfresh(kKeptService, kKeptAccount, data); });
        if (kept && !afresh)
            PanelLog(@"Jira: the sign-in macOS gave is kept in memory only: the Keychain didn't take it afresh");
        dispatch_async(dispatch_get_main_queue(), ^{
            if (kept) {
                self.held = kept;
                PanelLog(@"Jira: macOS gave this build the sign-in");
                return [self ended:TrackerSignedIn why:nil done:done];
            }
            if (found == KeychainFoundOthers || found == KeychainFoundChanged) {
                [self untrusted:found];
                return [self ended:TrackerSignInExpired why:self.why done:done];
            }
            BOOL there = KeychainHas(kKeptService, kKeptAccount);
            [self ended:there ? TrackerSignInAsksMac : TrackerSignedOut
                    why:there ? @"macOS didn't hand over the sign-in: Allow it there, or sign out and sign in again." : nil
                   done:done];
        });
    });
}

// Atlassian's sign-in addresses, read once from what it publishes.
- (void)server:(void (^)(OAuthServer *server, NSString *why))done {
    if (self.server) return done(self.server, nil);
    OAuthDiscover(self.session, JiraServer(), ^(OAuthServer *server, NSString *why) {
        if (server) self.server = server;
        done(server, why ? @"Couldn't reach Atlassian's sign-in just now" : nil);
    });
}

- (void)signInOpening:(void (^)(NSURL *))open done:(void (^)(TrackerSignIn, NSString *))done {
    [self.signIn cancel];
    self.state = TrackerSigningIn;
    self.why = nil;
    [self server:^(OAuthServer *server, NSString *why) {
        if (!server) return [self ended:TrackerSignedOut why:why done:done];
        OAuthSignIn *signIn = [[OAuthSignIn alloc] initWithServer:server name:@"Whozmove" resource:JiraResource()
                                                           scopes:JiraScopes() session:self.session];
        self.signIn = signIn;
        [signIn startOpening:open done:^(OAuthTokens *tokens, OAuthEnd end, NSString *why) {
            if (self.signIn != signIn) return;
            self.signIn = nil;
            if (tokens) {
                self.generation++;
                self.tokens = tokens;
                self.refusedWrites = NO;
                [self keep:tokens quietly:NO];
                PanelLog(@"Jira: signed in with Atlassian");
                return [self ended:TrackerSignedIn why:nil done:done];
            }
            PanelLog(@"Jira: not signed in (%ld)", (long)end);
            if (end == OAuthEndBlocked) return [self ended:TrackerSignInBlocked why:JiraBlockedWords() done:done];
            // Cancelled, or not finished: a sign-in kept from before still stands.
            BOOL kept = self.held || KeychainHas(kKeptService, kKeptAccount);
            [self ended:kept ? TrackerSignedIn : TrackerSignedOut why:kept ? nil : why done:done];
        }];
    }];
}

- (void)ended:(TrackerSignIn)state why:(NSString *)why done:(void (^)(TrackerSignIn, NSString *))done {
    self.state = state;
    self.why = why;
    if (done) done(state, why);
}

- (void)cancelSignIn {
    [self.signIn cancel];
    self.signIn = nil;
    if (self.state == TrackerSigningIn)
        self.state = KeychainHas(kKeptService, kKeptAccount) ? TrackerSignedIn : TrackerSignedOut;
}

- (void)signOut {
    [self cancelSignIn];
    // Off the main thread: kept by another build, macOS asks before it lets this one forget it.
    dispatch_async(self.keychain, ^{ KeychainForget(kKeptService, kKeptAccount); });
    self.generation++;
    self.tokens = nil;
    self.held = nil;
    self.refusedWrites = NO;
    self.state = TrackerSignedOut;
    self.why = nil;
    PanelLog(@"Jira: signed out");
}

- (void)blocked {
    self.state = TrackerSignInBlocked;
    self.why = JiraBlockedWords();
}

- (void)tokenRefused {
    self.tokens.expires = NSDate.distantPast;
}

- (void)token:(void (^)(NSString *, TrackerAnswer *))done {
    if (self.state == TrackerSignInBlocked)
        return done(nil, [TrackerAnswer end:TrackerEndBlocked why:self.why]);
    if (self.tokens.access && self.tokens.expires.timeIntervalSinceNow > kRefreshEarly)
        return done(self.tokens.access, [TrackerAnswer done]);
    if (self.state == TrackerSignInAsksMac)
        return done(nil, [TrackerAnswer end:TrackerEndAsksMac why:kAsksMac]);
    if (self.state == TrackerSignedOut || self.state == TrackerSignInExpired || self.state == TrackerSigningIn)
        return done(nil, [TrackerAnswer end:TrackerEndSignIn why:self.state == TrackerSignInExpired ? self.why
                                                                 : @"You aren't signed in with Atlassian"]);
    BOOL asks = NO;
    NSDictionary *kept = [self keptQuietly:&asks];
    if (asks) {
        self.state = TrackerSignInAsksMac;
        self.why = kAsksMac;
        PanelLog(@"Jira: macOS asks before it gives this build the sign-in");
        return done(nil, [TrackerAnswer end:TrackerEndAsksMac why:kAsksMac]);
    }
    if (self.state == TrackerSignInExpired) return done(nil, [TrackerAnswer end:TrackerEndSignIn why:self.why]);
    if (!kept) {
        self.state = self.state == TrackerSignInExpired ? TrackerSignInExpired : TrackerSignedOut;
        return done(nil, [TrackerAnswer end:TrackerEndSignIn why:@"You aren't signed in with Atlassian"]);
    }
    // One refresh at a time: calls made meanwhile wait for its token.
    if (self.waiting) return [self.waiting addObject:[done copy]];
    self.waiting = [NSMutableArray arrayWithObject:[done copy]];
    NSUInteger generation = self.generation;
    [self server:^(OAuthServer *server, NSString *why) {
        if (!server) return [self answerWaiting:nil answer:[TrackerAnswer end:TrackerEndFailed why:why]];
        OAuthRefresh(self.session, server, kept[@"client"], kept[@"refresh"], JiraResource(),
                     ^(OAuthTokens *tokens, OAuthEnd end, NSString *why) {
            // Signed out, or in again, since it began: what it brought is let go, and the calls get what's there now.
            if (self.generation != generation)
                return [self answerWaiting:self.tokens.access answer:self.tokens.access ? [TrackerAnswer done]
                                          : [TrackerAnswer end:TrackerEndSignIn why:@"You aren't signed in with Atlassian"]];
            if (tokens) {
                self.tokens = tokens;
                // Atlassian gives a new refresh token each time, and the old one stops working: keep the new one.
                [self keep:tokens quietly:YES];
                self.state = TrackerSignedIn;
                return [self answerWaiting:tokens.access answer:[TrackerAnswer done]];
            }
            if (end == OAuthEndSignInAgain) {
                dispatch_async(self.keychain, ^{ KeychainQuietly(^{ KeychainForget(kKeptService, kKeptAccount); }); });
                self.held = nil;
                self.state = TrackerSignInExpired;
                self.why = @"The sign-in has run out.";
                PanelLog(@"Jira: the sign-in has run out");
                return [self answerWaiting:nil answer:[TrackerAnswer end:TrackerEndSignIn why:self.why]];
            }
            [self answerWaiting:nil answer:[TrackerAnswer end:TrackerEndFailed why:@"Couldn't reach Atlassian just now"]];
        });
    }];
}

- (void)answerWaiting:(NSString *)token answer:(TrackerAnswer *)answer {
    NSArray *waiting = self.waiting;
    self.waiting = nil;
    for (void (^done)(NSString *, TrackerAnswer *) in waiting) done(token, answer);
}

@end
