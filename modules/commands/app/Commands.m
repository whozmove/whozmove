// Commands: a slash command from the panel (model, effort, mode, compact), from its menu to its result.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Commands.h"
#import "Command.h"
#import "Row.h"
#import "Log.h"
#import "Files.h"
#import "Text.h"
#import "Menus.h"
#import "Processes.h"
#import "Reason.h"
#import "Page.h"
#import "PanelWindow.h"
#import "Core.h"
#import "Rows.h"
#import "Send.h"

#pragma mark Why not

// A Claude Desktop row with no transcript yet is Claude's new-session page (a session it starts ahead of the first
// message). Claude doesn't count it as an open conversation, and a command there would start one.
NSString *WhyNoPick(Row *row, NSString *field, id<Reach> reach, NSArray<NSArray<NSString *> *> *cycles) {
    if (reach.desktop) {
        if (!reach.started) return @"Send this conversation's first message in Claude first";
        if (reach.changing) return kStillChanging;
        if ([row.status isEqual:@"busy"]) return @"Claude is working in this conversation: change it when it's done";
        if ([row.status isEqual:@"waiting"]) return @"Claude is waiting for your answer in this conversation";
        if ([field isEqual:@"mode"] && [row.agent[field] isEqual:@"plan"])
            return @"Plan is the only mode a slash command can set: change it in Claude";
        return nil;
    }
    NSString *why = WhyNoTab(reach, @"changed here", @"change it there");
    if (why) return why;
    // Its copies share one record of the mode, so which mode this one is in can't be told.
    if ([field isEqual:@"mode"] && reach.openElsewhere)
        return @"It's open elsewhere too: change its mode in the terminal";
    if ([row.status isEqual:@"busy"]) return @"Claude is working in this session: change it when it's done";
    if ([row.status isEqual:@"waiting"] || row.ask) return @"Claude is waiting for your answer in the terminal";
    // The mode is known only as of the session's last event, so a Shift+Tab count can be off if the mode was changed
    // in the terminal since. Where the cycle passes through Bypass, that's not worth risking.
    if ([cycles.firstObject containsObject:@"bypassPermissions"])
        return @"Bypass is in this session's Shift+Tab cycle: change its mode in the terminal";
    return nil;
}

NSString *WhyNoCompact(id<Reach> reach, BOOL compacting) {
    if (compacting) return @"Already compacting";
    if (!reach.started) return @"Send this conversation's first message first";
    if (reach.desktop) return reach.changing ? kStillChanging : reach.whyNotType.onCard;
    return WhyNoTab(reach, @"compacted from here", @"compact it there") ?: reach.whyNotType.onCard;
}

BOOL CantCompactNow(id<Reach> reach) {
    if (reach.ended || reach.changing) return YES;
    return !reach.desktop && (!reach.terminal || reach.openTwice);
}

// Whether a setting as a session's details show it is the value picked: a model by its id, which the details may
// follow with more ("[1m]").
static BOOL ShowsPick(NSString *now, NSString *field, NSString *value) {
    return [field isEqual:@"model"] ? [now hasPrefix:value] : [now isEqual:value];
}

@interface Commands ()
@property (strong) Page *page;
@property (strong) PanelWindow *window;
@property (weak) Core *core;
// sessionId -> what was picked, and when
@property (strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *chosen;
// sessionId -> when a /compact sent from the panel began
@property (strong) NSMutableDictionary<NSString *, NSNumber *> *compacting;
// sessionId -> a pick on its way into the session's terminal, {field, value, inTerminal}
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *going;
// "Switch model?" asked on a session's row, by sessionId: Claude Desktop's question, {from, to, tokens, never}, and the
// /model it's for, before it's sent (switchesToAsk) or while Claude's own box asks it (switchesAsked); a terminal
// session's /model whose agent's hook asks it (switchesAsked too), its question read from the hook; and when an answer
// to a hook's question went from here, until the hook has taken it.
@property (strong) NSMutableDictionary<NSString *, NSDictionary *> *switchQuestions;
@property (strong) NSMutableDictionary<NSString *, Command *> *switchesToAsk, *switchesAsked;
@property (strong) NSMutableDictionary<NSString *, NSDate *> *switchesAnswered;
@end

@implementation Commands

- (instancetype)initWithPage:(Page *)page window:(PanelWindow *)window core:(Core *)core {
    if (!(self = [super init])) return nil;
    self.page = page;
    self.window = window;
    self.core = core;
    self.chosen = [NSMutableDictionary dictionary];
    self.compacting = [NSMutableDictionary dictionary];
    self.going = [NSMutableDictionary dictionary];
    self.switchQuestions = [NSMutableDictionary dictionary];
    self.switchesToAsk = [NSMutableDictionary dictionary];
    self.switchesAsked = [NSMutableDictionary dictionary];
    self.switchesAnswered = [NSMutableDictionary dictionary];
    return self;
}

- (NSDictionary *)chosenFor:(NSString *)sessionId {
    return self.chosen[sessionId];
}

- (NSNumber *)compactingSince:(NSString *)sessionId {
    return self.compacting[sessionId];
}

- (NSDictionary *)goingIn:(NSString *)sessionId {
    return self.going[sessionId];
}

// Whether a pick from here is still going into a session, or "Switch model?" is asked for it: nothing more goes in
// until it's done, as the next command's keys could answer what Claude asks about this one. The row says it within a
// second (the reach's changing); this is for a press in that second.
- (BOOL)changesGoingInto:(NSString *)sessionId {
    return self.going[sessionId] || self.switchesToAsk[sessionId] || self.switchesAsked[sessionId]
        || self.switchQuestions[sessionId];
}

// What its row says of a pick on its way in: that it's going in, or that Claude Code is asking about it in the terminal
// (inTerminal); and nothing once it has its result, isn't waited on any more, or the panel asks about it itself.
- (void)show:(Command *)command going:(BOOL)going inTerminal:(BOOL)inTerminal {
    NSString *sid = command.sessionId;
    if (going) {
        self.going[sid] = @{@"field": command.field, @"value": command.value, @"inTerminal": @(inTerminal)};
    } else {
        NSDictionary *shown = self.going[sid];
        if (![shown[@"field"] isEqual:command.field] || ![shown[@"value"] isEqual:command.value]) return;
        [self.going removeObjectForKey:sid];
    }
    [self changed];
}

// A command's result is watched for about eleven minutes (awaitResult), so a pick older than fifteen is past
// waiting for. A session that's gone from the list for a moment keeps its newer picks.
- (void)keepPicksOf:(NSArray<Row *> *)rows {
    NSSet *listed = [NSSet setWithArray:[rows valueForKey:@"sessionId"]];
    double cutoff = (NSDate.date.timeIntervalSince1970 - 15 * 60) * 1000;
    for (NSString *sid in self.chosen.allKeys) {
        if ([listed containsObject:sid]) continue;
        NSDictionary *chosen = self.chosen[sid];
        double newest = 0;
        for (NSString *key in chosen)
            if ([key hasSuffix:@"At"]) newest = MAX(newest, [chosen[key] doubleValue]);
        if (newest < cutoff) [self.chosen removeObjectForKey:sid];
    }
}

// A row shows something new: a pick, or a compaction starting or ending.
- (void)changed {
    if (self.onChange) self.onChange();
}

// The agent that runs a session, if it takes commands from the panel.
- (id<AgentCommands, AgentPrompt>)agentOf:(Row *)row {
    id agent = [self.core agentOf:row];
    return [agent conformsToProtocol:@protocol(AgentCommands)] && [agent conformsToProtocol:@protocol(AgentPrompt)]
        ? agent : nil;
}

#pragma mark Model, effort and mode

// A click on the model, effort or mode opens a menu here, and the pick goes in as the slash command that would be
// typed by hand: `/model …`, `/effort …`. A terminal session (in Ghostty, say) gets it typed into its tab, with
// Shift+Tab for the mode. A Claude Desktop conversation gets it in its message box (its host's send:), and there
// the only mode a slash command can set is Plan (`/plan`), so that's all its mode menu offers.
- (void)pick:(NSDictionary *)msg {
    NSString *field = msg[@"field"];
    Row *row = self.core.rows.byId[msg[@"sessionId"]];
    if (!row || ![@[@"model", @"effort", @"mode"] containsObject:field]) return;
    id<AgentCommands, AgentPrompt> agent = [self agentOf:row];
    if (!agent) {
        PanelLog(@"%@ menu for %@: its agent takes no commands", field, row.sessionId);
        NSBeep();
        return;
    }
    SessionReach *reach = [self.core.send reachOf:row];
    BOOL desktop = reach.desktop;
    NSString *current = row.agent[field];
    // A terminal session's possible Shift+Tab cycles, worked out once for the check below and the menu.
    NSArray<NSArray<NSString *> *> *cycles = [field isEqual:@"mode"] && !desktop ? [agent modeCyclesFor:row] : nil;
    NSString *why = WhyNoPick(row, field, reach, cycles);

    PanelLog(@"%@ menu for %@%@", field, row.sessionId, why ? [@": " stringByAppendingString:why] : @"");

    NSMenu *menu = [NSMenu new];
    menu.autoenablesItems = NO;
    NSString *heading = @{@"model": @"Model", @"effort": @"Effort", @"mode": @"Permission mode"}[field];
    if (@available(macOS 14.0, *)) [menu addItem:[NSMenuItem sectionHeaderWithTitle:heading]];
    if (why) {
        SayInMenu(menu, why);
        // A way past it, when its terminal has one the panel can take (iTerm2's Python API, turned on), right under
        // it, so the menu never leaves you with only a reason.
        NSString *way = WayPast(reach, why);
        if (way) {
            NSMenuItem *item = [menu addItemWithTitle:way action:@selector(takeWayPast:) keyEquivalent:@""];
            item.target = self;
            item.representedObject = row.sessionId;
        }
    } else {
        // A terminal session's modes: the one it's in, and those a known number of Shift+Tabs away. When it can't
        // be told whether Auto is in its cycle, the modes past Plan are left to the terminal, and the menu says so.
        BOOL unsure = NO;
        for (NSArray<NSString *> *choice in [agent choicesFor:field]) {
            BOOL on = ShowsPick(current, field, choice[0]);
            if ([field isEqual:@"mode"] && desktop && ![choice[0] isEqual:@"plan"]) continue;
            if (cycles && !on && [agent shiftTabsFrom:current to:choice[0] cycles:cycles] <= 0) {
                unsure = unsure || (cycles.count > 1 && [cycles.firstObject containsObject:choice[0]]);
                continue;
            }
            NSMenuItem *item = [menu addItemWithTitle:choice[1] action:@selector(applyPick:) keyEquivalent:@""];
            item.target = self;
            item.representedObject = @{@"field": field, @"value": choice[0], @"sessionId": row.sessionId,
                                       @"tab": reach.tab ?: @""};
            item.state = on ? NSControlStateValueOn : NSControlStateValueOff;
        }
        if (unsure) SayInMenu(menu, @"Can't tell if this session has Auto: change other modes in the terminal");
    }
    [self.window popUpMenu:menu atPagePoint:NSMakePoint([msg[@"x"] doubleValue], [msg[@"y"] doubleValue])];
}

// The menu's button past the terminal's reason: the core's, as the Compact card's and a step's note's are.
- (void)takeWayPast:(NSMenuItem *)item {
    [self.core.send takeWayPast:@{@"sessionId": item.representedObject ?: @""}];
}

- (void)applyPick:(NSMenuItem *)item {
    NSDictionary *pick = item.representedObject;
    Row *row = self.core.rows.byId[pick[@"sessionId"]];
    if (!row || item.state == NSControlStateValueOn) {
        PanelLog(@"%@ -> %@ %@: %@", pick[@"sessionId"], pick[@"field"], pick[@"value"],
                 row ? @"already set" : @"session gone");
        return;
    }
    NSString *field = pick[@"field"], *value = pick[@"value"], *tab = pick[@"tab"];
    id<AgentCommands, AgentPrompt> agent = [self agentOf:row];
    if (!agent) {
        PanelLog(@"%@ -> %@ %@ not sent: no agent runs this session", row.sessionId, field, value);
        NSBeep();
        return;
    }
    if ([self changesGoingInto:row.sessionId]) {  // since the menu opened: its row says so within a second
        PanelLog(@"%@ -> %@ %@ not sent: %@", row.sessionId, field, value, kStillChanging);
        NSBeep();
        [self.page stepNote:row.sessionId text:kStillChanging];
        return;
    }
    id<ConversationHost> desktop = [self.core.send conversationHostOf:row];
    if (desktop) {
        Reason *why = WhyNotSendTo(agent, row);  // the menu may have been open a while
        if (why) {
            PanelLog(@"%@ -> %@ %@ not sent: %@", row.hostSessionId, field, value, why);
            NSBeep();
            return;
        }
        Command *command = [[Command alloc] initWithText:[agent commandSetting:field to:value] field:field value:value
                                                  forRow:row];
        command.agent = agent;
        // When Claude would ask "Switch model?", the panel asks first, and Claude's box gets the answer.
        if ([field isEqual:@"model"] && [desktop mayAskToSwitch:row]) {
            command.stage = CommandAsking;
            self.switchesToAsk[row.sessionId] = command;
            [self ask:command switchFrom:row];
            return;
        }
        [self showPickOf:command];
        [self sendToClaude:command row:row];
        return;
    }
    id<TypingHost> terminal = [self.core.send terminalOf:row];
    if (!terminal) {
        NSBeep();
        return;
    }
    // The menu may have been open a while: check again, right before any key goes in.
    Reason *why = WhyTerminalRefuses(terminal, tab) ?: [agent whyNotTypeInto:row.sessionId pid:row.pid];
    if (why) {
        PanelLog(@"%@ -> %@ %@ not typed: %@", row.sessionId, field, value, why);
        NSBeep();
        return;
    }
    if ([field isEqual:@"mode"]) {
        // Opened elsewhere since the menu came up: which mode this copy is in can't be told any more.
        if ([self.core.send reachOf:row].openElsewhere) { NSBeep(); return; }
        NSInteger presses = [agent shiftTabsFrom:row.agent[@"mode"] to:value cycles:[agent modeCyclesFor:row]];
        if (presses <= 0) { NSBeep(); return; }
        [terminal press:TerminalKeyShiftTab times:presses inTab:tab];
        // The terminal checks its own reason again as the presses go in, and refuses them all if it finds one.
        Reason *refused = WhyTerminalRefuses(terminal, tab);
        if (refused) {
            PanelLog(@"%@ -> mode %@ not pressed: %@", row.sessionId, value, refused);
            NSBeep();
            return;
        }
        [self remember:value as:@"mode" forSession:row.sessionId];
        PanelLog(@"mode of %@ -> %@ (%ld shift-tabs)", row.sessionId, value, (long)presses);
        [self changed];
        return;
    }
    Command *command = [[Command alloc] initWithText:[agent commandSetting:field to:value] field:field value:value
                                              forRow:row];
    command.agent = agent;
    command.terminal = terminal;
    command.tab = tab;
    [self showPickOf:command];
    [self type:command];
}

#pragma mark Sending

// The command's result lands in the transcript. If it hasn't within 2s (10s for a model switch whose session's hook
// asks about it in the panel first, after Claude Code has checked the model with its servers), Claude Code is asking
// something in the terminal, and its row says so, with the way there.
- (void)type:(Command *)command {
    id<AgentCommands, AgentPrompt> agent = command.agent;
    id mark = [agent markResultsOf:command.sessionId];
    if (!mark) {
        PanelLog(@"%@ -> %@ not typed: no transcript found", command.sessionId, command.text);
        [self abandon:command];
        NSBeep();
        return;
    }
    command.resultsMark = mark;
    [self holdDefaultsFor:command];
    PanelLog(@"%@ -> typing \"%@\" into %@ terminal %@", command.sessionId, command.text, command.terminal.name,
             command.tab);
    // A model switch is noted as the panel's first, so the agent's hook asks its "Switch model?" here (awaitResult:),
    // when the session's hooks can: then its answer is waited for longer before Claude is taken to ask in the terminal.
    if ([command.field isEqual:@"model"]) {
        [agent noteSwitchOf:command.sessionId to:command.value];
        command.hookAsks = [agent asksSwitchInPanel:self.core.rows.byId[command.sessionId] ?: [Row new]];
    }
    if (![command.field isEqual:@"compact"]) [self show:command going:YES inTerminal:NO];
    // Each keystroke goes in only while the session is still at its prompt (the agent's whyNotTypeInto:), and while
    // its terminal hasn't refused one (WhyTerminalRefuses), which a Compact card then says.
    [agent type:command.text into:command.terminal tab:command.tab
         whyNot:^{
        return WhyTerminalRefuses(command.terminal, command.tab)
            ?: [agent whyNotTypeInto:command.sessionId pid:command.pid];
    }
           done:^(Reason *why, NSUInteger typed, NSUInteger steps) {
        if (!why) {
            [self awaitResult:command tries:0];
            return;
        }
        PanelLog(@"%@ -> stopped typing \"%@\" after %lu of %lu steps: %@", command.sessionId, command.text,
                 (unsigned long)typed, (unsigned long)steps, why);
        NSBeep();
        if (why.kind == ReasonTerminal) {
            command.why = why.onCard;
            if ([command.terminal respondsToSelector:@selector(wayPastIn:)])
                command.way = [command.terminal wayPastIn:command.tab];
        }
        [self abandon:command];
    }];
}

- (void)sendToClaude:(Command *)command row:(Row *)row {
    id<ConversationHost> desktop = [self.core.send conversationHostOf:row];
    if (![desktop mayControl]) {
        PanelLog(@"%@ -> %@: Accessibility permission needed", row.hostSessionId, command.text);
        [self abandon:command];
        return;
    }
    // The transcript, if the conversation has one yet, carries the command's result; Claude's own record of
    // the conversation shows the change either way (the row's hostDetails).
    [desktop show:row];
    [self holdDefaultsFor:command];
    command.stage = CommandGoingIn;
    command.conversationHost = desktop;
    command.conversation = row.hostSessionId ?: @"";
    command.resultsMark = [command.agent markResultsOf:command.sessionId];
    [desktop send:command.text toConversation:command.conversation done:^(NSString *why) {
        if (!why) {
            [self awaitResult:command tries:0];
            return;
        }
        command.why = why;
        [self abandon:command];
    }];
}

#pragma mark "Switch model?"

// Claude Desktop's question for a command, on its row: the model it leaves and the one it switches to, with Don't ask
// again, as Claude keeps that answer.
- (void)ask:(Command *)command switchFrom:(Row *)row {
    self.switchQuestions[command.sessionId] = @{@"from": row.agent[@"model"] ?: @"", @"to": command.value,
                                                @"tokens": NSNull.null, @"never": @YES};
    [self changed];
}

// "Switch model?" as a session's row asks it: Claude Desktop's, or a terminal session's hook's, read from the hook
// itself, so it's there for as long as the hook asks (one asking for a panel that has restarted meanwhile included),
// and gone once it stops; but not once it's been answered here, while the hook takes the answer.
- (NSDictionary *)switchQuestionFor:(Row *)row {
    NSString *sid = row.sessionId;
    if (!sid) return nil;
    if (self.switchQuestions[sid]) return self.switchQuestions[sid];
    if (row.pid <= 0 || [self.core.send conversationHostOf:row]) return nil;
    NSDictionary *asked = [[self agentOf:row] switchAskedIn:sid];
    if (!asked) {
        [self.switchesAnswered removeObjectForKey:sid];
        return nil;
    }
    if (-[self.switchesAnswered[sid] timeIntervalSinceNow] < 10) return nil;
    return @{@"from": asked[@"from"] ?: @"", @"to": asked[@"to"] ?: @"", @"tokens": asked[@"tokens"] ?: NSNull.null,
             @"never": @NO};
}

// The answer to "Switch model?" given on a row: for Claude Desktop, before /model is sent (then it's sent, or not), or
// while Claude's own box is up (then that box gets the same answer); for a terminal session, to its agent's hook, at
// once, whether or not this panel typed the /model (it may have restarted since).
- (void)answerSwitch:(NSDictionary *)msg {
    NSString *sid = AsText(msg[@"sessionId"]);
    if (!sid) return;
    BOOL ok = [msg[@"ok"] boolValue], never = [msg[@"never"] boolValue];
    Command *waiting = self.switchesToAsk[sid];
    if (waiting) {
        [self.switchesToAsk removeObjectForKey:sid];
        [self.switchQuestions removeObjectForKey:sid];
        [self changed];
        if (never) [self stopAskingToSwitch];
        Row *row = self.core.rows.byId[sid];
        Reason *why = ok && row ? WhyNotSendTo(waiting.agent, row) : nil;  // the card may have been up a while
        PanelLog(@"%@ -> switch to %@: %@%@", sid, waiting.value, ok ? @"yes" : @"cancelled",
                 why ? [NSString stringWithFormat:@", not sent: %@", why] : @"");
        if (why) {
            NSBeep();
            [self.page stepNote:sid text:why.onButton];
        } else if (ok && row) {
            waiting.switchAnswer = never ? SwitchYesDontAskAgain : SwitchYes;
            [self showPickOf:waiting];
            [self sendToClaude:waiting row:row];
        }
        return;
    }
    Command *asked = self.switchesAsked[sid];
    if (asked.conversationHost) {  // Claude's own box asks: awaitResult passes the answer on
        [self.switchesAsked removeObjectForKey:sid];
        [self.switchQuestions removeObjectForKey:sid];
        if (never) [self stopAskingToSwitch];
        asked.switchAnswer = !ok ? SwitchCancel : never ? SwitchYesDontAskAgain : SwitchYes;
        [self changed];
        return;
    }
    Row *row = self.core.rows.byId[sid];
    id<AgentCommands, AgentPrompt> agent = asked.agent ?: (row ? [self agentOf:row] : nil);
    if (![agent switchAskedIn:sid]) {
        PanelLog(@"%@ -> \"Switch model?\" answered after its hook stopped asking", sid);
        [self.page stepNote:sid text:@"Claude is asking in the terminal now: answer there"];
        [self changed];
        return;
    }
    [agent answerSwitchIn:sid allow:ok];
    self.switchesAnswered[sid] = NSDate.date;
    if (asked) {
        [self.switchesAsked removeObjectForKey:sid];
        asked.switchAnswerGiven = YES;
        if (ok) [self show:asked going:YES inTerminal:NO];
        else [self keptModel:asked];
    }
    [self changed];
}

- (void)stopAskingToSwitch {
    for (id<ConversationHost> host in [self.core hostsThat:@protocol(ConversationHost)]) [host stopAskingToSwitch];
}

// A command that's over: the question it asked, and the note its switch left for the agent's hook, go with it, so a
// switch you then make in the terminal yourself is never taken for this one.
- (void)forgetSwitchOf:(Command *)command {
    NSString *sid = command.sessionId;
    if (self.switchesToAsk[sid] == command) {
        [self.switchesToAsk removeObjectForKey:sid];
        [self.switchQuestions removeObjectForKey:sid];
    }
    if (self.switchesAsked[sid] == command) {
        [self.switchesAsked removeObjectForKey:sid];
        if (command.conversationHost) [self.switchQuestions removeObjectForKey:sid];
    }
    if ([command.field isEqual:@"model"] && !command.conversationHost && command.agent)
        [command.agent noteSwitchOf:sid to:nil];
}

// A model switch turned down in the panel: its agent's hook blocks it, so the session stays on its model, and the draft
// comes back with the command's filler, which goes, as after a command's result.
- (void)keptModel:(Command *)command {
    command.stage = CommandAbandoned;
    [self show:command going:NO inTerminal:NO];
    [self forgetSwitchOf:command];
    [self takeBack:command];
    [self releaseDefaultsOf:command saved:NO];
    [self changed];
    id<AgentCommands, AgentPrompt> agent = command.agent;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        id why = [agent whyNotEditDraft:command.sessionId pid:command.pid];
        if (why) PanelLog(@"%@ -> filler left in the prompt: %@", command.sessionId, why);
        else [agent deleteFillerIn:command.terminal tab:command.tab];
    });
}

#pragma mark Compacting

// The Compact card's choice: `/compact`, with the focus picked or typed on the card, for that session. It goes in
// the way a model pick does (typed into its terminal tab, or written in Claude Desktop's message box), and only
// while the session sits idle. Claude's line says "Compacting" until the result; a refusal, or a compaction that
// doesn't go through, is said on the card.
- (void)compact:(NSDictionary *)msg {
    Row *row = self.core.rows.byId[msg[@"sessionId"]];
    if (!row) return;
    NSString *sid = row.sessionId;
    NSString *focus = [msg[@"focus"] isKindOfClass:NSString.class] ? msg[@"focus"] : @"";
    focus = OneLine(focus, 600);
    id<AgentCommands, AgentPrompt> agent = [self agentOf:row];
    if (!agent) {
        PanelLog(@"%@ -> /compact not sent: no agent runs this session", sid);
        NSBeep();
        [self.page compactNote:sid text:@"This conversation can't be compacted from here" way:nil];
        return;
    }
    NSString *text = [agent compactCommand:focus];
    SessionReach *reach = [self.core.send reachOf:row];
    NSString *why = WhyNoCompact(reach, self.compacting[sid] != nil)
        ?: ([self changesGoingInto:sid] ? kStillChanging : nil);
    if (why) {
        PanelLog(@"%@ -> %@ not sent: %@", sid, text, why);
        NSBeep();
        [self.page compactNote:sid text:why way:WayPast(reach, why)];
        return;
    }
    self.compacting[sid] = @(NSDate.date.timeIntervalSince1970 * 1000);
    Command *command = [[Command alloc] initWithText:text field:@"compact" value:focus forRow:row];
    command.agent = agent;
    if (reach.desktop) {
        [self sendToClaude:command row:row];
    } else {
        command.terminal = reach.typing;
        command.tab = reach.tab;
        [self type:command];
    }
    [self changed];
}

// A /compact sent from the card has run its course: Claude's line goes back to normal, and anything but
// "Compacted" is said on the card.
- (void)endCompact:(Command *)command result:(NSString *)result {
    if (![command.field isEqual:@"compact"] || !self.compacting[command.sessionId]) return;
    [self.compacting removeObjectForKey:command.sessionId];
    NSString *note = [command.agent compactNote:result];
    if (note)
        [self.page compactNote:command.sessionId
                          text:note.length ? note : command.why ?: @"The compaction didn't go through"
                           way:note.length ? nil : command.way];
    [self changed];
}

#pragma mark Picks and results

- (void)remember:(NSString *)value as:(NSString *)field forSession:(NSString *)sid {
    NSMutableDictionary *chosen = self.chosen[sid] ?: (self.chosen[sid] = [NSMutableDictionary dictionary]);
    chosen[field] = value;
    chosen[[field stringByAppendingString:@"At"]] = @(NSDate.date.timeIntervalSince1970 * 1000);
}

// Shows a command's pick on its row at once, before the session confirms it, and keeps what the row showed
// before, for takeBack if the change doesn't happen.
- (void)showPickOf:(Command *)command {
    NSDictionary *chosen = self.chosen[command.sessionId];
    command.showsPick = YES;
    command.pickBefore = chosen[command.field] ?: NSNull.null;
    command.pickBeforeAt = chosen[[command.field stringByAppendingString:@"At"]] ?: NSNull.null;
    [self remember:command.value as:command.field forSession:command.sessionId];
    [self changed];
}

// Puts a row back as it was before a command's pick, unless a newer pick has replaced it.
- (void)takeBack:(Command *)command {
    if (!command.showsPick) return;
    NSMutableDictionary *chosen = self.chosen[command.sessionId];
    NSString *field = command.field, *at = [field stringByAppendingString:@"At"];
    if (![chosen[field] isEqual:command.value]) return;
    if (command.pickBefore == NSNull.null) {
        [chosen removeObjectForKey:field];
        [chosen removeObjectForKey:at];
    } else {
        chosen[field] = command.pickBefore;
        chosen[at] = command.pickBeforeAt;
    }
    [self changed];
}

// `/model` and `/effort` also save the pick as the default for new sessions; the agent puts the defaults back once
// the command is over, each held once and let go once.
- (void)holdDefaultsFor:(Command *)command {
    [command.agent holdDefaults:command.field];
    command.holdsDefaults = YES;
}

- (void)releaseDefaultsOf:(Command *)command saved:(BOOL)saved {
    if (!command.holdsDefaults) return;
    command.holdsDefaults = NO;
    [command.agent releaseDefaults:command.field saved:saved];
}

// A command that didn't go through: the row goes back, the defaults it would have saved are let go, and a
// /compact's card says so.
- (void)abandon:(Command *)command {
    if (command.ended) return;
    command.stage = CommandAbandoned;
    [self show:command going:NO inTerminal:NO];
    [self forgetSwitchOf:command];
    [self takeBack:command];
    [self releaseDefaultsOf:command saved:NO];
    [self endCompact:command result:nil];
}

// Watches for the command's result: every quarter second for a minute, then every 2s for ten more (the row goes
// back meanwhile), since a question Claude Code asked first ("Switch model?") can be answered late.
- (void)awaitResult:(Command *)command tries:(int)tries {
    command.stage = CommandWaiting;
    id<ConversationHost> host = command.conversationHost;
    BOOL desktop = host != nil, late = tries > 240;
    // Claude asks "Switch model?" before re-reading a cached conversation. With an answer given in the panel, its
    // box gets it; if it asks without one (the panel didn't expect it), the panel asks now.
    if (desktop && !late && [command.field isEqual:@"model"] && !command.switchAnswerGiven && tries % 4 == 0) {
        SwitchAnswer answer = command.switchAnswer;
        if (answer != SwitchUnanswered
            && [host answerSwitchBox:answer != SwitchCancel dontAskAgain:answer == SwitchYesDontAskAgain]) {
            command.switchAnswerGiven = YES;
            PanelLog(@"%@ -> answered Claude's \"Switch model?\": %@", command.conversation,
                     answer != SwitchCancel ? @"switch" : @"cancel");
            if (answer == SwitchCancel) { [self abandon:command]; return; }
        } else if (answer == SwitchUnanswered && self.switchesAsked[command.sessionId] != command
                   && [host showsSwitchBox]) {
            self.switchesAsked[command.sessionId] = command;
            [self ask:command switchFrom:self.core.rows.byId[command.sessionId]
                                             ?: [[Row alloc] initWithFields:@{@"sessionId": command.sessionId}]];
        }
    }
    id<AgentCommands, AgentPrompt> agent = command.agent;
    // A terminal session's Claude Code asks "Switch model?" on its row, through its agent's hook, when the switch would
    // re-read a cached conversation: the row shows the hook's question for as long as the hook asks
    // (switchQuestionFor:), and your answer goes straight to the hook (answerSwitch:). If the hook stops asking without it (a minute went
    // by), Claude asks in the terminal, and the row says so.
    NSString *sid = command.sessionId;
    if (!desktop && [command.field isEqual:@"model"] && !command.switchAnswerGiven) {
        BOOL asked = [agent switchAskedIn:sid] != nil;
        if (asked && !command.askedInPanel) {
            command.askedInPanel = YES;
            self.switchesAsked[sid] = command;
            PanelLog(@"%@ -> \"Switch model?\" asked on its row", sid);
            [self show:command going:NO inTerminal:NO];  // the question stands in its place
        } else if (!asked && command.askedInPanel) {
            command.switchAnswerGiven = YES;
            if (self.switchesAsked[sid] == command) [self.switchesAsked removeObjectForKey:sid];
            PanelLog(@"%@ -> \"Switch model?\" not answered here: Claude asks in the terminal", sid);
            [self show:command going:YES inTerminal:YES];
        }
    }
    NSString *result = [agent resultOf:command.text since:command.resultsMark];
    // Claude Desktop's own record of the setting, as the conversation's row last read it.
    NSDictionary *details = self.core.rows.byId[command.sessionId].hostDetails;
    NSString *shown = desktop && ShowsPick(details[command.field], command.field, command.value) ? command.value : nil;
    if (!result && !shown) {
        // No result yet: Claude Code is asking something in the terminal, and the row says so, with the way there. A
        // question its agent's hook asks in the panel is answered here instead.
        if (tries == (command.hookAsks ? 40 : 8) && !desktop && ![command.field isEqual:@"compact"]
            && !command.askedInPanel) {
            PanelLog(@"%@ -> no result yet: Claude is asking in the terminal", command.sessionId);
            [self show:command going:YES inTerminal:YES];
        }
        if (tries == 240) {  // a minute: the row goes back, but a late answer still counts
            PanelLog(@"%@ -> no result for %@ after a minute; still watching", command.sessionId, command.text);
            [self takeBack:command];
        }
        if (tries >= 240 + 300) {
            PanelLog(@"%@ -> stopped watching for %@", command.sessionId, command.text);
            [self show:command going:NO inTerminal:NO];
            [self forgetSwitchOf:command];
            command.stage = CommandAbandoned;
            [self releaseDefaultsOf:command saved:NO];
            [self endCompact:command result:nil];
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((late ? 2 : 0.25) * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self awaitResult:command tries:tries + 1];
        });
        return;
    }
    command.stage = CommandDone;
    [self show:command going:NO inTerminal:NO];
    [self forgetSwitchOf:command];
    PanelLog(@"%@ -> %@", command.sessionId, result ?: [@"Claude shows " stringByAppendingString:shown]);
    [self endCompact:command result:result];
    // The draft (with its filler) is back in the prompt by now, so the filler is deleted, unless the session has
    // moved on to something a key could answer, or this came so late that someone may be typing there.
    if (!desktop)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            id why = late ? @"the result came late" : [agent whyNotEditDraft:command.sessionId pid:command.pid];
            if (why) PanelLog(@"%@ -> filler left in the prompt: %@", command.sessionId, why);
            else [agent deleteFillerIn:command.terminal tab:command.tab];
        });
    // What the result says applies, else what Claude Desktop's record shows.
    NSString *field = command.field, *applied = [agent resultApplies:field value:command.value result:result] ?: shown;
    if (applied) [self remember:applied as:field forSession:command.sessionId];  // what really applies
    else [self takeBack:command];                                               // declined or failed
    // Claude Desktop's record doesn't say whether the pick was saved as the default, so there the defaults go back
    // whenever they changed.
    [self releaseDefaultsOf:command saved:desktop || [agent resultSavedDefault:result]];
    [self changed];
}

@end
