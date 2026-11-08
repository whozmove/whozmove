# Landing

The chats beside the folded panel going home into their rows as the panel opens round it, and back out as the folded
panel's list goes back in: each pulled along its way as if on a spring, and its row taking over once it lands. Folding
before they've landed, they fade where they are.

## What it shows

- Opening the panel with chats out beside it, each is pulled into its row in the list, the lowest first, so each moves
  into room already clear, shedding its card on the way (its pin, its × and the time round it, colour and shadow), and
  its row takes over once the list is in.
- One whose row is out of sight slides under the list's edge on that side; one that's the session you're on, held at
  the list's edge, becomes that held row on its way.
- The folded panel's list going back in, the chats come back out the same way; one still on its way, turned back, keeps
  its speed. Folding before they've landed, they fade where they are.
- With reduced motion, each fades where it is.

## What it owns

- `page/landing.js`: the spring and its timings (`chatSpring`, `CHAT_PULL_DAMPING`, `CHAT_PULL_SPEED`,
  `CHAT_PULL_STAGGER`, `CHATS_LANDED_AT`, `CHAT_PULLED_OUT`), landing and leaving (`chatsLand`, `chatsLeave`), each
  chat's way and how it looks along it (`chatFlight`, `chatDrive`, `chatTurns`, `chatLook`, `chatLookAt`,
  `chatPulledAt`, `chatLooks`, `chatHeldAt`), and the end of it (`chatsFlying`, `chatsFlown`, `chatSettled`,
  `chatsLandingRows`, `chatsLanded`), with the held row's layers shown or hidden in step (`heldLayersAtOnce`). It keeps
  each chat's way, the frame that moves them and the timer that brings the rest of the panel in round them in
  `state.chats` (`flights`, `flyFrame`, `landTimer`), beside the chats' own, and holds the list as it is while they move
  (`state.settleUntil`). Its look is in the chats' chats.css (`.chat.landing`, `body.chats-landing` and the rest).
- `part.json`: its file for tools/page.sh, who it talks to, and what it provides.

## Who it talks to

It talks to the core, the bridge, the chats, the held row, the row and morph (`talksTo` in part.json), and provides
`chatsLand` and `chatsLeave`:

- **The list** has them land as the panel opens (`chatsLand`, parts/list), and peek has them leave as its list goes
  back in (`chatsLeave`, parts/peek); the bridge's hooks run it as the panel folds and opens, and as the list is drawn
  (`core.collapses`, `core.afterDraw`, parts/bridge).
- **The chats** (parts/chats) are what it moves: their frames, their element and how a chat is placed
  (`chatFrames`, `chatsEl`, `chatsPlaced`, `chatTransform`, `chatTowardCat`, `chatGoesAway`, `startChatClock`,
  `drawChats`), and a ride stopped where it has got to before a chat flies (`chatRideStop`).
- **The held row** (parts/held) says what it is for a chat landing on it, while it holds that session's row
  (`heldRowOf`), and folds a chat as its own lines fold (`stickyFold`, `stickyFoldLine`, `stickyMeasure`,
  `stickyCopyOf`, `stickyPlace`, and its layers `stickyEl` and `stickyUnder`); the row says whether a row is in view
  (`rowInView`, parts/row); and morph keeps it in step and says whether motion is reduced (`keepInStep`, `calm`,
  parts/morph).

## Rules

- **Each move follows from the one before:** each chat moves into room already clear, so things that overlap in time
  never touch ([Motion](../../docs/how-it-works/motion.md)).
- **It lands exactly where its row is,** measured at both ends as it sets off, so its row takes over with no jump.
- **Reduced motion tells the same story:** each chat fades where it is.
