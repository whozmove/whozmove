// TicketsPrints: --print-tickets, the tickets module driven as the core and the page would drive it, step by step,
// with a made-up tracker ("Sample", on sample sites), in a throwaway home only: bindings made by a start and by Use It,
// never by an ask or a file; what each ask answers; moves, by Move It or by May Move Its Ticket, and the steps marked
// as a person's; new tickets, drafted and made only by Create Ticket; the rows' `ticket`; what's kept for a later copy,
// and offered back only to the same process; and panel.log, which carries no ticket's words, no note, no field's
// value, no why and nothing of a new ticket's, and Whozmove's folder, where no file holds a ticket's description.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "TicketsModule.h"
#import "Allowed.h"
#import "Core.h"
#import "Modules.h"
#import "Row.h"
#import "Files.h"
#import "Processes.h"
#import "Git.h"
#import "TicketBindings.h"

// A made-up tracker: keys like ABC-1, links https://<site>/t/<key> on a .example site, three tickets that read, and
// whatever the next read or move is told to end with. ABC-3 has the steps a move is tried with: one that sets fields,
// one a person takes, and one that sets none; once moved, by Whozmove or by someone else (`moved`), it stands where
// that step led, with one step back. `took` says what each move was given, and each ticket made. New tickets go in
// ABC, which takes a Task or a Bug, and are ABC-4 on.
@interface SampleTracker : NSObject <Tracker>
@property TrackerSignIn signInState;
@property TrackerEnd nextEnd;
@property (strong) NSMutableDictionary<NSString *, TicketState *> *moved;
@property (strong) NSMutableArray<NSString *> *took;
@property NSInteger made;
// The next ticket made isn't read back, as a read just after can fail: it's answered by its key alone.
@property BOOL unread;
@end

@implementation SampleTracker
- (NSString *)trackerName { return @"Sample"; }
- (NSString *)signInName { return @"Sample's sign-in"; }
- (NSArray<NSString *> *)sites { return self.signInState == TrackerSignedIn ? @[@"one.example"] : @[]; }
- (NSString *)signInWhy { return nil; }
- (void)findSites:(void (^)(NSArray<NSString *> *))done { done(self.sites); }
- (NSString *)adminAsk { return @"Please let apps sign in."; }
- (void)signIn:(void (^)(TrackerSignIn, NSString *))done {
    self.signInState = TrackerSignedIn;
    done(self.signInState, nil);
}
- (void)cancelSignIn {}
- (void)signOut { self.signInState = TrackerSignedOut; }

- (NSString *)keyIn:(NSString *)text site:(NSString **)site {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSRegularExpression *key = [NSRegularExpression regularExpressionWithPattern:@"^[A-Z]+-[1-9][0-9]*$" options:0 error:nil];
    if ([key numberOfMatchesInString:trimmed options:0 range:NSMakeRange(0, trimmed.length)]) return trimmed;
    NSURL *link = [NSURL URLWithString:trimmed];
    NSString *last = link.path.lastPathComponent ?: @"";
    if (![link.scheme isEqual:@"https"] || ![link.host hasSuffix:@".example"] || ![link.path hasPrefix:@"/t/"]
        || ![key numberOfMatchesInString:last options:0 range:NSMakeRange(0, last.length)])
        return nil;
    if (site) *site = link.host;
    return last;
}
- (NSString *)linkFor:(NSString *)key site:(NSString *)site {
    return [NSString stringWithFormat:@"https://%@/t/%@", site, key];
}

static TicketStep *Step(NSString *stepId, NSString *name, TicketState *to, NSArray<TicketField *> *needs) {
    TicketStep *step = [TicketStep new];
    step.stepId = stepId;
    step.name = name;
    step.to = to;
    step.needs = needs ?: @[];
    return step;
}

// A field of the made-up tracker's: one of `options`, or a list of them where it takes `many`.
static TicketField *Field(NSString *fieldId, NSString *name, BOOL required, NSArray<NSString *> *options, BOOL many) {
    TicketField *field = [TicketField new];
    field.fieldId = fieldId;
    field.name = name;
    field.kind = @"option";
    field.required = required;
    field.options = options;
    field.many = many;
    return field;
}

- (Ticket *)ticket:(NSString *)key site:(NSString *)site {
    Ticket *ticket = [Ticket new];
    ticket.tracker = self.trackerName;
    ticket.site = site;
    ticket.key = key;
    ticket.title = [@"Made-up words of " stringByAppendingString:key];
    ticket.about = [NSString stringWithFormat:@"Made-up description of %@: what it asks, with <b>markup</b> & "
                    @"\"quotes\" to stay as text.", key];
    ticket.type = @"Task";
    ticket.state = [TicketState named:@"Doing" kind:TicketKindUnderWay];
    TicketGroup *group = [TicketGroup new];
    group.groupId = @"7";
    group.name = @"The board";
    group.kind = @"board";
    ticket.groups = @[group];
    TicketStep *step = [TicketStep new];
    step.stepId = @"5";
    step.name = @"Finish";
    step.to = [TicketState named:@"Done" kind:TicketKindDone];
    ticket.steps = @[step];
    if (![key isEqual:@"ABC-3"]) return ticket;
    TicketState *moved = self.moved[key];
    if (moved) {
        ticket.state = moved;
        ticket.steps = @[Step(@"7", @"Reopen", [TicketState named:@"Doing" kind:TicketKindUnderWay], nil)];
        return ticket;
    }
    ticket.steps = @[Step(@"5", @"Finish", [TicketState named:@"Done" kind:TicketKindDone],
                          @[Field(@"resolution", @"Resolution", YES, @[@"Fixed", @"Won't Fix"], NO),
                            Field(@"fixVersion", @"Fix version", NO, @[@"2.1", @"2.2"], YES)]),
                     Step(@"6", @"QA sign-off", [TicketState named:@"Signed Off" kind:TicketKindDone], nil),
                     Step(@"8", @"Send to review", [TicketState named:@"In Review" kind:TicketKindUnderWay], nil)];
    return ticket;
}
- (void)search:(NSString *)words done:(TicketsDone)done {
    done(@[[self ticket:@"ABC-1" site:@"one.example"]], [TrackerAnswer done]);
}
// Every ticket you can see: ABC-1 to ABC-3, or only ABC-3 changed since; told to end otherwise as a read is.
- (void)everyTicketSince:(NSDate *)since done:(TicketsDone)done {
    TrackerEnd end = self.nextEnd;
    self.nextEnd = TrackerEndDone;
    if (self.signInState != TrackerSignedIn) end = TrackerEndSignIn;
    if (end != TrackerEndDone)
        return done(@[], [TrackerAnswer end:end why:end == TrackerEndSignIn ? @"Sign in first" : @"Couldn't reach it"]);
    NSMutableArray *found = [NSMutableArray array];
    for (NSString *key in since ? @[@"ABC-3"] : @[@"ABC-1", @"ABC-2", @"ABC-3"]) {
        Ticket *ticket = [self ticket:key site:@"one.example"];
        TicketPerson *reporter = [TicketPerson new];
        reporter.personId = @"made-up-1";
        reporter.name = @"Made-up reporter";
        ticket.reporter = reporter;
        ticket.updated = @"2030-01-08T09:15:00Z";
        [found addObject:ticket];
    }
    TrackerAnswer *answer = [TrackerAnswer done];
    answer.more = !since;
    done(found, answer);
}
- (void)readWhole:(NSString *)key site:(NSString *)site done:(TicketDone)done {
    [self read:key site:site done:^(Ticket *ticket, TrackerAnswer *answer) {
        TicketMoveMade *move = [TicketMoveMade new];
        move.from = @"Ready";
        move.to = @"Doing";
        move.at = @"2030-01-07T10:00:00Z";
        move.by = [TicketPerson new];
        move.by.personId = @"made-up-2";
        move.by.name = @"Made-up mover";
        ticket.moves = ticket ? @[move] : nil;
        done(ticket, answer);
    }];
}
- (void)read:(NSString *)key site:(NSString *)site done:(TicketDone)done {
    TrackerEnd end = self.nextEnd;
    self.nextEnd = TrackerEndDone;
    if (self.signInState != TrackerSignedIn) end = TrackerEndSignIn;
    BOOL known = [@[@"ABC-1", @"ABC-2", @"ABC-3"] containsObject:key]
        || ([key hasPrefix:@"ABC-"] && [key substringFromIndex:4].integerValue >= 4
            && [key substringFromIndex:4].integerValue < 4 + self.made);
    if (end == TrackerEndDone && !known) end = TrackerEndNotFound;
    if (end == TrackerEndDone) return done([self ticket:key site:site], [TrackerAnswer done]);
    TrackerAnswer *answer = [TrackerAnswer end:end why:end == TrackerEndSlowDown ? @"Asked to slow down"
                             : end == TrackerEndSignIn ? @"Sign in first" : end == TrackerEndNotFound ? @"No such ticket"
                             : @"Couldn't reach it"];
    if (end == TrackerEndSlowDown) answer.retryAt = [NSDate dateWithTimeIntervalSinceNow:600];
    done(nil, answer);
}
// As a tracker takes a step: the ticket read first, a step it no longer lists never taken, and the ticket as it stands
// after.
- (void)take:(NSString *)stepId of:(NSString *)key site:(NSString *)site note:(NSString *)note
      fields:(NSDictionary *)fields done:(TicketDone)done {
    TrackerEnd end = self.nextEnd;
    self.nextEnd = TrackerEndDone;
    if (self.signInState != TrackerSignedIn) end = TrackerEndSignIn;
    // One turned away as it is says why in the tracker's own words, made up here, with some to escape.
    if (end == TrackerEndRefused) {
        TrackerAnswer *answer = [TrackerAnswer end:end why:@"It turned it away"];
        answer.trackerSays = @"Fill in <Reviewer> first";
        return done([self ticket:key site:site], answer);
    }
    if (end != TrackerEndDone)
        return done(nil, [TrackerAnswer end:end why:end == TrackerEndSignIn ? @"Sign in first" : @"Couldn't reach it"]);
    Ticket *now = [self ticket:key site:site];
    TicketStep *step = nil;
    for (TicketStep *each in now.steps)
        if ([each.stepId isEqual:stepId]) step = each;
    if (!step) return done(now, [TrackerAnswer end:TrackerEndStepGone
                                               why:[NSString stringWithFormat:@"%@ is %@ already", key,
                                                                              now.state.name]]);
    self.moved[key] = step.to;
    NSData *given = [NSJSONSerialization dataWithJSONObject:fields ?: @{} options:NSJSONWritingSortedKeys error:nil];
    [self.took addObject:[NSString stringWithFormat:@"%@ to %@, with %@ and fields %@", key, step.to.name,
                          note ? [NSString stringWithFormat:@"the note “%@”", note] : @"no note",
                          [[NSString alloc] initWithData:given encoding:NSUTF8StringEncoding]]];
    done([self ticket:key site:site], [TrackerAnswer done]);
}
- (void)addNote:(NSString *)note to:(NSString *)key site:(NSString *)site done:(void (^)(TrackerAnswer *))done {
    done([TrackerAnswer end:TrackerEndFailed why:@"Not in this run"]);
}
- (void)newTicketOptions:(NSString *)group site:(NSString *)site done:(void (^)(NSDictionary *, TrackerAnswer *))done {
    TrackerEnd end = self.nextEnd;
    self.nextEnd = TrackerEndDone;
    if (self.signInState != TrackerSignedIn) end = TrackerEndSignIn;
    if (end == TrackerEndDone && ![group isEqual:@"ABC"]) end = TrackerEndNotFound;
    if (end != TrackerEndDone)
        return done(nil, [TrackerAnswer end:end why:end == TrackerEndSignIn ? @"Sign in first"
                                                   : end == TrackerEndNotFound ? @"No such group" : @"Couldn't reach it"]);
    done(@{@"group": group, @"kind": @"board", @"types": @[@"Task", @"Bug"]}, [TrackerAnswer done]);
}
- (void)create:(NSDictionary *)draft site:(NSString *)site done:(TicketDone)done {
    TrackerEnd end = self.nextEnd;
    self.nextEnd = TrackerEndDone;
    if (self.signInState != TrackerSignedIn) end = TrackerEndSignIn;
    if (end != TrackerEndDone)
        return done(nil, [TrackerAnswer end:end why:end == TrackerEndSignIn ? @"Sign in first"
                                                   : end == TrackerEndRefused ? @"Turned away as it is"
                                                   : @"Couldn't reach it"]);
    NSString *key = [NSString stringWithFormat:@"ABC-%ld", (long)(4 + self.made++)];
    NSData *given = [NSJSONSerialization dataWithJSONObject:draft options:NSJSONWritingSortedKeys error:nil];
    [self.took addObject:[NSString stringWithFormat:@"made %@ on %@, from %@", key, site,
                          [[NSString alloc] initWithData:given encoding:NSUTF8StringEncoding]]];
    if (self.unread) {
        self.unread = NO;
        Ticket *made = [Ticket new];
        made.tracker = self.trackerName;
        made.site = site;
        made.key = key;
        return done(made, [TrackerAnswer done]);
    }
    done([self ticket:key site:site], [TrackerAnswer done]);
}
@end

static NSString *Line(id json) {
    if (!json) return @"none";
    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingSortedKeys
                                                                       | NSJSONWritingWithoutEscapingSlashes error:nil];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"?";
}

// Each step's line out of the step: `row <id>` (a session running in this process) or `ended <id>` (one whose process
// has gone); `start <id> <key>`, a start from the card with that ticket on it; `ask <id> ticket`, `ask <id> ticket-use
// <key>` and `ask <id> ticket-link <link>`; `move <id> <step> [<json>]`, ticket-move with that on stdin, and `stop
// <id> <step> <why>`, ticket-stop (`too-long` for a note or a why one character longer than it may be); `press <id>
// use|notNow`, and `press-move <id> move|notNow <key> <step>`, your answer on the move card that showed that; `create
// <id>`, a start from Create a ticket, `draft <id> <json>`, ticket-draft with that on stdin, `press-draft <id>
// create|check|notYet [stale]`, your answer on the new ticket's card, and `draft-cases`, the plain functions deciding
// how a draft's check and its making end, over made-up answers; `switch <id> on|off`, May Move Its Ticket ticked or unticked in the mode menu, and
// `menu <id>`, what the menu says of it and whether it's on; `rows`, each row's ticket, the rows whole for the switches
// too, `moves`, the same with only what moves show of each, and `drafts`, with only what new tickets show; `read <id>`, its ticket read again, as Try Again does; `fails <slow|signIn|failed|refused|unread>`, the next read or move;
// `elsewhere <key> <step>`, someone else taking that step, and `afresh <key>`, the ticket put back where it started;
// `took`, what the tracker was given for each move since; `signout` and `signin`, which the next `rows` (or `moves`,
// `drafts`) tells the module of; `kept`, the files kept; `hand-kept <id> <key>`, a
// file written by hand for this process; `relaunch`, a new copy reading what's kept; `log`, whether panel.log says any
// ticket's, note's, field's or why's words; and `logged`, its lines since the last, without their times. The first copy
// is the core's own, as May Move Its Ticket is its switch: the switch is tried before any relaunch.
static int PrintTickets(Core *core, NSArray<NSString *> *steps) {
    if (HomeIsYourOwn()) {
        fprintf(stderr, "--print-tickets runs only in a throwaway home\n");
        return 2;
    }
    // The sessions here run in this process, which works in no project until a step puts it in one (process-in), so a
    // session given a ticket marks none but the test's own.
    chdir("/");
    SampleTracker *sample = [SampleTracker new];
    sample.signInState = TrackerSignedIn;
    sample.moved = [NSMutableDictionary dictionary];
    sample.took = [NSMutableArray array];
    NSString *folder = AppDir(@"tickets");
    __block TicketsModule *own = nil;
    for (id each in core.modules.all)
        if ([each isKindOfClass:TicketsModule.class]) own = each;
    TicketsModule *(^make)(void) = ^TicketsModule *{
        TicketsModule *module = own ?: [[TicketsModule alloc] initWithCore:core];
        own = nil;
        module.givenTrackers = @[sample];
        [module keepIn:folder];
        return module;
    };
    TicketsModule *tickets = make();
    NSMutableDictionary<NSString *, Row *> *rows = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    NSString *(^base64)(NSString *) = ^NSString *(NSString *text) {
        return [[text dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
    };
    NSUInteger logRead = 0;
    for (NSString *step in steps) {
        NSArray<NSString *> *words = [step componentsSeparatedByString:@" "];
        NSString *verb = words.firstObject, *sessionId = words.count > 1 ? words[1] : @"";
        NSString *rest = words.count > 2 ? [[words subarrayWithRange:NSMakeRange(2, words.count - 2)]
                                            componentsJoinedByString:@" "] : @"";
        printf("== %s\n", step.UTF8String);
        if ([verb isEqual:@"row"] || [verb isEqual:@"ended"]) {
            Row *row = [Row new];
            row.sessionId = sessionId;
            row.pid = [verb isEqual:@"row"] ? getpid() : 0;
            if (!rows[sessionId]) [order addObject:sessionId];
            rows[sessionId] = row;
        } else if ([verb isEqual:@"create"]) {
            [tickets started:sessionId with:@{@"tracker": @"Sample", @"site": @"one.example", @"create": @YES}];
        } else if ([verb isEqual:@"draft"]) {
            NSString *given = [rest isEqual:@"too-long"]
                ? [NSString stringWithFormat:@"{\"title\": \"%@\", \"group\": \"ABC\", \"type\": \"Task\"}",
                   [@"" stringByPaddingToLength:kLongestTicketTitle + 1 withString:@"a" startingAtIndex:0]]
                : rest;
            NSDictionary *asked = given.length ? @{@"ask": @"ticket-draft", @"draft64": base64(given)}
                                               : @{@"ask": @"ticket-draft"};
            printf("%s\n", [tickets draft:asked from:rows[sessionId]].UTF8String);
        } else if ([verb isEqual:@"draft-cases"]) {
            // The plain functions deciding how a draft's check and its making end, over made-up answers.
            TicketDraft *(^fresh)(void) = ^TicketDraft *{
                TicketDraft *draft = [TicketDraft new];
                draft.group = @"ABC";
                draft.site = @"one.example";
                draft.type = @"bug";
                return draft;
            };
            NSString *(^shown)(TicketDraft *) = ^NSString *(TicketDraft *draft) {
                return [NSString stringWithFormat:@"type %@, %@%@%@", draft.type, draft.checked ? @"checked" : @"unchecked",
                        draft.groupKind ? [@", a " stringByAppendingString:draft.groupKind] : @"",
                        draft.problem ? [NSString stringWithFormat:@", waits on %ld (%@)%@", (long)draft.problem.end,
                                         draft.problem.why, draft.mayBeMade ? @", may have been made" : @""] : @""];
            };
            NSDictionary *types = @{@"kind": @"board", @"types": @[@"Task", @"Bug"]};
            NSArray *checks = @[@[@"its type, spelled as the tracker does", types, [TrackerAnswer done]],
                                @[@"a type it doesn't take", @{@"types": @[@"Task"]}, [TrackerAnswer done]],
                                @[@"no types said: any", @{}, [TrackerAnswer done]],
                                @[@"no such group", NSNull.null, [TrackerAnswer end:TrackerEndNotFound why:@"No such group"]],
                                @[@"couldn't ask", NSNull.null, [TrackerAnswer end:TrackerEndFailed why:@"Couldn't reach it"]],
                                @[@"the sign-in ran out", NSNull.null, [TrackerAnswer end:TrackerEndSignIn why:@"Run out"]]];
            for (NSArray *each in checks) {
                TicketDraft *draft = fresh();
                NSString *told = TicketDraftChecked(draft, AsRecord(each[1]), each[2]);
                printf("checked, %s: %s\n", [each[0] UTF8String], (told ?: shown(draft)).UTF8String);
            }
            NSArray *makes = @[@[@"made", @"ABC-9", [TrackerAnswer done]],
                               @[@"turned away", NSNull.null, [TrackerAnswer end:TrackerEndRefused why:@"Turned away"]],
                               @[@"no answer after it was sent", NSNull.null,
                                 [TrackerAnswer end:TrackerEndFailed why:@"Couldn't reach it"]],
                               @[@"answered with no key", NSNull.null, [TrackerAnswer done]],
                               @[@"the sign-in ran out first", NSNull.null, [TrackerAnswer end:TrackerEndSignIn why:@"Run out"]],
                               @[@"asked to slow down first", NSNull.null,
                                 [TrackerAnswer end:TrackerEndSlowDown why:@"Slow down"]],
                               @[@"an end it doesn't name", NSNull.null,
                                 [TrackerAnswer end:(TrackerEnd)99 why:@"Something new"]]];
            NSArray *ends = @[@"made", @"sent back", @"waits"];
            for (NSArray *each in makes) {
                TicketDraft *draft = fresh();
                draft.checked = YES;
                NSString *told = nil;
                TicketDraftEnd ended = TicketDraftMade(draft, AsText(each[1]), each[2], &told);
                printf("made, %s: %s%s\n", [each[0] UTF8String], [ends[ended] UTF8String],
                       (told ? [@": " stringByAppendingString:told]
                             : ended == TicketDraftWaits ? [@": " stringByAppendingString:shown(draft)] : @"").UTF8String);
            }
        } else if ([verb isEqual:@"press-draft"]) {
            BOOL stale = words.count > 3 && [words[3] isEqual:@"stale"];
            [tickets draftAnswer:words.count > 2 ? words[2] : @"" for:sessionId
                              at:stale ? @0 : [tickets draftAskedAt:sessionId]];
        } else if ([verb isEqual:@"start"]) {
            [tickets started:sessionId with:@{@"tracker": @"Sample", @"key": rest, @"site": @"one.example"}];
        } else if ([verb isEqual:@"ask"]) {
            Row *row = rows[sessionId];
            NSString *word = words.count > 2 ? words[2] : @"";
            NSString *given = words.count > 3 ? words[3] : @"";
            NSMutableDictionary *listAsked = [@{@"ask": @"tickets"} mutableCopy];
            for (NSUInteger i = 3; i + 1 < words.count; i += 2)
                listAsked[[words[i] isEqual:@"--since"] ? @"since" : [words[i] isEqual:@"--site"] ? @"site" : @"full"] = words[i + 1];
            if ([word isEqual:@"tickets"] && [given isEqual:@"--since"] && [words.lastObject isEqual:@"now"])
                listAsked[@"since"] = [[NSISO8601DateFormatter new] stringFromDate:[NSDate dateWithTimeIntervalSinceNow:-60]];
            NSString *answer = [word isEqual:@"ticket"] ? [tickets ticketFor:row]
                : [word isEqual:@"tickets"] ? [tickets ticketsFor:row process:row.pid asked:listAsked]
                : [word isEqual:@"ticket-use"] ? [tickets use:@{@"ask": word, @"key": given} from:row]
                : [word isEqual:@"ticket-link"] ? [tickets use:@{@"ask": @"ticket-use", @"link64":
                      [[given dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0]} from:row]
                : @"?";
            // When a list was read, which changes from run to run, is left out.
            NSRegularExpression *when = [NSRegularExpression regularExpressionWithPattern:@"\"(readAt|since)\":\"[^\"]*\""
                                                                                  options:0 error:nil];
            if ([word isEqual:@"tickets"])
                answer = [when stringByReplacingMatchesInString:answer options:0 range:NSMakeRange(0, answer.length)
                                                   withTemplate:@"\"$1\":\"(when)\""];
            printf("%s\n", answer.UTF8String);
        } else if ([verb isEqual:@"in"]) {
            // `in <id> <folder>`: the session's record says it works there, with that folder's git, as a row has it.
            rows[sessionId].cwd = rest;
            rows[sessionId].git = GitInfo(rest);
        } else if ([verb isEqual:@"reads-said"]) {
            // `reads-said <folder>`: what the new conversation card's line says Start there would also do.
            printf("%s\n", Line([tickets readsSaidFor:sessionId]).UTF8String);
        } else if ([verb isEqual:@"process-in"]) {
            // `process-in <folder>`: this process, which every session here runs in, works there, as macOS says.
            printf("%s\n", chdir(sessionId.fileSystemRepresentation) == 0 ? "moved" : "no such folder");
        } else if ([verb isEqual:@"off"] || [verb isEqual:@"on"]) {
            // `off <folder>`, `on <folder>`: your press of that project's switch in Settings ▸ Tickets.
            [tickets setReads:[verb isEqual:@"on"] for:sessionId];
            printf("%s reads %s\n", sessionId.lastPathComponent.UTF8String, [tickets reads:sessionId] ? "your tickets" : "none");
        } else if ([verb isEqual:@"settings"]) {
            // `settings <folder>`: what the project's page in Settings ▸ Tickets has of the tickets module's, each choice
            // ticked or not, with what picking the other would say first; and the projects it has a page for.
            printf("projects: %s\n", Line([tickets projectsWithSettings]).UTF8String);
            for (AppGroup *group in [tickets settingsForProject:sessionId])
                for (AppChoice *choice in group.rows) {
                    printf("%s (%s), its foot: %s\n", group.title.UTF8String, choice.title.UTF8String,
                           (group.foot ?: @"none").UTF8String);
                    for (NSDictionary *each in choice.choices())
                        printf("  [%s] %s: %s\n", [each[@"id"] isEqual:choice.picked()] ? "x" : " ",
                               [each[@"name"] UTF8String], [each[@"help"] UTF8String]);
                    for (NSDictionary *each in choice.choices()) {
                        NSDictionary *first = choice.confirm(each[@"id"]);
                        if (first) printf("  picking %s first says: before %s; after %s; %s\n", [each[@"id"] UTF8String],
                                          [first[@"before"] UTF8String], [first[@"after"] UTF8String],
                                          [first[@"keep"] UTF8String]);
                    }
                }
        } else if ([verb isEqual:@"pick-reads"]) {
            // `pick-reads <folder> on|off`: Change pressed after the before and after, as the back's choice makes it.
            for (AppGroup *group in [tickets settingsForProject:sessionId])
                for (AppChoice *choice in group.rows) choice.pick(rest);
            printf("%s reads %s\n", sessionId.lastPathComponent.UTF8String, [tickets reads:sessionId] ? "your tickets" : "none");
        } else if ([verb isEqual:@"reading"]) {
            // What's kept of which projects read no tickets, and who may read the file.
            NSString *path = AppDir(@"ticket-reading.json");
            NSDictionary *kept = AsRecord(ReadJSON(path));
            NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
            printf("%s (%o)\n", kept ? Line(kept).UTF8String : "none",
                   (unsigned)[attributes[NSFilePosixPermissions] unsignedShortValue]);
        } else if ([verb isEqual:@"move"] || [verb isEqual:@"stop"]) {
            Row *row = rows[sessionId];
            NSString *stepId = words.count > 2 ? words[2] : @"";
            NSString *given = words.count > 3 ? [[words subarrayWithRange:NSMakeRange(3, words.count - 3)]
                                                 componentsJoinedByString:@" "] : @"";
            NSMutableDictionary *asked = [@{@"ask": [@"ticket-" stringByAppendingString:verb], @"id": stepId}
                                          mutableCopy];
            // One character longer than a note or a why may be, said short.
            NSString *tooLong = [@"" stringByPaddingToLength:kLongestTicketNote + 1 withString:@"a" startingAtIndex:0];
            if ([given isEqual:@"too-long"])
                given = [verb isEqual:@"move"] ? [NSString stringWithFormat:@"{\"note\": \"%@\"}", tooLong] : tooLong;
            if (given.length) asked[[verb isEqual:@"move"] ? @"note64" : @"why64"] = base64(given);
            NSString *answer = [verb isEqual:@"move"] ? [tickets move:asked from:row process:row.pid]
                                                      : [tickets stop:asked from:row];
            printf("%s\n", answer.UTF8String);
        } else if ([verb isEqual:@"press"]) {
            [tickets answer:rest for:sessionId];
        } else if ([verb isEqual:@"press-move"]) {
            // As the card would send it, with when its move was asked; `stale` as a card drawn for the one before.
            NSString *act = words.count > 2 ? words[2] : @"", *key = words.count > 3 ? words[3] : @"";
            BOOL stale = words.count > 5 && [words[5] isEqual:@"stale"];
            [tickets moveAnswer:act for:sessionId key:key step:words.count > 4 ? words[4] : @""
                             at:stale ? @0 : [tickets moveAskedAt:sessionId]];
        } else if ([verb isEqual:@"switch"]) {
            BOOL on = [rest isEqual:@"on"];
            BOOL done = [core.allowed set:@"moveTicket" for:rows[sessionId] on:on];
            printf("%s\n", done ? (on ? "on" : "off") : "not changed");
        } else if ([verb isEqual:@"menu"]) {
            Row *row = rows[sessionId];
            SessionSwitch *move = nil;
            for (SessionSwitch *each in [core.allowed switchesFor:row])
                if ([each.key isEqual:@"moveTicket"]) move = each;
            NSString *says = !move ? @"not in its menu" : move.whyNot(row)
                ? [NSString stringWithFormat:@"%@, greyed: %@", move.title, move.whyNot(row)]
                : [NSString stringWithFormat:@"%@: %@", move.title, (move.says ? move.says(row) : nil) ?: move.line];
            printf("%s\n%s\n", says.UTF8String,
                   ([core.allowed whyOff:@"moveTicket" for:row from:row.pid] ?: @"on").UTF8String);
        } else if ([verb isEqual:@"rows"] || [verb isEqual:@"moves"] || [verb isEqual:@"drafts"]) {
            NSMutableArray *listed = [NSMutableArray array];
            for (NSString *id_ in order) [listed addObject:rows[id_]];
            [tickets rows:listed phase:RowPhaseListed];
            [core.allowed rowsListed:listed];
            for (Row *row in listed) {
                // Only what moves show: where it stands, the move card, the last move and the steps marked.
                NSDictionary *bound = row.ticket[@"bound"], *shown = row.ticket;
                // Only what new tickets show: the ticket it works on, "New ticket", and the card for Create Ticket.
                if ([verb isEqual:@"drafts"]) {
                    NSMutableDictionary *some = [NSMutableDictionary dictionary];
                    some[@"key"] = bound[@"key"];
                    some[@"creating"] = row.ticket[@"creating"];
                    some[@"draft"] = row.ticket[@"draft"];
                    shown = some.count ? some : nil;
                } else if ([verb isEqual:@"moves"] && bound) {
                    NSMutableDictionary *some = [NSMutableDictionary dictionary];
                    for (NSString *name in @[@"key", @"moved", @"stopped"]) some[name] = bound[name];
                    some[@"state"] = bound[@"state"][@"name"];
                    some[@"move"] = row.ticket[@"move"];
                    shown = some;
                }
                printf("%s: %s\n", row.sessionId.UTF8String, Line(shown).UTF8String);
            }
        } else if ([verb isEqual:@"fails"]) {
            sample.unread = [sessionId isEqual:@"unread"];
            sample.nextEnd = [sessionId isEqual:@"slow"] ? TrackerEndSlowDown : [sessionId isEqual:@"signIn"]
                ? TrackerEndSignIn : [sessionId isEqual:@"refused"] ? TrackerEndRefused
                : [sessionId isEqual:@"unread"] ? TrackerEndDone : TrackerEndFailed;
        } else if ([verb isEqual:@"elsewhere"]) {
            Ticket *now = [sample ticket:sessionId site:@"one.example"];
            for (TicketStep *step in now.steps)
                if ([step.stepId isEqual:rest]) sample.moved[sessionId] = step.to;
        } else if ([verb isEqual:@"afresh"]) {
            [sample.moved removeObjectForKey:sessionId];
        } else if ([verb isEqual:@"read"]) {
            [tickets read:sessionId after:0 ignoringWait:YES];
        } else if ([verb isEqual:@"took"]) {
            for (NSString *line in sample.took) printf("%s\n", line.UTF8String);
            if (!sample.took.count) printf("nothing taken\n");
            [sample.took removeAllObjects];
        } else if ([verb isEqual:@"signout"]) {
            [sample signOut];
        } else if ([verb isEqual:@"signin"]) {
            [sample signIn:^(TrackerSignIn state, NSString *why) {}];
        } else if ([verb isEqual:@"kept"]) {
            NSArray *names = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil]
                              sortedArrayUsingSelector:@selector(compare:)];
            for (NSString *name in names) {
                NSDictionary *record = AsRecord(ReadJSON([folder stringByAppendingPathComponent:name]));
                NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:
                                            [folder stringByAppendingPathComponent:name] error:nil];
                printf("%s: %s %s, for %s, only you can read it: %s\n", name.UTF8String, AsText(record[@"tracker"]).UTF8String,
                       AsText(record[@"key"]).UTF8String,
                       AsNumber(record[@"pid"]).intValue == getpid() ? "this process" : "another process",
                       [attributes[NSFilePosixPermissions] isEqual:@0600] ? "yes" : "no");
            }
            if (!names.count) printf("nothing kept\n");
        } else if ([verb isEqual:@"hand-kept"]) {
            NSDictionary *record = @{@"tracker": @"Sample", @"site": @"one.example", @"key": rest, @"pid": @(getpid()),
                                     @"processStart": @(ProcessStartedAt(getpid()))};
            [[NSJSONSerialization dataWithJSONObject:record options:0 error:nil]
             writeToFile:[folder stringByAppendingPathComponent:[sessionId stringByAppendingPathExtension:@"json"]]
              atomically:YES];
        } else if ([verb isEqual:@"relaunch"]) {
            tickets = make();
        } else if ([verb isEqual:@"log"]) {
            NSString *log = [NSString stringWithContentsOfFile:AppDir(@"panel.log") encoding:NSUTF8StringEncoding error:nil];
            printf("panel.log %s a ticket's words\n", [log containsString:@"Made-up words"] ? "HAS" : "has none of");
            printf("panel.log %s a ticket's description\n",
                   [log containsString:@"Made-up description"] ? "HAS" : "has none of");
            // Nor does any file Whozmove keeps: its description goes only to the session, in its answer.
            BOOL kept = NO;
            NSDirectoryEnumerator *files = [NSFileManager.defaultManager enumeratorAtPath:AppDir(@"")];
            for (NSString *name in files) {
                NSString *words = [NSString stringWithContentsOfFile:[AppDir(@"") stringByAppendingPathComponent:name]
                                                            encoding:NSUTF8StringEncoding error:nil];
                kept = kept || [words containsString:@"Made-up description"];
            }
            printf("Whozmove's folder %s a ticket's description in any file\n", kept ? "HAS" : "has none of");
            // The words the moves' tests give as a note, a field's value and a person's step's why, and the tracker's
            // own words for a move it turned away.
            BOOL said = NO;
            for (NSString *words in @[@"pull request", @"Fixed", @"Only QA", @"Reviewer"])
                said = said || [log containsString:words];
            printf("panel.log %s a note's, a field's or a why's words\n", said ? "HAS" : "has none of");
            // The words the new tickets' tests give as a title, a description and a priority.
            BOOL drafted = NO;
            for (NSString *words in @[@"Saved cards", @"every saved card", @"Highest"])
                drafted = drafted || [log containsString:words];
            printf("panel.log %s a new ticket's words\n", drafted ? "HAS" : "has none of");
        } else if ([verb isEqual:@"logged"]) {
            NSString *log = [NSString stringWithContentsOfFile:AppDir(@"panel.log") encoding:NSUTF8StringEncoding
                                                         error:nil] ?: @"";
            NSArray<NSString *> *lines = [log componentsSeparatedByString:@"\n"];
            for (NSUInteger i = logRead; i < lines.count; i++) {
                NSRange gap = [lines[i] rangeOfString:@"  "];
                if (gap.location != NSNotFound) printf("%s\n", [lines[i] substringFromIndex:NSMaxRange(gap)].UTF8String);
            }
            logRead = lines.count ? lines.count - 1 : 0;
        } else {
            fprintf(stderr, "--print-tickets: no step %s\n", verb.UTF8String);
            return 2;
        }
    }
    return 0;
}

NSDictionary<NSString *, PrintMode> *TicketsPrintModes(void) {
    return @{@"--print-tickets": ^int(Core *core, NSArray<NSString *> *arguments) { return PrintTickets(core, arguments); }};
}
