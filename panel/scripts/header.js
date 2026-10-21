// The header lies over the list's top (base.css) and stays there as the list scrolls, until the row you're on, held at
// the list's top, has folded all it can there (sticky.js): scrolling on, that pushes it up and away, point for point,
// for the list to have its room. It stays as far as it was pushed, part-way too, until the list has scrolled back to
// its very top, which brings it back with it. It's all there while the list is too short to scroll, the reader is open
// or a card or the setup line is under it; folded, it stays as it was, out of sight, until the panel opens, when it's all there
// (toggleCollapsed, panel.js). The app hears how much of it shows, for the drag strip over it, and when it has gone,
// for Whozmove beside the panel (app/core/PanelWindow.m). What it keeps between rebuilds is state.header (state.js).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// How tall the header is with its line: --header (tokens.css, kHeaderHeight in app/core/PanelWindow.m) and 1.
const HEADER_TALL = 47;
// How long it takes to come back where it can't go (the reader opening, a card or the setup line under it).
const HEADER_GLIDE = 200;

// How far the header has gone after the list has scrolled by `d` to `top`, the held row's copy having gone `push`
// points past where it has folded all it can at the list's top (stickyPush, sticky.js): further by as much of the
// scroll down as took the copy past there, and back only as the list's very top comes back into view (at the top, it's
// all there).
function headerAfterScroll(off, d, top, push, tall = HEADER_TALL) {
  return Math.max(0, Math.min(tall, off + Math.max(0, Math.min(d, push)), top));
}

// Whether the header counts as gone: all of it, and once it has, until it has come back by a few points, so a jitter
// of the scroll doesn't send Whozmove beside the panel in and out.
function headerGone(off, wasGone, tall = HEADER_TALL) {
  return wasGone ? off > tall - 6 : off >= tall - 0.5;
}

// Whether the header may slide away: not while the panel is folded, the reader is open or a card or the setup line is
// under it, nor while the list has less than a point to scroll.
function headerMayGo({ folded, reading, carded, room }) {
  return !folded && !reading && !carded && room > 1;
}

const headerEl = document.querySelector('#root > header');

// How much of the list's top the header covers now: the list's top edge for the held row (sticky.js).
function headerInset() {
  return headerCarded() ? 0 : HEADER_TALL - state.header.off;
}

// How far it has gone now, for measuring the name's o where it is when it's all there (catPlace, cat.js).
function headerOff() {
  return state.header.off;
}

// A new conversation's card (#dock), or the line under the header while Whozmove sets itself up (#install).
const headerCarded = () => !!document.getElementById('dock').firstElementChild
  || !document.getElementById('install').hidden;
const headerList = () => document.getElementById('list');
// Folded, or with the folded cat's list out (peek.js), whose head stands in for the header and stays where it is.
const headerFolded = () => document.body.classList.contains('collapsed') || document.body.classList.contains('peeking');
function headerCanGo() {
  const list = headerList();
  return headerMayGo({ folded: headerFolded(), reading: !!state.reading, carded: headerCarded(),
                       room: list.scrollHeight - list.clientHeight });
}

// The header `off` points up, the list clipped where its edge is, so rows go under it as they did under the fixed one.
function headerShow(off, force) {
  const h = state.header;
  off = Math.max(0, Math.min(HEADER_TALL, off));
  if (off === h.off && !force) return;
  h.off = off;
  headerEl.style.transform = off ? `translateY(${(-off).toFixed(2)}px)` : '';
  headerList().style.clipPath = headerCarded() ? '' : `inset(${(HEADER_TALL - off).toFixed(2)}px 0 0 0)`;
  stickyPlace();
  headerTell();
}

// All there at once, for what measures from it (the panel opening round the cat, catOpening in cat.js), its glide
// stopped.
function headerAllThere() {
  cancelAnimationFrame(state.header.glide);
  headerShow(0, true);
}

// How much of the line under the header shows: none once the held row's copy has attached at the list's top, so it
// meets the header with nothing between them (stickyShade, sticky.js).
function headerLine(shown) {
  headerEl.style.setProperty('--line', String(Math.round(shown * 1000) / 1000));
}

// The app hears how much of the header shows, for the drag strip over it, and whether it has gone, once a frame at
// most.
function headerTell() {
  const h = state.header;
  h.gone = headerGone(h.off, h.gone);
  if (h.telling) return;
  h.telling = true;
  requestAnimationFrame(() => {
    h.telling = false;
    const showing = Math.round((HEADER_TALL - 1 - h.off) * 2) / 2, gone = h.gone;
    if (h.told && h.told.showing === showing && h.told.gone === gone) return;
    h.told = { showing, gone };
    native({ type: 'header', showing: Math.max(0, showing), gone });
  });
}

// Folded, the list may still scroll (a scroll's momentum running on, the session you're on scrolled to): the header
// stays where it is, out of sight, until the panel opens (toggleCollapsed puts it all there). Open, the row you're on
// is laid out for the scroll first, so it's held at the list's top as soon as it has gone past it, and how far its copy
// pushes the header is measured from there.
function headerScrolled() {
  const h = state.header, list = headerList(), top = list.scrollTop, d = top - h.last;
  h.last = top;
  if (headerFolded()) return;
  if (!headerCanGo()) return headerGlideTo(0);
  stickyPlace();
  headerShow(headerAfterScroll(h.off, d, top, stickyPush()));
}

function headerGlideTo(to) {
  const h = state.header;
  cancelAnimationFrame(h.glide);
  const from = h.off;
  if (Math.abs(to - from) < 0.5 || calm.matches) return headerShow(to, true);
  const start = performance.now();
  const step = (now) => {
    const p = Math.min(1, (now - start) / HEADER_GLIDE);
    headerShow(from + (to - from) * (1 - (1 - p) ** 3), true);
    if (p < 1) h.glide = requestAnimationFrame(step);
  };
  h.glide = requestAnimationFrame(step);
}

core.starts.push(() => {
  headerList().addEventListener('scroll', headerScrolled, { passive: true });
  // A card opening under the header (a new conversation's), or the setup line, takes the header's room, and brings it
  // back with a slide if it had gone; one closing gives the room back to the list.
  const carded = new MutationObserver(() => (headerCarded() ? headerGlideTo(0) : headerShow(state.header.off, true)));
  carded.observe(document.getElementById('dock'), { childList: true });
  carded.observe(document.getElementById('install'), { attributes: true, attributeFilter: ['hidden'] });
  headerShow(0, true);
});
// A list that has become too short to scroll, or the reader opening, brings it back.
core.afterDraw.push(() => {
  if (state.header.off > 0 && !headerFolded() && !headerCanGo()) headerGlideTo(0);
});
