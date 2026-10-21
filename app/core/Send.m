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

NSString *WhyNoAsk(id<Reach> reach) {
    return WhyNoWords(reach, @"asked from here", @"ask there");
}

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
@end

@implementation Send

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    self.typing = [NSMutableSet set];
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

// The agent is asked in words, going in as /compact does, only while the session is idle, and nothing waits for a
// result (the row turns to working). They go in as one line, as a message typed once and sent. The row says it's
// asking (which also clears what it said about an earlier try), or why they can't go in.
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
    id<ConversationHost> desktop = reach.conversations;
    if (desktop) {
        [desktop show:row];
        [desktop send:text toConversation:row.hostSessionId ?: @"" done:^(NSString *why) {
            if (why) [self.core.page stepNote:sid text:why];
        }];
        return;
    }
    id<TypingHost> terminal = reach.typing;
    NSString *tab = reach.tab;
    pid_t pid = row.pid;
    id<AgentPrompt> agent = [self agentOf:row];
    [self.typing addObject:sid];
    [agent type:text into:terminal tab:tab
         whyNot:^{ return WhyTerminalRefuses(terminal, tab) ?: [agent whyNotTypeInto:sid pid:pid]; }
           done:^(Reason *why, NSUInteger typed, NSUInteger steps) {
        if (why) {
            [self.typing removeObject:sid];
            PanelLog(@"%@ -> stopped asking \"%@\" after %lu of %lu steps: %@", sid, text, (unsigned long)typed,
                     (unsigned long)steps, why);
            NSBeep();
            [self.core.page stepNote:sid text:why.onButton];
            return;
        }
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
