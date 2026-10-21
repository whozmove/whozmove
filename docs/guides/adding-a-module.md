# Adding a module

A module is one folder in `modules/`: its native code, its page files, its tests and its README. Nothing outside it
lists it: the app finds it at launch, the build compiles it, the page loads its files and the tests run it. So adding
one, an agent, an app for sessions to run in, or a feature, means writing that folder. The only change outside it is
its line in the docs' map, and an empty container in the page if it needs a place of its own.
[The overview](../how-it-works/overview.md) shows where it fits.

## 1. Choose what it is

- **An agent** runs the sessions the panel lists (Claude Code is one). It fills in `app/contracts/Agent.h`: its
  sessions, what its hooks or records say of each, the requests waiting on them, and the title of each; and whichever
  of its small protocols it can: `AgentWork` (what a session did: its PRs and its edits), `AgentCommands` (the words
  of a slash command and what its result says), `AgentPrompt` (typing into a session's prompt, and when that's safe),
  `AgentUsage` (your plan's usage) and `AgentStarts` (a new session's command, and folder trust).
- **A host** is an app sessions run in (Ghostty, iTerm2, Claude Desktop). It fills in `app/contracts/Host.h`: `Host`,
  and `TypingHost` if keys can go into a session there, `CommandHost` if it can open a tab running a command, or
  `ConversationHost` if it keeps conversations of its own. A terminal whose sessions can have no ordinary app above them
  (under a server of its own, which outlives the app, or with the app kept out of the Dock) says which processes it
  runs (`runsProcess:`, as iTerm2's does).
- **A feature** (the island, Deploy) fills in only `app/contracts/Module.h`, and reaches the agents and the hosts
  through the core (`app/core/Core.h`).

## 2. Make its folder

```
modules/<name>/                 lower case, words joined by -
├── app/                        its native code: <Name>Module.m, and its pieces, one job to a file
├── page/                       its scripts and styles, if it shows anything
├── module.json                 its page files, for tools/page.sh: {"order": 110, "scripts": [...], "styles": [...]}
├── tests/test.sh               its own tests, which tests/all.sh runs
└── README.md                   its pieces, the facts it relies on, its messages and its rules
```

A module that shows nothing has no `page/` and no `module.json` (Terminal's has neither); one with nothing native has
no `app/` (the reader's).

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
| `menuEntries` | its items in the pawn menu, each with its section and its order there (`MenuEntry`) |
| `appEntries` | the apps it works with, as the panel's back lists them, each with what Whozmove does with it, the permission macOS has to give and its switches (`AppEntry`, `AppSwitch`); or switches it adds to another module's app |
| `printModes` | its print modes for the tests, by flag (`--print-<name>`): what `Whozmove --print-<name> …` prints |

The core finds the class at launch through the Objective-C runtime, and `tools/compile.sh` compiles every `.m` in the
folder. A few rules keep modules from treading on each other:

- Objective-C has one namespace: give the module's functions and classes names of their own, and make a file's
  constants `static`.
- Import only the module's own headers, and the core's, the contracts' and the shared ones (`app/shared`). Its own are
  found beside its code; another module's never are, and `tests/checks.sh` fails on one.
- No categories on the core's or the contracts' classes: they'd quietly change them for everyone.
- Nothing slow on the main thread: files, git and other apps are read on a serial queue of the module's own, and what
  they find is handed back to the main thread.
- What the module relies on about its app that the app could change (an app id, where it keeps things, a label on
  its screen) goes in a facts header of its own, `<Name>Facts.h`, so a change in that app is fixed in one place.

## 4. Its page part

The module's scripts only register with `core` (`panel/scripts/modules.js`) as they load: what to do at start-up
(`core.starts`), with each update (`core.updates`), on a row (`core.slots`, `core.rowCards`, `core.lines`), on a press
(`core.presses`), and the rest that file lists. The core runs them once the whole page has loaded, so a module never
acts before the page is there and never names another module.

- Its state goes on the page's state through `moduleState({…})`, under keys no one else has.
- A function the app calls is `window.<name> = …`, and a message to the app is `native({type: '<type>', …})`, which
  its native face answers. `tests/checks.sh` fails on a call or a message with no other end.
- `module.json` lists its scripts and styles in the order they load. `order` places them among the other modules'
  (lower first); today's run from 10 (the island) to 100 (Spotify).
- Its styles take their colours, text sizes and corners from the tokens, so they follow the panel's look, light or
  dark, and its classes have names of its own ([reference/tokens.md](../reference/tokens.md)).
- Something that needs a place of its own on the page, a strip under the list say, gets an empty container in
  `panel/panel.html`, which the module fills.

## 5. Its tests

`tests/test.sh` runs the module's print modes, and its page part, and compares what they print with copies kept beside
it (`<name>.expected.txt`). `tests/all.sh` finds it. Spotify's is a good one to start from. What it shares:

- `tests/lib.sh`: `built_app` (the app, built once for the whole run), `in_minutes` (times as minutes ago, so a run
  reads the same every time) and `page_cases` (a file of the page's cases, run with macOS's JavaScriptCore).
- `tests/compare.sh`: `compare`, which prints the difference, or with `--update` keeps the new output once you've read
  it.
- A throwaway `HOME` for every run, so nothing touches your real sessions or files.

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

## 7. Check it

```bash
tools/compile.sh /tmp/Whozmove -Werror    # as CI builds it: every warning an error
tests/all.sh                              # every test, the module's own among them
```
