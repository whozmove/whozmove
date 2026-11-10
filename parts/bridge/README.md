# Bridge

Everything between the app and the panel's page: loading the page, every message it sends the app and every call the
app makes into it, and where on the page the core and the modules plug in. It draws nothing of its own.

## What it owns

- `app/Page.h`, `app/Page.m`: loading panel/panel.html from the bundle's panel folder (and again if WebKit's process
  for it ends), the page's messages to the app (`onMessage`, by type), and the app's calls into the page (`call:with:`,
  the arguments made JSON, and one method for each function the page core offers, as `update:`, `hoverAt:` and
  `stepNote:text:`). Only the page itself may send one: nothing in a frame of it, and no other page it would load.
- `app/Modules.h`, `app/Modules.m`: every module in the app, found at launch from the classes that adopt Module
  (contracts/Module.h), with no list to keep; the page's messages routed to the one module that answers each type (or
  the core), the print modes' flags and the words a session asks with likewise; and what each module adds, gathered
  in their order (the pawn menu's entries, the back's apps, Settings' rows, notices, session switches). Two modules
  claiming one message, flag or word is a clash the tests fail on.
- `page/modules.js`: the page's `core`, the lists the core's scripts and the modules' register with as they load
  (`core.starts`, `core.updates`, `core.places`, `core.pointerTargets` and the rest), and a module's own state
  (`moduleState`).
- `page/app-calls.js`: the frame's own functions the app calls on the page (`update`, `setRoom`,
  `setConversationShown`, `toggleCollapsed`, `hoverAt`, `hoverEnd`, `keyboardGone`, `turned`, `setRunningBuild`,
  `setSwitches`, `stepNote` and `panelSeen`);
  the folded panel's, the reader's, the side the reader would open to (`readerSide`) and `turnToApps` are beside what
  they draw (cat.js, peek.js, the pane's reader.js, the row's rows.js, input.js), as each module's are; it's the page's last script, so the modules start (`core.starts`) once the page is
  whole.
- `part.json`: its files for tools/page.sh, and what it provides.

## Who it talks to

It provides `Page.h`, `Modules.h`, `core`, `moduleState` and `toggleCollapsed` (the folded panel, the list's chevron and
the starts module fold and open the panel with it), and talks to the core, hover, the keyboard, peek and the list
(`talksTo` in part.json):

- **The app's start-up and the core** make the page (AppDelegate) and the modules (Core.m), and the rows are sent
  each second (`update:`, Rows.m). Every module that calls its own page functions imports `Page.h`, and those that
  ask the modules something import `Modules.h`.
- **The parts** call the page through it natively (the glass, the fold, hover, turn, flick, the pane, beside, the
  keyboard, focus, send, the pawn menu and Settings), printing asks the modules (`Modules`), and on the page plug into
  `core`'s lists (the list, the row, morph, a row's details, hover, the keyboard, the pane, the header, the held row,
  peek and beside).
- **On the page,** what the app calls goes on to the list's drawing and folding (`render`, `renderWhenSettled`,
  `reportHeight`, `forgetGone`, `openedNow`, `foldPanel`, parts/list), to hover (`pointerAt`, `pointerGone`), to the
  keyboard (`textBoxes`) and to peek (`peekPointer`, `peekStays`, `peekHeaderBack`).

## Rules

- **Only the panel's own page talks to the app.** The panel only ever shows panel.html, a page a session wrote shows in
  a Browser of its own with no bridge, and nothing in a frame may answer a request: [the panel's own
  rules](../../docs/how-it-works/panel-rules.md).
- **The app runs nothing in the page but its functions** (and a wait for the page's next drawing, `afterPaint:`), and
  any text it passes goes as JSON, so it arrives as it was.
- **A module only registers with `core` as its scripts load,** and the core runs it: its start-up once every script has
  loaded, its part of each update, fold, row and press. So a module never acts before the page is whole, and never
  needs to name another.
