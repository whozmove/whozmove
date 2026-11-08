// JiraAccount: Whozmove's sign-in with Atlassian, for Jira: signing in on Atlassian's own page in your browser
// (shared/OAuth), the refresh token and the client id Whozmove registered as kept in the Keychain only, the access token
// only in memory, refreshed before it runs out, and never logged.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Tracker.h"

// Why a call that writes to Jira isn't sent while the sign-in reads only (JiraAccount's readsOnly), as an answer says
// it, above the Sign In Again it comes with; and the line Jira's page on the panel's back says it with.
extern NSString *const kJiraReadsOnly;
extern NSString *const kJiraSignInToWrite;

@interface JiraAccount : NSObject
- (instancetype)initWithSession:(NSURLSession *)session;
// How the sign-in stands, and why when it isn't signed in.
@property (readonly) TrackerSignIn state;
@property (readonly, copy) NSString *why;
// Signs in: Atlassian's page is handed to `open`, for your browser; `done` once you're back, or it ended without.
- (void)signInOpening:(void (^)(NSURL *page))open done:(void (^)(TrackerSignIn state, NSString *why))done;
// While macOS asks before it gives this build the sign-in (TrackerSignInAsksMac): your press of Allow, which asks it.
- (void)allow:(void (^)(TrackerSignIn state, NSString *why))done;
- (void)cancelSignIn;
// Forgets the sign-in: the Keychain's entry, and the tokens in memory.
- (void)signOut;
// An access token to call Atlassian with, refreshed first when it's run out or about to; nil with the answer saying
// why (sign in, or couldn't refresh now). `done` on the main thread.
- (void)token:(void (^)(NSString *token, TrackerAnswer *answer))done;
// Atlassian turned the token away (401): the next call refreshes it first, and a refresh that's turned away too means
// signing in again.
- (void)tokenRefused;
// Whether the Keychain holds a sign-in of Whozmove's own to stay signed in with (a refresh token and the client id,
// readable by no other app), never what it is.
@property (readonly) BOOL keepsSignIn;
// Atlassian turned Whozmove away (its admin's rules): the sign-in stands as blocked until you sign in again.
- (void)blocked;
// Whether the sign-in it holds reads only: one kept before Whozmove asked to write (the scopes kept with it lack Jira's
// write scope), or one Atlassian refused a write for its scope. Known once the sign-in has been read; signing in again
// ends it.
@property (readonly) BOOL readsOnly;
// Atlassian refused a write for the sign-in's scope: it reads only until you sign in again.
- (void)writesRefused;
@end
