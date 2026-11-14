# Row

A session's row, and the cards on it: its template, with the places the modules fill, the group and project headers,
and the shared look of the cards a row shows (a request or a question, Compact, Deploy's set-up, "Switch model?", a
pick going in), with when a press on what's only just appeared counts.

## What it shows

- The row: its dot, the last exchange, the details line with where it runs and the context ring, its notes and its
  steps, and whatever the modules put in its places.
- The project and group headers the list is grouped under.
- The cards on a row, and what where a session runs and a session open twice say in their details; "Open twice" in
  words beside its icon.
- A row's bar at its far edge, the side the reader opens on: a strip in the row's last 8 points, past the end of its
  lines, where a module puts its button; the bar there faint while the row is pointed at, swelling a little and lit
  while the strip is, kept lit or in your move's colour when the module asks. The row never moves for it.

## What it owns

- `page/rows.js`: a session's row (`rowHTML`), what's on it (`chatHTML`, the line saying what it's doing while it works,
  `workLineHTML`, `workHTML`, `whereHTML`, `noteHTML`,
  `stepLine`: a module's note on a line of its own with `line`, and one in your move's colour giving way to any other),
  a module's ask line, what waits on you in a few words after its priority's name or a mark, with "+N"
  (`askLineHTML`: the module's words and attributes, its own press), in a bubble coloured by how pressing it is
  (`isAsk`, the note's `look`), ending in its one action (the note's `act`, its button drawn by `askActHTML`), its
  cards in their order (`rowCard`, `openingCard`), its details at the end of its lines
  (`detailsHTML`, parts/details), what where it runs and open twice say in theirs (`placeCardHTML`, `twiceCardHTML`), the app it runs in (`hostOf`, `worktreeChip`), the modules' places on it (`slot`, `core.slots`, with whether Claude's line is there for theirs at its end, `row.claudeLine`, whether the row asks something of you and for what, `row.asking` and `row.askWant`, whose one action another module may give, `askAct`, whether the bottom line's end is drawn, `row.placeEnd` (never while the row asks), and whether it is drawn at the end of the row's note, `row.endAtNote`: on a row shown briefly, with what stays on the bottom line whatever its end does before it, `placeStays`; the title line's gap before what goes at its end, and the time's width after it),
  the list's groups' HTML (`groupsHTML`), whether a row is in view
  (`rowInView`), its times kept
  ticking without the list being drawn again (`tickTimes`), and the strip at its far edge: whose strip the pointer is
  on, marked in place as hover looks and drawn so from `state.edgePointed` (state.js), on the side the app says the
  reader would open to (`readerSide`, as `far-left`), there whatever card is open on the row; and what a row keeps
  while Settings' Show Conversation Text is off (`state.conversationShown`, set by the bridge's
  `setConversationShown`): Claude's line only
  where `conversationLine` keeps it, and the dot saying the row's state in words (`dotWords`).
- `page/fresh.js`: whether a card or button has only just been shown, so a press on it doesn't count yet (`justShown`,
  `shownFor`, `showAgain`, `FRESH_MS`), and how a request was answered here (`answered`).
- `page/rows.css`: the row, and the strip and bar at its far edge.
- `page/cards.css`: the cards on a row, and what where it runs and open twice say in their details.
- `part.json`: its files for tools/page.sh, who it talks to, and what it provides.

## Who it talks to

It talks to the core, the bridge, the list, morph and the details (`talksTo` in part.json), and provides
the list's HTML and what the cards go by, as part.json lists:

- **The bridge's hooks** are where the modules plug into a row (`core.slots`, `core.rowCards`, `core.hosts`,
  parts/bridge). A module that puts something of its own after the context ring for a while marks the row
  `place-gives-way` (through `core.slots.rowClass`), and where the session runs makes way for it first (rows.css).
- **The list** draws it (`groupsHTML`, `tickTimes`, parts/list, in the groups its `listGroups` gives), and it reads from
  the list whose move it is (`waitsOnYou`, `isRead`, `view`, `lastActive`, `projectOf`, `ago`, `elapsed`,
  `minutesLeft`).
- **A row's details** (parts/details) are drawn at the end of its lines (`detailsHTML`), from what the row has as it's
  drawn.
- **A row's details, the keyboard and the modules** go by `justShown`, and the held row's hand-off has what's on a row
  count as only just shown once it's back (`showAgain`, parts/handoff).
- **A module that shows what a session is doing** away from its row (at a side chat's foot) draws the row's own line
  for it (`workLineHTML`, with its own label), so it reads the same wherever it's drawn, its time kept ticking by
  `tickTimes`. Drawn inside a scroller under sticky bars (a side chat in One Task's view), it's `still`: the same
  words without the shine or the breathing, which WebKit would paint again every frame there.
- **The strip at a row's far edge** holds what a module gives in `core.slots.edge` (parts/bridge); its bar swells as
  hover looks (`core.pointerWatchers`, parts/hover), on the side the reader opens (`.far-left` on the page, set by its
  own `readerSide` as the app tells it, parts/bridge).

## Rules

- **The strip at a row's far edge knows nothing of what's in it:** the module gives what fills it, and marks it
  `.keep` to keep the bar lit or `.lit` to light it in your move's colour; the row draws only the strip and its bar.
- **The strip never covers what's pressable, and never moves the row:** it's the row's own padding past the end of its
  lines, so Deploy, a next step and the folder name are pressed where they're drawn. Whether its bar is swelled is kept
  in state and drawn by rowHTML, so the list drawn again never plays the swell twice. A row with a card open on it
  keeps its strip: the card ends at the row's lines, its buttons further in, so the strip never covers them; the
  module whose button it is decides when a press there counts (Side Chat's waits until a request has been seen a
  moment).
- **The ask line names nothing of its own:** the module gives its words, its priority's name, how pressing it is, its
  tip for "+N", its label and what a press on it does; the row draws the name or the mark, the words and the bubble
  (`.ask-note`, `.ask-urgent`, `.ask-normal`, `.ask-low`), the same for every module, and keeps its action outside its
  press. **One ask, one action:** an ask ends in the one button for what it asks (`act`): another module's for what it
  wants (`askAct`: Deploy for 'try', the reader's button for 'plan' and 'look'), else the module's own; and while a row
  asks, the row draws the bottom line's end (`placeEnd`, Deploy) nowhere, and each module with an action elsewhere on
  the row decides for itself, from `row.asking`, to leave it off (the commands module's context ring on the bottom
  line). A swap at the ask's end (Copy for Deploy) waits to be seen, as a move does (`state.briefEnds`). Why: an ask
  shows the one thing to press for it, never its plan, the context ring and Deploy at once. Deploy's address stays on
  the bottom line (`placeStays`), where it can be pressed.
- **A press on what has only just appeared doesn't count:** it may have taken the place of what was being pressed, and
  it hasn't been seen yet (`justShown`).
- **The cards use the kit's pieces** (controls.css): its buttons, its box to tick, its box to type in and its notice.
- **The row's template is this part's;** what a module shows on it goes in its places, each giving its HTML or nothing.
- **A row shows one card at a time:** of the cards that want it, the one with the lowest `order` (`rowCard`), so a card
  that may stay up a long while takes a high order, and a request that comes meanwhile shows in its place.
- **What a card would run or change is there whole to read** (`.perm-detail`): wrapped, by default, with a scroll of its
  own past a few lines. Only a card that offers Show all cuts its lines (`.cut`), and Show all shows them whole again.
- **The bottom line keeps its room:** a session open twice is a mark after the time on the title line (`twiceHTML`), and
  short of room, a long name where it runs (past a dozen letters) gives way first, then the effort and the model; the
  name keeps its dozen letters (a shorter one all of them), whatever a module puts after it.
- **With Show Conversation Text off, a row shows no one's words:** not yours, not another session's, not Claude's reply
  or step, nor a module's line in Claude's place beside the folded panel. Claude's line stays only while it says what
  the panel knows (`conversationLine`: a request or a question, what you just answered, compacting, a conversation
  still starting); the cards, the notes (an ask line among them), what runs in the background and the bottom line stay.
- **A row in the list is shown briefly, and says each thing once** (`row.brief`, set by the row part for every row but
  a chat beside the folded panel and a start still under way; `briefLine`): Claude's line only where nothing else says
  it (what it asks with no card, or its finished line on a reply you haven't read), never under an ask's bubble or a
  request's card, nor while it works or once its reply is read. No module hides it; Show Conversation Text off hides
  it as on any row.
- **The row you're on keeps its tools** (`row.tools`: a short row whose session is the one in front in its app,
  `s.focused`): its work line and bottom line, as a whole row has, so the session you're working in can be steered from
  the list. A module that puts something elsewhere on a short row for want of a bottom line (the context ring, Deploy's
  address) leaves it there on this one. A row that gains or loses its work line and bottom line (the row you're on
  changing, or a start from the panel landing) counts what's on it as only just shown, as when its end moves.
- **The work line goes while the session's agent works,** asks along the way or compacts, but for a note, which it
  keeps saying in its place (`workHTML`).
