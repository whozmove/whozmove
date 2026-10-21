# Working on Whozmove

A floating macOS panel listing every Claude Code session on this Mac (Claude Desktop and terminal), with
what each is doing, whose move it is, and controls to answer prompts, change model/effort/mode, compact
and jump to a session. **README.md** says what it does and how to install it; keep it current: every
user-visible change gets a line there. This file is how it's built and how to work on it. Everyone taking
part, in issues, pull requests or anywhere else, follows the [code of conduct](CODE_OF_CONDUCT.md).

## How the pieces fit

Whozmove's own folder, `AppDir` below, is `~/Library/Application Support/Whozmove/`: kept out of `~/.claude`
so other agents can be added beside Claude later.

```
Claude Code ──hooks──▶ AppDir/sessions/<id>.json   (last prompt/reply, live step, outcome)
            └─────────▶ AppDir/asks/<id>.json        (a permission prompt waiting; answer in <id>.answer.json)
~/.claude/sessions/<pid>.json, transcripts, Claude Desktop's files, git, gh
        │
app/ (native shell) ── every 1s: update(rows, now) ──▶ panel/ (the whole UI, in a WKWebView)
        ◀── webkit.messageHandlers.panel.postMessage({type, …}) ──
```

- **`whozmove-claude.py`** (the Claude Code module's, in `modules/claude-code/plugin/hooks/`, as is the next): async
  hook on UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, Notification, Stop. Writes the session's state
  file under a `fcntl` lock, atomically. Must be fast and must never disturb a session: everything is wrapped so it
  always exits 0. Works out the live line, `stageAt` (when a step or the turn last started or ended),
  `turnReached`/`outcome` (how far a turn took the work), `workSteps` (built/tested/validated) and `audit` (local code
  review findings).
- **`whozmove-claude-permission.py`**: synchronous PermissionRequest hook (timeout 3600). Leaves the
  request for the panel and waits for its answer, while Claude's own prompt stays usable; whichever is
  answered first wins. Steps aside at once when the panel isn't running, for sub-agents and non-interactive
  sessions; steps aside later when the call's result shows up in the transcript (settled in Claude) or the session
  ends. Only ever allows once, never "always allow". A plan (ExitPlanMode) is never allowed from the panel, only sent
  back with your notes or stopped: Claude Code ignores a hook's approval of a plan, so approving stays in Claude's own
  prompt. All of this is deliberate.
- **`modules/claude-code/plugin/`** (`hooks/hooks.json` and `.claude-plugin/`): the two hooks as a Claude Code plugin,
  `whozmove` (in a marketplace of the same name), which is all Claude Code needs to run them. `install.sh` copies it
  into `AppDir/plugin` and adds it from there with `claude plugin`, so installing it never edits `settings.json`.
  Claude Code runs its own copy of the plugin, made per version, so each copy gets a version named after the hooks'
  contents (`modules/claude-code/plugin.sh`): a changed hook gets a new one, and Claude Code takes it once told
  (`claude plugin update`).
- **`build.sh`** and **`app/swap-in.sh`**: `build.sh` compiles, records where the build came from in its
  `build.json` (checkout, branch, commit), and copies `swap-in.sh` into it. Then `swap-in.sh` puts the build and its
  hooks in place, and `swap-in.sh --restart` restarts the app. An agent's build (one with Claude Code's `CLAUDECODE`
  mark, which a `!` command in Claude Code has too) never puts the hooks in place, and once Deploy is set up for
  Whozmove in the panel (its command is `./build.sh --now`), it stops after compiling while the panel runs with
  Deploy's button showing, and leaves putting it in place to Deploy, as for any project.
- **`app/`**: Objective-C, ARC, no Xcode project: `tools/compile.sh` compiles every `.m` in it and in `modules/` (see
  Modules below). It holds the core (`core/`), what modules fill in (`contracts/`) and the helpers that know no app
  (`shared/`); everything else is a module. One file per job:
  - `main.m` starts the app, or runs one of the print modes the tests check. `AppDelegate` makes the page, the panel's
    window, the pawn and the core, and starts them.
  - The core's pieces each keep only their own state: `Page` (loading the page; every call into it), `PanelWindow`
    (FloatingPanel, DragStrip, size, hover, growing beside the list to fit the reader, and back), `MenuBar` (the pawn,
    grouping, Next Steps' switches, and the modules' items), `Rows` (the rows read once a second, each module adding its
    part), `Focus` (the session you're on, when you last looked at each, and opening a session from its row), `Send`
    (words into a session, and why they can't go in now), `Work` (who's at work in a checkout), `Builds` (the running
    build, for the header) and `Printing` (what the print runs share).
  - The agent that runs the sessions is a module: `claude-code` (its sessions and its hooks' records, what's new in each
    transcript, a session's details, the words of the panel's commands and what their results say, typing into a
    session's prompt while keeping its draft, your plan's usage asked of `claude`, folder trust, a new session's
    command, and its hooks plugin).
  - The apps sessions run in are hosts, each a module too: `ghostty` (finding a session's tab, typing into it, which tab
    it shows), `claude-desktop` (its conversations, its message box, new conversations, "Switch model?") and
    `terminal-app` (macOS's Terminal, which only runs a command: Sign in, on a Mac without Ghostty). A session in any
    other terminal app opens by bringing that app forward. Another terminal is one new module that fills in the host
    contract.
  - Each feature is a module: `island` (`Checkouts`: git status, each checkout's base branch and new files, which of its
    files are staged, and its extra stage, with the file lists and commit subjects its menus show kept here, not sent
    with the rows; `Stages`: the extra stage, the command a repo's git config names, run only once you've allowed it,
    your answers, and its own steps, docs/reference/stages.md; `NextSteps`: the menu behind each stage, and the commits
    stage's card; `PullRequests` and `GitHub`: the PRs, from gh), `deploy` (`Deploys`: each project's deploy command,
    the one it suggests, running it detached with a log, each folder's last run; `DeployMenu`: its round button's menu),
    `changes` (`Changes`: what isn't committed in each checkout, from git, with each changed line credited to the
    session whose edits (or its sub-agents') match it, its shell commands' too (as its agent records them), else outside
    the sessions: a row's own numbers, and the changes view, a session's own sent with only its own parts, built off the
    main thread; and what the commits not on GitHub yet changed, worked out ahead while there are some, so the island's
    commits stage opens them at once; `Editors`: the editor a changed file opens in, offered from the editors it knows,
    the ones installed, chosen once, kept, changed from the pawn menu's Open With), `reader` (what a session wrote, on
    the page only), `usage` (`Usage`: your plan's usage, asked of the agent every few minutes, for the strip; Sign in),
    `starts` (`Starts`: a new conversation from the panel's card, the folder's trust checked, the session opened with
    your words, and watched for until it's listed; `Worktrees`: a worktree of its own for one; `Shortcut`: ⌃⌥N),
    `commands` (the model, effort and mode menus and the Compact card, from the menu to the command's result) and
    `spotify` (the now-playing strip, with its lyrics from LRCLIB, which open beside the list, and Spotify's token).
  - The data has a shape: `Row` (app/contracts) is one listed session, field by field as **`docs/reference/rows.md`**
    describes it (the contract between the hooks, the app and the page; `tests/rows.sh` keeps the two in step).
    `Command` (the commands module's) is one slash command sent from the panel, with its stage (asking, going in,
    waiting, done, abandoned), and `Reason` (app/contracts) names why keys can't go into a session right now.
  - Plain functions with a header each, in `shared/`: `Log`, `Files`, `Processes`, `Git`, `Text`, `AppleEvents`,
    `AppleScript`, `Accessibility`, `Links`, `Menus`.
  - Nothing slow runs on the main thread. The sessions' files, transcripts, git and gh are read on serial queues,
    and Ghostty is asked which tab it shows on one, and what they find is handed to the main thread, where all the
    state is kept (Ghostty's answer is matched to a session there, from what's already been read). The one thing
    read from both sides is Claude Desktop's log (`DesktopLog`'s `catchUp`), and they take turns.
- **Facts**: everything Whozmove relies on about another program that it could change is in that program's module
  (`ClaudeCodeFacts.h`: where Claude Code keeps things, its command, the model and mode choices; `ClaudeDesktopFacts.h`,
  `GhosttyFacts.h`, `SpotifyFacts.h`, and beside it `LRCLIBFacts.h`, for the lyrics' web service), and what it knows of
  the editors Open With offers is in the changes module's
  `Editors.m`. The
  versions they were last checked with are in the README. When one of them changes, the fix goes there.
- **`panel/`**: HTML, CSS and plain `<script>` files: no modules, no build step, no libraries.
  `update()` → `render()` → `morph()`.
  - `panel.html` is the markup, and loads the rest in order: `styles/` (`tokens`, the panel's colours, text sizes and
    corners by name; `base`, `rows`, `cards`, `reader`, its frame; the modules' styles; and `motion`) and `scripts/`, the
    modules' scripts last but for `panel`. `tools/page.sh` lists the modules' at the two lines the page marks for them.
  - `scripts/`, one job each. The page's core first: `util` (the bridge's send, storage, escaping, measuring text),
    `state` (everything the page keeps between rebuilds, in one object), `modules` (what the modules plug into the page
    with: see Modules below), `fresh` (whether a card or button has only just been shown, and a request answered here),
    `whose-move` (what each session is, where its row goes, and which session speaks for each checkout: plain
    functions, checked by `tests/panel.sh`), `icons`, `markdown` (plans and notes as HTML, everything escaped:
    a plain function), `builds` (the header's name for the running build), `morph` (the animation), `strips`
    (changing a strip's text, and easing, growing and folding it, for any strip under the
    list), `rows` (a row's template, with its places for the modules' parts, and the group and project headers), `hover`
    (what's pointed at, and the card something pointed at shows), `input` (presses, typing and the keyboard), `reader`
    (the reader beside the list, which its modes fill, each about a session, or, like Spotify's lyrics, about none),
    and `panel` (`render`, and the functions the app calls on the
    core). Then each module's, from its `page/`, one per job, each plugging into the core as it loads: Claude Code's
    `agent` (what a Claude Code session's model, mode and context mean) and `requests` (its requests, questions and
    plans on a row); Claude Desktop's `switch-model` (Claude's "Switch model?"); the commands module's `commands` (the
    model, effort and mode labels, the context ring and the Compact card); the island (`stages`: its stages, `stagesOf`,
    plain functions; `island`: the capsule, its gauge and how it moves; `island-files`: the gauge's file lists;
    `island-steps`: the commits stage's card; `stage-trust`: the extra stage's question; `prs`: the pull requests and
    their card); Deploy (`deploys`: whether a row has its round button, how it looks, and the set-up card, plain
    functions; `deploy-row`: the button, the line and the card on a row); the reader's `writings` (what a session wrote:
    its tag, and the reader's `writings` mode, where a plan is sent back or stopped); `changes` (a session's numbers,
    their card's parts of the branch, how the changes view groups files and lays lines side by side: plain functions)
    and `changes-view` (the numbers, their card, and the reader's `changes` mode); the usage strip (`usage`: what it
    shows, plain functions; `strip`: drawing it, folding it into one row and back;
    `waits`: its wait styles, chosen by name, each a file of its own, `wait-vine` the first, whose shape and reset are
    plain numbers too); and `starts` (the card for a new conversation, which opens under the header, the pending row a
    start shows as until it's listed, and the card turning into that row and moving down to its place; `start-words`:
    what the card reads in your words, @ for the project and # for where in it, and a new worktree's name, plain
    functions). The strip isn't in the list, so it's never rebuilt: it's built once, and only its text and widths
    change. Last, Spotify's: `now-playing` (what the now-playing strip shows, plain functions), `lyrics` (a song's lines
    and pauses from its LRC, and which shows when, plain functions), `np-strip` (drawing the strip, its words rolling in
    place, and its presses), `lyrics-view` (the one timer that changes the lines, and the reader's `lyrics` mode) and
    `spotify` (what it plugs in, and the functions the app calls).

Bridge, page → native (`type`): `height`, `open`, `pick`, `compact`, `switchAnswer`,
`answerAsk`, `openPR`, `keyboard`, `badge`, `stageMenu` (a stage of a row's island, `{stage, step, count, pr}`: the app
builds its menu and has the words its steps ask), `stageCard` (the commits stage pointed at, `{stage, step, count}`:
the app sends its menu's contents back for a card; asked with `quiet` with every update, only when they've changed) and `stageStep` (a step pressed on that card, `{from, step}`: the
app asks it only if the card offers it now), `stageTrust` (your answer about an extra stage's command,
`{command, allow}`), `stepMenu` (Deploy's menu, as `step: "deploy"`), `deploy`, `checkDeployCommand` (a command on
Deploy's set-up card, about to be confirmed), `saveDeployCommand`, `usageSignIn` (the usage strip's Sign in),
`expand`
(the reader's size, `{width, height}`: the panel grows beside the list to fit it, and is asked again as what's shown
changes) and `collapse` (back to the list), `readWriting` (one of a session's writings, `{sessionId, id}`),
`readChanges` (a session's changes for the changes view, `{sessionId, scope}`, asked for ahead as its numbers or its
island's commits stage are pointed at, so the view opens at once, `scope` being `session` or `branch`, of
what isn't committed, or `commits`, the commits not on GitHub yet),
`openFile` (one of them in your editor, `{sessionId, path, line}`, with `editor` when it was just chosen), `start` (a
new conversation, `{startId, folder, app, words, sessionId, trust, target}`: `sessionId` is the one the page
chose for a terminal start, `trust` your yes on the card, `target` where in the
folder's repo when not its own folder, `{kind: open, path}`, `{kind: branch, name}` or `{kind: new, name, base}`),
`checkFolder` (whether Claude may work there), `listBranches` (what a folder's repo has, for the card's #),
`checkWorktreeName` (whether a new worktree can be made, `{folder, name, base}`), `startMenu` (the card's small menus,
`{kind}`: `app`, `places` with `repo`, or `choose`), `spotify` (the now-playing strip's presses, `{action}`:
`playpause`, `next`, `previous`, `seek` with its `fraction`, `open` or `settings`; `folded` once it has folded away;
`collapsed` `{on}`; and `lyrics` `{on}`, your answer about lyrics) (each routed by its type to the core or the module
that answers it: `Modules`).
`answerAsk` for a plan carries `message` (your notes) or `stop`. Native → page:
`update(rows, now)`, `setRoom`, `hoverAt`/`hoverEnd` (with `still` while the pointer is off the panel without having
moved there: the panel's edge went past it, or one of its menus closed there; `hoverEnd` comes again once it moves),
`keyboardGone` (the panel no longer has the keyboard), `setGroupBy`, `toggleCollapsed`, `stepNote` (with `quiet` when
it says how something went that worked), `setRunningBuild` and `setSwitches` (the core's, in
`panel/scripts/panel.js`); `readerOpened(side, width)` (which side the list stays on, and the reader's width) and
`readerClosed` (in `reader.js`); and each feature's, in its own script: `askSwitch` (`switch-model.js`),
`compactNote` (`commands.js`), `setDeploys`, `openDeploySetup` and `deployChecked` (what that command really runs,
`{command, production, runs, more}`) (`deploy-row.js`), `setCheckoutFiles` (each checkout's files by kind, `{staged,
partly, unstaged, new}`, the first 100 of each, sent only when they change; while its extra stage holds something and
names the files outside it, only those) (`island-files.js`), `showStageCard(sid, {heading, items, more, steps,
enabled, wait}, step)` (`island-steps.js`), `setUsage` (your plan's usage: `{state, plan, session: {used, resetsAt},
week, limits: [{kind, percent, severity, resetsAt, model}], extraUsage, checkedAt}`, where `state` is `ok`,
`signedOut`, `other` or `none`) and `previewWait` (Working on Whozmove's Preview the Wait) (`strip.js`), `openStart`
(⌃⌥N, New Conversation), `folderChecked` (`{trusted}` or `{gone}`), `startUpdate` (how a start went: `{sessionId}`
once it's listed, `{note}` while it waits on you, `{why}` if it didn't start), `startProject` (a folder picked from the
card's chooser), `branchesListed` (`{here, worktrees, branches, base, folder, folderPath}` or `{none, where}`),
`worktreeNameChecked` (`{path, where, name, base}` or `{why}`), `worktreesMoved` (a repo's worktrees go somewhere else
now), `startAppChosen` (from Start's menu) and `setStartOptions` (`{terminal}`, the terminal a start can open in, or
null) (`starts.js`), `setNowPlaying` (the song Spotify is playing, or null) and `setLyrics` (what's known of its lyrics:
`{state}`, and for a song's `track`, with `lrc` or `plain` once found, or `none` or `failed` when there are none to be
had) (`spotify.js`),
`showWriting(sid, id, {text} or {missing})` (`writings.js`), and `showChanges(sid, scope, {scope, v, files, complete}
or {missing})` (each file `{path, status, binary, saved, complete, counts: {who: [added, removed]}, hunks: [{oldStart,
newStart, lines: [[sign, text, who]]}]}`, with `cut` past 30,000 lines) and `setEditors({choice, apps: [{id, name}]})`
(`changes-view.js`).
`setDeploys` gets `{projects: {project: {command}}, folders: {folder: {suggested, at, skippedAt, run}}}`, where a
run is `{startedAt, running, ok, finishedAt, lastLine, stopped}`; a project is a repo's main checkout (or a folder
outside git), saved by its real path (symlinks resolved, as `build.sh` finds it), and a folder is the checkout a
session runs in (for one that runs outside any, the one it last edited files in).

## Modules

Each outside program Whozmove works with, and each feature, is a module in a folder of its own, so a change in one
program is fixed in its module alone. The usage strip, the changes view, the reader's own parts, new conversations and
Spotify's strip keep their styles in their modules; the row's and the cards' are the core's (`panel/styles/rows.css`,
`cards.css` and `motion.css`: the island's, Deploy's and the requests' among them).

- **`app/core/`** is the panel itself: start-up (`AppDelegate`, `main.m`), the registry (`Modules`), the services a
  module gets (`Core`: the page, the window, the menu bar, the rows, the hosts, the agents), `Rows` (the rows read once
  a second, each module adding its part in the phase it belongs to, and sent), `Focus` (the session you're on, when you
  last looked at each, and opening a session from its row), `Send` (words into a session through its host and its
  agent, and why they can't go in now, worded as the menus, cards and steps say it), `Work` (who's at work in a
  checkout, which the island's steps and Deploy wait for), `Page`, `PanelWindow`, `MenuBar`, `Builds` and `Printing`
  (what the print runs share: the rows read, and read once what's worked out alongside them has come back).
  **`app/contracts/`** holds what modules fill in
  (`Module.h`, `Host.h`, `Agent.h`) and what they pass (`Row`, `Reason`), and **`app/shared/`** the helpers that know no
  app (`Log`, `Files`, `Processes`, `Git`, `Text`, `AppleEvents`, `AppleScript`, `Accessibility`, `Links`,
  `Menus`).
- **`modules/<name>/`** is one module: `app/` (its native code), `page/` (its scripts and styles), `module.json` (its
  page files in order, for tools/page.sh), `tests/` (its `test.sh`, which tests/all.sh runs, and what it
  compares with) and `README.md` (its pieces, the facts about its program, its messages, its rules). What the tests
  share is in tests/lib.sh: the app built once per run, `in_minutes`, and `page_cases`, which runs a file of the
  page's cases as tests/panel.sh runs the core's (tests/page-harness.js has their stand-ins and helpers).
- A module's face is a class that adopts `Module` (app/contracts/Module.h). The core finds it at launch, so nothing
  lists it. It names the page messages it answers (each type has one; two modules answering one fail the tests), its
  items in the pawn menu and where they go, its print modes, its part of each tick, its part of each row, in the
  phase it belongs to (the checkout's state, the session's work, its agent's details, and once the rows are whole), and
  whether it's still working something out off the main thread, which a print run waits for. Setting up only prepares
  data, since the tests' print runs make every module too; windows, observers and timers start in `launch`.
- An app sessions run in is a host: a module that adopts `Host` too (app/contracts/Host.h), and says what more it can
  do by the protocols it adopts beside it: `TypingHost` (a session's tab found, and keys typed into it), `CommandHost`
  (a command run in a new tab) and `ConversationHost` (an app that keeps sessions as conversations of its own, Claude
  Desktop's). The core finds the host a row runs in (`hostOf:`), so nothing else asks which app it is. On the page,
  each host names its rows (`core.hosts`: its icon, its name, "Open in … now").
- The agent that runs the sessions is a module that adopts `Agent` (app/contracts/Agent.h). As the rows are read, on
  their queue, it lists the sessions it runs; the hosts add what they know; it adds what its hooks recorded and the
  requests waiting; the core adds each session's checkout. It gives each session a title (a terminal finds its tab by
  it) and names the marks it puts on its commands. What more it does, it says by the protocols it adopts beside it,
  one for each part of the panel that uses it: `AgentWork` (what a session edited, and its PRs), `AgentCommands` (its
  menus' choices, the commands that make them, and whether one took), `AgentPrompt` (a command typed into a session's
  prompt while keeping your draft, and when that's safe), `AgentUsage` (your plan's usage) and `AgentStarts` (a new
  session's command, and folder trust). The core finds the agent that runs a row (`agentOf:`), so nothing else reaches
  into one: there's one, Claude Code, for now.
- On the page, a module's scripts only register as they load, in the lists panel/scripts/modules.js keeps, and the
  core runs them; a module never calls another's functions or reads its state. Its own state goes on the page's state
  with `moduleState`, which refuses a key another has. What it can plug in:
  - its start-up, and its part of each update, each fold to the header and each rebuild of the list (rows the app
    hasn't listed yet, what it works out before the list is drawn, and after);
  - a row's parts: its first look at the row, its parts in the row's places (`core.slots`: after the name, after the
    time, the end of the details' first line, under it, the agent's setup line, the end; a project's header), its card
    under the chat (`core.rowCards`, the most pressing showing, each the others' place when they want it), and the
    line under the details;
  - presses, typing and Return in its boxes, the boxes that take the keyboard, what the pointer can point at, what it
    does with what the pointer is on, and the card something pointed at shows;
  - the strips above or under the list and what hangs below it (for the panel's height), the reader's modes and their
    presses, its lines' motion (`core.lines`), the bits that cross-fade, what a step's note settles, and what's
    forgotten a minute after a session goes;
  - what an agent's details mean (`core.agent`), for the parts that show them.
- `tools/compile.sh` is the one compile line, for build.sh, the tests and CI. Only `app/` and its `core`, `contracts`
  and `shared` folders are on its include path, so a module can't import another module's header, nor the core a
  module's. `tools/page.sh` puts the page together.
- A module keeps the facts about its own program (Spotify's are in modules/spotify/app/SpotifyFacts.h, Claude Code's
  in modules/claude-code/app/ClaudeCodeFacts.h).
- Preference keys keep their names: build.sh reads `showNextSteps` and `showDeploy`, and every switch keeps its choice
  across launches.

## Build, install, debug

```bash
./build.sh            # compiles (clang -Wall), signs, puts ~/Applications/Whozmove.app and the hooks in place,
                      # restarts it; an agent's only compiles, once Deploy is set up for Whozmove (see below)
./build.sh --now      # the same, as Deploy runs it (from an agent, it still only compiles)
./install.sh          # adds the hooks as a Claude Code plugin, sets up the login item (LaunchAgent)
tests/all.sh          # every test below, the app built once for all of them (~80s)
tests/rows.sh         # the rows the app builds for a sample home, its mode menus' Shift+Tab counts, the menus' why
                      # nots, how a command's result is read and the macOS permissions the README names, compared
                      # with tests/rows.expected.txt
tests/panel.sh        # the page's labels, colours, sorting, row HTML, the usage strip and the vine's reset (macOS's
                      # jsc, in UTC), vs tests/panel.expected.txt
tests/build.sh        # build.sh against a throwaway HOME: when a build waits and when it goes in, swap-in.sh
                      # putting it and its hooks in place, and what it restarts, vs tests/build.expected.txt
tests/checks.sh       # the checks that keep modules apart (prints only problems): no page function in two
                      # scripts, every page call and message has its other end, no module imports another, no
                      # class styled on its own by both the core and a module (or two modules), each module's
                      # README with its pieces and its rules, and no colour, text size or corner written out in
                      # a style that tests/styles-by-hand.txt doesn't list (--update takes off the ones gone)
modules/*/tests/test.sh  # each module's own tests, with its own recorded outputs; Claude Code's run both hooks against
                         # a throwaway HOME, compared with modules/claude-code/tests/hooks.expected.txt
```

- After editing anything in `app/`, `modules/`, `panel/` or `icon/`: `./build.sh`. After editing a hook or its
  `hooks.json` (modules/claude-code/plugin/): `./build.sh` too, in your terminal (an agent's build leaves the hooks),
  once the plugin is installed (`./install.sh` the first time). Sessions run Claude Code's copy of the plugin, made
  from the one in `AppDir/plugin`, so a hook you're editing here never runs in them half-written, and a change reaches
  only sessions started after it.
- With Deploy set up for Whozmove (press Deploy on one of its rows once and confirm `./build.sh --now`, the
  suggestion), an agent's `./build.sh` only compiles, and Deploy on a row puts that checkout's build in place when you
  press it. Tick Show Build in Header (hold ⌥ as you open the pawn menu: Working on Whozmove ▸) and the header says
  which build you're running.
- `--update` on any of them re-records its expected output after a change you meant; read the diff first.
- `tests/panel-cases.js` holds the page's sample sessions; add a case there, or in a module's own
  `tests/page-cases.js` when it has one, for any new label or rule.
- `Whozmove --print-rows` prints the rows the panel would get for the home folder in `$HOME`, as JSON, and
  quits: what `tests/rows.sh` compares. It never asks GitHub, so PRs show as UNKNOWN there.
  `Whozmove --print-mode-moves` prints, for each terminal session, why keys can't go into it now (or that they
  can) and the Shift+Tabs its mode menu would type; the same test checks them, because a wrong answer types
  into a session at the wrong moment, and a wrong count lands it in another mode. Both read files the whole
  Mac shares (Claude Code's managed settings) from that home folder too, so what they print never depends on
  the Mac they run on. `Whozmove --print-typing`
  prints the keys a command is typed with, through a stand-in terminal, and where typing stops once the
  session moves on. `Whozmove --print-why-not` prints what each session's model, effort and mode menus, its Compact
  card and its next steps would say about why nothing can go into it now, and `Whozmove --print-results <command>
  <transcript>…` what the panel takes each command's result in a transcript to say.
- `Whozmove --print-changes <sessionId> <scope>` prints what the changes view would be sent for that session in
  `$HOME`, its own changes (`session`) or the whole branch's (`branch`), each changed line credited to whoever wrote
  it; `tests/rows.sh` checks it for two sessions sharing a checkout.
- `Whozmove --print-deploys <folder>…` prints the command Deploy would suggest for each folder, and how its last run
  went as the page would be told; `Whozmove --print-deploy-checks <folder> <command>…` what the set-up card would be
  told each command really runs there. `tests/rows.sh` checks them against sample projects and runs.
- `Whozmove --print-usage <file>…` prints what the usage strip would take from each file as Claude Code's answer to
  the usage request, or as `claude auth status`'s, and where `claude` is looked for (`$USAGE_PATH` as the PATH);
  `tests/rows.sh` checks it against recorded answers. The print modes never run `claude` (the agent's `askUsage`
  answers nothing in a print run).
- To see the usage strip's wait and reset without a limit to wait for: hold ⌥ as you open the pawn menu, Working on
  Whozmove ▸ Preview the Wait.
- `Whozmove --print-starts` prints what sample starts would run (a terminal tab's command, Claude Desktop's link), and
  `Whozmove --print-trust [--trust <folder>] <folder>…` whether Claude may work in each folder, as the state file in
  `$HOME` says, recording your yes for one first with `--trust`. The starts module's tests check the first, and
  `tests/rows.sh` the second, against its sample home. `Whozmove --print-worktrees [--make] <folder> <name>…` says
  whether a worktree of the folder's repo can take each name, where it would go and what it would start from, and
  with `--make` makes each; the starts module's tests run it against a sample repo.
- Native log: `AppDir/panel.log` (`PanelLog`/`LogProblem`; `swap-in.sh` writes there too). NSLog output isn't kept.
- The UI has no automated test. To try it with sample rows, put the whole page together in a new folder with
  `tools/page.sh <folder>`
  (`panel/panel.html` alone is the page's core, without the modules), load that folder's `panel.html` in a browser (its list's column
  starts `--side` in, as the page is laid out with room for the reader on either side: set `--side` to `0` there), stub
  the bridge
  (`window.webkit = { messageHandlers: { panel: { postMessage: console.log } } }`) and call
  `update(rows, Date.now())` with rows shaped as `docs/reference/rows.md` describes. To skip the animations while you
  look, make them instant with `Object.defineProperty(calm, 'matches', { get: () => true })`.
- Try every change on the real app.

## Rules that keep it safe

- **Never touch your real sessions or data while testing.** Use a throwaway `HOME` (as the Claude Code module's
  tests do) and sample rows. Don't compact, change model, or type into a real session to test.
- **Never kill processes by name pattern** (`pkill -f whozmove`, `pkill python`): live permission hooks
  are holding permission prompts in your sessions. Find the exact pid, check it, kill that.
- **`~/.claude/settings.json` holds secrets.** Never log or paste its contents; read the keys you need with a
  JSON parser.
  The panel itself writes it only to put back `/model`/`/effort` defaults, key by key, via JavaScriptCore's
  JSON so the layout stays as Claude Code wrote it.
- **The panel must never take the keyboard.** `FloatingPanel.canBecomeKeyWindow` is `wantsKeyboard`, set
  only while one of the panel's own text boxes is clicked into (`keyboard` message), or while the new conversation
  card is open from ⌃⌥N or New Conversation, until it starts or closes. Clicking a row leaves
  the keyboard with Claude, which is what lets "open a conversation, type straight away" work. Don't
  synthesize clicks or move the pointer to focus things in Claude: it makes the mouse pointer jump. When another app
  takes the keyboard, the page lets go of the box that had it (`keyboardGone`): asking for the keyboard makes the panel
  key at once, so a box focused again as the list is redrawn would take it back.
- **Only the panel's own page talks to the app.** The reader shows a prototype a session wrote, scripts and all, in
  a sandboxed frame from its own text; `Page` ignores every message that doesn't come from the main frame, and lets
  the frame load nothing but that text. Keep both: a page Claude wrote must never answer a request.
- **A changed file opens only from its checkout's changes.** `openFile` names a file by its path within the session's
  checkout, and the app opens it only if that checkout's changes list it (`Changes`' `fileOf:path:`), in the editor
  you chose and nothing else.
- **Hover is pointer polling** (25×/s, `pollPointer`), not mouse events: a non-key panel gets no mouse moves.
  Clicks are handled on `mousedown`, not `click`: the list re-renders every second.
- **Typing into a session only when it's safe.** Ghostty: only while idle at its prompt with no request
  pending (`WhyNotTypeInto`), since a stray Enter would approve a permission prompt, and Shift+Tab would allow
  all edits. Claude Desktop: only while idle (`WhyNotSendTo`) and only if its message box is empty; text goes in
  through the Accessibility API ("Prompt" text area, Submit button), not keystrokes. The one exception is a
  Return when Claude shows no Submit button, and only while Claude is in front (`submit:` in
  modules/claude-desktop/app/DesktopMessageBox.m). A new conversation's first message is sent with Claude's Send
  button, never a key, only in the conversation Whozmove has just opened with your words, once Claude shows its page,
  and only while its box holds exactly those words (`sendFirst:` in DesktopNewConversation.m) and Claude shows the
  folder the conversation is for. Claude loses a folder that comes in its link, so the folder is chosen as you would:
  its environment pressed among the recent ones Claude's page lists, once, which environment is which folder read
  from Claude's own record and never written (`chooseEnvironment:`), or on Claude's older screen its folder button
  pressed and the folder picked from its Recent ones, by path, the one time its list opens (`chooseFolder:`); never
  "Open folder…" or a new environment. Claude can let a press go by while it gets the folder ready, so Send is
  pressed again, a few times, until Claude's log says it's starting the conversation or its box empties
  (`pressSend:`); the words are never taken out of Claude's box.
  The one key that goes into a terminal session while Claude works is the Backspace that takes out the filler of a
  next step's request (`WhyNotEditDraft`): Claude Code puts the stashed draft back the moment a message is sent, and
  there a Backspace only edits it. Never while Claude asks something or a request waits. A step's words are fixed
  in the app (`StepRequest`), or come from an extra stage you allowed (its `ask` steps); the page only names the step.
- **`/model` and `/effort` also save a default** for new sessions; the panel puts those settings keys back
  (`holdDefaults`/`releaseDefaults`). Keep that if you add commands.
- **Folder trust is recorded only for a folder you trusted on the card.** `~/.claude.json` holds your account and more:
  `Trust.m` (in the Claude Code module) reads only `projects[<folder>].hasTrustDialogAccepted` from it, with a JSON
  parser, and never logs it. `TrustFolder` writes that one key for that folder, under the lock Claude Code takes to
  write the file (the folder `~/.claude.json.lock`; one 10s old or more is a dead writer's), through JavaScriptCore's
  JSON so the rest stays as Claude Code wrote it, and keeps who may read it. Claude Desktop's own "Trust workspace"
  button is pressed only for a folder the record already trusts. A terminal start's words go in a file only you can
  read, never on the command line, and the file goes once the session has started.
- **Builds keep their Accessibility grant** because `build.sh` signs with the bundle id as the designated
  requirement. Don't change the signing line without knowing that.
- **A build restarts only the app it replaced.** `swap-in.sh --restart` restarts the login item only if it runs
  `$HOME/Applications/Whozmove.app` (stopping first a copy that isn't the login item's own, by its checked pid), and a
  copy started some other way only by its checked pid, with a clean environment. So a build for a throwaway home
  (`tests/build.sh`) never restarts the panel you're using. An agent's build never puts the hooks in place: every
  session you start runs them.
- **Deploy runs only what you confirmed.** A project's command is saved only through the set-up card's two steps, in
  `AppDir/deploy.json` (never in the project, which an agent or a clone could change), and runs only when you press
  Deploy. A suggestion never runs by itself, and none is made that looks as if it could reach production, judged by
  what it really runs (`CheckDeploy`: the one list, which the set-up card asks the app about too). The run goes
  detached (`SpawnDetached`, in a session of its own, with signals as a new program has them and no descriptor of the
  panel's), through your login shell started as your terminal starts it (`-l -i`, job control off so Stop Deploy
  reaches all it started, and a trap so the shell itself ends on it), from a clean environment (`DeployEnvironment`:
  nothing of the panel's, which is an agent's if an agent's build restarted it, so no `CLAUDECODE` mark either), so it
  survives the panel restarting (launchd stopping the login item takes its process group too) and `build.sh` treats
  it as yours. A run counts as running for as long as its own process does (pid and start time), whatever its files
  say, so a pid handed to another process later can't hold Deploy up, and a stopped run can't be started again over
  itself. It never starts while the row's agent works or asks, or another session's agent works in the same folder
  (as its own, or where the turn it's on has edited files; one waiting on you doesn't count, as it may wait for days)
  (`WhyStepsWait`, and the button is dimmed): what goes in place shouldn't be half-way through a change. The island's
  steps wait the same way, while the island and its menus stay up.
- **The extra stage runs only what you allowed.** A repo's `whozmove.stage` command runs only once you've answered its
  card with Allow, and only that exact command: the answer is kept in `AppDir/stages.json` (never in the repo), against
  the command, and a changed command is asked about again. It runs on the checkouts' queue with limits (`RunBriefly`:
  3s, 64KB, its whole process group stopped after that), through your login shell without its startup files, with your
  terminal's PATH (`LoginPath`) and without the marks agents put on their commands. Its `run` steps go the same way, for
  30s, only while the row's agent is idle and no other is working in the checkout; its `ask` steps go in as the island's
  own steps do. Never run the command, or anything it prints, any other way (docs/reference/stages.md).
- **Don't name a script or flag for a deploy.** The session hook counts commands named for one as production
  deploys (`names_deploy` in the hook `whozmove-claude.py`), so building and deploying Whozmove use `build.sh`,
  `--now` and `swap-in.sh`.
- **Sorting and grouping** (`classify`, `sectionOf`, `stillOnIt`, `placeRows` and `sortKey` in whose-move.js;
  `heldNow`, `noteOnIt` and `state.placed` in panel.js; `noteSeen:` in app/core/Focus.m): what a session is (a
  request, working, a reply you haven't read, however old, one you have, or idle an hour after the last message or the
  last time you were on it) is kept apart from where its row is shown, its section and its place there. The page keeps
  when you were last on each session while it's yours, across launches (`noteOnIt`): you opened it here, wrote to it,
  or were on it for 2 seconds in Claude or Ghostty in front while at the Mac (the app's `seenAt`). A reply from before
  then is read. Your turn holds the requests, the replies you haven't read, and the ones you have until you've moved
  on, away from the session for 10 minutes; once you have, being on it again leaves its row in Seen until something new
  comes (a reply, or your message). Your turn is first come, first served: a row that comes into it joins the end and
  keeps its place there, so nothing above it moves; a working row sorts by when its turn began, so two working agents
  don't trade places with every step. Only a row you've
  pressed (`keepInPlace`) keeps the place it was last shown in, and its project's, showing what it is now there, until
  you've moved on from the panel: the pointer off it and moved (`hoverEnd`), no box with the keyboard. These are
  deliberate: read the comments in whose-move.js before changing them.

## Animation

`morph(list, html)` (in `panel/scripts/morph.js`) snapshots every row and line, swaps the HTML, then animates
the difference: lines grow and fold (`rowParts`, the modules' lines among them, from `core.lines`), changed text
rolls in place (`rollLine`; Claude's line rolls downward, your message upward), rows slide to their new place (FLIP),
and the list's own height eases with them, so the usage strip below it and the panel's bottom edge go with the rows.
Rows that keep their order slide underneath; one that passes others glides over them with only a frosted backdrop
(`.row.glide`, `keptInOrder`). The island animates stage by stage (`morphIsland` in island.js): a segment springs to
its new width and tint, a changed count blurs out upward as the new one blurs in from below, and a light sweeps once
across the stage that has just become where your next move is. Reduced motion (`calm`) skips it all.

The files gauge opening and closing as it's pointed at is CSS (`motion.css`), from the sizes `layoutIslands` gives it:
its total goes into the point where its parts meet, then the parts' counts come out of that point, and nothing fades.
Opening answers the pointer at once and settles in about half a second; closing is quicker, with no spring. A part's
file list grows out of the pointer and follows it along the gauge (`placeFiles` in island-files.js).

The usage strip moves the same way, without `morph`, as it's never rebuilt: folding into its one row, what's in both
travels between them (measured where it is and where it lands) while the rest fades, and the bars wind into their
numbers. Its wait styles each own a reset, a function of the time since it started (the vine's is `vineFrame`), so
`tests/panel.sh` checks its frames as numbers.

Spotify's token moves natively, as a window of its own under the panel: modules/spotify/README.md says how, and how a
song's lines roll into the now-playing strip and follow along beside the list.

The reader's panel grows and folds natively (`reshapeTo:` in PanelWindow.m): the window takes in everything the
panel covers on the way at once, the page is laid out and drawn there once, and then only the glass's and the page's
clip's edges move; it folds back to the list's measured height. Don't animate the window's own size: the page would be
drawn again every frame, a frame behind, and its edge would fill in tile by tile. And the page never changes width: it's
laid out once, as wide as the list with room for the reader on either side (`kReaderRoom`, `--side`), and the window
shows only the part in use, so opening and closing the reader never has WebKit lay the page out and draw it again,
which would flash the whole panel. Only its height follows the window. Don't cover a change of size with a picture of
the page either: WebKit draws its pictures on white, which shows through the panel's tint as a pale flash. The tint
itself is in the glass, so it moves with the glass's edges.

The style: motion is quiet and continuous. A row never vanishes and reappears; no lifted cards, shadows or
dimming of other rows. Every animation also keeps to these rules, which the vine's tests check:

- **Lanes.** Text has its lane and drawing has its own; nothing flies or slides through text.
- **A lane is cleared before anything enters it.** Text leaves before something takes its place (the vine's "Your
  move" and week figure go before its stem rises into their line).
- **Cause and effect.** Each move follows from the one before (a leaf leaving lets its part of the stem go), so things
  that overlap in time never touch.
- **What's there before and after moves; the rest fades,** the panel's way (fading, lifting 3px, sharpening).
- **It lands exactly where the layout ends up,** measured rather than guessed, with anything still easing beside it put
  at its end first (a column mid-transition measures short), so there's no jump when it hands over (the drain carries
  on at the speed the stem landed with).
- **Reduced motion tells the same story** as a cross-fade, or just the end of it.

For a new motion idea, open an issue describing it before building it.

## Style

- Plain words in UI text; say what people will see, not internals.
- Comments explain *why*, in full sentences, as the surrounding code does. Match that.
- A style takes its colours, text sizes and corners from `panel/styles/tokens.css`, where each is named for its job:
  use one there, or add one for a new job, rather than writing a value out. tests/checks.sh fails on one written out
  that `tests/styles-by-hand.txt` doesn't list; that list is the ones still written out, and only ever gets shorter.

## Pull requests

- One change per pull request, small enough to read in one go.
- For a bigger change, or any new motion idea, open an issue first, so we agree on it before you build it.
- A new pull request starts from a short form (`.github/pull_request_template.md`): what changes and why, how you
  tried it, and a checklist of the rules above. CI builds with every warning an error and runs `tests/all.sh`;
  both must pass.
- Contributions are shared under the project's licence, GPL-3.0-or-later.
