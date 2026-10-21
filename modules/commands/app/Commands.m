// Commands: a slash command from the panel (model, effort, mode, compact), from its menu to its result.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Commands.h"
#import "Command.h"
#import "Row.h"
#import "Log.h"
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
    if (reach.desktop) return reach.whyNotType.onCard;
    return WhyNoTab(reach, @"compacted from here", @"compact it there") ?: reach.whyNotType.onCard;
}

BOOL CantCompactNow(id<Reach> reach) {
    if (reach.ended) return YES;
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
@property (strong) Command *switchToAsk;  // a /model waiting on the "Switch model?" asked in the panel
@property (strong) Command *switchAsked;  // a /model whose "Switch model?" Claude asked unexpectedly
@end

@implementation Commands

- (instancetype)initWithPage:(Page *)page window:(PanelWindow *)window core:(Core *)core {
    if (!(self = [super init])) return nil;
    self.page = page;
    self.window = window;
    self.core = core;
    self.chosen = [NSMutableDictionary dictionary];
    self.compacting = [NSMutableDictionary dictionary];
    return self;
}

- (NSDictionary *)chosenFor:(NSString *)sessionId {
    return self.chosen[sessionId];
}

- (NSNumber *)compactingSince:(NSString *)sessionId {
    return self.compacting[sessionId];
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
            self.switchToAsk = command;
            [self askSwitchFor:row to:value];
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

// The command's result lands in the transcript. If it hasn't within about 1.5s, Claude Code is asking something
// first (a model switch on a cached conversation asks for a yes), so the tab comes forward to be answered there.
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
        if (why.kind == ReasonTerminal) command.why = why.onCard;
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

- (void)askSwitchFor:(Row *)row to:(NSString *)model {
    [self.page askSwitch:@{@"sessionId": row.sessionId, @"from": row.agent[@"model"] ?: @"", @"to": model}];
}

// The answer to "Switch model?" given in the panel: before /model is sent (then it's sent, or not), or while
// Claude's own box is up (then that box gets the same answer).
- (void)answerSwitch:(NSDictionary *)msg {
    BOOL ok = [msg[@"ok"] boolValue], never = [msg[@"never"] boolValue];
    if (never)
        for (id<ConversationHost> host in [self.core hostsThat:@protocol(ConversationHost)]) [host stopAskingToSwitch];
    Command *waiting = self.switchToAsk;
    if ([waiting.sessionId isEqual:msg[@"sessionId"]]) {
        self.switchToAsk = nil;
        Row *row = self.core.rows.byId[msg[@"sessionId"]];
        Reason *why = ok && row ? WhyNotSendTo(waiting.agent, row) : nil;  // the card may have been up a while
        PanelLog(@"%@ -> switch to %@: %@%@", msg[@"sessionId"], waiting.value, ok ? @"yes" : @"cancelled",
                 why ? [NSString stringWithFormat:@", not sent: %@", why] : @"");
        if (why) {
            NSBeep();
        } else if (ok && row) {
            waiting.switchAnswer = never ? SwitchYesDontAskAgain : SwitchYes;
            [self showPickOf:waiting];
            [self sendToClaude:waiting row:row];
        }
        return;
    }
    Command *asked = self.switchAsked;
    if ([asked.sessionId isEqual:msg[@"sessionId"]]) {
        self.switchAsked = nil;
        // awaitResult passes it on to Claude's box.
        asked.switchAnswer = !ok ? SwitchCancel : never ? SwitchYesDontAskAgain : SwitchYes;
    }
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
        [self.page compactNote:sid text:@"This conversation can't be compacted from here"];
        return;
    }
    NSString *text = [agent compactCommand:focus];
    SessionReach *reach = [self.core.send reachOf:row];
    NSString *why = WhyNoCompact(reach, self.compacting[sid] != nil);
    if (why) {
        PanelLog(@"%@ -> %@ not sent: %@", sid, text, why);
        NSBeep();
        [self.page compactNote:sid text:why];
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
                          text:note.length ? note : command.why ?: @"The compaction didn't go through"];
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
        } else if (answer == SwitchUnanswered && self.switchAsked != command && [host showsSwitchBox]) {
            self.switchAsked = command;
            [self askSwitchFor:self.core.rows.byId[command.sessionId]
                                   ?: [[Row alloc] initWithFields:@{@"sessionId": command.sessionId}]
                            to:command.value];
        }
    }
    id<AgentCommands, AgentPrompt> agent = command.agent;
    NSString *result = [agent resultOf:command.text since:command.resultsMark];
    // Claude Desktop's own record of the setting, as the conversation's row last read it.
    NSDictionary *details = self.core.rows.byId[command.sessionId].hostDetails;
    NSString *shown = desktop && ShowsPick(details[command.field], command.field, command.value) ? command.value : nil;
    if (!result && !shown) {
        // No result after about 1.5s: Claude Code is asking something, so its tab comes forward to be answered.
        if (tries == 4 && !desktop && ![command.field isEqual:@"compact"]) {
            PanelLog(@"%@ -> no result yet; bringing its tab forward", command.sessionId);
            [command.terminal open:self.core.rows.byId[command.sessionId] ?: [Row new]];
        }
        if (tries == 240) {  // a minute: the row goes back, but a late answer still counts
            PanelLog(@"%@ -> no result for %@ after a minute; still watching", command.sessionId, command.text);
            [self takeBack:command];
        }
        if (tries >= 240 + 300) {
            PanelLog(@"%@ -> stopped watching for %@", command.sessionId, command.text);
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
