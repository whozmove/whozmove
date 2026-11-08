// TicketBindings: which ticket each session works on, and what the row and the session are told about it, in plain
// functions. A binding is made only by your press (Start on the card with a ticket on it, or Use It on the row), and
// kept in the panel's memory; an offer is a ticket a session asked to work on, waiting on its row for your answer; a
// move is one of its ticket's next steps the session asked for, waiting there for your Move It, or taken by itself.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Ticket.h"

// A move a session asked for (ticket-move): one of its ticket's next steps, by the id its tracker gave, with where it
// leads, the note added as it goes and the fields it sets, by their ids, and each of those as people see it (`shown`:
// its name and its value, in words). One waits on the row for your Move It while May Move Its Ticket is off; one the
// switch lets it take goes at once (`itself`). `moving` while its tracker takes it; `problem`, why it couldn't, for Try
// Again; `instead`, where the move it took the place of led; `at`, when it was asked, so a card changed since can't
// take a press meant for the one before.
@interface TicketMove : NSObject
@property (copy) NSString *stepId, *name, *note, *instead;
@property (strong) TicketState *to;
@property (copy) NSDictionary *fields;
@property (copy) NSArray<NSDictionary *> *shown;
@property (strong) NSDate *at;
@property BOOL itself, moving;
@property (strong) TrackerAnswer *problem;
@end

// One session's ticket: its tracker (by name), site and key, the address made from them, and the ticket as last read,
// with when, whether a read is under way, and why the last one didn't read it, with when to try again. Then what its
// moves left: the one asked for (`move`), what the row's card says of the last (`moved`: {to, by, at}, by `itself` or
// `you`, or {gone, at}, why there was nothing to move, until the next read), how it went, for the session to be told
// once (`told`: {moved} or {notMoved}), and the steps it marked as a person's, each with why (`stopped`, by step id).
@interface TicketBinding : NSObject
@property (copy) NSString *tracker, *site, *key, *link;
@property (strong) Ticket *ticket;
@property (strong) NSDate *readAt, *triedAt;
@property BOOL reading;
@property (strong) TrackerAnswer *problem;
@property (strong) TicketMove *move;
@property (copy) NSDictionary *moved, *told;
@property (strong) NSMutableDictionary<NSString *, NSString *> *stopped;
@end

// A ticket a session asked to work on (ticket-use), or one it had before Whozmove restarted (`again`), shown on its row
// for your Use It; `instead`, the key it works on now, when it has one. The offered ticket is read once, as it's
// offered, so the card says what it is: `ticket` once read, else `problem`, why not.
@interface TicketOffer : NSObject
@property (copy) NSString *tracker, *site, *key, *link, *instead;
@property BOOL again;
@property (strong) Ticket *ticket;
@property (strong) TrackerAnswer *problem;
@end

// A new ticket a session drafted (ticket-draft), shown on its row for your Create Ticket: its tracker and site, where
// it goes (`group`, by the id its tracker reads, and `groupKind`, what the tracker calls that, once checked), its type,
// title, description (`details`), priority and parent, as the session gave them. Its tracker is asked first what the
// group takes (`checking`, until `checked`); `creating` while it's made; `problem`, why either couldn't be done, for Try
// Again; `again`, shown in place of one before; `at`, when it was asked, so a card changed since can't take a press
// meant for the one before.
@interface TicketDraft : NSObject
@property (copy) NSString *tracker, *site, *group, *groupKind, *type, *title, *details, *priority, *parent;
@property (strong) NSDate *at;
@property BOOL checking, checked, creating, again;
// Making it failed after it was sent (its tracker didn't answer, or didn't say the key), so it may be there all the
// same: the card says to look first, and offers Create Again.
@property BOOL mayBeMade;
// Whether its tracker's sites were looked for, once, for a draft made before they were known; and the problem the
// session was last told of, so it's told once.
@property BOOL sitesLooked;
@property (strong) TrackerAnswer *toldProblem;
@property (strong) TrackerAnswer *problem;
@end

// The row's `ticket`: {bound, offer, move, draft, creating}, each only when there is one (docs/reference/rows.md); nil
// with none. The move is only one waiting for your Move It, never one the session takes by itself; `creating` is the
// tracker a session started from Create a ticket makes its new ticket in, until it has one.
NSDictionary *TicketShown(TicketBinding *bound, TicketOffer *offer, TicketDraft *draft, NSString *creating);

// What `ask-panel.sh ticket` answers, at once, from what was last read: the ticket as one line of JSON; or "waiting: …"
// while it's read or your answer is waited for (which --wait waits through); "not used: …" once you said Not Now;
// "can't now: …" when it can't be read; "refused: …" with no ticket at all. `signIn` names whose sign-in the tracker
// uses, for the words, and `declined` is the key you said Not Now to, if you did. With the ticket comes its move, if
// one was asked for: {waiting: where to} until it's taken or not, then how it went ({moved} or {notMoved: why}), which
// the module tells once.
NSString *TicketAnswer(TicketBinding *bound, TicketOffer *offer, NSString *declined, NSString *signIn);

// The longest note a move adds, and the longest why for a person's step, in characters.
extern const NSUInteger kLongestTicketNote;

// The move a session asks for, checked against its ticket as last read: `stepId` one of its next steps; what came on
// stdin (`given`) nothing, or a JSON object with a note (text, kLongestTicketNote characters at most) and fields (an
// object naming only fields that step needs, by their ids, with every one it must have). nil for anything else, with
// why in plain words, naming the fields that are wrong.
TicketMove *TicketMoveAsked(Ticket *ticket, NSString *stepId, NSString *given, NSString **why);

// Names as a sentence lists them: "a, b and c".
NSString *TicketsListed(NSArray<NSString *> *names);

// The longest title and description a new ticket may have, in characters.
extern const NSUInteger kLongestTicketTitle, kLongestTicketDescription;

// The new ticket a session drafts (ticket-draft), from what came on stdin: a JSON object with a title (one line,
// kLongestTicketTitle characters at most), where it goes (`group`, a plain id), its type, and maybe a description
// (kLongestTicketDescription characters at most), a priority, a parent's key and the site, each text. nil for anything
// else, with why in plain words. Its tracker, its site and whether the parent is one of its keys are the module's to
// check.
TicketDraft *TicketDraftAsked(NSString *given, NSString **why);

// What `ask-panel.sh ticket` answers while a session's draft waits: "waiting: …", as it's checked, shown for your
// Create Ticket, or made; or "can't now: …" when it couldn't be checked or made (or may have been made: look first),
// with why, once (`told` after that),
// then "waiting: …" for your Try Again or sign-in, so the session's --wait carries on to how it ends.
NSString *TicketDraftWaiting(TicketDraft *draft, NSString *signIn, BOOL told);

// How a draft's check ended, from its tracker's answer to what its group takes (`options`, {kind, types}): ready for
// your Create Ticket (the draft takes the type as its tracker spells it, and what it calls its group: nil returned);
// waiting on the row for your Try Again (`problem` set: nil returned); or back to the session, the "not yet: …" it's
// told returned, for a group there isn't or a type that group doesn't take.
NSString *TicketDraftChecked(TicketDraft *draft, NSDictionary *options, TrackerAnswer *answer);

// How making a new ticket ended, from its tracker's answer and the key it gave (nil for none, as the tracker reads its
// keys): made; back to the session, turned away as it was given, with the "not yet: …" it's told in *told; or waiting
// on the row (`problem` set), for Try Again when it ended before anything was made (a sign-in, an admin, a request to
// slow down, no such group), else, as it may be there all the same (`mayBeMade`), for Create Again once you've looked.
typedef NS_ENUM(NSInteger, TicketDraftEnd) {
    TicketDraftMadeIt,
    TicketDraftSentBack,
    TicketDraftWaits,
};
TicketDraftEnd TicketDraftMade(TicketDraft *draft, NSString *key, TrackerAnswer *answer, NSString **told);

// The record kept for a binding, so a later copy of the panel can offer it back ({tracker, site, key, pid,
// processStart}), and the offer read back from one, for the same process only; nil for anything else.
NSDictionary *TicketKept(TicketBinding *bound, pid_t pid, long long processStart);
TicketOffer *TicketKeptOffer(NSDictionary *kept, pid_t pid, long long processStart);
