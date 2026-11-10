---
name: handing-tasks
description: How to hand the user a task in One Task, beside the panel's list, with ask-panel.sh task, how to read their answer, and how to take a task back the moment you no longer need it. Use it whenever you need the user to try something, pick between options, approve a plan, run a command only they can run, or look at something, and you'd otherwise wait for them in the chat.
---

# Handing the user a task

One Task shows the user one task at a time, beside their sessions: what it is, why, and buttons to answer. Hand it
something only they can do or decide. They answer between other work, so keep it short and plain.

## Sending one

Run `${CLAUDE_PLUGIN_ROOT}/scripts/ask-panel.sh task` with the task as JSON on stdin:

```json
{"id": "passkeys-try", "kind": "try", "title": "Try passkey sign-in", "why": "The sheet should come up on a phone.",
 "todo": ["Open the preview on your phone", "Sign in with a passkey"], "lookFor": "You land on your orders."}
```

- `kind` is one of `try`, `pick`, `approve`, `answer`, `run`, `do` or `seen`; `title` at most 80 characters; `why`
  one line, at most 160.
- A question, yes or no among them, is an `answer`, its choices each `{id, label}`. A `pick` is only for looks to
  choose between, its choices named `A`, `B`, `C`.
- An `approve` about a plan in a file may carry that plan's own "## At a glance" block as `glance`, its heading and
  line breaks kept, at most 2000 characters, in place of `points` or `phases`; attach the whole plan as a file too.
  One Task shows it as the plan's short view. Never send one for your own plan waiting for approval in plan mode,
  which shows on your row.
- A file you attach (`{"kind": "file", "label", "path"}`) opens in the user's reader only if you wrote it in this
  session, as a plan or a notes file; a team's lead may also attach one its members or the sessions it follows wrote.
  Any other shows without Open.
- A team's lead may name the session a task is about, by its session id (`"about": "<id>"`): one it leads or
  follows. One Task then offers Take Me There to it, so one press takes the user to that session's tab.
- It says `sent: <id>`, or `refused:` and why. Put that right and send it again.
- Send it again under the same `id` with something new, and it's that task's next step, in the same place.
- Your task's place in One Task is Whozmove's: by the priority of the ticket your session works on, in your tracker's
  own order, first come first served. Don't put a priority in the task: it's left out.
- The whole shape, and every field, is in Whozmove's docs/reference/task.md.

## Reading the answer

`${CLAUDE_PLUGIN_ROOT}/scripts/ask-panel.sh task-answer <id> --wait` waits until the user answers, then prints
`answered:` and the answer as JSON. Act on it. Whatever the user says in words, that it doesn't work or what
should change, comes as `Comment` with the words as its `note`, an answer like the others: so add no choice for
words of your own. Act on the comment, and if you still need the user, send the task again as its next step.

## Taking it back

**Take a task back the moment you no longer need its answer**, wherever it waits in the user's line: they answered
it another way (in your chat, say), or the work it's for was parked or dropped. A task left waiting that nobody needs
is the user's time spent for nothing.

```
${CLAUDE_PLUGIN_ROOT}/scripts/ask-panel.sh task-withdraw <id> answered|parked|dropped
```

It says `taken back`. The user sees why, in a quiet line, and the task leaves their line as soon as they aren't on
it.

## When they ask you about it

The user can ask you about a task from under it in One Task. Your words come in as a message that starts "About your
task …". Answer in at most 600 characters of plain words, as they read it between other work (One Task shows all of
it), and put a command or code in a fenced block, never in a sentence: One Task shows each block on a line of its
own, with Copy.
