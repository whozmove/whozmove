# How the pieces fit

Each piece of Whozmove, file by file: what it does and where it lives. The [overview](overview.md) is the short
version, and every message between the page and the app is in [the bridge](../reference/bridge.md).

Whozmove's own folder, `AppDir` below, is `~/Library/Application Support/Whozmove/`: kept out of `~/.claude`
so other agents can be added beside Claude later.

```
Claude Code ──hooks──▶ AppDir/sessions/<id>.json   (last prompt/reply, live step, outcome)
            └──line──▶ AppDir/hook.sock (app/)       (a permission prompt waiting; answered down the same line;
                                                       and words from a side chat, asked for between steps)
a session ──ask-panel.sh──▶ AppDir/ask.sock ──▶ app/ (a task for you; what you allowed it: AppDir/allowed/<id>.json)
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
- **`whozmove-claude-permission.py`**: synchronous PermissionRequest hook (timeout 3600). Asks the panel over a line
  of its own to the panel's socket (`AppDir/hook.sock`, the Claude Code module's `HookLine`), once it has checked the
  panel's own process is at the other end, and waits for the answer down that line, while Claude's own prompt stays
  usable; whichever is answered first wins. The panel takes a request only from a process that runs in the session it
  names, and nothing written in a file answers one. Steps
  aside at once when the panel isn't running, for sub-agents and non-interactive sessions; steps aside later when the
  call's result shows up in the transcript (settled in Claude), when Claude Code says the session has been idle since
  the request (a plan approved, then the turn stopped, leaves no result), or when the session ends. Only ever allows
  once, never "always allow". A plan (ExitPlanMode) is approved from the panel only for a session you allow to (May
  Approve Plans): the panel's answer then carries `approvePlan`, and the hook passes on an allow with an empty input,
  as Claude's own prompt does; it drops a bare allow for a plan, and `approvePlan` for anything else.
  A plan is sent back by a session you allow (May Send Back Plans, the Claude Code module's `AnswerFor`) as your own
  notes would be, marked as that session's, and a question answered by one (May Answer Questions) as the question
  card's answers would be, each marked: the panel answers down the same line, once. In a session you turned
  Don't Wait on Me on for (`dont-wait/<session>.json`), a request no one answers in 5 minutes is turned down for now,
  telling Claude you're away so it carries on and asks again later: never an allow, never stopping the turn, never a
  plan, and never while you're answering it, on its row or in its tab in front with you at the Mac (the panel sends a
  hold down the line, and it waits at least a minute past that). The same hook runs
  before each switch of a session's model (PreModelSwitch, timeout 90): only a switch the panel noted just before
  typing `/model` (`switches/<session>.panel.json`) is its business, which it allows while the conversation's cache
  isn't warm, and otherwise asks in the panel over its line, as a request is asked, stepping
  aside after a minute so Claude asks in the terminal. It never decides a re-read on its own. All of this is
  deliberate.
- **`whozmove-claude-words.sh`** and **`whozmove-claude-words.py`**: synchronous PostToolBatch and Stop hook (timeout
  10), your words from a side chat handed in between a session's steps. The shell part ends at once unless the app's
  flag (`AppDir/words-waiting`) says some wait; then the Python part asks the panel over the same line for its
  session's (`words`), and hands them to Claude as the event's additional context, which Claude reads before its next
  move; at Stop, the turn carries on. The panel hands them only to a process that session itself started (its hook, or a command it runs), each once
  (the Claude Code module's `BetweenSteps`). Skips a sub-agent's tool calls, and says nothing with no panel.
- **`modules/claude-code/plugin/`** (`hooks/hooks.json` and `.claude-plugin/`): the hooks as a Claude Code plugin,
  `whozmove` (in a marketplace of the same name), which is all Claude Code needs to run them. Every build carries a
  copy (`Contents/Resources/plugin`), and each time the app opens, the install module has the agent copy it into
  `AppDir/plugin` and add it from there with Claude Code's own `claude plugin` commands (`PluginInstall`), so
  Whozmove itself never edits `settings.json` for it. Claude Code runs its own copy of the plugin, made per version,
  so each copy gets a version named after the hooks' contents (`modules/claude-code/plugin.sh`): a changed hook gets a
  new one, and Claude Code takes it once told (`claude plugin update`). The session hook records nothing while the app
  noted in `AppDir/app` isn't there, so nothing more of your sessions is written down once Whozmove is removed.
- **`build.sh`**, **`tools/bundle.sh`** and **`app/swap-in.sh`**: `build.sh` makes the app with `tools/bundle.sh`
  (`make_bundle`: the program, the page, the icon, `swap-in.sh`, `ask-panel.sh` (what a session asks the panel), the
  hooks as the plugin, in `Contents/Resources/plugin`, and Betterleaks, which Keys looks with, in `Contents/Helpers`,
  for the Mac the program is built for, with its licence in `Contents/Resources/Betterleaks-LICENSE`: the version
  `tools/betterleaks.txt` names, which `tools/betterleaks.sh` fetches once from its GitHub release into
  `~/Library/Caches/Whozmove-build` and checks against its SHA-256 each time it's used), records where the build came
  from in its `build.json` (checkout, branch, commit, and `agent` when an agent built it), and signs it last
  (`sign_bundle`: Betterleaks on its own first, then the whole bundle, which takes in what's nested only once it's
  signed), so its hooks are sealed in its signature with
  the rest. Then `swap-in.sh` puts the build in place, and `swap-in.sh --restart` restarts the app, which brings the
  hooks it carries up to date as it starts (the install module). When the login item runs the app, it is unloaded and
  loaded again rather than restarted in place, as macOS ties a loaded login item to the build it found. An agent's
  build (one with Claude Code's `CLAUDECODE` mark, which a `!` command in Claude Code has too) never puts its hooks in
  place, and once Deploy is set up for Whozmove in the panel (its command is `./build.sh --now`), it stops after
  compiling while the panel runs with Deploy's button showing, and leaves putting it in place to Deploy, as for any
  project. With Whozmove not running, `swap-in.sh` restarts nothing, and says to open it to run the build.
- **`tools/release.sh`** and **`.github/workflows/release.yml`**: a release is made on GitHub from a pushed version tag
  (`v0.2.0`). `release.sh` builds the app for Apple silicon with `make_bundle`, every warning an error, and signs it
  with `sign_bundle`, refusing unless `app/Info.plist`, the plugin's version and a CHANGELOG section all say that
  version, `tools/betterleaks.txt`'s release line names a finished Betterleaks, the same as its build line, and the
  checkout has nothing uncommitted. It checks the build (its signature and requirement, Apple silicon only, the oldest
  macOS, the hooks it carries, the Betterleaks it carries: signed, for Apple silicon alone, and the release line's
  version; no home folder in it), zips it into `dist/`, and checks the
  copy unpacked from the zip the same way. The workflow runs every test on that copy, then makes a draft release,
  which is published by hand; Homebrew's cask (`whozmove/tap`) names the version and the zip's sha256, which the run
  prints. `--trial` makes a zip to try at any version, without the refusals; run by hand, the workflow makes one and
  keeps it with the run.
- **`app/`**: Objective-C, ARC, no Xcode project: `tools/compile.sh` compiles every `.m` in it, in `parts/` and in
  `modules/` (see [Modules](modules.md)). It holds the core (`core/`), what modules fill in (`contracts/`) and the
  helpers that know no app (`shared/`); `parts/` holds the panel's parts, and everything else is a module. One file per
  job:
  - `main.m` starts the app, or runs one of the print modes the tests check. `AppDelegate` makes the page, the panel's
    window, the pawn, the panel's settings and the core, and starts them.
  - The core's pieces each keep only their own state: `PanelWindow` (FloatingPanel, DragStrip, which covers only what
    shows of the header as it slides away, size, hover, growing beside the list to fit the reader, and back, turning
    over to the panel's back, which a module's view shows, its tint: grey, black or glass, light or dark, and its
    shadow, in a window of its own under it, a module's view held over the page, moving with it, the keyboard and the
    pointer for a site shown in it, a sideways flick sending it off the screen's edge and back, and, folded, the room
    beside the cat for its chats, which lets clicks through where nothing's drawn, and is kept as the panel opens or
    folds while they move into the list or back out: one class in a file per part, `PanelWindow.m` the glass's
    (`parts/glass`, with the page's frame, its `glass.css`), with its windows, its size, the page in it and its shadow,
    and a category of it, `PanelWindow+<Part>.m`, for each of the others, which share what's in `PanelWindow+Private.h`:
    the room beside the cat, the folding, the reader, turning over, the flick, the hover and the keyboard in their
    parts; the class's own interface and what the parts share stay in `app/core`), `Talking` (whether you're talking to
    an agent by voice right now, from who records from a microphone and what was in front as each began), `Allowed`
    (what each session may do by itself, as you allowed it at the foot of its mode menu), `SessionAsks` (what a session
    asks the panel, and which session that is, from the process that asks).
  - The panel's parts with one job each, beside the core, each in its own folder under `parts/` (its `app/` on the
    include path): `Page` (loading the page; every call into it) and `Modules` (every module, found at launch, and the
    page's messages routed to the one that answers each), in `parts/bridge`; `Rows` (the rows read once a second, each
    module adding its part), in `parts/list`; `CatShape` (the folded panel's shapes, for the menu bar's mark and
    `SideCat`), in `parts/cat`; the reader's window and `Browser` (web pages that aren't the panel's own, each in a web
    view of its own, for a module to show in the panel's window: what it may load, whether what it's signed in to is
    kept, where a link that goes somewhere else opens, how it introduces itself, and what a page asks, passed to the
    module that shows it), in `parts/pane`; `EdgeIcon` (an icon tucked half under the glass at the panel's edge, on the
    side facing the screen's middle, Spotify's token among them: its own window, following the glass, changing sides
    under it, coming out once the panel has opened, out of sight while it's turned over, and its label), `SideCat`
    (Whozmove beside the panel while the header has gone, an edge icon: its moves, folding the panel round it, a drag
    moving the panel, and bringing the panel back from the screen's edge), `Focus` (the session you're on, when you last
    looked at each, and opening a session from its row), `MenuBar` (the pawn, its menu, the modules' items among it,
    Settings… one, and the panel's switches, Show Next Steps and Show Deploy, which Git's page on the panel's back
    sets), `Settings` (the panel's own settings, its look and the list's order, the modules' ways to group it among it,
    kept and put on the panel, and their rows in Settings), `Send` (words into a session, why they can't go in now, and
    the way past a terminal's reason), `Work` (who's at work in a checkout), `Builds` (the running build, for the
    header) and `Printing` (what the print runs share). Each part's README says what it owns, who it talks to and its
    rules.
  - The agent that runs the sessions is a module: `claude-code` (its sessions and its hooks' records, its terminal
    sessions kept once they've ended, what's new in each transcript, a session's details, the words of the panel's
    commands and what their results say, typing into a session's prompt while keeping its draft, your plan's usage
    asked of `claude`, folder trust, a new session's command and an ended one's, its hooks plugin, put into Claude
    Code and kept up to date there with its own commands, and the sessions that don't wait on you).
  - The apps sessions run in are hosts, each a module too: `ghostty` (finding a session's tab, typing into it, which tab
    it shows), `iterm2` (finding a session's tab by its terminal device, typing into it through its Python API, else
    while it's alone in its window, which tab it shows, and a command in a new tab; its sessions can outlive the app,
    under a server of its own, so it says which processes it runs), `claude-desktop` (its conversations, its message
    box, new conversations, "Switch model?", and Claude's page on the panel's back, on every Mac, for Claude as a
    whole, where its sessions are tracked or not) and `terminal-app` (macOS's Terminal, which only runs a command: Sign in,
    on a Mac without Ghostty or iTerm2). A session in any other terminal app opens by bringing that app forward. Another
    terminal is one new module that fills in the host contract.
  - Each feature is a module: `git` (`Checkouts`: git status, each checkout's base branch and new files, and which of
    its files are staged; `NextSteps`: the steps a checkout has to take, Commit and its ways, Push, Publish and Create
    PR into the branch you pick, each asked of the agent in fixed words, and the branches on GitHub for Create PR's
    card; `PullRequests` and `GitHub`: the PRs, from gh), `deploy` (`Deploys`: each project's deploy command, the one
    it suggests, running it detached with a log, each folder's last run, and each project's build in place, which
    other modules read through `BuildsInPlace`; `DeployMenu`: its round button's menu; `DeployAsks`: Let It Deploy,
    and the deploys sessions ask for, waiting until they can run), `changes` (`Changes`: what isn't committed in each
    checkout, from git, as git status splits it, not staged (new files included) and staged, with each changed line
    credited to the session whose edits (or its sub-agents') match it, its shell commands' too (as its agent records
    them), else outside the sessions: the checkout's numbers on a row, and the changes view, made JSON off the main
    thread; and the commits not on GitHub yet, one by one, read ahead while there are some, so the view's Outgoing
    opens at once; `Editors`: the editor a file opens in, offered from the editors it knows, the ones installed,
    chosen once, kept, changed from Open Files With in Settings, which other modules open their files in through
    `FilesAtLines`), `reader` (what a session wrote; a prototype from its file, in a `Browser` held over the reader's
    body, and opened in your web browser), `usage` (`Usage`: your plan's usage, asked of the agent every few minutes,
    for the usage card; Sign in; `UsageCard`: the card under the panel that shows it, a window of its own with a page
    of its own), `starts` (`Starts`: a new conversation from the panel's card, the folder's trust checked, the session
    opened with your words, and watched for until it's listed; `Worktrees`: a worktree of its own for one; `Shortcut`:
    ⌃⌥N, and its switch in Settings), `bring-forward` (held keys bring a session you pick forward from any app:
    `HeldKeys`, a hold told apart from which modifier keys are down and how many keys have been pressed; and its page
    in Settings), `commands` (the model, effort and mode menus and the Compact card, from the menu to the command's
    result), `spotify` (the now-playing strip, with its lyrics from LRCLIB, which open beside the list, Spotify's
    token, and its music quieter while you talk to Claude, `SpotifyVolume`), `storage` (`Disk`: how full the disk is,
    looked at every minute, how fast it's filling, and the line above the list when it's running low; `Scanner`: the
    map of your disk, measured once Storage is on, what can't go to the Trash and why, and moving what you collected
    there; `CleanUp`: what comes back on its own, found on the map, and cleaning it, folders to the Trash and each
    tool's own command; `StorageFacts` and `CleanUpFacts`; Keys, Storage's third part, `KeyScan`: the keys left where
    they shouldn't be, found by itself from the first launch with the Betterleaks the app carries, in the checkouts
    the sessions are in, their commits not pushed yet, AI tools' records (the agent's own, `AgentRecords`, and other
    tools'), credential files others can read, shell histories, Downloads and Whozmove's own records, each kept as its
    kind, masked form and places, and what can be done with each, and `KeyFacts`; and Storage among the tools on the
    panel's back), `sessions` (Sessions, on every terminal's page and Claude's on the panel's back: every conversation
    the agent keeps, `AgentConversations`, those a host keeps itself left to it, and ticked ones moved to the Trash,
    ended first while open; `Trashed`: where each one's files went, for Undo and Put Back), `team` (`Team`: the team
    file a session leading a team of sessions can keep, read when it changes, and each row's place in it, and each
    team as a whole for the others (`TeamFacts`); and Group by Team among Settings' ways to show the list), `board`
    (`BoardModule`: each team as a whole sent to the page as the file changes, and Team Board among the tools on the
    panel's back), and `notifications` (`NotificationsModule`: what every module has to tell you, gathered as the rows
    are read, sent to the page with whether the panel is hidden or flicked off the screen's edge, a press run through
    the sender's own, and Working on Whozmove ▸ Preview Notices; `NoticeRules`: what you put away and until when, kept
    in `AppDir/notifications.json`). And `apps`, the panel's back (`AppsModule`: the apps every module works with,
    Settings first among them, its rows the panel's own and every module's, each choice's page; each app's page with
    its switches, its cards, its lists and what macOS lets Whozmove do with it; and Settings… in the pawn menu;
    `BackPage`: the back's web view, on the back of the glass). And `install`, Whozmove setting itself up as it opens
    (`Install`: from an Applications folder only, where it runs from noted for the hooks, the agent looked for,
    Apple's developer tools waited for, which only the agent's sessions need, with Install opening macOS's installer
    for them (`ToolsFacts`), then the hooks put into the agent or brought up to date there, `AgentInstall`; Open at
    Login, on from the first open, kept as you set it in the pawn menu, `LoginItem`; its own record in
    `AppDir/install.json`; `Reloads`: the sessions running since before the hooks went in, which run without them
    until they reload them, reloaded from the line or each one's row, one at a time, each once it's idle, with the
    agent's own command, through `Send`; `Updates`: a newer Whozmove out, for a copy Homebrew installed, read from its
    tap's cask (`HomebrewFacts`), said on the line with the command that updates it, and never installed from here;
    and the line under the header that says what it needs from you, with the cards it adds to Git's page and the one
    the agent's settings go on, Claude's, on the panel's back).
  - The data has a shape: `Row` (app/contracts) is one listed session, field by field as **`docs/reference/rows.md`**
    describes it (the contract between the hooks, the app and the page; `tests/rows.sh` keeps the two in step).
    `Command` (the commands module's) is one slash command sent from the panel, with its stage (asking, going in,
    waiting, done, abandoned), `Reason` (app/contracts) names why keys can't go into a session right now, and
    `Notice` (app/contracts) is what a module has to tell you.
  - Plain functions with a header each, in `shared/`: `Log`, `Files`, `Processes`, `Git`, `CheckoutWatch` (which
    checkouts may have changed, from macOS's file system events, so git runs only for those), `Text`, `OtherApps`
    (whether Whozmove may act on other apps now: only when this run's home is surely yours), `AppleEvents`,
    `AppleScript`, `Accessibility`, `Links`, `Menus`, `Appearance`, `EditKeys`, `Audio`, `UnixSockets` (a socket only
    you can connect to, and who's at its other end), `Signature` (who signed a running program, from the copy of its
    signature macOS keeps, so a program deleted since it started still says), and `Easing` (the curves the panel moves
    on, shared by `PanelWindow`, `EdgeIcon` and `SideCat`).
  - Nothing slow runs on the main thread. The sessions' files, transcripts, git and gh are read on serial queues,
    and each terminal is asked which tab it shows on one of its own, and what they find is handed to the main thread,
    where all the state is kept (a terminal's answer is matched to a session there, from what's already been read).
    The one thing read from both sides is Claude Desktop's log (`DesktopLog`'s `catchUp`), and they take turns.
- **Facts**: everything Whozmove relies on about another program that it could change is in that program's module
  (`ClaudeCodeFacts.h`: where Claude Code keeps things, its command, the model and mode choices; `ClaudeDesktopFacts.h`,
  `GhosttyFacts.h`, `ITerm2Facts.h`, `SpotifyFacts.h`, and beside it `LRCLIBFacts.h`, for the lyrics' web service;
  Storage's `StorageFacts.h`, for macOS's folders, and `CleanUpFacts.h`, for developers' tools' caches and commands),
  what it knows of the editors Open Files With offers is in the changes module's `Editors.m`, what Keys relies on about
  Betterleaks and other AI tools' records is in Storage's `KeyFacts.h`, and how macOS puts Apple's developer tools in,
  and how its launchd opens Whozmove at login, are the install module's (`ToolsFacts.h`, `LaunchdFacts.h`), as is what
  it reads of Homebrew to tell a new version is out (`HomebrewFacts.h`). What a `Browser` relies on to introduce itself
  as Safari is the pane part's, beside it, in `BrowserFacts.h`, and the setting of macOS's own that lets the panel show
  the hand and the text cursor while another app is in front is in `PanelWindow.m` (`LetPointerShapesIn`). macOS draws
  a light line round the edge of any window with its own shadow (`hasShadow`), which shows on a dark panel, so the
  panel has none and draws its shadow in a window of its own under it (`PanelWindow.m`'s shade).
  The versions they were last checked with are in docs/using/install.md. When one of them changes, the fix goes there.
- **`panel/`**: HTML, CSS and plain `<script>` files: no modules, no build step, no libraries.
  `update()` → `render()` → `morph()`.
  - `panel.html` is the markup, and loads the rest in order: `styles/` (`tokens`, the panel's colours, text sizes and
    corners by name; `base`, the row part's `rows` and `cards`, `controls` (the kit: what more than one part draws, each
    piece styled once, from the switch, a button and its quiet, small, main and split kinds, an icon button, a tag, a
    box to tick, a box to type in, a short list, a bar and the tabs to a one-line message with its button, a tray of
    things to move to the Trash and a card's head, title and lead), the pane part's `reader`, its frame; the chats part's `chats`, the cat part's `cat` and the
    peek part's `peek`, the folded cat's, and what comes out of it; the modules' styles; and the morph part's `motion`)
    and `scripts/`, the modules' scripts last but for `panel` and the bridge part's `app-calls`. The parts' files are
    loaded among them, each where its line in the page names it, in the order `tools/page.sh --scripts` and `--styles`
    print. `tools/page.sh` lists the modules' at the two lines the page marks for them.
  - `scripts/`, one job each. The page's core first: `util` (the bridge's send, storage, escaping, measuring text),
    `state` (everything the page keeps between rebuilds, in one object), the bridge part's `modules` (what the modules
    plug into the page with: see [Modules](modules.md)), the row part's `fresh` (whether a card or button has only just
    been shown, a row's again once it's back in view, and a request answered here), the list part's `whose-move` (what
    each session is, the list's order, and which session speaks for each checkout: plain functions, checked by
    `tests/panel.sh`), `icons`, the pane part's `markdown` (plans and notes as HTML, everything escaped: a plain
    function), the header part's `builds` (the header's name for the running build), the morph part's `morph` (the
    animation), the list part's `strips` (changing a strip's text, and easing, growing and folding it, for any strip
    under the list), the row part's `rows` (a row's template, with its places for the modules' parts, and the group and
    project headers), the hover part's `hover` (what's pointed at, and telling a row's details what it's on; see its
    [README](../../parts/hover/README.md)), the details part's `details` (a row's details, opened inside the row under
    its lines: how they go, `detailsNext`, a plain function checked by `tests/panel.sh`, drawing them in their row,
    opening and folding them; see its [README](../../parts/details/README.md)), the list part's `input` (presses and typing), the keyboard part's `keyboard`
    (when the panel takes the keyboard, and gives it back; see its [README](../../parts/keyboard/README.md)), the pane
    part's `reader` (the reader beside the list, which its modes fill, each about a session, or, like Spotify's lyrics,
    about none), the cat part's `cat` (the folded cat: its pose, its eyes on the pointer, its place on the name's o, the
    room beside it, and the panel opening round it and folding back), the chats part's `chats` (what needs you, out
    beside the folded cat by itself as its row: see [Motion](motion.md); where they go is plain functions, checked by
    `tests/panel.sh`, and which come out and when is the notifications module's), the landing part's `landing` (the
    chats going into their rows as the panel opens, and back out), the peek part's `peek` (the panel opening while the
    folded cat is pointed at, its header standing aside for a head of its own: see [Motion](motion.md)), the header
    part's `header` (the header pushed away by the row you're on, and back: see [Motion](motion.md); how far it has gone
    is plain functions, checked by `tests/panel.sh`; see its [README](../../parts/header/README.md)), the held part's
    `sticky` (the row you're on, held at the list's edge as the list scrolls past it, folded down: see
    [Motion](motion.md); how it folds is plain functions, checked by `tests/panel.sh`), the handoff part's `handoff`
    (its copy letting go, or sliding off as the session you're on changes), `waiting` (a request coming into view by
    itself, the strips at the list's edges naming those out of view while they wait there, and the card you're on kept
    still as rows move round it: see [Motion](motion.md); what to do is plain functions, `waitingNext` and
    `waitingLook`, checked by `tests/panel.sh`), the beside part's `beside` (its place on the page,
    `core.places.besideEdge`, told by notifications how many need you; see its
    [README](../../parts/beside/README.md)), and the list
    part's `panel` (`render`; the frame's own functions the app calls are the bridge part's `app-calls`, loaded after
    it). Then each module's, from its `page/`, one per job, each plugging into the core as it loads: the install
    module's `install` (what the line under the header says while Whozmove sets itself up, or when a new version is out,
    and how its × holds: plain functions) and `install-line` (drawing it in its place under the header, `#install`,
    growing in, changing its words and folding away, its button and its ×) and `reload-row` (a session running since
    before the hooks went in, on its row: that it started before the update, with Reload, and its note); Claude Code's `agent` (what a Claude
    Code session's model, mode and context mean) and `requests` (its requests, questions and plans on a row); the
    commands module's `commands` (the model, effort and mode labels, the context ring, the Compact card, and the card
    while a pick goes into a terminal session) and `switch-model` ("Switch model?", asked on its row for Claude Desktop
    and terminal sessions alike); the next steps (`steps`: which a checkout has to take, `stepsOf`, how its last code
    review went, and where a branch stands while commits wait, plain functions; `git-steps`: their icons on the work
    line, their words as they're pointed at, Create PR and its details, and the review or where the branch stands; `prs`:
    the pull requests, their details, and "+N more open"'s); Deploy (`deploys`: whether a row has its round button, how it looks, and the
    set-up card, plain functions; `deploy-row`: the button, the line and the card on a row); the reader's `writings`
    (what a session wrote: its tag, and the reader's `writings` mode, where a plan is sent back or stopped, and a
    prototype's space and the line above it); `changes` (the view's tabs, git's letters for each file, what its head
    says, and how lines are laid side by side: plain functions) and `changes-view` (the numbers, their details, and the
    reader's `changes` mode); and `starts` (the card for a new conversation, which opens under the header, the pending
    row a start shows as until it's listed, and the card turning into that row and moving down to its place;
    `start-words`: what the card reads in your words, @ for the project and # for where in it, and a new worktree's
    name, plain functions); and Storage's `disk-line` (the line above the list when the disk is running low, or when the
    map you were waiting for is ready), `map` (the map's rings and sizes, plain functions), `clean` (Clean up's list,
    plain functions), `map-view` (the reader's `storage` mode and its tabs) and `clean-view` (the Clean up tab); the
    team's `team` (Group by Team: its groups, every row short with its job's track, and what waits on you or where its
    job stands: plain functions); the board's `board` (where each job stands, who's on what, the goals as tiles, what's
    done this week, the kinds of what needs you and how many are in One Task, and what Take Me There opens: plain
    functions, and Up next's rows, line and words) and `board-view` (the reader's `board` mode, Glance, Up next for all
    goals or one, a job's card, and Up next or Team Board on the chief's line); notifications' `decide` (what the line under the header shows and how many wait, where
    each place is in sight, which sessions come out beside the folded panel and when, and how many the edge counts:
    plain functions), `notices`
    (running it and filling each place) and `notice-line` (the line in its place under the header, `#notices`, growing
    in, changing its words and folding away, its button, its +N and its ×). Last, Spotify's: `now-playing` (what the
    now-playing strip shows, plain functions), `lyrics` (a song's lines and pauses from its LRC, and which shows when,
    plain functions), `np-strip` (drawing the strip, its words rolling in place, and its presses), `lyrics-view` (the
    one timer that changes the lines, and the reader's `lyrics` mode) and `spotify` (what it plugs in, and the functions
    the app calls).
  - A module can have a page of its own too, for a window of its own: the usage module's card, `card.html`
    (modules/usage/page/), in the card's window under the panel. It loads the panel's tokens, `controls` and `util`,
    then its
    own `usage` (what the card shows, plain functions), `waits` (its wait styles, chosen by name, each a file of its
    own, `wait-vine` the first, whose shape and reset are plain numbers too) and `card` (drawing the card folded,
    slid out and open, opening and folding it, the pointer and presses on it, and the functions the app calls).
    And the apps module's `back.html` (modules/apps/page/), the panel's back, in a web view of its own on the back of
    the glass: the panel's tokens, `base` (so its header is the list's) and `controls`, `util` and `icons`, then its
    own `apps` (Settings' cards and pages, and the settings once one is pressed; what an app's permission says, what
    its cards show, and the switches once one is pressed: plain functions) and `back` (drawing the apps, Settings, each
    choice's page and each app's, going between them, the pointer and presses, and the functions the app calls).
