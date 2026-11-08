// The team board's rules, as plain functions (its page cases check them): where each job of a team stands, in a few
// plain words; who's on what; its goals as tiles; what's done this week; the kinds of what needs you, and how many of
// those its lead has sent One Task; and what Take Me There opens. Nothing here draws (board-view.js does): the board
// answers nothing, One Task does.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// Each team as the team module gives it (TeamFacts), each kind's word, in One Task's order (contracts/Task.h), and the
// sessions working now, by id (Work's SessionWorking, which the gear counts with), as the app last sent them
// (setBoard); null until it has.
moduleState({ board: null });

// Where a job is, in words: what needs you and what's done are the board's own; one moving or waiting its turn is said
// by its step's word ("Build", "Ready to try"); what's up next or on hold, and a job with no step word, are the team
// module's words for its stages (core.teamJob), so the list and the board say the same.
function boardWhereWord(where, job) {
  if (where === 'you') return 'Needs you';
  if (where === 'done' || where === 'old') return 'Done';
  const step = where === 'waiting' || where === 'moving' ? job?.steps?.find((st) => st.id === job.at)?.word : '';
  return step || core.teamJob?.stageWord({ moving: 'work', waiting: 'waiting', next: 'queued', hold: 'parked' }[where])
    || '';
}
// Done this week shows; one done before that counts only in its goal's tile, as done.
const BOARD_DONE_FOR = 7 * 24 * 60 * 60 * 1000;
// How many lines a group shows before Show All: a team can have hundreds of jobs, and dozens of members.
const BOARD_SHOWN = 12;

// Where `job` is now: next (queued), hold (parked), done (this week) or old (done before that), the board's own; else,
// under way, where the team module says it is (`underWay`, its one rule): you (its step waits on you), waiting (its
// step waits its turn, with nobody working on it) or moving (at work).
const BOARD_UNDER_WAY = { you: 'you', waiting: 'waiting', work: 'moving' };
function boardWhere(job, now) {
  if (job.stage === 'done') return job.doneAt && now - job.doneAt <= BOARD_DONE_FOR ? 'done' : 'old';
  if (job.stage === 'queued') return 'next';
  if (job.stage === 'parked') return 'hold';
  return BOARD_UNDER_WAY[job.underWay] || 'moving';
}

// How many of `jobs` are where: {you, moving, waiting, next, hold, done, old, all}.
function boardCounts(jobs, now) {
  const counts = { you: 0, moving: 0, waiting: 0, next: 0, hold: 0, done: 0, old: 0, all: jobs.length };
  for (const job of jobs) counts[boardWhere(job, now)]++;
  return counts;
}

// What the jobs of `jobs` waiting their turn wait for, said after how many there are: when they're all at one step,
// that step's own word ("6 ready to try"), else "waiting their turn" ("waiting its turn" for one). Never "waiting"
// alone, which beside up next would read as waiting on you.
function boardWaitingSays(jobs, now) {
  const waiting = jobs.filter((j) => boardWhere(j, now) === 'waiting');
  const words = new Set(waiting.map((j) => boardWhereWord('waiting', j)));
  const [word] = words;
  if (words.size === 1 && word && word !== core.teamJob?.stageWord('waiting')) {
    return word[0].toLowerCase() + word.slice(1);
  }
  return waiting.length === 1 ? 'waiting its turn' : 'waiting their turn';
}

// The team for `project`, else the first, A to Z (the app sends them so); null without one that has a lead.
function boardTeam(board, project) {
  const led = (board?.teams || []).filter((t) => t.lead);
  return led.find((t) => t.project === project) || led[0] || null;
}

// The last part of a project's folder, as the board names it.
const boardProjectName = (project) => String(project || '').replace(/\/+$/, '').split('/').pop() || 'Your project';
// The lead's name, or words for it when the file gives none: the session that starts the team's jobs, which Take Me
// There opens. In what people see, a session leading a team is its chief, so a lead with no name is "the chief", but
// for one behind a session you talk to, which is the chief, it's the session running the team.
const boardLeadName = (team) => team?.lead?.name
  || (team?.chief?.session && team.chief.session !== team.lead?.session ? 'the session running the team' : 'the chief');
// Who the team's chief is, as a head says it: "chief Atlas", or "its chief" when the file names none. The chief is the
// session you talk to when the file names one, else the lead: the team module's to say (`chief`), never worked out
// here.
const boardChiefSays = (team) => (team?.chief?.name ? `chief ${team.chief.name}` : 'its chief');

// A team's goals as tiles, each {key, name, due, n, jobs}: without goals, one tile of every job; with them, one per
// goal in the file's order, numbered by it (`n`, from 1), then a heading for how the team works (a goal marked `work`),
// unnumbered and no goal, then the jobs under none (Other).
function boardTiles(team) {
  const jobs = team?.jobs || [], goals = team?.goals || [];
  if (!goals.length) return [{ key: 'all', name: 'All tasks', jobs }];
  const tile = (g, n) => ({ key: `goal:${g.id}`, name: g.name, due: g.due, n, jobs: jobs.filter((j) => j.goal === g.id) });
  const numbered = goals.filter((g) => !g.work).map((g, i) => tile(g, i + 1));
  const work = goals.filter((g) => g.work).map((g) => tile(g, null));
  const none = jobs.filter((j) => !j.goal);
  return [...numbered, ...work, ...(none.length ? [{ key: 'none', name: 'Other', jobs: none }] : [])];
}

// Each goal's number, by its id, as its tile has it.
const boardNumbers = (team) => new Map(boardTiles(team).filter((t) => t.n).map((t) => [t.key.slice(5), t.n]));

// What the board shows for `goal` (boardPage.goal: null for Glance, 'all' or a tile's key for Up next), with `on`
// whether the rest of the board shows: without it, Up next's All goals takes Glance's place, and a goal that's gone
// from the file goes back to Glance, or to All goals.
function boardGoalShown(goal, tiles, on) {
  if (goal === 'all' || (goal && tiles.some((t) => t.key === goal))) return goal;
  return on ? null : 'all';
}

// Who's on what: each member with a job under way (moving, or waiting on you), in the order of their first job, as
// {name, part, now, you, moving, next, jobs}. `now` is the job its row speaks for (the team module marks it `now`),
// else its first under way; the counts are its other jobs, so none is counted twice: waiting on you, moving, up next
// (queued). `jobs` is its other jobs too, but for those done before this week. A job waiting its turn has no one at
// work on it, so a member with only those isn't on anything.
function boardMembers(team, now) {
  const members = new Map();
  for (const job of team?.jobs || []) {
    if (!job.member) continue;
    if (!members.has(job.member)) members.set(job.member, []);
    members.get(job.member).push(job);
  }
  const underWay = (job) => ['you', 'moving'].includes(boardWhere(job, now));
  return [...members].filter(([, jobs]) => jobs.some(underWay)).map(([name, jobs]) => {
    const on = jobs.find((j) => j.now && underWay(j)) || jobs.find(underWay);
    const others = (where) => jobs.filter((j) => j !== on && boardWhere(j, now) === where).length;
    return { name, part: on.part || jobs.find((j) => j.part)?.part || '', now: on, you: others('you'),
             moving: others('moving'), next: others('next'),
             jobs: jobs.filter((j) => j !== on && boardWhere(j, now) !== 'old') };
  });
}

// What's done this week, the one done last first.
function boardDone(team, now) {
  return (team?.jobs || []).filter((j) => boardWhere(j, now) === 'done').sort((a, b) => (b.doneAt || 0) - (a.doneAt || 0));
}

// The kinds of what needs you, in One Task's order, each {kind, word, n}; one with no kind the file gives counts as
// Your move, last.
function boardKinds(team, kinds, now) {
  const waiting = (team?.jobs || []).filter((j) => boardWhere(j, now) === 'you');
  const known = (kinds || []).map(({ kind, word }) => ({ kind, word, n: waiting.filter((j) => j.kind === kind).length }));
  const plain = waiting.filter((j) => !known.some((k) => k.kind === j.kind)).length;
  return [...known, { kind: '', word: 'Your move', n: plain }].filter((k) => k.n);
}

// How many of the jobs waiting on you the lead has sent One Task: its queue's picks whose job waits on you, each job
// once. One Task shows only what's been sent it, so its count can be the smaller.
function boardInOneTask(team, now) {
  const jobs = new Map((team?.jobs || []).map((j) => [j.id, j]));
  const sent = new Set((team?.queue || []).map((p) => p.job).filter((id) => jobs.has(id)));
  return [...sent].filter((id) => boardWhere(jobs.get(id), now) === 'you').length;
}

// What Take Me There opens for a job, among the sessions listed: the session holding its member's seat (the row marked
// as that member, so a cleared or new conversation in the member's workspace is the one opened), else the one the team
// file recorded for it, else, with why, the lead's. Two teams can have a member of one name, so a row marked so counts
// only when the lead leads it (its `leads`), or, with the lead's row not listed, when it's the only one of that name.
// One that has stopped is carried on, as pressing its ended row does, its button saying so (`again`: Open Wren Again).
// Neither listed, nothing, with why. {session, again, name, why}.
function boardTakeMe(job, team, sessions) {
  const row = (sid) => (sid ? sessions.find((s) => s.sessionId === sid) : null);
  const lead = boardLeadName(team), leads = row(team?.lead?.session), led = leads?.team?.leads;
  const named = job.member ? sessions.filter((s) => s.team?.role === 'member' && s.team.name === job.member) : [];
  const seats = led ? named.filter((s) => led.includes(s.sessionId)) : named.length === 1 ? named : [];
  const member = seats[0] || row(job.session);
  const opens = (s, name, why) => ({ session: s.sessionId, again: s.status === 'closed', name, why });
  if (member) return opens(member, job.member, member.status === 'closed' ? `${job.member} has stopped` : '');
  const missing = job.member ? `${job.member} isn’t in the list now` : 'No one has it yet';
  if (leads) return opens(leads, team.lead.name || 'the chief', `${missing}: this opens ${lead}`);
  return { session: null, why: job.member ? `${missing}, and nor is ${lead}`
    : `${missing}, and ${lead} isn’t in the list now` };
}

// What Take Me There opens beside a job let in and not started: the lead's session, which starts it, carried on when it
// has stopped (`again`); with why not, when it isn't in the list. {session, again, name, why}.
function boardOpensLead(team, sessions) {
  const lead = boardLeadName(team), s = sessions.find((x) => x.sessionId && x.sessionId === team?.lead?.session);
  if (!s) return { session: null, why: `${lead[0].toUpperCase()}${lead.slice(1)} isn’t in the list now` };
  return { session: s.sessionId, again: s.status === 'closed', name: team.lead.name || 'the chief', why: '' };
}

// The session whose title line under Group by Team carries Up next (or Team Board): the chief's, the session you talk
// to, else the lead (the team module's `chief`). While the chief isn't in the list (its conversation has ended, or a
// new one isn't in the file yet), the lead's, so Up next always has a way in; who the chief is doesn't change. Null for
// a team nobody leads.
function boardLineFor(team, sessions) {
  if (!team?.lead) return null;
  const chief = team.chief?.session;
  return chief && sessions.some((s) => s.sessionId === chief) ? chief : team.lead.session;
}

// What's done this week shows its newest few before Show All: the board is about the work still going.
const BOARD_DONE_SHOWN = 5;

// The jobs (or members) a group shows: all once Show All is pressed, else the first `most` (BOARD_SHOWN), with how many
// more.
function boardShown(jobs, all, most = BOARD_SHOWN) {
  return all || jobs.length <= most ? { jobs, more: 0 } : { jobs: jobs.slice(0, most), more: jobs.length - most };
}

// A member's jobs by where they stand (needs you, moving, waiting, up next, on hold, done), each part in the group's
// order.
const BOARD_PLACES = ['you', 'moving', 'waiting', 'next', 'hold', 'done', 'old'];
function boardByWhere(jobs, now) {
  return BOARD_PLACES.flatMap((where) => boardOrder(jobs.filter((j) => boardWhere(j, now) === where)));
}

// The order jobs show in within a group: the most pressing first, then the smallest, then the one that takes the least
// work, so small ones clear first; then the one that's sat there longest (a done one, the one done last first). A job
// the file doesn't size, or whose work it doesn't say, counts as medium, and one with a priority the ladder doesn't
// have as P1, the one a job without a priority gets.
const BOARD_RANKS = { priority: { critical: 0, p0: 1, p1: 2, p2: 3 }, size: { small: 0, medium: 1, big: 2 },
                      effort: { low: 0, medium: 1, high: 2 } };
const BOARD_RANK_ELSE = { priority: BOARD_RANKS.priority.p1, size: 1, effort: 1 };
function boardOrder(jobs) {
  const rank = (job, field) => BOARD_RANKS[field][job[field]] ?? BOARD_RANK_ELSE[field];
  return [...jobs].sort((a, b) => rank(a, 'priority') - rank(b, 'priority') || rank(a, 'size') - rank(b, 'size')
    || rank(a, 'effort') - rank(b, 'effort')
    || (a.stage === 'done' ? (b.doneAt || 0) - (a.doneAt || 0) : (a.stageAt || Infinity) - (b.stageAt || Infinity)));
}

// The stages of a team's jobs under way, as the strip under What's moving shows them: one per step word that has jobs
// at it, each {word, you, waits, jobs}, its jobs in the board's order (boardOrder). The words follow the jobs' own
// steps: going through the jobs by id, a word not placed yet goes after the last of that job's words already placed (or
// before the first of its later ones, else last), so every flow's steps keep their order. A step's `you` and `waits`
// are the first job's at it. Queued, parked and done jobs keep their own places on the board.
function boardStages(team, now) {
  const underWay = (team?.jobs || []).filter((j) => j.steps?.length && ['you', 'moving', 'waiting']
    .includes(boardWhere(j, now)));
  const order = [];
  for (const job of underWay) {
    const words = [...new Set(job.steps.map((st) => st.word))];
    let after = -1;
    words.forEach((word, i) => {
      const at = order.indexOf(word);
      if (at >= 0) {
        after = at;
        return;
      }
      const later = words.slice(i + 1).map((w) => order.indexOf(w)).find((x) => x >= 0);
      after = after >= 0 ? after + 1 : later ?? order.length;
      order.splice(after, 0, word);
    });
  }
  const stages = new Map(order.map((word) => [word, null]));
  for (const job of underWay) {
    const step = job.steps.find((st) => st.id === job.at);
    if (!step) continue;
    if (!stages.get(step.word)) {
      stages.set(step.word, { word: step.word, you: !!step.you, waits: !!step.waits, jobs: [] });
    }
    stages.get(step.word).jobs.push(job);
  }
  return [...stages.values()].filter(Boolean).map((stage) => ({ ...stage, jobs: boardOrder(stage.jobs) }));
}

// The stage open under the strip (boardPage.stage, by its word), while it still has jobs; else none, so a stage that's
// emptied folds.
const boardStageShown = (stage, stages) => (stage != null && stages.some((s) => s.word === stage) ? stage : null);

// Up next: every session working now, then what waits in the lead's order, for all goals together or one. The gear
// (core.gear.facts(), the usage module's: {gear, atWork, counted, over, limit, …}) says who's working and how many
// more it lets in; without it (null: no usage module, or the usage not known yet) the sessions working are those the
// app counts by the same rule (`working`, the ids setBoard sends), and nothing is let in, so there's no line and nothing
// "starts it". With Usage Gear off in Settings (`off`, core.gear.off()), there's no gear and no limit: every queued
// job is let in.
// When each job was let in (`letInAt`, its id to a time) is kept by the page in its memory only; it's handed back
// with those let in now, so one let in 10 minutes ago and still queued reads Not started. The gear's words for a
// session over it and for its line are the usage module's, passed in with its facts (`words`, core.gear.words:
// overSays, lineSays); why the line shows only on All goals is the board's own.
const BOARD_NOT_STARTED = 10 * 60 * 1000;

// `goal` is 'all', or a tile's key (boardTiles). Gives {rows, line, working, next, letInAt, says, empty, note}: each row
// {key, kind (working or next), session, job, goal, n (its goal's number, null for none), who, what, says,
// over, letIn, notStarted}; `line` how many rows come before the gear's line (All goals only, while a gear is set:
// after the sessions within the gear and the jobs it lets in, before those over it and the rest); `says` the view's
// count, `empty` its words when it has no rows, `note` what's under it; `lineSays` the line in words, for VoiceOver.
// A working row's `listed` says whether its session is in the list, so a press can open it.
function boardUpNext(team, gear, sessions, working, goal, now, letInAt = new Map(), words = {}, off = false) {
  const lead = boardLeadName(team), all = goal === 'all';
  const tile = all ? null : boardTiles(team).find((t) => t.key === goal), numbers = boardNumbers(team);
  const within = (g) => all || (goal === 'none' ? g === null : goal === `goal:${g}`);
  const known = new Map((team?.goals || []).map((g) => [g.id, g]));
  const goalOf = (job) => (job?.goal && known.has(job.goal) ? job.goal : null);
  const byId = new Map((sessions || []).map((s) => [s.sessionId, s]));
  // Who's working: the gear's count, else the app's by the same rule (never the page's own reading of a status: one
  // waiting for your OK isn't working, and one compacting or with agents in the background is), by when their turn
  // began, those over the gear last.
  const over = new Set(gear?.over || []);
  const ids = [...((gear ? gear.counted : working) || [])];
  const began = (sid) => byId.get(sid)?.statusUpdatedAt || 0;
  ids.sort((a, b) => over.has(a) - over.has(b) || began(a) - began(b));
  // What a session at work is on: its job moving (the one its row speaks for first), and only without one, its job
  // waiting on you, since a member's row puts what waits on you first but its session is working on the other.
  const jobOf = (sid) => {
    const mine = (team?.jobs || []).filter((j) => j.session === sid);
    const at = (where) => mine.filter((j) => boardWhere(j, now) === where);
    const pick = (jobs) => jobs.find((j) => j.now) || jobs[0];
    return pick(at('moving')) || pick(at('you')) || null;
  };
  const atWork = ids.map((sid) => {
    const s = byId.get(sid), job = jobOf(sid), g = goalOf(job), isLead = sid === team?.lead?.session;
    const isChief = sid === team?.chief?.session;
    const step = job?.steps?.find((st) => st.id === job.at)?.word;
    // The chief says so; the lead behind a session you talk to shows its name alone, as Lead is never a word shown.
    const who = isLead ? lead : isChief ? team.chief.name || s?.team?.shown || s?.name || 'The chief'
      : job?.member || s?.team?.shown || s?.team?.name || s?.name || (s ? base(s.cwd) : 'A session');
    const what = isChief ? 'Chief' : isLead ? '' : job ? job.title : s?.team?.part || 'Your session';
    const says = over.has(sid) ? words.overSays || '' : step ? `Moving · ${step}` : 'Moving';
    return { key: `s:${sid}`, kind: 'working', session: sid, job, goal: g, n: numbers.get(g) ?? null, who, what,
             says, over: over.has(sid), lead: isLead, listed: !!s };
  });
  // What waits: the lead's queued jobs, in its order (`place`, the team module's, across every led team). The room
  // the gear lets in (its `room`, the usage module's) is one for your account, so a job is let in by its place,
  // whichever team it's on; at the session's limit, or with no gear set, nothing is; with Usage Gear off, everything.
  const room = off ? Infinity : gear && Number.isFinite(gear.room) && !gear.limit ? gear.room : 0;
  const queued = (team?.jobs || []).filter((j) => j.stage === 'queued')
    .sort((a, b) => (a.place ?? Infinity) - (b.place ?? Infinity));
  const kept = new Map();
  const next = queued.map((job) => {
    const g = goalOf(job), letIn = job.place != null && job.place <= room;
    if (letIn) kept.set(job.id, letInAt.get(job.id) ?? now);
    const notStarted = letIn && now - kept.get(job.id) >= BOARD_NOT_STARTED;
    const says = notStarted ? `Not started: ${lead} starts it` : letIn ? `Up next · ${lead} starts it` : 'Up next';
    return { key: `j:${job.id}`, kind: 'next', job, goal: g, n: numbers.get(g) ?? null, who: job.member || 'No one yet',
             what: job.title, says, letIn, notStarted };
  });
  // In one goal, the sessions working on its jobs: the lead and a session with no job of the team's are in no goal,
  // and show only under All goals.
  const inGoal = (r) => all || (!!r.job && within(r.goal));
  const shownWorking = atWork.filter(inGoal), shownNext = next.filter(inGoal);
  const rows = [...shownWorking.filter((r) => !r.over), ...shownNext.filter((r) => r.letIn),
                ...shownWorking.filter((r) => r.over), ...shownNext.filter((r) => !r.letIn)];
  const line = all && gear && Number.isFinite(gear.gear)
    ? shownWorking.filter((r) => !r.over).length + shownNext.filter((r) => r.letIn).length : null;
  const name = all ? 'All goals' : tile?.name || '';
  const empty = !all ? `Nothing in this goal is working or up next: ${lead} puts its jobs here.`
    : !atWork.length ? `No one is working, and nothing is up next. Sessions working show here, then ${lead}’s queued `
      + 'jobs, the most pressing first.'
      : `Nothing is up next. ${lead}’s queued jobs show here, the most pressing first.`;
  // What the gear adds is said only with the gear.
  const why = !gear ? ''
    : all ? 'The gear’s line shows only here, on All goals, because the gear counts every goal together.'
      : 'The gear’s line is on All goals, because the gear counts every goal together. A job here that’s next to start '
        + 'says so on its row.';
  const note = `${all ? `Every session working now, then what waits, in ${lead}’s order.`
    : `This goal’s jobs, in ${lead}’s order.`}${why ? ` ${why}` : ''}`;
  const lineSays = line === null ? '' : words.lineSays?.(gear.gear) || '';
  return { rows, line, lineSays, working: shownWorking.length, next: shownNext.length, letInAt: kept,
           says: `${name} · ${shownWorking.length} working · ${shownNext.length} up next`,
           empty: all && shownNext.length || !all && rows.length ? '' : empty, note };
}

// The goals down Up next's side: All goals, then the team's goals as boardTiles has them (numbered, How we work,
// Other), each with how many sessions working are on its jobs. None for a team without goals: there's nothing to pick
// between.
function boardUpNextShelf(team, gear, sessions, working, now) {
  if (!team?.goals?.length) return [];
  const { rows } = boardUpNext(team, gear, sessions, working, 'all', now);
  const atWork = rows.filter((r) => r.kind === 'working');
  const count = (key) => atWork.filter((r) => r.job && (key === 'none' ? r.goal === null : `goal:${r.goal}` === key))
    .length;
  return [{ key: 'all', name: 'All goals', n: null, working: atWork.length },
          ...boardTiles(team).map((t) => ({ key: t.key, name: t.name, n: t.n ?? null, working: count(t.key) }))];
}

// Which of Up next's rows, by key, slide to their new places as it's drawn again: those in both `was` and `now` that
// keep their order among each other, as many as can (the longest run in the same order). The rest go and come, so a
// row that moved past others never slides through their words.
function boardKept(was, now) {
  const at = new Map(was.map((k, i) => [k, i]));
  const both = now.filter((k) => at.has(k));
  // For each, the longest run in the old order ending at it, and the one before it in that run.
  const best = both.map(() => 1), prev = both.map(() => -1);
  both.forEach((k, i) => {
    for (let j = 0; j < i; j++) {
      if (at.get(both[j]) < at.get(k) && best[j] + 1 > best[i]) [best[i], prev[i]] = [best[j] + 1, j];
    }
  });
  const kept = new Set();
  for (let i = best.indexOf(Math.max(0, ...best)); i >= 0; i = prev[i]) kept.add(both[i]);
  return kept;
}
