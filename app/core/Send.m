// Send: words into a session, through its host and its agent; and why they can't go in now.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import "Send.h"
#import "Core.h"
#import "Page.h"
#import "Row.h"
#import "Reason.h"
#import "Log.h"
#import "Text.h"

// Why no words can be typed into the session's tab: it has ended, there's no terminal the panel can type into, its tab
// isn't found, or another tab fits as well. `here` and `there` end the sentences ("can be changed here", "change it
// there").
NSString *WhyNoTab(id<Reach> reach, NSString *here, NSString *there) {
    if (reach.ended) return @"It isn't running: press its row to open it again";
    if (!reach.terminal)
        return [NSString stringWithFormat:@"Only sessions running in %@ can be %@", reach.terminals, here];
    if (!reach.hasTab) return [NSString stringWithFormat:@"Couldn't find this session's %@ tab", reach.terminal];
    if (reach.openTwice) return [Reason kind:ReasonOpenTwice].onCard;
    if (!reach.unique) return [NSString stringWithFormat:@"Another tab in this folder looks the same: %@", there];
    return nil;
}

// While it works, the command would go in as a message; while it waits, Claude is asking something in that
// conversation. With no agent to say, nothing goes in.
Reason *WhyNotSendTo(id<AgentPrompt> agent, Row *row) {
    if (!agent) return [Reason kind:ReasonSessionGone];
    return row.pid > 0 ? [agent whyNotTypeInto:row.sessionId pid:row.pid] : nil;
}

NSString *WhyNoAsk(id<Reach> reach) {
    if (!reach.started) return @"Send this conversation's first message first";
    if (reach.desktop)
        return !reach.mayControl ? @"Whozmove needs the Accessibility permission for this" : reach.whyNotType.onButton;
    return WhyNoTab(reach, @"asked from here", @"ask there") ?: reach.whyNotType.onButton;
}

@implementation SessionReach {
    Row *_row;
    __weak Send *_send;
    NSNumber *_started, *_mayControl;
    BOOL _lookedForTerminal, _lookedForTab, _unique, _askedWhyNot;
    id<TypingHost> _typing;
    NSString *_tab;
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
@end

@implementation Send

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    return self;
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

// The terminals the panel can type into, by name ("Ghostty", or "Ghostty or iTerm" once there are two).
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
        [self.core.page stepNote:sid text:why];
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
    [agent type:text into:terminal tab:tab whyNot:^{ return [agent whyNotTypeInto:sid pid:pid]; }
           done:^(Reason *why, NSUInteger typed, NSUInteger steps) {
        if (why) {
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
        });
    }];
}

@end
