# Details

A row's details: what something on a row says when you rest the pointer on it a moment, a PR, "+N more open", the
row's numbers, where it runs, a session open twice, Create PR or a team's job. They open inside the row,
under its own lines, and the rows below move down to make room; nothing is ever laid over the list. They work the same
in a chat beside the folded panel, which is its row.

## What it shows

- The details (`.details`): a line of the row, after its bottom line, on a step of their own (the hover tint, the box
  corner, no edge or shadow; the tint of the row you're on, on that row), with the kit's card head, title and lead.
- The steps on them (`.st-steps`), under a line, as a menu's items are, and what they say while a step waits
  (`.st-wait`).
- A long title in them (`detailsTitleHTML`): a short head in bold, the rest in the body's weight, cut at a word with
  "…" (the rules below).

What fills them is drawn by whoever has them (the modules' and the core's makers, `core.cards`), with the kit's card
head, title and lead, and their own styles beside their code.

## What it owns

- `page/details.js`: what decides how they go (`detailsNext`, a plain function, checked by tests/panel.sh), what's open
  and what the pointer rests on (`state.details`, declared with the page's other state in panel/scripts/state.js),
  finding what has details (`detailsAnchor`, `detailsKey`, `detailsAnchorIn`), drawing them in their row
  (`detailsHTML`, `detailsBlock`), a long title in them (`detailsTitle`, a plain function, and `detailsTitleHTML`),
  opening and closing them (`detailsFor`, `detailsOpen`, `detailsClose`,
  `detailsDraw`), the list easing to show them (`detailsReveal`), the row kept still as the list moves
  (`detailsHeldRow`), and a press on one of their buttons.
- `page/details.css`: their step, and the steps on them.
- `part.json`: its files for tools/page.sh, who it talks to, and what it provides.

## Who it talks to

It talks to the core, the bridge, hover, the list, the row, the held row and morph (`talksTo` in part.json):

- **Hover** (parts/hover) tells it what the pointer is on, each time it looks (`detailsFor`), once the modules' pointer
  watchers have, and looks again as the list scrolls under a still pointer.
- **The row** (parts/row) draws them at the end of its lines (`detailsHTML`), from what the row has as it's drawn.
- **Morph** (parts/morph) grows them in and folds them away as a line of the row (`.details` in its lines), and they
  say what counts as a change in them (`core.lines['.details']`'s `text`).
- **The held row** (parts/held) copies them with the row it holds at the list's edge, folding them first
  (`core.lines['.details']`'s `foldsFirst`), and shows them whole near the list's foot (`showLeast`).
- **The list** (parts/list and the core's waiting.js) is drawn again for them (`render`), keeps a pressed row in place
  (`keepInPlace`), and keeps the row they name still on the screen as it moves (`waitingHold` asks `detailsHeldRow`).
- **The makers** give their words through `core.cards`: each `{ selector, key(anchor), html(anchor) }`, and
  `press(key, act)` for those with buttons. The git module also opens Create PR's and "+N more open"'s details on a
  press (`detailsOpen`), asks which are open for Create PR's branch list (`detailsOpenKey`), and has them drawn again
  as the branches come in (`detailsDraw`). The team module shows a job's title with `detailsTitleHTML`.

## Rules

- **Never over the list.** They're a line of their row, so the list moving or scrolling takes them with it, and the
  rows below move down by their height as they open.
- **Resting opens them, passing doesn't:** the pointer rests on something a moment (0.3 s) before they open, so moving
  across the list doesn't open every row on the way. Pressing Create PR or "+N more open" on its row opens them at once,
  never the session. One is open at a time; resting on another thing in the same row changes them in place.
- **What's under the pointer never moves as they go.** Off their row upward, or off the list, they fold, moving only
  what's below the pointer. Off it downward onto the rows below, they fold while the list scrolls back by as much, so
  those rows stay still; near the list's top, where it can't scroll that far, the rows close up for the rest, once.
  Their room is never left empty.
- **They're shown whole:** opened where they don't fit below (a row near the panel's foot), once they've grown the list
  eases by just the part that's missing, down to the row's own foot, so the row's room under them stays as under any
  row, what was rested on staying in view. That move, and a reply moving the rows,
  are the list's own, not yours: they don't fold them meanwhile, and the row they're on keeps its place on the screen as
  the rows move. Your own scroll that takes their row from under the pointer folds them.
- **Never with words that no longer hold.** They're said afresh from what the row has each time it's drawn; what
  they're about gone from it (the PR merged, the other copy ended, the job moved on), they fold away as a line that's
  gone does, opening nothing else.
- **A press counts once they've been seen:** one on a button in them is passed on only once they've been up a moment
  (`justShown`), so details drawn under a moving pointer aren't pressed by accident. A press elsewhere in them does
  nothing (the row's own press would open the session).
- **A short title in bold:** a title with a ":" or " — " near its start shows what's before it in bold and the rest in
  the body's weight; one without is all bold while it's short, else all in the body's weight. The whole is cut at a word
  with "…", never inside a word.
- **They never take the keyboard.**
- **Reduced motion** opens, folds and scrolls them at once.
