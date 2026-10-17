// NextSteps: the menus behind a row's island, one per stage: what the stage holds, and the ways to take its next step;
// and the commits stage's card.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>

@class Core, Stages, Checkouts;

@interface NextSteps : NSObject
// The steps ask the agent through the core (its Send), which has the rows and the page too; the extra stage's own
// actions run through Stages, and what each stage holds comes from Checkouts.
- (instancetype)initWithCore:(Core *)core stages:(Stages *)stages checkouts:(Checkouts *)checkouts;
// A stage on a row's island ({stage, step, count, pr, sessionId, x, y}): its menu opens below it.
- (void)stageMenu:(NSDictionary *)msg;
// The commits stage pointed at ({stage: "commits", step, count, sessionId}): what its menu would hold, for the page to
// show as a card: {heading, items (commit subjects), more, steps: [{step, title, tip}], enabled, wait}, sent with
// showStageCard. Asked with `quiet` (with every update, to keep it ready), it's sent only when it has changed.
- (void)stageCard:(NSDictionary *)msg;
// A step pressed on that card ({sessionId, from (the stage's step, as the island names it), step}): asked of the agent
// in its fixed words, only if the card offers it for that step now and nothing waits.
- (void)takeStep:(NSDictionary *)msg;
@end
