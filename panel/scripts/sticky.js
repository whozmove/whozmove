// The row you're on, held at the list's edge: it never leaves the list's visible part. As the list scrolls past the
// session you're on, or moves its row out of sight by itself, the row holds on at the list's top (past it: the header's
// edge, wherever that has been pushed to) or at its bottom (past that), folded down to its title line, Claude's line
// and where it runs, and opens back into its place as it comes back. Folded all it can at the top, it's what pushes the
// header away as the list scrolls on (stickyPush, header.js).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// The row stays in the list, keeping its place, so nothing in the list moves: a copy of it, laid over the list's edge,
// is what holds on, made as the row starts holding on and gone once it lets go. The row itself is hidden meanwhile, and
// what's under the copy by a mask on the list, as the rows under the header are. Everything follows where the row's
// place is, catching up with it where it moves faster than a slow scroll, so scrolling back runs it all backwards. The
// plain functions come first, which tests/panel.sh checks; the rest measure and lay out the copy.

// How far past the edge the row has gone when its copy is fully part of the edge.
const STICKY_ATTACH = 24;
// What stays on the copy beside its chat line (Claude's, or with none, yours): the title line and the bottom line, with
// how the agent is set up and where it runs.
const STICKY_KEEPS = ['.line1', '.where'];
// How long the copy takes to come or go where it doesn't take over from the row in place, or hand back to it there (it
// starts holding on with the row already past the edge, or lets go with the row somewhere else), and to cross-fade
// into a copy of other lines.
const STICKY_FADE_MS = 240;
// How long the copy takes to slide off at its edge, and its tint to go to the row of the session you're on now, when
// that changes while it holds on.
const STICKY_HANDOFF_MS = 320;
// How the copy keeps up with the row's place when that moves faster than a slow scroll: as much of each move as a slow
// scroll makes (points a millisecond) it follows at once, and the rest it catches up with, all but there after six of
// these (milliseconds), about 0.2 s.
const STICKY_KEEP_UP = 0.4, STICKY_EASE_MS = 34;
// How far inside the list's edge a row the list scrolls to is put: the row you're on, pressed at the edge, the session
// you've switched to, a new conversation's.
const SHOW_GAP = 4;
const stickySmooth = (x) => x * x * (3 - 2 * x);

// Which edge the row you're on holds on at, for where its place is now: its top `t` from the top of the list's visible
// part, its height `h`, and that part's height `v`. Past the top it holds on at the list's top, past the bottom at its
// bottom, and in view nowhere (null). A quarter of a point either way still counts as in view, as layout rounds.
function stickyEdge(t, h, v) {
  if (t < -0.25) return 'top';
  if (t + h > v + 0.25) return 'bottom';
  return null;
}

// Whether the row holds on at an edge now, and how it gets there or goes. `was` is the edge it held on at till now (or
// null), and `inView` whether its place was wholly in view when last looked at. The row never leaves the list's
// visible part: whatever takes it past an edge, or further past one (`away`: your scrolling, the row moving to the top
// as a message comes in, rows above it growing, the list getting shorter), it holds on there. A row
// that only grows past the bottom edge, its top staying where it is (a card opening on it), stays as it is, still in
// view, and grows in as any row does. It never holds on while one of its boxes is typed in (`typing`), nor when it's
// taller than the list's visible part, which could then never show it whole. Returns { edge, fade }: the edge (or
// null), and whether the copy fades in or out rather than taking over from the row, or handing back to it, in place.
function stickyHold(t, h, v, { was, inView, away, typing, behind }) {
  const edge = stickyEdge(t, h, v);
  if (edge && !typing && h <= v + 0.25 && (was || away)) return { edge, fade: was ? was !== edge : !inView };
  // Back in view, it hands back to the row once its copy has caught up with the row's place (`behind`: not yet),
  // opening out and gliding there from the edge (stickyEase), however far the row came since the last frame (a quick
  // scroll moves it tens of points from one to the next). Still past the edge but not to be held any more (typed in,
  // or now too tall), the copy fades out where it is.
  if (was && !edge && behind) return { edge: was, fade: false };
  return { edge: null, fade: !!(was && edge) };
}

// Where the copy has got to, catching up with the row's place: its top `at`, moving `speed` points a millisecond, `dt`
// milliseconds on, the place's top having gone from `from` to `to` meanwhile. As much of the place's move as a slow
// scroll makes it follows at once, so a slow scroll folds it exactly as the place goes; the rest it catches up with
// smoothly, from rest or at the speed it's going, all but there in about 0.2 s and never past the place, so a quick
// scroll, or the list moving the row by itself, folds its lines one after another rather than all in a frame, and
// coming back, it opens out the same way. Returns { at, speed }; caught up, `at` is `to`.
function stickyEase(at, speed, from, to, dt) {
  const keep = STICKY_KEEP_UP * dt, x0 = at + Math.max(-keep, Math.min(keep, to - from)) - to;
  const k = 1 / STICKY_EASE_MS, e = Math.exp(-k * dt), x = (x0 + (speed + k * x0) * dt) * e;
  const v = (speed - (speed + k * x0) * k * dt) * e;
  if (x * x0 <= 0 || (Math.abs(x) < 0.5 && Math.abs(v) < 0.02)) return { at: to, speed: 0 };
  return { at: to + x, speed: v };
}

// How the copy folds as it holds on at `edge`. It's as tall as the part of the row's place still in view (`visible`),
// so the row next to it stays touching it, but never less than the lines that stay; a place taller than the copy (a
// line the row has lost still folding away there) is filled with its tint. What it has lost is folded off the lines
// that go, one after another, the one nearest the moving edge first: from the bottom up at the top edge, so Claude's
// line comes up under the title last, and from the top down at the bottom edge, where the title comes down onto them.
// `lines` are the row's lines top to bottom, each { extent, keep }: its height with its margin, and whether it stays;
// `full` is the copy's height. Returns its height, each line's fold in `lines`' order, and, from 0 to 1, how attached
// to the edge it is.
function stickyFold(lines, full, visible, edge) {
  const least = full - lines.reduce((sum, l) => sum + (l.keep ? 0 : l.extent), 0);
  const height = Math.max(least, visible);
  const folds = lines.map(() => 0), order = lines.map((l, i) => i).filter((i) => !lines[i].keep);
  if (edge === 'top') order.reverse();
  let left = Math.max(0, full - height);
  for (const i of order) {
    folds[i] = Math.min(left, lines[i].extent);
    left -= folds[i];
  }
  const part = (x) => Math.max(0, Math.min(1, x));
  return { height, folds, attach: part((full - visible) / STICKY_ATTACH) };
}

// How a line of the copy folds by `f` points, `line` being its height `h` and its margin above `m`. It keeps its size,
// so nothing in it moves or squeezes, and gives up the room it takes: at the top edge the line below comes up over it,
// so its foot goes under first, and at the bottom edge the line above comes down onto it, over its margin and then its
// head. What's covered is cut off (`clip`: [from its top, from its bottom]), and it fades, gone by 60% of the way.
function stickyLineFold({ h, m }, f, edge) {
  const q = m + h > 0 ? Math.min(1, f / (m + h)) : 0, opacity = 1 - stickySmooth(Math.min(1, q / 0.6));
  if (edge === 'top') return { marginTop: m, marginBottom: -f, clip: [0, Math.min(f, h)], opacity };
  return { marginTop: m - f, marginBottom: 0, clip: [Math.max(0, f - m), 0], opacity };
}

// Where a row `h` tall goes to be shown whole in the list's visible part, `v` tall, coming in at `edge`: SHOW_GAP
// inside that edge, or less where there isn't the room (so a row about as tall as the list isn't pushed past its other
// edge), and clear of what the copy held at the list's top and bottom covers (`top`, `bottom`). Its top, from the
// part's top.
function showAt(h, v, edge, top = 0, bottom = 0) {
  const gap = Math.max(0, Math.min(SHOW_GAP, v - top - bottom - h));
  return edge === 'top' ? top + gap : v - bottom - h - gap;
}

// What the copy of the row you're on would cover of the list's visible part once the list has scrolled `by` points
// further down, scrolling there holding the row on at the edge it would be past: [at the top, at the bottom]. The row's
// top is `t`, its height `h`, and its lines that stay are `least` tall.
function stickyCovers(t, h, v, least, by) {
  const at = t - by, edge = h <= v + 0.25 ? stickyEdge(at, h, v) : null;
  if (edge === 'top') return [Math.max(least, at + h), 0];
  if (edge === 'bottom') return [0, Math.max(least, v - at)];
  return [0, 0];
}

// ---- Laying it out ----

// Its two layers: over the list, the copy; under it, the tint.
const stickyEl = document.getElementById('sticky'), stickyUnder = document.getElementById('sticky-under');
const stickyPx = (n) => `${Math.round(n * 100) / 100}px`;

// The row you're on as the list shows it (in a folded group, its copy pinned below the group), or null: the row
// itself, not what's left of it fading out where it was (fadeAway).
function focusedRow(list) {
  return [...list.querySelectorAll('.row.focused[data-id]')]
    .find((r) => !r.closest('.prows.closed') && !r.matches('.fading')) || null;
}

// A copy of the row as it ends up, without what the list's own motion has put on it for the moment (a line folding
// away, text being written or erased, what a module's line has only while it moves: core.lines' `still`). It keeps
// what's cross-fading on the row, so that does on the copy too. Without what makes it the row: the data the page's
// parts find a row and its parts by (so none of them ever takes the copy for it) and what could take the keyboard
// (it's inert).
function stickyCopyOf(row) {
  const copy = row.cloneNode(true);
  copy.querySelectorAll('.folding, .rewrite-old').forEach((el) => el.remove());
  for (const sel of [':scope > .main > .you', ':scope > .main > .claude'])
    copy.querySelectorAll(sel).forEach((line) => settleLine(line));
  for (const [sel, line] of Object.entries(core.lines)) if (line.still) copy.querySelectorAll(sel).forEach(line.still);
  copy.classList.remove('is-hover', 'arrive', 'glide', 'landing');
  for (const el of [copy, ...copy.querySelectorAll('*')])
    for (const name of el.getAttributeNames())
      if (name.startsWith('data-') || name === 'id' || name === 'title') el.removeAttribute(name);
  copy.removeAttribute('style');
  for (const line of copy.querySelector(':scope > .main').children) line.removeAttribute('style');
  copy.querySelectorAll('[style]').forEach((el) => { el.style.transform = ''; el.style.transition = ''; });
  copy.inert = true;
  return copy;
}

// A row's chat line that stays on its copy: Claude's, or with none, yours.
function stickyChat(row) {
  return row && (row.querySelector(':scope > .main > .claude') || row.querySelector(':scope > .main > .you'));
}

// Each of a row's lines, as laid out with nothing folded: its height, its margin above, and whether it stays on the
// copy.
function stickyMeasure(row) {
  const main = row.querySelector(':scope > .main'), chat = stickyChat(row);
  return [...main.children].map((el) => {
    const h = el.getBoundingClientRect().height, m = parseFloat(getComputedStyle(el).marginTop);
    return { el, h, m, extent: m + h,
             keep: el === chat || STICKY_KEEPS.some((sel) => el.matches(sel)) };
  });
}

// How tall a row's lines that stay on its copy are, with its padding.
function stickyLeast(row) {
  const lines = stickyMeasure(row);
  return row.getBoundingClientRect().height - lines.reduce((sum, l) => sum + (l.keep ? 0 : l.extent), 0);
}

// Makes the copy of the row you're on, as it starts holding on and after each rebuild while it does, and measures it.
// Its chat line takes new text as the row's does, the old erasing and the new writing in (rewriteLine). A copy of other
// lines than before (a line came or went, or Claude's line gave way to yours) cross-fades in over the old one.
function stickyCopy() {
  const st = state.sticky, row = st.row, holder = stickyEl.querySelector('.sticky-copy');
  const chatLine = stickyChat(row), sel = chatLine?.matches('.claude') ? '.claude' : '.you';
  const chat = chatLine && { sel, text: partText(sel)(chatLine) };
  const shape = [...row.querySelector(':scope > .main').children].filter((l) => !l.matches('.folding'))
    .map((l) => l.classList[0]).join(' ');
  const old = st.copy?.parentNode === holder ? st.copy : null, oldChat = old && stickyChat(old);
  const was = oldChat && { el: oldChat, height: oldChat.getBoundingClientRect().height };
  const copy = stickyCopyOf(row);
  holder.style.width = stickyPx(row.getBoundingClientRect().width);
  if (old && shape !== st.shape && !calm.matches) {
    Object.assign(old.style, { position: 'absolute', left: '0', right: '0', top: '0' });
    holder.append(copy);
    tween(old, { opacity: '1' }, { opacity: '0' }, () => old.remove(), STICKY_FADE_MS);
    tween(copy, { opacity: '0' }, { opacity: '1' }, null, STICKY_FADE_MS);
  } else if (old) old.replaceWith(copy);
  else holder.replaceChildren(copy);
  const before = st.chat, same = shape === st.shape;
  Object.assign(st, { copy, chat, shape, lines: stickyMeasure(copy), full: copy.getBoundingClientRect().height,
                      copies: st.copies + 1, drawn: '' });
  const rewrites = was && same && before && chat && before.sel === chat.sel && before.text !== chat.text;
  if (rewrites && !calm.matches) rewriteLine(stickyChat(copy), was);
}

// After each rebuild of the list the row you're on is a new one, and while it holds on, so is its copy. When it's
// another session's, or none's, a copy holding on hands its tint over to that row as it slides away (stickyHandOff).
function stickyRefresh() {
  const st = state.sticky, row = focusedRow(document.getElementById('list')), sid = row?.dataset.id ?? null;
  if (sid !== st.sid) {
    if (st.edge && !st.leaving && !calm.matches) stickyHandOff();
    else if (st.edge) stickyLetGo(true);
    Object.assign(st, { sid, row, inView: false, lastT: null });
  } else {
    st.row = row;
    if (row && st.edge && !st.leaving) {
      row.inert = true;
      stickyCopy();
    }
  }
  stickyPlace();
}

// Lays the copy over the list's edge for where the row's place is now, or lets it go: as the list scrolls, and every
// frame anything else moves the list or the row in it (reportHeight), but only when something it's laid out for has
// changed (the scroll, the list's size and place, the row's place and size, its lines that stay, a new copy).
function stickyPlace() {
  const st = state.sticky, list = document.getElementById('list');
  // Folded into the cat, it stays as it was, fading with the list (base.css), and while it fades out, where it is.
  if (document.body.classList.contains('collapsed') || st.leaving) return;
  // A group sliding open takes the row's copy pinned below it away, for the row in it.
  if (st.row && !st.row.isConnected) st.row = focusedRow(list);
  const row = st.row?.dataset.id === st.sid ? st.row : null;
  if (!row) {
    if (st.edge) stickyLetGo(true);
    return;
  }
  // The list's visible part starts at the header's edge, wherever the header has slid to (headerInset, header.js).
  const ct = list.clientTop + headerInset(), lr = list.getBoundingClientRect(), rr = row.getBoundingClientRect();
  const root = list.parentElement.getBoundingClientRect(), top = lr.top + ct, left = lr.left + list.clientLeft;
  const t = rr.top - top, h = rr.height, v = list.clientHeight - headerInset(), w = list.clientWidth;
  const x = rr.left - left;
  // Where the copy has got to since it was last laid out, catching up with the row's place (stickyEase), or under
  // reduced motion, there at once. Past where it has folded all it can at `edge`, and attached, nothing more of it
  // changes, so it goes no further than that, and comes back from there. A frame or so at most has gone by: before
  // that, nothing was moving.
  const now = performance.now(), dt = Math.min(20, now - st.easedAt), lastT = st.lastT ?? t;
  const reach = (edge, y) => {
    const folded = stickyFolded();
    return edge === 'top' ? Math.max(y, folded - h) : Math.min(y, v - folded);
  };
  const catchUp = (edge, at, speed) => (calm.matches ? { at: reach(edge, t), speed: 0 }
    : stickyEase(at, speed, reach(edge, lastT), reach(edge, t), dt));
  st.easedAt = now;
  if (st.edge) Object.assign(st, catchUp(st.edge, st.at ?? t, st.speed));
  // Whether its top has moved toward the edge it's past since it was last looked at (at the bottom edge, from the
  // bottom edge, which a shorter list moves), not just its foot grown past the bottom one.
  const away = st.lastT != null && (t < -0.25 ? t < st.lastT - 0.1 : t - v > st.lastT - st.lastV + 0.1);
  const hold = stickyHold(t, h, v, { was: st.edge, inView: st.inView, away,
                                     typing: row.contains(document.activeElement),
                                     behind: !!st.edge && st.at !== reach(st.edge, t) });
  Object.assign(st, { inView: !stickyEdge(t, h, v), lastT: t, lastV: v });
  if (!hold.edge) {
    if (st.edge) stickyLetGo(hold.fade);
    return;
  }
  const started = !st.edge;
  if (hold.edge !== st.edge) {
    if (started) {
      row.inert = true;
      stickyCopy();
    }
    st.edge = hold.edge;
    st.drawn = '';
    cancelAnimationFrame(st.ramp);
    st.fade = hold.fade && !calm.matches ? 0 : 1;
    if (st.fade < 1) stickyRamp(1);
    // Taking over from the row in place, the copy starts where the row was last laid out, and catches up with it from
    // there; fading in, or at the other edge, it's where the row's place is.
    Object.assign(st, hold.fade ? { at: reach(st.edge, t), speed: 0 } : catchUp(st.edge, lastT, 0));
  }
  // Until it has caught up, it's laid out again each frame.
  cancelAnimationFrame(st.follow);
  if (st.at !== reach(st.edge, t)) st.follow = requestAnimationFrame(() => stickyPlace());
  // Its lines that stay as they are now (Claude's line may be easing between heights as it's rewritten).
  const lines = st.lines.map((l) => (l.keep ? { ...l, h: l.el.getBoundingClientRect().height } : l));
  lines.forEach((l) => { if (l.keep) l.extent = l.m + l.h; });
  const full = st.full + lines.reduce((sum, l, i) => sum + l.h - st.lines[i].h, 0);
  const drawn = [t, h, v, w, x, rr.width, top - root.top, full, st.copies, st.at].join(' ');
  if (drawn === st.drawn) return;
  st.drawn = drawn;
  // It's laid out for the row's place where the copy has got to: past the edge, folded to the part of it in view;
  // on its way back to the row, whole, where it has got to.
  const edge = st.edge, at = st.at, shown = Math.min(h, edge === 'top' ? at + h : v - at);
  const fold = stickyFold(lines, full, shown, edge);
  lines.forEach((line, i) => stickyFoldLine(st.lines[i], fold.folds[i], edge));
  // The band it covers. Its tint spreads from the row's sides to the list's as it attaches; rows under it are hidden
  // there, as they are under the header.
  const a = edge === 'top' ? Math.max(0, at) : Math.min(v, at + h) - fold.height, b = a + fold.height;
  Object.assign(st, { band: [a, b], clientTop: ct });
  const holder = stickyEl.querySelector('.sticky-copy'), tint = stickyUnder.querySelector('.sticky-tint');
  for (const layer of [stickyEl, stickyUnder]) {
    Object.assign(layer.style, { left: stickyPx(left - root.left), top: stickyPx(top - root.top), width: stickyPx(w),
                                 height: stickyPx(v) });
    layer.dataset.edge = edge;
    layer.classList.add('on');
  }
  Object.assign(holder.style, { left: stickyPx(x), top: stickyPx(a), height: stickyPx(b - a) });
  const attach = stickySmooth(fold.attach), spreadLeft = x * attach, spreadRight = (w - x - rr.width) * attach;
  Object.assign(tint.style, { left: stickyPx(x - spreadLeft), width: stickyPx(rr.width + spreadLeft + spreadRight),
                              top: stickyPx(a), height: stickyPx(b - a) });
  stickyUnder.style.setProperty('--attach', String(attach));
  st.attached = edge === 'top' && a <= 0 ? attach : 0;
  stickyShade();
  if (started && state.pointer) syncHover();  // what's under a pointer that hasn't moved may be the copy now
}

// How tall the copy is once it has folded all it can: its lines that stay, and at least STICKY_ATTACH short of all of
// it, so it's attached to the edge by then.
function stickyFolded() {
  const st = state.sticky, least = st.full - st.lines.reduce((sum, l) => sum + (l.keep ? 0 : l.extent), 0);
  return Math.min(least, st.full - STICKY_ATTACH);
}

// How far the row you're on has gone past the list's top beyond where its copy, held on there, has folded all it can:
// how far the copy would push the header away (header.js). 0 while it isn't held on at the top, or is going.
function stickyPush() {
  const st = state.sticky, list = document.getElementById('list');
  if (st.edge !== 'top' || st.leaving || !st.row?.isConnected) return 0;
  const r = st.row.getBoundingClientRect();
  const t = r.top - list.getBoundingClientRect().top - list.clientTop - headerInset();
  return Math.max(0, stickyFolded() - r.height - t);
}

// Folds a line of the copy by `f` points (stickyLineFold), or puts it back.
function stickyFoldLine(line, f, edge) {
  const s = line.el.style;
  if (f <= 0) {
    if (line.folded) Object.assign(s, { marginTop: '', marginBottom: '', clipPath: '', opacity: '' });
    line.folded = false;
    return;
  }
  const fold = stickyLineFold(line, f, edge);
  line.folded = true;
  Object.assign(s, { marginTop: stickyPx(fold.marginTop), marginBottom: stickyPx(fold.marginBottom),
                     clipPath: `inset(${stickyPx(fold.clip[0])} 0 ${stickyPx(fold.clip[1])} 0)`,
                     opacity: String(fold.opacity) });
}

// The copy's fade, coming or going (--fade), and the mask hiding the list under it, which fades the other way, so the
// rows there come back as the copy goes. Once the copy is wholly there, the row itself is hidden too (.sticky-away):
// WebKit scrolls the list a frame or so ahead of the page laying out the copy and the mask, and in a quick scroll the
// row's place would otherwise show past the mask's edge, the row there twice. As it attaches at the list's top, the
// line along that, under the header, goes too (`attached`), so the copy meets the header with no line between them:
// the header's own (headerLine, header.js), or with a card under the header, the list's top border, which the mask
// covers. As it slides off (stickyHandOff), what it uncovers of the part it covered comes back as it fades (`covered`,
// `back`), so the row's own lines there don't show beside the copy's going.
function stickyShade() {
  const st = state.sticky, list = document.getElementById('list');
  for (const layer of [stickyEl, stickyUnder]) layer.style.setProperty('--fade', String(st.fade));
  st.row?.classList.toggle('sticky-away', !!st.edge && !st.leaving && st.fade >= 1);
  const shown = (x) => `rgb(0 0 0 / ${Math.round(x * 1000) / 1000})`, [a, b] = st.band, m = st.clientTop;
  const [a0, b0] = st.covered ?? st.band, back = shown(st.back);
  const under = shown(1 - st.fade), line = shown(1 - st.attached * st.fade);
  list.style.webkitMaskImage = list.style.maskImage = `linear-gradient(to bottom, ${line} ${m}px, black ${m}px, `
    + `black ${m + a0}px, ${back} ${m + a0}px, ${back} ${m + a}px, ${under} ${m + a}px, ${under} ${m + b}px, `
    + `${back} ${m + b}px, ${back} ${m + b0}px, black ${m + b0}px)`;
  headerLine(1 - st.attached * st.fade);
}

// Eases the copy's fade to `to` (1, there; 0, gone), then runs `done`.
function stickyRamp(to, done) {
  const st = state.sticky, from = st.fade, start = performance.now();
  cancelAnimationFrame(st.ramp);
  const step = (now) => {
    const p = Math.min(1, (now - start) / STICKY_FADE_MS);
    st.fade = from + (to - from) * stickySmooth(p);
    stickyShade();
    if (p < 1) st.ramp = requestAnimationFrame(step);
    else done?.();
  };
  st.ramp = requestAnimationFrame(step);
}

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
  const out = edge === 'top' ? -b : list.clientHeight - headerInset() - a, layer = stickyUnder.getBoundingClientRect();
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

// Where the copy is under the pointer, while it holds on. It takes no pointer events itself, so a scroll over it
// scrolls the list; what's under it there is hidden, so the pointer (hover.js) and presses on it go to its tint. Only
// the list is hidden there: what's over the copy (a card that takes the pointer, or, folded, what's beside the folded
// panel, where the list has gone) keeps the pointer and its presses.
function stickyAt(x, y) {
  if (!state.sticky.edge || state.sticky.leaving) return null;
  const tint = stickyUnder.querySelector('.sticky-tint'), r = tint.getBoundingClientRect();
  const c = stickyEl.getBoundingClientRect();
  if (x < r.left || x >= r.right || y < Math.max(r.top, c.top) || y >= Math.min(r.bottom, c.bottom)) return null;
  return document.elementFromPoint(x, y)?.closest('#list') ? tint : null;
}

// A press on the copy scrolls the list back to the row, in one eased move, until it shows whole, and the row opens out
// into its place on the way. The row keeps its place in the list meanwhile, as one you've pressed does, and where it is
// is measured again each frame, so it gets there whatever else changes; scrolling by hand takes over.
function stickyBack() {
  const st = state.sticky, list = document.getElementById('list'), edge = st.edge;
  keepInPlace(st.sid);
  cancelAnimationFrame(st.mover);
  const by = () => {
    const r = st.row?.isConnected ? st.row.getBoundingClientRect() : null;
    if (!r) return 0;
    return r.top - list.getBoundingClientRect().top - list.clientTop - headerInset()
      - showAt(r.height, list.clientHeight - headerInset(), edge);
  };
  const first = by();
  if (calm.matches) {
    list.scrollTop += first;
    return stickyPlace();
  }
  const from = list.scrollTop, start = performance.now(), ms = Math.min(700, 260 + Math.abs(first) * 0.6);
  const ease = (p) => (p < 0.5 ? 4 * p * p * p : 1 - (-2 * p + 2) ** 3 / 2);
  const step = (now) => {
    const p = Math.min(1, (now - start) / ms), to = list.scrollTop + by();
    list.scrollTop = from + (to - from) * ease(p);
    stickyPlace();
    if (p < 1) st.mover = requestAnimationFrame(step);
  };
  st.mover = requestAnimationFrame(step);
}

// Scrolls the list just enough to show a row whole, SHOW_GAP inside the edge it comes in at, and clear of the copy of
// the row you're on, as the copy will be once the list has scrolled there: the session you've switched to, a new
// conversation's row. For the row you're on itself, the copy goes as the row comes into view.
function showInList(el) {
  const st = state.sticky, list = document.getElementById('list');
  // The list's visible part starts at the header's edge, wherever it has been pushed to: scrolling up leaves it there.
  const top = list.getBoundingClientRect().top + list.clientTop + headerInset(), v = list.clientHeight - headerInset();
  const r = el.getBoundingClientRect(), t = r.top - top, h = r.height;
  const held = el !== st.row && st.row?.isConnected && !st.row.contains(document.activeElement) ? st.row : null;
  const fr = held?.getBoundingClientRect(), least = held ? stickyLeast(held) : 0;
  const covers = (by) => (held ? stickyCovers(fr.top - top, fr.height, v, least, by) : [0, 0]);
  const [a, b] = covers(0), edge = t < a ? 'top' : t + h > v - b ? 'bottom' : null;
  if (!edge) return;
  let by = 0;
  for (let i = 0; i < 3; i++) by = t - showAt(h, v, edge, ...covers(by));
  list.scrollTop += by;
}

// A press on the copy, before anything under it in the list (or the page's own keyboard handling) sees it.
addEventListener('mousedown', (e) => {
  if (e.button !== 0 || !stickyAt(e.clientX, e.clientY)) return;
  e.preventDefault();
  e.stopPropagation();
  stickyBack();
}, true);

core.starts.push(() => {
  const list = document.getElementById('list');
  list.addEventListener('scroll', () => stickyPlace(), { passive: true });
  list.addEventListener('wheel', () => cancelAnimationFrame(state.sticky.mover), { passive: true });
  addEventListener('resize', () => stickyPlace());
});
core.afterDraw.push(stickyRefresh);
// Opening from the cat, it's laid out for the list as it is now, before the list fades in.
core.collapses.push((collapsed) => { if (!collapsed) stickyPlace(); });
core.pointerTargets.push('.sticky-tint');
