// The team: its groups and rows in the list. Above the projects, the chief, on top: the session you talk to when the
// file names one, else the lead (a session leading a team of other sessions for you); the lead, with what it says is
// next for you, how many jobs wait on you and how many are at work; the file's groups, and its team. Your own sessions
// stay under their projects. Every row is the list's short row, as every row is: its name, what it looks after and its
// job as a short track of its steps, and a line under it: what its job wants of you, in the session's own words, with
// Deploy when the row has it; else what the session itself asks (its request's card); else, while it's at work on one
// job and another of its jobs waits on you, that one's ask; else, quietly, where its job stands. Each row's place in
// the team is the app's (its `team`, docs/reference/rows.md). A member's reply to the lead is never yours to read.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// The session you talk to when another runs the team behind it (`front`), the one running the team (`lead`), and its
// members. Which of them is the chief is the app's to say (`team.chief`).
const TEAM_ROLES = ['front', 'lead', 'member'];

// The team's groups above the projects (core.topGroups), in order, each without the rows it hasn't: the session you
// talk to, then the lead unless the file puts it in a group, on top with no header; a group for each name the file
// gives members, or the lead behind the session you talk to (`group`), in its order (`groupAt`); and its other members
// (Team), after those groups unless the file places it among them (its members' `groupAt`). Everything else is yours,
// handed back (`rest`) to go under its project. A tag is only a mark: it moves no row. In each group the rows keep the
// order the list placed them in, newest message first, as in every project: nothing is lifted, as what waits on you
// says so in its bubble. A folded group hides all its rows, even one that needs you, and its header says how many wait
// on you. Null while no session listed is one of the team, so the list is its projects alone.
function teamGroups(placed) {
  const roleOf = (p) => p.s.team?.role;
  if (!placed.some((p) => TEAM_ROLES.includes(roleOf(p)))) return null;
  // Any other ended session in a member's folder is left out once it has nothing for you: the member's own row (its
  // last conversation there, ended, while none runs there) stands for that folder, and that conversation is over. Its
  // last reply is never yours to read (endedInMembersFolder), so only one that still asks you something stays, so it
  // can be answered, as the counts of what waits on you include it; so does one you've pressed or are on, so reading
  // it doesn't take it from under you, and one that speaks for its checkout (state.owners: it edited there after the
  // member did), as that checkout's next steps and Deploy, with any deploy asked for there, are on its row; one still
  // running there stays too, said to be there, or, in the member's own workspace, a duplicate of it, as it may clash
  // with the member's work. One left out is in neither the groups nor the rest, so it isn't shown.
  placed = placed.filter((p) => !(p.s.team?.inFolderOf && p.s.status === 'closed' && !waitsOnYou(p.kind) && !p.held
    && !p.s.focused && !state.owners.has(p.s.sessionId)))
    .map((p) => (p.s.team?.job?.you || p.s.team?.alsoAsks ? { ...p, waits: true } : p));
  const groupOf = (p) => (['member', 'lead'].includes(roleOf(p)) ? p.s.team.group || null : null);
  // The session you talk to and the lead keep their places on top, the session you talk to first.
  const head = [...placed.filter((p) => roleOf(p) === 'front'),
                ...placed.filter((p) => roleOf(p) === 'lead' && !groupOf(p))];
  const team = placed.filter((p) => roleOf(p) === 'member' && !groupOf(p));
  const named = [...new Map(placed.filter(groupOf).map((p) => [groupOf(p), p.s.team.groupAt ?? Infinity])).entries()];
  const teamAt = team.find((p) => p.s.team.groupAt != null)?.s.team.groupAt ?? Infinity;
  const inOrder = [...named, [null, teamAt]].sort(([a, at], [b, bt]) => at - bt || (a == null) - (b == null)
    || (a ?? '').localeCompare(b ?? ''));
  const groups = [
    { key: 'team:lead', name: null, rows: head },
    ...inOrder.map(([name]) => (name == null ? { key: 'team:team', name: 'Team', rows: team }
      : { key: `team:group:${name}`, name, rows: placed.filter((p) => groupOf(p) === name) })),
  ];
  return { groups: groups.filter((g) => g.rows.length),
           rest: placed.filter((p) => !TEAM_ROLES.includes(roleOf(p))) };
}

// The kind of wait a job is, as its colour says it: a Critical or P0 one in the colour of something to put right
// (`urgent`, as the track and an ask's bubble know it), a P2 one quiet (`low`: an ask's bubble grey, the counts' small
// dot an outline, teamCountsHTML), the rest in your move's colour (`normal`).
const waitLook = (priority) => (priority === 'critical' || priority === 'p0' ? 'urgent'
  : priority === 'p2' ? 'low' : 'normal');

// Each priority in the ladder's words, most pressing first; one it doesn't know reads as P1, as its look does.
const PRIORITY_WORDS = { critical: 'Critical', p0: 'P0', p1: 'P1', p2: 'P2' };
const priorityWord = (priority) => PRIORITY_WORDS[priority] || PRIORITY_WORDS.p1;

// What the lead says on its line under its name: how many jobs wait on you, in one number, its dot as pressing as the
// most pressing of them (the bubbles on the rows below say which), and how many are at work, each only when there are
// some, so it never shows a count of none (empty when there's nothing to count).
// One job needs you; more need you: the team board's words, so the lead's line and the board say the same.
const waitWord = (waiting) => (Object.keys(PRIORITY_WORDS).reduce((sum, k) => sum + (waiting[k] || 0), 0) === 1
  ? 'needs' : 'need');
function teamCountsHTML(counts) {
  const waiting = counts?.waiting || {}, working = counts?.working || 0;
  const mini = (look, text) => `<span class="tcount"><i class="tmini ${look}"></i>${text}</span>`;
  const waits = Object.keys(PRIORITY_WORDS).filter((k) => waiting[k]);
  const total = waits.reduce((sum, k) => sum + waiting[k], 0);
  const look = ['urgent', 'normal', 'low'].find((l) => waits.some((k) => waitLook(k) === l));
  return (total ? mini(look, `${total} ${waitWord(waiting)} you`) : '')
    + (working ? mini('busy', `${working} moving`) : '');
}
function teamCountsWords(counts) {
  const waiting = counts?.waiting || {}, n = (k) => waiting[k] || 0, working = counts?.working || 0;
  const kinds = Object.keys(PRIORITY_WORDS).filter(n).map((k) => `${n(k)} ${priorityWord(k)}`);
  const listed = kinds.length > 1 ? `${kinds.slice(0, -1).join(', ')} and ${kinds.at(-1)}` : kinds[0];
  const wait = listed ? `${listed} ${waitWord(waiting)} you` : '';
  const work = working ? `${working} moving` : '';
  return [wait, work].filter(Boolean).join(' · ') || 'Nothing needs you, and nothing is moving';
}

// What's wanted of you in a few words, as the row's ask line (the row part's askLineHTML), its priority's name first in
// the mark's place, with how many other jobs it holds up (its one action goes at its end: teamAct). Each session says
// its own: a member's ask is never marked as passed on by the session leading the team.
function teamAskLineHTML(words, priority, holds = 0) {
  return askLineHTML(words, holds, `Holds up ${holds} more`, '', `${priorityWord(priority)}: ${words}`,
                     priorityWord(priority));
}

// A member's job when it waits on you, on its line under its name: its short, else its step's word (the whole ask is
// on its card). Null when it doesn't wait on you.
function teamAskHTML(job) {
  if (!job?.you) return null;
  const step = job.steps.find((st) => st.id === job.at);
  return teamAskLineHTML(job.short || step?.word || '', job.priority, job.holds);
}

// An ask's one action, by what its step asks of you (its kind, in One Task's words), with that kind's icon and verb as
// One Task offers them (core.taskKinds): { icon, tip, to, want }. A press takes you to the session where it waits
// (`to`, its id, named `name`), where the plan, the looks or the question are, as a step has no page to open; and as it
// has no command to copy either, a kind that copies, or one that takes you there anyway, says Take Me There. A try is Deploy's
// (`want` 'try', the deploy module's, askAct) only on the row of the session it's about (`own`): the lead's next, for a
// member, takes you there. So are a plan to approve and looks to pick (`want` 'plan' and 'look'), which a module that
// can show them beside the list answers on that row, its button in place of this one; where none does (an approve
// that isn't a plan waiting, a merge or a commit among them), this one takes you to the session. That holds for
// another of its jobs waiting on you too, so a plan's ask has one shape and one press on every row: what the module
// shows beside the list while the session works says it's only to read there. With nowhere to go, only the want, else
// null.
const TEAM_WANTS = { try: 'try', approve: 'plan', pick: 'look' };
function teamAct(kind, to, name, own = true) {
  const wants = own ? TEAM_WANTS[kind] : '';
  const want = wants ? { want: wants } : {};
  if (!to) return want.want ? want : null;
  const shown = core.taskKinds?.act(kind);
  const go = !shown || shown.does === 'there' || shown.does === 'copy';
  const tip = go ? (name ? `Take Me There: ${name}` : 'Take Me There')
    : `${shown.verb}, in ${name ? `${name}'s` : 'its'} session`;
  const icon = go ? OUT_ICON : shown.icon;
  return { icon, tip, to, ...want };
}
// The note's `act` for it: what it wants, and its button (the row part's askActHTML).
const teamActNote = (a) => a && { want: a.want,
  html: a.to ? askActHTML(a.icon, a.tip, ` data-team-go="${esc(a.to)}"`) : '' };

// A team's row's note: on the lead, what it says is next for you, else its counts; on a member, what its job waits on
// you for. Either ask is a bubble in the colour of the kind of wait (its look: a Critical or P0 one in the colour of
// something to put right, the rest in your move's, which gives way to any other module's note that isn't, as a warning,
// and comes back once it's gone), ending in its one action (teamAct): on a member, for its step, in its own session
// (`sid`); on the lead, taking you to the session it's for, else its own, named as the team names it (`nameOf(id)`). A
// member at work on one job while another of its own waits on you (the app's `alsoAsks`) asks for that one the same
// way, its track still the job at work's; its class is `talso` rather than `task`, as the details that open from the
// row are the job at work's (core.cards below). Otherwise, only when no module has anything to say on the row, where
// its job stands (teamStatusNote).
function teamNote(team, sid = '', nameOf = () => '') {
  const asked = (html, priority, act, cls = 'task') => {
    const look = waitLook(priority);
    return { html, cls: `ask-note ${cls}`, look, act, line: true, quiet: false,
             tone: look === 'urgent' ? 'warn' : 'turn' };
  };
  if (team?.role === 'lead') {
    const next = team.next;
    if (next) {
      // The member it's for, while listed (named), else the lead's own session.
      const to = next.for && nameOf(next.for) ? next.for : sid;
      return asked(teamAskLineHTML(next.short, next.priority), next.priority,
                   teamActNote(teamAct(undefined, to, to === sid ? team.name : nameOf(to), to === sid)));
    }
    // With nothing to count, no line.
    const counts = teamCountsHTML(team.counts);
    return counts ? { html: counts, cls: 'tsum', quiet: true } : null;
  }
  const ask = teamAskHTML(team?.job);
  const step = team?.job?.steps.find((st) => st.id === team.job.at);
  if (ask) return asked(ask, team.job.priority, teamActNote(teamAct(step?.kind, sid, team.name)));
  const also = team?.alsoAsks;
  return also?.short ? asked(teamAskLineHTML(also.short, also.priority), also.priority,
                             teamActNote(teamAct(also.kind, sid, team.name)), 'talso') : null;
}

// Where a member's job stands, in a few words after its stage's: "Up next: after the search box", or the stage's word
// alone when the file gives none (never its title, which is on its card). Quiet, and without the row's Deploy at its
// end. None while the job waits on you, which says so in its ask's line (teamNote), or while the session asks you
// something itself (`kind` needs: what the session is now), which its card says, or Claude's line where it has none.
// The team board's words for where a job is, so the list and the board say the same. A job waiting its turn is said by
// its step's own word ("Ready to try"), and as Waiting only when it has none.
const STAGE_WORDS = { work: 'Moving', waiting: 'Waiting', queued: 'Up next', parked: 'On hold' };
// The stage's word, or the file's own for what a member is busy with ("Reviewing"), or for the step a job is at, at work
// or waiting its turn ("Build", "Ready to try"): the board names no stage Moving, so that's said only for a job whose
// file gives no steps.
const stageWord = (status) => (status?.stage === 'work' && status.doing)
  || ((status?.stage === 'work' || status?.stage === 'waiting') && status.word) || STAGE_WORDS[status?.stage];
function teamStatusText(status) {
  const stage = stageWord(status);
  return stage ? stage + (status.words ? `: ${status.words}` : '') : '';
}
function teamStatusNote(status, kind = '') {
  const text = status?.you || kind === 'needs' ? '' : teamStatusText(status);
  return text ? { html: `<span class="tstatus-words">${esc(text)}</span>`, cls: 'tstatus', quiet: true, end: false }
    : null;
}

// A session running in a member's own workspace while another holds the member's seat (the app's `duplicate`): its line
// says to close the one opened first, quietly, and only when nothing else is said on the row, so a task it sends you or
// a warning stays in front. Whichever is closed, one of the others then holds the seat. Its own class, so no job's
// details open from it, and without the row's Deploy.
function duplicateNote(team) {
  if (!team?.duplicate) return null;
  const words = team.earlier ? 'Close this one, the previous session' : 'Close the previous session';
  return { html: `<span class="tdup-words">${esc(words)}</span>`, cls: 'tdup', quiet: true, end: false };
}
// Pointed at, its mark says which session is on the member's row and which one to close; never which of the others
// carries on, as with more than two there the one opened first of the rest takes the seat.
function duplicateTip(team) {
  const name = team.inFolderOf;
  const on = team.seat ? `“${team.seat}” is on ${name}'s row` : `Another session is on ${name}'s row`;
  return `${on}, opened ${team.earlier ? 'after' : 'before'} this one: close ${team.earlier ? 'this' : 'that'} one, and`
    + ` one of the others carries on as ${name}`;
}

// A job's steps as a track (the row's parts' stepTrackHTML): how many, the one it's on, and its look, in the colour of
// whose move it is (the kind of wait, or the session at work or idle). A job waiting its turn is idle, whatever its
// session is doing: nobody is working on it.
const trackNow = (job, kind) => (job.you ? waitLook(job.priority) : !job.waits && kind === 'busy' ? 'busy' : 'idle');
function jobTrack(job, kind) {
  return { count: job.steps.length, at: job.steps.findIndex((st) => st.id === job.at), look: trackNow(job, kind) };
}
// VoiceOver hears the step's word with where it stands. A job of one step has none (stepTrackHTML).
function trackHTML(job, now) {
  const { count, at } = jobTrack(job);
  return stepTrackHTML(count, at, now, job.steps[at]?.word || '');
}
// Another module (the team board, One Task) draws a team's job with the same track, and says where it stands and how
// pressing it is in the same words and colours, through the core, never by calling this file.
// A job's priority is also given as its place in the ladder (`at`, 0 the most pressing, of `of`), so what orders it
// beside other lists of priorities (One Task, beside each ticket's tracker's) needs no level's name, with its look
// (waitLook), so how pressing it is stays the team's to say.
const priorityPlace = (priority) => {
  const ladder = Object.keys(PRIORITY_WORDS), at = ladder.indexOf(priority);
  return { at: at < 0 ? ladder.indexOf('p1') : at, of: ladder.length, look: waitLook(priority) };
};
core.teamJob = { track: jobTrack, stageWord: (stage) => STAGE_WORDS[stage] || '',
                 doNow: (priority) => waitLook(priority) === 'urgent', priorityWord, priorityPlace };

// A job's details, as rested on: a head line, the step it's at and for how long, and whether that waits on you or is at
// work; the job as its title; and what's wanted of you, in the colour of the kind of wait. The row already says whose
// it is.
function teamCardHTML(s, now) {
  const job = s.team.job, step = job.steps.find((st) => st.id === job.at);
  const since = job.stageAt ? ` for ${ago(now - job.stageAt)}` : '';
  return `<div class="card-head"><span>${esc(step?.word || '')}${since}</span>`
    + `<span class="end">${job.you ? 'needs you' : job.waits ? 'waiting' : 'moving'}</span></div>`
    + detailsTitleHTML(job.title)
    + (job.you && job.ask
      ? `<div class="card-lead ${waitLook(job.priority) === 'urgent' ? 'warn' : 'turn'}">${esc(job.ask)}</div>` : '');
}

// A member's details while its job isn't under way, or has no steps: where it stands and for how long, the job, and
// the words for that in full.
function teamStatusCardHTML(s, now) {
  const status = s.team.status, since = status.stageAt ? ` for ${ago(now - status.stageAt)}` : '';
  return `<div class="card-head"><span>${esc(stageWord(status))}${since}</span></div>`
    + (status.title ? detailsTitleHTML(status.title) : '')
    + (status.words ? `<div class="card-lead">${esc(status.words)}</div>` : '');
}

// The details of the lead while it names what's next for you: a head line, "Next for you" (in the colour of something
// to put right while it's Critical or P0) and the job it's for; its short as the title, then the whole ask, never cut
// (else the ask as the title); and the counts in words.
function teamNextCardHTML(s) {
  const team = s.team, next = team.next, urgent = waitLook(next.priority) === 'urgent';
  return `<div class="card-head"><span${urgent ? ' class="warn"' : ''}>Next for you</span>`
    + (next.title ? `<span class="end">${esc(next.title)}</span>` : '') + '</div>'
    + detailsTitleHTML(next.short || next.ask)
    + (next.short && next.ask ? `<div class="card-lead">${esc(next.ask)}</div>` : '')
    + `<div class="card-lead">${esc(teamCountsWords(team.counts))}</div>`;
}

moduleState({
  teamAsks: {},      // session id -> the job and step its ask's line was last drawn for (or what's next, on the lead)
  teamActs: {},      // session id -> the job, step and button its ask's action was last drawn for
});
core.forgotten.keys.push('teamAsks', 'teamActs');

core.topGroups.push(teamGroups);
// A conversation that has ended in a member's folder (its earlier one, the lead's or the front's too, but for the
// project's own folder, where your own conversations are: the app's `history`) is the member's history, none of it
// yours to read, whatever its replies answered, and one kept to read from before too: the member's own row stands for
// that folder. So it never
// waits on you in the list, nor in the counts beside the pawn, at the panel's edge or beside the
// folded panel, which all go by whose move it is. Only with a team file, which alone says whose folder it is.
const endedInMembersFolder = (s) => !!s.team?.inFolderOf && !!s.team.history && s.status === 'closed';
core.notYoursToRead.push(endedInMembersFolder);
// Every row of the team in the list (shown briefly, as every row is: the row part's row.brief) is under its name in the
// team, and its note says what its job wants of you or where it stands. An ask's line that's new counts as just shown,
// so the buttons at its end (Deploy) wait before they take a press, as any just shown do.
core.rowLooks.push((row) => {
  const s = row.s, sid = s.sessionId;
  if (TEAM_ROLES.includes(s.team?.role) && s.team.name) row.name = s.team.shown || s.team.name;
  // A chat beside the folded panel is there to say what's new, the reply or what it asks: the row whole, under its
  // name in the team as its row in the list has. What the list's row last showed is left as it is: the chat is drawn
  // beside it with each update (and by itself in between), and isn't the row.
  if (!row.brief) {
    if (!row.chat) delete state.teamAsks[sid];
    return;
  }
  const next = s.team?.next;
  const also = s.team?.alsoAsks;
  const asks = s.team?.job?.you ? `${s.team.job.id}:${s.team.job.at}` : also ? `${also.job}:${also.at}`
    : next ? `next:${next.job || ''}:${next.short}` : null;
  if (asks && state.teamAsks[sid] !== asks) showAgain(s);
  if (asks) state.teamAsks[sid] = asks;
  else delete state.teamAsks[sid];
});
// Its class with a job, where one stands, or what's next for you on the lead (it has a card). Its dot is the list's,
// saying whose move it is: a job waiting on you shows on its own line, its track and the counts, never on the dot, so a
// reply you've read never looks unread.
core.slots.rowClass.push((row) => {
  const team = row.s.team;
  return row.brief && (team?.job || team?.next || team?.status) ? ' tjob' : '';
});

// After the name on a brief row: Chief on the chief, the session you talk to, else the lead (its counts are on the team
// board, so its name has the room); on the lead behind a session you talk to or a member, the tag the file gives it in
// the same look, else what it looks after; on another session open where one of the team works, whose folder it is, or,
// running in a member's own workspace beside the session on the member's row, that it's a duplicate of it.
core.slots.brief.push((row) => {
  const team = row.s.team;
  if (!team) return '';
  if (team.chief) return '<span class="tag ttag">Chief</span>';
  if (team.tag) return `<span class="tag ttag">${esc(team.tag)}</span>`;
  if (team.duplicate) {
    return `<span class="tpart" title="${esc(duplicateTip(team))}">${esc(`Duplicate of ${team.inFolderOf}`)}</span>`;
  }
  const part = team.inFolderOf ? `In ${team.inFolderOf}'s folder` : team.part;
  return part ? `<span class="tpart">${esc(part)}</span>` : '';
});
// A job's track at the title line's end, before the time: the row puts a gap before it, so the tracks line up from row
// to row whatever follows the words.
core.slots.titleTrail.push((row) => (row.brief && row.s.team?.job
  ? trackHTML(row.s.team.job, trackNow(row.s.team.job, row.kind)) : ''));

core.rowNotes.push((row) => {
  // A chat beside the folded panel is the row whole, with no team's line: what the list's row showed stays as it was.
  if (row.chat) return null;
  const nameOf = (id) => state.last.sessions?.find((x) => x.sessionId === id)
    ?.team?.name || '';
  const sid = row.s.sessionId, team = row.s.team;
  const note = row.brief ? teamNote(team, sid, nameOf) : null;
  // Its action waits to be seen before it takes a press: when it first shows, and each time it's for another job, step
  // or session, or does another thing (`teamActs`, what it was last drawn for), the other job waiting on you among them.
  const act = note?.act?.html ? [team.job?.id, team.job?.at, team.alsoAsks?.job, team.alsoAsks?.at, team.next?.job,
    team.next?.short, note.act.html].join('|') : null;
  if (act && state.teamActs[sid] !== act) state.shownAt['team-act:' + sid] = Date.now();
  if (act) state.teamActs[sid] = act;
  else {
    delete state.shownAt['team-act:' + sid];
    delete state.teamActs[sid];
  }
  return note;
});
core.forgotten.prefixes.push('team-act');
// The action pressed: to the session where what's asked waits, once it's been seen.
core.presses.push(['[data-team-go]', (el, e) => {
  e.preventDefault();
  const sid = el.closest('.row[data-id]')?.dataset.id;
  if (!sid || justShown('team-act:' + sid)) return;
  const s = state.last.sessions.find((x) => x.sessionId === el.dataset.teamGo);
  if (s) openSession(s);
}]);
core.pointerTargets.push('[data-team-go]');
core.rowNotesLast.push((row) => (row.brief ? duplicateNote(row.s.team) : null));
core.rowNotesLast.push((row) => (row.brief ? teamStatusNote(row.s.team?.status, row.kind) : null));

// A job's details come from its track, the counts in the note, or its second line, never the whole row, so moving
// down the list doesn't open every row on the way; and only from the team's own line, never another module's in its
// place (One Task's), nor the ask for another of its jobs than the one at work (`talso`), whose details these aren't.
core.cards.push({
  selector: '.row.tjob[data-id] .step-track, .row.tjob[data-id] .tsum, .row.tjob[data-id] > .main > .step-note.task, '
    + '.row.tjob[data-id] > .main > .step-note.tstatus',
  key: (el) => 'team:' + el.closest('.row').dataset.id,
  html(el) {
    const s = state.last.sessions.find((x) => x.sessionId === el.closest('.row').dataset.id);
    const team = s?.team;
    return team?.next ? teamNextCardHTML(s) : team?.job ? teamCardHTML(s, state.last.now)
      : team?.status ? teamStatusCardHTML(s, state.last.now) : '';
  },
});
// The track and the second line cross-fade as the job moves on.
core.swaps.push(':scope > .main > .line1 .step-track');
