# One Task

The one thing that needs you most, handed to you in one shape whatever it is and whichever project it's from: its
kind (try, pick, approve, answer, run, do, seen), its title, the step it's at, why, what to do and what's
attached, and its answers to pick from, Comment last, sent with Answer. Any session can send one, and ask for your
answer. Only tasks: a session's own request, question or plan stays on its row in the list.

## Its pieces

- `app/contracts/Task.h` (the core's contracts): the task's shape and its check (`TaskFrom`). Only a task that passes
  is kept: its ids plain, its words short and hiding nothing, its command one line, its links the web's.
- `app/OneTaskModule.m`: its face for the core (contracts/Module.h). It answers three asks, which only show you
  something, or take it away again, and so need no switch: `task`, a task sent with ask-panel.sh task (with
  `--pick-for`, a lead's pick), `task-answer`, your answer asked for, and `task-withdraw`, a task taken back. Each session's tasks and answers are kept in `AppDir/one-task/<session>/record.json`, found by the session the
  core found asking, and taken away once the process that sent them has ended, or the session's row has gone (at once
  when that process now runs another listed session, as after a /clear, else after a minute missing). It has the
  print runs `--print-tasks` and `--print-task-asks`.
- In the core, for these asks: `SessionAsk`'s `askShowing:` (an ask that only shows you something needs no switch)
  and `logsItself`, and `SessionAsks` answering `starting:` until the sessions have first been read and while it
  closes, which `ask-panel.sh task-answer --wait` waits through.
- `app/TaskRecord.m`: what it keeps for one session, as plain functions over its record: a task sent (or its next
  step, under the same id, keeping its place in the line, and read once you've read it, `TaskRecordSeen`), up to a ceiling against runaway scripts
  (`TaskMostWaiting`, said in docs/reference/task.md); your answer, and which answers its
  kind has; a comment, which keeps it waiting; Can't Now; the lead's picks (`TaskRecordPick`); what
  task-answer says; and the words that open yours in the talk about a task (`TaskTalkLead`, the lead named only by a
  short plain name, `TaskTalkName`).
- The rest of `app/OneTaskModule.m`: what waits sent to the page (`setTasks`), your answers taken back at the step you
  saw, as it was sent then (`taskAnswer`, `taskPutBack`), a task its session takes back (ask-panel.sh task-withdraw,
  `TaskRecordTakeBackTask`) kept without its buttons until the page lets it go (`taskLetGo`), a command copied and a
  link opened from the task as it was checked (`taskCopy`, `taskOpen`), how it works as its page under Tools sets it
  (`oneTaskWho`, any session or only a team's lead, by `team.leads`; `oneTaskWhy`; `oneTaskWaitForGo`; `oneTaskTalk`),
  each default as One Task recommends, told to the page with what waits, and shown on One Task's page
  under Tools (`appEntries`: a tool, `one-task`, order 205, its switch and three groups of choices, with Use the
  Recommended Settings), which its row in Settings opens; on unless you turn it off, and One Task in the pawn menu
  while something waits, with how many as the page counts them (`oneTaskWaiting`), which opens it (`openOneTask`). And
  the lead's picks: the tasks a team's lead sends itself (ask-panel.sh task --pick-for, `TaskRecordPick`), kept in the
  lead's own record as tasks of their own (`pick`), apart from that ceiling, only for a member whose own row still
  places it on the team, sent again only when the task itself changes, and waiting until answered whatever the lead
  sends next (`pickTasks` remembers each by id); shown once the `team.queue` of its row names them, from when it first
  named each (`TaskRecordQueue`, `placePicks`, `shownAt`). And for the talk, told with each task (`talkOf:`): the words
  that open yours there (`lead`, and for the lead's pick, the member's own, `leadForMember`) and the terminal each
  session it may be with runs in (`terminals`); the talk itself is Side Chat's.
- `page/order.js`: its rules, as plain functions: what waits and in what order (the tasks, by the priority of the
  ticket their session works on, its place in its tracker's own list (`taskPlace`, from the row's `ticket.bound`:
  `priorityAt` of `priorities`), the most pressing first, two trackers compared from the top; a lead's pick whose
  member has no ticket by its job's priority in the queue (`pickPriority`, which the app keeps from the queue, placed
  by the team module, `core.teamJob.priorityPlace`); then those with no place; within each, first come first served,
  a lead's pick from when its queue first named it; Can't Now at the back), which are to do now (`taskDoNow`: a place
  above the middle of its list) and how each is coloured (`taskLook`), whom a task is from
  and its answer goes to ("Atlas's pick, for Wren", or "Atlas" alone for a pick about the lead's own work, told
  apart by session: `taskMember`), the one in front, each kind's answers (`taskChoices`), its buttons and the answer
  each gives, and the line that says a task waits; what each session's row says waits (`taskAsks`: its first task
  but a lead's pick, one put back or one taken back, and how many more). And the talk's: whom it's with (`talkTo`, the
  member or the lead for a lead's pick, at any time), the words that open yours there (`talkOpening`) and where it runs
  (`talkWhere`). The talk is drawn under the task (`taskTalkHTML`): whom it's with, then the place its session's own
  chat goes, which Side Chat draws there and its box at the view's foot (`core.sessionChat.draw`, `oneTaskTalkDraw`),
  with the words that open yours for the task in front; without Side Chat, or with the talk off, there's none. One Task
  never names Side Chat's classes or attributes (its page cases check), and styles only its own elements.
- `page/one-task.js`, `page/one-task-view.js` and `page/one-task.css`: the reader's mode beside the list. A task in
  one shape, with the kit's pieces: its title, step and one line on why, then each part a label over slim lines (a
  plan's own short view, drawn by the plans module through `core.plans.taskHTML`, or as written without it; its
  points or phases; a try's what changed, steps and what to look for), its answer held at the view's foot on
  a long task (`--sticky-foot`). A task you've seen stays in front until you leave it (`taskChooseFront`), seen by
  task, not by step, so through a reword, its next step and a restart (`taskSeen`, kept as `seenAt` on its record;
  `taskOpensOn`): one to do now ahead of it asks from a strip under the head (`taskStripHTML`, the kit's
  `.notice.urgent`), Go
  sets the one you're on aside with all you'd done on it, and answering brings you back as you left it, or, changed
  meanwhile, with only your words (`taskKeptUi`, as on a reword while you're on it). The one you're on leaving the
  line unanswered comes back once its session's row is back, or the foot says it no longer waits once the app no
  longer keeps it (`taskLeft`). A new task slides in; a next step only changes its words. While it isn't in sight, the line under the
  header says a task waits, with Open (a page sender's notice, `core.noticeSenders`); its × folds it to how many wait,
  which opens One Task too, until another task comes. On the session's row in the list, its first
  task as the row's note (`core.rowNotes`, `line`: a line of its own), drawn with the row part's `askLineHTML`, its
  ticket's word in the mark's place and its bubble coloured by `taskLook` (none: your move's colour, with the mark),
  giving way to any other note; pressed (`[data-one-task]`, a pointer target), once seen
  (`ot-row:<session>`), One Task opens at that task. Its one action at its end, by its kind (`TASK_KIND_ACTS`, each
  kind's icon, verb and what a press does, and `taskRowAct` in `page/order.js`; the button `[data-ot-act]`, for the
  step the line says, `<task key>:<sent>`, once seen too, a step sent again under the same id waiting again): Deploy
  for a try (`askAct`, else its session), Copy (`taskCopy`, its tick a moment, `taskCopied`), its page in your browser
  (`taskOpen`), each sent with the step seen so the app does nothing for a later one, its session, or One Task at it;
  never an answer. It offers each kind's icon, verb and what a press does to the other modules through the core
  (`core.taskKinds.act(kind)`), so a team's step shows the same button. Its Take Me There buttons end in the kit's
  `OUT_ICON`.
- `plugin/skills/handing-tasks/`: what every session is told of One Task (`whozmove:handing-tasks`): how to hand you
  a task and read your answer, to take a task back the moment its answer isn't needed, and how to answer what you ask
  about one.
- `tests/test.sh`: `--print-tasks`, compared with `tasks.expected.txt`, the asks for stand-in sessions with
  ask-panel.sh over a real socket (`--print-task-asks`), compared with `asks.expected.txt`, and the page's rules
  (`page-cases.js`), compared with `page.expected.txt`.

## Rules

- A task is only kept and shown, never acted on: Whozmove runs no command and opens no link or file of a task's by
  itself.
- One session never sees or replaces another's tasks or answers: each is kept and found by the session the core found
  asking, never by anything a task says.
- A session's own request, question or plan isn't a task, and can't be sent as one: it stays on its row in the list,
  answered only through that row's card, and never shows in One Task too: a session's own request stays on its row
  only; a task shows in One Task, and its row only points to it. One Task
  counts only tasks, sends no answer for a request and reads none of its tool's input.
- An answer goes back only at the step you saw, and only as one its kind has. A command is only ever copied, a link
  opened only if it's the web's, and a file only if it's one of the writings of the session that sent it, or for a
  team's lead, of its members and the sessions it follows, never of your other sessions, as any session can write
  the team file. It opens in the reader under the session that wrote it, named on its line, by its writing's id.
  Take Me There goes only to the session that sent it, the member it's for, or the one a lead's task is about
  (`about`), among the same sessions as its files, by the row's own open.
- A task goes once the process that sent it ends, or its session's row goes.
- Every part a task has shows (its steps to tick, its command, its choices), so no button acts on something you
  can't see.
- What panel.log keeps: each task sent and each answer's word, never what you typed with it, nor each ask that finds
  no answer yet.
- The talk is its session's own chat, Side Chat's, which sends your words by its own rules; One Task decides only
  whose chat it shows and the words that open yours there, which you see before you send. Whose: the session that sent
  the task, or for the lead's pick, the member the app still sends it for, or the lead you chose; the page decides it,
  from the task as the app sent it, never from anything else on the page. That reaches no further than the
  row's own Side Chat, which any listed session has. The words that open yours name the task as kept, and for a
  member, none of the lead's words and the lead only by a short plain name (`TaskTalkLead`).
