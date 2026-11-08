// The chats beside the folded panel going home into their rows as the panel opens round it, and back out as it folds:
// each pulled along its way as if on a spring, and its row taking over once it lands (chats.js places them).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// As the panel opens round the cat or folds back: the spring every chat is pulled by, into its row and back out (how
// much it's damped, and how quickly it goes), how far apart they set off, when the rest of the panel comes in round
// them as it opens, once the glass has spread out from behind the cat (kSpread, in PanelWindow+Private.h, and the
// moment it takes to start), and how long one takes to settle, when each row takes over from its chat, the list being
// in by then.
const CHAT_PULL_DAMPING = 0.68, CHAT_PULL_SPEED = 15, CHAT_PULL_STAGGER = 45;
const CHATS_LANDED_AT = 600, CHAT_PULLED_OUT = 800;

// --- Into the panel, and back out ---

const chatLerp = (a, b, p) => a + (b - a) * p, chatClamp = (v) => Math.min(1, Math.max(0, v));

// A chat pulled along its way between its place beside the cat (0) and its row in the list (1), as if on a spring:
// where it is on that way, and how fast it's going there (ways a second), `ms` after it set off from `from` at speed
// `v` toward `to`. From rest, it carries a little past `to` and settles back, as something with weight does; turned
// back on its way, it keeps the speed it had, slowing and turning as that would.
function chatSpring(from, v, to, ms) {
  const t = Math.max(0, ms) / 1000, w = CHAT_PULL_SPEED, z = CHAT_PULL_DAMPING, wd = w * Math.sqrt(1 - z * z);
  const a = from - to, b = (v + z * w * a) / wd, e = Math.exp(-z * w * t), c = Math.cos(wd * t), s = Math.sin(wd * t);
  return { at: to + e * (a * c + b * s), v: e * ((b * wd - z * w * a) * c - (a * wd + z * w * b) * s) };
}

// The panel opening round the cat with chats out beside it (foldPanel, in panel.js), from a press on the cat or with
// the pointer resting on it: each chat is pulled home into its row in the list, as if on a spring, the lowest first, so
// each moves into room already clear, shedding its card as it nears its row (its pin, its × and the time round it,
// colour and shadow), and its row takes over there once the list is in. One whose row is only partly in the list's
// sight lands there all the same, cut by the list's edge as its row is; one whose row is out of sight slides under the
// list's edge on that side. One that's the session you're on, held at the list's edge (sticky.js), becomes that held
// row on its way, in the same move (chatFlight). One still on its way back out of its row, the folded cat's list having
// gone back in a moment ago (chatsLeave), turns back where it is, keeping its speed. Meanwhile the rest of the panel
// waits out of sight (chats.css) until the glass has spread out from behind the cat: the app keeps all the room the
// chats need till then (foldMoving, in PanelWindow+Fold.m). Under reduced motion, each fades where it is. Says
// whether any were out.
function chatsLand() {
  const st = state.chats, body = document.body.classList;
  const back = [...st.flights.values()].filter((f) => f.drive.to === 0);
  // One still waiting to come out, never seen beside the cat, has no way into its row to show: it just goes. One
  // waiting to move up, or riding the one before it as that shrinks (chatRideStop), flies from where it is.
  for (const c of st.out) {
    const f = chatFrames.get(c.sid);
    clearTimeout(f?.moveTimer);
    if (f) f.ride = chatRideStop(f.el, f.ride);
    if (!f?.coming) continue;
    clearTimeout(f.comeTimer);
    chatFrames.delete(c.sid);
    chatGoesAway(f.el);
  }
  const frames = st.out.map((c) => [c.sid, chatFrames.get(c.sid)])
    .filter(([, f]) => f?.placed && !f.tucked && !f.flying);
  if (!frames.length && !back.length) return false;
  if (calm.matches) {
    for (const [sid, f] of frames) {
      chatFrames.delete(sid);
      chatGoesAway(f.el);
    }
    return true;
  }
  stickyPlace();  // the row you're on, held at an edge of the list as it now is, for a chat that becomes it
  // The lowest first: the last going down from the cat, the first going up from it.
  const band = listBand(), n = frames.length, up = state.cat.way.up;
  for (const f of back) chatTurns(f, 1);
  frames.forEach(([sid, f], i) => chatFlight(sid, f, band, 0, (up ? i : n - 1 - i) * CHAT_PULL_STAGGER));
  body.add('chats-landing');
  body.remove('chats-landed', 'chats-leaving');
  heldLayersAtOnce(() => {
    body.toggle('held-landing', [...st.flights.values()].some((f) => f.held));
    body.remove('held-leaving');
  });
  chatsLandingRows();
  clearTimeout(st.landTimer);
  st.landTimer = setTimeout(() => { body.remove('chats-landing'); body.add('chats-landed'); }, CHATS_LANDED_AT);
  chatsFlying();
  return true;
}

// The folded cat's list going back in as the pointer leaves it (peekGoes, in peek.js), with chats still out (pinned, or
// with time left): each is pulled back out from its row to its place beside it, top first, taking its card back as it
// lifts off the list, and its pin, × and the time round it once it's there; one held at the list's edge turns back into
// its chat on its way, in the same move; one whose row is out of sight comes out from under the list's edge. One still
// on its way into its row, the list having only just come out, turns back where it is, keeping its speed. The list
// fades and the glass closes round the cat meanwhile. Says the room they go to, as askChatRoom names it, for the app to
// keep as it folds; none with nothing out, or under reduced motion, when they come out of the cat afterwards.
function chatsLeave() {
  const st = state.chats, body = document.body.classList;
  if (calm.matches) return null;
  const out = new Set(st.out.map((c) => c.sid));
  const back = [...st.flights.values()].filter((f) => f.drive.to === 1 && out.has(f.sid)
    && chatFrames.get(f.sid) === f.frame);
  const frames = st.out.map((c) => [c.sid, chatFrames.get(c.sid)]).filter(([, f]) => f?.placed && !f.flying);
  if (!back.length && !frames.length) return null;
  // One waiting to come out beside the cat comes out of its row instead, with the rest, as does one waiting to move or
  // riding the one before it.
  for (const [, f] of frames) {
    clearTimeout(f.comeTimer);
    clearTimeout(f.moveTimer);
    f.ride = chatRideStop(f.el, f.ride);
    f.coming = false;
    f.el.classList.remove('coming');
  }
  // The top first: the first going down from the cat, the last going up from it.
  const band = listBand(), at = state.cat.at, n = frames.length, up = state.cat.way.up;
  clearTimeout(st.landTimer);
  for (const f of back) chatTurns(f, 0);
  const flights = [...back, ...frames.map(([sid, f], i) =>
    chatFlight(sid, f, band, 1, (up ? n - 1 - i : i) * CHAT_PULL_STAGGER))];
  for (const f of flights) f.row?.classList.add('chat-landing');
  body.add('chats-leaving');
  body.remove('chats-landing', 'chats-landed');
  heldLayersAtOnce(() => {
    body.toggle('held-leaving', flights.some((f) => f.held));
    body.remove('held-landing');
  });
  chatsFlying();
  return flights.map((f) => [f.home.x - at.x, f.home.y - at.y, f.el.offsetWidth, f.fullHeight]);
}

// One chat's way between its place beside the cat and its row, setting off from `from` (0 beside the cat, 1 in its
// row) after `delay` ms, measured at both ends: its place beside the cat in #chats (`home`), and on the page; its row's
// place, or where it slides under the list's edge (`band`) when its row is out of sight, and how far past that edge it
// is beside the cat, as it's cut there only on its row's side; the row it hands over to or leaves (`row`), when that's
// in sight; for the session you're on held at the list's edge, the held row it becomes (`held`): its lines, as
// sticky.js measures and folds them, and the held row's place; and where the list shows its row briefly, the look it
// takes on its way (`look`: chatLook). `at(now)` puts it where it is then.
function chatFlight(sid, frame, band, from, delay) {
  const el = frame.el, inside = el.querySelector('.chat-row > .row');
  el.classList.remove('tucked');
  el.classList.add('landing');
  Object.assign(el.style, { transition: 'none', opacity: '1', visibility: 'visible' });
  const chats = chatsEl.getBoundingClientRect(), home = frame.placed;
  const homeAt = { left: chats.left + home.x, top: chats.top + home.y };
  // Where its row is laid out inside it.
  const rowIn = { x: frame.row.offsetLeft + inside.offsetLeft, y: frame.row.offsetTop + inside.offsetTop };
  const fullHeight = el.offsetHeight;
  frame.flying = true;
  frame.tall = fullHeight;
  const f = { sid, el, frame, home, fullHeight, band, row: null, held: null, u: from, v: 0, settled: false,
              chrome: 1 - from, drawnAt: 0, drive: { from, v: 0, to: 1 - from, at: performance.now(), delay } };
  state.chats.flights.set(sid, f);
  state.settleUntil = Math.max(state.settleUntil, performance.now() + delay + CHAT_PULLED_OUT + 100);
  const row = rowInView(sid), target = row?.getBoundingClientRect();
  const held = heldRowOf(sid);
  // A chat that isn't its row as the list has it (a brief row, or one saying a module's line in Claude's place) takes
  // the row's look on its way, so nothing jumps as it hands over.
  if (row?.classList.contains('brief') || frame.said)
    f.look = held ? chatLook(inside, held.copy, held.kept) : chatLook(inside, row);
  if (held) {
    const holder = stickyEl.querySelector('.sticky-copy').getBoundingClientRect();
    const lines = stickyMeasure(inside, f.look?.has), full = inside.getBoundingClientRect().height;
    const least = f.look?.height ?? full - lines.reduce((sum, l) => sum + (l.keep ? 0 : l.extent), 0);
    Object.assign(f, { held: { lines, full, least, edge: held.edge, holder, homeAt, rowIn }, row });
    f.at = (now) => { chatDrive(f, now); chatHeldAt(f, f.u); };
    return f;
  }
  const seen = !!target && target.bottom > band.top && target.top < band.bottom;
  // Out of sight, it's just past the list's edge on its row's side, under the edge; with no row, under the foot.
  const h = f.look ? target.height : inside.getBoundingClientRect().height;
  let y = target ? target.top : band.bottom + 4;
  if (target && !seen) y = target.bottom <= band.top ? band.top - h - 4 : band.bottom + 4;
  const rowAt = { left: (target ? target.left : homeAt.left + rowIn.x) - rowIn.x, top: y - rowIn.y };
  const past = (top) => ({ top: Math.max(0, band.top - top), bottom: Math.max(0, top + fullHeight - band.bottom) });
  Object.assign(f, { a: homeAt, b: rowAt, start: past(homeAt.top), row: seen ? row : null,
                     cut: { top: y < band.top, bottom: y + h > band.bottom } });
  if (f.look) Object.assign(f.look, { lines: stickyMeasure(inside, f.look.has),
                                      end: fullHeight - inside.offsetHeight + f.look.height });
  f.at = (now) => { chatDrive(f, now); chatPulledAt(f, now); };
  return f;
}

// The look a chat takes on its way into a row the list shows briefly (a grouping's one line), where the chat is the row
// whole, or into its row from saying a module's line in Claude's place (a reply in its side chat): a copy of that row
// as the list has it, or as it's held at the list's edge (with `kept`, the lines of it that stay there), over the
// chat's own row, out of sight till it fades in (chatLookAt); which of the chat's lines it has too (`has`: the copy's,
// without one folding away in the list), how tall it is, and how far the chat's lines and dot are from where the row
// has them (`moves`: a brief row is laid out a little tighter).
function chatLook(inside, of, kept = null) {
  const copy = kept ? of.cloneNode(true) : stickyCopyOf(of);
  copy.classList.remove('chat-landing', 'sticky-away');
  Object.assign(copy.style, { position: 'absolute', left: `${inside.offsetLeft}px`, top: `${inside.offsetTop}px`,
                              width: `${inside.offsetWidth}px`, margin: '0', opacity: '0' });
  inside.after(copy);
  keepInStep(copy);
  const lines = new Set((kept ?? [...copy.querySelector(':scope > .main').children]).map((l) => l.classList[0]));
  const top = (row, sel) => row.querySelector(sel).getBoundingClientRect().top;
  const moves = [':scope > .main', ':scope > .dot'].map((sel) =>
    ({ el: inside.querySelector(sel), by: top(copy, sel) - top(inside, sel) }));
  return { copy, inside, moves, has: (el) => lines.has(el.classList[0]), height: copy.offsetHeight };
}

// A chat taking its row's look (chatLook), `k` of the way into its row: in the first part of the way, its own lines
// that the row hasn't fold away together, each as a held row's line does (sticky.js), and its lines and dot move to
// where the row has them, so it comes to the row's shape; then the row's look fades in over it, and only once it's
// all there does the chat's own go, so what's in both never dims. Going back out, the other way round. The held row's
// way folds its lines and sets its height itself (chatHeldAt). Says how tall it is.
function chatLookAt(f, k) {
  const L = f.look, folded = chatClamp(k / 0.6);
  for (const { el, by } of L.moves) el.style.transform = `translateY(${(by * folded).toFixed(2)}px)`;
  L.copy.style.opacity = chatClamp((k - 0.6) / 0.25).toFixed(3);
  L.inside.style.opacity = (1 - chatClamp((k - 0.85) / 0.15)).toFixed(3);
  if (f.held) return 0;
  for (const line of L.lines) if (!line.keep) stickyFoldLine(line, line.extent * folded, 'top');
  const tall = chatLerp(f.fullHeight, L.end, folded);
  f.el.style.height = `${tall.toFixed(2)}px`;
  return tall;
}

// Where the spring has a chat on its way at `now` (`u`, and its speed `v`), and whether it has settled.
function chatDrive(f, now) {
  const d = f.drive, ms = now - d.at - d.delay;
  const { at, v } = chatSpring(d.from, d.v, d.to, Math.min(Math.max(0, ms), CHAT_PULLED_OUT));
  f.u = at;
  f.v = v;
  f.settled = ms >= CHAT_PULLED_OUT;
}

// A chat on its way turned back toward `to` (its row, 1, or its place beside the cat, 0) from where it is now, at the
// speed it's going.
function chatTurns(f, to) {
  const now = performance.now();
  chatDrive(f, now);
  f.drive = { from: f.u, v: f.v, to, at: now, delay: 0 };
  f.settled = false;
  state.settleUntil = Math.max(state.settleUntil, now + CHAT_PULLED_OUT + 100);
}

// A chat pulled between its place beside the cat and its row, as far as its spring has it (`u`), at `now`: where it is,
// its card shed as it nears its row and taken back as it lifts off it, its pin, × and the time round it going as it
// sets off for its row and coming back once it's home, taking the look the row has in the list (chatLookAt), and cut
// where it's past the list's edge on its row's side, as much as it wasn't past it already beside the cat.
function chatPulledAt(f, now) {
  const d = f.drive, u = f.u, p = chatClamp(u), since = now - d.at - d.delay;
  const left = chatLerp(f.a.left, f.b.left, u), top = chatLerp(f.a.top, f.b.top, u);
  const chats = chatsEl.getBoundingClientRect();
  f.el.style.transform = chatTransform({ x: left - chats.left, y: top - chats.top });
  const dt = f.drawnAt ? now - f.drawnAt : 0;
  f.drawnAt = now;
  f.chrome = (d.to === 1 ? since < 0 : since >= 380) ? Math.min(1, f.chrome + dt / 160)
    : Math.max(0, f.chrome - dt / 140);
  const card = chatClamp(Math.hypot(f.b.left - left, f.b.top - top) / 60);
  chatLooks(f.el, { base: card, chrome: f.chrome, away: p });
  const tall = f.look ? chatLookAt(f, p) : f.fullHeight;
  let cutTop = 0, cutBottom = 0;
  if (f.cut.top) cutTop = Math.max(0, f.band.top - top - f.start.top * (1 - p));
  if (f.cut.bottom) cutBottom = Math.max(0, top + tall - f.band.bottom - f.start.bottom * (1 - p));
  f.el.style.clipPath = cutTop || cutBottom ? `inset(${cutTop.toFixed(1)}px 0 ${cutBottom.toFixed(1)}px 0)` : '';
}

// How much of a chat's card shows (its colour and shadow, `base`, for the .chat-base it fades), of its pin, × and the
// time round it (`chrome`), of the held row's tint (`tint`), and how far it is from being a chat (`away`: its title line
// taking the row's own room). Each is set on the chat as a custom property of that name, so none may share a token's
// name in tokens.css: where it isn't set yet, the chat would read the token's colour as a number.
function chatLooks(el, looks) {
  for (const [name, value] of Object.entries(looks)) el.style.setProperty('--' + name, value.toFixed(3));
}

// The chat of the session you're on, between its place beside the cat and the held row at the list's edge, `u` of the
// way (the spring's): it moves and changes shape as one, its lines folding as the held row's do (sticky.js, the one
// nearest the edge first), its tint coming in across the list, its corners squaring off against the edge, its shadow
// and padding going, so it has the held row's shape exactly as it stops there, and its look where the list shows it
// briefly (chatLookAt); going back out, the other way round.
function chatHeldAt(f, u) {
  const H = f.held, k = chatClamp(u);
  const visible = H.full - k * (H.full - H.least);
  const fold = stickyFold(H.lines, H.full, visible, H.edge);
  H.lines.forEach((line, i) => stickyFoldLine(line, fold.folds[i], H.edge));
  const padTop = H.rowIn.y * (1 - k), padBottom = (f.fullHeight - H.rowIn.y - H.full) * (1 - k);
  const height = padTop + visible + padBottom;
  // Its place as a card beside the cat, and as the held row: its row on the held row's copy.
  const left = chatLerp(H.homeAt.left, H.holder.left - H.rowIn.x, u);
  const top = H.edge === 'top' ? chatLerp(H.homeAt.top, H.holder.top, u)
    : chatLerp(H.homeAt.top + f.fullHeight, H.holder.bottom, u) - height;
  const chats = chatsEl.getBoundingClientRect(), el = f.el;
  el.style.transform = chatTransform({ x: left - chats.left, y: top - chats.top });
  el.style.paddingTop = `${padTop.toFixed(2)}px`;
  el.style.paddingBottom = `${padBottom.toFixed(2)}px`;
  el.style.height = `${height.toFixed(2)}px`;
  // Its corners: square against the edge, the held row's on its other side. Its card goes once it's over the glass, so
  // the held row's own glass and tint show through, as they will once it hands over.
  const near = 14 * (1 - k), far = 14 + (8 - 14) * k;
  el.style.borderRadius = H.edge === 'top' ? `${near}px ${near}px ${far}px ${far}px`
    : `${far}px ${far}px ${near}px ${near}px`;
  chatLooks(el, { base: 1 - chatClamp((k - 0.7) / 0.3), tint: k, chrome: 1 - chatClamp(1.6 * k), away: k });
  if (f.look) chatLookAt(f, k);
}

// Moves every chat on its way into its row or back out a frame at a time, each from when it set off, until all have
// settled (chatsFlown).
function chatsFlying() {
  const st = state.chats;
  cancelAnimationFrame(st.flyFrame);
  const step = (now) => {
    let moving = false;
    for (const f of st.flights.values()) {
      f.at(now);
      moving = moving || !f.settled;
    }
    st.flyFrame = moving ? requestAnimationFrame(step) : 0;
    if (!moving) chatsFlown();
  };
  step(performance.now());
}

// All have settled: those back beside the cat are ordinary chats again, and the rows take over from those in them.
function chatsFlown() {
  const st = state.chats;
  for (const f of [...st.flights.values()]) {
    if (f.drive.to !== 0) continue;
    st.flights.delete(f.sid);
    chatSettled(f);
  }
  document.body.classList.remove('chats-leaving', 'held-leaving');
  if (st.flights.size) chatsLanded(false);
}

// A chat pulled back out beside the cat has got there: it's an ordinary chat again, where its place is. Or one that
// has landed in its row while the folded cat's list is out (`tucked`): it stays out beside the cat, out of sight there
// till the list goes back in, when it's pulled back out of its row.
function chatSettled(f, tucked = false) {
  const el = f.el, frame = f.frame;
  frame.flying = false;
  f.row?.classList.remove('chat-landing');
  if (!el.isConnected) return;
  el.classList.remove('landing');
  for (const prop of ['clipPath', 'paddingTop', 'paddingBottom', 'height', 'borderRadius', 'visibility'])
    el.style[prop] = '';
  for (const prop of ['--base', '--tint', '--chrome', '--away']) el.style.removeProperty(prop);
  for (const line of f.held?.lines ?? []) stickyFoldLine(line, 0, f.held.edge);
  for (const line of f.look?.lines ?? []) stickyFoldLine(line, 0, 'top');
  f.look?.copy.remove();
  if (f.look) f.look.inside.style.opacity = '';
  for (const { el } of f.look?.moves ?? []) el.style.transform = '';
  el.style.opacity = tucked ? '0' : '1';
  el.classList.toggle('tucked', tucked);
  el.style.transform = chatTransform(tucked ? chatTowardCat(frame.placed) : frame.placed);
  void el.offsetWidth;
  el.style.transition = '';
  frame.tucked = tucked;
  startChatClock();
}

// The rows the chats land on or leave stay out of sight while they move, the list being drawn again or not.
function chatsLandingRows() {
  for (const f of state.chats.flights.values()) {
    f.row = f.row?.isConnected ? f.row : f.row && rowInView(f.sid);
    f.row?.classList.add('chat-landing');
  }
}

// The landing is over (or cut short, the panel folding again: `fading`): each row takes over from its chat, which
// goes, at once where it has landed, or fading where the panel folds, unless its chat is still out beside the folded
// cat, its list out (chatSettled); and the held row's copy shows in its place.
function chatsLanded(fading) {
  const st = state.chats, body = document.body.classList;
  clearTimeout(st.landTimer);
  for (const f of [...st.flights.values()]) {
    if (f.drive.to !== 1) continue;
    st.flights.delete(f.sid);
    if (!fading && chatFrames.get(f.sid) === f.frame) {
      chatSettled(f, true);
      continue;
    }
    if (chatFrames.get(f.sid) === f.frame) chatFrames.delete(f.sid);
    if (fading) chatGoesAway(f.el);
    else f.el.remove();
    f.row?.classList.remove('chat-landing');
  }
  if (!st.flights.size) cancelAnimationFrame(st.flyFrame);
  heldLayersAtOnce(() => body.remove('held-landing'));
  body.remove('chats-landing');
  setTimeout(() => body.remove('chats-landed'), fading ? 0 : 250);
}

// The held row's copy and tint (sticky.js) shown or hidden at once by `change`, in step with the chat taking over from
// them or handing over to them, whatever fades the rest of the panel meanwhile.
function heldLayersAtOnce(change) {
  for (const layer of [stickyEl, stickyUnder]) layer.style.setProperty('transition', 'none', 'important');
  change();
  void stickyEl.offsetWidth;
  requestAnimationFrame(() => {
    for (const layer of [stickyEl, stickyUnder]) layer.style.removeProperty('transition');
  });
}

// The panel opening: what's out is counted as seen, as the list shows it all, having gone into its rows (chatsLand);
// folding again before they've landed, they fade where they are, but for those turned back out (chatsLeave).
core.collapses.push((collapsed) => {
  if (collapsed && [...state.chats.flights.values()].some((f) => f.drive.to === 1)) chatsLanded(true);
  drawChats(chatsPlaced, state.last.now);
});
core.afterDraw.push(() => { if (state.chats.flights.size) chatsLandingRows(); });
