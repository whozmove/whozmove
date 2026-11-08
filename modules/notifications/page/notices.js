// What the notifications module does on the page: it takes what the app gathered (setNotices: every module's notices,
// with where the panel is), runs the decider (decide.js) with each update, as the panel folds and opens and as you
// press, and fills each place with what it picks: the line under the header (core.places.line, notice-line.js), and
// beside the folded panel the notices naming a session, as that session's chat (core.places.besideFold, chats.js),
// which tells it what went back, what you pinned and when you let go (core.notices), and how many of those need you to
// Whozmove beside the panel at its edge (core.places.besideEdge, parts/beside). Beside what the app gathered, it takes
// what the page's own senders say (core.noticeSenders), made from what only the page knows. It also runs the line's
// presses: a page sender's runs its own press here, any other press or × goes to the app, which runs the sender's own,
// and +N steps to the next one here. A line that says all went well goes once it has been in sight a few seconds.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

moduleState({
  notices: [],                                      // what the app sent: [{ id, level, text, button, … }]
  // Not hidden from the menu bar; flicked off the screen's edge; quiet hours, when only what's urgent is said.
  noticesWhere: { shown: true, parked: false, quiet: false },
  noticeView: { shown: null, front: null, frontWith: [] },  // the line's: the id showing, and the one +N stepped to
  noticeDone: { id: null, since: 0 },               // a line that says all went well, and since when it's in sight
  // A page sender's notice put away (the app keeps it), by id: its since then, or { since, at, awayFor }.
  noticeAwayHere: {},
  // Beside the folded panel: what of each notice has been seen, { id: since }, so it doesn't come out again, forgotten
  // a minute after it was last listed (`listedAt`, by id, from `loadedAt` for one not listed since the page loaded), as
  // is when each one's since came (`sinceAt`); whether what was there as the page loaded has been counted so; the chat
  // held by your going where it's about; what was last put out; and whether the decider is to run again once what's
  // telling it has finished; and the place's own order of sessions, when it gives one, for the edge's count.
  besideDone: {},
  // Whether the app's rows have come (`loaded`), and what was seen before the page loaded (`keptCame`, from the app's
  // record), as nothing is decided before both; and what was last told to the app to keep (`told`).
  beside: { seeded: false, loaded: false, keptCame: false, told: null, hold: null, out: [], again: false,
            listedAt: {}, sinceAt: {}, sessions: undefined, loadedAt: Date.now() },
});
// How long a line that says all went well is in sight before it goes by itself.
const NOTICE_DONE_MS = 4000;
const NOTICE_LEVELS = new Set(core.noticeLevels);

// Where each place is in sight now: what each says of itself, and what the app sends.
function noticesInSight() {
  const sees = (place) => !!place?.inSight?.();
  return noticeSight({ line: sees(core.places.line), beside: sees(core.places.besideFold),
                       edge: sees(core.places.besideEdge) }, state.noticesWhere);
}

// While you type in the panel, or have a card open, only something urgent comes in.
const noticesTyping = () => hasKeyboard() || keepsKeyboard();

// The app's, then the page senders', each with an id of its sender's own ('one-task/waits').
const noticesListed = () => state.notices.concat(noticesHere());

// What the page's senders say now, each with its id, its sender's name and then its key ('one-task/waits'): those
// with a level there is and words.
function noticesFromHere(now) {
  const said = [];
  for (const sender of core.noticeSenders)
    for (const n of sender.notices(now) || [])
      if (NOTICE_LEVELS.has(n.level) && typeof n.text === 'string') said.push({ n, id: `${sender.from}/${n.key}` });
  return said;
}

// The session a page sender's notice is about, by its id (letters, digits, '-' and '_'), or null: one with one goes
// beside the folded panel, as that session's chat. One that says a session at all never goes on the line, so a session
// whose id it can't take never shows there as an empty line.
const noticeSession = (n) => (typeof n.session === 'string' && /^[\w-]{1,128}$/.test(n.session) ? n.session : null);

// What the page's senders say now for the line under the header, each with its own press: kept to the shape the app's
// notices have, with a × unless it says it has none (`closes: false`), and left out while its sender says you're
// looking at what it's about (`seenNow`). One put away (the app keeps which, what made it new then, and for how long:
// setNotices) is left out while it's said the same way; or, if it says what it folds to (`chip`, "3 waiting"), it
// stays as that alone, a way back to it, behind whatever else needs you.
function noticesHere() {
  const now = Date.now(), said = [];
  for (const { n, id } of noticesFromHere(now)) {
    if (n.seenNow || n.session != null) continue;
    const since = n.since ?? '';
    const one = { id, level: n.level, text: n.text, after: n.after, button: n.button, press: n.press, since,
                  closes: n.closes !== false, done: !!n.done, busy: !!n.busy, pressedWord: n.pressedWord,
                  tag: n.tag, awayFor: Number.isFinite(n.awayFor) && n.awayFor > 0 ? n.awayFor : 0,
                  answersYou: !!n.answersYou, here: true };
    if (!noticeAwayStill(state.noticeAwayHere[id], since, now)) said.push(one);
    else if (typeof n.chip === 'string')
      said.push({ ...one, level: 'know', text: n.chip, after: undefined, title: n.chipTitle, folded: true,
                  closes: false, done: false, tag: undefined });
  }
  return said;
}

function noticesDecide() {
  const view = state.noticeView;
  const picked = noticeLine(noticesListed(), { ...view, typing: noticesTyping(), night: state.noticesWhere.quiet });
  Object.assign(view, { shown: picked.line?.id || null, shownSince: picked.line?.since ?? null, front: picked.front,
                        frontWith: picked.frontWith });
  core.places.line?.show(picked.line, picked.more);
  noticesInView(picked.line);
}

// What the line shows, once it's in sight: a line that says all went well is put away after a few seconds (out of
// sight, the time doesn't count).
function noticesInView(line) {
  const done = state.noticeDone;
  if (!line || !noticesInSight().line) {
    done.id = null;
    return;
  }
  if (!line.done) {
    done.id = null;
    return;
  }
  if (done.id !== line.id) Object.assign(done, { id: line.id, since: Date.now() });
  else if (Date.now() - done.since >= NOTICE_DONE_MS) {
    done.id = null;
    noticeAway(line.id);
  }
}

// ---- The line's presses (notice-line.js) ----

// Its button: the sender's own press, a page sender's run here, the app's there; nothing while it waits.
function noticePressed(id) {
  const notice = noticesListed().find((n) => n.id === id);
  if (!notice || notice.busy) return;
  if (notice.here) return notice.press?.();
  native({ type: 'noticePress', id });
}

// Its ×: away until what makes it new changes, or its time away passes. It goes from the line at once, the next coming
// in. A page sender's is kept by the app, as it was when you saw it on the line (not as it may have changed since).
function noticeAway(id) {
  const here = noticesHere().find((n) => n.id === id);
  if (here) {
    const since = id === state.noticeView.shown ? state.noticeView.shownSince ?? here.since : here.since;
    state.noticeAwayHere[id] = here.awayFor ? { since, at: Date.now(), awayFor: here.awayFor } : since;
    native({ type: 'noticeAwayHere', id, since, awayFor: here.awayFor });
  } else {
    native({ type: 'noticeAway', id });
    state.notices = state.notices.filter((n) => n.id !== id);
  }
  noticesDecide();
}

// +N: the next one waiting.
function noticeStep() {
  const view = { ...state.noticeView, night: state.noticesWhere.quiet };
  Object.assign(state.noticeView, noticeNext(noticesListed(), view));
  noticesDecide();
}

// ---- What the app calls ----

// What's listed now, each { id, level, text, button, pressedWord, busy, closes, done, tag, answersYou, session,
// outFor }, where the panel is and whether it's quiet hours ({ shown, parked, quiet }), and the page senders' notices
// put away, each id's `since` then (or { since, at, awayFor }): each time any changes, and as the page loads.
window.setNotices = (list, where, awayHere) => {
  state.notices = (Array.isArray(list) ? list : [])
    .filter((n) => n && typeof n.id === 'string' && NOTICE_LEVELS.has(n.level) && typeof n.text === 'string');
  if (where && typeof where === 'object')
    state.noticesWhere = { shown: where.shown !== false, parked: !!where.parked, quiet: !!where.quiet };
  if (awayHere && typeof awayHere === 'object') state.noticeAwayHere = { ...awayHere };
  noticesDecide();
};

core.updates.push(noticesDecide);

// Whozmove beside the panel at its edge: how many of the notices naming a session have something new, told after each
// drawing of the list, as what its senders say of each is worked out there.
core.afterDraw.push(() => {
  const b = state.beside, now = Date.now();
  const levels = besideRows(besideNotices(now), b.sessions, b.sinceAt, now).filter((r) => r.news).map((r) => r.level);
  core.places.besideEdge?.show(edgeCount(levels, state.noticesWhere.quiet));
});
// The app's rows have come: from now on what's waiting is decided on them (besideStep's `loaded`), never on the empty
// list the page draws before them.
core.updating.push(() => { state.beside.loaded = true; });
core.collapses.push(noticesDecide);

// ---- Beside the folded panel ----

// The page senders' notices naming a session, each as the decider's row beside the folded panel (besideStep), in the
// order they're listed, before any is chosen for its session (besideRows): its since, if it has one, being what's new
// in it. Only one that says how long it's out (`outFor`) comes out there, as nothing else would say when it goes back.
function besideNotices(now) {
  const rows = [];
  for (const { n, id } of noticesFromHere(now)) {
    const sid = noticeSession(n);
    if (!sid || !(Number.isFinite(n.outFor) && n.outFor > 0)) continue;
    rows.push({ id, sid, news: typeof n.since === 'string' && /^\S{1,160}$/.test(n.since) ? n.since : null,
                level: n.level, ...(n.text ? { line: n.text } : {}), ...(Number.isFinite(n.at) ? { at: n.at } : {}),
                on: !!n.seenNow, evenSeen: !!n.evenWhenSeen, outFor: n.outFor,
                ...(Number.isFinite(n.openedAt) ? { openedAt: n.openedAt } : {}) });
  }
  return rows;
}

// The notices naming a session, as chats beside the folded panel: what the place has (what's out, how many fit, whether
// nothing may come out now, what you point at or type in) and what each notice says go through the decider
// (besideStep), and the place is told what should be out. The panel open counts, unless it's open only while the folded
// cat's list is out (peek.js): those come back out as it folds back.
function besideDecide() {
  const place = core.places.besideFold, b = state.beside;
  if (!place) return;
  const at = place.state(), now = Date.now(), listed = besideNotices(now);
  // Every notice naming a session is listed, whichever says its session's chat, so what's been seen of each is kept.
  const kept = besideListed({ done: state.besideDone, listedAt: b.listedAt, sinceAt: b.sinceAt, loadedAt: b.loadedAt },
                            listed, now);
  state.besideDone = kept.done;
  Object.assign(b, { listedAt: kept.listedAt, sinceAt: kept.sinceAt, sessions: at.sessions });
  const rows = besideRows(listed, at.sessions, b.sinceAt, now);
  // Where you last went from the panel (a notice's openedAt, the latest) holds its chat out while you're there.
  const opening = rows.filter((r) => r.openedAt !== undefined)
    .reduce((last, r) => (!last || r.openedAt > last.at ? { sid: r.sid, at: r.openedAt } : last), null);
  b.hold = besideHold(b.hold, opening, at.out, rows);
  const inTab = b.hold.sid ? [b.hold.sid] : [];
  const holding = at.out.some((c) => at.pointed.includes(c.sid) || inTab.includes(c.sid));
  const open = (!document.body.classList.contains('collapsed') && !state.peek.open) || state.cat.arriving;
  const next = besideStep({ out: at.out, queue: at.queue, done: state.besideDone, seeded: b.seeded }, rows,
                          { loaded: b.loaded && b.keptCame, open, quiet: at.quiet, night: state.noticesWhere.quiet,
                            holding, most: at.most });
  state.besideDone = next.done;
  Object.assign(b, { seeded: next.seeded, out: next.out });
  place.show({ ...next, inTab, holding, open });
  besideKeep();
}

// What's been seen (and what's out) is kept by the app for a restart, told each time it changes.
function besideKeep() {
  const b = state.beside;
  if (!b.seeded) return;
  const seen = besideKept(state.besideDone, b.out), told = JSON.stringify(seen);
  if (told === b.told) return;
  b.told = told;
  native({ type: 'besideSeen', seen });
}

// What was seen beside the folded panel before the page loaded, from the app's record, as the page loads: it's what's
// already there, so only what's new since comes out, what came while Whozmove was down among it. Null on a first launch,
// when what's there as the rows come is taken as already there.
window.setBesideSeen = (seen) => {
  const b = state.beside;
  if (seen && typeof seen === 'object' && !b.seeded) {
    state.besideDone = Object.fromEntries(Object.entries(seen).filter(([, news]) => typeof news === 'string'));
    b.seeded = true;
  }
  b.keptCame = true;
  besideDecide();
};

// What a place says runs the decider again once it has finished saying it (several chats' time can run out at once).
function besideSoon() {
  if (state.beside.again) return;
  state.beside.again = true;
  queueMicrotask(() => {
    state.beside.again = false;
    besideDecide();
  });
}

Object.assign(core.notices, {
  // A chat gone back into the cat, by its session: by its × ('closed') or its time running out ('expired'), what it
  // said counts as seen.
  back(sid, why) {
    if (why === 'closed' || why === 'expired')
      state.besideDone = besideBack({ out: state.beside.out, done: state.besideDone }, sid).done;
    besideSoon();
  },
  pin: besideSoon,
  holding: besideSoon,
  again: besideDecide,
  // A page sender's notices changed (One Task opened or closed, or what waits): the line decides again now, not at
  // the next update.
  said: noticesDecide,
});
