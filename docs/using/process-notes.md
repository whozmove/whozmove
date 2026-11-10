# How a project works

A project says how work is done there in its own pages: its CONTRIBUTING, its CLAUDE.md or AGENTS.md, its pull request
template and its docs on reviewing and releasing. A session reads them and works by them. What those pages don't say,
the things you tell a session or it finds the hard way, Whozmove keeps beside them as a short note for the project, only
once you say so. Every worktree of the project shares it.

## Keep It

When a session learns something the pages don't say ("QA wants the staging link in each pull request", "the tests need
Docker running"), its row asks **Keep this as how acme-web works?**, with the note whole:

1. **Start Docker before npm test:** the tests need its database, and the pages don't say so. *found running the
   tests on PAY-142*
2. **Staging link:** QA wants it in each pull request's description. *you, on PAY-142*

Each step is numbered text, with where it came from after it. Nothing in the note is a choice to press: only the two
buttons under it are.

- **Keep It** keeps the note for the project, on this Mac. The card says **Keeping it…** for a moment. If it couldn't
  be saved, the card says why, with **Try Again**, and the draft keeps waiting.
- **Not Now** keeps nothing. The session works by the project's own pages. Another session's draft of the same
  changes doesn't ask you again, and a card already waiting with them goes; one with a change that wasn't there does,
  saying **You said Not Now at 17:02. This one has a change that wasn't there then.** Changed your mind? Ask the
  session to show it again.
- **To change anything,** say so in the conversation: the session drafts it again, and the new draft takes the old
  one's place on the row.

Pressed, the card takes the keys as a request does: Return is Keep It, and Esc lets the keyboard go, answering
nothing. A number key does nothing here.

## When it changes

Once a project has a note, a session that learns more drafts it again, whole. Its row asks **Keep the change to how
acme-web works?**, and says what changed against the note as kept: **Against the note kept at 17:02: 1 line added, 1
removed.** A new step says **new**, in green; one taken out is struck through and says **taken out**, in red. Keep It
keeps exactly what the card shows.

- **Two sessions on the project draft at once:** Keep It on one takes the other's card back, as it was drafted against
  the note before.
- **A session ends** while its draft waits: its card goes, and nothing is kept.
- **The same as the note kept:** no card.

## What it keeps

Each project's note is kept on this Mac, in Whozmove's folder, `process-notes/`, which only you can read: the project's
folder, the note, and when you kept it. It's written only by your Keep It. What you said Not Now to is kept only while
Whozmove runs. The note goes nowhere else, and Whozmove's log names only the project, never a word of the note. A note
with anything shaped like a key, a token or a password in it isn't shown at all: the session is told which line, to
draft it again without it. A note is checked the same way each time it's read, and a line that fails is left out.

[Back to Using Whozmove](README.md)
