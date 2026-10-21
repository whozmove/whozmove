# Security

Whozmove acts on your Claude Code sessions for you: it answers their permission requests, puts commands into them,
and keeps a little of what they say. A flaw in any of that matters, so please report it privately.

## Reporting a problem

Email hello@whozmove.com, or use **Report a vulnerability** on this repository's Security tab if it's there. Please
don't open a public issue, pull request or discussion about it.

Include what you can of:

- what's affected, and what someone could do with it;
- the steps that make it happen;
- the versions involved: Whozmove, macOS, Claude Code, and Claude Desktop or the terminal.

Take personal details out of anything you attach first: Whozmove's log and screenshots can show folder paths,
conversation names and text typed into sessions.

## What happens next

- You'll get a reply within a week, saying whether the problem is confirmed and what happens next.
- You'll hear how the fix is going until it's released.
- When the fix is released, you're credited for it, if you'd like to be.

Please keep the problem private until the fix is out, or for 90 days after your report, whichever comes first.

## Which versions get fixes

Only the latest release. A fix comes in the next release, so update to it.

## What counts

In scope:

- anything that lets Whozmove act on a session you didn't ask it to: answer a request, type into it, or send it a
  command;
- anything that makes Whozmove run a command you didn't allow: a deploy command you didn't confirm, or anything a
  deploy runs beyond the command you confirmed;
- anything that exposes what Whozmove keeps or reads;
- anything that weakens the permissions macOS gives Whozmove, or lets another app use them.

Out of scope:

- problems in Claude Code, Claude Desktop or a terminal app themselves: please report those to their makers;
- attacks that already need code running as you on your Mac, since such code could reach your sessions without
  Whozmove.

What Whozmove can do, what it keeps and the trade-offs it makes are in the README, under
[Privacy and security](README.md#privacy-and-security).
