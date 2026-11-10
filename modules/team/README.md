# Team

A team's groups and rows in the list. A session leading a team of other sessions for you can keep a team file in
Whozmove's folder (`team/team.json`, laid out in docs/reference/team.md). With it, the list (one view for everyone,
grouped by project) has the team's groups above the projects, in the same short rows as every other:
- **the session you talk to**, when the file names one apart from the lead (`front`), on top, marked Chief, with Up
  next at its end, and nothing else of the lead's; the lead right under it, unmarked, or in the group the file gives
  it, as a member is, with the tag the file gives it;
- **the lead** on top otherwise, marked Chief, saying how many jobs wait on you in one number, its dot as pressing as
  the most pressing, and how many are at work; when it names the next thing for you to look at, that is its line under
  its name, as a member's ask is, and the counts are on the team board;
- the groups the file names and **its team** (among them when the file's order names Team, else after them), each
  group folding as a project does, its header saying only its name; your own sessions stay under their projects;
- on each row its name (a member's as the team names it), the tag the file gives it, marked with it as Chief is
  ("Design"), else what it looks after, its job's steps as a short track and its time;
- a line under it: when the job waits on you, what's wanted in a few words (the whole ask is in the job's details,
  which open from its track or this line), in the session's own words, never marked as passed on, with how many jobs
  it holds up and the row's Deploy; else, while it's at work on one job and another of its jobs waits on you, that
  one's, the same way, but that the details open from its track only, as they're the job at work's; else, quietly and
  with no Deploy, where its job stands ("Up next: after the search box", or the stage's word alone), or what the file
  says it's busy with apart from its jobs ("Reviewing: Wren's search box"), unless the session asks you something
  itself.

Pointed at, a row with a job under way says who, the job, its step and since when; one whose job is queued or parked,
or under way without steps, who, the job, where it stands and since when; the lead, what's next for you in full, its
job and the counts in words. In each group the rows keep the list's order, newest first: nothing is lifted. A member's
reply to the lead counts as read. Without the file, the list is its projects alone.

## Its pieces

- `app/TeamModule.m`: its face for the core (contracts/Module.h).
  - It gives each row its place in the team (`team`, docs/reference/rows.md) in the work phase.
  - Working on Whozmove ▸ Show Teams (`readTeamFiles`, off until pressed): teams are for people working on Whozmove
    until anyone can make one, so every team surface (a team's groups in the list, the Chief tag, Up next, Team Board,
    a lead's picks in One Task, the answering switches on a lead's row) comes from this module reading the file only
    while it's ticked. Unticked, the file isn't read: no row has a `team` and `teams` is empty. A print run reads the
    file whatever the switch says, except `--print-teams --switch-off`, which prints what there is with it off.
    Another module asks whether teams show through `teamsShown` in `TeamFacts`, never by reading the switch.
- `app/Team.m` (`Team`): reading the file and matching each session to its place.
  - It looks at whether the file has changed no more than twice a second, and reads it again off the main thread when
    it has.
  - It decides who the chief is, in one place (`chief: true` on that row's place, and `chief` in `TeamFacts`): the
    session you talk to when the file names one (`front`) whose session isn't the lead's, while the lead has a
    session, else the lead. The page and the board read that rather than a role; the rest of what the lead does (who
    may hand you tasks, Bring Forward, the switches that answer for you) stays the lead's.
  - It works out each member's job under way: the one being worked on first, so a member at work shows what it's at,
    else the one that moved last; and, while its row speaks for another, the one of its jobs waiting on you that moved
    last (`alsoAsks`, with what its step asks of you, `kind`), which is then the row's ask. And where
    the job its row speaks for stands (`status`): that one, else one waiting its turn at a step that `waits` (said by
    the step's word, its track idle), else the next queued (the most pressing, then the one queued first), else the
    parked one that moved last.
  - It keeps a step's `waits` (one that isn't on you, where nobody works on the job while it waits its turn) and the
    job's at such a step. Where a job under way is, on you, waiting its turn or at work, is decided once (`UnderWayAt`):
    the lead's counts, a member's `status` and each job's `underWay` in `TeamFacts`, which the team board counts by, all
    go by it. It passes on each job's `size` and `effort` to the team board (`SizeOf`, `EffortOf`: one of their three
    words each, else none), never to the row.
  - It reads each job's priority as one of `critical`, `p0`, `p1` or `p2` (`PriorityOf`): the file's word whatever its
    case, `p1` for none and `p2` for a word it doesn't know, so the page only ever sees the four.
  - It counts the jobs for the lead, and finds what it says is next for you (its job's title, and its priority when it
    gives none), and names the session of the member whose job it is (`for`).
  - It reads the lead's queue (`QueueOf`): the ids of the picks it sent One Task itself, in its order,
    100 at most, each with its job's title and priority. It runs no check on a task and names no member there: One
    Task checked both as the pick was sent, and keeps them.
  - It lists the sessions the lead leads (`leads`): its members that keep their place on its team. That is what a
    module acting on a team reads, rather than the team's own words for each role.
  - It keeps each team as a whole, for a module that shows all of one (`TeamFacts`, contracts/Module.h, offered by
    `TeamModule`): its lead, its chief, its goals, its queue and every job but the dropped ones, each as its row has it
    (`JobOf`) with its goal, whose it is and that session, and what it holds up (`HoldsUp`, the one rule for the row's
    count and the board alike), `now` on the job each member's row speaks for (`Before`, the one rule for the row and
    the board's who's on what), and `place` on each queued job of a team with a lead: its place in the lead's order
    (`QueuedBefore`, the rule `Before` uses for queued jobs), numbered across every such team together, as the room your
    gear lets in is one for your account. `--print-teams` prints it.
  - It finds who holds each member's seat, once a pass over every row (`placesOf:`), by one rule (`SeatOf`, which
    `--print-seats` prints for sample cases): in a folder the file records for that member alone, the recorded
    session while it runs there, else the one that held the seat last pass (kept only while the app runs) or a new
    conversation on its process, else the one opened first; every other running one there is a duplicate. With none
    running there, the member is its last conversation there, ended: the one that held the seat last pass, else the
    recorded one, else the one that moved last, kept as the holder so the next pass finds it again. And it puts the
    session on each member's row, running or ended, in for the recorded one among the sessions the lead leads, and in
    what's next for you, on a copy of the lead's place made each pass.
  - It reads a time the file gives in seconds or ms.
  - It finds the group the file puts each member in (`group`), in the file's own words but never one that hides what
    it says or Team, the group the rest of the team is in, the lead's too while it isn't the chief, and the groups' order
    (`groups`, then A to Z), where Team may be named to place the rest of the team: then each member in no group
    carries Team's place (`groupAt`).
  - It reads each member's `tag` (3 words and 30 characters at most, else none), and the lead's while it isn't the
    chief, and the name a member shows (`shown`). A tag is only a mark: it moves no row.
- `page/team.js`: what the team adds to the list.
  - What it offers the other modules through the core (`core.teamJob`): a job's track (`track`, as `jobTrack` gives it)
    and the words for where a job is at each stage (`stageWord`: Moving and Waiting, said by the step's own word when the
    file gives one, Up next, On hold), which the team
    board draws and says too; and a priority's word (`priorityWord`: Critical, P0, P1 or P2) and whether it's to do now
    (`doNow`: Critical and P0, in the colour of something to put right), which the team board and One Task say as the
    list does; and its place in that ladder (`priorityPlace`: `{at, of, look}`, 0 the most pressing, one it doesn't
    know as P1's, with its look), which One Task orders and colours a pick by when its member has no ticket.
  - Plain functions:
    - its groups above the projects (`core.topGroups`, `teamGroups`: the session you talk to, the lead unless the file
      puts it in a group, and the file's own groups and Team in the file's order, each in the list's order, newest
      first, with what's yours handed back as `rest` for its project, and an ended session in a member's folder in
      neither, so it isn't shown);
    - the counts (`teamCountsHTML`, how many wait in one number, its dot the most pressing look among them, and in
      words `teamCountsWords`, which names each priority), the second line (`teamNote`, `teamAskHTML`,
      drawn with the row part's `askLineHTML` as `teamAskLineHTML`, and where a job stands, `teamStatusNote` and
      `teamStatusText`), a job's track (`trackHTML`, `trackNow`, `jobTrack`, drawn with the row's parts' `stepTrackHTML`) and the job's details, from its track and
      its second line, never the whole row (`teamCardHTML`, `teamStatusCardHTML` for a job not under way, and
      `teamNextCardHTML` for what's next on the lead, each title in the details' own shape, `detailsTitleHTML`; see
      [parts/details](../../parts/details/README.md)).
  - Every row in the list is shown briefly (the row part's `row.brief`), but one still starting from the panel. On it,
    the team's words after the name in the brief slot, its job's track at the line's end (`core.slots.titleTrail`,
    past the row's own gap), and its note: the ask's line, a bubble in its priority's colour
    (`waitLook`, given the row as the note's `look`) named first by it, ending in its one action for what its step
    asks of you (`teamAct`, with the kind's icon and verb as One Task offers them, `core.taskKinds`: Deploy for a try,
    and the plan or the looks beside the list for an approve or a pick, each through `askAct` on the member's own row,
    else its session, `[data-team-go]`, once seen, `team-act:<session>`, again for each job, step or
    button, `teamActs`), but that an ask in your move's colour gives way to a note that puts
    something right (Compact at Breaks' "Compacting stopped part-way") or a quiet one, and comes back once it's gone;
    else any other module's note; else where its job stands (`core.rowNotesLast`), which has no Deploy (`end: false`).
    While a member at work on one job has another waiting on you (`alsoAsks`), that one's ask is the note, of class
    `talso` rather than `task`, so the job at work's details don't open from it; its action is seen afresh when it
    turns to another job (`teamActs`). It ends in the plan or the looks beside the list as its own job's ask does,
    whatever the session is doing, so a plan's ask has one shape and one press; what opens says when it's only to
    read (a session at work takes no answer).
  - A duplicate in a member's own workspace says so in the brief slot ("Duplicate of Wren"), pointed at saying which
    session is on the member's row (`duplicateTip`), and, when nothing else is said on its row, a quiet line of its
    own class, with no Deploy, to close the previous session (`duplicateNote`, in `core.rowNotesLast`).
  - A conversation that has ended in a member's folder, the lead's or the front's (`endedInMembersFolder`) is wholly
    not yours to read (`core.notYoursToRead`), so its replies never wait on you, nor count beside
    the pawn, at the edge or beside the folded panel; one kept to read from before stays kept for if it's resumed.
  - A chat beside the folded panel (`row.chat`) is never brief: it's the row whole, so it says what's new (the reply, or
    what it asks), under a member's name in the team. Drawing it leaves what the list's row last showed as it was.
  - A row's dot is the list's, saying whose move it is (classify). A job
    that waits on you shows on its line, its track and the counts, never on the dot, and counts on its folded group's
    header (`waits`). Folded, a group hides all its rows, as every group does, and its header says how many wait on you.
  - What a row shows for the first time counts as just shown (`showAgain`), so its Deploy waits before it takes a
    press: an ask's line that's new.
- `page/team.css`: the tag, the part, the track, the second line, a duplicate's line and the
  counts, in the panel's tokens.
- `module.json` lists them for tools/page.sh.

`tests/test.sh` checks the groups, the counts, the notes, the tracks and a row as it's drawn (`page-cases.js`, with the
page's scripts), and who holds a member's seat for sample cases (`seats-cases.json`, through `--print-seats`). What the
app reads from a sample team file, and the seats it gives the sample sessions, are checked with the rows
(tests/rows.sh).

## Rules

- **Read only.** The file is the lead's. Whozmove only reads it: it never writes it, and runs nothing of the session
  keeping it.
- **A member is its workspace.** In the folder the file records for a member alone, one running session holds its
  seat and is that member, never by its tab's name: the recorded session while it runs there, else the one that held
  the seat or a new conversation on its process (a /clear), else the one opened first (`SeatOf`). With none running
  there, its last conversation there, ended, is the member, so closing its tab keeps its row. Every other session
  running there stays yours, marked a duplicate of the member, with a line to close the previous session. A folder two
  of the team share, the lead's and the front's seat nobody: another session there says whose folder it's in, and so
  does a session the file records for anyone, wherever it runs. Any other that has ended there is the member's earlier
  conversation (in the lead's or the front's folder only when that isn't the project's own, where your own conversations
  are too: Team.m's `history`): nothing in it is yours to read, and it isn't shown unless it asks
  you something, you're on it or have just pressed it, or it edited that checkout after the member did, as the member's
  own row stands for that folder.
- **No flows of its own.** The panel draws a job's steps as the file gives them. A job without them shows no track.
- **Only the file says who's on the team,** and where each works. Claude Code doesn't record which session started a
  `claude` in another terminal, so the panel never works a team out from the sessions it sees: it only seats one of
  them in a member's own workspace.
- **The session you talk to gets no power.** Marked Chief, it is never among the sessions the lead leads, nor answered
  for, nor what Take Me There opens: everything that runs the team stays the lead's.
- **A team adds groups, never changes a row.** Every row is the list's short row with or without the file; the team
  adds its groups above the projects, its words on its own rows, and that a member's reply to the lead isn't yours to
  read, nor a reply in an earlier conversation that has ended in a member's folder.
- **Newest first in every group.** The team's groups keep the list's order (placeRows), nothing lifted for waiting on
  you: its bubble, its dot and the count beside the pawn say so.
