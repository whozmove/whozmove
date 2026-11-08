// Send: words into a session, through its host and its agent; and why they can't go in now.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import "Send.h"
#import "Core.h"
#import "Rows.h"
#import "Page.h"
#import "Row.h"
#import "Reason.h"
#import "Log.h"
#import "Files.h"
#import "Text.h"

NSString *const kStillChanging = @"A change from the panel is still going in: finish that first";

// Why no words can be typed into the session's tab: it has ended, there's no terminal the panel can type into, it's
// paused in its terminal, a change from the panel is still going in, its tab isn't found (the terminal's reason, when it knows one), another tab fits as well, or
// the terminal has a reason of its own. A paused session (Ctrl+Z) has left its terminal's foreground, where a terminal
// that finds a session by its terminal device (iTerm2) finds no tab for it, so the pause is said first. `here` and
// `there` end the sentences ("can be changed here", "change it there").
NSString *WhyNoTab(id<Reach> reach, NSString *here, NSString *there) {
    if (reach.ended) return @"It isn't running: press its row to open it again";
    if (!reach.terminal)
        return [NSString stringWithFormat:@"Only sessions running in %@ can be %@", reach.terminals, here];
    if (reach.whyNotType && reach.whyNotType.kind == ReasonPaused) return reach.whyNotType.onCard;
    if (reach.changing) return kStillChanging;
    if (!reach.hasTab)
        return reach.tabWhyNot ?: [NSString stringWithFormat:@"Couldn't find this session's %@ tab", reach.terminal];
    if (reach.openTwice) return [Reason kind:ReasonOpenTwice].onCard;
    if (!reach.unique) return [NSString stringWithFormat:@"Another tab in this folder looks the same: %@", there];
    if (reach.tabWhyNot) return [NSString stringWithFormat:@"%@: %@", reach.tabWhyNot, there];
    return nil;
}

NSString *WayPast(id<Reach> reach, NSString *why) {
    NSString *own = why ? reach.tabWhyNot : nil;
    return own && [why hasPrefix:own] ? reach.wayPast : nil;
}

Reason *WhyTerminalRefuses(id<TypingHost> terminal, NSString *tab) {
    NSString *why = [terminal respondsToSelector:@selector(whyNotTypeIn:)] ? [terminal whyNotTypeIn:tab] : nil;
    return why ? [Reason terminal:why] : nil;
}

// While it works, the command would go in as a message; while it waits, Claude is asking something in that
// conversation. With no agent to say, nothing goes in.
Reason *WhyNotSendTo(id<AgentPrompt> agent, Row *row) {
    if (!agent) return [Reason kind:ReasonSessionGone];
    return row.pid > 0 ? [agent whyNotTypeInto:row.sessionId pid:row.pid] : nil;
}

NSString *WhyNoWords(id<Reach> reach, NSString *here, NSString *there) {
    if (!reach.started) return @"Send this conversation's first message first";
    if (reach.desktop) {
        if (reach.changing) return kStillChanging;
        return !reach.mayControl ? @"Whozmove needs the Accessibility permission for this" : reach.whyNotType.onButton;
    }
    return WhyNoTab(reach, here, there) ?: reach.whyNotType.onButton;
}

BOOL WordsRunACommand(NSString *words) {
    return words.length && [@"/!#&" rangeOfString:[words substringToIndex:1]].location != NSNotFound;
}

NSString *WhyNoAsk(id<Reach> reach) {
    return WhyNoWords(reach, @"asked from here", @"ask there");
}

BOOL WordsGoByThemselves(BOOL focused, BOOL desktop, NSString *hostApp, NSString *frontApp) {
    return !focused && !desktop && hostApp.length && ![hostApp isEqualToString:frontApp];
}

BOOL ReachGoesByItself(SessionReach *reach, BOOL focused, NSString *frontApp) {
    return WordsGoByThemselves(focused, reach.desktop, reach.typing.appId, frontApp);
}

NSString *ReachTerminalInFront(SessionReach *reach, NSString *frontApp) {
    NSString *app = reach.typing.appId;
    return app.length && [app isEqualToString:frontApp] ? reach.terminal : nil;
}

NSString *HeldWordsStep(BOOL works, BOOL first, BOOL pressed, BOOL byThemselves, BOOL changing, BOOL *stillPressed) {
    NSString *step = works ? @"turnEnd" : !first ? @"later" : pressed ? @"type" : !byThemselves ? @"press"
                   : changing ? @"later" : @"type";
    if (stillPressed) *stillPressed = pressed && [step isEqual:@"type"];
    return step;
}

// How long words typed in have to show in the session's own record before they count as not taken; and how long
// after its hook took them, once its turn has ended, words handed in have to show there.
static const double kTakenWithinMs = 5000, kReadWithinMs = 8000;

static double NowMs(void) {
    return NSDate.date.timeIntervalSince1970 * 1000;
}

// Whether a session is at work: asking you something counts, as it's in the middle of its turn.
static BOOL Works(Row *row) {
    return [row.status isEqual:@"busy"] || [row.status isEqual:@"waiting"] || row.ask;
}

// Words a session's own record shows it took, since `since`: the line they were typed as, as its hook keeps a prompt
// (on one line, its spaces run together, cut with "…").
static BOOL TookWords(Row *row, NSString *line, double since) {
    NSString *(^squeeze)(NSString *) = ^NSString *(NSString *text) {
        NSArray *words = [text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        return [[words filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]]
                componentsJoinedByString:@" "];
    };
    NSString *prompt = row.lastPrompt ?: @"";
    if (row.lastPromptAt.doubleValue < since - 2000) return NO;
    if ([prompt hasSuffix:@"…"]) prompt = [prompt substringToIndex:prompt.length - 1];
    NSString *took = squeeze(prompt);
    return took.length && [squeeze(line) hasPrefix:took];
}

// Words held for a session (sayBetweenSteps:): what they are, as they'd go in, how far they've got, what was last said
// of that, and whether your press sends them (Send, or Send Now).
@interface HeldWords : NSObject
@property (copy) NSString *wordsId, *sessionId, *line, *state, *told;
@property (copy) void (^progress)(NSDictionary *change);
@property (assign) double typedAt, handedAt;
// `withAgent`: held by its agent for its hook; `asking`: how far they've got is being asked of it now.
@property (assign) BOOL pressed, withAgent, asking;
@end

@implementation HeldWords
@end

@implementation SessionReach {
    Row *_row;
    __weak Send *_send;
    NSNumber *_started, *_mayControl;
    BOOL _lookedForTerminal, _lookedForTab, _unique, _askedTabWhyNot, _askedWayPast, _askedWhyNot;
    id<TypingHost> _typing;
    NSString *_tab, *_tabWhyNot, *_wayPast;
    Reason *_whyNotType;
}

- (instancetype)initWithRow:(Row *)row send:(Send *)send {
    if (!(self = [super init])) return nil;
    _row = row;
    _send = send;
    _conversations = [send conversationHostOf:row];
    return self;
}

- (BOOL)desktop {
    return self.conversations != nil;
}

- (BOOL)mayControl {
    if (!_mayControl) _mayControl = @([self.conversations mayControl]);
    return _mayControl.boolValue;
}

- (BOOL)started {
    if (!_started) _started = @([[_send agentOf:_row] hasStarted:_row.sessionId]);
    return _started.boolValue;
}

- (BOOL)ended {
    return [_send hasEnded:_row];
}

- (BOOL)openElsewhere {
    for (NSDictionary *copy in _row.alsoOpen)
        if (![copy[@"paused"] boolValue]) return YES;
    return NO;
}

// A copy that no app keeps as a conversation of its own runs in a terminal.
- (BOOL)openTwice {
    if (self.desktop) return NO;
    for (NSDictionary *copy in _row.alsoOpen)
        if (![copy[@"paused"] boolValue] && ![_send conversationHostOf:[[Row alloc] initWithFields:copy]]) return YES;
    return NO;
}

- (id<TypingHost>)typing {
    if (!_lookedForTerminal) {
        _lookedForTerminal = YES;
        _typing = self.desktop ? nil : [_send terminalOf:_row];
    }
    return _typing;
}

- (NSString *)terminal {
    return self.typing.name;
}

- (NSString *)terminals {
    return _send.terminalNames;
}

- (NSString *)tab {
    if (!_lookedForTab) {
        _lookedForTab = YES;
        BOOL unique = NO;
        _tab = [self.typing tabFor:_row unique:&unique];
        _unique = unique;
    }
    return _tab;
}

- (BOOL)hasTab {
    return self.tab != nil;
}

- (BOOL)unique {
    [self tab];
    return _unique;
}

// Asked once the tab has been looked for, of the tab found or of none.
- (NSString *)tabWhyNot {
    if (!_askedTabWhyNot) {
        _askedTabWhyNot = YES;
        _tabWhyNot = WhyTerminalRefuses(self.typing, self.tab).onCard;
    }
    return _tabWhyNot;
}

- (NSString *)wayPast {
    if (!_askedWayPast) {
        _askedWayPast = YES;
        id<TypingHost> typing = self.typing;
        NSString *tab = self.tab;
        _wayPast = tab && [typing respondsToSelector:@selector(wayPastIn:)] ? [typing wayPastIn:tab] : nil;
    }
    return _wayPast;
}

- (BOOL)changing {
    return _row.goingIn.count > 0 || _row.switchAsk.count > 0 || [_send typingInto:_row.sessionId];
}

// A Claude Desktop conversation by WhyNotSendTo, a terminal session by its agent; with no agent to say, never.
- (Reason *)whyNotType {
    if (!_askedWhyNot) {
        _askedWhyNot = YES;
        id<AgentPrompt> agent = [_send agentOf:_row];
        _whyNotType = self.desktop ? WhyNotSendTo(agent, _row)
                    : agent ? [agent whyNotTypeInto:_row.sessionId pid:_row.pid] : [Reason kind:ReasonSessionGone];
    }
    return _whyNotType;
}

@end

@interface Send ()
@property (weak) Core *core;
// The sessions words or a command of the agent's are going into now (ask:, run:), from the first key until the filler
// is out, so nothing else from the panel types into them meanwhile.
@property (strong) NSMutableSet<NSString *> *typing;
// Words held for sessions, in the order sent (sayBetweenSteps:), looked at again every second while there are any.
@property (strong) NSMutableArray<HeldWords *> *held;
@property (strong) NSTimer *heldTimer;
@end

@implementation Send

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.typing = [NSMutableSet set];
    self.held = [NSMutableArray array];
    return self;
}

- (BOOL)typingInto:(NSString *)sessionId {
    return sessionId && [self.typing containsObject:sessionId];
}

- (SessionReach *)reachOf:(Row *)row {
    return [[SessionReach alloc] initWithRow:row send:self];
}

- (id<AgentPrompt>)agentOf:(Row *)row {
    id agent = [self.core agentOf:row];
    return [agent conformsToProtocol:@protocol(AgentPrompt)] ? agent : nil;
}

// The terminal a session runs in, if it's one the panel can type into.
- (id<TypingHost>)terminalOf:(Row *)row {
    id host = [self.core hostOf:row];
    return [host conformsToProtocol:@protocol(TypingHost)] ? host : nil;
}

- (BOOL)hasEnded:(Row *)row {
    return [self.core hasEnded:row];
}

// The app that keeps a session as a conversation of its own (Claude Desktop), or nil.
- (id<ConversationHost>)conversationHostOf:(Row *)row {
    id host = [self.core hostHolding:row];
    return [host conformsToProtocol:@protocol(ConversationHost)] ? host : nil;
}

// The terminals the panel can type into, by name ("Ghostty or iTerm2").
- (NSString *)terminalNames {
    return [[[self.core hostsThat:@protocol(TypingHost)] valueForKey:@"name"] componentsJoinedByString:@" or "];
}

// Words go in as a message typed once and sent, on one line, with nothing in them that would act in a terminal or hide
// what they say (control, invisible and turning characters), only while the session is idle: typed into its terminal
// tab keeping your draft, each key only while it's still safe, or written in its Claude Desktop conversation's message
// box. Only how it went is logged, never the words, which may be anyone's.
- (void)say:(NSString *)words row:(Row *)row here:(NSString *)here there:(NSString *)there
       done:(void (^)(NSString *why, NSString *way))done {
    [self say:words row:row reach:row ? [self reachOf:row] : nil here:here there:there done:done];
}

- (void)say:(NSString *)words row:(Row *)row reach:(SessionReach *)reach here:(NSString *)here there:(NSString *)there
       done:(void (^)(NSString *why, NSString *way))done {
    [self say:words row:row reach:reach here:here there:there also:nil done:done];
}

// `also`, when given, is asked before each key too, as the terminal and the agent are, and stops the words as they do.
- (void)say:(NSString *)words row:(Row *)row reach:(SessionReach *)reach here:(NSString *)here there:(NSString *)there
       also:(Reason *(^)(void))also done:(void (^)(NSString *why, NSString *way))done {
    NSString *text = PlainOneLine(words, 600);
    if (!row || !text.length) {
        done(@"There's nothing to send", nil);
        return;
    }
    if (WordsRunACommand(text)) {
        done(@"Claude would take words starting with /, !, # or & as a command, so they don't go in", nil);
        return;
    }
    NSString *sid = row.sessionId;
    NSString *why = WhyNoWords(reach, here, there);
    if (why) {
        PanelLog(@"%@ -> words not sent: %@", sid, why);
        done(why, WayPast(reach, why));
        return;
    }
    id<ConversationHost> desktop = reach.conversations;
    if (desktop) {
        [desktop show:row];
        [desktop send:text toConversation:row.hostSessionId ?: @"" done:^(NSString *why) { done(why, nil); }];
        return;
    }
    id<TypingHost> terminal = reach.typing;
    NSString *tab = reach.tab;
    pid_t pid = row.pid;
    id<AgentPrompt> agent = [self agentOf:row];
    [self.typing addObject:sid];
    [agent type:text into:terminal tab:tab
         whyNot:^{
             return WhyTerminalRefuses(terminal, tab) ?: (also ? also() : nil) ?: [agent whyNotTypeInto:sid pid:pid];
         }
           done:^(Reason *why, NSUInteger typed, NSUInteger steps) {
        if (why) {
            [self.typing removeObject:sid];
            PanelLog(@"%@ -> words stopped after %lu of %lu steps: %@", sid, (unsigned long)typed, (unsigned long)steps,
                     why);
            done(why.onButton, WayPast(reach, why.onButton));
            return;
        }
        done(nil, nil);
        // The draft, with its filler, is back in the prompt once the request is sent (WhyNotEditDraft), so the filler
        // comes out, unless Claude has meanwhile asked something a key could answer.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            Reason *edit = [agent whyNotEditDraft:sid pid:pid];
            if (edit) PanelLog(@"%@ -> filler left in the prompt: %@", sid, edit);
            else [agent deleteFillerIn:terminal tab:tab];
            [self.typing removeObject:sid];
        });
    }];
}

// ---- Words between steps ----

- (NSString *)sayBetweenSteps:(NSString *)words row:(Row *)row progress:(void (^)(NSDictionary *change))progress {
    NSString *text = PlainOneLine(words, 600);
    if (!row || !text.length) {
        progress(@{@"state": @"refused", @"why": @"There's nothing to send"});
        return nil;
    }
    if (WordsRunACommand(text)) {
        progress(@{@"state": @"refused",
                   @"why": @"Claude would take words starting with /, !, # or & as a command, so they don't go in"});
        return nil;
    }
    HeldWords *held = [HeldWords new];
    held.wordsId = NSUUID.UUID.UUIDString;
    held.sessionId = row.sessionId;
    held.line = text;
    held.state = @"held";
    held.progress = progress;
    // Sent while it's idle, they go in now, as your press typed them.
    held.pressed = !Works(row);
    [self.held addObject:held];
    PanelLog(@"%@ -> words for it held", row.sessionId);
    [self moveHeld];
    return held.wordsId;
}

- (NSString *)takeBack:(NSString *)wordsId {
    HeldWords *held = [self heldWords:wordsId];
    if (!held) return @"read";
    if (![held.state isEqual:@"held"]) return [held.state isEqual:@"read"] ? @"read" : @"handed";
    // Held by its agent: out only if its hook hasn't taken them yet.
    if (held.withAgent && ![[self betweenStepsOf:held] takeBackWords:wordsId]) return @"handed";
    [self.held removeObject:held];
    PanelLog(@"%@ -> words for it taken back", held.sessionId);
    [self moveHeld];
    return nil;
}

- (void)sendNow:(NSString *)wordsId {
    HeldWords *held = [self heldWords:wordsId];
    if (![held.state isEqual:@"held"]) return;
    held.pressed = YES;
    [self moveHeld];
}

- (HeldWords *)heldWords:(NSString *)wordsId {
    for (HeldWords *held in self.held)
        if ([held.wordsId isEqual:wordsId]) return held;
    return nil;
}

// Each session's held words move on, one at a time, in the order sent: a session at work keeps them until its agent's
// hook hands them in or its turn ends; once it's idle, they go in by themselves only where it's safe, else for your
// press; typed in, they count as read once its own record shows them. Looked at every second while any are held.
- (void)moveHeld {
    NSMutableSet *before = [NSMutableSet set];
    for (HeldWords *held in [self.held copy]) {
        [self move:held first:![before containsObject:held.sessionId]];
        [before addObject:held.sessionId];
    }
    if (self.held.count && !self.heldTimer) {
        __weak typeof(self) weakSelf = self;
        self.heldTimer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t) {
            [weakSelf moveHeld];
        }];
    } else if (!self.held.count) {
        [self.heldTimer invalidate];
        self.heldTimer = nil;
    }
}

- (void)move:(HeldWords *)held first:(BOOL)first {
    Row *row = self.core.rows.byId[held.sessionId];
    if (!row || [self.core hasEnded:row]) return [self finish:held with:@{@"state": @"ended"}];
    if ([held.state isEqual:@"typed"]) {
        if (TookWords(row, held.line, held.typedAt))
            [self finish:held with:@{@"state": @"read", @"how": @"typed", @"at": row.lastPromptAt ?: @(NowMs())}];
        else if (NowMs() - held.typedAt > kTakenWithinMs) [self finish:held with:@{@"state": @"stopped"}];
        return;
    }
    id<AgentBetweenSteps> steps = [self betweenStepsOf:held];
    if ([held.state isEqual:@"handed"]) return [self follow:held row:row agent:steps];
    if (![held.state isEqual:@"held"]) return;
    if (held.withAgent) {
        if (Works(row)) return [self follow:held row:row agent:steps];
        // Its turn ended with them still untaken (stopped with Esc, say): they go on as held words do.
        if (![steps takeBackWords:held.wordsId]) return [self follow:held row:row agent:steps];
        held.withAgent = NO;
    } else if (Works(row) && [steps takesWordsBetweenSteps:row]) {
        // At work, with its agent's hook: held for the hook, which hands them in as its current step ends. A press
        // never outlasts this.
        [steps holdWords:held.line for:row id:held.wordsId];
        held.withAgent = YES;
        held.pressed = NO;
        return [self tell:held change:@{@"state": @"held", @"until": @"step"}];
    }
    SessionReach *reach = [self reachOf:row];
    BOOL byThemselves = ReachGoesByItself(reach, row.focused,
                                          NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier);
    BOOL works = Works(row), pressed = held.pressed, stillPressed = NO;
    BOOL changing = !works && first && !pressed && byThemselves
        && [WhyNoWords(reach, @"sent from here", @"say it there") isEqual:kStillChanging];
    NSString *step = HeldWordsStep(works, first, pressed, byThemselves, changing, &stillPressed);
    held.pressed = stillPressed;
    if ([step isEqual:@"turnEnd"] || [step isEqual:@"press"])
        return [self tell:held change:@{@"state": @"held", @"until": step}];
    if (![step isEqual:@"type"]) return;
    NSString *where = reach.desktop ? @"Claude Desktop" : reach.terminal;
    held.state = @"typing";
    [self tell:held change:@{@"state": @"typing"}];
    __weak typeof(self) weakSelf = self;
    [self say:held.line row:row reach:reach here:@"sent from here" there:@"say it there"
         also:pressed ? nil : [self stillAway:row] done:^(NSString *why, NSString *way) {
        if (why) return [weakSelf finish:held with:@{@"state": @"refused", @"why": why, @"way": way ?: NSNull.null,
                                                     @"where": where ?: NSNull.null}];
        held.state = @"typed";
        held.typedAt = NowMs();
        [weakSelf tell:held change:@{@"state": @"typed", @"at": @(held.typedAt)}];
    }];
}

// Going in by themselves, words stop at the next key if you come to the session meanwhile: its tab, or its terminal
// brought in front. Its terminal is found once, as the words start; the tab you're on and the app in front, at each key.
- (Reason *(^)(void))stillAway:(Row *)row {
    SessionReach *reach = [self reachOf:row];
    NSString *sid = row.sessionId;
    __weak typeof(self) weakSelf = self;
    return ^Reason *{
        Row *now = weakSelf.core.rows.byId[sid];
        NSString *front = NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier;
        return ReachGoesByItself(reach, now.focused, front) ? nil
            : [Reason terminal:@"You came to it as your words were going in"];
    };
}

// The agent that holds words for its sessions' hooks, if the session's agent does.
- (id<AgentBetweenSteps>)betweenStepsOf:(HeldWords *)held {
    Row *row = self.core.rows.byId[held.sessionId];
    id agent = row ? [self.core agentOf:row] : nil;
    return [agent conformsToProtocol:@protocol(AgentBetweenSteps)] ? agent : nil;
}

// Words its agent holds for its hook: handed once the hook has taken them, read once the session's own record shows
// them taken in. Handed, but its turn ended without them some seconds later (Claude Code let them go), they're
// stopped, for your Send Now.
- (void)follow:(HeldWords *)held row:(Row *)row agent:(id<AgentBetweenSteps>)steps {
    if (held.asking || !steps) return;
    held.asking = YES;
    __weak typeof(self) weakSelf = self;
    [steps wordsState:held.wordsId row:row done:^(NSDictionary *state) {
        held.asking = NO;
        if (![weakSelf.held containsObject:held]) return;
        NSString *now = AsText(state[@"state"]);
        if ([now isEqual:@"read"])
            return [weakSelf finish:held with:@{@"state": @"read", @"how": state[@"how"] ?: @"step",
                                                @"at": state[@"at"] ?: @(NowMs())}];
        if (![now isEqual:@"handed"]) return;
        if (![held.state isEqual:@"handed"]) {
            held.state = @"handed";
            held.handedAt = NowMs();
            [weakSelf tell:held change:@{@"state": @"handed"}];
        }
        Row *latest = weakSelf.core.rows.byId[held.sessionId];
        if (latest && !Works(latest) && NowMs() - held.handedAt > kReadWithinMs) {
            [steps forgetWords:held.wordsId];
            [weakSelf finish:held with:@{@"state": @"stopped"}];
        }
    }];
}

// How far held words have got, told once each time it changes.
- (void)tell:(HeldWords *)held change:(NSDictionary *)change {
    NSString *told = [NSString stringWithFormat:@"%@ %@", change[@"state"], change[@"until"] ?: @""];
    if ([held.told isEqual:told]) return;
    held.told = told;
    held.progress(change);
}

// Held words that have gone as far as they will: read, or not.
- (void)finish:(HeldWords *)held with:(NSDictionary *)change {
    held.state = change[@"state"];
    [self.held removeObject:held];
    PanelLog(@"%@ -> words for it %@", held.sessionId, held.state);
    held.progress(change);
}

// The agent is asked in words, going in as /compact does, as say: puts them in, and nothing waits for a result (the
// row turns to working). The row says it's asking (which also clears what it said about an earlier try), or why they
// can't go in.
- (void)ask:(NSString *)words row:(Row *)row {
    NSString *text = OneLine(words, 600);
    if (!row || !text.length) return;
    NSString *sid = row.sessionId;
    SessionReach *reach = [self reachOf:row];
    NSString *why = WhyNoAsk(reach);
    if (why) {
        PanelLog(@"%@ -> \"%@\" not asked: %@", sid, text, why);
        NSBeep();
        [self.core.page stepNote:sid text:why way:WayPast(reach, why)];
        return;
    }
    PanelLog(@"%@ -> asking \"%@\"", sid, text);
    [self.core.page stepNote:sid text:@"Asking…" quiet:YES];
    [self say:text row:row reach:reach here:@"asked from here" there:@"ask there" done:^(NSString *why, NSString *way) {
        if (!why) return;
        NSBeep();
        [self.core.page stepNote:sid text:why];
    }];
}

// The agent's command goes in as ask: puts words in, and its result is watched for, as a pick's is (the agent's
// AgentCommands): every quarter second, for 20 seconds, as one of the agent's own commands answers at once. In a
// terminal, the draft is back with its filler once the result is, so the filler comes out then.
- (void)run:(NSString *)command row:(Row *)row here:(NSString *)here there:(NSString *)there
       done:(void (^)(NSString *result, NSString *why))done {
    NSString *sid = row.sessionId;
    id agent = [self.core agentOf:row];
    id<AgentCommands> results = [agent conformsToProtocol:@protocol(AgentCommands)] ? agent : nil;
    id<AgentPrompt> prompt = [self agentOf:row];
    SessionReach *reach = [self reachOf:row];
    NSString *why = !results || !prompt ? [NSString stringWithFormat:@"This session can't be %@", here]
                  : WhyNoWords(reach, here, there);
    id mark = why ? nil : [results markResultsOf:sid];
    if (!why && !mark) why = @"Send this conversation's first message first";
    if (why) {
        PanelLog(@"%@ -> %@ not run: %@", sid, command, why);
        done(nil, why);
        return;
    }
    PanelLog(@"%@ -> running %@", sid, command);
    id<ConversationHost> desktop = reach.conversations;
    id<TypingHost> terminal = desktop ? nil : reach.typing;
    NSString *tab = reach.tab;
    pid_t pid = row.pid;
    [self.typing addObject:sid];
    void (^finished)(NSString *, NSString *) = ^(NSString *result, NSString *why) {
        [self.typing removeObject:sid];
        done(result, why);
    };
    void (^answered)(NSString *) = ^(NSString *result) {
        PanelLog(@"%@ -> %@: %@", sid, command, result ?: @"no result came");
        NSString *why = result ? nil : @"No answer came from the session";
        if (!terminal || !result) return finished(result, why);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            Reason *edit = [prompt whyNotEditDraft:sid pid:pid];
            if (edit) PanelLog(@"%@ -> filler left in the prompt: %@", sid, edit);
            else [prompt deleteFillerIn:terminal tab:tab];
            finished(result, why);
        });
    };
    if (desktop) {
        [desktop show:row];
        [desktop send:command toConversation:row.hostSessionId ?: @"" done:^(NSString *why) {
            if (why) finished(nil, why);
            else [self awaitResultOf:command since:mark from:results tries:0 then:answered];
        }];
        return;
    }
    [prompt type:command into:terminal tab:tab
          whyNot:^{ return WhyTerminalRefuses(terminal, tab) ?: [prompt whyNotTypeInto:sid pid:pid]; }
            done:^(Reason *why, NSUInteger typed, NSUInteger steps) {
        if (!why) {
            [self awaitResultOf:command since:mark from:results tries:0 then:answered];
            return;
        }
        PanelLog(@"%@ -> stopped typing %@ after %lu of %lu steps: %@", sid, command, (unsigned long)typed,
                 (unsigned long)steps, why);
        finished(nil, why.onButton);
    }];
}

- (void)awaitResultOf:(NSString *)command since:(id)mark from:(id<AgentCommands>)agent tries:(int)tries
                 then:(void (^)(NSString *result))then {
    NSString *result = [agent resultOf:command since:mark];
    if (result || tries >= 80) {
        then(result);
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self awaitResultOf:command since:mark from:agent tries:tries + 1 then:then];
    });
}

// The terminal says how its way went, on the row: where it waits for you now (quietly), or what's left for you to do.
// With nothing in the way any more (it was taken meanwhile), the row says so, rather than a press doing nothing.
- (void)takeWayPast:(NSDictionary *)msg {
    Row *row = self.core.rows.byId[AsText(msg[@"sessionId"])];
    if (!row) return;
    NSString *sid = row.sessionId;
    SessionReach *reach = [self reachOf:row];
    NSString *way = reach.wayPast;
    if (!way) {
        PanelLog(@"%@ -> nothing in the way to take now", sid);
        [self.core.page stepNote:sid text:@"Nothing's in the way now: try again" quiet:YES];
        return;
    }
    PanelLog(@"%@ -> %@", sid, way);
    __weak typeof(self) weakSelf = self;
    [reach.typing takeWayPastIn:reach.tab done:^(NSString *note, BOOL worked) {
        if (note) [weakSelf.core.page stepNote:sid text:note quiet:worked];
    }];
}

@end
