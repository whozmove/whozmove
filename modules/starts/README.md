# Starts

New conversations started from the panel's card, in Claude Desktop or a terminal: the folder's trust checked (and
recorded once you've said yes on the card), in the project's own folder or a worktree (one that's there, or made first),
the session opened with your words, and watched for until it's listed, when the page's pending row becomes its row; and
New Conversation and ⌃⌥N in the pawn menu.

## Its pieces

- `app/StartsModule.m`: its face for the core (contracts/Module.h): the card's messages, the starts still waiting
  matched to the sessions they became, New Conversation and its shortcut, and the print modes the tests check. It adds
  Open new conversations here to each terminal's page on the panel's back, and turns the panel back to its list before
  the card opens (`appEntries`).
- `app/Starts.m`: a start, from the card to its row: in a terminal that says which tab it shows (Ghostty or iTerm2,
  the one you picked on the card's menu, kept from then on by the core, where an ended terminal session opens again
  when the one it ran in can't open it: Core's `startTerminal`), with the session id the page chose and the command its
  agent gives (AgentStarts), or in the app that keeps conversations of its own (Claude Desktop's ConversationHost). A
  terminal says once its tab has opened, which can wait on macOS asking whether Whozmove may control it: only then is
  the start the session you're on, and its wait for the session begins; a tab that can't open says why at once.
- `app/Worktrees.m`: a start's folder in a repo: what the repo has (its own folder, its worktrees, its branches with no
  folder; `git worktree list`, `git for-each-ref`), whether a worktree can be made (no branch or folder there already;
  the branch it starts from there), where a repo's worktrees go (a folder you chose, kept in worktrees.json in
  Whozmove's folder, else one beside the repo, named after it, never inside it), and making one, through your
  shell as you (RunInCheckout): `git worktree add --track -b <name> <folder>/<name> <base>` for a new branch, from the
  repo's local base branch (app/shared/Git.h's LocalBaseBranch) unless another is named, or `git worktree add
  <folder>/<branch> <branch>` for a branch that's there.
- `app/Shortcut.m`: ⌃⌥N from any app, a hot key macOS hands straight to the panel, which needs no permission.
- `page/starts.js`: the card for a new conversation, which opens under the header, the pending row a start shows as
  until it's listed, and the card turning into that row and moving down to its place; `page/starts.css`, their style,
  and the pawn's hop as a conversation starts; `page/start-words.js`, what the card reads in your words (@ for the
  project, # for where in it) and a new worktree's name (plain functions). `module.json` lists them for tools/page.sh.
- `tests/test.sh`: what sample starts would run, a terminal tab's command and Claude Desktop's link (`--print-starts`,
  `starts.expected.txt`), what a sample repo has and worktrees checked and made in it, or refused without Apple's
  developer tools (`--print-worktrees`, `worktrees.expected.txt`),
  and the page's part (`page-cases.js`, `page.expected.txt`). tests/all.sh runs it.

Folder trust is the Claude Code module's: tests/rows.sh checks how it's read and recorded (`--print-trust`).

## Between the page and the app

- The page sends `start` (`{startId, folder, app, words, sessionId, trust, target}`, `target` being `{kind: open,
  path}`, `{kind: branch, name}` or `{kind: new, name, base}`), `checkFolder` (`{folder}`), `listBranches`
  (`{folder}`), `checkWorktreeName` (`{folder, name, base}`) and `startMenu` (`{kind: app, app, worktree}`, `{kind:
  places, repo}` or `{kind: choose}`).
- The app calls `openStart(folder, app)`, `folderChecked(folder, {trusted} or {gone})`, `branchesListed(folder, {here,
  worktrees, branches, base, folder, folderPath} or {none, where})`, `worktreeNameChecked(folder, name, {path, where,
  name, base} or {why})`, `worktreesMoved(repo)`, `startAppChosen(app)`, `startUpdate(startId, {sessionId}, {note} or
  {why})`, `startProject(folder)` and `setStartOptions({terminal, desktop, choice})`: the terminal a start opens in,
  or null; whether Claude Desktop's sessions are tracked, told again as that changes (while they aren't, the card
  offers only the terminal, and with no terminal either, says there's nowhere to start it); and whether Start's menu
  has another app to pick, which its ⌄ shows only then.

## Rules

- Folder trust is recorded only for a folder you trusted on the card, by the agent, where Claude Code and Claude
  Desktop both look.
- A terminal start's words go in a file only you can read, never on the command line, and the file goes once the
  session has started.
- The panel takes the keyboard while the card is open from ⌃⌥N or New Conversation, until it starts or closes.
- A worktree is made only when you start a conversation in one from the card, with git run as you run it (your PATH,
  without agents' marks), so the repo's own hooks run as they would for you; a name that's taken, or git refusing,
  starts nothing, and none is made before Apple's developer tools are installed, as git would offer to install them
  instead. A start in a worktree that's there goes only to one of the repo's own folders, as git lists them.
- Nothing switches the branch of a folder in use: a branch is only ever checked out in a new worktree.
- Where a repo's worktrees go is kept in Whozmove's folder, never in the repo.
