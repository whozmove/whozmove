# Edge

An icon tucked half under the panel's glass at its edge, on the side facing the screen's middle: Spotify's round
token at the bottom corner, and Whozmove's own at the top while the header has gone (parts/beside). This part is the
mechanism they share; what each icon shows and does is its own.

## What it shows

- A small window of the icon's own, which the panel holds under itself, so it's really beneath the glass: following the
  glass as it moves and grows, changing sides with the panel under the glass, waiting under the glass while the panel
  opens and then coming out, and out of sight while the panel is turned over.
- The label beside it, saying what a press does, in its own lane outside the panel.

## What it owns

- `app/EdgeIcon.h`, `app/EdgeIcon.m`: `EdgeIcon`, which an icon subclasses. Its window, held by the panel
  (`holdBy:`); its place out from the glass and along it, eased (`out`, `along`, `step:`, `place`); tucking under the
  glass and coming out (`tuckThen:`, `untuck`, `panelOpening`); taking clicks only over itself, and the pointer and
  presses on it (`pointerMoved:over:`, `downAt:`, `draggedTo:`, `upAt:`, `pressed`); its label (`setLabel:more:`,
  `showLabel:`); and the side it's on (`side`), which the panel works out once each time the glass moves
  (`edgeSide`, PanelWindow.h) with `EdgeSideFor`, a plain function checked by tests/edges.sh; and how far in an icon
  tucks (`kEdgeTucked`), which beside's moves use.
- `part.json`: who it talks to, and what it provides.

## Who it talks to

It talks to the core: the panel's window, which holds it and which it follows (`followGlass:`, `followPointer:`,
PanelWindow.h), `Appearance` and `Easing`; and to the turn and the flick, whose public methods in PanelWindow.h it
follows (`followTurn:`, `followAway:`). Whozmove beside the panel (parts/beside) and Spotify's token (the spotify
module) subclass it; the panel's window imports its header to work out the side (`EdgeSideFor`), and main.m's print runs
and Spotify's to check it. It calls the glass's (parts/glass) `attachBelow:`, `followGlass:`, `followPointer:`,
`edgeSide`, from PanelWindow.h's own interface.

## Rules

- **It's beneath the glass, not beside it:** the panel holds its window under itself, so the glass's shadow falls on
  it, and it comes out only once the panel has opened.
- **It takes clicks only over what shows of it,** so it never takes one meant for what's under the panel.
- **All the icons agree on the side:** the panel works out the side once each time the glass moves, before those
  following it are told.
