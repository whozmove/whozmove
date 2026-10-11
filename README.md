# Whozmove

A small Mac panel that floats above every window and tells you whose move it is: yours or your AI coding
agents'. It lists every Claude Code session running on this Mac, in Claude Desktop and in the terminal,
with what each is doing, so you can see at a glance which one needs you.

<p align="center"><img src="docs/screenshot.png" width="412"
  alt="The Whozmove panel: a session asking to run a command, one working, and one with a reply waiting for you"></p>

- group by **status** (Needs you / Working / Your turn / Idle), by **activity** (the same sections, but a
  session stays under Your turn until an hour passes with nothing happening, even once you've opened it)
  or by **project**, with a ＋ per project that starts a new session there (⌥-click: a new Ghostty tab
  running `claude`)
- Claude Desktop conversations stay listed after Claude quits (those active in the last 3 days)
- the conversation **open in Claude** right now is marked, and scrolled into view as you switch
- the last exchange, as a chat: your message, and below it Claude's line. While Claude works, its "Claude"
  label fades in and out in blue and the line says what it's doing, timed from your message like Claude's own
  progress row: the command's description ("Run the tests"), "Reading app.ts", "Editing styles.css",
  "Searching the web: …", "Calendar: list events", and so on. As in Claude, the latest step stays up while
  Claude thinks, and the reply takes its place at the end. Both lines stay from turn to turn, so your
  message, each step and the reply change the text in place, and Claude shows thinking the moment you
  send. A step shows once it starts running: a hook can't see it while Claude is still writing it. A
  working session's dot fades on and off
- a ring for how full each session's context is. Pointed at, it widens into a **Compact** button, filled
  the same way. A click opens a card with how much is left before auto-compact ("427k left") and three ways
  to compact: Compact, Keep details and Keep essentials (the last two are `/compact` with instructions for
  what the summary keeps), or your own focus. It goes in like a model pick, while the session is idle.
  Claude's line says "Compacting the conversation" until it's done, and the ring drops to the new size
  straight away
- each session's model, effort and permission mode: click one to change it while the session sits idle.
  Never while it's working or asking you something, since a key typed into a permission prompt would
  answer it.
  - In Ghostty, the panel types `/model …` or `/effort …` into the session's tab (a half-typed draft is
    stashed and comes back), or presses Shift+Tab for the mode. Those commands also save your choice as the
    default for new sessions, so the panel puts your default back (only that setting, and only when the
    command says it saved it). The mode menu offers only the modes it can reach with a known number of
    presses. Auto isn't in every session's Shift+Tab cycle, so unless the session is in Auto now or your
    settings turn Auto off, the menu offers just the moves that are the same either way, and says to change
    the others in the terminal. If Claude Code asks to confirm (switching model on a cached conversation),
    the tab comes forward.
  - In Claude Desktop, the same slash command goes into the conversation's own message box and is sent
    with its Send button through the Accessibility API, so nothing is typed and no menus open. Return is
    pressed only if Claude shows no Send button, and only while Claude is in front. Claude switches to the
    conversation first if it isn't showing it. The mode menu offers only Plan, since `/plan` is the only
    slash command for a mode, and nothing is sent while you have a message half-written there. Claude's
    "Switch model?" (a model switch re-reads a cached conversation) is asked in the panel instead, and your
    answer goes to Claude's box. This needs the Accessibility permission for Whozmove
- for an idle session, its current action: Waiting on you, In development, Ready to commit, Committed,
  "Pushed, no PR", Draft PR, CI running, CI failing, In review, Changes requested, Approved, Merged, On
  staging, Live in prod, Review posted, Exploring, Planning or Done. It comes from the repo's live state
  (git status, its PRs' checks and reviews) and how far the last turn took the work. Deploys count only
  when they name staging or production. Beside it, at the end of the row's project and branch line, is
  what that work has been through since it started: built, tested, validated (lint, types, a check in the
  browser), and a local code review as an **audit**: "audit: 15 found", then "audit: 1 left" once fixes are
  reported (a skipped finding counts as left), or "audit clean". It says "audit" so it never reads as a
  GitHub review (In review, Approved)
- a permission prompt waiting, which you can answer on the row, under Claude's line. A card shows exactly
  what the agent wants to do (the command, and whether it would run in the background or outside the
  sandbox; for an edit, the lines it takes out and puts in; the whole of a file being written; the URL and
  what's asked of it; a tool's input), with **Deny** and **Allow once**, never "always allow". A request too
  long to show in full can only be denied here. Claude's own prompt stays usable too, and whichever you
  answer first counts. Sub-agents' requests, sessions that aren't interactive (`claude -p`) and leaving plan
  mode are left to Claude's own prompt
- Claude's questions (its question tool) answered on the row, one at a time like Claude's own box: pick an
  option (or several), type your own answer, or enter a number, then Skip, Next, Submit, or × to dismiss
- the session's **branch**, and its **worktree** when it runs in one
- **open PRs** the session created or worked on, with a hover card (state, author, `+/−`, files)
- click a session to jump to it: Claude Desktop opens it (launching Claude if needed), and Ghostty focuses
  its tab
- a pawn in the menu bar with a count of sessions waiting on you; its menu switches the grouping

### Colours

A label's colour says whose move it is:

| Colour | Meaning | Labels |
|---|---|---|
| red-orange | blocked or broken: fix it | Needs you, CI failing, Changes requested |
| amber | your move: a routine next step | Your turn, Waiting on you, Ready to commit, Committed (with a remote), "Pushed, no PR", Draft PR, Approved |
| blue | work underway | Working, In development |
| teal | waiting on others or CI | In review, CI running, On staging |
| green | finished | Merged, Live in prod, Review posted, Committed (repo with no remote) |
| grey | nothing to do | Done, Exploring, Planning |

## Install

Needs macOS, Xcode Command Line Tools (`clang`, and the `python3` the hooks run on) and Claude Code.
Optional: `gh`, signed in, for PR status; Claude Desktop and Ghostty, for jumping to and controlling their
sessions. Sessions in other terminals are listed too, but a click only brings their app forward (not the
exact tab), and their model, effort and mode can't be changed from the panel.

Tested with Claude Code 2.1.270, Claude Desktop 2.31226.1 and Ghostty 1.3.1. Whozmove reads files and
labels these apps don't document, Claude Desktop's conversation files and log above all, so an update to one
of them can break part of the panel until Whozmove catches up. The fix always goes in `app/Upstream.h`.

```bash
git clone https://github.com/whozmove/whozmove
cd whozmove
./install.sh   # builds the app, adds Whozmove's hooks to Claude Code, and starts the app now and at every login
```

The hooks are how the panel learns your last prompt, Claude's last reply, requests for your OK and the tool
each agent is using. `install.sh` adds them as a Claude Code plugin, `whozmove`, with Claude Code's own
`claude plugin` commands, so there's nothing to edit in `~/.claude/settings.json`. Without the `claude`
command (Claude Desktop only, say), it prints the two `/plugin` lines to run in a session instead. Sessions
pick up hooks when they start, so they apply to sessions started (or restarted) after this.

macOS asks for two permissions the first time they're needed: **Accessibility** for Whozmove (to
change settings, compact and focus the message box in Claude Desktop), and **Automation** of Ghostty (to
focus and type into its tabs). Both can be granted later in System Settings → Privacy & Security.

After changing anything in `app/`, `panel/` or `icon/`, run `./build.sh` again; it restarts the running app.
`./install.sh --uninstall` removes the app, its login item and the plugin, and asks before deleting
Whozmove's folder.

## How it works

| Shows | Comes from |
|---|---|
| Running sessions and status | `~/.claude/sessions/<pid>.json`, Claude Code's live session registry |
| Claude Desktop conversations, running or not | `~/Library/Application Support/Claude/claude-code-sessions/*/*/local_*.json` |
| Conversation open in Claude | `setFocusedSession` lines in Claude's `main.log` (instant), else the newest `lastFocusedAt` |
| Last prompt / reply / notice | `~/Library/Application Support/Whozmove/sessions/<id>.json`, written by the hook (the folder is yours only: 700) |
| Live line | the same file: the hook describes each tool call as it starts (a command's own description, the file, the query, …) |
| Idle outcome | the same file: at Stop, the most advanced stage the turn's successful tool calls reached (a turn that only talked, or only looked things up within 2h of uncommitted changes, keeps the one before) |
| Current action | that outcome, plus `git status` per checkout (every 20s) and the PRs' state, checks and reviews from `gh` |
| "Your turn" | by status: a reply (from the hook) in the last 30 min that you haven't opened since, here or in Claude. By activity: a reply, while the conversation has moved in the last hour; opening it leaves it there, with its reply dimmed as read |
| Permission requests | `~/Library/Application Support/Whozmove/asks/<id>.json`, left by the permission hook while it waits; your answer goes back in `<id>.answer.json` |
| Branch and worktree | the session folder's `.git`, read directly (no `git` process) |
| Changing model, effort, mode | Ghostty's AppleScript (`input text`, `send key`, `perform action "text:\x13"` for Ctrl+S); Claude Desktop's message box ("Prompt") and Submit button via the Accessibility API; the result from the transcript's `<local-command-stdout>` or Claude's conversation file |
| PRs | `pr-link` entries in the session transcript; open/merged state from `gh pr view` |

| File | Role |
|---|---|
| `app/` | the native app, one file per job: the floating `NSPanel`, the menu bar item, the bridge to the page, the sessions and their rows, permission requests, git and `gh`, and the commands typed into Ghostty or sent to Claude Desktop |
| `app/Upstream.h`, `.m` | what Whozmove relies on about Claude Code, Claude Desktop and Ghostty, in one place |
| `panel/` | the UI, rendered in a transparent `WKWebView`: `panel.html` (the markup), `styles/`, and `scripts/`, one job each (rows, cards, animation, hover, clicks and typing; `whose-move.js`: which section, label and colour each session gets) |
| `hooks/whozmove-claude.py` | Claude Code hook that records per-session context |
| `hooks/whozmove-claude-permission.py` | Claude Code PermissionRequest hook: asks in the panel as well as in Claude |
| `hooks/hooks.json`, `.claude-plugin/` | the Claude Code plugin that runs both hooks; `install.sh` adds it from a copy in Whozmove's folder |
| `icon/make-icon.m` | draws `icon/AppIcon.icns` (re-run only to change the icon) |
| `build.sh`, `install.sh`, `app/login-item.plist` | build, and install (the plugin and the login item); they read the app's name and id from `app/Info.plist` |
| `tests/` | `all.sh` runs every test: `hooks.sh` runs both hooks against a throwaway home folder, `rows.sh` checks the rows the app builds for a sample one, when keys may go into each session, its mode menus' Shift+Tab counts, the keys a command is typed with, and that this README names the macOS permissions the app asks for and no file names one it doesn't, `panel.sh` the page's labels, colours and row HTML; each compares with its recorded `.expected.txt` |
| `CONTRIBUTING.md` | how it's built and how to work on it |
| `CHANGELOG.md` | what changed in each release |
| `SECURITY.md` | how to report a security problem, and what happens next |
| `CODE_OF_CONDUCT.md` | how everyone taking part treats each other, and how to report a problem (the Contributor Covenant) |
| `docs/rows.md` | what the panel knows about each session, field by field, and where each comes from |
| `docs/screenshot.png` | the panel at the top of this page, drawn from sample sessions |

Debug log: `~/Library/Application Support/Whozmove/panel.log`.

## Privacy and security

- The panel's only network traffic is `gh` asking GitHub about your PRs (as you, through your signed-in `gh`)
  and the GitHub avatars on PR cards. Everything else stays on this Mac.
- What it keeps is in `~/Library/Application Support/Whozmove/`, which only you can read: each session's last
  message and Claude's last reply (their first 280 characters), requests while they wait for your OK, and a
  small log.
- The permission hook only ever allows once, never "always allow", and keys go into a terminal session only
  while it sits idle at its prompt, with no request waiting.
- `build.sh` signs the app ad hoc, with its bundle id as its identity, so that a rebuild keeps the
  Accessibility permission. The catch: any other ad-hoc-signed app that claims the id `com.whozmove.app` would
  get that permission too. Signing with a certificate of your own closes that.
- To report a security problem, follow [SECURITY.md](SECURITY.md) rather than opening a public issue.

Whozmove is an independent project. It isn't made by, affiliated with or endorsed by Anthropic.

## Licence

Copyright (C) 2026 Satyaraj

Whozmove is free software under the [GNU General Public License](LICENSE), version 3 or (at your option)
any later version: you can use, study, change and share it, and anything you share that's built on it must
stay open under the same licence.

The pull-request and branch icons are GitHub's [Octicons](https://github.com/primer/octicons), under the MIT
licence (Copyright (c) 2026 GitHub Inc.); its full notice is beside them in `panel/scripts/icons.js`.

## Contact

hello@whozmove.com
