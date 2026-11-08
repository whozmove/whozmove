// The requests waiting on you: a tool waiting for your OK, a question, a plan, or a session asking in its own app. One
// that comes while you aren't answering another is brought into view, the list scrolling until its row shows whole
// (from its top, where it's taller than the list's visible part), and the newest takes the place of any before it.
// While you're answering one (its card has your keys, or you're typing in one of its boxes), or the pointer is on the
// panel, the list doesn't move by itself, and once you've scrolled it by hand, it stays where you put it. Each of the
// list's edges with one wholly out of sight past it has a strip held there naming the one nearest it, until it's
// answered or any of its row is back in view, which a press scrolls to; at an edge, the strip and the copy of the row
// you're on keep the list's order. Once you've answered one here, the list goes to the one waiting longest. And the
// card you're on, or pointing at, stays where it is as rows move round it (a row going in above it, as a message takes
// its row to the top): the list scrolls with it. The plain functions come first, which tests/panel.sh checks.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// What to do about the requests waiting on you, as the list is drawn or scrolled. `waiting` is them, the one waiting
// longest first, each { id, fresh, inView, edge, gone, y }: whether it has yet to be seen or brought into view, whether
// its row shows whole, which edge of the list's visible part it's past ('top' or 'bottom'; null in view), which edge
// it's wholly out of sight past (null while any of it shows), and where its row is, down the list. `busy`: you're
// answering one; `pointer`: it's on the panel; `answered`: you've answered one here, and the list hasn't gone on from
// it yet; `bringing`: the id of the one the list is on its way to. Returns { bring, strips, seen }: the request to
// scroll to, the strip at each edge ({ top, bottom }: the request it names, with how many more are past that edge as
// `more`, or null), and the ids that count as seen now. Each is brought into view once at most, counting as seen as the
// list sets off to it (and those a newer one took the place of with it), so the list never goes back to one you've
// scrolled away from. Each edge with a request wholly out of sight past it has its strip, whatever has been seen, for
// as long as one waits there, naming the one nearest it: the lowest of those above, the highest of those below. One
// with any of its row in view has none, so a request never shows twice.
function waitingNext(waiting, { busy, pointer, answered, bringing = null }) {
  const away = waiting.filter((w) => !w.inView), fresh = waiting.filter((w) => w.fresh);
  let bring = null, seen = busy ? [] : fresh.filter((w) => w.inView);
  if (answered && !busy) bring = away[0] || null;
  else if (!busy && !pointer) {
    bring = fresh.filter((w) => !w.inView).pop() || null;  // the newest: it takes the place of those before it
    if (bring) seen = fresh;
  }
  if (bring && !seen.includes(bring)) seen = [...seen, bring];
  const rest = waiting.filter((w) => w.gone && w !== bring && w.id !== bringing), strips = {};
  for (const edge of ['top', 'bottom']) {
    const past = rest.filter((w) => w.gone === edge);
    const near = past.reduce((n, w) => (!n || (w.y > n.y) === (edge === 'top') ? w : n), null);
    strips[edge] = near && { ...near, more: past.length - 1 };
  }
  return { bring, strips, seen: seen.map((w) => w.id) };
}

// One look at the requests waiting, keeping in `ws` what it needs from one look to the next ({ answerAt, answered,
// bringing }). `lastAnswer`: when the last answer given here was; `card`: you're on a card that waits, its keys yours
// or typing in one of its boxes; `keys`: the panel holds the keyboard; `settled`: the rows have stopped moving;
// `pointer`: it's on the panel. An answer is kept in mind until the list has gone on from it, whatever is drawn in
// between, and is acted on only once the rows have stopped (the answered card going), as only then is what's in view
// where it'll stay. Just after an answer, the keys the panel still holds don't count as answering another: only a card
// you're on does.
function waitingLook(ws, waiting, { lastAnswer, card, keys, settled, pointer }) {
  if (lastAnswer > ws.answerAt) {
    ws.answerAt = lastAnswer;
    ws.answered = true;
  }
  const busy = card || (!ws.answered && keys), answered = ws.answered && settled;
  const next = waitingNext(waiting, { busy, pointer, answered, bringing: ws.bringing });
  if (answered && !busy) ws.answered = false;
  return { ...next, busy, answered };
}

// ---- In the list ----

const waitingEls = { top: document.getElementById('waiting-top'), bottom: document.getElementById('waiting-bottom') };

// A session's row as the list shows it, or null: not one in a folded group, nor what's left of one fading out.
function waitingRow(sid) {
  return [...document.getElementById('list').querySelectorAll('.row[data-id]')]
    .find((r) => r.dataset.id === sid && !r.closest('.prows.closed') && !r.matches('.fading')) || null;
}

// The requests waiting on you that the list shows, the one waiting longest first, each { id, sid, row }: a request is
// known by its id, and a session asking in its own app by when it started to.
function waitingRows() {
  return state.last.sessions
    .filter((s) => state.kinds[s.sessionId] === 'needs' && !(s.ask && state.answering[s.ask.id]))
    .map((s) => ({ id: s.ask?.id || `${s.sessionId}@${turnSince(s, 'needs')}`, sid: s.sessionId,
                   at: turnSince(s, 'needs'), row: waitingRow(s.sessionId) }))
    .filter((w) => w.row)
    .sort((a, b) => a.at - b.at);
}

// The list's visible part for a row, from its top to its bottom on the page: from the header's edge, wherever that has
// been pushed to, and clear of the copy of the row you're on held at an edge, unless it's that row (its band is
// measured from inside the strip, stickyInsets).
function waitingBand(row) {
  const list = document.getElementById('list'), st = state.sticky, lr = list.getBoundingClientRect();
  const top = lr.top + list.clientTop + headerInset(), bottom = lr.top + list.clientTop + list.clientHeight;
  const held = st.edge && !st.leaving && row !== st.row, inner = lr.top + st.clientTop;
  return [held && st.edge === 'top' ? inner + st.band[1] : top,
          held && st.edge === 'bottom' ? inner + st.band[0] : bottom];
}

// Which edge of the list's visible part a row is past, or null while it shows whole (or, taller than that part, starts
// at its top).
function waitingEdge(row) {
  const [a, b] = waitingBand(row), r = row.getBoundingClientRect();
  if (r.top >= a - 0.5 && (r.bottom <= b + 0.5 || r.top <= a + 0.5)) return null;
  return r.top < a ? 'top' : 'bottom';
}

// Which edge a row is wholly out of sight past, or null while any of it shows: past the list's visible part, as
// waitingBand measures it, less a strip already standing at that edge (waitingStands), so a row hidden under one counts
// as gone. The row you're on, its copy held at an edge, never is: the copy already shows it there.
function waitingGone(row) {
  const st = state.sticky;
  if (row === st.row && st.edge && !st.leaving) return null;
  const [a, b] = waitingBand(row), r = row.getBoundingClientRect();
  if (r.bottom <= a + waitingStands('top') + 0.5) return 'top';
  if (r.top >= b - waitingStands('bottom') - 0.5) return 'bottom';
  return null;
}

// How far a strip standing at an edge reaches in past where waitingBand puts that edge: all of it, unless the copy of
// the row you're on is held there with the strip outside it, where the copy's band is measured inside the strip already
// (stickyInsets). Nothing for a strip on its way out.
function waitingStands(edge) {
  const held = state.waiting.held[edge], st = state.sticky;
  if (!held || !waitingEls[edge].classList.contains('in')) return 0;
  return st.edge === edge && !st.leaving && held.outside ? 0 : held.h;
}

// The card you're answering: the one that has your keys, or the one with the box you're typing in.
function waitingBusyCard() {
  return heldCard() || document.activeElement?.closest?.('#list .perm') || null;
}

// Looks at the requests waiting as the list is drawn (`drawn`), or as it scrolls, when nothing is brought into view:
// the scroll is yours, or the panel's own on its way to one.
function waitingUpdate(drawn) {
  const ws = state.waiting;
  // Folded, turned over to its back, or with the chats beside the folded cat going into their rows: the list isn't
  // there to look at. An answer given meanwhile is still newer than the last one looked at, so it isn't lost.
  if (stillFolded() || state.turned || state.chats.flights.size) return waitingStrips(null);
  for (const id of Object.keys(ws.known)) if (!(id.split('@')[0] in state.listedAt)) delete ws.known[id];
  const card = waitingBusyCard();
  const waiting = waitingRows().filter((w) => w.id !== card?.dataset.ask).map((w) => {
    const edge = waitingEdge(w.row), gone = edge && waitingGone(w.row);
    return { ...w, fresh: !ws.known[w.id], inView: !edge, edge, gone, y: w.row.getBoundingClientRect().top };
  });
  const next = waitingLook(ws, waiting, { lastAnswer: Math.max(0, ...Object.values(state.answeredAt)), card: !!card,
                                          keys: keepsKeyboard(), settled: performance.now() >= state.settleUntil,
                                          pointer: !drawn || !!state.pointer });
  for (const id of next.seen) ws.known[id] = true;
  if (next.bring && next.bring.id !== ws.bringing) {
    waitingLog(`bringing ${next.bring.id} (${next.bring.sid}) into view${next.answered ? ', after an answer' : ''}`);
    waitingBring(next.bring);
  }
  waitingStrips(next.strips, next.busy);
}

// A line in the app's log, for what the list did by itself: ids only, never what a session asks.
function waitingLog(text) {
  native({ type: 'log', text: `waiting: ${text}` });
}

// Scrolls the list to a request's row, in one eased move, measured again each frame, and on to where it ends up as the
// list finishes moving (its card growing in), until your own scrolling takes over. What comes into view counts as only
// just shown, so a press meant for what was there doesn't land on it (justShown).
function waitingBring(w) {
  const ws = state.waiting, list = document.getElementById('list');
  cancelAnimationFrame(ws.mover);
  cancelAnimationFrame(ws.keeper);
  ws.bringing = null;
  const by = () => {
    const row = waitingRow(w.sid);
    state.shownAt[w.id] = Date.now();
    return row ? showInListBy(row) : 0;
  };
  if (calm.matches) {
    list.scrollTop += by();
    return;
  }
  const first = by(), from = list.scrollTop, start = performance.now();
  const ms = Math.min(700, 260 + Math.abs(first) * 0.6), until = Math.max(start + ms, state.settleUntil);
  const ease = (p) => (p < 0.5 ? 4 * p * p * p : 1 - (-2 * p + 2) ** 3 / 2);
  const step = (now) => {
    const p = Math.min(1, (now - start) / ms), to = list.scrollTop + by();
    list.scrollTop = from + (to - from) * ease(p);
    if (now < until) ws.mover = requestAnimationFrame(step);
    else ws.bringing = null;
  };
  ws.bringing = w.id;
  ws.mover = requestAnimationFrame(step);
}

// The card you're answering or pointing at, or the row a row's details keep still (detailsHeldRow: the one they're open
// on, or the one under the pointer as they fold), as the list is about to be drawn again: where its row is now, if
// it's on the list (a card answered in a place beside it, core.keyPlaces, keeps none here).
function waitingHold() {
  const pointed = state.pointer && pointedAt()?.closest?.('#list .perm'), still = detailsHeldRow();
  const row = (waitingBusyCard() || pointed)?.closest('#list .row[data-id]') || (still && waitingRow(still));
  state.waiting.anchor = row ? { sid: row.dataset.id, top: row.getBoundingClientRect().top } : null;
}

// Keeps that row where it was as the list moves, scrolling the list by however far it has gone, each frame until the
// list's motion is done.
function waitingKeep() {
  const ws = state.waiting, held = ws.anchor, list = document.getElementById('list');
  ws.anchor = null;
  if (!held) return;
  cancelAnimationFrame(ws.keeper);
  const until = Math.max(performance.now(), state.settleUntil);
  const step = () => {
    const row = waitingRow(held.sid);
    if (!row) return;
    const d = row.getBoundingClientRect().top - held.top;
    if (Math.abs(d) > 0.5) list.scrollTop += d;
    if (performance.now() < until) ws.keeper = requestAnimationFrame(step);
  };
  step();
}

// The strips at the list's two edges ({ top, bottom }, or none), "after this" on each while you're answering another.
function waitingStrips(strips, after) {
  for (const edge of ['top', 'bottom']) waitingStrip(edge, strips?.[edge] && { ...strips[edge], after });
}

// The strip at one of the list's edges, naming a request past it ({ id, sid, row, more, after }), or none: what its row
// says (the session's name, the card's title), "after this" while you're answering another, and how many more wait past
// that edge. Things held at an edge keep the list's order: the strip is right at the edge when its request comes before
// the row you're on in the list at the top (after it, at the bottom), and just inside that row's copy held there
// otherwise (waitingOutside), so the two never trade places.
function waitingStrip(edge, w) {
  const ws = state.waiting, el = waitingEls[edge];
  if (w && ws.next[edge]?.id !== w.id) waitingLog(`naming ${w.id} (${w.sid}) at the list's ${edge}`);
  ws.next[edge] = w ? { id: w.id, sid: w.sid, edge, outside: waitingOutside(w.row, edge) } : null;
  if (!w) {
    el.classList.remove('in');
    // The edge stays the strip's until it has slid back under it (waiting.css), so the copy of the row you're on
    // doesn't move into it as it goes.
    if (ws.held[edge] && !ws.letGo[edge]) ws.letGo[edge] = setTimeout(() => waitingHolds(edge, null), 180);
    return;
  }
  const name = w.row.querySelector('.line1 .name')?.textContent || '';
  const s = state.last.sessions.find((x) => x.sessionId === w.sid);
  const what = (s?.ask && core.agent.askLine?.(s.ask)) || s?.notice || 'Waiting on you';
  const after = [w.after && 'after this', w.more && `${w.more} more`].filter(Boolean).join(' · ');
  // Its dot as the row's, with what the session runs in the background going round it: its ring's phase is set as the
  // strip is written, which is only when what it says changes, so the ring turns on through the rest. On its band,
  // which slides in from under the edge and back under it (waiting.css).
  const html = `<div class="w-band"><div class="w-strip notice boxed needs">`
    + `<span class="dot">${s ? orbitHTML(s, false) : ''}</span>`
    + `<span class="notice-text"><b>${esc(name)}</b> <span class="w-what">${esc(what)}</span></span>`
    + `<span class="w-after">${esc(after)}</span>${CHEVRON_ICON}</div></div>`;
  if (ws.html[edge] !== html) {
    el.innerHTML = ws.html[edge] = html;
    orbitTimed(el);
  }
  waitingPlace();
  el.classList.add('in');
  waitingHolds(edge, { h: el.offsetHeight, outside: ws.next[edge].outside });
}

// Whether a request's row is further out than the row you're on, toward an edge: before it in the list for the top,
// after it for the bottom (or there's no row you're on).
function waitingOutside(row, edge) {
  const mine = state.sticky.row;
  if (!mine?.isConnected || mine === row) return true;
  const before = !!(mine.compareDocumentPosition(row) & Node.DOCUMENT_POSITION_PRECEDING);
  return edge === 'top' ? before : !before;
}

// The part of an edge the strip holds ({ h, outside }, or none), and the copy of the row you're on laid out again when
// that changes (stickyPlace).
function waitingHolds(edge, held) {
  const ws = state.waiting;
  clearTimeout(ws.letGo[edge]);
  ws.letGo[edge] = 0;
  if (ws.held[edge]?.h === held?.h && ws.held[edge]?.outside === held?.outside) return;
  ws.held[edge] = held;
  stickyPlace();
}

// How much of the list's edge (top or bottom) the strip holds outside the copy of the row you're on, for the copy to
// hold inside it (stickyInsets, sticky.js): none where the strip is the one inside.
function waitingInset(edge) {
  const held = state.waiting.held[edge];
  return held?.outside ? held.h : 0;
}

// How much of the list's edge a strip that's staying there covers: as waitingInset, but nothing for one on its way out
// (its request answered, or now the one you're typing in), whose room is let go of a moment later.
function waitingCovers(edge) {
  return waitingEls[edge].classList.contains('in') ? waitingInset(edge) : 0;
}

// Lays each strip along its edge: right at it (below the header, or at the list's foot), or, where the row you're on
// comes first in the list's order and its copy is held at that edge, just inside the copy (st.band, from where the copy
// is measured: st.clientTop).
function waitingPlace() {
  const ws = state.waiting, list = document.getElementById('list'), st = state.sticky;
  if (!ws.next.top && !ws.next.bottom) return;
  const root = list.parentElement.getBoundingClientRect(), lr = list.getBoundingClientRect();
  const top = lr.top + list.clientTop + headerInset() - root.top, v = list.clientHeight - headerInset();
  for (const edge of ['top', 'bottom']) {
    const next = ws.next[edge], el = waitingEls[edge];
    if (!next) continue;
    const inside = !next.outside && st.edge === edge && !st.leaving, from = lr.top + st.clientTop - root.top;
    const at = edge === 'top' ? (inside ? from + st.band[1] : top)
      : (inside ? from + st.band[0] : top + v) - el.offsetHeight;
    Object.assign(el.style, { left: `${lr.left + list.clientLeft - root.left}px`, width: `${list.clientWidth}px`,
                              top: `${at}px` });
  }
}

// A press on a strip scrolls to the request it names; the card that had your keys lets go of them (keyboard.js), as
// you've moved on from it.
for (const [edge, el] of Object.entries(waitingEls)) el.addEventListener('mousedown', (e) => {
  const next = state.waiting.next[edge];
  if (e.button !== 0 || !next) return;
  e.preventDefault();
  state.waiting.known[next.id] = true;
  waitingStrip(edge, null);
  waitingBring(next);
});

core.pointerTargets.push('.waiting-strip');
core.beforeDraw.push(waitingHold);
core.afterDraw.push(() => {
  waitingKeep();
  waitingUpdate(true);
});
core.starts.push(() => {
  const list = document.getElementById('list');
  list.addEventListener('scroll', () => waitingUpdate(false), { passive: true });
  // Scrolled by hand: the list stays where you put it. What it was doing by itself stops, and every request waiting
  // counts as seen, so none is brought into view after it; the strip still names one out of view.
  list.addEventListener('wheel', () => {
    const ws = state.waiting;
    cancelAnimationFrame(ws.mover);
    cancelAnimationFrame(ws.keeper);
    ws.bringing = null;
    for (const w of waitingRows()) ws.known[w.id] = true;
  }, { passive: true });
});
