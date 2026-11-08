// The reader module's part of the page, run outside the app by test.sh: what the line above a prototype says, and what
// shows in its space, as the app says how it stands (writings.js). Nothing is drawn.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

load('tests/page-harness.js');  // the stand-ins, the page's scripts and the helpers below use

section('A prototype (writings.js)');
const page = { id: 'w1', kind: 'prototype', title: 'Landing page', path: '/work/app/landing.html', at: min(5) };
show('opening: the line, before the app has said anything', prototypeLine(page, null));
show('opening: its space, naming the file', prototypeUnder(null, page));
show('loading', prototypeLine(page, { loading: true, keyboard: false }));
show('loaded: click into it', prototypeLine(page, { loading: false, keyboard: false }));
show('loaded: its space, under it', prototypeUnder({ loading: false, keyboard: false }));
show('clicked into: it has the keyboard', prototypeNote({ loading: false, keyboard: true }));
for (const asked of ['window', 'alert', 'files', 'download', 'camera', 'otherApp', 'link', 'something new'])
  show(`it asked: ${asked}`, prototypeNote({ loading: false, keyboard: false, asked }));
show('it asked, while it has the keyboard', prototypeNote({ loading: false, keyboard: true, asked: 'window' }));
const gone = { loading: false, keyboard: false, problem: 'This file isn\'t there any more.' };
show('a problem: no note on the line', prototypeNote(gone));
show('a problem: in its space', prototypeUnder(gone));
show('published too', prototypeLine({ ...page, url: 'https://claude.ai/public/artifacts/example' },
                                    { loading: false, keyboard: false }));
show('a name that is markup is shown as text', prototypeLine({ ...page, path: '/work/<b>x</b>.html' }, null));

section('While a writing is read (writings.js)');
show('a plan: from the transcript', writingWaitWords({ kind: 'plan', path: '/home/.claude/plans/tidy.md' }));
show('notes: from their file', writingWaitWords({ kind: 'notes', path: '/work/app/NOTES.md' }));

section('A plan, at a glance where the plans module reads one (writings.js)');
const rdPlan = '# Shopping list\n\n## At a glance\n\n- **What changes for you:** one list, by aisle.\n- **You decide:**\n'
  + '  1. Where it lives: on your account (recommended), or this browser. Why: phones.\n'
  + '  2. Units: side by side (recommended); or grams. Why: cups aren\'t grams.\n\n## Context\n\nToday by hand.\n';
const rdAsk = (more = {}) => ({ id: 'q1', tool: 'ExitPlanMode', input: { plan: rdPlan }, at: min(2), ...more });
const rdSession = (more = {}) => ({ sessionId: 's1', name: 'Wren', cwd: '/work/pantry', ask: rdAsk(more) });
const rdWaiting = { id: 'ask:q1', kind: 'plan', title: 'Shopping list', at: min(2), status: 'waiting', fromAsk: rdPlan };
const rdOlder = { id: 'w0', kind: 'plan', title: 'Shopping list', at: min(90), status: 'declined' };
const rdReading = (more = {}) => ({ sent: {}, revising: false, notes: '', ...more });
state.planOpen.s1 = { 'q1\nchoice 0': true, 'w0\nchoice 0': true };  // its first choice open, to see its options
// What a body is: the card's view (whose picks, whether they can be made or are held), or the plain plan.
const rdBody = (html) => (html.startsWith('<div class="gl-view"')
  ? ['card', html.match(/data-plan="([^"]*)"/)[1], (html.match(/data-option="\d">/g) || []).length,
     (html.match(/data-option="\d" disabled>/g) || []).length]
  : html.slice(0, 40));
show('waiting: on its card, its picks by the request, options pressable [kind, id, pressable, not]',
     rdBody(writingBodyHTML(rdWaiting, rdSession(), { text: rdPlan }, rdReading())));
show('waiting, its notes open: the picks held',
     rdBody(writingBodyHTML(rdWaiting, rdSession(), { text: rdPlan }, rdReading({ revising: true }))));
show('waiting, sent back from here: Claude\'s picks only',
     rdBody(writingBodyHTML(rdWaiting, rdSession(), { text: rdPlan }, rdReading({ sent: { 'ask:q1': 'revise' } }))));
show('waiting in an older session the panel can\'t answer: Claude\'s picks only',
     rdBody(writingBodyHTML(rdWaiting, rdSession({ legacy: true }), { text: rdPlan }, rdReading())));
show('an older version: by its own id, Claude\'s picks only',
     rdBody(writingBodyHTML(rdOlder, rdSession(), { text: rdPlan }, rdReading())));
show('no glance and no sections: the plain plan', rdBody(writingBodyHTML(rdOlder, rdSession(),
     { text: 'Just move the coupon field.' }, rdReading())));
show('not a plan: its Markdown', rdBody(writingBodyHTML({ id: 'n1', kind: 'notes', at: min(3) }, rdSession(),
     { text: rdPlan }, rdReading())));
show('missing', writingBodyHTML(rdOlder, rdSession(), { missing: 'This file isn\'t there any more.' }, rdReading()));
const rdPlans = core.plans;
core.plans = null;
show('without the plans module: the plain plan',
     rdBody(writingBodyHTML(rdWaiting, rdSession(), { text: rdPlan }, rdReading())));

section('The bar under a waiting plan, with your picks (writings.js)');
core.plans = rdPlans;
state.reading = rdReading();
writingBodyHTML(rdWaiting, rdSession(), { text: rdPlan }, state.reading);
show('Claude\'s picks kept: as ever', answerHTML(rdWaiting, rdSession()).includes('r-revise'));
state.planPicks.q1 = { 0: 1 };
show('one changed', answerHTML(rdWaiting, rdSession()));
state.planPicks.q1 = { 0: 1, 1: 1 };
show('two changed', answerHTML(rdWaiting, rdSession()).match(/You changed[^.]*\./)[0]);
state.reading = rdReading({ revising: true });
show('Send Back with My Picks: the box, under your picks in words', answerHTML(rdWaiting, rdSession()));
state.reading.notes = '  Also rename the button.  ';
show('…what goes back: your picks\' words, then your own', planNotesMessage(state.reading, rdSession()));
state.reading = rdReading({ sessionId: 's1' });
state.planUnsent.s1 = 'Split step 2.';
show('answered elsewhere as Send to Claude was pressed: it says so, with your notes to copy and Take me there',
     answerHTML(rdWaiting, rdSession()));
delete state.planUnsent.s1;
state.reading = rdReading({ revising: true, notes: 'Split step 2.' });
core.plans.clearPicks('q1');
show('Use Claude\'s Picks, the box open: only your own words go back', planNotesMessage(state.reading, rdSession()));
state.reading = rdReading();
show('Use Claude\'s Picks: as ever again', answerHTML(rdWaiting, rdSession()).includes('r-revise'));
show('nothing written and no picks: nothing to send', planNotesMessage(rdReading({ notes: '  ' }), rdSession()));

section('What you typed on the row goes with your picks (core.planNotes, core.planRowNotes)');
{
  const kept = { openReader, openPlanNotes }, opened = [];
  let opensOn = rdSession();
  openReader = (sid) => {
    state.reading = rdReading({ mode: 'writings', sessionId: sid, id: 'ask:q1', session: opensOn });
  };
  openPlanNotes = () => opened.push('box open');
  core.planNotes('s1');
  show('the row\'s Send back…: the plan, its box open', opened.splice(0));
  opensOn = rdSession({ legacy: true });
  core.planNotes('s1');
  show('a session the panel can\'t answer: no box, only the plan', opened.splice(0));
  Object.assign(globalThis, kept);
}
state.reading = rdReading();
state.sendBack.q1 = { text: '  Keep it short.  ' };
planRowWords(state.reading, rdSession());
show('the bar\'s Send Back with My Picks: the box takes what you typed on the row, which leaves it',
     [state.reading.notes, state.sendBack.q1 ?? null]);
state.reading.notes = 'Split step 2.';
state.sendBack.q1 = { text: 'Keep it short.' };
planRowWords(state.reading, rdSession());
show('…under what you wrote there before', state.reading.notes);
state.planPicks.q1 = { 0: 1 };
show('…and it goes back with your picks', planNotesMessage(state.reading, rdSession()));
planRowWords(state.reading, rdSession());
show('…opened again, nothing new on the row: the box as you left it', state.reading.notes);
const rdBack = (more) => {
  const r = { ...state.reading, notesFor: 'q1', session: rdSession(), ...more };
  planNotesBack(r);
  return r;
};
const rdLeft = rdBack().notes;
show('the reader closed unsent: your words wait on the row again, lines and all, and leave the reader',
     [state.sendBack.q1, rdLeft]);
state.sendBack.q1 = { text: 'Rename the button.' };
rdBack();
show('…after what the row had typed in it since', state.sendBack.q1);
show('…the row\'s box, a line, shows the lines as spaces', /<input [^>]*value="([^"]*)"/.exec(
  (core.plans.clearPicks('q1'), askHTML(rdAsk(), NOW, '/work')))?.[1]);
state.planPicks.q1 = { 0: 1 };
delete state.sendBack.q1;
const rdOther = rdBack({ notesFor: 'q0' });
show('notes for a plan answered elsewhere: never onto the plan that asks next, and gone from the reader',
     [state.sendBack.q1 ?? null, rdOther.notes]);
rdBack({ session: rdSession({ legacy: true }) });
show('…nor onto a session the panel can\'t answer', state.sendBack.q1 ?? null);
core.plans.clearPicks('q1');
delete state.sendBack.q1;
state.reading = null;

section('Notes written for a version Claude no longer waits on: never sent to another, never dropped');
{
  const kept = { readerSession, putHTML, drawReader, wantKeyboard, drawView, fitReader }, sentNow = () => JSON.stringify(state.answering);
  const rdNext = rdSession({ id: 'q2' }), rdNextPlan = { ...rdWaiting, id: 'ask:q2' };
  Object.assign(globalThis, { readerSession: () => rdNext, putHTML() {}, drawReader() {}, wantKeyboard() {} });
  state.answering = {};
  state.planPicks.q1 = { 0: 1 };
  // (a) Claude's next version came under the plan the reader shows, the box still open with notes for the first.
  state.reading = rdReading({ sessionId: 's1', id: 'ask:q2', revising: true, notes: 'Keep it short.', notesFor: 'q1' });
  show('(a) a new version since: they\'re for the one before', planNotesStale(state.reading, rdNext));
  sendPlanAnswer('revise');
  show('…Send to Claude sends nothing to the new version, and the box closes',
       [sentNow(), state.reading.revising, state.reading.notes]);
  show('…the bar says so, with your picks\' words and your notes, to copy', answerHTML(rdNextPlan, rdNext));
  state.reading.revising = true;
  show('…and above the box, if you open it for the new version',
       answerHTML(rdNextPlan, rdNext).match(/<p class="r-picked r-unsent">[^<]*<\/p>/g)?.length);
  state.reading.revising = false;
  show('…with the new version\'s own Send back… and Stop beside Take me there and Done with These',
       answerHTML(rdNextPlan, rdNext).match(/class="button[^"]*">[^<]*/g));
  show('…but not on a version Claude isn\'t waiting on', answerHTML({ ...rdWaiting, status: 'declined' }, rdNext)
    .match(/class="button[^"]*">[^<]*/g));
  const rdFind = reader.querySelector;
  reader.querySelector = () => ({ querySelector: () => null, contains: () => false });
  Object.assign(globalThis, { drawView() {}, fitReader() {} });
  core.readerPresses.find(([sel]) => sel === '.r-revise')[1]();
  show('…its Send back… opens the box for the new version, your notes for the one before still above it, kept',
       [state.reading.revising, state.reading.notesFor, answerHTML(rdNextPlan, rdNext)
         .match(/<div class="r-q">Your notes for the version before[^<]*<\/div>\s*<p class="r-picked r-unsent">/)
         ?.length, !!state.planUnsent.s1]);
  reader.querySelector = rdFind;
  delete state.planUnsent.s1;
  // (b) The first version was answered in the session, the box open on it, its notes not sent yet.
  state.reading = rdReading({ sessionId: 's1', id: 'ask:q1', revising: true, notes: 'Split step 2.', notesFor: 'q1' });
  planNotesUnsent(state.reading);  // what drawing the reader does at once, as the request it was for has gone
  show('(b) answered elsewhere, the box open: the bar says so, the notes to copy',
       answerHTML({ ...rdWaiting, status: 'declined' }, rdNext)
         .match(/<div class="r-q">[^<]*<\/div>|r-unsent">[^<]*/g));
  delete state.planUnsent.s1;
  state.reading = rdReading({ sessionId: 's1', notes: 'Split step 2.', notesFor: 'q1', session: rdNext });
  planNotesBack(state.reading);
  show('…closed after Cancel instead: kept to copy, not dropped, and not on the new version\'s row',
       [state.planUnsent.s1, state.sendBack.q2 ?? null]);
  show('…until Done with These', (core.readerPresses.find(([sel]) => sel === '.r-unsent-done')[1](),
                                   state.planUnsent.s1 ?? null));
  Object.assign(globalThis, kept);
  core.plans.clearPicks('q1');
  state.reading = null;
}

