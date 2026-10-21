# What a row holds

Each session the panel lists reaches the page as one row, in `update(rows, now)`: a JSON object that
`app/Row.m` builds from four places. This page is the list of its fields. A field that's unknown is left out,
never sent as `null`. Times are milliseconds since 1970.

`Whozmove --print-rows` prints the rows for the home folder in `$HOME`. `tests/rows.sh` checks those against a
recorded copy, and checks that every field `app/Row.m` sends is described here, and nothing more.

Your plan's usage isn't in the rows: it's the panel's, not a session's, and reaches the page apart from them
(`setUsage`, see CONTRIBUTING.md). The second or so that the Claude Code module runs `claude` to ask for it, Claude
Code lists that run in its registry like any session; it runs in a folder kept for it, and is never a row.

## From Claude Code's registry

`~/.claude/sessions/<pid>.json`: one file per running session, written by Claude Code. A conversation can run in more
than one process at once: resumed in a second tab while it still runs, or open in Claude Desktop and a terminal. It's
still one row, whose fields here are those of the copy that needs you most: one asking you something, then one at
work, and otherwise the one the row followed already (when the row is new, the one whose state changed last, then the
one started last). One paused in its terminal (Ctrl+Z) never speaks for it while another runs.

| Field | What it is |
|---|---|
| `sessionId` | Claude Code's id for the session |
| `hostSessionId` | for a session in Claude Desktop, the conversation's own id there (`local_…`) |
| `pid` | the session's process; 0 for a closed Claude Desktop conversation |
| `procStart` | when that process started; with `pid`, it tells a process from a later one given the same pid |
| `cwd` | the folder the session runs in |
| `name` | the session's name, if it was given one |
| `entrypoint` | `cli` for a terminal, `claude-desktop` for Claude Desktop |
| `status` | `idle`, `busy` or `waiting` (asking something); `closed` for a conversation with no process |
| `statusUpdatedAt` | when the status last changed |
| `alsoOpen` | the conversation's other copies, when it runs in more than one process: each `{entrypoint, paused, busy, hostSessionId}`, `paused` for one stopped in its terminal, `busy` for one at work, and `hostSessionId` for one in Claude Desktop |

## From Claude Desktop

`~/Library/Application Support/Claude/claude-code-sessions/<account>/<org>/local_<id>.json`: one file per
conversation, running or not.

| Field | What it is |
|---|---|
| `activityAt` | when the conversation last did something: Claude's own time, or the hook's (below) when that's later |
| `lastFocusedAt` | when the conversation was last shown in Claude |

A conversation with no process, active in the last three days (or shown in Claude now), gets a row from this file
alone: `sessionId` (the terminal session's id if it was resumed in one), `hostSessionId`, `name` (its title, or
"Untitled"), `cwd`, `entrypoint` `claude-desktop`, `status` `closed`, `pid` 0, and its last activity as both
`statusUpdatedAt` and `activityAt`.

## From the hook

`~/Library/Application Support/Whozmove/sessions/<sessionId>.json`, written by the hook `whozmove-claude.py`
(modules/claude-code/plugin/hooks/).

| Field | What it is |
|---|---|
| `lastPrompt`, `lastPromptAt` | the last message sent to Claude, and when |
| `lastReply`, `lastReplyAt` | Claude's last reply, and when |
| `notice` | what Claude Code last notified about (waiting for permission, say), until the next prompt or reply |
| `activity`, `activityAt` | the live line: what Claude is doing ("Reading app.ts"), and when that step began (for a Claude Desktop conversation, Claude's own time when that's later) |
| `stageAt` | when the hook last saw a step or a turn start or end |
| `outcome`, `outcomeAt` | how far the last turn took the work (`Implemented`, `Tested`, `Committed`, `PR raised`, …), and when |
| `workSteps` | what the current piece of work has been through: `Built`, `Tested`, `Validated` |
| `builtAt` | when a build last succeeded: the panel offers Deploy for a build newer than the last deploy, in the folder the session runs in (where its commands run) |
| `audit` | the last local code review: `{found, left, settled, at}` |
| `workRoot` | the checkout the session last edited files in |
| `editedAt` | when it last edited files there: of the sessions running in a checkout, the one that edited it last speaks for it, and its row has the checkout's island. Edits in another checkout don't move a row, but that checkout's steps and Deploy wait while its agent is on a turn that has edited files there (`editedAt` after `lastPromptAt`) |
| `permissionMode` | the session's permission mode, as of its last event |

## Added by the app

| Field | What it is |
|---|---|
| `git` | the checkout the session runs in, read from its `.git`: `{branch or detached, root, worktree, worktreeOf, mainRoot}` |
| `workGit` | the same for `workRoot`, only for a session that runs outside any checkout: its row is about the one it last edited files in. A session that runs in a checkout is always about that one |
| `checkout` | that checkout's state, from `git status` and `gh`: `{changes, ahead, behind, upstream, remotes, checkedAt, pr, prBranch, prCheckedAt}` (`upstream`: the branch follows one on a remote, as `origin/main`; one that follows a local branch has none, and `ahead` and `behind` are 0 then; `pr` is null when GitHub says the branch has none, and missing until `gh` has answered), its `base` branch and `aheadOfBase` (commits the base doesn't have). For the island: `newFiles` (files git doesn't track yet), how the changed files split, `filesStaged` (all their changes staged), `filesPartly` (staged, then changed again) and `filesUnstaged` (none staged, or in conflict), and `stage`, the checkout's extra stage ([stages.md](stages.md)): `{count, label, edits}` once you've allowed its command and it has run, with `parts` (`{staged, partly, unstaged}`, how the files outside it split, as git sees them) while it holds something and names those files, or `{ask: command}` while its command waits for your answer. The file lists and the extra stage's menu stay in the app, and reach the page apart from the rows |
| `prs` | the PRs the session made or worked on, newest first: each `{url, number, repo, at}` from its transcript, and what `gh` says about it: `title, state, isDraft, author, additions, deletions, changedFiles, createdAt, checks, review` and `headRefName` (its branch, which the island matches against the session's) |
| `messageAt` | when the conversation last moved, from its transcript |
| `agent` | the details line: `{mode, model, effort, tokens, compactWindow}` |
| `ask` | a permission request waiting in the panel, as the permission hook left it: `{id, sessionId, tool, input, cwd, at, pid}`, with `truncated` when its input was cut short to show. A plan waiting for your OK is one too (`tool` is `ExitPlanMode`, its `input` has `plan` and `planFilePath`) |
| `writings` | what the session wrote for you to read, from its transcript, newest first (at most 50): each `{id, kind, title, path, at}`. `kind` is `plan` (each time Claude presented a plan for your OK, with `status`: `waiting`, `approved` or `declined`), `prototype` (an `.html` page it created, or published, with its `url`) or `notes` (a `.md` file it created). Files it only rewrote, and Claude Code's own files, aren't listed. What each says is read only when it's opened in the reader |
| `changes` | what the session itself changed in its checkout that isn't committed yet, line by line, as git status sees it: `{known, added, removed, files, parts, complete, v}`. The checkout's uncommitted change (staged or not, new files included) is read from git, and each changed line is credited to the listed session whose edits (Edit, MultiEdit and Write, from its transcript and its sub-agents' records) put it in or took it out, its shell commands' included (what Claude Code records each one changed, in auto mode); a plain or repeated line (`}`, a blank, a text there twice) goes with the lines around it. `files` are the session's, newest edit first: each `{path, added, removed, edits, at, created, saved, shared}` (`path` within the checkout; `saved`: nothing in it left unstaged; `shared`: someone else changed it too). `parts` is the checkout's uncommitted change by whose its lines are, `{who: [added, removed]}`: a session's id; `outside` (no listed session's record has it: your own, a closed session's, what git brought in); or `short` (a short or repeated line with nothing around it to tell whose it is by). `known` is false while what the session changed isn't known, as it ran a shell command Claude Code didn't record (or recorded only in part): then `added` and `removed` are the whole checkout's, and `files` and `parts` are empty. `complete`: every listed session in the checkout is known, so `outside` is no listed session's. `v` changes when any of it might have. Missing until the checkout has been counted (`added` and `removed` are 0 while the session has nothing uncommitted there), and in a checkout no listed session edited in; the lines themselves reach the page only when the changes view asks |
| `compacting` | when a `/compact` sent from the panel began |
| `focused` | `true` for the session you're on: the conversation Claude Desktop shows now, or the session in the tab Ghostty shows, whichever of the two was in front last. Claude Desktop's stays while Ghostty's tab holds none of the sessions listed, and while it can't be told which one it holds, the mark stays where it was |
| `seenAt` | when you were last looking at the session: on it for 2 seconds or more, in Claude Desktop or Ghostty in front, while at the Mac (the screen awake and unlocked, the keyboard or the mouse used in the last 5 minutes). A reply from before then counts as read. Missing until you've looked at it since the app started |
