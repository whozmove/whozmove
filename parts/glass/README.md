# Glass

The panel's window itself: the floating glass, its drag strip, its size, the page laid out in it and its shadow. The
window is one class, `PanelWindow`, in a file per part; this is its own file, with the class's own `@implementation`,
and the other parts' categories build on it.

## What it shows

- The glass: grey, black or glass, light or dark, as Settings' Appearance has it, with its rounded corners, and its
  shadow in a window of its own under it.
- The drag strip over the header (and over the reader's), which covers only what shows of the header as it slides away.
- The page's frame (`page/glass.css`): the column the header and the list are laid out in, at the page's one width, and
  the list's room under the header.

## What it owns

- `app/PanelWindow.m`: setting the window up and showing it (`initWithPage:`, `show`, `toggle`, `bringUp`,
  `resetPosition`), whether anything of it can be seen (`seen`, told to the page with `tellSeen:` as each of those says
  it and as macOS says it changed: hidden, the screen asleep or locked), its size and the room the screen gives it (`fitHeight:`, `resendRoom`, the reader's room with
  `roomFor:`), with the room kept under it for what a window it holds hangs there (`keepBelow:for:`, the most of them
  kept: the usage card's), and the most its header and list take on that screen, told to the page with the room
  (`setRoom`), the page laid out in it and what's held over or under it (`hold:overPage:`, `letGo:`, `attachBelow:`,
  `attachAbove:`, `hold:over:`), its look (`look`, followed with `followLook:`), the header's place for the drag strip
  (`headerShowing:gone:`, `followHeader:`), being dragged (`dragBy:`, `draggedByHand`), and who's told as it moves
  (`followGlass:`, `followPointer:`, the side its edge icons are on, `edgeSide`, and the side the reader would open to,
  told to the page as it changes, `tellReaderSide`); the shadow (`shadeGlass`,
  `holdShade`, `roundGlass:`), and the helper views and windows' own code (`FloatingPanel`, `DragStrip`, `SideView`,
  `PageCover`, `Tint`, `ShadeView`), whose interfaces are in the private header. Where the page's frame goes in the
  window (`PageFrameIn`), how tall the open panel can grow where it is (`RoomFor`, which opening out of the cat keeps
  to too: never less than the header, the lines under it, which the page says with each height it asks for
  (`linesUnder:`), and a row, so what hangs below gives way first), how tall it opens out of the cat (`OpenedHeight`:
  what the page asked for while it was folded) and the most the header and the list take on a screen (`ListLimitFor`:
  640pt, or all its room where it has less) are plain functions, checked by tests/edges.sh. And the setting of macOS's own that lets the
  panel show the hand and the text cursor while another app is in front (`LetPointerShapesIn`).
- `page/glass.css`: the page's frame, the list kept to the screen's limit (`--most`, set with the room: `setRoom`).
- `part.json`: its file for tools/page.sh, and who it talks to.

## Who it talks to

The class's own interface (app/core/PanelWindow.h) and what the window's parts share (app/core/PanelWindow+Private.h,
with the constants and the window's own state) stay in the core, so the frame and the modules use the window as before.
It talks to the core, to the chats, to the bridge, for the page laid out in it (`Page`, parts/bridge), and to the parts
whose categories it calls: the turn (`placeBack`, `turnOver:then:`, `takePendingTurn`), the flick (`swiped:`, `unpark`,
`backAtOnce`), hover (`pollPointerEvery:`, `restPointer:`, `tellCatWay`), the keyboard (`clickedAt:`), the pane
(`tellStill`, and, for the side the reader opened to, the window's `expanded` and `listOnRight`) and the edge
(`EdgeSideFor`). It calls the fold's (parts/fold) `catBoxIn:`, `foldedFrameFrom:`,
`foldedGlassIn:`, `placeAtOnce` and `startBreathing`, from the private header (app/core/PanelWindow+Private.h), and the
chats' (parts/chats) `letRoomGo`, the room beside the folded panel let go.

## What it doesn't give out

- **Its state as one value:** a part reads the window's properties one by one (`folded`, `parked`, `turned`, `edgeSide`,
  `listCorner`), each as PanelWindow.h declares it.
- **Room beside the list on request:** only the reader grows the panel beside the list (`expandReader:height:`).
- **A notice the moment a flag flips:** those following the fold and the flick are told when a move starts or ends,
  and `parked` and `folded` can change before that (`folded` at launch, `parked` as the slide off the edge starts), so a
  part that needs the flag reads it.

## Rules

- **The panel must never take the keyboard:** the window is a panel that becomes the key window only while one of its
  boxes, a card or a site in it has been clicked into ([the panel's own rules](../../docs/how-it-works/panel-rules.md)).
- **The page is never laid out at another width:** a change of width has WebKit lay it all out and draw it again, which
  shows as the whole panel flashing; the window shows the part in use.
- **What's held over or under the panel moves with it,** and every part that moves something with the glass follows it
  (`followGlass:`) rather than reading where it is.
- **The glass, the page's clip and the page move together, on one clock**
  (`moveGlassTo:clip:corner:glassCorner:over:easing:then:`): AppKit steps the glass's frame itself, so a clip Core
  Animation moved beside it would run ahead or behind and show the page past the glass's edge.

## Facts

- **macOS shows only the pointer shapes the app in front sets.** The panel's app is never in front, so on its own it
  could show only the arrow. A window server setting that isn't public, `SetsCursorInBackground` (seen working on macOS
  26.2), has macOS take them from Whozmove too; `LetPointerShapesIn` looks it up as the app runs and sets it once, so a
  macOS without it leaves the arrow, and says so in the panel's log.
