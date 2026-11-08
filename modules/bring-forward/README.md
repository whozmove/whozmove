# Bring Forward

Holding two keys, Fn + Option until you pick others, brings a session you pick in Settings ▸ Bring Forward forward from
any app, as a press on its row does: its terminal tab in Ghostty or iTerm2, or its conversation in Claude Desktop.
That's all it does. Then speak with your dictation app's own keys, and your words go into the session, as into any app
in front. Whozmove only looks at its keys, so they still reach every app. The Chief is among the sessions while a
session is leading a team for you (the team module's `team` on its row), and the pick follows whichever session that is.

## Its pieces

- `app/BringForwardModule.m`: its face for the core (contracts/Module.h).
  - `launch` starts the looks at the keys, 20 a second, only while a session is picked, and pauses them while the
    screens sleep or another user's session is on them.
  - The sessions that can be picked (running in a terminal the panel types into, or Claude Desktop's own conversations,
    `isOwnId:`) and the lead are found among the rows only when asked: as the keys count, or as Settings is drawn, never
    on each read.
  - `settingEntries` gives the Bring Forward page: the session, and the keys.
  - As the keys count, it opens the session through `core.focus`'s `open:`, as a press on its row does. When there's
    nothing to bring forward, a beep, and the row's note says why; `printModes` gives `--print-held-keys`.
  - `notices` (contracts/Notice.h) says for a minute on the line under the header what has no row to say it on: a hold
    of the keys with no session leading a team, or with the session picked no longer listed. Each answers the hold
    (`answersYou`), so it's said at night too, in quiet hours.
- `app/HeldKeys.m`: plain functions. A hold of the keys told apart (`HoldLooked`), from which modifier keys are down
  and how many keys macOS has counted pressed, neither of which needs a permission; and whether you're on the Mac's
  screen, unlocked (`OnTheScreen`).
- `module.json` gives its place among the modules; it has nothing on the page.

`tests/test.sh` checks the holds for each pair of keys (`--print-held-keys`, compared with `held-keys.expected.txt`),
without bringing anything forward.

## Rules

- **Only which modifier keys are down, and how many keys have been pressed, never which.** It sees no key you type,
  and holds up, changes or posts none, so the keys reach every app as they would without Whozmove.
- **It only brings the session forward,** as a press on its row does: it types nothing, presses nothing in it, and
  starts or stops no other app.
- **A hold counts only with no other key pressed,** for a quarter of a second, so a shortcut typed with the keys
  (⌥fn⌫) brings nothing forward.
- **A hold that brings nothing forward says why:** a beep at once, and the row's note, or the line under the header
  when there's no row.
- **Nothing runs while Bring Forward is Off.**
