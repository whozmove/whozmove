# Keyboard

When the panel takes the keyboard, and how it gives it back. The panel must never take the keyboard from the app you're
typing in: it has it only while one of its boxes is typed in, a card that answers to keys has been pressed, a site in
it has been clicked into, or the new conversation card is open, and hands it back to the app in front as soon as that
ends.

## What it owns

- `app/PanelWindow+Keyboard.m`: the window's Keyboard category. Taking the keyboard for a box of the page's
  (`takeKeyboard:`, `wantKeyboard:`) or a site's (`clickedAt:`, `browserAt:`), giving it back to the app in front
  through a window of its own that can't be seen (`releaseKeyboard`, `giveBackKeyboard`, `dropKeyboard`,
  `keptKeyboard`), passing the pointer's moves to a site (`pointBrowsersAt:moved:`, with `PassPointer`), and a menu at
  a point in the page (`popUpMenu:atPagePoint:`).
- `page/keyboard.js`: the boxes that take the keyboard (`TEXT_BOX`, `textBoxes`, the modules' `core.textBoxes`), the
  card that has it once it or a box in it is pressed (`pressTakesKeys`, `heldCard`, the modules' `core.keyCards`), in
  the list or a place beside it where a module draws rows (`keyPlaces`, the modules' `core.keyPlaces`), asking the app
  for it or giving it back
  (`wantKeyboard`), whether the panel has it now (`hasKeyboard`, as notifications asks), the keys on that card (Return presses its main button, Esc lets go), and its edge
  (`showHeldCard`, after the list is drawn, and by a place beside it drawn after that); and the view beside the list
  once pressed in (`viewPressed`, `viewHasKeys`), which Esc closes (`escClosesView`), as its ✕ does (`closeReader`,
  parts/pane), and where no other key acts while nothing in it is typed in (`viewKeyOnly`).
- `part.json`: its files, and what it provides.

## Who it talks to

It talks to the core, the bridge, the pane, the glass, the row, whose `justShown` keeps a card that has only just come
from taking the keyboard, and the list, whose element it looks for a card's boxes in (`list`, parts/list) (`talksTo` in
part.json): the window's own state and the other parts' methods through the private header
(app/core/PanelWindow+Private.h), its public methods in PanelWindow.h's Keyboard category, and on the page the bridge's
hooks (`core.textBoxes`, `core.keyCards`, `core.keyPlaces`, parts/bridge); and the pane's `Browser`, which it asks which
sites are in the panel's window (`inWindow:`), to give one the keyboard and pass it the pointer. The folding, turning
and flicking parts give it back as they start (`dropKeyboard`); Focus (parts/focus) has it give the keyboard back as a
session opens (`releaseKeyboard`, `keptKeyboard`); hover asks where the text boxes are (`textBoxes`), as the bridge,
peek and the new conversation's card do, and the list (parts/list) and the reader (parts/pane) find a card's boxes by
`TEXT_BOX`. It calls the glass's (parts/glass) `pageLeft`, `pageTop`, from the private header
(app/core/PanelWindow+Private.h).

## Rules

- **The panel must never take the keyboard** but while one of its boxes, a card or a site in it, or the view beside the
  list, has been clicked into, or the new conversation card is open, and then hands it back to the app in front
  ([the panel's own rules](../../docs/how-it-works/panel-rules.md)).
- **Giving a box the keys never scrolls the list** (`focus({ preventScroll: true })`, which tests/checks.sh looks for):
  WebKit would centre a box not wholly in view, and the list would jump under you. A box that opens out of view is
  shown by the least move that shows it (`showLeast`, parts/held).
- **Leaving a box waits a moment:** the list is drawn again whenever what it shows changes, any second, which swaps
  the box for a fresh one.
- **A card answered by its press doesn't take the keyboard** for that press, and one that has only just come isn't
  pressed by accident (`justShown`).
- **A card is held however you came in:** a press on the card or straight into a box in it holds it, so an Esc in the
  box leaves the keys on the card, and the next Esc lets go of them: its module's Esc (`core.escapes`) where it takes
  one, else the box is left, keeping what's typed in it (`keyOnHeldCard`). A box in no such card holds none.
- **Only the copy pressed has the keys.** A request drawn in two places (the list and a place beside it) is two cards
  with one id: the press remembers its place, so its keys answer that copy, once, and only that copy shows it has them.
- **An edit key goes by the letter it makes with ⌘ held,** as a menu's shortcuts are matched (`EditFor`, in
  app/shared/EditKeys.m), so ⌘V pastes on a Russian or Greek layout too, and a dictation app that pastes its words in
  with ⌘V reaches the box being typed in. Whozmove has no Edit menu to give it these keys, and the panel never takes
  the keyboard for them.
- **Only a press in the view beside the list gives it the keys,** never its opening: a row's tag leaves them with the
  app in front. Esc closes it unless something takes Esc first: the card that has the keys lets go, a module's own box
  does what its module says, and a box with words typed in it is left, keeping them, so the next Esc closes it.
- **A place says which of its cards can have the keys** (`{ el, open(card, pressing) }`): the chats beside the folded
  panel only while one is out where it can be seen, and for a press, once it has stayed where it is a moment.
