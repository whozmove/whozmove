# The folded panel

What's drawn on the folded panel's round glass, where the name's o is in the header: a face whose pose says whose move
it is, its eyes on the pointer while it's near, becoming the name's o as the panel opens round it and growing back from
it as the panel folds. The same shapes are drawn natively, for the pawn's mark in the menu bar and Whozmove beside the
panel.

## What it shows

- Its pose for the sessions there are: asleep while nothing runs, watching while sessions work, looking at you while
  one needs your input; pointed at, it looks up.
- Its eyes, which follow the pointer within 480 points of the glass's middle (`CAT_SEES`), drawn to it as if on a
  spring, and don't with reduced motion.
- The panel opening round it, as it shrinks into the name's o and the name comes in from both its sides, and folding
  back, as it grows from the o and the rest of the panel fades; and folding round Whozmove beside the panel, where it
  was pressed.

## What it owns

- `page/cat.js`: its pose and where its eyes look (`catPose`, `catGaze`: plain functions, checked by tests/panel.sh) and
  how they get there (`catSpring`); drawing it (`buildCat`, `drawCat`) and telling the app how many sessions work, for
  the glass's breath (`catBreathe`); the pointer on it (`catHover`, `pointOnCat`, `catLook`, `catEyes`) and near it
  (`catPointer`); its place on the name's o (`catPlace`, `catToName`); opening and folding (`catOpening`, `catFolding`,
  `catOnGlass`, `catGlass`), and from Whozmove beside the panel (`foldFromSide`, `catFromSide`, `catFromSideEnds`,
  `catLanded`); the room beside it (`askCatRoom`, `catRoomTaken`, `catMoving`) and which way what comes out of it goes
  (`catWay`). What it keeps between rebuilds is `state.cat` (state.js).
- `page/cat.css`: its poses and its eyes, the name's o, and how the panel's parts come and go round it as it opens and
  folds.
- `app/CatShape.h`, `app/CatShape.m`: its shapes as SVG paths, in its own units, and those paths as an `NSBezierPath`
  or a `CGPath` (`CatPath`, `CatCGPath`).
- `part.json`: its files for tools/page.sh, who it talks to, and what it provides.

## Who it talks to

It talks to the core, the bridge, the header, morph, for reduced motion (`calm`, parts/morph), and the chats
(parts/chats) (`talksTo` in part.json), and provides `CatShape.h`, `drawCat`, `catLook`, `catHover`, `catOnGlass`,
`pointOnCat`, `catFolding`, `catOpening`, `catFromSideEnds` and `askCatRoom`:

- **The list's drawing** draws it with each update and folds and opens round it (`drawCat`, `catLook`, `catHover`,
  `catFolding`, `catOpening`, `catFromSideEnds`, panel.js, parts/list); peek opens the panel round it and looks where
  the pointer is on it (parts/peek); the chats beside it ask for their room (`askCatRoom`, chats.js), and it tells them
  as it's dragged and as the way they come out turns (`chatsMoving`, `chatsTurned`).
- **The header** says where the name's o is (`headerOff`, parts/header). When Whozmove beside the panel is pressed, the
  panel folds round it through the bridge (`foldFromSide`, then `toggleCollapsed`, parts/bridge). The app calls
  `catRoomTaken`, `catMoving`, `catWay`, `catPointer`, `foldFromSide`, `catLanded` and `catGlass`.
- **Natively,** the pawn menu (parts/menubar) and Whozmove beside the panel (parts/beside) import `CatShape.h`.

## Rules

- **Its shapes match everywhere:** cat.js's, CatShape.m's and the app icon's (icon/make-icon.m). A change to one goes in
  all three.
- **It stays in sight the whole way** as the panel opens round it and folds back: the name's own o waits for it.
- **With reduced motion** its eyes stay still, and its pose changes and drift are left out (`#cat.calm`, cat.css).