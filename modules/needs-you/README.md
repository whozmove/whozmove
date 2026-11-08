# What needs you

Says, for each session, what's new in it that needs you, as a notice for beside the folded panel: a request, a wait,
a reply you haven't read, or what another module says is new in it (a reply in its side chat). Notifications brings
each out once for what's new, as that session's chat, and Whozmove beside the panel at its edge counts them.

## Its pieces

- `page/needs-you.js`: what's new in a session (`sessionNews`: a request by its id, a wait by when it began, a reply
  by when it came), how much it needs you (`sessionLevel`: a request or a wait urgent, a reply soon), what a module
  says beside it (`rowNews`, from `core.sessionNews`, the row's own first), whether you're in its tab
  (`sessionLookedAt`), and the notices it sends through `core.noticeSenders` (`needsYouNotices`): one for each session
  as the chats place has it (`chatsPlaced`, in its order), its key and `session` the session's id, its since what's new
  (empty for nothing), its words a module's line, `seenNow` while you're in its tab, `evenWhenSeen` for a request,
  `openedAt` for the one last opened from the panel, and `outFor`, how long its chat is out at most (45 seconds,
  `NEEDS_YOU_OUT_FOR`, its own).
- `core.sessionNews` is this module's: what a module knows is new in a session beyond its row's own state, each
  `(s) → { news, level, line, at } | null` (parts/bridge/page/modules.js has its contract). Side Chat adds its
  replies there, and Team reads it to put the rows that need you first.
- `tests/test.sh`: its cases (`page-cases.js`), compared with `page.expected.txt`.

## Rules

- **Only what the session's own state or a module says.** A module's word is its own (`side:…`), one word, never one
  of the row's own kinds (`ask:`, `wait:`, `reply:`), under 80 characters, with a level there is; its line one line
  of 160 characters at most. Anything else is passed over, so nothing a module says can pass for a request.
- **A request comes out even in its tab:** its session can't go on until you answer, so it's never seenNow's to hold
  back; a wait or a reply in the tab you're in is seen there.
- **One notice for every session listed,** with an empty since when nothing's new, so what's been seen of it is kept
  while it's listed, and a chat out for it stays while you're in its tab.
- **It says how long its chat is out at most, and nothing else of when or where:** its own 45 seconds, which
  notifications keeps to; once only, quiet hours and what fits are notifications' and the chats place's.
