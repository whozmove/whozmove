# Waiting on someone else

When a session has done its part and its next step is someone else's (a review of its pull request, an approval, a
merge), it doesn't need to sit at its prompt for you to notice, or loop on `gh` holding one of your seats. It waits
with Whozmove, and carries on by itself when that comes.

## What you see

- **While it waits,** its row says what it waits on, quietly, where its row says how things stand: **Waits on #12**.
  It holds no seat on the usage card, and its wait isn't shown as a job running in the background round its dot.
  Its last reply is yours to read once, as any reply is, and then nothing waits on you there. Anything else the row
  has to say comes first, such as a try it handed you in One Task.
- **When something comes,** it carries on by itself, with nothing typed into it:
  - an approval, a review asking for changes, a merge or a close of its pull request;
  - a comment, only when the session asked to be woken for comments too.

  Only someone GitHub says can change the repo (its owner, a member or a collaborator) wakes it, never an account
  marked as a bot, or a stranger. The session is told what came and who, and reads the rest itself, taking a
  comment's words as someone else's.
- **With your gear full,** what came waits for the next free seat, the oldest first, and the row says so, with where
  the gear is changed: **#12 approved · next free seat. Change your gear on the usage card, under the panel: press a
  seat.** With Usage Gear off, or no gear picked yet, it carries on at once.
- **If it can't be read now** (`gh` isn't signed in, or you're offline), the row says why, and what puts it right:
  **Waits on #12: gh may need you to sign in (gh auth login)**. After 30 minutes like that, the wait ends and the
  session tells you. A session with nothing of its own that someone else has to act on is told so at once, and
  doesn't wait.
- **A pull request merged or closed a moment before the wait began** carries it on too, as soon as it's read.

Its pull request is its branch's while that's open, else the newest open one it made or worked on. With Show Next
Steps off, Whozmove doesn't look up a branch's pull request, so it's the newest the session made or worked on.

## Closed while it waits

If its tab is closed, its terminal quits or the Mac restarts while it waits, its wait goes on without it.

- **Its grey row stays,** saying **Stopped, waiting on #12**, quietly, with **Resume** at its end. A terminal
  session's row stays past the 3 days an ended one usually does, for as long as it waits (30 days at most).
- **When something comes,** the row turns your move, **#12 approved**, with Resume, and the line under the header
  says so too: **#12 approved: Resume "checkout-fix"?**
- **Resume, or a press anywhere on its row,** opens it again where it ran, under the same conversation, and tells it
  to hear what came. It carries on from there: nothing it waited for is lost. Opening it only to look (Take Me There,
  say) tells it nothing; if it hasn't asked within two minutes, its row says **Not waiting on #12 any more**, with
  Resume, which types those same words in for you, when it's safe to.
- **In Claude Desktop,** Resume shows the conversation and sends it the same words, as your press. A Claude Desktop
  conversation's row stays only the 3 days it's usually listed, whether it waits or not.

## How a session waits

Any session can, in any project: Whozmove's plugin gives Claude Code's sessions a skill, `waiting`, that says when to
wait and how. The session reads where things stand once, then, as the last thing it does, runs
`ask-panel.sh wait` in the background and ends its turn. That command asks Whozmove every 10 seconds, and keeps
asking while Whozmove is away (restarting, say), so a wait never stops by itself; what came while Whozmove was away is
found as it comes back.

A wait ends when it wakes, or when the command stops while its session runs (`/clear`, or it was stopped in the
session). Opened again, it goes on in its new process once that asks (Resume's words have it ask at once). The Mac sleeping doesn't end it: what came while it slept wakes the session once it's
awake.

A bot account that has been added to the repo as a collaborator, with nothing in GitHub's answer marking it as a bot,
wakes a session as a person would.

[Back to Using Whozmove](README.md)
