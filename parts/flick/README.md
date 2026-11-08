# Flick

A sideways two-finger flick on the open panel's list pushes it off that edge of the screen, out of sight, with
Whozmove peeking out where it went; it comes back where it was from there, from Show / Hide Panel, or ⌃⌥N. It isn't
kept away when the app starts again.

## What it shows

- The panel leaning with the fingers, then going off the screen's edge at their speed, and coming back; with reduced
  motion, fading out and back in.
- Away, a swipe on Whozmove there pulls the panel back out with the fingers, point for point.

## What it owns

- `app/PanelWindow+Flick.m`: the window's Flick category. Taking a sideways swipe (`swiped:`), going away
  (`parkToward:speed:`, `slideTo:over:fading:then:`, `fadeTo:coming:then:`) and coming back (`unpark`,
  `unparkOver:`, `backAtOnce`); a swipe on Whozmove while away (`takeSwipesAwayOn:swiped:`, `swipedAway:`,
  `pulledTo:`), and the catch under it that takes the rest of the swipe and its glide (`holdAway`, `liftedAway`,
  `glided:`, `letGoAway`); and who's told (`followAway:`). Its flags (`parked`, `returning`) are set only here. How a
  swipe is read and where the panel goes are plain functions (`SwipeWay`, `SwipeFlicks`, `SwipePulled`,
  `PullBrings`, `ParkedOrigin`, `ParkedShows`), checked by tests/edges.sh.
- `part.json`: who it talks to, and what it provides.

## Who it talks to

The core: the window's own state and the other parts' methods through the private header
(app/core/PanelWindow+Private.h), and its public methods in PanelWindow.h's Flick category, which Whozmove beside the
panel and the edge's icons follow and use, as do the usage card and the notifications module (`followAway:`); the glass
brings the panel back from Show / Hide Panel and ⌃⌥N (`unpark`). The turn, which takes a turn that waited once the panel
is back (`takePendingTurn`), and the keyboard, which it has give the keyboard back as the panel goes (`dropKeyboard`).
The glass hands it a swipe, and hover has it let go of the catch. It calls the glass's (parts/glass) `edgeSide`, from
PanelWindow.h's own interface, and `glassOnScreen`, `tellGlass:over:`, from the private header
(app/core/PanelWindow+Private.h). It tells the page the panel has gone through the bridge's `Page` (`flickedAway`,
parts/bridge).

## Rules

- **Up and down stay the list's;** a swipe is the panel's only once it's plainly sideways, and while one of the page's
  boxes has the keyboard, it's the box's.
- **Folded, a swipe is the page's.**
- **What's held over or under the panel goes as it leaves and comes back as it starts back** (`followAway:`).
