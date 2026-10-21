# Usage

How much of your Claude plan you've used, in the five-hour session and the week: the usage card under the panel, as
wide as it, asked of the agent every few minutes; folded behind the panel to a thin line, slid out as it's pointed at,
and open with its two rows, its wait at the session limit, and its Sign in.

## Its pieces

- `app/UsageModule.m`: its face for the core (contracts/Module.h): a check when one is due, on every tick; the card,
  held by the panel, over it (PanelWindow's `attachAbove:`), following the glass and the pointer; what the card's page
  says, answered as the panel's page's messages are; Sign in; and Working on Whozmove's Preview the Wait. While the
  panel is turned over to its back, or flicked off the screen's edge, the card stays out of sight (`followTurn:`,
  `followAway:`).
- `app/Usage.m`: when to ask (every 3 minutes, soon after a window resets, often after Sign in, less often while asking
  fails, never while the screens sleep or the panel is hidden), what the card's page is told, and Sign in, run in the
  first terminal on this Mac that runs a command (Ghostty, else iTerm2, else macOS's Terminal).
- `app/UsageCard.m`: the card's window, a small one of its own that the panel holds over itself, showing the card's
  page, cut to what's outside the panel, so the panel's shadow doesn't fall on the card. It tells the page where the pointer is (the window
  is never key, so it gets no mouse moves), takes clicks only on the part of the card that shows, and never the
  keyboard.
- `page/card.html`, the card's page: the panel's tokens, its controls (`styles/controls.css`, whose one-line message
  with its button the card's Sign in line is) and `util`, then `page/usage.js` (what the card shows: plain
  functions), `page/waits.js` (its wait styles, chosen by name), `page/wait-vine.js` (the first, whose shape and reset
  are plain numbers too) and `page/card.js` (drawing the card folded, slid out and open, opening and folding it, the
  pointer and presses on it, and the functions the app calls), with `page/usage.css`, its style, with its reduced
  motion. `module.json` lists them for tools/page.sh, which puts the page together beside the panel's.

`tests/test.sh` checks what the card shows and the vine's reset frame by frame (`page-cases.js`, with the card page's
scripts); the Claude Code module's `--print-usage` checks what's taken from Claude Code's answers.

## Between the page and the app

The card's page has a bridge of its own, in the same shape as the panel's page's, in the card's window.

- The page sends `usageSignIn`, and `usageCard` (`{shown, extent}`: whether there's a card, and how much of it shows
  under the panel's edge, in points, where the window takes clicks), only when it changes.
- The app calls `setUsage({state, plan, session, week, limits, extraUsage, checkedAt})`, `previewWait()`,
  `cardPointer({x, y})` (where the pointer is in the window, from its top-left corner, while it's near the card;
  `null` once it has gone) and `cardAppear()` (the window has come back into sight).

## Rules

- Nothing about your account reaches the page: only what the card needs.
- The card's page only ever shows itself: it loads nothing else, and only its own page's messages are answered.
- The card takes clicks only on its part that shows under the panel, and never the keyboard: the panel's own bottom
  edge stays the panel's, and pointing at it only brings the card out.

## How the card moves

The card is a window of its own under the panel's edge, as round as the panel, and its page moves it. Folded, it's in
from each of the panel's sides by the panel's corner, so at rest only a thin straight line of it shows under the flat of
the panel's bottom edge, its ends drawn in by its own corners, coloured as far as the window it shows is used. Pointed
at along that line, or on the card, it slides straight down from under the panel by the height of the panel's corners,
widening to half as far in from the panel's sides, its words on it, so they come out from under the edge with it; it
goes back up a moment after the pointer has gone. Only the card moves: the panel keeps its shape and its corners. The
card is drawn over the panel's shadow, so its line keeps its colour; once it's out, its page draws the panel's shadow on
it, following the panel's round corners.

Pressed, the card opens as one. It grows further down and out to the panel's width, its top still behind the panel, so
it shows in the panel's round corners, while its colour shrinks into the bar of its own row, and the words on it travel
to their places in the rows, each measured where it is and where it lands, as two copies (light under the colour, dark
in it), so a word changes colour as it leaves the colour. Words going to the second row go down first, clearing the
first, then along it; words staying in the first go along it; the dot and "left" go before anything passes them. Then
the other row's time, the tracks, its bar drawing in from its start, and the pace note last. When the week is the window
the card shows, its words go down and along quicker and its colour waits a moment, so they're past the bar's place
before it lands. A press anywhere on it (its handle shows it can) folds it back at once: the card shrinks back under the
panel as, on the same timing, its row's bar spreads back into its background, the words going back to their places with
them; the other row's words, its bar, the tracks and the pace note fade first, and the other row's name and percent, the
dot and "left" come back on the card last. At the session limit, and for Sign in, the strip and the folded card
cross-fade as it grows or shrinks, as there's no bar for the colour to land on. While the panel moves or changes shape
(the reader, the cat), there's no card; when it comes back, its line draws in from its left end. Reduced motion has it
change at once.
