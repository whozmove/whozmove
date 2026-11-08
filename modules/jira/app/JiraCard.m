// JiraCard: Jira's page on the panel's back, for each way the sign-in stands.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "JiraCard.h"
#import "JiraAccount.h"

// Said under every state but signed out: what goes to Atlassian, and what stays.
static NSString *const kWhatGoes = @"What you search for and the tickets you give conversations are read from Jira, "
                                   @"as you, and their moves, with their notes, are made there as you. The sign-in "
                                   @"stays in this Mac's Keychain.";

static NSDictionary *Action(NSString *action, NSString *title, BOOL main) {
    return main ? @{@"id": action, @"title": title, @"main": @YES} : @{@"id": action, @"title": title};
}

NSDictionary *JiraCard(TrackerSignIn state, NSArray<NSString *> *sites, NSString *why, BOOL copied, BOOL readsOnly) {
    NSDictionary *copy = Action(@"copyAsk", copied ? @"Copied" : @"Copy What to Ask", NO);
    switch (state) {
        case TrackerSigningIn:
            return @{@"figure": @"Signing in…",
                     @"lines": @[@"Waiting for Atlassian's page in your browser…",
                                 @"If that page says your admin has blocked this, they can allow it once, for everyone."],
                     @"actions": @[Action(@"cancel", @"Cancel", NO), copy]};
        case TrackerSignedIn: {
            // Its sites are found the first time something needs them, as Whozmove starts without asking Atlassian.
            NSString *where = !sites.count ? @"To your Jira sites, found as you first look for a ticket."
                : sites.count == 1 ? [@"To " stringByAppendingString:sites[0]]
                : [NSString stringWithFormat:@"To %lu sites: %@", (unsigned long)sites.count,
                   [sites componentsJoinedByString:@", "]];
            // A sign-in that reads only still reads; signing in again asks for the write scope too.
            if (readsOnly)
                return @{@"figure": @"Signed in",
                         @"lines": @[where, [kJiraSignInToWrite stringByAppendingString:@"."], kWhatGoes],
                         @"actions": @[Action(@"signIn", @"Sign In Again", YES), Action(@"signOut", @"Sign Out", NO)]};
            return @{@"figure": @"Signed in", @"lines": @[where, kWhatGoes],
                     @"actions": @[Action(@"signOut", @"Sign Out", NO)]};
        }
        case TrackerSignInBlocked:
            return @{@"figure": @"Not allowed yet",
                     @"lines": @[why ?: @"Your Jira admin hasn't let apps sign in from this Mac yet.",
                                 copied ? @"Copied: paste it to your Jira admin." : @"Copy what to ask them, and send it."],
                     @"actions": @[Action(@"copyAsk", copied ? @"Copied" : @"Copy What to Ask", YES),
                                   Action(@"signIn", @"Try Again", NO)]};
        case TrackerSignInExpired:
            return @{@"figure": @"Sign in again",
                     @"lines": @[why ?: @"The sign-in has run out.", kWhatGoes],
                     @"actions": @[Action(@"signIn", @"Sign In Again", YES)]};
        case TrackerSignInAsksMac:
            return @{@"figure": @"Allow it once",
                     @"lines": @[why ?: @"Whozmove was updated, so macOS asks once before it hands over your Atlassian "
                                        @"sign-in.",
                                 @"Press Allow, then Always Allow in macOS's box: it asks once for each new build."],
                     @"actions": @[Action(@"signIn", @"Allow", YES), Action(@"signOut", @"Sign Out", NO)]};
        case TrackerSignedOut:
            break;
    }
    NSMutableArray *lines = [NSMutableArray arrayWithObject:
        @"Sign in with Atlassian once, and you can give a conversation a Jira ticket from the new conversation card."];
    if (why.length) [lines insertObject:why atIndex:0];
    return @{@"figure": @"Not signed in", @"lines": lines,
             @"actions": @[Action(@"signIn", @"Sign In with Atlassian", YES)]};
}
