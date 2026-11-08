# Group by Team

A session can lead a team of other sessions for you: usually the one you talk to, handing out work to the others, each
in a worktree of its own. When it keeps a team file, Whozmove can show the list by team, in short rows saying who does
what, what each needs from you, and where each job stands.

## Turning it on

On the panel's back, **Settings ▸ Session List** offers **Group by Team** beside **Newest First** and **Group by
Project**, while one of the team's sessions is listed. Your pick is kept across launches. While none of the team is
listed, the list shows newest first, as it would without the file; without a team file, nothing changes at all. Whozmove
reads the team file only while **Show Teams** is ticked, in Working on Whozmove ▸ (hold ⌥ as you open the pawn menu):
until then no team shows anywhere.

## The groups

- On top, the session leading the team, marked **Chief**. When the team file names the session you talk to apart from
  the one running the team, that session is on top, marked **Chief**, and the one running the team is right under it,
  unmarked, unless the file puts it in a group, where it's shown as a member is. A member's row shows the name the
  file gives it to show, when it gives one, else its name in the team, and the tag the file gives it, in the look of
  the Chief mark ("Design"), else what it looks after; the one running the team can have a tag too.
- A group for each name the team file gives its members, such as **Reviewers**, in the order the file lists them.
- **Team**: the rest of the team, after those groups, or among them where the file's order names Team.
- **Yours**: your own sessions, the ones the session running the team keeps an eye on among them. Another session open
  where one of the team works is yours too, and says whose folder it's in ("In Wren's folder"); once it has ended, it
  isn't shown, as the member's own row stands for that folder, unless it asks you something, you're on it, or it
  changed that folder's files after the member did, and none of its replies waits on you, under any grouping.

A member is its workspace, the folder the team file records for it alone. A session running there is that member,
under its name, with its job: the one the file records while it runs; else the one that was the member, or the same
tab's conversation after you clear it (/clear); else the one opened first. So clearing a member's conversation, or
opening a new one in its workspace after the old one has closed, keeps the member's row. Close the member's tab, with
nothing else running there, and its row stays where it was, shown as ended: its last conversation there, the one that
was the member (else the one the file records, else the one that moved last). Pressing it, or Take Me There on the
Team Board, carries that conversation on. Each other session running
there stays under Yours, says it's a duplicate ("Duplicate of Wren"), and, under its name, "Close the previous
session" (on the one opened first, "Close this one, the previous session"); pointed at, it says which session is on
Wren's row. Close the earlier one, and one of the others carries on as Wren. The folders of the session running the team
and of the one you talk to, and a folder two of the team share, have no seat: another session there is said to be in
it.

Each group has a header with how many rows it has, and folds with a press on it. A folded group hides all its rows,
even one that needs you, and its header says how many wait on you: "Reviewers › 2 wait on you", in your move's amber,
or in a request's colour while one of them asks for your OK. Opening it shows them. A request in a folded group still
comes out beside the folded panel and counts in the menu bar. In each group, what needs you comes first (a request or
question, a reply you haven't read, or a job waiting on you), then the rest, newest first.

## The rows on top

The session leading the team is marked **Chief**, unless you talk to another session that passes your words on to it.
Either way, the session leading the team says how many jobs wait on you, by how pressing they are, and how many are at
work: "● 1 ● 2 need you ● 3 moving", a Critical or P0 one in the colour of a request, a P1 one in your move's colour,
a P2 one as an empty ring. A job waiting its turn at a step nobody works on ("Ready to try") isn't counted as at work.
Only the counts there are show: with nothing waiting and nothing at work, it says nothing. When it names the next
thing for you to look at, that's its second line, in a few words, as a member's ask is (giving way, as that does, to
something to put right), its button taking you to the member's session it's for, and its counts are on
[Team Board](team-board.md).

## A team member's row

- **Its title line**: its name, as the team names it (not its tab's), what it looks after, its job's steps as a short
  track, and its time. The track has a tick for each step: the ones done in grey, the one it's on in the colour of
  whose move it is (yours, at work, or idle: idle too while the job waits its turn), and the ones to come faint.
- **The line under it**, the first of these that applies:
  - What its job wants of you, in a few words, when it's your move: "P1 Try the search box", in a bubble in the
    colour of how pressing it is (red for Critical and P0, amber for P1, grey for P2), its priority named first.
    **+2** says it holds up two more jobs. At its end is its one button, for what the step asks of you: Deploy for a
    try, when there's a build to put in place; otherwise a button that takes you to the member's session, where it
    waits: the plan's mark for a plan, the prototype's for looks to pick, ? for a question, an eye for something to
    look at, and ↗ for anything else. While it waits, the row shows no other Deploy or context ring: the ring and
    Deploy come back once it's answered. One in your move's colour gives way while the row has something to put
    right, such as Compact at Breaks' "Compacting stopped part-way", or a deploy's note, and comes back once that's
    gone. While the member works on one job and another of its jobs waits on your try or your yes, that one's ask is
    the line, the same way, with its button (Deploy for a try): the track stays on the job it's working on, and that
    job's details open from the track.
  - Any other note on the row, such as a plan sent back for you, or a task the session has handed you itself in One
    Task, with its own button at its end ([One Task](one-task.md#on-the-sessions-row)).
  - Quietly, where its job stands: "Up next: after the search box", "On hold: until the fonts land", "Build: pick the
    fonts", or the step a job waits its turn at ("Ready to try"), in the few words the team file gives, or the stage
    alone; or what the file says the member is busy with apart from its jobs, such as "Reviewing: Wren's search box". It
    has no context ring or Deploy. A member at work on one job speaks for that one, never another of its jobs waiting its turn.
- **What the session asks you itself**, a request, a question or a plan, shows with its card as on any row; meanwhile
  the line saying where its job stands steps aside.

A row has no reply on it: what's new comes out beside the folded panel, and the session itself has the rest.

## Whose move it is

Each row's dot is the list's, saying whose move it is, as under any grouping ([The list](the-list.md#whose-move-it-is)):
a team member's reply to a message from the session leading the team, or from any other session, went to that session,
not to you, so it counts as read. A question the member asks you itself still waits on you, and so does a reply to you
that you hadn't read when the message came, until that conversation ends: a conversation that has ended in a team
member's folder, or in the folder of the session leading the team or the one you talk to, is the member's history,
and none of its replies waits on you. The project's own folder is the exception: your own conversations are there
too, so one that has ended there still waits on you as it would without the team.

## A job's details

Resting on a job's track, or its second line, opens its details in the row: the step it's at and for how long ("Your try
for 30m · needs you"), the job's title (a short one in bold), and what's wanted of you in full. On the row on top,
they say "Next for you", the job it's for, what's next in a few words with the whole of it under them, and the counts in
words. They come from the track and that line only, so moving down the list doesn't open every row on the way.

## Beside the folded panel

What needs you still comes out beside the folded panel, as under any grouping, with its whole row, so it says what's
new: the reply, or what it asks, under the member's name in the team. A reply to the session leading the team doesn't
come out. There the row is shown whole, as without the team, so a member's job waiting on you isn't said on it; a task
the session has handed you is, with its one button at its end. See [The folded panel](folded-panel.md).

**Up next**, at the end of the chief's line, opens every session working now and what waits, in the team's order, by
goal, beside the list. While Working on Whozmove ▸ Show Team Board is ticked it says **Team Board**, and opens every job
of the team: [Team Board](team-board.md).

How the team file is laid out, for a session that keeps one: [The team file](../reference/team.md).

[All of Using Whozmove](README.md) · [Back to the README](../../README.md)
