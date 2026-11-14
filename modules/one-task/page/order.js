// One Task's rules, as plain functions (its page cases check them): what waits on you and in what order, the one in
// front, what each kind of task asks of you and the answer each button gives, and the line that says a task waits.
// Nothing here draws.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// Each kind's tag, as the task's head shows it.
// The kinds' words, by kind, as the app sends them with what waits (setTasks), from the task's contract
// (TaskKindWords): a task of a kind not among them isn't shown.
let taskKindWords = {};
// Where a task stands in the line: by its ticket's priority, then by when it came. A task's own priority isn't read
// (the contract leaves it out): only the priority of the ticket its session works on, which whoever writes the ticket
// sets, as its row carries it (rows.md: ticket), never the task.

// A task's place by its ticket: { at, of, word, queue }, `at` its priority's place in its tracker's own list (0 the
// most pressing) and `of` how many that list has, so tickets from trackers that name their priorities differently go
// in one order; `word`, the tracker's own word for it. The ticket is that of the session the task is about
// (taskThere: for the lead's pick, its member's; a pick for a member who isn't listed has no ticket, never the lead's
// own). A lead's pick its queue names, whose member's ticket has no place, takes its job's place in the queue instead,
// in the team module's words and with its look (core.teamJob), `queue` then. A ticket whose priority has no place yet
// (its tracker gives no order, or hasn't read it) has its word and `at` null; no ticket, or one with no priority,
// gives null.
function taskPlace(item) {
  const there = item.pickFor && !taskMember(item) ? null : taskThere(item);
  const bound = there?.ticket?.bound, word = typeof bound?.priority === 'string' ? bound.priority : '';
  const at = bound?.priorityAt, of = bound?.priorities;
  if (Number.isInteger(at) && Number.isInteger(of) && at >= 0 && at < of) return { at, of, word, queue: false };
  if (item.pick && item.pickAt != null && core.teamJob?.priorityPlace) {
    const { at: job, of: ladder, look } = core.teamJob.priorityPlace(item.pickPriority);
    return { at: job, of: ladder, look, word: core.teamJob.priorityWord(item.pickPriority), queue: true };
  }
  return word ? { at: null, of: null, word, queue: false } : null;
}
// Whether a task is one to do now: by a ticket, its place above the middle of its tracker's list, less than half its
// length rounded down (Jira's Highest and High of five, the top one of two or three, none of a list of one); by a
// team's queue, as the team says it (its look: Critical and P0). Never one put back with Can't Now.
const taskDoNow = (item) => !item.back && Number.isInteger(item.place?.at)
  && (item.place.queue ? item.place.look === 'urgent' : item.place.at < Math.floor(item.place.of / 2));
// How it's coloured, by the same rule: a task to do now in the colour of something to put right; by a ticket, one at
// its list's lowest place as low, and by a queue, as the team colours it; every other as normal.
const taskLook = (item) => (taskDoNow(item) ? 'urgent'
  : item.place?.queue ? (item.place.look === 'low' ? 'low' : 'normal')
    : Number.isInteger(item.place?.at) && item.place.at === item.place.of - 1 ? 'low' : 'normal');

// What waits on you, in the order One Task hands it to you: the tasks sessions sent (setTasks), while their session is
// listed, each { key, sid, s, task, place, came, at, sent, back }, and for the lead's pick (`pick`, in the lead's
// record) the member's session it's for (`forS`), if listed. Only tasks: a session's own request, question or plan
// stays on its row in the list, so nothing shows in two places. Those with a place by it (taskPlace), the most pressing
// first, two lists compared from the top; then those with none; then Can't Now, in the order they were put there.
// Within each, first come first served (`came`): a lead's pick from when its queue first named it (`shownAt`).
function taskLine(sent, sessions) {
  const items = [], byId = new Map(sessions.map((s) => [s.sessionId, s]));
  for (const one of sent) {
    const s = byId.get(one.sessionId);
    if (!s || !one.task?.id) continue;
    const isPick = !!one.pick, forS = isPick && one.for ? byId.get(one.for) : undefined;
    const item = { key: `task:${one.sessionId}:${one.task.id}`, sid: one.sessionId, s, task: one.task, back: !!one.back,
                   at: one.at || 0, came: (isPick && one.shownAt) || one.at || 0, sent: one.sent || 0, pick: isPick,
                   forS, writers: taskWriters(s, forS, sessions), about: taskAboutOf(s, one.task, sessions, byId),
                   talk: one.talk, takenBack: one.takenBack || null, pickAt: one.pickAt ?? null,
                   pickPriority: one.pickPriority || null, seenAt: one.seenAt || 0,
                   pickFor: isPick && !!one.for && one.for !== one.sessionId };
    item.place = taskPlace(item);
    items.push(item);
  }
  const group = (item) => (item.back ? 2 : Number.isInteger(item.place?.at) ? 0 : 1);
  return items.sort((a, b) => group(a) - group(b) || (group(a) === 0 ? a.place.at - b.place.at : 0)
    || (a.back ? a.at - b.at : a.came - b.came));
}

// What each session's row says waits on you, from the line in its order: session id → { item, more }, its first task and
// how many more of its own wait. Only a session's own tasks: a lead's picks are on the team's rows already, a task put
// back with Can't Now is one you said not now to, and one taken back no longer waits.
function taskAsks(items) {
  const asks = new Map();
  for (const item of items) {
    if (item.pick || item.back || item.takenBack) continue;
    const ask = asks.get(item.sid);
    if (ask) ask.more += 1;
    else asks.set(item.sid, { item, more: 0 });
  }
  return asks;
}

// What each kind of task asks of you, as the one button that does it: its icon (which of the kit's) and its verb, the
// same wherever an ask of that kind is drawn (a team's step reads them through the core: core.taskKinds), and what a
// press does with the task in hand (`does`): copies its command ('copy'), opens its attached page ('open'), opens One
// Task at it ('read'), or takes you to its session ('there').
const TASK_KIND_ACTS = {
  try: { icon: 'out', verb: 'Take Me There', does: 'there' },
  approve: { icon: 'plan', verb: 'Read the plan', does: 'read' },
  pick: { icon: 'prototype', verb: 'See the looks', does: 'open' },
  answer: { icon: 'answer', verb: 'See the question and its choices', does: 'read' },
  run: { icon: 'copy', verb: 'Copy the command', does: 'copy' },
  do: { icon: 'out', verb: 'Take Me There', does: 'there' },
  seen: { icon: 'seen', verb: 'See it', does: 'open' },
};

// A task's one action on its session's row, at its ask's end, by its kind (TASK_KIND_ACTS): { act, icon, tip, want,
// to }. `act` is what a press does: copies the command ('copy'), opens its attached page in your browser ('open'),
// takes you to a session ('there', `to`), or opens One Task at it ('reader'); `icon` which of the kit's it shows. A
// page to open that isn't attached opens One Task at it, as does a plan, unless it waits in its tab (`inTab`), where
// its session is. A try of the row's own session's stands in for Deploy (`want` 'try'), taking you to it when there's
// nothing to deploy; a try about another session takes you there, as the row's Deploy would put the wrong checkout in
// place. None of them answers it.
function taskRowAct(item) {
  const task = item.task, kind = TASK_KIND_ACTS[task.kind];
  if (!kind) return { act: 'reader', icon: 'answer', tip: 'Open in One Task' };
  const there = item.about?.s || taskThere(item), go = (tip) => ({ act: 'there', icon: kind.icon, tip, to: there });
  if (kind.does === 'there') {
    const own = task.kind === 'try' && there === item.s;
    return { ...go(`${kind.verb}: ${taskWho(there)}`), ...(own ? { want: 'try' } : {}) };
  }
  if (kind.does === 'copy') return { act: 'copy', icon: kind.icon, tip: `${kind.verb}, to paste in your terminal` };
  if (kind.does === 'open' && taskOpenAt(task) >= 0) {
    return { act: 'open', icon: kind.icon, tip: `${kind.verb}, in your browser` };
  }
  if (task.kind === 'approve' && task.inTab) return go(`${kind.verb}, in ${taskWho(there)}’s session`);
  return { act: 'reader', icon: kind.icon, tip: kind.verb };
}

// The one in front: the first in the line, but while you type in the view or point at it, the one you're on stays, as
// long as it still waits, so nothing changes under you.
function taskFront(items, shownKey, holding) {
  return (holding && items.find((item) => item.key === shownKey)) || items[0] || null;
}

// A task's step, as it's said over it: "Step 2 of 3 · Sign in on your laptop", or "Step 2 of 3" with no name.
function taskStepWords(task) {
  const step = task.step;
  if (!step) return '';
  return `Step ${step.n} of ${step.of}${step.name ? ` · ${step.name}` : ''}`;
}
// What makes what's shown new: the task, and when it was last sent (its next step, or the same step with what's
// new), which an answer names so it never lands on words sent after the ones you read; a request, by its id alone.
const taskStepKey = (item) => `${item.key}#${item.sent ?? ''}`;

// The parts a task has, in the order they show: a plan's own short view (`glance`), what changed, a plan's points or
// its phases, steps to tick, what to look for, a command only you can run, and last its answers to pick from
// (taskChoices), every kind having some.
// Every part it has shows, so a button never acts on something you can't see.
function taskParts(task) {
  return [task.glance && 'glance', task.changed && 'changed', task.points?.length && 'points',
    task.phases?.length && 'phases', task.todo?.length && 'todo', task.lookFor && 'lookFor',
    task.command?.run && 'command', 'choices'].filter(Boolean);
}

// A point that says what a plan leaves out ("Not in it: …"): shown greyed, and not counted.
const taskPointOut = (point) => /^not in it\b/i.test(point);
// What a plan's points are headed by: "Approve these 7 points" (or "Approve this point") for one to approve, else how
// many; never counting what it leaves out.
function taskPointsWords(task) {
  const n = task.points.filter((p) => !taskPointOut(p)).length;
  if (task.kind === 'approve') return n === 1 ? 'Approve this point' : `Approve these ${n} points`;
  return `${n} point${n === 1 ? '' : 's'}`;
}

// The line under a pick's looks until one is picked, saying two may be mixed: or nothing. What any other task waits
// for is said beside Answer (taskAnswerWaits).
function taskPickHint(task, chosen) {
  return task.kind === 'pick' && !chosen.length ? 'Pick one to send it, or two to mix them.' : '';
}

// What a press on something attached does: a link or a page opens in your browser ('web'); a file only if a session
// it may come from wrote it (taskWriting), in the reader ('writing'); the changes in the changes view ('changes');
// anything else (a commit, a file none of them wrote) shows without one (null).
function taskAttachOpens(a, item) {
  if (a.kind === 'diff') return 'changes';
  if (a.kind === 'link' || a.kind === 'page') return a.url ? 'web' : null;
  return a.kind === 'file' && taskWriting(item, a.path) ? 'writing' : null;
}
// The sessions besides the one that sent a task whose writings its files may open from: for the lead's pick, the
// member it's for; and for a task from a team's lead, the team's own sessions, its members and the ones it follows
// (row.team), never the rest of yours, as a team file any session can write could name one as its lead.
function taskWriters(s, forS, sessions) {
  const leads = s.team?.role === 'lead' ? s.team.leads || [] : null;
  const team = leads ? sessions.filter((one) => one !== s && one !== forS
    && (leads.includes(one.sessionId) || one.team?.role === 'followed')) : [];
  return [forS, ...team].filter(Boolean);
}
// The writing at `path`, with the session it's in ({ s, w }), which the reader can open, or null: one of the writings
// (rows.md: writings) of the session that sent the task, else of the sessions its files may come from (taskWriters),
// the one that wrote it last, so the reader opens it under the session that wrote it.
function taskWriting(item, path) {
  if (!path) return null;
  const at = (s) => (s?.writings || []).find((one) => one.path === path);
  if (at(item.s)) return { s: item.s, w: at(item.s) };
  let found = null;
  for (const s of item.writers || []) {
    const w = at(s);
    if (w && (!found || (w.at || 0) > (found.w.at || 0))) found = { s, w };
  }
  return found;
}
// The session a task is about (task.about), to take you there: only from a team's lead, and only to the lead itself
// or one of its team's own sessions (taskWriters), as a team file any session can write could name one its lead.
// {s, name}: the session, and the name the list knows it by, with its folder when another listed session has the
// same name, so you can tell which; or {why} it can't; or null when the task names none, or isn't a lead's.
function taskAboutOf(s, task, sessions, byId) {
  if (!task.about || s.team?.role !== 'lead') return null;
  const to = byId.get(task.about);
  if (!to) return { why: 'Its session isn’t in your list now' };
  if (to !== s && !taskWriters(s, undefined, sessions).includes(to)) {
    return { why: 'Can’t go there: it isn’t one the team leads or follows' };
  }
  const name = taskWho(to), twin = sessions.some((one) => one !== to && taskWho(one) === name);
  return { s: to, name: twin && to.cwd ? `${name} in ${base(to.cwd)}` : name };
}
// Why a file it attached doesn't open, in plain words: no session it may come from wrote it.
const taskAttachWhy = (item) => (item.s.team?.role === 'lead' ? 'Can’t open: no one on the team wrote it'
  : `Can’t open: ${taskWho(item.s)} didn’t write it`);

// What you answer a task with, as choices to pick from, every kind alike, so you either choose or say it in words and
// the answer is only one: a question's or a pick's own choices, with More options for a pick; else the kind's one
// plain answer (Works, Approve, Done, Seen); and last, always, Comment, an answer in your own words, in a box under it
// once it's picked. Each {id, label, detail, recommended}, its id what's sent (TaskRecordFits).
const TASK_COMMENT = { id: 'Comment', label: 'Comment', detail: 'Answer in your own words', comment: true };
const TASK_PLAIN = { try: ['Works', 'It does what it says'], approve: ['Approve', 'Go ahead with it as it is'],
                     run: ['Done', 'It ran'], do: ['Done', 'It’s done'], seen: ['Seen', 'You’ve seen it'] };
function taskChoices(task) {
  const plain = TASK_PLAIN[task.kind];
  const own = task.kind === 'answer' || task.kind === 'pick' ? task.choices || []
    : plain ? [{ id: plain[0], label: plain[0], detail: plain[1] }] : [];
  const more = task.kind === 'pick' ? [{ id: 'More Options', label: 'More options', detail: 'Ask for other looks' }]
    : [];
  return [...own, ...more, TASK_COMMENT];
}
// Comment and More options are answers on their own: picking one lets the rest go.
const taskAlone = (id) => id === 'Comment' || id === 'More Options';

// The buttons under a task's answers, in order, each { act, word, main, quiet, off }: what you do that isn't an
// answer (Open a prototype, Copy a command, Can't Now, Take Me There), then Answer, the one action, dimmed until the
// choice picked can be sent (taskCanAnswer). Open and Copy are the main one until pressed (`ui.first`), and so is
// Take Me There to the session a lead's task is about (`about`, taskAboutOf) when the task is something to do there.
function taskButtons(task, ui, about) {
  const opened = !!ui.first, page = task.kind === 'pick' && taskOpenAt(task) >= 0;
  const there = about?.s && { act: 'there', word: `Take Me There: ${about.name}` };
  const first = page ? [{ act: 'first', word: 'Open', main: !opened }]
    : task.kind === 'run' ? [{ act: 'first', word: opened ? 'Copied' : 'Copy', main: !opened }]
    : there && task.kind === 'do' ? [{ ...there, main: !opened }] : [];
  const aside = task.kind === 'do' ? [{ act: 'later', word: 'Can’t Now', quiet: true }] : [];
  const tab = there ? (task.kind === 'do' ? [] : [{ ...there, quiet: true }])
    : task.kind === 'approve' && task.inTab ? [{ act: 'there', word: 'Take Me There', quiet: true }] : [];
  return [...first, { act: 'answer', word: 'Answer', main: !first.length || opened, off: !taskCanAnswer(task, ui) },
          ...aside, ...tab];
}

// The answer the choices picked give, as the app keeps it and the session reads it (TaskRecordFits): Comment, More
// Options, the kind's plain answer, or the choices' ids, one, two joined with "+" for a pick that mixes them, any
// joined with "," for a question that takes several. Null while nothing is picked.
function taskAnswer(task, chosen) {
  if (chosen.includes('Comment')) return 'Comment';
  if (chosen.includes('More Options')) return 'More Options';
  if (task.kind === 'pick' || task.kind === 'answer') {
    const ids = (task.choices || []).map((c) => c.id).filter((id) => chosen.includes(id));
    return ids.length ? ids.join(task.kind === 'pick' ? '+' : ',') : null;
  }
  return chosen[0] === TASK_PLAIN[task.kind]?.[0] ? chosen[0] : null;
}
// What's said beside Answer while it waits, dimmed, as what it waits for may be out of sight above: or nothing.
function taskAnswerWaits(task, ui) {
  if (taskCanAnswer(task, ui)) return '';
  return ui.chosen.includes('Comment') ? 'Write your comment above' : 'Pick an answer above';
}
// Whether Answer can send: a choice picked, and for Comment, words in its box.
const taskCanAnswer = (task, ui) => {
  const answer = taskAnswer(task, ui.chosen);
  return !!answer && (answer !== 'Comment' || !!String(ui.note || '').trim());
};

// Where the first page a pick attached is among what's attached (its Open opens it), or -1.
function taskOpenAt(task) {
  return (task.attach || []).findIndex((a) => a.kind === 'page' && a.url);
}

// A choice pressed: picked or let go. Comment and More options are each an answer of its own; a pick may mix two of its
// looks (a third lets the first go); a question that takes several takes any; otherwise the one pressed is the one
// picked.
function taskChoose(task, chosen, id) {
  if (chosen.includes(id)) return chosen.filter((c) => c !== id);
  if (taskAlone(id)) return [id];
  const rest = chosen.filter((c) => !taskAlone(c));
  if (task.kind === 'pick') return [...rest, id].slice(-2);
  return task.several ? [...rest, id] : [id];
}

// What Comment's box asks for, once Comment is picked: a comment for whom the answer goes to.
const taskBoxWords = (to) => `A comment for ${to}`;

// Who a task is from, as Whozmove found it asking: the name the list shows it by, its name in its team (rows.md: team)
// when it has one, else the session's own name, else its folder's; never one a task gives itself.
const taskWho = (s) => s.team?.name || s.name || base(s.cwd || '');
// The member the lead's pick is for, when it's another session than the lead's own and it's listed: a lead's pick
// about its own work has none, so it's said as the lead's alone. By session, never by any role.
const taskMember = (item) => (item.pick && item.forS && item.forS.sessionId !== item.sid ? item.forS : undefined);
// Whom a task is from, as the head says it: the session's name, with its ticket's priority in its tracker's word when
// it has one ("From Wren · Highest"); for the lead's pick, the lead's, and the member's it's for ("Atlas's pick, for
// Wren"), or the lead's name alone for a pick about its own work ("Atlas").
function taskFrom(item) {
  if (!item.pick) return `From ${taskWho(item.s)}${item.place?.word ? ` · ${item.place.word}` : ''}`;
  const member = taskMember(item);
  return member ? `${taskWho(item.s)}’s pick, for ${taskWho(member)}` : taskWho(item.s);
}
// The session a task is about, where Take Me There goes and whose changes it shows: the member the lead's pick is
// for, if there's one, else the session that sent it.
const taskThere = (item) => taskMember(item) || item.s;
// What's said of a task its session took back (`takenBack`, why: answered elsewhere, its job parked or dropped), on it
// while you're still on it, and at the foot once it has gone.
function taskTakenBackWords(item) {
  const who = taskWho(item.s);
  return { answered: `Taken back: answered in ${who}’s session`, parked: `Taken back: ${who} parked its job`,
           dropped: `Taken back: ${who} dropped its job` }[item.takenBack] || `Taken back by ${who}`;
}

// What the foot says when the task in front changes under the same id while you're on it (its sender reworded it, or
// sent its next step): who changed it, so a question that changes in place is never taken for another.
// When a choice you'd picked was let go with it (taskPickLetGo), it says to pick again, so a pick that's gone is never
// left unexplained.
const taskUpdatedWords = (item, letGo = false) => `${taskWho(item.s)} updated this just now: ${
  letGo ? 'pick again on what you see now' : 'it’s what you see now'}.`;
// …and when you come back to it changed (‹ Back, or opening One Task again), as it changed while you were elsewhere.
const taskUpdatedAwayWords = (item, letGo = false) => `${taskWho(item.s)} updated this while you were away: ${
  letGo ? 'pick again on what you see now' : 'it’s what you see now'}.`;
// Whether a change let go of a choice you'd picked (`before` and `after`, what you'd done on it, as taskKeptUi keeps it):
// any but Comment, which stays with your words.
const taskPickLetGo = (before, after) => before.chosen.some((id) => id !== 'Comment' && !after.chosen.includes(id));
// Whom your answer goes to, as the foot says it.
const taskTo = (item) => (taskMember(item) ? `${taskWho(item.s)}, for ${taskWho(taskMember(item))}` : taskWho(item.s));

// What the foot says once you've answered: where it went.
function taskSaid(item, answer, note) {
  const to = taskTo(item);
  if (answer === 'Comment') return `Sent to ${to}: your comment.`;
  if (answer === 'Seen') return 'Seen.';
  return `Sent to ${to}: “${answer}”${note ? ', with your note' : ''}.`;
}

// When the newest of what waits came (a task's last send, a request's coming), never going back: what's new to the line
// under the header is only what comes after.
function taskNewest(items, before) {
  return items.reduce((most, item) => Math.max(most, item.sent || item.at || 0), before || 0);
}

// The line under the header while One Task isn't in sight and something waits (a page sender's notice for the
// notifications module): who it's from and its title, and for the lead's pick, as its head names it ("Atlas's pick,
// for Wren: Search box"). What makes it new is the newest to come (taskNewest), so once its × has put it away it stays
// away until another task joins, or one is sent again; meanwhile it folds to how many wait, which opens One Task as
// Open does. With more than one waiting, the line says how many after its words, the same as it folds to, so the
// number is the same either side of its ×.
function taskNotice(items, newest, onKey) {
  // Those to do now have a line of their own (taskUrgentNotice), which comes first, and is said in quiet hours; but
  // for the one you were on (`onKey`), which it leaves out, as its Open doesn't go back to it: this line names that.
  const item = items.find((one) => !taskDoNow(one) || one.key === onKey);
  if (!item) return null;
  const what = item.task.title;
  return { key: 'waits', level: 'soon',
           text: item.pick ? `${taskFrom(item)}: ${what}` : `A task from ${taskWho(item.s)} waits: ${what}`,
           after: items.length > 1 ? `${items.length} waiting` : undefined, button: 'Open', since: String(newest || 0),
           chip: `${items.length} waiting`, chipTitle: 'Open One Task' };
}

// ---- Something to do now while you're on a task ----

// A task you've seen stays yours until you leave it: seen once it has been in front this long with One Task open, or
// the moment you press anything on it.
const TASK_SEEN_MS = 1500;

// Whether Go can set a task aside to come back to: any task, one to do now among them, as Go only ever goes to one
// ahead of it.
const taskSetsAside = (item) => !!item?.task;

// The tasks to do now that are ahead of the one you're on (`frontKey`) in the line, in its order: all of them when
// that isn't in it.
function taskUrgentOthers(items, frontKey) {
  const front = items.findIndex((item) => item.key === frontKey);
  return items.filter((item, at) => taskDoNow(item) && (front < 0 || at < front));
}

// What the strip under One Task's head says of them, with Go, in pieces, so its bold part is never cut from the
// sentence: { head, title, more }, "Highest from Wren" and "Fix the login crash", or for more than one, "2 to do now"
// and "Fix the login crash", with " and 1 more"; the tracker's word as it gave it. Null for none.
function taskUrgentParts(urgent) {
  if (!urgent.length) return null;
  const first = urgent[0];
  if (urgent.length > 1) return { head: `${urgent.length} to do now`, title: first.task.title,
                                  more: ` and ${urgent.length - 1} more` };
  return { head: `${first.place?.word || 'To do now'} from ${taskWho(first.s)}`, title: first.task.title, more: '' };
}
// …the same as one line: "Highest from Wren: Fix the login crash".
function taskUrgentWords(urgent) {
  const parts = taskUrgentParts(urgent);
  return parts ? `${parts.head}: ${parts.title}${parts.more}` : '';
}

// The line under the header for the tasks to do now, while One Task isn't in sight: the strip's words, with Open,
// which goes straight to the first and sets aside the task you were on (`onKey`), never named here, as Open doesn't go
// back to it; new again whenever they change, so its × puts away only the ones it named.
function taskUrgentNotice(items, onKey) {
  const urgent = items.filter((item) => taskDoNow(item) && item.key !== onKey);
  if (!urgent.length) return null;
  return { key: 'urgent', level: 'urgent', text: taskUrgentWords(urgent), button: 'Open',
           since: urgent.map(taskStepKey).join(' ') };
}

// What the foot says of the task you set aside, when it wasn't there to come back to: taken back by its session (176),
// with why, or gone some other way (answered elsewhere, its session ended).
function taskAsideGone(title, item) {
  if (!item?.takenBack) return `“${title}” no longer waits.`;
  const who = taskWho(item.s);
  return `“${title}” was taken back: ${{ answered: `answered in ${who}’s session`, parked: `${who} parked its job`,
    dropped: `${who} dropped its job` }[item.takenBack] || `by ${who}`}.`;
}

// Which task is in front, as One Task decides it, from where you are (`on`): { next, key, held, seen, waitForGo,
// wanted, aside }, the task a press has just brought in, the one you're on, whether you're pointing at it or typing in
// it, which tasks you've read (a function of the task's key: a task, not a step, so a reword or its next step leaves it
// read), whether one to do now waits for your Go, the one a row's task line opened at, and the task you set aside
// ({key, step}) to come back to. A task you've read is yours until you leave it: nothing replaces it, not a newer task,
// not the lead reordering or rewording it, not one to do now (with `waitForGo` off, one to do now ahead of it does).
// While one is set aside, those to do now ahead of it come first. Gives { front, gone }: `gone`, the task you set
// aside, as it was let go, when it no longer waits. Coming back to it, what's kept of what you'd done on it is
// taskKeptUi's.
function taskChooseFront(items, on) {
  const find = (key) => (key ? items.find((item) => item.key === key) || null : null);
  if (find(on.next)) return { front: find(on.next) };
  const current = find(on.key);
  // With tasks to do now not waiting for your Go (One Task's page, `waitForGo` false), one ahead takes the front from
  // a task you've read; nothing else does.
  const holds = on.seen(current?.key) && (on.waitForGo !== false || !taskUrgentOthers(items, current?.key).length);
  if (current && (on.held || holds)) return { front: current };
  if (find(on.wanted)) return { front: find(on.wanted) };
  if (on.aside) {
    // The one to do now that a press brought in stays in front, read or not, while no other to do now is ahead of it:
    // Open on the line under the header can bring in one behind the task it sets aside, as it names those too.
    if (current && current.key !== on.aside.key && taskDoNow(current)
        && !taskUrgentOthers(items, current.key).some((item) => item.key !== on.aside.key)) return { front: current };
    const urgent = taskUrgentOthers(items, on.aside.key)[0];
    if (urgent) return { front: urgent };
    const it = find(on.aside.key);
    if (it && !it.takenBack) return { front: it };
    return { front: items.find((item) => !item.takenBack) || null, gone: it || on.gone || { takenBack: null } };
  }
  return { front: items[0] || null };
}

// What's kept of what you'd done on a task (`ui`, as one-task.js keeps it) when it comes back changed under the same
// id, `before` as you saw it and `after` as it is now (a reword, its next step): your words, Comment still picked for
// them, the code you'd opened in its talk, and what you'd ticked while its steps are the same. Every other pick, and the
// kind's plain answer (Approve, Works, Done), goes: nothing you chose on the old words is sent with the new ones, as an
// answer always names the step you see. Unchanged, all of it stays.
function taskKeptUi(ui, before, after) {
  if (JSON.stringify(before) === JSON.stringify(after)) return ui;
  const sameSteps = JSON.stringify(before?.todo || []) === JSON.stringify(after?.todo || []);
  return { ...ui, first: false, chosen: ui.chosen.includes('Comment') ? ['Comment'] : [],
           ticks: sameSteps ? ui.ticks : {}, copied: {} };
}

// What becomes of the task you were on (`left`: {key, sid}) once it has left the line, neither answered here nor taken
// back (each of which says so itself), from what's known now (`now`: { on, turnedAway, waiting, touched }): whether One
// Task is on, the sessions that may not hand you tasks now, the keys the app still keeps waiting, and whether you've
// started on the task in front since (a press, or typing). While the app still keeps it, it was only its session's row
// missing from a read: 'back' once it's in the line again, as it was yours, unless you've started on another since;
// 'gone' once the app no longer keeps it, for the foot to say it no longer waits; 'drop' to forget it, saying nothing,
// as it still waits then (One Task off, its session turned away) or you've moved on; null to wait and see.
function taskLeft(left, items, now) {
  if (!now.on || now.turnedAway.includes(left.sid)) return 'drop';
  if (items.some((item) => item.key === left.key)) return now.touched ? 'drop' : 'back';
  return now.waiting.has(left.key) ? null : 'gone';
}

// Which task One Task opens on, of what waits: the one you were last on (`last`, {key}), if you'd read it (`seen`, a
// function of its key) and it still waits, changed or not; when there's none, as after Whozmove restarts, the waiting
// one you read most recently (`seenAt`, kept by the app), never one put back with Can't Now nor one taken back. Null
// for none: the line's first then.
function taskOpensOn(items, last, seen) {
  if (last) return items.find((item) => item.key === last.key && seen(item.key)) || null;
  return items.filter((item) => item.seenAt && !item.back && !item.takenBack)
    .sort((a, b) => b.seenAt - a.seenAt)[0] || null;
}

// Say why each is here (One Task's page): why the one in front is first, and each after it is where it is, in a
// line: its ticket's priority in its tracker's word ("Highest on its ticket"), or with no order known for it (its
// tracker gives none, or couldn't be read); a lead's pick by its queue ("P1 in Atlas's queue"); a ticket with no
// priority, one not read yet since Whozmove started, or no ticket; then how long it has waited, "longest" for the first
// of those in the same place.
function taskWhyHere(item, items, now) {
  if (item.back) return 'You put it back with Can’t Now';
  const p = item.place, placed = Number.isInteger(p?.at), bound = taskThere(item).ticket?.bound;
  const none = !bound ? 'No ticket' : !bound.readAt ? 'Its ticket isn’t read yet' : 'No priority on its ticket';
  const why = !p ? none : p.queue ? `${p.word} in ${taskWho(item.s)}’s queue`
    : `${p.word} on its ticket${placed ? '' : ', no order known'}`;
  const same = items.filter((one) => !one.back && (placed ? one.place?.at === p.at : !Number.isInteger(one.place?.at)));
  const waited = ago(now - item.came);
  return `${why}, ${same[0] === item ? `waited longest, ${waited}` : `waited ${waited}`}`;
}

// The sessions that may not hand you tasks now (One Task's page: only a team's lead), what they sent waiting unseen,
// as a line under the task: "2 sessions can't hand you tasks: storefront, rq".
function taskTurnedAwayWords(ids, sessions) {
  const names = ids.map((id) => sessions.find((s) => s.sessionId === id)).filter(Boolean).map(taskWho);
  if (!names.length) return '';
  return `${names.length} session${names.length > 1 ? 's' : ''} can’t hand you tasks: ${names.join(', ')}`;
}

// What the foot says once you're back on the task you set aside.
// After Whozmove restarts, what you'd done on it wasn't kept: only back to it.
const taskBackWords = (title, asLeft = true) => `Back to “${title}”${asLeft ? ', as you left it' : ''}.`;

// The words the foot offers to copy when a task you were on, or set aside, no longer waits: what you'd typed in its
// Comment box, so nothing you wrote goes with it. What you wrote in its talk stays in its session's chat.
const taskKeptWords = (ui) => (ui?.note || '').trim();

// ---- The talk about a task: the chat with the session it's about, under the task ----

// Whom the talk is with: { s, name, lead }. The session that sent the task, or for the lead's pick its member, unless
// you chose the lead (`toLead`) or the member isn't listed: each is that session's own chat (Side Chat's), so the choice
// can change at any time. `lead`: the talk is with the lead, not its member.
function talkTo(item, sessions, toLead) {
  const s = taskMember(item) && !toLead ? taskMember(item) : item.s;
  return { s, name: taskWho(s), lead: !!item.pick && s === item.s };
}

// The words that open yours in the session, as the app makes them for the task and its step, shown under the box
// before you send and sent with your words: the member's own for the lead's pick, which name none of the lead's.
const talkOpening = (item, to) => (to.s && to.s !== item.s ? item.talk?.leadForMember : item.talk?.lead) || '';

// Where the session runs, as the talk's heading says it: in Claude Desktop, or its session in the terminal the app
// names (`terminals`, by session).
const talkWhere = (s, terminals) => (s?.entrypoint === 'claude-desktop' ? 'in Claude Desktop'
  : terminals?.[s?.sessionId] ? `its session in ${terminals[s.sessionId]}` : 'its session');
