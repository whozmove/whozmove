// Tracker: a ticket tracker Whozmove works with (Jira; Linear and Asana later), the same way for each. A tracker is a
// module that adopts Tracker; the module that gives sessions tickets finds the trackers through the core and talks to
// them only through this, so it never names one, and a tracker's facts (its addresses, its tools, its key's shape)
// stay in its own module. Every step a ticket can take comes from its tracker, for that ticket, each time.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Ticket.h"

// How a tracker's sign-in stands: not signed in, waiting for you on its page in your browser, signed in (to one site or
// more), turned away by an admin, run out (sign in again), or kept where macOS asks you once before it gives it to
// this build of Whozmove (signIn: then asks it, as your press of Allow).
typedef NS_ENUM(NSInteger, TrackerSignIn) {
    TrackerSignedOut,
    TrackerSigningIn,
    TrackerSignedIn,
    TrackerSignInBlocked,
    TrackerSignInExpired,
    TrackerSignInAsksMac,
};

typedef void (^TicketsDone)(NSArray<Ticket *> *tickets, TrackerAnswer *answer);
typedef void (^TicketDone)(Ticket *ticket, TrackerAnswer *answer);

// Each `done` runs on the main thread; the work runs off it.
@protocol Tracker <NSObject>
// Its name as people see it ("Jira"), and whose sign-in it uses ("Atlassian").
@property (readonly) NSString *trackerName;
@property (readonly) NSString *signInName;
// How its sign-in stands, the sites it's signed in to, and why it stands so when that isn't signed in (in plain words).
@property (readonly) TrackerSignIn signInState;
@property (readonly) NSArray<NSString *> *sites;
// The sites it's signed in to, found first when they aren't known yet (as after Whozmove starts), then `done`.
- (void)findSites:(void (^)(NSArray<NSString *> *sites))done;
@property (readonly) NSString *signInWhy;
// What to ask an admin who has kept apps from signing in, in words to send them (Copy What to Ask).
@property (readonly) NSString *adminAsk;
// Signing in on its own page in your browser (or, while macOS asks first, asking it), and ending that, or signing out
// (forgetting what it kept).
- (void)signIn:(void (^)(TrackerSignIn state, NSString *why))done;
- (void)cancelSignIn;
- (void)signOut;
// Plain functions: the key in `text` when it's one of this tracker's keys or links (a link names its site, in *site),
// else nil; and a ticket's address, made from its site and key.
- (NSString *)keyIn:(NSString *)text site:(NSString **)site;
- (NSString *)linkFor:(NSString *)key site:(NSString *)site;
// The tickets you can see with these words in them (a key finds that one), across every board you're on.
- (void)search:(NSString *)words done:(TicketsDone)done;
// One ticket, now: where it stands, its parent, its groups and its next steps, with the fields each needs.
- (void)read:(NSString *)key site:(NSString *)site done:(TicketDone)done;
// One of its next steps, by the id it gave, with a note added as it goes and the fields it needs, each by its id with a
// value as TicketField describes (never the tracker's own shape); the ticket as it stands after. TrackerStepGone when
// the step isn't one of the ticket's now; TrackerEndRefused when the tracker turns the move away as it is (a field to
// fill in on the ticket first, or a move that isn't yours), with what it said, if it did, as `trackerSays`.
- (void)take:(NSString *)stepId of:(NSString *)key site:(NSString *)site note:(NSString *)note
      fields:(NSDictionary *)fields done:(TicketDone)done;
// A note on the ticket, as a comment.
- (void)addNote:(NSString *)note to:(NSString *)key site:(NSString *)site done:(void (^)(TrackerAnswer *answer))done;
// What a new ticket can be in `group`: {group, kind (what the tracker calls a group: project, team, board), types};
// TrackerEndNotFound when there's no such group you can make tickets in. And making one from a draft ({group, type,
// title, description, priority, parent}): the ticket as made, read; once it's made, always with its key and site, as
// done, even when it couldn't be read just then, so it's never made twice. TrackerEndRefused when the tracker turns
// the draft away as given; any end but those that stop before anything is made (a sign-in, macOS asking first, an
// admin, a request to slow down, no such group) counts as one that may have been made all the same.
- (void)newTicketOptions:(NSString *)group site:(NSString *)site
                    done:(void (^)(NSDictionary *options, TrackerAnswer *answer))done;
- (void)create:(NSDictionary *)draft site:(NSString *)site done:(TicketDone)done;
@optional
// The fields a ticket like this one (its project, its type) takes one option of from a list, each with its options
// and their ids (TicketField's optionIds), so the ticket's own values (Ticket's `values`, from a read) can be matched
// to them: empty for none, nil with why when they couldn't be read.
- (void)optionFieldsOf:(Ticket *)ticket done:(void (^)(NSArray<TicketField *> *fields, TrackerAnswer *answer))done;
@end
