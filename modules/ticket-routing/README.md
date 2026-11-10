# Ticket routing

Where a ticket you give a new conversation starts, for each project: in a worktree of its own, named after its key
(PAY-142 in pay-142), so two tickets never work in the same copy of your files; in the project's own folder; or by one
of its tickets' fields, each of the field's options in a folder of the project's own. The first time you give a
ticket to a new conversation in a git project, a short guide on the card asks which; from then on the card puts each
ticket where its project's way says, and says so in one line under its box, with one press back to the project's
folder. A ticket a conversation already works says so, with Go to It. Settings ▸ Tickets changes a project's way
later, showing before and after first. A change counts only for new tickets: one started already keeps its folder.

This module never makes a worktree or starts anything: it tells the card where (the starts module's `where`), and the
card makes it as it makes any worktree, by its own checks of the name. It never names a tracker or a field: it finds
the trackers through the core (`modulesThat:` with app/contracts/Tracker.h), and a field and its options come from the
tracker, by their ids.

## Its pieces

- `app/Routes.m`: plain functions. Each project's way, read back from what's kept and checked again (a project still a
  repo's main folder, a field's folders still among its own, from their `.git` files, without running git); where a
  ticket goes by its project's way, given its own options; each of a field's options matched to one of the project's
  folders by name (the option's name, ignoring case, spaces, dashes and underscores, the same as a folder's branch or
  its name, or that name after the project's and a dash: acme-shop-checkout); and before and after, for Settings.
- `app/TicketRoutingModule.m`: its face for the core (contracts/Module.h).
  - The card's ask, `ticketRoute` (`{asked, folder, tracker, site, key}`), answered at once with what's kept
    (`ticketRouted({asked, key, git, project, name, way, place, guide, problem})`), then again once the ticket's own
    options are read from its tracker, for a way by a field or for the guide, which offers the field whose options
    match most of the project's folders, if any do. `place` is `{kind: own}` (its own worktree), `{kind: here}`,
    `{kind: folder, folder, where}`, or its own worktree for now with `why` (`noValue`, `noFolder`, `gone`, `unread`);
    `problem` says why a ticket wasn't read.
  - `ticketRouteSet` (`{folder, way: {kind, field}}`), the guide's Start: the project's way, kept. By a field, only the
    one the guide offered, its options matched to the project's folders as it's set.
  - `ticketRouteSignIn` (`{tracker}`), Sign In on a line whose ticket couldn't be read for want of one: the tracker's
    own sign-in, then `ticketRouteAgain()`, and the card asks afresh.
  - Settings ▸ Tickets (`settingEntries`), once a project's way is set, opening its page (`appEntries`, a tool, with
    the ticket mark on its tile): a heading marked Important over a row for each project (AppPage), saying its way,
    opening the project's page: its way, picked only after its before and after (AppChoice's `confirm`),
    and for a way by a field, each option's folder, one row each picked from the Mac's menu (AppChoice's `menu`), one
    that has gone said so; a project whose folder isn't there any
    more is said too, with Forget It, its way written back as it was until then.
- `app/TicketRoutingPrints.m`: `--print-ticket-routing`, for the tests.
- `page/routing.js`: its card part (`core.startCardParts`): `where`, `waits` (Start waits while a field's option is
  read), `under` (the guide, or the line), `warn` (another ticket's conversation where it would start), its presses,
  Esc on the guide, and the guide's Start as the card's is sent. `page/routing-words.js`: what it says, as plain functions; `page/routing.css`, their style. It reads the
  card's ticket through `core.cardTicket` (the tickets module's), and the rows' `ticket` and `git`.
- `tests/test.sh`: the module driven in a made-up repo with a made-up tracker (`--print-ticket-routing`,
  `routing.expected.txt`), and the page's part (`page-cases.js`, `page.expected.txt`). tests/all.sh runs it.

## What it keeps

`AppDir/ticket-routing/routes.json`, only you can read it: each project's way by its main folder, and for a way by a
field, its tracker and site, the field's id and name, and each option's id, name and folder. Never a ticket's title or
words. panel.log says only which project's way changed, or which project's folder was let go as it was read.

## Rules

- The guide never trusts a folder, and Esc never starts: Esc only puts the guide away, as Not Now does in a folder
  Claude hasn't worked in, where trusting it stays Trust and Start's. A press or Esc just after the guide shows, or
  changes, doesn't count.
- Only your press sets a project's way: Start with the guide showing (its foot says so), or Change after its before
  and after. Until you press Start, where the card shows it starting is only a suggestion, and your own pick of where
  (`@`, `#`, Use <project>) always wins.
- A change moves no ticket: only new starts follow it.
- A ticket's key becomes a branch and folder name only through its name rule here (lower case, letters, digits, dots
  and dashes), then the card's and the app's checks of any worktree's name. Nothing builds a path from a key or an
  option's name.
- What comes from a tracker (a field's and its options' names) goes into the page escaped.
