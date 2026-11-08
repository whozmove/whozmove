# The inbox

A session writes to its team's lead through the inbox, so the lead reads every message one at a time, most pressing
first, however the line that told it went. Whozmove keeps each message first, in its folder, before that line is
sent: the agent's own messages between sessions can be held in a tab for your OK, expire unread, or be dropped, and a
message kept here is read all the same. What the asks print is below, for scripts that read them; the module is
[modules/inbox](../../modules/inbox/README.md), and what you see of it is [Messages](../using/messages.md).

## Writing to the lead

```bash
ask-panel.sh message --to lead --priority question --about J12 < message.txt
```

`lead` is the session the [team file](team.md) names its team's lead, for the project the asking session runs in
(its repo's main checkout, from a worktree too), whichever session that is now: a lead that starts afresh reads what
waited for the one before. Any session in the project may write, the lead's own aside. `--priority` is how pressing
it is, one of:

- `urgent`: you're stuck, or someone waits on you;
- `question`: anything the lead must answer, such as which of two ways to take;
- `report`: a result;
- `note`: the rest.

`--about` is optional: up to 40 characters, as a job's id. The words come on stdin: up to 8,000 characters, 12 KB once
encoded, with nothing in them shaped like a key. It prints:

```
kept m-7f3a2c
ring: uds:/tmp/cc-socks/1234.sock
line: Inbox m-7f3a2c · question from Pip: Which colour for the coupon button? …
```

Send that `line:` to that `ring:` address the way your agent sends messages between sessions (with Claude Code, its
SendMessage). The line
only tells the lead a message waits: the lead reads the message itself from the inbox, so if the line is held,
expires or is dropped, nothing is lost, and it needn't be sent again. Where there's no address, the second line says
why instead:

- `Atlas isn't running: it reads this when it starts, so there's nothing to ring`;
- `no address to ring yet: …, so send the line below to Atlas by name, the way your agent sends messages between
  sessions`, while no agent on this Mac says where its sessions listen, with the `line:` after it.

It's refused, with what to do, for a project that keeps no team, or whose team no one leads now (send it by name, the
way your agent sends messages between sessions), for the lead itself, for words it can't keep, and once 50 of the
sender's messages wait unanswered.

## Reading it, as the lead

Only the session the team file names a team's lead reads or marks its inbox. Any other session asking is told the lead's
name, never its session.

- `ask-panel.sh inbox`: what waits, most pressing first (urgent, question, report, note), the oldest first within
  each, one line of JSON each without its words, or `empty`. Each is `{id, from: {session, name}, priority, about, at,
  readAt, readBy, told}`, with `about`, `readAt`, `readBy` and `told` only when there's one.
- `ask-panel.sh inbox-next`: the first of those this session hasn't read, whole, as one line of JSON, `{id, from,
  priority, about, at, text, told}`, which is then marked read by it; or `empty`. One a lead before it read and nobody
  answered counts as unread for the next.
- `ask-panel.sh inbox-answered <id> [< note]`: marks it answered by this session, with a note of up to 400 characters
  if one is piped in: "answered m-7f3a2c", or "answered m-7f3a2c already".

`at`, `readAt` and the rest are ms since 1970. `told` is what became of the line that told the lead, as the agent says
it: `{messageId, state, at}`, its state one of `arrived`, `held` (waiting in the lead's tab for your OK), `denied`
(turned down there), `expired`, `dropped`, `failed` (no session listened at the address) or `sent`; it's kept only from
the session that wrote the message.

## What's kept

`~/Library/Application Support/Whozmove/inbox/inbox.json`, which only you can read, written only by Whozmove:
`{version, messages, weeks}`. Each message is `{id, from: {session, name}, to: {lead: <the project's folder>},
priority, about, at, text, told, readAt, readBy, answeredAt, answeredBy, note}`. An answered message goes after 7 days,
one nobody answered after 14. `weeks` counts, for each team's lead and each week (from its Monday), the lines held,
expired, turned down, dropped or failed, and the plain messages to the lead that never reached it (`lost`), for
[Messages](../using/messages.md)' head; each week's counts go after 8 weeks. No message's words, what it's about or an
answer's note go into Whozmove's log: only each ask, the message's id and its priority.
