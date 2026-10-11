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

- **`hooks/whozmove-claude.py`**: async hook on UserPromptSubmit, PreToolUse, PostToolUse,
  PostToolUseFailure, Notification, Stop. Writes the session's state file under a `fcntl` lock, atomically.
  Must be fast and must never disturb a session: everything is wrapped so it always exits 0. Works out the
  live line, `stageAt` (when a step or the turn last started or ended), `turnReached`/`outcome` (how far a
  turn took the work), `workSteps` (built/tested/validated) and `audit` (local code review findings).
- **`hooks/whozmove-claude-permission.py`**: synchronous PermissionRequest hook (timeout 3600). Leaves the
  request for the panel and waits for its answer, while Claude's own prompt stays usable; whichever is
  answered first wins. Steps aside at once when the panel isn't running, for sub-agents, non-interactive
  sessions and ExitPlanMode; steps aside later when the call's result shows up in the transcript (settled in
  Claude) or the session ends. Only ever allows once, never "always allow". Don't weaken any of that.
- **`hooks/hooks.json`** and **`.claude-plugin/`**: the two hooks as a Claude Code plugin, `whozmove` (in a
  marketplace of the same name), which is all Claude Code needs to run them. `install.sh` copies it into
  `AppDir/plugin` and adds it from there with `claude plugin`, so Whozmove never edits `settings.json`.
- **`app/`**: Objective-C, ARC, no Xcode project: `build.sh` compiles every `.m` in it. One file per job:
  - `main.m` starts the app, or prints rows for `tests/rows.sh`. `AppDelegate` creates the pieces and wires
    them together, runs the 1-second tick and builds the rows (`readRows`, `sendRows`).
  - Each piece is a small class that keeps only its own state: `Page` (loading the page; every call into it),
    `PanelWindow` (FloatingPanel, DragStrip, size, hover), `MenuBar` (the pawn, grouping), `Sessions` and
    `DesktopConversations` (what's listed), `Transcripts` (what's new in each transcript), `PullRequests` (gh),
    `Checkouts` (git status), `AgentDetails` (model, effort, mode, context, Shift+Tab cycles), `Commands` (model,
    effort, mode and compact from the panel, from the menu to the result), `SettingsFile` (putting the `/model`
    and `/effort` defaults back), and the two ways it sends: into a terminal, and `ClaudeDesktop` (its links
    and the Accessibility API).
  - `Terminal.h` is the shape every terminal fills in: find a session's tab, bring it forward, open a new one,
    put text and keys into a tab. `Ghostty` fills it in through AppleScript; typing a command while keeping the
    draft (`TypeCommand`) is written once, on top of it. A session in any other terminal app opens by bringing
    that app forward. Another terminal is one new file that fills in the shape, added to `terminals` in
    `AppDelegate.m`.
  - The data has a shape: `Row` is one listed session, field by field as **`docs/rows.md`** describes it (the
    contract between the hooks, the app and the page; `tests/rows.sh` keeps the two in step). `Command` is one
    slash command sent from the panel, with its stage (asking, going in, waiting, done, abandoned), and `Reason`
    names why keys can't go into a session right now.
  - Plain functions with a header each: `Log`, `Files`, `Processes`, `Git`, `GitHub`, `Asks`.
  - Nothing slow runs on the main thread. The sessions' files, transcripts, git and gh are read on serial queues,
    and what they find is handed to the main thread, where all the state is kept. The one thing read from both
    sides is Claude Desktop's log (`readFocusLog`), and they take turns.
- **`app/Upstream.h`**: everything Whozmove relies on about Claude Code, Claude Desktop and Ghostty that they
  could change (app ids, where they keep things, links, log line, on-screen labels, the model and mode
  choices). The versions it was last checked with are in the README. When one of them changes, the fix goes
  here.
- **`panel/`**: HTML, CSS and plain `<script>` files: no modules, no build step, no libraries.
  `update()` → `render()` → `morph()`.
  - `panel.html` is the markup, and loads the rest in order: `styles/` (`base`, `rows`, `cards`, `motion`) and
    `scripts/`.
  - `scripts/`, one job each: `util` (the bridge's send, storage, escaping), `state` (everything the page keeps
    between rebuilds, in one object), `whose-move` (which section each session goes in, how it sorts, and the
    label and colour of its work's state: plain functions, checked by `tests/panel.sh`), `icons`, `rows` and
    `cards` (their HTML), `morph` (the animation), `hover`, `input` (one small handler per kind of thing
    pressed), and `panel` (`render`, and every function the app calls).

Bridge, page → native (`type`): `height`, `open`, `newSession`, `pick`, `compact`, `switchAnswer`,
`answerAsk`, `openPR`, `keyboard`, `badge` (each routed to its piece in `AppDelegate`'s `page:said:`).
Native → page: `update(rows, now)`, `setRoom`, `hoverAt`/`hoverEnd`, `setGroupBy`, `toggleCollapsed`,
`askSwitch`, `compactNote` (all in `panel/scripts/panel.js`).

## Build, install, debug

```bash
./build.sh            # compiles (clang -Wall), signs, installs ~/Applications/Whozmove.app, restarts it
./install.sh          # adds the hooks as a Claude Code plugin, sets up the login item (LaunchAgent)
tests/all.sh          # every test below (~25s)
tests/hooks.sh        # both hooks against a throwaway HOME, compared with tests/hooks.expected.txt
tests/rows.sh         # the rows the app builds for a sample home, its mode menus' Shift+Tab counts and the macOS
                      # permissions the README names, compared with tests/rows.expected.txt
tests/panel.sh        # the page's labels, colours, sorting and row HTML (macOS's jsc), vs tests/panel.expected.txt
```

- After editing anything in `app/`, `panel/` or `icon/`: `./build.sh`. After editing a hook or `hooks/hooks.json`:
  `./install.sh`. Sessions run the plugin's copy in `AppDir/plugin`, so a hook you're editing here never runs in
  them half-written.
- `--update` on any of them re-records its expected output after a change you meant; read the diff first.
- `tests/panel-cases.js` holds the page's sample sessions; add a case there for any new label or rule.
- `Whozmove --print-rows` prints the rows the panel would get for the home folder in `$HOME`, as JSON, and
  quits: what `tests/rows.sh` compares. It never asks GitHub, so PRs show as UNKNOWN there.
  `Whozmove --print-mode-moves` prints, for each terminal session, why keys can't go into it now (or that they
  can) and the Shift+Tabs its mode menu would type; the same test checks them, because a wrong answer types
  into a session at the wrong moment, and a wrong count lands it in another mode. Both read files the whole
  Mac shares (Claude Code's managed settings) from that home folder too, so what they print never depends on
  the Mac they run on. `Whozmove --print-typing`
  prints the keys a command is typed with, through a stand-in terminal, and where typing stops once the
  session moves on.
- Native log: `AppDir/panel.log` (`PanelLog`/`LogProblem`). NSLog output isn't kept.
- The UI has no automated test. To try it with sample rows, load `panel/panel.html` in a browser, stub the bridge
  (`window.webkit = { messageHandlers: { panel: { postMessage: console.log } } }`) and call
  `update(rows, Date.now())` with rows shaped as `docs/rows.md` describes. To skip the animations while you
  look, make them instant with `Object.defineProperty(calm, 'matches', { get: () => true })`.
- Try every change on the real app before you call it done.

## Rules that keep it safe

- **Never touch your real sessions or data while testing.** Use a throwaway `HOME` (as
  `tests/hooks.sh` does) and sample rows. Don't compact, change model, or type into a real session to test.
- **Never kill processes by name pattern** (`pkill -f whozmove`, `pkill python`): live permission hooks
  are holding permission prompts in your sessions. Find the exact pid, check it, kill that.
- **`~/.claude/settings.json` holds secrets.** Never log or paste its contents; read the keys you need with a
  JSON parser.
  The panel itself writes it only to put back `/model`/`/effort` defaults, key by key, via JavaScriptCore's
  JSON so the layout stays as Claude Code wrote it.
- **The panel must never take the keyboard.** `FloatingPanel.canBecomeKeyWindow` is `wantsKeyboard`, set
  only while one of the panel's own text boxes is clicked into (`keyboard` message). Clicking a row leaves
  the keyboard with Claude, which is what lets "open a conversation, type straight away" work. Don't
  synthesize clicks or move the pointer to focus things in Claude: it makes the mouse pointer jump.
- **Hover is pointer polling** (25×/s, `pollPointer`), not mouse events: a non-key panel gets no mouse moves.
  Clicks are handled on `mousedown`, not `click`: the list re-renders every second.
- **Typing into a session only when it's safe.** Ghostty: only while idle at its prompt with no request
  pending (`WhyNotTypeInto`), since a stray Enter would approve a permission prompt, and Shift+Tab would allow
  all edits. Claude Desktop: only while idle (`WhyNotSendTo`) and only if its message box is empty; text goes in
  through the Accessibility API ("Prompt" text area, Submit button), not keystrokes. The one exception is a
  Return when Claude shows no Submit button, and only while Claude is in front (`submit:` in ClaudeDesktop.m).
- **`/model` and `/effort` also save a default** for new sessions; the panel puts those settings keys back
  (`holdDefaults`/`releaseDefaults`). Keep that if you add commands.
- **Builds keep their Accessibility grant** because `build.sh` signs with the bundle id as the designated
  requirement. Don't change the signing line without knowing that.
- **Sorting and grouping** (`classify` and `sortKey` in whose-move.js, `goTo` and `state.current` in panel.js):
  Status groups by the agent's state; Activity keeps a session that replied under Your turn until an hour
  passes with nothing happening. The session you're on stays put until you move to another one; a working row
  sorts by when its turn began, so two working agents don't trade places with every step. Each of these is
  deliberate; don't simplify them away.

## Animation

`morph(list, html)` (in `panel/scripts/morph.js`) snapshots every row and line, swaps the HTML, then animates
the difference: lines grow and fold (`PARTS`), changed text rolls in place (`rollLine`; Claude's line rolls
downward, your message upward), rows slide to their new place (FLIP). Rows that keep their order slide
underneath; one that passes others glides over them with only a frosted backdrop (`.row.glide`, `keptInOrder`).
Reduced motion (`calm`) skips it all.

The style: motion is quiet and continuous. A row never vanishes and reappears; no lifted cards, shadows or
dimming of other rows. For a new motion idea, open an issue describing it before building it.

## Style

- Plain words in UI text; say what people will see, not internals.
- Comments explain *why*, in full sentences, as the surrounding code does. Match that.

## Pull requests

- One change per pull request, small enough to read in one go.
- For a bigger change, or any new motion idea, open an issue first, so we agree on it before you build it.
- A new pull request starts from a short form (`.github/pull_request_template.md`): what changes and why, how you
  tried it, and a checklist of the rules above. CI builds with every warning an error and runs `tests/all.sh`;
  both must pass.
- Contributions are shared under the project's licence, GPL-3.0-or-later.
