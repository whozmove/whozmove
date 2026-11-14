# Adding a module

A module is one folder in `modules/`: its native code, its page files, its tests and its README. Nothing outside it
lists it: the app finds it at launch, the build compiles it, the page loads its files and the tests run it. So adding
one, an agent, an app for sessions to run in, or a feature, means writing that folder. The only change outside it is
its line in the docs' map, an empty container in the page if it needs a place of its own, and, if it needs an ability
macOS's hardened runtime holds back that Whozmove doesn't ask for yet, its entitlement in `tools/Whozmove.entitlements`
(CONTRIBUTING.md's rules say which never go in).
[The overview](../how-it-works/overview.md) shows where it fits.

## 1. Choose what it is

- **An agent** runs the sessions the panel lists (Claude Code is one). It fills in `app/contracts/Agent.h`: its
  sessions, its terminal sessions that have ended lately, as closed rows (`readEndedSessions:`), what its hooks or
  records say of each, the requests waiting on them, and the title of each; and whichever of its small protocols it can:
  `AgentWork` (what a session did: its PRs and its edits), `AgentCommands` (the words of a slash command and what its
  result says), `AgentPrompt` (typing into a session's prompt, and when that's safe), `AgentUsage` (your plan's usage),
  `AgentStarts` (a new session's command, an ended one's to carry it on, `resumeCommand:wordsFile:`, and folder trust),
  `AgentInstall` (what lets the panel follow its sessions, its hooks for one, put in as Whozmove opens), `AgentVoice`
  (whether a process recording from the microphone is one of its sessions taking your voice), `AgentRecords` (where it
  keeps what its sessions were told and read, for Keys to look through, and the command that clears a project's) and
  `AgentConversations` (every conversation it keeps, the files each is made of, and ending an open one, for Sessions);
  and which session a process of its is (`sessionOfProcess:`), why that process can't ask in the session's name, when it
  doesn't run the agent's own program (`whyNotAsker:`), and why a session's process can't ask for something that only
  shows you something now (`whyNot:speakFrom:`), for what a session asks the panel.
- **A host** is an app sessions run in (Ghostty, iTerm2, Claude Desktop). It fills in `app/contracts/Host.h`: `Host`,
  and `TypingHost` if keys can go into a session there (with the terminal's own reason when they can't,
  `whyNotTypeIn:`, as iTerm2's says when other sessions share the window, and a button past it the panel can take for
  you, `wayPastIn:`, as iTerm2's turns its Python API on), `CommandHost` if it can open a tab running a command, or
  `ConversationHost` if it keeps conversations of its own (with those it keeps, `keptConversations`, which Sessions
  leaves to it to delete). A terminal whose sessions can have no
  ordinary app above them (under a server of its own, which outlives the app, or with the app kept out of the Dock)
  says which processes it runs (`runsProcess:`, as iTerm2's does).
- **A feature** (git, Deploy) fills in only `app/contracts/Module.h`, and reaches the agents and the hosts
  through the core (`app/core/Core.h`).

## 2. Make its folder

```
modules/<name>/                 lower case, words joined by -
├── app/                        its native code: <Name>Module.m, and its pieces, one job to a file
├── page/                       its scripts and styles, if it shows anything
├── module.json                 its page files, for tools/page.sh: {"order": 110, "scripts": [...], "styles": [...]}
├── plugin/skills/<name>/        what it tells Claude Code's sessions, if anything: a SKILL.md, and what it needs
├── tests/test.sh               its own tests, which tests/all.sh runs
└── README.md                   its pieces, the facts it relies on, its messages and its rules
```

A module that shows nothing has no `page/` and no `module.json` (Terminal's has neither); one with nothing native has
no `app/` (the reader's).

A skill in `plugin/skills/` goes into Whozmove's Claude Code plugin with every build, where sessions find it as
`whozmove:<name>`; its name has to be one no other module's skill has, or the build stops, naming both. Like the
hooks, it reaches only sessions started after a build that carries it, and it's text anyone can read, so it says what
the module does in plain words.

## 3. Its native face

One class adopts `Module` (`app/contracts/Module.h`). Two parts are needed:

- `+moduleName`, the name the routing table and the tests show.
- `-initWithCore:`, which only sets up data: a print run, for the tests, makes every module too.

Then whatever it has, each optional:

| | |
|---|---|
| `launch` | the app has started: windows, observers, timers and shortcuts start here, never in a print run |
| `pageLoaded` | the page has loaded, at the start or again: tell it what the module knows |
| `tick` | once a second, before the rows are read |
| `rows:phase:` | its part of every row, in the phase it belongs to (`RowPhase`) |
| `working` | whether it's still working something out off the main thread, which a print run waits for |
| `messages` | the page's messages it answers, by type: each type has one module |
| `notices` | what it has to tell you now, each a `Notice` (`app/contracts/Notice.h`): a key of its own, how much it needs you, one sentence, what makes it new again after its ×, its one button and what that does, and as it needs a tag ("New") whether you're looking at what it's about now (`seenNow`, when it isn't said), whether it answers something you just did (`answersYou`, said at night too), the id of the session it's about (`session`), and how long it's out at most where it comes out by itself (`outFor`). The notifications module decides what shows, when and where |
| `menuEntries` | its items in the pawn menu, each with its section and its order there (`MenuEntry`) |
| `settingEntries` | its rows in Settings on the panel's back, each a switch, a choice or a row opening an app's page, with its tile's mark, its card and its order there, and the page a choice shares with others (`SettingEntry`) |
| `appEntries` | the apps it works with, as the panel's back lists them, each with what Whozmove does with it, the permission macOS has to give, its switches, its groups (a heading over a card of switches, choices of one among a few, or drawn as one row with the Mac's menu of them, parts of the day and rows opening a page of their own, with a line under it, marked Important where it matters more than most), whether its page is as recommended, and its cards, each saying how something it needs there stands, with a button for it; a tool's tile can carry a mark of Settings' (`AppEntry`, its `glyph`, `AppSwitch`, `AppGroup`, `AppChoice`, its `menu` and `confirm`, `AppTime`, `AppPage`, `AppStatus`); or switches, groups, cards and lists it adds to another module's app (`AppList`: a page of rows to tick and act on, as Sessions is) |
| `sessionSwitches` | what a session may do by itself once you allow it, at the foot of its mode menu (`SessionSwitch`): its name, its line, how long it lasts, why it can't be turned on now and a way past that, what it's given for, and what the module does as it goes on or off; the core keeps them (`Allowed`) |
| `sessionAsks` | what a session may ask the panel (`ask-panel.sh <word>`), by its word, each with the switch it needs on (`SessionAsk`), or none for one that only shows you something (`askShowing:`): the core finds the session from the process asking, checks the switch, then asks the module for a line to answer with |
| `printModes` | its print modes for the tests, by flag (`--print-<name>`): what `Whozmove --print-<name> …` prints |
| `helperRuns` | its helper runs, by flag (`--helper-<job>`): a job of the app's own that it runs as a process of its own, on your real files, never for the tests, so each refuses whatever it isn't for (Sessions' `--helper-trash-item`) |

The core finds the class at launch through the Objective-C runtime, and `tools/compile.sh` compiles every `.m` in the
folder. A few rules keep modules from treading on each other:

- Objective-C has one namespace: give the module's functions and classes names of their own, and make a file's
  constants `static`.
- Import only the module's own headers, and the core's, the contracts', the shared ones (`app/shared`) and the parts'
  (each part's `app/`, the ones its `part.json` provides). Its own are found beside its code; another module's never
  are, and `tests/checks.sh` fails on one.
- No categories on the core's or the contracts' classes: they'd quietly change them for everyone.
- Nothing slow on the main thread: files, git and other apps are read on a serial queue of the module's own, and what
  they find is handed back to the main thread.
- What the module relies on about its app that the app could change (an app id, where it keeps things, a label on
  its screen) goes in a facts header of its own, `<Name>Facts.h`, so a change in that app is fixed in one place.

## 4. Its page part

The module's scripts only register with `core` (`parts/bridge/page/modules.js`) as they load: what to do at start-up
(`core.starts`), with each update (`core.updates`), on a row (`core.slots`, `core.rowCards`, `core.lines`), on a press
(`core.presses`), and the rest that file lists. The core runs them once the whole page has loaded, so a module never
acts before the page is there and never names another module.

- Its state goes on the page's state through `moduleState({…})`, under keys no one else has.
- A function the app calls is `window.<name> = …`, and a message to the app is `native({type: '<type>', …})`, which
  its native face answers. `tests/checks.sh` fails on a call or a message with no other end.
- `module.json` lists its scripts and styles in the order they load. `order` places them among the other modules'
  (lower first); today's run from 10 (git) to 100 (Spotify).
- Its styles take their colours, text sizes and corners from the tokens, so they follow the panel's look, light or
  dark, and its classes have names of its own ([reference/tokens.md](../reference/tokens.md)).
- Something that needs a place of its own on the page, a strip under the list say, gets an empty container in
  `panel/panel.html`, which the module fills.

## 5. Its tests

`tests/test.sh` runs the module's print modes, and its page part, and compares what they print with copies kept beside
it (`<name>.expected.txt`). `tests/all.sh` finds it. Spotify's is a good one to start from. What it shares:

- `tests/lib.sh`: `throwaway` and `leave_nothing` (the test's own folder and its clean-up), called at the top, before
  anything else: the folder goes, and everything the test started stops, however it ends (`|| exit 1` stops the test
  when no folder could be made):

  ```bash
  T=$(throwaway <name>) || exit 1
  leave_nothing "$T"
  ```

  Then `built_app` (the app, built once for the whole run), `detached` and `pause` (stand-in processes),
  `in_minutes` (times as minutes ago, so a run reads the same every time), `page_cases` (a file of the page's cases,
  run with macOS's JavaScriptCore) and `page_test` (those cases compared with what was recorded beside them).
- `tests/compare.sh`: `compare`, which prints the difference, or with `--update` keeps the new output once you've read
  it.
- A throwaway `HOME` for every run, so nothing touches your real sessions or files.
- `tests/sandboxed.sh`, sourced on the line after the script's `cd` (`. tests/sandboxed.sh "$@"`): the test runs again
  in a macOS sandbox of its own, which lets it write only to the temporary folders (and, with `--update`, the
  checkout), so a test that reaches for your home folder fails instead. `tests/checks.sh` fails on a test without it.

## 6. Its README

Every module's README has the same shape, and `tests/checks.sh` fails on one without its pieces and its rules:

```
# <Name>

What it is, in a sentence or two: what people see of it.

## Its pieces

- `app/<Name>Module.m`: its face for the core (contracts/Module.h): …
- each other file, and its job; its facts header; its page files; its tests

## Between the page and the app

- The page sends `<type>` (`{…}`), and the app calls `<function>(…)`.

## Rules

- What must always hold, and why.
```

Leave out "Between the page and the app" when it has no messages. Add it to the modules' table in
[the docs' map](../README.md#the-modules).

What people see of it goes in a line in the CHANGELOG's Unreleased section and in the docs/using page for its part of
the panel (or a new page there, listed in [Using Whozmove](../using/README.md)). The project's README.md is its front
page, and a module changes it only where CONTRIBUTING.md's Pull requests says: the macOS permissions under Install,
when the module asks for a new one, and Privacy, when it sends, keeps or reads something new.

## 7. Check it

```bash
tools/compile.sh /tmp/Whozmove -Werror    # as CI builds it: every warning an error
tests/all.sh                              # every test, the module's own among them
```
