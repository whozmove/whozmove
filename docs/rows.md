# What a row holds

Each session the panel lists reaches the page as one row, in `update(rows, now)`: a JSON object that
`app/Row.m` builds from four places. This page is the list of its fields. A field that's unknown is left out,
never sent as `null`. Times are milliseconds since 1970.

`Whozmove --print-rows` prints the rows for the home folder in `$HOME`. `tests/rows.sh` checks those against a
recorded copy, and checks that every field `app/Row.m` sends is described here, and nothing more.

## From Claude Code's registry

`~/.claude/sessions/<pid>.json`: one file per running session, written by Claude Code.

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

## From Claude Desktop

`~/Library/Application Support/Claude/claude-code-sessions/<account>/<org>/local_<id>.json`: one file per
conversation, running or not.

| Field | What it is |
|---|---|
| `activityAt` | when the conversation last did something. Once the hook has seen a step, its time is used instead |
| `lastFocusedAt` | when the conversation was last shown in Claude |
| `summaryStatus` | Claude's own verdict on its last turn (`blocked`, `completed`, …), only while it's about the latest reply |

A conversation with no process, active in the last three days (or shown in Claude now), gets a row from this file
alone: `sessionId` (the terminal session's id if it was resumed in one), `hostSessionId`, `name` (its title, or
"Untitled"), `cwd`, `entrypoint` `claude-desktop`, `status` `closed`, `pid` 0, and its last activity as both
`statusUpdatedAt` and `activityAt`.

## From the hook

`~/Library/Application Support/Whozmove/sessions/<sessionId>.json`, written by `hooks/whozmove-claude.py`.

| Field | What it is |
|---|---|
| `lastPrompt`, `lastPromptAt` | the last message sent to Claude, and when |
| `lastReply`, `lastReplyAt` | Claude's last reply, and when |
| `notice` | what Claude Code last notified about (waiting for permission, say), until the next prompt or reply |
| `activity`, `activityAt` | the live line: what Claude is doing ("Reading app.ts"), and when that step began |
| `stageAt` | when the hook last saw a step or a turn start or end |
| `outcome`, `outcomeAt` | how far the last turn took the work (`Implemented`, `Tested`, `Committed`, `PR raised`, …), and when |
| `workSteps` | what the current piece of work has been through: `Built`, `Tested`, `Validated` |
| `audit` | the last local code review: `{found, left, settled, at}` |
| `workRoot` | the checkout the session last edited files in |
| `permissionMode` | the session's permission mode, as of its last event |

## Added by the app

| Field | What it is |
|---|---|
| `git` | the checkout the session runs in, read from its `.git`: `{branch or detached, root, worktree, worktreeOf, mainRoot}` |
| `workGit` | the same for `workRoot`, when that's another checkout |
| `checkout` | that checkout's state, from `git status` and `gh`: `{changes, ahead, behind, upstream, remotes, checkedAt, pr, prBranch, prCheckedAt}` |
| `prs` | the PRs the session made or worked on, newest first: each `{url, number, repo, at}` from its transcript, and what `gh` says about it: `title, state, isDraft, author, additions, deletions, changedFiles, createdAt, checks, review` |
| `messageAt` | when the conversation last moved, from its transcript |
| `agent` | the details line: `{mode, model, effort, tokens, compactWindow}` |
| `ask` | a permission request waiting in the panel, as the permission hook left it: `{id, sessionId, tool, input, cwd, at, pid}`, with `truncated` when its input was cut short to show |
| `compacting` | when a `/compact` sent from the panel began |
| `focused` | `true` for the conversation Claude Desktop shows now |
