# What a row holds

Each session the panel lists reaches the page as one row, in `update(rows, now)`: a JSON object that
`app/Row.m` builds from five places. This page is the list of its fields. A field that's unknown is left out,
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
| `pid` | the session's process; 0 for a conversation with no process (a closed Claude Desktop conversation, or a terminal session that has ended) |
| `procStart` | when that process started; with `pid`, it tells a process from a later one given the same pid |
| `cwd` | the folder the session runs in |
| `name` | the session's name, if it was given one |
| `entrypoint` | `cli` for a terminal, `claude-desktop` for Claude Desktop |
| `status` | `idle`, `busy` or `waiting` (asking something); `closed` for a conversation with no process |
| `statusUpdatedAt` | when the status last changed; for a terminal session that has ended, when its conversation last moved |
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

## From Whozmove's record of terminal sessions

`~/Library/Application Support/Whozmove/conversations/<sessionId>.json`: one file per terminal session, written by the
Claude Code module while the session runs (its id, folder, name, the terminal it runs in, its process, its transcript
and when its conversation last moved; no prompts or replies), as Claude Desktop keeps one per conversation. A session
that has ended, whose conversation moved in the last three days, gets a row from this file alone, while Claude Code
still has its transcript and its folder is there, and no other row has it (Claude Desktop's own comes first): its
`sessionId`, `name`, `cwd`, `entrypoint` `cli`, `status` `closed`, `pid` 0, and when its conversation last moved as
`statusUpdatedAt`. A session whose process went on to another conversation (`/clear`, or `/resume` of another) isn't
kept.

| Field | What it is |
|---|---|
| `opensIn` | the terminal a press on its row opens it again in, carrying the conversation on under the same id: the one it ran in while that's on the Mac and Whozmove can open a tab there, else the one New Conversation starts in, else macOS's Terminal |

## From the hook

`~/Library/Application Support/Whozmove/sessions/<sessionId>.json`, written by the hook `whozmove-claude.py`
(modules/claude-code/plugin/hooks/).

| Field | What it is |
|---|---|
| `lastPrompt`, `lastPromptAt` | the last message sent to Claude, and when |
| `lastReply`, `lastReplyAt` | Claude's last reply, and when |
| `notice` | what Claude Code last notified about (waiting for permission, say), until the next prompt or reply |
| `activity`, `activityAt` | the live line: what Claude is doing ("Reading app.ts"), and when that step began (for a Claude Desktop conversation, Claude's own time when that's later) |
| `stageAt` | when the hook last saw a step, a turn or a compaction start or end |
| `outcome`, `outcomeAt` | how far the last turn took the work (`Implemented`, `Tested`, `Committed`, `PR raised`, …), and when |
| `workSteps` | what the current piece of work has been through: `Built`, `Tested`, `Validated` |
| `builtAt` | when a build last succeeded: the panel offers Deploy for a build newer than the last deploy, in the folder the session runs in (where its commands run) |
| `audit` | the last local code review, from its report (Claude Code's ReportFindings tool), and again from its report of what became of each finding: `{found, left, settled, at, branch}`, `branch` the one checked out where the session ran it (for a detached HEAD, its commit's first 7 characters). The work line's start says how it went while there's work to go on that branch: one with nothing left to fix until the checkout is edited again, any other until it's edited after a commit made since the review last reported |
| `workRoot` | the checkout the session last edited files in |
| `editedAt` | when it last edited files there: of the sessions running in a checkout, the one that edited it last speaks for it, and its row has the checkout's numbers and next steps. Edits in another checkout don't move a row, but that checkout's steps and Deploy wait while its agent is on a turn that has edited files there (`editedAt` after `lastPromptAt`) |
| `permissionMode` | the session's permission mode, as of its last event |

## Added by the app

| Field | What it is |
|---|---|
| `git` | the checkout the session runs in, read from its `.git`: `{branch or detached, root, worktree, worktreeOf, mainRoot}` |
| `workGit` | the same for `workRoot`, only for a session that runs outside any checkout: its row is about the one it last edited files in. A session that runs in a checkout is always about that one |
| `checkout` | that checkout's state, from `git status` and `gh`: `{changes, ahead, behind, upstream, remotes, checkedAt, pr, prBranch, prCheckedAt}` (`upstream`: the branch follows one on a remote, as `origin/main`; one that follows a local branch has none, and `ahead` and `behind` are 0 then; `pr` is null when GitHub says the branch has none, and missing until `gh` has answered), its `base` branch and `aheadOfBase` (commits the base doesn't have), and `headAt`, when its last commit was made (git's commit time, in seconds). For the next steps: `newFiles` (files git doesn't track yet), and how the changed files split, `filesStaged` (all their changes staged), `filesPartly` (staged, then changed again) and `filesUnstaged` (none staged, or in conflict), which say whether a commit takes only what's staged |
| `prs` | the PRs the session made or worked on, newest first: each `{url, number, repo, at}` from its transcript, and what `gh` says about it: `title, state, isDraft, author, additions, deletions, changedFiles, createdAt, checks, review` and `headRefName` (its branch, which the next steps match against the session's) |
| `messageAt` | when the conversation last moved, from its transcript |
| `agent` | how its agent is set up, at the start of the bottom line: `{mode, model, effort, tokens, compactWindow}` |
| `ask` | a permission request waiting in the panel, as the permission hook left it: `{id, sessionId, tool, input, cwd, at, pid}`, with `truncated` when its input was cut short to show. A plan waiting for your OK is one too (`tool` is `ExitPlanMode`, its `input` has `plan` and `planFilePath`) |
| `writings` | what the session wrote for you to read, from its transcript, newest first (at most 50): each `{id, kind, title, path, at}`. `kind` is `plan` (each time Claude presented a plan for your OK, with `status`: `waiting`, `approved` or `declined`), `prototype` (an `.html` page it created, or published, with its `url`) or `notes` (a `.md` file it created). Files it only rewrote, and Claude Code's own files, aren't listed. What each says is read only when it's opened in the reader |
| `changes` | what isn't committed in the session's checkout, as git status sees it, and the session's own share of it: `{all, known, added, removed, files, parts, complete, v}`. `all` is the checkout's, as git counts it, which the row's numbers show: `{added, removed, files, unstaged: {files, added, removed}, staged: {files, added, removed}}`, every change since the last commit (each file once, new files included), then what `git diff` shows plus the files git doesn't track yet, and what `git diff --cached` shows (a file staged and changed again is in both). The rest is the session's share: the checkout's uncommitted change is read from git, and each changed line is credited to the listed session whose edits (Edit, MultiEdit and Write, from its transcript and its sub-agents' records) put it in or took it out, its shell commands' included (what Claude Code records each one changed, in auto mode); a plain or repeated line (`}`, a blank, a text there twice) goes with the lines around it. `files` are the session's, newest edit first: each `{path, added, removed, edits, at, created, saved, shared}` (`path` within the checkout; `saved`: nothing in it left unstaged; `shared`: someone else changed it too). `parts` is the checkout's uncommitted change by whose its lines are, `{who: [added, removed]}`: a session's id; `outside` (no listed session's record has it: your own, a closed session's, what git brought in); or `short` (a short or repeated line with nothing around it to tell whose it is by). `known` is false while what the session changed isn't known, as it ran a shell command Claude Code didn't record (or recorded only in part): then `added` and `removed` are the whole checkout's, and `files` and `parts` are empty. `complete`: every listed session in the checkout is known, so `outside` is no listed session's. `v` changes when any of it might have. Missing until the checkout has been counted, and while its last `git status` found nothing to commit (`added` and `removed` are 0 while the session has nothing uncommitted there); the lines themselves reach the page only when the changes view asks |
| `compacting` | when the compaction under way began: one sent from the panel, or, while the session runs, any the hook saw start in the last 15 minutes, by itself or asked for, and not end (its record's `compactingAt`, null once it has ended: its end, which `compactedAt` keeps, or Claude's own next step, your message, the turn ending or Claude waiting for you, a second or more after it began). One that began before the panel's own `/compact` had its result was that one, and has ended |
| `noCompact` | `true` when a `/compact` from the panel certainly couldn't go in now, as far as is known without asking its terminal: it has ended, runs in no terminal the panel can type into, is open twice, or a change from the panel is still going into it (`goingIn`, `switchAsk`). The ring doesn't say "Compact now" then |
| `switchAsk` | "Switch model?" asked on the row, `{from, to, tokens, never}`: the model it leaves and the one it switches to, how many tokens the conversation holds (or null), and whether Don't ask again is offered. Before `/model` goes to a Claude Desktop conversation whose cache is warm, once Claude's own box asks it there, or while a terminal session's hook (Claude Code's PreModelSwitch) waits for the answer, which then goes to the hook. Gone once it's answered, or the hook stops waiting |
| `goingIn` | a pick from the panel on its way into a terminal session, `{field, value, inTerminal}`, from the moment it's typed until its result: `inTerminal` once no result has come for it (in 2 seconds, or 10 for a model switch the session's hooks ask about in the panel), or once the panel's own "Switch model?" went unanswered and the hook stopped waiting, as Claude Code is asking about it in the terminal (its "Change effort level?", say). Missing while the panel itself asks "Switch model?" (`switchAsk`), once the command has its result or is given up on, and on a row whose session has ended |
| `focused` | `true` for the session you're on: the conversation Claude Desktop shows now, or the session in the tab a terminal shows (Ghostty or iTerm2), whichever was in front last. Claude Desktop's stays while the terminal's tab holds none of the sessions listed, and while it can't be told which one it holds, the mark stays where it was |
| `seenAt` | when you were last looking at the session: on it for 2 seconds or more, in Claude Desktop, Ghostty or iTerm2 in front, while at the Mac (the screen awake and unlocked, the keyboard or the mouse used in the last 5 minutes). A reply from before then counts as read. Missing until you've looked at it since the app started |
