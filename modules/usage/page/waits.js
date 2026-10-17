// Wait styles: what the usage strip shows while the session limit is reached, until it resets, and how that turns back
// into the strip. One shows at a time, by name; each is a file of its own that adds itself to WAITS (wait-vine.js).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// A style draws in a layer the strip gives it (an <svg> the strip's full width and `height` tall), never into the
// session's line at the top: the strip's text lane. The strip calls:
//   build(layer)            once, as the wait starts
//   draw(progress, calm)    each second of the wait, from 0 at the limit to 1 at the reset; `calm` is reduced motion
//   resetFrame(t, stage)    each frame of the reset, `t` ms in, up to `resetMs`. `stage` holds the strip's own parts it
//                           moves: the session line's message and the text at its right, the session bar's track and
//                           fill, the session's percent, the week row and its fill, and the strip itself (its height).
//                           At `resetMs` each is where the normal strip has it, so the strip takes over without a jump.
//   clear()                 when the wait is over
// Easing and fading are shared, so every style moves the panel's way.
const WAITS = {};
const waitStyle = () => WAITS[store.get('waitStyle', 'vine')] || WAITS.vine;

const clamp01 = (x) => Math.max(0, Math.min(1, x));
const lerp = (a, b, p) => a + (b - a) * p;
const within = (t, start, ms) => clamp01((t - start) / ms);  // how far through a span of time, 0 to 1
const easeOut = (p) => 1 - Math.pow(1 - p, 3);
const easeInOut = (p) => p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2;
// Text arriving or leaving, the panel's way (motion.css's swapIn): it fades, lifts 3px and sharpens, or the reverse.
const SHOWN = { opacity: 1, blur: 0, dy: 0 }, GONE = { opacity: 0, blur: 0, dy: 0 };
const fadeIn = (t, start, ms) => {
  const p = easeOut(within(t, start, ms));
  return { opacity: p, blur: 1.5 * (1 - p), dy: 3 * (1 - p) };
};
const fadeOut = (t, start, ms) => {
  const p = easeOut(within(t, start, ms));
  return { opacity: 1 - p, blur: 1.5 * p, dy: -3 * p };
};
function applyFade(el, f) {
  if (!el) return;
  el.style.opacity = f.opacity.toFixed(3);
  el.style.filter = f.blur > 0.01 ? `blur(${f.blur.toFixed(2)}px)` : '';
  el.style.transform = f.dy ? `translateY(${f.dy.toFixed(2)}px)` : '';
}
