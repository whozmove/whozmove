# Commands

A session's model, effort and permission mode changed from its row, and a session compacted from its Compact card: the
menu opened where you pressed, the pick written as the slash command you'd type (in the words of the agent that runs
the session) and put in through the app the session runs in, and its result watched for, so the row shows the pick at
once and takes it back if it doesn't go through.

## Its pieces

- `app/CommandsModule.m`: its face for the core (contracts/Module.h): the page's `pick`, `compact` and `switchAnswer`,
  its part of each row (a pick the session hasn't confirmed yet, which its details show, and a compaction under way),
  and its print mode.
- `app/Commands.m`: the menus and the Compact card, from the press to the result. A terminal session gets the pick
  typed into its tab (a mode by Shift+Tab presses, as many as its agent says take it there for certain); a Claude
  Desktop conversation gets it written in its message box, where the only mode a command can set is Plan, and "Switch
  model?" is asked in the panel first when Claude would ask it. Why a menu or the card offers nothing now is worded by
  plain functions (`WhyNoPick`, `WhyNoCompact`), from the session's reach (the core's `Send`).
- `app/Command.m`: one slash command, from going in to its end.
- `page/commands.js`: the model, effort and mode labels at the start of a row's bottom line, the context ring and the
  Compact card.
  `module.json` lists it for tools/page.sh.

tests/rows.sh checks why each sample session's menus, Compact card and next steps would offer nothing now
(`--print-why-not`), with parts of a session's reach changed too.

## Between the page and the app

- The page sends `pick` (`{sessionId, field, x, y}`: a press on the model, effort or mode, whose menu opens there),
  `compact` (`{sessionId, focus}`: the Compact card's choice) and `switchAnswer` (`{sessionId, ok, never}`: the answer
  to "Switch model?" asked in the panel).
- The app calls `compactNote(sid, text)` when a compaction from the card didn't go through, or says why it can't.

## Rules

- A pick goes in only while the session sits idle (in a terminal, at its prompt with no request waiting), checked again
  right before any key goes in, and a mode only where the Shift+Tab count is the same in every cycle the session could
  have: a key too many would land it in another mode, and none is risked where the cycle passes through Bypass.
- `/model` and `/effort` also save the pick as the default for new sessions, and a pick in the panel is for one
  session: the agent puts those defaults back once the command is over (`holdDefaults`/`releaseDefaults`).
