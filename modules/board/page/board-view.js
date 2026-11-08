// The team board, drawn beside the list in the reader's place (core.readerModes.board), about the team's work, never
// answering anything (One Task does): Glance, what needs you as one quiet line that opens One Task, what's moving as one
// bold figure, a strip of the stages its jobs are at, each opening its jobs, who's on what, the goals as tiles and
// what's done this week; Up next, for all goals or one, with the goals down the reader's shelf: every session working
// now, then what waits in the lead's order; and a job's card at the foot, with Take Me There. At the end of the chief's
// title line under Group by Team, Up next opens Up next, or, while Show Team Board is ticked, Team Board opens Glance.
// What's decided is board.js's.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// What the board shows: the team (by its project), Up next's goal ('all', or a tile's key; null: Glance), the member
// whose jobs are open, the stage open under the strip (by its word), the job whose card is open, the groups shown
// whole, what was drawn last (for the fade between views), when each job was let in, by project (boardUpNext's
// `letInAt`, kept in memory only), and whether Up next's rows are moving (a draw that comes meanwhile waits for them:
// `later`).
const boardPage = { project: null, goal: null, member: null, stage: null, job: null, all: new Set(), drawn: null,
                    letIn: new Map(), moving: false, later: false, moves: 0, pressed: false, watching: false };
const BOARD_WIDTH = 760;
// A mark for each kind of what needs you, said in words to VoiceOver (its aria-label): never a colour of its own, as
// the colour stays whose move it is.
const BOARD_MARKS = { try: '▶', pick: '◐', approve: '✓', answer: '?', run: '›', do: '✎', seen: '•' };

const boardReading = () => state.reading?.mode === 'board' && !state.reading.closing;
// Whether the rest of the board shows (Working on Whozmove ▸ Show Team Board): Up next shows whatever it says.
const boardOn = () => state.board?.on !== false;
// The gear's facts (core.gear, the usage module's), or null without it: everything that needs the gear reads this; and
// whether Usage Gear is off in Settings, when every queued job is let in.
const boardGear = () => core.gear?.facts?.() || null;
const boardGearOff = () => !!core.gear?.off?.();
const boardNow = () => state.last?.now || Date.now();
// "needs you" for one, "need you" for more.
const boardNeed = (n) => (n === 1 ? 'needs you' : 'need you');
const boardKindWord = (kind) => state.board?.kinds?.find((k) => k.kind === kind)?.word || 'Your move';

// A job's priority as a chip, wherever the board lists the job, in the team module's words (core.teamJob): in the
// colour of something to do now for Critical and P0, and quieter for P2. Nothing without the team module's words.
function boardPrioHTML(job) {
  const word = job && core.teamJob?.priorityWord(job.priority);
  if (!word) return '';
  const look = core.teamJob.doNow(job.priority) ? ' urgent' : job.priority === 'p2' ? ' quiet' : '';
  return `<span class="tag chip outline bd-prio${look}">${esc(word)}</span>`;
}

// A job's line: its title, where it is (with its kind's mark while it waits on you, else a dot), whose it is (left out
// under its member's own line), its priority, and how long it's been there.
function boardLineHTML(job, team, goalName = '', whose = true) {
  const now = boardNow(), where = boardWhere(job, now), you = where === 'you';
  const mark = you ? `<span class="bd-mark${core.teamJob?.doNow(job.priority) ? ' urgent' : ''}" role="img" `
    + `aria-label="${esc(boardKindWord(job.kind))}">${BOARD_MARKS[job.kind] || '•'}</span>`
    : `<span class="bd-dot ${where}" aria-hidden="true"></span>`;
  const sub = [boardWhereWord(where, job), whose && (job.member || 'No one yet'), goalName].filter(Boolean);
  const since = where === 'done' || where === 'old' ? job.doneAt : job.stageAt;
  return `<button class="bd-line ${where}${boardPage.job === job.id ? ' on' : ''}" data-board-job="${esc(job.id)}">`
    + `${mark}<span class="bd-words"><b>${esc(job.title)}</b><span>${esc(sub.join(' · '))}</span>`
    + `</span>${boardPrioHTML(job)}${since ? `<span class="bd-age">${esc(ago(now - since))}</span>` : ''}</button>`;
}

// A member's other jobs under its line, in the order given, without its name: the first BOARD_SHOWN until Show All.
function boardMemberJobsHTML(key, jobs, team) {
  if (!jobs.length) return '';
  const { jobs: shown, more } = boardShown(jobs, boardPage.all.has(key));
  return `<div class="bd-group bd-mjobs">${shown.map((j) => boardLineHTML(j, team, '', false)).join('')}`
    + (more ? `<button class="button small bd-more" data-board-all="${esc(key)}">Show All ${jobs.length}</button>` : '')
    + '</div>';
}

// Glance's head: its title, the project and its lead, the teams when there's more than one, and ✕.
function boardHeadHTML(team) {
  const close = `<button class="icon-button r-close" title="Close">${CLOSE_ICON}</button>`;
  if (!team) return `<span class="r-title">${boardOn() ? 'Team Board' : 'Up next'}</span><span class="r-sub"></span>${close}`;
  return `<span class="r-title">Team Board</span><span class="r-sub">${esc(boardProjectName(team.project))} · `
    + `${esc(boardChiefSays(team))}</span>${boardTeamsHTML(team)}${close}`;
}

// A chip for each team a session leads, the one shown pressed, when there's more than one.
function boardTeamsHTML(team) {
  const led = (state.board?.teams || []).filter((t) => t.lead);
  return led.length > 1 ? `<span class="bd-teams">${led.map((t) => `<button class="tag chip bd-team" `
    + `data-board-team="${esc(t.project)}" aria-pressed="${t.project === team.project}">`
    + `${esc(boardProjectName(t.project))}</button>`).join('')}</span>` : '';
}

// Up next's head: ‹ back to Glance while Show Team Board is ticked, its title, the project and its lead, the teams
// when there's more than one, and ✕. The gear is changed in one place only, the usage card's seats: Up next shows what
// it lets in.
function boardQueueHeadHTML(team) {
  const back = boardOn() ? '<button class="icon-button small bd-back" data-board-back="1" title="Team Board" '
    + 'aria-label="Team Board">‹</button>' : '';
  return `${back}<span class="r-title">Up next</span><span class="r-sub">${esc(boardProjectName(team.project))} · `
    + `${esc(boardChiefSays(team))}</span>${boardTeamsHTML(team)}`
    + `<button class="icon-button r-close" title="Close">${CLOSE_ICON}</button>`;
}

// What needs you, as one quiet line: how many of the team's jobs wait on you and how many of those the lead has sent
// One Task when that's fewer, each kind's mark with its count; a press opens One Task, while it's in the panel.
function boardYouHTML(team) {
  const now = boardNow(), kinds = boardKinds(team, state.board?.kinds, now);
  const n = kinds.reduce((sum, k) => sum + k.n, 0);
  if (!n) return '<div class="bd-you none"><span class="bd-tick" aria-hidden="true">✓</span>Nothing needs you</div>';
  const sent = boardInOneTask(team, now), opens = !!core.readerModes.oneTask;
  const marks = kinds.map((k) => `<span class="bd-k" role="img" title="${esc(`${k.n} ${k.word}`)}" `
    + `aria-label="${esc(`${k.n} ${k.word}`)}">`
    + `<span class="bd-mark" aria-hidden="true">${BOARD_MARKS[k.kind] || '•'}</span>${k.n > 1 ? k.n : ''}</span>`).join('');
  const go = opens ? `<span class="bd-go">${sent < n ? `${sent} in One Task ›` : 'One Task ›'}</span>`
    : sent < n ? `<span class="bd-go">${sent} in One Task</span>` : '';
  const inner = `<span class="bd-you-w"><b>${n}</b> ${boardNeed(n)}</span><span class="bd-ks">${marks}</span>${go}`;
  return opens ? `<button class="bd-you" data-board-onetask="1">${inner}</button>` : `<div class="bd-you">${inner}</div>`;
}

// The one bold figure, what's moving; and beside it, smaller, what's up next, what waits its turn, said by what it
// waits for (boardWaitingSays, when any), and on hold.
function boardHeroHTML(team) {
  const now = boardNow(), c = boardCounts(team.jobs, now);
  return `<div class="bd-hero"><span class="bd-big">${c.moving}</span><span class="bd-bigw">moving</span>`
    + `<span class="bd-figs"><span><b>${c.next}</b> up next</span>`
    + (c.waiting ? `<span><b>${c.waiting}</b> ${esc(boardWaitingSays(team.jobs, now))}</span>` : '')
    + `<span><b>${c.hold}</b> on hold</span></span></div>`;
}

// What the strip says under the stage open, so the order needs no guessing.
const BOARD_STAGE_ORDER = 'The most pressing first, then the smallest, then the least work.';
// The strip of stages under What's moving: a chip for each step word with jobs at it and how many, told to VoiceOver
// as "Ready to try, 6 jobs" (and "needs you" on one whose step waits on you, as its count's colour says), the first
// BOARD_SHOWN until Show All. Pressed, a stage's jobs show under it, in the board's order, the first BOARD_SHOWN until
// Show All, with a line saying that order; pressed again, they fold. None while no job is at a step, and the stage open
// folds then too, so it never comes back open by itself.
function boardStagesHTML(team) {
  const stages = boardStages(team, boardNow());
  boardPage.stage = boardStageShown(boardPage.stage, stages);
  if (!stages.length) return '';
  const { jobs: shown, more } = boardShown(stages, boardPage.all.has('stages'));
  const chips = shown.map((st) => {
    const n = st.jobs.length, said = `${st.word}, ${n} ${n === 1 ? 'job' : 'jobs'}${st.you ? `, ${boardNeed(n)}` : ''}`;
    return `<button class="tag chip bd-stage${st.you ? ' you' : ''}" data-board-stage="${esc(st.word)}" `
      + `aria-pressed="${boardPage.stage === st.word}" aria-label="${esc(said)}" title="${esc(said)}">`
      + `<span class="bd-stage-word">${esc(st.word)}</span><b>${n}</b></button>`;
  }).join('');
  const open = stages.find((st) => st.word === boardPage.stage);
  const key = open && `stage:${open.word}`, list = open && boardShown(open.jobs, boardPage.all.has(key));
  return '<div class="bd-sec"><div class="bd-sec-h">Stages<span>Press one to see its jobs</span></div>'
    + `<div class="bd-stages">${chips}`
    + (more ? `<button class="button small bd-more" data-board-all="stages">Show All ${stages.length}</button>` : '')
    + '</div>'
    + (open ? `<div class="bd-group bd-stage-jobs">${list.jobs.map((j) => boardLineHTML(j, team)).join('')}`
      + (list.more ? `<button class="button small bd-more" data-board-all="${esc(key)}">Show All ${open.jobs.length}`
        + '</button>' : '')
      + `<div class="bd-stage-why">${BOARD_STAGE_ORDER}</div></div>` : '')
    + '</div>';
}

// A member's line in who's on what: its name and part, the job its row names now with that job's goal, its step and
// track, its other jobs' counts, and how long since the job got where it is; pressed, its other jobs under it (a
// member with none has nothing to press).
function boardMemberHTML(m, team, numbers) {
  const now = boardNow(), job = m.now, where = boardWhere(job, now), open = boardPage.member === m.name;
  const step = job.steps?.find((st) => st.id === job.at);
  const track = step && core.teamJob ? core.teamJob.track(job, 'busy') : null;
  const n = numbers.get(job.goal);
  // A step waiting on you is in your move's colour, or in the colour of something to do now for a Critical or P0 job,
  // as its ask is under Group by Team.
  const doNow = where === 'you' && core.teamJob?.doNow(job.priority) ? ' urgent' : '';
  const counts = [m.you && `<span class="bd-m-you">${m.you} ${boardNeed(m.you)}</span>`, m.moving && `+${m.moving} moving`,
                  m.next && `${m.next} up next`].filter(Boolean).join(' · ');
  const inner = `<span class="bd-who"><b>${esc(m.name)}</b>${m.part ? `<span>${esc(m.part)}</span>` : ''}</span>`
    + `<span class="bd-on">${n ? `<span class="bd-gn">${n}</span>` : ''}<b>${esc(job.title)}</b>${boardPrioHTML(job)}</span>`
    + `<span class="bd-step ${where}${doNow}">${esc(step?.word || boardWhereWord(where, job))}`
    + `${track ? stepTrackHTML(track.count, track.at, track.look) : ''}</span>`
    + `<span class="bd-mcount">${counts}</span>`
    + `<span class="bd-age">${job.stageAt ? esc(ago(now - job.stageAt)) : ''}</span>`;
  if (!m.jobs.length) return `<div class="bd-member">${inner}</div>`;
  return `<button class="bd-member${open ? ' on' : ''}" data-board-member="${esc(m.name)}" aria-expanded="${open}">`
    + `${inner}</button>`
    + (open ? boardMemberJobsHTML(`member:${m.name}`, boardByWhere(m.jobs, now), team) : '');
}

function boardTeamHTML(team) {
  const members = boardMembers(team, boardNow()), numbers = boardNumbers(team);
  const head = `<div class="bd-sec-h">Who’s on what<span>${esc(boardChiefSays(team))}</span></div>`;
  if (!members.length) return `<div class="bd-sec">${head}<div class="bd-quiet">No one’s on a job now.</div></div>`;
  const { jobs: shown, more } = boardShown(members, boardPage.all.has('members'));
  return `<div class="bd-sec">${head}<div class="bd-team">${shown.map((m) => boardMemberHTML(m, team, numbers)).join('')}`
    + (more ? `<button class="button small bd-more" data-board-all="members">Show All ${members.length}</button>` : '')
    + '</div></div>';
}

// A goal's tile: its number (none for a heading or for jobs under none), its name and when it's due, a bar of its jobs
// by where they stand, and how many need you (when any), are moving and are done, of how many; said to VoiceOver as one
// line, with how many wait their turn when any do, by what they wait for, as the bar draws them.
function boardTileHTML(tile) {
  const now = boardNow(), c = boardCounts(tile.jobs, now), done = c.done + c.old;
  const parts = [['you', c.you], ['moving', c.moving], ['waiting', c.waiting], ['next', c.next], ['hold', c.hold],
                 ['done', done]].filter(([, n]) => n);
  const name = tile.n ? `Goal ${tile.n}, ${tile.name}` : tile.name;
  const said = c.all ? `${name}: ${c.you ? `${c.you} ${boardNeed(c.you)}, ` : ''}${c.moving} moving, `
    + `${c.waiting ? `${c.waiting} ${boardWaitingSays(tile.jobs, now)}, ` : ''}${done} done, `
    + `${c.all} ${c.all === 1 ? 'job' : 'jobs'}`
    : `${name}: no jobs yet`;
  return `<button class="bd-tile${tile.key === 'none' ? ' none' : ''}" data-board-goal="${esc(tile.key)}" `
    + `aria-label="${esc(said)}"><span class="bd-tile-top">${tile.n ? `<b class="bd-tile-n">${tile.n}</b>` : ''}`
    + `<span class="bd-tile-name">${esc(tile.name)}</span>`
    + (tile.due ? `<span class="bd-tile-due">${esc(tile.due)}</span>` : '') + '</span>'
    + `<span class="bd-bar" aria-hidden="true">${parts.map(([where, n]) => `<i class="${where}" style="flex:${n}"></i>`)
      .join('')}</span>`
    + `<span class="bd-tile-q">${c.all ? (c.you ? `<span><b class="you">${c.you}</b> ${boardNeed(c.you)}</span>` : '')
      + `<span><b class="moving">${c.moving}</b> moving</span>`
      + `<span><b class="done">${done}</b> done</span><span class="bd-tile-all">${c.all} ${c.all === 1 ? 'job' : 'jobs'}</span>`
      : 'No jobs yet'}</span></button>`;
}

// What's done this week, newest first: the first few, then Show All; left out when nothing was.
function boardDoneHTML(team) {
  const done = boardDone(team, boardNow());
  if (!done.length) return '';
  const { jobs: shown, more } = boardShown(done, boardPage.all.has('done'), BOARD_DONE_SHOWN);
  return `<div class="bd-sec"><div class="bd-sec-h">Done this week<span>${done.length}</span></div>`
    + `<div class="bd-group done">${shown.map((j) => boardLineHTML(j, team)).join('')}`
    + (more ? `<button class="button small bd-more" data-board-all="done">Show All ${done.length}</button>` : '')
    + '</div></div>';
}

function boardGlanceHTML(team) {
  return boardYouHTML(team) + boardHeroHTML(team) + boardStagesHTML(team) + boardTeamHTML(team)
    + `<div class="bd-sec"><div class="bd-sec-h">Goals</div><div class="bd-tiles">${boardTiles(team).map(boardTileHTML)
      .join('')}</div></div>` + boardDoneHTML(team);
}

// Take Me There to the lead's session: beside a job let in and not started, which it starts, and beside an empty view,
// whose jobs it puts there.
function boardTakeLeadHTML(team) {
  const take = boardOpensLead(team, state.last?.sessions || []);
  return take.session ? `<button class="button small bd-q-take" data-board-take="${esc(take.session)}">`
    + `${esc(take.again ? `Open ${take.name} Again` : 'Take Me There')}</button>`
    : `<span class="bd-q-why">${esc(take.why)}</span>`;
}

// One row of Up next: its dot, its goal's number (All goals only: "–" for none), who and what, how pressing a job
// waiting is, and where it stands against the gear. A press opens a job's card, or the session of one with no job of
// the team's; Take Me There sits beside a job not started.
function boardQueueRowHTML(row, team, all) {
  const n = !all ? '' : row.n ? `<span class="tag bd-gn" role="img" aria-label="Goal ${row.n}">${row.n}</span>`
    : '<span class="tag bd-gn" role="img" aria-label="No goal">–</span>';
  // A session the gear counts that isn't in the list has nothing to open: its row is words only.
  const press = row.job ? `data-board-job="${esc(row.job.id)}"`
    : row.listed !== false ? `data-board-take="${esc(row.session)}"` : '';
  const tag = press ? 'button' : 'div';
  const st = row.over ? 'over' : row.notStarted ? 'not' : row.letIn ? 'through' : row.kind === 'working' ? 'moving' : '';
  return `<div class="bd-q ${row.kind}${row.job && boardPage.job === row.job.id ? ' on' : ''}" data-key="${esc(row.key)}">`
    + `<${tag} class="bd-q-in"${press ? ` ${press}` : ''}><span class="bd-dot ${row.kind === 'working' ? 'moving' : 'next'}" `
    + 'aria-hidden="true"></span><span class="bd-q-main"><span class="bd-q-l1">'
    + `${n}<b>${esc(row.who)}</b><span class="bd-q-what">${esc(row.what)}</span>`
    + boardPrioHTML(row.job)
    + `</span><span class="bd-q-st${st ? ` ${st}` : ''}">${esc(row.says)}</span></span></${tag}>`
    + (row.notStarted ? boardTakeLeadHTML(team) : '') + '</div>';
}

// Up next, for all goals or one: the gear's line, why and where to change it, the view's count, every session working
// now and what waits, with the gear's line among them on All goals, and what's under it.
function boardQueueHTML(team, goal) {
  const gear = boardGear(), now = boardNow(), all = goal === 'all';
  const q = boardUpNext(team, gear, state.last?.sessions || [], state.board?.working, goal, now,
                        boardPage.letIn.get(team.project), core.gear?.words, boardGearOff());
  boardPage.letIn.set(team.project, q.letInAt);
  // The gear's line with how many are working, as Up next has no seats to light, and why, in the usage module's words
  // (core.gear.line and whyLine), then where to change it, in the usage module's words too (core.gear.words.where), as
  // Up next carries no seats; with Usage Gear off, those words alone, in the line's place.
  const said = gear ? core.gear.line(gear) : null;
  const where = core.gear?.words?.where?.(gear) || '';
  const top = (said ? `<div class="bd-q-gear">${esc(said.says)}${said.over ? `<span>${esc(said.over)}</span>` : ''}`
    + `</div><div class="bd-q-whyline">${esc(core.gear.whyLine(gear, now))}</div>` : '')
    + (where ? `<div class="bd-q-where">${esc(where)}</div>` : '');
  // The gear's line, its number in a lane of its own: only on All goals, with a gear set. Every row keeps the line's
  // room under it, and the line sits in the gap before row `at` (boardPlaceLine), so the line moving moves no row.
  const line = q.line === null ? '' : `<div class="bd-q-line" data-at="${q.line}" role="img" `
    + `aria-label="${esc(q.lineSays)}"><span class="bd-q-pill">${gear.gear}</span><i></i></div>`;
  const rows = q.rows.map((r) => boardQueueRowHTML(r, team, all));
  // In reading order after the rows within the gear, for VoiceOver; boardPlaceLine puts it in its gap. The lanes are
  // there whenever the gear is known on All goals, so the line's first coming moves no row either.
  if (line) rows.splice(q.line, 0, line);
  return `${top}<div class="bd-q-says">${esc(q.says)}</div>`
    + (q.rows.length ? `<div class="bd-q-list${all && gear ? ' lane' : ''}">${rows.join('')}</div>` : '')
    // Empty, it says what shows here and who puts it there, with the way to that lead.
    + (q.empty ? `<div class="bd-quiet bd-q-empty"><span>${esc(q.empty)}</span>${boardTakeLeadHTML(team)}</div>` : '')
    + (q.rows.length ? `<div class="bd-q-note">${esc(q.note)}</div>` : '');
}

// Up next's goals down the reader's shelf: All goals, then each goal with its number and how many are working on it.
function boardQueueShelfHTML(team, open) {
  const shelf = boardUpNextShelf(team, boardGear(), state.last?.sessions || [], state.board?.working, boardNow());
  if (!shelf.length) return '';
  return '<div class="r-group caps">Goals</div>' + shelf.map((g) => `<button class="r-item bd-goal`
    + `${g.key === open ? ' on' : ''}" data-board-goal="${esc(g.key)}"><span class="bd-goal-n">${g.n || ''}</span>`
    + `<span class="r-name">${esc(g.name)}</span><span></span><span class="r-meta">${g.working} working</span></button>`)
    .join('');
}

// A job's card at the foot: where it is and for how long, whose it is, its title, its track, what it wants of you, what
// it holds up, and Take Me There (its member's session, else the lead's, else why neither).
function boardCardHTML(team) {
  const job = team.jobs.find((j) => j.id === boardPage.job);
  if (!job) return '';
  const now = boardNow(), where = boardWhere(job, now), since = where === 'done' || where === 'old' ? job.doneAt
    : job.stageAt;
  const track = job.steps && core.teamJob ? core.teamJob.track(job, 'idle') : null;
  const titles = new Map(team.jobs.map((j) => [j.id, j.title]));
  const holds = (job.holdsUp || []).map((id) => titles.get(id)).filter(Boolean);
  const take = boardTakeMe(job, team, state.last?.sessions || []);
  return `<div class="bd-card"><div class="card-head"><span>${esc(boardWhereWord(where, job))}`
    + `${since ? ` for ${esc(ago(now - since))}` : ''}</span>${boardPrioHTML(job)}<span class="end">${esc([job.member || 'No one yet',
      job.part].filter(Boolean).join(' · '))}</span><button class="icon-button small bd-card-x" data-board-shut="1" `
    + `title="Close">${CLOSE_ICON}</button></div>${detailsTitleHTML(job.title)}`
    + (track ? `<div class="bd-track">${stepTrackHTML(track.count, track.at, track.look)}</div>` : '')
    + (where === 'you' && job.ask ? `<div class="card-lead ${core.teamJob?.doNow(job.priority) ? 'warn' : 'turn'}">`
      + `${esc(job.ask)}</div>` : '')
    + (holds.length ? `<div class="card-lead">Holds up ${esc(holds.join(', '))}</div>` : '')
    + `<div class="bd-take">${take.why ? `<span>${esc(take.why)}</span>` : ''}`
    + (take.session ? `<button class="button small main" data-board-take="${esc(take.session)}">`
      + `${esc(take.again ? `Open ${take.name} Again` : 'Take Me There')}</button>` : '') + '</div></div>';
}

// How long Up next's rows take as they come and go: one going fades; the rest then slide once, from where they were
// straight to where they end up, into its room and out of the way of one coming, which then fades in. One after
// another, so nothing slides through words, and nothing moves twice.
const BOARD_GO_FADE = 120, BOARD_SLIDE = 300, BOARD_COME_FADE = 150;

// The gap the gear's line sits in, between rows (as tall as .bd-q-list.lane's row gap).
const BOARD_LANE = 12;
// The gear's line put in the gap before row `at` (after the last, for all of them), and in reading order there.
function boardPlaceLine(body) {
  const line = body.querySelector('.bd-q-line');
  if (!line) return;
  const rows = body.querySelectorAll('.bd-q-list > .bd-q'), at = Number(line.dataset.at);
  const last = rows[rows.length - 1];
  if (at < rows.length) {
    if (line.nextElementSibling !== rows[at]) rows[at].before(line);
  } else if (line.previousElementSibling !== last) last.after(line);
  line.style.top = `${at < rows.length ? rows[at].offsetTop - BOARD_LANE : last.offsetTop + last.offsetHeight}px`;
}

// Whether the gear's line is somewhere else, or says something else, once `next` is drawn: its gap, its number, or a
// row coming, going or moving above it.
function boardLineMoves(body, next, stay) {
  const line = body.querySelector('.bd-q-line'), to = next.querySelector('.bd-q-line');
  if (!line !== !to) return true;
  if (!line) return false;
  if (line.dataset.at !== to.dataset.at || line.textContent !== to.textContent) return true;
  const above = (root, at) => [...root.querySelectorAll('.bd-q-list > .bd-q')].slice(0, Number(at))
    .map((el) => el.dataset.key);
  return above(body, line.dataset.at).some((k) => !stay.has(k)) || above(next, to.dataset.at).some((k) => !stay.has(k));
}

// How long a press on the gear's seats on the usage card takes in Up next, while it shows beside the list: the gear's
// number first (the usage module's, 160 ms), then the line leaves its old gap (120 ms) and draws in at its new one
// (200 ms), then each row the line passed says its new words, one after another (out 80 ms, in 120 ms, each 60 ms after
// the one before). No row moves: each keeps the line's room.
const BOARD_NUMBER = 160, BOARD_LINE_OUT = 120, BOARD_LINE_IN = 200, BOARD_WORDS_OUT = 80, BOARD_WORDS_IN = 120,
  BOARD_WORDS_STEP = 60;

// Up next after your press on the usage card's seats, where its rows stay: the line moves, then the words change, then
// what's drawn is the new view. Anything else that changed (a row coming or going) is drawn by boardMove.
async function boardGearMove(body, html) {
  const next = document.createElement('div');
  next.innerHTML = html;
  const keys = (root) => [...root.querySelectorAll('.bd-q-list > .bd-q')].map((el) => el.dataset.key).join(' ');
  if (keys(body) !== keys(next)) return boardMove(body, html);
  boardPage.moving = true;
  const id = ++boardPage.moves;
  const step = async (moves) => {
    await Promise.all(moves);
    if (id !== boardPage.moves || !boardReading()) throw new Error('called off');
  };
  const wait = (ms) => new Promise((done) => setTimeout(done, ms));
  try {
    await step([wait(BOARD_NUMBER)]);
    let line = body.querySelector('.bd-q-line');
    const to = next.querySelector('.bd-q-line'), first = !line && !!to;
    // The first gear you set brings the line in: into its lanes, which were there already, drawing in as below.
    if (first) {
      line = to.cloneNode(true);
      line.style.opacity = '0';
      body.querySelector('.bd-q-list')?.append(line);
      boardPlaceLine(body);
    }
    if (line && to && (first || line.dataset.at !== to.dataset.at || line.textContent !== to.textContent)) {
      const rule = line.querySelector('i'), pill = line.querySelector('.bd-q-pill');
      if (!first) {
        await step([rule.animate([{ opacity: 1 }, { opacity: 0 }], { duration: BOARD_LINE_OUT, easing: 'ease-out',
                                                                      fill: 'forwards' }).finished,
                    pill.animate([{ opacity: 1 }, { opacity: 0 }], { duration: BOARD_LINE_OUT, easing: 'ease-out',
                                                                      fill: 'forwards' }).finished]);
      }
      line.style.opacity = '';
      line.dataset.at = to.dataset.at;
      line.setAttribute('aria-label', to.getAttribute('aria-label'));
      pill.textContent = to.querySelector('.bd-q-pill').textContent;
      boardPlaceLine(body);
      await step([rule.animate([{ opacity: 1, transform: 'scaleX(0)' }, { opacity: 1, transform: 'scaleX(1)' }],
                               { duration: BOARD_LINE_IN, easing: MORPH_EASE, fill: 'forwards' }).finished,
                  pill.animate([{ opacity: 0 }, { opacity: 1 }], { duration: BOARD_LINE_IN, easing: 'ease-out',
                                                                    fill: 'forwards' }).finished]);
    }
    // Then the words of each row the line passed, top to bottom, and the count over them with the first.
    const now = new Map([...next.querySelectorAll('.bd-q-list > .bd-q')].map((el) => [el.dataset.key, el]));
    const changed = [...body.querySelectorAll('.bd-q-list > .bd-q')].filter((el) => {
      const to = now.get(el.dataset.key)?.querySelector('.bd-q-st');
      return to && el.querySelector('.bd-q-st').outerHTML !== to.outerHTML;
    });
    const says = [['.bd-q-says'], ['.bd-q-gear'], ['.bd-q-whyline']].map(([sel]) => [body.querySelector(sel),
                                                                                    next.querySelector(sel)]);
    const swap = async (el, to, delay) => {
      await wait(delay);
      if (id !== boardPage.moves) return;
      await el.animate([{ opacity: 1 }, { opacity: 0 }], { duration: BOARD_WORDS_OUT, easing: 'ease-out',
                                                           fill: 'forwards' }).finished;
      if (id !== boardPage.moves) return;
      el.replaceWith(to);
      await to.animate([{ opacity: 0 }, { opacity: 1 }], { duration: BOARD_WORDS_IN, easing: 'ease-out' }).finished;
    };
    await step([...says.filter(([a, b]) => a && b && a.outerHTML !== b.outerHTML).map(([a, b]) => swap(a, b, 0)),
                ...changed.map((el, i) => swap(el.querySelector('.bd-q-st'),
                                               now.get(el.dataset.key).querySelector('.bd-q-st'),
                                               i * BOARD_WORDS_STEP))]);
    body.innerHTML = body.dataset.drawn = html;
    boardPlaceLine(body);
  } catch {
    return;
  } finally {
    if (id === boardPage.moves) boardPage.moving = false;
  }
  boardLanded();
}

// Up next drawn again where it was: the rows that went fade, those still there slide to their new places, and the ones
// that came fade in. A row whose place among the others changed goes and comes rather than sliding past them, so
// nothing slides through another row's words. Under reduced motion it's the same story as a cross-fade: nothing
// slides. A draw that comes meanwhile waits for them to land.
async function boardMove(body, html) {
  const keyed = (root) => new Map([...root.querySelectorAll('.bd-q-list > [data-key]')].map((el) => [el.dataset.key, el]));
  const was = keyed(body), next = document.createElement('div');
  next.innerHTML = html;
  const coming = keyed(next), stay = boardKept([...was.keys()], [...coming.keys()]);
  // The gear's line, when it's to be somewhere else, leaves with the rows going and comes back with the ones coming:
  // its lane is cleared before rows slide, so none passes over its words.
  const lineMoves = boardLineMoves(body, next, stay), oldLine = lineMoves ? body.querySelector('.bd-q-line') : null;
  const goers = [...was].filter(([k]) => !stay.has(k)).map(([, el]) => el).concat(oldLine ? [oldLine] : []);
  boardPage.moving = true;
  // Each step goes on only while this is still the move under way and the board still shows: a view changed under it,
  // or the reader turned to something else, calls it off (boardDraw, and the mode's reset and closed).
  const id = ++boardPage.moves;
  const step = async (moves) => {
    await Promise.all(moves);
    if (id !== boardPage.moves || !boardReading()) throw new Error('called off');
  };
  try {
    if (goers.length) {
      await step(goers.map((el) => el.animate([{ opacity: 1 }, { opacity: 0 }],
        { duration: BOARD_GO_FADE, easing: 'ease-out', fill: 'forwards' }).finished));
    }
    // Where each row still there was, with the ones going still in their places, so it slides once from there.
    const tops = new Map([...was].filter(([k]) => stay.has(k)).map(([k, el]) => [k, el.getBoundingClientRect().top]));
    body.innerHTML = body.dataset.drawn = html;
    boardPlaceLine(body);
    const newLine = lineMoves ? body.querySelector('.bd-q-line') : null;
    const now = keyed(body), comers = [...now].filter(([k]) => !stay.has(k)).map(([, el]) => el)
      .concat(newLine ? [newLine] : []);
    // The ones coming are laid out whole but unseen, so the rest are measured where they end up and slide straight
    // there, never pushed on again as one opens.
    for (const el of comers) el.style.opacity = '0';
    if (!calm.matches) {
      await step([...now].filter(([k]) => tops.has(k)).map(([k, el]) => {
        const by = tops.get(k) - el.getBoundingClientRect().top;
        return by ? el.animate([{ transform: `translateY(${by}px)` }, { transform: 'none' }],
                               { duration: BOARD_SLIDE, easing: MORPH_EASE }).finished : null;
      }));
    }
    await step(comers.map((el) => {
      el.style.opacity = '';
      return el.animate([{ opacity: 0 }, { opacity: 1 }], { duration: BOARD_COME_FADE, easing: 'ease-out' }).finished;
    }));
    boardPlaceLine(body);
  } catch {
    // Called off: what's drawn now is another view's, so nothing more is done here.
    return;
  } finally {
    if (id === boardPage.moves) boardPage.moving = false;
  }
  boardLanded();
}

// Landed: rows have just moved under the pointer, so a press on one waits a beat (justShown), and the reader takes the
// height they've come to, measured now they're still.
function boardLanded() {
  state.shownAt['board:upnext'] = Date.now();
  if (boardPage.later) {
    boardPage.later = false;
    drawReader();
  } else {
    fitReader();
    syncHover();
  }
}

// A move called off: the rows stop where they are, and the next draw is whole.
function boardStopMove() {
  boardPage.moves++;
  boardPage.moving = boardPage.later = false;
  reader.querySelector('.r-body')?.getAnimations({ subtree: true }).forEach((a) => a.cancel());
}

function boardDraw() {
  const r = state.reading, team = boardTeam(state.board, boardPage.project);
  boardPage.goal = boardGoalShown(boardPage.goal, team ? boardTiles(team) : [], boardOn());
  const goal = team ? boardPage.goal : null;
  const shelf = goal ? boardQueueShelfHTML(team, goal) : '';
  reader.querySelector('.r-in')?.classList.toggle('bd-in-goal', !!shelf);
  putHTML(reader.querySelector('.r-head'), goal ? boardQueueHeadHTML(team) : boardHeadHTML(team));
  putHTML(reader.querySelector('.r-shelf'), shelf);
  const body = reader.querySelector('.r-body');
  const html = `<div class="bd">${!state.board ? '<div class="bd-quiet">Reading the team file…</div>'
    : !team ? '<div class="bd-quiet">This team isn’t in the team file any more.</div>'
      : goal ? boardQueueHTML(team, goal)
        : !team.jobs.length ? '<div class="bd-quiet">Nothing on this team’s board yet: its chief adds jobs to the team '
          + 'file.</div>' : boardGlanceHTML(team)}</div>`;
  const view = `${team?.project}:${goal ?? ''}`;
  if (boardPage.moving) {
    // Up next's rows are still moving: drawn once they've landed, unless the view itself changed.
    if (boardPage.drawn === view) boardPage.later = true;
    else boardStopMove();
  }
  if (body.dataset.drawn !== html && !boardPage.moving) {
    const pressed = boardPage.pressed;
    boardPage.pressed = false;
    // Up next drawn again where it was moves its rows (boardMove), as a cross-fade under reduced motion.
    if (goal && boardPage.drawn === view && body.querySelector('.bd-q-list')) {
      (pressed && !calm.matches ? boardGearMove : boardMove)(body, html);
    } else {
      body.innerHTML = body.dataset.drawn = html;
      boardPlaceLine(body);
      // Glance, Up next and its goals take each other's place as the panel's views do: fading in, lifting 3px. For
      // Glance, a change in what the file says is simply drawn: nothing travels.
      if (boardPage.drawn && boardPage.drawn !== view && !calm.matches) {
        body.querySelector('.bd')?.animate([{ opacity: 0, transform: 'translateY(3px)' },
                                            { opacity: 1, transform: 'none' }], { duration: 300, easing: MORPH_EASE });
      }
    }
    boardPage.drawn = view;
  }
  putHTML(reader.querySelector('.r-answer'), team ? boardCardHTML(team) : '');
  r.ready = true;
  // While rows move the reader keeps its height: it's measured once they've landed (boardMove).
  if (boardPage.moving) return;
  fitReader();
  syncHover();
}

core.readerModes.board = {
  sessionless: true,
  width: () => BOARD_WIDTH,
  draw: boardDraw,
  shown() {
    Object.assign(boardPage, { member: null, stage: null, job: null, all: new Set(), drawn: null });
  },
  reset() {
    boardStopMove();
    reader.querySelector('.r-in')?.classList.remove('bd-in-goal');
  },
  closed() {
    boardStopMove();
    reader.querySelector('.r-in')?.classList.remove('bd-in-goal');
  },
  cls: 'k-board',
};

// The board on `project`'s team, from Up next or Team Board on its chief's line; pressed again on the team it shows, it
// closes.
function boardToggle(project) {
  if (boardReading() && boardPage.project === project) return closeReader();
  window.openBoard(project, boardOn() ? null : 'upnext');
}

// When each led team's jobs were let in, kept whether Up next shows or not, so Not started comes 10 minutes after the
// gear let one in, never after the view was opened: looked at whenever the gear or the teams change, as nothing else
// lets a job in.
function boardTrackLetIn() {
  const gear = boardGear(), now = Date.now();
  for (const team of (state.board?.teams || []).filter((t) => t.lead)) {
    const q = boardUpNext(team, gear, state.last?.sessions || [], state.board.working, 'all', now,
                          boardPage.letIn.get(team.project), core.gear?.words, boardGearOff());
    boardPage.letIn.set(team.project, q.letInAt);
  }
}

// The gear's changes (core.gear.changed, the usage module's): what's let in is looked at again, and Up next drawn again
// at once, after your press on the usage card with the line's motion (boardGearMove). Watched from the first setBoard,
// as the usage module's scripts load after the board's.
function boardWatchGear() {
  if (boardPage.watching || !core.gear) return;
  boardPage.watching = true;
  core.gear.changed.push((facts, pressed) => {
    boardTrackLetIn();
    if (!boardReading()) return;
    boardPage.pressed = boardPage.pressed || !!pressed;
    drawReader();
  });
}

// The teams, the kinds' words, whether the rest of the board shows (Working on Whozmove ▸ Show Team Board: Up next
// shows either way; turned off while Glance shows, it turns to Up next's All goals, boardDraw), and the sessions working
// now, by id.
window.setBoard = (teams, kinds, on, working) => {
  state.board = { teams: teams || [], kinds: kinds || [], on: on !== false, working: working || [] };
  boardWatchGear();
  boardTrackLetIn();
  if (boardReading()) drawReader();
};

// The board on `project`'s team: Glance, or with `view` 'upnext', Up next's All goals.
window.openBoard = (project, view) => {
  Object.assign(boardPage, { project, goal: view === 'upnext' ? 'all' : null, member: null, stage: null, job: null });
  if (boardReading()) return drawReader();
  toggleReader(null, null, 'board');
};

// At the end of the chief's title line, under Group by Team (its brief row), or the lead's while the chief isn't in
// the list (boardLineFor): Up next, or Team Board while Show Team Board is ticked.
core.slots.brief.push((row) => {
  const team = (state.board?.teams || [])
    .find((t) => boardLineFor(t, state.last?.sessions || []) === row.s.sessionId);
  if (!team) return '';
  return `<button class="button small bd-open" data-board-open="${esc(team.project)}">`
    + `${boardOn() ? 'Team Board' : 'Up next'}</button>`;
});
core.presses.push(['[data-board-open]', (el) => boardToggle(el.dataset.boardOpen)]);

// An Up next row that's moving, or has only just landed under the pointer, isn't pressed: another may have taken its
// place as you aimed.
const boardRowMoved = (el) => !!el.closest('.bd-q') && (boardPage.moving || justShown('board:upnext'));

core.readerPresses.push(
  ['[data-board-goal]', (el) => { Object.assign(boardPage, { goal: el.dataset.boardGoal, job: null }); drawReader(); }],
  ['[data-board-back]', () => { Object.assign(boardPage, { goal: null, job: null }); drawReader(); }],
  ['[data-board-member]', (el) => { const name = el.dataset.boardMember;
                                    boardPage.member = boardPage.member === name ? null : name; drawReader(); }],
  ['[data-board-stage]', (el) => { const word = el.dataset.boardStage;
                                   boardPage.stage = boardPage.stage === word ? null : word; drawReader(); }],
  // What needs you opens One Task, by its view's name, while it's in the panel: the board answers nothing itself.
  ['[data-board-onetask]', () => { if (core.readerModes.oneTask) openReader(null, null, 'oneTask'); }],
  ['[data-board-team]', (el) => window.openBoard(el.dataset.boardTeam)],
  ['[data-board-job]', (el) => { if (boardRowMoved(el)) return;
                                 const id = el.dataset.boardJob;
                                 boardPage.job = boardPage.job === id ? null : id; drawReader(); }],
  ['[data-board-shut]', () => { boardPage.job = null; drawReader(); }],
  ['[data-board-all]', (el) => { boardPage.all.add(el.dataset.boardAll); drawReader(); }],
  ['[data-board-take]', (el) => {
    if (boardRowMoved(el)) return;
    const s = state.last?.sessions?.find((x) => x.sessionId === el.dataset.boardTake);
    if (s) openSession(s);
  }],
);
core.pointerTargets.push('.bd-open', '.bd-line', '.bd-tile', '.bd-you[data-board-onetask]', '.bd-member[data-board-member]',
                         '.bd-back', '.bd-goal', '.bd-more', '.bd-team', '.bd-stage', '.bd-card-x', '[data-board-take]',
                         'button.bd-q-in');
