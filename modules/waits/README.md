# Waits

A session whose next step is someone else's (a review of its pull request, an approval, a merge) waits for it without
holding a seat: it runs `ask-panel.sh wait` in the background and ends its turn, and its row says what it waits on,
quietly ("Waits on #12"). When something comes, and the gear has a seat for it, the wait answers and Claude Code
carries the conversation on by itself. While what came waits for a seat, the row says so ("#12 approved · next free
seat"). Nothing is typed into the session: its own background command is what carries it on.

This module never names what it waits on. It finds the sources through the core (`modulesThat:` with
app/contracts/Wake.h): the git module tells a session's pull request and what came on it. It asks each source what a
session waits on and what has come since its wait began, and never reads a source's own state.

## Its pieces

- `app/WaitsModule.m`: its face for the core (contracts/Module.h).
  - The ask: `wait` (`{now, comments}`): the first from a session's process begins its wait, from now, watched by each
    source that has something of the session's ("waiting: Waits on #12"), or says at once that there's nothing to wait
    on, or nothing that can be read now ("nothing to wait for: …"). Each after says "waiting: …" until something has
    come, then "woke: " and what came as one line of JSON, once the gear has room for it. `now` answers at once,
    "nothing yet: …" when nothing has come. `askShowing:`, as it only reads back what came, and `logsItself`, as it's
    asked every 10 seconds.
  - Each second (`tick`, which comes before every read of the rows, so it asks for no read of its own), a pass over the
    rows, once they've been read at least once: a wait ends when its row goes, or when its command hasn't asked for a
    minute of the Mac being awake while it runs (killed, or `/clear`); one whose conversation closes is kept, and
    watched, for Resume; one run again in a new process that hasn't asked within two minutes (opened only to look) is
    kept too, its row offering Resume's words, typed in by your press; each source not watching a wait yet is asked to,
    with what the wait began on, so a wait read back after a restart is watched again from when it began even before its
    source can name it; what came is asked of the sources; and which held wakes go is decided with the gear as the usage
    module keeps it (`GearFacts`), oldest wake first. One let go counts as taken until it's at work, or for 30 seconds,
    so two never go for one seat. With Usage Gear off, or no gear picked yet, every wake goes.
  - The row's `wait` (docs/reference/rows.md): what it waits on, in words and for VoiceOver, what it waits on as each
    source named it, what came, and whether that waits for a seat.
  - What's kept for a later copy: `AppDir/waits/<session>.json`, when its wait began, its process (its pid and when it
    started), whether comments wake it, and what it waits on by each source's ids, only you able to read it. Never a
    word of what came.
  - Its background waits (`BackgroundWaits`, contracts/Module.h): `wait`, with `--now` and `--comments` in each order,
    which the agent's module leaves off the row's jobs; its test runs each through ask-panel.sh.
  - Closed while it waits: the first ask from the conversation's new process carries the wait on there, from when it
    began, so `wait --now` hears what came while it was closed (a copy open beside the old process begins its own);
    its words as it's opened again from its row (`ReopenWords`, contracts/Wake.h), which Focus puts in as its first
    message, by Resume, its row's own press or anything that opens it as that does; and, once something has come, a
    notice with Resume (`notices`, contracts/Notice.h).
- `app/Waits.m`: plain functions: the row's words, what came in a few words, which held wakes go, a let-go wake's
  seat, what a wait answers (`WaitAnswer`), why one ends (`WhyWaitEnds`), how long the Mac slept between passes
  (`WaitSlept`), and the record kept and read back.
- `app/WaitsPrints.m`: `--print-wakes`, the module driven step by step with a made-up source and gear, in a throwaway
  home.
- `page/waits.js`: the waiting note, through `core.rowNotesLast`, so any other note on the row (an ask it handed you
  in One Task) shows over it; a closed one's ask line, through `core.rowNotes`, quiet until something came, then in
  your move's colour, ending in Resume, which takes no press of its own, so a press on it is its row's; as words for a full row's work line, and for VoiceOver; while held, with where the gear
  is changed, in the usage module's words (`core.gear`).
- `plugin/skills/waiting/SKILL.md`: how a session waits, collected into Whozmove's plugin as `whozmove:waiting`: when
  to wait, reading where things stand once first, the wait as the turn's last step, and a comment's words read as
  someone else's.
- `tests/test.sh`: `--print-wakes` in homes of their own, `ask-panel.sh wait` against a stand-in panel, and the page's
  cases (`page-cases.js`), compared with `wakes.expected.txt`, `asks.expected.txt` and `page.expected.txt`.
  tests/all.sh runs it.

## Between the page and the app

- The page sends `waitSay` (`{sessionId}`): your press of Resume on a row whose conversation runs again and hasn't
  asked, which types Resume's words in as Send says it's safe, or says why not on the row, with the way past it.
- A row's `wait` (docs/reference/rows.md) is all the page is told.

## Rules

- **A wait only hears what came.** It lets a session do nothing it couldn't do itself, and does nothing in its name:
  so it needs no switch. What wakes it is someone else's act (a review, a merge), told by a source.
- **Nothing is typed into a session to wake it.** The session's own background command answers, and Claude Code
  carries it on, so no key ever lands where you're typing. A closed one is carried on only by your press of its row or
  Resume, with fixed words, never anything from outside, and never by a press only to look at it.
- **A wake from someone else goes only as the gear has room,** oldest first, so the gear stays the one limit on how
  many work at once; with no gear, every one goes.
- **Every wait ends:** it wakes, its row goes, or its command stops asking while it runs. One closed while it waits is kept until Resume or its row goes (30 days at most, as its
  agent's kept record says). Its command waits through Whozmove being away for as long as it takes, as only Whozmove can wake it,
  and the Mac sleeping never ends a wait.
- **A session never waits on nothing:** with nothing of its own to wait on, or nothing that can be read now, it's
  told so at once; and a wait whose every thing has been unreadable for 30 minutes ends, so the session says so.
- **Nothing is decided before the rows have been read once:** until then every session would look gone, and every
  kept wait would end.
- **Nothing of what came is logged or kept:** panel.log says which session, how many things it waits on, that
  something came, and from which kind of source, never who or what; the kept file has only times, a process and ids.
