# Usage

How much of your Claude plan you've used, in the five-hour session and the week: the usage card under the panel, as
wide as it, asked of the agent every few minutes; folded behind the panel to a thin line, slid out as it's pointed at,
and open with its two rows, your gear with its seats, the session that has used the most today at its foot, its wait
at the session limit, and its Sign in.

## Its pieces

- `app/UsageModule.m`: its face for the core (contracts/Module.h): a check when one is due, on every tick; the card,
  held by the panel, over it (PanelWindow's `attachAbove:`), following the glass and the pointer; what the card's page
  says, answered as the panel's page's messages are; once the rows are whole, the session that has used the most
  today (`setHeaviest`, from each row's `agent.today`, only while two or more have used any); Sign in; and Working on
  Whozmove's Preview the Wait. While the
  panel is turned over to its back, or flicked off the screen's edge, the card stays out of sight (`followTurn:`,
  `followAway:`). Your gear: on each read of the rows, the sessions working on the plan it shows counted, and the
  time added up; at each answer, a sample kept in `usage-gear.json` (3 days, numbers only) and what it measures; a
  press on a seat (`gearSet`) setting the gear, kept in the preferences under `gear` and said in panel.log ("gear set
  to N", as the preferences keep only the latest); both pages told at once
  (`setGear`); `gear.json` for a lead session of yours; `GearFacts` (contracts/Module.h) for the rest of the app; and
  Usage Gear, its switch in Settings (`usageGear` in the preferences, on until you turn it off), which turned off
  counts nothing, forgets your gear and its files, and tells both pages it's off.
- `app/Gear.m`: the gear's plain functions: who counts as working (Work's `SessionWorking`), what the reads add up, the
  samples kept, how much of the week a working session-hour took lately, the recommendation and why there's none yet,
  the forecast at a gear, the gear a press on a seat sets, gear.json and its off record, how a lead reads it
  (`GearFileLimit`), what's taken away with the gear off (`GearForget`), and `--print-gear`.
- `app/Usage.m`: when to ask (every 3 minutes while a session works or the card is slid out or open, else every 10,
  soon after a window resets, often after Sign in, less often while asking fails, never while you're away from the Mac,
  the screens sleep or the panel is hidden; as plain functions, `UsageDue` and `UsageAnswered`), and the last numbers
  found kept in `usage-last.json` in Whozmove's folder (each window's percent and reset, and when, nothing else), for a
  script of yours to read, what the card's page is told, what panel.log says of each answer (`UsageLogAnswer`: with no
  card, that it's hidden and why, from the agent's `noPlan`, once each time that changes and once as Whozmove starts,
  each reason in words of its own; else, in its own words too, what the card does: shows your plan's numbers, asks you
  to sign in, or keeps what it last showed when no answer came), and Sign in, run in the first terminal on this Mac
  that runs a command (Ghostty, else iTerm2, else macOS's Terminal).
- `app/UsageCard.m`: the card's window, a small one of its own that the panel holds over itself, showing the card's
  page, cut to what's outside the panel, so the panel's shadow doesn't fall on the card. It tells the page where the
  pointer is (the window is never key, so it gets no mouse moves), takes clicks only on the part of the card that
  shows, and never the keyboard. How much of the card can show under the panel's edge, at most, is `UsageCardReach`
  (UsageCard.h): the window is sized by it, and the module has the panel keep that much room under itself
  (PanelWindow's `keepBelow:for:`) from launch, letting it go only once an answer leaves no card (`UsageShowsCard`: no
  plan's numbers, the agent's `noPlan` saying why, or nothing to ask), and keeping it again when one comes; never as
  the card slides out, opens or folds, so nothing moves then. Under the reach, the window keeps 36pt more for the
  card's shadow, so with the panel kept just high enough, up to 20pt of soft shadow may go under the screen's edge
  while the card stays whole.
- `page/card.html`, the card's page: the panel's tokens, its controls (`styles/controls.css`, whose one-line message
  with its button the card's Sign in line is) and `util`, then `page/usage.js` (what the card shows: plain
  functions, every word of the gear and where its seats are among them), `page/gear.js` with `page/gear.css` (the
  gear's seats, drawn on the card; on the panel's page, `core.gear`: the gear, its lines and its words, with where to
  change it),
  `page/over.js` (Over the gear at the end of the title line of each session in `over`, on the panel's page), `page/waits.js` (its wait styles, chosen by name), `page/wait-vine.js` (the first, whose shape and reset
  are plain numbers too) and `page/card.js` (drawing the card folded, slid out and open, opening and folding it, the
  pointer and presses on it, and the functions the app calls), with `page/usage.css`, its style, with its reduced
  motion. `module.json` lists them for tools/page.sh, which puts the page together beside the panel's.

`tests/test.sh` checks what the card shows and the vine's reset frame by frame (`page-cases.js`, with the card page's
scripts), its part of the panel's page, the gear beyond the card and Over the gear on a row (`panel-cases.js`), and when the usage is asked over sample stretches of time (`Whozmove --print-usage-checks`, with
`checks-cases.json`), what's kept of an answer (`--print-usage-kept`, with `kept-usage.json`), what panel.log says as
answers come (`--print-usage-said`, with `said-answers.json`), and the gear's numbers
(`--print-gear`, with `gear-cases.json`), and why Sign in can't open with no terminal, naming those Whozmove opens,
and the reason with the command to run yourself (`--print-sign-in`); the Claude Code module's `--print-usage` checks
what's taken from Claude Code's answers.

## Its pace

Each window's pace is how much of it is used over how much of its time has gone (`windowPace` in page/usage.js): 1 uses
it up right as it resets. Anything above 1 is fast, as the window then runs out before it resets, however slightly;
from 0.2 under 1 up to 1 counts as even, and anything lower is slow. The card never shows it as a number: each row
shows where its window ends up by its reset at that pace (`endsText`), `→ 30%`, or `out 1:41 PM` when it runs out first
(its time to the reset then reading `resets 4d 1h`, `resetsText`), dotted on along its bar from the end of what's used,
grey while even, amber fast and blue slow. A window shows a dash until it has run long enough for its pace to mean
something: 20 minutes for the session, 12 hours for the week. The line under the rows says what that comes to, and under
it, on a line of its own, what to do about it, about the session, unless the week will run out first and the session
won't, or the session has no reading. A window Claude Code's answer has nothing for has no reading (`usageWindow`'s
`known`), which isn't 0%: its row shows "–" and "no reading" (`percentText`, `resetsText`), still while it's pointed
at, and the folded card shows the window that has one. The notch on the slid-out card is where even use would be by
now.

## Between the page and the app

The card's page has a bridge of its own, in the same shape as the panel's page's, in the card's window.

- The page sends `usageSignIn`, `gearSet` (`{to}`: a press on a seat, the gear it sets, from 1 to 30), and
  `usageCard` (`{shown, extent}`: whether there's a card, and how much of it shows
  under the panel's edge, in points, where the window takes clicks), only when it changes.
- The app calls `setUsage({state, plan, session, week, limits, extraUsage, checkedAt})`, `setHeaviest({name, share,
  tokens})` (the session that has used the most today, or `null`: UsageModule's, from each row's `agent.today`),
  `setGear(facts, pressed, off)` (your gear: also on the panel's page, at once, each time it changes and after your
  press; `null`, with `off`, while it's turned off in Settings),
  `signInFailed(why)` (Sign in's terminal couldn't open it, as the terminal says why, with the command to run yourself),
  `previewWait()`, `cardPointer({x, y, from})` (where the pointer is in the window, from its top-left corner, while it's
  near the card, and `from`, `{x, y}`, where it was at the app's look before, even outside the window, so a quick hand
  that crossed the panel's edge between two looks slides the card out too; `null` once it has gone),
  `cardAppear(drawIn)` (the window fades in, its fill drawing in, or comes back into sight with the panel: the card
  looks once, without moving, so what came meanwhile is there as it shows, and its clock runs) and `cardGone()` (the
  window fades out, or goes from sight with the panel: its clock stops).

## Rules

- Nothing about your account reaches the page: only what the card needs.
- The card's page only ever shows itself: it loads nothing else, and only its own page's messages are answered.
- The card takes clicks only on its part that shows under the panel, and never the keyboard: the panel's own bottom
  edge stays the panel's, and pointing at it only brings the card out.
- What eases on the open card as the pointer comes and goes is on a layer of its own from the start (`will-change` in
  usage.css).
- The pace is advice only: the card says where each window ends up and what to do about it, and changes nothing in
  Claude Code.
- **Only your press moves the gear.** The recommendation never sets it, a session may read `gear.json` but never set
  it, and the app reads that file back only to see whether it holds the off record, never to take a gear from it. A
  session over the gear is only counted, never stopped.
- **Usage Gear off keeps nothing for the gear.** Turned off in Settings, nothing is counted or sampled, your gear and
  when you set it go from the preferences, `usage-gear.json` goes from Whozmove's folder, and `gear.json` is only the
  off record, `{off: true, updatedAt}`, holding no gear (`GearForget`, and again as the app starts while it's off);
  both pages are told the gear is off (`setGear(null, NO, YES)`).
- **Off means no limit, and only the off record says so.** Off, Up next lets every queued job in, and a lead finds
  `"off": true`. A lead reads anything but the off record or a gear (`GearFileLimit`) as none: no file, one it can't
  read, `gear` null. So a file not written yet (before the first start, deleted, a write that failed, which is
  logged) never lets everything in. On, the off record gives way at the start and as it's turned on to `gear` null
  until the gear is known, and with no gear set Up next lets nothing in.
- The gear names no gear until the week has risen 5 points over 2 working session-hours while Whozmove watched, and
  never from the five-hour window alone, which can only lower it. It's worked out at each answer and each press, never
  on the clock alone, so while you're away it stays as it was.
- Every word of the gear is usage.js's (`core.gear` gives them to the panel's page): nothing else words it.

## How the card moves

The card is a window of its own under the panel's edge, as round as the panel, and its page moves it. Folded, it's in
from each of the panel's sides by the panel's corner, so at rest only a thin straight line of it shows under the flat of
the panel's bottom edge, its ends drawn in by its own corners, coloured as far as the window it shows is used. Pointed
at along that line, or on the card, it slides straight down from under the panel by the height of the panel's corners,
widening to half as far in from the panel's sides, its words on it, and a notch at its bottom edge where even use
would be by now, so they come out from under the edge with it; it
goes back up a moment after the pointer has gone. Only the card moves: the panel keeps its shape and its corners. The
card is drawn over the panel's shadow, so its line keeps its colour; once it's out, its page draws the panel's shadow on
it, following the panel's round corners.

Pressed, the card opens as one. It grows further down and out to the panel's width, its top still behind the panel, so
it shows in the panel's round corners, while its colour shrinks into the bar of its own row, and the words on it travel
to their places in the rows, each measured where it is and where it lands, as two copies (light under the colour, dark
in it), so a word changes colour as it leaves the colour. Words going to the second row go down first, clearing the
first, then along it; words staying in the first go along it; the dot and "left" go before anything passes them. Then
the other row's time, where both end up, the tracks and their dots, its bar drawing in from its start, and the pace line,
the gear and the foot line last, fading in and lifting 3px. A press on a seat turns the gear's number first (the old
one fading and lifting out as the new comes in, 0 to 160 ms) as its box eases to the new gear (340 ms), then the line
under the rows clears and the new words come in, lifting 3px. Pointing at a seat, a ring fades in round the box a
press there would make. When the week is the window
the card shows, its words go down and along quicker and its colour waits a moment, so they're past the bar's place
before it lands. A press anywhere on it but your gear's line (its handle shows it can) folds it back at once: the card shrinks back under the
panel as, on the same timing, its row's bar spreads back into its background, the words going back to their places with
them; the other row's words, where both end up, its bar, the tracks and their dots, and the pace line fade first, and the
other row's name and percent, the dot, "left" and the notch at the card's edge come back on the card last. At the session limit, and for Sign in, the strip and the folded card
cross-fade as it grows or shrinks, as there's no bar for the colour to land on. While the panel moves or changes shape
(the reader, the cat), there's no card; when it comes back, its line draws in from its left end. Reduced motion has it
change at once.
