# Handoff

What happens as the row you're on stops being held at the list's edge: its copy lets go, handing back to the row in
place or fading out where it is, or, when the session you're on changes while it holds on, slides off at its edge
while its tint goes to the new session's row; and then it's gone.

## What it shows

- The copy handing back to the row in place at once, or fading out where it is, the list under it coming back.
- Switching sessions while the copy holds on (pressing another row, or another session in Claude Desktop or a terminal):
  the copy slides off at its edge, out of sight, uncovering the list under it as it goes, while its tint goes to the new
  session's row and that row's own tint takes over as it lands.

## What it owns

- `page/handoff.js`: letting go (`stickyLetGo`), sliding off as the session you're on changes (`stickyHandOff`, over
  `STICKY_HANDOFF_MS`), and the copy gone, with what a hand-off left on its layers (`stickyGone`). It writes the held
  row's state as it goes (`state.sticky`: its band, what it covered and how attached it is, and all of it reset once
  it's gone).
- `part.json`: its file for tools/page.sh, who it talks to, and what it provides.

## Who it talks to

It talks to the core, the held row, the header, the row, hover and morph (`talksTo` in part.json), and provides
`stickyLetGo` and `stickyHandOff`, which the held row calls:

- **The held row** (parts/held) has it let go, or hand off; it lays the copy out on held's own (`stickyPlace`,
  `stickyShade`, `stickyRamp`, `stickyPx`, `focusedRow`, and the layers `stickyEl` and `stickyUnder`).
- **The row** counts what's on the row as only just shown once it's back (`showAgain`, parts/row); the header's line
  comes back as the copy goes (`headerLine`, parts/header); hover looks again at what the pointer is on (`syncHover`,
  parts/hover); and with reduced motion it lets go at once (`calm`, parts/morph).

## Rules

- **What's on the row counts as only just shown once it's back** (`showAgain`): a card that came meanwhile can't be
  pressed by a press meant for the copy.
- **The rows stay as they are while it slides off** (`state.settleUntil`), and it starts in the frame the list is drawn
  in, so the new row never shows its own tint before this one lands.
- **A hand-off cut short by another change of session** leaves nothing behind: the next copy isn't drawn where that one
  had slid to.
