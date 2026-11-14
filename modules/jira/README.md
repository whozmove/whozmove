# Jira

Jira as a ticket tracker (app/contracts/Tracker.h): signing in with Atlassian once, on Atlassian's own page in your
browser, and Jira's tickets searched, read with their own next steps, project and boards, moved, noted on and made, as
you, through Atlassian's server for AI tools (the Rovo MCP server, v2). Its page on the panel's back says how the
sign-in stands, with Sign In with Atlassian, Cancel, Sign Out, Allow (after an update), Sign In Again (for a sign-in
that can't move tickets), or what to ask your Jira admin.

Nothing here knows a site's status by name. A ticket's next steps are Jira's transitions for that ticket, read each
time, with the fields each one's screen needs. The kinds to do, under way and done come from Jira's own three status
categories (by their key, or by their name where an answer gives only that), and dropped from the resolution's name
(see Rules).

## Its pieces

- `app/JiraModule.m`: its face for the core (contracts/Module.h) and its Tracker: the calls, each through Atlassian's
  server with a token; Jira on the panel's back (`appEntries`), its card in `app/JiraCard.m` (a plain function for each
  state); a notice once the sign-in has run out, with Sign In Again; and `--print-jira talk`, a whole sign-in and every
  call against a stand-in.
- `app/JiraAccount.m`: the sign-in. It finds Atlassian's sign-in from the server's own published pages, signs in with
  `app/shared/OAuth`, keeps the refresh token and the client id in the Keychain (`app/shared/Keychain`), with the scopes
  that sign-in asked for, keeps the access token in memory only, and refreshes it before it runs out, one refresh at a
  time. As it starts it only looks whether a sign-in is kept, and whether only this build can read it; the secret is
  read the first time a call needs it, quietly, and when macOS would ask first (a new build), the sign-in stands as
  asking (`TrackerSignInAsksMac`) until your press of Allow reads it, off the main thread, with macOS's box, and keeps
  it afresh as this build's. It says whether the sign-in it holds reads only (`readsOnly`).
- `app/JiraTickets.m`: plain functions turning the server's answers into tickets, steps, boards, sites, a project's
  types and its priorities in order (each ticket's place among them by Jira's id), a ticket's options in its own
  fields that take one (Ticket's `values`) and a type's fields that take one option, with their options' ids (for
  where a ticket starts: `optionFieldsOf:done:`), looking for
  each in every shape the server has given it, and a move's fields, given as every tracker gives them, into Jira's own
  shapes for that step's screen (an option by the id Jira gave it). For a read of every ticket you can see: a search's next
  page (`everyTicketSince:done:`), and a ticket's moves from its history (`readWhole:site:done:`).
- `app/JiraFacts.m`: what Atlassian could change: the server's address, the scopes, the tools' names, a key's and a
  link's shapes, the search's JQL and every ticket's (what changed lately),
  the kinds, and what to ask an admin. It says which answers are assumed until a live read confirms them.
- `app/JiraPrints.m`: `--print-jira facts <samples>`, `--print-jira answers <folder> <site>` and `--print-jira keychain
  …` (a made-up entry of its own, for a virtual Mac), for the tests.
- `tests/test.sh`: the plain functions over made-up samples (`facts.json`), recorded answers (`answers/`, made up, in
  the server's shapes), the Keychain's stand-in, and talks with
  `tests/stand-in.py`, a stand-in for Atlassian on 127.0.0.1 that checks what Whozmove sends as Atlassian would (and,
  in its `noscope` mode, refuses writes as Jira refuses a token without the write scope).
  Compared with `jira.expected.txt`. tests/all.sh runs it.

## Atlassian's facts it relies on

As Atlassian's own docs and its server's published pages describe the Rovo MCP server, v2:

- **Jira's usual app sign-in (OAuth 2.0 3LO) needs a client secret,** which an open-source app can't keep. Atlassian's
  server for AI tools takes apps with no secret: its resource page
  (`/.well-known/oauth-protected-resource/v2/mcp`) names its sign-in service on auth.atlassian.com. That service lets an
  app register itself (dynamic registration), takes PKCE with S256 only, and allows `none` as a client's way to sign
  in. `http://127.0.0.1` is among the return addresses Atlassian allows by default.
- **The scopes asked for:** Jira's read, search and write through the server (`write:jira:agent-interface`, as a
  session moves its ticket and adds its note there; never delete or manage), `offline_access` to stay signed in, and
  `read:me` and `read:account`, which the list of your sites needs.
- **Refresh tokens rotate:** each refresh gives a new one, and the old one stops working, so the new one is kept each
  time. One unused for 90 days runs out.
- **Tools, by their v2 names.** Listed directly: `getAccessibleAtlassianResources`, `searchJiraIssuesUsingJql`,
  `getJiraIssue`, `transitionJiraIssue`, `addOrEditJiraIssueComment` and `createJiraIssue`. Called through
  `executeRead` (`{name, cloudId, inputs}`): `listJiraIssueTransitions`, `listJiraBoards` and
  `listJiraProjectIssueTypesMetadata` (a project's types, which a new ticket is checked against before it's shown)
  and `getJiraIssueTypeMetaWithFields` (a type's create fields, among them the priority field's allowed values in the
  project's scheme's order, with Jira's ids). Each takes the site as `cloudId`, given as the site's address.
- **A project's priorities, in order:** priority schemes are per project, and only some types' create fields list
  priority (a Task's and a Story's do; a Bug's, an Epic's and a Subtask's have been seen without it, though each holds
  one), so the order is read from the project's Task type (its English name, `untranslatedName` on a site in another
  language), never each ticket's own type; a project with none has no order. The inputs' names (`projectIdOrKey`,
  `issueTypeId`, `maxResults`) and the answer's shapes (`fields` or `results`, each field with its `allowedValues`) are
  as Atlassian's docs give them for Jira's own create fields read.
- **The answers' shapes:** each under `data`: the sites under `resources` (each with its `url` and the `products` it
  has, Jira among them or not), an issue as itself, a search's issues as a list (once under `issues.nodes`, still
  read), the transitions, boards (`values`) and a project's `issueTypes`. A search has given at most five issues a
  page, so it asks for five.
- **An issue is read, and searched, as the server's full view (`view: "full"`).** It is the only view whose answer
  has the priority's id (`priority: {id, name}`), the status category's key (`status.statusCategory.key`), the
  parent (`{id, key, fields: {summary, status, priority, issuetype}}`), the type and project, and a done ticket's
  resolution (`{id, name, description}`). A list of `fields`, which overrides the view, or a smaller view gives the
  priority and the category by their names alone and leaves the parent and the resolution out, whatever it names.
  The description is read as Ticket's `about`, for the session working the ticket alone: text as it comes, in the
  format the answer names (`appliedContentFormat: "markdown"` in the full view), or Atlassian's document format (a
  tree of nodes) as its plain text, cut near 20,000 characters, at a word's end, with a line saying so. It brings up to 20 comments as well, which
  Whozmove doesn't read. Still read, for an answer without them:
  the category by its name (To Do, In Progress, Done), the project from the key, and the type from a search for the
  key. Custom fields come mapped by name under `customFields`, each as `{id, value}`.
- **A move names its step as `transitionId`.** Jira turning a request away comes back as an answer, not an error:
  `{data: {error: "TRANSITION_FAILED", message, problems: [{field, reason}], status}}`, each reason in Jira's own
  words ("Fill in Blocked by first"); its `status` can come as text ("400"). A move answered with a 4xx, once a
  sign-in, an admin, no such ticket and slowing down are ruled out, is turned away as it is (`TrackerEndRefused`),
  with Jira's reasons, or its message, as what the tracker said (`trackerSays`), clipped to 300 characters, and none
  when it said nothing. A 5xx, even with reasons, is one that couldn't be done now. Another tool's own error comes as
  `{error: true, message, statusCode}`. A field a site's rules want filled in before a move, but that isn't on the
  move's screen, can't be given with it.
- **Teamwork Graph's enriched reads use a site's Rovo credits,** so none are used.

## Between the page and the app

None of its own: the tickets module (modules/tickets) shows Jira's tickets, through the Tracker contract, and its
page's messages (signing in, Allow, Copy What to Ask) reach this module through it. Jira's page on the panel's back
goes through the apps module (`card` and `act`), and its notice through the core's notices.

## Rules

- **The sign-in lives in the Keychain only:** the refresh token and client id in one Keychain entry, with the scopes
  that sign-in asked for, the access token in memory, never in a file, a log or anything a session reads. While the
  home folder is a test's, a stand-in file in that home takes the Keychain's place, so a test never touches yours.
- **A sign-in kept that can't be used means signing in again, never a dead end.** Any build signed as Whozmove, or a
  look-alike signed with its identifier, can replace or delete the Keychain entry without macOS asking, though it can't
  make Whozmove read what it put there. So an entry that's gone, or can't be read as a sign-in, stands as signed out,
  with Sign In with Atlassian; and a refresh Atlassian refuses for any reason of its own (a token run out, taken back,
  or not one it gave) stands as run out, with Sign In Again. Only Atlassian not answering, or asking to slow down, is
  tried again later.
- **An entry other apps can read is never used.** Another program can add an entry first that lets every app read it,
  or that names an app other than this one, and a secret put into it would be open to them. So each Sign In clears
  whatever is kept and makes a new entry that names only this build, a refresh updates only an entry this build is
  given without macOS asking (else the new refresh token lives in memory only, and the next start stands as Sign In
  Again), and an entry other apps can read is neither trusted nor read: it stands as Sign In Again, with its reason.
- **macOS's box only ever follows your press.** Builds are signed ad hoc, so macOS gives the entry only to the build
  that kept it: checked on virtual Macs (macOS 15 and 26), a new build, a tool given Whozmove's identifier and
  `security find-generic-password` from a session each get macOS's box, and nothing without it. So nothing reads the
  secret as the app starts, every read but Allow's fails rather than ask, and Allow (on Jira's page, the card's list,
  a ticket's card or the notice) asks once for each new build: Always Allow there lets that build in.
- **A sign-in this build kept is read only as this build's.** Keeping it afresh records, in the entry's attributes,
  which build kept it (that build's own code hash, which isn't secret), and reading that never asks. macOS gives a build
  its own entry without asking, so an entry that says this very build kept it, and that macOS would ask about all the
  same, was changed since by something else: it's never used, nor asked for with Allow, and stands as Sign In Again,
  with its reason. An entry with no build recorded, or another's, is a new build's, which Allow asks for once; what
  Allow is given is kept afresh at once, never asking again, so the entry names this build alone and says it kept it.
- **A move needs the write scope, and a sign-in without it still reads.** A sign-in kept before Whozmove asked to write
  has no scopes kept with it, and one Atlassian refuses a write for its scope (a 403, or its own error naming a scope)
  counts the same until you sign in again. Its reads carry on; a move, a note or a new ticket is never sent, and what
  asked, and Jira's page on the panel's back, say to sign in again, with Sign In Again.
- **Sign in with Atlassian's own page,** in your browser, never a key you paste, and never a page inside the panel.
  The way back is a one-time listener on 127.0.0.1 alone, on a path of its own, checked for the `state` it sent, closed
  after one answer or ten minutes.
- **Only Atlassian's server, over https.** The one exception is a test's stand-in on 127.0.0.1, which only a throwaway
  home can name (`WHOZMOVE_JIRA_SERVER`).
- **A ticket's address is made from its site and key,** never taken from what the server sends.
- **A step that isn't one of the ticket's now is never sent:** the ticket is read again first.
- **A done ticket is dropped by its resolution's English name.** Jira's status categories only say to do, under way or
  done, and a resolution has an id, a name and a description but no category, and its id differs from site to site. So
  a done ticket whose resolution is named Won't Do, Won’t Do, Duplicate, Cannot Reproduce, Declined or Won't Fix counts
  as dropped, and any other name, in another language or a site's own, as done: wrong only by showing a dropped ticket
  as done.
- **Nothing it reads is logged:** panel.log says which tool, and how it ended, never a ticket's words, a note or a token.
  A call that failed says how in Whozmove's own words and numbers (MCP's `MCPHowItFailed`): "no answer in 30s", "no
  connection: …", "HTTP 502", "the server's error -32603", "an answer it couldn't read", "the tool said it failed", or
  Jira's own error by its status ("its own error, 500"), never a word of the answer.

## What it sends, and where

Only to Atlassian (mcp.atlassian.com and auth.atlassian.com), as you, once you've signed in:

- the words you search for on the new conversation card;
- the keys of the tickets you give conversations, to read them, their next steps and their project's boards and
  priorities (its types, then its Task type's create fields, read once an hour a project, and again sooner only for a
  priority not among them, at most once in ten minutes); and, when you give a ticket in a project whose way of opening
  tickets isn't set yet, that ticket's type's create fields, for the fields that take one option, kept an hour;
- a conversation's moves of its ticket, with the note it adds and the fields the step sets, once you press Move It on
  its row or let it with May Move Its Ticket;
- a new ticket a conversation drafted: the project it goes in, to ask what types it takes, as the draft comes; then its
  title, type, description, priority and parent, once you press Create Ticket on its row;
- when a conversation reads your tickets: a search for every ticket you can see on each site (with how many minutes
  back, for what changed), a page at a time, and a ticket's key, to read it with its history;
- signing in: Whozmove's name and its return address on this Mac, to register.

It keeps the sign-in in your Keychain, with the scopes it asked for and which build kept it, and nothing else: each
project's boards, priorities and fields of options are kept in memory only, for an hour.
