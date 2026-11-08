# Tickets

A session can work on one ticket from a ticket tracker (Jira today), given by your press: on the new conversation
card, the Ticket chip finds one as you type, takes its link pasted into your words, offers Create a ticket, or signs
you in first, and Start binds the new session to it (or, for Create a ticket, starts it on a new one). The session reads its ticket with `ask-panel.sh ticket` and works it by that ticket's own
next steps, parent and boards, as its skill says (`working-a-ticket`): it moves it at its milestones with
`ask-panel.sh ticket-move`, which waits on its row for your Move It unless you've turned on May Move Its Ticket for
it, and marks a step that's a person's with `ask-panel.sh ticket-stop`. A new ticket, talked through in the
session, is drafted with `ask-panel.sh ticket-draft`, checked with its tracker, and made only by your Create Ticket on
its row; it's then the session's own. The session's row shows the ticket after its
name, with where it stands; pointing at the tag shows the ticket, and pressing it opens the ticket in your browser.

This module never names a tracker. It finds the trackers through the core (`modulesThat:` with
app/contracts/Tracker.h) and talks to them only through that contract, so a tracker (modules/jira) brings its own
sign-in, keys, links and calls, and nothing here knows what a status is called.

## Its pieces

- `app/TicketsModule.m`: its face for the core (contracts/Module.h).
  - Each session's ticket, bound only by your press: a start from the card that carried one (Module's
    `started:with:`, from the starts module), or Use It on the row.
  - The asks: `ticket-use` (a session asks to work on a ticket, by its key or link: "Work on PAY-148 here?" waits on
    its row), `ticket` (its own ticket, at once, from the last read, with how its last move went, told once),
    `ticket-move` (one of its next steps, with a note and the fields it sets, checked against the last read: "Move
    PAY-142 to In Review?" waits on its row, taking the place of any move waiting there, or it's taken at once while
    May Move Its Ticket is on for the very process that asks) and `ticket-stop` (a next step marked as a person's,
    with why, for the ticket's card) and `ticket-draft` (a new ticket, as JSON: checked with its tracker, whether its
    group is there and takes that type, then "Create this ticket?" waits on its row, taking the place of any draft
    waiting there; one its tracker turns away goes back to the session, "not yet: …", and is never shown, as does one
    it turns away at Create Ticket). Each is
    `askShowing:`, as it only shows you something or reads back what you gave, `ticket-move` checking the switch
    itself, and `logsItself`.
  - A start from Create a ticket (Module's `started:with:`, `{tracker, site, create}`): its row says "New ticket" until
    it has one, and its drafts go to that tracker and site. Your Create Ticket makes it, and binds the session to it.
  - May Move Its Ticket (`SessionSwitch` `moveTicket`), shown only for a session with a ticket, lasting while its
    process and Whozmove run, and given for its ticket (its tracker, site and key), so it ends once that changes.
  - The reads: when a ticket is given, on each ask (not more than once a minute), when its card on the row opens (not
    more than once in 30 seconds), and every five minutes while the session's process runs, each counted from the
    last try however it went, never sooner than the tracker asks; at once on Try Again, and when its tracker is
    signed in again.
    A ticket a session is offered is read once, as it's offered (and again after a restart), for the Use It card.
  - The row's `ticket` (docs/reference/rows.md), the trackers' sign-ins for the card (`setTicketTrackers`), and the
    page's messages: the card's search and a pasted link (`ticketSearch`, `ticketFind`), signing in (`ticketSignIn`,
    `ticketCancelSignIn`, `ticketCopyAsk`), Use It or Not Now (`ticketAnswer`), Move It, Try Again or Not Now
    (`ticketMove`), Create Ticket, Try Again or Not Yet (`ticketDraft`), reading again (`ticketRead`) and opening it
    (`openTicket`).
  - What's kept for a later copy of the panel: `AppDir/tickets/<session>.json`, the tracker, site and key with the
    session's process (its pid and when it started), only you able to read it.
- `app/TicketBindings.m`: plain functions: the row's `ticket`, what `ask-panel.sh ticket` answers (and while a new
  ticket waits), a move checked against the ticket as last read, a new ticket's draft checked, and the record kept and
  read back.
- `app/TicketsPrints.m`: `--print-tickets`, the module driven step by step with a made-up tracker, in a throwaway home,
  May Move Its Ticket through the core's own switches.
- `page/ticket-words.js`: what it draws, in plain functions: the chip and its list in each state, the line a start
  adds to your words, a link found in them, the row's tag, its card (with its last move, and a step marked as a
  person's), the card asking to use a ticket, the card asking to move it, and the card asking to create one.
- `page/tickets.js`: the card's part (`core.startCardParts`), the tag (`core.slots.name`), its card (`core.cards`), the
  Use It card (`core.rowCards`, order 25), the Move It card (order 26) and the Create Ticket card (order 27), and the
  app's answers (`ticketsFound`, `ticketPicked`).
- `page/tickets.css`: their look, from the panel's tokens only.
- `plugin/skills/working-a-ticket/SKILL.md`: how a session works its ticket, collected into Whozmove's plugin as
  `whozmove:working-a-ticket`. A start from the card names it in the line it adds to your words, to work a ticket or
  to create one.
- `tests/test.sh`: `--print-tickets`, its moves and its new tickets in homes of their own, ask-panel.sh turning malformed keys, links and
  step ids, and stdin too long, away, and the page's cases (`page-cases.js`), compared with `tickets.expected.txt`.
  tests/all.sh runs it.

## Between the page and the app

The page sends `ticketSearch {words, asked}`, `ticketFind {text, asked}`, `ticketSignIn {tracker}`,
`ticketCancelSignIn {tracker}`, `ticketCopyAsk {tracker}`, `ticketAnswer {sessionId, act}` (`use` or `notNow`),
`ticketMove {sessionId, key, stepId, act}` (`move` or `notNow`), `ticketDraft {sessionId, at, act}` (`create` or
`notYet`), `ticketRead {sessionId, now}` and `openTicket {sessionId}`. The app calls `setTicketTrackers(trackers)`,
`ticketsFound(asked, {tickets, end, why})` and `ticketPicked(asked, {ticket} | {none} | {key, end, site})`, and each
row carries its `ticket`. A start carries `with: {tickets: {tracker, site, key}}`, or `{tracker, site, create: true}`
for Create a ticket. docs/reference/bridge.md has them
all.

## Rules

- **Only your press gives a session a ticket:** Start on the card with the ticket on it, or Use It on the session's row.
  A session's ask (`ticket-use`) only puts the question on its row, and what's kept for a later copy of the panel is
  only offered back there, to the same process, for another Use It. One session, one ticket.
- **Only your press, or a switch you turned on, moves a ticket.** A session's `ticket-move` puts "Move PAY-142 to In
  Review?" on its row for your Move It, unless May Move Its Ticket is on for that session's own process and its
  ticket, which only your press in its mode menu turns on. A move is only ever one of the next steps last read, with
  only the fields that step sets, and its tracker turns away a step the ticket has moved past (Tracker's `take:`), so
  that one is never taken.
- **Only your press makes a ticket.** A session's `ticket-draft` puts "Create this ticket?" on its row, whole, once its
  tracker has said where it can go; only Create Ticket there makes it, for the draft that card showed, and the session
  hears "created: …" or "not yet: …" once. One that may have been made all the same (sent, and no answer back) is
  never made again by Try Again: the card says to look first, and offers Create Again. No switch lets a session make
  one by itself.
- **Nothing here names a tracker or a status.** A ticket's next steps come from its tracker, read each time, by the
  ids it gives; its kind (to do, under way, done, dropped) gives its colour. Nor does anything in the project name
  someone's own tracker: its tests and docs use made-up sites and keys (acme.atlassian.net, PAY-142), and
  tests/checks.sh fails on any other, and on code that decides by a status's or a step's name.
- **A ticket's address is made from its site and key** by its tracker, never taken from what the tracker sends.
- **Every word from a tracker goes into the page escaped,** and into a session only as `ask-panel.sh ticket`'s JSON.
- **Nothing about a ticket is logged but its key:** panel.log says which ask, which key, which step and how it went,
  never a ticket's title, its words, a note, a field's value, a person's step's why, or anything of a new ticket's but
  where it goes and the key it's given. A move's note and fields, the steps marked and a new ticket's draft are kept
  only in the panel's memory, never written to a file.
- **No read or new ticket for a session that has ended** (a new ticket being made already as it ends finishes), and
  none sooner than its tracker asks after it said to slow down.
