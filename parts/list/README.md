# List

The list of sessions: the rows read once a second and sent to the page, what each session is and whose move it is,
the order they're shown in, drawing the list again as they change, and what a press or a key does on it.

## What it shows

- Every session as a row, sorted by whose move it is, grouped by project or a module's grouping, or newest first.
- The row you're on with its tint, and a row you've pressed kept in its place until you've moved on from the panel.
- The list scrolling just enough to show the row you're on as that changes, but never under a press.
- The panel growing to fit the list, and what hangs below it.
- The list filling the panel down to the strips at its foot whenever the panel is taller than its rows need.

## What it owns

- `app/Rows.h`, `app/Rows.m`: the rows, read once a second and whenever one has something new to show (`start`,
  `refresh`, `read:`): the sessions on their own queue, from the agents and the hosts, then each module's part of every
  row, phase by phase on the main thread, then sent to the page (`update:`).
- `page/whose-move.js`: what each session is (`classify`), whether you've read its reply and since when you've been on
  it (`isRead`, `stillToRead`, `onItAt`, `stillOnIt`, `waitsOnYou`, `turnSince`), the list's order (`placeRows`,
  `lastActive`, `steady`), which session speaks for each checkout (`checkoutOwners`, `unpushedCommits`, `projectOf`) and
  how long ago or how long is left (`ago`, `elapsed`, `minutesLeft`): plain functions, checked by tests/panel.sh.
- `page/panel.js`: the list drawn again (`render`, `renderWhenSettled`), the session you're on and what you've read
  (`goTo`, `followClaude`, `noteOnIt`, `keepSeen`, `keepToRead`, `openedNow`), its row shown as that changes
  (`revealOpenConversation`, `revealsOpen`), the rows you pressed kept in place (`keepInPlace`, `heldNow`), the panel's
  height (`reportHeight`, `hangingBelow`, what it asks for with the list at its usual limit, the glass's for the
  screen: `askedHeight`, `panelAsks`, and how tall the lines under the header are, which the glass always keeps room
  for: `linesUnder`) and the list filling a taller panel (`listFill`, `panelRoom`, `fillList`), what's kept for a session
  that's gone (`forgetGone`), the header's name for the running build (`nameRunningBuild`), and the page's side of
  folding (`foldPanel`, `stillFolded`, `openFromCat`).
- `page/strips.js`: a strip under the list changing its text, easing to a new height, growing in and folding away
  (`setText`, `easeHeight`, `growIn`, `foldAway`).
- `page/input.js`: what a press, a key or typing does on the list, the modules' handlers first (`core.presses`,
  `core.typing`, `core.returns`, and `core.escapes`, Esc in a box of a module's own card, the first match taking it) and
  the list's own last: a note's button (`pressNoteWay`: the terminal's way past, Take me there, or a module's own,
  `core.noteWays`), a group's header, a project's, and the row itself, opening its session (`openSession`); a group slid
  open or shut on morph's `slideGroup`, and the list drawn again once it has; and the header's apps button turning the
  panel over, as Settings… in the pawn menu does (`turnToApps`).
- `part.json`: its files for tools/page.sh, who it talks to, and what it provides.

## Who it talks to

It talks to the core, the bridge, focus, the row, morph, the keyboard, the pane, the header, hover, the folded panel's
part, the chats, drawn with the list (`drawChats`, parts/chats), their landing as the panel opens (`chatsLand`,
parts/landing), and the held row, whose copy goes with the list as it moves and which shows the row you're on when it
changes (`stickyPlace`, `focusedRow`, `showInList`, parts/held) (`talksTo` in part.json), and provides `Rows.h`, the
list's element (`list`, for the keyboard), and what the others call (the drawing, the panel's height, the rows kept in
place, whose move it is, and the page's side of folding), as part.json lists:

- **Natively,** the core makes the rows and the modules fill them in (`Core.m`, `Module.h`'s phases); they're sent
  through the bridge's `Page`, and focus says which session you're on (`Focus.h`). The app's start-up, the core, the
  modules that read the rows (Claude Code's, the commands', Deploy's, git's, the install module's, bring-forward's and
  Storage's), focus, send and printing import `Rows.h`.
- **On the page,** the bridge's calls from the app draw the list again and keep its sessions (`render`,
  `renderWhenSettled`, `forgetGone`, `openedNow`); each row is the row part's (`rowsHTML`, `groupsHTML`,
  `projectsHTML`), and the list moves from what it was by morph (`morph`). As it draws, it has hover look again at what
  the pointer is on (`syncHover`), the reader drawn and fitted (`drawReader`, `fitReader`), the folded panel posed
  (`drawCat`, `catLook`), the header named (`headerBuild`) and the keyboard let go once no box on the list keeps it
  (`keepsKeyboard`, `wantKeyboard`).

## Rules

- **Sorting and grouping are deliberate:** read [the panel's own rules](../../docs/how-it-works/panel-rules.md) and the
  comments in whose-move.js before changing them.
- **A row you pressed keeps its place** until you've moved on from the panel: your pointer off it, and none of its
  boxes with the keyboard. Meanwhile the list doesn't scroll by itself to show the row you're on.
- **The list scrolls on by itself as your own scroll ends** only to take the row you're on the last bit onto its edge:
  the held part's rule (`stickySnap`, parts/held).
- **The list is drawn again only once what's moving has settled,** or at once for the session you're on changing in
  its app, as a press here does.
- **Presses are handled on `mousedown`,** not on click: [the panel's own rules](../../docs/how-it-works/panel-rules.md).
- **Only a message takes a row to the top** (`lastActive`, `movedAt`): Claude's reply, a request or yours. A change of
  model or status doesn't, nor does the summary a compaction leaves, which Claude Code writes down as your message
  though you sent nothing (the Claude Code module's transcript reading skips it).
- **A time that counts by itself is a clock the tick sets,** never a reason to draw the list again: how long ago, how
  long a step has run, how long is left (`data-since`, `data-ago`, `data-left`, and `data-until` with `data-span` for a
  ring), set each second by the row part's `tickTimes`, so the list keeps its rows, and the boxes in them, between
  updates.
