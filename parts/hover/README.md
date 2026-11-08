# Hover

The pointer over the panel: where it is, polled rather than heard, as the panel is almost never the window you type
in; what it's on in the page, highlighted, and what the modules do with that; the pointer's shape there; and the
folded panel's eyes following it while it's near.

## What it shows

- What's under the pointer, highlighted (`.is-hover`), as WebKit's own hover goes stale in a window that isn't the one
  you type in, and the list is drawn again whenever what it shows changes, any second.
- The pointer's shape the page asks for: the hand over what a press does something with, the text cursor over text,
  else the arrow, shown only while the pointer is on the page.

## What it owns

- `app/PanelWindow+Hover.m`: the window's Hover category. Polling the pointer (`pollPointer`, `pollPointerEvery:`),
  resting while nothing of the panel can be seen (`restPointer:`, which the glass's `tellSeen:` calls), and telling
  the page where it is (`hoverAt`, `hoverEnd`); the pointer's shape (`pointerShape:`, `dropShape`); what
  the panel holds over or under itself taking the pointer (`heldTakes:`); the folded panel told where the pointer is
  and which way what comes out of it goes (`tellCatPointer:`, `tellCatPointerGone`, `tellCatWay`, with `CatWayFor`);
  where the room beside it takes a click (`CatRoomTakes`); and whether you've been using the panel lately
  (`inUseWithin:`).
- `page/hover.js`: what's under the pointer (`pointedAt`), what gains or loses `.is-hover` (`syncHover`), the shape
  it asks the app for (`pointerShape`), and the modules' watchers, then a row's details, told what it's on; and
  looking again as the list scrolls under a still pointer, so every watcher and the details follow what's under it.
- `part.json`: its files, and what it provides.

## Who it talks to

It talks to the core, the bridge, the glass, the chats, whose room beside the folded panel it lets clicks through
(`passClicks:`, parts/chats), the held row (`stickyAt`, what the pointer is on over its copy, parts/held), a row's
details, the keyboard and the flick (`talksTo` in part.json): the window's own state and the other parts' methods through
the private header (app/core/PanelWindow+Private.h), its public methods in PanelWindow.h's Hover category, the page
through the bridge's `Page` (`hoverAt:`, `hoverEnd:held:`, `catPointer:`, `catWay:up:across:tall:`), and on the page the
bridge's hooks (`core.pointerTargets`, `core.pointerWatchers`, parts/bridge). A row's details (parts/details) are
told what the pointer is on (`detailsFor`); the keyboard's `textBoxes` say where the text cursor goes, and it asks the keyboard
which site is where (`browserAt:`, `pointBrowsersAt:moved:`); off the catch under a swipe on Whozmove at the screen's
edge, it has the flick let it go (`letGoAway`). It calls the glass's (parts/glass) `glassOnScreen`, `pageLeft`,
`pageTop`, from the private header (app/core/PanelWindow+Private.h), and tells those following the pointer
(`followPointer:`) where it is; and the fold's (parts/fold) `catBoxIn:` and `foldedGlassIn:`, from the private header
(app/core/PanelWindow+Private.h), for where the folded panel is.

## Rules

- **Hover is pointer polling** (25 times a second, `pollPointer`), not mouse events: a panel that isn't the key window
  gets no mouse moves. Clicks are handled on `mousedown`.
- **The page is told the whole point a press would land on:** the pointer's place is cut down to the point below, as
  WebKit cuts a press's, so what lights is what a press there takes, even within a point of where two things meet.
- **What changed is all that changes:** only what gains or loses `.is-hover` does, or each move would restart every
  hover transition.
- **The shape goes back to the arrow at once** off the page, so a hand never stays over another app.
