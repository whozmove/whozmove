// Deploys: Deploy, a next step for any project: the command you've set for each project, the one Whozmove suggests
// before you have, running it on this Mac, and how each folder's last run went.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Page, Row;

@interface Deploys : NSObject
- (instancetype)initWithPage:(Page *)page;
// Keeps what the page knows about these sessions' projects and folders fresh: read alongside, every couple of
// seconds, and sent to the page when anything changed.
- (void)refreshFor:(NSArray<Row *> *)rows;
// Tells a freshly loaded page at once.
- (void)resend;
// Deploy pressed on a row, with a command saved for its project: runs it, from the row's folder. Not while the row's
// agent works or asks: the row then says it waits.
- (void)deploy:(Row *)row;
// A command you confirmed, twice, in the set-up card: saved for the row's project, and run straight away if Deploy
// was what opened the card.
- (void)save:(NSString *)command forRow:(Row *)row thenDeploy:(BOOL)deploy;
// Not This Time: a suggested Deploy steps aside until the next piece of work in the folder.
- (void)skip:(Row *)row;
// Forget Deploy Command: the project's saved command goes, and with it the always-there button.
- (void)forget:(Row *)row;
// Stop Deploy: ends the run going on in the row's folder, and what it started.
- (void)stop:(Row *)row;
// A command on the set-up card, about to be confirmed: the page is told what it really runs in the row's folder, and
// whether that looks as if it could reach production (CheckDeploy), so the card can say so.
- (void)check:(NSString *)command forRow:(Row *)row;
// For a row's ▾: {command, suggested, running, log}, each there if there is one. From what was last read, so it never
// waits.
- (NSDictionary *)stateOf:(Row *)row;
@end

// The project a session works in, as Deploy keys it: the repo's main checkout, so its worktrees share one command, or
// the folder itself outside git. And the folder it deploys from: its own checkout, or that folder.
NSString *DeployProject(Row *row);
NSString *DeployFolder(Row *row);
// The command Whozmove suggests for a folder, from the project's own files, or nil when it can't tell. Blocking.
NSString *SuggestDeploy(NSString *folder);
// What a deploy command really runs in a folder and whether it looks as if it could reach production: {command,
// production, runs, more}, `runs` being the package scripts or Makefile recipes it names (up to 12 lines; `more` says
// how many more there are), when it names any. Blocking.
NSDictionary *CheckDeploy(NSString *folder, NSString *command);
// How a folder's last deploy went, as the page gets it ({startedAt, running, ok, finishedAt, lastLine, stopped}), or
// nil before its first. Blocking.
NSDictionary *LastDeployRun(NSString *folder);
