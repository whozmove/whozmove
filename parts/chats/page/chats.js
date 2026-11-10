// The chats beside the folded cat, the place notifications fills beside the folded panel (core.places.besideFold).
// While the panel is folded, a session that comes to need you (a request, a question, a plan, or a reply you haven't
// read) comes out beside the cat by itself, as its row, the list's own (rowHTML), so it's answered or opened there as
// it would be in the list; whole, saying what's new, where the list shows its rows briefly (row.chat), and
// saying a module's line in Claude's place where that's what's new, a reply in its side chat (`said`). Which
// come out and when is notifications' (its decider, besideStep): in the order they came, the first nearest the cat,
// three at most: a new one comes out after the others, or, with three out, waits its turn, never taking the place of
// one out, with a pill under the chats saying how many wait. Each stays out a while, the time it has left a ring round
// its × that empties: pointing at it, typing in it, pinning it, or being in its session's tab once pressing it (or its
// row) has put you there, holds it out; and while you hold one, nothing new comes out, and what's new waits. The one
// you're pointing at or typing in, and those before it, stay where they are but to keep clear of one that grows, and
// the rest close up after them. It goes back into the cat once it's answered or answered elsewhere, or read, unless
// you're in its tab (but for a request, which goes once answered there too), when its time runs out, or when its × is
// pressed: it comes out again only when something new happens in its session. Those below move up, and the first
// waiting comes out after them. The app gives them the room beside the cat that they need, letting clicks through
// everywhere else (catRoom, in PanelWindow+Chats.m); they go toward the screen's middle, and up from the cat while it's
// low on the screen.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// How long a chat stays out by itself; how many are out at once, at most; how far a chat's near end is from the cat's
// glass's middle, clear of the cat's square, which the app keeps for pressing and dragging the cat; how far apart the
// chats are, and the pill from the last; how far the cat's glass reaches from its middle (76 across); and how much of
// the screen's edge the chats keep clear of.
const CHAT_MS = 45000, CHATS_MOST = 3, CHAT_FROM = 56, CHATS_GAP = 10, CHAT_PILL_GAP = 6, CHAT_GLASS_R = 38;
const CHAT_CLEAR = 8;
// How long a chat takes to come out, move up or go back, to go in for now as the cat is moved, and to fade (chats.css);
// how far toward the cat one starts or goes; and how far one lifts as it comes out with another nearer the cat.
const CHAT_MOVE_MS = 420, CHAT_TUCK_MS = 160, CHAT_FADE_MS = 200, CHAT_SLIDE = 40, CHAT_LIFT = 3;

// --- What comes out, and where: plain functions ---

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

// Where the chats go while you're on one (`laid` being chatsLayout's places for them, `heights` tall): each kept
// where it was (`kept[i]`, { x, y, tall }, its top-left corner and how tall it was there), its end nearest the cat
// staying put as it grows or shrinks, but never nearer than CHATS_GAP to the one before it, should that have grown;
// each not kept (null) CHATS_GAP from the one before it, as it shrinks or goes, or where `laid` has it for the first;
// then the pill, `pill` tall, past the last.
function chatsKept(laid, kept, heights, way, pill) {
  const chats = [];
  heights.forEach((h, i) => {
    const was = kept[i], before = chats[i - 1];
    const after = before && (way.up ? before.y - CHATS_GAP - h : before.y + heights[i - 1] + CHATS_GAP);
    let y = was ? (way.up ? was.y + was.tall - h : was.y) : before ? after : laid.chats[i].y;
    if (before) y = way.up ? Math.min(y, after) : Math.max(y, after);
    chats.push({ x: was ? was.x : laid.chats[i].x, y });
  });
  if (!chats.length) return laid;
  const ends = chats.map((p, i) => (way.up ? p.y : p.y + heights[i]));
  const end = way.up ? Math.min(...ends) - CHAT_PILL_GAP - pill : Math.max(...ends) + CHAT_PILL_GAP;
  return { chats, pill: { x: laid.pill.x, y: end } };
}

// The chat you're pointing at, { sid, landed, passing }, given `under`, the session of the one under the pointer now,
// and `before`, what was known when it was last looked at: { still, sid, landed, passing, moving, settling }, whether
// the pointer is where it was then, the one it was on (undefined for none), whether that one had landed there and
// whether it was passing, whether the one under it now is still moving or easing to a new height, and whether it or one
// before it is still on its way to where they'll end up (chatsSettling). Moving the pointer points at what it's on at
// once; but one it comes onto on its way, as the one above it shrinks and it closes up, is passing, holding their time
// but not its place (chatKeptTo) till they've all got there, so it finishes closing up rather than stop short with a
// gap above it, and keeps its place once it's there. A chat that has come to be under a pointer that hasn't moved did
// so by moving there itself, as the one below closes up when the one above it shrinks, so it isn't pointed at while it
// moves; once it has stopped, it has landed there: it's the one you'll read next, as the one you answered goes, so it
// holds their time as if you'd pointed at it, but not its place, which would leave a gap above it as the one above it
// shrinks again.
function chatPointed(under, before) {
  const passing = under === before.sid ? before.passing && before.settling : !!under && before.settling;
  if (!before.still) return { sid: under, landed: false, passing };
  if (under === before.sid) return { sid: under, landed: before.landed, passing };
  return before.moving ? { sid: undefined, landed: false, passing: false }
    : { sid: under, landed: true, passing: false };
}

// --- Drawing them ---

const chatsEl = document.getElementById('chats');
// A press on a chat's row does what it would in the list.
takesPresses(chatsEl);
// Each chat's frame, kept by its session as long as it's out (its row drawn in it afresh with each update), the rows
// last placed, and the pill under the chats.
const chatFrames = new Map();
let chatsPlaced = [], chatsNow = 0, chatMoreEl = null, chatMorePlaced = null, chatMoreRide = null;
// Whether a chat's frame is out where you can see it: placed, not in for now while the cat moves, and not on its way
// into its row.
const chatShown = (frame) => !!frame?.placed && !frame.tucked && !frame.flying && !frame.coming;
// Whether it has only just come out or moved up, so a press on it may have been meant for what was there before.
const chatFresh = (frame) => Date.now() - frame.shownAt < FRESH_MS;
// A request's card on a chat takes its keys once pressed, as on the list (core.keyPlaces): only while the chat is out
// where you can see it, and for a press, once it has stayed where it is a moment. A chat going has no frame, so its
// card lets go of them before it has faded.
core.keyPlaces.push({ el: chatsEl, open: (card, pressing) => {
  const frame = chatFrames.get(card.closest('.chat')?.dataset.chat);
  return chatShown(frame) && !(pressing && chatFresh(frame));
} });

// With each update (render, in panel.js), and whenever what may come out changes (the peek going or staying): the rows
// as placed, kept for drawing them, and notifications asked again what should be out (core.notices.again), which it
// says through core.places.besideFold.show.
function drawChats(placed, now) {
  chatsPlaced = placed;
  chatsNow = now;
  core.notices.again?.();
}

core.places.besideFold = {
  // Seen while the panel is folded, its list not out on pointing, and not opening round the cat.
  inSight() {
    const body = document.body.classList;
    return body.contains('collapsed') && !body.contains('peeking') && !body.contains('arriving');
  },
  // What notifications decides from: the rows as placed and their time, what's out now and what waits, how many fit
  // beside the cat, whether nothing may come out now, and the sessions whose chats you're pointing at or typing in.
  state: () => ({ placed: chatsPlaced, now: chatsNow, out: state.chats.out, queue: state.chats.queue,
                  most: state.chats.fits, quiet: chatsQuiet(), pointed: chatsOn() }),
  // What it decided: what's out and what waits, which came out and which went, the chat you hold by being in its tab
  // (`inTab`, one you pressed, or whose row you pressed, while it was out), whether you hold one out, and whether the
  // panel is open, when what was out fades where it is, as the list shows it.
  show(next) {
    const st = state.chats, was = st.out.map((c) => c.sid);
    Object.assign(st, { out: next.out, queue: next.queue, inTab: next.inTab, holding: next.holding });
    for (const sid of next.went) chatGoes(sid, next.open ? 'open' : was.indexOf(sid) === 0 ? 'cat' : 'up');
    placeChats(new Map(chatsPlaced.map((p) => [p.s.sessionId, p])), chatsNow, next.came);
  },
};

// Whether you hold a session's chat out now: pointing at it, typing in it (its card having your keys counts), or in
// its session's tab once pressing it, or its row, has put you there (`inTab`, notifications').
function chatsHeld() {
  const on = chatsOn(), st = state.chats;
  return (sid) => on.includes(sid) || st.inTab.includes(sid);
}

// The sessions whose chats you're pointing at or typing in now, or whose card has your keys; with `places`, leaving out
// one that has only landed under a still pointer, or that the pointer came onto as it moved and that hasn't stopped
// yet, which hold their time but not their places (chatPointed). The gap
// before a chat, on its side nearest the cat, counts as that chat, so the pointer going from one to the next is never
// on neither (chatBefore).
function chatsOn(places = false) {
  const p = state.pointer, st = state.chats;
  const under = p && (document.elementFromPoint(p.x, p.y)?.closest?.('.chat')?.dataset.chat ?? chatBefore(p));
  // What was seen last time is kept, so a chat that moves under a pointer that is still is taken for pointed at only
  // once it has stopped there (chatPointed).
  const still = st.pointSeen?.x === p?.x && st.pointSeen?.y === p?.y;
  const { sid, landed, passing } = p
    ? chatPointed(under, { still, sid: st.pointedSid, landed: st.pointLanded, passing: st.pointPassing,
                           moving: chatMoving(chatFrames.get(under)),
                           settling: !!under && (under !== st.pointedSid || st.pointPassing) && chatsSettling(under) })
    : { sid: undefined, landed: false, passing: false };
  st.pointSeen = p ? { x: p.x, y: p.y } : null;
  st.pointedSid = sid;
  st.pointLanded = landed;
  st.pointPassing = passing;
  const pointed = places && (landed || passing) ? undefined : sid;
  const typed = document.activeElement?.closest?.('.chat')?.dataset.chat;
  const keyed = heldCard()?.closest?.('.chat')?.dataset.chat;  // its card has your keys, as typing in it
  return [pointed, typed, keyed].filter(Boolean);
}

// Whether a chat's frame is moving to its place, coming out or fading, or its row is easing to a new height: its own
// transitions and morph's easing, not what runs inside its row (a working session's band of light), which never ends.
function chatMoving(frame) {
  return !!frame && [...frame.el.getAnimations(), ...frame.row.getAnimations()].some((a) => a.playState === 'running');
}

// Whether the chat out for a session, or one before it, is still on its way to where they'll end up: moving or easing
// to a new height, or grown or shrunk since they were last laid out, so they're to be laid out again (chatsResized).
function chatsSettling(sid) {
  const out = state.chats.out, i = out.findIndex((c) => c.sid === sid);
  return out.slice(0, i + 1).some((c) => {
    const frame = chatFrames.get(c.sid);
    return chatMoving(frame) || (frame?.laidTall != null && Math.abs(chatTall(frame) - frame.laidTall) > 0.5);
  });
}

// The session of the chat out whose gap before it, CHATS_GAP on its side nearest the cat, has the pointer `p` in it.
function chatBefore(p) {
  const up = state.cat.way.up;
  return state.chats.out.find((c) => {
    const frame = chatFrames.get(c.sid);
    if (!chatShown(frame)) return false;
    const r = frame.el.getBoundingClientRect(), y = up ? p.y - r.bottom : r.top - p.y;
    return p.x >= r.left && p.x <= r.right && y >= 0 && y <= CHATS_GAP;
  })?.sid;
}

// The session of the last chat out, from the cat, that you're pointing at or typing in, which keeps its place, and
// those before it theirs, so none moves from under you (chatsKept); null when you're on none. One held only by being
// in its session's tab, which nothing is pressed in, keeps none.
function chatKeptTo() {
  const on = chatsOn(true);
  return state.chats.out.findLast((c) => on.includes(c.sid))?.sid ?? null;
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
    // Out for what a module says is new in the session, not the row's own news, it says that in Claude's place.
    const said = c.line ? { line: c.line, at: c.at } : null;
    if (!frame.flying && !composing) {
      frame.said = !!said;
      morph(frame.row, rowHTML(p.s, p.kind, now, { chat: true, said }));
    }
  }
  layChats(came);
  startChatClock();
}

// The chats out measured and placed beside the cat; those that don't fit before the screen's edge, with the pill under
// them while more wait, wait at the queue's head, unseen, and fewer come out until the first has gone back. Each is
// measured as tall as it counts (chatTall), and the room they need is asked for before any comes out or moves
// (askChatRoom), so the window's edge never cuts one off. While you point at one or type in one, it and those before
// it keep their places, a gap left where one before it went, until you move off, each moving only to keep clear of the
// one before it as that grows; those after it close up to it as one shrinks or goes (chatsKept). Once laid out,
// they're laid out again as one's height changes (chatsResized).
function layChats(came) {
  const st = state.chats, way = state.cat.way, at = state.cat.at;
  // A chat whose row is shrinking is laid out as it'll end, and those after it ride its foot there (chatRide).
  const ride = chatRide(st.out);
  if (ride) ride.frame.ridden = ride.ease;
  const heights = st.out.map((c) => {
    const frame = chatFrames.get(c.sid);
    return frame ? chatTall(frame) : 0;
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
  let laid = chatsLayout(heights.slice(0, st.out.length), way, wide, at, pill);
  st.keptTo = tucked ? null : chatKeptTo();
  if (st.keptTo) {
    const last = st.out.findIndex((c) => c.sid === st.keptTo);
    const kept = st.out.map((c, i) => {
      const frame = chatFrames.get(c.sid);
      return i <= last && frame?.placed && !frame.tucked && !frame.flying
        ? { ...frame.placed, tall: frame.laidTall ?? heights[i] } : null;
    });
    laid = chatsKept(laid, kept, heights.slice(0, st.out.length), way, pill);
  }
  chatsEl.classList.toggle('to-right', !!way.right);
  chatsEl.classList.toggle('up', !!way.up);
  // Going up from the cat, each is placed by its foot, its end nearest the cat, so its foot stays put as its row
  // eases to a new height (chatTransform).
  const moves = st.out.map((c, i) => {
    const frame = chatFrames.get(c.sid), to = way.up ? { ...laid.chats[i], tall: heights[i] } : laid.chats[i];
    // Coming out, or back out after going in for now (moveChat: from under the cat, or in its own place after another).
    const fresh = came.includes(c.sid) || !frame.placed || (frame.tucked && !tucked);
    // What has only just come out, or moved up, takes no press for a moment (the frames' mousedown, below).
    if (fresh || frame.placed.x !== to.x || frame.placed.y !== to.y) frame.shownAt = Date.now();
    return { frame, to, fresh, i };
  }).filter((m) => !m.frame.flying);  // one being pulled back out beside the cat moves itself (chatsLeave)
  // The pill's own part is as wide as it is, at the end of its row nearest the cat (chats.css).
  const pillWide = chatMoreEl.firstChild.offsetWidth, pillX = laid.pill.x + (way.right ? 0 : wide - pillWide);
  const parts = tucked ? [] : [...laid.chats.map((to, i) => [to.x, to.y, wide, heights[i]]),
                               ...(pill ? [[pillX, laid.pill.y, pillWide, pill]] : [])];
  for (const m of moves) m.frame.laidTall = heights[m.i];
  // Where they were is kept till those moving have got there, which they start for once the one going has faded, or
  // as long as a ride lasts.
  const moving = tucked ? CHAT_TUCK_MS
    : Math.max(chatComesAfter([st.fadedAt], Date.now()) + CHAT_MOVE_MS, ride?.left ?? 0);
  askChatRoom(parts.map(([x, y, w, h]) => [x - at.x, y - at.y, w, h]), () => {
    moveChats(moves, laid.chats, tucked, ride);
    placeChatMore(laid.pill, !!pill && !tucked, ride);
  }, moving);
  // One whose row is easing to a new height is laid out again once it has got there, as it counts as tall as it gets on
  // the way till then (chatTall).
  const easing = st.out.flatMap((c) => chatFrames.get(c.sid)?.row.getAnimations() ?? [])
    .map((a) => a.effect.getComputedTiming().endTime - a.currentTime);
  clearTimeout(st.easedTimer);
  if (easing.length) st.easedTimer = setTimeout(chatsResized, Math.max(...easing) + 20);
}

// How tall a chat counts beside the cat: as tall as its row is growing to from the moment it starts (atMorphEnd), so
// the one after it moves clear as it grows; and while it eases, as tall as it still gets on the rest of the way
// (chatAhead), so the one after it moves up only into room already clear, once the row has got there. Up to as tall as
// a chat goes, where its row scrolls. One on its way into its row or back out counts as tall as it is beside the cat,
// whatever it's folded to meanwhile.
function chatTall(frame) {
  if (frame.flying) return frame.tall;
  const most = parseFloat(getComputedStyle(frame.el).maxHeight) || Infinity;
  const ridden = !!frame.ridden && frame.ridden === chatEasing(frame);
  return Math.min(most, atMorphEnd(frame.row, () => frame.el.offsetHeight) + (ridden ? 0 : chatAhead(frame)));
}

// The easing a chat's row is on now (morph's), if any.
function chatEasing(frame) {
  return frame?.row.getAnimations().find((a) => a.playState === 'running') ?? null;
}

// The shrinking row those after it ride, closing up with it as it shrinks, on its curve, so each keeps CHATS_GAP from
// the foot of the one before it all the way: the one chat whose row is easing smaller than they were laid out for, or
// that they ride already, while no other's eases, nothing goes back beside the cat, and motion isn't reduced, when it
// just ends. { i, frame, ease, keys, end, sign, left }: its place among those out, its frame, its easing, that easing's
// keyframes ({ offset, height, easing }) and the height they end at, which way those after it move as it shrinks (up
// from the cat, they come down to it), and how long it has left. Null otherwise, when they close up once it has stopped
// (chatAhead); and one that grows never has them ride it, as they move clear of it at once.
function chatRide(out) {
  if (calm.matches || chatsQuiet() || chatComesAfter([state.chats.fadedAt], Date.now())) return null;
  const easing = out.map((c, i) => ({ i, frame: chatFrames.get(c.sid) }))
    .map((e) => ({ ...e, ease: chatEasing(e.frame) })).filter((e) => e.ease);
  if (easing.length !== 1) return null;
  const { i, frame, ease } = easing[0];
  const keys = ease.effect.getKeyframes()
    .map((k) => ({ offset: k.computedOffset, height: parseFloat(k.height), easing: k.easing }));
  const end = keys[keys.length - 1]?.height;
  if (!(end >= 0) || frame.laidTall == null) return null;
  if (frame.ridden !== ease) {
    const most = parseFloat(getComputedStyle(frame.el).maxHeight) || Infinity;
    const will = Math.min(most, atMorphEnd(frame.row, () => frame.el.offsetHeight));
    if (frame.laidTall >= most - 0.5 || !(will < frame.laidTall - 0.5)) return null;
  }
  const timing = ease.effect.getComputedTiming();
  return { i, frame, ease, keys, end, sign: state.cat.way.up ? -1 : 1, left: timing.endTime - ease.currentTime };
}

// How far along its way each of a ride's keyframes puts those riding it from where they end, `dy`, as the row it
// rides is taller than it ends by then: down from the cat they're that much lower, up from it that much higher; each
// eased on to the next as the row's is.
function chatRideFrames(keys, end, sign) {
  return keys.map((k) => ({ offset: k.offset, easing: k.easing ?? 'linear', dy: sign * (k.height - end) }));
}

// An element riding a shrinking row to its place `to`, from where the row's easing has got to, landing with it.
function chatRideOn(el, to, ride) {
  el.style.transition = 'none';
  el.style.transform = chatTransform(to);
  void el.offsetWidth;
  el.style.transition = '';
  const goes = el.animate(chatRideFrames(ride.keys, ride.end, ride.sign)
    .map(({ offset, easing, dy }) => ({ offset, easing, transform: chatTransform({ ...to, y: to.y + dy }) })),
  { duration: ride.ease.effect.getTiming().duration, easing: ride.ease.effect.getTiming().easing });
  // On the row's own clock, so they keep in step from the first frame: at once, or as soon as the row's easing has
  // started, when it has only just been made.
  const inStep = () => {
    if (goes.playState === 'running' && ride.ease.startTime != null) goes.startTime = ride.ease.startTime;
  };
  goes.currentTime = ride.ease.currentTime ?? 0;
  if (ride.ease.startTime != null) inStep();
  else ride.ease.ready.then(inStep, () => {});
  goes.rides = ride.ease;
  return goes;
}

// A ride stopped, its element left where it is now (not jumping to where the ride ends), to move on from there.
function chatRideStop(el, goes) {
  if (!goes) return null;
  if (goes.playState === 'running') {
    el.style.transition = 'none';
    goes.commitStyles();
    goes.cancel();
    void el.offsetWidth;
    el.style.transition = '';
  } else goes.cancel();
  return null;
}

// How much taller than where it's going a chat's row still gets on its way (morphOvershoot), none once it's within a
// point of it, as near as the eye can tell: a row that shrinks has the last of its height still to lose for half its
// easing (MORPH_EASE's long tail), and the one after it closes up once it's seen to have stopped, landing where it
// ends up.
function chatAhead(frame) {
  const over = morphOvershoot(frame.row);
  return over < 1 ? 0 : over;
}

// A chat's height changed since the chats were laid out (its row has finished easing to a new height, a card in it has
// opened, or anything else): they're laid out again, so each stays CHATS_GAP from the one before it. One whose row is
// still easing counts the same once it's within a point of where it's going (chatAhead), so the one after it follows
// as soon as it's seen to stop; till then the timer in layChats looks again. One gone from the page is no longer
// watched.
function chatsResized(changes = []) {
  for (const { target } of changes) if (!target.isConnected) chatSizes.unobserve(target);
  const st = state.chats;
  if (st.flights.size || chatsQuiet()) return;
  const moved = st.out.some((c) => {
    const frame = chatFrames.get(c.sid);
    return frame?.laidTall != null && !frame.flying && !chatAhead(frame)
      && Math.abs(chatTall(frame) - frame.laidTall) > 0.5;
  });
  // One that has started shrinking is ridden at once, from its first step (chatRide).
  const ride = moved ? null : chatRide(st.out);
  if (moved || (ride && ride.frame.ridden !== ride.ease)) layChats([]);
}
const chatSizes = typeof ResizeObserver === 'function' ? new ResizeObserver(chatsResized) : null;

// Where a chat starts as it comes out from under the cat, or goes as it goes back into it: a little toward the cat,
// a little smaller, faded.
function chatTowardCat(to, way = state.cat.way) {
  return { ...to, x: to.x + (way.right ? -CHAT_SLIDE : CHAT_SLIDE), scale: 0.96 };
}

// Where a chat starts as it comes out: the first, nearest the cat, from under it; one with another nearer the cat, in
// its own place, a little lower, so it lifts into it as it fades in, the panel's way, and never passes over the one
// before it.
function chatComesFrom(to, first, way) {
  return first ? chatTowardCat(to, way) : { ...to, y: to.y + CHAT_LIFT };
}

// How long a chat coming out waits, at `now`: until the chats moving to new places have landed and the one going has
// faded (`until`, the times each does), so it enters a lane already clear.
function chatComesAfter(until, now) {
  return Math.max(0, ...until.map((at) => (at || 0) - now));
}

// The chats to their places (`laid`, layChats): those moving, once the one going has faded, so none moves up over it,
// those after a shrinking one riding it there (`ride`, chatRide); then those coming out, once those have landed too
// (chatComesAfter). One still waiting to come out from when they were laid out last is coming out too, so it goes on
// waiting for them to land.
function moveChats(moves, laid, tucked, ride = null) {
  const now = Date.now(), comes = (m) => m.fresh || m.frame.coming;
  const staying = moves.filter((m) => !comes(m)), faded = chatComesAfter([state.chats.fadedAt], now);
  for (const m of staying) moveChat(m, null, tucked, now, faded, ride && m.i > ride.i ? ride : null);
  const wait = chatComesAfter([...staying.map((m) => m.frame.landsAt), state.chats.fadedAt], now);
  for (const m of moves) if (comes(m)) moveChat(m, laid[m.i - 1], tucked, now, wait);
}

// A chat to its place `to`: while what's out is in for now (`tucked`), toward the cat and faded out, keeping its place
// to come back to; if it's coming out, hidden there till `wait` has passed (one still waiting waits again, for what
// moves now), then out from where it comes (chatComesFrom: from under the cat, or with `before`, the chat before it,
// in its own place); and otherwise there once `wait` has passed, where it was till then, or, after a shrinking one,
// riding its foot there (`ride`), unless it was already on its way somewhere. One that moves notes when it lands
// (`landsAt`), for what comes out after it.
function moveChat({ frame, to, fresh }, before, tucked, now = Date.now(), wait = 0, ride = null) {
  const el = frame.el, moved = !frame.placed || frame.placed.x !== to.x || frame.placed.y !== to.y;
  // A ride goes on as long as it's the same one to the same place; anything else moves on from where it has got to.
  if (frame.ride && !(ride && frame.ride.rides === ride.ease && !moved)) frame.ride = chatRideStop(el, frame.ride);
  const rides = !!ride && moved && !tucked && !fresh && !frame.coming && wait <= 0 && !frame.ride && !!frame.placed
    && !el.getAnimations().some((a) => a.playState === 'running');
  frame.placed = to;
  frame.tucked = tucked;
  frame.first = !before;
  clearTimeout(frame.comeTimer);
  clearTimeout(frame.moveTimer);
  frame.moveTimer = 0;
  if (!tucked && (fresh || frame.coming)) {
    if (fresh) {
      el.style.transition = 'none';
      el.style.opacity = '0';
      void el.offsetWidth;
      el.style.transition = '';
    }
    frame.coming = true;
    el.classList.add('coming');
    el.classList.remove('tucked');
    if (wait > 0) frame.comeTimer = setTimeout(() => chatComes(frame), wait);
    else chatComes(frame);
    return;
  }
  frame.coming = false;
  el.classList.remove('coming');
  el.style.opacity = tucked ? '0' : '1';
  el.classList.toggle('tucked', tucked);
  if (rides) {
    frame.ride = chatRideOn(el, to, ride);
    frame.landsAt = now + ride.left;
    return;
  }
  if (tucked || wait <= 0) el.style.transform = chatTransform(tucked ? chatTowardCat(to) : to);
  else {
    frame.moveTimer = setTimeout(() => {
      frame.moveTimer = 0;
      frame.shownAt = Date.now();
      el.style.transform = chatTransform(frame.placed);
    }, wait);
  }
  if (moved && !tucked) frame.landsAt = now + Math.max(0, wait) + (calm.matches ? 0 : CHAT_MOVE_MS);
}

// A chat waiting to come out comes out to where it's placed now, from where it comes.
function chatComes(frame) {
  const el = frame.el, to = frame.placed;
  frame.comeTimer = 0;
  frame.coming = false;
  el.classList.remove('coming');
  el.style.transition = 'none';
  el.style.transform = chatTransform(chatComesFrom(to, frame.first, state.cat.way));
  el.style.opacity = '0';
  void el.offsetWidth;
  el.style.transition = '';
  el.style.transform = chatTransform(to);
  el.style.opacity = '1';
  frame.shownAt = Date.now();
  frame.landsAt = frame.shownAt + (calm.matches ? 0 : CHAT_MOVE_MS);
}

// A chat's transform to its place, { x, y }, its top-left corner; or, with `tall`, how tall it counts there, by its
// foot, y + tall, so that as its row eases to a new height its foot stays where it is and its top moves.
const chatTransform = ({ x, y, scale = 1, tall }) => (tall == null ? `translate(${x}px, ${y}px)`
  : `translate(${x}px, ${y + tall}px) translateY(-100%)`) + (scale !== 1 ? ` scale(${scale})` : '');

// A chat's frame: its row's box, which morph draws its row in as the list's are, and its pin and ×, the ring round the
// × emptying as its time runs out (controls.css's .timed); and under its row, its card and the held row's tint, for
// its way into the list and back (chatsLand, chatsLeave).
function makeChatFrame(sid) {
  const el = document.createElement('div');
  el.className = 'chat';
  el.dataset.chat = sid;
  el.innerHTML = '<div class="chat-base"></div><div class="chat-tint"></div><div class="chat-row"></div>'
    + '<div class="chat-tools">'
    + `<button class="icon-button small chat-tool chat-pin" data-chat-act="pin" title="Keep it out">${PIN_ICON}</button>`
    + '<button class="icon-button small timed chat-tool" data-chat-act="close" title="Back into the panel">'
    + `${TIMED_CLOSE_ICON}</button></div>`;
  chatsEl.appendChild(el);
  const frame = { el, row: el.querySelector('.chat-row'), placed: null, tucked: false, shownAt: 0, coming: false,
                  comeTimer: 0, moveTimer: 0, first: true, landsAt: 0, ride: null, ridden: null };
  chatFrames.set(sid, frame);
  chatSizes?.observe(el);
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
  clearTimeout(frame.comeTimer);
  clearTimeout(frame.moveTimer);
  frame.ride = chatRideStop(el, frame.ride);
  if (how === 'unseen' || !to || frame.coming) { el.remove(); return; }
  // What comes out next waits till this one has faded from where it was (chatComesAfter).
  if (how === 'cat' || how === 'up') state.chats.fadedAt = Date.now() + (calm.matches ? 0 : CHAT_FADE_MS);
  el.classList.add(how === 'open' ? 'going-all' : 'going');
  if (how === 'cat') el.style.transform = chatTransform(chatTowardCat(to));
  if (how === 'up') el.style.transform = chatTransform({ ...to, y: to.y + (state.cat.way.up ? 12 : -12), scale: 0.97 });
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

function placeChatMore(place, shows, ride = null) {
  const moved = !chatMorePlaced || chatMorePlaced.x !== place.x || chatMorePlaced.y !== place.y;
  if (chatMoreRide && !(ride && chatMoreRide.rides === ride.ease && !moved)) {
    chatMoreRide = chatRideStop(chatMoreEl, chatMoreRide);
  }
  if (shows && ride && moved && chatMorePlaced && !chatMoreRide) chatMoreRide = chatRideOn(chatMoreEl, place, ride);
  else if (shows) chatMoreEl.style.transform = chatTransform(place);
  chatMorePlaced = shows ? place : null;
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

// Their time runs, ten times a second, while one is out and none is held: pointed at, typed in, or in its session's tab
// once pressing it has put you there, when every chat's time stands still, so none goes and moves the one you're on;
// and not for one pinned, or while they're in for now. The ring round each one's × eases between the ticks
// (controls.css), so it empties smoothly. Each tick's time is capped, so one that came late (the Mac asleep) never
// takes much of it at once.
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
      chatGoes(c.sid, was.indexOf(c.sid) === 0 ? 'cat' : 'up');
      core.notices.back(c.sid, 'expired');
    }
    return;
  }
  if (out.some((c) => !held(c))) st.clock = setTimeout(() => chatClock(performance.now()), CHAT_TICK_MS);
}

// Pointing at a chat holds their time, and moving off lets it run again; and once you hold none, they close up where
// one went, and what waits comes out. Moving off the chat that kept its place, onto another nearer the cat or none,
// those after where you are now close up.
core.pointerWatchers.push(() => {
  startChatClock();
  const st = state.chats;
  if (st.holding && !st.out.some((c) => chatsHeld()(c.sid))) core.notices.holding(false);
  else if (st.keptTo && st.keptTo !== chatKeptTo() && !st.flights.size && !chatsQuiet()) layChats([]);
});

// --- Presses ---

// The pin keeps a chat out until it's pressed again, and the × sends it back into the cat. A press on what has only
// just come out or moved up doesn't count: it may have taken the place of what was being pressed.
chatsEl.addEventListener('mousedown', (e) => {
  const el = e.target.closest?.('.chat'), frame = el && chatFrames.get(el.dataset.chat);
  if (e.button !== 0 || !frame) return;
  const act = e.target.closest('[data-chat-act]')?.dataset.chatAct;
  if (act || chatFresh(frame)) {
    e.preventDefault();
    e.stopImmediatePropagation();
  }
  if (!act || chatFresh(frame)) return;
  const st = state.chats, sid = el.dataset.chat;
  if (act === 'pin') {
    st.out = st.out.map((c) => (c.sid === sid ? { ...c, kept: !c.kept } : c));
    const kept = !!st.out.find((c) => c.sid === sid)?.kept;
    el.classList.toggle('kept', kept);
    startChatClock();
    core.notices.pin(sid, kept);
    return;
  }
  const first = st.out[0]?.sid === sid;
  st.out = st.out.filter((c) => c.sid !== sid);
  chatGoes(sid, first ? 'cat' : 'up');
  core.notices.back(sid, 'closed');
}, true);

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

core.pointerTargets.push('.chat-tool');
