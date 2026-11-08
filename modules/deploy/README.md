# Deploy

Deploy, a next step for any project: the command you've set for each project, the one Whozmove suggests before you
have, running it on this Mac, and how each folder's last run went; its round button on a row, its set-up card and its
menu; and Let It Deploy, which lets a session you allow ask for its project's Deploy.

## Its pieces

- `app/DeployModule.m`: its face for the core (contracts/Module.h): the round button's presses, the set-up card's
  messages, each row's project and folder kept fresh, and the print modes the tests check. It adds Show Deploy to Git's
  page on the panel's back (`appEntries`). Its round button sits among a row's next steps, so the switch is on only
  while they show, and turning it on turns Show Next Steps on too; Show Next Steps turned off leaves Deploy's own choice
  for when it's back on. Like Show Next Steps, it waits for Apple's developer tools. It registers Let It Deploy
  (`sessionSwitches`, at the foot of a session's mode menu, which the core keeps: Allowed) and the words a session
  asks with (`sessionAsks`: `put-in-place` and `status`).
- `app/Deploys.m`: the commands you've saved, by project, in Whozmove's own folder (`deploy.json`), never in the
  project; the one it suggests, from the project's own files; running one detached with a log, noting the commit it
  starts from and how many files aren't committed (`BuildNow`); the port each checkout's build gets in $PORT
  (`ports.json`, `DeployPort`); each folder's last run, and while it runs, what its process group listens on, noted
beside it (`NoteRunUp`: its members, and `up`, its port, once it listens), from app/shared's `GroupMembers` and `ListeningOf`; and each project's build in place (`in-place.json`: the last run that went through, from whichever checkout, and the one before it), which
  `DeployModule.m` offers other modules (`BuildsInPlace`, contracts/Module.h).
- `app/DeployMenu.m`: the menu behind the round button: what it runs, changing or forgetting that, passing on it,
  stopping a run, the last run's log, and the checkout's sessions that may ask for Deploy, with Not This Time for a
  deploy one asked for that's waiting, and Don't Deploy for your press kept while an agent works.
- `app/DeployAsks.m`: what a session that may deploy asks, answered in a line (`ask-panel.sh put-in-place [folder]`
  keeps its ask, a newer one in the same folder replacing it; `status [folder]` says how that folder's deploy stands),
  for its own checkout only, the one its row is about, named or not (a folder named is checked with `DeployCheckoutIn`,
  as the worktree names the repo and the repo names it back, so a refusal says why), and each second, each ask waiting
  run once nothing holds it up there (`AskWaits`), or, for a build of its checkout that's up, restarted as Restart
  does (`restartAsked:`), or dropped once its switch has ended, its session has gone, its
  session's row is about another checkout, or a deploy has run there since. Asks are kept in memory only, one per
  folder.
- `app/DeployKept.m`: your press of Deploy while an agent works in the checkout, kept in memory only, one per folder,
  and each second run as a press runs once nothing holds it up (the port checked, what the command runs checked), or
  dropped once its session has gone, its checkout has, the project's command has changed or been forgotten, Deploy is
  hidden, a deploy has run there since, or Don't Deploy, in Deploy's menu.
- `page/deploys.js` (whether a row has the round button, how it looks, a build that's up and its address, and the
  set-up card: plain functions), `page/deploy-row.js` (the button, the address, the line and the card on a row; the
  button is an ask to try's one action, `askAct`, and isn't on a row asking anything else) and
  `page/deploy.css` (a build that's up: the ring closing, and its address coming in). `module.json` lists them for
  tools/page.sh.

tests/rows.sh checks what it suggests for sample projects and how their last runs read (`--print-deploys`), and what
the set-up card is told sample commands really run (`--print-deploy-checks`). Its own tests (tests/test.sh) check Let It
Deploy with two stand-in sessions (`--print-deploy-asks`): the switch's menu line, each ask's answer, the waits, when
the switch ends, and `ask-panel.sh` over a real socket, from inside a session and from outside any; and the build in
place, from runs in a real repo and its worktree (`--print-deploys`); and real runs there (`--print-builds-up`): each
checkout's own port, a command kept from running once what it runs has changed since it was confirmed, a confirmation
of what the card showed before a change not saved, and an older command confirmed once more; and stand-in servers on
a block of free ports: side by side, on every address, on a port of their own, on two, never listening, one its shell
leaves running, which Stop Deploy stops by its pid, a process that joins its group after its shell has ended, which is
never noted or stopped, and one that ignores being told to end, made to 2 seconds later; and Install First, with the
install each lock file gets, and Install and Deploy run with a stand-in npm in the throwaway home, never while an agent
works there. tests/rows.sh checks what
the card is told a command runs for sample projects: npm's start, bun's bare script names, scripts that run other
runners, Makefiles with includes, GNUmakefile first, files run, runners and make pointed elsewhere, and a package.json
that's a pipe, never read.

## For other modules

`BuildsInPlace` (contracts/Module.h), found with the core's `moduleThat:`: `buildInPlaceFor:` a project (its main
checkout, or its folder outside git) gives what Deploy last put in place there, `{folder, commit, uncommitted, at, by,
before}`, as plain data, from what Deploy last read, so it never waits. Whether a commit is in that build is the
reader's to ask git, in the project's main checkout, which has a removed worktree's commits too.

## Between the page and the app

- The page sends `deploy` (`{sessionId}`), `deployCard` (`{sessionId, act}`: a press on Deploy's card for the row's
  folder; the app finds every port itself), `openAddress` (`{sessionId}`: the app makes `http://localhost:<port>` from the
  port it read the row's folder's run listening on, never from the page, and opens it in the app that opens web
  pages), `openDeployLog`, `copyInstall`, `checkInstall` and `stopDeploy` (`{sessionId}`: from the card a run has to
  say; the app copies, or works out what runs for Install First's second step, the install it finds from the
  checkout's lock file (`DeployInstallWords`, fixed words), never text from the page), `installAndDeploy`
  (`{sessionId, words, hash}`: what that step showed, which the app checks is still what the install runs),
  `saveDeployCommand`
  (`{sessionId, command, deployNow}`), `checkDeployCommand`
  (`{sessionId, command}`: a command on the set-up card, about to be confirmed) and `stepMenu` (`{step: "deploy",
  sessionId, x, y}`: its menu).
- The app calls `setDeploys({projects, folders})`, `openDeploySetup(sid, then)` and `deployChecked(sid, {command,
  production, runs, cut, files, unsure, others})`. A folder has `port`, the one a deploy there gets in $PORT; its run has `by` when a
  session asked for it, and `port` when it was given one; and a folder has `asked`, `{by, waits}`, while a deploy a session asked for waits there: the row's note says so (`deployNote`).

## Rules

- Deploy runs only what you confirmed. A project's command is saved only through the set-up card's two steps, in
  Whozmove's own folder (never in the project, which an agent or a clone could change), and runs only when you press
  Deploy, or a session you turned Let It Deploy on for asks for it (below), the same way, the same command. Install
  First runs, before it, only the install the checkout's lock file names (`DeployInstallWords`: fixed words, never
  text from the project), on your press of Install and Deploy alone, never from an ask or a kept press, and only as
  its card showed it: what that install runs (the project's own install scripts, its lock file, the runner's settings)
  is followed and fingerprinted as a confirmed command is (`DeployInstallCheck`), and checked again just before it
  runs, and if it has changed, nothing runs and the card shows it again. A
  suggestion never runs by itself, and none is made that looks as if it could reach production, judged by
  what it really runs (`CheckDeploy`: the one list, which the set-up card asks the app about too).
- All that decides what a command runs (`WhatRuns`: each package script it names, with pre- and post- scripts for every
  runner, npm's start, test, stop and restart and an install's scripts, and the scripts those run, up to 6 deep, with
  package.json checked whole whenever a runner is named, and what the runners read besides (.npmrc, .yarnrc,
  .pnpmfile.cjs, yarn's .pnp.cjs and .pnp.loader.mjs, and bunfig.toml, in the package's folder and the checkout's top;
  .yarnrc.yml in each folder from the package's up; pnpm-workspace.yaml at the top; and the files those name to run:
  the yarn that yarnPath names, yarn's plugins, bun's preloads), and for an install, the lockfile; the Makefile make would read, in make's order, and every file
  it includes; each file in the checkout it runs, sources, or gives an interpreter, and what `sh -c` runs; each from
  the folder it runs in, after a cd, pushd or make -C, a runner's package.json being the nearest at or above it, as
  the runner finds it; each file by the SHA-256 of its bytes, so one that isn't text
  is checked too) is kept as its SHA-256 when you confirm it
  (`runsHash`), only if it's all still what the card showed for that row and command (kept in
  memory as the card was told, in full), and checked in the checkout before every run: changed since, by a branch or an
  agent, it doesn't run, and the set-up card shows it again for your press (a session's ask is refused). A command
  confirmed before this was kept needs confirming once more the same way, unless it runs nothing that's checked. What
  it can't follow or can't check (a runner pointed at another folder or package, a cd out of the checkout or to a
  folder named by a variable, a cd inside ( ) or in a sourced script, a script the command names that isn't in the
  package.json found, a package.json above the checkout, a runner's word it doesn't know, an include named by a variable, a file it depends on
  that's outside the checkout or isn't a plain file) the card says, and it's part of what's kept, so it's never passed
  over; and the programs it runs whose own files decide what they do, what the files it gives node or python load,
  what an install's packages' own install scripts do, and any other file a package runner may read, which aren't
  checked.
- It reads a project's files only if they're regular files inside the checkout (`Look`), opened so as never to block,
  and checked again once open (`OpenFile`): never a pipe or a device, which could hold its queue. A file's bytes are
  read a piece at a time to check it, however big; its text, up to 1MB, only to follow what it calls.
- A command confirmed on the card that says so gets its checkout's own port in `$PORT` (`ports.json`: the project's
  first, 3000, for its main checkout, and the next one no other checkout of any project has for each worktree, kept,
  and given back once the worktree has gone); the port the card showed is kept as it's confirmed. One confirmed before
  runs exactly as it was confirmed, without one.
- The run goes detached (`SpawnDetached`, in a session of its own, with signals as a new program has them and no
  descriptor of the panel's), through your login shell started as your terminal starts it (`-l -i`, job control off so
  Stop Deploy reaches all it started, and a trap so the shell itself ends on it), from a clean environment
  (`DeployEnvironment`: nothing of the panel's, which is an agent's if an agent's build restarted it, so no
  `CLAUDECODE` mark either), so it survives the panel restarting (launchd stopping the login item takes its process
  group too) and `build.sh` treats it as yours.
- A run counts as running for as long as its own process does (pid and start time), whatever its files say, so a pid
  handed to another process later can't hold Deploy up, and a stopped run can't be started again over itself; or, once
  its shell has gone, for as long as a member of its process group noted while it ran is still the process it was (a
  server its shell left running).
- A run's process group is read only while its shell is surely its own (pid and start time). Once the shell has gone,
  a server that left the group (a daemon's setsid) can leave it empty and its number could be anyone's, so no new
  member is noted, and what it listens on is read only from the members noted before, each while it's still the
  process it was.
- Before a press runs, the port the build will listen on is checked (`portCheckIn:`): its checkout's own, or for a
  server that picks its own port (a run of the same command listened somewhere other than its `$PORT`) that one, or for
  a command confirmed before ports another of the project's builds' running now. What holds it is found among this
  user's processes (`PortHolder`, named only by the name macOS keeps for it). Another of Deploy's builds (its shell, or
  a member noted, by pid and start time): a card asks to replace it. Anything else: a card names it, and the listed
  session it descends from, counted only if that session's process started before it, and is never stopped. Use Port
  finds the next free port again as it's pressed (`NextFreePort`: none in the record, none listened on), shows the card
  again if that has changed, and keeps it for the checkout (`KeepDeployPort`); Stop It and Deploy stops the other
  build, then deploys once it has ended, with the waits checked again.
- Stop Deploy signals the run's process group only while its shell is surely its own. Once the shell has gone, it
  signals only the members noted while the run went on, each while it's still the process it was. What it makes stop
  2 seconds later is only what was there as you stopped it (the members noted, and while the shell was its own, all
  its group had then), one by one, each still the process it was: never a later run's or a stranger's.
- A server's run (one that's been seen listening) is the project's build in place once it's up; once it has ended,
  whatever its shell's status, it didn't go through.
- It never starts while the row's agent works or asks, or another session's agent works in the same folder (as its
  own, or where the turn it's on has edited files; one waiting on you doesn't count, as it may wait for days)
  (`WhyStepsWait`, in parts/work, and the button is dimmed): what goes in place shouldn't be half-way through a
  change. The next steps wait the same way; while the row's own agent is at work, the work line they're on isn't there
  (`workHTML`).
- A session asks for Deploy only with Let It Deploy on for it, which only your press in its mode menu turns on. It lasts
  for that session's process, and is given for its project and the command you confirmed there: it ends once either
  changes, or once Deploy is hidden. The ask runs that command from the session's own checkout, the one its row is
  about, where it shows while it waits (an ask naming any other folder is refused), as your press would, once no other
  session's agent is at work there (not waiting for the asking session's own turn to end, as it asks once its change is
  ready), no run is going, and you've been off the panel 5 seconds; just before, everything is checked again, and the
  command must still be the one the switch was given for. Which session asks is found from its process, never from
  what it sends. What you've allowed is kept in Whozmove's folder, where any program running as you could change it, as
  it could `deploy.json`.
