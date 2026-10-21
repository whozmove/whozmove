// The folded panel: the cat in its round glass where the name's o is in the header. The app folds the panel round the
// glass (fold:instant: in app/core/PanelWindow.m); this draws what's on it. The cat shows whose turn it is the way a
// cat would: asleep while nothing runs, watching while sessions work, looking at you while one needs your input.
// Pointed at, it looks up at you, and its list comes out round it (peek.js); what needs you comes out beside it by
// itself (chats.js); a press on it opens the panel round it, the cat becoming the name's o. While the pointer is near,
// its eyes follow it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// The cat's shapes, in its own units (448 to 92pt): the glass is 370 across (76pt) and the folded window round it 497
// (102pt), room for its shadow. Its head, its folded ears, its nose, and its eyes shut.
const CAT_HEAD = 'M0 74C-46 74 -84 50 -84 10C-84 -20 -76 -40 -64 -52C-62 -64 -54 -72 -42 -72C-34 -72 -28 -68 -24 -64'
  + 'C-8 -68 8 -68 24 -64C28 -68 34 -72 42 -72C54 -72 62 -64 64 -52C76 -40 84 -20 84 10C84 50 46 74 0 74Z';
const CAT_EARS = 'M-70 -44C-68 -60 -54 -72 -36 -70C-30 -69 -26 -66 -24 -62L-45 -43C-49 -39 -54 -38 -58 -40Z'
  + 'M70 -44C68 -60 54 -72 36 -70C30 -69 26 -66 24 -62L45 -43C49 -39 54 -38 58 -40Z';
const CAT_NOSE = 'M-7 22C-7 18 7 18 7 22C7 26 3 28 0 30C-3 28 -7 26 -7 22Z';
const CAT_SHUT = 'M-44 2Q-30 16 -16 2M16 2Q30 16 44 2';
// How low its head sits in the glass: asleep, chin down; watching the work, a little higher; looking at you, up.
// Pointed at, it lifts its head all the way (cat.css).
const CAT_LIFT = { asleep: 70, watch: 50, turn: 0 };
// The glass's units in a point, and where the eyes are, below the glass's middle, before the head is lowered.
const CAT_UNITS = 448 / 92, CAT_EYES_AT = 14, CAT_BOX = 102, CAT_GLASS_R = 185;
// The raised head's middle, in points below the glass's middle (its shape's middle, 1 unit down, moved 8 down in the
// glass): what goes on the name's o.
const CAT_HEAD_AT = 9 / CAT_UNITS;
// The eyes follow the pointer while it's within this many points of the glass's middle, so they watch it on its way
// over and not only once it's there, turning this many units at most, as far as they go without nearing the nose.
// Within this many points of the eyes they turn less, so with the pointer on its face it looks at you rather than
// flicking from side to side. With reduced motion, they don't follow.
const CAT_SEES = 480, CAT_GLANCE = 12, CAT_GAZE_NEAR = 16;
// The eyes aren't held to the pointer: they're drawn to where it is like a weight on a spring this stiff (catSpring),
// setting off and arriving softly, so they stay close to a slow pointer and take a moment to catch up with a quick one,
// and turn to it smoothly from wherever they were as it comes near.
const CAT_GAZE_SPRING = 24;
// Where the glass's middle is from its square's corners (the folded window is 102pt, the glass 76 in its middle): the
// pointer within about this far of it is on the cat.
const CAT_GLASS_IN = 51;

const catEl = document.getElementById('cat');

// What the cat does for these counts of sessions, { needs (your input: the menu bar's number), working, idle }: it
// looks at you while any needs your input, watches while any are working, and otherwise sleeps.
function catPose(counts) {
  if (counts.needs > 0) return 'turn';
  if (counts.working > 0) return 'watch';
  return 'asleep';
}

// Where the eyes look, toward the pointer at (x, y) points from the glass's middle (y running down), from where they
// are with the head lowered by `lift`: a few units at most, fewer while the pointer is close to them.
function catGaze(x, y, lift) {
  const dx = x * CAT_UNITS, dy = y * CAT_UNITS - (CAT_EYES_AT + lift), d = Math.hypot(dx, dy) || 1;
  const turn = CAT_GLANCE * Math.min(1, d / (CAT_GAZE_NEAR * CAT_UNITS));
  return { x: dx / d * turn, y: dy / d * turn };
}

// The cat, drawn once; what changes is the classes on #cat (cat.css) and where it looks.
function buildCat() {
  const half = CAT_BOX * CAT_UNITS / 2;
  catEl.innerHTML = `<svg viewBox="${-half} ${-half} ${2 * half} ${2 * half}">
    <defs><clipPath id="catInGlass"><circle r="${CAT_GLASS_R - 8}"/></clipPath></defs>
    <g clip-path="url(#catInGlass)"><g class="cat-pose"><g transform="translate(0 8)">
      <path class="cat-face" d="${CAT_HEAD}"/><path class="cat-face" d="${CAT_EARS}"/>
      <path class="cat-feature" d="${CAT_NOSE}"/>
      <g class="cat-gaze"><g class="cat-drift"><g class="cat-open">
        <circle class="cat-feature" cx="-30" cy="6" r="13"/><circle class="cat-feature" cx="30" cy="6" r="13"/>
      </g></g></g>
      <path class="cat-shut" d="${CAT_SHUT}"/>
    </g></g></g>
  </svg>`;
  catEl.classList.toggle('calm', calm.matches);
  // Asleep until the first update says otherwise: the panel can come back folded before the rows have been read.
  catEl.classList.add('asleep');
  state.cat.pose = 'asleep';
}
buildCat();
calm.addEventListener?.('change', () => {
  catEl.classList.toggle('calm', calm.matches);
  catLook();
});

// With each update (render, in panel.js): its pose, for these counts of sessions (catPose).
function drawCat(counts) {
  catPlace();
  const pose = catPose(counts);
  if (pose !== state.cat.pose) {
    catEl.classList.remove('asleep', 'watch', 'turn');
    catEl.classList.add(pose);
    state.cat.pose = pose;
    catLook();
  }
  catBreathe(counts.working);
  // Whozmove beside the panel keeps the same mood, so it grows into this one as it sits (app/core/SideCat.m).
  if (pose !== state.cat.toldPose) {
    state.cat.toldPose = pose;
    native({ type: 'catPose', pose });
  }
}

// The glass the cat sits on breathes while sessions work, as a cat does, quicker the more are working, and as a heart
// beats once 20 or more are: the app moves it (catBreathe, in app/core/PanelWindow.m), told how many as that changes.
function catBreathe(working) {
  if (state.cat.working === working) return;
  state.cat.working = working;
  native({ type: 'catBreathe', working });
}

// Where each of `els` is from the folded glass's middle, as the app takes the room beside the cat (catRoom): [x, y,
// width, height] in points, y running down, as each is laid out where it ends up (not as it moves on its way there).
function catParts(els) {
  const root = document.getElementById('root').getBoundingClientRect();
  const gx = root.left + state.cat.at.x, gy = root.top + state.cat.at.y;
  return [...els].map((el) => {
    const r = el.getBoundingClientRect(), shift = catShift(el);
    return [r.left - shift.x - gx, r.top - shift.y - gy, r.width, r.height].map((n) => Math.round(n * 10) / 10);
  });
}

// The room beside the folded cat (catRoom, in app/core/PanelWindow.m), for what comes out there, each part as catParts
// has it: the chats' (chats.js), `what` being { chats }. With none, the room goes. `then` runs once the window has it
// (catRoomTaken), or a moment later if the app doesn't say, so what comes out is never cut off by the window's edge on
// its way. Each ask is numbered, and the app says which it has taken: asked again before then, an older ask's `then`
// runs once its own room or a newer one is taken, and the newest's only once its own is.
function askCatRoom(what = {}, then = null) {
  const cat = state.cat, room = Object.assign(cat.room, what), ask = ++cat.roomAsk;
  if (then) cat.roomWaits.push({ ask, then });
  native({ type: 'catRoom', parts: room.chats, ask });
  clearTimeout(cat.roomTimer);
  cat.roomTimer = setTimeout(() => window.catRoomTaken(ask), 900);
}

window.catRoomTaken = (ask = state.cat.roomAsk) => {
  const cat = state.cat;
  if (ask >= cat.roomAsk) clearTimeout(cat.roomTimer);
  const ready = cat.roomWaits.filter((w) => w.ask <= ask);
  cat.roomWaits = cat.roomWaits.filter((w) => w.ask > ask);
  for (const { then } of ready) then();
};

// The folded cat is being dragged with something out beside it (app/core/PanelWindow.m): what's out goes in, and gives
// the room back, so the cat moves on its own; once it has stopped, what comes out of it comes out the way the app has
// said it goes from there (catWay).
window.catMoving = (moving) => chatsMoving(moving);

// The pointer on the folded cat, or its list out (peek.js): it opens its eyes and lifts its head to look at you, as
// long as the pointer stays. Open, the panel has none of it. Folded with the pointer still on the cat, it doesn't until
// the pointer has left it once.
function catHover(on) {
  if (state.cat.arriving) return;
  if (!document.body.classList.contains('collapsed') && !state.peek.open) on = false;
  if (!on) state.cat.waitForLeave = false;
  if (on && state.cat.waitForLeave) return;
  if (on === state.cat.hovering) return;
  state.cat.hovering = on;
  catEl.classList.toggle('hover', on);
  catLook();
}

// Whether the page point (x, y) is on the folded cat.
function pointOnCat(x, y) {
  const root = document.getElementById('root').getBoundingClientRect();
  return Math.hypot(x - root.left - state.cat.at.x, y - root.top - state.cat.at.y) <= CAT_GLASS_IN + 2;
}

// Its eyes on the pointer while it's near and the cat is awake (asleep, it wakes while it's pointed at); otherwise as
// its pose has them (cat.css: drifting over the work, or on you with a glance down now and then). Following it, the
// eyes are drawn to it a frame at a time (catEyes), from wherever they were as it came near.
function catLook() {
  const near = state.cat.near, gaze = catEl.querySelector('.cat-gaze');
  const awake = state.cat.pose !== 'asleep' || state.cat.hovering;
  const sees = !!near && awake && !calm.matches && document.body.classList.contains('collapsed')
    && Math.hypot(near.x, near.y) < CAT_SEES;
  if (!gaze) { catEl.classList.toggle('tracking', sees); return; }
  if (!sees) {
    catEl.classList.remove('tracking');
    state.cat.eyes = null;
    gaze.style.transform = '';
    return;
  }
  if (!catEl.classList.contains('tracking')) {
    // Where the eyes are now, drifting over the work or still easing back from the last time, taken on by the gaze as
    // the drifting stops (cat.css), so they set off from there.
    const at = catShift(gaze), drift = catShift(catEl.querySelector('.cat-drift'));
    state.cat.eyes = { x: at.x + drift.x, y: at.y + drift.y, vx: 0, vy: 0, at: 0, moving: false };
    catEl.classList.add('tracking');
  }
  const eyes = state.cat.eyes;
  if (!eyes.moving) {
    eyes.moving = true;
    eyes.at = performance.now();
    requestAnimationFrame(catEyes);
  }
}

// The eyes, a frame at a time, drawn toward where the pointer has them look, until they've come to rest there; the
// next move of the pointer sets them off again (catLook).
function catEyes(now) {
  const eyes = state.cat.eyes, near = state.cat.near, gaze = catEl.querySelector('.cat-gaze');
  if (!eyes || !near || !gaze) return;
  const to = catGaze(near.x, near.y, state.cat.pose === 'turn' || state.cat.hovering ? CAT_LIFT.turn : CAT_LIFT.watch);
  Object.assign(eyes, catSpring(eyes, to, Math.min(0.1, Math.max(0, (now - eyes.at) / 1000))));
  eyes.at = now;
  gaze.style.transform = `translate(${eyes.x.toFixed(2)}px, ${eyes.y.toFixed(2)}px)`;
  eyes.moving = Math.hypot(to.x - eyes.x, to.y - eyes.y) > 0.02 || Math.hypot(eyes.vx, eyes.vy) > 0.05;
  if (eyes.moving) requestAnimationFrame(catEyes);
}

// The eyes `dt` seconds on, drawn toward `to` from where they are, { x, y } in units, at their speed, { vx, vy } in
// units a second: pulled harder the further they have to go and held back by their speed, so they come to rest on it
// without going past it. Their place and speed after it, worked out exactly for that long rather than stepped, so
// however far apart the frames come, they never overshoot and shake back.
function catSpring(eyes, to, dt) {
  const k = CAT_GAZE_SPRING, decay = Math.exp(-k * dt);
  const along = (at, speed, target) => {
    const off = at - target, pull = (speed + k * off) * dt;
    return [target + (off + pull) * decay, (speed - k * pull) * decay];
  };
  const [x, vx] = along(eyes.x, eyes.vx, to.x), [y, vy] = along(eyes.y, eyes.vy, to.y);
  return { x, y, vx, vy };
}

// How far a part of the cat is moved now, by its animation or transition as much as by its style, in its units.
function catShift(el) {
  const m = el && /matrix\(([^)]+)\)/.exec(getComputedStyle(el).transform);
  if (!m) return { x: 0, y: 0 };
  const v = m[1].split(',').map(Number);
  return { x: v[4], y: v[5] };
}

// Which way what comes out of the cat goes, as the app sees where it is (CatWayFor, in app/core/PanelWindow.h): to its
// right while it's on the screen's left half, else its left; up from its foot while it's on the lower half, else down
// from its top; and how far there is to the screen's edge each way, `across` and `tall`. Its chats, out the other way
// (it moved quickly), come out afresh this way (chats.js).
window.catWay = (way) => {
  const was = state.cat.way;
  state.cat.way = way;
  if (!!was.right !== !!way.right || !!was.up !== !!way.up) chatsTurned();
};

// Where the pointer is from the folded glass's middle, in points with y running down, while it's near; null once it
// has gone (the app's pollPointer, app/core/PanelWindow.m).
window.catPointer = (x, y) => {
  state.cat.near = x === null || x === undefined ? null : { x, y };
  catLook();
};

// --- Opening and folding -------------------------------------------------------------------------------------------

// Where the folded glass's middle is, from #root's top-left corner: just above the name's o as laid out now, with the
// header all there however far it has slid away (header.js), so the cat's raised head is on the o (cat.css), and the
// app keeps the folded glass there (catAt, in app/core/PanelWindow.m), so the panel opens round the cat. Measured with
// each update, as the name moves up while the build shows under it; not while the cat is on its way.
function catPlace() {
  if (state.cat.arriving || state.cat.fromSide || document.body.classList.contains('departing')) return;
  const o = document.querySelector('header .name-cat')?.getBoundingClientRect();
  const root = document.getElementById('root').getBoundingClientRect();
  if (!o || !o.width) return;
  const { x, y } = catPlaceFrom(o, root, headerOff());
  if (state.cat.at && state.cat.at.x === x && state.cat.at.y === y) return;
  state.cat.at = { x, y };
  const rootEl = document.getElementById('root');
  rootEl.style.setProperty('--cat-x', `${x}px`);
  rootEl.style.setProperty('--cat-y', `${y}px`);
  native({ type: 'catAt', x, y });
}

// Where the folded glass's middle is for the name's o laid out at `o`, from #root's top-left corner at `root` (each a
// rectangle as the page measures one), with the header `off` points slid away: where it is with the header all there.
function catPlaceFrom(o, root, off) {
  return { x: Math.round((o.left + o.width / 2 - root.left) * 100) / 100,
           y: Math.round((o.top + o.height / 2 - root.top - CAT_HEAD_AT + off) * 100) / 100 };
}

// The cat's change of size between the glass and its place as the o of the name in the header: a transform for #cat
// that puts its head, measured where it is now, on the o, at the o's size. Raised (cat.css), its head's middle is the
// o's already, so it only changes size.
function catToName() {
  const head = catEl.querySelector('.cat-face')?.getBoundingClientRect();
  const o = document.querySelector('header .name-cat')?.getBoundingClientRect();
  const box = catEl.getBoundingClientRect();
  if (!head || !o || !head.width || !o.width) return null;
  const hx = head.left + head.width / 2 - box.left, hy = head.top + head.height / 2 - box.top;
  const scale = o.width / head.width;
  return { origin: `${hx.toFixed(2)}px ${hy.toFixed(2)}px`,
           transform: `translate(${(o.left + o.width / 2 - box.left - hx).toFixed(2)}px, `
             + `${(o.top + o.height / 2 - box.top - hy).toFixed(2)}px) scale(${scale.toFixed(4)})` };
}

// The panel opening round the cat (toggleCollapsed, in panel.js), before the page shows the list: the cat stays where
// it is and becomes the name's o as the glass spreads out from behind it (app/core/PanelWindow.m), the name coming in
// from both its sides as it shrinks, and then the list comes in (cat.css). `show` takes the folded look off. `already`
// when the panel is open round the cat already, its list out while it's pointed at (peek.js): the cat shrinks, and the
// name comes in, at once, the list staying as it is. With reduced motion it all just fades.
function catOpening(show, already = false) {
  if (calm.matches) { show(); return; }
  state.cat.arriving = true;
  // Its head stays where it is now (raised, as it is while pointed at, or still on its way up) and goes from there onto
  // the o as it shrinks, so nothing moves on once it has; its eyes open on the way, as the o's are.
  const pose = catEl.querySelector('.cat-pose');
  pose.style.transition = 'none';
  pose.style.transform = getComputedStyle(pose).transform;
  catEl.classList.add('waking');
  document.body.classList.add('arriving');
  document.body.classList.toggle('open-already', already);
  show();
  const move = catToName();
  if (move) catEl.style.transformOrigin = move.origin;
  // The cat starts shrinking, and the name coming in round it, as the glass starts spreading out from behind it: the
  // app says when (catGlass), once the page has been drawn at the open panel's size, as before that WebKit draws
  // nothing new. A moment later if it doesn't say. With the glass spread already, at once.
  const shrink = () => {
    if (move) catEl.style.transform = move.transform;
    document.body.classList.add('name-in');
    setTimeout(() => {
      // Put back as the folded cat where it's out of sight, without growing there: the name's own cat is the o now.
      catEl.style.transition = 'none';
      catEl.style.transform = '';
      catEl.style.transformOrigin = '';
      document.body.classList.remove('arriving', 'name-in', 'open-already');
      void catEl.offsetWidth;
      catEl.style.transition = '';
      catEl.classList.remove('hover', 'waking');
      pose.style.transform = '';
      pose.style.transition = '';
      state.cat.hovering = false;
      state.cat.arriving = false;
      askCatRoom({ chats: [] });
    }, 560);
  };
  if (already) shrink();
  else catOnGlass(shrink, 400);
}

// The panel folding round the cat (toggleCollapsed): the name's o grows back into the folded cat at once, as the click
// lands, "Wh" and "zmove" going out at its sides as it does and the list fading, while the glass closes in round it
// (app/core/PanelWindow.m). The cat doesn't look up at the pointer still on it, nor its list come out, until the
// pointer has left it once. `hide` puts the folded look on. Folding round Whozmove beside the panel, with the header
// gone, there's no o to grow from: catFromSide.
function catFolding(hide) {
  state.cat.waitForLeave = true;
  if (state.cat.fromSide) return catFromSide(hide);
  if (calm.matches) { hide(); return; }
  // Its head goes up at once, while it's out of sight, so it's as the name's o has it when it takes the o's place.
  catEl.classList.add('hover', 'snap');
  void catEl.getBoundingClientRect();
  catEl.classList.remove('snap');
  const move = catToName();
  if (!move) { hide(); return; }
  document.body.classList.add('departing');
  catEl.style.transition = 'none';
  catEl.style.transformOrigin = move.origin;
  catEl.style.transform = move.transform;
  void catEl.offsetWidth;
  hide();
  catEl.style.transition = '';
  catEl.style.transform = '';
  document.body.classList.add('name-out');
  setTimeout(() => {
    document.body.classList.remove('departing');
    catEl.style.transformOrigin = '';
    // The name stays out of sight until the header has gone (cat.css).
    setTimeout(() => document.body.classList.remove('name-out'), 250);
  }, 340);
  // Once the glass has closed in round it, it settles into its pose, unless the pointer is on it.
  setTimeout(() => { if (!state.cat.hovering) catEl.classList.remove('hover'); }, 800);
}

// Whozmove beside the panel was pressed, with the header gone (app/core/SideCat.m): the panel folds round it where it
// is, `x` and `y` from #root's top-left corner, as catPlace's are. The page stays where it is as the glass closes in,
// so the list fades in place, and the folded cat is there, out of sight, until it takes over (catLanded).
window.foldFromSide = (x, y) => {
  if (document.body.classList.contains('collapsed') || state.reading) return;
  state.cat.fromSide = true;
  state.cat.at = { x, y };
  const rootEl = document.getElementById('root');
  rootEl.style.setProperty('--cat-x', `${x}px`);
  rootEl.style.setProperty('--cat-y', `${y}px`);
  native({ type: 'catAt', x, y });
  toggleCollapsed();
};

// The cat beside the panel grows into the folded cat in front of the glass as the glass closes round it (SideCat.m):
// this one waits out of sight, raised, its eyes where its pose starts them (cat.css), and takes over from it once it
// has grown (catLanded), then settles into its pose as it does after any fold.
function catFromSide(hide) {
  catEl.classList.add('hover', 'snap', 'from-side');
  void catEl.getBoundingClientRect();
  catEl.classList.remove('snap');
  hide();
  clearTimeout(state.cat.landing);
  state.cat.landing = setTimeout(window.catLanded, 1500);
}

// Opened before the fold round Whozmove beside the panel has landed: the folded cat shows where it is, and its place
// goes back to the name's o, as at the hand-off (catLanded).
function catFromSideEnds() {
  clearTimeout(state.cat.landing);
  state.cat.fromSide = false;
  catEl.classList.remove('from-side');
  catPlace();
}

// The cat beside the panel has grown into the folded cat where the glass closed round it. The folded cat's place goes
// back to the name's o first (catPlace), the app moving the page under the glass to put it there, all out of sight;
// then this one shows there, as it is, and once it's drawn the one beside the panel goes (catShown).
window.catLanded = () => {
  clearTimeout(state.cat.landing);
  if (!catEl.classList.contains('from-side')) return;
  state.cat.fromSide = false;
  catPlace();
  requestAnimationFrame(() => requestAnimationFrame(() => {
    catEl.classList.add('landing');
    catEl.classList.remove('from-side');
    void catEl.offsetWidth;
    requestAnimationFrame(() => requestAnimationFrame(() => {
      catEl.classList.remove('landing');
      native({ type: 'catShown' });
    }));
  }));
  setTimeout(() => { if (!state.cat.hovering) catEl.classList.remove('hover'); }, 800);
};

// Runs `go` when the app says the glass is about to spread out from behind the cat (catGlass), or after `wait` ms if it
// hasn't, once either way.
function catOnGlass(go, wait) {
  let done = false;
  const once = () => {
    if (done) return;
    done = true;
    clearTimeout(timer);
    state.cat.onGlass = null;
    go();
  };
  const timer = setTimeout(once, wait);
  state.cat.onGlass = once;
}

// The app's word that the glass is about to spread out from behind the cat as the panel opens (app/core/PanelWindow.m).
window.catGlass = () => state.cat.onGlass?.();
