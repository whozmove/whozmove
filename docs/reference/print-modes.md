# Print runs

Run with one of these, `Whozmove` prints what the panel would do, for the home folder in `$HOME` or for sample
cases, and quits. The tests compare what they print with recorded copies. Helper runs (`Whozmove --helper-<job>`)
aren't print runs: they're the app's own jobs, which it runs as a process of its own on your real files, described in
[Modules](../how-it-works/modules.md).

- `Whozmove --print-board-card [<project>]` prints Team Board's card on the panel's back for the team with a lead in
  that project (the first, A to Z, without one): `tests/rows.sh` checks its figures are the board's own counts.
- `Whozmove --print-seats <cases.json>` prints who holds a member's seat in its workspace for each sample case (the
  team module's `SeatOf`): the session holding it, the ended one standing for the member while none runs there, the
  one kept as its holder, and each duplicate, and whether it was opened earlier. The team module's tests check it.
- `Whozmove --print-teams` prints each team as a whole, as the team module offers it to the others
  ([team.md](team.md#each-team-as-a-whole)), once the rows have been read for the home folder in `$HOME`: what
  `tests/rows.sh` checks. It reads the team file whatever Working on Whozmove ▸ Show Teams says; with `--switch-off` it
  prints what the team module gives with that switch off instead: no teams and no row with a team, which
  `tests/rows.sh` checks too.
- `Whozmove --print-rows` prints the rows the panel would get for the home folder in `$HOME`, as JSON, and
  quits: what `tests/rows.sh` compares. It never asks GitHub, so PRs show as UNKNOWN there.
  `Whozmove --print-mode-moves` prints, for each terminal session, why keys can't go into it now (or that they
  can) and the Shift+Tabs its mode menu would type; the same test checks them, because a wrong answer types
  into a session at the wrong moment, and a wrong count lands it in another mode. Both read files the whole
  Mac shares (Claude Code's managed settings) from that home folder too, so what they print never depends on
  the Mac they run on. `Whozmove --print-typing`
  prints the keys a command is typed with, through a stand-in terminal, and where typing stops once the
  session moves on or the terminal refuses a key. `Whozmove --print-why-not` prints what each session's model,
  effort and mode menus, its Compact card and its next steps would say about why nothing can go into it now, and
  `Whozmove --print-results <command> <transcript>…` what the panel takes each command's result in a transcript to
  say.
- `Whozmove --print-command-logs` prints how panel.log says each kind of command (a model, effort or mode pick by the
  menu's word, a /compact by its focus's length, never its words), then sends a /compact whose focus holds a made-up
  token to the sample session Compacter in `$HOME`, which nothing can type into, and prints whether the log says why it
  wasn't sent and whether the token reached it. The token is made as it runs and never printed. The commands
  module's tests run it. It writes Whozmove's log in `$HOME`, so it refuses your own.
- `Whozmove --print-desktop-logs` prints how panel.log says what's written in a Claude Desktop conversation's message
  box (a slash command by its first word, anything else as "words", each with its length), and what Claude's window
  shows round it (only Claude's own labels by name, any other name by its length), from sample words holding a
  made-up token, and that the token is in none of it. The Claude Desktop module's tests run it.
- `Whozmove --print-compact-time` prints whether now is a natural break to compact each of its sample sessions, and
  why (the commands module's CompactTime, which the context ring's Compact now and Compact at Breaks both go by), or
  null when it isn't: `tests/rows.sh` checks the breaks, and everything that's never one.
- `Whozmove --print-compact-for-you` prints whether Compact at Breaks would compact each of its sample sessions at a
  break now, or why not, and whether nobody's on it; the compact-at-breaks module's tests check it. It compacts
  nothing.
- `Whozmove --print-kept` prints what would be kept of each terminal session running in `$HOME`, so its row stays once
  it ends, and which of the sessions kept there would be dropped: their process went on to another conversation, or
  they've gone. It writes nothing; `tests/rows.sh` checks it.
- `Whozmove --print-hook-line <seconds>` is the panel's end of the permission hook's line in `$HOME`'s Whozmove
  folder, answering each request "deny", and prints what each connection came to: asked by its session, refused and
  why, answered. The Claude Code module's tests run the real hook against it from inside a stand-in session. It
  changes Whozmove's folder in `$HOME`, so it refuses your own.
- `Whozmove --print-held` prints which of its sample sessions' requests would be held as you answer them in their
  tab, whether they go by themselves (Don't Wait on Me) or wait on you, with you at the Mac and away; `tests/rows.sh`
  checks it.
- `Whozmove --print-dont-wait-files` makes Don't Wait on Me's files in `$HOME`'s Whozmove folder, one for a session
  with the switch's record and one for a session without, then takes away those whose session has no record, as the
  app does as it opens, and prints the files before and after. The Claude Code module's tests check it. It changes
  Whozmove's folder in `$HOME`, so it refuses your own.
- `Whozmove --print-on-top` prints, for sample windows on the screen, whether a terminal's window is on top, no other
  app's normal window above it anywhere on the screen: only then does a press on the row of the session its tab shows
  leave it as it is; `tests/rows.sh` checks it.
- `Whozmove --print-other-apps` prints what each way Whozmove presses, types or sends in another app (its Apple events,
  Accessibility presses and posted keys) gives from a home that isn't your own, and how often panel.log says it did nothing: so a
  test or a print run never drives your apps. Each is aimed at Whozmove itself or at no element, and it refuses your
  own home; `tests/rows.sh` checks it.
- `Whozmove --print-file-reads` prints what a file read every second gives as it's written, rewritten (a new size, or
  only a new date), caught half-written, written whole and taken away, and a file's date: it's read again only once it
  has changed, and nothing is kept while it can't be read; `tests/rows.sh` checks it.
- `Whozmove --print-ticked <step>…` runs each step as one copy of the panel would, against the switches in
  `ticked.json` in Whozmove's folder in `$HOME`, with stand-in switches of its own (three kept while Whozmove runs, two
  kept for a folder): a sample session (`row`, with `in=` its folder), one that may not hold a switch kept for its
  folder (`block`, `unblock`), which session one was ticked in (`held`), the copy starting and reading the file
  (`start`), your press on a switch (`on`, `off`), an answer counted (`count`), the rows listed (`list`), your press on
  Turn Back On (`bring`), why a switch is off (`ask`), what is on and waiting (`show`), the file (`file`), the folder
  made unwritable (`lock`, `unlock`) and the copy ending as a Quit or a restart ends it (`quit`, `restart`). Without
  `start` nothing is written, as in any print run. It refuses your own home; `tests/ticked.sh` checks it.
- `Whozmove --print-attention <events.json>` takes made-up events as Keep App Switches does (the switch ticked,
  an app coming to the front, away and back, a look at a session, the old days taken away) into the home's attention folder, then prints
  each day's file, its mode and its lines. It refuses your own home; the attention module's tests check it.
- `Whozmove --print-held-keys` prints what each saved pick reads as (The Chief, a session, or Off, for a value it
  doesn't know), and when sample holds of each pair of keys Bring Forward offers count, bringing nothing forward; the bring-forward module's tests check it.
- `Whozmove --print-changes <sessionId> <scope>` prints what the changes view would be sent for that session's
  checkout in `$HOME`, one of its tabs: `unstaged`, `staged` or `outgoing`; `tests/rows.sh` checks each on a checkout
  with a file staged and changed again, files git doesn't track, and a commit not on its upstream.
- `Whozmove --print-count-due` prints whether a checkout's changes are due a count for sample states (watched or not,
  what changed, and how long since the last count, the latest change and the first one not counted); the changes
  module's tests check it.
- `Whozmove --print-watched <root>…` tells those checkouts' changes as the app does (CheckoutWatch), runs each
  `<what>\t<command>` line on its standard input, and prints which checkouts each was told for (their files, refs or
  repo); then whether the branches on the lines after `branches` are on a remote, when a git status read is due for
  sample states, how long each checkout is left while nothing in it seems to change (`CheckoutQuietEvery`), and when a
  burst of changes has settled for sample times (`CheckoutSettled`); the git module's tests run it on a throwaway repo.
- `Whozmove --print-pr-wakes <activity.json> <since>` prints what would wake a session waiting on a pull request,
  from gh's answer as the file gives it, for a wait begun at `since` (ISO 8601): the events kept from it, the wakes
  without comments and with them, and what its row says it waits on; the git module's tests run it on a made-up
  answer.
- `Whozmove --print-pr-due` prints, for sample states, whether a checkout's branch can have a pull request of its own
  (the branch and the repo's base branch), and whether it's due its look-up (those, the branch last looked up, and how
  long ago); the git module's tests run it.
- `Whozmove --print-deploys <folder>…` prints the command Deploy would suggest for each folder, the port a deploy
  there gets in $PORT, how its last run went as the page would be told, what a deploy from it would note it starts from now (its commit, and how many files
  aren't committed), and its project's build in place as Deploy keeps it, keeping nothing itself; `Whozmove
  --print-deploy-checks <folder> <command>…` what the set-up card would be told each command really runs there,
  with a short fingerprint of what would be kept as it's confirmed.
  `tests/rows.sh` checks them against sample projects and runs, and the deploy module's tests the build in place in a
  real repo and its worktree.
  `Whozmove --print-builds-up <seconds> <project> <worktree> [<base port> [<pid>]]` really runs Deploy there, waiting up
  to <seconds> for each run: a command confirmed in the main checkout, each checkout's run with its own port in $PORT,
  the ports kept, and the worktree's recipe changed after the card showed it, as a branch could, so it doesn't run, and
  confirming what the card showed before isn't saved, until the card has shown it again; a command confirmed before what
  it runs was kept, which needs confirming once more; and one that runs nothing checked. Given a <base port> after them,
  the first of a block of free ones, it runs stand-in servers too: one in each checkout at once, each up on its own
  $PORT, the later in place; on every address; on a port of its own; on two; one that never listens; one whose program
  isn't installed, with a package.json and no node_modules and then with neither (what its card goes by, its last
  lines with terminal codes and direction marks taken out, and the install its Copy copies and Install First runs
  for each lock file); what Install First's second step shows; Install and Deploy, with a stand-in npm on the PATH of
  the throwaway $HOME's shell, not run while an agent works there, nor once package.json has gained a postinstall
  since the step showed it, and with a stand-in pnpm whose install doesn't go through, which the run says; one that
  ends by itself once up; a press kept while an agent works there, run once it's done, and dropped once the command
  changes, on Don't Deploy, or once its session isn't listed; and one its shell leaves running, which Stop Deploy stops by its pid. Given the pid of a process that started a server on base+7 too, it
  runs the port check before a press: another of Deploy's builds on the port (an older command's, a server's that picks
  its own), with Cancel and Stop It and Deploy, and that server, named, with the session that started it (the pid,
  counted only if it started first), and Use Port; and a session's ask meeting each, the card left waiting for the
  server that picks its own, and the next free port taken and kept for the held one, with what its status says, then the same session asking again while that build is up, which
  restarts it. Last, a command holding a made-up token, which prints it and
  fails, is set on the card, pressed, run as a session asked for it, given in a version too long to save, and
  confirmed with Deploy where macOS refuses the save (a folder in deploy.json's place, the saved file set aside and
  put back), which prints, in its own words, whether panel.log says it wasn't saved and why, and whether anything ran;
  and it prints whether panel.log, and the run's own log, hold the token. It runs from Whozmove's folder in `$HOME`, so it
  refuses your own; the deploy module's tests run it. Where saves made as Deploy makes them are refused there (Claude
  Code's sandbox refuses their temporary copy), it prints `Deploy's saves are refused here: <why>` alone and exits 3.
  `Whozmove --print-deploy-asks <socket> <seconds> [<copy>]` prints, for the sample sessions Asker and Other in
  `$HOME`, what Let It Deploy's menu line says, what the panel answers each ask (for the session's own checkout, or
  another named), what each second's look decides, how long one waits and when the switch ends, then listens at that
  socket for `ask-panel.sh` to ask from inside a session and from outside any. Then a command holding a made-up token,
  which prints it and fails, is confirmed and really run, and Asker asks for status and put-in-place: it prints whether
  each answer, and panel.log, hold the token. The deploy module's tests run it. It changes Whozmove's folder in
  `$HOME`, so it refuses your own, and where Deploy's saves are refused there it says so as `--print-builds-up` does.
  Given nothing else, it only checks that: it prints that line and exits 3, or prints nothing and exits 0.
- `Whozmove --print-jira facts <samples>` prints what Jira's module makes of the made-up samples in that JSON file:
  keys and links read, links made from a site and key, the search each set of words makes, the kind each status
  category counts as, the scopes, the sign-in service's published pages, PKCE's challenge, which sign-in services it
  can use, and its page on the panel's back in each state; `--print-jira answers <folder> <site>` each recorded answer
  in that folder read as a ticket (with its description apart, as only a session is given it), steps, boards, sites, a project's types, its priorities in order with each one's
  place, or an error; `--print-jira talk <site> <steps…>` a whole
  sign-in and each call against a stand-in for Atlassian whose address `WHOZMOVE_JIRA_SERVER` gives (only 127.0.0.1,
  and only in a throwaway home), the run itself following Atlassian's page as your browser would (`every`, every
  ticket you can see, or `every changed`, those changed lately; `whole`, a ticket with its moves); and
  `--print-jira keychain write|open|update|newbuild|rewritten|has|quietly|read|forget` a made-up Keychain entry under
  a service of its own, for a virtual Mac (`write`, `open`, which makes the stand-in's entry one other apps can read,
  `update`, `newbuild`, which makes it one an older build kept, and `rewritten`, one something else changed since this
  build kept it, refuse your own home). Jira's tests run them; the talk refuses your own home.
- `Whozmove --print-kept-waits` prints which made-up kept terminal sessions have gone: 3 days after they last moved,
  or 30 while their row waits on someone else, and at once once their transcript has; the Claude Code module's tests run
  it.
- `Whozmove --print-own-waits` prints whether each sample command a session left running in the background is one of
  Whozmove's own waits through its plugin's ask-panel.sh, which the row leaves off its jobs; the Claude Code module's
  tests run it.
- `Whozmove --print-wakes <steps…>` drives the waits module as the core would, with a made-up source, gear and clock, in
  a throwaway home only: sample sessions (`row`, `newproc`, `closed`, `gone`), what each has to wait on (`has`, readable
  or not, `nothing`), its wait command asking (`ask`, with `now` or `comments`), something coming (`came`, maybe
  `yours`), time passing (`later`, and `sleep`, the Mac asleep), the gear (`gear off`, `gear unpicked`, or its room and
  who's at work), a second's pass (`pass`, and `unread`, one before the rows have been read), the rows' `wait` (`rows`),
  its notices (`notices`), its words for a conversation opened again (`reopen`), its background waits (`words`), what's
  kept (`kept`), a new copy reading it (`relaunch`), the plain functions (`cases`), and whether panel.log says any word
  of what came (`log`, `logged`).
- `Whozmove --print-process <steps…>` drives the process-notes module as the core and the page would, with made-up
  projects (acme-web, a worktree of it, a folder outside git) and a clock of its own, in a throwaway home only: sample
  sessions (`row`, `ended`), a session's `process-draft` with one of its made-up notes (`draft`), your Keep It or Not
  Now on its card (`keep`, `notnow`, and `stale` for a card drawn for a draft gone since), Keep It unable to write
  (`locked`, `unlocked`), time passing (`later`), the rows' `processDraft` (`rows`), a session's way (`way`), what's
  kept (`kept`), a new copy reading it (`relaunch`), the plain functions (`cases`), and whether panel.log says any word
  of a note (`log`, `logged`).
- `Whozmove --print-ticket-routing <repo> <steps…>` drives the ticket routing module as the card and Settings would,
  with a made-up tracker whose tickets have a Team field, in a throwaway home only, against a made-up repo: each
  ticket's Team (`team`), that field given with no options, as one looked up as you type (`lookup`), a way kept for a
  folder that's no project now (`elsewhere`) and Forget It on it (`forget`), the card's ask (`ask`, from a folder given), the guide's Start (`set`), Settings' picks
  (`pick way`, `pick option`) and its page (`settings`), a conversation working a ticket there (`busy`), what's kept
  (`kept`), a new copy reading it (`relaunch`), a file changed by hand (`hand`), the plain match by name (`match`),
  and what panel.log says (`logged`). The ticket routing module's tests.
- `Whozmove --print-tickets <steps…>` drives the tickets module as the core and the page would, with a made-up
  tracker: sample sessions (`row`, `ended`), a start from the card with a ticket (`start`), each ask (`ask`), your Use
  It or Not Now (`press`), the rows' `ticket` (`rows`), a read that ends otherwise (`fails`), what's kept (`kept`), a
  file written by hand (`hand-kept`), a new copy of the panel reading it (`relaunch`), and whether panel.log says any
  ticket's words (`log`, `logged`); and moves: a session's `ticket-move` and `ticket-stop` (`move`, `stop`, with
  `too-long` for a note or why past its length), your Move It or Not Now on its card (`press-move`, with `stale` for a
  card drawn for the move before), May Move Its Ticket turned on or off (`switch`) and its mode menu's line (`menu`),
  the moves waiting on rows (`moves`), a read (`read`), the ticket moved on by someone else (`elsewhere`) or back
  (`afresh`), and what the tracker was asked to take (`took`); and new tickets: a start from Create a ticket
  (`create`), a session's `ticket-draft` (`draft`, with `too-long` for a title past its length), your Create Ticket or
  Not Yet on its card (`press-draft`, with `stale` for a card drawn for the draft before), and the drafts waiting on rows
  (`drafts`), with what the tracker was asked to make in `took`; and a read of your tickets: the folder a session's record names
  (`in`) and the one its process works in, as macOS says (`process-in`), `ask <id> tickets` with `--since` (`now`, a
  minute ago) and `--full`, what the new conversation card says Start in a folder would also do (`reads-said`), a project's choice pressed (`off`, `on`, `pick-reads`), its page (`settings`) and what's
  kept of it (`reading`). The tickets module's tests run it;
  it refuses your own home.
- `Whozmove --print-tasks` prints what One Task makes of sample tasks as they come in (taken, with what's kept, or
  refused and why), of one session's record as tasks are sent, answered, commented on and put back, and which
  answers each kind has; `Whozmove --print-task-asks
  <socket> <seconds>` what the panel answers the sample sessions Asker, Other and Gone in `$HOME` (a task sent, its
  answer asked for, by another session too), that a session's tasks go once its process has ended, then listens at
  that socket for `ask-panel.sh task` and `task-answer --wait` from inside Asker, answering its first task a second
  after it comes. The One Task module's tests run them. The second changes Whozmove's folder in `$HOME`, so it
  refuses your own.
- `Whozmove --print-inbox` prints the inbox's rules over made-up messages: words it refuses, the order a team's lead
  reads them in, the next for a lead and for a fresh one, answered, the line that tells the lead and its id, what
  became of that line joined only from its sender, the week's counts, the ceiling, and what goes once it's old.
  `Whozmove --print-inbox-asks first|fresh|none [<socket> <seconds>]` prints what the panel answers the sample sessions
  Lead, Lead2, Pip, Chief, You and Lone in `$HOME` (a message written, refused, listed, read and answered), with a
  stand-in agent saying what became of their messages, or none, then listens at that socket for `ask-panel.sh message`
  and the lead's asks from inside their processes. The inbox module's tests run them. The second changes Whozmove's
  folder in `$HOME`, so it refuses your own.
- `Whozmove --print-answer-for <seconds> <pid> <pid>` acts as the panel for what a session you allow may answer for
  you, for the sample team in `$HOME` (the session leading it, whose pid is given, its members, a member in another
  project and one of your own, each waiting on a plan or a question its real permission hook asked over its line):
  what its mode menu says, what the panel answers each ask (and another process registered as that session, the second
  pid), then serves `ask-panel.sh` until `answer-for.done` is in Whozmove's folder, and says what came of it. The
  leading session's stand-in program is named in `WHOZMOVE_STAND_IN_CLAUDE`, counted as Claude Code's own. The Claude
  Code module's tests run it. It changes Whozmove's folder in `$HOME`, so it refuses your own.
- `Whozmove --print-switch-holder <programs> <step>…` says which session holds the answer-for switches kept for its
  folder, by what macOS says of each process: stand-in sessions it starts from a folder of stand-in programs, whose
  `claude` is named in `WHOZMOVE_STAND_IN_CLAUDE` (`open`, `close`, with `as=` the program, `at=` where it really runs,
  `bypass`; `orphan`, one whose starting shell has exited; `clear`, a /clear; `pair`, one session's commands starting
  another), the team file's lead (`lead`), your press on the three (`tick`, `untick`), why each is on or off (`why`),
  what's said under the header (`notices`), where the walk up a session's parents stops (`stops`), and the rule alone on
  made-up facts (`rule`). The Claude Code module's tests run it, compared with `switch-holder.expected.txt`. It refuses
  your own home.
- `Whozmove --print-spent <transcript>` prints what a transcript's replies and its sub-agents' (in the folder beside
  it) used today, as the panel counts it for a row's `agent.today`, read whole, a line at a time, and again from its
  start as if rewritten, which must agree; the Claude Code module's tests check it.
- `Whozmove --print-reply <transcript> [<since> <prompt>]…` prints Claude's reply to each prompt sent after `since`
  (ms), as AgentWork's `replyTo:of:since:done:` reads it for words put into a session's prompt, read whole and from
  the file's second line; the Claude Code module's tests check it.
- `Whozmove --print-writing-wait <session> <other session> [--times]` prints whether the first thing a session in
  `$HOME` wrote for you to read comes back for the reader while another session's transcript is still being read from
  its start, as every one is when Whozmove opens (`--times` adds how long each took); the Claude Code module's tests
  check it with a sample note and a long transcript.
- `Whozmove --print-record-how <transcript>` prints, for each line of a sample transcript by its uuid, how Keys is
  told it got there: sent (you sent it, or queued it while Claude worked), read (a tool read or returned it), wrote
  (Claude wrote it, its prompts to sub-agents among them) or nobody; the Claude Code module's tests check it.
- `Whozmove --print-reads <session> <grown folder> <keep folder> <day before> <day>` reads a sample session's
  transcript and its sub-agents' records, keeps what it found in a folder of its own as Whozmove does when it quits,
  lets each file grow by what its copy in the grown folder has past its end, then goes on from what was kept, and
  reads it all from its start too. It prints how much each read, whether the two came to the same, the kept file with
  its shape, why a kept read is read from its start once it or one of its files has changed, and which kept reads a
  prune takes away. It writes in the home folder, so it refuses to run in your own; the Claude Code module's tests
  check it, and fail when what the sample keeps changes without its shape.
- `Whozmove --print-askers <pid>…` prints what the panel answers processes in a sample home that ask in a session's
  name, through the asks' own path with no socket: one running the test's stand-in for Claude Code's program, one
  started from inside it, two whose records name one session, one in a folder its session wasn't seen working in, one
  running another program, one whose record claims a session while that session's own still runs, another program
  started inside a session, and one running as an older Claude Code from npm, run by Node, with its record; then the
  rule for what a process runs (`ClaudeProgramFrom`) on made-up facts, and the short names Claude Code's process may
  have; then what macOS's signature says of two of them; last, the rule for who speaks for a session alone
  (`WhyNotSpeakFrom`), on made-up facts. The stand-in counts as Claude Code's program by its path
  (`WHOZMOVE_STAND_IN_CLAUDE`, parted by colons), in a print run only. It refuses your own home; the Claude Code
  module's tests check it.
- `Whozmove --print-program <pid>…` prints what each process runs, as the asks take it: Claude Code's own build
  signed by Anthropic, an older Claude Code from npm, run by Node, or neither. The real Claude Code run checks it
  (real.sh).
- `Whozmove --print-aside` prints a question asked on a session's side, running nothing of Claude Code's: the command
  and the words it runs, the sessions it may be asked of (only one whose id is a UUID), the model and program it's asked
  with, how each ending of its output is read, the steps it says as it answers, which versions of Claude Code are asked
  for its thinking's summaries, what its checker (`--helper-aside-check`) lets it read and run in a sample folder, when
  a follow-up goes into the open copy and what a fresh copy is told, a kept conversation with a stand-in that answers
  each line it's sent, a question asked of stand-ins for Claude Code that take or turn down the summaries' flag, and its
  process kept out of what's read from Claude Code's registry while it runs. It writes in the home folder, so it refuses
  to run in your own; the Claude Code module's tests check it. With `--steps <file> <folder>`, it prints only the step
  each tool call in the file says, which the same tests hold beside the session's own hook's words.
- `Whozmove --print-usage <file>…` prints what the usage card would take from each file as Claude Code's answer to
  the usage request, or as `claude auth status`'s, what an answer with no plan's numbers becomes beside that auth
  status (`noPlan`, without and with a key in your shell), and where `claude` is looked for (`$USAGE_PATH` as the PATH);
  `tests/rows.sh` checks it against recorded answers. The print modes never run your `claude` (the agent's
  `askUsage` and `connect:before:from:` answer nothing in a print run).
- `Whozmove --print-usage-checks <cases.json>` prints when the usage card's check would ask, second by second over
  each sample stretch of time (you away, a session at work, asking failing, a window resetting, Sign in), through the
  same functions the app runs, then which answers leave a card, and room kept under the panel for it; the usage
  module's tests check it. `Whozmove --print-usage-kept <usage.json>` prints
  what's kept of that answer in `usage-last.json`; it changes Whozmove's folder in `$HOME`, so it refuses your own.
  `Whozmove --print-usage-said <answers.json>` prints what panel.log says as each answer of each run comes, from a
  fresh start, without the lines' times: with the card hidden, why, once each time the reason changes; it writes
  panel.log in `$HOME`, so it refuses your own. The usage module's tests check both.
- `Whozmove --print-gear <cases.json>` prints, for each case, what the gear's plain functions (modules/usage/app/Gear.m)
  make of it: which rows count as working and which are over the gear, what reads add up, what kept answers measure
  (the recommendation, why not yet, the forecast), the gear a press on a seat sets, which answers are kept, `gear.json`
  as written with its mode, how many a lead may have working by a sample `gear.json` (none for no file, never no
  limit), and what the gear keeps in the preferences and its files before and after it's turned off, with the off
  record it leaves (in a bare build's own preferences, "Whozmove", never the app's); it writes Whozmove's folder in `$HOME`, so it
  refuses your own. The usage module's tests check
  it.
- `Whozmove --print-sign-in` prints what the usage card's Sign in says with no terminal on this Mac, naming the
  terminals Whozmove opens (each terminal module the app has, in its order), then for none, one and two sample names,
  and a sample reason with the command to run yourself; the usage module's tests check it.
- `Whozmove --print-plugin-install [--answer <press>] [--before] <hooks>` puts the hooks in a folder into Claude Code
  as the app does as it opens, with `claude` looked for on `$INSTALL_PATH` first, and prints what it reached; the
  Claude Code module's tests run it with a stand-in `claude`. `Whozmove --print-install <case>…` prints what the app
  does as it opens in each of the install module's sample cases, with stand-ins for where it runs from, the agent,
  Apple's developer tools, macOS's installer for them and launchctl, and the login item it writes; that module's tests
  check it. Both change Whozmove's folder in `$HOME` (and the second the login item there), so they refuse to run in
  your own home folder: give them a throwaway one, as their tests do.
  `Whozmove --print-install-cards` prints every card the install module puts on the panel's back, for each state.
  `Whozmove --print-updates <case>…` prints what the install module finds of a newer version in each sample case: a
  Homebrew receipt and its tap's cask, Homebrew's copy and GitHub's (from the case, never asked), and look by look
  through `Updates` itself; it writes in Whozmove's folder in `$HOME`, so it refuses your own home folder too.
- `Whozmove --print-browsing <folder>` prints where each kind of address goes from sample setups of a `Browser` (the
  web, a site with its links out, the folder's pages with and without the web's parts), which folders a page can be
  shown from, the store each sample name's sign-ins are kept in, and how a Browser introduces itself; tests/browser.sh
  checks it.
- `Whozmove --print-edges` prints what the panel's edge does with sample panels and screens: the side the icons at
  its edge are on, where the panel folds round Whozmove beside it, whether a two-finger swipe is the panel's and flicks
  it off the screen's edge, where a flicked panel goes and how much of it shows on its way, how far a swipe on
  Whozmove there pulls it back out, whether it then comes back, and how far it pushes Whozmove in, which way what comes
  out of the folded cat goes, the room the window takes in for it, and where that takes a click, and the room the
  window asks for to turn over, where macOS keeps it at the top of the screen and how far that moves it, and how
  tall the header and the list may get on a screen and the open panel where it is, with room kept for what hangs below
  it; tests/edges.sh checks it.
- `Whozmove --print-edit-keys` prints the edit each sample key does in a web view being typed in (⌘V pastes, and so
  on), and that none does while nothing in it has the keyboard; tests/keys.sh checks it.
- `Whozmove --print-talking <file>…` prints why each sample recording counts as talking to an agent, or doesn't: from
  its process, what was in front as it began, and the sessions listed; tests/rows.sh checks it.
- `Whozmove --print-apps` prints the apps every module lists for the panel's back, in their order, each with what it
  says, its permission, its switches and its groups (those other modules add among them), and `Whozmove
  --print-settings` Settings' rows, the panel's own and each module's, in their order. `Whozmove --print-app-page` prints
  what the back is sent for a made-up tool's page with groups (one of them another module's) and a row in Settings
  opening it, then what each press makes of it: a choice picked, one on a page a row opens, ones that can't be, the tool turned off, a time picked
  from each end's menu, and Use the Recommended Settings; what each end's menu of times offers; and a time as two
  places write it. The apps module's tests check all three.
- `Whozmove --print-sessions <stand-in Trash> [--helper <program>] [trash|undo|putback <id>…|tick]` prints Sessions
  for the home folder in `$HOME`, as the back's page would show it, after that press when one is given (with each
  row's steps, for trash), moving files into the stand-in Trash folder rather than macOS's own (your account's
  whatever `HOME` says), by `program` in place of the helper run when given; `tick` ticks it as the app would until it
  looks for files Finder put back. It changes Whozmove's folder and Claude Code's in `$HOME`, so it refuses your own
  home folder. The sessions module's tests check it against a sample home.
- `Whozmove --print-disk <file>…` prints what would be said of each sample disk (its size, free space, hourly samples
  and the low-disk line's last ×): whether the line shows, its words, how soon it's full, and Storage's card on the
  back; `Whozmove --print-map [<busy.json>]` the map of the folder in `$HOME`, measured as the map measures your home
  folder, each part with what keeps it from going to the Trash, given the folders agents are at work in; and
  `Whozmove --print-cleanup [<busy.json> [<checkout>…]]` Clean up's list for it, given the checkouts the sessions are in
  too, without asking any tool anything; `Whozmove --print-cleanup-usual [<busy.json>]` the list as the first pass alone
  gives it, before the first map: the usual places only; and `Whozmove --print-cleanup-clean <stand-in Trash>
  <busy.json> [--stale] <id>…` what cleaning those does, step by step and at the end, moving into the stand-in folder
  rather than macOS's Trash (your account's whatever `HOME` says) and running no tool: it moves files in `$HOME`, so it
  refuses your own home folder. With `cleanable` in a sample disk, `--print-disk` says the line's second part as it is
  once Storage is on. The storage module's tests check all of them, against sample homes.
- `Whozmove --print-notices` prints what the notifications module keeps for you, for sample cases: what a × puts away
  and until when (what makes a notice new changing, or its time away passing), a page sender's notice put away, and
  when it's quiet hours, by the time of day. It changes nothing on disk; the notifications module's tests check it.
- `Whozmove --print-keys [--full-disk-access] [--keep-every <n> --stop-after <n>] <betterleaks> [<checkout>…]` prints
  what Keys' look finds in the home folder in `$HOME` and those checkouts, with that Betterleaks (`--full-disk-access`:
  Downloads too), as the page would be shown it as each place is read, and how many AI tools' records it read; with
  `--stop-after`, it stops once it has read and kept that many records (kept every `--keep-every`), as a restart
  would, and says so. And
  `Whozmove --print-keys-act private|trash|ignore|replaced|undo <id> [<place> [<busy folder>…]]` does one of a found
  key's actions, or one of its place's; both write in Whozmove's folder in `$HOME`, so they refuse your own home
  folder. The storage module's tests (`keys.sh`) check them against a sample home whose keys are made up as they
  run.
- `Whozmove --print-starts` prints what sample starts would run (a terminal tab's command, Claude Desktop's link), and
  `Whozmove --print-trust [--trust <folder>] <folder>…` whether Claude may work in each folder, as the state file in
  `$HOME` says, recording your yes for one first with `--trust`. The starts module's tests check the first, and
  `tests/rows.sh` the second, against its sample home. `Whozmove --print-worktrees [--make] <folder> <name>…` says
  whether a worktree of the folder's repo can take each name, where it would go and what it would start from, and
  with `--make` makes each; the starts module's tests run it against a sample repo.
