// What a session wrote for you to read (its plans, prototypes and notes): the tag on its row, the button at the end of
// a row's ask for a plan or a look, and the reader's "writings" mode, where a plan Claude is waiting on can be
// approved, sent back with your notes, or stopped.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// Pressing a row's tag opens the reader beside the list (reader.js), with everything the session wrote down its side,
// newest first. A plan Claude waits on is approved here only by your press on Approve, for the text drawn with it: the
// app checks it again before it answers (through the session's agent's module, core.planAsks), and says here how it
// went.

const WRITING_WORDS = { plan: ['Plan', 'Plans'], prototype: ['Prototype', 'Prototypes'], notes: ['Notes', 'Notes'] };
// What a session wrote, on its tag and in the reader's list: a plan (a page with lines), a prototype (a window) and
// notes (a page of text).
const WRITING_ICONS = {
  plan: '<svg width="9" height="10" viewBox="0 0 9 10"><path d="M1.5 1h4l2 2v6h-6z M3 5h3 M3 7h3" fill="none" '
    + 'stroke="currentColor" stroke-width="1.2" stroke-linejoin="round"/></svg>',
  prototype: '<svg width="10" height="10" viewBox="0 0 10 10"><rect x="1" y="1.5" width="8" height="7" rx="1.2" '
    + 'fill="none" stroke="currentColor" stroke-width="1.2"/><path d="M1 3.8h8" stroke="currentColor" '
    + 'stroke-width="1.2"/></svg>',
  notes: '<svg width="9" height="10" viewBox="0 0 9 10"><path d="M1.5 1h6v8h-6z M3 3.5h3 M3 5.5h3 M3 7.5h2" fill="none" '
    + 'stroke="currentColor" stroke-width="1.2" stroke-linejoin="round"/></svg>',
};
// A prototype is shown at a laptop's width, and its height can't be measured (it's in a browser of its own), so it
// takes the height the screen allows.
const PROTOTYPE_HEIGHT = 2000;

// The listed plan Claude's request is about: one still without an answer, presented just before the request was
// left (the hook leaves it as Claude asks). An older one without an answer was left when its session moved on, and
// a plan answered here must be the one you read, so it never stands in for a newer request.
const ASKED_WITHIN_MS = 5 * 60 * 1000;
// The plan the session's agent waits for your OK on, as that agent's module says it (core.planAsks: its request's id,
// text and file, whether the panel can answer it, and what stands in Approve's way), with that module to answer it
// (`by`: approve, sendBack, stop, hold), or null.
function planAskOf(s) {
  for (const by of core.planAsks) {
    const ask = by.of(s);
    if (ask) return { ...ask, by };
  }
  return null;
}
// Your Approve of request `id` as its row says it went, by whichever agent's module knows it: 'pending', 'approved',
// 'notTaken' or null.
const planYours = (s, id) => core.planAsks.map((by) => by.yours(s, id)).find(Boolean) ?? null;

function askedPlan(listed, ask) {
  return listed.find((w) => w.kind === 'plan' && w.status === 'waiting' && w.at <= ask.at + 60000
                            && ask.at - w.at < ASKED_WITHIN_MS) || null;
}

// A session's writings as the reader lists them. A plan Claude has only just asked about is there at once, from
// its request, before the transcript's next read lists it (`fromAsk`).
function writingsOf(s) {
  const listed = s?.writings || [];
  const ask = planAskOf(s);
  if (!ask || askedPlan(listed, ask)) return listed;
  const plan = ask.text;
  return [{ id: 'ask:' + ask.id, kind: 'plan', title: (plan.match(/^\s*#+\s*(.+)$/m) || [])[1] || 'Plan',
            path: ask.path, at: ask.at, status: 'waiting', fromAsk: plan }, ...listed];
}

// The plan Claude is waiting on now, while its request is up.
function waitingPlan(s) {
  const ask = planAskOf(s);
  if (!ask) return null;
  const all = writingsOf(s);
  return all.find((w) => w.id === 'ask:' + ask.id) || askedPlan(all, ask);
}

// The plan Claude still waits on in its session though no request for it is up here, as its agent's module says it
// (core.planAsks' `left`): the writing, with `held` (only its session's own prompt can answer it, which a key would
// answer, so nothing is typed in) and the module that knows it (`by`: typeBack, typed). A request stops asking here
// after an hour, or when Whozmove restarts, while Claude's own prompt in its session keeps it, so it's read beside the
// list. Null while a request is up (a session started before Whozmove's update included, whose request has its own
// words), or for any other session. A plain function.
function transcriptPlan(s) {
  if (planAskOf(s)) return null;
  for (const by of core.planAsks) {
    const left = by.left?.(s), w = left && (s.writings || []).find((x) => x.id === left.id);
    if (w) return { ...w, held: left.held, by };
  }
  return null;
}
// The plan a session at work last showed you, while none waits on you there and it wasn't approved: read beside the
// list from an ask for it on the session's row (a team's, for another of its jobs, say), as a session at work takes no
// answer for it. At work is what the list says of its row (state.kinds: 'busy'), never a 'background' one, whose turn
// has ended. Null while a plan waits or was left waiting (waitingPlan, transcriptPlan), for a session not at work, or
// one whose newest plan was approved, which is the work it's doing. A plain function of the rows.
function workingPlan(s) {
  if (!s || state.kinds?.[s.sessionId] !== 'busy' || planAskOf(s) || transcriptPlan(s)) return null;
  const w = writingsOf(s).find((x) => x.kind === 'plan');
  return w && w.status !== 'approved' ? w : null;
}
// What your notes would go to now: the request Claude waits on, where the panel can answer it, else a plan it still
// waits on that they can be typed in for ('w:' and its id), else nothing. A plain function.
function planNotesTarget(s) {
  const ask = planAskOf(s);
  if (ask) return ask.answerable ? ask.id : null;
  const left = transcriptPlan(s);
  return left && !left.held ? 'w:' + left.id : null;
}

// The row's tag, quietly: the icon of the plan waiting for you, or else of the newest thing written, and how many
// things it wrote. A plan waiting for you is in the plan's colour. It shows as pressed while the reader is open on its
// session, as pressing it again closes it.
function writingsTag(s) {
  const all = writingsOf(s);
  if (!all.length) return '';
  const waiting = waitingPlan(s) || transcriptPlan(s), lead = waiting || all[0];
  const r = state.reading;
  const on = r?.mode === 'writings' && r.sessionId === s.sessionId && !r.closing ? ' on' : '';
  const title = waiting ? 'A plan waiting for you: read it'
    : `Read what this session wrote: ${all.length} ${all.length === 1 ? 'thing' : 'things'}`;
  return `<span class="tag wtag${waiting ? ' plan' : ''}${on}" data-writings="${esc(s.sessionId)}"`
    + ` data-wid="${esc(lead.id)}" title="${title}">${WRITING_ICONS[lead.kind]}${all.length}</span>`;
}

// How a writing stands, as its line in the list says: for a plan, whether it's waiting on you or how it was
// answered; a plan with no answer that isn't waiting any more was left when its session moved on.
function writingStatus(w, s) {
  if (w.kind !== 'plan') return [base(w.path) || WRITING_WORDS[w.kind][0], ''];
  const sent = state.reading?.sent?.[w.id];
  if (sent) return [sent === 'stop' ? 'Stopped' : 'Sent back', 'back'];
  if (w.status === 'approved') return ['Approved', 'ok'];
  if (w.status === 'declined') return ['Not approved', 'back'];
  return (waitingPlan(s) || transcriptPlan(s))?.id === w.id ? ['Waiting for you', 'wait'] : ['No answer', ''];
}

// A writing's text, read by the app: {text} or {missing}.
window.showWriting = (sid, wid, read) => {
  const r = state.reading;
  if (!r || r.sessionId !== sid || r.mode !== 'writings') return;
  r.reads[wid] = { ...read, at: r.reads[wid]?.at };
  if (r.id === wid) drawView();
};

// ---- Drawing ----

// What the reader shows, from the newest rows: its header, the list and the answer bar each time; what's being
// read only when it changes, so the page's scroll, a prototype's own state and the notes being typed are kept.
function drawWritings() {
  const r = state.reading, s = readerSession();
  if (planNotesStale(r, s)) planNotesUnsent(r);
  planKeptStale(r, s);
  const all = writingsOf(s);
  if (!all.some((w) => w.id === r.id) && all.length) r.id = (waitingPlan(s) || transcriptPlan(s) || all[0]).id;
  const w = all.find((x) => x.id === r.id);
  // The list's update comes every second: only what changed is put in, so hover effects and the layout aren't redone
  // each time, and the panel is measured again only then.
  const head = `<span class="r-title">${esc(s.name || base(s.cwd))}</span>
    <span class="r-sub">${all.length} written in this session</span>
    <button class="icon-button r-close" title="Close">${CLOSE_ICON}</button>`;
  let changed = putHTML(reader.querySelector('.r-head'), head);
  changed = putHTML(reader.querySelector('.r-shelf'), shelfHTML(s, all, r.id)) || changed;
  changed = drawAnswer(r, s, w) || changed;
  drawView();
  if (!changed) return;
  fitReader();
  syncHover();
}

// The bar under what's read, but not while you're typing in it: whether it changed. Approve in it waits to be seen
// each time it comes into the bar, for another request or text or after the bar showed something else (the box for
// your notes, your picks), as a card's buttons do (`approve:<request>`).
function drawAnswer(r, s, w = writingsOf(s).find((x) => x.id === r.id)) {
  const answer = reader.querySelector('.r-answer');
  if (!answer || answer.contains(document.activeElement)) return false;
  const changed = putHTML(answer, w ? answerHTML(w, s) : '');
  const approve = answer.querySelector('.r-approve');
  const shown = approve ? `${approve.dataset.ask}@${approve.dataset.digest}` : null;
  if (r.approveShown !== shown) {
    r.approveShown = shown;
    if (approve) state.shownAt['approve:' + approve.dataset.ask] = Date.now();
  }
  return changed;
}

// The list down the reader's side: plans, then prototypes, then notes, each newest first. A file's name is whatever
// the session called it, so it goes in as text, like everything else the session wrote.
function shelfHTML(s, all, current) {
  const now = state.last.now;
  return ['plan', 'prototype', 'notes'].map((kind) => {
    const items = all.filter((w) => w.kind === kind);
    if (!items.length) return '';
    return `<div class="caps r-group">${WRITING_WORDS[kind][1]}</div>` + items.map((w) => {
      const [label, tone] = writingStatus(w, s);
      return `<button class="r-item k-${kind}${w.id === current ? ' on' : ''}" data-wid="${esc(w.id)}">
          <span class="r-icon">${WRITING_ICONS[kind]}</span><span class="r-name">${esc(w.title || base(w.path))}</span>
          <span class="r-meta"><span class="${tone ? 'st-' + tone : ''}">${esc(label)}</span> · ${ago(now - (w.at || now))}</span>
        </button>`;
    }).join('');
  }).join('');
}

// What's being read: asked of the app once (again if the file was written since), shown when it's back; or a
// prototype, which the app shows itself.
function drawView() {
  const r = state.reading, s = readerSession();
  if (!r || !s) return;
  const w = writingsOf(s).find((x) => x.id === r.id);
  const src = reader.querySelector('.r-src'), body = reader.querySelector('.r-body');
  if (w?.kind === 'prototype') return drawPrototype(w, src, body);
  leavePrototype();
  if (!w) {
    putHTML(src, '');
    body.innerHTML = '<div class="r-missing">Nothing written in this session yet.</div>';
    r.shown = null;
    return;
  }
  // The plan Claude waits on is drawn from its request's own text, the one Approve is for (the transcript's copy, or
  // its file, can differ from it), with the request and digest it's drawn for (`drawn`, which Approve carries).
  const asked = askedText(w, s), ask = planAskOf(s), drawn = asked === null ? null : { id: ask.id, digest: ask.digest };
  let read;
  if (asked !== null) read = { text: asked };
  else if (w.fromAsk !== undefined) read = { text: w.fromAsk };
  else {
    if (r.reads[w.id]?.at !== w.at) {
      r.reads[w.id] = { at: w.at };
      native({ type: 'readWriting', sessionId: s.sessionId, id: w.id });
    }
    read = r.reads[w.id];
    if (read.text === undefined && !read.missing) read = null;  // asked, not back yet
  }
  // A plan is drawn again as whether it can take your picks changes, where you were in it kept.
  const same = `${w.id}@${w.at}@${read?.text?.length ?? read?.missing ?? 'wait'}`
    + `@${drawn ? drawn.id + drawn.digest : ''}`;
  const how = planHow(w, s, r), key = `${same}@${how.waiting}@${how.held}`;
  if (r.shown === key) return;
  const kept = r.shown?.startsWith(`${same}@`) ? body.scrollTop : 0;
  r.shown = key;
  r.drawnPlan = null;  // until the text it's for is in the body
  putHTML(src, `<span class="r-path">${esc(w.path || '')}</span>${publishedHTML(w)}`);
  if (!read) {
    readerWait(body, writingWaitWords(w));
    r.ready = false;
    fitReader();
    return;
  }
  const html = writingBodyHTML(w, s, read, r);
  // Still the one to show: another writing may have been picked while the words it waited with went.
  const show = () => {
    if (r.shown !== key) return;
    body.innerHTML = html;
    // What's drawn at the width it has (a diagram) is drawn before where you were is put back, so it lands there.
    for (const drawn of core.readerDrawn) drawn(body);
    body.scrollTop = kept;
    r.ready = true;
    // Approve shows once the text it's for is drawn, so the bar is drawn again with it.
    r.drawnPlan = drawn;
    drawAnswer(r, s);
    fitReader();
  };
  // In place of the words it waited with, it comes in once they've gone.
  if (body.querySelector(':scope > .r-wait')) readerRefill(body, show);
  else show();
}

// How a plan stands for the picks on its card: whose they are (the request's id while Claude waits on it, else the
// plan's own), whether they can be made (Claude waits on it, the panel can answer it, and it hasn't been sent back or
// stopped from here), and whether they're held while the notes they go back in are open. A plain function.
function planHow(w, s, r) {
  const ask = planAskOf(s), asked = w.kind === 'plan' && !!ask && waitingPlan(s)?.id === w.id;
  const waiting = asked && ask.answerable && !r.sent?.[w.id];
  return { id: asked ? ask.id : w.id, waiting, held: waiting && !!r.revising };
}

// The text to draw for the plan Claude waits on: its request's own, which the app's digest is of, unless it came cut
// short (not `whole`), when the transcript's whole copy is read instead and Approve isn't offered; null for any other
// writing. A plain function.
function askedText(w, s) {
  const ask = planAskOf(s);
  if (w?.kind !== 'plan' || !ask || !ask.whole || waitingPlan(s)?.id !== w.id) return null;
  return ask.text;
}

// Whether Approve is offered under a plan, a plain function. Only for the plan Claude waits on, from a session the
// panel can answer, not sent back or stopped from here, once the text it's for is drawn in the body (`r.drawnPlan`, the
// request and digest Approve carries, which must still be the request's), with nothing the app knows already standing
// in its way, the request cut short among them (`whyNot`, in its words). `going` is your Approve of it while the app
// has it (state.planApproving); how your last press went is the app's, on the ask (`approval`, { why }, with `again`
// where a second press may yet approve it). What it says: { approve, id, digest }, with { why, refused } when a second
// press may yet; { why } where Claude waits on it but it can't be approved here (`refused` when the app said so at your
// press); { going } while the app has your press; { drawing } until its text is in; null for anything else.
function planApproveHow(w, s, r, going = state.planApproving[s?.sessionId]) {
  const ask = planAskOf(s);
  if (w?.kind !== 'plan' || waitingPlan(s)?.id !== w.id || !ask || !ask.answerable || r.sent?.[w.id]) return null;
  if (going?.id === ask.id) return { going: true };
  const went = ask.approval?.why ? { why: planSentence(ask.approval.why), refused: true } : null;
  if (went && !ask.approval.again) return went;
  if (ask.whyNot) return { why: planSentence(ask.whyNot) };
  const d = r.drawnPlan;
  if (!r.ready || !d?.digest || d.id !== ask.id || d.digest !== ask.digest) return { drawing: true };
  return { approve: true, id: d.id, digest: d.digest, ...went };
}

// Words the app gives, as a sentence: a capital first, a full stop last. A plain function.
const planSentence = (words) => {
  const text = String(words || '').trim();
  return text ? text[0].toUpperCase() + text.slice(1) + (/[.!?]$/.test(text) ? '' : '.') : '';
};

// What a writing shows once it's read: why it can't be; a plan on its card at a glance, where the plans module gives
// one; else its Markdown. It decides nothing else, but the plans module keeps what it drew, which the bar's picks are
// read from (core.plans.picks): a plan not drawn yet has none.
function writingBodyHTML(w, s, read, r) {
  if (read.missing) return `<div class="r-missing">${esc(read.missing)}</div>`;
  const how = planHow(w, s, r);
  const glance = w.kind === 'plan' ? core.plans?.readerHTML(read.text, { sessionId: s.sessionId, id: how.id,
    who: s.name || base(s.cwd), waiting: how.waiting, held: how.held }) : null;
  return glance ?? `<article class="md">${markdownHTML(read.text)}</article>`;
}

// Where a writing is being read from, while it is: a plan as Claude asked about it, from the session's transcript, or
// a file as it is now. A plain function.
function writingWaitWords(w) {
  return w.kind === 'plan' ? 'Reading the plan from the session\'s transcript…' : `Reading ${base(w.path) || 'the notes'}…`;
}

// A writing published from the session (its address on the web), to open there.
function publishedHTML(w) {
  return w.url ? ` · <button class="r-open" data-url="${esc(w.url)}">Open the published page</button>` : '';
}

// ---- A prototype ----

// A prototype shows from its file, in a browser of its own the app holds over the reader's body
// (modules/reader/app/ReaderModule.m), where the files beside it, its links and its scripts work as in your browser,
// and nothing in it can reach the panel. Here the body is only the space it's held over: what's in that space shows
// until its page is in, or when it can't be shown. What the app says of it, {loading, problem, asked, keyboard}, is
// kept on the reader as `proto`, with the prototype it's about, and what the app was told of where it goes.

// What the line above a prototype says under its path: what it asked for that the panel doesn't do, else whether it
// has the keyboard, and with it the pointer, which it gets only once you've clicked into it. A plain function.
const PROTOTYPE_ASKS = {
  window: 'It tried to open a window, which the panel doesn\'t do.',
  alert: 'It tried to show a message box, which the panel doesn\'t do.',
  files: 'It asked for a file, which the panel doesn\'t pick.',
  download: 'It tried to download a file, which the panel doesn\'t do.',
  camera: 'It asked for the camera or the microphone, which the panel doesn\'t give.',
  otherApp: 'It tried to open another app, which the panel doesn\'t do.',
  link: 'That link goes to a file outside its folder, which the panel doesn\'t open.',
};
function prototypeNote(st) {
  if (!st || st.problem) return '';
  if (st.asked) return `${PROTOTYPE_ASKS[st.asked] || 'It asked for something the panel doesn\'t do.'} `
    + 'Open it in your browser for that.';
  if (st.loading) return '';
  return st.keyboard ? 'It has the keyboard: click the list to give it back.' : 'Click into it to point and type.';
}

// What shows in its space while the page isn't over it: which file is loading until it's in, or why it can't be shown.
function prototypeUnder(st, w) {
  if (st?.problem) return st.problem;
  return !st || st.loading ? `Loading ${base(w?.path) || 'the prototype'}…` : '';
}

// The line above a prototype: where it is, Open in Browser, and what prototypeNote says.
function prototypeLine(w, st) {
  const note = prototypeNote(st);
  return `<span class="r-path">${esc(w.path || '')}</span> · <button class="r-open r-outside">Open in Browser</button>`
    + publishedHTML(w) + (note ? `<div class="r-note">${esc(note)}</div>` : '');
}

// The body becomes the prototype's space once (again when the file's been written since), and the line and the words
// in that space follow what the app says.
function drawPrototype(w, src, body) {
  const r = state.reading;
  if (r.proto && r.proto.id !== w.id) leavePrototype();
  r.proto ??= { id: w.id, state: null };
  const key = `${w.id}@${w.at}`;
  if (r.shown !== key) {
    r.shown = key;
    body.innerHTML = '<div class="r-proto"><div class="r-missing"></div></div>';
    body.scrollTop = 0;
    prototypeWatch?.disconnect();
    prototypeWatch?.observe(body.firstElementChild);
    r.ready = true;
  }
  const lineChanged = putHTML(src, prototypeLine(w, r.proto.state));
  const under = body.querySelector('.r-proto .r-missing');
  if (under) {
    under.textContent = prototypeUnder(r.proto.state, w);
    // It breathes while the page loads (readerWait's words do too).
    under.classList.toggle('r-wait', !r.proto.state?.problem && !!(!r.proto.state || r.proto.state.loading));
  }
  if (lineChanged) fitReader();
  placePrototype();
}

// Tells the app where the prototype's space is in the page, once the reader is laid out at the width it asked for, so
// the panel grows to it first and the page loads in view: shown the first time, and again once its file's been
// written since (it loads again, where you were in it); moved as the space moves. Not while the reader folds away:
// the prototype stays as it was meanwhile, as the reader's text does.
function placePrototype() {
  const r = state.reading, space = reader.querySelector('.r-proto');
  if (!r?.proto || !space || r.closing || !(Math.abs((r.laidOutWidth ?? -9) - (r.askedWidth ?? 0)) < 1)) return;
  const w = writingsOf(readerSession()).find((x) => x.id === r.id);
  if (w?.kind !== 'prototype' || w.id !== r.proto.id) return;
  const box = space.getBoundingClientRect();
  const rect = { x: Math.round(box.left + window.scrollX), y: Math.round(box.top + window.scrollY),
                 width: Math.round(box.width), height: Math.round(box.height) };
  const key = `${w.id}@${w.at}`;
  if (r.proto.key !== key) {
    r.proto.key = key;
    r.proto.rect = rect;
    native({ type: 'prototype', action: 'show', sessionId: r.sessionId, id: w.id, at: w.at, rect });
  } else if (JSON.stringify(rect) !== JSON.stringify(r.proto.rect)) {
    r.proto.rect = rect;
    native({ type: 'prototype', action: 'place', rect });
  }
}

// The space changes size as the panel grows and as the line above it changes: the prototype goes with it at once,
// rather than at the next update.
const prototypeWatch = typeof ResizeObserver === 'function' ? new ResizeObserver(() => placePrototype()) : null;

// The reader shows something else, or has closed: the app takes the prototype away.
function leavePrototype() {
  const r = state.reading;
  if (!r?.proto) return;
  r.proto = null;
  prototypeWatch?.disconnect();
  native({ type: 'prototype', action: 'hide' });
}

// How the prototype stands, as the app says: loading, why it can't be shown, what it asked for, and whether it has the
// keyboard.
window.prototypeState = (sid, wid, st) => {
  const r = state.reading;
  if (!r || r.sessionId !== sid || r.proto?.id !== wid) return;
  r.proto.state = st;
  drawView();
};

// Under a plan Claude is waiting on: Approve, for the text drawn (planApproveHow), else why it can't be approved here;
// sending it back with notes, or stopping it, as its agent's module answers it (core.planAsks); and Take me there, to
// its session. A plan from a session started before Whozmove's update is answered in the session only, as
// its row says.
function answerHTML(w, s) {
  const r = state.reading, sent = r.sent[w.id];
  if (sent === 'approve') return approvedHTML(w, s, r);
  if (sent === 'typed') return typedHTML(w, s, r);
  if (sent) return `<div class="r-done">${sent === 'stop' ? 'Stopped. Claude won\'t carry out this plan.'
    : 'Sent back to Claude with your notes. It stays in plan mode and writes a new version, which shows up here.'}</div>`;
  // While the version shown is the one Claude waits on, its own Send back… and Stop stay too: Send back… opens its
  // box with these notes above it, to copy from, so moving on never needs Done with These first.
  const unsent = w.kind === 'plan' && state.planUnsent[r.sessionId];
  if (unsent && !r.revising) {
    const answerable = waitingPlan(s)?.id === w.id && !!planAskOf(s)?.answerable;
    const typable = !answerable && transcriptPlan(s)?.id === w.id && !!planNotesTarget(s);
    return `<div class="r-ask"><div class="r-q">Claude isn't waiting on the version your notes were for any more: it was
        answered elsewhere, so they weren't sent. Here they are, to copy into what you send next:</div>
      <p class="r-picked r-unsent">${esc(unsent)}</p>
      <div class="r-buttons"><button class="button main r-go">Take me there</button>${answerable
        ? '<button class="button r-revise">Send back…</button><button class="button r-stop">Stop</button>'
        : typable ? '<button class="button r-revise">Send back…</button>' : ''}
        <button class="button r-unsent-done">Done with These</button></div></div>`;
  }
  // The plan of a session at work, opened from its row's ask: only to read, as nothing reaches it while it works.
  if (workingPlan(s)?.id === w.id) {
    return `<div class="r-ask"><div class="r-q">Only to read here: Claude is working in its session, so answer anything
        about this plan there.</div>
      <div class="r-buttons"><button class="button main r-go">Take me there</button></div></div>`;
  }
  // One Claude still waits on in its session, whose request stopped asking here: read here; approved or stopped only
  // there; sent back from here with your notes typed in as a message, but only while its session is idle at its
  // prompt, as a key typed while the plan's own prompt is up would answer it.
  const left = transcriptPlan(s);
  if (left?.id === w.id) {
    const why = 'A plan stops asking here after an hour, or when Whozmove restarts. Claude\'s own prompt in its '
      + 'session still has it.';
    if (left.held) {
      return `<div class="r-ask"><div class="r-q" title="${esc(why)}"><span class="dot"></span>Claude is waiting for
          your OK on this plan. Answer it in its session: it stopped asking here.</div>
        <div class="r-buttons"><button class="button main r-go">Take me there</button></div></div>`;
    }
    if (r.revising) return planNotesBoxHTML(r, s, unsent, '', 'Your notes are typed into its session as a message, '
      + 'and Claude writes a new version. What should change?');
    const kept = state.planKept[r.sessionId]?.id === 'w:' + w.id ? ' Your notes for it are kept: Send back… opens them.'
      : '';
    return `<div class="r-ask"><div class="r-q" title="${esc(why)}"><span class="dot"></span>Claude is waiting for your
        OK on this plan, but it stopped asking here: approve or stop it in its session. Send back… types your notes in
        as a message.${kept}</div>
      <div class="r-buttons"><button class="button main r-revise">Send back…</button>
        <button class="button r-go">Take me there</button></div></div>`;
  }
  if (waitingPlan(s)?.id !== w.id) return '';
  const ask = planAskOf(s);
  if (!ask.answerable) {
    return `<div class="r-ask"><div class="r-q"><span class="dot"></span>Claude is waiting for your OK on this plan.
        Answer it in the session: it started before Whozmove's update, so the panel can't answer it.</div>
      <div class="r-buttons"><button class="button main r-go">Take me there</button></div></div>`;
  }
  // Picks of yours on its card that differ from Claude's (the plans module's) go back as notes: in the box, above
  // your own words, to read first.
  const picks = core.plans?.picks(ask.id);
  if (r.revising) {
    const picked = picks?.changed ? picks.note : '';
    return planNotesBoxHTML(r, s, unsent, picked, picked
      ? 'Your picks go back in these words, and Claude writes a new version. Add anything else:'
      : 'What should change? Claude stays in plan mode and writes a new version.');
  }
  if (picks?.changed) {
    return `<div class="r-ask"><div class="r-q"><span class="dot"></span>You changed ${picks.changed === 1 ? 'one pick'
        : `${picks.changed} picks`}. Claude gets your picks and writes a new version.</div>
      <div class="r-buttons"><button class="button main r-picks">Send Back with My Picks</button>
        <button class="button r-claude-picks">Use Claude's Picks</button></div></div>`;
  }
  const how = planApproveHow(w, s, r);
  if (how?.going) return '<div class="r-ask"><div class="r-q">Approving…</div></div>';
  // Notes of yours kept for it since the reader last left it: Send back… opens its box with them.
  const kept = state.planKept[r.sessionId]?.id === ask.id ? ' Your notes for it are kept: Send back… opens them.' : '';
  const back = '<button class="button r-revise">Send back…</button><button class="button r-stop">Stop</button>';
  if (how?.approve) {
    const refused = how.why ? ` Not approved: ${esc(how.why)}` : '';
    // Read folded, as at a glance, Approve says it's for all of it, the parts you haven't opened too.
    const whole = core.plans?.folded(s.sessionId, how.id)
      ? '<div class="r-whole">Approves the whole plan, folded parts too</div>' : '';
    return `<div class="r-ask"><div class="r-q"><span class="dot"></span>Claude is waiting for your OK on this plan.${
      refused}${kept}
      </div>${whole}<div class="r-buttons"><button class="button main r-approve" data-ask="${esc(how.id)}"
        data-digest="${esc(how.digest)}">Approve</button>${back}
        <button class="button r-go">Take me there</button></div></div>`;
  }
  const why = how?.why ? (how.refused ? ` Not approved: ${esc(how.why)}` : ` ${esc(how.why)}`) : '';
  return `<div class="r-ask"><div class="r-q"><span class="dot"></span>Claude is waiting for your OK on this plan.${why}${
    kept}
    </div>
    <div class="r-buttons"><button class="button main r-go">Take me there</button>${back}</div></div>`;
}

// The box for your notes, under what it says they do (`says`): your notes for the version before, to copy, above it;
// your picks' words, which go first, above it too; Send to Claude while there's something to send. A plain function.
function planNotesBoxHTML(r, s, unsent, picked, says) {
  const ready = planNotesMessage(r, s) ? '' : ' disabled';
  return `<div class="r-ask">${unsent ? `<div class="r-q">Your notes for the version before, to copy:</div>
      <p class="r-picked r-unsent">${esc(unsent)}</p>` : ''}<label class="r-q" for="r-notes">${esc(says)}</label>${picked
      ? `<p class="r-picked">${esc(picked)}</p>` : ''}
    <textarea id="r-notes" class="field q-type r-notes" placeholder="Your notes for Claude">${esc(r.notes)}</textarea>
    <div class="r-buttons"><button class="button main r-send"${ready}>Send to Claude</button>
      <button class="button r-cancel">Cancel</button></div></div>`;
}

// Under a plan whose notes you sent to be typed into its session (r.sent 'typed', at r.typedAt), as its row says that
// went (core.planAsks' `typed`; one said before your latest press is taken as still typing): typing; typed, Claude
// writing a new version; or not, with why, the way past the terminal's reason where there's one, Take me there, and
// Send back… again, your notes kept for it. A plain function.
function typedHTML(w, s, r) {
  const went = core.planAsks.map((by) => by.typed?.(s, w.id)).find(Boolean);
  const state = went && went.at >= (r.typedAt?.[w.id] || 0) ? went.state : 'typing';
  if (state === 'typed') {
    return '<div class="r-done">Typed into its session as a message, with your notes. Claude writes a new version, '
      + 'which shows up here.</div>';
  }
  if (state !== 'notTyped') return '<div class="r-ask"><div class="r-q">Typing your notes into its session…</div></div>';
  const way = went.way ? `<button class="button r-way">${esc(went.way)}</button>` : '';
  return `<div class="r-ask"><div class="r-q"><span class="dot"></span>Your notes weren't typed in: ${
    esc(planSentence(went.why || 'they couldn\'t go in'))} They're kept: Send back… opens them.</div>
    <div class="r-buttons"><button class="button main r-go">Take me there</button>${way}
      <button class="button r-revise">Send back…</button></div></div>`;
}

// Under a plan you approved here, as its row says it went (planYours, for the request approved: r.approved): taken once
// its transcript says approved; not taken, approved in its tab or not at all, with the way there, as the request is
// gone and only its tab can answer it now; else waiting for Claude to take it. A plain function.
function approvedHTML(w, s, r) {
  const mine = planYours(s, r.approved?.[w.id]);
  if (mine === 'notTaken') {
    return `<div class="r-ask"><div class="r-q"><span class="dot"></span>Not approved: your approval wasn't taken, so
        approve it in its tab.</div>
      <div class="r-buttons"><button class="button main r-go">Take me there</button></div></div>`;
  }
  return `<div class="r-done">${w.status === 'approved' || mine === 'approved'
    ? 'Approved. Claude carries out the plan.' : 'Approved, waiting for Claude to take it.'}</div>`;
}

// Your press on Approve: the request and the digest drawn with it go to the app, never the request as it is now, so a
// press meant for one version never approves the next. Not while it's only just been drawn, nor twice. The bar says
// "Approving…" until the rows say how it went (planApprovalsFrom), kept with what the ask said of the last press
// (`after`), so only a newer word ends it.
function approvePressed(button) {
  const s = readerSession(), id = button.dataset.ask, digest = button.dataset.digest;
  if (!s || !id || !digest || justShown('approve:' + id) || state.planApproving[s.sessionId]?.id === id) return;
  const ask = planAskOf(s);
  if (!ask) return;  // no plan waiting there any more: nothing to approve
  keepInPlace(s.sessionId);
  state.planApproving[s.sessionId] = { id, after: ask.id === id ? ask.approval?.at ?? 0 : 0 };
  ask.by.approve(s, id, digest);
  drawAnswer(state.reading, s);
  fitReader();
}

// How each Approve the app has went, as the newest rows say, before the list is drawn: not approved, a newer word on
// its ask (`approval`), which the bar shows from there; approved, the request gone and the row answered by you for it
// (planYours), which its row says as for any request answered here (answered: 'approved'), and
// the bar too; gone some other way, nothing more. The sessions whose press ended. Changes state.planApproving.
function planApprovalsFrom(sessions) {
  const ended = [];
  for (const [sid, going] of Object.entries(state.planApproving)) {
    const s = sessions.find((x) => x.sessionId === sid), ask = planAskOf(s);
    if (ask?.id === going.id && (ask.approval?.at ?? 0) === going.after) continue;
    delete state.planApproving[sid];
    ended.push(sid);
    if (ask?.id === going.id || !planYours(s, going.id)) continue;
    answered(going.id, 'approved');
    const r = state.reading;
    if (r?.mode === 'writings' && r.sessionId === sid && r.drawnPlan?.id === going.id) {
      r.sent[r.id] = 'approve';
      (r.approved ??= {})[r.id] = going.id;
    }
  }
  return ended;
}
core.updating.push((sessions) => { planApprovalsFrom(sessions); });

// ---- Presses ----

// What goes back to Claude from the box: your picks' words, then your own. A plain function.
function planNotesMessage(r, s) {
  const ask = planAskOf(s), picks = ask ? core.plans?.picks(ask.id) : null;
  return [picks?.changed ? picks.note : '', r.notes.trim()].filter(Boolean).join('\n\n');
}

// A plan sent back with your notes, or stopped. Answered elsewhere while the box was open, or a new version asked
// since your notes were written, the bar says so, with your notes to copy, and Take me there goes to its session.
function sendPlanAnswer(how) {
  const r = state.reading, s = readerSession(), left = s && transcriptPlan(s);
  if (left && !left.held && left.id === r.id && how === 'revise' && !planNotesStale(r, s)) return typePlanNotes(r, s, left);
  const w = waitingPlan(s), ask = planAskOf(s);
  if (!w || w.id !== r.id || !ask?.answerable || planNotesStale(r, s)) {
    if (!r.revising || !s) return;
    planNotesUnsent(r);
    const shown = writingsOf(s).find((x) => x.id === r.id);
    putHTML(reader.querySelector('.r-answer'), shown ? answerHTML(shown, s) : '');
    return drawReader();
  }
  const message = planNotesMessage(r, s);
  if (how === 'revise' && !message) return;
  keepInPlace(s.sessionId);  // sent with Return too, not only a press: its row stays where it is
  answered(ask.id, how === 'stop' ? 'stopped' : 'sentBack');
  r.sent[w.id] = how;
  r.revising = false;
  r.notes = '';
  wantKeyboard(false);
  if (how === 'stop') ask.by.stop(s, ask.id);
  else ask.by.sendBack(s, ask.id, message);
  core.plans?.clearPicks(ask.id);  // they went with the notes, or with the plan stopped
  putHTML(reader.querySelector('.r-answer'), answerHTML(w, s));
  drawReader();
}

// Your notes on a plan Claude still waits on with no request up here, typed into its session as a message by its
// agent's module (typeBack), on your press: kept for it meanwhile, so notes that weren't typed in come back with
// Send back…, until its row says they went in (planKeptStale).
function typePlanNotes(r, s, left) {
  const words = r.notes.trim();
  if (!words) return;
  keepInPlace(s.sessionId);
  state.planKept[r.sessionId] = { id: 'w:' + left.id, text: words };
  r.sent[left.id] = 'typed';
  (r.typedAt ??= {})[left.id] = Date.now();
  r.revising = false;
  r.notes = '';
  r.notesFor = null;
  wantKeyboard(false);
  left.by.typeBack(s, left.id, words);
  putHTML(reader.querySelector('.r-answer'), answerHTML(left, s));
  drawReader();
}

// Your notes kept for the plan they were written for (planNotesBack), put back in this box under what's there as it
// opens on that plan again, so they go with your picks.
function planKeptWords(r, s) {
  const kept = state.planKept[r.sessionId];
  if (!kept || kept.id !== planNotesTarget(s)) return;
  delete state.planKept[r.sessionId];
  r.notes = [r.notes.trim(), kept.text].filter(Boolean).join('\n\n');
}

// Your notes, kept by session for the plan they were written for as the reader closes, or turns to another session or
// view, so nothing you typed is lost: Send back… on that plan opens its box with them (planKeptWords), and the bar
// says they wait. Only for that plan, still waiting, never for whatever asks next: notes for a version no longer
// waited on are kept to copy (planNotesUnsent). They leave the reader either way.
function planNotesBack(r) {
  const s = r.session, words = r.notes?.trim(), forId = r.notesFor;
  if (words && forId && forId === planNotesTarget(s)) {
    const had = state.planKept[r.sessionId]?.id === forId ? state.planKept[r.sessionId].text : '';
    state.planKept[r.sessionId] = { id: forId, text: [had, words].filter(Boolean).join('\n\n') };
    r.notes = '';
    r.notesFor = null;
  } else if (words) planNotesUnsent(r);
}

// Notes kept for a version of the plan Claude no longer waits on (answered elsewhere, or a new version asked since),
// moved to those kept to copy, with their picks' words, so they're shown rather than left where nothing shows them.
function planKeptStale(r, s) {
  const kept = state.planKept[r.sessionId];
  if (!kept || kept.id === planNotesTarget(s)) return;
  // Notes typed in for a plan, as its row says: they've gone, so nothing is left to keep.
  const typed = kept.id.startsWith('w:')
    && core.planAsks.map((by) => by.typed?.(s, kept.id.slice(2))).find(Boolean)?.state === 'typed';
  if (typed) {
    delete state.planKept[r.sessionId];
    return;
  }
  const picks = core.plans?.picks(kept.id);
  const words = [picks?.changed ? picks.note : '', kept.text].filter(Boolean).join('\n\n');
  state.planUnsent[r.sessionId] = [state.planUnsent[r.sessionId], words].filter(Boolean).join('\n\n');
  delete state.planKept[r.sessionId];
}

// Whether your notes were written for a version of the plan Claude no longer waits on: answered elsewhere, or a new
// version asked since, which they'd otherwise go to without the picks they were written with. A plain function.
const planNotesStale = (r, s) => !!r.notesFor && r.notesFor !== planNotesTarget(s);

// Notes that can't go now, kept by session with the picks' words they'd have gone with, and shown in the bar to copy
// until you're done with them (Done with These): never sent to another version, and never dropped.
function planNotesUnsent(r) {
  const picks = r.notesFor ? core.plans?.picks(r.notesFor) : null;
  const words = [picks?.changed ? picks.note : '', r.notes.trim()].filter(Boolean).join('\n\n');
  if (words) state.planUnsent[r.sessionId] = [state.planUnsent[r.sessionId], words].filter(Boolean).join('\n\n');
  const answer = reader.querySelector('.r-answer');
  if (r.revising && answer?.contains(document.activeElement)) document.activeElement.blur();
  if (r.revising) wantKeyboard(false);
  r.revising = false;
  r.notes = '';
  r.notesFor = null;
}

// The box for your notes, with the keyboard, its cursor at the end of what you wrote there before. While it's open
// the plan's card holds your picks, so the words above the box say every pick that goes.
function openPlanNotes() {
  const r = state.reading, s = readerSession();
  if (planNotesStale(r, s)) planNotesUnsent(r);
  r.revising = true;
  r.notesFor = planNotesTarget(s);  // whose notes these are, for keeping them (planNotesBack)
  if (r.sent[r.id] === 'typed') delete r.sent[r.id];  // Send back… again, after notes that weren't typed in
  planKeptWords(r, s);
  const answer = reader.querySelector('.r-answer');
  putHTML(answer, answerHTML(waitingPlan(s) || transcriptPlan(s), s));
  drawView();
  fitReader();
  wantKeyboard(true);
  const box = answer.querySelector('textarea');
  box?.focus({ preventScroll: true });
  box?.setSelectionRange(box.value.length, box.value.length);
}

core.readerPresses.push(
  ['.r-item[data-wid]', (item) => {
    state.reading.id = item.dataset.wid;
    state.reading.revising = false;
    putHTML(reader.querySelector('.r-answer'), '');
    drawReader();
  }],
  ['.r-open[data-url]', (b) => native({ type: 'openPR', url: b.dataset.url })],
  ['.r-outside', () => native({ type: 'prototype', action: 'outside', sessionId: state.reading.sessionId,
                                id: state.reading.id })],
  ['.r-go', () => { const s = readerSession(); closeReader(); if (s) openSession(s); }],
  // The way past the terminal's reason your notes weren't typed in (the send part's, through the core): the terminal
  // takes it, and the row says how it went.
  ['.r-way', () => { const s = readerSession(); if (s) native({ type: 'wayPast', sessionId: s.sessionId }); }],
  ['.r-unsent-done', () => {
    delete state.planUnsent[state.reading.sessionId];
    putHTML(reader.querySelector('.r-answer'), '');
    drawReader();
  }],
  ['.r-revise', () => openPlanNotes()],
  ['.r-picks', () => openPlanNotes()],
  ['.r-claude-picks', () => {
    core.plans?.clearPicks(planAskOf(readerSession())?.id);
    drawReader();
  }],
  // Your picks and your words are kept: the picks are only held while the box is open.
  ['.r-cancel', () => {
    state.reading.revising = false;
    wantKeyboard(false);
    putHTML(reader.querySelector('.r-answer'), '');
    drawReader();
  }],
  ['.r-send', (b) => { if (!b.disabled) sendPlanAnswer('revise'); }],
  ['.r-stop', () => sendPlanAnswer('stop')],
  ['.r-approve', (b) => approvePressed(b)],
);

reader.addEventListener('input', (e) => {
  if (!e.target.classList.contains('r-notes') || !state.reading) return;
  state.reading.notes = e.target.value;
  const send = reader.querySelector('.r-send');
  if (send) send.disabled = !planNotesMessage(state.reading, readerSession());
});
// ⌘Return sends the notes; Return alone starts a new line, as notes can run to several.
reader.addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && e.metaKey && e.target.classList.contains('r-notes')) {
    e.preventDefault();
    sendPlanAnswer('revise');
  }
});

// ---- What it plugs into ----

// Your notes for a version of a plan Claude no longer waits on, by session, to copy (planNotesUnsent), and those for
// the one it waits on, kept for its Send back… once the reader has left it ({ id, text }, planNotesBack); your Approve
// of the plan a session waits on, by session: { id, after } of the request while the app has it, until the rows say how
// it went (planApprovalsFrom); and what each row's button for a plan or a look last opened (askActOf). Forgotten with
// the session.
moduleState({ planUnsent: {}, planKept: {}, planApproving: {}, wrActs: {} });
core.forgotten.keys.push('planUnsent', 'planKept', 'planApproving', 'wrActs');
core.forgotten.prefixes.push('wr-act', 'approve');

// The reader's mode. What it keeps on the reader (state.reading): the writings' texts as the app read them, by id; the
// plans answered from here; whether notes are being written for one, and the notes; what's drawn now (drawView); the
// prototype the app shows (proto); and the width the reader was last laid out at.
core.readerModes.writings = {
  draw: drawWritings,
  wide: (r, s) => writingsOf(s).find((x) => x.id === r.id)?.kind === 'prototype',
  contentHeight: (page) => (page?.classList.contains('r-proto') ? PROTOTYPE_HEIGHT : undefined),
  shown(r) {
    r.reads ??= {};
    r.sent ??= {};
    r.notes ??= '';
    r.revising = false;
  },
  reset(r) {
    planNotesBack(r);
    r.shown = null;
    leavePrototype();
  },
  laidOut(r, width) {
    r.laidOutWidth = width;
    placePrototype();
  },
  closed(r) {
    planNotesBack(r);
    leavePrototype();
  },
};

// While the reader is open on a plan Claude waits on, it's being answered here: the app is told, every 10s at most, so
// no session you allow answers it for you meanwhile (and the app holds it only while you're at the Mac).
let planHeldAt = 0;
core.updates.push(() => {
  const r = state.reading, s = r && readerSession(), w = s && waitingPlan(s), ask = planAskOf(s);
  if (!w || w.id !== r.id || !ask?.answerable || Date.now() - planHeldAt < 10000) return;
  planHeldAt = Date.now();
  ask.by.hold(s, ask.id);
});

// What a row's ask for a plan or a look (row.askWant) opens beside the list, if this module has it: 'plan' while
// Claude waits on a plan there, opened at that plan, its request's while one is up, else one its session still waits
// on with no request up here (transcriptPlan), else, while the session is at work, the newest it showed you that
// wasn't approved, only to read (workingPlan); one the panel can't answer is read here and answered in the session,
// as the words under it say; 'look' at the session's newest prototype. Anything else is left to the ask's own button
// (a team's approve of a merge or a commit, say), which takes you to the session. { w, icon, tip } or null. A plain
// function.
function askActOf(s, want) {
  let w = null, onlyRead = false;
  if (want === 'plan') {
    const ask = planAskOf(s), left = !ask && transcriptPlan(s), working = !ask && !left && workingPlan(s);
    w = ask ? waitingPlan(s) : left || working;
    onlyRead = ask ? !ask.answerable : !!left?.held;
    if (working) return { w, icon: PLAN_ICON, tip: 'Read the plan, beside the list: Claude is working in its session' };
  } else if (want === 'look') w = writingsOf(s).find((x) => x.kind === 'prototype') || null;
  if (!w) return null;
  if (want === 'look') return { w, icon: PROTOTYPE_ICON, tip: 'See the looks, beside the list' };
  return { w, icon: PLAN_ICON, tip: onlyRead ? 'Read the plan, beside the list: answer it in its session'
    : 'Read the plan, beside the list' };
}
// That button, at the ask's end; its press waits to be seen each time what it opens changes (`wr-act:<session>`).
core.slots.askAct.push((row) => {
  const sid = row.s.sessionId, a = askActOf(row.s, row.askWant), key = a ? `${a.w.id}@${a.w.at}` : '';
  if ((state.wrActs[sid] || '') !== key) {
    if (key) {
      state.wrActs[sid] = key;
      state.shownAt['wr-act:' + sid] = Date.now();
    } else delete state.wrActs[sid];
  }
  return a ? askActHTML(a.icon, a.tip, ` data-wr-act="${esc(sid)}" data-wid="${esc(a.w.id)}"`) : '';
});
core.presses.push(['[data-wr-act]', (el, e) => {
  e.preventDefault();
  const sid = el.dataset.wrAct;
  if (!justShown('wr-act:' + sid)) openReader(sid, el.dataset.wid, 'writings');
}]);
core.pointerTargets.push('[data-wr-act]');

// The row's tag, after its name, on a short row as on a whole one, as what the session wrote is on its tag alone;
// pressed, the reader opens on that session's writings, or closes.
core.slots.name.push((row) => writingsTag(row.s));
core.slots.brief.push((row) => writingsTag(row.s));
core.presses.push(['.wtag[data-writings]', (tag, e) => {
  e.preventDefault();
  toggleReader(tag.dataset.writings, tag.dataset.wid);
}]);
core.pointerTargets.push('.wtag');
core.swaps.push('.wtag');
