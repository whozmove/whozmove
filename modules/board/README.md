# The board module

Up next and Team Board, beside the list, for a team a session leads: Up next, every session working now and what
waits in the lead's order, by goal; and Team Board, what's moving, who's on what, its goals and what's done this week,
with what needs you as one line that opens One Task, which answers it
([docs/using/team-board.md](../../docs/using/team-board.md)). It reads each team whole from the team module
(`TeamFacts`, app/contracts/Module.h), never the team file itself, and writes nothing.

## Its pieces

- `app/BoardModule.m` (`BoardModule`):
  - Working on Whozmove ▸ Show Team Board (`showTeamBoard`, off until pressed): the rest of the board is for people
    working on Whozmove until anyone can make a team. Like every team surface, both need Working on Whozmove ▸ Read Team
    Files ticked (the team module's). Unticked, only Up next shows: the chief's line says Up next, Glance turns to Up
    next's All goals, and Team Board isn't among the tools.
  - It tells the page each team, each kind of task's word (`setBoard`, as contracts/Task.h's `TaskKinds` and
    `TaskKindWords` give them), whether the rest of the board shows, and the sessions working now, by id, as the page
    loads, whenever the team module's teams change, which it tells by the array alone, as Show Team Board is pressed,
    and whenever who's working changes.
  - Who's working is counted once the rows are whole, with Work's `SessionWorking` (parts/work), the rule the gear
    counts with: busy and not asking you, compacting, at work in a copy, or with agents in the background. The page
    never reads it from a status itself.
  - Team Board among the tools on the panel's back (order 210), while a session leads a team and Show Team Board is
    ticked: how many of the first team's jobs are moving, its figure, and how many need you (`BoardCard`, by each job's
    `underWay`, the team module's, as `boardWhere` goes by too; a job waiting its turn is neither), and Open Team Board,
    which turns the panel back and opens it (`openBoard`). `--print-board-card [project]` prints it, ticked or not.
- `page/board.js`, plain functions, checked by the page cases:
  - where a job stands (`boardWhere`: up next, on hold, done this week or done before that, the board's own; under way,
    needs you, waiting its turn or moving, as the team module says it is, `underWay`), its words (`boardWhereWord`:
    Needs you and Done its own, a moving or waiting job its step's word, the rest the team module's, `core.teamJob.stageWord`) and
    the counts (`boardCounts`, which the Tools card's figures agree with: tests/rows.sh checks them on the same team);
  - the team shown (`boardTeam`), who's on what (`boardMembers`: members with a job under way, each on the job its
    row speaks for, the team module's `now`, its other jobs counted once each), its goals as tiles (`boardTiles`:
    numbered in the file's order, a heading for how the team works after them with no number, All tasks without
    goals, Other for the rest), what's done this week (`boardDone`), and the stages of its jobs under way
    (`boardStages`: one per step word with jobs at it, in the order of the flows' steps, each in `boardOrder`), with the
    one open folding once it's gone (`boardStageShown`);
  - Up next (`boardUpNext`): every session working now (the gear's count, `core.gear.facts()`, else the ids the app
    counted by the same rule), by when its turn began, those over the gear last, then the lead's queued jobs by their `place`
    (the team module's); which the gear lets in (by place, across every led team), the gear's line among them on All
    goals, Not started 10 minutes after one was let in, and every word; its goals down the side (`boardUpNextShelf`),
    what Take Me There opens beside Not started and an empty view (`boardOpensLead`), whose title line carries Up
    next (`boardLineFor`: the chief's, else the lead's while the chief isn't in the list), which view shows for a goal
    (`boardGoalShown`), each goal's number (`boardNumbers`), and which rows slide as it's drawn again (`boardKept`);
  - the kinds of what needs you (`boardKinds`), how many of those the lead has sent One Task (`boardInOneTask`), what
    Take Me There opens (`boardTakeMe`: the session holding the member's seat, else the one recorded for it, else the
    lead's, else why neither), how many lines a group shows (`boardShown`) and in what order (`boardOrder`: the most
    pressing, Critical, P0, P1 then P2, a job with a priority it doesn't have as P1, then the smallest, then the least
    work, a job without a size or effort as medium, then the longest there; and a member's by where they stand,
    `boardByWhere`); a job's priority it says and colours as the team module does (`core.teamJob.priorityWord`, and
    `core.teamJob.doNow` for Critical and P0, drawn in the colour of something to put right).
- `page/board-view.js`, the drawing:
  - the reader's `board` mode (`core.readerModes.board`): Glance (`boardGlanceHTML`: what needs you, `boardYouHTML`,
    which opens One Task by its view's name while it's in the panel; the figure, `boardHeroHTML`; the strip of stages,
    `boardStagesHTML`, in the kit's chips, the one open pressed (`boardPage.stage`, by its word) with its jobs under it
    and a line saying their order; who's on what, `boardTeamHTML` and `boardMemberHTML`; the tiles, `boardTileHTML`; and
    `boardDoneHTML`), Up next for all goals or one, with its goals down the reader's shelf (`boardQueueHTML`,
    `boardQueueRowHTML`, `boardQueueHeadHTML`, `boardQueueShelfHTML`), the gear's line in its lane between the rows
    (`boardPlaceLine`), its rows coming and going (`boardMove`) and a press on the usage card's seats (`boardGearMove`),
    what the gear has let in, kept whether Up next shows or not (`boardTrackLetIn`, on each `core.gear.changed` and
    setBoard: `boardWatchGear`), and a job's card at the foot (`boardCardHTML`), in the kit's card parts
    (`detailsTitleHTML`) with the row's step track (`stepTrackHTML`, the job turned into it by the team module's
    `core.teamJob.track`); and every job it lists with its priority's chip (`boardPrioHTML`: on its line, the job a
    member is on, Up next's rows and its card);
  - Up next, or Team Board while Show Team Board is ticked, at the end of the chief's line under Group by Team
    (`core.slots.brief`), after the team module's own parts (module order 30). The chief is the team module's to say
    (`chief` in TeamFacts): the session you talk to when the file names one apart from the lead, else the lead. Its
    name is in the heads (`boardChiefSays`) and "Chief" on its working row in Up next; the lead keeps its name
    (`boardLeadName`) for who starts the jobs and what Take Me There opens;
  - its presses (`core.readerPresses`, and `core.presses` for Team Board on the list).
- `page/board.css`.

## Rules

- **It reads, and only through the team module.** The team file has one reader, the team module; the board gets its
  teams through `TeamFacts`, and a job's track, its stage's words and its priority's through `core.teamJob`. It never writes the file,
  nor sends the lead
  anything.
- **Neutral words.** A job is where it is in the board's own plain words (Needs you, Moving, Waiting, Up next, On hold,
  Done), which Group by Team uses too, and a kind in One Task's words; never the file's own stage names or role words.
  A step's word is the file's, as its track and the strip of stages show it.
- **No flows of its own.** The stages are the steps the file gives, in their order; nothing here knows a step by its
  id or word.
- **Take Me There finds a member by its session:** the one its lead leads for that member, by the name the team
  module gives its row, else the one the file records, never a tab's name, and opens it as a row's press does
  (`openSession`).
- **It answers nothing.** What needs you is One Task's to answer; the board only says how many, and opens it.
- **The list's colours for where a job stands:** at work `--busy`, your move `--turn` (words `--turn-words`, or
  `--needs-text` for a Critical or P0 job's step, as `core.teamJob.doNow` says), done `--pr` (words `--done-text`),
  up next, waiting and on hold `--idle`; blue only for what you press.
- **Depth by fill, never a shadow,** and done words in the muted colour: never faded so far they can't be read.
- **Up next's rows move one after another; nothing else moves.** A row that goes fades; those still there then slide
  once, straight to where they end up (measured with the ones coming laid out but unseen); one that comes then fades in
  (`boardMove`, each length written there), so nothing slides through another row's words. The gear's line, when it's
  to be somewhere else, leaves with the rows going and comes back with the ones coming, so no row slides over it. After
  a press on the usage card's seats while Up next shows, its number turns first (the usage module's), then the line
  leaves its gap and draws in at its new one, then each row it passed changes its words, one after another
  (`boardGearMove`); every row keeps the line's room, so no row moves with it. A draw meanwhile waits for them to land;
  reduced motion tells the same story as a cross-fade, with no slide. Glance, Up next and its goals take each other's
  place with the panel's fade; a change in Glance is simply drawn again.
- **The gear is the usage module's, and changed only on the usage card.** Up next draws no seats: one place sets the
  gear. Who's working, the line, what's let in (its `room`) and every word of the gear (`core.gear.words`: Over the
  gear, the line's words for VoiceOver, where to change it), passed into `boardUpNext` with its facts, come from
  `core.gear`; why the line shows only on All goals is in the board's own words; without it, Up next shows the
  sessions the app counted as working, by the gear's own rule, and lets nothing in.
