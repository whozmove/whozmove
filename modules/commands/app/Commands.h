// Commands: a slash command from the panel (model, effort, mode, compact), from its menu to its result.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import "Agent.h"
#import "Send.h"
#import "Module.h"

@class Page, PanelWindow, Core, Row, Allowed;

@interface Commands : NSObject
// Commands go into sessions through the hosts they run in (the core's: a terminal the panel types into, or Claude
// Desktop's conversations), in the words of the agent that runs them, which also says what their results mean.
- (instancetype)initWithPage:(Page *)page window:(PanelWindow *)window core:(Core *)core;
// Called when a row has something new to show: a pick, or a compaction starting or ending.
@property (copy) void (^onChange)(void);

// The page's messages: a click on a model, effort or mode (its menu), the Compact card's choice, and an answer to
// "Switch model?" asked on a row.
- (void)pick:(NSDictionary *)msg;
- (void)compact:(NSDictionary *)msg;
- (void)answerSwitch:(NSDictionary *)msg;

// For a session's row: what was picked for it and not confirmed yet, when a /compact sent from the panel began, and
// when the last one had its result.
- (NSDictionary *)chosenFor:(NSString *)sessionId;
- (NSNumber *)compactingSince:(NSString *)sessionId;
- (NSNumber *)compactEndedAt:(NSString *)sessionId;
// When a /compact from the panel last compacted a session, as its result said, and whether one is going in anywhere.
- (NSNumber *)compactedAt:(NSString *)sessionId;
@property (readonly) BOOL compactingAny;
// A /compact with its focus for a session: from the card (`stillMay` nil), or by itself (SessionCompacting's compact:).
- (void)compactRow:(Row *)row focus:(NSString *)focus stillMay:(BOOL (^)(void))stillMay
          whenOver:(void (^)(CompactEnd end, NSString *why))whenOver;
// A pick from the panel on its way into a session's terminal: {field, value, inTerminal}.
- (NSDictionary *)goingIn:(NSString *)sessionId;
// "Switch model?" as a session's row asks it, {from, to, tokens, never}, or nil.
- (NSDictionary *)switchQuestionFor:(Row *)row;
// Forgets what was picked for sessions no longer listed, once nothing can still be waiting on it.
- (void)keepPicksOf:(NSArray<Row *> *)rows;
@end

// Why a session's model, effort or mode can't be changed from its menu now, as the menu says it, or nil. `cycles` are
// a terminal session's possible Shift+Tab cycles, for its mode menu.
NSString *WhyNoPick(Row *row, NSString *field, id<Reach> reach, NSArray<NSArray<NSString *> *> *cycles);
// The item at the foot of a session's mode menu that turns back on the switches that went off as Whozmove restarted, for
// a row, as {title, line, greyed}: its title names each switch it would turn on now (and the folder, for those kept for
// one), its line is "They went off as Whozmove restarted", or, greyed only when none can come back, the first reason
// (as the press would give it, Allowed's bringableFor:among:why:). Nil while nothing waits for the row.
NSDictionary *TurnBackOnItem(Allowed *allowed, Row *row);
// Whether your press on a switch turns it on: only when it's neither on nor kept for the row's folder, so a press on a
// dash, as on a tick, turns it off.
BOOL SwitchPressTurnsOn(Allowed *allowed, NSString *key, Row *row);
// Why it can't be compacted from the Compact card now, as the card says it, or nil. `compacting`: a compaction, sent
// from the panel or not, hasn't ended yet.
NSString *WhyNoCompact(id<Reach> reach, BOOL compacting);
// Whether a compaction certainly couldn't go in now, from what's known without asking a terminal (so it can be asked of
// every row each second): the session has ended, a change from the panel is still going into it, or it runs in no
// terminal the panel can type into, or is open twice. The rest of WhyNoCompact's reasons need its tab looked for, which
// the card does once pressed.
BOOL CantCompactNow(id<Reach> reach);
// Why a compaction can't go in by itself, beyond why the card couldn't (WhyNoCompact), or nil: in Claude Desktop, which
// would come forward, or into a conversation open there too, where you may be writing.
NSString *WhyNotByItself(id<Reach> reach);
