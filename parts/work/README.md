# Work

Who's at work in a checkout, and what waits for them: the next steps and Deploy both wait while an agent works where
they'd act, so they never act on files half-way through a change.

## What it owns

- `app/Work.h`, `app/Work.m`: `AgentAtWork` (a row's agent working, asking or compacting), `BackgroundAtWork` (its
  agent's jobs in the background that can change files, as its row's `background` marks them: its agents, say),
  `SessionWorking` (a session working now: busy and not asking you, compacting, busy in a copy, or with agents
  at work in the background), `OthersAtWork` (the other sessions at work in the folder a row's steps act on, their agents in the background
  among them) and `WhyStepsWait` (why the steps, or Deploy, wait now, in the words the row says it: for what runs in
  the background, the one it waits for, or how many, and `/tasks` in the session to stop one). Plain functions.
- `part.json`: who it talks to, and what it provides.

## Who it talks to

It talks only to the core (the rows, `Row`). The git module's next steps, the deploy module, storage, the usage
module (counting the sessions working), the board (who's working in Up next, by the same rule) and the commands and
compact-at-breaks modules (whether a session is at work, or runs something in the background, before compacting it)
import its header, and the print runs (main.m).

## Rules

- **A step never runs while the row's agent works or asks, or another session's agent works in the same folder.**
- **Agents left at work in the background count as working,** though their session takes your messages: they edit
  files there. A shell command left running (a dev server) doesn't: it may run all day.
- **One waiting on you doesn't count:** it changes nothing until you answer it, which may be days away.
- What waits stays on the row meanwhile, dimmed, and says why: only what it would do waits.
