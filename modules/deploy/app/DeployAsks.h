// DeployAsks: Let It Deploy, a switch for one session at a time (Allowed, in the core): that session may ask the panel
// (ask-panel.sh) to run its project's Deploy command, as your press of Deploy would, from its own checkout, the one its
// row is about, so the row shows the ask waiting and Not This Time can drop it. The run waits until no other session's
// agent is at work there (not for the asking session's own turn to end) and you've stepped off the panel, then
// everything is checked again.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Core, Deploys, Row;

// The switch's key, as Allowed keeps it.
extern NSString *const kLetItDeploy;

@interface DeployAsks : NSObject
- (instancetype)initWithCore:(Core *)core deploys:(Deploys *)deploys;
// What a session that may deploy asks with ask-panel.sh, from its own process `process`, about its own checkout (nil,
// or that checkout named as `folder`; any other folder is refused), answered in a line: `put-in-place` keeps its ask
// (a newer one in the same folder replaces it), `status` says how that folder's deploy stands.
- (NSString *)ask:(Row *)row from:(pid_t)process folder:(NSString *)folder;
- (NSString *)status:(Row *)row folder:(NSString *)folder;
// Each second: each ask waiting runs once nothing holds it up, and goes once its switch has ended (for that process),
// its session has gone, its session's row is about another checkout now, or a deploy has run there since it was asked.
// What was decided for each folder at the last look ("would run now" in a print run, which never runs one; "waits …"; "dropped, as …"), for
// the tests.
- (void)tick;
@property (readonly) NSDictionary<NSString *, NSString *> *decided;
// The ask waiting in a folder, {sessionId, pid, by, at, waits}, or nil; Not This Time, from Deploy's ▾, drops it, as
// the switch going off does for the asks of that session.
- (NSDictionary *)askedIn:(NSString *)folder;
- (void)dropIn:(NSString *)folder;
- (void)dropFrom:(NSString *)sessionId;
@end

// Why an ask from a session's row about its checkout waits now, said after "Deploy asked by …", or nil when it can run:
// a deploy already running there, another session's agent at work there (WhyStepsWait), or you on the panel.
NSString *AskWaits(Row *row, NSArray<Row *> *rows, BOOL panelInUse, BOOL running);
// Whether an ask for a folder whose last run is `run` (LastDeployRun's) restarts it rather than deploying: its build is
// up, a server that runs till you stop it, so it's stopped, then deployed, rather than waited on.
BOOL AskRestarts(NSDictionary *run);
// The checkout of `project` at `folder`: the project's own checkout, a worktree its repo lists, or, for a project
// outside git, the folder itself; nil, with *why, for any other folder.
NSString *DeployCheckoutIn(NSString *folder, NSString *project, NSString **why);
// A session as its row is titled: its name, else its folder's.
NSString *SessionTitle(Row *row);
