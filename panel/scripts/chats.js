// The chats beside the folded cat. While the panel is folded, a session that comes to need you (a request, a question,
// a plan, or a reply you haven't read) comes out beside the cat by itself, as its row, the list's own (rowHTML), so
// it's answered or opened there as it would be in the list. Newest first, as the list has them, nearest the cat, three
// at most: a new one comes out on top, and the oldest of three goes back in to wait, with a pill under the chats saying
// how many wait. Each stays out a while, the time it has left shrinking along its foot: pointing at it, typing in it,
// pinning it, or being in its session's tab, as pressing it puts you, holds it out; and while you hold one, nothing
// new comes out or moves, and what's new waits. It goes back into the cat once it's answered or answered elsewhere, or
// read, unless you're in its tab, when its time runs out, or when its × is pressed: it comes out again only when
// something new happens in its session. The one below moves up, and the newest waiting comes out under the rest. The
// app gives them the room beside the cat that they need, letting clicks through everywhere else (catRoom, in
// app/core/PanelWindow.m); they go toward the screen's middle, and up from the cat while it's low on the screen.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// How long a chat stays out by itself; how many are out at once, at most; how far a chat's near end is from the cat's
// glass's middle, clear of the cat's square, which the app keeps for pressing and dragging the cat; how far apart the
// chats are, and the pill from the last; how far the cat's glass reaches from its middle (76 across); and how much of
// the screen's edge the chats keep clear of.
const CHAT_MS = 45000, CHATS_MOST = 3, CHAT_FROM = 56, CHATS_GAP = 10, CHAT_PILL_GAP = 6, CHAT_GLASS_R = 38;
const CHAT_CLEAR = 8;
// How long after the app last saw you in a session's tab (its seenAt, which keeps moving while you're there, once
// you've been there a moment) you're taken to be there still, as the rows come about once a second; and how long after
// you've opened one from here, before the app has seen you there.
const CHAT_LOOKED_MS = 2500, CHAT_OPENED_MS = 4000;
// How long a chat takes to come out, move up or go back, and to go in for now as the cat is moved (chats.css), and how
// far toward the cat one starts or goes.
const CHAT_MOVE_MS = 420, CHAT_TUCK_MS = 160, CHAT_SLIDE = 40;
// As the panel opens round the cat or folds back: the spring every chat is pulled by, into its row and back out (how
// much it's damped, and how quickly it goes), how far apart they set off, when the rest of the panel comes in round
// them as it opens, once the glass has spread out from behind the cat (kSpread, in app/core/PanelWindow.m, and the
// moment it takes to start), and how long one takes to settle, when each row takes over from its chat, the list being
// in by then.
const CHAT_PULL_DAMPING = 0.68, CHAT_PULL_SPEED = 15, CHAT_PULL_STAGGER = 45;
const CHATS_LANDED_AT = 600, CHAT_PULLED_OUT = 800;

// --- What comes out, and where: plain functions ---

// What's new in a session that brings its chat out, so the same thing never brings it out twice: its request (by its
// id), a wait without one (by when it began), or a reply you haven't read (by when it came); null for anything else.
function chatNews(s, kind) {
  if (s.pending) return null;
  if (kind === 'needs') return s.ask ? `ask:${s.ask.id}` : `wait:${s.statusUpdatedAt || 0}`;
  if (kind === 'turn') return `reply:${s.lastReplyAt || 0}`;
  return null;
}

// What's out and what waits once the rows have come in again. `chats` is as it was: { out: [{ sid, news, left, kept }],
// done: { sid: news }, seeded }, `done` holding what of each session has been seen, so it doesn't come out again.
// `rows` are the list's, each { sid, news, on } (chatNews; `on`: you're in its session's tab now, chatLookedAt), in its
// order, newest first. `rule` says whether the panel is open (what it shows counts as seen), whether nothing may come
// out now (`quiet`: the cat is being moved, or its list is out), whether you hold one of those out (`holding`: pointing
// at it, typing in it, or in its tab), and how many may be out (`most`). Returns the new { out, queue, done, seeded },
// `queue` being those waiting, newest first, and which sessions' chats came out and which went.
function chatsStep(chats, rows, rule) {
  const done = { ...chats.done }, byId = new Map(rows.map((r) => [r.sid, r]));
  // Seen in the open panel, or there as the page loaded (the app restarted, or Deploy put a new build in place):
  // nothing of that comes out.
  if (rule.open || !chats.seeded) {
    for (const r of rows) if (r.news) done[r.sid] = r.news;
    return { out: [], queue: [], done, seeded: true, came: [], went: chats.out.map((c) => c.sid) };
  }
  // One stays out while you're in its session's tab, whatever it has to say now; otherwise it goes once its session has
  // nothing new for you (answered, here or elsewhere, read, or ended). Something newer in it keeps it out, its time
  // starting again.
  const kept = [], went = [];
  for (const c of chats.out) {
    const r = byId.get(c.sid);
    if (r && (r.on || r.news)) kept.push(r.news && r.news !== c.news ? { ...c, news: r.news, left: CHAT_MS } : c);
    else went.push(c.sid);
  }
  // What's new in the tab you're in is seen there; the rest waits, newest first.
  const outIds = new Set(kept.map((c) => c.sid)), waiting = [];
  for (const r of rows) {
    if (!r.news || outIds.has(r.sid) || done[r.sid] === r.news) continue;
    if (r.on) done[r.sid] = r.news;
    else waiting.push({ sid: r.sid, news: r.news });
  }
  if (rule.quiet || rule.holding) return { out: kept, queue: waiting, done, seeded: true, came: [], went };
  // Newest first, pinned ones staying out: those that fit come out, and an older one that doesn't goes back in to wait.
  const place = new Map(rows.map((r, i) => [r.sid, i])), order = (a, b) => place.get(a.sid) - place.get(b.sid);
  const pinned = kept.filter((c) => c.kept);
  const rest = [...kept.filter((c) => !c.kept), ...waiting.map((w) => ({ ...w, left: CHAT_MS, kept: false }))]
    .sort(order);
  const room = Math.max(0, rule.most - pinned.length), back = rest.slice(room);
  const out = [...pinned, ...rest.slice(0, room)].sort(order);
  for (const c of back) if (outIds.has(c.sid)) went.push(c.sid);
  return { out, queue: back.map(({ sid, news }) => ({ sid, news })), done, seeded: true,
           came: out.filter((c) => !outIds.has(c.sid)).map((c) => c.sid), went };
}

// Whether you're in a session's tab now: it's the one you're on, and the app has just seen you there (`seenAt`, as of
// the rows' time `now`), or you opened it from here a moment ago (`opened`, { sid, ago }), before the app could have.
function chatLookedAt(s, now, opened) {
  if (!s.focused) return false;
  return now - (s.seenAt || 0) < CHAT_LOOKED_MS || (opened?.sid === s.sessionId && opened.ago < CHAT_OPENED_MS);
}

// A chat sent back into the cat (its time ran out, or its × was pressed): what it said counts as seen.
function chatsBack(chats, sid) {
  const c = chats.out.find((x) => x.sid === sid);
  if (!c) return chats;
  return { ...chats, out: chats.out.filter((x) => x !== c), done: { ...chats.done, [sid]: c.news } };
}

// The chats `dt` ms on: each not held (`held(chat)`: pinned, in for now, or while you hold one of them) has that much
// less time. Returns those still out, and those whose time has run out.
function chatsTick(out, dt, held) {
  const still = [], expired = [];
  for (const c of out) {
    const left = held(c) ? c.left : Math.max(0, c.left - dt);
    (left > 0 ? still : expired).push({ ...c, left });
  }
  return { out: still, expired };
}

// How many chats, `heights` tall, fit one after another with CHATS_GAP between them in `tall` points: the first always.
function chatsFit(heights, tall) {
  let used = 0, n = 0;
  for (const h of heights) {
    if (n && used + CHATS_GAP + h > tall) break;
    used += (n ? CHATS_GAP : 0) + h;
    n++;
  }
  return n;
}

// Where the chats go beside the cat, its glass's middle at `at` ({ x, y }, in the list's own points), `way` as the app
// says (catWay): each `wide` chat's near end CHAT_FROM from the glass's middle, to its right or left; the first level
// with the glass's top and the rest under it, or, going up, the first level with its foot and the rest above it; then
// the pill, `pill` tall. Each place is a top-left corner, { x, y }, y running down.
function chatsLayout(heights, way, wide, at, pill) {
  const x = Math.round(way.right ? at.x + CHAT_FROM : at.x - CHAT_FROM - wide);
  const chats = [];
  let edge = way.up ? at.y + CHAT_GLASS_R : at.y - CHAT_GLASS_R;
  for (const h of heights) {
    chats.push({ x, y: Math.round(way.up ? edge - h : edge) });
    edge = way.up ? edge - h - CHATS_GAP : edge + h + CHATS_GAP;
  }
  const end = way.up ? edge + CHATS_GAP - CHAT_PILL_GAP - pill : edge - CHATS_GAP + CHAT_PILL_GAP;
  return { chats, pill: { x, y: Math.round(end) } };
}

// --- Drawing them ---

const chatsEl = document.getElementById('chats');
// A press on a chat's row does what it would in the list.
takesPresses(chatsEl);
// Each chat's frame, kept by its session as long as it's out (its row drawn in it afresh with each update), the rows
// last placed, and the pill under the chats.
const chatFrames = new Map();
let chatsPlaced = [], chatMoreEl = null;

// With each update (render, in panel.js): what comes out, what goes back, and each chat's row as it is now. The panel
// open while the folded cat's list is out (peek.js) doesn't count: they come back out as it folds back.
function drawChats(placed, now) {
  chatsPlaced = placed;
  const st = state.chats;
  const open = (!document.body.classList.contains('collapsed') && !state.peek.open) || state.cat.arriving;
  // A session opened from here (openSession, in input.js) is the tab you're in from then.
  if (state.opening) st.opened = { sid: state.opening.sessionId, at: state.opening.at };
  const opened = st.opened && { sid: st.opened.sid, ago: Date.now() - st.opened.at };
  const rows = placed.map(({ s, kind }) => ({ sid: s.sessionId, news: chatNews(s, kind),
                                             on: chatLookedAt(s, now, opened) }));
  st.inTab = rows.filter((r) => r.on).map((r) => r.sid);
  // What's kept of a session's chat goes a minute after the session has (FORGET_MS, in panel.js).
  for (const sid of Object.keys(st.done))
    if (!rows.some((r) => r.sid === sid) && Date.now() - (state.listedAt[sid] ?? state.loadedAt) > FORGET_MS)
      delete st.done[sid];
  const was = st.out.map((c) => c.sid), held = chatsHeld();
  st.holding = st.out.some((c) => held(c.sid));
  const next = chatsStep(st, rows, { open, quiet: chatsQuiet(), holding: st.holding, most: st.fits });
  Object.assign(st, { out: next.out, queue: next.queue, done: next.done, seeded: next.seeded });
  for (const sid of next.went) chatGoes(sid, open ? 'open' : was.indexOf(sid) === 0 ? 'cat' : 'up');
  placeChats(new Map(placed.map((p) => [p.s.sessionId, p])), now, next.came);
}

// Whether you hold a session's chat out now: pointing at it, typing in it, or in its session's tab.
function chatsHeld() {
  const p = state.pointer, st = state.chats;
  const pointed = p && document.elementFromPoint(p.x, p.y)?.closest?.('.chat')?.dataset.chat;
  const typed = document.activeElement?.closest?.('.chat')?.dataset.chat;
  return (sid) => sid === pointed || sid === typed || st.inTab.includes(sid);
}

// Nothing comes out, and what's out goes in for now, while the cat is being moved, its list is out (peek.js), it's
// folding or opening, or the panel is opening for the reader (a press on a chat).
function chatsQuiet() {
  const body = document.body.classList;
  return state.chats.moving || state.peek.open || state.cat.fromSide || !!state.reading
    || body.contains('departing') || body.contains('arriving');
}

// Each chat out, drawn, then measured and placed beside the cat (layChats).
function placeChats(byId, now, came) {
  const st = state.chats, way = state.cat.way;
  // A chat is as tall as its row, up to as far as the screen goes beside the cat, where its row scrolls.
  chatsEl.style.setProperty('--chat-most', `${Math.max(CHAT_FROM * 2, way.tall - CHAT_CLEAR)}px`);
  for (const c of st.out) {
    const p = byId.get(c.sid);
    if (!p) continue;
    const frame = chatFrames.get(c.sid) || makeChatFrame(c.sid);
    frame.el.classList.toggle('chat-needs', p.kind === 'needs');
    frame.el.classList.toggle('kept', c.kept);
    // One on its way into its row or back out keeps its row as it measured it, its lines folding as it goes
    // (chatFlight); and one with a word being composed in its box isn't drawn again, which would throw the word away.
    const composing = state.composing && frame.el.contains(document.activeElement);
    if (!frame.flying && !composing) morph(frame.row, rowHTML(p.s, p.kind, now));
  }
  layChats(came);
  startChatClock();
}

// The chats out measured and placed beside the cat; those that don't fit before the screen's edge, with the pill under
// them while more wait, wait at the queue's head, unseen, and fewer come out until the first has gone back. Each is
// measured as tall as its row is growing or shrinking to (atMorphEnd), and the room they need is asked for before any
// comes out or moves (askChatRoom), so the window's edge never cuts one off. While you hold one, those out keep their
// places, a gap left where one went, until you let go.
function layChats(came) {
  const st = state.chats, way = state.cat.way, at = state.cat.at;
  // One on its way into its row or back out counts as tall as it is beside the cat, whatever it's folded to meanwhile.
  const heights = st.out.map((c) => {
    const frame = chatFrames.get(c.sid);
    if (!frame) return 0;
    return frame.flying ? frame.tall : atMorphEnd(frame.row, () => frame.el.offsetHeight);
  });
  drawChatMore();
  const pillRoom = chatMoreEl.offsetHeight + CHAT_PILL_GAP;
  let fit = chatsFit(heights, way.tall - CHAT_CLEAR);
  if (fit < st.out.length || st.queue.length) fit = chatsFit(heights, way.tall - CHAT_CLEAR - pillRoom);
  if (fit < st.out.length) {
    const extra = st.out.slice(fit);
    st.out = st.out.slice(0, fit);
    st.queue = [...extra.map(({ sid, news }) => ({ sid, news })), ...st.queue];
    for (const c of extra) chatGoes(c.sid, 'unseen');
    st.fits = Math.max(1, fit);
    st.fitsFor = st.out[0]?.sid;
  } else if (st.out[0]?.sid !== st.fitsFor) st.fits = CHATS_MOST;
  drawChatMore();
  const tucked = chatsQuiet(), wide = chatFrames.values().next().value?.el.offsetWidth || 340;
  const pill = st.queue.length ? chatMoreEl.offsetHeight : 0;
  const laid = chatsLayout(heights.slice(0, st.out.length), way, wide, at, pill);
  if (st.holding && !tucked) {
    st.out.forEach((c, i) => {
      const frame = chatFrames.get(c.sid);
      if (frame?.placed && !frame.tucked && !frame.flying) laid.chats[i] = frame.placed;
    });
    const ends = laid.chats.map((p, i) => (way.up ? p.y : p.y + heights[i]));
    if (ends.length) laid.pill.y = way.up ? Math.min(...ends) - CHAT_PILL_GAP - pill : Math.max(...ends) + CHAT_PILL_GAP;
  }
  chatsEl.classList.toggle('to-right', !!way.right);
  chatsEl.classList.toggle('up', !!way.up);
  const moves = st.out.map((c, i) => {
    const frame = chatFrames.get(c.sid), to = laid.chats[i];
    // Coming out, or back out after going in for now, it comes from under the cat, or from under the chat before it.
    const fresh = came.includes(c.sid) || !frame.placed || (frame.tucked && !tucked);
    // What has only just come out, or moved up, takes no press for a moment (the frames' mousedown, below).
    if (fresh || frame.placed.x !== to.x || frame.placed.y !== to.y) frame.shownAt = Date.now();
    return { frame, to, fresh, i };
  }).filter((m) => !m.frame.flying);  // one being pulled back out beside the cat moves itself (chatsLeave)
  // The pill's own part is as wide as it is, at the end of its row nearest the cat (chats.css).
  const pillWide = chatMoreEl.firstChild.offsetWidth, pillX = laid.pill.x + (way.right ? 0 : wide - pillWide);
  const parts = tucked ? [] : [...laid.chats.map((to, i) => [to.x, to.y, wide, heights[i]]),
                               ...(pill ? [[pillX, laid.pill.y, pillWide, pill]] : [])];
  askChatRoom(parts.map(([x, y, w, h]) => [x - at.x, y - at.y, w, h]), () => {
    for (const m of moves) moveChat(m, laid.chats[m.i - 1], tucked);
    placeChatMore(laid.pill, !!pill && !tucked);
  }, tucked ? CHAT_TUCK_MS : CHAT_MOVE_MS);
}

// Where a chat starts as it comes out from under the cat, or goes as it goes back into it: a little toward the cat,
// a little smaller, faded.
function chatTowardCat(to) {
  return { x: to.x + (state.cat.way.right ? -CHAT_SLIDE : CHAT_SLIDE), y: to.y, scale: 0.96 };
}

// A chat to its place `to`: if it's coming out, from under the cat, or from under the chat before it (`before`), and
// faded in; or, while what's out is in for now (`tucked`), toward the cat and faded out, keeping its place to come
// back to.
function moveChat({ frame, to, fresh }, before, tucked) {
  const el = frame.el;
  if (fresh && !tucked) {
    const from = before ? { x: to.x, y: before.y, scale: 0.98 } : chatTowardCat(to);
    el.style.transition = 'none';
    el.style.transform = chatTransform(from);
    el.style.opacity = '0';
    void el.offsetWidth;
    el.style.transition = '';
  }
  frame.placed = to;
  frame.tucked = tucked;
  el.style.transform = chatTransform(tucked ? chatTowardCat(to) : to);
  el.style.opacity = tucked ? '0' : '1';
  el.classList.toggle('tucked', tucked);
}

const chatTransform = ({ x, y, scale = 1 }) => `translate(${x}px, ${y}px)${scale !== 1 ? ` scale(${scale})` : ''}`;

// A chat's frame: its row's box, which morph draws its row in as the list's are, its pin and ×, and the line along its
// foot that shrinks as its time runs out; and under its row, its card and the held row's tint, for its way into the
// list and back (chatsLand, chatsLeave).
function makeChatFrame(sid) {
  const el = document.createElement('div');
  el.className = 'chat';
  el.dataset.chat = sid;
  el.innerHTML = '<div class="chat-base"></div><div class="chat-tint"></div><div class="chat-row"></div>'
    + '<div class="chat-tools">'
    + `<button class="chat-tool chat-pin" data-chat-act="pin" title="Keep it out">${PIN_ICON}</button>`
    + `<button class="chat-tool" data-chat-act="close" title="Back into the panel">${CLOSE_ICON}</button></div>`
    + '<div class="chat-time"></div>';
  chatsEl.appendChild(el);
  const frame = { el, row: el.querySelector('.chat-row'), placed: null, tucked: false, shownAt: 0 };
  chatFrames.set(sid, frame);
  return frame;
}

// A chat going: back into the cat (`how` 'cat', the one nearest it) or under the chat before it ('up'), fading; with
// the panel opening ('open'), fading where it is, as the list shows it; or at once, never seen ('unseen': it didn't fit
// beside the cat, and waits). One on its way into its row lands there all the same; one on its way back out of it
// fades where it is.
function chatGoes(sid, how) {
  const frame = chatFrames.get(sid);
  if (!frame) return;
  chatFrames.delete(sid);
  if (frame.flying) {
    const f = state.chats.flights.get(sid);
    if (f?.drive.to === 0) {
      state.chats.flights.delete(sid);
      f.row?.classList.remove('chat-landing');
      chatGoesAway(f.el);
    }
    return;
  }
  const el = frame.el, to = frame.placed;
  if (how === 'unseen' || !to) { el.remove(); return; }
  el.classList.add(how === 'open' ? 'going-all' : 'going');
  if (how === 'cat') el.style.transform = chatTransform(chatTowardCat(to));
  if (how === 'up') el.style.transform = chatTransform({ x: to.x, y: to.y + (state.cat.way.up ? 12 : -12),
                                                         scale: 0.97 });
  el.style.opacity = '0';
  setTimeout(() => el.remove(), CHAT_MOVE_MS + 40);
}

// The pill under the chats, while more wait their turn.
function drawChatMore() {
  if (!chatMoreEl) {
    chatMoreEl = document.createElement('div');
    chatMoreEl.className = 'chat-more';
    chatMoreEl.innerHTML = '<span></span>';
    chatsEl.appendChild(chatMoreEl);
  }
  const n = state.chats.queue.length;
  if (n) chatMoreEl.firstChild.textContent = `${n} more waiting`;
}

function placeChatMore(place, shows) {
  if (shows) chatMoreEl.style.transform = chatTransform(place);
  chatMoreEl.classList.toggle('shows', shows);
}

// The room beside the cat for the chats (askCatRoom, in cat.js), each [x, y, width, height] from the glass's middle.
// While chats move, for `ms`, the window holds the room for where they were and where they go, and only what they need
// once they've got there.
function askChatRoom(parts, then, ms) {
  const st = state.chats, key = JSON.stringify(parts);
  if (key === st.roomKey) { then(); return; }
  const was = st.roomParts;
  st.roomKey = key;
  st.roomParts = parts;
  clearTimeout(st.roomTimer);
  askCatRoom({ chats: [...was, ...parts] }, then);
  st.roomTimer = setTimeout(() => askCatRoom({ chats: st.roomParts }), ms + 80);
}

// --- Their time ---

// Their time runs, ten times a second, while one is out and none is held: pointed at, typed in, or in its session's
// tab, when every chat's time stands still, so none goes and moves the one you're on; and not for one pinned, or while
// they're in for now. The line along each one's foot eases between the ticks (chats.css), so it shrinks smoothly.
// Each tick's time is capped, so one that came late (the Mac asleep) never takes much of it at once.
const CHAT_TICK_MS = 100;
function startChatClock() {
  const st = state.chats;
  if (st.clock || !st.out.length) return;
  st.tickAt = performance.now();
  st.clock = setTimeout(() => chatClock(performance.now()), CHAT_TICK_MS);
}

function chatClock(now) {
  const st = state.chats, dt = Math.min(2 * CHAT_TICK_MS, Math.max(0, now - st.tickAt)), tucked = chatsQuiet();
  st.tickAt = now;
  st.clock = 0;
  const holds = chatsHeld(), holding = st.out.some((c) => holds(c.sid));
  const held = (c) => c.kept || tucked || holding;
  const was = st.out.map((c) => c.sid), { out, expired } = chatsTick(st.out, dt, held);
  st.out = out;
  for (const c of out) {
    const frame = chatFrames.get(c.sid);
    frame?.el.style.setProperty('--left', (c.left / CHAT_MS).toFixed(4));
    frame?.el.classList.toggle('held', holds(c.sid) && !c.kept && !tucked);
  }
  if (expired.length) {
    for (const c of expired) {
      Object.assign(st, chatsBack({ ...st, out: [...st.out, c] }, c.sid));
      chatGoes(c.sid, was.indexOf(c.sid) === 0 ? 'cat' : 'up');
    }
    drawChats(chatsPlaced, state.last.now);
    return;
  }
  if (out.some((c) => !held(c))) st.clock = setTimeout(() => chatClock(performance.now()), CHAT_TICK_MS);
}

// Pointing at a chat holds their time, and moving off lets it run again; and once you hold none, they close up where
// one went, and what waits comes out.
core.pointerWatchers.push(() => {
  startChatClock();
  const st = state.chats;
  if (st.holding && !st.out.some((c) => chatsHeld()(c.sid))) drawChats(chatsPlaced, state.last.now);
});

// --- Presses ---

// The pin keeps a chat out until it's pressed again, and the × sends it back into the cat. A press on what has only
// just come out or moved up doesn't count: it may have taken the place of what was being pressed.
chatsEl.addEventListener('mousedown', (e) => {
  const el = e.target.closest?.('.chat'), frame = el && chatFrames.get(el.dataset.chat);
  if (e.button !== 0 || !frame) return;
  const act = e.target.closest('[data-chat-act]')?.dataset.chatAct;
  if (act || Date.now() - frame.shownAt < FRESH_MS) {
    e.preventDefault();
    e.stopImmediatePropagation();
  }
  if (!act || Date.now() - frame.shownAt < FRESH_MS) return;
  const st = state.chats, sid = el.dataset.chat;
  if (act === 'pin') {
    st.out = st.out.map((c) => (c.sid === sid ? { ...c, kept: !c.kept } : c));
    el.classList.toggle('kept', !!st.out.find((c) => c.sid === sid)?.kept);
    startChatClock();
    return;
  }
  const first = st.out[0]?.sid === sid;
  Object.assign(st, chatsBack(st, sid));
  chatGoes(sid, first ? 'cat' : 'up');
  drawChats(chatsPlaced, state.last.now);
}, true);

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

// The list's visible part on the page, top and bottom, below the header (or the head that stands in for it).
function chatsBand() {
  const list = document.getElementById('list'), r = list.getBoundingClientRect(), top = r.top + list.clientTop;
  return { top: top + headerInset(), bottom: top + list.clientHeight };
}

// The panel opening round the cat with chats out beside it (foldPanel, in panel.js), from a press on the cat or with
// the pointer resting on it: each chat is pulled home into its row in the list, as if on a spring, the lowest first, so
// each moves into room already clear, shedding its card as it nears its row (its pin, ×, time line, colour and shadow),
// and its row takes over there once the list is in. One whose row is only partly in the list's sight lands there all
// the same, cut by the list's edge as its row is; one whose row is out of sight slides under the list's edge on that
// side. One that's the session you're on, held at the list's edge (sticky.js), becomes that held row on its way, in the
// same move (chatFlight). One still on its way back out of its row, the folded cat's list having gone back in a moment
// ago (chatsLeave), turns back where it is, keeping its speed. Meanwhile the rest of the panel waits out of sight
// (chats.css) until the glass has spread out from behind the cat: the app keeps all the room the chats need till then
// (foldMoving, in app/core/PanelWindow.m). Under reduced motion, each fades where it is. Says whether any were out.
function chatsLand() {
  const st = state.chats, body = document.body.classList;
  const back = [...st.flights.values()].filter((f) => f.drive.to === 0);
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
  const band = chatsBand(), n = frames.length, up = state.cat.way.up;
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

// The folded cat's list going back in as the pointer leaves it (peekGoes, in peek.js), with chats still out (pinned,
// or with time left): each is pulled back out from its row to its place beside it, top first, taking its card back as
// it lifts off the list, and its pin, × and time line once it's there; one held at the list's edge turns back into its
// chat on its way, in the same move; one whose row is out of sight comes out from under the list's edge. One still on
// its way into its row, the list having only just come out, turns back where it is, keeping its speed. The list fades
// and the glass closes round the cat meanwhile. Says the room they go to, as askChatRoom names it, for the app to keep
// as it folds; none with nothing out, or under reduced motion, when they come out of the cat afterwards.
function chatsLeave() {
  const st = state.chats, body = document.body.classList;
  if (calm.matches) return null;
  const out = new Set(st.out.map((c) => c.sid));
  const back = [...st.flights.values()].filter((f) => f.drive.to === 1 && out.has(f.sid)
    && chatFrames.get(f.sid) === f.frame);
  const frames = st.out.map((c) => [c.sid, chatFrames.get(c.sid)]).filter(([, f]) => f?.placed && !f.flying);
  if (!back.length && !frames.length) return null;
  // The top first: the first going down from the cat, the last going up from it.
  const band = chatsBand(), at = state.cat.at, n = frames.length, up = state.cat.way.up;
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
// in sight; and, for the session you're on held at the list's edge, the held row it becomes (`held`): its lines, as
// sticky.js measures and folds them, and the held row's place. `at(now)` puts it where it is then.
function chatFlight(sid, frame, band, from, delay) {
  const el = frame.el, inside = el.querySelector('.chat-row > .row'), sticky = state.sticky;
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
  if (sticky.edge && !sticky.leaving && sticky.sid === sid && sticky.copy) {
    const holder = stickyEl.querySelector('.sticky-copy').getBoundingClientRect(), lines = stickyMeasure(inside);
    const full = inside.getBoundingClientRect().height;
    const least = full - lines.reduce((sum, l) => sum + (l.keep ? 0 : l.extent), 0);
    Object.assign(f, { held: { lines, full, least, edge: sticky.edge, holder, homeAt, rowIn }, row });
    f.at = (now) => { chatDrive(f, now); chatHeldAt(f, f.u); };
    return f;
  }
  const seen = !!target && target.bottom > band.top && target.top < band.bottom;
  // Out of sight, it's just past the list's edge on its row's side, under the edge; with no row, under the foot.
  const h = inside.getBoundingClientRect().height;
  let y = target ? target.top : band.bottom + 4;
  if (target && !seen) y = target.bottom <= band.top ? band.top - h - 4 : band.bottom + 4;
  const rowAt = { left: (target ? target.left : homeAt.left + rowIn.x) - rowIn.x, top: y - rowIn.y };
  const past = (top) => ({ top: Math.max(0, band.top - top), bottom: Math.max(0, top + fullHeight - band.bottom) });
  Object.assign(f, { a: homeAt, b: rowAt, start: past(homeAt.top), row: seen ? row : null,
                     cut: { top: y < band.top, bottom: y + h > band.bottom } });
  f.at = (now) => { chatDrive(f, now); chatPulledAt(f, now); };
  return f;
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
// its card shed as it nears its row and taken back as it lifts off it, its pin, × and time line going as it sets off
// for its row and coming back once it's home, and cut where it's past the list's edge on its row's side, as much as it
// wasn't past it already beside the cat.
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
  chatLooks(f.el, { card, chrome: f.chrome, away: p });
  let cutTop = 0, cutBottom = 0;
  if (f.cut.top) cutTop = Math.max(0, f.band.top - top - f.start.top * (1 - p));
  if (f.cut.bottom) cutBottom = Math.max(0, top + f.fullHeight - f.band.bottom - f.start.bottom * (1 - p));
  f.el.style.clipPath = cutTop || cutBottom ? `inset(${cutTop.toFixed(1)}px 0 ${cutBottom.toFixed(1)}px 0)` : '';
}

// How much of a chat's card shows (its colour and shadow, `card`), of its pin, × and time line (`chrome`), of the held
// row's tint (`tint`), and how far it is from being a chat (`away`: its title line taking the row's own room).
function chatLooks(el, looks) {
  for (const [name, value] of Object.entries(looks)) el.style.setProperty('--' + name, value.toFixed(3));
}

// The chat of the session you're on, between its place beside the cat and the held row at the list's edge, `u` of the
// way (the spring's): it moves and changes shape as one, its lines folding as the held row's do (sticky.js, the one
// nearest the edge first), its tint coming in across the list, its corners squaring off against the edge, its shadow
// and padding going, so it has the held row's shape exactly as it stops there; going back out, the other way round.
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
  chatLooks(el, { card: 1 - chatClamp((k - 0.7) / 0.3), tint: k, chrome: 1 - chatClamp(1.6 * k), away: k });
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
  for (const prop of ['--card', '--tint', '--chrome', '--away']) el.style.removeProperty(prop);
  for (const line of f.held?.lines ?? []) stickyFoldLine(line, 0, f.held.edge);
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

function chatGoesAway(el) {
  el.style.transition = 'opacity .15s ease';
  el.style.opacity = '0';
  setTimeout(() => el.remove(), 200);
}

// The cat being moved (catMoving, in cat.js): what's out goes in, keeping its time, and comes out again once it has
// stopped, the way the app says it goes from there.
function chatsMoving(moving) {
  state.chats.moving = moving;
  drawChats(chatsPlaced, state.last.now);
}

// The cat now faces another way (catWay, in cat.js): what's out comes out afresh that way, rather than sliding across
// the cat to get there.
function chatsTurned() {
  for (const frame of chatFrames.values()) frame.tucked = true;
  if (state.chats.out.length) drawChats(chatsPlaced, state.last.now);
}

// The panel opening: what's out is counted as seen, as the list shows it all, having gone into its rows (chatsLand);
// folding again before they've landed, they fade where they are, but for those turned back out (chatsLeave).
core.collapses.push((collapsed) => {
  if (collapsed && [...state.chats.flights.values()].some((f) => f.drive.to === 1)) chatsLanded(true);
  drawChats(chatsPlaced, state.last.now);
});
core.afterDraw.push(() => { if (state.chats.flights.size) chatsLandingRows(); });
core.pointerTargets.push('.chat-tool');
