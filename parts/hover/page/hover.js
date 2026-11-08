// Hover: what's under the pointer is highlighted, the modules look at what it's on, and a row's details are told what
// it's on (parts/details), which open in the row while something that has them is rested on (a PR, a session's
// numbers).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// Everything hover-related follows one pointer position that the app polls and sends (hoverAt, hoverEnd).
// Neither :hover nor mouse events are used: the panel is rarely the focused window, so WebKit's own hover goes
// stale, and the list is rebuilt whenever what it shows changes, any second.
const HOVER_TARGETS = ['.row', '.chev', '.apps', '.project', '.perm button', '.opt', '.q-close',
                       '.step-note button',
                       '#reader button'];

// What the pointer is on: the copy of the row you're on, held at the list's edge over what it hides there (stickyAt),
// or else what's under it on the page.
function pointedAt() {
  const p = state.pointer;
  return p && (stickyAt(p.x, p.y) || document.elementFromPoint(p.x, p.y));
}

// What the pointer looks like where it is, which the app shows, as WebKit's own shapes never show in a window that
// isn't the one you type in: the text cursor over a box or text that can be selected (its style's cursor says so), the
// hand over what a press does something with (what the pointer can point at, a button, a link, the folded cat), but
// for one that's off, else the arrow.
function pointerShape(el, hovered) {
  if (!el) return 'arrow';
  if (el.closest(textBoxes()) || getComputedStyle(el).cursor === 'text') return 'text';
  const button = el.closest('button, a[href], [data-act], #cat');
  if (button) return button.matches(':disabled, .off, [aria-disabled="true"]') ? 'arrow' : 'hand';
  return hovered.size ? 'hand' : 'arrow';
}

// What the pointer can point at, the core's and the modules' (core.pointerTargets), joined the first time it's needed,
// once every script has loaded and added its own.
let allTargets = null;

function syncHover() {
  // What's under the pointer is found first, then only what changed gains or loses .is-hover. Taking it off everything
  // and putting it back restarted every hover transition each time the pointer moved: the look in between made the page
  // apply the state without it.
  const el = pointedAt();
  allTargets ??= [...HOVER_TARGETS, ...core.pointerTargets];
  const hovered = new Set(allTargets.map((target) => el?.closest(target)).filter(Boolean));
  document.querySelectorAll('.is-hover').forEach((n) => { if (!hovered.has(n)) n.classList.remove('is-hover'); });
  for (const n of hovered) n.classList.add('is-hover');
  const shape = pointerShape(el, hovered);
  if (shape !== state.shape) native({ type: 'pointer', shape: state.shape = shape });
  // What the modules do with what it's on: a step's word coming in, the context ring widening, the changes asked for
  // ahead of a press.
  for (const watch of core.pointerWatchers) watch(el);
  // Then the row's details, once they have: what they show can follow what they did.
  detailsFor(el);
}

function pointerAt(x, y) { state.pointer = { x, y }; syncHover(); }
function pointerGone() { state.pointer = null; syncHover(); }

// The list scrolling under a still pointer (by your hand, or by itself, as it brings a request into view) has hover
// look again, so what it highlights, the modules' watchers and the row's details follow what's under it now.
core.starts.push(() => {
  document.getElementById('list').addEventListener('scroll', () => { if (state.pointer) syncHover(); },
                                                   { passive: true });
});
