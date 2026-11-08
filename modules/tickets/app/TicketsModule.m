// TicketsModule: tickets for sessions, from any tracker (contracts/Tracker.h), never naming one. A session is given one
// ticket by your press (Start on the new conversation card with the ticket on it, or Use It on its row), and works it
// by the ticket's own next steps, parent and groups, which it reads with `ask-panel.sh ticket`; its row shows the
// ticket. Reads go to the ticket's tracker when it's given, on each ask, when its card on the row opens, and every five
// minutes while the session runs, never sooner than its tracker asks; a ticket a session is offered is read once, as it
// is offered, for the card on its row. A session moves its ticket only by one of the next steps last read, by your Move
// It on its row, or by itself while you've turned on May Move Its Ticket for it. A session makes a new ticket only by
// your Create Ticket on its row, once it has drafted one and its tracker has said where it can go; the new ticket is
// then its own.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <AppKit/AppKit.h>
#import "Module.h"
#import "Allowed.h"
#import "Core.h"
#import "Page.h"
#import "Rows.h"
#import "Row.h"
#import "Files.h"
#import "Links.h"
#import "Log.h"
#import "Processes.h"
#import "Text.h"
#import "Tracker.h"
#import "TicketBindings.h"
#import "TicketsModule.h"

// How often a bound ticket is read again while its session runs, and how soon after a read an ask or a look at its
// card reads it again.
static const NSTimeInterval kReadEvery = 5 * 60, kReadAgainAfter = 60, kLookAgainAfter = 30;
// The longest key, link or search the page or a session may send.
static const NSUInteger kLongestText = 2000;
// May Move Its Ticket, at the foot of a session's mode menu.
static NSString *const kMoveTicket = @"moveTicket";

@interface TicketsModule () <BackgroundWaits>
// Each session's ticket, its offer waiting on the row, and the key you said Not Now to, by session id.
@property (strong) NSMutableDictionary<NSString *, TicketBinding *> *bound;
@property (strong) NSMutableDictionary<NSString *, TicketOffer *> *offers;
@property (strong) NSMutableDictionary<NSString *, NSString *> *declined;
// Each session's new ticket waiting for your Create Ticket, and how the last one went, for it to be told once
// ("created: …" or "not yet: …"); and the tracker and site a start from Create a ticket makes its new one in, until it
// has a ticket ({tracker, site}).
@property (strong) NSMutableDictionary<NSString *, TicketDraft *> *drafts;
@property (strong) NSMutableDictionary<NSString *, NSString *> *draftTold;
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *creating;
// What a copy of the panel before this one kept, by session id, offered back once that session's row is listed.
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *kept;
// The sessions whose binding changed and isn't kept yet: written as their rows are next listed, with their process.
@property (strong) NSMutableSet<NSString *> *unkept;
// The sessions seen ended, whose offers and kept file have gone.
@property (strong) NSMutableSet<NSString *> *ended;
// Where bindings are kept (AppDir/tickets), nil until launch or a print run says.
@property (copy) NSString *keptFolder;
// The trackers' sign-ins as the page was last told, so it's told again only when they change.
@property (copy) NSArray *shownTrackers;
@end

@implementation TicketsModule

+ (NSString *)moduleName { return @"tickets"; }

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    _core = core;
    _bound = [NSMutableDictionary dictionary];
    _offers = [NSMutableDictionary dictionary];
    _declined = [NSMutableDictionary dictionary];
    _drafts = [NSMutableDictionary dictionary];
    _draftTold = [NSMutableDictionary dictionary];
    _creating = [NSMutableDictionary dictionary];
    _kept = [NSMutableDictionary dictionary];
    _unkept = [NSMutableSet set];
    _ended = [NSMutableSet set];
    return self;
}

- (void)launch {
    [self keepIn:AppDir(@"tickets")];
}

// Bindings are kept in `folder`, one file a session, only you able to read them; what's there is read once, to offer.
- (void)keepIn:(NSString *)folder {
    self.keptFolder = folder;
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES
                                             attributes:@{NSFilePosixPermissions: @0700} error:nil];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil]) {
        NSString *sessionId = [name hasSuffix:@".json"] ? name.stringByDeletingPathExtension : nil;
        NSDictionary *record = IsPlainId(sessionId, 64) ? AsRecord(ReadJSON([folder stringByAppendingPathComponent:name])) : nil;
        if (record) self.kept[sessionId] = record;
    }
}

#pragma mark Trackers

- (NSArray<id<Tracker>> *)trackers {
    return self.givenTrackers ?: [self.core modulesThat:@protocol(Tracker)];
}
- (id<Tracker>)tracker:(NSString *)name {
    for (id<Tracker> tracker in self.trackers)
        if ([tracker.trackerName isEqual:name]) return tracker;
    return nil;
}

// The ticket some text names, from the tracker whose key or link it is: {tracker, site, key}, the site the link's, else
// the one the tracker is signed in to when it's one, else the one `near` has (the session's own ticket's), if any.
- (NSDictionary *)ticketIn:(NSString *)text near:(TicketBinding *)near {
    if (text.length > kLongestText) return nil;
    for (id<Tracker> tracker in self.trackers) {
        NSString *site = nil, *key = [tracker keyIn:text site:&site];
        if (!key) continue;
        if (!site && [near.tracker isEqual:tracker.trackerName]) site = near.site;
        if (!site && tracker.sites.count == 1) site = tracker.sites.firstObject;
        return @{@"tracker": tracker.trackerName, @"key": key, @"site": site ?: @""};
    }
    return nil;
}

static NSString *SignInWord(TrackerSignIn state) {
    switch (state) {
        case TrackerSignedOut: return @"out";
        case TrackerSigningIn: return @"signing";
        case TrackerSignedIn: return @"in";
        case TrackerSignInBlocked: return @"blocked";
        case TrackerSignInExpired: return @"expired";
        case TrackerSignInAsksMac: return @"allow";
    }
    return @"out";
}

// How each tracker's sign-in stands, for the card's list.
- (NSArray *)trackersShown {
    NSMutableArray *shown = [NSMutableArray array];
    for (id<Tracker> tracker in self.trackers)
        [shown addObject:@{@"name": tracker.trackerName ?: @"", @"signInName": tracker.signInName ?: @"",
                           @"signIn": SignInWord(tracker.signInState), @"sites": tracker.sites ?: @[],
                           @"why": tracker.signInWhy ?: @""}];
    return shown;
}
- (void)tellTrackers:(BOOL)always {
    NSArray *shown = [self trackersShown];
    if (!always && [shown isEqual:self.shownTrackers]) return;
    // A tracker signed in again (or allowed, after an update): its tickets that couldn't be read are read now.
    for (NSDictionary *tracker in shown) {
        if (![tracker[@"signIn"] isEqual:@"in"]) continue;
        BOOL was = NO;
        for (NSDictionary *before in self.shownTrackers)
            if ([before[@"name"] isEqual:tracker[@"name"]]) was = [before[@"signIn"] isEqual:@"in"];
        if (was) continue;
        for (NSString *sessionId in self.bound.allKeys) {
            TicketBinding *binding = self.bound[sessionId];
            if (![binding.tracker isEqual:tracker[@"name"]]) continue;
            if (binding.problem) [self read:sessionId always:YES];
            // A move the sign-in stopped is offered again as it was asked, for Move It.
            TrackerEnd stopped = binding.move.problem.end;
            if (stopped == TrackerEndSignIn || stopped == TrackerEndAsksMac) binding.move.problem = nil;
        }
        // A new ticket the sign-in stopped is checked again, or offered again for Create Ticket.
        for (NSString *sessionId in self.drafts.allKeys) {
            TicketDraft *draft = self.drafts[sessionId];
            TrackerEnd stopped = draft.problem.end;
            if (![draft.tracker isEqual:tracker[@"name"]] || !draft.problem
                || (stopped != TrackerEndSignIn && stopped != TrackerEndAsksMac))
                continue;
            if (draft.checked) draft.problem = nil;
            else [self check:sessionId];
        }
    }
    self.shownTrackers = shown;
    [self.core.page call:@"setTicketTrackers" with:@[shown]];
}

#pragma mark Binding and reading

// Binds a session to a ticket, by your press: the one it had goes, and the ticket is read, unless it was just read
// (`read`, a ticket just made).
- (void)bind:(NSString *)sessionId to:(NSDictionary *)ticket why:(NSString *)why {
    [self bind:sessionId to:ticket why:why read:nil];
}
- (void)bind:(NSString *)sessionId to:(NSDictionary *)ticket why:(NSString *)why read:(Ticket *)read {
    id<Tracker> tracker = [self tracker:AsText(ticket[@"tracker"])];
    NSString *key = AsText(ticket[@"key"]), *site = AsText(ticket[@"site"]);
    if (!tracker || !key.length || !IsPlainId(sessionId, 64)) return;
    TicketBinding *binding = [TicketBinding new];
    binding.tracker = tracker.trackerName;
    binding.key = key;
    binding.site = site.length ? site : nil;
    binding.link = binding.site ? [tracker linkFor:key site:binding.site] : nil;
    self.bound[sessionId] = binding;
    [self.offers removeObjectForKey:sessionId];
    [self.declined removeObjectForKey:sessionId];
    [self.creating removeObjectForKey:sessionId];
    PanelLog(@"%@ works on %@ %@ now (%@)", sessionId, binding.tracker, key, why);
    [self.unkept addObject:sessionId];
    if (read.state && [read.key isEqual:key]) {
        [self took:read for:binding];
        binding.triedAt = NSDate.date;
    } else [self read:sessionId always:YES];
}

// Reads a session's ticket again, unless it's being read, or was read just now (`always` reads it all the same), or its
// tracker asked to wait.
- (void)read:(NSString *)sessionId always:(BOOL)always {
    [self read:sessionId after:always ? 0 : kReadAgainAfter ignoringWait:NO];
}
- (void)read:(NSString *)sessionId after:(NSTimeInterval)after ignoringWait:(BOOL)now {
    TicketBinding *binding = self.bound[sessionId];
    id<Tracker> tracker = [self tracker:binding.tracker];
    if (!binding || !tracker || binding.reading) return;
    // Counted from the last try, however it went: a ticket that can't be read is tried again on the same schedule as
    // one that can, never sooner.
    if (after > 0 && binding.triedAt && -binding.triedAt.timeIntervalSinceNow < after) return;
    if (!now && binding.problem.retryAt && binding.problem.retryAt.timeIntervalSinceNow > 0) return;
    if (!binding.site) {
        binding.problem = [TrackerAnswer end:TrackerEndNotFound why:@"Say which site it's on: give its link"];
        return;
    }
    binding.reading = YES;
    binding.triedAt = NSDate.date;
    __weak typeof(self) weakSelf = self;
    [tracker read:binding.key site:binding.site done:^(Ticket *ticket, TrackerAnswer *answer) {
        binding.reading = NO;
        // Only for the binding it was read for: one made since takes its place.
        if (weakSelf.bound[sessionId] != binding) return;
        TrackerAnswer *was = binding.problem;
        if (ticket) [weakSelf took:ticket for:binding];
        else binding.problem = answer;
        // The key and how it went, never what the ticket says, and only when that changes.
        if (!ticket && (!was || was.end != answer.end))
            PanelLog(@"%@ %@: couldn't read it (%ld)", binding.tracker, binding.key, (long)answer.end);
    }];
}

// The ticket as its tracker just gave it, read or moved: kept as last read, with what no longer holds of it gone (a step
// marked as a person's that it no longer lists, and the words saying there was nothing to move).
- (void)took:(Ticket *)ticket for:(TicketBinding *)binding {
    binding.ticket = ticket;
    binding.readAt = NSDate.date;
    binding.problem = nil;
    if (binding.moved[@"gone"]) binding.moved = nil;
    NSMutableSet *listed = [NSMutableSet set];
    for (TicketStep *step in ticket.steps)
        if (step.stepId) [listed addObject:step.stepId];
    for (NSString *stepId in binding.stopped.allKeys)
        if (![listed containsObject:stepId]) [binding.stopped removeObjectForKey:stepId];
}

// Reads the ticket a session is offered, once, as it's offered, so the card on its row says what it is. Only for the
// offer it was read for: an answer that comes after the offer has gone or changed is dropped.
- (void)readOffered:(NSString *)sessionId {
    TicketOffer *offer = self.offers[sessionId];
    id<Tracker> tracker = [self tracker:offer.tracker];
    if (!offer || !tracker) return;
    if (!offer.site.length) {
        offer.problem = [TrackerAnswer end:TrackerEndNotFound why:@"Say which site it's on: give its link"];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [tracker read:offer.key site:offer.site done:^(Ticket *ticket, TrackerAnswer *answer) {
        if (weakSelf.offers[sessionId] != offer) return;
        if (ticket) offer.ticket = ticket;
        else {
            offer.problem = answer;
            // The key and how it went, never what the ticket says.
            PanelLog(@"%@ %@: couldn't read it as offered (%ld)", offer.tracker, offer.key, (long)answer.end);
        }
    }];
}

// What's kept of a session's binding, for a later copy to offer back: for the process it runs in now, only you able to
// read it. Gone with the binding.
- (void)keep:(Row *)row {
    NSString *sessionId = row.sessionId;
    [self.unkept removeObject:sessionId ?: @""];
    if (!self.keptFolder || !IsPlainId(sessionId, 64)) return;
    NSString *path = [self.keptFolder stringByAppendingPathComponent:[sessionId stringByAppendingPathExtension:@"json"]];
    NSDictionary *record = TicketKept(self.bound[sessionId], row.pid, row.pid > 0 ? ProcessStartedAt(row.pid) : 0);
    NSData *data = record ? [NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingSortedKeys error:nil] : nil;
    if (data) [NSFileManager.defaultManager createFileAtPath:path contents:data attributes:@{NSFilePosixPermissions: @0600}];
    else [NSFileManager.defaultManager removeItemAtPath:path error:nil];
}
- (void)forgetKept:(NSString *)sessionId {
    [self.kept removeObjectForKey:sessionId];
    if (!self.keptFolder || !IsPlainId(sessionId, 64)) return;
    [NSFileManager.defaultManager removeItemAtPath:
        [self.keptFolder stringByAppendingPathComponent:[sessionId stringByAppendingPathExtension:@"json"]] error:nil];
}

// Whether a session's process still runs: only then is its ticket read again by itself.
- (BOOL)runs:(Row *)row {
    return row.pid > 0 && ![self.core hasEnded:row] && ProcessAlive(row.pid);
}

- (void)rows:(NSArray<Row *> *)rows phase:(RowPhase)phase {
    if (phase != RowPhaseListed) return;
    for (Row *row in rows) {
        NSString *sessionId = row.sessionId;
        if (!sessionId) continue;
        // A session that has ended: what waited on its row goes, with what was kept for it, and nothing is read for it.
        BOOL runs = [self runs:row];
        if (!runs) [self.offers removeObjectForKey:sessionId];
        // A new ticket isn't made for a session that has ended, unless it's being made already.
        if (!runs && !self.drafts[sessionId].creating) [self.drafts removeObjectForKey:sessionId];
        if (!runs) [self.creating removeObjectForKey:sessionId];
        if (!runs && !self.drafts[sessionId]) [self.draftTold removeObjectForKey:sessionId];
        if (!runs && !self.bound[sessionId].move.moving) self.bound[sessionId].move = nil;
        if (!runs && self.bound[sessionId] && ![self.ended containsObject:sessionId]) {
            [self.ended addObject:sessionId];
            [self forgetKept:sessionId];
            [self.unkept removeObject:sessionId];
        }
        // A binding from the copy before this one is only offered, and only to the process it was made for.
        NSDictionary *kept = self.kept[sessionId];
        if (kept && !self.bound[sessionId] && !self.offers[sessionId]) {
            TicketOffer *offer = row.pid > 0 ? TicketKeptOffer(kept, row.pid, ProcessStartedAt(row.pid)) : nil;
            id<Tracker> tracker = [self tracker:offer.tracker];
            if (offer && tracker) {
                offer.link = offer.site.length ? [tracker linkFor:offer.key site:offer.site] : nil;
                self.offers[sessionId] = offer;
                [self readOffered:sessionId];
            } else [self forgetKept:sessionId];
        }
        if (runs && [self.unkept containsObject:sessionId]) [self keep:row];
        if (runs && self.bound[sessionId]) [self read:sessionId after:kReadEvery ignoringWait:NO];
        row.ticket = TicketShown(self.bound[sessionId], self.offers[sessionId], self.drafts[sessionId],
                                 self.creating[sessionId][@"tracker"]);
    }
    [self tellTrackers:NO];
}

- (void)pageLoaded {
    [self tellTrackers:YES];
}

// A start from the card with a ticket on it: your press of Start binds it. One from Create a ticket only says which
// tracker (and site) its new ticket goes to, for its row's tag and its draft: nothing is made until your Create Ticket.
- (void)started:(NSString *)sessionId with:(id)with {
    NSDictionary *ticket = AsRecord(with);
    id<Tracker> tracker = [self tracker:AsText(ticket[@"tracker"])];
    if ([ticket[@"create"] isEqual:@YES]) {
        if (!tracker || !IsPlainId(sessionId, 64)) return;
        NSString *site = AsText(ticket[@"site"]);
        self.creating[sessionId] = @{@"tracker": tracker.trackerName,
                                     @"site": [tracker.sites containsObject:site] ? site : @""};
        PanelLog(@"%@ starts a new %@ ticket", sessionId, tracker.trackerName);
        return;
    }
    NSString *site = nil, *key = [tracker keyIn:AsText(ticket[@"key"]) ?: @"" site:&site];
    if (!key || ![key isEqual:ticket[@"key"]]) return;
    [self bind:sessionId to:@{@"tracker": tracker.trackerName, @"key": key, @"site": AsText(ticket[@"site"]) ?: @""}
           why:@"started with it"];
}

#pragma mark What a session may do

// May Move Its Ticket, at the foot of the mode menu of a session with a ticket: it moves its ticket at its milestones
// without asking you each time. It lasts while that session's process and Whozmove run, and is given for its ticket, so
// it ends once the session works on another; hidden (no ticket), it ends there and then.
- (NSArray<SessionSwitch *> *)sessionSwitches {
    __weak typeof(self) weakSelf = self;
    NSString *line = @"It moves its own ticket at its milestones, adds its note and sets the fields its step "
                     @"asks for, without asking each time";
    SessionSwitch *move = [SessionSwitch switchWithKey:kMoveTicket title:@"May Move Its Ticket" line:line
                                                 lasts:SwitchLastsWhileRunning];
    // Only while the session runs: it lasts for its process, and a reason the menu gives always has its press.
    move.shown = ^BOOL(Row *row) { return row.pid > 0 && weakSelf.bound[row.sessionId ?: @""] != nil; };
    move.hiddenSays = @"this session has no ticket, or isn't running";
    move.endsHidden = YES;
    move.wayTitle = @"Sign In…";
    move.way = ^(Row *row) {
        id<Tracker> tracker = [weakSelf tracker:weakSelf.bound[row.sessionId ?: @""].tracker];
        if (!tracker || tracker.signInState == TrackerSignedIn) return;
        [tracker signIn:^(TrackerSignIn state, NSString *why) { [weakSelf tellTrackers:YES]; }];
        [weakSelf tellTrackers:YES];
    };
    move.whyNot = ^NSString *(Row *row) {
        id<Tracker> tracker = [weakSelf tracker:weakSelf.bound[row.sessionId ?: @""].tracker];
        if (tracker.signInState == TrackerSignInAsksMac)
            return [NSString stringWithFormat:@"Allow its sign-in first, on %@'s page on the panel's back",
                                              tracker.trackerName];
        if (tracker && tracker.signInState != TrackerSignedIn)
            return [NSString stringWithFormat:@"Sign in with %@ first, on %@'s page on the panel's back",
                                              tracker.signInName ?: tracker.trackerName, tracker.trackerName];
        return nil;
    };
    move.bound = ^NSString *(Row *row) {
        TicketBinding *binding = weakSelf.bound[row.sessionId ?: @""];
        return binding ? [NSString stringWithFormat:@"%@\n%@\n%@", binding.tracker, binding.site ?: @"", binding.key]
                       : nil;
    };
    move.boundSays = @"this session works on another ticket since it was turned on";
    move.says = ^NSString *(Row *row) {
        NSInteger count = [weakSelf.core.allowed count:kMoveTicket session:row.sessionId];
        return count ? [NSString stringWithFormat:@"%@ · moved it %@", line,
                                                  count == 1 ? @"once" : [NSString stringWithFormat:@"%ld times",
                                                                                                    (long)count]]
                     : nil;
    };
    return @[move];
}

#pragma mark What a session asks

// `ticket --wait`, which waits through its ticket's read and your answer, may be left running in the background: it's
// this module's own ask waiting on the panel, not the session's work (BackgroundWaits).
- (NSArray<NSArray<NSString *> *> *)backgroundWaits {
    return @[@[@"ticket", @"--wait"]];
}

- (NSDictionary<NSString *, SessionAsk *> *)sessionAsks {
    __weak typeof(self) weakSelf = self;
    SessionAsk *use = [SessionAsk askShowing:^NSString *(Row *row, pid_t process, NSDictionary *asked) {
        return [weakSelf use:asked from:row];
    }];
    SessionAsk *ticket = [SessionAsk askShowing:^NSString *(Row *row, pid_t process, NSDictionary *asked) {
        return [weakSelf ticketFor:row];
    }];
    // A move only shows on the row for your Move It, unless May Move Its Ticket is on, which it checks itself, for the
    // very process that asks; marking a person's step only shows you something.
    SessionAsk *move = [SessionAsk askShowing:^NSString *(Row *row, pid_t process, NSDictionary *asked) {
        return [weakSelf move:asked from:row process:process];
    }];
    SessionAsk *stop = [SessionAsk askShowing:^NSString *(Row *row, pid_t process, NSDictionary *asked) {
        return [weakSelf stop:asked from:row];
    }];
    // A new ticket only shows on the row for your Create Ticket.
    SessionAsk *draft = [SessionAsk askShowing:^NSString *(Row *row, pid_t process, NSDictionary *asked) {
        return [weakSelf draft:asked from:row];
    }];
    // Each logs the key and how it went itself, never what the ticket, a note, a field, a why or a new ticket says.
    use.logsItself = ticket.logsItself = move.logsItself = stop.logsItself = draft.logsItself = YES;
    return @{@"ticket-use": use, @"ticket": ticket, @"ticket-move": move, @"ticket-stop": stop,
             @"ticket-draft": draft};
}

// ticket-use: the ticket a session asks to work on, by its key or link, shown on its row for your Use It. Nothing is
// bound until you press it.
- (NSString *)use:(NSDictionary *)asked from:(Row *)row {
    NSString *sessionId = row.sessionId, *text = AsText(asked[@"key"]);
    if (!text && AsText(asked[@"link64"])) {
        NSData *data = [[NSData alloc] initWithBase64EncodedString:asked[@"link64"] options:0];
        text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    }
    TicketBinding *now = self.bound[sessionId];
    NSDictionary *ticket = text ? [self ticketIn:text near:now] : nil;
    if (!ticket) {
        PanelLog(@"%@ asked ticket-use: not a ticket", sessionId);
        return @"refused: that isn't a ticket Whozmove knows: give its key (PAY-142) or its link";
    }
    id<Tracker> tracker = [self tracker:ticket[@"tracker"]];
    if (![ticket[@"site"] length] && tracker.signInState == TrackerSignedIn && !tracker.sites.count) {
        // The sites aren't known yet (Whozmove has started since): found now, for the ask again.
        [tracker findSites:^(NSArray<NSString *> *sites) {}];
        return [NSString stringWithFormat:@"refused: Whozmove is finding the user's sites just now: ask again in a "
                @"few seconds, or give %@'s link", ticket[@"key"]];
    }
    if (![ticket[@"site"] length]) {
        PanelLog(@"%@ asked ticket-use: %@, with no site", sessionId, ticket[@"key"]);
        return [NSString stringWithFormat:@"refused: the user is signed in to more than one site, or none, so give "
                @"%@'s link, which names its site", ticket[@"key"]];
    }
    if ([now.key isEqual:ticket[@"key"]] && [now.tracker isEqual:ticket[@"tracker"]])
        return [NSString stringWithFormat:@"working on it already: %@", now.key];
    // Asked for again while it waits: the same offer, not a second one, read again only if it couldn't be read.
    TicketOffer *offer = self.offers[sessionId];
    NSString *site = [ticket[@"site"] length] ? ticket[@"site"] : nil;
    BOOL same = [offer.tracker isEqual:ticket[@"tracker"]] && [offer.key isEqual:ticket[@"key"]]
        && [offer.site ?: @"" isEqual:site ?: @""];
    if (!same) {
        offer = [TicketOffer new];
        offer.tracker = ticket[@"tracker"];
        offer.key = ticket[@"key"];
        offer.site = site;
        offer.link = offer.site ? [[self tracker:offer.tracker] linkFor:offer.key site:offer.site] : nil;
    }
    offer.instead = now.key;
    offer.again = NO;
    self.offers[sessionId] = offer;
    BOOL failed = same && offer.problem;
    if (failed) offer.problem = nil;
    if (!same || failed) [self readOffered:sessionId];
    [self.declined removeObjectForKey:sessionId];
    PanelLog(@"%@ asked ticket-use: %@, shown on its row", sessionId, offer.key);
    return [NSString stringWithFormat:@"shown on your row: “Work on %@ %@?” Carry on; ask-panel.sh ticket --wait says "
            @"once the user has answered", offer.key, now ? @"instead" : @"here"];
}

// ticket: the session's own ticket, at once, from what was last read, and read again for next time; while a new ticket
// it drafted waits, how that stands, and once it's answered, how it went, told once.
- (NSString *)ticketFor:(Row *)row {
    NSString *sessionId = row.sessionId;
    TicketBinding *binding = self.bound[sessionId];
    TicketDraft *draft = self.drafts[sessionId];
    // Why it couldn't be checked or made is said once; then it's waited for, as the user's Try Again or sign-in.
    if (draft && !self.offers[sessionId]) {
        NSString *answer = TicketDraftWaiting(draft, [self tracker:draft.tracker].signInName,
                                              draft.problem && draft.toldProblem == draft.problem);
        draft.toldProblem = draft.problem;
        return answer;
    }
    NSString *told = self.draftTold[sessionId];
    if (told && !self.offers[sessionId]) {
        [self.draftTold removeObjectForKey:sessionId];
        return told;
    }
    if (!binding && self.creating[sessionId] && !self.offers[sessionId])
        return @"refused: this session has no ticket yet: it's to make a new one. Talk it through with the user, then "
               @"draft it with ask-panel.sh ticket-draft, which they answer on its row";
    [self read:sessionId always:NO];
    NSString *answer = TicketAnswer(binding, self.offers[sessionId], self.declined[sessionId],
                                    [self tracker:binding.tracker].signInName);
    // A Not Now is told once, and so is how a move went, with the ticket.
    if (!self.offers[sessionId]) [self.declined removeObjectForKey:sessionId];
    if ([answer hasPrefix:@"{"]) binding.told = nil;
    return answer;
}

static NSString *Decoded64(id value) {
    NSData *data = AsText(value) ? [[NSData alloc] initWithBase64EncodedString:value options:0] : nil;
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}

// What a session can't move or mark until its ticket is there and read, or nil once it is.
- (NSString *)notReady:(TicketBinding *)binding ask:(NSString *)word session:(NSString *)sessionId {
    if (!binding) {
        PanelLog(@"%@ asked %@: no ticket", sessionId, word);
        return @"refused: this session has no ticket. The user gives it one on the new conversation card, or ask with "
               @"ask-panel.sh ticket-use <key or link>, which they answer on its row";
    }
    if (binding.ticket) return nil;
    PanelLog(@"%@ asked %@: %@, not read yet", sessionId, word, binding.key);
    return [NSString stringWithFormat:@"refused: %@ hasn't been read yet, so its next steps aren't known: ask again "
            @"once ask-panel.sh ticket --wait has it", binding.key];
}

// ticket-move: one of its ticket's next steps, as last read, with a note and the fields it sets: taken at once while
// May Move Its Ticket is on for the process that asks, else shown on its row for your Move It, in place of any move
// waiting there. Either way the session carries on, and `ticket` says how it went, once.
- (NSString *)move:(NSDictionary *)asked from:(Row *)row process:(pid_t)process {
    NSString *sessionId = row.sessionId, *stepId = AsText(asked[@"id"]);
    TicketBinding *binding = self.bound[sessionId];
    NSString *refused = [self notReady:binding ask:@"ticket-move" session:sessionId];
    if (refused) return refused;
    if (binding.move.moving) {
        PanelLog(@"%@ asked ticket-move: %@, being moved already", sessionId, binding.key);
        return [NSString stringWithFormat:@"refused: %@ is being moved just now: ask-panel.sh ticket says once it has",
                binding.key];
    }
    NSString *why = nil;
    TicketMove *move = TicketMoveAsked(binding.ticket, stepId, Decoded64(asked[@"note64"]), &why);
    if (!move) {
        // The key and the step, never what it gave: its words may be the note's or a field's.
        PanelLog(@"%@ asked ticket-move: %@ step %@, refused", sessionId, binding.key,
                 IsPlainId(stepId, 64) ? stepId : @"(not one)");
        return [@"refused: " stringByAppendingString:why];
    }
    NSString *to = move.to.name ?: move.name;
    TicketMove *was = binding.move;
    binding.told = nil;
    if (![self.core.allowed whyOff:kMoveTicket for:row from:process]) {
        move.itself = YES;
        binding.move = move;
        PanelLog(@"%@ asked ticket-move: %@ step %@, moving it by itself", sessionId, binding.key, move.stepId);
        [self take:move for:sessionId];
        return [NSString stringWithFormat:@"moving %@ to %@: ask-panel.sh ticket says once it has", binding.key, to];
    }
    if (was) move.instead = was.to.name ?: was.name;
    binding.move = move;
    PanelLog(@"%@ asked ticket-move: %@ step %@, shown on its row", sessionId, binding.key, move.stepId);
    return [NSString stringWithFormat:@"shown on your row: “Move %@ to %@?” Carry on; ask-panel.sh ticket says once the "
            @"user has answered", binding.key, to];
}

// A move taken, by your Move It or by itself: the ticket as it stands after is kept as read, and the session told once
// how it went. One that went is said on the ticket's card, by whom; one whose step had gone already is said there
// until the next read, and its card closes; one that failed stays on the row, saying why, for Try Again or Not Now,
// unless it was taken by itself, which only the session is told.
- (void)take:(TicketMove *)move for:(NSString *)sessionId {
    TicketBinding *binding = self.bound[sessionId];
    id<Tracker> tracker = [self tracker:binding.tracker];
    if (!binding || !tracker) return;
    move.moving = YES;
    move.problem = nil;
    NSString *to = move.to.name ?: move.name ?: @"";
    __weak typeof(self) weakSelf = self;
    [tracker take:move.stepId of:binding.key site:binding.site note:move.note fields:move.fields
             done:^(Ticket *ticket, TrackerAnswer *answer) {
        move.moving = NO;
        // Only for the binding it was taken for: one made since takes its place.
        if (weakSelf.bound[sessionId] != binding) return;
        if (ticket) [weakSelf took:ticket for:binding];
        NSNumber *at = @(floor(NSDate.date.timeIntervalSince1970 * 1000));
        BOOL current = binding.move == move;
        if (answer.ok) {
            binding.moved = @{@"to": to, @"by": move.itself ? @"itself" : @"you", @"at": at};
            binding.told = @{@"moved": to};
            [binding.stopped removeAllObjects];
            if (move.itself) [weakSelf.core.allowed countUp:kMoveTicket session:sessionId];
            PanelLog(@"%@ %@: step %@ taken (%@)", binding.tracker, binding.key, move.stepId,
                     move.itself ? @"by itself" : @"Move It");
        } else {
            if (answer.end == TrackerEndStepGone) binding.moved = @{@"gone": answer.why ?: @"", @"at": at};
            // One it took by itself that the sign-in stopped comes to the row as yours to move, for the way forward
            // (Sign In Again, or Allow), which only you can take.
            BOOL signIn = answer.end == TrackerEndSignIn || answer.end == TrackerEndAsksMac, byItself = move.itself;
            if (byItself && signIn) move.itself = NO;
            if (answer.end == TrackerEndStepGone || byItself)
                binding.told = @{@"notMoved": answer.why ?: @"it couldn't be moved"};
            if (answer.end != TrackerEndStepGone && !move.itself) move.problem = answer;
            PanelLog(@"%@ %@: step %@ not taken (%ld)", binding.tracker, binding.key, move.stepId, (long)answer.end);
        }
        if (current && (answer.ok || answer.end == TrackerEndStepGone || move.itself)) binding.move = nil;
    }];
}

// ticket-stop: one of its ticket's next steps marked as a person's (an approval, a sign-off), with why, for the
// ticket's card on its row. The mark goes once a read no longer lists the step, or the ticket moves.
- (NSString *)stop:(NSDictionary *)asked from:(Row *)row {
    NSString *sessionId = row.sessionId, *stepId = AsText(asked[@"id"]);
    TicketBinding *binding = self.bound[sessionId];
    NSString *refused = [self notReady:binding ask:@"ticket-stop" session:sessionId];
    if (refused) return refused;
    TicketStep *step = nil;
    for (TicketStep *each in binding.ticket.steps)
        if (stepId && [each.stepId isEqual:stepId]) step = each;
    NSString *why = [Decoded64(asked[@"why64"]) stringByTrimmingCharactersInSet:
                     NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *refusal = !step ? [NSString stringWithFormat:@"that isn't one of %@'s next steps now: ask-panel.sh "
                                                           @"ticket lists them", binding.key]
        : !why.length ? @"say on stdin whose step it is, and why it's theirs"
        : why.length > kLongestTicketNote ? [NSString stringWithFormat:@"a why may be %lu characters at most",
                                                                        (unsigned long)kLongestTicketNote]
        : nil;
    if (refusal) {
        PanelLog(@"%@ asked ticket-stop: %@ step %@, refused", sessionId, binding.key,
                 IsPlainId(stepId, 64) ? stepId : @"(not one)");
        return [@"refused: " stringByAppendingString:refusal];
    }
    if (!binding.stopped) binding.stopped = [NSMutableDictionary dictionary];
    binding.stopped[step.stepId] = why;
    PanelLog(@"%@ asked ticket-stop: %@ step %@, marked a person's", sessionId, binding.key, step.stepId);
    return [NSString stringWithFormat:@"marked: %@ is a person's step: say so in your reply and stop",
            step.name ?: step.to.name];
}

// ticket-draft: a new ticket, as the session drafted it, checked with its tracker (whether its group takes that type),
// then shown on its row for your Create Ticket, in place of any draft waiting there. Its tracker is the session's
// ticket's, or the one its start named, or the one you're signed in to; its site likewise, or the one it names.
- (NSString *)draft:(NSDictionary *)asked from:(Row *)row {
    NSString *sessionId = row.sessionId, *why = nil;
    TicketDraft *draft = TicketDraftAsked(Decoded64(asked[@"draft64"]), &why);
    // Never what it gave: its words are the new ticket's.
    if (!draft) {
        PanelLog(@"%@ asked ticket-draft: refused", sessionId);
        return [@"refused: " stringByAppendingString:why];
    }
    TicketDraft *was = self.drafts[sessionId];
    if (was.creating) {
        PanelLog(@"%@ asked ticket-draft: one is being created already", sessionId);
        return @"refused: the new ticket is being created just now: ask-panel.sh ticket --wait says once it has";
    }
    TicketBinding *binding = self.bound[sessionId];
    NSDictionary *start = self.creating[sessionId];
    NSArray<id<Tracker>> *signedIn = [self.trackers filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(id<Tracker> tracker, id _) { return tracker.signInState == TrackerSignedIn; }]];
    id<Tracker> tracker = [self tracker:binding.tracker ?: start[@"tracker"]]
        ?: (signedIn.count == 1 ? signedIn.firstObject : self.trackers.count == 1 ? self.trackers.firstObject : nil);
    NSString *refusal = nil;
    if (!tracker) refusal = signedIn.count ? @"say which tracker it's for: ask the user to start it from Create a "
                                             @"ticket on the new conversation card"
                                           : @"the user isn't signed in to a ticket tracker: they sign in on the new "
                                             @"conversation card's Ticket chip";
    else if (tracker.signInState == TrackerSignedIn && !tracker.sites.count) {
        // The sites aren't known yet (Whozmove has started since): found now, for the ask again.
        [tracker findSites:^(NSArray<NSString *> *sites) {}];
        refusal = @"Whozmove is finding the user's sites just now: ask again in a few seconds";
    }
    NSString *site = draft.site;
    if (!refusal && site && tracker.sites.count && ![tracker.sites containsObject:site])
        refusal = [NSString stringWithFormat:@"%@ isn't a site the user is signed in to: it's one of %@",
                   Clip(site, 60), [tracker.sites componentsJoinedByString:@", "]];
    if (!refusal && !site) {
        NSString *near = binding.site ?: AsText(start[@"site"]);
        site = near.length ? near : tracker.sites.count == 1 ? tracker.sites.firstObject : nil;
    }
    if (!refusal && !site && tracker.signInState == TrackerSignedIn)
        refusal = [NSString stringWithFormat:@"say which site it goes on, as \"site\": one of %@",
                   [tracker.sites componentsJoinedByString:@", "]];
    if (!refusal && draft.parent) {
        NSString *parentSite = nil, *key = [tracker keyIn:draft.parent site:&parentSite];
        if (![key isEqual:draft.parent])
            refusal = [NSString stringWithFormat:@"the parent is to be a %@ ticket's key%@", tracker.trackerName,
                       binding.key ? [NSString stringWithFormat:@", as %@ is", binding.key] : @""];
    }
    if (refusal) {
        PanelLog(@"%@ asked ticket-draft: refused", sessionId);
        return [@"refused: " stringByAppendingString:refusal];
    }
    draft.tracker = tracker.trackerName;
    draft.site = site;
    draft.again = was != nil;
    self.drafts[sessionId] = draft;
    [self.draftTold removeObjectForKey:sessionId];
    PanelLog(@"%@ asked ticket-draft: a new %@ ticket in %@, shown on its row", sessionId, draft.tracker, draft.group);
    [self check:sessionId];
    return [NSString stringWithFormat:@"shown on your row: “Create this ticket?”, once %@ has said %@ takes it. Carry on; "
            @"ask-panel.sh ticket --wait says once the user has answered", draft.tracker, draft.group];
}

// Asks the draft's tracker what its group takes: one it doesn't take, or a group there isn't, is sent back to the
// session to draft again, and never shown; one it couldn't ask waits on the row, saying why, for Try Again.
- (void)check:(NSString *)sessionId {
    TicketDraft *draft = self.drafts[sessionId];
    id<Tracker> tracker = [self tracker:draft.tracker];
    if (!draft || !tracker || draft.checking) return;
    if (tracker.signInState != TrackerSignedIn && tracker.signInState != TrackerSignInAsksMac) {
        draft.problem = [TrackerAnswer end:TrackerEndSignIn why:@"You aren't signed in"];
        return;
    }
    // Drafted before the sites were known (signed out, say): the one you're signed in to now, once they're known (after
    // your Allow, or found first), else back to the session.
    if (!draft.site.length && !tracker.sites.count) {
        if (tracker.signInState == TrackerSignInAsksMac) {
            draft.problem = [TrackerAnswer end:TrackerEndAsksMac why:@"macOS asks before it hands over the sign-in"];
            return;
        }
        if (!draft.sitesLooked) {
            draft.sitesLooked = YES;
            __weak typeof(self) weakSelf = self;
            [tracker findSites:^(NSArray<NSString *> *sites) { [weakSelf check:sessionId]; }];
            return;
        }
    }
    if (!draft.site.length && tracker.sites.count == 1) draft.site = tracker.sites.firstObject;
    // A site the session named before the sites were known, checked now they are.
    if (draft.site.length && tracker.sites.count && ![tracker.sites containsObject:draft.site]) {
        [self.drafts removeObjectForKey:sessionId];
        self.draftTold[sessionId] = [NSString stringWithFormat:@"not yet: %@ isn't a site the user is signed in to "
                                     @"(they're on %@): draft it again with one of theirs", Clip(draft.site, 60),
                                     TicketsListed(tracker.sites)];
        return;
    }
    if (!draft.site.length) {
        [self.drafts removeObjectForKey:sessionId];
        self.draftTold[sessionId] = [NSString stringWithFormat:@"not yet: say which site it goes on, as \"site\": one "
                                     @"of %@, then draft it again", TicketsListed(tracker.sites)];
        return;
    }
    draft.checking = YES;
    draft.problem = nil;
    __weak typeof(self) weakSelf = self;
    [tracker newTicketOptions:draft.group site:draft.site done:^(NSDictionary *options, TrackerAnswer *answer) {
        // Only for the draft it was asked for: one drafted since takes its place.
        if (weakSelf.drafts[sessionId] != draft) {
            draft.checking = NO;
            return;
        }
        NSString *notYet = TicketDraftChecked(draft, options, answer);
        if (notYet) {
            [weakSelf.drafts removeObjectForKey:sessionId];
            weakSelf.draftTold[sessionId] = notYet;
            PanelLog(@"%@ %@: a new ticket in %@ sent back to draft again", draft.tracker, draft.site, draft.group);
        } else if (draft.problem)
            PanelLog(@"%@ %@: couldn't check a new ticket in %@ (%ld)", draft.tracker, draft.site, draft.group,
                     (long)answer.end);
    }];
}

// Makes the new ticket, by your Create Ticket: it's then the session's own ticket, read as it was made, and the session
// is told its key once; one turned away goes back to the session; one that couldn't be made waits on the row, saying
// why, for Try Again (or Create Again, once you've looked, when it may have been made all the same) or Not Yet.
- (void)create:(NSString *)sessionId {
    TicketDraft *draft = self.drafts[sessionId];
    id<Tracker> tracker = [self tracker:draft.tracker];
    if (!draft || !tracker || draft.creating) return;
    draft.creating = YES;
    draft.problem = nil;
    NSMutableDictionary *made = [@{@"group": draft.group, @"type": draft.type, @"title": draft.title} mutableCopy];
    if (draft.details) made[@"description"] = draft.details;
    if (draft.priority) made[@"priority"] = draft.priority;
    if (draft.parent) made[@"parent"] = draft.parent;
    __weak typeof(self) weakSelf = self;
    [tracker create:made site:draft.site done:^(Ticket *ticket, TrackerAnswer *answer) {
        NSString *site = nil, *key = ticket.key ? [tracker keyIn:ticket.key site:&site] : nil, *told = nil;
        TicketDraftEnd ended = TicketDraftMade(draft, key, answer, &told);
        if (weakSelf.drafts[sessionId] != draft) return;
        if (ended == TicketDraftSentBack) {
            [weakSelf.drafts removeObjectForKey:sessionId];
            weakSelf.draftTold[sessionId] = told;
            PanelLog(@"%@ %@: a new ticket in %@ turned away, sent back to draft again", draft.tracker, draft.site,
                     draft.group);
            return;
        }
        if (ended == TicketDraftWaits) {
            PanelLog(@"%@ %@: a new ticket in %@ not created (%ld)%@", draft.tracker, draft.site, draft.group,
                     (long)draft.problem.end, draft.mayBeMade ? @", and may have been all the same" : @"");
            return;
        }
        [weakSelf.drafts removeObjectForKey:sessionId];
        PanelLog(@"%@ %@: %@ created", draft.tracker, draft.site, key);
        [weakSelf bind:sessionId to:@{@"tracker": draft.tracker, @"key": key, @"site": draft.site} why:@"Create Ticket"
                  read:ticket];
        TicketBinding *binding = weakSelf.bound[sessionId];
        weakSelf.draftTold[sessionId] = [NSString stringWithFormat:@"created: %@%@. It's this session's ticket now: "
                                         @"ask-panel.sh ticket --wait reads it", key,
                                         binding.link ? [@": " stringByAppendingString:binding.link] : @""];
    }];
}

#pragma mark What the page says

- (NSDictionary<NSString *, void (^)(NSDictionary *message)> *)messages {
    __weak typeof(self) weakSelf = self;
    return @{
        // The card's search, as you type: every tracker you're signed in to, its answers by the ask they're for.
        @"ticketSearch": ^(NSDictionary *msg) { [weakSelf search:AsText(msg[@"words"]) asked:msg[@"asked"]]; },
        // A key or link written or pasted on the card: that ticket, read, for its chip.
        @"ticketFind": ^(NSDictionary *msg) { [weakSelf find:AsText(msg[@"text"]) asked:msg[@"asked"]]; },
        @"ticketSignIn": ^(NSDictionary *msg) {
            id<Tracker> tracker = [weakSelf tracker:AsText(msg[@"tracker"])];
            [tracker signIn:^(TrackerSignIn state, NSString *why) { [weakSelf tellTrackers:YES]; }];
            [weakSelf tellTrackers:YES];
        },
        @"ticketCancelSignIn": ^(NSDictionary *msg) {
            [[weakSelf tracker:AsText(msg[@"tracker"])] cancelSignIn];
            [weakSelf tellTrackers:YES];
        },
        @"ticketCopyAsk": ^(NSDictionary *msg) {
            NSString *ask = [weakSelf tracker:AsText(msg[@"tracker"])].adminAsk;
            if (!ask.length) return;
            [NSPasteboard.generalPasteboard clearContents];
            [NSPasteboard.generalPasteboard setString:ask forType:NSPasteboardTypeString];
        },
        // Your answer on a row's card: Use It or Not Now.
        @"ticketAnswer": ^(NSDictionary *msg) {
            // Only for the ticket the card showed: one asked for since is shown before it can be answered.
            NSString *sessionId = AsText(msg[@"sessionId"]);
            TicketOffer *offer = sessionId ? weakSelf.offers[sessionId] : nil;
            if (offer && [offer.key isEqual:AsText(msg[@"key"])]) [weakSelf answer:AsText(msg[@"act"]) for:sessionId];
        },
        // Your answer on a row's move card: Move It (or Try Again), or Not Now.
        @"ticketMove": ^(NSDictionary *msg) {
            [weakSelf moveAnswer:AsText(msg[@"act"]) for:AsText(msg[@"sessionId"]) key:AsText(msg[@"key"])
                            step:AsText(msg[@"stepId"]) at:AsNumber(msg[@"at"])];
        },
        // Your answer on a row's new ticket card: Create Ticket (or Try Again), or Not Yet.
        @"ticketDraft": ^(NSDictionary *msg) {
            [weakSelf draftAnswer:AsText(msg[@"act"]) for:AsText(msg[@"sessionId"]) at:AsNumber(msg[@"at"])];
        },
        // Its card opened (read it again, unless it was just now), or Try Again or Try Now pressed on it.
        @"ticketRead": ^(NSDictionary *msg) {
            NSString *sessionId = AsText(msg[@"sessionId"]);
            Row *row = sessionId ? weakSelf.core.rows.byId[sessionId] : nil;
            if (!row || ![weakSelf runs:row]) return;
            BOOL now = [msg[@"now"] isEqual:@YES];
            [weakSelf read:sessionId after:now ? 0 : kLookAgainAfter ignoringWait:now];
        },
        // The tag pressed: the ticket in your browser, at the address made from its site and key.
        @"openTicket": ^(NSDictionary *msg) {
            TicketBinding *binding = weakSelf.bound[AsText(msg[@"sessionId"]) ?: @""];
            NSURL *link = binding.link ? [NSURL URLWithString:binding.link] : nil;
            if (link) OpenInWebBrowser(link);
        },
    };
}

- (void)answer:(NSString *)act for:(NSString *)sessionId {
    TicketOffer *offer = sessionId ? self.offers[sessionId] : nil;
    if (!offer) return;
    if ([act isEqual:@"use"]) {
        [self forgetKept:sessionId];
        [self bind:sessionId to:@{@"tracker": offer.tracker, @"key": offer.key, @"site": offer.site ?: @""}
               why:offer.again ? @"Use It, again" : @"Use It"];
    } else if ([act isEqual:@"notNow"]) {
        [self.offers removeObjectForKey:sessionId];
        if (offer.again) [self forgetKept:sessionId];
        else self.declined[sessionId] = offer.key;
        PanelLog(@"%@: Not Now for %@", sessionId, offer.key);
    }
}

- (NSNumber *)moveAskedAt:(NSString *)sessionId {
    TicketMove *move = sessionId ? self.bound[sessionId].move : nil;
    return move ? @(floor(move.at.timeIntervalSince1970 * 1000)) : nil;
}

// Your answer on the move card: only for the move it showed (its ticket, its step and when it was asked, as the session
// may ask the same step again with another note or fields just before your press), and never while it's being taken.
- (void)moveAnswer:(NSString *)act for:(NSString *)sessionId key:(NSString *)key step:(NSString *)stepId
                at:(NSNumber *)at {
    TicketBinding *binding = sessionId ? self.bound[sessionId] : nil;
    TicketMove *move = binding.move;
    if (!move || move.itself || move.moving || ![binding.key isEqual:key] || ![move.stepId isEqual:stepId]) return;
    if (!at || at.doubleValue != floor(move.at.timeIntervalSince1970 * 1000)) return;
    if ([act isEqual:@"move"]) {
        PanelLog(@"%@: Move It for %@ step %@", sessionId, binding.key, move.stepId);
        [self take:move for:sessionId];
    } else if ([act isEqual:@"notNow"]) {
        binding.move = nil;
        binding.told = @{@"notMoved": @"the user said Not Now"};
        PanelLog(@"%@: Not Now for moving %@ (step %@)", sessionId, binding.key, move.stepId);
    }
}

- (NSNumber *)draftAskedAt:(NSString *)sessionId {
    TicketDraft *draft = sessionId ? self.drafts[sessionId] : nil;
    return draft ? @(floor(draft.at.timeIntervalSince1970 * 1000)) : nil;
}

// Your answer on the new ticket's card: only for the draft it showed (by when it was asked, as the session may draft it
// again just before your press), never while it's made: Create Ticket (`create`) only once its tracker has said where
// it can go, Try Again (`check`) only while it hasn't, and Not Yet (`notYet`) at any time but while it's made.
- (void)draftAnswer:(NSString *)act for:(NSString *)sessionId at:(NSNumber *)at {
    TicketDraft *draft = sessionId ? self.drafts[sessionId] : nil;
    if (!draft || draft.creating || (draft.checking && ![act isEqual:@"notYet"])) return;
    if (!at || at.doubleValue != floor(draft.at.timeIntervalSince1970 * 1000)) return;
    // Create Ticket (or Create Again) only makes a checked draft, and Try Again only checks one that isn't: a press meant
    // for the one is never taken as the other's.
    if ([act isEqual:@"create"] && draft.checked) {
        PanelLog(@"%@: %@ for a new ticket in %@", sessionId,
                 draft.mayBeMade ? @"Create Again" : draft.problem ? @"Try Again" : @"Create Ticket", draft.group);
        [self create:sessionId];
    } else if ([act isEqual:@"check"] && !draft.checked) {
        PanelLog(@"%@: Try Again for checking a new ticket in %@", sessionId, draft.group);
        [self check:sessionId];
    } else if ([act isEqual:@"notYet"]) {
        [self.drafts removeObjectForKey:sessionId];
        // A start from Create a ticket says "New ticket" no more: a draft again doesn't need it.
        [self.creating removeObjectForKey:sessionId];
        self.draftTold[sessionId] = @"not yet: the user chose Not Yet: ask what to change, then draft it again";
        PanelLog(@"%@: Not Yet for a new ticket in %@", sessionId, draft.group);
    }
}

// How an answer ended, in the page's words (ticket-words.js draws each with its way forward).
static NSString *EndWord(TrackerEnd end) {
    switch (end) {
        case TrackerEndSlowDown: return @"slow";
        case TrackerEndSignIn: return @"signIn";
        case TrackerEndAsksMac: return @"allow";
        case TrackerEndNotFound: return @"notFound";
        case TrackerEndBlocked: return @"blocked";
        default: return @"failed";
    }
}

// Tickets found for the card: every signed-in tracker's, together; with none signed in, why.
- (void)search:(NSString *)words asked:(id)asked {
    NSNumber *ask = AsNumber(asked) ?: @0;
    words = Clip(words ?: @"", kLongestText);
    NSArray<id<Tracker>> *signedIn = [self.trackers filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(id<Tracker> tracker, id _) { return tracker.signInState == TrackerSignedIn; }]];
    if (!signedIn.count) return [self.core.page call:@"ticketsFound" with:@[ask, @{@"tickets": @[], @"end": @"signIn"}]];
    __block NSUInteger left = signedIn.count;
    NSMutableArray *found = [NSMutableArray array];
    __block TrackerAnswer *failed = nil;
    __weak typeof(self) weakSelf = self;
    for (id<Tracker> tracker in signedIn)
        [tracker search:words done:^(NSArray<Ticket *> *tickets, TrackerAnswer *answer) {
            for (Ticket *ticket in tickets) {
                NSMutableDictionary *json = [[ticket json] mutableCopy];
                json[@"tracker"] = tracker.trackerName;
                json[@"link"] = ticket.site ? [tracker linkFor:ticket.key site:ticket.site] : nil;
                [found addObject:json];
            }
            if (!answer.ok) failed = answer;
            if (--left) return;
            NSMutableDictionary *said = [@{@"tickets": found} mutableCopy];
            if (failed && !found.count) {
                said[@"end"] = EndWord(failed.end);
                said[@"why"] = failed.why ?: @"";
            }
            [weakSelf.core.page call:@"ticketsFound" with:@[ask, said]];
        }];
}

// One ticket for the card, from a key or a link: read, so its chip says what it is; or why not.
- (void)find:(NSString *)text asked:(id)asked {
    [self find:text asked:asked sitesFound:NO];
}
- (void)find:(NSString *)text asked:(id)asked sitesFound:(BOOL)found {
    NSNumber *ask = AsNumber(asked) ?: @0;
    NSDictionary *named = text ? [self ticketIn:text near:nil] : nil;
    id<Tracker> tracker = [self tracker:named[@"tracker"]];
    void (^say)(NSDictionary *) = ^(NSDictionary *said) { [self.core.page call:@"ticketPicked" with:@[ask, said]]; };
    if (!tracker) return say(@{@"none": @YES});
    // Its sites aren't known yet (Whozmove has started since): found first, once.
    if (!found && tracker.signInState == TrackerSignedIn && !tracker.sites.count)
        return [tracker findSites:^(NSArray<NSString *> *sites) { [self find:text asked:asked sitesFound:YES]; }];
    NSString *site = named[@"site"];
    if (tracker.signInState != TrackerSignedIn) return say(@{@"key": named[@"key"], @"end": @"signIn",
                                                             @"tracker": tracker.trackerName});
    if (!site.length) return say(@{@"key": named[@"key"], @"end": @"site", @"tracker": tracker.trackerName});
    if (![tracker.sites containsObject:site])
        return say(@{@"key": named[@"key"], @"end": @"elsewhere", @"site": site, @"tracker": tracker.trackerName});
    [tracker read:named[@"key"] site:site done:^(Ticket *ticket, TrackerAnswer *answer) {
        if (!ticket) return say(@{@"key": named[@"key"], @"end": EndWord(answer.end), @"why": answer.why ?: @"",
                                  @"tracker": tracker.trackerName});
        NSMutableDictionary *json = [[ticket json] mutableCopy];
        json[@"tracker"] = tracker.trackerName;
        json[@"link"] = [tracker linkFor:ticket.key site:site];
        say(@{@"ticket": json});
    }];
}

#pragma mark Print runs

+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return TicketsPrintModes();
}

@end
