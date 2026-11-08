# Fold

The panel folding into a small round glass where the name's o is in its header, and opening round it again; and the
folded glass's breath while sessions work.

## What it shows

- The fold: as the rest of the panel fades, the glass closes in from every side at once, its corners rounding off into
  the circle, and the window becomes the folded panel's square. Opening runs it backwards, the glass spreading out from
  behind the folded panel, moved in from the screen's edge if the open panel would run off it.
- The breath: while sessions work, the folded glass breathes, about 20 a minute with one at work, quicker and a little
  deeper with each more up to five, and from there turning little by little into a soft double heartbeat; once none
  are, it finishes the breath it's in and rests.

## What it owns

- `app/PanelWindow+Fold.m`, the window's category for it:
  - who's told as it folds and opens (`followFold:`, `tellFold:`);
  - the folded window and the open panel, each found from the other (`foldedGlassIn:`, `catBoxIn:`, `foldedFrameFrom:`,
    `openFrameFrom:`, with where its top goes and the room it opens into: `openTopFrom:`, `openRoomFrom:`), round where
    the page measured the name's o (`catAt:`), kept in whole points;
  - folding and opening (`fold:instant:room:peek:`, `fold:instant:`, `keepOpen`), what was asked for meanwhile
    (`takePending`), the panel as it is with nothing moving (`placeAtOnce`), the move itself (`foldMoving`) and how long
    one turned back on its way takes (`foldTimeFrom:to:other:`);
  - the breath (`catBreathe:`, `startBreathing`, `breathe:`, `stopBreathing`), shaped by plain functions (`BreathFor`,
    `BreathLevel`).
- `part.json`: who it talks to.

## Who it talks to

It talks to the core, the bridge, the glass, the turn, hover, the keyboard, the pane and the chats (`talksTo` in
part.json):

- **The core** routes the page's messages to it (`fold`, `catAt`, `catBreathe`, `keepOpen`, Core.m), and the chats
  (parts/chats) hold the room beside the folded panel (`catRoom:`, `letRoomGo`, `roomParts:around:`, `CatRoomFrame`),
  which it takes and lets go as it folds and opens.
- **The glass** moves for it (`setWindowFrame:glass:clip:then:`, `setWindowFrame:showing:then:`,
  `moveGlassTo:clip:corner:glassCorner:over:easing:then:`, `rootAround:`, `settle`, `resendRoom`), and the open
  panel keeps to the glass's room as it opens (`RoomFor`, with `keptBelow` and `linesUnder`), at the height the page
  asked for while it was folded (`OpenedHeight`, `foldedAsked`), which the glass hears with the room it will open
  into (`openRoomFrom:`); the turn puts the
  panel back on its list side at once before it folds (`turnBackAtOnce`); the keyboard is given back as it folds
  (`dropKeyboard`); hover watches the pointer more often while the room beside it is out (`pollPointerEvery:`,
  `tellCatPointerGone`); and a reader asked for while it moved opens once it has (`expandReader:height:`).
- **The bridge's page** is told as the glass is about to spread out (`catGlass:`).
- **Those that follow it** (`followFold:`) are Whozmove beside the panel and the apps module. The glass, hover, the turn
  and the chats' room beside the folded panel (parts/chats) call the private header's `catBoxIn:`, `foldedGlassIn:`,
  `foldedFrameFrom:`, `placeAtOnce`, `startBreathing` and `takePending`.

## Rules

- **The folded panel stays where it is** as the panel folds round it and opens again: its window and the open panel are
  found from the same point, in whole points, so a fraction rounded away at each fold doesn't walk the panel down the
  screen.
- **Only the edges move,** as with the reader, so the page is drawn once; a fold turned back on its way starts from
  where everything is, over as much of the time as it has left to go.
- **Not while the reader is open:** the panel folds from the list alone.
- **The breath only while folded,** never with reduced motion, and it changes only between breaths.
