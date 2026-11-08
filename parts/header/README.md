# Header

The panel's header: Whozmove's name, the build running now under it while Show Build in Header is on, and its buttons.
It lies over the list's top, and stays there as the list scrolls until the row you're on, held at the list's top, has
folded all it can there: scrolling on, that pushes it up and away, point for point, and it comes back as the list
scrolls back to its very top.

## What it shows

- The name, drawn from its letters with the folded panel's shape for its first o, and the running build under it.
- The ＋ for a new conversation, which turns into a × while its card is open.
- Its line along the list's top, which goes as the held row's copy meets it, or while a card or a line is under the
  header; how much of it shows is set on the panel's root, so the peek's head follows it (parts/peek).

The header's own markup is in panel/panel.html. The bare `header` rules, its layout and the apps and chevron buttons,
stay in panel/styles/base.css, as the panel's back has a header of its own that shares them.

## What it owns

- `page/header.js`: how far the header has gone (`headerAfterScroll`, `headerGone`, `headerMayGo`: plain functions,
  checked by tests/panel.sh), moving it and clipping the list at its edge (`headerShow`, `headerGlideTo`,
  `headerAllThere`), its line (`headerLine`), how much of the list's top it covers (`headerInset`), and telling the
  app how much of it shows and whether it has gone (`headerTell`). What it keeps between rebuilds is `state.header`,
  declared with the page's other state in panel/scripts/state.js.
- `page/builds.js`: the header's name for the running build (`headerBuild`, `buildLabel`: plain functions, checked
  by tests/panel.sh).
- `page/header.css`: the name, the build, the ＋, and how the header lies over the list's top with its line.
- `part.json`: its files for tools/page.sh, and what it provides.

## Who it talks to

It talks to the core, the bridge, the list, whose `ago` says how long ago the running build was built (parts/list's
whose-move.js), and morph, for reduced motion (`calm`, parts/morph) (`talksTo` in part.json), and provides
`headerInset`, `headerOff`, `headerAllThere`, `headerLine`, `headerGlideTo` and `headerBuild`:

- **The held row** (parts/held) measures the list's top from the header's edge (`headerInset`) and sets its line
  (`headerLine`), as its hand-off does once its copy has gone (parts/handoff). The header reaches it only through two of
  the bridge's hooks (`core`, parts/bridge): it tells what's measured from its edge each time it moves
  (`core.headerMoves`, which places the held row again), and reads one number, how far the held row's copy has gone past
  where it folded all it can (`core.heldPast`).
- **The folded panel** (cat.js, panel.js) measures the name's o where the header has it all there (`headerOff`,
  `headerAllThere`); the reader brings it back as it opens (`headerGlideTo`); the list's visible part starts at its
  edge (`listBand`, util.js; waiting.js).
- **The starts module** drives the ＋ itself: it finds `header .add-new`, turns it into a × while a new
  conversation's card is open (its `.open` and title) and takes its press; and it hops the name's o
  (`header .name-cat`, starts.css). The folded panel's styles (cat.css, chats.css, peek.css) style the header's name
  and buttons as the panel folds and opens.
- **The app** hears how much of it shows, for the drag strip over it, and when it has gone, for Whozmove beside the
  panel (the `header` message).
- **The running build** comes from the app (`setRunningBuild`, the bridge's app-calls.js), and the list's drawing names
  it with `headerBuild` (panel.js, parts/list).

## Rules

- **It's all there** while the list is too short to scroll, the reader is open, or a card, the setup line or
  notifications' line is under it; folded, it stays as it was, out of sight, until the panel opens.
- **It moves with the scroll, point for point,** and comes back only as the list's very top comes back into view.
- **Whozmove beside the panel comes out once the header has all gone,** and goes back only once the header has come
  back a few points, so a jitter of the scroll doesn't send it in and out (`headerGone`).
- `HEADER_TALL` matches `--header` and its line (tokens.css) and `kHeaderHeight` (app/core/PanelWindow+Private.h).
