# Notifications

One place every part of Whozmove sends what needs you, with how important it is: the app's own news, and what's new
in each session (the needs-you module's). It knows nothing of what any of it means, and decides what shows, when and
where: on the line under the header in the open
panel, beside the folded panel, and through Whozmove beside the panel at its edge; later in places outside the panel
(macOS notifications, email, Slack), each a module of its own.

## Its pieces

- `app/contracts/Notice.h` (the core's contracts): `Notice`, what a module has to tell you now (its key, its level,
  its words, what makes it new, its one button and what that does, a tag, whether you're looking at what it's about
  now, the session it's about, and how long a place that brings it out keeps it out).
  `NoticeGathering.h` is what only the gathering sets: the module that sent each, and what putting one away does.
- `app/NotificationsModule.m`: its face for the core (contracts/Module.h). Each time the rows are read it gathers every
  module's notices, leaves out what you put away and what you're looking at now, and sends the rest to the page with
  whether the panel is hidden or flicked off the screen's edge, and whether it's quiet hours (`setNotices`, only when
  that changes): `quietHours` on, from `quietHoursFrom` to `quietHoursTo` (minutes after midnight, 22:00 and 08:00
  unless set), kept in the app's defaults. Its messages
  are a press on a notice's button (`noticePress`: the sender's own `press`), its × (`noticeAway`), a page sender's
  notice put away (`noticeAwayHere`, which goes back to the page with the notices), and what's come out beside the
  folded panel, by notice id (`besideSeen`, with when each was first seen beside it in `besideSeenAt`, and going back to
  the page as it loads: `setBesideSeen`). It has Working on Whozmove ▸
  Preview Notices (a made-up notice every 8 seconds, through the real path), the print run `--print-notices`, and
  quiet hours' group on One Task's page under Tools (`appEntries`: its switch and its Night, off at first; Use the
  Recommended Settings puts back the times, never the switch).
- `app/NoticeRules.m`: what it keeps for you, as plain functions over its record: what you put away and until when
  (its `since` changing, or its `awayFor` passing), and a page sender's notices put away (the last for each); and
  whether it's quiet hours at a time of day (`NoticeQuietAt`).
- `page/decide.js`: the decider, plain functions: what the line shows (the most urgent first; among equals, the one
  showing, then the first to come) and how many wait, at night only what's urgent (`noticesSaid`); +N stepping round
  them; whether a page sender's notice put away
  is away still; where each place is in sight, from what each says of itself and whether the panel is on the screen;
  how many notices naming a session Whozmove beside the panel at its edge counts, at night only what's urgent
  (`edgeCount`); and which of them come out beside the folded panel, as their session's chat, and when (besideStep):
  in the order they came, the rest waiting their turn, once for each new word of a since (`newsWithSeen`, one kept for
  each source, the part before its ':'), none while its sender says you're looking at what it's about (seenNow) but
  one that comes out even then (`evenWhenSeen`), which goes once its since changes there, and nothing new while you
  hold one, going where one is about holding it only when you went there from its chat, or its row, while it was out,
  until you leave or the chat goes (besideHold); nothing decided before the app's first rows have come, and what had
  come out before a restart, which the app keeps (`besideSeen`), so only what's new since comes out, what came while it
  was closed among it; and what's been seen of one forgotten a minute after it was last listed (`besideForgotten`).
- `page/notices.js`: runs the decider with each update, as the panel folds and opens and as you press, and fills each
  place (`core.places`): the line, and beside the folded panel, for the page senders' notices naming a session
  (`besideNotices`, only one that says its `outFor`; `besideRows`, one for each session: the more urgent of two, then
  one with something new, then the one whose since came last, in the place's own order once its state() gives
  `sessions`), the chats (`core.places.besideFold`, chats.js, which keeps their cards, room, pins and clock, and tells
  it through `core.notices` what went back, what was pinned and when you let go), and after each drawing of the list,
  Whozmove beside the panel at its edge how many need you (`core.places.besideEdge`). Beside the app's notices, it takes
  the page's own senders' (`core.noticeSenders`, each `{ from, notices(now) }`, made from what only the page knows, as
  One Task's "A task waits"), with the fields the app's notices have and its own press, run on the page. One put away by
  its × (the app keeps which, `noticeAwayHere`) stays away while what makes it new is the same and its time away hasn't
  passed, or, if it says what it folds to, stays as that alone, a chip at the line's end ("3 waiting") that a press
  opens as its button would. It runs the line's presses, and puts a line that says all went well away once it has been
  in sight 4 seconds.
- `page/notice-line.js`, `page/notices.css`: the line under the header (`core.places.line`, in `#notices`): the kit's
  one-line message, its tag ("New"), its button, a +N chip and its ×. It says whether it's in sight: in the open
  panel, or while the folded panel's list is out, and not while the panel is turned over. It grows in, swaps only when
  the notice changes, folds away, and doesn't count a press too soon after it changed (FRESH_MS). VoiceOver says each
  new line once.
- `tests/test.sh`: `--print-notices`, compared with `notices.expected.txt`, and the decider's cases
  (`page-cases.js`), compared with `page.expected.txt`.

## Rules

- A sender only lists what it has to say now. It never calls this module, and this module never acts on a press
  itself: the sender's own `press` runs. So modules stay apart, and
  a notice goes the moment its cause does.
- The level is the sender's: urgent when something stops or waits without you, soon when there's something to do
  when you can, good to know when there's nothing to do. Nothing here raises or lowers it.
- Once only: × keeps a notice away until what makes it new changes, or its time away passes; one naming a session
  comes out once for each new word of its since.
- Never while you're there: nothing is said that its sender says you're looking at now (`seenNow`), beside the
  folded panel only one its sender says comes out even then (`evenWhenSeen`), and nothing new while you point at one
  there, type in it, are where it's about after going there from it, or move the panel.
- It knows no domain: what decides and delivers here reads only its own state (tests/checks.sh), never the rows or
  what a session is; what still reads the panel's fold is listed in tests/part-crossings.txt.
- Nothing jumps under you: while you type in the panel, or a card there has the keyboard, only something urgent comes
  onto the line, or the one you step to with +N; and a press too soon after the line changed doesn't count.
- Quiet at night: during quiet hours only what's urgent is said, on the line, beside the folded panel and at the edge,
  whoever sends it, and what answers something you just did (`answersYou`, as why a press did nothing). The rest isn't
  put away or counted as seen, and is said in the morning if it's still there; what was showing as they began stays
  until it goes, and a chat out then takes newer news that isn't urgent without its time starting again.
