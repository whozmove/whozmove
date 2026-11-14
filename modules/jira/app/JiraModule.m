// JiraModule: Jira's face for the core (Module) and its tracker (Tracker): signing in with Atlassian, its page on the
// panel's back with Sign In and Sign Out, a notice when the sign-in has run out, and Jira's tickets read, searched,
// moved, noted on and made, each through Atlassian's server for AI tools (JiraFacts).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import "Module.h"
#import "Notice.h"
#import "Tracker.h"
#import "Core.h"
#import "Files.h"
#import "Keychain.h"
#import "Links.h"
#import "Log.h"
#import "MCP.h"
#import "JiraAccount.h"
#import "JiraCard.h"
#import "JiraFacts.h"
#import "JiraTickets.h"
#import "JiraPrints.h"

// How long a request to Atlassian may take, and how long the boards of a project are kept before they're read again,
// as are its priorities, which are read sooner only for a priority not among them, and then at most once in ten
// minutes a project.
static const NSTimeInterval kJiraTimeout = 30;
static const NSTimeInterval kBoardsKept = 60 * 60;
static const NSTimeInterval kPrioritiesKept = 60 * 60, kPrioritiesAgain = 10 * 60;

@interface JiraModule : NSObject <Module, Tracker>
@property (weak) Core *core;
@property (strong) NSURLSession *session;
@property (strong) JiraAccount *account;
@property (strong) MCPClient *server;
@property (copy) NSArray<NSString *> *knownSites;
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *boards;  // "site key" → {at, groups}
// "site key" → {order, readAt, againAt, reading, waiting}: the project's priorities, most pressing first, each {id,
// name}, when they were last read, when they were last asked for sooner than the hour, or didn't answer, whether
// they're being read now, and meanwhile the project's other tickets waiting for that read to place them.
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *priorities;
// "site project type" → {at, fields}: the fields a type of a project's tickets takes one option of, kept an hour.
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *optionFields;
@property (strong) NSDate *slowUntil;  // Atlassian asked to slow down until then
@property (assign) BOOL copiedAsk;
// What opens Atlassian's page for you: your browser, but in Jira's tests, which follow the page themselves.
@property (copy) void (^opener)(NSURL *page);
@end

@implementation JiraModule

+ (NSString *)moduleName {
    return @"jira";
}

+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return @{@"--print-jira": ^int(Core *core, NSArray<NSString *> *arguments) { return PrintJira(arguments); }};
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.session = JiraSession(kJiraTimeout);
    self.account = [[JiraAccount alloc] initWithSession:self.session];
    self.server = [[MCPClient alloc] initWithURL:JiraServer() session:self.session name:@"Whozmove"
                                         version:JiraVersion()];
    self.boards = [NSMutableDictionary dictionary];
    self.priorities = [NSMutableDictionary dictionary];
    return self;
}

// ---- Tracker ----

- (NSString *)trackerName {
    return @"Jira";
}
- (NSString *)signInName {
    return @"Atlassian";
}
- (TrackerSignIn)signInState {
    return self.account.state;
}
- (void)findSites:(void (^)(NSArray<NSString *> *))done {
    if (self.account.state != TrackerSignedIn) return done(@[]);
    [self loadSites:^(TrackerAnswer *answer) { done(self.sites); }];
}
- (NSString *)adminAsk {
    return JiraWhatToAsk();
}
- (NSString *)signInWhy {
    return self.account.why;
}
- (NSArray<NSString *> *)sites {
    return self.account.state == TrackerSignedIn ? self.knownSites ?: @[] : @[];
}

- (void)signIn:(void (^)(TrackerSignIn, NSString *))done {
    // A new build: your press of Allow asks macOS for the sign-in kept, rather than signing in again.
    if (self.account.state == TrackerSignInAsksMac)
        return [self.account allow:^(TrackerSignIn state, NSString *why) {
            if (state != TrackerSignedIn) return done(state, why);
            [self loadSites:^(TrackerAnswer *answer) { done(self.account.state, self.account.why); }];
        }];
    void (^opener)(NSURL *) = self.opener ?: ^(NSURL *page) { OpenInWebBrowser(page); };
    [self.account signInOpening:opener
                           done:^(TrackerSignIn state, NSString *why) {
        [self.server reset];
        if (state != TrackerSignedIn) return done(state, why);
        self.knownSites = nil;
        [self loadSites:^(TrackerAnswer *answer) { done(self.account.state, self.account.why); }];
    }];
}
- (void)cancelSignIn {
    [self.account cancelSignIn];
}
- (void)signOut {
    [self.account signOut];
    [self.server reset];
    self.knownSites = nil;
    [self.boards removeAllObjects];
    [self.priorities removeAllObjects];
}

- (NSString *)keyIn:(NSString *)text site:(NSString **)site {
    return JiraKeyIn(text, site);
}
- (NSString *)linkFor:(NSString *)key site:(NSString *)site {
    return JiraLinkFor(key, site);
}

// One tool called on Atlassian's server, with a token, as you: a 401 refreshes the token once and calls again. What it
// answered, or why not, as a tracker's answer; a tool's own error ({error: true}, or one in its data) counts as not
// done. A tool that
// writes isn't called while the sign-in reads only, and one Atlassian refuses for its scope (a 403, or its own error
// naming a scope) means signing in again, as a sign-in kept before Whozmove asked to write has no write scope.
- (void)call:(NSString *)tool arguments:(NSDictionary *)arguments again:(BOOL)again
        done:(void (^)(id value, TrackerAnswer *answer))done {
    if (self.slowUntil.timeIntervalSinceNow > 0) return done(nil, [self slowDown]);
    BOOL writes = JiraToolWrites(tool);
    [self.account token:^(NSString *token, TrackerAnswer *answer) {
        if (!token) return done(nil, answer);
        if (writes && self.account.readsOnly)
            return done(nil, [TrackerAnswer end:TrackerEndSignIn why:kJiraReadsOnly]);
        self.server.accessToken = token;
        [self.server call:tool arguments:arguments done:^(id value, MCPEnd end, NSString *why, NSDate *retryAt) {
            NSInteger error = end == MCPEndAnswered || end == MCPEndToolFailed ? JiraErrorIn(value) : 0;
            if (writes && (end == MCPEndRefused || error == 403 || JiraErrorNamesScope(value))) {
                [self.account writesRefused];
                PanelLog(@"Jira: %@ was refused for the sign-in's scope", tool);
                return done(nil, [TrackerAnswer end:TrackerEndSignIn why:kJiraReadsOnly]);
            }
            if ((end == MCPEndSignIn || error == 401) && !again) {
                [self.account tokenRefused];
                return [self call:tool arguments:arguments again:YES done:done];
            }
            if (end == MCPEndSlowDown || error == 429) {
                self.slowUntil = retryAt ?: [NSDate dateWithTimeIntervalSinceNow:60];
                PanelLog(@"Jira: Atlassian asked to slow down");
                return done(nil, [self slowDown]);
            }
            if (end == MCPEndAnswered && !error) return done(value, [TrackerAnswer done]);
            // A new ticket Jira turns away as given (400): a priority, a parent or a field that project wants. A move
            // it turns away (a 4xx: a field to fill in on the ticket first, or a move that isn't yours), with what Jira
            // said if it said anything, which trying again as it is won't change. A 5xx, reasons or not, is Jira not
            // managing it just then, as when it couldn't be reached, which trying again may mend.
            BOOL turnedAway = [tool isEqualToString:kJiraToolTransition] && JiraTurnedAway(value);
            TrackerEnd ended = end == MCPEndSignIn || error == 401 ? TrackerEndSignIn
                : end == MCPEndRefused || error == 403 ? TrackerEndBlocked
                : error == 404 ? TrackerEndNotFound
                : error == 400 && [tool isEqualToString:kJiraToolCreate] ? TrackerEndRefused
                : turnedAway ? TrackerEndRefused : TrackerEndFailed;
            NSString *says = ended == TrackerEndRefused && turnedAway ? @"Jira turned it away"
                : ended == TrackerEndSignIn ? @"The sign-in has run out"
                : ended == TrackerEndBlocked ? @"Atlassian turned Whozmove away for this site: your Jira admin can allow it"
                : ended == TrackerEndNotFound ? @"There's no such ticket, or it isn't yours to see"
                : ended == TrackerEndRefused ? @"Jira turned it away as it is: a priority, a parent or a field this "
                                               @"project wants may be wrong"
                : @"Couldn't reach Jira just now";
            // How, in Whozmove's own words and numbers, never the answer's: the tool's own error by its status, else
            // how the call failed (MCPHowItFailed).
            NSString *how = error ? [NSString stringWithFormat:@"its own error, %ld", (long)error] : why ?: @"unknown";
            PanelLog(@"Jira: %@ didn't answer (%ld): %@", tool, (long)ended, how);
            TrackerAnswer *answer = [TrackerAnswer end:ended why:says];
            if (ended == TrackerEndRefused && turnedAway) answer.trackerSays = JiraErrorWords(value);
            done(nil, answer);
        }];
    }];
}

- (TrackerAnswer *)slowDown {
    TrackerAnswer *answer = [TrackerAnswer end:TrackerEndSlowDown why:@"Atlassian asked Whozmove to slow down"];
    answer.retryAt = self.slowUntil;
    return answer;
}

// A tool v2 lists only through its deferred calls: by name, the site as its cloudId, and its inputs as one flat object.
- (void)callDeferred:(NSString *)tool write:(BOOL)write site:(NSString *)site inputs:(NSDictionary *)inputs
                done:(void (^)(id value, TrackerAnswer *answer))done {
    [self call:write ? kJiraExecuteWrite : kJiraExecuteRead
     arguments:@{@"name": tool, @"cloudId": JiraCloudId(site), @"inputs": inputs} again:NO done:done];
}

// The Jira sites you're on, read once after signing in (and after a launch, before the first search).
- (void)loadSites:(void (^)(TrackerAnswer *answer))done {
    if (self.knownSites) return done([TrackerAnswer done]);
    [self call:kJiraToolSites arguments:@{} again:NO done:^(id value, TrackerAnswer *answer) {
        if (answer.ok) self.knownSites = JiraSitesIn(value);
        if (answer.end == TrackerEndBlocked) [self.account blocked];
        done(answer);
    }];
}

- (void)search:(NSString *)words done:(TicketsDone)done {
    [self loadSites:^(TrackerAnswer *sitesAnswer) {
        NSArray *sites = self.knownSites;
        // Asked to slow down, it says so with its time to try again, rather than that the sites are gone.
        if (!sites.count) return done(@[], self.account.state != TrackerSignedIn
            ? [TrackerAnswer end:TrackerEndSignIn why:@"Sign in with Atlassian first"]
            : !sitesAnswer.ok ? sitesAnswer
            : [TrackerAnswer end:TrackerEndNotFound why:@"Your Atlassian account reaches no Jira site: sign in with "
                                                      @"another on Jira's page, on the panel's back"]);
        NSMutableArray *found = [NSMutableArray array];
        __block TrackerAnswer *last = [TrackerAnswer done];
        __block NSUInteger left = sites.count;
        for (NSString *site in sites) {
            NSDictionary *arguments = @{@"cloudId": JiraCloudId(site), @"jql": JiraSearchFor(words),
                                        @"maxResults": @(kJiraSearchMost), @"view": kJiraReadView};
            [self call:kJiraToolSearch arguments:arguments again:NO done:^(id value, TrackerAnswer *answer) {
                if (answer.ok) for (NSDictionary *issue in JiraIssuesIn(value)) {
                    Ticket *ticket = JiraTicketFrom(issue, site);
                    if (ticket) [found addObject:ticket];
                } else last = answer;
                if (--left) return;
                done(found, found.count || last.ok ? [TrackerAnswer done] : last);
            }];
        }
    }];
}

- (void)read:(NSString *)key site:(NSString *)site done:(TicketDone)done {
    [self read:key site:site withSteps:^(Ticket *ticket, TrackerAnswer *answer, id steps) { done(ticket, answer); }];
}

// A read, with Jira's own answer for its next steps as well, which a move turns its fields into Jira's shapes from.
- (void)read:(NSString *)key site:(NSString *)site
   withSteps:(void (^)(Ticket *ticket, TrackerAnswer *answer, id steps))done {
    if (!JiraIsKey(key) || !JiraIsSite(site))
        return done(nil, [TrackerAnswer end:TrackerEndNotFound why:@"That isn't a Jira ticket"], nil);
    NSDictionary *arguments = @{@"cloudId": JiraCloudId(site), @"issueIdOrKey": key, @"view": kJiraReadView};
    [self call:kJiraToolIssue arguments:arguments again:NO done:^(id value, TrackerAnswer *answer) {
        NSDictionary *issue = answer.ok ? JiraIssueIn(value) : nil;
        Ticket *ticket = issue ? JiraTicketFrom(issue, site) : nil;
        if (!ticket)
            return done(nil, answer.ok ? [TrackerAnswer end:TrackerEndFailed why:@"Couldn't read it now"] : answer, nil);
        [self typeOf:ticket done:^{
            // Its next steps, from Jira's own transitions for this ticket now, with the fields each one's screen needs.
            [self callDeferred:kJiraToolTransitions write:NO site:site
                        inputs:@{@"issueIdOrKey": key, @"expand": @"transitions.fields"}
                          done:^(id steps, TrackerAnswer *stepsAnswer) {
                // Steps it couldn't read end the read with that answer (asked to slow down, say): a ticket read with
                // none would tell a move its step had gone.
                if (!stepsAnswer.ok) return done(nil, stepsAnswer, nil);
                ticket.steps = JiraStepsIn(steps);
                [self boardsOf:ticket done:^{
                    [self place:ticket priority:JiraPriorityIdOf(issue) done:^{ done(ticket, [TrackerAnswer done], steps); }];
                }];
            }];
        }];
    }];
}

// The ticket's place among its project's priorities, matched by Jira's id. The list is kept an hour a project, and
// asked for sooner only for a priority not among it, at most once in ten minutes, never while Atlassian asked to slow
// down, and once at a time a project: a ticket read meanwhile waits for that read, and is placed by it. Not read
// (offline, slowed down, not allowed, no type that lists them), the ticket reads all the same, by the list it had, else
// with no place, until a later read places it.
- (void)place:(Ticket *)ticket priority:(NSString *)priorityId done:(void (^)(void))done {
    TicketGroup *project = ticket.groups.firstObject;
    if (!priorityId || !project.groupId) return done();
    NSString *kept = [NSString stringWithFormat:@"%@ %@", ticket.site, project.groupId];
    NSDictionary *known = self.priorities[kept];
    BOOL fresh = known[@"readAt"] && [known[@"readAt"] timeIntervalSinceNow] > -kPrioritiesKept;
    BOOL again = known[@"againAt"] && [known[@"againAt"] timeIntervalSinceNow] > -kPrioritiesAgain;
    // An empty list is a project with no order (no type that lists its priorities): no sooner read for that.
    BOOL settled = fresh && (JiraPlaceIn(ticket, priorityId, known[@"order"]) || ![known[@"order"] count]);
    // Being read already, for another of the project's tickets (all of them are read together as Whozmove starts):
    // placed when that read answers, rather than going a whole read unplaced.
    if (known[@"reading"]) {
        NSMutableDictionary *reading = (NSMutableDictionary *)known;
        [reading[@"waiting"] addObject:^{
            JiraPlaceIn(ticket, priorityId, reading[@"order"]);
            done();
        }];
        return;
    }
    if (settled || again) {
        JiraPlaceIn(ticket, priorityId, known[@"order"]);
        return done();
    }
    // Asked again within the hour, for a priority not among them, or after a read that didn't answer: not again for
    // ten minutes.
    NSMutableDictionary *next = [known mutableCopy] ?: [NSMutableDictionary dictionary];
    if (fresh) next[@"againAt"] = NSDate.date;
    next[@"reading"] = @YES;
    next[@"waiting"] = [NSMutableArray array];
    self.priorities[kept] = next;
    [self prioritiesOf:project.groupId site:ticket.site done:^(NSArray *order) {
        NSArray *waiting = next[@"waiting"];
        [next removeObjectsForKeys:@[@"reading", @"waiting"]];
        if (order) [next addEntriesFromDictionary:@{@"order": order, @"readAt": NSDate.date}];
        else next[@"againAt"] = NSDate.date;
        JiraPlaceIn(ticket, priorityId, next[@"order"]);
        done();
        for (void (^placed)(void) in waiting) placed();
    }];
}

// A project's priorities in their scheme's order, read from its type that lists them (JiraFacts): empty for a project
// without that type, nil when either read didn't answer.
- (void)prioritiesOf:(NSString *)project site:(NSString *)site done:(void (^)(NSArray *order))done {
    [self callDeferred:kJiraToolIssueTypes write:NO site:site inputs:@{@"projectIdOrKey": project}
                  done:^(id types, TrackerAnswer *answer) {
        if (!answer.ok) return done(nil);
        NSString *typeId = JiraTypeIdIn(types, kJiraPriorityType);
        if (!typeId) return done(@[]);
        [self callDeferred:kJiraToolTypeFields write:NO site:site
                    inputs:@{@"projectIdOrKey": project, @"issueTypeId": typeId,
                             @"maxResults": @(kJiraFieldsMost)}
                      done:^(id fields, TrackerAnswer *read) { done(read.ok ? JiraPrioritiesIn(fields) : nil); }];
    }];
}

// The ticket's type, when its read left it out (a view smaller than v2's full one does): from a search for its key.
// A search that can't say leaves it without one, and none is made while Atlassian has asked to slow down.
- (void)typeOf:(Ticket *)ticket done:(void (^)(void))done {
    if (ticket.type.length || self.slowUntil.timeIntervalSinceNow > 0) return done();
    NSDictionary *arguments = @{@"cloudId": JiraCloudId(ticket.site), @"jql": JiraSearchFor(ticket.key),
                                @"maxResults": @1, @"view": kJiraReadView};
    [self call:kJiraToolSearch arguments:arguments again:NO done:^(id value, TrackerAnswer *answer) {
        for (NSDictionary *issue in answer.ok ? JiraIssuesIn(value) : @[])
            if ([AsText(issue[@"key"]) isEqualToString:ticket.key]) ticket.type = JiraTicketFrom(issue, ticket.site).type;
        done();
    }];
}

// The boards the ticket's project is on, added to its groups after its project, kept an hour a project.
- (void)boardsOf:(Ticket *)ticket done:(void (^)(void))done {
    TicketGroup *project = ticket.groups.firstObject;
    if (!project.groupId) return done();
    NSString *kept = [NSString stringWithFormat:@"%@ %@", ticket.site, project.groupId];
    // With the project's name, which a read of the issue may leave out, from what the boards answer says of it.
    void (^add)(NSArray *, NSString *) = ^(NSArray *boards, NSString *name) {
        for (TicketGroup *board in boards) board.sprint = project.sprint;
        if (name.length && [project.name isEqualToString:project.groupId]) project.name = name;
        ticket.groups = [@[project] arrayByAddingObjectsFromArray:boards];
        done();
    };
    NSDictionary *known = self.boards[kept];
    if (known && [known[@"at"] timeIntervalSinceNow] > -kBoardsKept) return add(known[@"groups"], known[@"name"]);
    [self callDeferred:kJiraToolBoards write:NO site:ticket.site inputs:@{@"projectKeyOrId": project.groupId}
                  done:^(id value, TrackerAnswer *answer) {
        NSArray *boards = answer.ok ? JiraBoardsIn(value) : @[];
        NSString *name = answer.ok ? JiraProjectNameIn(value, project.groupId) : nil;
        if (answer.ok) self.boards[kept] = name ? @{@"at": NSDate.date, @"groups": boards, @"name": name}
                                                : @{@"at": NSDate.date, @"groups": boards};
        add(boards, name);
    }];
}

- (void)take:(NSString *)stepId of:(NSString *)key site:(NSString *)site note:(NSString *)note
      fields:(NSDictionary *)fields done:(TicketDone)done {
    // A sign-in that reads only can't move it: nothing is asked of Atlassian.
    if (self.account.readsOnly) return done(nil, [TrackerAnswer end:TrackerEndSignIn why:kJiraReadsOnly]);
    // Read first: a step that isn't one of the ticket's now (it has moved on) is never sent.
    [self read:key site:site withSteps:^(Ticket *ticket, TrackerAnswer *answer, id steps) {
        if (!ticket) return done(nil, answer);
        BOOL listed = NO;
        for (TicketStep *step in ticket.steps) if ([step.stepId isEqualToString:stepId]) listed = YES;
        if (!listed) return done(ticket, [TrackerAnswer end:TrackerEndStepGone
                                                        why:[NSString stringWithFormat:@"%@ is %@ already",
                                                             key, ticket.state.name]]);
        // The fields as every tracker gives them, in Jira's own shapes for this step's screen as just read.
        NSString *why = nil;
        NSDictionary *shaped = fields.count ? JiraFieldsFor(steps, stepId, fields, &why) : @{};
        if (!shaped) return done(ticket, [TrackerAnswer end:TrackerEndFailed why:why]);
        NSMutableDictionary *arguments = [@{@"cloudId": JiraCloudId(site), @"issueIdOrKey": key,
                                            @"transitionId": stepId} mutableCopy];
        if (shaped.count) arguments[@"fields"] = shaped;
        [self call:kJiraToolTransition arguments:arguments again:NO done:^(id value, TrackerAnswer *moved) {
            if (!moved.ok) return done(ticket, moved);
            PanelLog(@"Jira: %@ moved", key);
            void (^after)(void) = ^{ [self read:key site:site done:done]; };
            if (!note.length) return after();
            [self addNote:note to:key site:site done:^(TrackerAnswer *noted) { after(); }];
        }];
    }];
}

- (void)addNote:(NSString *)note to:(NSString *)key site:(NSString *)site done:(void (^)(TrackerAnswer *))done {
    if (self.account.readsOnly) return done([TrackerAnswer end:TrackerEndSignIn why:kJiraReadsOnly]);
    [self call:kJiraToolComment arguments:@{@"cloudId": JiraCloudId(site), @"issueIdOrKey": key, @"commentBody": note}
         again:NO done:^(id value, TrackerAnswer *answer) { done(answer); }];
}

- (void)newTicketOptions:(NSString *)group site:(NSString *)site
                    done:(void (^)(NSDictionary *, TrackerAnswer *))done {
    [self callDeferred:kJiraToolIssueTypes write:NO site:site inputs:@{@"projectIdOrKey": group ?: @""}
                  done:^(id value, TrackerAnswer *answer) {
        if (!answer.ok) return done(nil, answer);
        // A Jira ticket's group is its project.
        done(@{@"group": group ?: @"", @"kind": @"project", @"types": JiraIssueTypesIn(value)}, [TrackerAnswer done]);
    }];
}

// The fields a ticket's project takes one option of for its type, from that type's create fields (JiraFacts), kept an
// hour: read through the same calls, and the same slow-down, as the rest.
- (void)optionFieldsOf:(Ticket *)ticket done:(void (^)(NSArray<TicketField *> *, TrackerAnswer *))done {
    NSString *project = ticket.groups.firstObject.groupId, *site = ticket.site, *type = ticket.type;
    if (!project.length || !type.length || !JiraIsSite(site))
        return done(nil, [TrackerAnswer end:TrackerEndNotFound why:@"Couldn't tell its project and type"]);
    NSString *kept = [NSString stringWithFormat:@"%@ %@ %@", site, project, type];
    NSDictionary *known = self.optionFields[kept];
    if (known && [known[@"at"] timeIntervalSinceNow] > -kBoardsKept) return done(known[@"fields"], [TrackerAnswer done]);
    [self callDeferred:kJiraToolIssueTypes write:NO site:site inputs:@{@"projectIdOrKey": project}
                  done:^(id types, TrackerAnswer *answer) {
        if (!answer.ok) return done(nil, answer);
        NSString *typeId = JiraTypeIdIn(types, type);
        if (!typeId) return done(@[], [TrackerAnswer done]);
        [self callDeferred:kJiraToolTypeFields write:NO site:site
                    inputs:@{@"projectIdOrKey": project, @"issueTypeId": typeId, @"maxResults": @(kJiraFieldsMost)}
                      done:^(id fields, TrackerAnswer *read) {
            if (!read.ok) return done(nil, read);
            NSArray *found = JiraOptionFieldsIn(fields);
            if (!self.optionFields) self.optionFields = [NSMutableDictionary dictionary];
            self.optionFields[kept] = @{@"at": NSDate.date, @"fields": found};
            done(found, [TrackerAnswer done]);
        }];
    }];
}

- (void)create:(NSDictionary *)draft site:(NSString *)site done:(TicketDone)done {
    NSMutableDictionary *arguments = [@{@"cloudId": JiraCloudId(site), @"projectKey": AsText(draft[@"group"]) ?: @"",
                                        @"issueType": AsText(draft[@"type"]) ?: @"Task",
                                        @"summary": AsText(draft[@"title"]) ?: @""} mutableCopy];
    if (AsText(draft[@"description"])) arguments[@"description"] = draft[@"description"];
    if (AsText(draft[@"priority"])) arguments[@"priority"] = draft[@"priority"];
    if (JiraIsKey(AsText(draft[@"parent"]))) arguments[@"parent"] = draft[@"parent"];
    [self call:kJiraToolCreate arguments:arguments again:NO done:^(id value, TrackerAnswer *answer) {
        NSString *key = AsText(AsRecord(value)[@"key"]) ?: AsText(AsRecord(AsRecord(value)[@"data"])[@"key"]);
        if (!answer.ok || !JiraIsKey(key))
            return done(nil, answer.ok ? [TrackerAnswer end:TrackerEndFailed why:@"Jira didn't say the new ticket's key"]
                                       : answer);
        PanelLog(@"Jira: %@ created", key);
        // Made: answered as done with its key and site whatever the read brings, so it's never made again.
        [self read:key site:site done:^(Ticket *ticket, TrackerAnswer *read) {
            // Its type, if the read had none (a search may not find a ticket made a moment ago): the one it was made as.
            if (ticket && !ticket.type.length) ticket.type = arguments[@"issueType"];
            if (ticket) return done(ticket, read);
            Ticket *made = [Ticket new];
            made.tracker = @"Jira";
            made.site = site;
            made.key = key;
            made.link = JiraLinkFor(key, site);
            made.type = arguments[@"issueType"];
            done(made, [TrackerAnswer done]);
        }];
    }];
}

// Every ticket you can see: each site's search (JiraEveryJQL), at most kJiraEveryMost a site, a page at a time, each
// ticket placed among its project's priorities; with no site, why, as the card's search says it.
- (void)everyTicketSince:(NSDate *)since done:(TicketsDone)done {
    [self loadSites:^(TrackerAnswer *sitesAnswer) {
        NSArray *sites = self.knownSites;
        if (!sites.count) return done(@[], self.account.state != TrackerSignedIn
            ? [TrackerAnswer end:TrackerEndSignIn why:@"Sign in with Atlassian first"]
            : !sitesAnswer.ok ? sitesAnswer
            : [TrackerAnswer end:TrackerEndNotFound why:@"The user's Atlassian account reaches no Jira site: they can "
                                                      @"sign in with another on Jira's page, on the panel's back"]);
        NSMutableArray *every = [NSMutableArray array];
        __block TrackerAnswer *last = nil;
        __block BOOL more = NO;
        __block NSUInteger left = sites.count;
        for (NSString *site in sites)
            [self tickets:JiraEveryJQL(since) site:site after:nil into:[NSMutableArray array]
                     done:^(NSArray<Ticket *> *tickets, TrackerAnswer *answer) {
                [every addObjectsFromArray:tickets];
                if (!answer.ok) last = answer;
                more = more || answer.more;
                if (--left) return;
                // One site's failure fails the read only when none answered; else the list says it's part.
                if (!every.count && last) return done(@[], last);
                // The most recently changed first across the sites, as Jira writes a time, which sorts as text.
                [every sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(Ticket *a, Ticket *b) {
                    return [b.updated ?: @"" compare:a.updated ?: @""];
                }];
                TrackerAnswer *told = [TrackerAnswer done];
                told.more = more || last;
                done(every, told);
            }];
    }];
}

// One page of a search, then the next, until the last page or kJiraEveryMost; then each ticket placed.
- (void)tickets:(NSString *)jql site:(NSString *)site after:(NSString *)page into:(NSMutableArray *)found
           done:(TicketsDone)done {
    NSMutableDictionary *arguments = [@{@"cloudId": JiraCloudId(site), @"jql": jql, @"maxResults": @(kJiraSearchMost),
                                        @"view": kJiraReadView} mutableCopy];
    if (page) arguments[@"nextPageToken"] = page;
    [self call:kJiraToolSearch arguments:arguments again:NO done:^(id value, TrackerAnswer *answer) {
        // A page after the first that fails keeps those read before it, said to be part of the list; the first's
        // failure is the read's.
        if (!answer.ok && !page) return done(@[], answer);
        if (!answer.ok) {
            TrackerAnswer *part = [TrackerAnswer done];
            part.more = YES;
            return done(found, part);
        }
        NSMutableArray<NSDictionary *> *issues = [NSMutableArray array];
        NSMutableSet *keys = [NSMutableSet set];
        for (Ticket *ticket in found) [keys addObject:ticket.key];
        BOOL cut = NO;
        for (NSDictionary *issue in JiraIssuesIn(value)) {
            Ticket *ticket = JiraTicketFrom(issue, site);
            // A page given again (a server that didn't take the page's token) adds nothing twice.
            if (!ticket || [keys containsObject:ticket.key]) continue;
            if ((NSInteger)found.count >= kJiraEveryMost) {
                cut = YES;
                continue;
            }
            [keys addObject:ticket.key];
            [found addObject:ticket];
            [issues addObject:issue];
        }
        NSString *next = JiraNextPageIn(value);
        // A full page that names no next one and doesn't say it's the last may be followed by more all the same.
        BOOL unsure = !next && !JiraIsLastPage(value) && JiraIssuesIn(value).count >= (NSUInteger)kJiraSearchMost;
        // Each placed by its own priority's id, from the issue it came as.
        __block NSUInteger left = issues.count + 1;
        void (^placed)(void) = ^{
            if (--left) return;
            if (next && (NSInteger)found.count < kJiraEveryMost && ![next isEqual:page] && issues.count)
                return [self tickets:jql site:site after:next into:found done:done];
            // Cut at the most it reads, or stopped with a page named and unread, or one that may follow: said, so the
            // list isn't taken as whole.
            TrackerAnswer *answer = [TrackerAnswer done];
            answer.more = cut || next || unsure;
            done(found, answer);
        };
        NSUInteger from = found.count - issues.count;
        for (NSUInteger i = 0; i < issues.count; i++)
            [self place:found[from + i] priority:JiraPriorityIdOf(issues[i]) done:placed];
        placed();
    }];
}

// One read, with its history: the issue with its changelog, its moves taken from it and its priority placed. Its next
// steps aren't read: whoever reads a ticket whole doesn't move it by them.
- (void)readWhole:(NSString *)key site:(NSString *)site done:(TicketDone)done {
    if (!JiraIsKey(key) || !JiraIsSite(site))
        return done(nil, [TrackerAnswer end:TrackerEndNotFound why:@"That isn't a Jira ticket"]);
    NSDictionary *arguments = @{@"cloudId": JiraCloudId(site), @"issueIdOrKey": key, @"view": kJiraReadView,
                                @"expand": kJiraHistoryExpand};
    [self call:kJiraToolIssue arguments:arguments again:NO done:^(id value, TrackerAnswer *read) {
        NSDictionary *issue = read.ok ? JiraIssueIn(value) : nil;
        Ticket *ticket = issue ? JiraTicketFrom(issue, site) : nil;
        if (!ticket) return done(nil, read.ok ? [TrackerAnswer end:TrackerEndFailed why:@"Couldn't read it now"] : read);
        ticket.moves = JiraMovesIn(issue);
        [self place:ticket priority:JiraPriorityIdOf(issue) done:^{ done(ticket, [TrackerAnswer done]); }];
    }];
}

// ---- Module ----

// Jira on the panel's back: how the sign-in stands, with Sign In with Atlassian, Cancel, Sign Out, Sign In Again (for
// one that reads only), or what to ask an admin.
- (NSArray<AppEntry *> *)appEntries {
    __weak typeof(self) weakSelf = self;
    AppEntry *jira = [AppEntry appWithId:@"jira" name:@"Jira"
                                    does:@"Gives a conversation a Jira ticket, and shows it on its row." order:150];
    jira.present = ^BOOL { return YES; };
    jira.hint = ^NSString * {
        return weakSelf.account.state == TrackerSignedIn ? nil : @"Sign in with Atlassian";
    };
    jira.card = ^NSDictionary * { return JiraCard(weakSelf.account.state, weakSelf.sites, weakSelf.account.why,
                                                  weakSelf.copiedAsk, weakSelf.account.readsOnly); };
    jira.act = ^(NSString *action) { [weakSelf act:action]; };
    return @[jira];
}

- (void)act:(NSString *)action {
    if ([action isEqualToString:@"signIn"]) {
        self.copiedAsk = NO;
        return [self signIn:^(TrackerSignIn state, NSString *why) {}];
    }
    if ([action isEqualToString:@"cancel"]) return [self cancelSignIn];
    if ([action isEqualToString:@"signOut"]) return [self signOut];
    if ([action isEqualToString:@"copyAsk"]) {
        [NSPasteboard.generalPasteboard clearContents];
        [NSPasteboard.generalPasteboard setString:JiraWhatToAsk() forType:NSPasteboardTypeString];
        self.copiedAsk = YES;
    }
}

// The sign-in, once it has run out: one notice, with Sign In Again, until you've signed in or out.
- (NSArray<Notice *> *)notices {
    TrackerSignIn state = self.account.state;
    if (state != TrackerSignInExpired && state != TrackerSignInAsksMac) return @[];
    // A new build's: only once something wanted the sign-in, so macOS's own box only ever follows your press of Allow.
    BOOL asks = state == TrackerSignInAsksMac;
    Notice *notice = [Notice noticeWithKey:asks ? @"allow" : @"signIn" level:NoticeSoon
                                      text:asks ? @"Whozmove was updated, so macOS asks once before it hands over Jira's "
                                                  @"sign-in: press Allow, then Always Allow."
                                                : self.account.why ?: @"Jira's sign-in has run out: sign in with Atlassian "
                                                                      @"again to see tickets."];
    notice.title = @"Jira";
    notice.button = asks ? @"Allow" : @"Sign In Again";
    __weak typeof(self) weakSelf = self;
    notice.press = ^{ [weakSelf act:@"signIn"]; };
    return @[notice];
}

@end

// ---- Jira's tests: a whole sign-in and every call, against a stand-in for Atlassian (JiraPrints.h) ----

// Runs the main thread's loop until `finished` is set, or a minute has passed.
static void WaitFor(BOOL *finished) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:60];
    while (!*finished && until.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}

static NSString *Said(TrackerAnswer *answer) {
    if (answer.ok) return @"done";
    NSArray *ends = @[@"done", @"sign in", @"macOS asks first", @"blocked", @"slow down", @"not found", @"step gone", @"failed",
                      @"refused"];
    return [NSString stringWithFormat:@"%@: %@%@%@", ends[answer.end], answer.why,
            answer.retryAt ? @" (with a time to try again)" : @"",
            answer.trackerSays ? [NSString stringWithFormat:@" (Jira says: %@)", answer.trackerSays] : @""];
}
static NSString *Line(id json) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:json ?: NSNull.null
        options:NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes | NSJSONWritingFragmentsAllowed error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

// The sign-in's Keychain entry, as the stand-in holds it for a test.
static NSString *const kSignInService = @"Whozmove: Atlassian sign-in";

// A new copy of the module, as after Whozmove starts again, following Atlassian's page the same way.
static JiraModule *Restarted(JiraModule *jira) {
    JiraModule *again = [[JiraModule alloc] initWithCore:nil];
    again.opener = jira.opener;
    return again;
}

int PrintJiraTalk(NSString *site, NSArray<NSString *> *steps) {
    JiraModule *jira = [[JiraModule alloc] initWithCore:nil];
    NSArray *states = @[@"signed out", @"signing in", @"signed in", @"blocked", @"expired", @"macOS asks first"];
    // The run is the browser: it follows Atlassian's page, which sends it straight back to Whozmove's listener.
    NSURLSession *browser = JiraSession(10);
    jira.opener = ^(NSURL *page) {
        printf("opened: %s\n", [page.query containsString:@"code_challenge_method=S256"]
               ? "Atlassian's page, with an S256 challenge and a state" : "a page without PKCE");
        [[browser dataTaskWithURL:page completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
            NSString *html = [[NSString alloc] initWithData:d ?: NSData.data encoding:NSUTF8StringEncoding];
            NSString *said = [html containsString:@"Signed in."] ? @"Signed in. You can close this tab."
                : [html containsString:@"Not signed in."] ? @"Not signed in." : @"(nothing)";
            dispatch_async(dispatch_get_main_queue(), ^{ printf("the browser's tab: %s\n", said.UTF8String); });
        }] resume];
    };
    for (NSString *step in steps) {
        NSArray *words = [step componentsSeparatedByString:@" "];
        NSString *verb = words.firstObject, *rest = words.count > 1 ? words[1] : @"";
        __block BOOL finished = NO;
        printf("== %s\n", step.UTF8String);
        if ([verb isEqualToString:@"signin"]) {
            [jira signIn:^(TrackerSignIn state, NSString *why) {
                printf("sign-in: %s%s\n", [states[state] UTF8String],
                       why ? [[@" (" stringByAppendingFormat:@"%@)", why] UTF8String] : "");
                printf("sites: %s\n", Line(jira.sites).UTF8String);
                finished = YES;
            }];
        } else if ([verb isEqualToString:@"newbuild"] || [verb isEqualToString:@"rewritten"]) {
            // As a new build starts: the stand-in says macOS would ask about the sign-in kept, which an older build
            // kept, and the module starts afresh, as it does in a new build. Or, `rewritten`, as a look-alike's quiet
            // rewrite would leave it: macOS would ask, though the entry still says this build kept it.
            [jira.account keepsSignIn];  // what was being kept is kept first: it's written off the main thread
            JiraStandInAsks(kSignInService, [verb isEqualToString:@"newbuild"]);
            jira = Restarted(jira);
            printf("sign-in: %s\n", [states[jira.signInState] UTF8String]);
            finished = YES;
        } else if ([verb isEqualToString:@"readonly"]) {
            // As a sign-in kept before Whozmove asked to write: the entry rewritten without the scopes it asked for, as
            // this build would, and the module starting afresh.
            [jira.account keepsSignIn];
            NSData *data = KeychainReadQuietly(kSignInService, @"atlassian", NULL);
            id parsed = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            NSMutableDictionary *kept = [AsRecord(parsed) mutableCopy];
            [kept removeObjectForKey:@"scopes"];
            BOOL without = kept && KeychainUpdateQuietly(kSignInService, @"atlassian",
                [NSJSONSerialization dataWithJSONObject:kept options:0 error:nil]);
            jira = Restarted(jira);
            printf("%s; sign-in: %s\n", without ? "kept without its scopes" : "not rewritten",
                   [states[jira.signInState] UTF8String]);
            finished = YES;
        } else if ([verb isEqualToString:@"card"]) {
            printf("card: %s\n", Line(jira.appEntries.firstObject.card()).UTF8String);
            finished = YES;
        } else if ([verb isEqualToString:@"replaced"]) {
            // As something else signed as Whozmove might: the entry replaced with what isn't a sign-in, and the module
            // starting afresh, as after a restart.
            [jira.account keepsSignIn];
            KeychainKeepAfresh(kSignInService, @"atlassian", [@"not a sign-in" dataUsingEncoding:NSUTF8StringEncoding]);
            jira = Restarted(jira);
            printf("sign-in: %s\n", [states[jira.signInState] UTF8String]);
            finished = YES;
        } else if ([verb isEqualToString:@"planted"]) {
            // As something else might plant one first: an entry shaped like the sign-in that other apps can read, and
            // the module starting afresh. Whozmove must not use it, and signing in again makes its own.
            [jira.account keepsSignIn];
            NSString *planted = @"{\"refresh\":\"planted-refresh\",\"client\":\"planted-client\"}";
            KeychainKeepAfresh(kSignInService, @"atlassian", [planted dataUsingEncoding:NSUTF8StringEncoding]);
            JiraStandInOpenAccess(kSignInService);
            jira = Restarted(jira);
            printf("sign-in: %s\n", [states[jira.signInState] UTF8String]);
            finished = YES;
        } else if ([verb isEqualToString:@"others"]) {
            // The entry turning into one other apps can read, while Whozmove runs.
            [jira.account keepsSignIn];
            JiraStandInOpenAccess(kSignInService);
            printf("the entry lets other apps read it now\n");
            finished = YES;
        } else if ([verb isEqualToString:@"refused"]) {
            // As when Atlassian turns the access token away: the next call refreshes it first.
            [jira.account tokenRefused];
            printf("the access token is turned away\n");
            finished = YES;
        } else if ([verb isEqualToString:@"restart"]) {
            [jira.account keepsSignIn];
            jira = Restarted(jira);
            printf("sign-in: %s%s\n", [states[jira.signInState] UTF8String],
                   jira.signInWhy ? [[@" (" stringByAppendingFormat:@"%@)", jira.signInWhy] UTF8String] : "");
            finished = YES;
        } else if ([verb isEqualToString:@"log"]) {
            // What panel.log says of the sign-in: its lines name no token, and a line's time is left out.
            [jira.account keepsSignIn];
            NSString *log = [NSString stringWithContentsOfFile:AppDir(@"panel.log") encoding:NSUTF8StringEncoding error:nil];
            for (NSString *line in [log componentsSeparatedByString:@"\n"]) {
                NSRange at = [line rangeOfString:@"  Jira: "];
                if (at.location != NSNotFound) printf("log: %s\n", [line substringFromIndex:at.location + 2].UTF8String);
            }
            // Nor a ticket's description, nor any word of an answer that failed: the stand-in's are all made up, as
            // "Made-up description…" and "Made-up server words…".
            printf("log: %s a ticket's description\n",
                   [log containsString:@"Made-up description"] ? "HAS" : "has none of");
            printf("log: %s a failed answer's words\n", [log containsString:@"Made-up server words"] ? "HAS" : "has none of");
            finished = YES;
        } else if ([verb isEqualToString:@"hows"]) {
            // How a call failed in each way a stand-in can't make in a test's time: a timeout, macOS's own errors.
            NSArray *codes = @[@(NSURLErrorTimedOut), @(NSURLErrorNotConnectedToInternet), @(NSURLErrorCannotFindHost),
                               @(NSURLErrorCannotConnectToHost), @(NSURLErrorNetworkConnectionLost),
                               @(NSURLErrorServerCertificateUntrusted), @(NSURLErrorCancelled)];
            for (NSNumber *code in codes)
                printf("how: %s\n", MCPHowItFailed([NSError errorWithDomain:NSURLErrorDomain code:code.integerValue
                                                                    userInfo:nil], 0, nil, NO, 30).UTF8String);
            printf("how: %s\n", (MCPHowItFailed(nil, 200, @{@"result": @{}}, NO, 30) ?: @"answered").UTF8String);
            finished = YES;
        } else if ([verb isEqualToString:@"notices"]) {
            for (Notice *notice in jira.notices) printf("notice: %s [%s]\n", notice.text.UTF8String, notice.button.UTF8String);
            finished = YES;
        } else if ([verb isEqualToString:@"kept"]) {
            // Read through the stand-in's own path, as the app reads the Keychain, and never printed.
            printf("keychain stand-in: %s\n", jira.account.keepsSignIn ? "holds the sign-in" : "empty");
            finished = YES;
        } else if ([verb isEqualToString:@"search"]) {
            [jira search:[step substringFromIndex:MIN(step.length, 7)] done:^(NSArray<Ticket *> *tickets, TrackerAnswer *answer) {
                printf("%s, %lu found\n", Said(answer).UTF8String, (unsigned long)tickets.count);
                for (Ticket *t in tickets) printf("  %s\n", Line([t json]).UTF8String);
                finished = YES;
            }];
        } else if ([verb isEqualToString:@"read"]) {
            [jira read:rest site:site done:^(Ticket *ticket, TrackerAnswer *answer) {
                printf("%s\n%s\n", Said(answer).UTF8String, ticket ? Line([ticket json]).UTF8String : "no ticket");
                if (ticket.about) printf("its description: %s\n", JiraAboutSaid(ticket.about).UTF8String);
                finished = YES;
            }];
        } else if ([verb isEqualToString:@"every"]) {
            // Every ticket you can see; `every changed`, only those changed in the last hour.
            NSDate *since = [rest isEqualToString:@"changed"] ? [NSDate dateWithTimeIntervalSinceNow:-3600] : nil;
            [jira everyTicketSince:since done:^(NSArray<Ticket *> *tickets, TrackerAnswer *answer) {
                printf("%s, %lu tickets%s\n", Said(answer).UTF8String, (unsigned long)tickets.count,
                       answer.more ? ", and more" : "");
                for (Ticket *t in tickets) {
                    NSMutableDictionary *json = [[t jsonWhole] mutableCopy];
                    [json removeObjectForKey:@"steps"];
                    printf("  %s\n", Line(json).UTF8String);
                }
                finished = YES;
            }];
        } else if ([verb isEqualToString:@"whole"]) {
            [jira readWhole:rest site:site done:^(Ticket *ticket, TrackerAnswer *answer) {
                printf("%s; its moves: %s\n", Said(answer).UTF8String,
                       ticket ? Line([ticket jsonWhole][@"moves"] ?: @[]).UTF8String : "none read");
                if (ticket.about) printf("its description: %s\n", JiraAboutSaid(ticket.about).UTF8String);
                finished = YES;
            }];
        } else if ([verb isEqualToString:@"take"] && words.count >= 3) {
            // After the step's id, its fields as one JSON object (no spaces in it), then the note.
            NSUInteger from = 3;
            NSDictionary *fields = nil;
            if (words.count > 3 && [words[3] hasPrefix:@"{"]) {
                fields = AsRecord([NSJSONSerialization JSONObjectWithData:[words[3] dataUsingEncoding:NSUTF8StringEncoding]
                                                                  options:0 error:nil]);
                from = 4;
            }
            NSString *note = words.count > from ? [[words subarrayWithRange:NSMakeRange(from, words.count - from)]
                                                   componentsJoinedByString:@" "] : nil;
            [jira take:words[2] of:rest site:site note:note fields:fields
                  done:^(Ticket *ticket, TrackerAnswer *answer) {
                printf("%s; it stands: %s\n", Said(answer).UTF8String, ticket.state.name.UTF8String ?: "unknown");
                finished = YES;
            }];
        } else if ([verb isEqualToString:@"fields"]) {
            // The fields a ticket of PAY of this type takes one option of: read, or kept from the read before.
            Ticket *ticket = [Ticket new];
            ticket.key = @"PAY-142";
            ticket.site = site;
            ticket.type = rest;
            TicketGroup *project = [TicketGroup new];
            project.groupId = @"PAY";
            ticket.groups = @[project];
            [jira optionFieldsOf:ticket done:^(NSArray<TicketField *> *fields, TrackerAnswer *answer) {
                printf("%s, %s\n", Said(answer).UTF8String, fields ? [NSString stringWithFormat:@"%lu fields",
                       (unsigned long)fields.count].UTF8String : "none read");
                for (TicketField *field in fields)
                    printf("  %s %s %s %s\n", field.fieldId.UTF8String, field.name.UTF8String, Line(field.options).UTF8String,
                           Line(field.optionIds).UTF8String);
                finished = YES;
            }];
        } else if ([verb isEqualToString:@"types"]) {
            [jira newTicketOptions:rest site:site done:^(NSDictionary *options, TrackerAnswer *answer) {
                printf("%s: %s\n", Said(answer).UTF8String, options ? Line(options).UTF8String : "no options");
                finished = YES;
            }];
        } else if ([verb isEqualToString:@"create"]) {
            // `create refused`, with a priority the project doesn't have; `create unread`, one that can't be read back.
            NSDictionary *draft = @{@"group": @"PAY", @"type": @"Bug",
                                    @"title": [rest isEqualToString:@"unread"] ? @"Saved cards, unread"
                                                                                : @"Saved cards vanish after an update",
                                    @"description": @"Every saved card is gone.",
                                    @"priority": [rest isEqualToString:@"refused"] ? @"Nope" : @"High",
                                    @"parent": @"PAY-120"};
            [jira create:draft site:site done:^(Ticket *ticket, TrackerAnswer *answer) {
                printf("%s: %s\n", Said(answer).UTF8String, ticket.key.UTF8String ?: "no key");
                finished = YES;
            }];
        } else if ([verb isEqualToString:@"signout"]) {
            [jira signOut];
            printf("sign-in: %s\n", [states[jira.signInState] UTF8String]);
            finished = YES;
        } else if ([verb isEqualToString:@"state"]) {
            printf("sign-in: %s%s\n", [states[jira.signInState] UTF8String],
                   jira.signInWhy ? [[@" (" stringByAppendingFormat:@"%@)", jira.signInWhy] UTF8String] : "");
            printf("notices: %lu\n", (unsigned long)jira.notices.count);
            finished = YES;
        } else {
            fprintf(stderr, "Unknown step: %s\n", step.UTF8String);
            return 2;
        }
        WaitFor(&finished);
        if (!finished) printf("(no answer within a minute)\n");
        fflush(stdout);
    }
    return 0;
}
