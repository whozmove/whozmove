# Install

Whozmove setting itself up each time it opens. An install from Homebrew only copies the app, so everything the
install script did happens here, as the app starts: it notes where it runs from, looks for the agent, waits for
Apple's command line developer tools, which only the agent's sessions need, and puts its hooks into the agent (Claude
Code's plugin) or brings them up to date there. When it needs something from you, a line under the header says so,
with the button that does it, and the panel's back keeps the same buttons: on Git's page for the developer tools, and
on the page the agent's settings go on for its hooks (Claude's, for Claude Code).

## Its pieces

- `app/InstallModule.m`: its face for the core (contracts/Module.h). At launch it finds the agent that takes the
  hooks (`AgentInstall`, contracts/Agent.h) and starts the check; each tick, while the check waits for the agent or
  for the developer tools, it looks again every 10 seconds, and once the agent has said how the hooks stand, every 5
  minutes, so hooks turned off or taken out there while Whozmove runs show on the line; it tells the line how things stand (`setInstall`), takes
  its presses (`install`), and adds its cards to the panel's back (`appEntries`): Apple's command line developer tools
  to Git's page, and Whozmove's plugin to the page the agent's settings go on (the agent's `appId`: Claude's, for
  Claude Code), under the agent's name. Its print modes are `--print-install` and
  `--print-install-cards`.
- `app/Install.h/.m`: the check, in this order, on a queue of its own, one at a time, your presses included:
  1. How Apple's developer tools stand, wherever it runs from, for Git's page: in, missing, or installing while
     macOS's installer for them is open. Install has macOS open it (unless it's open, or they're in) and waits a
     moment for it to show. While it's open, and at the look after it closes, macOS is asked again at each look
     (`DeveloperToolsLookNow`), rather than at most every 5 minutes (`DeveloperToolsReady`).
  2. Only from an Applications folder (`InApplications`: /Applications or ~/Applications, at any depth). A copy
     opened where it was downloaded, from a disk image, from a build's folder, or from the copy macOS runs one of
     those from (App Translocation) sets nothing up.
  3. Where it runs from goes in Whozmove's folder (`app`), written whole, and only when it changed: the hooks record
     only while that app is there.
  4. Nothing more until the agent is on this Mac (`onThisMac`, found without running anything): Whozmove works
     without it, and the developer tools are only needed for its sessions.
  5. Nothing more until Apple's developer tools are in: the agent may run git, which until then offers to install
     them each time it runs.
  6. A build an agent made (build.json's `agent`, `BuiltByAgent` in the core's Builds) leaves the hooks as they are.
  7. The agent puts the hooks in, or brings them up to date (`connect:before:from:`), from the copy this app carries
     (`Contents/Resources/plugin`), with your press on the line when it's the agent's (Add Back, Turn On, Try Again).
  It also has the words for its cards on the panel's back (`ToolsCard`, `PluginCard`).
- `app/ToolsFacts.h/.m`: what it relies on about how macOS puts the developer tools in: the command that asks for
  them, `xcode-select --install`, and the installer it opens, by its bundle id.
- Its own record, in Whozmove's folder (`install.json`), not the app's preferences, which a print run's home folder
  doesn't reach: when the hooks were first found in the agent, so ones you take out aren't put back; and what the
  last check found and since when, so that time holds across launches while it stays so. Each outcome goes in the
  panel's log, once, until it changes.
- `page/install.js`: what the line under the header says for each state, its button and what a press asks, and
  whether it has a ×, and how a × holds (plain functions); `page/install-line.js`: drawing the line in its place
  under the header (`#install`, panel.html), where it takes the header's room from the list as a card there does,
  growing in, changing its words and folding away with the strips' helpers, its button, which waits from a press
  until the app says how it went, and its ×; `page/install.css`, for what isn't the core's: the line is the panel's
  one-line message (controls.css) with the core's × (cards.css). `module.json` lists them for tools/page.sh.

`tests/test.sh` runs `--print-install`'s cases, each with stand-ins for where the app runs from, whether an agent
made it, the agent, the developer tools and macOS's installer for them, and compares what each check found (and how
the tools stood, and whether since when it had been so was kept), what the agent was asked, how macOS was asked about
the tools and what was noted with `tests/install.expected.txt`, with every card `--print-install-cards` prints; and
what the line says for each state (`page-cases.js`, with the page's scripts) with `tests/page.expected.txt`.

## What the line says

| State | The line | Its button | × |
|---|---|---|---|
| `added` | ✓ Connected to Claude Code: sessions you start from now on show here in full. | — | yes |
| `notInApplications` | Move Whozmove into your Applications folder, then open it again, to finish setting it up. | — | no |
| `noTools` | Install Apple's developer tools to see what each session is doing, and answer its requests here. | Install | no |
| `installing` | Waiting for Apple's developer tools to finish installing. | — | no |
| `noCommand` | Install Claude Code, or open Claude Desktop's Code tab once, to see your sessions here. | Get Claude Code | yes |
| `removed` | Add Whozmove's plugin back to see what each session is doing, and answer its requests here. | Add Back | yes |
| `turnedOff` | Turn Whozmove's plugin back on to see what each session is doing, and answer its requests here. | Turn On | yes |
| `failed` | Couldn't connect to Claude Code («what it said»), so sessions show only part of what they do. | Try Again | yes |

`added` has a green tick before its words, and puts itself away 4 seconds after it shows, folding as it does for its ×. `ready`, `updated` and `agentBuild` show no line. A × keeps that state away, as the time it began, so the line comes
back only once things have changed (its record keeps that time across launches).

## Between the page and the app

- The app calls `setInstall({state, detail, since, busy})` whenever what the check found changes, as a press sets one
  going, and when the page loads: `since` is when it has been so (ms since 1970), `busy` whether a check is under way.
- The page sends `install` with `{action}`: `tools`, `addBack`, `turnOn`, `retry` or `getAgent` (the agent's install
  page in your browser). The app holds the commands and the address; the page only names the action, and a press that
  no longer fits how things stand (or comes while a check is under way) does nothing.
- On the panel's back, its cards' buttons do what the line's do (the apps module's `appsAction`).

## Rules

- Nothing is set up from anywhere but an Applications folder: a copy that may be gone tomorrow must never decide where
  the hooks look for the app. Install on Git's page works wherever it runs from: it only has macOS open its installer.
- Hooks you took out of the agent are never put back unless you ask (Add Back; `before`, from its record).
- An agent's build never puts its hooks in place: every session you start would run them.
- Apple's developer tools are asked for only once the agent is on this Mac, and nothing of it runs the agent before
  they're in. Their line has no ×, as your sessions can't be followed without them; it stays until they're in.
- Presses go one at a time, on the check's queue, and only one that still fits how things stand.
- `--print-install` writes in Whozmove's folder in `$HOME`, so it never runs in your own home folder.
