// A row's details: what something on a row says when pointed at (a PR, the row's numbers, where it runs, a session
// open twice, Create PR, a team job), opened inside the row, under its own lines, the rows below moving down.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// The modules say what has details (core.cards): each { selector, key(anchor), html(anchor) }, the key saying what
// they're about ("pr:<url>"), or null when there are none now (a session's numbers have none while the reader shows
// its changes), and the HTML empty when what they're about has gone. One with press(key, act) has buttons (data-act):
// a press on one is passed on, and the details are drawn again when it says they've changed (it returns true: a pick
// on them), else they've done what they're for and fold away.
//
// Resting on something that has them a moment (DETAILS_REST_MS, so passing over the list doesn't open every row on the
// way) opens them, in the row it's in: the list's, or a chat's beside the folded panel. Only one is open at a time.
// They're part of the row's drawing (rowHTML puts detailsHTML at its end), so the list moving or scrolling takes them
// with their row, and they grow in and fold away as a line of the row does (morph's `.details`). See the part's README
// for how they go.
const DETAILS_REST_MS = 300;
// Your own scroll moves the list (a wheel) this recently: one that takes the row from under the pointer folds them.
const DETAILS_YOURS_MS = 300;

const detailsMaker = (anchor) => core.cards.find((c) => anchor.matches(c.selector));
// What the pointer is on that has details, and their key.
function detailsAnchor(el) {
  return core.cards.length ? el?.closest?.(core.cards.map((c) => c.selector).join(', ')) ?? null : null;
}
function detailsKey(anchor) {
  return anchor ? detailsMaker(anchor)?.key(anchor) ?? null : null;
}
// What has the details with `key` in `root`: a row being drawn, or the page.
function detailsAnchorIn(root, key) {
  for (const maker of core.cards)
    for (const anchor of root.querySelectorAll(maker.selector)) if (maker.key(anchor) === key) return anchor;
  return null;
}

// What the details do as the pointer moves, a plain function (tests/panel.sh). `open` is what's open ({ key }), or
// null; `at` the key of what the pointer is on, or null; `on` whether it's on the open row; `onList` on the list;
// `below` past the open row's foot there. `rested`: on `at` for DETAILS_REST_MS. `yours`: your own scroll just moved
// the list. `moving`: the list is moving by itself (a reply moving the rows, or the list easing to show what opened).
// `gone`: what's open has gone from its row.
// Returns { leave, want }. `leave`: 'stay'; 'fold'; or 'fold-hold', folding with the list scrolled back by as much as
// it can, so the rows under the pointer stay still, or, where it can't scroll that far (near its top), close up once,
// never leaving an empty room. `want`: 'none'; 'wait', resting on something else; or 'open'.
function detailsNext({ open = null, at = null, on = false, onList = false, below = false,
                       rested = false, yours = false, moving = false, gone = false } = {}) {
  let leave = 'stay';
  if (open && gone) leave = 'fold';
  else if (open && !on && !moving) leave = yours || !below ? 'fold' : 'fold-hold';
  const want = !at || at === open?.key ? 'none' : rested ? 'open' : 'wait';
  return { leave, want };
}

// The details as a row draws them, around what their maker says: a line of the row (`.details`), its key on it.
function detailsBlock(key, html) {
  return `<div class="details" data-details="${esc(key)}"><div class="details-in">${html}</div></div>`;
}

// A title as the details show it, a plain function (tests/panel.sh): { head, rest }, the head bold and the rest in the
// body's weight. A title with a ":" or " — " within DETAILS_HEAD_MAX splits there; one without is all head while it's
// short (DETAILS_BOLD_MAX), else all rest. The whole is cut at a word with "…" past DETAILS_TITLE_MAX, well under
// what's read of a title, so one clipped mid-word where it was read never shows its cut end. Never split inside a word.
const DETAILS_HEAD_MAX = 32, DETAILS_BOLD_MAX = 40, DETAILS_TITLE_MAX = 120;
function detailsTitle(text) {
  text = String(text ?? '').replace(/\s+/g, ' ').trim();
  const brk = /:(?= )| (?=— )/.exec(text);
  let head = '';
  if (brk?.index > 0 && brk.index <= DETAILS_HEAD_MAX) head = text.slice(0, brk.index + (brk[0] === ':' ? 1 : 0));
  else if (text.length <= DETAILS_BOLD_MAX) head = text;
  let rest = text.slice(head.length);
  if (head.length + rest.length > DETAILS_TITLE_MAX) rest = detailsCut(rest, DETAILS_TITLE_MAX - head.length);
  return { head, rest };
}
// The words of `text` that fit in `max` characters, then "…"; a first word longer than that stays whole.
function detailsCut(text, max) {
  if (text.length <= max) return text;
  const at = text.lastIndexOf(' ', max);
  if (at <= 0) return text;
  return text.slice(0, at).replace(/[\s,;:—–-]+$/, '') + '…';
}
// The details' title in the kit's card title: its head in bold, the rest in the body's weight.
function detailsTitleHTML(text) {
  const { head, rest } = detailsTitle(text);
  return `<div class="card-title">${esc(head)}${rest ? `<span class="card-rest">${esc(rest)}</span>` : ''}</div>`;
}

// What the row for session `sid` shows of the details (rowHTML, at the end of its lines, with `row` the row's HTML so
// far): the details open on it, said afresh as it's drawn. Gone from the row (what they're about isn't on it now),
// they aren't drawn, so they fold away as a line that's gone does, never with words that no longer hold, and they're
// forgotten once the row is drawn (detailsDrawn).
function detailsHTML(sid, chat, row) {
  const d = state.details;
  if (!d.key || d.sid !== sid || d.chat !== chat) return '';
  const drawn = document.createElement('template');
  drawn.innerHTML = row;
  const anchor = detailsAnchorIn(drawn.content, d.key), html = anchor && detailsMaker(anchor).html(anchor);
  return html ? detailsBlock(d.key, html) : '';
}

// The row the details are open on, as drawn now, and its details.
function detailsRow() {
  const d = state.details;
  return d.key ? document.querySelector(`${d.chat ? '#chats' : '#list'} .row[data-id="${CSS.escape(d.sid)}"]`) : null;
}
const detailsIn = (row) => row?.querySelector(':scope > .main > .details:not(.folding)') ?? null;

// The list drawn again, for the details opening, folding or changing: once a frame, never from inside a drawing.
function detailsDraw() {
  const d = state.details;
  if (d.drawPending) return;
  d.drawPending = true;
  requestAnimationFrame(() => { d.drawPending = false; render(); });
}

// What the details do now, each time hover looks (detailsFor, with what the pointer is on).
function detailsFor(el) {
  const d = state.details, now = performance.now(), p = state.pointer;
  const anchor = detailsAnchor(el), at = detailsKey(anchor);
  // Nothing open, nor anything with details under the pointer: nothing to do, each time hover looks.
  if (!d.key && !at) { d.want = null; return; }
  const list = document.getElementById('list'), lr = list.getBoundingClientRect();
  const onList = !!p && !d.chat && p.x >= lr.left && p.x <= lr.right && p.y >= lr.top && p.y <= lr.bottom;
  const row = detailsRow(), r = row?.getBoundingClientRect();
  if (d.want?.key !== at) d.want = at ? { key: at, at: now } : null;
  const yours = now - d.wheelAt < DETAILS_YOURS_MS, until = Math.max(d.movingUntil, yours ? 0 : state.settleUntil);
  const { leave, want } = detailsNext({
    open: d.key ? { key: d.key } : null, at,
    on: !!(el && row?.contains(el)), onList, below: !!(r && onList && p.y > r.bottom),
    rested: !!d.want && now - d.want.at >= DETAILS_REST_MS, yours, moving: now < until,
  });
  // The list moving by itself holds them open; once it stops, hover looks again, as the pointer may be off them by
  // then, or off the panel.
  if (now < until) {
    clearTimeout(d.settleTimer);
    d.settleTimer = setTimeout(syncHover, until - now + 20);
  }
  if (leave === 'fold-hold') {
    // The row under the pointer (or the first below it, on a group's header) keeps its place on the screen as they fold
    // (waitingKeep): the list scrolls back by as much, as far as it can, and the rows close up for the rest.
    d.still = detailsRowAt(el, p.y);
    detailsClose();
  } else if (leave === 'fold') detailsClose();
  if (want === 'open') detailsOpen(anchor);
  else if (want === 'wait') {
    clearTimeout(d.timer);
    d.timer = setTimeout(() => { if (state.pointer) syncHover(); }, DETAILS_REST_MS + 20);
  }
}

// Opens what `anchor` has, now: rested on, or pressed (Create PR on its row). The list eases to show them whole once
// they've grown, if they don't fit below (detailsReveal).
function detailsOpen(anchor) {
  const d = state.details, key = detailsKey(anchor), sid = anchor?.closest('[data-id]')?.dataset.id;
  if (!key || !sid) return;
  if (d.key === key) return;
  Object.assign(d, { key, sid, chat: !!anchor.closest('#chats'), want: null });
  state.shownAt['details:' + sid] = Date.now();
  detailsDraw();
  requestAnimationFrame(() => setTimeout(() => detailsReveal(key),
                                         Math.max(0, state.settleUntil - performance.now()) + 20));
}

// The details fold away.
function detailsClose() {
  const d = state.details;
  if (!d.key) return;
  Object.assign(d, { key: null, sid: null, chat: false });
  detailsDraw();
}

// The list's row the pointer is on, by its session, or the first one below it (on a group's header between rows).
function detailsRowAt(el, y) {
  const on = el?.closest?.('#list .row[data-id]');
  if (on) return on.dataset.id;
  return [...document.querySelectorAll('#list .row[data-id]')].find((r) => r.getBoundingClientRect().top >= y)
    ?.dataset.id ?? null;
}

// Opened where they don't fit below (a row near the panel's foot), once they've grown: the list scrolls by just the
// part that's missing, down to the row's own foot, so the row's room under them stays as under any row, what was
// pointed at kept in view (showLeast), measured where the list ends up. Meanwhile the list moving counts as its own,
// not yours, so it doesn't fold them.
function detailsReveal(key) {
  const d = state.details, row = detailsRow(), box = detailsIn(row);
  if (d.key !== key || d.chat || !box) return;
  d.movingUntil = performance.now() + 600;
  showLeast(box, detailsAnchorIn(row, key) ?? box, row);
  setTimeout(syncHover, 620);
}

// The session whose row keeps its place on the screen as the list is drawn again (waitingHold): the one under the
// pointer as the details fold, or the one they're open on while the pointer is on the panel. None for a chat's.
function detailsHeldRow() {
  const d = state.details;
  return d.still ?? (d.key && !d.chat && state.pointer ? d.sid : null);
}

// The key of what's open, if anything (Create PR's branch list stays open while its details do).
function detailsOpenKey() {
  return state.details.key;
}

// Once the list is drawn: the row held still as they folded lets go, and details whose row no longer has what they're
// about (they weren't drawn: detailsHTML) are forgotten.
function detailsDrawn() {
  const d = state.details;
  d.still = null;
  if (!d.key) return;
  const row = detailsRow();
  if (detailsNext({ open: { key: d.key }, gone: !detailsIn(row), on: true }).leave === 'fold')
    Object.assign(d, { key: null, sid: null, chat: false });
}

// A press in the details: on one of their buttons, its maker's press, unless they've only just come; anywhere else in
// them, nothing (the row's own press would open the session). The row stays where it is meanwhile.
core.presses.push(['.details', (box, e) => {
  e.preventDefault();
  const d = state.details, key = box.dataset.details, button = e.target.closest('button[data-act]');
  if (!button || button.disabled || !key || key !== d.key || justShown('details:' + d.sid)) return;
  const anchor = detailsAnchorIn(box.closest('.row'), key), press = anchor && detailsMaker(anchor)?.press;
  if (!press) return;
  keepInPlace(d.sid);
  if (press(key, button.dataset.act)) detailsDraw();
  else detailsClose();
}]);
core.pointerTargets.push('.details button');
core.lines['.details'] = {
  text: (el) => el.dataset.details,  // other details cross-fade in
  foldsFirst: true,                  // held at the list's edge, the last thing opened folds first (sticky.js)
};
core.forgotten.prefixes.push('details');
core.afterDraw.push(detailsDrawn);
// Your own scroll (a wheel, as waiting.js tells one), as against the list moving by itself.
addEventListener('wheel', () => { state.details.wheelAt = performance.now(); }, { passive: true, capture: true });
