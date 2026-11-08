# Attention

While Working on Whozmove ▸ Keep App Switches is ticked, Whozmove keeps on this Mac what you turn to, to measure how
much of your attention your agents take: each time an app comes to the front, saying only whether it's one Whozmove
works with (a terminal it knows, or Claude Desktop); when you go away from the Mac and come back; and when you look at
a session. Each day's lines go in a file of their own in Whozmove's folder, `attention/<day>.jsonl`, kept for two
weeks and sent nowhere. That's all it does: it shows nothing, and reads the lines back for nobody but a script of
yours.

## Its pieces

- `app/AttentionModule.m`: its face for the core (contracts/Module.h).
  - `launch` listens for an app coming to the front (NSWorkspace), whose id it asks the core about (`hostFor:`): an
    app Whozmove works with, or another one, and never which.
  - `tick` takes away the days past their two weeks, ticked or not. Ticked, it keeps each change of whether you're at
    the Mac, from the focus part's `AtTheMac()` (5 minutes with no key or pointer, or the screen locked or asleep), and
    each look at a session, from the rows' `seenAt` as the focus part marks it: a new look at once (the first, or one
    after a gap), then once a minute while you stay on it, as `seenAt` is brought up to date every second. On the tick
    after it's ticked, the looks from before are taken as kept, never written, and the record starts with the app in
    front.
  - `menuEntries` gives Keep App Switches in Working on Whozmove ▸, off until you press it (`keepAppSwitches`); a
    press says in the log that it was turned on or off, and while its last line couldn't be written, the item says
    so ("Keep App Switches: Can't Write").
  - `printModes` gives `--print-attention`.
- `app/Attention.m`: plain functions. What each line says (`AttentionFront`, `AttentionPresence`, `AttentionSeen`),
  when a look is kept (`AttentionSeenDue`), the day's file a line goes in (`AttentionFileFor`), which days have had
  their two weeks (`AttentionExpired`, by their names, never parsed back), and adding a line to its file
  (`AttentionAppend`).

`tests/test.sh` takes made-up events into a throwaway home (`--print-attention` with `events.json`, compared with
`attention.expected.txt`), and, where the run's HOME is the account's own (CI, or your own run), checks it refuses it.

## Rules

- **Never which app, never what's in it.** An app coming to the front is kept only as one Whozmove works with, or
  another; a look at a session only as its id and the time. Nothing of a window, a key you type or a page is read.
- **Only while it's ticked.** Off, nothing is kept, a look made while it was off is never written, and the days already
  kept go as they reach two weeks.
- **Only you can read it, and it goes nowhere.** The folder is 0700 and each file 0600; nothing is sent.
- **No timer of its own.** It keeps what changed on the core's tick and on macOS's own notice of an app coming to the
  front.
- **A failure is said, and once.** A line that can't be written is said in the log once a launch, not every second;
  each line after it is still tried, and the item says it can't write while its last line failed.
