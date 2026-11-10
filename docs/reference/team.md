# The team file

A session leading a team of other sessions for you (handing out work to the others, each in a worktree of its own) can
tell Whozmove who's on its team by keeping this file. Usually it's the one you talk to; when you talk to another session
that passes your words on to it, the file can name that one too (`front`). With it, while one of its team's sessions
is listed, the list has the team's groups above its projects, in the same short rows as every other:
- the chief on top, marked Chief: the session you talk to;
- the session leading the team, the chief itself unless the file names another you talk to, in which case it's right
  under that one, unmarked, or in the group the file gives it, with how many jobs wait on you and how many are at
  work, and a second line, when it names one, with the next thing for you to look at;
- then the file's groups and its team, each folding to its header, which then says how many wait on you, newest
  first inside each, nothing lifted; your own sessions stay under their projects;
- each row with its name, what it looks after and the job it's on as a short track of its steps;
- and a second line: what its job wants of you in a few words, in the session's own words, with Deploy when the row
  has it;
  else what the session itself asks you; else, quietly, where its job stands ("Up next: after the search box").

What needs you still comes out beside the folded panel with its whole row, so it says what's new: the reply, or what
it asks.

Whozmove only reads the file. It never writes it. Without it, the list is its projects alone. And it reads it only while
Working on Whozmove ▸ Show Teams is ticked (hold ⌥ as you open the pawn menu): until then no team shows anywhere.

It lives at `~/Library/Application Support/Whozmove/team/team.json`, and it's read again whenever it changes. Write it
whole and move it into place, so it's never read half-written. Anything else in it is left alone.

```json
{
  "version": 1,
  "projects": {
    "/Users/you/project": {
      "front": {"session": "…", "worktree": "/Users/you/project", "name": "Iris"},
      "lead": {
        "session": "…", "worktree": "/Users/you/project-worktrees/lead", "name": "Atlas",
        "next": {"short": "Pick a name", "ask": "Pick one of the three names in the plan, so the docs can use it"},
        "queue": [{"id": "search-box-try", "job": "j12"}, {"id": "font-pick"}]
      },
      "members": {
        "Wren": {"session": "…", "worktree": "/Users/you/project-worktrees/docs", "part": "docs", "group": "Reviewers"},
        "Moss": {"session": "…", "worktree": "/Users/you/project-worktrees/fonts", "part": "fonts"}
      },
      "groups": ["Reviewers"],
      "followed": {
        "dark mode": {"session": "…", "worktree": "/Users/you/project-worktrees/dark"}
      },
      "jobs": {
        "j12": {
          "title": "Search box",
          "stage": "test",
          "member": "Wren",
          "steps": [
            {"id": "plan", "word": "Plan", "you": true},
            {"id": "build", "word": "Build", "you": false},
            {"id": "ready", "word": "Ready to try", "you": false, "waits": true},
            {"id": "test", "word": "Your try", "you": true},
            {"id": "merge", "word": "Merge", "you": false}
          ],
          "at": "test",
          "short": "Try the search box",
          "status": "after the release",
          "ask": "Try the search box on a page with a hundred results, and say if it keeps up",
          "priority": "p1",
          "size": "small",
          "effort": "low",
          "dependsOn": ["j9"],
          "stageAt": 1760000000000
        },
        "j13": {
          "title": "Dark mode",
          "stage": "build",
          "followed": "dark mode",
          "steps": [{"id": "build", "word": "Build", "you": false}, {"id": "look", "word": "Look", "you": true}],
          "at": "build",
          "stageAt": 1760000000000
        }
      }
    }
  }
}
```

## Fields

- **`version`**: 1 for this layout.
- **`projects`**: each project, by its folder, with its team.
- **`front`**: the session you talk to, when another session runs the team behind it, if any. Its row is on top,
  marked Chief, with Up next at its end, and the session leading the team comes right under it, unmarked, or in its
  `group`; all the rest stays with the one leading the team. It takes nothing else of the lead's: not its counts, its
  next or its queue, nor the sessions it leads. Left out when it names the lead's own session, or when the file names
  no `lead`.
  - `session` and `worktree`: as the lead's.
  - `name`: what the list calls it.
  - `shown`: the name its row shows, 40 characters at most, as a member's is.
- **`lead`**: the session leading the team; its chief, unless `front` names another session you talk to.
  - `session`: its id, as Claude Code names it.
  - `worktree`: the folder it runs in, or its checkout's top folder.
  - `name`: what the list calls it.
  - `group` and `tag`: while `front` names another session you talk to, a group it's shown in and a tag shown after
    its name, as a member's below; without a group, it's right under the session you talk to. As the chief, it stays
    on top, marked Chief, whatever these say.
  - `next`: the one thing it says is next for you to look at, if any.
    - `short`: two to four words, verb first ("Pick a name"), on its row's second line. The row's Deploy, when it has
      one, sits at the end of that line, as at the end of an ask's line on any row (a line saying where a job stands
      has none), and puts in place what's in the folder it runs in, not a member's.
    - `ask`: the whole of it. Pointing at the row shows it.
    - `job`: the id of the job it's for, if any. Pointing at the row shows the job's title.
    - `priority`: as a job's, below. Without one, the job's.
    - Either `short` or `ask` is enough: without a short, the row says the ask. Without either, there's no second
      line. A task for you goes to One Task with `ask-panel.sh task --pick-for`, named in `queue`.
  - `queue`: the picks it has for you, 100 at most, each `{id, job}`, in its order: the id it gave
    a pick it sent One Task with `ask-panel.sh task --pick-for` ([task.md](task.md)), and the id of the job it's for,
    if any. One Task shows each pick it sent once the queue names it, in its own line: by its member's ticket's
    priority, or, when the member has no ticket, by its job's priority here (none counts as P1), counted from when the
    queue first named it. One taken off the queue keeps waiting, by its member's ticket's priority, else with the
    tasks that have none, until it's answered or the chief takes it back with
    `ask-panel.sh task-withdraw <id> answered|parked|dropped`. The task and the member it's for are what was checked
    as it was sent, never read from here. An id with other than letters, digits, `.`, `_` or `-`, one named twice and
    any past the 100th are left out.
- **`members`**: the team, by name.
  - `session` and `worktree`: its session's id, and the folder it works in.
  - `part`: a word or two for what it looks after, shown beside its name.
  - `group`: a group of your own naming it's shown in ("Reviewers"), 40 characters at most. Each group gets a header
    of its own, after the chief and before Team. Without one, a member is under Team. A name with a character that
    can't be seen, or Team, the group the rest of the team is in, is no group.
  - `tag`: a few words of your own shown after its name in place of its part, in the look of the Chief mark
    ("Design"), 3 words and 30 characters at most (a longer one, or one that hides what it says, is no tag). It's
    only a mark: the member stays in its group, or in Team.
  - `shown`: the name its row shows ("Juniper"), 40 characters at most, so a name the team keeps without spaces
    can show as you'd write it. Without one, its row shows its name in the team.
  - `status` and `doing`: what it's busy with apart from its jobs, if anything ("Wren's search box"), and the word for
    it ("Reviewing"). Its row says it in place of where its job stands: "Reviewing: Wren's search box", or "Moving:
    …" without a word.
- **`groups`**: the order the groups go in, by name. Any not listed follow, A to Z. Naming `Team` among them puts the
  rest of the team there (`["Reviewers", "Team", "Writers"]`); without it, Team comes after every group.
- **`goals`**: what the team's jobs are for, in the order to show them, 50 at most, each `{id, name, due, work}`: an id
  as a pick's is (letters, digits, `.`, `_` or `-`), a name of 40 characters at most, and, if it has one, when it's
  due, in a few words of the file's own ("Fri"). `work: true` makes it a heading for jobs about how the team works
  ("How we work") rather than a goal: Team Board gives it a tile after the goals, with no number, and doesn't count it
  as one. One without a plain id or a name, or with an id named before, is left out.
- **`followed`**: your own sessions the chief keeps an eye on, by name, each with its `session`.
- **`jobs`**: the work handed out, by id.
  - `title`: a few words.
  - `stage`: where it is. `queued`, `parked`, `done` and `dropped` count as not under way; anything else is under way.
  - `member` or `followed`: whose it is, by its name above.
  - `steps`: its steps in order, each `{id, word, you, kind, waits}`. `word` is a word or two to show. `you` says the
    step waits on you, and `kind`, on one that does, what you're asked to do there, in One Task's words
    ([task.md](task.md)): `try`, `pick`, `approve` (a plan or a merge), `answer`, `run`, `do` or `seen`. Any other word
    is left out. `waits: true`, on a step that doesn't wait on you, says nobody works on the job there while it waits
    its turn ("Ready to try"): it counts as waiting, not moving, and its member's line says the step's word, quietly.
    On a step that waits on you, it's left out.
  - `at`: the step it's on.
  - `short`: what's wanted of you in two to four words, verb first ("Try the search box"), while it waits on you: the
    row's second line says it. Without one, it says the step's word.
  - `status`: where it stands in two to five plain words, said after its stage's ("Up next: after the search box",
    "On hold: until the fonts land", "Moving: wider gutters") while nothing of it waits on you. Without one, its
    `short`; without either, the stage's word alone. Its title is only ever in the job's details.
  - `ask`: what's wanted of you in full, while it waits on you; else `decision`, the decision it waits on. The job's
    details show it.
  - `priority`: `critical`, `p0`, `p1` or `p2`, in any case; `p1` when it's missing, and `p2` for any other word. A wait
    that is Critical or P0 shows in the colour of something to put right, a P1 one in your move's colour, and a P2 one
    quietly: its ask's bubble grey, and its dot in the counts on the chief an outline. Its ask names it first.
  - `dependsOn`: the ids of the jobs it waits for. A job shows how many jobs under way wait for it.
  - `stageAt`: when it got there, in seconds or ms since 1970 (a time under 10^11 is taken as seconds).
  - `queuedAt`: when it was queued, the same way; without it, `stageAt`.
  - `doneAt`: when a done one was done, the same way.
  - `goal`: the id of the goal it's for, one of `goals`.
  - `size`: how big it is, `small`, `medium` or `big`; and `effort`: how much work it takes, `low`, `medium` or `high`.
    Team Board lists jobs within a stage by priority, then size (smaller first), then effort (less first). Without
    either, or with any other word, the job counts as medium.
  - A job without `steps` and `at` shows no track.

## Each team as a whole

What one module offers the others, for a view of a whole team (`TeamFacts`, app/contracts/Module.h, the team module's):
each project's team, by its folder, A to Z, as `{project, lead, chief, goals, queue, jobs}`. `lead` is `{session,
name}`, while the file names one; `chief` is the same for the session marked Chief, there with the lead: the `front`
while it keeps its place, else the lead; `queue` is as its row has it ([rows.md](rows.md)'s `team`); `goals` as above.
`jobs` has every job but the dropped ones, in the order of their ids. One under way with its steps is as its member's
row has it (rows.md's `team.job`, with `waits` while its step waits its turn), with `holdsUp`, the ids of the jobs under
way that wait for it, in place of how many. Every one has `{id, title, stage, priority, stageAt}` (`stage` in the file's
own word); one under way has `underWay`, where it is: `you` while its step waits on you, `waiting` while its step waits
its turn, else `work` (a job without steps too), the one rule the session leading the team counts by, which a module
showing a team counts by rather than working it out; and, when the file gives them, `size` and `effort` (one of their
words, above), `goal` (one of the team's goals), `member` (whose it is, by name) with its `session` and its `part`,
`kind` (what the step it's at asks of you, while it waits on you), and `doneAt` for a done one. `now` marks the one job
each member's row speaks for: of those under way, the one being worked on first, else the one that moved last; else one
waiting its turn, the one that moved last; else the next queued, else the parked one that moved last. A queued job of a
team with a chief (its `lead`) has `place`, its place in the chief's order, from 1: the most pressing first, then the
one queued first (`queuedAt`, else `stageAt`; one with neither last), numbered across every team with a chief together,
since the room your gear lets in is one for your account. It's read with the rest of the file, and is the same until the
file changes. `Whozmove --print-teams` prints it ([Print runs](print-modes.md)). `teamsShown`, in the same contract,
says whether teams show now (Working on Whozmove ▸ Show Teams): while they don't, `teams` is empty, and One Task turns
away a lead's picks and offers neither of a chief's choices, but for Only a team's chief while it's chosen.

## Up next, for a team's chief

Up next, beside the list ([Team Board](../using/team-board.md#up-next)), shows every session working now, then the
chief's queued jobs in that order, with your gear's line among them. A chief that starts its queued jobs by itself reads
your gear from `gear.json` in Whozmove's folder ([The usage card](../using/usage.md#your-gear)), and starts as many as
it lets in, in the same order: the most pressing first, then the one queued first. It reads the file this way:
`"off": true`, written while Usage Gear is off in Settings and holding no gear, means no limit, so it starts them all,
as Up next lets them all in; a `gear` that's a whole number from 1 to 30 means that many working at once; anything
else (no file, one it can't read, `gear` null before your first press, or not a whole number) means it starts none of
them by itself, as Up next lets none in with no gear set. A missing file never means no limit: it may be one not
written yet. Up next marks those it lets in "Up
next · Atlas starts it", and one still queued 10 minutes after it was let in "Not started", with Take Me There to the
chief. Jobs waiting on you, on hold or done aren't listed there.

## How sessions are matched

- **A member is its workspace.** In a member's own workspace (its `worktree`: the folder a session runs in, or its
  checkout's top folder, with symlinks resolved), one running session holds the member's seat, and is that member, by
  its name in the team: the session the file records for it while it runs there; else the one that held the seat
  before, while it still runs there, or a new conversation on that one's process (cleared with /clear), and while
  that process runs, nobody else takes the seat; else the one opened first. So a member's conversation cleared, or
  one opened again in its workspace, stays the member, with its job, its group and what the lead may do for it.
  While none runs there, the member is its last conversation there, ended: the one that held the seat (remembered
  only while Whozmove runs), else the one the file records, else the one that moved last. So closing a member's tab
  leaves its row where it was, ended, whichever conversation the file records, and the lead's `leads` and what's
  next for you name that one, as they name a running one.
- **A duplicate.** Each other session running in a member's own workspace is still yours, and says it's a duplicate
  of the member ("Duplicate of Wren"), with a line to close the previous session: the one opened first. Pointed at, it
  says which session is on the member's row. Close the earlier one, and one of the others carries on as the member.
- **Only a member's own workspace.** A folder the file records for two or more of the team, in any of its projects,
  and the lead's and the front's folders seat nobody: another session there is yours, and the list says whose folder
  it's in while it runs. So is a session the file records for anyone, wherever it runs: one running in another
  member's workspace is never seated there or marked a duplicate. One of your own followed sessions counts by its id
  alone. Any other ended session in a member's folder, the file's own among them while another stands for the
  member, is the member's earlier conversation, and so is one ended in the lead's or the front's folder while that isn't
  the project's own folder, where your own conversations are too: nothing in it is yours to read, and it isn't shown
  unless it asks you something, you're on it or have just pressed it, or it
  edited that checkout after the member did. The member's own row stands for that folder.
- **One job per member.** A member's row speaks for one job: one under way, the one being worked on first, else the one
  that moved last (another of its jobs waiting on you meanwhile is its row's ask, with that job's button, its track still the one at work); else one waiting its turn, the one that moved last; else the next queued, the most pressing, then
  the one queued first; else the parked one that moved last. One done or dropped says nothing. While it waits on you,
  its second line says what for; otherwise where it stands, after its stage's word: `queued` "Up next", `parked` "On
  hold", at a step that waits its turn that step's word ("Ready to try"), any other "Moving". That line has no Deploy,
  and steps aside while the session asks you something itself.
- **The counts.** The session leading the team shows how many jobs under way wait on you (as the steps they're at say),
  by priority, and how many are at work (never one at a step that waits its turn), each only when there are some. While
  it names what's next for you, that is its second line, in the colour of its priority as a job's ask is, and the row
  shows no counts: pointing at it says them in words, and they're on Team Board.
- **The name.** A member shows under its name in the file, never its tab's; one of your own, under its session's.
- **Who it leads.** The lead's row lists the sessions of its members, by id (`team.leads` in [rows.md](rows.md)), for
  what acts on its team: for each, the session on its row (holding its seat, or its last conversation there, ended,
  while none runs there), else the one the file records. What's next for you names the same session as the member
  it's for (`next.for`). One of your own sessions it follows is never among them, nor a session that keeps a place
  elsewhere, as below.
- **A session listed twice** keeps one place: the front's, else the lead's, else a member's, else one of your own. The
  other entries for it are left out.
- **A reply to the chief.** A member's reply to a message from the session leading its team, as to one from any other
  session, answers that session, not you, so it counts as read ([The
  list](../using/the-list.md#whose-move-it-is)). So does any reply in a conversation once it has ended in a member's
  folder (the lead's and the front's too), whatever it answered: the member's own row stands for that folder.
