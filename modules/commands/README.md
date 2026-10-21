# Commands

A session's model, effort and permission mode changed from its row, and a session compacted from its Compact card: the
menu opened where you pressed, the pick written as the slash command you'd type (in the words of the agent that runs
the session) and put in through the app the session runs in, and its result watched for, so the row shows the pick at
once and takes it back if it doesn't go through.

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
  plain functions (`WhyNoPick`, `WhyNoCompact`), from the session's reach (the core's `Send`). When that's the
  terminal's own reason and it has a way past it (iTerm2's Python API, turned on), the menu and the card offer a
  button for it right under the reason (`WayPast`), which the core's `Send` has the terminal take.
- `app/Command.m`: one slash command, from going in to its end.
- `page/commands.js`: the model, effort and mode labels at the start of a row's bottom line, the context ring and the
  Compact card, and the card on a row while a pick goes into a terminal session (the row's `goingIn`): going in, then
  Claude Code asking about it in the terminal, with Take me there; `page/switch-model.js`: "Switch model?", asked on
  its row, as the card under its chat, for Claude Desktop and terminal sessions alike. The ring opens by itself into
  "Compact now" when it's a good time to compact (`compactNow`: a plain function, checked by tests/panel.sh), and
  turns as a short arc while the conversation compacts, settling at its new size once it's done (`ringSettle`). It
  doesn't say "Compact now" again while the size it has is still the one from before the compaction (`sizeBefore`),
  until the new size comes in, or for 30s at most, as a compaction stopped with Esc keeps its size.
  `module.json` lists them for tools/page.sh.

tests/rows.sh checks why each sample session's menus, Compact card and next steps would offer nothing now
(`--print-why-not`), with parts of a session's reach changed too.

## Between the page and the app

- The page sends `pick` (`{sessionId, field, x, y}`: a press on the model, effort or mode, whose menu opens there),
  `compact` (`{sessionId, focus}`: the Compact card's choice), `switchAnswer` (`{sessionId, ok, never}`: the answer to "Switch
  model?" asked on the row). The card's button past a terminal's reason sends `wayPast` (`{sessionId}`), which the core
  answers.
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
  session: the agent puts those defaults back once the command is over (`holdDefaults`/`releaseDefaults`).
- One change from the panel at a time: while a pick goes in or "Switch model?" is asked, the menus, the Compact card and
  the next steps say a change is still going in, so nothing typed meets Claude's question in the terminal.
- A switch noted for the hook is taken back once the command ends, whichever way, so the hook never allows a switch the
  panel didn't just make.
