# Working on Whozmove

A floating macOS panel listing every Claude Code session on this Mac (Claude Desktop and terminal), with
what each is doing, whose move it is, and controls to answer prompts, change model/effort/mode, compact
and jump to a session. **README.md** is Whozmove's front page: what it does, in pictures, and how to install it.
**docs/using/** has every part of the panel in detail. A change people can see gets a line in the CHANGELOG's
Unreleased section (start `## Unreleased` at its top when there isn't one) and in its docs/using page. The front page
changes only when a feature earns a place there, which is decided before each release, so a feature's pull request
leaves README.md as it is but for the few parts Pull requests names. This file is how to work on it: building,
testing, the rules that keep it safe, and sending a change. How it's built is in
[docs/how-it-works](docs/how-it-works/overview.md). Everyone taking part, in issues, pull requests or anywhere
else, follows the [code of conduct](CODE_OF_CONDUCT.md).

## How the pieces fit

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

Each piece, file by file, is in [How the pieces fit](docs/how-it-works/architecture.md), and every message between
the page and the app in [the bridge](docs/reference/bridge.md). The [overview](docs/how-it-works/overview.md) is
the short version.

## Modules

Each outside program Whozmove works with, and each feature, is a module in a folder of its own, so a change in one
program is fixed in its module alone. How a module plugs in is in [Modules](docs/how-it-works/modules.md), and
[Adding a module](docs/guides/adding-a-module.md) walks through making one.

- The panel itself is made of parts, each in a folder of its own under `parts/` (a row's details are
  `parts/details/`), in a module's shape: its `part.json` names its page files, who it talks to (`talksTo`: `core`, and
  the parts it names) and what it gives the others (`provides`), and its README what it owns and its rules.
- `tools/compile.sh` is the one compile line, for build.sh, the tests and CI. Only `app/` and its `core`, `contracts`
  and `shared` folders, and each part's `app/`, are on its include path, so a module can't import another module's
  header, nor the core or a part a module's. It builds for the oldest macOS `app/Info.plist` names
  (`LSMinimumSystemVersion`), so a newer call made without checking for it is a warning, and fails CI.
  `tools/page.sh` puts the page together: the panel's files and the parts' where `panel/panel.html` names them, each
  module's at the page's marks, and a module's own pages (module.json's `pages`) beside it.
- A module keeps the facts about its own program (Spotify's are in modules/spotify/app/SpotifyFacts.h, Claude Code's
  in modules/claude-code/app/ClaudeCodeFacts.h).
- Preference keys keep their names: build.sh reads `showNextSteps` and `showDeploy`, and every switch and choice keeps
  what you picked across launches, under the name it has always had (`panelLook`, `appearance`, `openWith`,
  `newConversationShortcut`), wherever it's set from now; a key no longer read (`groupBy`, the list's order before it
  had one view) is never used again for another choice.
- A choice you make once and come back to now and then is a row in Settings (Module's `settingEntries`, or the settings
  part's `Settings`), not an item in the pawn menu: the menu keeps what has to work while the panel is hidden, folded or
  lost off the screen.
- On the page, a module only registers with the core as its scripts load, and never calls another module's functions
  or reads its state: [Modules](docs/how-it-works/modules.md).

### Architecture

`tests/checks.sh` keeps the walls up. What it can't check is whether each piece of work is in the right place, so every
plan and change is held to these ten principles. Each one's why, with an example from the code, is in
[Modules](docs/how-it-works/modules.md#architecture).

1. **One job per module or part.** Its README says the job in a sentence, and a second job gets a folder of its own.
2. **Services know nothing about sessions or features.** The core, the parts, the contracts, the shared helpers, the
   bridge and the notifications module each give one ability to whoever asks. They never decide what a session, a
   request or a song means.
3. **A feature is a module of its own,** with its own folder, README and tests. It uses the services, and never lives
   inside one of them or inside another feature.
4. **The core and the parts name no outside app or feature.** They reach them only through the contracts.
5. **What Whozmove relies on about an outside program lives in that program's module,** in its facts header.
6. **Modules and parts meet only through contracts.** No module depends on another's code, state, files or words.
7. **One owner for each piece of data, style and rule:** one writer, and one place that decides it.
8. **Decide in plain functions, and draw in a separate file,** so the rules are tested without the screen.
9. **Every feature works for any project.** Tools for working on Whozmove itself stay in Working on Whozmove ▸.
10. **Grow by adding a folder.** Add no contract, part, layer or setting until something uses it.

## Build, install, debug

```bash
./build.sh            # compiles (clang -Wall), signs, puts ~/Applications/Whozmove.app in place, restarts it (it
                      # brings its hooks up to date as it starts); an agent's only compiles, once Deploy is set up
                      # for Whozmove (see below), or once you sign your own builds; it signs with your Developer ID,
                      # asking your signing keychain's password, once that's set up (docs/guides/signing.md)
./build.sh --now      # the same, as Deploy runs it (from an agent, it still only compiles)
./install.sh          # ./build.sh, then opens the app, which sets itself up as it opens (its hooks, Open at Login);
                      # --uninstall takes the app, its login item and its hooks out
tools/release.sh X.Y.Z --trial # builds, signs, checks and zips a release to try into dist/, publishing nothing; a
                      # release itself is made only by the release workflow, signed with the Developer ID and notarised
tools/energy.sh now 5 # what the running Whozmove costs over 5 minutes, read-only (also launch, week):
                      # docs/how-it-works/energy.md
tests/all.sh          # every test, the app built once for all of them (~80s)
```

Each test on its own, and what it checks, is in [Tests](docs/reference/tests.md).

- After editing anything in `app/`, `parts/`, `modules/`, `panel/` or `icon/`: `./build.sh`. After editing a hook or its
  `hooks.json` (modules/claude-code/plugin/): `./build.sh` too, in your terminal: the app puts the hooks it carries in
  place as it restarts (an agent's build leaves them as they are). Sessions run Claude Code's copy of the plugin, made
  from the one in `AppDir/plugin`, so a hook you're editing here never runs in them half-written, and a change reaches
  only sessions started after it.
- With Deploy set up for Whozmove (press Deploy on one of its rows once and confirm `./build.sh --now`, the
  suggestion), an agent's `./build.sh` only compiles, and Deploy on a row puts that checkout's build in place when you
  press it. Tick Show Build in Header (hold ⌥ as you open the pawn menu: Working on Whozmove ▸) and the header says
  which build you're running.
- `--update` on any [test](docs/reference/tests.md) records its output again after a change you meant: read the diff.
- `tests/panel-cases.js` holds the page's sample sessions; add a case there, or in a module's own
  `tests/page-cases.js` when it has one, for any new label or rule.
- Every print run (`Whozmove --print-rows` and the rest), what it prints and which test checks it, is in
  [Print runs](docs/reference/print-modes.md).
- To see the usage card's wait and reset without a limit to wait for: hold ⌥ as you open the pawn menu, Working on
  Whozmove ▸ Preview the Wait. To see the line under the header without waiting for something to need you: Working
  on Whozmove ▸ Preview Notices, which sends made-up notices through the real path, one every 8 seconds.
- Native log: `AppDir/panel.log` (`PanelLog`/`LogProblem`; `swap-in.sh` writes there too). NSLog output isn't kept.
- The UI has no automated test. To try it with sample rows, put the whole page together in a new folder with
  `tools/page.sh <folder>`
  (`panel/panel.html` alone doesn't run: it names the parts' files by their place in that folder), load that folder's `panel.html` in a browser (its list's column
  starts `--side` in, as the page is laid out with room for the reader on either side: set `--side` to `0` there), stub
  the bridge
  (`window.webkit = { messageHandlers: { panel: { postMessage: console.log } } }`) and call
  `update(rows, Date.now())` with rows shaped as `docs/reference/rows.md` describes. To skip the animations while you
  look, make them instant with `Object.defineProperty(calm, 'matches', { get: () => true })`. The usage card's page is
  there too, in `modules/usage/page/card.html`: stub its bridge the same way, and call `setUsage(…)` with usage shaped
  as [its bridge](docs/reference/bridge.md) describes,
  and `cardPointer({x, y})` to point at it (the panel's bottom edge is 24px down).
- Try every change on the real app.

## Rules that keep it safe

Each rule is here whole, or as its headline with a link to the rest, where it applies.

- **Nothing goes online, starts a program or comes from outside the project unlisted, and macOS checks every
  certificate.** Each needs its line in `tests/outside.txt`, in the same change, and the README's Privacy says what it
  sends, keeps or reads. Every certificate check is macOS's: no App Transport Security exception, no answering a
  certificate challenge in code, no `curl -k`, and only `https://` leaves this Mac.
- **What comes from outside is shown as text.** A session's words, what comes from the web or another program
  (lyrics, a pull request's title) and anything else the panel didn't write go into the panel's page escaped (`esc`),
  never as HTML, since that page can answer a request for your OK: [the panel's own
  rules](docs/how-it-works/panel-rules.md).
- **Never touch your real sessions or data while testing.** Use a throwaway `HOME` (as the Claude Code module's
  tests do) and sample rows, made up: no real paths, prompts, names or session ids. Take the home folder from `HOME`
  (`Home()` in the app), never `NSHomeDirectory()` or the account's record, which ignore it: tests/checks.sh fails on
  one. Every test runs in a macOS sandbox of its own (tests/sandboxed.sh), which lets it write only to the temporary
  folders. Don't compact, change model, or type into a real session to test.
- **Never kill processes by name pattern** (`pkill -f whozmove`, `pkill python`): live permission hooks
  are holding permission prompts in your sessions. Find the exact pid, check it, kill that.
- **`~/.claude/settings.json` holds secrets.** Never log or paste its contents; read the keys you need with a
  JSON parser.
  Claude Code's own `claude plugin` commands, which the app runs to put its hooks in, write their entries there. The
  panel itself writes it only to put back `/model`/`/effort` defaults, key by key, via JavaScriptCore's JSON so the
  layout stays as Claude Code wrote it.
- **The panel must never take the keyboard.** It has it only while one of its boxes, a card or a site in it, or the
  view open beside the list, has been clicked into, or the new conversation card is open, and then hands it back to the
  app in front: [the panel's own rules](docs/how-it-works/panel-rules.md).
- **Only the panel's own page talks to the app.** A page Claude wrote must never answer a request: [the panel's own
  rules](docs/how-it-works/panel-rules.md).
- **A changed file opens only from its checkout's changes,** in the editor you chose: [the changes module's
  rules](modules/changes/README.md#rules).
- **Hover is pointer polling,** not mouse events, and clicks are handled on `mousedown`: [the panel's own
  rules](docs/how-it-works/panel-rules.md).
- **Whozmove runs no git of its own before Apple's developer tools are there**: [the install module's
  rules](modules/install/README.md#rules).
- **Typing into a session only when it's safe:** idle at its prompt, no request waiting, and never where a key could
  land in another copy or another session: [the panel's own rules](docs/how-it-works/panel-rules.md).
- **`/model` and `/effort` also save a default** for new sessions, which the panel puts back; keep that if you add
  commands: [the commands module's rules](modules/commands/README.md#rules).
- **Folder trust is recorded only for a folder you trusted on the card**: [the Claude Code module's
  rules](modules/claude-code/README.md#rules).
- **Builds keep their Accessibility grant** because each is signed the same way every time (`sign_bundle` in
  tools/bundle.sh): releases, and your own builds once you've set it up, with the developer's Developer ID and macOS's
  own rule for it, which names the team; others ad hoc, with the bundle id as their designated requirement. Every
  program in the bundle runs with the hardened runtime. What the
  runtime holds back that Whozmove needs is an entitlement in `tools/Whozmove.entitlements`, added only with the code
  that uses it; get-task-allow, allow-dyld-environment-variables, disable-library-validation,
  allow-unsigned-executable-memory and allow-jit never go in. A signing key signs only after asking for its keychain's
  password, and an agent's build is never signed with it: [Signing your own builds](docs/guides/signing.md). Don't
  change the signing lines without knowing all that.
- **The app never loads its own login item into launchd**: [the install module's
  rules](modules/install/README.md#rules).
- **A build restarts only the app it replaced.** `swap-in.sh --restart` restarts the login item only if it runs
  `$HOME/Applications/Whozmove.app` (stopping first a copy that isn't the login item's own, by its checked pid), and a
  copy started some other way only by its checked pid, with a clean environment. So a build for a throwaway home
  (`tests/build.sh`) never restarts the panel you're using. An agent's build never puts its hooks in place (the
  install module leaves them as they are): every session you start runs them.
- **Whozmove sets itself up only from an Applications folder**: [the install module's
  rules](modules/install/README.md#rules).
- **Only the panel answers a request for your OK,** down the line the hook opened to it, never a file:
  [the Claude Code module's rules](modules/claude-code/README.md#rules).
- **Only Claude Code's own program asks the panel in a session's name,** its build signed by Anthropic, never a
  record in Claude Code's registry alone: [the Claude Code module's rules](modules/claude-code/README.md#rules).
- **A session answers for you only as its switch says**, kept only in the panel's memory, for the lead's folder while
  Whozmove runs, and set only by your press. The team file says which session there holds it, checked to be Claude
  Code alone in that folder by what the system reports, never which folder, and a line under the header shows each
  time it moves to a new session.
  May Send Back Plans sends a team member's plan back with a note, never approves one, and May Answer Questions
  answers a team member's questions, never a request for your OK, and May Approve Plans approves only the plan as
  listed, never one whose file has changed or from a session that might bypass permissions: [the Claude Code module's
  rules](modules/claude-code/README.md#rules).
- **Deploy runs only what you confirmed,** and never while another agent works in that folder, or, for your press,
  while the row's own agent works or asks: [the deploy module's rules](modules/deploy/README.md#rules).
- **Only your press lets a session do more by itself,** at the foot of its mode menu, never a message from the page:
  [the panel's own rules](docs/how-it-works/panel-rules.md).
- **Only your press moves the gear,** on a seat of the usage card's: never the recommendation, a session or a file:
  [the usage module's rules](modules/usage/README.md#rules).
- **Don't name a script or flag for a deploy.** The session hook counts commands named for one as production
  deploys (`names_deploy` in the hook `whozmove-claude.py`), so building and deploying Whozmove use `build.sh`,
  `--now` and `swap-in.sh`, and a session asks for a deploy with `ask-panel.sh put-in-place` (the deploy module's
  tests check the hook takes none of these for one).
- **Storage moves things to the Trash, never deletes them, and only what its own measure found**: [the storage
  module's rules](modules/storage/README.md#rules).
- **A key never leaves the Mac, and is never kept whole**: Keys keeps only a key's kind, how it starts, its last 4
  characters and a fingerprint, never edits another app's files, and the tests' keys are made up as they run: [the
  storage module's rules](modules/storage/README.md#rules).
- **Sorting and grouping** are deliberate: read [the panel's own rules](docs/how-it-works/panel-rules.md) and the
  comments in whose-move.js before changing them.

## Animation

How each part of the panel moves, from the list's rows to the panel turning over, is in
[Motion](docs/how-it-works/motion.md): read it before changing any motion.

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

What the eye should follow through a change (nothing just vanishing, one thing at a time, the pointer kept on what
it aimed at) is in [Experience](docs/how-it-works/experience.md#motion).

For a new motion idea, open an issue describing it before building it.

## Style

- Plain words in UI text; say what people will see, not internals.
- Write Whozmove as one word, never as a question.
- Every flow is held to [Experience](docs/how-it-works/experience.md): what you approve is what you see, never stuck,
  one shape and one name, words at a glance's length, a press lands on what you saw, every state drawn, everyone can
  use it, one press where you already are.
- Comments explain *why*, in full sentences, as the surrounding code does. Match that.
- A style takes its colours, text sizes and corners from `panel/styles/tokens.css`, where each is named for its job:
  use one there, or add one for a new job, rather than writing a value out. tests/checks.sh fails on one written out
  that `tests/styles-by-hand.txt` doesn't list; that list is the ones still written out, and only ever gets shorter.
- Each colour token has a dark value and a light one, so the panel follows Settings' Appearance: add both, and try
  both. tests/checks.sh fails on a colour without its light value. A colour a script sets is a token too, as `var(--…)`,
  or read with `tokenColour` where a `var()` can't go (an animation's keyframes).

## Pull requests

- One change per pull request, small enough to read in one go.
- For a bigger change, or any new motion idea, open an issue first, so we agree on it before you build it.
- A new pull request starts from a short form (`.github/pull_request_template.md`): what changes and why, how you
  tried it, and a checklist of the rules above. CI builds with every warning an error and runs `tests/all.sh`;
  both must pass.
- Leave README.md as it is but for two parts, which change with the change that makes them untrue: the macOS
  permissions under Install, when the app starts or stops asking for one (`tests/checks.sh` checks that the README names
  each one it asks for, and no other), and Privacy, when the change sends, keeps or reads something new. In the pull
  request, say if you think your change belongs on the front page, and why, and if it makes anything else the README
  says, or one of its pictures, no longer true. A front-page feature is one that would make someone install
  Whozmove, is stronger than the one it would replace (it shows ten at most), and shows in one short moving picture.
- Contributions are shared under the project's licence, GPL-3.0-or-later.
