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
// Runs the project's saved command in a folder, as a press or an ask does once nothing waits (see Deploys.m): why it
// didn't start, or nil; `reconfirm` set when what the command runs changed since you confirmed it, so the set-up card
// should show it again. On Deploy's queue, or in a print run.
- (NSString *)runIn:(NSString *)folder project:(NSString *)project expecting:(NSString *)expecting by:(NSString *)by
          reconfirm:(BOOL *)reconfirm;
// The same, installing the checkout's packages first as Install First's card showed it (`install`: {words, hash}, from
// DeployInstallCheck), in the same shell, its output at the start of the run's log; the command runs only once that has
// gone through. If what the install runs has changed since (its words, the project's install scripts, its lock file),
// nothing runs, and the card's second step shows what it runs now.
- (NSString *)runIn:(NSString *)folder project:(NSString *)project expecting:(NSString *)expecting by:(NSString *)by
          reconfirm:(BOOL *)reconfirm install:(NSDictionary *)install;
// A command you confirmed, twice, in the set-up card: saved for the row's project, with what it runs in the row's
// folder and the port it showed, and run straight away if Deploy was what opened the card. Saved only if what it runs
// there is still all the card was shown for that row and command (check:); else the card opens again to show it.
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
// For a row's ▾: {command, suggested, running, log, up}, each there if there is one. From what was last read, so it never
// waits.
- (NSDictionary *)stateOf:(Row *)row;
// The address of a row's folder's build that's up (http://localhost:<port>, from the port Deploy read), or nil; and
// opening it in the app that opens web pages.
- (NSURL *)addressOf:(Row *)row;
- (void)openAddress:(Row *)row;
// Restart, for a build that's up: Stop Deploy, then the same deploy a press makes once that run has ended, with the
// same waits. Stop Deploy pressed while it waits for that run to end calls it off, as does a later Restart.
- (void)restart:(Row *)row;
// Install and Deploy, on the card for a run with no packages: your press alone, never an ask or a kept press. The
// checkout's packages installed, only as its card showed it (`shown`: {words, hash}, from checkInstallOf:), then the
// command run, with every wait and the port checked as a press of Deploy checks them.
- (void)installAndDeploy:(Row *)row as:(NSDictionary *)shown;
// What Install First runs in the row's checkout (DeployInstallCheck), worked out on the queue for its card's second
// step, which the page is given (deployInstallChecked).
- (void)checkInstallOf:(Row *)row;
// A session's row as it was last listed (refreshFor:, readNowFor:), or nil: who a kept press is for.
- (Row *)listedRow:(NSString *)sessionId;
// The presses kept while an agent works (DeployKept), by folder ({sessionId}), sent to the page with each folder.
- (void)showKept:(NSDictionary<NSString *, NSDictionary *> *)kept;
// Whether a Restart, or Stop It and Deploy, is still waiting to deploy in a folder: for a print run, which waits for
// it to have done what it will before the next case.
- (BOOL)deployWaitsIn:(NSString *)folder;
// A press on Deploy's card for the row's folder (a port another build or program holds): close, cancel, ports, next or
// replace (Deploys.m).
- (void)cardAct:(NSString *)act forRow:(Row *)row;
// Deploy's card for a folder, as last read, or nil; and the port check before a press runs, with the sessions listed
// ({sid, name, pid, start}): the card to show, or nil (Deploys.m).
// The row's folder's last run's log, opened in the app that opens it.
- (void)openLogOf:(Row *)row;
// The row's checkout's install command (DeployInstallCommand), copied for you to run where you choose.
- (void)copyInstallOf:(Row *)row;
- (NSDictionary *)cardIn:(NSString *)folder;
- (NSDictionary *)portCheckIn:(NSString *)folder project:(NSString *)project sessions:(NSArray<NSDictionary *> *)sessions;
// How many times, half a second apart, Restart looks for the run before to have ended before it gives up: 20, but for
// a print run's case.
@property (assign) int restartTries;
// Why a deploy can't start from this row now (its agent, or another in its folder, at work or asking), or nil.
- (NSString *)whyNotNow:(Row *)row;
// The command you confirmed for a row's project, and its folder's last run (LastDeployRun's), from what was last read;
// nil for none.
- (NSString *)commandFor:(Row *)row;
- (NSDictionary *)runIn:(NSString *)folder;
// What these rows' projects and folders have, read now and kept, for a print run, which never refreshes; and waiting
// until what was set going on its queue (a command saved) is done.
- (void)readNowFor:(NSArray<Row *> *)rows;
- (void)settle;
// A deploy a session asked for, as you allowed it (Let It Deploy): run as your press runs one, from `folder`, one of
// the row's project's checkouts, only while the project's command is still `command`, and noted as asked by `by`. The
// row says why, if it didn't start. Its port is checked first, as a press's: held while the server takes $PORT, it runs
// on the next free port, kept from now on (movedIn: says which, and the one it took it in place of); held otherwise,
// it doesn't run, and the card waits for you, with `asked` naming who asked.
- (void)deployAsked:(Row *)row in:(NSString *)folder expecting:(NSString *)command by:(NSString *)by;
- (NSDictionary *)movedIn:(NSString *)folder;
// The deploys sessions have asked for and are waiting, by folder, {by, waits}, which the page is told with the rest.
- (void)showAsked:(NSDictionary<NSString *, NSDictionary *> *)asked;
// A project's build in place, as BuildsInPlace (contracts/Module.h) gives it, from what was last read; nil for none.
- (NSDictionary *)buildInPlaceFor:(NSString *)project;
@end

// The project a session works in, as Deploy keys it: the repo's main checkout, so its worktrees share one command, or
// the folder itself outside git. And the folder it deploys from: its own checkout, or that folder.
NSString *DeployProject(Row *row);
NSString *DeployFolder(Row *row);
// The command Whozmove suggests for a folder, from the project's own files, or nil when it can't tell. Blocking.
NSString *SuggestDeploy(NSString *folder);
// What a deploy command really runs in a folder and whether it looks as if it could reach production: {command,
// production, runs, cut, files, unsure, others}: `runs` the package scripts, Makefile recipes and files it runs, with
// what they call in turn (`cut` when there's more than the card shows), `files` those that decide it, which are checked
// before every run, `unsure` what Whozmove can't follow or can't check (a file outside the checkout, say), and `others`
// the programs whose own files decide what they do, which aren't checked. Blocking.
NSDictionary *CheckDeploy(NSString *folder, NSString *command);
// All that decides what a command runs in a folder, as one text ("" when nothing it runs is checked): what's confirmed
// with it, and checked before every run. Blocking.
NSString *DeployCheckText(NSString *folder, NSString *command);
// That text's SHA-256, as it's kept with a confirmed command (`runsHash`). Blocking.
NSString *DeployRunsHash(NSString *folder, NSString *command);
// How a folder's last deploy went, as the page gets it ({startedAt, running, ok, finishedAt, lastLine, stopped, by,
// commit, uncommitted, port, up}, `by` naming the session that asked for it, when one did, `commit` and `uncommitted`
// what it started from, BuildNow's, `port` the one it was given in $PORT, and `up` what it listens on once it does,
// {port, at, every, also}), or nil before its first. One that installs its packages first (Install First) has
// `installing` while that goes on and `installedAt` once it went through, or, once ended, `installFailed` if it didn't,
// the command never run. It runs while its shell does, or a member of its process group noted while it ran (a server
// its shell left running); a run that was up and has ended didn't go through. Blocking.
NSDictionary *LastDeployRun(NSString *folder);
// Where a folder's last deploy's output is kept.
NSString *DeployLogPath(NSString *folder);
// How a checkout's packages are installed, from the lock file in its top folder alone: {words, lockfile}, the form that
// never rewrites it (`npm ci` for npm-shrinkwrap.json or package-lock.json, `pnpm install --frozen-lockfile`, `yarn
// install --immutable`, or `--frozen-lockfile` for Yarn 1, as yarn.lock's first lines say, `bun install
// --frozen-lockfile` for bun.lock or bun.lockb); with none, {words: "npm install", makesLockfile: YES}. Always one of
// these fixed commands, never text from the project. Its lock file is read as every project file is, never blocking,
// on Deploy's queue. What the card for a run with no packages copies, and Install First runs.
NSDictionary *DeployInstallWords(NSString *folder);
NSString *DeployInstallCommand(NSString *folder);
// What Install First runs in a folder, followed as a confirmed command is (CheckDeploy): DeployInstallWords' words and
// lock file, with `runs` (the project's own install scripts), `unsure`, `others` and `files`, and `hash`, the
// fingerprint of all that decides it, which runIn: checks before it installs. On Deploy's queue.
NSDictionary *DeployInstallCheck(NSString *folder);
// While a folder's run goes on, what its process group is and listens on, noted beside the run: its members, which Stop
// Deploy signals once the run's shell has gone, and once it listens, `up` ({port, at, every, also}), which
// LastDeployRun gives with the run. The panel looks every couple of seconds while a run lasts. Blocking.
void NoteRunUp(NSString *folder);
// What a deploy from a folder notes it starts from: {commit, uncommitted}, the checkout's commit and how many of its
// files aren't committed, as the row's numbers count them; empty outside git. Blocking.
NSDictionary *BuildNow(NSString *folder);
// Each of these folders' projects' build in place, by project, as Deploy keeps it once it reads them next, without
// keeping anything: for a print run, which only looks. Blocking.
NSDictionary *BuildsInPlaceSeen(NSDictionary<NSString *, NSString *> *projectOf);
// The port a deploy in a folder of a project gets in $PORT (ports.json): the one it was given, or the project's first
// port for its main checkout and the next one no other checkout has for a worktree, kept only if `keep`. Blocking.
NSNumber *DeployPort(NSString *project, NSString *folder, BOOL keep);
