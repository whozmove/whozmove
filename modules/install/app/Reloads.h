// Reloads: the sessions that were running before Whozmove's hooks went into their agent, which run without them until
// they reload them, and reloading them from the panel: a row's own press, or Reload Them on the line for all of them,
// one at a time, each only while it's idle (Reload Them takes the ones idle at the press, never one at work, which would
// go in by itself later); one the panel can't type into, or whose reload Claude Code held back, is left for you to
// reload in its tab. What's been reloaded is kept in Whozmove's folder (reloads.json), by session, as when, so a session
// reloaded since it started isn't asked again, the panel opening again or the hooks put back.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Agent.h"

@class Core, Row;

@interface Reloads : NSObject
- (instancetype)initWithCore:(Core *)core agent:(id<AgentInstall>)agent;
// When the hooks last went in, in ms since 1970 (Install's hooksAt), while they're in; else nil, and no session needs
// reloading.
@property (strong) NSNumber *hooksAt;
// Marks each row that needs it (its `reload`), as the rows are whole.
- (void)mark:(NSArray<Row *> *)rows;
// A press: one session's, on its row (Reload, or Try Again on one left for you), or Reload Them's, for all that need it
// and are idle now.
- (void)reload:(NSString *)sessionId;
- (void)reloadAll;
// Each tick: the next one waiting goes in, while none is going in; one that started working meanwhile is let go.
- (void)tick;
// For the line, while the hooks are in: {open, idle, byHand, first, waiting, going, done, total, since}, while sessions
// need it: how many the panel can reload, and of them how many are idle now, how many are left for you to reload in
// their tabs (the first of them, {sessionId, name, command, held}, which the line names and takes you to: `held` when
// Claude Code held its reload back), how many are waiting for theirs or going in, the name of the one going in, how
// many of how many were reloaded since the last press, and since when they've needed it (the hooks' time, which a × on
// the line holds for); {allSet, since} once a press has reloaded the last of them, since then; else nil. `onChange`
// hears when it changes.
@property (readonly) NSDictionary *summary;
@property (copy) void (^onChange)(void);
@end
