# Modules

How a module plugs into the core, natively and on the page. [Adding a module](../guides/adding-a-module.md)
walks through making one.

Each outside program Whozmove works with, and each feature, is a module in a folder of its own, so a change in one
program is fixed in its module alone. The usage card, the changes view, the reader's own parts, new conversations,
Spotify's strip, Storage and the PR details keep their styles in their modules; the row's and the cards on it are the
row and morph parts' (`parts/row/page/rows.css` and `cards.css`, `parts/morph/page/motion.css`: the next steps',
Deploy's and the requests' among them),
and a row's details' step and the panel's header are their parts' (`parts/details`, `parts/header`).

- **`app/core/`** is the panel itself: start-up (`AppDelegate`, `main.m`), the services a module gets (`Core`: the page,
  the window, the menu bar, the panel's settings, the rows, the hosts, the agents, the terminal new sessions start in,
  and a `Browser` for web pages of its own), `Talking` (whether you're talking to an agent by voice now, for a module to
  follow, listened for only while one does), `Allowed` (what each session may do by itself, as you allowed it in its
  mode menu), `SessionAsks` (what a session asks the panel, on `AppDir/ask.sock`, and which session that is) and
  `PanelWindow`. **`parts/<name>/`** is one of the panel's parts, in a module's shape (`part.json`, its README, `app/`
  and `page/`), each with one job: the bridge between the app and the page (`parts/bridge`: `Page`, the registry
  (`Modules`), and on the page `core` and what the app calls), the list (`parts/list`: `Rows`, the rows read once a
  second, each module adding its part in the phase it belongs to, and sent; on the page, what each session is, the
  list's order, drawing it and the presses on it), a row and the cards on it (`parts/row`), the animation
  (`parts/morph`), the row you're on held at the list's edge and its copy letting go (`parts/held`, `parts/handoff`),
  the chats beside the folded panel and their landing (`parts/chats`, `parts/landing`), a row's details
  (`parts/details`), the header (`parts/header`), the reader beside the list and its `Browser` for web pages
  (`parts/pane`), the glass, the fold, turning over and the flick (`parts/glass`, `parts/fold`, `parts/turn`,
  `parts/flick`), hover and the keyboard (`parts/hover`, `parts/keyboard`), each with the window's category for it, the
  folded panel and peek (`parts/cat`, `parts/peek`, with `CatShape`, the folded panel's shapes), and natively `EdgeIcon`
  (an icon tucked half under the glass at the panel's edge) and `SideCat` (Whozmove beside the panel), `Focus` (the
  session you're on, when you last looked at each, and opening a session from its row, an ended terminal session's in a
  new tab), `Send` (words into a session through its host and its agent, and why they can't go in now, worded as the
  menus, cards and steps say it; and one of the agent's own commands typed in the same way, its result watched for),
  `Work` (who's at work in a checkout, which the next steps and Deploy wait for), `MenuBar`, `Settings`, `Builds` and
  `Printing` (what the print runs share: the rows read, and read once what's worked out alongside them has come back),
  each in its own part (`parts/edge`, `parts/beside`, `parts/focus`, `parts/send`, `parts/work`, `parts/menubar`,
  `parts/settings`, `parts/builds`, `parts/printing`), its header on the include path. **`app/contracts/`** holds what
  modules fill in (`Module.h`, `Host.h`, `Agent.h`; and what one module offers the others, which the core finds with
  `moduleThat:`: `WhozmoveAgain`, getting this copy of Whozmove again, the install module's; `FilesAtLines`, opening
  a file at a line in the editor you chose, the changes module's; `TeamFacts`, each team in the team file as a
  whole, the team module's; `BuildsInPlace`, what Deploy last put in place for a project, the deploy module's;
  `GearFacts`, your gear, how many sessions are working and the gear your plan can carry, the usage module's;
  `ProjectWay`, how a project works (its own pages, and the note you kept for it), the process-notes module's;
  `KeyPlaces`, where keys are kept, as Keys knows it, the storage module's, which a side question's copy never reads;
  `BackgroundWaits`, the ask-panel.sh commands a module's asks wait with in a session's background, which the agent's
  module leaves off the row's jobs, the waits and tickets modules'; and
  what any number of modules may offer, which the core lists with `modulesThat:`: `Tracker`, a ticket tracker,
  Jira's module's, with `Ticket`, one ticket the same for every tracker, its next steps its tracker's own; and
  `WakeSource` (`Wake.h`), what a waiting session waits on and what has come for it, the git module's for a pull
  request, which the waits module asks)
  and what they pass (`Row`, `Reason`, `Notice`), and
  **`app/shared/`** the helpers that know no app (`Log`, `Files`, `Processes`, `Git`, `CheckoutWatch`, `Text`,
  `OtherApps`, `AppleEvents`, `AppleScript`, `Accessibility`, `Links`, `Menus`, `Appearance`, `EditKeys`, `Audio`,
  `UnixSockets`, `Easing`, `Signature` (who signed a running program, from the copy of its signature macOS keeps); and
  `Keychain`, a secret in macOS's Keychain, `OAuth`, signing in on a service's own page in your browser with PKCE, and
  `MCP`, a small client for a server for AI tools).
- **`modules/<name>/`** is one module: `app/` (its native code), `page/` (its scripts and styles), `module.json` (its
  page files in order, for tools/page.sh, and its own pages, if it has any: `pages`), `tests/` (its `test.sh`, which
  tests/all.sh runs, and what it compares with) and `README.md` (its pieces, the facts about its program, its
  messages, its rules). What the tests share is in tests/lib.sh: a throwaway folder and its clean-up, the app built
  once per run, stand-in processes, `in_minutes`, and `page_cases`, which runs a file of the page's cases as
  tests/panel.sh runs the core's, or a module page's with that page's scripts (tests/page-harness.js has their
  stand-ins and helpers). What a module tells the sessions
  themselves, it keeps as Claude Code skills, each in a folder of its own, `plugin/skills/<name>/` with its `SKILL.md`:
  the Claude Code module's plugin carries every module's (modules/claude-code/plugin.sh), where sessions find each as
  `whozmove:<name>`, so two modules' skills never share a name (a build stops, naming both).
- A module's face is a class that adopts `Module` (app/contracts/Module.h). The core finds it at launch, so nothing
  lists it. It names the page messages it answers (each type has one; two modules answering one fail the tests), its
  items in the pawn menu and where they go, its rows in Settings on the panel's back (each a switch or a choice, its
  tile's mark, its card and its order there), the apps it works with as the panel's back lists them (each with what
  Whozmove does with it, the permission macOS has to give, its switches, and its cards, `AppStatus`, each saying how
  something Whozmove needs there stands, with a button for it; or switches, cards and lists, `AppList`, it adds to
  another module's app), what a session may do once you allow it (`SessionSwitch`, at the foot of the session's mode
  menu) and what a session may ask the panel (`SessionAsk`, by its word: each word has one module; one that only shows
  you something needs no switch), its print modes (for the tests), its helper runs (`helperRuns`: jobs of the app's
  own, by a `--helper-<job>` flag, which it runs as a process of its own on your real files, each refusing whatever it
  isn't for, never for the tests), its part of each
  tick, its part of each row, in the
  phase it belongs to (the checkout's state, the session's work, its agent's details, and once the rows are whole), and
  whether it's still working something out off the main thread, which a print run waits for. Setting up only prepares
  data, since the tests' print runs make every module too; windows, observers and timers start in `launch`.
- What a module has to tell you now, it lists (`notices`): each a `Notice` (app/contracts/Notice.h), with a key of its
  own, how much it needs you (urgent, soon or good to know), one sentence, what makes it new again after its ×, and its
  one button with what that does (the module's own `press`), and as it needs, a tag ("New"), whether you're looking at
  what it's about now, when it isn't said, and whether it answers something you just did, when it's said at night too.
  `Modules` gathers them as the rows are read, naming the module each came from, and the notifications module decides
  what shows, when and where. No module calls it, and it never acts on a press itself. A notice may name the session
  it's about (`session`), and how long it's out at most where it comes out by itself (`outFor`).
  A place outside the panel (macOS's notifications, say) will be a module of its own, its contract made with it.
- An app sessions run in is a host: a module that adopts `Host` too (app/contracts/Host.h), and says what more it can
  do by the protocols it adopts beside it: `TypingHost` (a session's tab found, and keys typed into it), `CommandHost`
  (a command run in a new tab) and `ConversationHost` (an app that keeps sessions as conversations of its own, Claude
  Desktop's, whose sessions are tracked only while it's on this Mac and its switch says so: while they aren't, the core
  lists none of them, and nothing starts in it; which conversations it keeps, `keptConversations`, is still asked, so
  Sessions leaves those to it). The core finds the host a row runs in (`hostOf:`), so nothing else asks which app it
  is. On the page,
  each host names its rows (`core.hosts`: its name, "Open in … now").
- The agent that runs the sessions is a module that adopts `Agent` (app/contracts/Agent.h). As the rows are read, on
  their queue, it lists the sessions it runs; the hosts add what they know (and Claude Desktop its conversations,
  running or not); it adds its terminal sessions that have ended, as closed rows no other row has, which Focus opens
  again in a new tab (`resumeCommand:wordsFile:`, in the terminal it ran in, else the core's `startTerminal`); it adds
  what its hooks recorded and the requests waiting; the core adds each session's checkout. It gives each session a title
  (a terminal finds its tab by it, and by whether the tab's title shows it at work), and names the marks it puts on its
  commands. A conversation running in more than one process at once is one row, the copy that needs you most, which
  names the others (`alsoOpen`, with whether each is at work, which Deploy and the next steps wait for). What more it
  does, it says by the protocols it adopts beside it, one for each part of the panel that uses it: `AgentWork` (what a
  session edited, and its PRs), `AgentCommands` (its menus' choices, the commands that make them, and whether one took),
  `AgentPrompt` (a command typed into a session's prompt while keeping your draft, and when that's safe), `AgentUsage`
  (your plan's usage), `AgentStarts` (a new session's command, an ended one's, and folder trust), `AgentInstall`
  (Whozmove's hooks put into it, and kept up to date, and the sessions that started before they went in, which reload
  them with its own command), `AgentVoice` (whether a process recording from the microphone is one of its sessions
  taking your voice), `AgentRecords` (where it keeps what its sessions were told and read, which Keys looks in, and its
  command that clears a project's) and `AgentConversations` (every conversation it keeps, the files each is made of, and
  ending an open one, for Sessions). It also says which session a process of its is (`sessionOfProcess:`), why that
  process can't ask the panel things in the session's name, when it doesn't run the agent's own program
  (`whyNotAsker:`), and why a session's process can't ask for something that only shows you something now
  (`whyNot:speakFrom:`), for what a session asks the panel. The core finds the agent that runs a row (`agentOf:`), so
  nothing else reaches into one: there's one, Claude Code, for now.
- On the page, a module's scripts only register as they load, in the lists parts/bridge/page/modules.js keeps, and the
  core runs them; a module never calls another's functions or reads its state. Its own state goes on the page's state
  with `moduleState`, which refuses a key another has. What it can plug in:
  - its start-up, and its part of each update, each fold to the header and each rebuild of the list (rows the app
    hasn't listed yet, what it works out before the list is drawn, and after), and groups of its own above the
    projects (`core.topGroups`, handing back the rows it leaves for them), and which sessions' replies
    went to another session rather than to you, so they never wait on you (`core.repliesElsewhere`), and which
    conversations have nothing in them for you to read at all (`core.notYoursToRead`);
  - a row's parts: its first look at the row, its parts in the row's places (`core.slots`: after the name, or on a
    row shown briefly in its place; after the title line's words, and past a gap that lines it up, what goes before its
    time; the end of Claude's line, after its words; the work line's start, its numbers and its steps; the bottom
    line's start and its end; a project's header; the strip at the row's far edge, the side the reader opens on, past the
    end of its lines, whose bar swells as the pointer comes onto it, kept lit by what's in it marked `.keep` and in
    your move's colour by what's marked `.lit`; with whether the row has Claude's line, `row.claudeLine`, and
    whether it asks something of you, `row.asking`, and for what, `row.askWant` (an ask's one action, at its end, is
    the first module's that answers it, `core.slots.askAct`: Deploy's for 'try', the reader's for 'plan', a plan Claude
    waits on there, and 'look', the session's newest prototype, each opened beside the list, else the note's own
    `act.html`),
    whether its bottom line's end is drawn, `row.placeEnd` (never while it asks: one ask, one action, so a module that
    puts an action elsewhere on the row, as the context ring, leaves it off while `row.asking`), and whether that end is drawn at its note's end (`row.endAtNote`: a row shown briefly) rather than on the
    bottom line, all known before
    the title line's are asked, so a part with one place to go goes in one; and just before that end, what stays on
    the bottom line whatever the end does, `placeStays`, asked only there, as Deploy's address), its card under the chat (`core.rowCards`, the most pressing showing, each the others' place
    when they want it), and the row's note, said in its work line's place (`core.rowNotes`), or on a line of its own
    with `line` (an ask line, `askLineHTML`), one in your move's colour giving way to any other; and, as every row in
    the list is shown briefly (the row part's `row.brief`: its title line, Claude's line only where nothing else says
    it, its card and its note), a name of the module's for it, `row.name`;
  - its part of the new conversation card (`core.startCardParts`, the starts module's card): a chip after where it
    starts, a list under the box with a field of its own that stays put as the list comes in afresh, the box's words,
    a line it adds to your words, and what the start carries for its module, handed to it natively once the start is a
    session (Module's `started:with:`); and where it starts: where the part would have it start (`where`, followed
    while you haven't picked where yourself), the line under the box in the card's own line's place (`under`), a
    warning in the busy notice's place (`warn`), Start held while it finds out where (`waits`), keys in the box
    (`boxKeys`), and what Start would also do, a line of text under the card's line (`note`), with the card's `api.place()`,
    `useHere()` and `start()`. The ticket on the card, for its other parts, is `core.cardTicket()`, the tickets
    module's;
  - presses, typing and Return in its boxes, the boxes that take the keyboard, the cards that take it once pressed and
    their keys, what the pointer can point at, what it does with what the pointer is on, and the card something pointed
    at shows (with buttons, `press`, it stays while the pointer moves onto it);
  - the strips above or under the list and what hangs below it (for the panel's height), the reader's modes and their
    presses, its lines' motion (`core.lines`), the bits that cross-fade, what a step's note settles, and what's
    forgotten a minute after a session goes;
  - what an agent's details mean, what Claude's line says while a request waits, and on a chat beside the folded
    panel once you've answered it there (`core.agent`, its `askLine` and `answeredLine`), for the parts that show them;
  - a team's job as the team module draws it, for what draws its jobs elsewhere (the team board): its track for the
    row's parts' `stepTrackHTML`, its stage in the list's words, its priority's word, its place in the ladder and
    whether it's to do now (`core.teamJob`, its `track`, `stageWord`, `priorityWord`, `priorityPlace` and `doNow`), for
    the team board and One Task;
  - each kind of task as One Task does it, for what shows an ask of that kind elsewhere (a team's step): its icon, its
    verb and what a press does with the task in hand (`core.taskKinds.act(kind)`: `icon`, `verb`, `does`), for the
    team;
  - your gear as the usage module words it, for what shows it beyond the usage card: what the app last said, what runs
    after each time it does, its lines, its words for what lists the sessions beside it and where it's changed, as
    the seats are only on the usage card, and whether Usage Gear is off (`core.gear`: `facts`, `off`, `changed`,
    `line`, `whyLine` and `words`, with `words.where`);
  - a session's chat as Side Chat keeps and draws it, for the views that show it (One Task's talk under a task): its
    conversation and its box drawn into the elements a view gives, with the words that open yours there, everything
    inside Side Chat's (`core.sessionChat.draw(s, { lines, box, opening })`);
  - a plan at a glance as the plans module draws it, for the places that show a plan (the reader, One Task), each
    passing the text it has (`core.plans`: `readerHTML`, `cardLines`, `taskHTML`, `picks` for what a send-back
    carries, and `folded`, whether a plan is shown folded beside the list);
  - the plan a session's agent waits for your OK on, in the panel's own words, and how to answer it, for the module
    that shows it beside the list, so only the agent's own module reads its request and sends its messages
    (`core.planAsks`, one from each agent's module: `of`, with its text, whether the panel can answer it and why
    Approve can't be offered; `yours`, how your Approve of it went; and `approve`, `sendBack`, `stop` and `hold`; and
    for a plan its session still waits on once its request has gone, `left`, `typeBack`, your notes typed in as a
    message, and `typed`, how that went);
  - the code blocks a module draws, by their language, told whether it's the reader or the list (`core.fences`); what's
    drawn at the width it has as the reader is fitted (`core.readerDrawn`); and diagrams as the diagrams module draws
    them, for the places that show Markdown (`core.diagrams`: `smallHTML`, `words`, `says`, `firstFlow` and `draw`);
  - the places notifications fills (`core.places`: the line under the header, Whozmove beside the panel at its edge, the
    chats beside the folded panel), what a place tells it (`core.notices`), and what a module on the page adds to what
    the app sends (`core.noticeSenders`), with the fields a `Notice` has, one naming a session coming out beside the
    folded panel as that session's chat; and what a module knows is new in a session beyond its row
    (`core.sessionNews`: a reply in its side chat, with a line to say and its time), which the needs-you module says
    beside the folded panel as the row's own news.
- The rules every module keeps (one compile line, its program's facts in its own module, settings that keep their
  names, and where a choice goes) are in CONTRIBUTING's [Modules](../../CONTRIBUTING.md#modules).

## Architecture

`tests/checks.sh` keeps the walls up: no module imports another's header, no page function is in two scripts, every
message has both ends, no class is styled by two owners, and every module and part has its README. What it can't check
is whether each piece of work is in the right place. These ten principles decide that, for every plan and every
change; CONTRIBUTING's [Architecture](../../CONTRIBUTING.md#architecture) lists them in short.

A service, below, is anything the others use for one ability: the core, every part, the contracts, the shared
helpers, the bridge between the page and the app, the places on the page (`core.places`, `core.slots`,
`core.rowCards`), and the notifications module.

1. **One job per module or part.** Each module and part has one job, said in a sentence in its README, and everything
   in it serves that job. A second job gets a folder of its own. *Why:* a fix happens in one folder, and whoever
   changes it can keep all of it in mind. *For example,* `parts/send` puts words into a session and says why they
   can't go in now, and nothing else.
2. **Services know nothing about sessions or features.** A service gives one ability (deliver, place, hold, move,
   draw, send a message) to whoever asks. It never decides what a domain's things mean: what a session needs, how
   urgent something is, which feature goes first. That comes from the module that knows it, as data the service
   carries. *Why:* once a service decides things for one domain, every new feature has to change it, and features
   fight over it. *For example,* `parts/edge` and `parts/beside` only provide a place at the panel's edge; what shows
   there, such as Spotify's token, is the module's that shows it.
3. **A feature is a module of its own.** Something people can see or use is a module, with its own folder, README and
   tests. It uses the services, and never lives inside one of them or inside another feature. *Why:* a feature that
   lives inside something else can't be changed, tested, turned off or taken out on its own. *For example,*
   `modules/deploy` reaches who's at work in a checkout and typing into a session through the core.
4. **The core and the parts name no outside app or feature.** They reach agents, hosts and features only through the
   contracts (`hostOf:`, `agentOf:`, `core.agent`, `core.hosts`, the modules' hooks). *Why:* when the core names one
   agent or app, adding a second means changing the core, not only adding a module. *For example,* the core finds
   the app a session runs in and the agent running it through `Core.h`, so nothing else asks which app it is.
5. **What Whozmove relies on about an outside program lives in that program's module.** Every fact the program could
   change (an app id, a path, a file's format, a label, a tool's name, an environment variable) is in the module's
   facts header (`<Name>Facts.h`) or its README, and nowhere else. *Why:* when that program changes, the fix is in
   one file. *For example,* `modules/spotify/app/SpotifyFacts.h` and `modules/claude-code/app/ClaudeCodeFacts.h`.
6. **Modules and parts meet only through contracts.** No module imports another's code, calls its functions, reads
   its state or files, or depends on its words. They meet through `Module.h`, `Agent.h`, `Host.h`, `Notice`, the
   fields of a row (docs/reference/rows.md), the core's hooks on the page, and a part's `talksTo` and `provides`.
   *Why:* so any module can be rewritten or taken out without the others changing. *For example,* a module lists
   the notices it has (`app/contracts/Notice.h`) and never calls the notifications module.
7. **One owner for each piece of data, style and rule.** Each preference key, file in Whozmove's folder, row field,
   page state key, style class and rule has one writer and one place that decides it; the rest read it, or ask its
   owner. *Why:* two places that write the same thing or decide the same rule drift apart. *For example,*
   `moduleState` refuses a key another module already has, and `Allowed` keeps what each session may do, for every
   module.
8. **Decide in plain functions, and draw in a separate file.** What a module decides (what shows, in what order, with
   what words, when) is in plain functions with no page or window in them, with cases in its tests; drawing, timers
   and presses are in another file that calls them. *Why:* the rules are tested without the screen, and the drawing
   can change without changing them. *For example,* the notifications module's `decide.js` beside `notice-line.js`,
   and the git module's `steps.js` beside `git-steps.js`.
9. **Every feature works for any project.** A feature works for anyone's project (a website, a command-line tool, an
   app), any repo and its worktrees, with no special case for Whozmove's own. Tools for working on Whozmove itself go
   in Working on Whozmove ▸ (`MenuSectionWhozmove`), which shows only while ⌥ is held. *Why:* everything that ships
   has to work for someone else's project. *For example,* Preview Notices, Preview the Wait and Show Build in Header.
10. **Grow by adding a folder.** A new agent, terminal or feature is one new folder that the core finds by itself, and
    a contract grows by a small protocol for what's new rather than by special cases. Add no contract, part, layer or
    setting until something uses it. *Why:* adding stays cheap, and nothing is kept for a future that may not come.
    *For example,* `Modules` finds every module at launch, so nothing lists them, and a new ability of the agent is
    a protocol of its own (`AgentVoice`).
