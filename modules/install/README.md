# Install

Whozmove setting itself up each time it opens. An install from Homebrew only copies the app, so everything the
install script did happens here, as the app starts: it notes where it runs from, looks for the agent, waits for
Apple's command line developer tools, which only the agent's sessions need, and puts its hooks into the agent (Claude
Code's plugin) or brings them up to date there. When it needs something from you, a line under the header says so,
with the button that does it, and the panel's back keeps the same buttons: on Git's page for the developer tools, and
on the page the agent's settings go on for its hooks (Claude's, for Claude Code).

## Its pieces

- `app/InstallModule.m`: its face for the core (contracts/Module.h). At launch it finds the agent that takes the hooks
  (`AgentInstall`, contracts/Agent.h) and starts the check; each tick, while the check waits for the agent or for the
  developer tools, it looks again every 10 seconds, and once the agent has said how the hooks stand, every 5 minutes, so
  hooks turned off or taken out there while Whozmove runs show on the line, and the next session waiting to reload goes
  in (`Reloads`), whose rows it marks once the rows are whole; it tells the line how things stand (`setInstall`), takes
  its presses (`install`), and adds its cards to the panel's back (`appEntries`): Apple's command line developer tools
  to Git's page, and Whozmove's plugin to the page the agent's settings go on (the agent's `appId`: Claude's, for Claude
  Code), under the agent's name. Its print modes are `--print-install`, `--print-updates` and `--print-install-cards`.
- `app/Install.h/.m`: the check, in this order, on a queue of its own, one at a time, your presses included:
  1. How Apple's developer tools stand, wherever it runs from, for Git's page: in, missing, or installing while
     macOS's installer for them is open. Install has macOS open it (unless it's open, or they're in) and waits a
     moment for it to show. While it's open, and at the look after it closes, macOS is asked again at each look
     (`DeveloperToolsLookNow`), rather than at most every 5 minutes (`DeveloperToolsReady`).
  2. Only from an Applications folder (`InApplications`: /Applications or ~/Applications, at any depth). A copy
     opened where it was downloaded, from a disk image, from a build's folder, or from the copy macOS runs one of
     those from (App Translocation) sets nothing up.
  3. Where it runs from goes in Whozmove's folder (`app`), written whole, and only when it changed: the hooks record
     only while that app is there. Then Open at Login: on at the very first open, then as you set it, its login item
     put right for this app (`LoginItem`, below).
  4. Nothing more until the agent is on this Mac (`onThisMac`, found without running anything): Whozmove works
     without it, and the developer tools are only needed for its sessions.
  5. Nothing more until Apple's developer tools are in: the agent may run git, which until then offers to install
     them each time it runs.
  6. A build an agent made (build.json's `agent`, `BuiltByAgent` in the core's Builds) leaves the hooks as they are.
  7. The agent puts the hooks in, or brings them up to date (`connect:before:from:`), from the copy this app carries
     (`Contents/Resources/plugin`), with your press on the line when it's the agent's (Add Back, Turn On, Try Again).
  It also has the words for its cards on the panel's back (`ToolsCard`, `PluginCard`).
- `app/LoginItem.h/.m`: Open at Login, as a login item of its own, `~/Library/LaunchAgents/<bundle id>.plist`: what
  it holds (this app's program, run at load, restarted only after a crash, in your login session only, named for the
  app in Login Items), written only when that differs (a moved app gets a new one), and taken out. Install puts it
  right at each check, from an Applications folder only, with the choice in its record (`openAtLogin`): none recorded
  is the very first open, which turns it on. It's never loaded into launchd from here; taken out, its job is unloaded
  (`launchctl bootout`) only when this copy isn't the one launchd runs for it, as `launchctl print` says. launchctl is
  asked only through Install's stand-in, so the print mode never reaches your real login item. The pawn menu's Open at
  Login (`InstallModule`, `MenuSectionApp`, just above Quit) shows and sets it; on macOS 13 and later, one you turned
  off in System Settings' Login Items (`SMAppService`) shows unticked, and a press opens Login Items.
- `app/Updates.h/.m`: a newer Whozmove out, for a copy Homebrew installed (its receipt in the Caskroom names the tap),
  read from that tap's cask, Homebrew's copy on this Mac and GitHub's raw file, the newer counting, against Info.plist's
  version, part by part; never for a build from a checkout (its build.json). Looked at as the app opens and every 6
  hours, on a queue of its own; a missing file, no network or a slow answer finds nothing, said once in the log. The
  line shows it once setting up needs nothing of you; Copy Command puts the command on the clipboard (it never runs
  brew), and its × keeps that version away in `updates.json`. `--print-updates <case>…` checks it with sample receipts
  and casks.
- `app/HomebrewFacts.h/.m`: what it relies on about Homebrew: its folder, a cask's receipt, a tap's cask on this Mac
  and on GitHub, the cask's version line, and the command that updates it.
- `app/LaunchdFacts.h/.m`: what it relies on about launchd for the login item: the folder it goes in, launchctl, a
  job's name in your login session, and the line `launchctl print` names its process on.
- `app/ToolsFacts.h/.m`: what it relies on about how macOS puts the developer tools in: the command that asks for
  them, `xcode-select --install`, and the installer it opens, by its bundle id.
- `app/Reloads.h/.m`: the sessions that were running before the hooks went in (the record's `addedAt`, when they last
  went in from here; hooks found already in, with no `addedAt`, went in before any session now open), which run without
  them until they reload them, as the agent tells (`runsWithoutHooks:`: started before then, and nothing recorded since
  it started), once their first message is sent. Each such row is marked (`reload`); a press on one, or Reload Them for
  all, puts them in a queue, and each goes in once it's idle, one at a time, as the agent's own command
  (`reloadCommand`, `/reload-plugins` for Claude Code), typed through the core's `Send` with the panel's typing checks;
  its result says whether it took (`reloaded:`). One that started working meanwhile is let go, and its row offers Reload
  again once it's done; one the panel can't type into (its tab isn't certain, a terminal it can't type into), or one
  whose reload Claude Code held back, is left for you: its row says what to type in it, and why, and Reload Them doesn't
  try it again. What's been reloaded is kept in Whozmove's folder (`reloads.json`), by session, as when: one reloaded
  since its process started has the hooks until it ends, even if they're taken out and put back meanwhile, so the panel
  opening again, or the hooks going in again, doesn't ask again.
- Its own record, in Whozmove's folder (`install.json`), not the app's preferences, which a print run's home folder
  doesn't reach: when the hooks were first found in the agent, so ones you take out aren't put back; and what the
  last check found and since when, so that time holds across launches while it stays so. Each outcome goes in the
  panel's log, once, until it changes.
- `page/install.js`: what the line under the header says for each state, its button and what a press asks, and
  whether it has a ×, and how a × holds (plain functions); `page/reload-row.js`: a session's mark at its work
  line's start, Shown in part with Reload, and its note once it waits or reloads; `page/install-line.js`: drawing
  the line in its place
  under the header (`#install`, panel.html), where it takes the header's room from the list as a card there does,
  growing in, changing its words and folding away with the strips' helpers, its button, which waits from a press
  until the app says how it went (Copy Command doesn't wait: it says Copied a moment, its words cross-fading), and
  its ×; `page/install.css`, for what isn't the core's: the line is the panel's
  one-line message (controls.css) with the core's × (cards.css). `module.json` lists them for tools/page.sh.

`tests/test.sh` runs `--print-install`'s cases, each with stand-ins for where the app runs from, whether an agent
made it, the agent, the developer tools and macOS's installer for them, and compares what each check found (and how
the tools stood, and whether since when it had been so was kept), what the agent was asked, how macOS was asked about
the tools and what was noted with `tests/install.expected.txt`, with every card `--print-install-cards` prints; and
what the line says for each state (`page-cases.js`, with the page's scripts) with `tests/page.expected.txt`; and
`--print-updates`' cases, sample Homebrew receipts and casks (Homebrew's copy and GitHub's, from the case), with
what each finds, and look by look through `Updates` itself: a build from a checkout never looking, a version put
away staying away until a newer one, and a look GitHub doesn't answer keeping what it said last.

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

While the hooks are in and sessions open from before still need reloading, the line says so in place of `added`'s, with
**Reload Them** (**Reload It** for one) and a ×: "Connected to Claude Code. New sessions show here in full, and the 3
already open will once they're reloaded." just after connecting, else "2 open sessions show here only in part until
they're reloaded, which keeps their conversation as it is."; while they reload, "Reloading your open sessions: 1 of 3
done." (or, for one, "Reloading “Release notes”."); with only ones the panel can't type into left, "“Pricing cards”
shows here only in part, and Whozmove can't type into it: type /reload-plugins in it to reload it.", with **Take me
there**, which brings that session forward as a press on its row does; and once a press has reloaded the last, "All set:
every open session shows here in full.", with a tick, putting itself away as `added` does. Its × keeps the reload's line
away for the hooks' time, and `added`'s with it; the rows keep their Reload.

Once setting up needs nothing of you (no line above shows, or you've put it away), a copy Homebrew installed says when
a newer Whozmove is out: "Whozmove 0.2.1 is out. Run brew upgrade --cask whozmove/tap/whozmove to update.", with
**Copy Command**, which puts that command on the clipboard (it says Copied a moment), and a × that hides that version
until a newer one ("Hide until a newer version"). When Homebrew has put the newer one in already, but this copy still
runs (its quit was refused), it says "Whozmove 0.2.1 is installed: restart it to use it.", with **Restart**, which
quits it and opens it again from where it is.

`added` has a green tick before its words, and puts itself away 4 seconds after it shows, folding as it does for its
×. `ready`, `updated` and `agentBuild` show no line of their own (but a new version's). A × keeps that state away, as
the time it began, so the line comes back only once things have changed (its record keeps that time across launches);
a new version's, as its version, kept in `updates.json`.

## Between the page and the app

- The app calls `setInstall({state, detail, since, busy, reload, update})` (`update`: `{version, command}`, a newer
  Whozmove out) whenever what the check found changes, or how the
  sessions open from before stand (`reload`: `{open, idle, byHand, first, waiting, going, done, total, since}` while
  some need reloading (`idle`, how many the panel can reload now; `byHand`, the ones left for you, the first of them
  `{sessionId, name, command, held}`; `going`, the name of the one going in), `{allSet, since}` once a press has
  reloaded the last of them, and nothing while the hooks aren't in), as a press sets one
  going, and when the page loads: `since` is when it has been so (ms since 1970), `busy` whether a check is under way.
- The page sends `install` with `{action}`: `copyUpgrade` (Copy Command), `putAwayUpdate` with `version` (its ×),
  `reloadAll` (Reload Them), `reload` with `sessionId` (a row's Reload),
  `tools`, `addBack`, `turnOn`, `retry` or `getAgent` (the agent's install
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
- Presses go one at a time, on the check's queue, and only one that still fits how things stand (Copy Command and a
  new version's × act at once: they change nothing of setting up).
- `--print-install` writes in Whozmove's folder and the login item's in `$HOME`, so it never runs in your own home
  folder; its launchctl is a stand-in.
- The app never loads its own login item into launchd, and opens at login only from an Applications folder.
- A session reloads only after your press, its row's or Reload Them's, right then: Reload Them takes the ones idle at
  the press, and one at work is never queued to go in by itself later. Only while it's idle, with the typing checks
  the panel's commands have, and nothing else from the panel types into it meanwhile (Send's `typingInto:`). Never
  with `--force`: a reload Claude Code holds back, because its next message would read the whole conversation again,
  is left for you, its row naming `/reload-plugins --force`, and pointed at, saying what Claude Code said.
- A new version is only said: nothing runs `brew` or installs anything, and a build from a checkout never looks.
