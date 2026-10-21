# Changes

What isn't committed in each listed checkout, line by line, as git status splits it, with each line credited to
whoever wrote it: the checkout's numbers on a row, and the changes view beside the list, in git status's own tabs
(Changes, Staged, and Outgoing, the commits not on GitHub yet, one by one); and a changed file opened in the editor you
chose.

## Its pieces

- `app/ChangesModule.m`: its face for the core (contracts/Module.h): each row's numbers, the view the page asks for, a
  file opened, the pawn menu's Open With, and the print mode the tests check.
- `app/Changes.m`: the counting, off the main thread: git's diffs, matched line by line with what each session edited,
  as its agent says (AgentWork's editsOf:).
- `app/Editors.m`: the editors it knows, the ones on this Mac, and the one you chose, kept.
- `page/changes.js` (the view's tabs, git's letters for each file, what its head says, and how lines are laid side
  by side: plain functions) and `page/changes-view.js` (the numbers, their card, and the reader's `changes` mode, with
  its steps).
  `page/changes.css` is the view's style, in the reader's frame (the core's panel/styles/reader.css). `module.json`
  lists them for tools/page.sh. A row's numbers are styled with the row, in the core's panel/styles/rows.css.

tests/rows.sh checks each tab on a checkout with a file staged and changed again, files git doesn't track, and a
commit not on its upstream (`--print-changes`), and tests/panel.sh the page's part.

## Between the page and the app

- The page sends `readChanges` (`{sessionId, scope}`: `unstaged`, `staged` or `outgoing`, asked for ahead as the
  numbers are pointed at), `openFile` (`{sessionId, path, line}`, with `editor` when it was just
  chosen), and the view's steps, which the git module answers: `gitStep` (`{sessionId, step}`) and `gitWays`
  (`{sessionId, x, y}`).
- The app calls `showChanges(sid, scope, view)` (the view made JSON off the main thread; `{counting: true}` while git
  hasn't finished counting the checkout's changes, which the page says while it asks again every few seconds)
  and `setEditors({choice, apps})`.

## Rules

- A changed file opens only from its checkout's changes (`fileOf:path:`), in the editor you chose and nothing else.
