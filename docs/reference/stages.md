# The extra stage

A session's island shows where the work in its checkout stands: the files changed, the commits not on GitHub yet,
and GitHub. A tool that keeps changes on their way to a commit (a queue of patches, or changes waiting for review) can
add a stage of its own between the files and the commits: its count on the island, and what it holds and its own steps
in that stage's menu.

## Setting one up

Name a command for it in the repo's own git config:

```bash
git config whozmove.stage 'review stage'
```

That's the repo's local config (`.git/config`), which is never cloned or pushed, and every worktree of the repo shares
it. The command is one line of up to 1,000 plain characters: one with a line break, or with a character that doesn't
show or turns the text around, isn't run, as the card couldn't show you what would run.

The next time Whozmove reads the checkout, the row that speaks for it asks, showing the command in full:

- **Allow:** Whozmove runs it from then on.
- **Not now:** it isn't run, and you aren't asked again until the command changes.

A changed command is asked about again before it runs. In the stage's menu, **Stop This Stage** is Not now after
the fact; after Not now, the files stage's menu offers **Ask About the Extra Stage Again**. Your answers are kept in
`~/Library/Application Support/Whozmove/stages.json`, never in the repo.

## How it runs

- In the checkout's folder, through your login shell without its startup files (`zsh -f`, or
  `bash --noprofile --norc`), with the PATH your terminal has (your login shell is asked for it once; if it doesn't
  say in time, again five minutes later).
- As yours, not an agent's: the marks Claude Code puts on an agent's commands (`CLAUDECODE`,
  `CLAUDE_CODE_SESSION_ID`) are taken off.
- Each time Whozmove reads the checkout: every 20 seconds, and within 2 seconds of a session working there. Not while
  the pawn menu's **Next Steps ▸** is off.
- For 3 seconds at most (one that takes longer is left alone for a minute), printing 64KB at most, and it must exit
  with status 0. Otherwise the stage isn't shown, and what went wrong is in
  `~/Library/Application Support/Whozmove/panel.log`.

## What it prints

One JSON object:

| Field | | What it does |
|---|---|---|
| `count` | required | How many things the stage holds: a whole number from 0. The stage shows it, and is a dot at 0 |
| `label` | | The words after the count, as they should read ("1 to review", "3 to review"), up to 24 characters; without one, "pending" |
| `edits` | | How many changed files are outside this stage. While the stage holds something, the files stage shows it in place of git's own count, since some of git's changes are in this stage, and without its staged and unstaged parts unless `editFiles` names them; while it's empty (count 0), every change is outside it, and the files stage shows git's count and parts |
| `editFiles` | | Those files, each by its path from the top of the checkout, up to 1,000: all of them or none, as many as `edits` says, each one line of plain text. With them, the files stage keeps its gauge while the stage holds something: those files, split as git sees them into staged, partly and unstaged, each part listing its files, and its menu lists them too |
| `header` | | The top line of the stage's menu, up to 80 characters |
| `items` | | What the stage holds, a line each, up to 80 characters; the menu lists the first 10 and says how many more |
| `actions` | | Up to 8 steps for the menu, each `{"title", "run"}` or `{"title", "ask"}`, titles up to 40 characters. With `"in": "edits"`, a step goes in the files stage's menu instead |

A `run` step is a command of one line. It runs the way the stage's command does, for 30 seconds at most, and only
while the session's agent is idle and no other agent is working in the checkout (there, or editing files there; one
waiting on you doesn't count). The stage's menu still opens meanwhile, with its steps greyed out and the session they
wait for named. Its last line of output shows under the row, quietly when it worked, and the checkout is read again
straight after.

An `ask` step is one line of words for the session's agent, up to 300 characters: typed into its terminal, or sent in
Claude Desktop, the way the island's own steps go in, and waits as a `run` step does. Words starting with `/`, `!`
or `#` would be taken as one of Claude Code's own commands, so a step with them is left out.

Text over its length is cut, except a step's `run` and `ask`: a step whose command or words are longer than allowed is
left out, as cut short they'd no longer say what you chose. Fields of the wrong kind are left out, and so are steps
past the first 8. Control characters in text become spaces.

An example:

```json
{
  "label": "to review",
  "count": 3,
  "edits": 2,
  "editFiles": ["src/parser.c", "README.md"],
  "header": "3 to review, oldest first",
  "items": ["1  Tidy the parser", "2  Faster startup", "3  New icons"],
  "actions": [
    {"title": "Send the Oldest for Review", "run": "review send"},
    {"title": "Add These Changes", "in": "edits",
     "ask": "Add the current changes to the review queue, with a short note on what they do."}
  ]
}
```

## Safety

- Whozmove runs only a command you've allowed, and only that exact command. The steps it offers are part of what
  that command prints, so allowing it means trusting it to say what its steps run.
- It runs outside any agent's permissions, every time the checkout is read. Anything that can change the command, or
  the files it runs, can change what Whozmove runs: if agents work in the repo, keep the command, and whatever it runs,
  where they can't change it.
- The card that asks warns you when, as far as its words show, the command runs a file inside the checkout: a path
  from there (`./review`, `tools/review.py`), a script named by itself (`python3 review.py`), or a task runner that
  reads the checkout's own files (`make`, `npm run`).
