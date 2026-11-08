// TicketBindings: which ticket each session works on, and what the row and the session are told about it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "TicketBindings.h"
#import "Files.h"

@implementation TicketMove
@end
@implementation TicketBinding
@end
@implementation TicketOffer
@end
@implementation TicketDraft
@end

static NSNumber *Ms(NSDate *date) {
    return date ? @(floor(date.timeIntervalSince1970 * 1000)) : nil;
}

// Why the last read didn't read it, as the row's tag says it: signing in again, asked to slow down (until when), or
// anything else, in the tracker's words.
static NSDictionary *ProblemShown(TrackerAnswer *problem) {
    if (!problem || problem.ok) return nil;
    NSString *kind = problem.end == TrackerEndSignIn ? @"signIn" : problem.end == TrackerEndAsksMac ? @"allow"
        : problem.end == TrackerEndSlowDown ? @"slow" : @"failed";
    NSMutableDictionary *shown = [@{@"kind": kind, @"why": problem.why ?: @""} mutableCopy];
    if (problem.retryAt) shown[@"retryAt"] = Ms(problem.retryAt);
    return shown;
}

NSDictionary *TicketShown(TicketBinding *bound, TicketOffer *offer, TicketDraft *draft, NSString *creating) {
    NSMutableDictionary *shown = [NSMutableDictionary dictionary];
    if (bound) {
        // The ticket as read, but its site, key and address are always the binding's own, made from its site and key.
        NSMutableDictionary *b = [([bound.ticket json] ?: @{}) mutableCopy];
        [b addEntriesFromDictionary:@{@"tracker": bound.tracker ?: @"", @"site": bound.site ?: @"", @"key": bound.key ?: @""}];
        if (bound.link) b[@"link"] = bound.link;
        else [b removeObjectForKey:@"link"];
        if (bound.readAt) b[@"readAt"] = Ms(bound.readAt);
        if (bound.reading) b[@"reading"] = @YES;
        NSDictionary *problem = ProblemShown(bound.problem);
        if (problem) b[@"problem"] = problem;
        if (bound.moved) b[@"moved"] = bound.moved;
        if (bound.stopped.count) b[@"stopped"] = [bound.stopped copy];
        shown[@"bound"] = b;
        // A move waiting for your Move It, as its card shows it: where it leads, its note and its fields, whole.
        TicketMove *move = bound.move;
        if (move && !move.itself) {
            NSMutableDictionary *m = [@{@"key": bound.key ?: @"", @"stepId": move.stepId ?: @"",
                                        @"name": move.name ?: @"", @"fields": move.shown ?: @[]} mutableCopy];
            if (move.to) m[@"to"] = @{@"name": move.to.name ?: @"", @"kind": TicketKindWord(move.to.kind)};
            if (move.note.length) m[@"note"] = move.note;
            if (move.instead) m[@"instead"] = move.instead;
            if (move.moving) m[@"moving"] = @YES;
            if (move.at) m[@"at"] = Ms(move.at);
            NSDictionary *failed = ProblemShown(move.problem);
            if (failed) m[@"problem"] = failed;
            shown[@"move"] = m;
        }
    }
    if (offer) {
        NSMutableDictionary *o = [@{@"tracker": offer.tracker ?: @"", @"site": offer.site ?: @"", @"key": offer.key ?: @""}
                                  mutableCopy];
        if (offer.link) o[@"link"] = offer.link;
        if (offer.instead) o[@"instead"] = offer.instead;
        if (offer.again) o[@"again"] = @YES;
        // What the card shows of the offered ticket: how it stands and its title, or why it couldn't be read.
        NSDictionary *read = [offer.ticket json];
        for (NSString *name in @[@"title", @"type", @"state"])
            if (read[name]) o[name] = read[name];
        NSDictionary *problem = ProblemShown(offer.problem);
        if (problem) o[@"problem"] = problem;
        shown[@"offer"] = o;
    }
    // A new ticket waiting for your Create Ticket, as its card shows it: every part of it the session gave, whole.
    if (draft) {
        NSMutableDictionary *d = [@{@"tracker": draft.tracker ?: @"", @"site": draft.site ?: @"",
                                    @"group": draft.group ?: @"", @"type": draft.type ?: @"",
                                    @"title": draft.title ?: @""} mutableCopy];
        if (draft.groupKind) d[@"groupKind"] = draft.groupKind;
        if (draft.details.length) d[@"description"] = draft.details;
        if (draft.priority.length) d[@"priority"] = draft.priority;
        if (draft.parent.length) d[@"parent"] = draft.parent;
        if (bound.key) d[@"instead"] = bound.key;
        if (draft.again) d[@"again"] = @YES;
        if (draft.checking) d[@"checking"] = @YES;
        if (draft.checked) d[@"checked"] = @YES;
        if (draft.mayBeMade) d[@"mayBeMade"] = @YES;
        if (draft.creating) d[@"creating"] = @YES;
        if (draft.at) d[@"at"] = Ms(draft.at);
        NSDictionary *failed = ProblemShown(draft.problem);
        if (failed) d[@"problem"] = failed;
        shown[@"draft"] = d;
    }
    if (creating && !bound) shown[@"creating"] = @{@"tracker": creating};
    return shown.count ? shown : nil;
}

static NSString *Line(id json) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:json
                                                   options:NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes
                                                     error:nil];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}

NSString *TicketAnswer(TicketBinding *bound, TicketOffer *offer, NSString *declined, NSString *signIn) {
    if (offer) return [NSString stringWithFormat:@"waiting: for the user to answer “Work on %@ %@?” on this session's "
                       @"row", offer.key, offer.instead ? @"instead" : @"here"];
    if (declined && bound) return [NSString stringWithFormat:@"not used: the user chose Not Now for %@, so carry on "
                                   @"with %@", declined, bound.key];
    if (!bound) {
        if (declined) return [NSString stringWithFormat:@"not used: the user chose Not Now for %@, so carry on "
                              @"without it", declined];
        return @"refused: this session has no ticket. The user gives it one on the new conversation card, or ask with "
               @"ask-panel.sh ticket-use <key or link>, which they answer on its row";
    }
    if (bound.ticket) {
        NSMutableDictionary *answer = [@{@"ticket": TicketShown(bound, nil, nil, nil)[@"bound"]} mutableCopy];
        NSMutableDictionary *ticket = [answer[@"ticket"] mutableCopy];
        [ticket removeObjectForKey:@"readAt"];
        [ticket removeObjectForKey:@"reading"];
        [ticket removeObjectForKey:@"problem"];
        [ticket removeObjectForKey:@"moved"];
        answer[@"ticket"] = ticket;
        // Its move: waiting while it's on the row or being taken, then how it went, once.
        if (bound.move) answer[@"move"] = @{@"waiting": bound.move.to.name ?: bound.move.name ?: @""};
        else if (bound.told) answer[@"move"] = bound.told;
        NSISO8601DateFormatter *iso = [NSISO8601DateFormatter new];
        answer[@"readAt"] = [iso stringFromDate:bound.readAt ?: NSDate.date];
        // Read before, and not read again just now: said with it, so the session knows it may be out of date.
        if (bound.problem && !bound.problem.ok) answer[@"notReadAgain"] = bound.problem.why ?: @"";
        return Line(answer) ?: @"can't now: couldn't put the ticket in words";
    }
    TrackerAnswer *problem = bound.problem;
    if (bound.reading || !problem || problem.ok) return [NSString stringWithFormat:@"waiting: reading %@", bound.key];
    if (problem.end == TrackerEndSlowDown)
        return [NSString stringWithFormat:@"waiting: %@ asked Whozmove to slow down, so %@ is read again in a while",
                signIn ?: bound.tracker, bound.key];
    if (problem.end == TrackerEndAsksMac)
        return [NSString stringWithFormat:@"can't now: %@ can't be read until the user presses Allow on Whozmove's "
                @"panel, so macOS gives this build of Whozmove the sign-in with %@", bound.key, signIn ?: bound.tracker];
    if (problem.end == TrackerEndSignIn)
        return [NSString stringWithFormat:@"can't now: %@ can't be read until the user signs in with %@ again, on "
                @"Whozmove's panel", bound.key, signIn ?: bound.tracker];
    return [NSString stringWithFormat:@"can't now: couldn't read %@: %@", bound.key, problem.why ?: @"no reason given"];
}

NSDictionary *TicketKept(TicketBinding *bound, pid_t pid, long long processStart) {
    if (!bound.tracker.length || !bound.key.length || pid <= 0 || processStart <= 0) return nil;
    return @{@"tracker": bound.tracker, @"site": bound.site ?: @"", @"key": bound.key, @"pid": @(pid),
             @"processStart": @(processStart)};
}

TicketOffer *TicketKeptOffer(NSDictionary *kept, pid_t pid, long long processStart) {
    NSString *tracker = AsText(kept[@"tracker"]), *key = AsText(kept[@"key"]);
    if (!tracker.length || !key.length || pid <= 0 || AsNumber(kept[@"pid"]).intValue != pid
        || AsNumber(kept[@"processStart"]).longLongValue != processStart)
        return nil;
    TicketOffer *offer = [TicketOffer new];
    offer.tracker = tracker;
    offer.site = AsText(kept[@"site"]);
    offer.key = key;
    offer.again = YES;
    return offer;
}

const NSUInteger kLongestTicketNote = 2000;

// Names as a sentence lists them: "a, b and c".
NSString *TicketsListed(NSArray<NSString *> *names) {
    if (names.count < 2) return names.firstObject ?: @"";
    return [NSString stringWithFormat:@"%@ and %@", [[names subarrayWithRange:NSMakeRange(0, names.count - 1)]
                                                     componentsJoinedByString:@", "], names.lastObject];
}

// A field's value as people read it on the card, or nil with why when it isn't one the field takes (Ticket.h): text,
// one of its options when it has them, a number for a number, and a list of those only where it takes many. Its
// tracker turns it into its own shape, so nothing here knows one.
static NSString *ValueShown(TicketField *field, id value, NSString *named, NSString **why) {
    NSArray *each = AsList(value);
    if (each && !field.many) {
        *why = [NSString stringWithFormat:@"%@ takes one value, not a list", named];
        return nil;
    }
    if (!each) each = @[value];
    if (!each.count) {
        *why = [NSString stringWithFormat:@"give %@ at least one value, or leave it out", named];
        return nil;
    }
    BOOL number = [field.kind isEqual:@"number"];
    NSMutableArray<NSString *> *shown = [NSMutableArray array];
    for (id one in each) {
        // JSON's true and false come as numbers too, and are neither.
        BOOL isNumber = AsNumber(one) && CFGetTypeID((__bridge CFTypeRef)one) != CFBooleanGetTypeID();
        NSString *text = number ? (isNumber ? [one stringValue] : nil) : AsText(one);
        if (!text.length) {
            *why = [NSString stringWithFormat:@"%@ takes %@", named,
                    number ? @"a number" : field.options.count ? @"one of its options, by name" : @"text"];
            return nil;
        }
        if (field.options.count && ![field.options containsObject:text]) {
            *why = field.options.count <= 8
                ? [NSString stringWithFormat:@"%@ takes %@, not %@", named, TicketsListed(field.options), Clip(text, 40)]
                : [NSString stringWithFormat:@"%@ takes one of its options, not %@: ask-panel.sh ticket lists them",
                   named, Clip(text, 40)];
            return nil;
        }
        [shown addObject:text];
    }
    return [shown componentsJoinedByString:@", "];
}

TicketMove *TicketMoveAsked(Ticket *ticket, NSString *stepId, NSString *given, NSString **why) {
    __autoreleasing NSString *unused = nil;
    if (!why) why = &unused;
    TicketStep *step = nil;
    for (TicketStep *each in ticket.steps)
        if (stepId && [each.stepId isEqual:stepId]) step = each;
    if (!step) {
        *why = [NSString stringWithFormat:@"that isn't one of %@'s next steps now: ask-panel.sh ticket lists them",
                ticket.key];
        return nil;
    }
    NSDictionary *asked = @{};
    NSString *text = [given stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (text.length) {
        NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
        asked = AsRecord(data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil);
        if (!asked) {
            *why = @"what's on stdin isn't a JSON object: give {\"note\": \"…\", \"fields\": {…}}, or nothing";
            return nil;
        }
    }
    NSMutableArray<NSString *> *others = [NSMutableArray array];
    for (NSString *name in asked)
        if (![name isEqual:@"note"] && ![name isEqual:@"fields"]) [others addObject:Clip(name, 40)];
    if (others.count) {
        *why = [NSString stringWithFormat:@"only a note and fields go with a move, not %@",
                TicketsListed([others sortedArrayUsingSelector:@selector(compare:)])];
        return nil;
    }
    id note = asked[@"note"], fields = asked[@"fields"];
    if (note && !AsText(note)) {
        *why = @"the note is to be text";
        return nil;
    }
    note = [note stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([note length] > kLongestTicketNote) {
        *why = [NSString stringWithFormat:@"a note may be %lu characters at most", (unsigned long)kLongestTicketNote];
        return nil;
    }
    if (fields && !AsRecord(fields)) {
        *why = @"fields are to be a JSON object, each field's id with its value";
        return nil;
    }
    // Only the fields this step needs, named by their ids, and every one it must have.
    NSString *to = step.to.name ?: step.name;
    NSMutableArray<NSString *> *needed = [NSMutableArray array], *unknown = [NSMutableArray array],
                               *missing = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *shown = [NSMutableArray array];
    for (TicketField *field in step.needs) {
        NSString *named = field.name.length && ![field.name isEqual:field.fieldId]
            ? [NSString stringWithFormat:@"%@ (%@)", field.name, field.fieldId] : field.fieldId ?: @"";
        [needed addObject:named];
        id value = field.fieldId ? fields[field.fieldId] : nil;
        if (value == NSNull.null) {
            // Null clears a field, which the card would have nothing to show for.
            *why = [NSString stringWithFormat:@"%@ can't be set to null: give its value, or leave it out", named];
            return nil;
        }
        if (value) {
            NSString *seen = ValueShown(field, value, named, why);
            if (!seen) return nil;
            [shown addObject:@{@"name": field.name ?: field.fieldId, @"value": seen}];
        } else if (field.required) [missing addObject:named];
    }
    for (NSString *fieldId in fields) {
        BOOL known = NO;
        for (TicketField *field in step.needs)
            if ([field.fieldId isEqual:fieldId]) known = YES;
        if (!known) [unknown addObject:Clip(fieldId, 40)];
    }
    if (unknown.count) {
        [unknown sortUsingSelector:@selector(compare:)];
        *why = needed.count
            ? [NSString stringWithFormat:@"moving it to %@ doesn't set %@: it sets %@", to, TicketsListed(unknown),
               TicketsListed(needed)]
            : [NSString stringWithFormat:@"moving it to %@ sets no fields, so leave out %@", to, TicketsListed(unknown)];
        return nil;
    }
    if (missing.count) {
        *why = [NSString stringWithFormat:@"moving it to %@ needs %@ too, in fields", to, TicketsListed(missing)];
        return nil;
    }
    TicketMove *move = [TicketMove new];
    move.stepId = step.stepId;
    move.name = step.name;
    move.to = step.to;
    move.note = [note length] ? note : nil;
    move.fields = fields ?: @{};
    move.shown = shown;
    move.at = NSDate.date;
    return move;
}

NSString *TicketDraftWaiting(TicketDraft *draft, NSString *signIn, BOOL told) {
    NSString *who = signIn ?: draft.tracker;
    TrackerAnswer *problem = draft.problem;
    if (problem && told && draft.mayBeMade && problem.end != TrackerEndSignIn && problem.end != TrackerEndAsksMac)
        return [NSString stringWithFormat:@"waiting: for the user to look in %@ and press Create Again, or Not Yet",
                draft.group];
    if (problem && told)
        return problem.end == TrackerEndSignIn
            ? [NSString stringWithFormat:@"waiting: for the user to sign in with %@ again, on Whozmove's panel", who]
            : problem.end == TrackerEndAsksMac ? @"waiting: for the user to press Allow on Whozmove's panel"
            : @"waiting: for the user's Try Again on this session's row";
    NSString *then = @". Tell the user; ask-panel.sh ticket --wait then waits for them";
    if (problem && problem.end == TrackerEndSignIn)
        return [NSString stringWithFormat:@"can't now: the new ticket waits until the user signs in with %@ again, on "
                @"Whozmove's panel%@", who, then];
    if (problem && problem.end == TrackerEndAsksMac)
        return [NSString stringWithFormat:@"can't now: the new ticket waits until the user presses Allow on "
                @"Whozmove's panel, so macOS gives this build of Whozmove the sign-in with %@%@", who, then];
    if (problem && draft.mayBeMade)
        return [NSString stringWithFormat:@"can't now: Whozmove couldn't tell whether the new ticket was made (%@), so it "
                @"may be in %@ already: the user looks there first, and presses Create Again on the row if it isn't%@",
                problem.why ?: @"no reason given", draft.group, then];
    if (problem)
        return [NSString stringWithFormat:@"can't now: the new ticket couldn't be %@: %@. It waits on the row for the "
                @"user's Try Again%@", draft.checked ? @"created" : @"checked",
                problem.why ?: @"no reason given", then];
    if (draft.creating) return [NSString stringWithFormat:@"waiting: creating the new ticket in %@", draft.group];
    if (draft.checking) return [NSString stringWithFormat:@"waiting: checking with %@ what %@ takes", draft.tracker,
                                draft.group];
    return @"waiting: for the user to answer “Create this ticket?” on this session's row";
}

const NSUInteger kLongestTicketTitle = 255, kLongestTicketDescription = 8000;

// Text from the draft, trimmed, at most `most` characters, on one line unless `lines`; nil with why for anything else.
static NSString *DraftText(NSDictionary *asked, NSString *name, NSUInteger most, BOOL lines, NSString **why) {
    id value = asked[name];
    if (!value) return nil;
    NSString *text = [AsText(value) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!text) *why = [NSString stringWithFormat:@"the %@ is to be text", name];
    else if (text.length > most)
        *why = [NSString stringWithFormat:@"a %@ may be %lu characters at most", name, (unsigned long)most];
    else if (!lines && [text rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound)
        *why = [NSString stringWithFormat:@"the %@ is to be one line", name];
    else return text;
    return nil;
}

TicketDraft *TicketDraftAsked(NSString *given, NSString **why) {
    __autoreleasing NSString *unused = nil;
    if (!why) why = &unused;
    *why = nil;
    NSString *text = [given stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSData *data = text.length ? [text dataUsingEncoding:NSUTF8StringEncoding] : nil;
    NSDictionary *asked = AsRecord(data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil);
    if (!asked) {
        *why = @"give the new ticket on stdin as a JSON object: {\"title\": …, \"group\": …, \"type\": …, "
               @"\"description\": …}, with a \"priority\" and a \"parent\" if it has them";
        return nil;
    }
    NSArray *names = @[@"title", @"description", @"group", @"type", @"priority", @"parent", @"site"];
    NSMutableArray<NSString *> *others = [NSMutableArray array];
    for (NSString *name in asked)
        if (![names containsObject:name]) [others addObject:Clip(name, 40)];
    if (others.count) {
        *why = [NSString stringWithFormat:@"a new ticket has a title, description, group, type, priority, parent and "
                @"site, not %@", TicketsListed([others sortedArrayUsingSelector:@selector(compare:)])];
        return nil;
    }
    TicketDraft *draft = [TicketDraft new];
    draft.title = DraftText(asked, @"title", kLongestTicketTitle, NO, why);
    if (!*why) draft.details = DraftText(asked, @"description", kLongestTicketDescription, YES, why);
    if (!*why) draft.group = DraftText(asked, @"group", 64, NO, why);
    if (!*why) draft.type = DraftText(asked, @"type", 64, NO, why);
    if (!*why) draft.priority = DraftText(asked, @"priority", 64, NO, why);
    if (!*why) draft.parent = DraftText(asked, @"parent", 64, NO, why);
    if (!*why) draft.site = DraftText(asked, @"site", 253, NO, why);
    if (*why) return nil;
    // An empty optional part is none: what's sent is only ever what the card shows.
    if (!draft.details.length) draft.details = nil;
    if (!draft.priority.length) draft.priority = nil;
    if (!draft.parent.length) draft.parent = nil;
    if (!draft.site.length) draft.site = nil;
    // A group's id as its tracker writes it, in any shape it has (Jira's PAY_OPS): one word, which the tracker checks.
    NSCharacterSet *space = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    if (!draft.title.length) *why = @"give the new ticket a title";
    else if (!draft.group.length || [draft.group rangeOfCharacterFromSet:space].location != NSNotFound
             || [draft.group rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound)
        *why = @"say where it goes, by its group's id as its tracker writes it, as the ticket you work on lists in "
               @"`groups`";
    else if (!draft.type.length) *why = @"say its type, as its tracker names it (a Bug, a Task)";
    if (*why) return nil;
    draft.at = NSDate.date;
    return draft;
}

NSString *TicketDraftChecked(TicketDraft *draft, NSDictionary *options, TrackerAnswer *answer) {
    draft.checking = NO;
    if (answer.end == TrackerEndNotFound)
        return [NSString stringWithFormat:@"not yet: there's no %@ on %@ that the user can make tickets in: ask them "
                @"where it goes, then draft it again", draft.group, draft.site];
    if (!answer.ok) {
        draft.problem = answer;
        return nil;
    }
    NSArray *types = AsList(options[@"types"]) ?: @[];
    NSString *type = nil;
    for (id each in types)
        if (AsText(each) && [each caseInsensitiveCompare:draft.type] == NSOrderedSame) type = each;
    if (types.count && !type)
        return [NSString stringWithFormat:@"not yet: %@ takes %@, not %@: draft it again with one of them", draft.group,
                TicketsListed(types), Clip(draft.type, 40)];
    if (type) draft.type = type;
    draft.groupKind = AsText(options[@"kind"]);
    draft.problem = nil;
    draft.checked = YES;
    return nil;
}

TicketDraftEnd TicketDraftMade(TicketDraft *draft, NSString *key, TrackerAnswer *answer, NSString **told) {
    draft.creating = NO;
    if (key.length) return TicketDraftMadeIt;
    // Turned away as it was given: back to the session to put right, as trying again would only be turned away again.
    if (answer.end == TrackerEndRefused) {
        if (told) *told = [NSString stringWithFormat:@"not yet: %@. Ask the user what to change, then draft it again",
                           answer.why ?: @"it was turned away as it is"];
        return TicketDraftSentBack;
    }
    // Only the ends known to stop before anything is made (a sign-in, macOS asking first, an admin, a request to slow
    // down, no such group) are tried again as they are. Any other, a failure on the way back or one this doesn't know,
    // may have been made all the same, so it's never made again without your look first.
    TrackerEnd end = answer.end;
    draft.mayBeMade = answer.ok || !(end == TrackerEndSignIn || end == TrackerEndAsksMac || end == TrackerEndBlocked
                                     || end == TrackerEndSlowDown || end == TrackerEndNotFound);
    draft.problem = answer.ok ? [TrackerAnswer end:TrackerEndFailed why:@"It didn't say the new ticket's key"] : answer;
    return TicketDraftWaits;
}
