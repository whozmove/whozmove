# Held

The row you're on, held at the list's edge: it never leaves the list's visible part. As the list scrolls past the
session you're on, or moves its row out of sight by itself, the row holds on at the list's top (past the header's
edge, wherever that has been pushed to) or at its bottom, folded down to its title line, Claude's line and where it
runs, and opens back into its place as it comes back. Folded all it can at the top, it's what pushes the header away as
the list scrolls on.

## What it shows

- A copy of the row laid over the list's edge, with its tint under the list, while the row itself keeps its place in
  the list, hidden, so nothing in the list moves.
- The copy folding down, line by line, as the row goes past the edge, and opening back out as it comes back. A line
  that says it folds first (`core.lines`' `foldsFirst`: a row's details, the last thing opened on it) goes before the
  others at either edge.
- A press on the copy scrolling the list back to the row, in one eased move.
- The row left near the list's top or bottom edge it was heading for as your scroll ends: the list going on the last
  bit by itself, so the row clicks onto the edge.

## What it owns

- `page/sticky.js`:
  - the plain functions tests/panel.sh checks: where the edge is (`stickyEdge`), whether to hold on (`stickyHold`),
    how it keeps up (`stickyEase`), how it folds (`stickyFold`, `stickyLineFold`), how far a row is shown inside the
    edge (`showAt`), what the copy covers (`stickyCovers`), how far the list goes on by itself as your scroll
    ends (`stickySnapBy`), and the least it moves to show a box just opened past its edge (`leastToShow`);
  - laying it out: the row you're on (`focusedRow`), its copy (`stickyCopyOf`, `stickyCopy`, `stickyChat`,
    `stickyMeasure`, `stickyLeast`), placing it (`stickyRefresh`, `stickyPlace`, `stickyInsets`, `stickyFolded`), how
    far it has gone past where it folds all it can (`stickyPush`), its lines folding (`stickyFoldLine`), the mask over
    the list and its fade (`stickyShade`, `stickyRamp`);
  - the pointer and presses on it (`stickyAt`, `stickyBack`), what it is for a chat landing on it (`heldRowOf`),
    scrolling the list just enough to show a row whole, clear of the copy (`showInList`, `showInListBy`), or a box
    you're about to type in, never centring it nor taking its card's top out of view (`showLeast`), and the list's
    last bit as your scroll ends (`stickySnap`), on morph's `pullScroll`.

  What it keeps between rebuilds is `state.sticky` (state.js); its two layers are in panel/panel.html (`#sticky`,
  `#sticky-under`), and their look in the row part's rows.css.
- `part.json`: its file for tools/page.sh, who it talks to, and what it provides.

## Who it talks to

It talks to the core, the bridge, the handoff, the header, the list, morph and hover (`talksTo` in part.json), and
provides what the others call, as part.json lists:

- **The bridge's hooks:** it's laid out again once the list is drawn and as the header moves, tells the header how far
  it has gone past where it folds all it can, and is a place the pointer can be on (`core.afterDraw`,
  `core.headerMoves`, `core.heldPast`, `core.pointerTargets`, parts/bridge).
- **The handoff** (parts/handoff) lets its copy go, and slides it off as the session you're on changes
  (`stickyLetGo`, `stickyHandOff`); the handoff lays its copy out again and fades it on held's own (`stickyPlace`,
  `stickyShade`, `stickyRamp`).
- **The header** says where its edge is (`headerInset`) and takes its line from it (`headerLine`, parts/header); the
  list keeps a pressed row in place (`keepInPlace`) and asks it to show a row (`showInList`, parts/list); its lines
  fold and write on morph's helpers (`tween`, `rewriteLine`, `settleLine`, `partText`, `keepInStep`, parts/morph); and
  hover finds what the pointer is on over its copy (`stickyAt`, parts/hover), as it has hover look again
  (`syncHover`).
- **The chats' landing** (parts/landing) asks what the held row is for a chat landing on it (`heldRowOf`: its edge, its
  copy and the lines that stay, while it holds that session's row), and folds a chat as its lines do (`stickyFold`,
  `stickyFoldLine`, `stickyMeasure`, `stickyCopyOf`, `stickyPlace`, and its layers `stickyEl` and `stickyUnder`). The
  core's waiting strips keep clear of it (`showInListBy`, `stickyPlace`), the starts module shows a new
  conversation's row (`showInList`), and a row's details, opened near the list's foot, are shown whole (`showLeast`,
  parts/details).

## Rules

- **The row stays in the list, keeping its place:** a copy of it holds on, so nothing in the list moves.
- **Everything follows where the row's place is,** catching up where it moves faster than a slow scroll, so scrolling
  back runs it all backwards.
- **A scroll over the copy scrolls the list:** the copy takes no pointer events itself.
- **Never held while one of its boxes is typed in, or while it's taller than the list's visible part** (`stickyHold`):
  holding it would take the box from under your typing, and a row that tall could never show whole, so its buttons
  would be out of reach.
- **The copy is only a picture of the row:** made only while the row is held, inert, and without the data the page
  finds rows by (`stickyCopyOf`), so no part takes it for the row, and nothing on it can take the keyboard or answer a
  request; a press on it only scrolls back to the row.
