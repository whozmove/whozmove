// The folded panel: the cat in its round glass where the name's o is in the header. The app folds the panel round the
// glass (fold:instant: in app/core/PanelWindow.m); this draws what's on it. The cat shows whose turn it is the way a
// cat would: asleep while nothing runs, watching while sessions work, looking at you while one needs your input. While
// the pointer is on it, what's waiting on you comes out beside it by name, and everything else as its dot: a press on
// either opens that conversation, and a press on the cat opens the panel round it, the cat becoming the name's o. While
// the pointer is near, its eyes follow it.
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
// The labels, in points from the glass's middle, counted away from the cat. What's waiting on you has a tag by name,
// at most this many: the first one's near end this far out (6pt off the glass) and its middle level with the glass's,
// each next one this far down. Everything else is its dot, in a row this far below the last tag's middle (level with
// the glass's middle when there's none): the first under the tags' dots, each next one this far out, this many to a
// row, each next row this far down.
const CAT_TAG_END = 44, CAT_TAG_STEP = 30, CAT_NAMES_MOST = 5;
const CAT_DOTS_BELOW = 26, CAT_DOT_FIRST = 57, CAT_DOT_STEP = 17, CAT_DOTS_ROW = 12, CAT_DOT_ROWS_STEP = 18;
// A tag's height, and the box a dot is pointed at and pressed in (cat.css).
const CAT_TAG_TALL = 24, CAT_DOT_WIDE = 17, CAT_DOT_TALL = 20;
// Where the glass's middle is from its square's corners (the folded window is 102pt, the glass 76 in its middle).
const CAT_GLASS_IN = 51;
// The labels come out this long after the pointer comes onto the cat, each this long after the one before.
const CAT_TAGS_START = 0.08, CAT_TAGS_STAGGER = 0.035;

const catEl = document.getElementById('cat');
const catTagsEl = document.getElementById('catTags');

// What the cat does for these counts of sessions, { needs (your input: the menu bar's number), working, idle }: it
// looks at you while any needs your input, watches while any are working, and otherwise sleeps.
function catPose(counts) {
  if (counts.needs > 0) return 'turn';
  if (counts.working > 0) return 'watch';
  return 'asleep';
}

// Where each session's label goes, for the sessions in the list's order, each { section } (whose-move.js): { names,
// dots }, each a list of { i, y } and { i, x, y }, `i` the session's place in the list, `y` its middle down from the
// glass's middle and `x` a dot's middle out from it, in points. The first sessions waiting on you have a tag by name;
// the rest of them, first, and everything else have a dot.
function catLabels(kinds) {
  const names = [], dots = [];
  kinds.forEach((k, i) => (k.section === 'turn' && names.length < CAT_NAMES_MOST ? names : dots).push(i));
  const row = names.length ? (names.length - 1) * CAT_TAG_STEP + CAT_DOTS_BELOW : 0;
  return {
    names: names.map((i, n) => ({ i, y: n * CAT_TAG_STEP })),
    dots: dots.map((i, n) => ({ i, x: CAT_DOT_FIRST + (n % CAT_DOTS_ROW) * CAT_DOT_STEP,
                                y: row + Math.floor(n / CAT_DOTS_ROW) * CAT_DOT_ROWS_STEP })),
  };
}

// Where a label `tall` points high goes, its near end `out` points from the glass's middle and its middle `y` below it,
// as a style for its place in #catTags, which is at the top-right corner of the cat's square: to the cat's left, or to
// its right while it's on the screen's left half (`right`).
function catLabelStyle(out, y, tall, right) {
  const across = right ? `left: ${(out - CAT_GLASS_IN).toFixed(1)}px` : `right: ${(CAT_GLASS_IN + out).toFixed(1)}px`;
  return `${across}; top: ${(CAT_GLASS_IN + y - tall / 2).toFixed(1)}px`;
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
  catTagsEl.classList.toggle('calm', calm.matches);
  // Asleep until the first update says otherwise: the panel can come back folded before the rows have been read.
  catEl.classList.add('asleep');
  state.cat.pose = 'asleep';
}
buildCat();
calm.addEventListener?.('change', () => {
  catEl.classList.toggle('calm', calm.matches);
  catTagsEl.classList.toggle('calm', calm.matches);
  catLook();
});

// With each update (render, in panel.js): its pose, and a label for each of `sessions` (in the list's order, `kinds`
// saying what each is and where the list shows it, { kind, section }), drawn again only when they've changed. New ones
// drawn while the labels are out show in their places at once, as an element's first look isn't animated, and the app
// is asked for the room they need now.
function drawCat(counts, sessions, kinds) {
  catPlace();
  const pose = catPose(counts);
  if (pose !== state.cat.pose) {
    catEl.classList.remove('asleep', 'watch', 'turn');
    catEl.classList.add(pose);
    state.cat.pose = pose;
    catLook();
  }
  catBreathe(counts.working);
  const names = sessions.map((s) => s.name || base(s.cwd));
  state.cat.drawn = { counts, sessions, kinds };
  const right = state.cat.right;
  // Each label's dot, as the list draws it for its kind (rows.css): a Claude Desktop conversation that isn't running
  // has a hollow one.
  const kindOf = (i) => kinds[i].kind + (sessions[i].status === 'closed' ? ' closed' : '');
  const dot = (i) => `<span class="cat-mark ${kindOf(i)}"><span class="dot"></span></span>`;
  const key = (right ? 'right\n' : '')
    + sessions.map((s, i) => `${kindOf(i)}:${kinds[i].section}:${s.sessionId}:${names[i]}`).join('\n');
  if (key === state.cat.marks || state.cat.arriving) return;
  state.cat.marks = key;
  // They come out one after another: the tags, then the dots.
  let order = 0;
  const delay = () => `--delay: ${(CAT_TAGS_START + order++ * CAT_TAGS_STAGGER).toFixed(3)}s`;
  const laid = catLabels(kinds);
  catTagsEl.innerHTML = laid.names.map(({ i, y }) => `<div class="cat-tag" data-id="${esc(sessions[i].sessionId)}" `
      + `style="${catLabelStyle(CAT_TAG_END, y, CAT_TAG_TALL, right)}; ${delay()}">${dot(i)}`
      + `<span class="cat-tag-name">${esc(names[i])}</span></div>`).join('')
    + laid.dots.map(({ i, x, y }) => `<div class="cat-dot${kinds[i].kind === 'idle' ? ' quiet' : ''}" `
      + `data-id="${esc(sessions[i].sessionId)}" `
      + `style="${catLabelStyle(x - CAT_DOT_WIDE / 2, y, CAT_DOT_TALL, right)}; ${delay()}">${dot(i)}`
      + `<span class="cat-dot-name">${esc(names[i])}</span></div>`).join('');
  if (state.cat.hovering) askForTagsRoom();
}

// The glass the cat sits on breathes while sessions work, as a cat does, quicker the more are working, and as a heart
// beats once 20 or more are: the app moves it (catBreathe, in app/core/PanelWindow.m), told how many as that changes.
function catBreathe(working) {
  if (state.cat.working === working) return;
  state.cat.working = working;
  native({ type: 'catBreathe', working });
}

// Asks the app for the room the labels need while they're out (catFan, in app/core/PanelWindow.m).
function askForTagsRoom() {
  const room = catTagsRoom();
  if (room) native({ type: 'catFan', on: true, width: room.width, height: room.height });
}

// How much of the screen the labels need, from the cat's square's top corner on the far side from them, so the app can
// make room for them while they're out (catFan, in app/core/PanelWindow.m): { width, height } in points, or null with
// none. A dot's name, under it while it's pointed at, is counted in, as wide as it reaches past the dot on either side.
function catTagsRoom() {
  const labels = [...catTagsEl.querySelectorAll('.cat-tag, .cat-dot')];
  if (!labels.length) return null;
  // On the cat's right, they're measured from the square's left end (2 × CAT_GLASS_IN from its right).
  let width = 0, height = 0;
  for (const label of labels) {
    const name = label.querySelector('.cat-dot-name');
    const past = name ? Math.max(0, (name.offsetWidth - label.offsetWidth) / 2) : 0;
    const across = state.cat.right ? 2 * CAT_GLASS_IN + parseFloat(label.style.left) + label.offsetWidth
                                   : parseFloat(label.style.right) + label.offsetWidth;
    width = Math.max(width, across + past);
    height = Math.max(height, parseFloat(label.style.top)
      + (name ? name.offsetTop + name.offsetHeight : label.offsetHeight));
  }
  // Room for their shadow too.
  return { width: Math.ceil(width + 12), height: Math.ceil(height + 16) };
}

// The pointer on the folded cat (hoverAt and hoverEnd, in panel.js): the labels come out, the app making room for them
// first; as it leaves, they fade together, and then the room goes. Open, the panel has none of it. Folded with the
// pointer still on the cat, they don't come until the pointer has left it once.
function catHover(on) {
  if (state.cat.arriving) return;
  if (!document.body.classList.contains('collapsed')) on = false;
  if (!on) state.cat.waitForLeave = false;
  if (on && state.cat.waitForLeave) return;
  if (on === state.cat.hovering) return;
  state.cat.hovering = on;
  clearTimeout(state.cat.leaving);
  if (on) {
    askForTagsRoom();
    catEl.classList.remove('leaving', 'reset');
    catTagsEl.classList.remove('leaving', 'reset');
    catEl.classList.add('hover');
    catTagsEl.classList.add('out');
  } else {
    catTagsEl.querySelectorAll('.is-pointed').forEach((t) => t.classList.remove('is-pointed'));
    catEl.classList.add('leaving');
    catEl.classList.remove('hover');
    catTagsEl.classList.add('leaving');
    catTagsEl.classList.remove('out');
    state.cat.leaving = setTimeout(() => {
      catEl.classList.add('reset');
      catEl.classList.remove('leaving');
      catTagsEl.classList.add('reset');
      catTagsEl.classList.remove('leaving');
      if (!state.cat.arriving) native({ type: 'catFan', on: false });
      requestAnimationFrame(() => requestAnimationFrame(() => {
        catEl.classList.remove('reset');
        catTagsEl.classList.remove('reset');
      }));
    }, 420);
  }
  catLook();
}

// Whether the page point (x, y) is on the folded cat or one of its labels: what keeps them out while the room the app
// made for them is pointed at, and lets the pointer go from the cat to a label, and from one to another.
function catPointedAt(x, y) {
  const root = document.getElementById('root').getBoundingClientRect();
  const gx = root.left + state.cat.at.x, gy = root.top + state.cat.at.y;
  const labels = [...catTagsEl.querySelectorAll('.cat-tag, .cat-dot')];
  // The one label pointed at is lit, or, for a dot, shows its name; on the cat, none is.
  const point = (label) => labels.forEach((l) => l.classList.toggle('is-pointed', l === label));
  if (Math.hypot(x - gx, y - gy) <= CAT_GLASS_IN + 2) { point(null); return true; }
  if (!state.cat.hovering || !labels.length) return false;
  const inside = (r, by) => x >= r.left - by && x <= r.right + by && y >= r.top - by && y <= r.bottom + by;
  // A dot pointed at keeps its name while the pointer is on the name. Anywhere between the cat and its labels, the
  // pointer is still on its way to one.
  let on = null, box = { left: gx, right: gx, top: gy, bottom: gy };
  for (const label of labels) {
    const r = label.getBoundingClientRect();
    const name = label.classList.contains('is-pointed') && label.querySelector('.cat-dot-name');
    if (!on && (inside(r, 2) || (name && inside(name.getBoundingClientRect(), 0)))) on = label;
    box = { left: Math.min(box.left, r.left), right: Math.max(box.right, r.right),
            top: Math.min(box.top, r.top), bottom: Math.max(box.bottom, r.bottom) };
  }
  point(on);
  return !!on || inside(box, 6);
}

// A press on a label or a dot opens that conversation where it is, as its row's would, and the panel stays folded: the
// labels go back in. The keyboard stays with the conversation.
catTagsEl.addEventListener('mousedown', (e) => {
  const label = e.target.closest('.cat-tag, .cat-dot');
  if (!label || e.button !== 0) return;
  e.preventDefault();
  const s = state.last.sessions.find((x) => x.sessionId === label.dataset.id);
  if (s) openSession(s);
  catHover(false);
});

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

// Which side of the cat the labels come out on, as the app sees where it is: its right while it's on the screen's left
// half, its left otherwise. Laid out again at once, while they're in.
window.catSide = (right) => {
  if (state.cat.right === right) return;
  state.cat.right = right;
  catTagsEl.classList.toggle('to-right', right);
  state.cat.marks = null;
  const d = state.cat.drawn;
  if (d) drawCat(d.counts, d.sessions, d.kinds);
};

// Where the pointer is from the folded glass's middle, in points with y running down, while it's near; null once it
// has gone (the app's pollPointer, app/core/PanelWindow.m).
window.catPointer = (x, y) => {
  state.cat.near = x === null || x === undefined ? null : { x, y };
  catLook();
};

// --- Opening and folding -------------------------------------------------------------------------------------------

// Where the folded glass's middle is, from #root's top-left corner: just above the name's o as laid out now, so the
// cat's raised head is on the o (cat.css), and the app keeps the folded glass there (catAt, in
// app/core/PanelWindow.m), so the panel opens round the cat. Measured with each update, as the name moves up while the
// build shows under it; not while the cat is on its way.
function catPlace() {
  if (state.cat.arriving || document.body.classList.contains('departing')) return;
  const o = document.querySelector('header .name-cat')?.getBoundingClientRect();
  const root = document.getElementById('root').getBoundingClientRect();
  if (!o || !o.width) return;
  const x = Math.round((o.left + o.width / 2 - root.left) * 100) / 100;
  const y = Math.round((o.top + o.height / 2 - root.top - CAT_HEAD_AT) * 100) / 100;
  if (state.cat.at && state.cat.at.x === x && state.cat.at.y === y) return;
  state.cat.at = { x, y };
  const rootEl = document.getElementById('root');
  rootEl.style.setProperty('--cat-x', `${x}px`);
  rootEl.style.setProperty('--cat-y', `${y}px`);
  native({ type: 'catAt', x, y });
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
// from both its sides as it shrinks, and then the list comes in (cat.css); the labels that were out fade where they
// are. `show` takes the folded look off. With reduced motion it all just fades.
function catOpening(show) {
  if (calm.matches) { show(); return; }
  state.cat.arriving = true;
  clearTimeout(state.cat.leaving);
  catEl.classList.remove('leaving', 'reset');
  // Its head stays where it is now (raised, as it is while pointed at, or still on its way up) and goes from there onto
  // the o as it shrinks, so nothing moves on once it has; its eyes open on the way, as the o's are.
  const pose = catEl.querySelector('.cat-pose');
  pose.style.transition = 'none';
  pose.style.transform = getComputedStyle(pose).transform;
  catEl.classList.add('waking');
  document.body.classList.add('arriving');
  catTagsEl.classList.add('into-rows');
  show();
  const move = catToName();
  if (move) catEl.style.transformOrigin = move.origin;
  // The cat starts shrinking, and the name coming in round it, as the glass starts spreading out from behind it: the
  // app says when (catGlass), once the page has been drawn at the open panel's size, as before that WebKit draws
  // nothing new. A moment later if it doesn't say.
  catOnGlass(() => {
    if (move) catEl.style.transform = move.transform;
    document.body.classList.add('name-in');
    setTimeout(() => {
      // Put back as the folded cat where it's out of sight, without growing there: the name's own cat is the o now.
      catEl.style.transition = 'none';
      catEl.style.transform = '';
      catEl.style.transformOrigin = '';
      document.body.classList.remove('arriving', 'name-in');
      void catEl.offsetWidth;
      catEl.style.transition = '';
      catTagsEl.classList.remove('into-rows', 'out');
      catEl.classList.remove('hover', 'waking');
      pose.style.transform = '';
      pose.style.transition = '';
      state.cat.hovering = false;
      state.cat.arriving = false;
      native({ type: 'catFan', on: false });
    }, 560);
  }, 400);
}

// The panel folding round the cat (toggleCollapsed): the name's o grows back into the folded cat at once, as the click
// lands, "Wh" and "zmove" going out at its sides as it does and the list fading, while the glass closes in round it
// (app/core/PanelWindow.m). The labels don't come back, nor, while the pointer is still on the cat, until the pointer
// has left it once. `hide` puts the folded look on.
function catFolding(hide) {
  state.cat.waitForLeave = true;
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
