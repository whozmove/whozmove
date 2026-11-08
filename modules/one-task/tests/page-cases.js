// One Task's rules, run outside the tApp by test.sh: what waits on you and in what order, the one in front, what each
// kind asks of you and the answer each button gives, and the tLine that says a task waits (order.js). Nothing is drawn.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

load('tests/page-harness.js');  // the stand-ins, the page's scripts and the helpers below use
// The kinds' words, as the app sends them with setTasks (TaskKindWords, app/contracts/Task.m).
taskKindWords = { try: 'Try', pick: 'Pick', approve: 'Approve', answer: 'Answer', run: 'Run', do: 'Do', seen: 'Seen' };

const tShop = session({ sessionId: 'shop', name: 'storefront' });
const tCli = session({ sessionId: 'cli', name: '', cwd: '/code/rq' });
const tApp = session({ sessionId: 'app', name: 'trailmap', ask: { id: 'a1', tool: 'Bash', at: min(4),
                                                                  input: { command: 'pod install' } },
                      statusUpdatedAt: min(4) });
const tSessions = [tShop, tCli, tApp];
const tSent = (sessionId, id, at, more = {}) => ({ sessionId, at, task: { id, kind: 'try', title: id, why: 'w', ...more },
                                                 ...(more.back ? { back: true } : {}) });
const tKeys = (items) => items.map((i) => i.key).join(', ');

section('What waits, in order');
show('by priority, the oldest first; Can\'t Now at the back; trailmap\'s own request not among them', tKeys(taskLine([
  tSent('shop', 'old', min(30)), tSent('cli', 'low', min(40), { priority: 'low' }), tSent('shop', 'new', min(5)),
  tSent('cli', 'back', min(50), { back: true }), tSent('shop', 'urgent', min(1), { priority: 'urgent' }),
], tSessions)));
show('a task from a session that isn\'t listed is left out', tKeys(taskLine([tSent('gone', 'x', min(3))], tSessions)));
show('a request waiting on you, and no task: nothing (the request stays on its row in the list)',
     tKeys(taskLine([], tSessions)));
show('a task waiting, and a request beside it: the task alone', tKeys(taskLine([
  tSent('app', 'Offline maps', min(10))], tSessions)));

section('The one in front');
const tLine = taskLine([tSent('shop', 'old', min(30)), tSent('shop', 'new', min(5))], [tShop]);
show('nothing held: the first', taskFront(tLine, 'task:shop:new', false).key);
show('held (typed in, pointed at): the one you\'re on stays', taskFront(tLine, 'task:shop:new', true).key);
show('held, but the one you were on has gone: the first', taskFront(tLine, 'task:shop:gone', true).key);
show('nothing waits', taskFront([], null, false));

section('Who it\'s from, and its step');
show('a session\'s name', taskWho(tShop));
show('one with none: its folder\'s', taskWho(tCli));
show('a try\'s step, as every kind\'s', taskStepWords({ kind: 'try', step: { n: 2, of: 3, name: 'Sign in on your laptop' } }));
show('another kind\'s step', taskStepWords({ kind: 'do', step: { n: 1, of: 2 } }));
show('no step', taskStepWords({ kind: 'seen' }));

section('Each kind\'s buttons');
const tUi = (more = {}) => ({ first: false, chosen: [], note: '', ...more });
const tWords = (task, given, about) => taskButtons(task, given, about)
  .map((b) => `${b.word}${b.main ? '*' : ''}${b.quiet ? ' (quiet)' : ''}${b.off ? ' (off)' : ''}`).join(' | ');
const tPage = { kind: 'link', label: 'p', url: 'https://claude.example/p' };
const tPick = { kind: 'pick', choices: [{ id: 'A' }, { id: 'B' }, { id: 'C' }], attach: [{ ...tPage, kind: 'page' }] };
show('try', tWords({ kind: 'try' }, tUi()));
show('pick, before Open', tWords(tPick, tUi()));
show('pick, opened, B picked', tWords(tPick, tUi({ first: true, chosen: ['B'] })));
show('pick, opened, two picked', tWords(tPick, tUi({ first: true, chosen: ['A', 'C'] })));
show('pick with no page to open', tWords({ ...tPick, attach: [] }, tUi()));
show('approve', tWords({ kind: 'approve' }, tUi()));
show('approve, waiting in its tab', tWords({ kind: 'approve', inTab: true }, tUi()));
show('answer, nothing picked', tWords({ kind: 'answer', choices: [{ id: 'a' }] }, tUi()));
show('try, Works picked', tWords({ kind: 'try' }, tUi({ chosen: ['Works'] })));
show('try, Comment picked, no words yet', tWords({ kind: 'try' }, tUi({ chosen: ['Comment'] })));
show('…and with words', tWords({ kind: 'try' }, tUi({ chosen: ['Comment'], note: 'The sheet never came up.' })));
show('…only spaces', tWords({ kind: 'try' }, tUi({ chosen: ['Comment'], note: '   ' })));
show('beside Answer while it waits: nothing picked, Comment with no words, picked',
     [taskAnswerWaits({ kind: 'try' }, tUi()), taskAnswerWaits({ kind: 'try' }, tUi({ chosen: ['Comment'] })),
      taskAnswerWaits({ kind: 'try' }, tUi({ chosen: ['Works'] }))]);
show('run, before Copy', tWords({ kind: 'run' }, tUi()));
show('run, copied', tWords({ kind: 'run' }, tUi({ first: true })));
show('do', tWords({ kind: 'do' }, tUi()));
show('seen', tWords({ kind: 'seen' }, tUi()));

section('The answer each press gives');
const tAsked = { kind: 'answer', several: true, choices: [{ id: 'ios' }, { id: 'android' }, { id: 'web' }] };
show('try, Works', taskAnswer({ kind: 'try' }, ['Works']));
show('approve, Approve', taskAnswer({ kind: 'approve' }, ['Approve']));
show('run, Done', taskAnswer({ kind: 'run' }, ['Done']));
show('pick, two picked (in the choices\' order)', taskAnswer(tPick, ['C', 'A']));
show('pick, More Options', taskAnswer(tPick, ['More Options']));
show('pick, nothing picked', taskAnswer(tPick, []));
show('a question taking several', taskAnswer(tAsked, ['web', 'ios']));
show('seen', taskAnswer({ kind: 'seen' }, ['Seen']));
show('a comment, on a do and on a seen', [taskAnswer({ kind: 'do' }, ['Comment']),
                                         taskAnswer({ kind: 'seen' }, ['Comment'])]);
show('a word that isn\'t its kind\'s', taskAnswer({ kind: 'try' }, ['Approve']));

section('Picking');
show('a pick takes two, a third letting the first go', taskChoose(tPick, ['A', 'B'], 'C'));
show('pressed again, it\'s let go', taskChoose(tPick, ['A', 'B'], 'A'));
show('a question taking one', taskChoose({ kind: 'answer', choices: [] }, ['a'], 'b'));
show('a question taking several', taskChoose(tAsked, ['ios'], 'web'));
show('Comment lets the others go, and a choice lets Comment go', [taskChoose(tAsked, ['ios', 'web'], 'Comment'),
                                                                   taskChoose(tAsked, ['Comment'], 'web')]);
show('More Options lets a pick\'s letters go', taskChoose(tPick, ['A', 'C'], 'More Options'));

section('Every task\'s choices, Comment last');
const tChoiceIds = (task) => taskChoices(task).map((c) => c.id).join(' | ');
show('each kind', ['try', 'approve', 'run', 'do', 'seen'].map((kind) => `${kind}: ${tChoiceIds({ kind })}`));
show('a pick, and a question', [tChoiceIds(tPick), tChoiceIds(tAsked)]);

section('Where your answer went');
const tItem = { s: tShop, task: { kind: 'try' } };
show('an answer', taskSaid(tItem, 'Works', ''));
show('a comment', taskSaid(tItem, 'Comment', 'Fine on the phone.'));
show('seen', taskSaid(tItem, 'Seen', ''));
show('Comment\'s box\'s words', taskBoxWords('storefront'));

section('What shows, and what a press on it does');
show('every part a task has, in order', taskParts({ kind: 'run', todo: ['Open your terminal'], command: { run: 'make' },
                                                   choices: [{ id: 'a' }] }));
show('a try with steps only', taskParts({ kind: 'try', todo: ['Open it'] }));
show('a try whole: what changed, its steps, what to look for', taskParts({ kind: 'try', changed: 'c', todo: ['t'],
                                                                         lookFor: 'l' }));
show('a plan\'s points, and its phases', [taskParts({ kind: 'approve', points: ['a', 'b'] }),
                                         taskParts({ kind: 'approve', phases: [{ name: 'n', lines: ['l'] }] })]);
const tPoints = ['Apple Pay above the card form', 'Behind the payments flag', 'Not in it: Google Pay',
                 'not in it saved cards', 'Nothing stored here'];
show('points headed by how many, never counting what it leaves out; one; and not a plan to approve',
     [taskPointsWords({ kind: 'approve', points: tPoints }), taskPointsWords({ kind: 'approve', points: ['a', 'Not in it: b'] }),
      taskPointsWords({ kind: 'seen', points: tPoints })]);
show('the line under a pick\'s looks until one is picked; none for a question, one taking several, picked, a try',
     [taskPickHint({ kind: 'pick', choices: [{ id: 'A' }] }, []), taskPickHint({ kind: 'answer', choices: [{ id: 'a' }] }, []),
      taskPickHint({ kind: 'answer', several: true, choices: [{ id: 'a' }] }, []),
      taskPickHint({ kind: 'answer', choices: [{ id: 'a' }] }, ['a']), taskPickHint({ kind: 'try' }, [])]);
const tBody = (task) => taskBodyHTML({ key: 'k', sid: 'shop', s: tShop, sent: 1, task: { id: 'x', why: 'Live.', ...task } },
                                     tUi({ ticks: {} }), null);
const tChoicesDrawn = (task) => tBody({ ...task, title: 'T' }).match(/<div class="options[\s\S]*?<\/div>/)[0];
const tDrawnWith = (chosen) => taskBodyHTML({ key: 'k', sid: 'shop', s: tShop, sent: 1, task: { id: 'x', why: 'Live.',
  kind: 'try', title: 'T' } }, tUi({ ticks: {}, chosen }), null).match(/<div class="options[\s\S]*?<\/div>/)[0];
show('a try\'s choices, drawn', tChoicesDrawn({ kind: 'try' }));
show('…Comment picked: its box on its line, under it', tDrawnWith(['Comment']));
show('a plan cut to its points, drawn: numbered, what it leaves out greyed',
     tBody({ kind: 'approve', title: 'Apple Pay', points: tPoints }));
const tGlance = '## At a glance\n\n- **What changes for you:** Apple Pay above the card form.\n- **You decide:**\n'
  + '  1. Where it shows: on Safari only (recommended), or everywhere. Why: <only> Safari has it.\n'
  + '- **Left out:** Google Pay.';
show('a plan with its own short view: first, before what to pick', taskParts({ kind: 'approve', glance: tGlance }));
show('a plan with its own short view, drawn: its card, as the plans module draws it',
     tBody({ kind: 'approve', title: 'Apple Pay', glance: tGlance }));
{
  const plans = core.plans;
  core.plans = null;
  show('…without the plans module: as the plan wrote it', tBody({ kind: 'approve', title: 'Apple Pay', glance: tGlance })
    .match(/<div class="ot-part"><span class="caps">The plan at a glance[\s\S]*?<\/div><\/div>/)?.[0]);
  core.plans = plans;
}
show('…a short view with a line the card has no place for: as the plan wrote it, even with the plans module',
     tBody({ kind: 'approve', title: 'Apple Pay', glance: `${tGlance}\n- **Cost:** a fee per payment.` })
       .match(/<div class="ot-part"><span class="caps">The plan at a glance[\s\S]*?<\/div><\/div>/)?.[0]);
show('a plan in phases, drawn', tBody({ kind: 'approve', title: 'Completions', step: { n: 2, of: 3, name: 'Build' },
  phases: [{ name: 'Bash', lines: ['Words and files', 'Its flags'] }, { name: 'Zsh & fish', lines: ['<the same>'] }] }));
show('a try, drawn: what changed, Do this, Look for', tBody({ kind: 'try', title: 'Offline maps', changed: 'Saved maps open.',
  todo: ['Turn on Airplane Mode'], lookFor: 'The map stays sharp.' }));
show('a question unpicked, drawn: Answer saying what it waits for, and a long title whole',
     tBody({ kind: 'answer', title: 'Which of the three onboarding flows should we ship to everyone next week', choices: [
       { id: 'a', label: 'Short' }, { id: 'b', label: 'Long', recommended: true }] }));
const tWrote = session({ writings: [{ id: 'w1', path: '/work/app/notes.md' }] });
show('a link, a page, a page with no address, the changes, a file it wrote, a file it didn\'t, a commit',
     [{ kind: 'link', url: 'https://x.example' }, { kind: 'page', url: 'https://x.example' }, { kind: 'page' },
      { kind: 'diff' }, { kind: 'file', path: '/work/app/notes.md' }, { kind: 'file', path: '/etc/hosts' },
      { kind: 'commit' }].map((a) => taskAttachOpens(a, { s: tWrote })));
show('a task sent again, its words new: what\'s shown is new', [
  taskStepKey({ key: 'task:shop:a', sent: min(9) }), taskStepKey({ key: 'task:shop:a', sent: min(2) })]);

section('The lead\'s pick');
const tLead = session({ sessionId: 'lead', name: 'Atlas' });
const tWren = session({ sessionId: 'wren', name: 'Wren', writings: [{ id: 'w9', path: '/work/app/plans/search.md' }],
                        ask: { id: 'a9', tool: 'Bash', input: { command: 'npm test' } } });
const tPicked0 = { sessionId: 'lead', at: min(30), sent: min(30), pick: true, for: 'wren',
                task: { id: 'j12', kind: 'approve', title: 'Search box', why: 'Wren\'s plan.',
                        attach: [{ kind: 'file', label: 'The plan', path: '/work/app/plans/search.md' }] } };
const tPickLine = taskLine([tSent('shop', 'normal', min(60)), tPicked0, tSent('shop', 'urgent', min(5), { priority: 'urgent' })],
                         [tShop, tLead, tWren]);
show('after anything urgent, before the rest; its member\'s own request not among them', tKeys(tPickLine));
const tPicked = tPickLine.find((i) => i.pick);
show('its head, and where your answer goes', [taskFrom(tPicked), taskSaid(tPicked, 'Approve', '')]);
show('without its member listed', taskFrom(taskLine([tPicked0], [tLead])[0]));
const tNamed = taskLine([tPicked0], [session({ sessionId: 'lead', name: 'lead', team: { role: 'lead', name: 'Atlas' } }),
                                     session({ sessionId: 'wren', name: 'search-box', team: { role: 'member', name: 'Wren' } })],
                        )[0];
show('named by their names in the team, not their sessions\'', [taskFrom(tNamed), taskSaid(tNamed, 'Approve', ''),
                                                                 taskNotice([tNamed], 0).text, taskSayWords(tNamed)]);
show('Take me there and its changes go to its member', taskThere(tPicked).name);
show('the line under the header says it as its head does, urgent when the pick is', [
  taskNotice([tPicked], 0).text, taskUrgentNotice([{ ...tPicked, task: { ...tPicked.task, priority: 'urgent' } }])
    .level]);
const tAllOf = (item) => {
  const to = talkTo(item, [tLead, tWren], false);
  return [taskFrom(item), taskSaid(item, 'Approve', ''), taskThere(item).name, taskNotice([item], 0).text,
          `Talk with ${to.name}`, taskTalkHTML(item, to).includes('ot-to') ? 'member or lead to choose' : 'no choice',
          talkOpening({ ...item, talk: { lead: 'About your task: ', leadForMember: 'About the task Atlas gave me: ' } },
                      to)];
};
show('a lead\'s pick with no member: the lead\'s name alone, everywhere it\'s said',
     tAllOf(taskLine([{ ...tPicked0, for: undefined }], [tLead])[0]));
show('…its member the lead itself: the same, never "Atlas\'s pick, for Atlas"',
     tAllOf(taskLine([{ ...tPicked0, for: 'lead' }], [tLead])[0]));
show('…a different member: "Atlas\'s pick, for Wren" stays', tAllOf(tPicked));
show('two of the lead\'s picks waiting, the one before unanswered: both in line, in the order they came',
     tKeys(taskLine([tPicked0, { ...tPicked0, at: min(10), sent: min(10), task: { ...tPicked0.task, id: 'j13',
                                                                                     title: 'Search results' } }],
                    [tLead, tWren])));
show('a pick reworded while it\'s in front: the foot says who changed it', taskUpdatedWords(tPicked));
show('the lead\'s picks in its queue\'s order, one off the queue after them, all after anything urgent', tKeys(taskLine([
  { ...tPicked0, pickAt: 1, task: { ...tPicked0.task, id: 'b' } },
  { ...tPicked0, at: min(90), task: { ...tPicked0.task, id: 'off' } },
  { ...tPicked0, pickAt: 0, at: min(1), task: { ...tPicked0.task, id: 'a' } },
  tSent('shop', 'urgent', min(2), { priority: 'urgent' })], [tShop, tLead, tWren])));
// A pick the queue names, with how pressing its job is there (`pickPriority`, from the queue): Critical and P0 come
// before everything else, Critical first, each in the queue's order.
const tQueued = (id, pickAt, pickPriority, more = {}) => ({ ...tPicked0, pickAt, pickPriority, at: min(20),
  task: { ...tPicked0.task, id }, ...more });
const tFirst = [tSent('shop', 'old', min(90)), tQueued('p1-pick', 0, 'p1'), tQueued('p0-pick', 1, 'p0'),
                tQueued('crit-pick', 2, 'critical'), tSent('shop', 'urgent', min(2), { priority: 'urgent' })];
show('a Critical or P0 pick comes before everything else: Critical, then P0, then urgent, the P1 pick, the rest',
     tKeys(taskLine(tFirst, [tShop, tLead, tWren])));
show('…and the same when the user chose the oldest first', tKeys(taskLine(tFirst, [tShop, tLead, tWren],
                                                                         { next: 'oldest' })));
show('…each in the queue\'s order', tKeys(taskLine([tQueued('c2', 3, 'critical'), tQueued('c1', 1, 'critical'),
                                                    tQueued('z1', 2, 'p0'), tQueued('z0', 0, 'p0')],
                                                   [tShop, tLead, tWren])));
show('a P1 or P2 pick keeps its old place, after anything urgent', tKeys(taskLine([
  tSent('shop', 'old', min(90)), tQueued('p2-pick', 1, 'p2'), tQueued('p1-pick', 0, 'p1'),
  tSent('shop', 'urgent', min(2), { priority: 'urgent' })], [tShop, tLead, tWren])));
show('a pick the queue no longer names loses it, and goes after those it names', tKeys(taskLine([
  tQueued('named', 0, 'p1'), tQueued('dropped', undefined, 'critical', { pickPriority: undefined }),
  tQueued('also-dropped', undefined, 'critical')], [tShop, tLead, tWren])));
show('…a task put back with Can\'t Now still goes to the back', tKeys(taskLine([
  tSent('shop', 'old', min(90)), tQueued('crit-pick', 0, 'critical', { back: true })], [tShop, tLead, tWren])));
const tAtlas = session({ sessionId: 'lead', name: 'lead', team: { role: 'lead', name: 'Atlas' } });
const tCrit = taskLine([tQueued('crit-pick', 0, 'critical'), tQueued('p0-pick', 1, 'p0')], [tShop, tAtlas, tWren]);
show('the why line: the lead\'s name and the ladder\'s word, or "the chief" when the file gives no name',
     [...tCrit.map((i) => taskWhyHere(i, tCrit, min(0))),
      taskWhyHere(taskLine([tQueued('crit-pick', 0, 'critical')], [tShop, tLead, tWren])[0], [], min(0))]);

section('Something urgent while you\'re on a task');
const tOn = taskLine([tSent('shop', 'search', min(20)), tSent('cli', 'notes', min(15))], tSessions);
const tUrg = (id, at) => tSent('app', id, at, { priority: 'urgent' });
const tWith = (...urgent) => taskLine([tSent('shop', 'search', min(20)), tSent('cli', 'notes', min(15)), ...urgent],
                                      tSessions);
const tSeen = (...steps) => (step) => steps.includes(step);
const tFront = (items, on) => { const r = taskChooseFront(items, { seen: tSeen(), ...on });
  return [r.front?.key ?? null, r.gone ? 'gone' : null]; };
show('not seen yet: something urgent takes the front, as before', tFront(tWith(tUrg('crash', min(1))),
                                                                         { key: tOn[0].key }));
show('seen: it stays, whatever comes', tFront(tWith(tUrg('crash', min(1))),
                                              { key: tOn[0].key, seen: tSeen(tOn[0].key) }));
show('…pointed at or typed in, not seen yet: it stays too', tFront(tWith(tUrg('crash', min(1))),
                                                                     { key: tOn[0].key, held: true }));
show('…a newer task that isn\'t urgent: it stays', tFront(taskLine([...[tSent('shop', 'search', min(20))],
  tSent('cli', 'older', min(90))], tSessions), { key: 'task:shop:search', seen: tSeen(tOn[0].key) }));
const tUrgents = tWith(tUrg('crash', min(1)), tUrg('backup', min(2)));
show('the urgent ones while you\'re on another, and what the strip says: one, and two',
     [taskUrgentOthers(tUrgents, tOn[0].key).map((i) => i.task.id), taskUrgentWords(taskUrgentOthers(tWith(
       tUrg('crash', min(1))), tOn[0].key)), taskUrgentWords(taskUrgentOthers(tUrgents, tOn[0].key))]);
const tAside = { key: tOn[0].key, step: taskStepKey(tOn[0]) };
show('Go: the urgent one a press brought in', tFront(tUrgents, { next: 'task:app:backup', key: tOn[0].key, aside: tAside }));
show('…answered one, set aside: the next urgent one', tFront(tWith(tUrg('crash', min(1))), { key: 'task:app:backup',
                                                                                             aside: tAside }));
show('…answered both: back to the one set aside, as you left it', tFront(tOn, { key: 'task:app:crash',
                                                                                aside: tAside }));
show('…its next step came meanwhile: back to it all the same, keeping your words', tFront(taskLine([
  tSent('shop', 'search', min(20), { step: { n: 2, of: 3 } }), tSent('cli', 'notes', min(15))], tSessions).map((i) =>
  ({ ...i, sent: i.sent + 1 })), { key: 'task:app:crash', aside: tAside }));
show('…taken back meanwhile: not back to it, the line\'s first instead, and said so', tFront(
  [{ ...tOn[0], takenBack: 'answered' }, tOn[1]], { key: 'task:app:crash', aside: tAside }));
show('…gone meanwhile', tFront([tOn[1]], { key: 'task:app:crash', aside: tAside }));
show('what the foot says of it: taken back, parked, gone; and once you\'re back', [
  taskAsideGone('Search box', { ...tOn[0], takenBack: 'answered' }), taskAsideGone('Search box', { ...tOn[0],
  takenBack: 'parked' }), taskAsideGone('Search box', null), taskBackWords('Search box')]);
show('the strip: what\'s urgent with Go, and ‹ Back', [taskStripHTML(taskUrgentOthers(tUrgents, tOn[0].key), null),
                                                      taskStripHTML([], { title: 'Search <box>' })]);
show('Go sets aside a task with no priority, a normal one and a low one, never an urgent one',
     [{}, { priority: 'normal' }, { priority: 'low' }, { priority: 'urgent' }].map((more) =>
       taskSetsAside(taskLine([tSent('shop', 'x', min(3), more)], tSessions)[0])));
const tNormal = taskLine([tSent('shop', 'search', min(20), { priority: 'normal' }), tUrg('crash', min(1))], tSessions);
const tNormalOn = tNormal.find((i) => i.task.id === 'search');
show('…a normal task set aside comes back as you left it, after the urgent one', tFront(
  tNormal.filter((i) => i.task.id === 'search'), { key: 'task:app:crash', aside: { key: tNormalOn.key,
                                                                                    step: taskStepKey(tNormalOn) } }));
const tLow = taskLine([tSent('shop', 'search', min(20), { priority: 'low' })], tSessions)[0];
show('…and a low one', tFront([tLow], { key: 'task:app:crash', aside: { key: tLow.key, step: taskStepKey(tLow) } }));
// Read once, kept read: what you've read is asked of by task, not by step, so a reword (a lead's pick, a session's next
// step) never lets something else take its place.
const tReworded = (...more) => taskLine([tSent('shop', 'search', min(20)), tSent('cli', 'notes', min(30)), ...more],
                                        tSessions).map((i) => (i.task.id === 'search' ? { ...i, sent: i.sent + 1 } : i));
show('read, then reworded, with something urgent sent: it stays, the urgent one asking from the top', tFront(
  tReworded(tUrg('crash', min(1))), { key: 'task:shop:search', seen: tSeen('task:shop:search') }));
show('read, then reworded, with an older task waiting: it stays', tFront(tReworded(),
  { key: 'task:shop:search', seen: tSeen('task:shop:search') }));
const tToApprove = { id: 'p', kind: 'approve', title: 'Search box', why: 'w', todo: ['Open it', 'Type'] };
const tStarted = (chosen, note = '') => ({ first: true, chosen, ticks: { 0: true }, note, open: { a: true },
                                          copied: { b: true } });
show('a comment you\'re typing, the task reworded: your words stay, Comment still picked, its ticks kept',
     taskKeptUi(tStarted(['Comment'], 'Softer, please'), tToApprove, { ...tToApprove, why: 'Reworded.' }));
show('…Approve picked, the plan reworded: Approve goes, as an answer made on the old words',
     taskKeptUi(tStarted(['Approve']), tToApprove, { ...tToApprove, why: 'Reworded.' }));
show('…its steps changed: what you\'d ticked goes', taskKeptUi(tStarted(['Comment'], 'x'), tToApprove,
                                                                { ...tToApprove, todo: ['Open it', 'Type', 'Clear'] }).ticks);
show('…unchanged: all of it stays, as you left it', taskKeptUi(tStarted(['Approve']), tToApprove, { ...tToApprove }));
show('the foot, back to a task changed while you were away, and while you watch',
     [taskUpdatedAwayWords(tOn[0]), taskUpdatedWords(tOn[0])]);
const tReworded2 = { ...tToApprove, why: 'Reworded.' };
show('…Approve let go by the change: the foot says to pick again; only Comment kept: it doesn\'t',
     [taskPickLetGo(tStarted(['Approve']), taskKeptUi(tStarted(['Approve']), tToApprove, tReworded2)),
      taskPickLetGo(tStarted(['Comment'], 'x'), taskKeptUi(tStarted(['Comment'], 'x'), tToApprove, tReworded2)),
      taskUpdatedWords(tOn[0], true), taskUpdatedAwayWords(tOn[0], true)]);
const tReadAt = (id, seenAt, more = {}) => ({ ...tSent('shop', id, min(20)), seenAt, ...more });
const tOpenLine = taskLine([tReadAt('older', 100), tReadAt('newest', 300), tReadAt('put-back', 400, { back: true }),
                           tReadAt('taken', 500, { takenBack: 'answered' }), tSent('cli', 'unread', min(5))], tSessions);
const tOpens = (last, seen = () => true) => taskOpensOn(tOpenLine, last, seen)?.task.id ?? null;
const tLeftOf = { key: 'task:shop:search', sid: 'shop' };
const tNow = (more = {}) => ({ on: true, turnedAway: [], waiting: new Set(['task:shop:search']), touched: false,
                               ...more });
show('the task you were on, gone from the line unanswered: its row missing from a read, back in the line',
     taskLeft(tLeftOf, tOn, tNow()));
show('…back in the line, but you\'d started on the one in front since: forgotten',
     taskLeft(tLeftOf, tOn, tNow({ touched: true })));
show('…its row still missing, the app still keeping it: wait and see', taskLeft(tLeftOf, [tOn[1]], tNow()));
show('…the app no longer keeping it (its session ended): the foot says it no longer waits',
     [taskLeft(tLeftOf, [tOn[1]], tNow({ waiting: new Set() })), taskAsideGone('Search box', null)]);
const tGoneWith = (talk) => {
  const tasksBefore = state.tasks, ot = { left: { ...tLeftOf, title: 'Search box',
    ui: { ...oneTaskUi(), chosen: ['Comment'], note: 'Make it wider ' } } };
  state.tasks = [];
  if (talk) state.talkDrafts[tLeftOf.key] = talk;
  oneTaskLeft(ot, []);
  delete state.talkDrafts[tLeftOf.key];
  state.tasks = tasksBefore;
  return [ot.said, ot.kept];
};
show('…a comment typed, then the task gone: the foot offers its words to copy', tGoneWith());
show('…words in its talk box too: both, Comment\'s first', tGoneWith('Which file? '));
show('…the words it offers, for a task set aside too: Comment\'s and the talk box\'s, either alone, or none',
     [taskKeptWords(' Which file?', { note: 'Wider' }), taskKeptWords('', { note: ' Wider ' }),
      taskKeptWords('Which file?', { note: ' ' }), taskKeptWords(undefined, { note: '' }),
      taskKeptWords('', undefined)]);
show('…One Task turned off, or its session turned away: it still waits, so nothing is said',
     [taskLeft(tLeftOf, [], tNow({ on: false, waiting: new Set() })),
      taskLeft(tLeftOf, [], tNow({ turnedAway: ['shop'], waiting: new Set() }))]);
show('back to a task, as you left it, and after a restart, with nothing of what you\'d done on it kept',
     [taskBackWords('Search box'), taskBackWords('Search box', false)]);
show('which task One Task opens on: the one you were last on, read and still waiting',
     tOpens({ key: 'task:shop:older' }));
show('…the one you were last on, not read: none, the line\'s first then',
     tOpens({ key: 'task:shop:older' }, () => false));
show('…after a restart: the one read most recently, never one at the back nor one taken back', tOpens(null));
show('…after a restart, nothing read: none', taskOpensOn(taskLine([tSent('cli', 'unread', min(5))], tSessions), null,
                                                         () => true));
show('the foot\'s count, with how many are urgent', [taskMoreWords(3, true, 2), taskMoreWords(3, true)]);
show('the urgent line under the header, and the line for the rest', [taskUrgentNotice(tUrgents), taskNotice(tUrgents,
                                                                                                             0)?.text]);
const tTaken = (why) => taskLine([{ ...tPicked0, takenBack: why }], [tLead, tWren])[0];
show('taken back by the lead: what\'s said of it, by why', ['answered', 'parked', 'dropped', 'other'].map((why) =>
  taskTakenBackWords(tTaken(why))));
show('…still on it, Comment picked: no buttons and no box, only what became of it', taskBodyHTML(tTaken('answered'),
  { first: false, chosen: ['Comment'], ticks: {}, note: '', open: {}, copied: {} }, null)
  .match(/<div class="ot-act">[\s\S]*$/)[0]);
show('its file opens from its member\'s writings', [taskAttachOpens(tPicked0.task.attach[0], tPicked),
                                                    taskWriting(tPicked, '/work/app/plans/search.md')?.s.name]);

section('A file from a team\'s lead');
const tPlan = '/work/app/plans/search.md', tFiles = (sid, ...paths) => tSent(sid, 'read', min(9), {
  attach: paths.map((path, i) => ({ kind: 'file', label: `File ${i + 1}`, path })) });
const tTeam = [
  session({ sessionId: 'lead', name: 'storefront', team: { role: 'lead', name: 'Atlas', leads: ['wren'] },
            writings: [{ id: 'l1', path: '/work/storefront/notes.md', at: min(20) }] }),
  session({ sessionId: 'wren', name: 'search-box', team: { role: 'member', name: 'Wren' },
            writings: [{ id: 'w1', path: tPlan, at: min(40) }] }),
  session({ sessionId: 'quill', name: 'search', cwd: '/work/search', team: { role: 'followed', name: 'Quill' },
            writings: [{ id: 's1', path: tPlan, at: min(10) }] }),
  session({ sessionId: 'mine', name: 'side-project',
            writings: [{ id: 'm1', path: '/work/side/notes.md', at: min(5) }] })];
const tFromLead = taskLine([tFiles('lead', '/work/storefront/notes.md', tPlan, '/work/side/notes.md')], tTeam)[0];
show('its own, the one its member and a session it follows both wrote (the latest), and one of yours outside it',
     tFromLead.task.attach.map((a) => [taskAttachOpens(a, tFromLead), taskWriting(tFromLead, a.path)?.s.sessionId]));
show('…drawn: whose it is, and why one doesn\'t open',
     tFromLead.task.attach.map((a, i) => taskAttachHTML(a, i, tFromLead)));
const tFromWren = taskLine([tFiles('wren', '/work/storefront/notes.md')], tTeam)[0];
show('from a member: only its own open, and why not', [taskAttachOpens(tFromWren.task.attach[0], tFromWren),
                                                     taskAttachHTML(tFromWren.task.attach[0], 0, tFromWren)]);
const tClaims = taskLine([tFiles('mine', tPlan)],
                         [{ ...tTeam[3], team: { role: 'followed', name: 'Mine' } }, ...tTeam.slice(1, 3)])[0];
show('from a session the team follows: no team\'s files', taskAttachOpens(tClaims.task.attach[0], tClaims));

section('The session a lead\'s task is about');
const tAbout = (about, kind = 'do', from = 'lead', sessions = tTeam) => taskLine([{ sessionId: from, at: min(5),
  sent: min(5), task: { id: 'go', kind, title: 'Say yes in its tab', why: 'It waits for you there.', about } }],
                                                                             sessions)[0];
const tThere = (item, ui = tUi()) => [item.about && (item.about.s ? `${item.about.s.sessionId}: ${item.about.name}`
  : item.about.why), tWords(item.task, ui, item.about)];
show('a do about a session it follows: Take Me There leads, by its name in the list', tThere(tAbout('quill')));
show('…once pressed, Answer leads', tThere(tAbout('quill'), tUi({ first: true })));
show('an approve about its member: Take Me There beside Answer', tThere(tAbout('wren', 'approve')));
show('about a session no longer listed: why, and no button', tThere(tAbout('3f2a9c1e-gone')));
show('…drawn', taskBodyHTML(tAbout('3f2a9c1e-gone'), { ...tUi(), ticks: {}, open: {}, copied: {} }, null)
  .match(/<div class="ot-buttons">[\s\S]*?<\/div>/)[0]);
show('about one of yours outside the team: why, and no button', tThere(tAbout('mine')));
show('two listed with its name: its folder too',
     tAbout('quill', 'do', 'lead', [...tTeam, session({ sessionId: 'quill-2', name: 'Quill', cwd: '/work/docs' })])
       .about.name);
show('from a sender that isn\'t the lead: not taken', tThere(tAbout('quill', 'do', 'wren')));

section('The line under the header');
const tWaiting = taskLine([tSent('shop', 'Passkeys', min(9)), tSent('cli', 'Nightly', min(12))], tSessions);
show('two tasks, a request beside them: the first task\'s words, how many wait, and what its × folds to',
     taskNotice(tWaiting, taskNewest(tWaiting, 0)));
show('a request alone: no line from One Task (its row says it)', taskNotice(taskLine([], tSessions), 0));
const tQuiz = session({ sessionId: 'coupon', name: 'coupon box', ask: { id: 'q3', tool: 'AskUserQuestion', at: min(2),
  input: { questions: [{ question: 'One?' }, { question: 'Two?' }, { question: 'Three?' }] } } });
show('a session asking three questions and no task: no line, never a "task"', taskNotice(taskLine([], [tQuiz]), 0));
show('…with a task from another session: the line names only that task',
     taskNotice(taskLine([tSent('shop', 'Passkeys', min(9))], [tQuiz, tShop]), 0)?.text);
const tOne = taskNotice(taskLine([tSent('shop', 'Passkey sign-in', min(9), { step: { n: 2, of: 3 } })], [tShop]), 0);
show('a task in front, the only one: its title, and no count after it', [tOne.text, tOne.after ?? null, tOne.chip]);
show('a low one', taskNotice(taskLine([tSent('cli', 'Nightly', min(9), { priority: 'low' })], tSessions), 0).level);
show('nothing waits', taskNotice([], 0));
const tNewer = taskLine([{ ...tSent('shop', 'Later', min(1)), sent: min(1) }, tSent('shop', 'Passkeys', min(9))],
                        tSessions);
show('what\'s new to the line: the newest to come, which a task joining moves on', [taskNewest(tWaiting, 0) === min(9),
                                                                                taskNewest(tNewer, min(4)) === min(1)]);
show('…and one answered or gone never moves it back', taskNewest([], min(1)) === min(1));

section('The talk about a task');
const tTalkSay = (state, more = {}) => ({ at: min(3), words: 'Where is the search box?', state, ...more });
const tTalked = (talk) => taskLine([{ ...tSent('shop', 'Search', min(9)), talk }], [tShop])[0];
const tPickedTalk = (talk, sessions = [tShop, tLead, tWren]) => taskLine([{ ...tPicked0, talk }], sessions, {})[0];
const tTo = (to) => [to.name, to.lead, to.gone, to.s?.sessionId ?? null];
show('to the session that sent it', tTo(talkTo(tTalked(undefined), [tShop], false)));
show('the lead\'s pick: to its member, before the talk begins', tTo(talkTo(tPickedTalk(undefined), [tLead, tWren], false)));
show('…or to the lead, chosen', tTo(talkTo(tPickedTalk(undefined), [tLead, tWren], true)));
show('…its member not listed: the lead', tTo(talkTo(tPickedTalk(undefined, [tLead]), [tLead], false)));
show('once begun, the session it began with, whatever is chosen', tTo(talkTo(tPickedTalk({ to: 'wren' }), [tLead, tWren],
                                                                             true)));
show('…the pick now for another member', tTo(talkTo({ ...tPickedTalk({ to: 'moss' }) },
                                                    [tLead, tWren, session({ sessionId: 'moss', name: 'Moss' })], false)));
show('…its session gone', tTo(talkTo(tTalked({ to: 'gone' }), [tShop], false)));
show('…a task not the lead\'s pick, its talk naming another session: nowhere',
     tTo(talkTo(tTalked({ to: 'lead' }), [tShop, tLead], false)));
const tOpening = talkOpening(tPickedTalk({ lead: 'About your task “Search box”: ',
                                           leadForMember: 'About the task Atlas gave me on your work: ' }),
                             talkTo(tPickedTalk(undefined), [tLead, tWren], false));
show('what opens the words, to the member, and the room left of 600', [tOpening, talkRoom(tOpening)]);
const tIdle = session({ sessionId: 'shop', name: 'storefront', status: 'idle' });
const tBusy = { ...tIdle, status: 'busy', activity: 'Reading search.ts' };
const tAsking = { ...tIdle, ask: { id: 'a2', tool: 'Bash', input: { command: 'npm run build' } } };
const tInFront = { ...tIdle, focused: true };
const tDesktop = { ...tIdle, entrypoint: 'claude-desktop' };
const tState = (said, s, asks, front, waits) => {
  const st = talkState(said, s, 'storefront', asks, front, waits);
  return [st.words, ...st.acts.map((a) => a.act)];
};
show('held: while it works', tState(tTalkSay('held'), tBusy));
show('held: behind its own request, what it asks, with Show It', tState(tTalkSay('held'), tAsking,
                                                                        core.agent.askLine(tAsking.ask)));
show('…its request not worded', tState(tTalkSay('held'), tAsking, ''));
show('held: idle, its tab the one you\'re in', tState(tTalkSay('held'), tInFront));
show('held: idle, in Claude Desktop', tState(tTalkSay('held'), tDesktop));
show('held: idle, its terminal the app in front, on another tab', tState(tTalkSay('held'), tIdle, '', 'Ghostty'));
show('held: idle, about to go in', tState(tTalkSay('held'), tIdle));
show('held: its session not on the task now', tState(tTalkSay('held'), undefined));
show('going in, typed, in Claude Desktop, taken', [tState(tTalkSay('typing'), tIdle), tState(tTalkSay('typed'), tIdle),
                                                   tState(tTalkSay('typed'), tDesktop), tState(tTalkSay('sent'), tIdle)]);
show('not taken, and finished without a reply', [tState(tTalkSay('notTaken'), tIdle),
                                                 tState(tTalkSay('noReply'), tIdle)]);
show('a reason with its own full stop, and without', [talkWhy('It has ended.'), talkWhy('Ghostty is busy'), talkWhy('')]);
show('back in the box: none of it went in, into a terminal, Claude Desktop without Accessibility, and somewhere unnamed',
     [talkBackWords(tTalkSay('refused', { why: 'Its conversation is open in another terminal too', where: 'Ghostty' })),
      talkBackWords(tTalkSay('refused', { why: 'Whozmove needs the Accessibility permission for this',
                                          where: 'Claude Desktop', way: 'Open Accessibility Settings',
                                          permission: true })),
      talkBackWords(tTalkSay('refused', { why: 'It isn’t running: press its row to open it again' }))]);
show('…stopped part-way, with the terminal\'s way past it',
     talkBackWords(tTalkSay('stopped', { why: 'Ghostty asks for your OK', where: 'Ghostty', way: 'Allow' })));
show('where it runs: Claude Desktop, a terminal the app names, and one it doesn\'t',
     [talkWhere(tDesktop, { shop: 'Ghostty' }), talkWhere(tIdle, { shop: 'Ghostty' }), talkWhere(tIdle, {})]);
const tStep = (n, sent) => ({ ...tTalked(undefined), sent, task: { ...tTalked(undefined).task, step: { n, of: 3 } } });
show('a next step coming in as you write: said, and Send names it; the step you began on; a task with no step',
     [talkNewStep(tStep(3, 200), 100), talkNewStep(tStep(2, 100), 100),
      talkNewStep({ ...tTalked(undefined), sent: 200 }, 100), talkNewStep(tStep(3, 200), undefined)]);
show('its live line while it works on your words', [talkLive([tTalkSay('sent')], tBusy, 'storefront'),
  talkLive([tTalkSay('sent')], { ...tBusy, activity: '' }, 'storefront'), talkLive([tTalkSay('held')], tBusy, 'storefront'),
  talkLive([tTalkSay('replied')], tBusy, 'storefront')]);
show('a reply, a long one whole, and one its agent cut at the most it gives',
     [talkReply([{ prose: 'Behind the magnifier.' }]),
      ((r) => [r.parts[0].prose.length, r.cut])(talkReply([{ prose: 'x'.repeat(3000) }])),
      ((r) => [r.parts.length, r.cut])(talkReply([{ prose: 'x'.repeat(9000) }, { cut: true }]))]);
const tCmd = { code: 'npm run build -- --watch', lang: 'bash' };
const tHeredoc = { code: "python3 - <<'EOF'\nimport json\nprint(\"<ok>\")\nEOF", lang: '' };
show('a reply with no code; a fenced command; a heredoc; two blocks; inline code, as the app cuts them', [
  talkReply([{ prose: 'It is behind the magnifier.' }]),
  talkReply([{ prose: 'Paste it into a terminal:' }, tCmd, { prose: 'Then reload.' }]),
  talkReply([{ prose: 'Run:' }, tHeredoc]),
  talkReply([{ prose: 'First:' }, { code: 'make', lang: 'sh' }, { prose: 'then:' }, { code: 'make test', lang: '' }]),
  talkReply([{ prose: 'Use `make test` there.' }])]);
show('…a long reply with code: every part, each block whole, in order',
     ((r) => [r.parts.map((p) => (p.code !== undefined ? `code ${p.code.length} #${p.n}` : `prose ${p.prose.length}`)),
              r.cut])(talkReply([{ prose: 'a'.repeat(400) }, { code: 'c'.repeat(3000), lang: '' },
                                 { prose: 'b'.repeat(300) }, { code: 'after', lang: '' }])));
show('…as VoiceOver says it', talkReplyWords(talkReply([{ prose: 'Paste it:' }, tCmd, { prose: 'Then reload.' }])));
const tCoded = tTalked({ to: 'shop', says: [tTalkSay('replied', { repliedAt: min(1), reply: [
  { prose: 'Paste it into a terminal:' }, tHeredoc, { prose: 'Use `make` after.' }] })] });
show('a reply with a heredoc, drawn: one line with Copy, the prose as prose, everything escaped',
     taskTalkHTML(tCoded, talkTo(tCoded, [tShop], false)));
show('…pressed, shown whole', taskTalkHTML(tCoded, talkTo(tCoded, [tShop], false),
                                          { [taskCodeKey(tCoded, min(3), 1)]: true }));
show('…its Copy just pressed: "Copied" on the button itself', taskCodeHTML({ ...tCmd, n: 1 }, min(3), false, true));
show('a command shown whole wraps only between words: "--env=staging" stays one, a word past a line may break',
     taskCodeWords(`npm run deploy -- --env=staging --region=eu-west-1 <x> ${'k'.repeat(60)}`));
const tReplied = tTalked({ to: 'shop', says: [tTalkSay('replied', { repliedAt: min(1),
  reply: [{ prose: 'It’s **behind** the <b>magnifier</b>.' }] })] });
show('the line under the header: a reply not seen yet', talkNotice([tReplied], [tShop], {}) && [
  talkNotice([tReplied], [tShop], {}).text, talkNotice([tReplied], [tShop], {}).level]);
show('…once seen in One Task', talkNotice([tReplied], [tShop], { [tReplied.key]: min(1) }));
show('the talk drawn: your words, its reply in Markdown, everything escaped',
     taskTalkHTML(tReplied, talkTo(tReplied, [tShop], false)));
show('…before anything is said, the lead\'s pick to choose for',
     taskTalkHTML(tPickedTalk(undefined), talkTo(tPickedTalk(undefined), [tLead, tWren], false)));
show('…held, with Take Back', taskTalkHTML(tTalked({ to: 'shop', says: [tTalkSay('held')] }),
                                         { s: tBusy, name: 'storefront', lead: false, gone: false }));
show('…held for the tab you\'re in, Send Now beside Take Back; words back in the box not drawn; in Ghostty',
     taskTalkHTML(tTalked({ to: 'shop', terminals: { shop: 'Ghostty' },
                            says: [tTalkSay('held'), tTalkSay('refused', { at: min(2), why: 'x' })] }),
                  { s: tInFront, name: 'storefront', lead: false, gone: false }));
show('…a reply its agent cut, and one from before Whozmove restarted',
     taskTalkHTML(tTalked({ to: 'shop', says: [tTalkSay('replied', { reply: [{ prose: 'y…' }, { cut: true }] }),
                                               tTalkSay('replied', { at: min(2) })] }),
                  { s: tIdle, name: 'storefront', lead: false, gone: false }));

section('How One Task works, as its page under Tools sets it');
const tRules = [tSent('shop', 'normal-old', min(90)), { ...tPicked0, at: min(5), sent: min(5) },
                tSent('shop', 'urgent', min(2), { priority: 'urgent' })];
show('what comes first: a lead\'s picks after anything urgent, or simply the oldest',
     [tKeys(taskLine(tRules, [tShop, tLead, tWren])), tKeys(taskLine(tRules, [tShop, tLead, tWren], { next: 'oldest' }))]);
const tWhyLine = taskLine([...tRules, tSent('shop', 'normal-new', min(1))], [tShop, tLead, tWren]);
show('say why each is here, for each in line', tWhyLine.map((i) => `${i.task.id}: ${taskWhyHere(i, tWhyLine,
                                                                                                  min(0))}`));
show('…drawn: over the task, and what\'s after it', [taskWhyHTML(tWhyLine[0], tWhyLine, min(0)),
                                                     taskAfterHTML(tWhyLine[0], tWhyLine, min(0))]);
show('urgent tasks not waiting for your Go: one you\'ve seen gives way, as before; pointed at, it stays', [
  tFront(tWith(tUrg('crash', min(1))), { key: tOn[0].key, seen: () => false }),
  tFront(tWith(tUrg('crash', min(1))), { key: tOn[0].key, held: true, seen: () => false })]);
show('held words waiting for your Send Now: idle, and while it works', [
  tState(tTalkSay('held'), tIdle, '', '', true), tState(tTalkSay('held'), tBusy, '', '', true)]);
show('sessions turned away: one, two, and one not listed', [taskTurnedAwayWords(['shop'], tSessions),
  taskTurnedAwayWords(['shop', 'cli'], tSessions), taskTurnedAwayWords(['gone'], tSessions)]);
show('a pick, its looks by letter: each letter in its own column before its label, ticks as two may be mixed',
     tBody({ kind: 'pick', title: 'Pick a look', choices: [{ id: 'A', label: 'Table', recommended: true },
                                                           { id: 'B', label: 'Cards' }] }).match(/<div class="options[\s\S]*?<\/div>/)[0]);
show('…a question with words for its choices: round buttons, no letters', tBody({ kind: 'answer', title: 'Both?',
  choices: [{ id: 'yes', label: 'Yes, both', recommended: true }, { id: 'no', label: 'Not like that' }] })
  .match(/<div class="options[\s\S]*?<\/div>/)[0]);

section('Where it\'s for, in the head');
const tHead = (s, more = {}) => taskHeadHTML({ key: 'k', sid: s.sessionId, s, at: min(18),
                                               task: { id: 'x', kind: 'try' }, ...more }, NOW)
  .match(/<span class="r-sub">[\s\S]*?<\/span>(?=<button)/)[0];
const tAt = (sessionId, name, git, more) => session({ sessionId, name, git, ...more });
show('a checkout, by its branch', tHead(tShop));
show('a worktree, on its chip', tHead(tAt('wt', 'search', { branch: 'search-box', root: '/w/s', worktree: true })));
show('a detached checkout', tHead(tAt('dt', 'bisect', { detached: 'a1b2c3d', root: '/work/app' })));
show('a folder outside git, by its name', tHead(tAt('fo', 'notes', null, { cwd: '/work/notes' })));
show('a lead\'s pick: where the member it\'s for works', tHead(tLead, tPicked));

section('On the session\'s row');
// Each session's first task in One Task's order, and how many more of its own wait: never a lead's pick, one put back
// with Can't Now, or one taken back.
const tAsksOf = (sent, sessions) => [...taskAsks(taskLine(sent, sessions)).entries()]
  .map(([sid, ask]) => `${sid}: ${ask.item.task.id}${ask.more ? ` +${ask.more}` : ''}`);
show('each session\'s first, in the line\'s order, and how many more', tAsksOf([
  tSent('shop', 'old', min(30)), tSent('shop', 'new', min(5)), tSent('shop', 'newer', min(4)), tSent('cli', 'one', min(9)),
], tSessions));
show('a lead\'s pick: not on a row', tAsksOf([tPicked0], [tLead, tWren]));
show('put back with Can\'t Now, or taken back: not on a row', tAsksOf([
  tSent('shop', 'back', min(9), { back: true }), { ...tSent('cli', 'gone', min(8)), takenBack: 'answered' }],
  tSessions));
show('none waiting: no rows', tAsksOf([], tSessions));
// Drawn on the row, without a team: the row's note, on a line of its own, the press on its words only.
const tLastBefore = state.last;
const tRowOf = (s, kind = 'seen') => rowHTML(s, kind, NOW);
const tNote = (html) => html.match(/<div class="step-note[\s\S]*?<\/div>/)?.[0].replace(/<svg[\s\S]*?<\/svg>/, '[mark]')
  ?? 'no line';
setTasks([tSent('shop', 'passkeys', min(3), { title: 'Passkey sign-in' }), tSent('shop', 'more', min(2)),
          tSent('cli', 'help', min(4), { kind: 'approve', title: 'A <b>plan</b>' })], true, taskKindWords);
state.last = { sessions: tSessions, now: NOW };
for (const draw of core.beforeDraw) draw(state.last.sessions);
show('a full row with no team: its task, "+1", on a line of its own', tNote(tRowOf(tShop)));
show('…a title that is markup is shown as text', tNote(tRowOf(tCli)));
show('…a session with none: no line', tNote(tRowOf(tApp, 'needs')));
core.slots.workStart.push((row) => (row.s.sessionId === 'shop' ? '[PR #12]' : ''));
const tWorked = tRowOf(tShop);
show('a row with a work line: the work line stays, the task\'s line under it',
     /<div class="work">\[PR #12\]<\/div>/.test(tWorked) && tNote(tWorked) !== 'no line');
core.slots.workStart.pop();
// One ask, one action: while its task waits, the row offers nothing else (no Deploy on its bottom line); a try's action
// is Deploy (another module's, askAct) when there's a build to put in place, else the session it's about.
core.slots.placeEnd.push(() => '[Deploy]');
show('a full row, while its task waits: no Deploy on the row', !tRowOf(tShop).includes('[Deploy]'));
const tTryDeploy = (row) => (row.askWant === 'try' ? '[Try Deploy]' : '');
core.slots.askAct.push(tTryDeploy);
show('…a try with a build to put in place: Deploy at its end, alone', tNote(tRowOf(tShop)).match(/\[[\w ]+\]|data-ot-act/g));
core.slots.askAct.pop();
core.slots.placeEnd.pop();
show('…with none: its action, to the session (Take Me There)', tNote(tRowOf(tShop)).match(/title="Take Me There[^"]*"/g));
// Each kind's one action (taskRowAct): what a press does, its icon and its tip; none answers the task.
const tActOf = (more) => {
  const how = taskRowAct(taskLine([tSent('shop', 'a', min(1), more)], tSessions)[0]);
  return `${how.act} ${how.icon}${how.want ? ` (${how.want})` : ''}: ${how.tip}`;
};
const tLooksPage = { attach: [{ kind: 'page', url: 'https://example.com/looks' }] };
show('each kind\'s action', [
  tActOf({ kind: 'try' }), tActOf({ kind: 'approve' }), tActOf({ kind: 'approve', inTab: true }),
  tActOf({ kind: 'pick', ...tLooksPage }), tActOf({ kind: 'pick' }), tActOf({ kind: 'answer' }),
  tActOf({ kind: 'run', command: 'gh auth login' }), tActOf({ kind: 'do' }), tActOf({ kind: 'seen', ...tLooksPage }),
  tActOf({ kind: 'seen' })]);
show('…a try about another session: to it, never the row\'s own Deploy', (({ act, want, to }) => [act, want ?? null,
  to?.sessionId])(taskRowAct(tAbout('wren', 'try'))));
// Pressed: Copy copies through the app, and shows a tick a moment; a page opens through the app; the rest open One
// Task at it, or the session. Never before the line has been seen.
{
  const sentBefore = window.webkit, sentNow = [], readerBefore = openReader, renderBefore = render;
  render = () => {};
  window.webkit = { messageHandlers: { panel: { postMessage: (m) => sentNow.push(`${m.type} ${m.id}`
    + (m.sent ? ` sent ${Math.round((NOW - m.sent) / 60000)}m ago` : '')) } } };
  openReader = (a, b, mode, key) => sentNow.push(`reader ${key}`);
  // A press on the action as the row draws it now (its data-ot-act), for the task sent `sent` ago.
  const pressNow = () => {
    sentNow.length = 0;
    const otAct = tRowOf(tShop).match(/data-ot-act="([^"]*)"/)[1].replace(/&#39;/g, "'");
    core.presses.find(([sel]) => sel === '[data-ot-act]')[1]({ dataset: { otAct },
      closest: () => ({ dataset: { id: 'shop' } }) }, { preventDefault() {} });
  };
  const send = (more, sent = min(1)) => {
    setTasks([{ ...tSent('shop', 'a', min(1), more), sent }], true, taskKindWords);
    for (const draw of core.beforeDraw) draw(state.last.sessions);
  };
  const press = (more) => {
    send(more);
    state.shownAt['ot-row:shop'] = 1;
    pressNow();
  };
  press({ kind: 'run', command: 'gh auth login' });
  show('…Copy pressed: the app copies it, and its button shows the tick', [sentNow.splice(0),
    /title="Copied"/.test(tNote(tRowOf(tShop)))]);
  press({ kind: 'pick', ...tLooksPage });
  show('…a prototype\'s: the app opens its page', sentNow.splice(0));
  press({ kind: 'answer' });
  show('…a question\'s: One Task at it', sentNow.splice(0));
  send({ kind: 'answer' }, min(1));
  state.shownAt['ot-row:shop'] = 1;
  send({ kind: 'run', command: 'gh auth login' }, min(0));
  pressNow();
  show('…the same task sent again as a command to run, pressed at once: nothing copied yet', sentNow.splice(0));
  state.shownAt['ot-row:shop'] = 1;
  pressNow();
  show('…once seen: that step copied, as sent', sentNow.splice(0));
  const tSeenStep = tRowOf(tShop).match(/data-ot-act="([^"]*)"/)[1];
  send({ kind: 'answer' }, min(0) + 1);
  state.shownAt['ot-row:shop'] = 1;
  core.presses.find(([sel]) => sel === '[data-ot-act]')[1]({ dataset: { otAct: tSeenStep },
    closest: () => ({ dataset: { id: 'shop' } }) }, { preventDefault() {} });
  show('…a press on a step no longer said: nothing', sentNow.splice(0));
  delete state.taskCopied.shop;
  window.webkit = sentBefore; openReader = readerBefore; render = renderBefore;
  setTasks([tSent('shop', 'passkeys', min(3), { title: 'Passkey sign-in' }), tSent('shop', 'more', min(2)),
            tSent('cli', 'help', min(4), { kind: 'approve', title: 'A <b>plan</b>' })], true, taskKindWords);
  for (const draw of core.beforeDraw) draw(state.last.sessions);
}
show('just come, it takes no press yet', justShown('ot-row:shop'));
state.shownAt['ot-row:shop'] = 1;
for (const draw of core.beforeDraw) draw(state.last.sessions);
show('…the same task drawn again: still seen', !justShown('ot-row:shop'));
setTasks([tSent('shop', 'more', min(2))], true, taskKindWords);
for (const draw of core.beforeDraw) draw(state.last.sessions);
show('…now saying another task: taking no press again', justShown('ot-row:shop'));
// Drawn again after giving way to another note, in that note's place: it waits to be seen again (a stand-in list, as
// the cases have no page to draw into).
const tListWith = (...sids) => ({ querySelectorAll: () => sids.map((sid) => ({ closest: () => ({ dataset: { id: sid } }) })) });
oneTaskLinesBack(tListWith('shop'));
state.shownAt['ot-row:shop'] = 1;
oneTaskLinesBack(tListWith('shop'));
show('…drawn again in place: still seen', !justShown('ot-row:shop'));
oneTaskLinesBack(tListWith());
oneTaskLinesBack(tListWith('shop'));
show('…back after giving way to another note: taking no press again', justShown('ot-row:shop'));
// One Task's line gives way to a note that puts something right, and comes back once it's gone.
core.rowNotes.push((row) => (row.s.sessionId === 'shop' ? { html: 'Compacting stopped part-way' } : null));
show('a warning on the row: that, in its place', tNote(tRowOf(tShop)));
core.rowNotes.pop();
show('…once it\'s gone: the task\'s line again', tNote(tRowOf(tShop)));
// Pressed, One Task opens at that task: named as the reader's scope, it's set once any other mode's reset has gone (the
// reader on Changes, say), and the task you were last on and had read isn't put back in front of it.
const tR = { scope: null };
globalThis.queueMicrotask ??= (run) => run();  // macOS's jsc has none
state.tasksWant = null;
core.readerModes.oneTask.reset(tR);
tR.scope = 'task:shop:more';
core.readerModes.oneTask.shown(tR);
show('opened at a task from another mode: that task wanted', state.tasksWant);
setTasks([tSent('shop', 'more', min(2)), tSent('cli', 'read', min(9))], true, taskKindWords);
const tOpenItems = oneTaskItems(), tRead = tOpenItems.find((i) => i.key === 'task:cli:read');
// The task read last, as chief keeps it across a restart too (tasksLastOn and what was seen).
state.tasksLastOn = { key: tRead.key, step: taskStepKey(tRead), ui: {}, title: 'read' };
state.tasksSeen[tRead.key] = true;
show('…with another task read before: none put back in front of it', oneTaskOpening(tOpenItems).next ?? 'none');
state.tasksWant = null;
show('…opened with none named: back on the one read before', oneTaskOpening(tOpenItems).next);
state.tasksWant = 'task:gone:x';
show('…named, but no longer waiting: back on the one read before', oneTaskOpening(tOpenItems).next);
// After Whozmove restarts, the task read last comes from the app's seenAt alone, with no tasksLastOn.
state.tasksLastOn = null;
setTasks([tSent('shop', 'more', min(2)), { ...tSent('cli', 'read', min(9)), seenAt: 900 }], true, taskKindWords);
state.tasksWant = 'task:shop:more';
show('…after a restart, another task read last: none put back in front of it', oneTaskOpening(oneTaskItems()).next
     ?? 'none');
state.tasksWant = null;
show('…after a restart, opened with none named: the one read last', oneTaskOpening(oneTaskItems()).next);
state.tasksWant = null;
state.tasksLastOn = null;
setTasks([], true, taskKindWords);
state.last = tLastBefore;
for (const draw of core.beforeDraw) draw(state.last?.sessions || []);
