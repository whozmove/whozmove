// What a session wrote for you to read (its plans, prototypes and notes): the tag on its row, and the reader's
// "writings" mode, where a plan Claude is waiting on can be sent back with your notes, or stopped.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// Pressing a row's tag opens the reader beside the list (reader.js), with everything the session wrote down its side,
// newest first. Approving a plan happens in the session, unless you've let a session approve plans for you (May
// Approve Plans).

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
function askedPlan(listed, ask) {
  return listed.find((w) => w.kind === 'plan' && w.status === 'waiting' && w.at <= ask.at + 60000
                            && ask.at - w.at < ASKED_WITHIN_MS) || null;
}

// A session's writings as the reader lists them. A plan Claude has only just asked about is there at once, from
// its request, before the transcript's next read lists it (`fromAsk`).
function writingsOf(s) {
  const listed = s?.writings || [];
  const ask = s?.ask?.tool === 'ExitPlanMode' ? s.ask : null;
  if (!ask || askedPlan(listed, ask)) return listed;
  const plan = String(ask.input?.plan || '');
  return [{ id: 'ask:' + ask.id, kind: 'plan', title: (plan.match(/^\s*#+\s*(.+)$/m) || [])[1] || 'Plan',
            path: ask.input?.planFilePath, at: ask.at, status: 'waiting', fromAsk: plan }, ...listed];
}

// The plan Claude is waiting on now, while its request is up.
function waitingPlan(s) {
  if (s?.ask?.tool !== 'ExitPlanMode') return null;
  const all = writingsOf(s);
  return all.find((w) => w.id === 'ask:' + s.ask.id) || askedPlan(all, s.ask);
}

// The row's tag, quietly: the icon of the plan waiting for you, or else of the newest thing written, and how many
// things it wrote. A plan waiting for you is in the plan's colour. It shows as pressed while the reader is open on its
// session, as pressing it again closes it.
function writingsTag(s) {
  const all = writingsOf(s);
  if (!all.length) return '';
  const waiting = waitingPlan(s), lead = waiting || all[0];
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
  return waitingPlan(s)?.id === w.id ? ['Waiting for you', 'wait'] : ['No answer', ''];
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
  const all = writingsOf(s);
  if (!all.some((w) => w.id === r.id) && all.length) r.id = (waitingPlan(s) || all[0]).id;
  const w = all.find((x) => x.id === r.id);
  // The list's update comes every second: only what changed is put in, so hover effects and the layout aren't redone
  // each time, and the panel is measured again only then.
  const head = `<span class="r-title">${esc(s.name || base(s.cwd))}</span>
    <span class="r-sub">${all.length} written in this session</span>
    <button class="icon-button r-close" title="Close">${CLOSE_ICON}</button>`;
  let changed = putHTML(reader.querySelector('.r-head'), head);
  changed = putHTML(reader.querySelector('.r-shelf'), shelfHTML(s, all, r.id)) || changed;
  const answer = reader.querySelector('.r-answer');
  if (!answer.contains(document.activeElement)) changed = putHTML(answer, w ? answerHTML(w, s) : '') || changed;
  drawView();
  if (!changed) return;
  fitReader();
  syncHover();
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
  let read;
  if (w.fromAsk !== undefined) read = { text: w.fromAsk };
  else {
    if (r.reads[w.id]?.at !== w.at) {
      r.reads[w.id] = { at: w.at };
      native({ type: 'readWriting', sessionId: s.sessionId, id: w.id });
    }
    read = r.reads[w.id];
    if (read.text === undefined && !read.missing) read = null;  // asked, not back yet
  }
  // A plan is drawn again as whether it can take your picks changes, where you were in it kept.
  const same = `${w.id}@${w.at}@${read?.text?.length ?? read?.missing ?? 'wait'}`;
  const how = planHow(w, s, r), key = `${same}@${how.waiting}@${how.held}`;
  if (r.shown === key) return;
  const kept = r.shown?.startsWith(`${same}@`) ? body.scrollTop : 0;
  r.shown = key;
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
  const asked = w.kind === 'plan' && waitingPlan(s)?.id === w.id && !!s.ask;
  const waiting = asked && !s.ask.legacy && !r.sent?.[w.id];
  return { id: asked ? s.ask.id : w.id, waiting, held: waiting && !!r.revising };
}

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

// Under a plan Claude is waiting on: approving happens in the session; sending it back with notes, or stopping it,
// happens here, down the permission hook's line to the panel (answerAsk). A plan from a session started before
// Whozmove's update is answered in the session only, as its row says.
function answerHTML(w, s) {
  const r = state.reading, sent = r.sent[w.id];
  if (sent) return `<div class="r-done">${sent === 'stop' ? 'Stopped. Claude won\'t carry out this plan.'
    : 'Sent back to Claude with your notes. It stays in plan mode and writes a new version, which shows up here.'}</div>`;
  // While the version shown is the one Claude waits on, its own Send back… and Stop stay too: Send back… opens its
  // box with these notes above it, to copy from, so moving on never needs Done with These first.
  const unsent = w.kind === 'plan' && state.planUnsent[r.sessionId];
  if (unsent && !r.revising) {
    const answerable = waitingPlan(s)?.id === w.id && !s.ask?.legacy;
    return `<div class="r-ask"><div class="r-q">Claude isn't waiting on the version your notes were for any more: it was
        answered elsewhere, so they weren't sent. Here they are, to copy into what you send next:</div>
      <p class="r-picked r-unsent">${esc(unsent)}</p>
      <div class="r-buttons"><button class="button main r-go">Take me there</button>${answerable
        ? '<button class="button r-revise">Send back…</button><button class="button r-stop">Stop</button>' : ''}
        <button class="button r-unsent-done">Done with These</button></div></div>`;
  }
  if (waitingPlan(s)?.id !== w.id) return '';
  if (s.ask?.legacy) {
    return `<div class="r-ask"><div class="r-q"><span class="dot"></span>Claude is waiting for your OK on this plan.
        Answer it in the session: it started before Whozmove's update, so the panel can't answer it.</div>
      <div class="r-buttons"><button class="button main r-go">Take me there</button></div></div>`;
  }
  // Picks of yours on its card that differ from Claude's (the plans module's) go back as notes: in the box, above
  // your own words, to read first.
  const picks = core.plans?.picks(s.ask.id);
  if (r.revising) {
    const picked = picks?.changed ? picks.note : '', ready = planNotesMessage(r, s) ? '' : ' disabled';
    const ask = picked ? 'Your picks go back in these words, and Claude writes a new version. Add anything else:'
      : `What should change? Claude stays in plan mode and
        writes a new version.`;
    return `<div class="r-ask">${unsent ? `<div class="r-q">Your notes for the version before, to copy:</div>
        <p class="r-picked r-unsent">${esc(unsent)}</p>` : ''}<label class="r-q" for="r-notes">${ask}</label>${picked
        ? `<p class="r-picked">${esc(picked)}</p>` : ''}
      <textarea id="r-notes" class="field q-type r-notes" placeholder="Your notes for Claude">${esc(r.notes)}</textarea>
      <div class="r-buttons"><button class="button main r-send"${ready}>Send to Claude</button>
        <button class="button r-cancel">Cancel</button></div></div>`;
  }
  if (picks?.changed) {
    return `<div class="r-ask"><div class="r-q"><span class="dot"></span>You changed ${picks.changed === 1 ? 'one pick'
        : `${picks.changed} picks`}. Claude gets your picks and writes a new version.</div>
      <div class="r-buttons"><button class="button main r-picks">Send Back with My Picks</button>
        <button class="button r-claude-picks">Use Claude's Picks</button></div></div>`;
  }
  return `<div class="r-ask"><div class="r-q"><span class="dot"></span>Claude is waiting for your OK on this plan.
      Approving happens in the session.</div>
    <div class="r-buttons"><button class="button main r-go">Take me there</button><button class="button r-revise">Send back…</button>
      <button class="button r-stop">Stop</button></div></div>`;
}

// ---- Presses ----

// What goes back to Claude from the box: your picks' words, then your own. A plain function.
function planNotesMessage(r, s) {
  const picks = s?.ask ? core.plans?.picks(s.ask.id) : null;
  return [picks?.changed ? picks.note : '', r.notes.trim()].filter(Boolean).join('\n\n');
}

// A plan sent back with your notes, or stopped. Answered elsewhere while the box was open, or a new version asked
// since your notes were written, the bar says so, with your notes to copy, and Take me there goes to its session.
function sendPlanAnswer(how) {
  const r = state.reading, s = readerSession(), w = waitingPlan(s);
  if (!w || w.id !== r.id || !s.ask || s.ask.legacy || planNotesStale(r, s)) {
    if (!r.revising || !s) return;
    planNotesUnsent(r);
    const shown = writingsOf(s).find((x) => x.id === r.id);
    putHTML(reader.querySelector('.r-answer'), shown ? answerHTML(shown, s) : '');
    return drawReader();
  }
  const message = planNotesMessage(r, s);
  if (how === 'revise' && !message) return;
  keepInPlace(s.sessionId);  // sent with Return too, not only a press: its row stays where it is
  answered(s.ask.id, how === 'stop' ? 'stopped' : 'sentBack');
  r.sent[w.id] = how;
  r.revising = false;
  r.notes = '';
  wantKeyboard(false);
  native({ type: 'answerAsk', id: s.ask.id, allow: false, ...(how === 'stop' ? { stop: true } : { message }) });
  core.plans?.clearPicks(s.ask.id);  // they went with the notes, or with the plan stopped
  putHTML(reader.querySelector('.r-answer'), answerHTML(w, s));
  drawReader();
}

// What you typed in the plan's box on its row (the Claude Code module's), put in this box under what's there, from
// either way in (the row's Send back…, the bar's Send Back with My Picks), so it goes with your picks.
function planRowWords(r, s) {
  const typed = s?.ask ? core.planRowNotes?.take(s.ask.id) : '';
  if (typed?.trim()) r.notes = [r.notes.trim(), typed.trim()].filter(Boolean).join('\n\n');
}

// Your notes, given back to the row of the plan they were written for as the reader closes, or turns to another
// session or view, where they wait (the reader keeps nothing once it's gone), so nothing you typed is lost; and only
// to that plan, still waiting, never to whatever asks next: notes for a version no longer waited on are kept to copy
// (planNotesUnsent). They leave the reader either way.
function planNotesBack(r) {
  const s = r.session, words = r.notes?.trim(), forId = r.notesFor;
  if (words && forId && s?.ask?.id === forId && !s.ask.legacy) {
    core.planRowNotes?.keep(forId, words);
    r.notes = '';
    r.notesFor = null;
  } else if (words) planNotesUnsent(r);
}

// Whether your notes were written for a version of the plan Claude no longer waits on: answered elsewhere, or a new
// version asked since, which they'd otherwise go to without the picks they were written with. A plain function.
const planNotesStale = (r, s) => !!r.notesFor && r.notesFor !== (s?.ask?.legacy ? null : s?.ask?.id);

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
  r.notesFor = s?.ask?.id ?? null;  // whose notes these are, for giving them back (planNotesBack)
  planRowWords(r, s);
  const answer = reader.querySelector('.r-answer');
  putHTML(answer, answerHTML(waitingPlan(s), s));
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
  ['.r-unsent-done', () => {
    delete state.planUnsent[state.reading.sessionId];
    putHTML(reader.querySelector('.r-answer'), '');
    drawReader();
  }],
  ['.r-revise', () => openPlanNotes()],
  ['.r-picks', () => openPlanNotes()],
  ['.r-claude-picks', () => {
    core.plans?.clearPicks(readerSession()?.ask?.id);
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

// Your notes for a version of a plan Claude no longer waits on, by session, to copy (planNotesUnsent), forgotten with
// the session.
moduleState({ planUnsent: {} });
core.forgotten.keys.push('planUnsent');

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

// The plan Claude waits on in session `sid`, opened beside the list with the box for your notes open, what you typed
// on its row in it, under your picks: the row's Send back… while picks of yours differ from Claude's, as only this box
// sends them (planNotesMessage). Where the reader can't open on it, it opens as Read the plan does.
core.planNotes = (sid) => {
  openReader(sid, null, 'writings');
  const r = state.reading, s = r?.sessionId === sid && r.mode === 'writings' && readerSession();
  const w = s && waitingPlan(s);
  if (!w || w.id !== r.id || !s.ask || s.ask.legacy) return;
  openPlanNotes();
};

// While the reader is open on a plan Claude waits on, it's being answered here: the app is told, every 10s at most, so
// no session you allow answers it for you meanwhile (and the app holds it only while you're at the Mac).
let planHeldAt = 0;
core.updates.push(() => {
  const r = state.reading, s = r && readerSession(), w = s && waitingPlan(s);
  if (!w || w.id !== r.id || !s.ask || s.ask.legacy || Date.now() - planHeldAt < 10000) return;
  planHeldAt = Date.now();
  native({ type: 'holdAsk', id: s.ask.id });
});

// The row's tag, after its name; pressed, the reader opens on that session's writings, or closes.
core.slots.name.push((row) => writingsTag(row.s));
core.presses.push(['.wtag[data-writings]', (tag, e) => {
  e.preventDefault();
  toggleReader(tag.dataset.writings, tag.dataset.wid);
}]);
core.pointerTargets.push('.wtag');
core.swaps.push('.wtag');
