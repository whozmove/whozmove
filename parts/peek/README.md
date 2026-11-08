# Peek

The folded panel's list while it's pointed at. Resting on the folded panel a moment, the panel opens as a press opens
it, the glass spreading out from behind it; the chats beside it go in first. It's the open panel but for its header: a
head as tall stands in for it, with the folded panel in it as it is, where the name's o is, and at its other end how
many are waiting on you. Moving off the panel, it folds back, and the chats come back out.

## What it shows

- The head in the header's place: its line, which comes and goes as the header's does, the folded panel where the
  name's o is, and how many sessions are waiting on you, where the header's buttons are.
- The list, with the lines under the header and a card at its top, coming in as it does as the panel opens, and going
  as it folds.
- Pressing the folded panel or the head only finishes opening it: the head's words go, the name comes in round the o,
  and the header's buttons come in where the words were.

## What it owns

- `page/peek.js`: what the head says (`peekTitle`), whether the list may come out now (`peekMay`), where the pointer
  is (`peekPointer`), the list coming out and going (`peekOpen`, `peekGoes`), pressing it to open the panel for good
  (`peekStays`), the header back in the head's place (`peekHeaderBack`), and how long each takes (`PEEK_REST`,
  `PEEK_LEAVE`, `PEEK_FOLD`); the app tells it when the folded panel is pressed (`catPressed`) and when the panel was
  flicked off the screen's edge (`flickedAway`). What it keeps between rebuilds is `state.peek` (state.js).
- `page/peek.css`: the head, and the open panel without its header.
- `part.json`: its files for tools/page.sh, who it talks to, and what it provides.

## Who it talks to

It talks to the core, the bridge, the keyboard, the folded panel's part, the list, the header and morph, for reduced
motion (`calm`, parts/morph) (`talksTo` in part.json), and provides `peekPointer`, `peekStays` and `peekHeaderBack`:

- **The bridge** passes on where the pointer is, and a press that opens the panel for good (`hoverAt`, `hoverEnd`,
  `toggleCollapsed`, parts/bridge), and it names the waiting sessions again after each rebuild of the list
  (`core.afterDraw`).
- **The folded panel** (parts/cat) opens round it and says where the pointer is on it (`catOpening`, `catOnGlass`,
  `catHover`, `pointOnCat`); the list's drawing folds and opens the panel for it (`foldPanel`, with `peek`, parts/list's
  panel.js), and the app folds the glass back round it (parts/fold). It has the chats go in and come back out round it
  (`chatsLeave`, parts/landing; `drawChats`, `chatsPlaced`, parts/chats), and counts those waiting on you as the list
  does (`waitsOnYou`, parts/list's whose-move.js).
- **The header** (parts/header) sets how much of its line shows, which the head's line follows (`--line`, set by
  `headerLine`).
- **The keyboard** keeps it out while one of the panel's boxes is typed in (`textBoxes`, parts/keyboard).

## Rules

- **Not while the folded panel is pressed:** a press opens the panel or drags it.
- **Off the panel, it goes,** but not while one of its boxes is typed in, nor while the pointer is on what the panel
  holds over or under itself.
- **How the panel was left isn't kept** as its list comes out and goes back; opening it for good is.