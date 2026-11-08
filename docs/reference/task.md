# A task's shape

What a session sends to hand you a task (`ask-panel.sh task < task.json`, from inside the session). Whozmove checks
it as it comes in (`app/contracts/Task.h`) and keeps it in one shape whatever the project: the kind decides what you're
asked to do, so a sender never names its buttons.

```json
{
  "id": "passkeys",
  "kind": "try",
  "title": "Passkey sign-in",
  "step": { "n": 1, "of": 3, "name": "Sign up with a passkey" },
  "why": "Deployed to the preview. Sign-in now offers a passkey before the password.",
  "todo": ["Open the preview on your phone", "Make an account, and save the passkey with Face ID"],
  "lookFor": "You land on your orders, signed in, with no password asked.",
  "attach": [{ "kind": "link", "label": "storefront preview #412", "url": "https://preview-412.storefront.example" }]
}
```

A plan to approve, cut short to its points:

```json
{
  "id": "apple-pay-plan",
  "kind": "approve",
  "title": "Apple Pay at checkout",
  "why": "The plan for it, waiting for your yes.",
  "points": ["Apple Pay above the card form, on Safari and iPhone only", "Behind the payments flag, off at first",
             "Not in it: Google Pay and saved cards"],
  "attach": [{ "kind": "file", "label": "The whole plan", "path": "/Users/you/code/storefront/plans/apple-pay.md" }]
}
```

| Field | What it is |
|---|---|
| `id` | needed: the sender's own name for it, letters, digits, `.`, `_` or `-`, 64 at most. Sent again with the same id, it's the task's next step, and its title stays |
| `kind` | needed: `try` (a change to try, step by step), `pick` (choices from a prototype), `approve` (a plan, a merge, a commit, a proposal), `answer` (a question), `run` (a command only you can run), `do` (something by hand) or `seen` (news with nothing to answer) |
| `title` | needed: a few words, 80 characters at most |
| `why` | needed: why it's asking, one line of 160 characters at most |
| `step` | `{n, of, name}`: step `n` of `of` (up to 20), and the step's own name |
| `todo` | up to 6 steps to tick, each a line |
| `command` | `{run, where}`: one line only you can run (400 characters at most), and the folder to run it in, as a full path. A `run` needs it |
| `choices` | 2 to 6, each `{id, label, detail, recommended}`, the id 16 characters at most. A `pick` or an `answer` needs them; `several: true` on an `answer` lets more than one be picked. A `pick`'s choices are its looks, each named by a letter, `A` to `Z`, as two can be mixed (`A+C`); a question with words for its choices, such as yes or no, is an `answer` |
| `points` | a plan or proposal cut short: 2 to 12 lines, 90 characters each; a line starting "Not in it:" says what it leaves out |
| `phases` | or its phases: 2 to 8, each `{name, lines}`, its name (40 characters at most) and 1 to 3 lines of 60 on what it does; never both points and phases |
| `glance` | or, for an `approve` about a plan in a file, the plan's own "## At a glance" block as written, with or without its heading, its line breaks kept: 2000 characters at most, never with points or phases. One Task shows it as the plan's short view ([Plans at a glance](../using/plans.md)); attach the whole plan too. Never for your own plan waiting in plan mode, which shows on your row |
| `changed` | for a try, what changed, one line of 120 characters at most |
| `lookFor` | for a try, what to look for, one line of 120 characters at most |
| `attach` | up to 6, each `{kind, label}` and its `url` (a `page` or a `link`, `https://` only: any other is left out, and the attachment shows without Open), `path` (a `file`, a full path; links and paths 400 characters at most; or an `image`, a picture you took, as a full path to a `.png`, `.jpg`, `.gif` or `.heic`, 4 at most, shown only when its path, followed through any link or `..`, lies inside your session's folder or its writings, with `choice` naming the choice it's the picture of, for designs side by side), `added` and `removed` (a `diff`); or a `commit` |
| `inTab` | `true` when it also waits in its own tab, so you can go there |
| `about` | from a team's lead, the session the task is about, by its session id: one the lead leads or follows ([team.md](team.md)). One Task then offers **Take Me There** to it, named as the list names it; for a `do`, it's the first thing to press. From any other session it's left unused |

A `file` opens in One Task's reader only when it's one of the writings of the session that sent the task (what it
wrote for the user to read: a plan, a notes file, a prototype; rows.md's `writings`), or of the member a lead's pick
is for. A team's lead may also attach one its members or the sessions it follows wrote, and One Task names that
session on its line. Any other file shows without Open, saying why.

Text has no control or invisible characters, and a task never holds anything shaped like a key, a token or a private
key (an API key, a GitHub, GitLab, Slack, npm or Hugging Face token, an AWS, Stripe, Google or SendGrid key, a Google
client secret, a bearer token): one that does is refused, as the panel shows it. Fields it doesn't know are left out.
A task is 12 KB at most as it's sent, which a task of plain text within these limits always fits.

The order in One Task is Whozmove's, the same for every session: tasks whose session is waiting on the answer
(running `task-answer --wait`) first, then the rest, the longest waiting first. A task can't ask to come first. One
Task holds only tasks: a session's own request for the user's OK, its question or its plan stays on its row in the
list, answered there.

A team's lead hands you a task for one of its members with `ask-panel.sh task --pick-for <member> < task.json`, the
member named by its session id or its name in the team: checked as every task is, and answered at once, `sent`, or
`refused:` and why (this session leads no team; Wren isn't on your team; two on your team are called Wren, so use its
session id; or what the check found). The member it names is the pick's, from then on. One Task shows the pick once
the lead's team file names it in its `queue` ([team.md](team.md)), in the queue's order, after anything urgent;
`task-answer` says it waits unseen until then, and that an id the queue names was never sent.

One Task shows a lead's pick after anything urgent. Its answers are the lead's, read with
`ask-panel.sh task-answer <id>` from the lead's session, and a pick that doesn't pass the check is refused there, with
why. Each pick waits until the user answers it, whatever the lead names next: naming another, or none, never
takes one away unanswered. Named again under its id with new words, it changes in place, and One Task says the lead
updated it. A pick never shares an id with one of the lead's own tasks waiting: it isn't shown until the lead names it
another, and the lead's own can't be sent under the id of its pick.

## When the user asks about it

Under a task, the user can ask the session it's about what it means or what to press. Their words come into that
session as a message of theirs, once it's idle at its prompt, after words naming the task:

```
About your task “Search as you type” (step 2 of 3, On a phone): Where's the search box on a phone?
```

For a team lead's pick sent to the member it's for, they name the lead and the step, never the lead's own words:
`About the task Atlas gave me on your work (step 2 of 3): …`. The lead's name is used only when it's short and plain
(24 characters at most, of letters, digits, spaces and hyphens); otherwise they say "your lead". The message is 600 characters at most, with those
words. Answer it in your reply, short and plain, in 600 characters of prose at most too, as the user reads it between
other work: One Task shows all of it under their words (up to 16,384 characters, where Whozmove stops reading a
reply). Put a command or code in a fence (```), never inline: One Task shows each fence whole behind one line, with
Copy, and doesn't count it toward the 600.

## What comes back

`ask-panel.sh task` says `sent: <id>`, or `refused:` and why. Up to 100 of a session's tasks may wait at once: not a
limit anyone meets, only a ceiling so a script that sends in a loop can't fill the user's line. Nothing waiting is ever
dropped to make room: the one past it is refused, saying why, and one sent again under its id is its next step, at the
ceiling too. While the user has One Task off (its page under Tools, which Settings ▸ One Task opens), both asks are
refused, saying so, and a wait ends.

**Take a task back the moment you no longer need its answer**, wherever it waits in the user's line: the user
answered it another way (in your session, say), or the work it's for was parked or dropped. A task left waiting that
nobody needs is the user's time spent for nothing.

`ask-panel.sh task-withdraw <id> answered|parked|dropped` takes back a task your session sent, or a lead's pick: its
answer came elsewhere (in your session, say), or its job was parked or dropped. It says `taken back`, or `gone` when
no task of that id waits. The task leaves the user's line as soon as they aren't on it (pointing at it or typing in
it), and One Task says why in a quiet line ("Taken back: answered in Atlas's session"); named again unchanged, it stays
gone, and sent again with something new, it's back as its next step.

`ask-panel.sh task-answer <id>` says one of:
- `answered: {"id", "step", "answer", "note", "at"}`: the button's word or the choice, what you typed with it, and when;
- `waiting`;
- `can't now`: you put it at the back of your line;
- `refused:` and why, for a team's lead asking about its pick, when the pick didn't pass the check;
- `gone`: no task of that id waits: it was never sent, it went with the session's process or conversation, or you
  took it back (then it says so, and why). Send it again if it's still needed;
- `starting`: Whozmove is starting up or closing, and can't tell yet which session asks.

The answer is one of its kind's:

| Kind | `answer` |
|---|---|
| `try` | `Works` |
| `pick` | the choice's id, two ids joined with `+` to mix them (`A+C`), or `More Options` |
| `approve` | `Approve` |
| `answer` | the choice's id, or with `several`, the ids picked joined with `,` |
| `run` | `Done` |
| `do` | `Done`; Can't Now puts it at the back of the line, and task-answer says `can't now` |
| `seen` | `Seen` |

Anything the user says in words comes as `Comment`, the last choice of every task, with the words as its `note`:
"it doesn't work" for a try, what should change in a plan, what a run said, what the next looks should try. So a
task needs no choice of its own for words, and its `note` is empty but for a comment. A comment answers the task as
any choice does: it leaves the user's line, and if you still need them, send it again as its next step. An answer
is only ever to the task as it was last sent when the user saw it: send it again, and an answer to what was there
before isn't taken.

With `--wait` it asks every 10 seconds until it's answered, gone or refused, and waits through a restart of
Whozmove, stopping once it hasn't been able to reach Whozmove for 10 minutes. So a session can run it in the
background and hear when you've answered.

A session's tasks are its own: no session sees or answers another's, and they go once the process that sent them
ends, or the session's row goes (a /clear starts another conversation in the same process). Whozmove keeps them,
and your answers, in `AppDir/one-task/<session>/record.json`.
