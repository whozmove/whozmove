# Changes

What each session changed that isn't committed yet, line by line, as git sees it, with each line credited to whoever
wrote it: a row's own numbers, and the changes view beside the list, of a session's own changes, the whole branch's,
or its commits not on GitHub yet; and a changed file opened in the editor you chose.

## Its pieces

- `app/ChangesModule.m`: its face for the core (contracts/Module.h): each row's numbers, the view the page asks for, a
  file opened, the pawn menu's Open With, and the print mode the tests check.
- `app/Changes.m`: the counting, off the main thread: git's diffs, matched line by line with what each session edited,
  as its agent says (AgentWork's editsOf:).
- `app/Editors.m`: the editors it knows, the ones on this Mac, and the one you chose, kept.
- `page/changes.js` (a session's numbers, their card's parts of the branch, how the view groups files and lays lines
  side by side: plain functions) and `page/changes-view.js` (the numbers, their card, and the reader's `changes` mode).
  `page/changes.css` is the view's style, in the reader's frame (the core's panel/styles/reader.css). `module.json`
  lists them for tools/page.sh. A row's numbers are styled with the row, in the core's panel/styles/rows.css.

tests/rows.sh checks the view for two sessions sharing a checkout (`--print-changes`), and tests/panel.sh the page's
part.

## Between the page and the app

- The page sends `readChanges` (`{sessionId, scope}`: `session`, `branch` or `commits`, asked for ahead as the numbers
  or the commits stage are pointed at) and `openFile` (`{sessionId, path, line}`, with `editor` when it was just
  chosen).
- The app calls `showChanges(sid, scope, view)` (the view made JSON off the main thread) and `setEditors({choice,
  apps})`.

## Rules

- A changed file opens only from its checkout's changes (`fileOf:path:`), in the editor you chose and nothing else.
