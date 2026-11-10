# Changelog

## Unreleased

### Installing and setting up

- **Needs macOS 15 or later.** On macOS 12 to 14, 0.2.0 is the last version: keep the one you have, or download it
  from its release on GitHub. Homebrew won't install a newer one there, and the × on 0.2.0's line saying one is out
  puts that version away. Built from source on an older Mac, `./build.sh` says so and changes nothing.

### The panel

- **One view for everyone.** The list is always grouped by project, the projects A to Z, each with its conversations
  newest first; nothing is lifted for waiting on you, as its bubble, its dot and the count beside the pawn say so. A
  group's header says only its name. Settings has no Session List choice any more: Newest First and Group by
  Project, which it offered, are this one view, and a team's groups come first in it (below). Folded, a project hides
  all its rows, even those waiting on you, and its header says how many wait on you ("shop › 2 wait on you"), as a
  team's group does; a request still comes out beside the folded panel, and a conversation you start there opens it.
- **Every row says one thing under its name.** Rows are short: the name, the tag for what it wrote, the ticket it works
  on or what it looks after, the job's track and the time, then the bubble when something waits on you, else a request's
  card, else Claude's line only where nothing else says it (what it asks with no card, or a reply you haven't read). A
  stopped session says "Stopped · press to carry on" there, and one started before Whozmove's update offers Reload. A
  chat beside the folded panel shows its row whole.
- **The row you're on keeps its tools.** The session in front in its app keeps, under its short lines, its pull
  requests, what isn't committed and its next steps, then its model, effort and mode, its context ring, how compacting
  at a break last went, where it runs and Deploy; as you move to another session, its row opens out and the one you left
  goes short.
- **A job's track is one bar.** However many steps a job or its board has, its track is the same short bar: what's
  done, then the step it's on, never thinner than a dot, and as it moves on, the bar cross-fades; VoiceOver says "Step
  4 of 6, Your try". A job of one step has none, here, on Team Board and in One Task, which draw the same bar.
- **A chief's line says what waits in one number.** "● 3 need you · 2 moving", the dot as pressing as the most pressing
  of them; the bubbles below say which. A team member's bubble is in its own words, never marked as passed on.
- **A ticket starts in a worktree of its own.** A ticket picked on the new conversation card starts in a worktree
  named after its key, or goes to the conversation already working it; the first ticket in a project asks how its
  tickets should open, a warning shows where another ticket's conversation works, and Settings ▸ Tickets changes a
  project's way, showing what changes first.
- **A job's priority reads Critical, P0, P1 or P2.** On a team's rows, on Team Board and in One Task, a job's
  priority is one of the four, Critical and P0 in the colour of something to do now and P2
  drawn quieter, and Team Board shows it on every job it lists, a Critical or P0 job waiting on you in that colour
  too.
- **Every ask is a bubble, with one button.** What a row asks of you (a team member's job, the chief's next) sits in a
  bubble in the colour of how pressing it is, red for Critical and P0, amber for P1 and
  grey for P2, a team's job named by its priority first ("P1 Try the search box"). At its end is the one button that
  does what it asks: Deploy for a try, the plan's mark for a plan, the prototype's for looks to pick, Copy for a
  command to run, ? for a question, an eye for something to look at, ↗ for something to do elsewhere. While it waits,
  the row shows no other Deploy or context ring, on every row and beside the folded panel; a running server's address
  stays on the bottom line, where you can still press it.
- **A team member's other job waiting on you is its ask.** While a member works on one job and another of its jobs
  waits on your try or your yes, that one is the bubble on its row, named by its priority, with its one button
  (Deploy for a try), rather than a quiet line under it; the track still shows the job it's working on.
- **A plan waiting is its row's bubble, and Approve is beside the list.** A plan Claude waits on shows on its row as a
  bubble, "Plan" and the plan's title (a team member's, its job's own bubble, or its other job's, only to read while
  its session works), ending in the plan button, its one shape on the row: no plan card, and where another ask has the
  row's line, the plan's tag opens it. Press it, and the plan opens beside the list with Approve, Send back…, Stop and
  Take me there. Approve approves the plan as it's shown, only by your press, saying it approves the whole plan,
  folded parts too, while it's read folded; a new version asked for shows in its place, and the bar says why where it
  can't: its file changed since, too long to show whole, or a session that might bypass permissions. A plan Claude
  still waits on in its session after it stopped asking in the panel (an hour on, or once Whozmove restarts) opens
  beside the list too: while Claude Code's own prompt for it is up, it's answered there; with the session idle at its
  prompt, Send back… types your notes in as a message, saying how it went. A look's prototype button opens the
  prototype beside the list too.
- **A session waiting on a review carries on by itself.** A session whose next step is someone else's (a review of its
  pull request, an approval, a merge) waits without holding a seat, its row saying what it waits on ("Waits on #12"),
  and carries on by itself when that comes, as your gear has room. Only someone who can change the repo wakes it.
- **A session closed while it waits shows Resume.** Its grey row stays, saying what it waits on, for as long as it
  waits; once something comes, it's your move, with Resume, and one press opens it again and carries on with what came.
- **↗ marks what takes you out of the panel.** Take Me There, in One Task and on a row's note, ends in a box with an
  arrow out of its corner.
- **The panel leaves room for the usage card.** The panel ends high enough for the usage card under it to open whole,
  rather than running to the screen's bottom, unless it's dragged so low that only its header, the lines under it and a
  row fit.
- **Compact at Breaks.** Turn it on in Settings, and a long conversation in Ghostty or iTerm2 is compacted for you at a
  natural break while it sits at its prompt, never while Claude works or asks; its row says so until its next message.
- **Compact now waits for a natural break.** The context ring says it when a session's work has just been saved, when
  it's nearly full, or when you've been away from it for an hour, and no longer for a long conversation alone.
- **Side chat.** Talk with a session beside the list while it works: press the bar at its row's far edge, which swells
  a little as you point at it, there too while it waits on your answer to a request, a question or a plan, and your
  words reach it between its steps, with nothing typed, so it can change course; its replies come back there. **Ask
  Without Interrupting** asks a question the session never sees: a copy of its conversation answers it in the chat while
  the session works on, showing each step it takes as it goes, reading the project's files and git in its folder if it
  needs to but never opening a file where keys are kept, changing nothing and saving nothing, and a follow-up remembers
  your earlier side questions until the session compacts. **Add to Message** passes the answer on in your own words.
  Send says when your words go in: **Send After This Step**, **Send After Its Turn** or **Send After You Answer**. The
  one you pressed last is the dark button, and Return goes that way until you press the other; ⌥Return goes the other
  way. While the session works, the chat ends with what it's doing right now, as its row says it, until its reply takes
  that line's place.
- **Up next beside the list, while a session is your team's chief:** every session working now and what waits behind
  your gear, in the chief's order, by goal, from **Up next** at the end of the chief's line. It needs **Show Teams**
  ticked in Working on Whozmove ▸.
- **Show Conversation Text.** Turn it off in Settings, and rows show no one's words: not yours, not what another
  session sent, not Claude's replies or what it's working on. Each row keeps its name, its dot, its time and its
  buttons, and what needs you stays: a request or a question with its card, what you just answered, a task's line
  saying what to do, and compacting. In the list, and on the chats beside the folded panel.
- **The line under a head shows only while something scrolls under it.** Under the header, the folded panel's head,
  the panel's back and the page beside the list, the thin line is there only while what's under it is scrolled, and
  always under the lowest thing that stays put: the setup line, notifications' line or a new conversation's card when
  they show, or One Task's strip.
- **Flows drawn in plans and notes.** A flow diagram Claude writes (a ` ```mermaid ` block) shows as a drawing in the
  panel's own colours, with **Diagram** and **As written** above it: arrows that jump over steps go round them, arrows
  can have heads, crosses or circles at either end, and words on arrows get room of their own. Another kind of diagram
  shows as written, saying why. A plan's flow sits small on its At a glance card and opens its section when pressed,
  and a section that's only a diagram says what it shows. (docs/using/plans.md)
- **Plans at a glance.** A plan opens on a short view that tells the whole plan: what changes for you, what you decide
  with Claude's pick and why, what could go wrong, what you'll try, what it keeps or sends, and what's left out, with
  the rest folded by section under it (the short view's own block too, open, when the card can't show every line of
  it: "At a glance, as written"),
  or, with **Full version of the plan**, the plan exactly as written; a task in One Task about a plan shows its
  card too. Pick another option and the plan goes back with your picks. Claude writes the short view
  itself, asked by Whozmove's skill; for a plan without one, Whozmove reads only the headings that match, and nothing is
  summarised by an AI.
- **A row's details open inside the row.** Rest the pointer a moment on a pull request, a row's numbers, where it
  runs, "Open twice", Create PR or a job's track, and its details open under the row's own lines,
  the rows below moving down to make room, instead of a card over the list. Near the panel's foot, the list scrolls
  just enough to show them. They fold away as you move on, and the rows under the pointer stay where they are. Pressing
  Create PR, or "+2 more open" under a row's pull requests, opens its details rather than the session; "+2 more open"
  lists the rest, each opening on GitHub. "Open twice" is said in words on its row, beside its icon.
- **One Task.** Beside the list, the one task a session has handed you that needs you most, in one shape whatever the
  project, its head saying whom it's from and where (a worktree on its chip, or the branch): its title, the step it's
  at, one line on why, then a few slim lines and its answers to pick from: Works, Approve, Done or a question's own
  choices, and last of all Comment, its box on its line, for anything you'd say in words. Answer sends it. Tasks come
  in the order of the tickets their sessions work on, by each ticket's priority in its tracker's own order (Jira's
  Highest first, or Blocker on a site that names its priorities that way), first come first served within it, with
  those that have no ticket after, and the head says each one's priority ("From Wren · Highest"); a chief's pick for a
  member with no ticket takes its job's place in the chief's queue. A plan
  comes cut to its points ("Approve these 7 points") or its phases, a change to try says what changed, what to do and
  what to look for, a file it attached opens in the reader, Take Me There goes to the session a chief's task is about,
  and on a long task Answer stays at the foot while it'd be out of sight. A task you've seen stays until you leave it,
  even when its session rewords it, you close One Task or Whozmove restarts, and one that ends while you're on it says
  so: one to do now, in the top half of its tracker's list, asks from a strip under One Task's head, with Go
  ("Highest from Wren: Fix the login crash"), and answering it brings you back to the task
  you were on exactly as you left it, or, if it was updated meanwhile, says so, keeping your words. Its own page under
  Tools sets how it works: who may hand you tasks, a line on why each is where it is, and the talk.
  A session's own request for your OK, its question or its plan stays on its row in the list only. A session's task
  also shows on its row, as a short line in a bubble coloured by its ticket's priority, red for one to do now, amber,
  and grey for its tracker's lowest; press it to open One Task at that task.
- **Talk with the agent in One Task.** Under a task, ask the session that sent it what it's about or what to press:
  your words go into its prompt once it's free, and its reply shows under the task, all of it, with a command or code
  in it on a line of its own and a Copy button beside it. For a team chief's pick, your words go to the member it's
  for, opened with a line naming the chief and the step, never the chief's own words.
- **Stop near an edge, and the row goes the rest of the way.** Stop scrolling with the row you're on close to the top
  or bottom edge it's heading for, and once your scroll has come to rest the list goes on the last bit by itself, so
  the row clicks onto the edge. Scroll it away from an edge and it stays where you leave it; scrolling again takes over
  at once.
- **The list fills the panel.** With a session's page or One Task open beside it, or whenever the panel is taller than
  its rows need, the list fills it down to the strips at its foot, so there's no empty room under it while there are
  conversations to scroll to.
- **Esc closes the page beside the list.** Click in a session's page or One Task, and Esc folds the panel back to the
  list, as its ✕ does, and your typing goes back to the app you were in. Opening it still leaves your typing where it
  was, and until you click into one of its boxes only Esc acts there, so typing meant for another app presses nothing
  in it. In a box with words typed in it, Esc leaves the box and keeps them, and the next Esc closes it; on a request
  you've clicked, the first Esc gives its keys back.
- **Swipe the panel back from the screen's edge.** With the panel flicked away, a sideways two-finger swipe on
  Whozmove, peeking out at the edge, toward the middle of the screen pulls the panel back out with your fingers: let go
  once it's a third of the way out, or flick it, and it goes back where it was, as fast as you swiped. Swiped toward the
  edge, Whozmove gives a little, harder the further you go, and springs back out. Only Whozmove gets the swipe, never
  the app under it.
- **Settings on the panel's back.** Turned over, the panel's back has a **Settings** app first among your apps, and
  **Settings…** in the pawn menu turns the panel over straight to it. It's laid out as a phone's: each row with its
  coloured tile, its name and what it's set to. **Appearance** shows Grey, Black (White on a light panel) and Glass as
  small panels to pick from, then Match the Mac, Light or Dark, and the panel changes as you pick. **Open Files With**
  has the editors on your Mac with their icons (or, with none of them there, **Get Visual Studio Code**, as the changes
  view's Open in Editor offers too), and **New Conversation with ⌃⌥N** its switch, and ‹ goes back a page. On your apps,
  ‹ turns the panel back to the list, the other way round
  from rows, as if you'd pressed that edge in. The pawn menu now keeps what you need while the panel is hidden, folded
  or off the screen: New Conversation, Show / Hide Panel, Reset Position, Settings…, Open at Login and Quit. Look ▸,
  the list's order, Open With and Use ⌃⌥N in Any App have moved to Settings, each keeping what you'd picked.
- **Sessions, to clear old conversations away.** Each terminal's page and Claude's on the panel's back has
  **Sessions**, every Claude Code conversation on this Mac, wherever it ran, by project. Tick some (or **Tick All
  Ended**) and **Move to Trash**: each goes to the Trash on its own, ended first if it's still open, with **Undo**, and
  **Put Back** from **In the Trash** or Finder. One that's working or waiting on you says so, with **Take me there**,
  and one Claude Desktop keeps is deleted there, with **Open in Claude Desktop**.
- **A team's groups on top.** When a session leading a team of other sessions for you keeps a team file
  (docs/using/the-list.md#with-a-team), the team's groups come first in the list, above the projects. The team file is
  read only while **Show Teams** is ticked in Working on Whozmove ▸ (shown while ⌥ is held as the pawn menu opens). Its
  rows are short, as every row is: a line with its name, what it looks after, its job's steps as a short track and its
  time, and, when it has a job, a line under it saying what it needs you for, with the one button for it at its end, or
  else, quietly, where its job stands: "Up next: after the search box", "On hold", "Moving", or the step a job waits its
  turn at, with nobody working on it ("Ready to try"). Its dot says whose move it is, as on every row. The session
  leading it sits on top, marked Chief, with how many jobs wait on you and how many are at work (never one waiting its
  turn), each only when there are some, and, when it names one, the next thing for you to look at in a few words, the
  whole of it when you point at the row; under it a group for each name the file gives its members (Reviewers, say) and
  the team, each group folding to its header, which then says how many of its rows wait on you; the file's order can
  name Team to put it among its groups. Your own sessions stay under their projects. When the file names the session you
  talk to apart from the one leading the team, that session sits on top, marked Chief, with Up next at its end, and the
  one leading the team right under it, with no mark, or in a group the file gives it. A member shows under the name the
  file gives it to show, marked with the tag the file gives it ("Design"), as the one leading the team can be. In each
  group, as in every project, the newest message comes first. What needs you comes out beside the folded panel, saying
  what's new, the reply or what it asks, under a member's name in the team. A member's reply to a message from the chief
  went to that session, not to you, so it never counts as waiting on you; a question it asks you itself, or a reply to
  you you hadn't read yet, still does. Nor does any reply in a conversation once it has ended in a team member's folder:
  the member's own row stands for it, and Sessions on the panel's back doesn't count it as a reply you haven't read. A
  member is its workspace: a conversation you clear there, or a new one you open there, is that member, by its name,
  with its job, and Take Me There on the Team Board opens it while it runs, never a duplicate; a second session running
  there says it's a duplicate of the member ("Duplicate of Wren"), with a line to close the previous session. Closing a
  member's tab keeps its row where it was, shown as ended, and pressing it, or Take Me There, carries that conversation
  on. A member at work on one job shows that job and the step it's at, while another of its jobs waiting on your try is
  said quietly under it ("Also waiting on you: Try the search box").
- **One look for the panel's controls.** Buttons, the ×, tags, boxes to tick, short lists, labels in capitals and bars
  now look the same wherever they are, on the list, its cards, the reader, the panel's back, Storage, Spotify's strip
  and the new conversation card: a card's title is 12pt, something you can't press yet fades to the same 40%, and a
  pick of one is a round pick with a dot. A row's numbers have details built like the others, with "Not committed"
  and the checkout over the numbers.
- **A hand over what you can press.** The pointer turns into a hand over anything in the panel you can press, and into
  a text cursor over text you can select or type in, while the app you're typing in stays in front. Before, it stayed
  an arrow everywhere.
- **One line under the header for what needs you, most urgent first.** What Whozmove has to tell you shows one at a
  time, with the one button it asks you to press, and urgent words in red. When more are waiting, **+1** before the ×
  steps through them; × keeps one away until what it says changes, and the next comes in. A line that says all went
  well goes by itself once you've had it in sight for 4 seconds, and while you type in the panel only something urgent
  comes onto it. What you've put away stays away across restarts.
- **Quiet hours.** On One Task's page under Tools, once you turn them on, from 22:00 to 08:00 unless you change it,
  only what's urgent is said: under the header, beside the folded panel and beside the panel at the screen's edge.
  The rest isn't lost; it's said in the morning. What answers something you just did is said all the same.
- **Conversations beside the folded panel take their turn.** A request, a question, a plan or a reply you haven't read
  comes out beside the folded panel after those already out, in the order they came, and once three are out the next
  waits its turn, counted in the pill under them. Before, the newest came out nearest the panel and sent the oldest of
  three back in, so a newer one took the place of one you were reading. A request comes out even while its session's
  tab is in front, and goes once you've answered it there. Being in a session's tab stops the conversations' time
  beside the folded panel only when pressing its conversation, or its row, took you there, until you leave that tab.
- **Answer what comes out beside the folded panel with its keys.** Click a request or a question there and its keys
  work on it as they do on the list: Return allows once, 1 to 9 pick an option, and Esc gives them back. It stays out
  while they're yours. Before, it could only be answered with its buttons.
- **The time left on a conversation beside the folded panel** is now a thin ring round its ×, full as it comes out
  and emptying as its time runs out, instead of a line along its foot.
- **A stopped session says so.** The grey row of a terminal session whose Claude has ended, or of a Claude Desktop
  conversation Claude isn't running, now says **Stopped · press to carry on** under what it last said, after any pull
  requests, and pointed at, "Stopped: click to carry it on in Ghostty" (or in Claude). Pressing the row carries the
  conversation on, as before.

### Answering and steering sessions

- **Keep how a project works, beside its own pages.** When a session learns something a project's CONTRIBUTING,
  CLAUDE.md or AGENTS.md, pull request template or docs don't say (what you told it, or what it found the hard way), its
  row asks **Keep this as how acme-web works?**, with the note whole as numbered steps, each saying where it came from.
  Only **Keep It** keeps it, on this Mac, for the project and every worktree of it. A note drafted again is shown
  against the one kept, each step new or taken out marked, so Keep It keeps exactly what you see; after **Not Now**, the
  same lines don't ask again. Whozmove's plugin carries a skill that says what a note holds and what never goes in one.
- **Give a conversation a Jira ticket.** Sign in with Atlassian once, on Atlassian's own page in your browser, from
  Jira's page on the panel's back or the new conversation card. The card's **Ticket** chip then finds a ticket as you
  type (words, its key or its link), or takes a ticket's link pasted into your words, and Start gives the new
  conversation that ticket. Its row shows the ticket's key and where it stands after its name, in red with what to do
  when it can't be read ("sign in again"); pointing at it shows what it's part of when Jira says, its project and boards
  and where it can go next, and pressing it opens it in your browser. A conversation that asks for another ticket gets
  it only once you press **Use It** on its row, which says what the ticket is. Whozmove's plugin carries a skill that
  says how to work a ticket by its own next steps, stopping at a step that's a person's. The conversation reads the
  ticket's description with it (a very long one cut short, the rest on the ticket's page), and only that conversation
  does: it's never shown on the panel, kept or logged.

- **A conversation moves its Jira ticket at its milestones.** Its row asks "Move PAY-142 to In Review?" with the note
  it adds and every field the step sets, for **Move It** or **Not Now**, and **May Move Its Ticket**, at the foot of its
  mode menu, lets it move without asking. When Jira turns a move away, the row says what Jira said ("Fill in Blocked
  by first"), with **Open in Jira** to put it right there. A step that's a person's, such as QA's sign-off, is marked
  on the ticket's card, and the card says the ticket's last move.

- **Create a Jira ticket, talked through first.** Pick **Create a ticket** on the new conversation card's Ticket chip,
  write a line and Start: Claude asks what it needs, then its row asks "Create this ticket?" with the title, project,
  type, priority and whole description, for **Create Ticket** or **Not Yet**. Nothing is made in Jira before your press,
  and the conversation then works on the new ticket.

- **What runs in the background, round the dot.** A small mark goes round a session's dot for each job it runs in the
  background, an agent or a command left running, and a line under Claude's says what they are ("Running npm run
  dev"). When Claude replies but agents it started are still at work there, the session takes your messages at once,
  but its reply isn't counted as your move until they're done and Claude replies again. Meanwhile Deploy and the next
  steps wait for them, as they wait for an agent at work, and say which one they wait for, with `/tasks` to type in
  the session to stop it sooner. A command left running, such as a dev server, holds none of this, but Storage keeps
  off a checkout while anything runs there in the background.

- **Don't Wait on Me**, at the foot of a terminal session's mode menu: a question or a request for your OK that no one
  answers in 5 minutes goes, and Claude carries on with what doesn't need it and asks again later. Its row says when it
  goes; it waits while you're answering it, on the row or in the session's tab, and a plan never goes.
- **Let It Deploy**, at the foot of a session's mode menu once Deploy is set up for its project: that session can ask
  the panel to run your project's Deploy command, from its own checkout, with Whozmove's `ask-panel.sh put-in-place`.
  It runs as your press of Deploy would, once no other agent is at work there and you've stepped off the panel,
  without waiting for the asking session's turn to end, and restarts a build of that checkout that's up; the row says who asked and what it waits for, then who it was
  deployed by. It ends with the session, or once the command changes, and Deploy's ▾ says which of its checkout's
  sessions may ask, with Not This Time for one waiting. Like Deploy's command, what you've allowed is kept in
  Whozmove's folder, where any program running as you could change it.
- **A request comes into view by itself.** When a session asks for your OK, a question's answer or a plan's, the list
  scrolls until its whole card shows, a newer one taking the place of one before it. While you're answering a card, or
  your pointer is on the panel, the list stays put, and once you scroll it yourself, it stays where you put it. Whenever
  a request waits wholly out of view, a solid strip slides up at the list's edge it's beyond (top, bottom, or both),
  naming the one nearest that edge and what it asks, "after this" while you answer, and slides back away as soon as any
  of its row is in view or it's answered; pressing it takes you there. A request never shows twice; it and the row
  you're on, held at the same edge, keep the list's order. Once you've answered, the list goes to the one waiting
  longest, and the card you're on stays still as rows move round it.
- **A card for each kind of request.** Claude's line on the row says what it wants ("Wants to edit total.ts"), and the
  card leads with what it's for: a command with Claude's reason, "Outside the sandbox" in red where it applies, then the
  command; an edit with its file, folder and how many lines change, one edit at a time with ‹ › for a change in 3 or
  more; a file read or a web search on one line; a page with what Claude wants to learn from it. A question with one
  pick is answered with one press, or its number key; several picks are boxes to tick; Type an answer becomes a box in
  its own row, and Esc keeps what you typed; several questions come one at a time, with ‹ ›, Skip and Next, ← and →
  moving between them, and Submit on the last with your other answers above it; a number has − and +. Every card that
  needs you, Compact, Deploy's set-up and "Switch model?" (now Keep or Switch) among them, is raised a step from the
  panel with no red edge. Its title is never cut short; a command shows wrapped, every line whole, its first 4 with Show
  all past them; other code sits on it a line at a time, fading where it's cut, with Show all. Once you answer, a line
  says so where the card was; beside the folded panel the card just goes, Claude's line saying what you answered and the
  dot turning to the working one, so the conversation shrinks once, and the line comes there only if the answer hasn't
  landed after a few seconds. What a session you allow answered for you shows as a card of its own.
- **Questions that read at a glance.** Whozmove's Claude Code plugin gives every session a skill for asking you
  questions: one thing to decide in a short line, two to four options named in a few words, each with one line of what
  it means, and the one Claude would pick first.
- **May Send Back Plans**, at the foot of the mode menu of the session leading a team (its team file): that session
  can send back a team member's plan for you, in the same project, with a note, using `ask-panel.sh waiting` and
  `send-back <id>`. It never approves one. The member's row says the plan was sent back, by whom and why; you can
  always answer first, and while you're answering, it's left to you. It's kept for that session's folder while Whozmove
  runs: after an update of Whozmove, or quitting it, it's off until one press brings it back (below).
- **May Answer Questions**, beside it: that session can answer a team member's questions for you, with one of each
  question's options or written words, using `ask-panel.sh answer <id>`, marked as chosen for you and as no OK of
  yours for anything that needs your permission. It never answers a request for your OK. The member's row says what
  was answered, and by whom.
- **May Approve Plans**, the third: that session can approve a team member's plan for you, as `ask-panel.sh waiting`
  lists it with its text, with `ask-panel.sh approve <id> <digest>`, as your own approval in its tab would; the member goes back to the mode it
  planned from. Never for a session that could switch to bypassing permissions. The member's row says the plan was
  approved, and by whom, once Claude Code has taken it, with Read plan and Take me there. Like the other two, it's
  kept for that session's folder while Whozmove runs, and never held by a session that could bypass permissions.
- **The three switches stay with the lead's folder.** Close the session leading the team and start another there, or
  clear it, and once the team file names it, May Send Back Plans, May Answer Questions and May Approve Plans are on for
  it with nothing to press, and a line under the header, kept until you close it, says so each time, naming its terminal
  app and when it started. A folder none has held them in for 7 days stops being kept. Only a session that works in that
  folder, is Claude Code's own program signed by Anthropic, wasn't started by another session and is the only one there
  holds them; where one doesn't, the switch shows a dash and says why, and pressing it stops keeping it.
- **One press brings back the switches an update turned off.** After an update of Whozmove, or Whozmove starting again
  after a crash, May Send Back Plans, May Answer Questions and May Approve Plans are off, and one press at the foot of
  the session's mode menu turns back on just what you had ticked: **Turn Back On May Answer Questions and May Approve
  Plans for shop**, which names each and the folder. A line under the header says the same, and a session
  asking while they wait is told they're off since Whozmove restarted. It's offered to any session that may hold them
  in the folder they were ticked for, naming only those one press can bring back now, and greyed with the reason only
  when none can. After quitting Whozmove it's offered the same way.
- **Bring Forward.** Pick a session in Settings ▸ Bring Forward, and holding Fn + Option (or Fn + Shift) for a moment
  from any app brings it forward, its terminal tab or its Claude Desktop conversation, as a click on its row does, and
  that's all. Then speak with your dictation app's own keys, and your words go into the session. When there's nothing to
  bring forward you hear a beep, and its row or the line under the header says why. The Chief is among the picks while a
  session leads a team for you.
- **Only Claude Code itself asks in a session's name.** A task for you, the inbox, a message or a ticket's step comes
  only from Claude Code's own program, signed by Anthropic, working where that session works, never from another
  program that wrote a session's record. Sessions still running a version Claude Code has since updated count as ever.
  Claude Code from npm counts as ever from 2.1.113 on, as it's the same build; an older one, run by Node, still shows
  its sessions, but they can't ask. A refused ask says why and what to do.

### Deploy

- **Run a website from Deploy.** A command that starts a server and keeps running, such as a website's dev server,
  shows a steady ring round its stop square once it listens, and its address after the folder: a press opens it in
  your browser. Its menu offers Open, Restart and Stop Deploy, and resting on it says how long it's run and whether
  other devices on your network can reach it.
- **Deploy says how a run went, on a card.** "Deployed: open shop at localhost:3001" as a server comes up; and when a
  run doesn't go through, what happened in plain words (stopped before it was up, stopped by itself, no packages
  installed yet, or no port after 2 minutes), with the last lines it wrote, its log and a way to try again. With no
  packages, Install First shows the project's own install scripts, then installs them once, from the checkout's lock
  file, and deploys, but only if those scripts are still as shown; or Copy and Go copies that install and takes you
  to the session in that checkout to run it.
- **Deploy when the agent's done.** Pressed while an agent is editing that checkout, Deploy keeps your press and
  deploys by itself once it's done, with everything checked again; its menu has Don't Deploy.
- **Deploy asks before a port clash.** If another of its builds is already on the port a deploy needs, a card asks
  whether to replace it, or offers the next free port; if a program Deploy didn't start holds it, the card says what,
  and offers the next free port or the session that started it. Deploy only ever stops builds it started. A
  session's ask that meets one takes the next free port by itself, and its status says which.
- **Each checkout gets its own port.** A Deploy command you confirm now runs with a port of its own in `$PORT` for
  each checkout of the project: 3000 for the main one, and the next free one for each worktree, kept. So a website's
  dev server can run in every checkout at once.
- **Deploy shows all a command runs, and asks again when that changes.** The set-up card shows every package script,
  Makefile recipe and file in the checkout your command runs, with the scripts those run in turn, and says what it
  can't follow. If any of that has changed in a checkout since you confirmed it, by a branch or an agent, Deploy
  doesn't run it there: the set-up card shows what it runs now, for you to confirm again. A command you confirmed
  before needs confirming once more.

### Usage and Spotify

- **Your gear, on the usage card.** Opened, the card shows a seat for each gear from 1 to 30, one lit for each session
  working: those up to your gear in a box, and a notch under the one your plan can carry to the week's end. Press a seat
  to set your gear there; then the line under the rows says where the week ends at that gear, "At gear 8 the week ends
  near 94%.", or when it runs out. It recommends no gear until the week has gone up enough while Whozmove watched to be
  measured, and says why not yet. Only your press sets the gear; a chief session of yours can read it from `gear.json`.
  A session working beyond your gear says **Over the gear** on its row in the list, and carries on, as the gear holds
  back only queued jobs waiting to start; a session you open yourself is never held. **Usage Gear**, in Settings, turns
  it all off, so queued jobs start without a limit, and forgets the gear you set.
- **Less empty space on the usage card's rows.** Opened, each row's percent, where it ends up and its time sit
  together at its end, and its bar takes the rest of the row: the percent keeps a column of its own, and the other two
  are each as wide as their own words, so a short one beside a long one in the other row no longer leaves a gap. Both
  bars start at the same point.
- **Where your usage ends up, on the usage card.** Opened, each row shows beside its percent where it ends up by its
  reset at the pace you're going, `→ 30%`, or `out 1:41 PM` when it runs out first (`out in 2d 4h` when that isn't
  today), dotted on along its bar from what you've used: grey when that's about even, amber when it's fast, blue when
  it's slow; a row that runs out first says its time to the reset as `resets 4d 1h`. A line under the rows says what
  that comes to, "Going slow: about 70% of the session would go unused." or "Going fast: the session runs out before it
  resets.", and under it, on a line of its own, what to do: "Room to do more." or "Ease off to make it last." Slid out,
  the card shows a notch at its bottom edge where even use would be by now.
- **The session using the most, on the usage card.** At the foot of the open card, the session that has used the most
  of your plan today, its share of what your sessions used and how long its conversation is now ("site-redesign uses
  the most today: 17% · 744k long").
- **The usage card rests while you're away.** It asks Claude Code for your usage every 3 minutes while a session works
  or the card is slid out or open, and every 10 otherwise; with no key pressed or pointer moved for 5 minutes it stops
  asking, and as you come back it asks again if the last check is over 3 minutes old, so it's right when you look.
- **Spotify goes quieter while you talk to Claude.** Talking to a Claude session by voice (Claude Code's voice mode in
  any terminal, Claude Desktop's dictation, or a dictation app such as macOS Dictation into a session's tab in Ghostty
  or iTerm2, or into Claude Desktop) turns the music down to half its volume as you start, a point at a time as a steady
  hand turns a knob, and once you've stopped, back up the same way to exactly where it was, never louder. A change you
  make to Spotify's volume meanwhile is left as you made it. A small speaker beside the strip's time shows it. Spotify's
  page on the panel's back turns it off, and sets how much quieter: **A little**, **Half** or **Much quieter**. It needs
  macOS 14 or later, and Whozmove allowed to control Spotify, which a card there asks for when it isn't yet (**Allow**).
  Whozmove reads only whether a microphone is in use and by which app, never a sound.

### Storage

- **Storage: what fills your disk, and what can go.** When your disk runs low, a line above your sessions says what's
  left and how soon it's full, and opens **Clean up** beside your sessions: what comes back on its own (Xcode's built
  files, your tools' caches, what Homebrew and Docker leave behind, models, your projects' built files, worktrees you're
  done with), ready in a few seconds from the usual places while the rest of your disk is measured, the line saying how
  much it can clean, and when the map it comes from was measured once that's over an hour ago ("· measured 6 hours
  ago"). Tick what you want gone, then **Clean Up**: folders go to the Trash, each tool's own command runs, and each
  row says how it's going, one that stayed saying why and what to do, and one that went saying so; the line then says
  what's in the Trash until you empty it.
  **Map** shows your disk as rings round the folder you're in, with what's in it beside them, biggest first; **＋**
  collects what can go for **Move to Trash**, and nothing an agent is working in, with changes not committed or commits
  not pushed, or macOS's own, can; a folder it can't look inside without Full Disk Access says so on its row, with
  **Allow Access**. Storage is off until you press the line or **Map My Disk**, measures again as
  Whozmove opens only once its map is a day old, measures only sizes, never what's in your files, and keeps them on your
  Mac.
- **The map moves with you.** Pressing a folder on the map, its piece grows into the middle as the rest of the rings
  fade, then its own rings come in round it; coming back out, the middle shrinks back into its piece. **＋** sends the
  item's name from its row to what's collected under the map.
- **Keys left out.** Whozmove looks for keys left where they shouldn't be, by itself from the first launch and once a
  day after: in a commit not pushed yet, already pushed, not committed, in a new file git would add or a remote's
  address, in what Claude Code keeps of your conversations (what you sent, what its tools read, your message history,
  long pastes and copies of the files it edited) and reads into every session as its instructions (your CLAUDE.md files
  and rules, skills, agents, commands and output styles, each project's memory and what they import), in what Codex,
  Gemini CLI and Aider keep of yours, in your shell history and your shell's settings (~/.zshrc and the rest) and, with
  Full Disk Access, in Downloads; and for credential files other accounts can read. Storage's **Keys** tab, beside Map
  and Clean up, shows each key once, as soon as it's found, and how far its look has got, most urgent first: **Do now**
  for a key that has left your Mac or is about to (pushed, sent to Claude or another AI tool, in a commit not pushed
  yet), then **When you can** for one only on your Mac. Each says what it is, where it is in a sentence (a file in every
  copy of a project and its commits said together), whether it looks real and why, and its best fix (**Replace at** its
  provider, **Open at the Line**, **Make It Yours Only**), with the rest under its ⌄ (**Copy Clear-Up Command**, Claude
  Code's own `claude purge` for that project, for you to run; **Move to Trash**, after one Confirm, only for a
  downloaded file that's nothing but the key). **Show Where** lists its places, each with **Open at the Line**, **Open
  the Conversation** or **Show in Finder**, a copy Claude Code kept of a file it edited named by that file. A key most
  likely made up for a test, one an agent made up itself, or an id, isn't counted, and waits folded at the foot. What
  only looks like a key isn't listed: a word, a variable's name, a sentence, a private key's first line with nothing
  after it, or a run inside a picture's data. **Mark Replaced** and **Not a Key** put a key away, each with **Undo**. A
  line above your sessions speaks only for keys that have left your Mac or are about to.
  Nothing is checked online, and a key is never kept: only its kind, how it starts and its last 4 characters.

### Working on Whozmove

- **Keep App Switches**, while it's ticked: Whozmove keeps on this Mac, for two weeks, each time an app comes to the
  front (only whether it's one Whozmove works with, a terminal it knows or Claude Desktop, never which app), when you
  go away from the Mac and come back, and when you look at a session, to measure how much of your attention your
  agents take. Nothing is sent anywhere.
- **Messages**, while **Show Messages** is ticked: every message your sessions send each other, beside the list, with
  how pressing each one is and whether it was read, answered, held or lost; press a name for everything one session
  sent and received. And an inbox for a team's lead: a session writes to it with `ask-panel.sh message`, which keeps
  the message before the line that tells the lead is sent, so a line held in the lead's tab or expired loses nothing,
  and the lead reads its inbox one message at a time, most pressing first.
- **Team Board**, while **Show Team Board** and **Show Teams** are ticked (in Working on Whozmove ▸, shown while ⌥ is
  held as the pawn menu opens): the work of a team a session leads, beside the list, from **Team Board** at the end of
  the chief's line, or under Tools on the panel's back. It answers nothing: what needs you is one line, with each kind's
  mark, that opens One Task. Then what's moving, as one big number, with how many wait their turn at a step nobody works
  on ("Ready to try"), counted apart from what's moving; a strip of the steps the jobs are at, each with its count,
  which opens its jobs, the most pressing first, then the smallest, then the least work; who's on what, a line for each
  member with the job it's on, its step and its other jobs; a tile for each goal, numbered, with a bar of its jobs by
  where they stand, and a heading for how the team works after them; and what's done this week. A goal's tile opens its
  Up next; a job opens its card, with its track, what it wants of you, what it holds up, and **Take Me There**. Where a
  job stands has the colours its row in the list has.

### Fixes

- **Building from source on macOS 27.2 no longer leaves the panel gone.** `./build.sh` and Deploy restart the login
  item by loading it again, so macOS accepts the new build instead of stopping it as it starts.
- **The usage card says "no reading" when Claude Code's answer has no window for it.** When the answer has the week but
  no five-hour window, the Session row showed an empty bar and "0%" with nothing after it. It now shows a dash and "no
  reading", the line under the rows goes by the week, and the folded card shows the week.
- **Whozmove's log no longer keeps a deploy command's words, a compaction's focus, or words sent to or shown in a
  Claude Desktop conversation.** It names a deploy's project and folder, that its command ran or was set, and its
  length in characters; a slash command by its name and the menu's pick; what goes into Claude Desktop's message box
  only as its slash command, or "words", with its length; and what Claude Desktop's window shows only by its own
  labels. A session that asks for a deploy is told the project and folder, never the command's words.
- **A plan or note opens at once, even just after Whozmove opens.** The reader no longer says "Reading NOTES.md…" for
  as long as it takes Whozmove to read every session's transcript again after it opens (or after Deploy restarts it):
  what a session wrote is read straight away, beside those reads.
- **Opening no longer reads every conversation from its start.** Whozmove keeps what it found in each session's
  transcript in its own folder, so after it opens, or Deploy restarts it, it reads only what's been written since,
  rather than gigabytes of transcripts again, and a row's pull requests, edits and writings are there from its first
  read.
- **What's highlighted follows the list as it scrolls.** Scrolling the list under a still pointer (by hand, or as it
  brings a request into view) highlights what's under the pointer now, rather than what was.
- **A short branch stays whole on a row's bottom line.** With a build's address after it, "main" reads whole:
  a long name shortens first, to about a dozen letters, then the effort and the model give way.
- **No empty sliver for the effort or model.** On a crowded bottom line, one with no room for even a letter goes
  whole, with its "·", rather than leaving a sliver beside it; the mode always shows.
- **Uses much less energy with many sessions open.** Whozmove runs git for a checkout only once something in it has
  changed, as macOS tells it, rather than every few seconds for every one; reads each commit waiting to go once,
  rather than again each time a branch moves; asks GitHub for a branch's pull request only once the branch is on
  GitHub, and never for the default branch, which pull requests go into; reads each session's records again only once
  they've changed, rather than every second; looks at how its plugin stands in Claude Code when Claude Code's own
  records of its plugins change, and hourly, rather than starting Claude Code every 5 minutes, so the plugin turned off
  or taken out there shows on the line within seconds; moves the band of light across what Claude is doing and the ring
  round a waiting dot as layers, so the panel isn't drawn again on every frame for them, and holds the folded panel's
  eyes still while it's open; and sets just the times in its list when nothing else in it has changed, rather than
  drawing the whole list again every second, and leaves the list as it is while the panel is hidden or the screen is
  asleep or locked, drawing it as it is then the moment the panel can be seen again. What each row says, and how soon it
  says it, stay as they were.
- A session's row brings its terminal tab forward, with the keyboard, when another app's window is above it, over it
  or beside it, without that app being in front, as Arc's single-page windows can be. Before, a press on the row of the
  session the tab showed did nothing.
- Paste works in the panel's text boxes: ⌘V, and a dictation app that puts its words in by pasting. ⌘C, ⌘X and ⌘A work
  there too.
- Flicking the panel away while it's open from pointing at it leaves Whozmove at the screen's edge, as from a press,
  and the panel comes back open, instead of the panel folding up and moving about the screen.
- A plan you approved in Claude Code no longer stays on its row as waiting for your OK after you stop the turn, nor
  after the plan was edited before you approved it.
- A message another Claude Code session sent shows on the row under that session's name, where yours says You, instead
  of Claude Code's wrapper around it, and the reply to it went back to that session, so it never waits on you.
- A conversation sitting at its prompt while a command Claude started in the background still runs can be compacted
  and changed from the panel. Before, the Compact card said it wasn't running.
- Pointing at Spotify's icon shows the song to resume however long its name, in any script, shortened with … when it
  doesn't fit. Before, a long name came up as an empty box.
- At the top of the screen, the panel stays where it is as it turns over to its back: its list no longer drops a
  little before it turns, nor jumps back up as it turns back to the list.
- A conversation beside the folded panel that grows, with a longer message or a request, no longer covers the one
  after it, and one that shrinks or goes no longer leaves a gap after it: the ones after it move clear as it grows,
  and close up as it shrinks or goes, even while you're in one's tab. Only the one you've moved the pointer onto keeps
  its place, once it has got there: one you move onto as it closes up, as the one above shrinks once you've answered
  it, goes on up all the way, and so does one that closes up under a pointer you've left there, which once it has
  stopped holds their time while you read it, as if you'd pointed at it. The ones after one going back move up once it
  has faded, one coming out waits till they've moved, and one coming out after the first fades in where it goes,
  rising a little into it, so none passes over another on its way.
- A reply you've already seen beside the folded panel no longer comes out again after a request in its session has
  come and gone.
- A model, effort or mode pick that can't go in says why on its row, with the button past it when its terminal has
  one, or Take me there when it has to be changed in the session itself, and a compaction that stopped part-way says
  why on its card. Before, most of them only beeped.
- Resting the pointer on the folded panel while a line under the header shows no longer draws a rule between the
  panel's head and that line, so it looks as it does when the panel is open.
- Resting the pointer on the folded panel, the line under the header and a card at the list's top come in with the
  list, rather than before it, and the rule under the panel's head goes as a row held at the list's top meets it, as
  it does when the panel is open.
- Sign in on the usage card opens a terminal to sign Claude Code in, or says why the terminal couldn't, with the
  command to run yourself; and pointing at a row of the open card shows the clock time it resets at.
- Moving the pointer quickly down onto the usage card slides it out, as a slower move does. Before, the card stayed
  folded, and with the panel folded, the list your pointer had brought out folded away, the card with it.
- The open usage card stays in sight as the pointer moves on and off it. Before, a card that was already open when
  Whozmove opened could vanish and come back each time the pointer crossed its edge.

## 0.2.0 - 2026-10-21

### Installing and setting up

- **Install with Homebrew.** `brew install --cask whozmove/tap/whozmove` installs Whozmove on a Mac with Apple silicon
  and macOS 13 or later. It isn't signed by Apple yet, so the first time you open it, press Open Anyway in System
  Settings → Privacy & Security, once. `brew upgrade` brings each new version, and
  `brew uninstall --cask --zap whozmove` takes it out with its login item and its folder. Each release is built on
  GitHub from its version's tagged commit (`tools/release.sh`).
- **Whozmove says when a new version is out**, installed with Homebrew: the line under the header names it, with the
  command that updates it and **Copy Command**. It never runs `brew` itself, and its × keeps that version away until a
  newer one. Once Homebrew has put the new version in while Whozmove kept running, the line says so, with **Restart**.
- **Whozmove sets itself up as it opens**, from an Applications folder, where `./install.sh` used to do it: it adds its
  hooks to Claude Code as the `whozmove` plugin, or brings them up to date there, with Claude Code's own `claude plugin`
  commands, using the `claude` your terminal finds, else Claude Desktop's own copy. It never adds back hooks you took
  out of Claude Code, and the hooks now record nothing while Whozmove isn't installed: once it's gone, nothing more of
  your sessions is written down. `./install.sh` now builds the app and opens it.
- **Whozmove opens at login from its first open**, as a login item of its own, with **Open at Login** in the pawn menu
  to turn it off and on (and, turned off in System Settings' Login Items, a press there opens them). It restarts
  Whozmove only after a crash.
- **A line under the header says when setting up needs you**, with the button that does it: **Install** for Apple's
  command line developer tools, which your sessions are followed with, asked for only once Claude Code is there (the
  line stays until they're in, says so while macOS installs them, and carries on by itself once they are); **Get Claude
  Code** when it isn't on this Mac; **Add Back** or **Turn On** when Whozmove's plugin was taken out of Claude Code or
  turned off there; **Try Again** when connecting failed; and that it's connected, with a tick, for a few seconds once
  it is. Its × puts it away until things change, and the panel's back keeps the same buttons: Git's page for the
  developer tools, Claude's for the plugin.
- **Sessions already open when Whozmove connects to Claude Code catch up without a restart.** They show only part of
  what they do until they reload Whozmove's plugin: the line under the header offers **Reload Them**, and each of their
  rows says it's shown in part, with **Reload**. Whozmove types Claude Code's `/reload-plugins` into each idle one, one
  at a time, keeping a half-typed message in a terminal, and its conversation carries on as it was. One it can't type
  into says what to type there, with **Take me there** on the line.

### The list

- **One list, newest first, as a chat app keeps it**, in place of the Needs you, Working, Your turn and Idle sections. A
  conversation goes to the top whenever a message comes, Claude's reply or a request, and when you send one, from the
  panel, Claude or a terminal. While Claude works, its row stays where your message put it, and compacting doesn't move
  it at all. A row you've just pressed stays put until your pointer has left the panel, then goes to its place. Once a
  conversation is idle, a day after you read its reply, it goes below the rest. In the pawn menu, Group by Status is now
  **Newest First**, and Group by Activity is gone (a panel set to it shows the list newest first). Grouped by project,
  the projects go A to Z and stay put, each with its conversations newest first.
- **The dot says whose move it is**: a pulsing red-orange one for a request or question, and amber for a reply you
  haven't read, which now stays so until you've read it (opened it here, been on it in Claude, Ghostty or iTerm2 for a
  couple of seconds since it came, watching it come in counts, or written to it), rather than for 30 minutes; an empty
  ring once you have. While Claude works, its "Claude" label fades in and out in cream, no longer blue.
- **Rows no longer show a coloured label** for where an idle session's work stands ("Ready to commit", "In review",
  "Done" and the like), or what that work has been through ("built · tested", the audit). The work line (below) shows
  what's left to do instead.
- **The row of the session you're on stays in view**, whether you scroll the list past it or the list moves it out of
  sight (to the top as a message comes in, say): it holds on at the top of the list, or at its bottom while it's further
  down, folding a line at a time, the row next to it touching it all the way, until its name, Claude's line and where it
  runs are left. The rest of the list goes under it as under the header. Back in view it opens out and glides into its
  place, and pressing it scrolls back to it. Switch to another session and its tint moves over to that one's row as it
  slides away. A row you're typing in, or one too tall to show whole, goes out of sight as any row does.
- **Terminal sessions stay listed once they've ended**, as Claude Desktop's conversations do: close a session's tab,
  quit the terminal or restart the Mac, and its row stays, grey, with its last message and reply, for 3 days after its
  conversation last moved. Click it and it carries on in a new tab of the terminal it ran in (Ghostty, iTerm2 or
  Terminal; else the one new conversations start in), in its folder, as the same conversation, and the row turns back
  into the running one. Until then its menus say "It isn't running: press its row to open it again", and its row keeps
  its checkout's changes and next steps. If Claude Code doesn't carry it on in the new tab within half a minute, the row
  says so, and nothing tries again until you click. One you left with `/clear`, or whose transcript Claude Code has
  cleared away, isn't listed.
- **A conversation open in two places at once** (resumed in a second tab while it still runs, or open in Claude Desktop
  and a terminal) is one row instead of two, following the copy that needs you: one asking you something, then one at
  work, and otherwise the one it followed already, which pressing the row opens. An orange icon of two windows after its
  time says so, and pointed at, where else it's open, as each copy knows only what was said in it since the second
  opened, with **Close the other copy** for those in other terminal tabs. The panel types nothing into it while another
  copy runs in a terminal, and doesn't change its mode while one is open in Claude Desktop. Deploy and next steps wait
  while any copy is at work.
- Nothing is typed into a session paused in its terminal (Ctrl+Z), where the keys would go to the shell: its menus and
  next steps say to bring it back with `fg` first.
- A Claude Desktop conversation's row says when it last moved by the later of Claude Desktop's own time and the hooks'.

### The panel

- **More room for the list.** The header stays as you scroll the list down until the row you're on reaches it and has
  folded down there; scrolling on, that row pushes the header away, point for point, and it stays away, even part-way,
  until you've scrolled back to the top of the list. While it's gone, Whozmove peeks out beside the panel's top corner,
  on the side facing the middle of the screen: it looks up as your pointer comes near, blinks slowly when you rest on
  it, and flicks an ear when something new needs you. Press it and the panel folds round it, right where it is; drag it
  to move the panel. The panel opens round it again, with the header back.
- **Flick the panel away.** A quick sideways two-finger swipe on the panel pushes it off that side of the screen, fading
  as it goes, and Whozmove peeks out from the screen's edge; press it, or Show / Hide Panel, or ⌃⌥N, and the panel
  slides back where it was. Up and down still scroll the list.
- **What needs you comes out beside the folded panel.** While the panel is folded, a request, a question, a plan or a
  reply you haven't read comes out beside it by itself, as its own row from the list, so you can answer it there or
  press it to open its session. Newest first, three at most, each for 45 seconds, its time running out along its foot;
  pointing at one, typing in it or being in its session keeps them all out, and nothing new comes out meanwhile. Pin one
  to keep it out, or × to send it back; under them it says how many more are waiting.
- **Rest the pointer on the folded panel and it opens**, headed with how many are waiting on you; move off and it folds
  back, or press it to keep it open. As it opens, what's out beside it goes into its row, and back out as it folds.
- **The panel turns over to the apps Whozmove works with.** The four squares in the header turn the whole panel over,
  about its middle. Behind the list are Claude, Ghostty, iTerm2, Terminal, Spotify and Git, each with its own icon (the
  terminals when they're on your Mac); press one for what Whozmove does with it, its switches, how what Whozmove needs
  there stands, what macOS lets Whozmove do with it (with Open System Settings when it isn't allowed), and Open. The
  terminal new conversations open in, Spotify's song, lyrics and icon, and Git's next steps and Deploy are switched
  there. Claude's page is for Claude as a whole: with **Track Claude Desktop app sessions** off, Claude Desktop's
  conversations leave the list and new conversations start only in a terminal, and on a Mac without Claude Desktop,
  **Get Claude Desktop** opens its download page. Rows, where the four squares were, turn the panel back; its chevron
  folds the panel away. With reduced motion, one side fades into the other.
- **Light mode**: the panel, its cards, the usage card and Spotify's token follow the Mac's Light or Dark appearance, or
  the one picked in the pawn menu's new **Look ▸**, with colours of their own for each: on a light panel, the status
  colours are deeper so their words read, and a card's main button is dark. **Look ▸** also picks the panel's own
  colour: **Grey**, now how it starts, **Black** (white on a light panel), or **Glass**, the see-through panel it was,
  showing what's behind it, blurred. While Reduce Transparency is on in System Settings, Glass is grey.
- The header and the list keep to 640pt, and what opens with them (a new conversation's card, the now-playing strip)
  comes on top: the panel grows to fit it, as far down as the screen goes, and only there does the list give way and
  scroll. When a row comes or goes, the panel's bottom edge eases with the rows instead of jumping to its new height.
- **Your message and Claude's line are written in.** New text writes in from the left once the old has erased from the
  right, and Claude's next step keeps what it shares with the one before ("Reading …"), rewriting only the rest. A reply
  on two lines writes one line, then the next; Claude's time stays just past its text as it goes. With reduced motion,
  the lines change at once.
- Once you've typed in the panel (Compact's words, a plan's notes, a new conversation) or clicked into a prototype in
  the reader, the keyboard goes back to the app you were in as you leave, and pressing a terminal session's row leaves
  it in the terminal, so you can type there straight away.

### Answering and steering sessions

- **Start a conversation** from the panel: the ＋ in its header, a project's ＋, or ⌃⌥N from any app (New Conversation in
  the pawn menu, which can also turn the shortcut off) opens a card at the top of the panel. Write what Claude should do
  and press ⌘Return: the card turns into the conversation's row and moves down to its place in the list, saying it's
  starting until Claude lists it. Chips under your words say where it starts: **@** in your words (or the project's
  chip) chooses the project, and **#** where in it, its own folder, a worktree that's there, or a new worktree, for a
  branch that's there or a new one (**#name from release** starts it from that branch), in a folder beside the repo
  (`shop-worktrees` for `shop`) or one you choose. Anything in a worktree starts in a terminal, and nothing switches the
  branch of a folder in use. Start names the app, Claude Desktop (where it's on this Mac), Ghostty or iTerm2, with an
  arrow to switch it. A card closed before it starts comes back as you left it. A folder Claude hasn't worked in before
  is asked about on the card, once, for both apps.
- **Click a request or a question on a row and the keys work on it**: 1 to 9, or ↓ and ↑, pick an option, Return goes
  on, submits or allows once, and Esc leaves it, answering nothing. Its edge shows it has the keyboard, which goes back
  to the app you were in once you answer, so Return no longer reaches the app in front, where it could answer Claude's
  own copy of the question with a different option.
- A permission request's card always offers **Allow once**, where a request too long to show in full could only be
  denied before. Each part now shows up to 100,000 characters; past that the card says the content is too large to show
  in full, and Allow once still allows all of it. Any tool without a card of its own (a connector's, like a widget or a
  Slack message) is listed field by field, as in Claude's own prompt, instead of raw JSON.
- **Plans in the panel.** While Claude waits on a plan, its row asks for your OK, with **Read plan** and **Take me
  there**: the plan can be sent back with your notes (**Revise…**) or stopped, and approving it happens in the session.
- **"Switch model?" on the row.** Claude Code's question, for a model picked in the panel (switching re-reads a cached
  conversation), is asked on its row, as Claude Desktop's now is too (no longer over the list), saying how much the
  conversation holds, and only when Claude Code would ask it: Switch goes on, Cancel keeps the model, and with no answer
  within a minute Claude asks in the terminal. It takes Claude Code 2.1.304 or later. A pick going into a terminal
  session shows on its row at once ("Switching to Opus 5.5…"), and anything else Claude Code asks in the terminal before
  it goes in (its "Change effort level?") shows there too, with Take me there, until it has your answer, instead of the
  tab jumping forward.
- **Compact now.** When it's a good time to compact a session, its context ring opens by itself and says so ("98% ·
  Compact now"), and why when you point at it: while it sits idle, once its conversation is nearly full or long, or,
  once it's big, when its work has just been committed or you've been away from it for an hour. Pointed at, the ring's
  Compact button says how full the context is too ("98% · Compact").
- **Compacting, shown on the ring.** While a conversation compacts, whether by itself or asked for, its context ring
  becomes a short arc going round, and Claude's line says "Compacting the conversation" with how long it has taken. When
  it's done, the arc fades and the ring fills to the new size.

### Work in a checkout

- **A work line** under a row's last message and reply, while there's work in flight: its pull requests at the start,
  and at the end what isn't committed and the **next steps** its checkout has to take, as git sees it, each an icon: a
  commit icon while something isn't committed, **↑2** while the branch is ahead of its copy on GitHub, a cloud for a
  branch never pushed. Pointed at, each says its step beside it (**Commit**, **Push**, **Publish**); pressed, it asks
  the session's agent in words, only while it's idle and no other agent is working in that checkout (meanwhile the steps
  are dimmed, and a press says what they wait for). A commit takes only what's staged when something is, as git does.
  While commits wait to go, the line's start says where the branch stands ("Ahead of origin · 2 commits", or "Not
  published · 3 commits"), and pressed, opens those commits. After a code review that reports what it found to Claude
  Code, it says how the review went: "Reviewed · 5 to fix", then "Reviewed · all fixed" with a green tick, or "Changed
  since the review" when files are edited after it with something still to fix. Once everything is pushed, a branch with
  no pull request shows **No pull request** and **Create PR**, into the repo's default branch or another you pick, or
  **Create Draft PR**. One row per checkout has its numbers, steps and Deploy: of the sessions running in it, the one
  that edited files there last, else the one you used last there. Git, on the panel's back, turns the next steps and
  Deploy, or just Deploy, off.
- **What isn't committed** in a checkout ("+26 −13"), at the end of the work line, counted as git counts it: every
  change since the last commit, staged or not, new files included. Pointing at the numbers says how many files that is;
  pressing them grows the panel beside the list with git status's own tabs: **Changes**, **Staged** and **Outgoing**
  (the commits not on GitHub yet), each file marked as git marks it, with the tab's step: **Commit** (and, under its ⌄,
  Commit and Push, and Commit and Open a Pull Request), **Push** or **Publish**. Files one after another or one at a
  time, lines inline or side by side. The view keeps up while the agent works. **Open in Editor** opens a file at its
  first change, in the editor you pick the first time; the pawn menu's **Open With ▸** changes it.
- **Deploy**, a round play button at the end of the bottom line, for any project Whozmove can work out a deploy command
  for: it puts that checkout's code in place on this Mac. The first press suggests the command and you confirm it twice,
  seeing what a package script or Makefile target in it really runs, with a warning if that looks as if it could deploy
  to production (never suggested); from then on the button is always there for that project, with a dot when an agent
  edited files or built since the last deploy. It runs in your own shell as your terminal starts it, never while the
  agent is working or asking, or another is working there, shows a stop square in a turning arc while it runs (a press
  then offers **Stop Deploy** and its log) and a check when it's done; if it didn't go through, the work line says why.
  A right-click changes or forgets the command.
- **A bottom line** like an editor's status bar: how the session's agent is set up (its model, effort, mode and context
  ring) at its start, and at its end where it runs, its branch (in purple with a worktree icon in a worktree) or its
  folder outside git, then Deploy. Pointed at, the branch says its project, its folder and the app it runs in. Short of
  room, a long name shortens first, before the model and effort. Rows no longer show the app's icon.
- **What a session wrote**, on a tag on its row: press it and the panel grows beside the list with the session's
  **Plans**, **Prototypes** (`.html` pages it created) and **Notes** (`.md` files it created), newest first. Plans and
  notes read as formatted text; a prototype runs as it would in a browser, without reaching anything else, with **Open
  in Browser**. Drag the panel by either header to move it, reader and all.

### Terminals

- **iTerm2**: a click on a session's row brings forward its window, its tab and its pane, and the session in the iTerm2
  tab you're looking at is marked as the one you're on. With iTerm2's Python API switched on (Settings ▸ General ▸
  Magic), every session takes the model, effort and mode menus, Compact and next steps, the keys going into that session
  alone; with it off, only a session alone in its window does, as iTerm2's Broadcast Input could copy the keys into the
  others, and for one that shares its window, they say so and offer Turn On iTerm2's Python API…, which opens iTerm2's
  Settings at that box and ticks it, for iTerm2 to ask you. When iTerm2 has gone while its sessions live on (after a
  crash), the click starts it. A conversation started in iTerm2 opens in a new tab of its front window.
- **Ghostty**: a click on a session's row switches Ghostty to its tab before bringing Ghostty forward, so it lands on
  that session every time, and the session in the Ghostty tab you're looking at is marked as the one you're on, as
  Claude Desktop's open conversation is.

### Usage and Spotify

- **Your Claude plan's usage** on a card under the panel, asked of Claude Code itself every 3 minutes: the session and
  the week, how long until each resets (pointing at one shows the clock time), in Claude's own colours, with a note when
  you're on course to run out. A press folds the card away behind the panel, where only a thin line shows along the
  panel's bottom edge, coloured as far as the session is used; pointed at, the card slides out with the numbers on it,
  and pressed, it opens again. At the session limit a vine grows from the card's corner until the reset, then pulls taut
  into the session's bar and drains as usage starts over. Not signed in, **Sign in** opens a tab running
  `claude auth login`.
- **Spotify**, from a round token tucked half under the panel's bottom corner, on the side facing the middle of the
  screen; dragged across the screen, the panel takes it under itself to the other corner. **Play** opens Spotify in the
  background if it's closed and plays what it last had; paused, the token wears the song's cover and resumes it. Without
  Spotify it offers **Download**, and turns into Play by itself once Spotify is installed.
- **Now playing**, at the bottom of the panel, while a song plays: its cover, song, artist and time, with a thin line
  for how far in it is. Pointing at it shows back, pause and next, the line jumps where it's pressed, and pressing the
  strip brings Spotify forward (once lyrics are on, it opens them); paused, it greys and offers Play, and after 15
  minutes folds into the token. Spotify's page on the panel's back has **Show the song** (off, the token and the strip
  go, and Whozmove leaves Spotify alone), **Lyrics**, **Its icon at the panel's corner** and **Open Spotify**.
- **Lyrics** for Spotify's song, from LRCLIB, once you say yes to the strip's question: while a line is sung it takes
  the place of the song's name in the strip, and the name comes back between verses. Pressing the strip opens the whole
  song beside the list, the line being sung lit as it plays; pressing a line jumps the song there. **Show lyrics in the
  strip**, at their foot, turned off keeps the strip on the song's name. Nothing is looked up before you say yes; when
  LRCLIB is busy, Whozmove asks again, a little later each time; and the lyrics found are kept on this Mac, so a song
  played again shows them at once, until you turn lyrics off.

### Working on Whozmove

- **Working on Whozmove ▸** in the pawn menu, shown while ⌥ is held: **Show Build in Header** says which checkout the
  running build came from and when, and **Preview the Wait** plays the usage card's wait without a limit to wait for.

### Fixes

- The panel no longer flashes lighter at its bottom edge as it grows, and moving the pointer over something no longer
  restarts its hover effect with every move.
- The panel lets go of what each git read opens as soon as it's done, so with many checkouts it can't run out of files
  it may open, which would make a checkout look as if it had no changes for a few seconds.

## 0.1.0 - 2026-10-11

The first release: a floating Mac panel that lists every Claude Code session on this Mac, in Claude Desktop and in
the terminal, with whose move it is in each. It answers permission requests and Claude's questions, changes a
session's model, effort and mode, compacts it, and jumps to it. The README has the details.
