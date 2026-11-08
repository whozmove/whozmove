// AnswerFor: the switches a session you allow answers for you with, the asks they let through, the checks every answer
// goes through before it's sent, and what each row says was answered for you.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "AnswerFor.h"
#import "Core.h"
#import "Rows.h"
#import "Row.h"
#import "Allowed.h"
#import "Notice.h"
#import "HookLine.h"
#import "Asks.h"
#import "Git.h"
#import "Files.h"
#import "Text.h"
#import "Log.h"
#import "PluginInstall.h"
#import "ClaudeSessions.h"
#import "ClaudeCodeFacts.h"
#import "Processes.h"
#import "Focus.h"
#import "Links.h"
#import "SwitchHolder.h"
#import <CommonCrypto/CommonDigest.h>

NSString *const kSendBackKey = @"sendBack";
NSString *const kAnswerQuestionsKey = @"answerQuestions";
NSString *const kApprovePlansKey = @"approvePlans";

// How long a request you've been answering is kept from a session you allow (a hold is renewed every 10s while you
// answer, and each second while you're in its tab), how long a row says what was answered for it, and the longest note.
static const double kHeldWithinMs = 60 * 1000, kShownForMs = 30 * 60 * 1000;
// How long after an approval its plan's result may take to show in the transcript before the row says it wasn't taken.
static const double kTakenWithinMs = 15 * 1000;
static const NSUInteger kLongestNote = 4000;

// A session as the answers name it: its name in the team, else its own, else its folder's.
static NSString *NameOf(Row *row) {
    NSString *name = AsText(row.team[@"name"]) ?: (row.name.length ? row.name : row.cwd.lastPathComponent);
    return Clip(name ?: @"a session", 40);
}

// How long whether a session's process might bypass permissions is kept before it's asked again: each row pass, menu
// and ask may want it, and its settings files are read for it.
static const NSTimeInterval kBypassCheckedFor = 1;

// A plan's title, as its card shows it: its first heading.
static NSString *PlanTitle(NSDictionary *request) {
    NSString *plan = AsText(AsRecord(request[@"input"])[@"plan"]) ?: @"";
    NSRegularExpression *heading = [NSRegularExpression regularExpressionWithPattern:@"^\\s*#+\\s*(.+)$"
                                                                             options:NSRegularExpressionAnchorsMatchLines
                                                                               error:nil];
    NSTextCheckingResult *found = [heading firstMatchInString:plan options:0 range:NSMakeRange(0, plan.length)];
    return found ? Clip([plan substringWithRange:[found rangeAtIndex:1]], 120) : @"Its plan";
}

// A request's questions (at most four, as its card shows them), each as it takes an answer: its text, its header, its
// kind (choice, text or number, by Claude Code's names), its options' labels and whether several may be picked, and a
// number's least and most.
static NSArray<NSDictionary *> *QuestionsOf(NSDictionary *request) {
    NSArray *questions = [AsRecord(request[@"input"])[@"questions"] isKindOfClass:NSArray.class]
        ? AsRecord(request[@"input"])[@"questions"] : @[];
    NSMutableArray *shown = [NSMutableArray array];
    for (id each in questions) {
        NSDictionary *q = AsRecord(each);
        NSString *text = AsText(q[@"question"]);
        if (!text || shown.count == 4) continue;
        NSString *kind = AsText(q[@"kind"]) ?: AsText(q[@"type"]) ?: @"choice";
        NSMutableDictionary *entry = [@{@"question": text, @"kind": kind} mutableCopy];
        if (AsText(q[@"header"])) entry[@"header"] = q[@"header"];
        if ([kind isEqual:@"choice"]) {
            NSMutableArray *labels = [NSMutableArray array];
            for (id option in [q[@"options"] isKindOfClass:NSArray.class] ? q[@"options"] : @[])
                if (AsText(AsRecord(option)[@"label"])) [labels addObject:AsRecord(option)[@"label"]];
            entry[@"options"] = labels;
            entry[@"multiSelect"] = @([q[@"multiSelect"] boolValue]);
            entry[@"answers"] = @"{option: label}, {options: [labels]} where several may be picked, or {written: text}";
        } else {
            if (AsNumber(q[@"min"])) entry[@"min"] = q[@"min"];
            if (AsNumber(q[@"max"])) entry[@"max"] = q[@"max"];
            entry[@"answers"] = @"{written: text}";
        }
        [shown addObject:entry];
    }
    return shown;
}

// One question's answer as the session gave it, checked against the question as its card would take it: the answer's
// words, or nil and why not.
static NSString *AnswerTo(NSDictionary *q, id given, NSString **why) {
    NSDictionary *answer = AsRecord(given);
    NSString *text = q[@"question"], *kind = q[@"kind"];
    NSArray *labels = q[@"options"] ?: @[];
    // Written words on one line, as the card's box takes them.
    NSString *written = [[AsText(answer[@"written"]) componentsSeparatedByCharactersInSet:
                          NSCharacterSet.newlineCharacterSet] componentsJoinedByString:@" "];
    written = [written stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (written.length) {
        if (written.length > 2000) {
            *why = [NSString stringWithFormat:@"the answer to “%@” is too long: 2000 characters at most", Clip(text, 80)];
            return nil;
        }
        if ([kind isEqual:@"number"]) {
            NSScanner *scan = [NSScanner scannerWithString:written];
            double n = 0;
            NSNumber *least = AsNumber(q[@"min"]), *most = AsNumber(q[@"max"]);
            if (![scan scanDouble:&n] || !scan.isAtEnd || !isfinite(n) || (least && n < least.doubleValue)
                || (most && n > most.doubleValue)) {
                *why = [NSString stringWithFormat:@"“%@” takes a number%@", Clip(text, 80),
                                                  least || most ? [NSString stringWithFormat:@" from %@ to %@",
                                                                  least ?: @"any", most ?: @"any"] : @""];
                return nil;
            }
            return [NSString stringWithFormat:@"%.15g", n];  // as the card sends a number: "5" for "05"
        }
        return written;
    }
    if (![kind isEqual:@"choice"]) {
        *why = [NSString stringWithFormat:@"“%@” takes a written answer: {written: text}", Clip(text, 80)];
        return nil;
    }
    // A pick named twice counts once, as a pick on the card is on or off.
    NSArray *picked = AsText(answer[@"option"]) ? @[answer[@"option"]]
        : [answer[@"options"] isKindOfClass:NSArray.class]
        ? [NSOrderedSet orderedSetWithArray:answer[@"options"]].array : nil;
    if (!picked.count) {
        *why = [NSString stringWithFormat:@"answer “%@” with {option: label}, or {written: text}", Clip(text, 80)];
        return nil;
    }
    if (picked.count > 1 && ![q[@"multiSelect"] boolValue]) {
        *why = [NSString stringWithFormat:@"“%@” takes one option", Clip(text, 80)];
        return nil;
    }
    for (id label in picked)
        if (![labels containsObject:label]) {
            *why = [NSString stringWithFormat:@"“%@” has no option “%@”", Clip(text, 80), Clip(AsText(label) ?: @"", 60)];
            return nil;
        }
    return [picked componentsJoinedByString:@", "];
}

// The digest a plan is approved by: the first 16 hex letters of the SHA-256 of its text, so a plan written again
// since the session allowed read it isn't approved in its place.
static NSString *PlanDigest(NSDictionary *request) {
    NSData *text = [(AsText(AsRecord(request[@"input"])[@"plan"]) ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(text.bytes, (CC_LONG)text.length, hash);
    NSMutableString *hex = [NSMutableString string];
    for (int i = 0; i < 8; i++) [hex appendFormat:@"%02x", hash[i]];
    return hex;
}

// Text sent base64-encoded, so no quoting in ask-panel.sh can break its line: nil for none, or text that isn't.
static NSString *Decoded(id value) {
    NSString *encoded = AsText(value);
    NSData *data = encoded ? [[NSData alloc] initWithBase64EncodedString:encoded options:0] : nil;
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}

static NSString *WhyGone(NSString *askId, BOOL listed);

static NSString *JSONLine(id object) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingSortedKeys error:nil];
    return json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"{}";
}

@interface AnswerFor ()
@property (weak) Core *core;
// By the session answered for: {by, what, title, note, at}, and for an approval its `state` (pending, approved or
// notTaken), the plans settled before it (`settledBefore`) and the one it settled on (`planId`). How many each switch
// has answered is kept with the switch (Allowed's count), written to ticked.json with it, and comes back with the one
// press that turns the switch back on after a restart.
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *answered;
// When this copy of Whozmove started, which makes each restart's notice a new one, even for switches that were waiting
// the last time too.
@property (assign) NSTimeInterval startedAt;
// Which session may hold the switches kept for its folder (SwitchHolder).
@property (strong) SwitchHolder *holder;
// Why each session's process might bypass permissions, or NSNull for none, as last checked: by its pid and start, with
// when (`bypassOf:`).
@property (strong) NSMutableDictionary<NSString *, NSArray *> *bypassChecked;
// Each new session that has held the switches kept for its folder, by its id and process, as its line says it
// (`handoverOf:`), kept a day while Whozmove runs.
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *handovers;
@end

@implementation AnswerFor

- (instancetype)initWithCore:(Core *)core program:(ClaudeProgram (^)(pid_t pid))programOf
                       mayBe:(BOOL (^)(NSString *name))mayBe {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.holder = [[SwitchHolder alloc] initWithCore:core program:programOf mayBe:mayBe
                                               named:^NSString *(Row *row) { return NameOf(row); }];
    self.answered = [NSMutableDictionary dictionary];
    self.bypassChecked = [NSMutableDictionary dictionary];
    self.handovers = [NSMutableDictionary dictionary];
    self.startedAt = NSDate.date.timeIntervalSince1970;
    return self;
}

#pragma mark The switches

// One of the switches, shown only on the row of the session leading the team (Group by Team's team file), as it's the
// one that answers for the team; it's kept for that session's folder while Whozmove runs, so a new session there holds
// it too, once it may (SwitchHolder). Its `whyNot` gives only the cause, as where it's said (the tick, the dash, Turn
// Back On) adds what to do next; a cause the panel can help with has a way past it (`wayTitleFor`). Its line counts
// what it has done (`done`: "sent back", "answered", "approved").
- (SessionSwitch *)switchWithKey:(NSString *)key title:(NSString *)title line:(NSString *)line done:(NSString *)done {
    __weak typeof(self) weakSelf = self;
    SessionSwitch *each = [SessionSwitch switchWithKey:key title:title line:line lasts:SwitchLastsWorkspace];
    each.shown = ^BOOL(Row *row) { return [row.team[@"role"] isEqual:@"lead"]; };
    each.hiddenSays = @"this session isn't the one leading the team in the team file (Group by Team), whose row "
                      @"offers it";
    each.workspace = ^NSString *(Row *row) { return KeptFolderOf(row); };
    // Any program can write Claude Code's registry to make itself a second copy of a session, which the row may follow:
    // so never while there's another; and the folder holds it only for one session there that may hold it.
    each.whyNot = ^NSString *(Row *row) {
        NSString *hold = [weakSelf.holder whyNot:row][@"why"];
        if (hold) return hold;
        // A session that might bypass permissions would approve with no one asked at all, so it never holds this.
        NSString *bypass = [key isEqual:kApprovePlansKey] ? [weakSelf bypassOf:row] : nil;
        return bypass ? [AtSentenceStart(bypass) stringByAppendingString:@": start it without that"] : nil;
    };
    // The way past a cause the panel can help with: to the other session that's in the way, or to Claude Code's own
    // build in place of an older one from npm.
    each.wayTitleFor = ^NSString *(Row *row) {
        NSDictionary *hold = [weakSelf.holder whyNot:row];
        if ([hold[@"kind"] isEqual:@"npm"]) return @"Get Claude Code";
        return hold[@"other"] ? @"Take Me There" : nil;
    };
    each.way = ^(Row *row) {
        NSDictionary *hold = [weakSelf.holder whyNot:row];
        if ([hold[@"kind"] isEqual:@"npm"]) {
            OpenInWebBrowser([NSURL URLWithString:kClaudeCodeInstallPage]);
            return;
        }
        Row *other = weakSelf.core.rows.byId[hold[@"other"] ?: @""];
        if (other) [weakSelf.core.focus open:@{@"sessionId": other.sessionId, @"pid": @(other.pid)}];
    };
    each.says = ^NSString *(Row *row) {
        NSString *folder = [weakSelf.core.allowed keptFolder:key for:row];
        NSString *kept = folder ? [NSString stringWithFormat:@"Stays on for %@ while Whozmove runs",
                                                             folder.lastPathComponent] : line;
        NSInteger count = [weakSelf.core.allowed count:key session:row.sessionId];
        return count ? [NSString stringWithFormat:@"%@ · %ld %@", kept, (long)count, done] : kept;
    };
    return each;
}

- (void)forgetHolds {
    [self.holder forget];
    [self.bypassChecked removeAllObjects];
}

// Why a session might bypass permissions, or nil once it's ruled out, kept with what the system said of its process
// (its settings files are read for it), so a row pass doesn't read them each second.
- (NSString *)bypassOf:(Row *)row {
    NSString *key = [NSString stringWithFormat:@"%d %lld", row.pid, ProcessStartedAt(row.pid)];
    NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
    NSArray *checked = self.bypassChecked[key];
    if (checked && now - [checked[0] doubleValue] < kBypassCheckedFor)
        return [checked[1] isKindOfClass:NSString.class] ? checked[1] : nil;
    NSString *bypass = self.bypassWhy ? self.bypassWhy(row, row.pid) : @"bypassing permissions can't be ruled out";
    if (self.bypassChecked.count > 64) [self.bypassChecked removeAllObjects];
    self.bypassChecked[key] = @[@(now), bypass ?: NSNull.null];
    return bypass;
}

- (NSArray<SessionSwitch *> *)switches {
    return @[[self switchWithKey:kSendBackKey title:@"May Send Back Plans"
                            line:@"It can send back a team member's plan in this project with a note, never approve one"
                            done:@"sent back"],
             [self switchWithKey:kAnswerQuestionsKey title:@"May Answer Questions"
                            line:@"It can answer a team member's questions in this project for you, never a request "
                                 @"for your OK"
                            done:@"answered"],
             [self switchWithKey:kApprovePlansKey title:@"May Approve Plans"
                            line:@"It can approve a team member's plan for you, which then starts building"
                            done:@"approved"]];
}

- (NSDictionary<NSString *, SessionAsk *> *)asks {
    __weak typeof(self) weakSelf = self;
    return @{
        @"waiting": [SessionAsk askNeedingAny:@[kSendBackKey, kAnswerQuestionsKey, kApprovePlansKey]
                                       answer:^NSString *(Row *row, pid_t process, NSDictionary *asked) {
            return [weakSelf waitingFor:row from:process];
        }],
        @"send-back": [SessionAsk askNeeding:kSendBackKey
                                      answer:^NSString *(Row *row, pid_t process, NSDictionary *asked) {
            return [weakSelf sendBack:asked from:row];
        }],
        @"answer": [SessionAsk askNeeding:kAnswerQuestionsKey
                                   answer:^NSString *(Row *row, pid_t process, NSDictionary *asked) {
            return [weakSelf answer:asked from:row];
        }],
        @"approve": [SessionAsk askNeeding:kApprovePlansKey
                                    answer:^NSString *(Row *row, pid_t process, NSDictionary *asked) {
            return [weakSelf approve:asked from:row];
        }],
    };
}

#pragma mark The notices

- (NSArray<Notice *> *)notices {
    NSMutableArray<Notice *> *notices = [NSMutableArray array];
    NSDictionary<NSString *, Row *> *byId = self.core.rows.byId;
    for (NSString *sessionId in [byId.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        Row *row = byId[sessionId];
        // Only this module's own switches: the notice speaks for them.
        NSMutableArray<SessionSwitch *> *waiting = [NSMutableArray array];
        for (SessionSwitch *each in [self.core.allowed waitingFor:row])
            if ([@[kSendBackKey, kAnswerQuestionsKey, kApprovePlansKey] containsObject:each.key])
                [waiting addObject:each];
        if (!waiting.count) continue;
        // True in each state, as the menu's item is: one press brings back those that can come back now (Allowed's
        // bringableFor:among:why:, the press's own checks, of this module's switches only), naming them when not all
        // can, and only when none can it says what to do first.
        NSString *reason = nil;
        NSArray<SessionSwitch *> *able = [self.core.allowed bringableFor:row among:waiting why:&reason];
        NSString *names = [Allowed namesOf:waiting];
        NSString *them = able.count && able.count < waiting.count ? [Allowed namesOf:able]
            : waiting.count == 1 ? @"it" : @"them";
        NSString *how = able.count ? @"one press at the foot of its mode menu brings %@ back"
            : [AfterColon(reason) stringByAppendingString:@", then one press at the foot of its mode menu brings %@ back"];
        NSString *text = [NSString stringWithFormat:@"Whozmove restarted, so %@ went off for %@ in %@: %@.", names,
                          NameOf(row), KeptFolderOf(row).lastPathComponent ?: @"its folder",
                          [NSString stringWithFormat:how, them]];
        Notice *notice = [Notice noticeWithKey:[@"switches-wait-" stringByAppendingString:sessionId]
                                         level:NoticeSoon text:text];
        notice.title = @"Switches Went Off";
        notice.since = [NSString stringWithFormat:@"%@ %.0f", names, self.startedAt];
        notice.closes = YES;
        [notices addObject:notice];
    }
    [notices addObjectsFromArray:[self heldNotices:byId]];
    return notices;
}

// How long a handover is remembered for its line: a day, more than the line is put away for.
static const NSTimeInterval kHandoverKept = 24 * 3600;

// A new session holding the switches kept for its folder, first seen now, as the line under the header and panel.log
// tell it: its terminal app and when its process started, which are the system's, never what the team file or the
// session says. {session, pid, names, folder, app, started, at}.
- (NSDictionary *)handoverOf:(Row *)row held:(NSArray<SessionSwitch *> *)held folder:(NSString *)folder {
    NSString *app = OwningApp(row.pid).localizedName;
    NSDate *began = [NSDate dateWithTimeIntervalSince1970:ProcessStartedAt(row.pid) / 1e6];
    NSString *started = [NSDateFormatter localizedStringFromDate:began dateStyle:NSDateFormatterNoStyle
                                                       timeStyle:NSDateFormatterShortStyle];
    NSMutableDictionary *handover = [@{@"session": row.sessionId, @"pid": @(row.pid), @"names": [Allowed namesOf:held],
                                       @"folder": folder.lastPathComponent ?: @"", @"started": started,
                                       @"at": @(NSDate.timeIntervalSinceReferenceDate)} mutableCopy];
    if (app.length) handover[@"app"] = app;
    PanelLog(@"%@ -> %@ came on for a new session (%@, started %@), kept for %@", row.sessionId, handover[@"names"],
             app ?: @"no app", started, handover[@"folder"]);
    return handover;
}

// One notice for each session and process that has held the switches kept for its folder, other than the one they
// were ticked in, or brought back on: what files say decides which session in the folder holds them, so you're told
// each time it's a new one, a cleared conversation too. It stays until you close it, even once that session has gone,
// so one that held them for a moment isn't missed.
- (NSArray<Notice *> *)heldNotices:(NSDictionary<NSString *, Row *> *)byId {
    for (NSString *sessionId in byId) {
        Row *row = byId[sessionId];
        NSString *process = [NSString stringWithFormat:@"%@ %d", sessionId, row.pid];
        if (self.handovers[process]) continue;
        NSMutableArray<SessionSwitch *> *held = [NSMutableArray array];
        NSString *folder = nil;
        for (NSString *key in @[kSendBackKey, kAnswerQuestionsKey, kApprovePlansKey]) {
            NSDictionary *ticked = [self.core.allowed tickedIn:key for:row];
            if (!ticked || ![self.core.allowed isOn:key for:row]) continue;
            if ([ticked[@"session"] isEqual:sessionId] && [ticked[@"pid"] intValue] == row.pid) continue;
            [held addObject:[self.core.allowed switchWithKey:key]];
            folder = [self.core.allowed keptFolder:key for:row];
        }
        if (held.count) self.handovers[process] = [self handoverOf:row held:held folder:folder];
    }
    NSMutableArray<Notice *> *notices = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
    for (NSString *process in [self.handovers.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSDictionary *handover = self.handovers[process];
        if (now - [handover[@"at"] doubleValue] > kHandoverKept) {
            [self.handovers removeObjectForKey:process];
            continue;
        }
        NSString *where = handover[@"app"] ? [NSString stringWithFormat:@" in %@", handover[@"app"]] : @"";
        NSString *text = [NSString stringWithFormat:@"%@ came on for a new session%@, started at %@: kept for %@ while "
                                                    @"Whozmove runs.", handover[@"names"], where, handover[@"started"],
                                                    handover[@"folder"]];
        Notice *notice = [Notice noticeWithKey:[@"switches-held-" stringByAppendingString:process]
                                         level:NoticeGoodToKnow text:text];
        notice.title = @"Switches Came On";
        notice.since = process;
        notice.closes = YES;
        notice.session = handover[@"session"];
        // Only while that session still runs: one that has gone has nothing to be taken to.
        if (ProcessAlive([handover[@"pid"] intValue])) {
            notice.button = @"Take Me There";
            notice.press = ^{
                [weakSelf.core.focus open:@{@"sessionId": handover[@"session"], @"pid": handover[@"pid"]}];
            };
        }
        [notices addObject:notice];
    }
    return notices;
}

#pragma mark The checks

// Why a session may not answer a request for you, or nil when it may: the request's session must be another of the
// team's members, in the same project, and you mustn't be answering it yourself just now.
- (NSString *)whyNot:(Row *)asker answer:(NSDictionary *)request {
    NSString *askId = AsText(request[@"id"]);
    Row *target = self.core.rows.byId[AsText(request[@"sessionId"]) ?: @""];
    if (!target) return @"its session isn't listed";
    if ([target.sessionId isEqual:asker.sessionId]) return @"it's this session's own";
    NSString *role = AsText(target.team[@"role"]);
    if (![role isEqual:@"member"])
        return [NSString stringWithFormat:@"only the team's sessions can be answered for the user, as the team file "
                                          @"names them, and %@ isn't one: the user answers it", NameOf(target)];
    // Compared as real paths: git's own files may name a folder by another path to it (/tmp for /private/tmp).
    NSString *project = ProjectRoot(asker.cwd), *theirs = ProjectRoot(target.cwd);
    if (!project)
        return @"it answers for the user only within a project kept in git, and this session's folder isn't in one";
    if (!theirs || ![RealPath(project) isEqual:RealPath(theirs)])
        return [NSString stringWithFormat:@"%@ is in another project, %@", NameOf(target),
                                          theirs.lastPathComponent ?: target.cwd.lastPathComponent ?: @"outside any"];
    double held = [[HookLine shared] heldAt:askId], now = NSDate.date.timeIntervalSince1970 * 1000;
    if (held && now - held < kHeldWithinMs) return @"the user is answering it: leave it to them";
    return nil;
}

// The request an ask names by its id, still waiting on its line, or nil and why not.
- (NSDictionary *)request:(NSDictionary *)asked why:(NSString **)why {
    NSString *askId = AskId(asked[@"id"]);
    if (!askId) {
        *why = @"name a request by the id ask-panel.sh waiting lists";
        return nil;
    }
    NSDictionary *request = [HookLine shared].requests[askId];
    if (request && [[HookLine shared] stillAsking:askId]) return request;
    *why = WhyGone(askId, request != nil);
    return nil;
}

// Why a request no longer waits on its line, in plain words; `listed`: it's still on the line, answered already.
static NSString *WhyGone(NSString *askId, BOOL listed) {
    NSString *gone = [[HookLine shared] whyGone:askId];
    return [gone isEqual:@"waitedOut"]
        ? @"it has waited over an hour: only the user can answer it now, in its session's tab"
        : [gone isEqual:@"letGo"] ? @"its session isn't taking answers now (paused, say): only the user can answer it, "
                                    @"in its session's tab"
        : listed || [gone isEqual:@"answered"] ? @"it has been answered already"
        : gone ? @"it has gone: answered in its session's tab, or Claude stopped asking"
        : @"there's no request with that id waiting";
}

#pragma mark The asks

// What's waiting that this session may answer, as one line of JSON, for the switches it has on: each plan's id,
// session, name, title, file and text, with what it may do with it (`may`: send-back, approve) and, with May Approve
// Plans, its digest, or why it can't be approved (`approveWhyNot`); each question's with its questions as they take an
// answer (May Answer Questions); listed apart, those from sessions started before Whozmove's update, which only the user
// can answer, in their tab; and approvals Claude Code didn't take (`approvalNotTaken`).
- (NSString *)waitingFor:(Row *)asker from:(pid_t)process {
    BOOL sendBack = ![self.core.allowed whyOff:kSendBackKey for:asker from:process];
    BOOL approve = ![self.core.allowed whyOff:kApprovePlansKey for:asker from:process];
    BOOL plans = sendBack || approve;
    BOOL questions = ![self.core.allowed whyOff:kAnswerQuestionsKey for:asker from:process];
    NSMutableArray *listed = [NSMutableArray array], *onlyTheUser = [NSMutableArray array];
    for (NSDictionary *request in [HookLine shared].requests.allValues) {
        if (![[HookLine shared] stillAsking:AsText(request[@"id"]) ?: @""]) continue;
        BOOL plan = [request[@"tool"] isEqual:@"ExitPlanMode"], question = [request[@"tool"] isEqual:@"AskUserQuestion"];
        if (!(plan && plans) && !(question && questions)) continue;
        NSString *why = [self whyNot:asker answer:request];
        if (why && ![why hasPrefix:@"the user is answering"]) continue;
        Row *target = self.core.rows.byId[request[@"sessionId"]];
        NSMutableDictionary *entry = [@{@"id": request[@"id"], @"kind": plan ? @"plan" : @"question",
                                        @"sessionId": target.sessionId, @"name": NameOf(target)} mutableCopy];
        if (plan) {
            entry[@"title"] = PlanTitle(request);
            NSString *file = AsText(AsRecord(request[@"input"])[@"planFilePath"]);
            if (file) entry[@"file"] = file;
            entry[@"text"] = AsText(AsRecord(request[@"input"])[@"plan"]) ?: @"";
            NSMutableArray *may = [NSMutableArray array];
            if (sendBack) [may addObject:@"send-back"];
            if (approve) {
                NSString *whyNot = [self whyNotApprove:target request:request];
                if (whyNot) entry[@"approveWhyNot"] = whyNot;
                else [may addObject:@"approve"];
                entry[@"digest"] = PlanDigest(request);
            }
            entry[@"may"] = may;
        } else {
            entry[@"questions"] = QuestionsOf(request);
        }
        if (why) entry[@"held"] = @YES;
        [listed addObject:entry];
    }
    [PendingAsks() enumerateKeysAndObjectsUsingBlock:^(NSString *sessionId, NSDictionary *ask, BOOL *stop) {
        if (![ask[@"legacy"] boolValue]) return;
        Row *target = self.core.rows.byId[sessionId];
        NSString *role = AsText(target.team[@"role"]);
        if (target && [role isEqual:@"member"])
            [onlyTheUser addObject:@{@"sessionId": sessionId, @"name": NameOf(target), @"tool": ask[@"tool"] ?: @""}];
    }];
    // Approvals Claude Code didn't take, so the session allowed tells the user.
    NSMutableArray *notTaken = [NSMutableArray array];
    for (NSString *sessionId in self.answered) {
        NSDictionary *answered = self.answered[sessionId];
        if ([answered[@"what"] isEqual:@"approved"] && [answered[@"state"] isEqual:@"notTaken"])
            [notTaken addObject:@{@"sessionId": sessionId, @"name": NameOf(self.core.rows.byId[sessionId]),
                                  @"title": answered[@"title"] ?: @""}];
    }
    NSSortDescriptor *byName = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES];
    NSMutableDictionary *said = [@{@"waiting": [listed sortedArrayUsingDescriptors:@[byName]],
                                   @"onlyTheUser": [onlyTheUser sortedArrayUsingDescriptors:@[byName]]} mutableCopy];
    if (notTaken.count) said[@"approvalNotTaken"] = [notTaken sortedArrayUsingDescriptors:@[byName]];
    return JSONLine(said);
}

// A plan sent back with a note, marked as this session's, as your "keep planning" answer would send it: never "stop",
// never an approval. The note is needed: Claude rewrites the plan by it.
- (NSString *)sendBack:(NSDictionary *)asked from:(Row *)asker {
    NSString *why = nil;
    NSDictionary *request = [self request:asked why:&why];
    if (!request) return [@"refused: " stringByAppendingString:why];
    if (![request[@"tool"] isEqual:@"ExitPlanMode"])
        return @"refused: it isn't a plan: May Send Back Plans sends back only plans";
    if ((why = [self whyNot:asker answer:request])) return [@"refused: " stringByAppendingString:why];
    NSString *note = [Decoded(asked[@"note64"]) stringByTrimmingCharactersInSet:
                      NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!note.length) return @"refused: say what should change, in a note: a plan is sent back with one";
    if (note.length > kLongestNote)
        return [NSString stringWithFormat:@"refused: a note may be %lu characters at most",
                                          (unsigned long)kLongestNote];
    NSString *by = NameOf(asker);
    NSString *marked = [NSString stringWithFormat:@"(Sent back by “%@”, a session the user lets send plans back for "
                                                  @"them.) %@", by, note];
    NSString *askId = AsText(request[@"id"]);
    if (!SendAnswer(askId, AskReply(@{@"allow": @NO, @"message": marked})))
        return [@"refused: " stringByAppendingString:WhyGone(askId, [HookLine shared].requests[askId] != nil)];
    Row *target = self.core.rows.byId[request[@"sessionId"]];
    NSString *title = PlanTitle(request);
    self.answered[target.sessionId] = @{@"by": by, @"what": @"sentBack", @"title": title, @"note": OneLine(note, 300),
                                        @"at": @(floor(NSDate.date.timeIntervalSince1970 * 1000))};
    [self.core.allowed countUp:kSendBackKey session:asker.sessionId];
    target.answeredFor = self.answered[target.sessionId];
    PanelLog(@"%@ sent back %@'s plan %@", asker.sessionId, target.sessionId, askId);
    return [NSString stringWithFormat:@"sent back: %@'s plan “%@”, with your note", NameOf(target), title];
}

// A question answered, every question it asks, each checked against it, marked as this session's choice for you and
// as no OK of yours for anything that needs your permission; sent as your own answers on its card would be.
- (NSString *)answer:(NSDictionary *)asked from:(Row *)asker {
    NSString *why = nil;
    NSDictionary *request = [self request:asked why:&why];
    if (!request) return [@"refused: " stringByAppendingString:why];
    if (![request[@"tool"] isEqual:@"AskUserQuestion"])
        return @"refused: it isn't a question: May Answer Questions answers only questions";
    if ((why = [self whyNot:asker answer:request])) return [@"refused: " stringByAppendingString:why];
    NSData *json = [Decoded(asked[@"answers64"]) dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *given = json ? AsRecord([NSJSONSerialization JSONObjectWithData:json options:0 error:nil]) : nil;
    if (!given.count) return @"refused: give the answers on stdin, as JSON: {question: {option: label}}";
    NSArray<NSDictionary *> *questions = QuestionsOf(request);
    NSMutableSet *asks = [NSMutableSet set];
    for (NSDictionary *q in questions) [asks addObject:q[@"question"]];
    for (NSString *text in given)
        if (![asks containsObject:text])
            return [NSString stringWithFormat:@"refused: “%@” isn't one of its questions", Clip(text, 80)];
    NSString *by = NameOf(asker);
    NSString *mark = [NSString stringWithFormat:@" (chosen for the user by “%@”; not the user's OK for anything that "
                                                @"needs their permission)", by];
    NSMutableDictionary *answers = [NSMutableDictionary dictionary];
    NSMutableArray *said = [NSMutableArray array];
    for (NSDictionary *q in questions) {
        if (!given[q[@"question"]])
            return [NSString stringWithFormat:@"refused: answer every question: “%@” has none", Clip(q[@"question"], 80)];
        NSString *answer = AnswerTo(q, given[q[@"question"]], &why);
        if (!answer) return [@"refused: " stringByAppendingString:why];
        answers[q[@"question"]] = [answer stringByAppendingString:mark];
        [said addObject:[NSString stringWithFormat:@"%@ “%@”", Clip(q[@"question"], 80), Clip(answer, 80)]];
    }
    NSString *askId = AsText(request[@"id"]);
    if (!SendAnswer(askId, AskReply(@{@"allow": @YES, @"answers": answers})))
        return [@"refused: " stringByAppendingString:WhyGone(askId, [HookLine shared].requests[askId] != nil)];
    Row *target = self.core.rows.byId[request[@"sessionId"]];
    self.answered[target.sessionId] = @{@"by": by, @"what": @"answered", @"title": questions.firstObject[@"question"],
                                        @"note": OneLine([said componentsJoinedByString:@" · "], 300),
                                        @"at": @(floor(NSDate.date.timeIntervalSince1970 * 1000))};
    [self.core.allowed countUp:kAnswerQuestionsKey session:asker.sessionId];
    target.answeredFor = self.answered[target.sessionId];
    PanelLog(@"%@ answered %@'s question %@", asker.sessionId, target.sessionId, askId);
    return [NSString stringWithFormat:@"answered: %@'s %@", NameOf(target),
                                      questions.count > 1 ? @"questions" : @"question"];
}

// Why a member's plan can't be approved from here, though it may be sent back, or nil when it can: its hooks must take
// an approval (sessions started after Whozmove's update), and its mode menu mustn't reach bypassed permissions, as an
// approved plan goes back to the mode it was planned from.
- (NSString *)whyNotApprove:(Row *)target request:(NSDictionary *)request {
    // The copy of the conversation whose hook asked, which may not be the one the row follows.
    pid_t session = 0;
    if (![SessionAbove(AsNumber(request[@"pid"]).intValue, &session) isEqual:target.sessionId] || session <= 0)
        return @"its session's process can't be found, so it can't be approved from here: only the user can, in its tab";
    if (!SessionHasHookPart(session, HookPartApprovePlan, !self.core.printing))
        return @"its session started before Whozmove's update: only the user can approve it, in its tab";
    NSString *bypass = self.bypassWhy ? self.bypassWhy(target, session) : @"bypassing permissions can't be ruled out";
    if (bypass) return [bypass stringByAppendingString:@": only the user can approve its plans, in its tab"];
    return nil;
}

// A plan approved, as Claude's own prompt approves it: down its line, an allow the hook passes on with an empty input,
// marked `approvePlan`, which only this adds (never the page's answers, AskReply). Only the plan read: by its digest.
- (NSString *)approve:(NSDictionary *)asked from:(Row *)asker {
    NSString *why = nil;
    NSDictionary *request = [self request:asked why:&why];
    if (!request) return [@"refused: " stringByAppendingString:why];
    if (![request[@"tool"] isEqual:@"ExitPlanMode"])
        return @"refused: it isn't a plan: May Approve Plans approves only plans";
    if ((why = [self whyNot:asker answer:request])) return [@"refused: " stringByAppendingString:why];
    Row *target = self.core.rows.byId[request[@"sessionId"]];
    if ((why = [self whyNotApprove:target request:request])) return [@"refused: " stringByAppendingString:why];
    NSString *digest = AsText(asked[@"digest"]);
    if (!digest.length) return @"refused: name the plan's digest too, as ask-panel.sh waiting lists it with its text";
    if (![digest isEqual:PlanDigest(request)])
        return @"refused: that digest isn't this plan's: read the plan's text in ask-panel.sh waiting, and use its digest";
    // The plan Claude asked about is the one its file holds still: one edited since isn't approved for what was read.
    NSDictionary *input = AsRecord(request[@"input"]);
    NSString *file = AsText(input[@"planFilePath"]);
    if (file) {
        NSString *now = [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil];
        if (![now isEqual:AsText(input[@"plan"])])
            return @"refused: its plan file has changed since Claude asked: only the user can approve it now, in its tab";
    }
    NSMutableDictionary *reply = [AskReply(@{@"allow": @YES}) mutableCopy];
    reply[@"approvePlan"] = @YES;
    NSString *askId = AsText(request[@"id"]);
    if (!SendAnswer(askId, reply))
        return [@"refused: " stringByAppendingString:WhyGone(askId, [HookLine shared].requests[askId] != nil)];
    NSString *by = NameOf(asker), *title = PlanTitle(request);
    NSMutableArray *settledBefore = [NSMutableArray array];
    for (NSDictionary *writing in target.writings)
        if ([writing[@"kind"] isEqual:@"plan"] && ![writing[@"status"] isEqual:@"waiting"] && writing[@"id"])
            [settledBefore addObject:writing[@"id"]];
    self.answered[target.sessionId] = @{@"by": by, @"what": @"approved", @"title": title, @"state": @"pending",
                                        @"settledBefore": settledBefore,
                                        @"at": @(floor(NSDate.date.timeIntervalSince1970 * 1000))};
    [self.core.allowed countUp:kApprovePlansKey session:asker.sessionId];
    target.answeredFor = self.answered[target.sessionId];
    PanelLog(@"%@ approved %@'s plan %@", asker.sessionId, target.sessionId, askId);
    return [NSString stringWithFormat:@"approved: %@'s plan “%@”; once Claude Code has taken it, its row says so, and "
                                      @"ask-panel.sh waiting lists one it didn't", NameOf(target), title];
}

#pragma mark The rows

// What was answered for a session shows on its row for 30 minutes, or until it asks something newer.
- (void)markRows:(NSArray<Row *> *)rows {
    double now = NSDate.date.timeIntervalSince1970 * 1000;
    // What was answered for a session no longer listed goes too, once it's as old as a row would show it.
    for (NSString *sessionId in self.answered.allKeys)
        if (now - AsNumber(self.answered[sessionId][@"at"]).doubleValue > kShownForMs)
            [self.answered removeObjectForKey:sessionId];
    for (Row *row in rows) {
        NSDictionary *answered = row.sessionId ? self.answered[row.sessionId] : nil;
        double at = AsNumber(answered[@"at"]).doubleValue;
        BOOL pending = [answered[@"what"] isEqual:@"approved"] && [answered[@"state"] isEqual:@"pending"];
        if (answered && (now - at > kShownForMs || (!pending && AsNumber(row.ask[@"at"]).doubleValue > at))) {
            [self.answered removeObjectForKey:row.sessionId];
            answered = nil;
        }
        // An approval counts as taken only once the plan's result in its transcript says so; one that hasn't in a few
        // seconds wasn't, and its plan still waits on Claude's own prompt.
        if ([answered[@"what"] isEqual:@"approved"] && ![answered[@"state"] isEqual:@"approved"]) {
            // A plan approved since: one that wasn't settled when the approval went. One that isn't taken is looked
            // for still, as a slow read of the transcript, or the user's own approval in its tab, may yet show it.
            NSString *state = nil, *planId = nil;
            NSArray *before = answered[@"settledBefore"] ?: @[];
            for (NSDictionary *writing in row.writings)
                if ([writing[@"kind"] isEqual:@"plan"] && [writing[@"status"] isEqual:@"approved"]
                    && ![before containsObject:writing[@"id"] ?: @""]) {
                    state = @"approved";
                    planId = writing[@"id"];
                    break;
                }
            if (!state && [answered[@"state"] isEqual:@"pending"] && now - at > kTakenWithinMs) state = @"notTaken";
            if (state) {
                NSMutableDictionary *settled = [answered mutableCopy];
                settled[@"state"] = state;
                if (planId) settled[@"planId"] = planId;
                self.answered[row.sessionId] = answered = settled;
                PanelLog(@"%@'s plan approved for the user: %@", row.sessionId,
                         [state isEqual:@"approved"] ? @"taken" : @"not taken");
            }
        }
        row.answeredFor = answered;
    }
}

@end
