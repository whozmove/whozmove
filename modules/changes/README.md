# Changes

What isn't committed in each listed checkout, line by line, as git status splits it, with each line credited to
whoever wrote it: the checkout's numbers on a row, and the changes view beside the list, in git status's own tabs
(Changes, Staged, and Outgoing, the commits not on GitHub yet, one by one); and a changed file opened in the editor you
chose.

## Its pieces

- `app/ChangesModule.m`: its face for the core (contracts/Module.h): each row's numbers, the view the page asks for, a
  file opened, Open Files With in Settings, and the print modes the tests check.
- `app/Changes.m`: the counting, off the main thread: git's diffs, matched line by line with what each session edited,
  as its agent says (AgentWork's editsOf:). A checkout is looked at again every 3s at most, once something in it has
  changed (`CheckoutWatch`, in app/shared), or a session's edits there have, and those changes have settled: 2s after
  the latest, or 10s after the first while an agent keeps writing (`CheckoutSettled`, `ChangesCountDue`); and the
  commits not on GitHub once its HEAD or refs have moved, each commit's diff read once while it's listed.
- `app/Editors.m`: the editors it knows, the ones on this Mac (asked again every half minute), the one you chose,
  kept, and with none on this Mac, the one to get. Other modules open a file at a line in it through the module's
  `FilesAtLines` (contracts/Module.h), as Keys does; which files they open is theirs to check, as which of its changes
  open here is this module's.
- `page/changes.js` (the view's tabs, git's letters for each file, what its head says, and how lines are laid side by
  side: plain functions) and `page/changes-view.js` (the numbers, their details, and the reader's `changes` mode, with its
  steps). `page/changes.css` is the view's style, in the reader's frame (the pane part's, parts/pane/page/reader.css).
  `module.json` lists them for tools/page.sh. A row's numbers are styled with the row, in the row
  part's parts/row/page/rows.css.

tests/rows.sh checks each tab on a checkout with a file staged and changed again, files git doesn't track, and a
commit not on its upstream (`--print-changes`), and tests/panel.sh the page's part. Its own `tests/test.sh` checks when
a checkout's changes are due a count for sample states (`--print-count-due`, `ChangesCountDue`, compared with
`count-due.expected.txt`).

## Between the page and the app

- The page sends `readChanges` (`{sessionId, scope}`: `unstaged`, `staged` or `outgoing`, asked for ahead as the
  numbers are pointed at), `openFile` (`{sessionId, path, line}`, with `editor` when it was just
  chosen), `getEditor` (the picker's Get button, with no editor on this Mac: the download page of the one it names),
  and the view's steps, which the git module answers: `gitStep` (`{sessionId, step}`) and `gitWays`
  (`{sessionId, x, y}`).
- The app calls `showChanges(sid, scope, view)` (the view made JSON off the main thread; `{counting: true}` while git
  hasn't finished counting the checkout's changes, which the page says while it asks again every few seconds)
  and `setEditors({choice, apps, get})`, `get` naming the editor to get while none is on this Mac.

## Rules

- The changes view shows git's own stages and no others (Changes, Staged and Outgoing): you come to it knowing git,
  so nothing in it is a step git doesn't have.
- A changed file opens only from its checkout's changes. `openFile` names a file by its path within the session's
  checkout, and the app opens it only if that checkout's changes list it (`Changes`' `fileOf:path:`), in the editor
  you chose and nothing else.
- A line is said to be a session's only when its agent's records say so. A session counts as known only while every
  change it made was recorded, its shell commands' included (Claude Code records those only in some modes:
  `SessionKnown`); one that isn't has its row show the whole checkout's numbers, with nothing called its own. While
  any session in a checkout isn't known, or one of its shell commands failed, no line there is said to be no listed
  session's (`allInDoubt`). Nothing is guessed from when commands ran, which would credit the wrong session.
