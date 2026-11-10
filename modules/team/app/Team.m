// Team: the team the session leading it keeps in Whozmove's folder, and each row's place in it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Team.h"
#import "Row.h"
#import "Files.h"
#import "Log.h"
#import "Printing.h"
#import "Processes.h"
#import "Task.h"

// The stages a job is at when nobody is working on it: queued, set aside, finished or given up. (A job under way can
// wait its turn too, at a step that `waits`: JobOf.)
static NSSet *Resting(void) {
    return [NSSet setWithArray:@[@"queued", @"parked", @"done", @"dropped"]];
}


// A time the file gives, as the page takes it, in ms since 1970: one under 10^11, which in ms would be before 1973, is
// in seconds.
static NSNumber *TimeOf(id value) {
    NSNumber *time = AsNumber(value);
    return time && time.doubleValue < 1e11 ? @(time.doubleValue * 1000) : time;
}

// How pressing a job is, as the file says, whatever the case: `critical`, `p0`, `p1` or `p2`; `p1` when it doesn't say,
// and `p2` for any word it doesn't know, so the page only ever sees the four.
static NSString *PriorityOf(NSDictionary *job) {
    NSString *priority = AsText(job[@"priority"]).lowercaseString;
    if (!priority) return @"p1";
    if ([@[@"critical", @"p0", @"p1", @"p2"] containsObject:priority]) return priority;
    return @"p2";
}

// How big a job is (`small`, `medium` or `big`) and how much work it takes (`low`, `medium` or `high`), as the file
// says, for the team board's order: nil for none, and for any other word, so a job the file doesn't size sorts as
// medium.
static NSString *SizeOf(id value) {
    NSString *size = AsText(value);
    return [@[@"small", @"medium", @"big"] containsObject:size ?: @""] ? size : nil;
}
static NSString *EffortOf(id value) {
    NSString *effort = AsText(value);
    return [@[@"low", @"medium", @"high"] containsObject:effort ?: @""] ? effort : nil;
}

// What each job holds up: the ids of the jobs under way that wait for it, in the order of their ids. A job's row
// counts them, and the team board names them.
static NSDictionary<NSString *, NSArray<NSString *> *> *HoldsUp(NSDictionary *jobs) {
    NSMutableDictionary<NSString *, NSMutableArray *> *holdsUp = [NSMutableDictionary dictionary];
    for (NSString *jobId in [jobs.allKeys sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
        NSString *stage = AsText(AsRecord(jobs[jobId])[@"stage"]);
        if (!stage || [Resting() containsObject:stage]) continue;
        for (id other in AsList(AsRecord(jobs[jobId])[@"dependsOn"]))
            if (AsText(other)) [holdsUp[other] ?: (holdsUp[other] = [NSMutableArray array]) addObject:jobId];
    }
    return holdsUp;
}

// A job as a row shows it: {id, title, steps, at, you, waits, short, ask, priority, holds, stageAt}, where `steps` are
// its flow's steps in order, each {id, word, you, kind, waits}, `kind` what a step that waits on you asks of you, in
// One Task's words (contracts/Task.h), `waits` on a step that doesn't, where nobody works on the job while it waits its
// turn ("Ready to try"), `at` the one it's on, `you` whether that one waits on you, `waits` whether it waits its turn,
// `short` what's wanted of you in a few words, `ask` in full (its ask, else the decision it waits on), and `holds` how
// many jobs under way wait for it (`holdsUp`, HoldsUp). Nil for a job that isn't under way, or whose steps the file
// doesn't give: the panel knows no flows of its own.
static NSDictionary *JobOf(NSString *jobId, NSDictionary *job, NSArray *holdsUp) {
    NSString *stage = AsText(job[@"stage"]), *at = AsText(job[@"at"]);
    if ([Resting() containsObject:stage ?: @""] || !at) return nil;
    NSMutableArray *steps = [NSMutableArray array];
    BOOL you = NO, waits = NO, found = NO;
    for (id item in AsList(job[@"steps"])) {
        NSDictionary *step = AsRecord(item);
        NSString *stepId = AsText(step[@"id"]), *word = AsText(step[@"word"]);
        if (!stepId || !word) continue;
        BOOL yours = [AsNumber(step[@"you"]) boolValue];
        // A step is on you or waits its turn, never both: one on you is what you're waited on for.
        BOOL waiting = !yours && [AsNumber(step[@"waits"]) boolValue];
        NSString *kind = AsText(step[@"kind"]);
        [steps addObject:yours && [TaskKinds containsObject:kind ?: @""]
            ? @{@"id": stepId, @"word": Clip(word, 24), @"you": @YES, @"kind": kind}
            : waiting ? @{@"id": stepId, @"word": Clip(word, 24), @"you": @NO, @"waits": @YES}
            : @{@"id": stepId, @"word": Clip(word, 24), @"you": @(yours)}];
        if ([stepId isEqualToString:at]) {
            found = YES;
            you = yours;
            waits = waiting;
        }
    }
    if (!found) return nil;
    NSMutableDictionary *shown = [@{@"id": jobId, @"title": Clip(AsText(job[@"title"]) ?: @"", 200), @"steps": steps,
                                    @"at": at, @"you": @(you), @"priority": PriorityOf(job), @"holds": @(holdsUp.count),
                                    @"stageAt": TimeOf(job[@"stageAt"]) ?: @0} mutableCopy];
    if (waits) shown[@"waits"] = @YES;
    NSString *ask = AsText(job[@"ask"]).length ? AsText(job[@"ask"]) : AsText(job[@"decision"]);
    if (you && ask.length) shown[@"ask"] = Clip(ask, 400);
    if (you && AsText(job[@"short"]).length) shown[@"short"] = Clip(AsText(job[@"short"]), 60);
    return shown;
}

// Where a job under way is, the one rule the lead's counts, a member's row and the team board (`underWay` in TeamFacts)
// all go by: `you` while the step it's at waits on you, `waiting` while that step waits its turn, with nobody working
// on it, else `work`, which a job without steps is too. `shown` is the job as its row has it (JobOf), nil without
// steps.
static NSString *UnderWayAt(NSDictionary *shown) {
    if ([shown[@"you"] boolValue]) return @"you";
    return [shown[@"waits"] boolValue] ? @"waiting" : @"work";
}

// Where a job stands, as a member's row says it while nothing of it waits on you: {stage, word, words, job, title,
// stageAt, you}, `stage` being `work` (under way) or `waiting` (under way, at a step that waits its turn), `word` the
// step it's at, in the team board's own word ("Build"), `queued` or `parked`, `words` a few of its own (its `status`, else its `short`), the job's id and title,
// when it got there, and whether its step waits on you. `shown` is the job as its row has it (JobOf), when it does. Nil
// for one done or given up.
static NSDictionary *StatusOf(NSString *jobId, NSDictionary *job, NSDictionary *shown) {
    NSString *stage = AsText(job[@"stage"]);
    if (!stage || [@[@"done", @"dropped"] containsObject:stage]) return nil;
    BOOL waits = [UnderWayAt(shown) isEqualToString:@"waiting"];
    NSMutableDictionary *status = [@{@"stage": [Resting() containsObject:stage] ? stage : waits ? @"waiting" : @"work",
                                     @"job": jobId, @"title": Clip(AsText(job[@"title"]) ?: @"", 200),
                                     @"you": @([shown[@"you"] boolValue]),
                                     @"stageAt": TimeOf(job[@"stageAt"]) ?: @0} mutableCopy];
    for (NSDictionary *step in shown[@"steps"])
        if ([step[@"id"] isEqual:shown[@"at"]]) status[@"word"] = step[@"word"];
    NSString *words = AsText(job[@"status"]).length ? AsText(job[@"status"]) : AsText(job[@"short"]);
    if (words.length) status[@"words"] = Clip(words, 60);
    return status;
}

// Whether the queued job `job` comes before `was` in its lead's order: the most pressing, then the one queued first.
// One without a time goes after those with one.
static BOOL QueuedBefore(NSDictionary *job, NSDictionary *was) {
    NSArray *pressing = @[@"critical", @"p0", @"p1", @"p2"];
    NSUInteger p = [pressing indexOfObject:PriorityOf(job)], q = [pressing indexOfObject:PriorityOf(was)];
    if (p != q) return p < q;
    NSNumber *at = TimeOf(job[@"queuedAt"]) ?: TimeOf(job[@"stageAt"]);
    NSNumber *other = TimeOf(was[@"queuedAt"]) ?: TimeOf(was[@"stageAt"]);
    return (at ? at.doubleValue : INFINITY) < (other ? other.doubleValue : INFINITY);
}

// Whether `status` is the one a member's row speaks for over `than` (of its job `job`, `was`): one under way, the one
// being worked on first, so a member at work shows what it's at rather than an older try waiting on you (that's its
// row's ask: AlsoAsksOf), else the one that moved last; else one waiting its turn, the one that moved last,
// so a member at work on one job isn't shown on another that waits for a try; else the next queued, in its lead's
// order (QueuedBefore); else the parked one that moved last.
static BOOL Before(NSDictionary *status, NSDictionary *job, NSDictionary *than, NSDictionary *was) {
    if (!than) return YES;
    NSArray *stages = @[@"work", @"waiting", @"queued", @"parked"];
    NSUInteger a = [stages indexOfObject:status[@"stage"]], b = [stages indexOfObject:than[@"stage"]];
    if (a != b) return a < b;
    if (a == 0 && [status[@"you"] boolValue] != [than[@"you"] boolValue]) return ![status[@"you"] boolValue];
    if (a == 2) return QueuedBefore(job, was);
    return [status[@"stageAt"] doubleValue] > [than[@"stageAt"] doubleValue];
}

// What a member's or followed session's row asks of you for a job of its own waiting on you while the row speaks for
// another it's at work on (Before): {job, title, short, at, priority, kind}, `short` what's wanted of you in a few
// words, else the step's word, and `kind` what that step asks of you (in One Task's words), when it says, so the row's
// ask ends in the one action for it. `asks` is that job as its row would have it (JobOf), the one that moved last of
// those waiting on you, and `speaks` what the row speaks for. Nil while the row speaks for that one itself, or there's
// none.
static NSDictionary *AlsoAsksOf(NSDictionary *asks, NSArray *speaks) {
    if (!asks || [asks[@"id"] isEqual:speaks[0][@"job"]]) return nil;
    NSString *words = asks[@"short"], *kind = nil;
    for (NSDictionary *step in asks[@"steps"]) {
        if (![step[@"id"] isEqual:asks[@"at"]]) continue;
        if (!words) words = step[@"word"];
        kind = step[@"kind"];
    }
    NSMutableDictionary *also = [@{@"job": asks[@"id"], @"title": asks[@"title"], @"short": words ?: @"",
                                   @"at": asks[@"at"], @"priority": asks[@"priority"]} mutableCopy];
    if (kind) also[@"kind"] = kind;
    return also;
}

// What the lead says you're to look at next, as its row shows it: {short, ask, priority, job, title, for}, `short` a few
// words (else the ask, which the row's line shortens as it fits), `ask` in full, `priority` its own, else its job's, and
// `job` and `title` the job it's for, when it names one the file has. `for` is the session of the member whose job it's
// for. Nil without words. The tasks a lead hands you aren't here: it sends them to One Task itself and the file names
// them in its queue (QueueOf).
static NSDictionary *NextOf(NSDictionary *next, NSDictionary *team) {
    NSString *words = AsText(next[@"short"]), *ask = AsText(next[@"ask"]), *jobId = AsText(next[@"job"]);
    if (!words.length && !ask.length) return nil;
    NSDictionary *job = jobId ? AsRecord(AsRecord(team[@"jobs"])[jobId]) : nil;
    NSMutableDictionary *shown = [@{@"priority": PriorityOf(AsText(next[@"priority"]) ? next : job)} mutableCopy];
    if (words.length) shown[@"short"] = Clip(words, 60);
    else shown[@"short"] = Clip(ask, 400);
    if (ask.length) shown[@"ask"] = Clip(ask, 400);
    if (job) {
        shown[@"job"] = jobId;
        if (AsText(job[@"title"]).length) shown[@"title"] = Clip(AsText(job[@"title"]), 200);
        NSString *member = AsText(job[@"member"]);
        NSString *session = member ? AsText(AsRecord(AsRecord(team[@"members"])[member])[@"session"]) : nil;
        if (session.length) shown[@"for"] = session;
    }
    return shown;
}

// The most picks a lead's queue holds: far above use, only a ceiling against a script gone wrong.
static const NSUInteger QueueMost = 100;

// What the lead has queued for you, in its order: [{id, job, title, priority}], each the id of a pick it sent One Task
// itself (docs/reference/task.md), the job it's for by id and title when the file has it, and how pressing that job is.
// The task and the member it's for aren't here: One Task keeps them as the pick was checked, so the queue can't send a
// pick to another session than the one checked. An id that isn't plain, or one named before, is left out, and so is
// everything past the first QueueMost.
static NSArray<NSDictionary *> *QueueOf(id queue, NSDictionary *team) {
    NSMutableArray<NSDictionary *> *shown = [NSMutableArray array];
    NSMutableSet<NSString *> *named = [NSMutableSet set];
    for (id item in AsList(queue)) {
        if (shown.count == QueueMost) break;
        NSDictionary *entry = AsRecord(item);
        NSString *pick = AsText(entry[@"id"]), *jobId = AsText(entry[@"job"]);
        if (!TaskIdPlain(pick) || [named containsObject:pick]) continue;
        [named addObject:pick];
        NSDictionary *job = jobId ? AsRecord(AsRecord(team[@"jobs"])[jobId]) : nil;
        NSMutableDictionary *place = [@{@"id": pick, @"priority": PriorityOf(job)} mutableCopy];
        if (job) {
            place[@"job"] = jobId;
            if (AsText(job[@"title"]).length) place[@"title"] = Clip(AsText(job[@"title"]), 200);
        }
        [shown addObject:place];
    }
    return shown;
}

// A few words the file gives, trimmed and clipped, or nil for none or for words that hide what they say.
static NSString *WordsOf(id value, NSUInteger most) {
    NSString *words = Clip([AsText(value) ?: @""
                            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet], most);
    return words.length && !TaskTextHides(words, NO) ? words : nil;
}

// A team's goals, in the file's order: [{id, name, due, work}], `due` only when it gives one, and `work` on a heading
// for jobs about how the team works rather than a goal of the project (the team board gives it a tile, but no number,
// and counts it as no goal). One without a plain id or a name, or with an id named before, is left out, and so is
// everything past the 50th.
static NSArray<NSDictionary *> *GoalsOf(id goals) {
    NSMutableArray<NSDictionary *> *shown = [NSMutableArray array];
    NSMutableSet<NSString *> *named = [NSMutableSet set];
    for (id item in AsList(goals)) {
        if (shown.count == 50) break;
        NSDictionary *goal = AsRecord(item);
        NSString *goalId = AsText(goal[@"id"]), *name = WordsOf(goal[@"name"], 40), *due = WordsOf(goal[@"due"], 24);
        if (!TaskIdPlain(goalId) || !name || [named containsObject:goalId]) continue;
        [named addObject:goalId];
        NSMutableDictionary *shownGoal = [@{@"id": goalId, @"name": name} mutableCopy];
        if (due) shownGoal[@"due"] = due;
        if ([AsNumber(goal[@"work"]) boolValue]) shownGoal[@"work"] = @YES;
        [shown addObject:shownGoal];
    }
    return shown;
}

// A job as the team board shows it (TeamFacts): the job as its row has it (JobOf), when it has steps and is under way,
// with `holdsUp` in place of how many, and for every job {id, title, stage, underWay, priority, size, effort, stageAt,
// goal, member, session, part, kind, doneAt}. `stage` is the file's own word, `underWay` where one under way is
// (UnderWayAt: you, waiting or work), `size` and `effort` only when the file gives one of their words (SizeOf,
// EffortOf), `goal` one of the team's goals, `member` whose it is, by name, with its
// `session` and the `part` it looks after, `kind` what the step it's at asks of you while it waits on you, and `doneAt`
// when a done one was done.
static NSDictionary *JobFactsOf(NSString *jobId, NSDictionary *job, NSDictionary *team, NSSet *goalIds,
                                NSArray *holdsUp) {
    NSString *stage = AsText(job[@"stage"]), *goal = AsText(job[@"goal"]);
    NSMutableDictionary *facts = [JobOf(jobId, job, holdsUp) mutableCopy]
        ?: [@{@"id": jobId, @"title": Clip(AsText(job[@"title"]) ?: @"", 200), @"priority": PriorityOf(job),
              @"stageAt": TimeOf(job[@"stageAt"]) ?: @0} mutableCopy];
    [facts removeObjectForKey:@"holds"];
    facts[@"stage"] = stage;
    if (![Resting() containsObject:stage]) facts[@"underWay"] = UnderWayAt(facts);
    NSString *size = SizeOf(job[@"size"]), *effort = EffortOf(job[@"effort"]);
    if (size) facts[@"size"] = size;
    if (effort) facts[@"effort"] = effort;
    if (holdsUp.count) facts[@"holdsUp"] = holdsUp;
    if (goal && [goalIds containsObject:goal]) facts[@"goal"] = goal;
    NSString *memberName = AsText(job[@"member"]), *name = memberName ?: AsText(job[@"followed"]);
    if (name.length) {
        facts[@"member"] = name;
        NSDictionary *member = memberName ? AsRecord(AsRecord(team[@"members"])[name])
                                          : AsRecord(AsRecord(team[@"followed"])[name]);
        if (AsText(member[@"session"]).length) facts[@"session"] = AsText(member[@"session"]);
        NSString *part = WordsOf(member[@"part"], 40);
        if (part) facts[@"part"] = part;
    }
    if ([facts[@"you"] boolValue])
        for (NSDictionary *step in facts[@"steps"])
            if ([step[@"id"] isEqual:facts[@"at"]] && step[@"kind"]) facts[@"kind"] = step[@"kind"];
    if ([stage isEqual:@"done"] && TimeOf(job[@"doneAt"])) facts[@"doneAt"] = TimeOf(job[@"doneAt"]);
    return facts;
}

// The group a member is in, in the words of the one keeping the file, or nil for none: a name of its own, trimmed and
// clipped, never one that hides what it says, nor Team, the name of the group the rest of the team is in, so a name
// never stands for two groups.
static NSString *const TeamGroup = @"Team";
static NSString *GroupOf(NSDictionary *member) {
    NSString *group = WordsOf(member[@"group"], 40);
    if (!group) return nil;
    if ([group caseInsensitiveCompare:TeamGroup] == NSOrderedSame) return nil;
    return group;
}

// A member's tag, shown after its name, in the words of the one keeping the file ("Product"): at most 3 words and 30
// characters, else none, rather than one cut short; never one that hides what it says.
static NSString *TagOf(NSDictionary *member) {
    NSString *tag = [AsText(member[@"tag"]) ?: @""
                     stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (tag.length > 30) return nil;
    NSArray *words = [[tag componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
                      filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    return words.count <= 3 ? WordsOf(tag, 30) : nil;
}

// What the file says a member is busy with apart from its jobs, as its row says where it stands: {stage: work, words,
// doing}, `words` what it's on ("Wren's search box") and `doing` the word for it, said in place of Moving
// ("Reviewing"). Nil without words.
static NSDictionary *BusyWith(NSDictionary *member) {
    NSString *words = WordsOf(member[@"status"], 60), *doing = WordsOf(member[@"doing"], 24);
    if (!words) return nil;
    return doing ? @{@"stage": @"work", @"words": words, @"doing": doing} : @{@"stage": @"work", @"words": words};
}

// The groups the team's members and its lead are in (`placed`, each one's record in the file), in order: as the
// file's `groups` lists them, then any it doesn't, A to Z (a JSON object's keys come in no order). The list may name
// Team too, to put the rest of the team among the groups rather than after them; it's in the order then, by that
// name.
static NSArray<NSString *> *GroupsOf(NSDictionary *team, NSArray<NSDictionary *> *placed) {
    NSMutableSet<NSString *> *named = [NSMutableSet set];
    for (NSDictionary *record in placed) {
        NSString *group = GroupOf(record);
        if (group) [named addObject:group];
    }
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    for (id listed in AsList(team[@"groups"])) {
        NSString *words = WordsOf(listed, 40);
        if (words && [words caseInsensitiveCompare:TeamGroup] == NSOrderedSame) {
            if (![order containsObject:TeamGroup]) [order addObject:TeamGroup];
            continue;
        }
        NSString *group = GroupOf(@{@"group": AsText(listed) ?: @""});
        if (group && [named containsObject:group] && ![order containsObject:group]) [order addObject:group];
    }
    for (NSString *group in [named.allObjects sortedArrayUsingSelector:@selector(localizedStandardCompare:)])
        if (![order containsObject:group]) [order addObject:group];
    return order;
}

// How long a seat's holder may be missing from the list while its process still runs before another takes its seat:
// one read can miss a row now and then, but an app whose sessions you stopped tracking keeps its process running.
static const NSTimeInterval kSeatHeldFor = 60;

// A member is its workspace: one session running there holds its seat. The file's own session while it runs there;
// else the one that held it last pass, while it runs there, or a new conversation on its process (a /clear keeps the
// seat), and nobody else while that process runs but its row is missed (`lastUnseen`, for kSeatHeldFor at most), so a
// pass that misses a row never hands the seat on; else the one opened first, one without a known start last, then by id, so the seat doesn't move as the
// sessions there take turns at work. While none runs there, the member is still its last conversation there, ended
// (`ended`): the one that held the seat last, else the file's own, else the one that moved last, so closing a member's
// tab leaves its row where it was, whichever conversation the file records.
NSDictionary *SeatOf(NSArray<NSDictionary *> *here, NSString *recorded, NSDictionary *last, BOOL lastUnseen) {
    NSMutableArray<NSDictionary *> *running = [NSMutableArray array], *over = [NSMutableArray array];
    for (NSDictionary *one in here)
        if (AsText(one[@"session"]).length) [[one[@"running"] boolValue] ? running : over addObject:one];
    NSDictionary *(^findIn)(NSArray *, NSString *, id) = ^NSDictionary *(NSArray *among, NSString *key, id value) {
        if (!AsText(value).length) return nil;
        for (NSDictionary *one in among) if ([one[key] isEqual:value]) return one;
        return nil;
    };
    NSDictionary *(^find)(NSString *, id) = ^NSDictionary *(NSString *key, id value) {
        return findIn(running, key, value);
    };
    NSDictionary *seat = find(@"session", recorded) ?: find(@"session", last[@"session"])
        ?: find(@"process", last[@"process"]);
    NSDictionary *holder = nil;
    if (!seat && last && lastUnseen) {
        holder = last;
    } else {
        if (!seat) {
            seat = [running sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                long long x = [a[@"startedAt"] longLongValue], y = [b[@"startedAt"] longLongValue];
                if (x != y) return !x ? NSOrderedDescending : !y ? NSOrderedAscending
                    : x < y ? NSOrderedAscending : NSOrderedDescending;
                return [a[@"session"] compare:b[@"session"]];
            }].firstObject;
        }
        if (seat) {
            NSMutableDictionary *kept = [@{@"session": seat[@"session"], @"startedAt": seat[@"startedAt"] ?: @0}
                                         mutableCopy];
            if (AsText(seat[@"process"]).length) {
                kept[@"process"] = seat[@"process"];
                kept[@"pid"] = seat[@"pid"] ?: @0;
            }
            holder = kept;
        }
    }
    // Nobody running there: the ended one that stands for the member, kept as the holder so the next pass finds it
    // again rather than an older conversation the file records.
    NSDictionary *ended = nil;
    if (!holder) {
        ended = findIn(over, @"session", last[@"session"]) ?: findIn(over, @"session", recorded)
            ?: [over sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                   double x = [a[@"movedAt"] doubleValue], y = [b[@"movedAt"] doubleValue];
                   if (x != y) return x > y ? NSOrderedAscending : NSOrderedDescending;
                   return [a[@"session"] compare:b[@"session"]];
               }].firstObject;
        if (ended) holder = @{@"session": ended[@"session"], @"startedAt": @0};
    }
    // Every other one running there is a duplicate, said to be the earlier of the two when its process started before
    // the holder's.
    long long holderAt = [holder[@"startedAt"] longLongValue];
    NSMutableDictionary<NSString *, NSNumber *> *duplicates = [NSMutableDictionary dictionary];
    for (NSDictionary *one in running) {
        if ([one[@"session"] isEqual:holder[@"session"]]) continue;
        long long at = [one[@"startedAt"] longLongValue];
        duplicates[one[@"session"]] = at && holderAt && at < holderAt ? @YES : @NO;
    }
    NSMutableDictionary *found = [@{@"duplicates": duplicates} mutableCopy];
    if (seat) found[@"seat"] = seat[@"session"];
    if (ended) found[@"ended"] = ended[@"session"];
    if (holder) found[@"holder"] = holder;
    return found;
}

int PrintSeats(NSArray<NSString *> *arguments) {
    NSArray *cases = arguments.count ? AsList(ReadJSON(arguments[0])) : nil;
    if (!cases) {
        fprintf(stderr, "usage: Whozmove --print-seats <cases.json>\n");
        return 1;
    }
    NSMutableArray *printed = [NSMutableArray array];
    for (NSDictionary *c in cases) {
        NSDictionary *found = SeatOf(AsList(c[@"here"]) ?: @[], AsText(c[@"recorded"]), AsRecord(c[@"last"]),
                                     [c[@"lastUnseen"] boolValue]);
        [printed addObject:@{@"name": AsText(c[@"name"]) ?: @"", @"found": found}];
    }
    return PrintJSON(printed);
}

@interface Team ()
@property (strong) dispatch_queue_t queue;
@property (assign) BOOL working;
@property (strong) NSDate *readMtime;
@property (assign) NSTimeInterval checkedAt;
// How many reads have started, and the newest whose result is in use. The latest read's result, {n, members, folders,
// seats, teams, mtime}, is set on the queue as it ends, where the first rows can take it before its own hand-over (refresh).
@property (assign) NSUInteger reads, taken;
@property (copy) NSDictionary *lastRead;
// The read under way, which the first rows wait on for a moment, and whether they've waited already.
@property (strong) dispatch_group_t reading;
@property (assign) BOOL waited;
// What was read: each member by session id, {place, folder}, where `place` is what the row gets and `folder` where it
// must be working to be that member (nil for your own sessions, which may move); and each folder a member works in,
// {name, history}: its name, for another session open there, and whether a conversation that has ended there is the
// team's history rather than yours (a member's workspace always; the lead's and the front's apart from the project's
// own folder, where your own conversations are too).
@property (copy) NSDictionary<NSString *, NSDictionary *> *members;
@property (copy) NSDictionary<NSString *, NSDictionary *> *folders;
// Each member's own workspace, a folder the file records for that member alone in all its projects, with the member,
// {name, session}: whoever runs there holds the member's seat (SeatOf). And who held each seat last pass, by folder,
// with the member's name, kept only while Whozmove runs, so a /clear or a missed row never hands a seat on, and the
// ended conversation standing for a member while none runs there stays the one on its row.
@property (copy) NSDictionary<NSString *, NSDictionary *> *seats;
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *lastSeats;
@property (readwrite, copy) NSArray<NSDictionary *> *teams;
// Each folder a row's session works in, with symlinks resolved, as the team records its members' folders: asked about
// every row every second, so each is resolved once.
@property (strong) NSMutableDictionary<NSString *, NSString *> *realFolders;
@end

@implementation Team

- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.queue = dispatch_queue_create("whozmove.team", DISPATCH_QUEUE_SERIAL);
    self.reading = dispatch_group_create();
    self.members = @{};
    self.folders = @{};
    self.seats = @{};
    self.lastSeats = [NSMutableDictionary dictionary];
    self.teams = @[];
    self.realFolders = [NSMutableDictionary dictionary];
    // Read as the app starts, while the sessions are read for the first rows, which wait for it (refresh).
    [self refresh];
    return self;
}

// A folder with its symlinks resolved, once.
- (NSString *)real:(NSString *)folder {
    if (!folder.length) return nil;
    NSString *real = self.realFolders[folder];
    if (!real) {
        // Kept only while there are few: a folder resolved again now and then costs little.
        if (self.realFolders.count > 500) [self.realFolders removeAllObjects];
        real = self.realFolders[folder] = RealPath(folder);
    }
    return real;
}

- (void)refresh {
    // The first rows wait for the first read: a row sent without its place in the team would count a member's reply to
    // its lead as one to you. They wait on the main thread, so for half a second at most: a disk that doesn't answer
    // mustn't hold the panel up, and the rows go without the team until the read comes in (the page lets go of a reply
    // it kept as unread once it's known to have gone elsewhere).
    if (self.working && !self.taken && !self.waited) {
        self.waited = YES;
        if (dispatch_group_wait(self.reading, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2)) == 0)
            [self take:self.lastRead];
        else
            LogProblem(@"the team file took over half a second to read: the first rows went without the team");
    }
    NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
    if (self.working || (self.checkedAt && now - self.checkedAt < 0.5)) return;
    self.checkedAt = now;
    NSString *path = AppDir(@"team/team.json");
    NSDate *mtime = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil].fileModificationDate;
    if ((!mtime && !self.readMtime) || [mtime isEqual:self.readMtime]) return;
    self.working = YES;
    NSUInteger n = ++self.reads;
    dispatch_group_async(self.reading, self.queue, ^{
        // The file is written whole and swapped in by the one keeping it, so a read never finds half of it.
        NSDictionary *file = mtime ? AsRecord(ReadJSON(path)) : nil;
        NSMutableDictionary *members = [NSMutableDictionary dictionary], *folders = [NSMutableDictionary dictionary];
        NSMutableDictionary *seats = [NSMutableDictionary dictionary];
        NSMutableArray *teams = [NSMutableArray array];
        [self read:file into:members folders:folders seats:seats teams:teams];
        NSDictionary *read = @{@"n": @(n), @"members": members, @"folders": folders, @"seats": seats, @"teams": teams,
                               @"mtime": mtime ?: NSNull.null};
        self.lastRead = read;
        dispatch_async(dispatch_get_main_queue(), ^{ [self take:read]; });
    });
}

// A read's result put in use, once: the first may be taken before its own hand-over comes, as the first rows wait for
// it (refresh).
- (void)take:(NSDictionary *)read {
    NSUInteger n = [read[@"n"] unsignedIntegerValue];
    if (n <= self.taken) return;
    self.taken = n;
    self.members = read[@"members"];
    self.folders = read[@"folders"];
    self.seats = read[@"seats"];
    self.teams = read[@"teams"];
    self.readMtime = [read[@"mtime"] isKindOfClass:NSDate.class] ? read[@"mtime"] : nil;
    self.working = NO;
}

// Each project's team: the session you talk to (its front), the lead, its members, and your own sessions it follows,
// each found by its session id. A member is only that member while it works in the folder recorded for it, so a session
// that's moved, or a recorded id that now belongs to something else, never counts as it. And each team as a whole, by
// its project's folder, A to Z.
- (void)read:(NSDictionary *)file into:(NSMutableDictionary *)members folders:(NSMutableDictionary *)folders
       seats:(NSMutableDictionary *)seats teams:(NSMutableArray *)teams {
    NSDictionary *projects = AsRecord(file[@"projects"]);
    // How many of the team, in every project, each folder is recorded for: a member's own workspace is one recorded
    // for it alone, as a folder two share can't say which of them a session there is.
    NSCountedSet<NSString *> *recorded = [NSCountedSet set];
    for (NSString *project in [projects.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSDictionary *team = AsRecord(projects[project]);
        // The one job each member's or followed session's row speaks for (Before), by whose it is (`member/Wren`,
        // `followed/dark mode`): where it stands, the job, and, while it's under way with its steps, the job as the row
        // shows it (its track, and what it wants of you).
        NSMutableDictionary<NSString *, NSArray *> *standing = [NSMutableDictionary dictionary];
        // And, by whose it is, of its jobs under way that wait on you, the one that moved last (JobOf), for the
        // ask its row has while it speaks for another (AlsoAsksOf).
        NSMutableDictionary<NSString *, NSDictionary *> *asking = [NSMutableDictionary dictionary];
        // And the jobs under way (UnderWayAt): those that wait on you as their steps say, by how pressing they are, and
        // those at work, never those at a step that waits its turn, which nobody is working on. A job holds up each one
        // under way that waits for it.
        NSMutableDictionary<NSString *, NSNumber *> *waiting =
            [@{@"critical": @0, @"p0": @0, @"p1": @0, @"p2": @0} mutableCopy];
        NSInteger working = 0;
        NSDictionary *allJobs = AsRecord(team[@"jobs"]);
        NSDictionary<NSString *, NSArray *> *holdsUp = HoldsUp(allJobs);
        for (NSString *jobId in allJobs) {
            NSDictionary *job = AsRecord(allJobs[jobId]) ?: @{}, *shown = JobOf(jobId, job, holdsUp[jobId]);
            NSString *member = AsText(job[@"member"]), *followed = AsText(job[@"followed"]);
            NSString *key = member ? [@"member/" stringByAppendingString:member]
                : followed ? [@"followed/" stringByAppendingString:followed] : nil;
            NSDictionary *status = key ? StatusOf(jobId, job, shown) : nil;
            if (status) {
                NSArray *was = standing[key];
                if (Before(status, job, was[0], was[1])) standing[key] = shown ? @[status, job, shown] : @[status, job];
                if ([status[@"stage"] isEqual:@"work"] && [status[@"you"] boolValue]
                    && (!asking[key] || [shown[@"stageAt"] doubleValue] > [asking[key][@"stageAt"] doubleValue]))
                    asking[key] = shown;
            }
            NSString *stage = AsText(job[@"stage"]);
            if (!stage || [Resting() containsObject:stage]) continue;
            NSString *priority = shown[@"priority"];
            NSString *where = UnderWayAt(shown);
            if ([where isEqualToString:@"you"]) waiting[priority] = @(waiting[priority].integerValue + 1);
            else if ([where isEqualToString:@"work"]) working++;
        }
        NSDictionary *leading = AsRecord(team[@"lead"]);
        BOOL (^add)(NSString *, NSString *, NSDictionary *) =
            ^BOOL(NSString *session, NSString *folder, NSDictionary *place) {
            // A session listed twice keeps the first place it was given (the session you talk to, then the lead, are
            // added first), so a stray entry never takes its row from it.
            if (!session.length || members[session]) return NO;
            NSMutableDictionary *member = [@{@"place": place} mutableCopy];
            if (folder.length) {
                member[@"folder"] = RealPath(folder);
                BOOL history = [place[@"role"] isEqual:@"member"]
                    || ![member[@"folder"] isEqualToString:RealPath(project)]
                    || [folders[member[@"folder"]][@"history"] boolValue];
                folders[member[@"folder"]] = @{@"name": place[@"name"] ?: @"", @"history": @(history)};
                [recorded addObject:member[@"folder"]];
                if ([place[@"role"] isEqual:@"member"])
                    seats[member[@"folder"]] = @{@"name": place[@"name"], @"session": session};
            }
            members[session] = member;
            return YES;
        };
        // The session you talk to, when another runs the team behind it (`front`): it's the chief, marked so and on
        // top, and is added first, so it keeps its row whatever else names its session. It gets nothing of the lead's:
        // the lead still holds the team's counts, its picks for you, the sessions it leads and the jobs it starts. A
        // front without a lead that has a session fronts no team, and one naming the lead's own session is the lead.
        NSDictionary *fronting = AsRecord(team[@"front"]);
        NSString *leadSession = AsText(leading[@"session"]), *frontSession = AsText(fronting[@"session"]);
        NSMutableDictionary *front = nil;
        if (leadSession.length && frontSession.length && ![frontSession isEqualToString:leadSession]) {
            front = [@{@"role": @"front", @"name": AsText(fronting[@"name"]) ?: @"", @"chief": @YES} mutableCopy];
            NSString *shown = WordsOf(fronting[@"shown"], 40);
            if (shown) front[@"shown"] = shown;
            if (!add(frontSession, AsText(fronting[@"worktree"]), front)) front = nil;
        }
        NSMutableDictionary *lead = nil;
        if (leading) {
            lead = [@{@"role": @"lead", @"name": AsText(leading[@"name"]) ?: @"",
                      @"counts": @{@"waiting": waiting, @"working": @(working)}} mutableCopy];
            if (!front) lead[@"chief"] = @YES;
            // Behind the session you talk to, the lead is one of the team, so it takes the group and the tag the file
            // gives it, as a member does; as the chief, it keeps its place on top, marked Chief.
            NSString *group = front ? GroupOf(leading) : nil, *tag = front ? TagOf(leading) : nil;
            if (group) lead[@"group"] = group;
            if (tag) lead[@"tag"] = tag;
            NSDictionary *next = NextOf(AsRecord(leading[@"next"]), team);
            if (next) lead[@"next"] = next;
            NSArray *queue = QueueOf(leading[@"queue"], team);
            if (queue.count) lead[@"queue"] = queue;
            add(leadSession, AsText(leading[@"worktree"]), lead);
        }
        // The sessions it leads: its members that took their place on this team, never one the file gives a place
        // elsewhere first, so a module acting on its team only ever reaches the members its own team names.
        NSMutableArray<NSString *> *leads = [NSMutableArray array];
        NSDictionary *teamMembers = AsRecord(team[@"members"]);
        NSMutableArray<NSDictionary *> *grouped = [NSMutableArray array];
        for (NSString *name in teamMembers) [grouped addObject:AsRecord(teamMembers[name]) ?: @{}];
        if (lead[@"group"]) [grouped addObject:@{@"group": lead[@"group"]}];
        NSArray<NSString *> *groups = GroupsOf(team, grouped);
        if (lead[@"group"]) lead[@"groupAt"] = @([groups indexOfObject:lead[@"group"]]);
        // Where the file puts the rest of the team among its groups, when its list names Team: on each member in none.
        NSUInteger teamAt = [groups indexOfObject:TeamGroup];
        for (NSString *name in teamMembers) {
            NSDictionary *s = AsRecord(teamMembers[name]);
            NSMutableDictionary *place = [@{@"role": @"member", @"name": name} mutableCopy];
            if (AsText(s[@"part"]).length) place[@"part"] = AsText(s[@"part"]);
            NSString *tag = TagOf(s), *shown = WordsOf(s[@"shown"], 40);
            if (tag) place[@"tag"] = tag;
            if (shown) place[@"shown"] = shown;
            NSString *group = GroupOf(s);
            if (group) {
                place[@"group"] = group;
                place[@"groupAt"] = @([groups indexOfObject:group]);
            } else if (teamAt != NSNotFound) {
                place[@"groupAt"] = @(teamAt);
            }
            NSArray *speaks = standing[[@"member/" stringByAppendingString:name]];
            if (speaks.count > 2) place[@"job"] = speaks[2];
            NSDictionary *also = AlsoAsksOf(asking[[@"member/" stringByAppendingString:name]], speaks);
            if (also) place[@"alsoAsks"] = also;
            // What the file says it's busy with apart from its jobs (a review of another's) is what it's on now.
            NSDictionary *busy = BusyWith(s);
            if (busy || speaks) place[@"status"] = busy ?: speaks[0];
            if (add(AsText(s[@"session"]), AsText(s[@"worktree"]), place)) [leads addObject:AsText(s[@"session"])];
        }
        if (leads.count) lead[@"leads"] = [leads sortedArrayUsingSelector:@selector(compare:)];
        NSDictionary *followed = AsRecord(team[@"followed"]);
        for (NSString *name in followed) {
            NSDictionary *f = AsRecord(followed[name]);
            NSMutableDictionary *place = [@{@"role": @"followed", @"name": name} mutableCopy];
            NSArray *speaks = standing[[@"followed/" stringByAppendingString:name]];
            if (speaks.count > 2) place[@"job"] = speaks[2];
            NSDictionary *also = AlsoAsksOf(asking[[@"followed/" stringByAppendingString:name]], speaks);
            if (also) place[@"alsoAsks"] = also;
            if (speaks) place[@"status"] = speaks[0];
            add(AsText(f[@"session"]), nil, place);
        }
        // The job each member's row speaks for is the one the team board says it's on now, by the same rule (Before).
        NSMutableSet<NSString *> *now = [NSMutableSet set];
        for (NSArray *speaks in standing.allValues) [now addObject:speaks[0][@"job"]];
        // Its name as its row shows it, so the board's heads and its row say the same.
        NSDictionary *chief = front ? @{@"session": frontSession, @"name": front[@"shown"] ?: front[@"name"]} : nil;
        [teams addObject:[self factsOf:team project:project lead:lead session:leadSession chief:chief
                               holdsUp:holdsUp now:now]];
    }
    for (NSString *folder in seats.allKeys)
        if ([recorded countForObject:folder] > 1) [seats removeObjectForKey:folder];
    // Each queued job's place in its lead's order (`place`, from 1), numbered across every team with a lead together:
    // the room your gear lets in is one for your account, so the queue reads its order from here rather than sorting
    // again, and a team nobody leads starts nothing, so takes none of it. Two just as pressing and queued at once keep
    // the teams' order, A to Z, then their ids'.
    NSMutableArray<NSArray *> *queued = [NSMutableArray array];
    for (NSDictionary *facts in teams) {
        if (!facts[@"lead"]) continue;
        NSDictionary *fileJobs = AsRecord(AsRecord(projects[facts[@"project"]])[@"jobs"]);
        for (NSMutableDictionary *job in facts[@"jobs"])
            if ([job[@"stage"] isEqual:@"queued"]) [queued addObject:@[job, AsRecord(fileJobs[job[@"id"]]) ?: @{}]];
    }
    NSArray *ordered = [queued sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSArray *a,
                                                                                                         NSArray *b) {
        return QueuedBefore(a[1], b[1]) ? NSOrderedAscending : QueuedBefore(b[1], a[1]) ? NSOrderedDescending
             : NSOrderedSame;
    }];
    [ordered enumerateObjectsUsingBlock:^(NSArray *pair, NSUInteger i, BOOL *_) { pair[0][@"place"] = @(i + 1); }];
}

// A team as a whole (TeamFacts): {project, lead: {session, name}, chief: {session, name}, goals, queue, jobs}, every
// job but the dropped ones, in the order of their ids. `queue` is its lead's place's, as its row has it. A job in `now`
// is one a member's row speaks for, marked `now`; a queued one gets its `place` once every team is read (read:into:).
- (NSDictionary *)factsOf:(NSDictionary *)team project:(NSString *)project lead:(NSDictionary *)lead
                  session:(NSString *)session chief:(NSDictionary *)chief
                  holdsUp:(NSDictionary<NSString *, NSArray *> *)holdsUp now:(NSSet<NSString *> *)now {
    NSArray *goals = GoalsOf(team[@"goals"]);
    NSSet *goalIds = [NSSet setWithArray:[goals valueForKey:@"id"]];
    NSDictionary *allJobs = AsRecord(team[@"jobs"]);
    NSArray *ids = [allJobs.allKeys sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    NSMutableArray *jobs = [NSMutableArray array];
    for (NSString *jobId in ids) {
        NSDictionary *job = AsRecord(allJobs[jobId]);
        NSString *stage = AsText(job[@"stage"]);
        if (!stage || [stage isEqual:@"dropped"]) continue;
        NSMutableDictionary *facts = [JobFactsOf(jobId, job, team, goalIds, holdsUp[jobId]) mutableCopy];
        if ([now containsObject:jobId]) facts[@"now"] = @YES;
        [jobs addObject:facts];
    }
    NSMutableDictionary *facts = [@{@"project": project, @"goals": goals, @"jobs": jobs,
                                    @"queue": lead[@"queue"] ?: @[]} mutableCopy];
    if (lead && session.length) {
        facts[@"lead"] = @{@"session": session, @"name": lead[@"name"] ?: @""};
        // The chief, marked so in the list: the session you talk to when the file names one, else the lead.
        facts[@"chief"] = chief ?: facts[@"lead"];
    }
    return facts;
}

// A row's place by its session and folder alone: the session the file names for it, while it works in the folder
// recorded for it (any folder for one of yours), or another session open where one of the team works, said to be
// there; nil for any other. Who holds a member's seat is worked out after, from every row (placesOf:).
- (NSDictionary *)placeOf:(Row *)row {
    if (!row.sessionId) return nil;
    NSDictionary *member = self.members[row.sessionId];
    if (!member && !self.folders.count) return nil;
    if (member && !member[@"folder"]) return member[@"place"];
    NSString *root = nil, *cwd = nil;
    [self workspaceOf:row root:&root cwd:&cwd];
    if (member && ([root isEqualToString:member[@"folder"]] || [cwd isEqualToString:member[@"folder"]]))
        return member[@"place"];
    // Another session open where one of the team works: yours, but said to be there, rather than taken for it, and
    // whether once it has ended it's the team's history there (`history`).
    NSDictionary *whose = (root ? self.folders[root] : nil) ?: (cwd ? self.folders[cwd] : nil);
    if (!whose) return nil;
    return [whose[@"history"] boolValue] ? @{@"inFolderOf": whose[@"name"], @"history": @YES}
                                        : @{@"inFolderOf": whose[@"name"]};
}

// Where a row works, its checkout's top folder and the folder it runs in (which may be one inside it); and of those,
// the one that's a member's own workspace, if either is.
- (NSString *)workspaceOf:(Row *)row root:(NSString **)root cwd:(NSString **)cwd {
    *root = [self real:AsText(row.git[@"root"])];
    *cwd = [self real:row.cwd];
    return (*root && self.seats[*root]) ? *root : (*cwd && self.seats[*cwd]) ? *cwd : nil;
}

- (NSArray *)placesOf:(NSArray<Row *> *)rows {
    NSMutableArray *places = [NSMutableArray arrayWithCapacity:rows.count];
    // Each member's own workspace, by its folder: the rows there whose session the file names for no one, and the
    // file's own session for it while it's there. A session the file names, wherever it runs, keeps the place it has.
    NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *here = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *processes = [NSMutableSet set];
    [rows enumerateObjectsUsingBlock:^(Row *row, NSUInteger i, BOOL *stop) {
        NSDictionary *place = [self placeOf:row];
        [places addObject:place ?: NSNull.null];
        if (row.pid > 0) [processes addObject:ProcessKey(row.pid, row.procStart)];
        if (!row.sessionId || !self.seats.count) return;
        NSDictionary *member = self.members[row.sessionId];
        NSString *root = nil, *cwd = nil, *folder = [self workspaceOf:row root:&root cwd:&cwd];
        if (member ? !(place[@"role"] && [self.seats[member[@"folder"] ?: @""][@"session"] isEqual:row.sessionId])
                   : !folder)
            return;
        folder = member ? member[@"folder"] : folder;
        [here[folder] ?: (here[folder] = [NSMutableArray array]) addObject:@(i)];
    }];
    // Who holds each seat, and the session it stands for in the lead's `leads` (and in what's next for you).
    NSMutableDictionary<NSString *, NSString *> *seated = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSDictionary *> *holders = [NSMutableDictionary dictionary];
    NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
    for (NSString *folder in self.seats) {
        NSDictionary *seat = self.seats[folder];
        NSString *recorded = seat[@"session"];
        NSArray<NSNumber *> *at = here[folder] ?: @[];
        NSMutableArray<NSDictionary *> *sessions = [NSMutableArray array];
        for (NSNumber *i in at) [sessions addObject:[self seatedAs:rows[i.unsignedIntegerValue]]];
        // Who held the seat last pass counts only for the member it held it for: a folder the file now gives another
        // member starts afresh, so that member's row never shows the earlier one's conversation.
        NSDictionary *last = self.lastSeats[folder];
        if (last && ![last[@"name"] isEqual:seat[@"name"]]) last = nil;
        // The last holder missed while its process runs keeps the seat for kSeatHeldFor from when it was first missed.
        BOOL unseen = last && [self stillRuns:last among:processes];
        NSNumber *missed = unseen ? (last[@"missedAt"] ?: @(now)) : nil;
        if (missed && now - missed.doubleValue >= kSeatHeldFor) unseen = NO;
        NSDictionary *found = SeatOf(sessions, recorded, last, unseen);
        if (found[@"holder"]) {
            NSMutableDictionary *held = [found[@"holder"] mutableCopy];
            if (unseen && !found[@"seat"]) held[@"missedAt"] = missed;
            held[@"name"] = seat[@"name"] ?: @"";
            holders[folder] = held;
        }
        // The session on the member's row: the one running in its seat, else the ended one standing for it, which the
        // lead's `leads` and what's next for you name as they name a running one.
        NSString *holder = found[@"seat"] ?: found[@"ended"];
        if (!at.count) continue;
        if (holder && ![holder isEqualToString:recorded]) seated[recorded] = holder;
        NSString *holderName = nil;
        for (NSNumber *i in at) if ([rows[i.unsignedIntegerValue].sessionId isEqual:holder])
            holderName = rows[i.unsignedIntegerValue].name;
        NSDictionary *duplicates = found[@"duplicates"];
        for (NSNumber *i in at) {
            NSString *sid = rows[i.unsignedIntegerValue].sessionId;
            if ([sid isEqualToString:holder]) {
                places[i.unsignedIntegerValue] = self.members[recorded][@"place"];
            } else if (duplicates[sid]) {
                NSMutableDictionary *mark = [@{@"inFolderOf": seat[@"name"], @"duplicate": @YES,
                                               @"earlier": duplicates[sid]} mutableCopy];
                if (holderName.length) mark[@"seat"] = holderName;
                places[i.unsignedIntegerValue] = mark;
            } else if (holder && [sid isEqualToString:recorded]) {
                // The file's own session, ended, while another holds its seat or stands for the member: an ended one in
                // the member's folder.
                places[i.unsignedIntegerValue] = @{@"inFolderOf": seat[@"name"], @"history": @YES};
            }
        }
    }
    self.lastSeats = holders;
    // The lead's place, copied for this pass: each member's seat put in for the file's id, among the sessions it leads
    // and in what's next for you, so a pick for the member reaches the session on its row, never a duplicate.
    if (seated.count) {
        for (NSUInteger i = 0; i < places.count; i++) {
            NSDictionary *place = places[i];
            NSArray *leads = [place isKindOfClass:NSDictionary.class] ? place[@"leads"] : nil;
            if (!leads.count) continue;
            NSMutableDictionary *copy = [place mutableCopy];
            NSMutableArray *seats = [NSMutableArray array];
            for (NSString *one in leads) [seats addObject:seated[one] ?: one];
            copy[@"leads"] = [seats sortedArrayUsingSelector:@selector(compare:)];
            NSString *forId = AsText(place[@"next"][@"for"]);
            if (forId && seated[forId] && [leads containsObject:forId]) {
                NSMutableDictionary *next = [place[@"next"] mutableCopy];
                next[@"for"] = seated[forId];
                copy[@"next"] = next;
            }
            places[i] = copy;
        }
    }
    return places;
}

// A row as SeatOf takes it: {session, process, pid, startedAt, running, movedAt}, `movedAt` being when its
// conversation last moved, in ms, as the list's lastActive (whose-move.js) has it: your message, Claude's reply or its
// newest message, else its live line, else its status.
- (NSDictionary *)seatedAs:(Row *)row {
    double moved = MAX(MAX(row.lastReplyAt.doubleValue, row.lastPromptAt.doubleValue), row.messageAt.doubleValue)
        ?: row.activityAt.doubleValue ?: row.statusUpdatedAt.doubleValue;
    NSMutableDictionary *one = [@{@"session": row.sessionId, @"running": @(![row.status isEqual:@"closed"]),
                                  @"startedAt": @0, @"movedAt": @(moved)} mutableCopy];
    if (row.pid > 0) {
        one[@"process"] = ProcessKey(row.pid, row.procStart);
        one[@"pid"] = @(row.pid);
        one[@"startedAt"] = @(ProcessStartedAt(row.pid));
    }
    return one;
}

// Whether the seat's last holder still runs, the same process, though no row listed has it: then nobody else takes
// its seat this pass.
- (BOOL)stillRuns:(NSDictionary *)last among:(NSSet<NSString *> *)processes {
    pid_t pid = [last[@"pid"] intValue];
    if (pid <= 0 || [processes containsObject:AsText(last[@"process"]) ?: @""]) return NO;
    long long started = [last[@"startedAt"] longLongValue];
    return ProcessAlive(pid) && (!started || ProcessStartedAt(pid) == started);
}

@end
