# Commands

A session's model, effort and permission mode changed from its row, and a session compacted from its Compact card: the
menu opened where you pressed, the pick written as the slash command you'd type (in the words of the agent that runs
the session) and put in through the app the session runs in, and its result watched for, so the row shows the pick at
once and takes it back if it doesn't go through. It also says when it's a good time to compact a session (CompactTime),
and offers the way a compaction goes in to Compact at Breaks (modules/compact-at-breaks), which compacts by itself.

## Its pieces

- `app/CommandsModule.m`: its face for the core (contracts/Module.h): the page's `pick`, `compact` and `switchAnswer`,
  its part of each row (a pick the session hasn't confirmed yet, which its details show, a compaction under way, a pick
  on its way into a terminal session, `goingIn`, "Switch model?" while it's asked, `switchAsk`, and `noCompact` where a
  compaction certainly couldn't go in now, `CantCompactNow`), and its print mode.
- `app/Commands.m`: the menus and the Compact card, from the press to the result. A terminal session gets the pick
  typed into its tab (a mode by Shift+Tab presses, as many as its agent says take it there for certain); a Claude
  Desktop conversation gets it written in its message box, where the only mode a command can set is Plan, and "Switch
  model?" is asked in the panel first when Claude would ask it. A terminal session's model switch is noted as the
  panel's right before `/model` goes in, so the agent's hook asks its "Switch model?" in the panel too, when Claude
  Code would ask it, and your answer goes back to the hook. Why a menu or the card offers nothing now is worded by
  plain functions (`WhyNoPick`, `WhyNoCompact`), from the session's reach (`Send`, parts/send). When that's the
  terminal's own reason and it has a way past it (iTerm2's Python API, turned on), the menu and the card offer a
  button for it right under the reason (`WayPast`), which `Send` (parts/send) has the terminal take. At the foot of a
  session's mode menu, what it may do by itself, each switch a module registers (the core's Allowed: Don't Wait on Me,
  Let It Deploy, May Send Back Plans, May Answer Questions, May Approve Plans), its line saying what it does, or why it can't be turned on now (the switch's
  `whyNot`), or, while it's on, what it has done so far, when its module says (`says`). They type
  nothing into the session, so they're there whatever the menu says above; turning one off always can be. A greyed one
  has a way past its reason under it when its module has one (Set Up Deploy…). Above them, once Whozmove has
  restarted, one item, titled "Turn Back On" and each switch the core's Allowed still holds from before the restart
  (`waitingFor:`) by name, and the folder for those kept for one, with the line "They went off as Whozmove restarted",
  turns those back on with one press (`bringBack:`, which checks again what ticking checks); it names only those
  that can come back now, and is greyed with the reason the press would give (`bringableFor:among:why:`) only when
  none can. A switch's reason has its way
  past under it when its module gives one (`wayTitle`, or `wayTitleFor` the row), under a dash too. A switch kept for the row's folder that's off for it now (Allowed's
  `keptFolder:for:`) shows a dash on every row in that folder, with "Kept for <folder>, off now" and why; a press on it,
  as on a ticked one, turns it off, decided from what Allowed holds at the press, never from how the item was drawn.
  Its items are the only way a switch goes on (tests/checks.sh holds to it).
- `app/Command.m`: one slash command, from going in to its end.
- `app/CompactTime.m`: whether now is a natural break to compact a session (`CompactTime`, a plain function), the one
  rule the ring's "Compact now" and Compact at Breaks (modules/compact-at-breaks) both go by, on each row as its
  `compactTime`, worked out once the rows are whole, with who's been on each session from the rows before
  (`--print-compact-time`, checked by tests/rows.sh). A compaction goes in one way (`compactRow:focus:stillMay:
  whenOver:`), from the Compact card or by itself, which the module offers the others as `SessionCompacting`
  (contracts/Module.h).
- `page/commands.js`: the model, effort and mode labels at the start of a row's bottom line, the context ring (on a row
  shown briefly, at its note's end, before Deploy; never while the row asks something of you, `row.asking`, so the ask
  has one action) and the Compact card, and the card on a row while a pick goes into a
  terminal session (the row's `goingIn`): going in, then
  Claude Code asking about it in the terminal, with Take me there; `page/switch-model.js`: "Switch model?", asked on
  its row, as the card under its chat, for Claude Desktop and terminal sessions alike. The ring opens by itself into
  "Compact now" when it's a good time to compact (the row's `compactTime`), and turns as a short arc while the
  conversation compacts, settling at its new size once it's done (`ringSettle`). It
  doesn't say "Compact now" again while the size it has is still the one from before the compaction (`sizeBefore`),
  until the new size comes in, or for 30s at most, as a compaction stopped with Esc keeps its size.
  `module.json` lists them for tools/page.sh.

tests/rows.sh checks why each sample session's menus, Compact card and next steps would offer nothing now
(`--print-why-not`), with parts of a session's reach changed too, and what each session's mode menu says under each
switch at its foot.

## Between the page and the app

- The page sends `pick` (`{sessionId, field, x, y}`: a press on the model, effort or mode, whose menu opens there),
  `compact` (`{sessionId, focus}`: the Compact card's choice), `switchAnswer` (`{sessionId, ok, never}`: the answer to "Switch
  model?" asked on the row). The card's button past a terminal's reason sends `wayPast` (`{sessionId}`), which the core
  answers.
- A pick's note whose reason sends you to the session ("change it there") has Take me there, which opens it, and a
  switch's note that couldn't be changed has Open the Menu (`core.noteWays.modeMenu`), which opens the mode menu again
  under the row's mode, where it's pressed again, or where its reason's way past is: only the menu turns a switch on.
- The app calls `compactNote(sid, text, way)` when a compaction from the card didn't go through, or says why it can't,
  with the words of the button past that reason, or null.
- "Switch model?" is the row's `switchAsk` (`{from, to, tokens, never}`: `tokens`, how much the conversation holds,
  when its agent says; `never`, whether Don't ask again is offered, only where the app keeps that answer, Claude
  Desktop), on the row for as long as it's asked. Your answer goes to Claude Desktop's box, or straight to the terminal
  session's hook, and the card gives way to the pick going in, or to nothing, while the row catches up.

## Rules

- A pick goes in only while the session sits idle (in a terminal, at its prompt with no request waiting), checked again
  right before any key goes in, and a mode only where the Shift+Tab count is the same in every cycle the session could
  have: a key too many would land it in another mode, and none is risked where the cycle passes through Bypass.
- `/model` and `/effort` also save the pick as the default for new sessions, and a pick in the panel is for one
  session: the agent puts those defaults back once the command is over (`holdDefaults`/`releaseDefaults`). Keep that
  if you add commands.
- One change from the panel at a time: while a pick goes in or "Switch model?" is asked, the menus, the Compact card and
  the next steps say a change is still going in, so nothing typed meets Claude's question in the terminal.
- A switch noted for the hook is taken back once the command ends, whichever way, so the hook never allows a switch the
  panel didn't just make.
- The ring says "Compact now" only at a natural break, when compacting would lose nothing half done (`CompactTime`):
  while the session sits idle with nothing asked or going in, once it holds 200k or more (100k with a 200k window),
  when its work has just been saved, or it's nearly full (85%), or nobody has been on it for an hour, as Claude would
  read all of it again with the next message. Never for its size alone, never where a compaction couldn't go in
  (`noCompact`), and not again once the panel has compacted it, until its next message. While it's open, the row's
  place (its folder and branch) makes room for it.
- A compaction going in by itself (`SessionCompacting`) never beeps or opens the Compact card, goes only into a
  terminal and never one also open in Claude Desktop (`WhyNotByItself`), and stops before any key once what sent it
  says it may not (you came to the session). Its filler's Backspace, once the result comes, however late, goes in only
  while that still says it may: else it's left for you. How it ended (`CompactEnd`) goes back to what sent it, which
  says it on the row.
- A pick or a switch that can't go in never only beeps: its row's note says why, with the way past a terminal's reason
  when there is one (`cantPick:`), and one that stops part-way says it there too, or on the Compact card for a
  compaction (`abandon:`).
