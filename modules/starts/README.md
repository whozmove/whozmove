# Starts

New conversations started from the panel's card, in Claude Desktop or a terminal: the folder's trust checked (and
recorded once you've said yes on the card), the session opened with your words, and watched for until it's listed,
when the page's pending row becomes its row; and New Conversation and ⌃⌥N in the pawn menu.

## Its pieces

- `app/StartsModule.m`: its face for the core (contracts/Module.h): the card's messages, the starts still waiting
  matched to the sessions they became, New Conversation and its shortcut, and the print mode the tests check.
- `app/Starts.m`: a start, from the card to its row: in a terminal the panel types into, with the session id the page
  chose and the command its agent gives (AgentStarts), or in the app that keeps conversations of its own (Claude
  Desktop's ConversationHost).
- `app/Shortcut.m`: ⌃⌥N from any app, a hot key macOS hands straight to the panel, which needs no permission.
- `page/starts.js`: the box under the list and its card, the pending row a start shows as until it's listed, and the
  card turning into that row and rising to its place; `page/starts.css`, their style, and the pawn's hop as a
  conversation starts. `module.json` lists them for tools/page.sh.

tests/rows.sh checks what sample starts would run (`--print-starts`), and the Claude Code module's `--print-trust` how
folder trust is read and recorded.

## Between the page and the app

- The page sends `start` (`{startId, folder, app, words, sessionId, trust, stay}`), `checkFolder` (`{folder}`) and
  `startMenu` (the card's folder menu).
- The app calls `openStart(folder, app)`, `folderChecked(folder, {trusted} or {gone})`, `startUpdate(startId,
  {sessionId}, {note} or {why})`, `startProject(folder)` and `setStartOptions({terminal})`.

## Rules

- Folder trust is recorded only for a folder you trusted on the card, by the agent, where Claude Code and Claude
  Desktop both look.
- A terminal start's words go in a file only you can read, never on the command line, and the file goes once the
  session has started.
- The panel takes the keyboard while the card is open from ⌃⌥N or New Conversation, until it starts or closes.
