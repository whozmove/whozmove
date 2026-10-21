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
  hook on UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, Notification, Stop, PreCompact, PostCompact.
  Writes the session's state file under a `fcntl` lock, atomically. Must be fast and must never disturb a session:
  everything is wrapped so it always exits 0. Works out the live line, `stageAt` (when a step, the turn or a
  compaction last started or ended), `turnReached`/`outcome` (how far a turn took the work), `workSteps`
  (built/tested/validated), `audit` (local code review findings) and `compactingAt` (a compaction under way, by itself
  or asked for).
- **`whozmove-claude-permission.py`**: synchronous PermissionRequest hook (timeout 3600). Leaves the request for the
  panel and waits for its answer, while Claude's own prompt stays usable; whichever is answered first wins. Steps
  aside at once when the panel isn't running, for sub-agents and non-interactive sessions; steps aside later when the
  call's result shows up in the transcript (settled in Claude) or the session ends. Only ever allows once, never
  "always allow". A plan (ExitPlanMode) is never allowed from the panel, only sent back with your notes or stopped:
  Claude Code ignores a hook's approval of a plan, so approving stays in Claude's own prompt. The same hook runs
  before each switch of a session's model (PreModelSwitch, timeout 90): only a switch the panel noted just before
  typing `/model` (`switches/<session>.panel.json`) is its business, which it allows while the conversation's cache
  isn't warm, and otherwise asks in the panel (`switches/<session>.ask.json`, answered in `.answer.json`), stepping
  aside after a minute so Claude asks in the terminal. It never decides a re-read on its own. All of this is
  deliberate.
- **`modules/claude-code/plugin/`** (`hooks/hooks.json` and `.claude-plugin/`): the two hooks as a Claude Code plugin,
  `whozmove` (in a marketplace of the same name), which is all Claude Code needs to run them. Every build carries a
  copy (`Contents/Resources/plugin`), and each time the app opens, the install module has the agent copy it into
  `AppDir/plugin` and add it from there with Claude Code's own `claude plugin` commands (`PluginInstall`), so
  Whozmove itself never edits `settings.json` for it. Claude Code runs its own copy of the plugin, made per version,
  so each copy gets a version named after the hooks' contents (`modules/claude-code/plugin.sh`): a changed hook gets a
  new one, and Claude Code takes it once told (`claude plugin update`). The session hook records nothing while the app
  noted in `AppDir/app` isn't there, so nothing more of your sessions is written down once Whozmove is removed.
- **`build.sh`**, **`tools/bundle.sh`** and **`app/swap-in.sh`**: `build.sh` makes the app with `tools/bundle.sh`
  (`make_bundle`: the program, the page, the icon, `swap-in.sh`, and the hooks as the plugin, in
  `Contents/Resources/plugin`), records where the build came from in its `build.json` (checkout, branch, commit, and
  `agent` when an agent built it), and signs it last (`sign_bundle`), so its hooks are sealed in its signature with
  the rest. Then `swap-in.sh` puts the build in place, and `swap-in.sh --restart` restarts the app, which brings the
  hooks it carries up to date as it starts (the install module). An agent's build (one with Claude Code's
  `CLAUDECODE` mark, which a `!` command in Claude Code has too) never puts its hooks in place, and once Deploy is set
  up for Whozmove in the panel (its command is `./build.sh --now`), it stops after compiling while the panel runs with
  Deploy's button showing, and leaves putting it in place to Deploy, as for any project.
- **`app/`**: Objective-C, ARC, no Xcode project: `tools/compile.sh` compiles every `.m` in it and in `modules/` (see
  Modules below). It holds the core (`core/`), what modules fill in (`contracts/`) and the helpers that know no app
  (`shared/`); everything else is a module. One file per job:
  - `main.m` starts the app, or runs one of the print modes the tests check. `AppDelegate` makes the page, the panel's
    window, the pawn and the core, and starts them.
  - The core's pieces each keep only their own state: `Page` (loading the page; every call into it), `PanelWindow`
    (FloatingPanel, DragStrip, which covers only what shows of the header as it slides away, size, hover, growing beside
    the list to fit the reader, and back, turning over to the panel's back, which a module's view shows, its tint: grey,
    black or glass, light or dark, and its shadow, in a window of its own under it, a module's view held over the page,
    moving with it, the keyboard and the pointer for a site shown in it, a sideways flick sending it off the screen's
    edge and back, and, folded, the room beside the cat for its chats, which lets clicks through where nothing's drawn,
    and is kept as the panel opens or folds while they move into the list or back out), `MenuBar` (the pawn, grouping,
    the Look menu, the modules' items, and the panel's switches, Show Next Steps and Show Deploy, which Git's page on
    the panel's back sets), `Rows` (the rows read once a second, each module adding its part), `Focus` (the session
    you're on, when you last looked at each, and opening a session from its row), `Send` (words into a session, why they
    can't go in now, and the way past a terminal's reason), `Work`
    (who's at work in a checkout), `Builds` (the running build, for the header), `Printing` (what the print runs share),
    `EdgeIcon` (an icon tucked half under the glass at the panel's edge, on the side facing the screen's middle,
    Spotify's token among them: its own window, following the glass, changing sides under it, coming out once the panel
    has opened, out of sight while it's turned over, and its label), `SideCat` (Whozmove beside the panel while the
    header has gone, an edge icon: its moves, folding the panel round it, a drag moving the panel, and bringing the
    panel back from the screen's edge), `CatShape` (the cat's shapes, for the menu bar's mark and `SideCat`), `Easing`
    (the curves the panel moves on, shared by `PanelWindow`, `EdgeIcon` and `SideCat`) and `Browser` (web pages that
    aren't the panel's own, each in a web view of its own, for a module to show in the panel's window: what it may load,
    whether what it's signed in to is kept, where a link that goes somewhere else opens, how it introduces itself, and
    what a page asks, passed to the module that shows it).
  - The agent that runs the sessions is a module: `claude-code` (its sessions and its hooks' records, its terminal
    sessions kept once they've ended, what's new in each transcript, a session's details, the words of the panel's
    commands and what their results say, typing into a session's prompt while keeping its draft, your plan's usage
    asked of `claude`, folder trust, a new session's command and an ended one's, and its hooks plugin, put into Claude
    Code and kept up to date there with its own commands).
  - The apps sessions run in are hosts, each a module too: `ghostty` (finding a session's tab, typing into it, which tab
    it shows), `iterm2` (finding a session's tab by its terminal device, typing into it through its Python API, else
    while it's alone in its window, which tab it shows, and a command in a new tab; its sessions can outlive the app,
    under a server of its own, so it says which processes it runs), `claude-desktop` (its conversations, its message
    box, new conversations, "Switch model?") and `terminal-app` (macOS's Terminal, which only runs a command: Sign in,
    on a Mac without Ghostty or iTerm2). A session in any other terminal app opens by bringing that app forward. Another
    terminal is one new module that fills in the host contract.
  - Each feature is a module: `git` (`Checkouts`: git status, each checkout's base branch and new files, and which of
    its files are staged; `NextSteps`: the steps a checkout has to take, Commit and its ways, Push, Publish and Create
    PR into the branch you pick, each asked of the agent in fixed words, and the branches on GitHub for Create PR's
    card; `PullRequests` and `GitHub`: the PRs, from gh), `deploy` (`Deploys`: each project's deploy command, the one it
    suggests, running it detached with a log, each folder's last run; `DeployMenu`: its round button's menu),
    `changes` (`Changes`: what isn't committed in each checkout, from git, as git status splits it, not staged (new
    files included) and staged, with each changed line credited to the session whose edits (or its sub-agents') match
    it, its shell commands' too (as its agent records them), else outside the sessions: the checkout's numbers on a
    row, and the changes view, made JSON off the main thread; and the commits not on GitHub yet, one by one, read ahead
    while there are some, so the view's Outgoing opens at once; `Editors`: the editor a changed file opens in, offered from the editors it knows,
    the ones installed, chosen once, kept, changed from the pawn menu's Open With), `reader` (what a session wrote; a
    prototype from its file, in a `Browser` held over the reader's body, and opened in your web browser), `usage`
    (`Usage`: your plan's usage, asked of the agent every few minutes, for the usage card; Sign in; `UsageCard`: the
    card under the panel that shows it, a window of its own with a page of its own), `starts` (`Starts`: a new
    conversation from the panel's card, the folder's trust checked, the session opened with your words, and watched for
    until it's listed; `Worktrees`: a worktree of its own for one; `Shortcut`: ⌃⌥N), `commands` (the model, effort and
    mode menus and the Compact card, from the menu to the command's result) and `spotify` (the now-playing strip, with
    its lyrics from LRCLIB, which open beside the list, and Spotify's token). And `apps`, the panel's back
    (`AppsModule`: the apps every module works with, each one's page with its switches and what macOS lets Whozmove do
    with it; `BackPage`: the back's web view, on the back of the glass). And `install`, Whozmove setting itself up as it
    opens (`Install`: from an Applications folder only, where it runs from noted for the hooks, the agent looked for,
    Apple's developer tools waited for, which only the agent's sessions need, then the hooks put into the agent or
    brought up to date there, `AgentInstall`; its own record in `AppDir/install.json`).
  - The data has a shape: `Row` (app/contracts) is one listed session, field by field as **`docs/reference/rows.md`**
    describes it (the contract between the hooks, the app and the page; `tests/rows.sh` keeps the two in step).
    `Command` (the commands module's) is one slash command sent from the panel, with its stage (asking, going in,
    waiting, done, abandoned), and `Reason` (app/contracts) names why keys can't go into a session right now.
  - Plain functions with a header each, in `shared/`: `Log`, `Files`, `Processes`, `Git`, `Text`, `AppleEvents`,
    `AppleScript`, `Accessibility`, `Links`, `Menus`, `Appearance`.
  - Nothing slow runs on the main thread. The sessions' files, transcripts, git and gh are read on serial queues,
    and each terminal is asked which tab it shows on one of its own, and what they find is handed to the main thread,
    where all the state is kept (a terminal's answer is matched to a session there, from what's already been read).
    The one thing read from both sides is Claude Desktop's log (`DesktopLog`'s `catchUp`), and they take turns.
- **Facts**: everything Whozmove relies on about another program that it could change is in that program's module
  (`ClaudeCodeFacts.h`: where Claude Code keeps things, its command, the model and mode choices; `ClaudeDesktopFacts.h`,
  `GhosttyFacts.h`, `ITerm2Facts.h`, `SpotifyFacts.h`, and beside it `LRCLIBFacts.h`, for the lyrics' web service), and
  what it knows of the editors Open With offers is in the changes module's `Editors.m`. What a `Browser` relies on to
  introduce itself as Safari is the core's, beside it, in `BrowserFacts.h`. The versions they were last
  checked with are in the README. When one of them changes, the fix goes there.
- **`panel/`**: HTML, CSS and plain `<script>` files: no modules, no build step, no libraries.
  `update()` → `render()` → `morph()`.
  - `panel.html` is the markup, and loads the rest in order: `styles/` (`tokens`, the panel's colours, text sizes and
    corners by name; `base`, `rows`, `cards`, `controls` (what more than one part draws: the switch, a button),
    `reader`, its frame; `cat`, `chats` and `peek`, the folded cat's, and what comes out of it; the modules' styles;
    and `motion`) and `scripts/`, the
    modules' scripts last but for `panel`. `tools/page.sh` lists the modules' at the two lines the page marks for them.
  - `scripts/`, one job each. The page's core first: `util` (the bridge's send, storage, escaping, measuring text),
    `state` (everything the page keeps between rebuilds, in one object), `modules` (what the modules plug into the page
    with: see Modules below), `fresh` (whether a card or button has only just been shown, a row's again once it's back
    in view, and a request answered here),
    `whose-move` (what each session is, the list's order, and which session speaks for each checkout: plain
    functions, checked by `tests/panel.sh`), `icons`, `markdown` (plans and notes as HTML, everything escaped:
    a plain function), `builds` (the header's name for the running build), `morph` (the animation), `strips`
    (changing a strip's text, and easing, growing and folding it, for any strip under the
    list), `rows` (a row's template, with its places for the modules' parts, and the group and project headers), `hover`
    (what's pointed at, and the card something pointed at shows), `input` (presses, typing and the keyboard), `reader`
    (the reader beside the list, which its modes fill, each about a session, or, like Spotify's lyrics, about none),
    `cat` (the folded cat: its pose, its eyes on the pointer, its place on the name's o, the room beside it, and the
    panel opening round it and folding back), `chats` (what needs you, out beside the folded cat by itself as its row:
    see Animation; which come out, when and where are plain functions, checked by `tests/panel.sh`), `peek` (the
    panel opening while the folded cat is pointed at, its header standing aside for a head of its own: see Animation),
    `header` (the header pushed away by the row you're on, and back: see Animation; how far it has gone is plain
    functions, checked by `tests/panel.sh`), `sticky` (the row you're on, held at the list's edge as the list scrolls
    past it, folded down: see Animation; how it folds is plain functions, checked by `tests/panel.sh`), and `panel`
    (`render`, and the functions the app calls on the core). Then each module's, from its `page/`, one per job, each
    plugging into the core as it loads: Claude Code's `agent` (what a Claude Code session's model, mode and context
    mean) and `requests` (its requests, questions and plans on a row); the commands module's `commands` (the model,
    effort and mode labels, the context ring, the Compact card, and the card while a pick goes into a terminal session)
    and `switch-model` ("Switch model?", asked on its row for Claude Desktop and terminal sessions alike); the next
    steps (`steps`: which a checkout has to take, `stepsOf`, how its last code review went, and where a branch stands
    while commits wait, plain functions; `git-steps`: their icons on the work line, their words as they're pointed at,
    Create PR and its card, and the review or where the branch stands; `prs`: the pull requests and their card); Deploy
    (`deploys`: whether a row has its round button, how it looks, and the set-up card, plain functions; `deploy-row`:
    the button, the line and the card on a row); the reader's `writings` (what a session wrote:
    its tag, and the reader's `writings` mode, where a plan is sent back or stopped, and a prototype's space and the
    line above it); `changes` (the view's tabs, git's letters for each file, what its head says, and how lines are laid
    side by side: plain functions) and `changes-view` (the numbers, their card, and the reader's `changes` mode); and
    `starts` (the card for a new conversation, which opens under the header, the pending row a start shows as until it's
    listed, and the card turning into that row and moving down to its place; `start-words`: what the card reads in your
    words, @ for the project and # for where in it, and a new worktree's name, plain functions). Last, Spotify's:
    `now-playing` (what the now-playing strip shows, plain functions), `lyrics` (a song's lines and pauses from its LRC,
    and which shows when, plain functions), `np-strip` (drawing the strip, its words rolling in place, and its presses),
    `lyrics-view` (the one timer that changes the lines, and the reader's `lyrics` mode) and `spotify` (what it plugs
    in, and the functions the app calls).
  - A module can have a page of its own too, for a window of its own: the usage module's card, `card.html`
    (modules/usage/page/), in the card's window under the panel. It loads the panel's tokens and `util`, then its
    own `usage` (what the card shows, plain functions), `waits` (its wait styles, chosen by name, each a file of its
    own, `wait-vine` the first, whose shape and reset are plain numbers too) and `card` (drawing the card folded,
    slid out and open, opening and folding it, the pointer and presses on it, and the functions the app calls).
    And the apps module's `back.html` (modules/apps/page/), the panel's back, in a web view of its own on the back of
    the glass: the panel's tokens, `base` (so its header is the list's) and `controls`, `util` and `icons`, then its
    own `apps` (what an app's permission says, and the switches once one is pressed: plain functions) and `back`
    (drawing the apps and each one's page, the pointer and presses, and the functions the app calls).

Bridge, page → native (`type`): `height`, `open`, `pick`, `compact`, `wayPast` (the button past a terminal's reason, on
the Compact card or a step's note, `{sessionId}`: `Send` asks the session's host to take it), `switchAnswer`,
`answerAsk`, `openPR`, `keyboard`, `badge`, `gitStep` (a step pressed on a row or in the changes view, `{step, into}`:
`commit`, `push`, `publish`, `pr` or `draftPR`, asked only if the checkout has it to take; `into`, the branch a pull
request goes into, one of the repo's on GitHub, else its default), `gitWays` (the ways to commit, in a menu under the
view's ⌄), `prBranches` (the branches on GitHub, for Create PR's card), `stepMenu` (Deploy's menu, as `step: "deploy"`),
`deploy`, `checkDeployCommand` (a command on Deploy's set-up card, about to be confirmed), `saveDeployCommand`, `expand`
(the reader's size, `{width, height}`: the panel grows beside the list to fit it, and is asked again as what's shown
changes) and `collapse` (back to the list), `turn` (`{on}`: the header's four squares turn the panel over to its
back), `header` (`{showing, gone}`: how many of the header's points still show as it's pushed away, which the drag
strip covers, and whether it has gone, for Whozmove beside the panel), `catShown` (the page's folded cat has
taken over from Whozmove beside the panel, where the panel folded round it), `catPose` (`{pose}`: the folded cat's
mood, asleep, watch or turn, which Whozmove beside the panel keeps too), `fold` (`{on, instant, room, peek}`: the
panel folds into the cat, or opens out of it; `room`, as `catRoom` names it, is where the chats still out go back to
beside the cat, which the window keeps as it folds; `peek` for the folded cat's list coming out or going back in,
which, asked the other way while it's still moving, turns back from where it is, and isn't kept for next launch),
`keepOpen` (the folded cat's list on pointing kept open by a press: the panel is left open for next launch), `catAt`
(`{x, y}`: where the name's o is, which the folded glass's middle is kept on), `catBreathe` (`{working}`: how many
sessions work, for the folded glass's breath), `catRoom` (`{parts, ask}`: the room beside the folded cat for its
chats, each part `[x, y, width, height]` from the glass's middle, which takes clicks, and `ask`, its number, which
`catRoomTaken` names), `readWriting` (one of a session's
writings, `{sessionId, id}`), `prototype` (the reader's prototype, shown from
its file over its space: `{action: show, sessionId, id, at, rect}`, `{action: place, rect}`, `{action: hide}` or
`{action: outside, sessionId, id}`, Open in Browser), `closeCopy` (from an "open twice" card: the conversation's other
copies in terminals closed, `{sessionId}`), `readChanges` (one of the changes view's tabs, `{sessionId, scope}`, asked
for ahead as the row's numbers or its numbers are pointed at, so the view opens at once, `scope` being `unstaged`,
`staged` or `outgoing`, the commits not on GitHub yet), `openFile` (one of them in your editor, `{sessionId, path,
line}`, with `editor` when it was just chosen), `start` (a new conversation, `{startId, folder, app, words, sessionId,
trust, target}`: `sessionId` is the one the page chose for a terminal start, `trust` your yes on the card, `target`
where in the folder's repo when not its own folder, `{kind: open, path}`, `{kind: branch, name}` or `{kind: new, name,
base}`), `checkFolder` (whether Claude may work there), `listBranches` (what a folder's repo has, for the card's #),
`checkWorktreeName` (whether a new worktree can be made, `{folder, name, base}`), `startMenu` (the card's small menus,
`{kind}`: `app`, `places` with `repo`, or `choose`), `spotify` (the now-playing strip's presses, `{action}`:
`playpause`, `next`, `previous`, `seek` with its `fraction`, `open` or `settings`; `folded` once it has folded away;
`collapsed` `{on}`; and `lyrics` `{on}`, your answer about lyrics) (each routed by its type to the core or the module
that answers it: `Modules`).
`answerAsk` for a plan carries `message` (your notes) or `stop`. Native → page:
`update(rows, now)`, `setRoom`, `hoverAt`/`hoverEnd` (with `still` while the pointer is off the panel without having
moved there: the panel's edge went past it, or one of its menus closed there; `hoverEnd` comes again once it moves; and
`held` while it's on what the panel holds over or under itself, Spotify's token or the usage card),
`keyboardGone` (the panel no longer has the keyboard), `turned` (the panel is turning over to its back, or back on its
list side), `setGroupBy`, `toggleCollapsed`, `stepNote` (with `quiet` when
it says how something went that worked, and `way`, the button past a terminal's reason, when there is one),
`setRunningBuild` and `setSwitches` (the core's, in `panel/scripts/panel.js`); `foldFromSide(x, y)` (Whozmove beside
the panel was pressed: the panel folds round it, there), `catLanded` (it has grown into the folded cat, which takes
over), `catPointer(x, y)` (where the pointer is from the folded glass's middle while it's near, or null), `catGlass`
(the glass is about to spread out from behind the cat as the panel opens), `catWay({right, up, across, tall})` (which
way what comes out of the folded cat goes, and how far there is to the screen's edge), `catRoomTaken(ask)` (the window
has the room asked for beside it, in the ask it names) and `catMoving(moving)` (the folded cat is being dragged with
something out beside it, which goes in meanwhile, and has stopped) (in `cat.js`); `catPressed(down)` (the folded cat
pressed, and let go: its list doesn't come out on pointing meanwhile) (in `peek.js`); `readerOpened(side, width)`
(which side the list
stays on, and the reader's width) and `readerClosed` (in `reader.js`); and each feature's, in its own script:
`compactNote` (why a compaction didn't go in, and the button past it, `(sid, text, way)`) (`commands.js`),
`setDeploys`, `openDeploySetup` and `deployChecked` (what that command really runs,
`{command, production, runs, more}`) (`deploy-row.js`), `setPRBranches(sid, {base, branches})` (`git-steps.js`),
`openStart`
(⌃⌥N, New Conversation), `folderChecked` (`{trusted}` or `{gone}`), `startUpdate` (how a start went: `{sessionId}`
once it's listed, `{note}` while it waits on you, `{why}` if it didn't start), `startProject` (a folder picked from the
card's chooser), `branchesListed` (`{here, worktrees, branches, base, folder, folderPath}` or `{none, where}`),
`worktreeNameChecked` (`{path, where, name, base}` or `{why}`), `worktreesMoved` (a repo's worktrees go somewhere else
now), `startAppChosen` (from Start's menu) and `setStartOptions` (`{terminal}`, the terminal a start can open in, or
null) (`starts.js`), `setNowPlaying` (the song Spotify is playing, or null) and `setLyrics` (what's known of its lyrics:
`{state}`, and for a song's `track`, with `lrc` or `plain` once found, or `none` or `failed` when there are none to be
had) (`spotify.js`),
`showWriting(sid, id, {text} or {missing})` and `prototypeState(sid, id, {loading, problem, asked, keyboard})`
(`writings.js`), and `showChanges(sid, scope, {scope, v, files} or {missing} or {counting})` (each file `{path,
status, binary, untracked, alsoStaged or alsoUnstaged, hunks: [{oldStart, newStart, lines: [[sign, text]]}]}`, with
`cut` past 30,000 lines; Outgoing's `{scope, v, upstream, commits: [{hash, short, subject, at, files}], more}`) and `setEditors({choice,
apps: [{id, name}]})` (`changes-view.js`). `setDeploys` gets `{projects: {project: {command}}, folders: {folder:
{suggested, at, skippedAt, run}}}`, where a run is `{startedAt, running, ok, finishedAt, lastLine, stopped}`; a project
is a repo's main checkout (or a folder outside git), saved by its real path (symlinks resolved, as `build.sh` finds it),
and a folder is the checkout a session runs in (for one that runs outside any, the one it last edited files in).

The usage card's own page (modules/usage/page/card.html) has a bridge of its own, in the same shape, in its own window
(`UsageCard`): it sends `usageSignIn` (its Sign in) and `usageCard` (`{shown, extent}`: whether there's a card, and how
much of it shows under the panel's edge, in points, where its window takes clicks), which the usage module answers;
and the app calls its `setUsage` (your plan's usage: `{state, plan, session: {used, resetsAt}, week, limits: [{kind,
percent, severity, resetsAt, model}], extraUsage, checkedAt}`, where `state` is `ok`, `signedOut`, `other` or `none`),
`previewWait` (Working on Whozmove's Preview the Wait), `cardPointer` (where the pointer is in its window, `{x, y}` from
its top-left corner, while it's near, or null once it has gone: its window is never key, so it gets no mouse moves) and
`cardAppear` (its window has come back into sight) (`card.js`).

The panel's back (modules/apps/page/back.html) has a bridge of its own too, in its web view (`BackPage`): it sends
`appsTurnBack`, `appsFold`, `appsSwitch` (`{app, key, on}`), `appsOpen` and `appsPrivacy` (`{app}`), which the apps
module answers; and the app calls its `setApps(apps, look)` (each app `{id, name, does, icon, open, switches,
permission}`), `turned(false)` and `backPointer` (`{x, y}` from its top-left corner while the panel is turned over and
the pointer is on it, or null) (`back.js`). modules/apps/README.md has each one's shape.

## Modules

Each outside program Whozmove works with, and each feature, is a module in a folder of its own, so a change in one
program is fixed in its module alone. The usage card, the changes view, the reader's own parts, new conversations and
Spotify's strip keep their styles in their modules; the row's and the cards' are the core's (`panel/styles/rows.css`,
`cards.css` and `motion.css`: the next steps', Deploy's and the requests' among them).

- **`app/core/`** is the panel itself: start-up (`AppDelegate`, `main.m`), the registry (`Modules`), the services a
  module gets (`Core`: the page, the window, the menu bar, the rows, the hosts, the agents, the terminal new sessions
  start in, and a `Browser` for web pages of its own), `Rows` (the rows read once a second, each module adding its part
  in the phase it belongs to, and sent), `Focus` (the session you're on, when you last looked at each, and opening a
  session from its row, an ended terminal session's in a new tab), `Send` (words into a session through its host and its
  agent, and why they can't go in now, worded as the menus, cards and steps say it), `Work` (who's at work in a
  checkout, which the next steps and Deploy wait for), `Page`, `PanelWindow`, `MenuBar`, `Builds` and `Printing`
  (what the print runs share: the rows read, and read once what's worked out alongside them has come back).
  **`app/contracts/`** holds what modules fill in (`Module.h`, `Host.h`, `Agent.h`) and what they pass (`Row`,
  `Reason`), and **`app/shared/`** the helpers that know no app (`Log`, `Files`, `Processes`, `Git`, `Text`,
  `AppleEvents`, `AppleScript`, `Accessibility`, `Links`, `Menus`, `Appearance`).
- **`modules/<name>/`** is one module: `app/` (its native code), `page/` (its scripts and styles), `module.json` (its
  page files in order, for tools/page.sh, and its own pages, if it has any: `pages`), `tests/` (its `test.sh`, which
  tests/all.sh runs, and what it compares with) and `README.md` (its pieces, the facts about its program, its
  messages, its rules). What the tests share is in tests/lib.sh: the app built once per run, `in_minutes`, and
  `page_cases`, which runs a file of the page's cases as tests/panel.sh runs the core's, or a module page's with that
  page's scripts (tests/page-harness.js has their stand-ins and helpers).
- A module's face is a class that adopts `Module` (app/contracts/Module.h). The core finds it at launch, so nothing
  lists it. It names the page messages it answers (each type has one; two modules answering one fail the tests), its
  items in the pawn menu and where they go, the apps it works with as the panel's back lists them (each with what
  Whozmove does with it, the permission macOS has to give, and its switches, or switches it adds to another module's
  app), its print modes, its part of each tick, its part of each row, in the
  phase it belongs to (the checkout's state, the session's work, its agent's details, and once the rows are whole), and
  whether it's still working something out off the main thread, which a print run waits for. Setting up only prepares
  data, since the tests' print runs make every module too; windows, observers and timers start in `launch`.
- An app sessions run in is a host: a module that adopts `Host` too (app/contracts/Host.h), and says what more it can
  do by the protocols it adopts beside it: `TypingHost` (a session's tab found, and keys typed into it), `CommandHost`
  (a command run in a new tab) and `ConversationHost` (an app that keeps sessions as conversations of its own, Claude
  Desktop's). The core finds the host a row runs in (`hostOf:`), so nothing else asks which app it is. On the page,
  each host names its rows (`core.hosts`: its name, "Open in … now").
- The agent that runs the sessions is a module that adopts `Agent` (app/contracts/Agent.h). As the rows are read, on
  their queue, it lists the sessions it runs; the hosts add what they know (and Claude Desktop its conversations,
  running or not); it adds its terminal sessions that have ended, as closed rows no other row has, which Focus opens
  again in a new tab (`resumeCommand:`, in the terminal it ran in, else the core's `startTerminal`); it adds what its
  hooks recorded and the requests waiting; the core adds each session's checkout. It gives each session a title (a
  terminal finds its tab by it, and by whether the tab's title shows it at work), and names the marks it puts on its
  commands. A conversation running in more than one process at once is one row, the copy that needs you most, which
  names the others (`alsoOpen`, with whether each is at work, which Deploy and the next steps wait for). What more
  it does, it says by the protocols it adopts beside it, one for each part of the panel that uses it: `AgentWork` (what
  a session edited, and its PRs), `AgentCommands` (its menus' choices, the commands that make them, and whether one
  took), `AgentPrompt` (a command typed into a session's prompt while keeping your draft, and when that's safe),
  `AgentUsage` (your plan's usage), `AgentStarts` (a new session's command, an ended one's, and folder trust) and
  `AgentInstall` (Whozmove's hooks put into it, and kept up to date). The core finds the agent that runs a row
  (`agentOf:`), so nothing else reaches into one: there's one, Claude Code, for now.
- On the page, a module's scripts only register as they load, in the lists panel/scripts/modules.js keeps, and the
  core runs them; a module never calls another's functions or reads its state. Its own state goes on the page's state
  with `moduleState`, which refuses a key another has. What it can plug in:
  - its start-up, and its part of each update, each fold to the header and each rebuild of the list (rows the app
    hasn't listed yet, what it works out before the list is drawn, and after);
  - a row's parts: its first look at the row, its parts in the row's places (`core.slots`: after the name; the work
    line's start, its numbers and its steps; the bottom line's start and its end; a project's header), its card
    under the chat (`core.rowCards`, the most pressing showing, each the others' place when they want it), and the
    row's note, said in its work line's place (`core.rowNotes`);
  - presses, typing and Return in its boxes, the boxes that take the keyboard, the cards that take it once pressed and
    their keys, what the pointer can point at, what it does with what the pointer is on, and the card something pointed
    at shows (with buttons, `press`, it stays while the pointer moves onto it);
  - the strips above or under the list and what hangs below it (for the panel's height), the reader's modes and their
    presses, its lines' motion (`core.lines`), the bits that cross-fade, what a step's note settles, and what's
    forgotten a minute after a session goes;
  - what an agent's details mean (`core.agent`), for the parts that show them.
- `tools/compile.sh` is the one compile line, for build.sh, the tests and CI. Only `app/` and its `core`, `contracts`
  and `shared` folders are on its include path, so a module can't import another module's header, nor the core a
  module's. It builds for the oldest macOS `app/Info.plist` names (`LSMinimumSystemVersion`), so a newer call made
  without checking for it is a warning, and fails CI. `tools/page.sh` puts the page together, and a module's own
  pages (module.json's `pages`) beside it.
- A module keeps the facts about its own program (Spotify's are in modules/spotify/app/SpotifyFacts.h, Claude Code's
  in modules/claude-code/app/ClaudeCodeFacts.h).
- Preference keys keep their names: build.sh reads `showNextSteps` and `showDeploy`, and every switch keeps its choice
  across launches, as the Look menu's do (`panelLook`, `appearance`).

## Build, install, debug

```bash
./build.sh            # compiles (clang -Wall), signs, puts ~/Applications/Whozmove.app in place, restarts it (it
                      # brings its hooks up to date as it starts); an agent's only compiles, once Deploy is set up
                      # for Whozmove (see below)
./build.sh --now      # the same, as Deploy runs it (from an agent, it still only compiles)
./install.sh          # adds the hooks as a Claude Code plugin, sets up the login item (LaunchAgent)
tests/all.sh          # every test below, the app built once for all of them (~80s)
tests/rows.sh         # the rows the app builds for a sample home, its mode menus' Shift+Tab counts, the menus' why
                      # nots, how a command's result is read and the macOS permissions the README names, compared
                      # with tests/rows.expected.txt
tests/panel.sh        # the page's labels, colours, sorting and row HTML (macOS's jsc, in UTC), vs
                      # tests/panel.expected.txt
tests/build.sh        # build.sh against a throwaway HOME: when a build waits and when it goes in, the hooks it
                      # carries, sealed in its signature, swap-in.sh putting it in place, and what it restarts, vs
                      # tests/build.expected.txt
tests/browser.sh      # where each kind of address goes from a Browser's sample setups, and the folders, stores and
                      # names it keeps to, for a sample folder, vs tests/browser.expected.txt
tests/edges.sh        # the panel's edge for sample panels and screens: the side its icons are on, where it folds
                      # round Whozmove beside it, whether a swipe is the panel's and flicks it off the screen's edge,
                      # where a flicked panel goes and how much shows on its way, which way what comes out of the
                      # folded cat goes and the room for it, vs tests/edges.expected.txt
tests/checks.sh       # the checks that keep modules apart (prints only problems): no page function in two
                      # scripts, every page call and message has its other end, no module imports another, no
                      # class styled on its own by both the core and a module (or two modules), each module's
                      # README with its pieces and its rules, and no colour, text size or corner written out in
                      # a style that tests/styles-by-hand.txt doesn't list (--update takes off the ones gone)
modules/*/tests/test.sh  # each module's own tests, with its own recorded outputs; Claude Code's run both hooks against
                         # a throwaway HOME, compared with modules/claude-code/tests/hooks.expected.txt (on the
                         # developer tools' Python too), and put its plugin into a stand-in Claude Code; the install
                         # module's, how the app sets itself up as it opens; the usage module's, what the usage card
                         # shows and the vine's reset, with its page's scripts
```

- After editing anything in `app/`, `modules/`, `panel/` or `icon/`: `./build.sh`. After editing a hook or its
  `hooks.json` (modules/claude-code/plugin/): `./build.sh` too, in your terminal: the app puts the hooks it carries in
  place as it restarts (an agent's build leaves them as they are). Sessions run Claude Code's copy of the plugin, made
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
  session moves on or the terminal refuses a key. `Whozmove --print-why-not` prints what each session's model,
  effort and mode menus, its Compact card and its next steps would say about why nothing can go into it now, and
  `Whozmove --print-results <command> <transcript>…` what the panel takes each command's result in a transcript to
  say.
- `Whozmove --print-changes <sessionId> <scope>` prints what the changes view would be sent for that session's
  checkout in `$HOME`, one of its tabs: `unstaged`, `staged` or `outgoing`; `tests/rows.sh` checks each on a checkout
  with a file staged and changed again, files git doesn't track, and a commit not on its upstream.
- `Whozmove --print-deploys <folder>…` prints the command Deploy would suggest for each folder, and how its last run
  went as the page would be told; `Whozmove --print-deploy-checks <folder> <command>…` what the set-up card would be
  told each command really runs there. `tests/rows.sh` checks them against sample projects and runs.
- `Whozmove --print-usage <file>…` prints what the usage card would take from each file as Claude Code's answer to
  the usage request, or as `claude auth status`'s, and where `claude` is looked for (`$USAGE_PATH` as the PATH);
  `tests/rows.sh` checks it against recorded answers. The print modes never run your `claude` (the agent's
  `askUsage` and `connect:before:from:` answer nothing in a print run).
- `Whozmove --print-plugin-install [--answer <press>] [--before] <hooks>` puts the hooks in a folder into Claude Code
  as the app does as it opens, with `claude` looked for on `$INSTALL_PATH` first, and prints what it reached; the
  Claude Code module's tests run it with a stand-in `claude`. `Whozmove --print-install <case>…` prints what the app
  does as it opens in each of the install module's sample cases, with stand-ins for where it runs from, the agent and
  Apple's developer tools; that module's tests check it. Both change Whozmove's folder in `$HOME`, so they refuse to
  run in your own home folder: give them a throwaway one, as their tests do.
- To see the usage card's wait and reset without a limit to wait for: hold ⌥ as you open the pawn menu, Working on
  Whozmove ▸ Preview the Wait.
- `Whozmove --print-browsing <folder>` prints where each kind of address goes from sample setups of a `Browser` (the
  web, a site with its links out, the folder's pages with and without the web's parts), which folders a page can be
  shown from, the store each sample name's sign-ins are kept in, and how a Browser introduces itself; tests/browser.sh
  checks it.
- `Whozmove --print-edges` prints what the panel's edge does with sample panels and screens: the side the icons at
  its edge are on, where the panel folds round Whozmove beside it, whether a two-finger swipe is the panel's and flicks
  it off the screen's edge, where a flicked panel goes and how much of it shows on its way, which way what comes out
  of the folded cat goes, the room the window takes in for it, and where that takes a click; tests/edges.sh checks it.
- `Whozmove --print-apps` prints the apps every module lists for the panel's back, in their order, each with what it
  says, its permission and its switches (those other modules add among them); the apps module's tests check it.
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
  look, make them instant with `Object.defineProperty(calm, 'matches', { get: () => true })`. The usage card's page is
  there too, in `modules/usage/page/card.html`: stub its bridge the same way, and call `setUsage(…)` with usage shaped
  as its bridge describes, and `cardPointer({x, y})` to point at it (the panel's bottom edge is 24px down).
- Try every change on the real app.

## Rules that keep it safe

- **Never touch your real sessions or data while testing.** Use a throwaway `HOME` (as the Claude Code module's
  tests do) and sample rows. Don't compact, change model, or type into a real session to test.
- **Never kill processes by name pattern** (`pkill -f whozmove`, `pkill python`): live permission hooks
  are holding permission prompts in your sessions. Find the exact pid, check it, kill that.
- **`~/.claude/settings.json` holds secrets.** Never log or paste its contents; read the keys you need with a
  JSON parser.
  Claude Code's own `claude plugin` commands, which the app runs to put its hooks in, write their entries there. The
  panel itself writes it only to put back `/model`/`/effort` defaults, key by key, via JavaScriptCore's JSON so the
  layout stays as Claude Code wrote it.
- **The panel must never take the keyboard.** `FloatingPanel.canBecomeKeyWindow` is `wantsKeyboard`, set only while one
  of the panel's own text boxes is clicked into (`keyboard` message), while the new conversation card is open from ⌃⌥N
  or New Conversation, until it starts or closes, or while a site shown in the panel (a `Browser`) has been clicked
  into, until a click anywhere else in the panel, the panel folding or turning over, or the site going; and while a
  request or a question in the list has been pressed (`core.keyCards`, `heldCard` in input.js), but where the press
  answers it, until it's answered or gone, Esc, or a press anywhere else, so Return answers it there and not Claude's
  own copy of it in the app in front. Clicking a row leaves the keyboard with Claude, which is what lets "open a
  conversation, type straight away" work. When the panel lets go of the keyboard, it hands it to an unseen window of its
  own, which goes at once, so macOS gives it back to the app in front (`giveBackKeyboard`): asking that app to come
  forward does nothing while it's in front already. A moment after a press brings a terminal's tab forward, the terminal
  is checked to have it (`keyboardTo:tries:` in Focus.m), and the log says who had it when it hasn't. Don't synthesize
  clicks or move the pointer to focus things in Claude: it makes the mouse pointer jump. When another app takes the
  keyboard, the page lets go of the box or the card that had it (`keyboardGone`): asking for the keyboard makes the
  panel key at once, so a box focused again as the list is redrawn would take it back.
- **Only the panel's own page talks to the app.** The panel's page has no frames: `Page` lets none load in it, and
  ignores every message that doesn't come from its main frame. The reader shows a prototype a session wrote, scripts and
  all, in a `Browser` of its own, only from the file its session's row lists (never a path the page sends). Keep all
  three: a page Claude wrote must never answer a request. A `Browser` has no bridge at all, and no way to be given one:
  what it shows can never send the app a message. A folder's pages in one can't read the folder's files (WebKit's own
  rule for file pages), which is why they may take parts from the web: never turn on WebKit's file access preferences.
- **A changed file opens only from its checkout's changes.** `openFile` names a file by its path within the session's
  checkout, and the app opens it only if that checkout's changes list it (`Changes`' `fileOf:path:`), in the editor
  you chose and nothing else.
- **Hover is pointer polling** (25×/s, `pollPointer`), not mouse events: a non-key panel gets no mouse moves.
  Clicks are handled on `mousedown`, not `click`: the list re-renders every second. Folded with chats out beside
  the cat, the window holds the room for it, and only the cat and what's drawn there take the
  pointer and clicks (`passClicks:`, from the parts the page names in `catRoom`): everywhere else in that room, clicks
  go through to what's under the panel, decided as the pointer moves (60×/s then), never while a button is held. A
  site shown in the panel (a `Browser`) is passed the pointer only while the panel has the keyboard, once you've
  clicked into it: WebKit follows the pointer only in the window you type in, and the panel never seems to be that
  window when it isn't.
- **Whozmove runs no git of its own before Apple's developer tools are there.** Without them, `/usr/bin/git` (like
  `python3` and the other tools macOS keeps there) offers to install them each time it's run. So the app's git goes
  through `RunGit`, and everything else it runs that runs git waits for `DeveloperToolsReady()` too: `gh` (`GhPath`),
  making a worktree, and Claude Code's usage check, as `claude` may. What you start yourself, a conversation or a
  Deploy, runs as it would from your terminal.
- **Typing into a session only when it's safe.** Ghostty: only while idle at its prompt with no request pending
  (`WhyNotTypeInto`), since a stray Enter would approve a permission prompt, and Shift+Tab would allow all edits. Never
  while it's paused in its terminal (Ctrl+Z), where keys go to the shell, nor while its conversation runs in another
  terminal too (open twice: resumed in a second tab), where a key could land in the other copy, whose tab can look just
  the same; and no Shift+Tab while it's open anywhere else too (Claude Desktop), as the copies share one record of the
  mode. iTerm2: the same, and only into a session alone in its window, no other tab or pane there (`whyNotTypeIn:`, and
  again in the script that types, right before): its Broadcast Input copies scripted typing into the window's other
  sessions, hidden floating panes among them, and nothing in its scripting says whether it's on. While a connection to
  its Python API is open (`ITerm2API`), keys go through that instead, into the session alone (`suppress_broadcast`), so
  the window rule is lifted. The API is turned on only in iTerm2's own Settings, as you would, for a press of yours
  (the button `wayPastIn:` names, which `takeWayPastIn:done:` answers, or its switch on the panel's back), where iTerm2 asks you first; never by writing its settings. A key
  it refuses stops the rest of the command, so none goes in half. Claude Desktop: only while idle (`WhyNotSendTo`) and
  only if its message box is empty; text goes in through the Accessibility API ("Prompt" text area, Submit button), not
  keystrokes. The one exception is a Return when Claude shows no Submit button, and only while Claude is in front
  (`submit:` in modules/claude-desktop/app/DesktopMessageBox.m). A new conversation's first message is sent with
  Claude's Send button, never a key, only in the conversation Whozmove has just opened with your words, once Claude
  shows its page, and only while its box holds exactly those words (`sendFirst:` in DesktopNewConversation.m) and Claude
  shows the folder the conversation is for. Claude loses a folder that comes in its link, so the folder is chosen as you
  would: its environment pressed among the recent ones Claude's page lists, once, which environment is which folder read
  from Claude's own record and never written (`chooseEnvironment:`), or on Claude's older screen its folder button
  pressed and the folder picked from its Recent ones, by path, the one time its list opens (`chooseFolder:`); never
  "Open folder…" or a new environment. Claude can let a press go by while it gets the folder ready, so Send is pressed
  again, a few times, until Claude's log says it's starting the conversation or its box empties (`pressSend:`); the
  words are never taken out of Claude's box. The one key that goes into a terminal session while Claude works is the
  Backspace that takes out the filler of a next step's request (`WhyNotEditDraft`): Claude Code puts the stashed draft
  back the moment a message is sent, and there a Backspace only edits it. Never while Claude asks something or a request
  waits. A step's words are fixed in the app (`StepRequest`); the page only names the step, and the branch a pull
  request goes into, which goes in its words only if it's the repo's default or one of its branches on GitHub as the app
  read them for Create PR's card.
- **`/model` and `/effort` also save a default** for new sessions; the panel puts those settings keys back
  (`holdDefaults`/`releaseDefaults`). Keep that if you add commands.
- **Folder trust is recorded only for a folder you trusted on the card.** `~/.claude.json` holds your account and more:
  `Trust.m` (in the Claude Code module) reads only `projects[<folder>].hasTrustDialogAccepted` from it, with a JSON
  parser, and never logs it. `TrustFolder` writes that one key for that folder, under the lock Claude Code takes to
  write the file (the folder `~/.claude.json.lock`; one 10s old or more is a dead writer's), through JavaScriptCore's
  JSON so the rest stays as Claude Code wrote it, and keeps who may read it. Claude Desktop's own "Trust workspace"
  button is pressed only for a folder the record already trusts. A terminal start's words go in a file only you can
  read, never on the command line, and the file goes once the session has started.
- **Builds keep their Accessibility grant** because every bundle is signed with the bundle id as its designated
  requirement (`sign_bundle` in tools/bundle.sh). Don't change the signing line without knowing that.
- **A build restarts only the app it replaced.** `swap-in.sh --restart` restarts the login item only if it runs
  `$HOME/Applications/Whozmove.app` (stopping first a copy that isn't the login item's own, by its checked pid), and a
  copy started some other way only by its checked pid, with a clean environment. So a build for a throwaway home
  (`tests/build.sh`) never restarts the panel you're using. An agent's build never puts its hooks in place (the
  install module leaves them as they are): every session you start runs them.
- **Whozmove sets itself up only from an Applications folder** (`InApplications`, in modules/install). A copy opened
  anywhere else (where it was downloaded, a disk image, a build's folder, or the copy macOS runs one of those from)
  changes nothing: it may be gone tomorrow, and the hooks record only while the app noted in `AppDir/app` is there.
  Hooks you took out of Claude Code are never put back unless you ask, and nothing runs `claude` before Apple's
  developer tools are in.
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
  (`WhyStepsWait`, and the button is dimmed): what goes in place shouldn't be half-way through a change. The next
  steps wait the same way; while the row's own agent is at work, the work line they're on isn't there (`workHTML`).
- **Don't name a script or flag for a deploy.** The session hook counts commands named for one as production
  deploys (`names_deploy` in the hook `whozmove-claude.py`), so building and deploying Whozmove use `build.sh`,
  `--now` and `swap-in.sh`.
- **Sorting and grouping** (`classify`, `stillOnIt`, `placeRows` and `movedAt` in whose-move.js; `heldNow`,
  `noteOnIt` and `state.placed` in panel.js; `noteSeen:` in app/core/Focus.m): what a session is (a request, working, a
  reply you haven't read, however old, one you have, or idle a day after the last message or the last time you were
  on it) is kept apart from where its row is shown. What it is shows on its dot; where it's shown is one list, newest
  message first, as a chat app's (grouped by project, the projects A to Z, so they never move, each with its
  rows in that order): a reply, a request coming or your message takes its row to the top, and a working
  row sorts by when its turn began, so its steps never move it and two working agents don't trade places with every
  step. Only the idle rows go below the rest (`quiet`), so a reply you haven't read never sits under one you were done
  with. The page keeps when you were last on each session while it's yours, across launches (`noteOnIt`): you opened it
  here, wrote to it, or were on it for 2 seconds in Claude, Ghostty or iTerm2 in front while at the Mac (the app's
  `seenAt`). A reply from before then is read. Only a row you've pressed (`keepInPlace`) keeps the place it was last
  shown in, showing what it is now there, until you've moved on from the panel: the pointer off it
  and moved (`hoverEnd`), no box with the keyboard. These are deliberate: read the comments in whose-move.js before
  changing them.

## Animation

`morph(list, html)` (in `panel/scripts/morph.js`) snapshots every row and line, swaps the HTML, then animates
the difference: lines grow and fold (`rowParts`, with how a module's part of a line moves from `core.lines`), changed
text cross-fades, rows slide to their new place (FLIP), and the list's own height eases with them, so the now-playing
strip below it and the panel's bottom edge go with the rows.
Your message and Claude's line are written (`rewriteLine`): the old text erases from its end back to its start, then the
new text writes in from there, each by a soft edge, so the two never meet; what they share at their start, by whole
words, stays (the next step's "Reading "). A reply on two lines writes its first line, then its second, and erases the
other way round. Claude's time beside its working text rides just past what shows, and its label changes as the new
text starts. A new line writes in as its room opens; one that's gone erases, then folds. When both change at once,
yours goes first and Claude's follows, and going, Claude's goes first. All of it fits in the rebuild's own second
(`chatTimes`), and a line that shrinks keeps its room until its old text has gone, the list's height following that
too (`listFrames`).
Rows that keep their order slide underneath; one that passes others glides over them with only a frosted backdrop
(`.row.glide`, `keptInOrder`). Reduced motion (`calm`) skips it all.

The row you're on never leaves the list's visible part (`sticky.js`): whatever takes it past an edge, your scrolling or
the list moving it (to the top as a message comes in, rows above it growing, a shorter list), it holds
on there, at the list's top past its top, at its bottom past its bottom (`stickyHold`). A row that only grows past the
bottom edge, its top staying where it was (a card opening on it), stays as it is, still in view. It never holds on while
one of its boxes is typed in, nor when it's taller than the list's visible part. The row stays in the list, keeping its
place, so nothing in the list moves; a copy of it, laid over the edge, is what holds on, made as the row starts holding
on and gone once it lets go. The copy is as tall as the part of the row's place still in view, so the row next to it
stays touching it, and every point you scroll folds a point off it (`stickyFold`): one line at a time, the one nearest
the moving edge first (from the bottom up at the top edge, so Claude's line comes up under the title last; from the top
down at the bottom edge), until its title line, Claude's line and its bottom line are left. A folding line keeps its
size and gives up its room, the line beside it covering it as it fades (`stickyLineFold`), so nothing in it moves or
squeezes and nothing passes through text. As it attaches, its tint spreads to the list's sides and squares off against
the edge; what's under it is hidden by a mask on the list, as under the header, and attached at the list's top, it meets
the header with no line between them. The row itself is hidden too (`.row.sticky-away`): WebKit scrolls the list a frame
or so ahead of the page laying out the copy and the mask, and in a quick scroll the row's place would otherwise show
past the mask's edge, the row there twice. It follows the scroll position, and every frame anything else moves the list
or the row in it (`reportHeight`), so scrolling back runs it backwards. It follows at once as far as a slow scroll goes
in a frame; what's past that (a quick scroll moves the row tens of points from one frame to the next, as does the list
moving it by itself) it catches up with, all but there in about 0.2 s, without ever passing the row's place
(`stickyEase`), so its lines still fold one after another, and the rows going by meanwhile go under it. Back in view, it
opens out and glides from the edge to the row's place the same way, however far the row came in a frame, and hands back
to the row once it's there. Where it can't take over from the row in place (it starts holding on with the row already
past the edge, or the row's session ends), it fades in or out, the mask fading the other way. When the session you're on
changes while it holds on (you press another row, or switch to another session in Claude or a terminal), it hands its
tint over (`stickyHandOff`): the copy slides off at its edge, out of sight, fading, the list under it uncovered as it
moves off and coming back as it fades, while its tint goes to the new session's row, where that is in each frame, whose
own tint takes over as it lands. The tint is on a layer of its own under the list (`#sticky-under`), so as it goes it's
drawn behind the rows' text, as a row's own tint is. It takes no pointer events, so a scroll over it scrolls the list,
and what the pointer is on there is found by where it is (`stickyAt`); a press on it scrolls back to the row, which
keeps its place meanwhile. Back in view, what's on the row counts as only just shown (`showAgain`), so a card that came
while it was away can't take a press meant for the copy. The copy is inert and has none of the data the page finds a row
by, and leaves out what a module's line has only while it moves (`core.lines`' `still`). Its lines change as the row's
do: what cross-fades on the row does on the copy too, its chat line is written as the row's is, and a copy of other
lines cross-fades in. It
fades with the list as the panel folds into the cat. Under reduced motion it still follows the scroll at once, which is
your own motion, while its fades, text changes and the move back to the row happen at once.

While the panel is folded, what needs you comes out beside the cat by itself (`chats.js`): each chat is the session's
row, the list's own (`rowHTML`, its request card and all, drawn through `morph` so its lines change as the list's do),
on a card of the panel's colour, with a pin, a × and the time it has left as a line along its foot, as tall as its
row, a request's card and all, up to where the screen ends beside the cat, where its row scrolls. Three at most,
newest first, toward the screen's middle: the newest level with the cat's top and the rest under it, or, from a cat
low on the screen, level with its foot and the rest above it; a pill under them says how many more wait. A new one
comes out on top, the others moving down, and the oldest of three goes back in to wait; while you hold one (pointing at
it, typing in it, or in its session's tab, as pressing it puts you), every chat's time stands still, nothing new comes
out, and those out keep their places, a gap left where one answered elsewhere went, until you let go. A chat comes out
from under the cat, or from under the chat before it, fading in as it slides out; going back, it slides back the way
it came, fading, and the one below moves up into its place. The window takes in the room
before anything moves, for where they were and where they go, and only what they need once they're there, each
measured as tall as its row is growing to (`atMorphEnd`), so the window's edge never cuts one off (`askChatRoom`), and
the pill's own room is kept before the screen's edge. Dragged, the cat moves once they've gone in (quickly, toward
it), and they come out again where it stops, the way it then faces; a press that moved far enough to be a drag is one,
even if the cat hadn't moved yet, never a click. The panel opening round the cat, from a
press or the pointer resting on it, each is pulled home into its row in the list as one thing (`chatsLand`), as if on
a spring, carrying a little past its row and settling back, the lowest first, so each moves into room already clear,
shedding its card as it nears its row; one whose row is partly out of the list's sight lands there cut by the list's
edge as its row is, and one whose row is out of sight slides under that edge. The app keeps the room they need till
the glass has spread (`foldMoving`), and the page keeps the rest of the panel out of sight till then, but for the cat
and the name; then the list comes in round them, and each row takes over from its chat. The folded cat's list going
back in as the pointer leaves it, the chats still out are pulled back out on the same spring, top first
(`chatsLeave`), taking their card back as they lift off the list, while the list fades and the glass closes round the
cat; the page names the room they go to with the fold, and the window keeps it from the start. The chat of the session
you're on, held at the list's edge (`sticky.js`), becomes that held row on its way in, in the same move: it moves and
changes shape as one, on the one spring, its lines folding as the held row's do, its tint spreading across the list
and its corners squaring off against the edge, so it has the held row's shape exactly as it stops; going out, it turns
back into its chat the same way (`chatHeldAt`). Moving off the folded cat's list before they've landed, or pointing
at the cat again before they're back out, each turns back where it is, keeping its speed (`chatTurns`), and the glass
turns back with them from where it is (`foldMoving`), rather than either finishing first. Reduced motion fades them in
and out where they are.

Resting on the folded cat a moment, the panel opens as a press on the cat opens it, where a press opens it (`peek.js`),
but for its header: a head as tall stands in for it, the cat in it as it is folded, where the name's o is, and at its
other end how many are waiting on you. The glass spreads out from behind the cat, the list comes in as it does from a
press, and what's held over or under the panel (Spotify's token, the usage card) comes out once it has opened; the
pointer on one of those is still with the panel. Moving off the panel, it folds back round the cat as from a press, the
cat staying as it is, and its chats come back out; with one of its boxes typed in, it folds once the box lets go of the
keyboard. It doesn't come out while the cat is pressed. Pressing the cat, or the head, only finishes opening it, as an
opening does once the glass has spread: the cat shrinks into the name's o, the name coming in from both its sides, and
the header's buttons come in where the head's words were, once they've gone (`catOpening`). The page always has room
above the list (`kAboveRoom`, `--above`), as it has beside it for the reader, for a cat low on the screen, whose chats
go up.

A step's word coming in beside its icon as it's pointed at is CSS (`motion.css`): its room opens, then the word fades
in, lifting 3px as it lands, while what's to its left slides over; pointed away, the word fades first, then its room
closes. It's drawn open as the list is drawn again while it's pointed at (`hoverStep`), so it doesn't come in afresh
each second, as the context ring widening into Compact is.

The usage card moves on its own page (`card.js`), in its own window under the panel, without `morph`: pointed at, it
slides out from under the panel; pressed, it opens as one, growing as its colour shrinks into its row's bar and the
words on it travel to their places in the rows, each measured where it is and where it lands, the rest of the strip
coming in around them; folding runs the other way round (modules/usage/README.md says how). Its wait styles each own a
reset, a function of the time since it started (the vine's is `vineFrame`), so the usage module's tests check its
frames as numbers.

Spotify's token moves natively, as a window of its own under the panel: the core's `EdgeIcon` holds it under the glass
and takes it across to the other side, and modules/spotify/README.md says how it moves, and how a song's lines roll
into the now-playing strip and follow along beside the list.

The reader's panel grows and folds natively (`reshapeTo:` in PanelWindow.m): the window takes in everything the
panel covers on the way at once, the page is laid out and drawn there once, and then only the glass's and the page's
clip's edges move; it folds back to the list's measured height. Don't animate the window's own size: the page would be
drawn again every frame, a frame behind, and its edge would fill in tile by tile. And the page never changes width: it's
laid out once, as wide as the list with room for the reader on either side (`kReaderRoom`, `--side`), and the window
shows only the part in use, so opening and closing the reader never has WebKit lay the page out and draw it again,
which would flash the whole panel. Only its height follows the window. Don't cover a change of size with a picture of
the page either: WebKit draws its pictures on white, which shows through the panel's tint as a pale flash. The tint
itself is in the glass, so it moves with the glass's edges.

The panel turns over natively too (`turnOver:then:` in PanelWindow.m), as one card about its middle: the glass, the
list's page, the back's page (a module's view, `holdBack:`) and the panel's shadow are turned together by Core
Animation, as the folded glass's breath is, so nothing is laid out or drawn again on the way. Both sides are always
drawn, so the back is already there as it comes round; each shows only while it faces you, and they swap edge-on, where
a thin edge in the panel's colour stands across its side. Turning back carries on the same way round, so over and back
make one whole turn. The window first takes in room above and below for the near edge, which comes toward you and is
seen taller than the panel, the glass and the page staying where they are, and is the panel again once it has turned.
What's held over or under the panel (the usage card, Spotify's token) goes from sight in the same frame the turn starts
(`followTurn:`), and comes back in the frame it lands on its list side; an open reader folds back first. Reduced motion
fades one side into the other.

The header stays where it is as the list scrolls (`header.js`) until the row you're on, held at the list's top, has
folded all it can there; scrolling on, that copy pushes it away, point for point (`stickyPush`). It stays as far as it
was pushed, part-way too, until the list has scrolled back to its very top, which brings it back with it. It lies over
the list's top, in room the list keeps for it, the list clipped at its edge, so nothing is laid out again as it moves,
and the row you're on holds on at that edge wherever it is (`headerInset`). The drag strip over it covers only what
still shows (`headerShowing:gone:` in PanelWindow.m), so a press on the rows that have come up under it goes to them.

Whozmove beside the panel (`SideCat.m`, an `EdgeIcon` as Spotify's token is) comes out once the header has gone, at the
panel's top corner on the side facing the screen's middle, and goes back once the header has come back a few points. It
reacts with its face, each of its values on a spring worked out exactly for however long a frame was, on the edge icon's
timer, which runs only while something moves; its eyes' drift is Core Animation's. Pressed, it's held over the panel
instead of under it, and the page folds the panel round it where it is (`foldFromSide`): the page stays put, the list
fading in place, and as the glass closes, the cat grows on the glass's own curve into the folded cat there, its head's
middle never moving. Once the fold has finished, the page puts the folded cat's place back on the name's o, the app
moving the page under the glass, out of sight, and the page's own folded cat takes over in the same place at the same
size (`catLanded`, `catShown`). So opening is the ordinary opening: the panel grows round the cat, which stays put.

A sideways two-finger swipe on the panel's list is the panel's (`swiped:` in PanelWindow.m), taken before the page gets
it; up and down stay the list's, and while one of the page's boxes has the keyboard, the swipe is the box's. The panel
leans with the fingers, and lifting them fast enough sends it off that edge of the screen at the flick's speed, easing
out, fading by how much of it has gone past the edge, so on a display beside it, it never shows. Whozmove beside the
panel stays, peeking out from the screen's edge, and brings the panel back the way it went. What's held over or under
the panel goes as it leaves and comes back as it starts back (`followAway:`). With reduced motion it fades out and back
in. Folded, a swipe is the page's, as it is in a chat beside the cat.

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
- Each colour token has a dark value and a light one, so the panel follows the Look menu: add both, and try both.
  tests/checks.sh fails on a colour without its light value. A colour a script sets is a token too, as `var(--…)`,
  or read with `tokenColour` where a `var()` can't go (an animation's keyframes).

## Pull requests

- One change per pull request, small enough to read in one go.
- For a bigger change, or any new motion idea, open an issue first, so we agree on it before you build it.
- A new pull request starts from a short form (`.github/pull_request_template.md`): what changes and why, how you
  tried it, and a checklist of the rules above. CI builds with every warning an error and runs `tests/all.sh`;
  both must pass.
- Contributions are shared under the project's licence, GPL-3.0-or-later.
