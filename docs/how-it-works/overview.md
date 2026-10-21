# How Whozmove fits together

Whozmove is a floating macOS panel. A native app (Objective-C, in `app/` and `modules/`) finds out what every Claude
Code session on the Mac is doing, and a page (HTML, CSS and plain scripts, in `panel/` and `modules/`) shows it, in a
WKWebView inside the panel. The core is the panel itself and names no outside app and no feature. Each app Whozmove
works with, and each feature, is a module of its own: a folder that holds its native code, its page files, its tests
and its README.

```
               Claude Code      Claude Desktop     Ghostty, iTerm2,      git, gh       Spotify, LRCLIB
                                                   Terminal
                    │                  │                   │                 │             │
                    ▼                  ▼                   ▼                 ▼             ▼
 modules/      claude-code      claude-desktop      ghostty,            git,          spotify, usage,
               the agent        a host              iterm2,             changes,      starts, commands,
                                                    terminal-app        deploy        reader
                                                    hosts
                    │ Agent.h          │ Host.h            │ Host.h          │ Module.h    │ Module.h
                    └──────────────────┴───────────────────┴─────────────────┴─────────────┘
                                                    │
 app/core      Rows, once a second: the sessions read on a queue, then each module's part of every row
               Page · PanelWindow · MenuBar · Focus · Send · Work · Browser · Modules, the registry
                                │ update(rows, now)                   ▲ the page's messages, each by its type
                                ▼                                     │ to the one module that answers it
 panel/        the core's scripts and styles, and each module's page files: render, then morph
```

Every module fills in `Module.h`. The agent fills in `Agent.h` too, and a host `Host.h`. A feature needs only
`Module.h`, and works with the agent and the hosts through the core.

## The parts

- **The core**, in `app/core` and `panel/`. Natively: `Modules` (the registry), `Core` (what a module is given: the
  page, the window, the menu bar, the rows, the agents, the hosts and the terminal new sessions start in), `Rows` (the
  rows read and sent), `Focus` (the session you're on, when you last looked at each, and opening one from its row, an
  ended terminal session's in a new tab), `Send` (words into a session, and why
  they can't go in now), `Work` (who's at work in a checkout), `Page`, `PanelWindow`, `MenuBar`, `Builds`, `Printing`
  (what the tests' print runs share), `EdgeIcon` (an icon tucked half under the glass at the panel's edge, as Spotify's
  token is), `SideCat` (Whozmove beside the panel while the header has gone), `CatShape` (the cat's shapes, drawn
  natively), `Easing` (the curves the panel moves on) and `Browser` (web pages that aren't the panel's own, each in a
  web view of its own with no way to talk to the app, for a module to show). On the page: the rows and their places for
  the modules' parts, sorting, the animation (`morph`), the header pushed away by the row you're on as the list
  scrolls (`header`), the row you're on held at the list's edge as the list scrolls past it (`sticky`), the pointer,
  presses and typing, the reader's frame, and `modules.js`, every list a module plugs into.
- **The contracts**, in `app/contracts`: what a module fills in and what it passes. `Module.h` is every module's;
  `Agent.h` is the agent's, with what it can do in small protocols of their own (`AgentWork`, `AgentCommands`,
  `AgentPrompt`, `AgentUsage`, `AgentStarts`, `AgentInstall`); `Host.h` is an app sessions run in (`Host`, and `TypingHost`,
  `CommandHost` or `ConversationHost` for what it can do); `Row` is one listed session, as
  [reference/rows.md](../reference/rows.md) describes it field by field; and `Reason` says why keys can't go into a
  session now.
- **The shared helpers**, in `app/shared`: plain functions that know no app. `Log`, `Files`, `Processes`, `Git`,
  `Text`, `AppleEvents`, `AppleScript`, `Accessibility`, `Links`, `Menus` and `Appearance`.
- **The modules**, in `modules/`: the agent, the hosts and the features, each with its README (the table in
  [the docs' map](../README.md#the-modules)).

## One second of the panel

1. Each module's `tick` runs, for what it checks that often.
2. On a queue of their own, the sessions are read: each agent's running sessions; then what each app that keeps
   conversations of its own knows of them (Claude Desktop's record, and its conversations that aren't running); then
   the agent's terminal sessions that have ended, from the record Whozmove keeps of each while it runs, for 3 days;
   then what the agent's hooks recorded of each, and the checkout it runs in; and last, the requests waiting for your
   answer.
3. On the main thread, every module adds its part of each row, phase by phase (`RowPhase` in `Module.h`): the
   checkout's state first, then the session's work, then its agent's details, and last, once the rows are whole, what
   a module keeps or sends apart from them.
4. The rows go to the page as JSON: `update(rows, now)`.
5. The page works out what each session is and places its row, newest message first, but for the rows you've pressed,
   which stay where you saw them until you've moved on from the panel. It draws the list again and animates the
   difference (`morph`), each module drawing its parts into the row's places, its cards and its strips.
6. What you press or type on the page goes back to the app as a message, which reaches the one module that answers
   its type.

## How a module is found

- At launch, `Modules` asks the Objective-C runtime for every class that adopts `Module`, makes each with the core,
  in the order of their names, and starts them (`launch`). Nothing lists them.
- `tools/compile.sh` compiles every `.m` in `app/` and `modules/`.
- `tools/page.sh` puts the page together: `panel/panel.html`, with each module's styles and scripts where the page
  marks a place for them, in the order of the modules' `module.json` files.
- A module's scripts only register with `core` (`panel/scripts/modules.js`) as they load. The core runs them once the
  whole page has loaded, so a module never acts before the page is there and never needs to name another module.

[Adding a module](../guides/adding-a-module.md) goes through each of these.

## What keeps the parts apart

`tests/checks.sh` fails when any of these slips:

- A module imports only its own headers, and the core's, the contracts' and the shared ones; the core imports no
  module's.
- Each page message has the one module that answers it, every page function the app calls is there, and no page
  function or constant is in two scripts.
- A style takes its colours, text sizes and corners from the tokens ([reference/tokens.md](../reference/tokens.md)),
  and no class is styled on its own by both the core and a module, or by two modules.
- Each module has its README, with its pieces and its rules.
