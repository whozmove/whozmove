# Beside

Whozmove beside the panel: while the header has gone, pushed away by the row you're on as the list scrolls, its head
peeks out from behind the panel's top corner, on the side facing the screen's middle, an edge icon as Spotify's token
is. Where the panel was flicked off the screen's edge, it peeks out from there.

## What it shows

- The folded panel's moods, the pointer noticed, a slow blink when the pointer rests on it, and an ear flicked when
  something new needs you.
- Pressed, it comes in front of the glass and the panel folds round it where it is; dragged, it moves the panel. Where
  the panel has gone off the screen's edge, a press or a sideways swipe toward the screen's middle brings it back, and
  one toward the edge pushes it in a little, and it springs back out.

## What it owns

- `app/SideCat.h`, `app/SideCat.m`: `SideCat`, an `EdgeIcon` (parts/edge): its moves, its moods (`takeMood:`), what
  needs you (`needs:`), folding the panel round it, a drag moving the panel, and bringing the panel back from the
  screen's edge; where the folded glass goes as the panel folds round it (`SideCatFoldAt`) and how far a push takes it
  in (`SideCatPushed`): plain functions, checked by tests/edges.sh.
- `page/beside.js`: its place on the page (`core.places.besideEdge`, parts/bridge), for the notifications module to
  fill, in sight whenever the panel is at its edge, which the app knows (`inSight`): it tells it how many sessions need
  you, at night (quiet hours) only those stopped on you. It tells the app (`besideEdge`), and an ear flicks when there
  are more (`needs:`).
- `part.json`: its file for tools/page.sh, who it talks to, and what it provides.

## Who it talks to

The core: the panel's window, which it follows (`followHeader:`, `followLook:`, PanelWindow.h, and the fold's
`followFold:`, parts/fold) and asks to be dragged and to hold it over the glass (`dragBy:`, `draggedByHand`,
`hold:over:`); the folded panel's shapes (`CatShape`, parts/cat); and the shared `Easing`. The bridge (parts/bridge):
the page, which it asks to fold round it (`foldFromSide`), and for the folded panel's moods (`Page`). And the edge part,
whose `EdgeIcon` it is; and the flick, whose public methods in PanelWindow.h it follows and asks to bring the panel back
(`followAway:`, `takeSwipesAwayOn:swiped:`, `unpark`). The core makes it, and passes on what its place on the page is
told (`besideEdge`); main.m's print runs check its plain functions. It reads the window's state through what
PanelWindow.h declares (`parked`, `folded`, `listCorner`, `look`) rather than keeping copies its followers give it, as
`parked` and `folded` change before their followers are told. It calls the glass's (parts/glass) `dragBy:`,
`draggedByHand`, `hold:over:`, `followHeader:`, `followLook:`, `listCorner`, `look`, from PanelWindow.h's own interface.

## Rules

- **It comes out once the header has all gone,** and goes back once the header has come back a few points, so a jitter
  of the scroll doesn't send it in and out.
- **It keeps the folded panel's shapes** (`CatShape`, matching parts/cat/page/cat.js), so it grows into the folded panel
  as the panel folds round it.
