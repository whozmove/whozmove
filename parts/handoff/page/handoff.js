// What happens as the row you're on stops being held at the list's edge (sticky.js holds it): its copy lets go,
// handing back to the row in place or fading out where it is, or, when the session you're on changes, slides off at
// its edge while its tint goes to the new session's row; and then it's gone.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// How long the copy takes to slide off at its edge, and its tint to go to the row of the session you're on now, when
// that changes while it holds on.
const STICKY_HANDOFF_MS = 320;

// The row is back in view, or isn't the one to hold on any more: the copy goes. Where it hands back to the row in place
// it goes at once; elsewhere it fades out where it is, the list under it coming back as it goes. What's on the row
// counts as only just shown once it's back, as it hasn't been seen while it was away (showAgain): a card that came
// meanwhile can't be pressed by a press meant for the copy.
function stickyLetGo(fade) {
  const st = state.sticky;
  if (st.row) {
    st.row.inert = false;
    st.row.classList.remove('sticky-away');
  }
  const s = state.last.sessions.find((x) => x.sessionId === st.sid);
  if (s) showAgain(s);
  cancelAnimationFrame(st.ramp);
  cancelAnimationFrame(st.follow);
  if (fade) cancelAnimationFrame(st.mover);  // handed back in place, a scroll back to the row goes on to its end
  if (!fade || calm.matches) return stickyGone();
  st.leaving = true;
  stickyRamp(0, () => {
    stickyGone();
    stickyPlace();  // where the row is now, for the next scroll
  });
}

// The session you're on changed while its copy held on (you pressed another row, or switched to another session in
// Claude or a terminal): the copy slides off at its edge, out of sight, uncovering the list under it as it goes, which
// comes back as the copy fades, while its tint goes to the new session's row, where that is in each frame (the list may
// be scrolling to show it), and that row's own tint takes over as it lands. With no row for the new session, the tint
// goes with the copy.
function stickyHandOff() {
  const st = state.sticky, list = document.getElementById('list'), edge = st.edge, [a, b] = st.band;
  const holder = stickyEl.querySelector('.sticky-copy'), tint = stickyUnder.querySelector('.sticky-tint');
  const s = state.last.sessions.find((x) => x.sessionId === st.sid);
  if (s) showAgain(s);
  cancelAnimationFrame(st.ramp);
  cancelAnimationFrame(st.follow);
  cancelAnimationFrame(st.mover);
  st.leaving = true;
  // How far the copy goes to be out of sight; where the tint starts, in its layer; how attached it was.
  const out = edge === 'top' ? -b : st.lastV - a, layer = stickyUnder.getBoundingClientRect();
  const r0 = tint.getBoundingClientRect(), from = [r0.left - layer.left, r0.top - layer.top, r0.width, r0.height];
  const attach = parseFloat(stickyUnder.style.getPropertyValue('--attach')) || 0, attached = st.attached;
  const start = performance.now();
  state.settleUntil = Math.max(state.settleUntil, start + STICKY_HANDOFF_MS + 40);  // the rows stay as they are
  let landing = null;
  const step = (now) => {
    // Both start at once, the copy easing out of sight and the tint into its new place.
    const p = Math.min(1, (now - start) / STICKY_HANDOFF_MS), slide = 1 - (1 - p) ** 2, come = 1 - (1 - p) ** 3;
    const d = out * slide;
    holder.style.transform = `translateY(${stickyPx(d)})`;
    // The list under it is uncovered as it moves off, never through it, and it fades as it goes; its tint doesn't,
    // going to the new row.
    st.band = edge === 'top' ? [a, Math.max(a, b + d)] : [Math.min(b, a + d), b];
    Object.assign(st, { covered: [a, b], back: p, attached: attached * (1 - p) });
    stickyShade();
    stickyEl.style.setProperty('--fade', String(1 - p));
    const row = focusedRow(list);
    if (row !== landing) {
      landing?.classList.remove('sticky-landing');
      row?.classList.add('sticky-landing');
      landing = row;
    }
    const r = row?.getBoundingClientRect();
    const to = r ? [r.left - layer.left, r.top - layer.top, r.width, r.height]
      : [from[0], from[1] + d, from[2], from[3]];
    const [x, y, w, h] = from.map((f, i) => f + (to[i] - f) * (r ? come : 1));
    Object.assign(tint.style, { left: stickyPx(x), top: stickyPx(y), width: stickyPx(w), height: stickyPx(h) });
    stickyUnder.style.setProperty('--attach', String(r ? attach * (1 - come) : attach));
    tint.classList.toggle('is-hover', !!row?.classList.contains('is-hover'));
    if (p < 1) {
      st.ramp = requestAnimationFrame(step);
      return;
    }
    stickyGone();
    stickyPlace();
  };
  step(start);  // in the frame the list is drawn in, so the new row never shows its own tint before this one lands
}

// The copy is gone: both its layers, and the mask, and what a hand-off leaves on them as it goes, which another change
// of session may cut short (stickyLetGo), so the next copy isn't drawn where that one had slid to.
function stickyGone() {
  const st = state.sticky, list = document.getElementById('list'), holder = stickyEl.querySelector('.sticky-copy');
  Object.assign(st, { edge: null, leaving: false, copy: null, chat: null, shape: '', lines: [], drawn: '', fade: 1,
                      at: null, speed: 0, attached: 0, covered: null, back: 1 });
  stickyEl.classList.remove('on');
  stickyUnder.classList.remove('on');
  holder.replaceChildren();
  holder.style.transform = '';
  stickyUnder.querySelector('.sticky-tint').classList.remove('is-hover');
  list.querySelectorAll('.sticky-landing').forEach((row) => row.classList.remove('sticky-landing'));
  list.style.webkitMaskImage = list.style.maskImage = '';
  headerLine(1);
  if (state.pointer) syncHover();
}
