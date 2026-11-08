# Chats

What needs you, out beside the folded panel: the place the notifications module fills beside it
(`core.places.besideFold`). While the panel is folded, a session that comes to need you comes out beside it by itself,
as its row, the list's own, so it's answered or opened there as it would be in the list. Which come out and when is the
notifications module's; this part places them, keeps their time, and gives them the room they need.

## What it shows

- Up to three chats beside the folded panel, nearest it first, toward the screen's middle, and up from it while it's
  low on the screen; a pill under them saying how many more wait.
- A request's or a question's card on a chat taking its keys once pressed, as on the list (`core.keyPlaces`, the
  keyboard part's), while the chat is out where it can be seen, and not for a press on one only just come out or moved
  up; holding them holds it out.
- A row's details opening in a chat as they do in the list, the chat growing with them (parts/details).
- Each chat's time left as a ring round its ×, which empties; pointing at it, typing in it, pinning it, or being in its
  session's tab after pressing it, or its row, holds it out, until you leave the tab.
- A chat out for what a module says is new in its session (a reply in its side chat), not the row's own news, saying
  the module's line in Claude's place, with its time (`said`, to rowHTML).
- A chat going back in once it's answered, read, pressed away or out of time, those below moving up and the first
  waiting coming out after them.

## What it owns

- `page/chats.js`:
  - the plain functions tests/panel.sh checks: their time (`chatsTick`), how many fit (`chatsFit`), where each goes
    (`chatsLayout`), where the one you hold stays (`chatsKept`), which one you're pointing at (`chatPointed`), and
    where one coming out starts (`chatComesFrom`) and how long it waits for a clear lane (`chatComesAfter`), and
    where a ride puts those riding it on its way (`chatRideFrames`);
  - the place notifications fills (`core.places.besideFold`), which says it's in sight while the panel is folded, its
    list not out and not opening round the cat (`inSight`), drawing them with each update (`drawChats`), placing and
    laying them out (`placeChats`, `layChats`, `moveChats`, `moveChat`, `chatComes`, `makeChatFrame`, `chatGoes`,
    `chatGoesAway`), those after a shrinking one riding its foot (`chatRide`, `chatEasing`, `chatRideOn`,
    `chatRideStop`, the landing's too), the pill (`drawChatMore`, `placeChatMore`), the room they ask for
    (`askChatRoom`), their clock (`startChatClock`, `chatClock`), the pointer and presses on them, whether a chat is out
    where it can be seen (`chatShown`), has only just come out (`chatFresh`) or is still on its way, or one before it
    (`chatsSettling`), and its cards' place for the keys (`core.keyPlaces`), and following the folded panel as it's
    dragged or turns (`chatsMoving`, `chatsTurned`).

  What it keeps between rebuilds is `state.chats` (state.js), but for the landing's ways into their rows (`flights`,
  `flyFrame`, `landTimer`), which a chat going back in ends (`chatGoes`).
- `page/chats.css`: a chat's card, its pin, its × and its ring, and the pill; and the landing's look (`.chat.landing`,
  `.row.chat-landing`, `body.chats-landing` and the rest).
- `app/PanelWindow+Chats.m`, the window's category for it: the room beside the folded panel for the chats, which the
  page names (`catRoom:`, `roomParts:around:`, `CatRoomFrame`), letting it go (`letRoomGo`), and the clicks it lets
  through where nothing's drawn (`passClicks:`).
- `part.json`: its files for tools/page.sh, who it talks to, and what it provides.

## Who it talks to

It talks to the core, the bridge, the glass, the fold, hover, the list, the row, morph, the folded panel's part and the
keyboard (`talksTo` in part.json), and provides what the others call, as part.json lists:

- **The bridge:** the notifications module fills its place (`core.places.besideFold`, `core.notices`), and the page is
  told once the room it asked for is there (`catRoomTaken:`, parts/bridge). The core routes the page's `catRoom` message
  to it (Core.m), and main.m's print runs check `CatRoomFrame`.
- **On the page,** each chat is the row part's row (`rowHTML`, `FRESH_MS`, parts/row), moved on morph's helpers
  (`morph`, `morphOvershoot`, `atMorphEnd`, parts/morph); its presses go through the list's (`takesPresses`,
  parts/list), and its cards' keys through the keyboard's (`core.keyPlaces`, `heldCard`, parts/keyboard); and it asks
  the folded panel for room beside it (`askCatRoom`, parts/cat), which follows it as it's dragged or turns
  (`chatsMoving`, `chatsTurned`). The list draws it with each update, peek redraws it as the list comes out and goes
  back (`drawChats`), and the landing (parts/landing) takes them into their rows and back out, stopping any ride
  where it has got to first (`chatRideStop`).
- **Natively,** the room moves on the glass's (`setWindowFrame:glass:clip:then:`, `rootAround:`, `settle`,
  parts/glass), with the fold's square (`catBoxIn:`, `takePending`, parts/fold) and hover watching the pointer
  (`pollPointerEvery:`, parts/hover); the fold takes and lets go of it as it folds, the glass lets it go, and hover
  has it let clicks through (`passClicks:`).

## Rules

- **What comes out, and when, is the notifications module's:** this part only places what it's told to show.
- **The room beside the folded panel takes clicks only where something's drawn;** everywhere else they go through to
  what's under it.
- **The window's frame isn't saved while there's room beside it,** so the panel comes back next time as the folded
  panel alone.
