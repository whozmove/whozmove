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

section('Approve under the plan Claude waits on (planApproveHow, answerHTML)');
{
  // A plan Claude waits on with the app's digest, and the reader once its text is drawn for that request and digest.
  const asks = (more = {}) => rdSession({ digest: 'd1', ...more });
  const drawn = (more = {}) => rdReading({ ready: true, drawnPlan: { id: 'q1', digest: 'd1' }, ...more });
  const how = (s, r, going) => planApproveHow(rdWaiting, s, r, going);
  show('drawn whole, nothing in its way: Approve, for the request and digest drawn', how(asks(), drawn()));
  show('its text not drawn yet: not yet', how(asks(), rdReading()));
  show('drawn for another text of the request: not yet', how(asks({ digest: 'd2' }), drawn()));
  show('no digest from the app: not yet',
       how(asks({ digest: undefined }), drawn({ drawnPlan: { id: 'q1', digest: '' } })));
  show('cut short: why, and no Approve', how(asks({ truncated: true }), drawn()));
  show('what the app knows already: in its words, as a sentence', how(asks({
    approveWhyNot: 'it may run with permissions bypassed once approved, so approve it in its tab' }), drawn()));
  show('a session the panel can\'t answer: none (its own bar says so)', how(asks({ legacy: true }), drawn()));
  show('sent back from here: none', how(asks(), drawn({ sent: { 'ask:q1': 'revise' } })));
  show('not the plan Claude waits on: none', planApproveHow(rdOlder, asks(), drawn()));
  show('your Approve, with the app', how(asks(), drawn(), { id: 'q1', after: 0 }));
  show('…not approved, as its ask says: why, and no Approve',
       how(asks({ approval: { why: 'its plan was written again', at: 5 } }), drawn()));
  show('…of an earlier request: not this one\'s', how(asks(), drawn(), { id: 'q0', after: 0 }));
  show('…not, where a second press may yet approve it: Approve, with why',
       how(asks({ approval: { why: 'press Approve again', again: true, at: 5 } }), drawn()));
  state.reading = drawn();
  show('the bar: Approve, carrying the request and digest drawn, then Send back…, Stop and Take me there',
       answerHTML(rdWaiting, asks()));
  show('…Return never presses it: it isn\'t a card\'s main answer (.perm-allow), and the reader takes only a mousedown',
       answerHTML(rdWaiting, asks()).includes('perm-allow'));
  // Drawn at a glance beside the list, read folded (Skimmed): Approve says it's for the whole plan; read in full, not.
  const lookBefore = state.planReadAs, drawnBefore = { ...state.planDrawn.s1 };
  core.plans.readerHTML('# Sync\n\n## At a glance\n\n- **What changes for you:** faster sync.\n\n## Steps\n\nOne.',
                        { sessionId: 's1', id: 'q1', waiting: true });
  state.planReadAs = 'skimmed';
  const wholeLine = () => /<div class="r-whole">([^<]*)<\/div>/.exec(answerHTML(rdWaiting, asks()))?.[1] ?? null;
  const skimmedLine = wholeLine();
  state.planReadAs = 'full';
  show('…read folded at a glance, then in full: [the line above Approve, none]', [skimmedLine, wholeLine()]);
  state.planReadAs = lookBefore;
  state.planDrawn.s1 = drawnBefore;
  state.planApproving.s1 = { id: 'q1', after: 0 };
  show('…pressed: Approving…', answerHTML(rdWaiting, asks()));
  delete state.planApproving.s1;
  show('…not approved: why, with Take me there', answerHTML(rdWaiting, asks({
    approval: { why: 'its plan file has changed since Claude asked', at: 5 } })));
  show('…not approved, where a second press may yet: why, with Approve still', answerHTML(rdWaiting, asks({
    approval: { why: 'press Approve again', again: true, at: 5 } })));
  state.reading = drawn({ sent: { 'ask:q1': 'approve' }, approved: { 'ask:q1': 'q1' } });
  const yours = (state) => ({ ...rdSession(), ask: undefined,
                              answeredFor: { what: 'approved', yours: true, askId: 'q1', state } });
  show('…approved, until Claude takes it', answerHTML(rdWaiting, yours('pending')));
  show('…taken', answerHTML(rdWaiting, yours('approved')));
  show('…its transcript saying approved', answerHTML({ ...rdWaiting, status: 'approved' }, rdSession()));
  show('…not taken: why, with the way to its tab, as only it can answer it now', answerHTML(rdWaiting,
                                                                                           yours('notTaken')));
  show('…not taken, for another request of its session\'s: still waiting for Claude to take it',
       answerHTML(rdWaiting, { ...yours('notTaken'), answeredFor: { ...yours('notTaken').answeredFor, askId: 'q0' } }));
  state.reading = drawn();
  show('the app knows why not: why, with Take me there, Send back… and Stop', answerHTML(rdWaiting, asks({
    approveWhyNot: 'it may run with permissions bypassed once approved, so approve it in its tab' })));
  state.reading = rdReading();
  show('not drawn yet: no Approve', answerHTML(rdWaiting, asks()).includes('r-approve'));
  show('the text drawn for the waiting plan: the request\'s own', askedText({ ...rdOlder, id: 'ask:q1' }, asks()));
  show('…a plan cut short: the transcript\'s', askedText(rdWaiting, asks({ truncated: true })));
  show('…a writing that isn\'t the waiting plan: its own', askedText(rdOlder, asks()));
  show('the app\'s words as a sentence', [planSentence('its file changed'), planSentence('Done.'), planSentence('')]);
}

section('Approve waits to be seen from when it comes into the bar (drawAnswer)');
{
  // The bar as the page has it: what's put in it, and Approve found in that (the stand-in page has no HTML of its own).
  const bar = { dataset: {}, contains: () => false, querySelector(sel) {
    const m = sel === '.r-approve' && /r-approve" data-ask="([^"]*)"\s+data-digest="([^"]*)"/.exec(this.innerHTML || '');
    return m ? { dataset: { ask: m[1], digest: m[2] } } : null;
  } };
  const pick = reader.querySelector;
  reader.querySelector = (sel) => (sel === '.r-answer' ? bar : pick(sel));
  const r = rdReading({ id: rdWaiting.id, ready: true, drawnPlan: { id: 'q1', digest: 'd1' } });
  const s = rdSession({ digest: 'd1' });
  state.reading = r;
  const seen = () => { const at = 'approve:q1' in state.shownAt; delete state.shownAt['approve:q1']; return at; };
  delete state.shownAt['approve:q1'];
  drawAnswer(r, s, rdWaiting);
  show('drawn: its wait starts', seen());
  drawAnswer(r, s, rdWaiting);
  show('…drawn again as it was: no new wait', seen());
  r.revising = true;
  drawAnswer(r, s, rdWaiting);
  show('the box for your notes in its place: no wait for what isn\'t there', seen());
  r.revising = false;
  drawAnswer(r, s, rdWaiting);
  show('…cancelled, Approve back: its wait starts again', seen());
  reader.querySelector = pick;
  state.reading = null;
}

section('Your Approve, and how the rows say it went (approvePressed, planApprovalsFrom)');
{
  const kept = { readerSession, justShown, keepInPlace, drawAnswer, fitReader, render, answered };
  const bridge = window.webkit;
  const sent = [];
  let approval;  // what the ask says of your last press, as the app put it on the row
  window.webkit = { messageHandlers: { panel: { postMessage: (m) => sent.push(m) } } };
  Object.assign(globalThis, { readerSession: () => rdSession({ digest: 'd2', approval }),
    keepInPlace() {}, drawAnswer() {}, fitReader() {}, render() {},
    answered: (id, how) => sent.push({ answered: id, how }) });
  state.reading = rdReading({ mode: 'writings', sessionId: 's1', id: 'ask:q1', drawnPlan: { id: 'q1', digest: 'd1' } });
  const button = { dataset: { ask: 'q1', digest: 'd1' } };
  const rows = (more) => planApprovalsFrom([{ sessionId: 's1', ...more }]);
  justShown = () => true;
  approvePressed(button);
  show('only just drawn: not taken', sent.splice(0));
  justShown = () => false;
  approvePressed(button);
  show('pressed: the request and digest it was drawn with, never the request as it is now', sent.splice(0));
  approvePressed(button);
  show('…pressed again while the app has it: nothing more', sent.splice(0));
  show('rows with the ask as it was: still with the app', [rows({ ask: rdAsk() }), state.planApproving.s1]);
  approval = { why: 'the Mac had no keyboard or mouse use just before the press', again: true, at: 5 };
  show('…its ask saying it wasn\'t approved: the press ends, the bar shows why from the ask',
       [rows({ ask: rdAsk({ approval }) }), state.planApproving.s1, sent.splice(0)]);
  approvePressed(button);
  show('pressed again: sent again, kept with what the ask said of the last press', [sent.splice(0),
    state.planApproving.s1]);
  show('…rows still saying the last press: still with the app', [rows({ ask: rdAsk({ approval }) }),
    state.planApproving.s1]);
  show('…the request gone, approved by you for it: the row says so, and the bar',
       [rows({ answeredFor: { what: 'approved', yours: true, askId: 'q1' } }), sent.splice(0), state.reading.sent]);
  state.reading.sent = {};
  approval = undefined;
  approvePressed(button);
  sent.splice(0);
  show('…gone some other way (answered in its tab): the press ends, nothing said',
       [rows({ answeredFor: { what: 'approved', yours: true, askId: 'q0' } }), sent.splice(0), state.reading.sent]);
  delete state.planApproving.s1;
  Object.assign(globalThis, kept);
  window.webkit = bridge;
  state.reading = null;
}

section('The button at the end of a row\'s ask for a plan or a look (askActOf)');
{
  const proto = { id: 'p2', kind: 'prototype', title: 'Chats', path: '/work/chats/chats.html', at: min(4) };
  const of = (s, want) => { const a = askActOf(s, want); return a && [a.w.id, a.tip]; };
  show('a plan Claude waits on: opened at it', of(rdSession(), 'plan'));
  show('…in a session the panel can\'t answer: opened at it, to read, answered in its session',
       of(rdSession({ legacy: true }), 'plan'));
  show('…no plan waiting (a merge to approve, say): none', of({ sessionId: 's1', writings: [rdOlder] }, 'plan'));
  show('a look: the newest prototype', of({ sessionId: 's1', writings: [rdOlder, proto,
    { ...proto, id: 'p1', at: min(40) }] }, 'look'));
  show('…none written: none', of({ sessionId: 's1', writings: [rdOlder] }, 'look'));
  show('a try: not this module\'s', of(rdSession(), 'try'));
  // A plan Claude still waits on in its session with no request up here (it stopped asking after an hour, or when
  // the panel restarted): opened at the transcript's plan, to read, and answered in its session.
  const stale = { id: 'w9', kind: 'plan', title: 'Shopping list', at: min(2900), status: 'waiting' };
  const onlyListed = (more = {}) => ({ sessionId: 's1', name: 'Wren', status: 'waiting', writings: [stale, rdOlder],
                                       ...more });
  show('a plan waiting in the transcript only: opened at it, to read', of(onlyListed(), 'plan'));
  show('…its session idle at its prompt: opened at it, to send back from here', of(onlyListed({ status: 'idle' }), 'plan'));
  show('…its session at work: none', of(onlyListed({ status: 'busy' }), 'plan'));
  show('…in the list: waiting for you', writingStatus(stale, onlyListed()));
  show('…while a request is up for one the panel can\'t answer: its request\'s plan, as that request\'s words say',
       of(onlyListed({ ask: rdAsk({ legacy: true }) }), 'plan'));
  const was = state.reading;
  state.reading = rdReading({ mode: 'writings', sessionId: 's1', id: 'w9' });
  show('…under it, beside the list: why, and the way to its session, with nothing to answer here',
       answerHTML(stale, onlyListed()));
  show('…an older plan of its own: nothing under it', answerHTML(rdOlder, onlyListed()));
  const idle = onlyListed({ status: 'idle' });
  show('its session idle at its prompt: Send back… types your notes in, and Take me there; Approve and Stop are its '
       + 'session\'s', answerHTML(stale, idle));
  show('…your notes go to it', planNotesTarget(idle));
  state.reading.revising = true;
  show('…Send back…: the box, saying they\'re typed in as a message', answerHTML(stale, idle));
  const kept = { readerSession, putHTML, drawReader, wantKeyboard, keepInPlace }, typedSent = [];
  Object.assign(globalThis, { readerSession: () => idle, putHTML: () => {}, drawReader: () => {},
                              wantKeyboard: () => {}, keepInPlace: () => {} });
  const bridge = window.webkit;
  window.webkit = { messageHandlers: { panel: { postMessage: (m) => typedSent.push(m) } } };
  state.reading.notes = '  Split step 2.  ';
  state.reading.notesFor = planNotesTarget(idle);
  sendPlanAnswer('revise');
  window.webkit = bridge;
  show('…Send to Claude: typed in by its agent\'s module, and kept meanwhile', [typedSent,
    state.planKept.s1, state.reading.sent.w9]);
  const typedFor = (st, more = {}) => ({ by: 'You', what: 'sentBack', yours: true, askId: 'w9', planId: 'w9',
                                         state: st, at: Date.now() + 1000, ...more });
  show('…before the row says anything: typing', answerHTML(stale, idle));
  show('…not typed in: why, the way past, Take me there and Send back… again',
       answerHTML(stale, { ...idle, answeredFor: typedFor('notTyped', { why: 'Ghostty is in front', way: 'Bring It Here' }) }));
  show('…a refusal said before this press: still typing', answerHTML(stale, { ...idle,
    answeredFor: typedFor('notTyped', { why: 'old', at: 1 }) }));
  const typedIn = { ...idle, lastPromptAt: NOW, answeredFor: typedFor('typed') };
  show('…typed in', answerHTML(stale, typedIn));
  planKeptStale(state.reading, typedIn);
  show('…and the notes it kept for it go', state.planKept.s1 ?? null);
  Object.assign(globalThis, kept);
  delete state.reading.sent.w9;
  const held = onlyListed();
  show('held at its own prompt: nothing to send your notes to', planNotesTarget(held));
  state.reading = was;
}

section('Your notes, kept for the plan they were written for (planNotesBack, planKeptWords)');
state.reading = rdReading({ sessionId: 's1' });
const rdBack = (more) => {
  const r = { ...state.reading, notesFor: 'q1', session: rdSession(), ...more };
  planNotesBack(r);
  return r;
};
state.reading.notes = '  Split step 2.\n\nKeep it short.  ';
const rdLeft = rdBack().notes;
show('the reader closed unsent: your words kept for that plan, lines and all, and leave the reader',
     [state.planKept.s1, rdLeft]);
show('…the bar under it says they wait', /are kept: Send back… opens them/.test(answerHTML(rdWaiting, rdSession())));
state.reading.notes = 'Rename the button.';
rdBack();
show('…closed unsent again: after what was kept', state.planKept.s1);
state.reading.notes = '';
planKeptWords(state.reading, rdSession());
show('Send back… on that plan: its box has them, and they leave the keeping', [state.reading.notes,
                                                                                 state.planKept.s1 ?? null]);
state.planPicks.q1 = { 0: 1 };
show('…and they go back with your picks', planNotesMessage(state.reading, rdSession()));
state.planKept.s1 = { id: 'q0', text: 'For the version before.' };
state.reading.notes = '';
planKeptWords(state.reading, rdSession());
show('notes kept for another version: never put in this one\'s box', [state.reading.notes, state.planKept.s1]);
planKeptStale(state.reading, rdSession());
show('…and, drawn, moved to those to copy, with nothing left kept', [state.planUnsent.s1, state.planKept.s1 ?? null]);
delete state.planUnsent.s1;
state.reading.notes = 'Split step 2.';
const rdOther = rdBack({ notesFor: 'q0' });
show('notes for a plan answered elsewhere: never kept for the plan that asks next, and gone from the reader',
     [state.planKept.s1 ?? null, rdOther.notes]);
delete state.planUnsent.s1;
state.reading.notes = 'Split step 2.';
rdBack({ session: rdSession({ legacy: true }) });
show('…nor for a session the panel can\'t answer', state.planKept.s1 ?? null);
delete state.planUnsent.s1;
core.plans.clearPicks('q1');
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
  show('…closed after Cancel instead: kept to copy, not dropped, and not kept for the new version',
       [state.planUnsent.s1, state.planKept.s1 ?? null]);
  show('…until Done with These', (core.readerPresses.find(([sel]) => sel === '.r-unsent-done')[1](),
                                   state.planUnsent.s1 ?? null));
  Object.assign(globalThis, kept);
  core.plans.clearPicks('q1');
  state.reading = null;
}

