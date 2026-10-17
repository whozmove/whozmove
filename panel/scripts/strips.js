// The strips under the list (the usage strip, Spotify's now-playing strip): changing a strip's text, and easing it to a
// new height, growing it in and folding it away, the panel's bottom edge going with it. Plain helpers on the motion
// engine (morph.js), for any strip.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// A strip's text, set only when it changes, so nothing is laid out again for nothing.
function setText(el, text) {
  if (el.textContent !== text) el.textContent = text;
}

// An element's height eases from what it was to what it is now, the panel following.
function easeHeight(el, before) {
  const after = el.offsetHeight;
  if (Math.abs(after - before) < 1 || calm.matches) return reportHeight();
  tween(el, { height: `${before}px`, overflow: 'hidden' }, { height: `${after}px` }, null, 300);
  followHeight(340);
}

// A strip at the panel's bottom easing from `before` to its height now as its content comes in the panel's way, the
// panel's bottom edge going with it; then `done`.
function growIn(el, before, done) {
  tween(el, { height: `${before}px`, overflow: 'hidden' }, { height: `${el.offsetHeight}px` }, done, 340);
  el.animate([{ opacity: 0, filter: 'blur(1.5px)', transform: 'translateY(3px)' },
              { opacity: 1, filter: 'blur(0)', transform: 'none' }], { duration: 600, easing: MORPH_EASE });
  followHeight(380);
}

// Such a strip fading as it eases away to nothing, the panel's bottom edge coming up with it; then `done`, which hides
// it before its height comes back.
function foldAway(el, done) {
  tween(el, { height: `${el.offsetHeight}px`, opacity: 1, overflow: 'hidden' }, { height: '0px', opacity: 0 }, done,
        300);
  followHeight(340);
}
