# Compact at Breaks

With Settings ▸ Compact at Breaks on, a long conversation in Ghostty or iTerm2 is compacted for you at a natural break,
while it sits at its prompt and nobody's on it, never while Claude works or asks. A break is what the context ring's
"Compact now" goes by (the row's `compactTime`, the commands module's CompactTime): its work has just been saved, or
it's nearly full and Claude would soon compact it by itself, in the middle of a task. Its row then says "Compacted at
1:12" beside the ring until its next message, and panel.log says why and the size before and after. Every
conversation re-sends all it holds with each message, so a long one compacted where nothing is half done costs far
less from then on, and loses nothing it's in the middle of.

## Its pieces

- `app/CompactAtBreaksModule.m`: its face for the core (contracts/Module.h).
  - `tick`, once a second with its switch on: the biggest session that may be compacted for you now is, one at a time,
    through the commands module's `SessionCompacting` (contracts/Module.h, found with `moduleThat:`), which types it
    in as the Compact card does. Its checks are asked cheapest first. Last, only for the one session that has passed
    the rest: whether macOS lets Whozmove control its terminal, asked without asking you, and only then its tab.
  - `rows`, once they're whole: the row's `compactedFor`, until the session's next message: `{at, why, before,
    after}` once it has compacted it, `after` once its new size has been read (or after 30 s, as one can leave it as
    it was); `{at, stopped}` once it stopped part-way; `{at, failed}` once it didn't go through. And while it's at a
    break but can't go in, the row's `compactNote`, `{text, way}`, its whole sentence ("Compact at Breaks can't: …")
    and the way past it, which the ring's tip says, and its Compact card with the way's button; looked at again once
    you've been on the session.
  - `settingEntries` gives its switch in Settings (`autoCompact`, off until you turn it on), with the panel's other
    ways of working with your sessions.
  - `printModes` gives `--print-compact-for-you`.
- `app/ForYou.m`: plain functions. Whether it may compact a session now, or why not (`WhyNotCompactForYou`), and
  whether nobody's on it (`NobodyOnIt`), asked again before each key.
- `page/compacted.js`: what it did. After the ring on the row's bottom line (`compactedForYou`, a plain function):
  "Compacted at 1:12", its tip saying why and the size before and after, or "Couldn't compact", its tip saying why;
  while it shows, the row is marked for where the session runs to make way for it (the row part's
  `place-gives-way`). In the row's note (`compactedStopped`): "Compacting stopped part-way: check its prompt", on one
  line with Take me there, whose tip says why. `page/compacted.css` its look, from the tokens.
- `module.json` lists them for tools/page.sh.

`tests/test.sh` checks each of its checks from sample sessions (`--print-compact-for-you`, compared with
`for-you.expected.txt`) and what the row says (`page-cases.js`, compared with `page.expected.txt`), compacting nothing.

## Rules

- **Off until you turn it on in Settings.** Its switch is a preference, which anything running as you could set, so all
  it can ever do is type `/compact` with its fixed words.
- **Only at a natural break.** The row's `compactTime` says when: its work saved, or nearly full. "Nobody on it for an
  hour" is the ring's suggestion for your press, never one it takes: by then Claude's cache of the conversation has
  gone cold, and compacting reads all of it at full price, which pays off only if the session gets another message. So
  it compacts only within the hour after a turn ends, and only once that turn has been over for 2 minutes, so a quick
  back-and-forth is never interrupted. Never for its size alone, never while Claude works, asks or runs something in
  the background that can change files, and never twice before its next message, even when one didn't go through.
  Never a session started before Whozmove's hooks, whose next message couldn't be told.
- **Never where you might be typing.** Not a session you've been on in the last 5 minutes (looking at it, or writing
  to it); not for 5 minutes after Whozmove starts, as who's been on each session is known only from then; not one also
  open in Claude Desktop, where you may be writing; and, while you're at the Mac, only where held words would go in by
  themselves (not the session you're on, and its terminal not the app in front); and not while you're using the
  panel. Asked again before each key, and before the Backspace that takes its filler out once the result comes: if you
  come to it, the rest is left for you.
- **Nothing asks you with nobody's press.** Its tab is looked for only once macOS has let Whozmove control its
  terminal; until then the ring's tip says so, and compacting once from the card is the press macOS asks on.
- **Only into a terminal the panel types into,** never Claude Desktop, which would come forward. A Claude Code
  session running in the background has no terminal the panel can type into, so it never reaches one; starting a fresh
  session from a handover is for whatever leads that work.
- **It types only `/compact` and its one fixed instruction** (what to keep: where the work stands, the user's own
  words, what's left and what it waits for), never words from anywhere else.
- **It never beeps or opens the Compact card.** What it did stays on the row until the session's next message:
  compacted or couldn't, quietly on its bottom line, and stopped part-way in its note, with Take me there, as part of
  its command may be in the prompt and what was typed there kept aside. One that can't go in says why in the ring's
  tip. panel.log says why each time it waits, once each time that changes.
