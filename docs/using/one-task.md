# One Task

The one thing that needs you most, beside the list, whichever session asks: open it from the line under the header,
or One Task in the pawn menu. It holds only the tasks sessions hand you: a session's own request for your OK, its
question or its plan stays on its row in the list ([Requests, questions and plans](requests.md)). What a task shows,
and the shape a session sends one in, is in [the task's reference](../reference/task.md). A task comes only from
Claude Code's own program, signed by Anthropic (as npm's is from 2.1.113 on; an older one from npm can't hand you
tasks), and only from the session's one copy of it, where that session works: another program that writes a session's
record is refused, and told why.

The head says who a task is from: the session's name, or for a team chief's pick, "Atlas's pick, for Wren", and the
chief's name alone when the pick is about its own work. After it comes where the task is for, as the list's rows say
where a session runs: a worktree on its chip, a checkout by its branch, or a folder by its name; for a chief's pick,
where the member works. A chief's picks come in the order its queue gives them, and
each waits until you answer it, even once the chief has named others. If one changes while you're on it, the foot says who updated it. When a session takes a task back, because you
answered it elsewhere or its job was parked or dropped, it leaves as soon as you aren't pointing at it or typing in it,
and the foot says why ("Taken back: answered in Atlas's session"). Every task leads with its title, then the step it's at ("Step 2 of 3 · Build", with a bar for each step), then one line
on why. What it is follows in a few slim parts, each a label in capitals over short lines, and its buttons come right
under them:

- **A plan** comes cut to its points, "Approve these 7 points", a numbered line each, with what it leaves out ("Not in
  it: …") greyed and not counted; or to its phases, each its name over a line or three; or on its own short view, At
  a glance, every choice with Claude's pick and why ([Plans at a glance](plans.md)), or that view as it was written
  when the card can't hold all of it.
- **A change to try** says what changed, what to do (steps you can tick) and what to look for.
- **What's attached** is a line each: a link opens in your browser, the changes in their view, and a file in the
  reader, when the session that sent the task wrote it. A team's chief may also hand you a file one of its team or a
  session it follows wrote, and the line says whose ("Search plan · from Quill"). Any other file says why it doesn't
  open ("Can't open: Wren didn't write it").
- **Its answers** are a short list to pick from: Works for a change to try, Approve for a plan, Done for a command
  to run or something to do, or a question's own choices, and last of all **Comment**. Pick one and press **Answer**.
  Comment opens its box on its line, for whatever you'd say in words (that it doesn't work, what should change), and
  Return sends it, as Answer does: like any answer, it goes to the session, the foot says so ("Sent to Wren: your
  comment"), and the next task comes. Until you pick, Answer waits, dimmed,
  with "Pick an answer above" beside it, and looks to pick from say "Pick one to send it, or two to mix them".
- **Take Me There** takes you to the session a team chief's task is about, named as the list names it ("Take Me
  There: search-box"), with its folder too when two have that name; when it's something to do there, it's the first
  thing to press. If that session has gone from the list, the task says so instead.
- **A long task** scrolls. While its buttons would be below what you can see, they stay at the foot of One Task, and
  pressing Answer while it waits scrolls the choices into view (or, with Comment picked, puts you in its box).

## On the session's row

A session that has handed you a task says so on its row in the list too, however the list is shown: a short line in a
bubble of your move's colour, under Claude's line, with a speech mark, the kind of task and its title ("Try: Passkey
sign-in"), cut with "…" when it's long, and "+2" when two more of that session's tasks wait. It names the first of
them in One Task's own order. Press its words, and One Task opens at that task; the rest of the row still takes you to
the session. Just come, or now naming another task, it waits a moment to be seen before it takes a press.

At its end is one button, the one thing the task asks for. None of them answers it: you answer in One Task.

| Task | Its button | A press |
|---|---|---|
| Try | ▶ Deploy | puts the build in place, when there's one to put in place; else ↗ takes you to its session |
| Approve | the plan's mark | opens One Task at the plan, or takes you to the session when the plan waits in its tab |
| Pick | the prototype's mark | opens its page in your browser, or One Task at it when it has none |
| Answer | ? | opens One Task at the question and its choices |
| Run | Copy | copies the command, to paste in your terminal; a tick shows it went |
| Do | ↗ | Take Me There: the session it's about, or the one that sent it |
| Seen | an eye | opens its page in your browser, or One Task at it when it has none |

↗, a box with an arrow out of its corner, marks whatever takes you out of the panel, here and on Take Me There.

- **It goes** once the task is answered or taken back, its session ends, or One Task is turned off. A task you put back
  with Can't Now isn't on the row: you said not now.
- **It gives way** to anything else the row has to say (a plugin reloading, a deploy, Compact at Breaks' "Compacting
  stopped part-way"), and comes back once that's gone.
- **Its own line:** it sits over the row's bottom line, under any pull requests and next steps, which stay. While it
  waits, the row shows no Deploy or context ring, but for a try's own Deploy as its button. They come back
  once the task is answered.
- **Under Group by Team** a team row's own line comes first (a job waiting on you, the chief's next or its counts), and
  the task's line takes the place of where a member's job stands, with its one button at its end, as a member's ask
  has. A chief's picks stay on the team's rows: [Group by Team](group-by-team.md).

## Its page under Tools

One Task has a page of its own on the panel's back, under Tools after Storage. Settings ▸ One Task opens it. It says
what One Task does, then its switch, then a few choices, each with a line on what it does, all set to work as they
are:

- **Who may hand you tasks:** any session, or only a team's chief, offered while Working on Whozmove ▸ Show Teams is
  ticked. Once you've chosen only a team's chief, it stays in sight with Show Teams off too, as then no session may,
  each told it can tick Show Teams or choose Any session. A session that may not is told why when it asks, what it sent
  before waits unseen, and One Task says which sessions can't.
- **What comes first:** a chief's Critical or P0 pick first of all, Critical before P0, then urgent tasks, then a
  chief's other picks in its order, or simply the oldest: a choice offered while Show Teams is ticked too. **Say why
  each is here** (New, off at first) adds a line on why the task in front is first, and lists what's after it by name,
  each with why. **Urgent tasks wait for your Go** (New, on) keeps the task you've seen in front, as below; off,
  something urgent takes the front at once.
- **Talking with the agent:** the talk under each task, on or off, and whether words written while the session works
  go in by themselves once it's free, or wait for **Send Now**.
- **Quiet hours:** at night only what's urgent is said, for everything Whozmove says, not only tasks (see [What needs
  you](notifications.md#quiet-hours)). It isn't dimmed while One Task is off.

A change applies to what comes next: the task you have open stays where it is. Use the Recommended Settings shows once
anything differs from how it starts. While One Task is off, its own choices are dimmed.

## Something urgent while you're on a task

A task you've seen is yours until you leave it: seen once it has been in front for a moment with One Task open, or as
soon as you press anything on it. Nothing takes its place then, not a newer task and not something urgent. It stays
yours when its session rewords it or sends its next step, when you close One Task and open it again, and when Whozmove
restarts. Changed, the foot says who updated it, "just now" or "while you were away"; your comment stays, but a choice
you'd picked, Approve among them, is let go, so nothing you chose on the old words goes with the new ones, and the
foot says to pick again on what you see now. If it goes while you're on it, as when its session ends, the foot says
"“…” no longer waits." rather than it slipping away.

- **Something urgent** asks from a strip under One Task's head, in red: "Urgent from trailmap: Fix the login crash",
  with **Go**, or "2 urgent: Fix the login crash and 1 more". With One Task closed, the line under the header says
  the same, and **Open** goes straight to it.
- **Go** sets the task you're on aside, with everything you'd done on it: the choice you picked, what you ticked and
  typed, the talk's words, where you'd scrolled. Your keys stay free until you click in the urgent one. While you're
  on it, the strip says **‹ Back to** the task you left.
- **Answer it**, and you're back on the task you left exactly as you left it, the next urgent one first if there are
  two. The foot says "Back to …, as you left it", or, if its session updated it meanwhile, that it did, with your
  comment kept and any choice you'd picked let go.
- **Taken back meanwhile:** if the task you set aside was taken back by its session while you were away, you aren't
  brought back to it. The foot says so, with what you'd typed in its Comment box and its talk box, and
  **Copy Your Words**. The same goes for the task you're on, if it stops waiting while it's in front of you.

## Talk with the agent

Under a task, you can ask the session that handed it to you what it's about, or what to press, without leaving One
Task. **Talk with Wren** says whom you're talking to; the box at the foot of One Task, "Ask Wren about this…", is where
you write. Under the box, before you send, a line shows exactly what will go in: your words after a few words naming
the task, as "About your task “Search as you type” (step 2 of 3, On a phone): …". Return sends; Esc leaves the box.

- **Whom it goes to.** The session that sent the task. For a team chief's pick of a member's work, the member, who did
  the work, with your words opened by "About the task Atlas gave me on your work (step 2 of 3)": the chief and the
  step, never the chief's own words, so one session's words never steer another. Before you've asked anything,
  **Wren · Atlas** beside the heading lets you ask the chief instead. Once you've asked, the talk stays with that
  session.
- **When it goes in.** Only while the session sits idle at its prompt, with nothing asked of you, as everything the
  panel types. While it works, your words wait under the task: "Goes to Wren when it finishes", with **Take Back**.
  They go in by themselves once it's done, unless its terminal is the app in front, or it's a Claude Desktop
  conversation, which comes forward only when you press: then **Send Now**, beside Take Back. A request of its own comes first:
  "Wren asks first: Wants to run a command. Answer it on its row, and your words go after", with **Show It**, which
  brings that row into view.
- **How far it got.** "Typed in", then "Sent" once the session's own record shows it took your words, then what it's
  doing as its row says it, then its reply, under your words. If your words were typed in but the session didn't take
  them, or it finished without a reply, **Take Me There** opens its tab. If your words can't be typed in ("Can't type
  into Ghostty", and why) or typing stopped part-way, they're back in the box: the line under it gives the way past
  the reason when there is one (Open Accessibility Settings, say), and **Copy and Go** puts them on the clipboard as
  they'd go in and takes you to the session, to paste them there yourself.
- **While you write.** The line under the box shows all of what will go in. If the task's next step comes in as you
  write, it says so, and Send says **Send about step 3**.
- **The reply.** All of it, in place under your words, however long. Only a reply too long for Whozmove to read whole
  (16,384 characters) says the rest is in the session, with Take Me There. A command or code it gives shows on a line
  of its own, whole when you press it, with **Copy**, which copies exactly that code and none of the words around it,
  however long it is. Nothing in it is ever run. While One Task is out of sight, the line under the header says "Wren
  answered you about Search as you type", with **Open**; beside the folded panel, the reply comes out as the session's
  own, as every reply does.
- **What's kept.** The last ten things you asked about a task, with the task, until it's answered or its session ends.
  Replies are read from the session again; Whozmove keeps none. With each task, when you last read it, so it stays in
  front through a restart; never what you'd typed on it, which a restart lets go.

[Back to Using Whozmove](README.md)
