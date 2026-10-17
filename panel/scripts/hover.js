// Hover: what's under the pointer is highlighted, the modules look at what it's on, and a card shows while something
// that has one is pointed at (a PR, a session's numbers).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// Everything hover-related follows one pointer position that the app polls and sends (hoverAt, hoverEnd).
// Neither :hover nor mouse events are used: the panel is rarely the focused window, so WebKit's own hover goes
// stale, and the list is rebuilt every second.
const HOVER_TARGETS = ['.row', '.chev', '.group.toggle', '.project', '.perm button', '.opt', '.q-close',
                       '#reader button'];

// The card shown while something is pointed at, below it. The modules say what has one (core.cards): each { selector,
// key(anchor), html(anchor) }, the key saying what the card is about ("pr:<url>"), or null when it shows none now (a
// session's numbers have none while the reader is open), and the HTML empty when what it's about has gone.
const card = document.getElementById('card');
const cardMaker = (anchor) => core.cards.find((c) => anchor.matches(c.selector));
function cardAnchor(el) {
  return core.cards.length ? el?.closest(core.cards.map((c) => c.selector).join(', ')) || null : null;
}
function cardKey(anchor) {
  return anchor ? cardMaker(anchor)?.key(anchor) ?? null : null;
}

// Below what it's about when the panel can grow to fit it, otherwise above.
function placeCard(anchor) {
  const r = anchor.getBoundingClientRect();
  const h = card.offsetHeight;
  let top = r.bottom + 4;
  if (top + h + 8 > state.panelMax) top = Math.max(6, r.top - h - 4);
  card.style.top = top + 'px';
  state.cardBottom = Math.ceil(top + h + 8);
}

function showCard(key) {
  const anchor = cardUnderPointer();
  if (!anchor || cardKey(anchor) !== key) return;
  const html = cardMaker(anchor).html(anchor);
  if (!html) return;
  // The same card, pointed at still, is drawn again only when what it says has changed (its row's numbers, say).
  const redraw = state.cardKey !== key || state.cardHTML !== html;
  if (redraw) card.innerHTML = state.cardHTML = html;
  state.cardKey = key;
  card.hidden = false;
  placeCard(anchor);
  if (redraw) reportHeight();
}

// The card goes at once. Where it reached below the list, the panel keeps that room a moment longer, so a pointer moving
// on to the next row's card doesn't have the panel's edge go up and down between them.
function hideCard() {
  if (!state.cardKey) return;
  state.cardKey = null;
  card.hidden = true;
  state.cardHeld = { bottom: state.cardBottom, until: performance.now() + 400 };
  setTimeout(reportHeight, 420);
}

function cardUnderPointer() {
  // The card itself isn't found: it takes no pointer events.
  return cardAnchor(state.pointer && document.elementFromPoint(state.pointer.x, state.pointer.y));
}

// What the pointer can point at, the core's and the modules' (core.pointerTargets), joined the first time it's needed,
// once every script has loaded and added its own.
let allTargets = null;

function syncHover() {
  // What's under the pointer is found first, then only what changed gains or loses .is-hover. Taking it off everything
  // and putting it back restarted every hover transition each time the pointer moved: the look in between made the page
  // apply the state without it.
  const el = state.pointer && document.elementFromPoint(state.pointer.x, state.pointer.y);
  allTargets ??= [...HOVER_TARGETS, ...core.pointerTargets];
  const hovered = new Set(allTargets.map((target) => el?.closest(target)).filter(Boolean));
  document.querySelectorAll('.is-hover').forEach((n) => { if (!hovered.has(n)) n.classList.remove('is-hover'); });
  for (const n of hovered) n.classList.add('is-hover');
  // What the modules do with what it's on: the island's gauge opening, its commits stage's card, the context ring
  // widening, the changes asked for ahead of a press.
  for (const watch of core.pointerWatchers) watch(el);
  const key = cardKey(cardAnchor(el));
  if (key && key === state.cardKey) { showCard(key); return; }
  // At once, both ways: the card is up as soon as what it's about is pointed at, and gone as soon as it isn't.
  if (key) showCard(key);
  else hideCard();
}

function pointerAt(x, y) { state.pointer = { x, y }; syncHover(); }
function pointerGone() { state.pointer = null; syncHover(); }
