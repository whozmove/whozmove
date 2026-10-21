// The usage strip, at the bottom of the panel: your plan's session and week (usage.js says what), how long until each
// resets (pointing at one shows the clock time instead), a note when you're on course to run out first, Sign in when
// Claude Code isn't signed in, and the wait style while the session limit is reached (waits.js). Its handle folds it
// into one row of numbers, and that row opens it again; folded or not is kept across launches. Folded into the cat,
// the panel hides it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// The strip isn't in the list, so the list's rebuild every second never touches it: it's built once, and only its
// text and widths change, when they change. Its motion follows CONTRIBUTING.md's rules: everything stays in its lane,
// what's there before and after moves while the rest fades, and it lands exactly where the strip ends up.

// Your plan's usage as the app last found it (setUsage; app/Usage.m), Preview the Wait's stand-in while one plays,
// and whether the strip is folded into its one row (kept across launches).
moduleState({ usage: null, usagePreview: null, usageFolded: store.get('usageFolded', false) });

const usageEl = document.getElementById('usage');
const strip = {
  built: false, mode: 'hidden',  // what's showing: hidden, signin, ok, wait or folded
  moving: false,                 // a fold, an unfold or the reset is playing: presses wait, the text isn't redrawn
  waitShown: null,               // the wait being shown: { resetsAt, since }
};
const FOLD_MS = 620;

// The strip's parts, built the first time there's something to show.
function stripParts() {
  if (strip.built) return strip.parts;
  usageEl.innerHTML = `
    <div class="u-strip">
      <span class="u-handle" title="Hide usage"></span>
      ${['session', 'week'].map((w) => `
      <div class="u-row u-${w}">
        <span class="u-label">${w === 'session' ? 'Session' : 'Week'}</span>
        <span class="u-track"><span class="u-fill"></span></span>
        <span class="u-pct"></span>
        <span class="u-time"><span class="u-left"></span><span class="u-clock"></span></span>
        ${w === 'session' ? '<span class="u-message"></span><span class="u-right"></span>' : ''}
      </div>`).join('')}
      <div class="u-pace" hidden></div>
      <div class="u-signin"><span>See your session and weekly usage here</span>
        <button class="u-sign-in">Sign in</button></div>
      <svg class="u-layer" width="340" height="${WAITS.vine.height}" viewBox="0 0 340 ${WAITS.vine.height}"
           aria-hidden="true"></svg>
    </div>
    <div class="u-mini" title="Show usage">
      <span class="u-label">Session</span><span class="u-pct u-mini-session"></span>
      <span class="u-time u-hours"><span class="u-left"></span><span class="u-clock"></span></span>
      <span class="u-gap"></span>
      <span class="u-label u-mini-week-label">Week</span><span class="u-pct u-mini-week"></span>
    </div>`;
  const q = (sel) => usageEl.querySelector(sel);
  const row = (w) => ({ row: q(`.u-${w}`), track: q(`.u-${w} .u-track`), fill: q(`.u-${w} .u-fill`),
                        pct: q(`.u-${w} .u-pct`), time: q(`.u-${w} .u-time`), left: q(`.u-${w} .u-left`),
                        clock: q(`.u-${w} .u-clock`), label: q(`.u-${w} .u-label`) });
  strip.parts = {
    strip: q('.u-strip'), handle: q('.u-handle'), session: row('session'), week: row('week'), pace: q('.u-pace'),
    message: q('.u-message'), right: q('.u-right'), signIn: q('.u-sign-in'), layer: q('.u-layer'),
    mini: q('.u-mini'), miniSession: q('.u-mini-session'), miniHours: q('.u-hours'),
    miniLeft: q('.u-hours .u-left'), miniClock: q('.u-hours .u-clock'), miniWeekLabel: q('.u-mini-week-label'),
    miniWeek: q('.u-mini-week'), miniLabel: q('.u-mini .u-label'),
  };
  strip.built = true;
  return strip.parts;
}

// What the strip goes by: a preview (Working on Whozmove's Preview the Wait) while one plays, else the app's.
const usageData = () => state.usagePreview?.data ?? state.usage;
// Folded, it shows the numbers row; not while a preview plays, which is there to be seen.
const foldedNow = () => state.usageFolded && !state.usagePreview;

// The mode a view shows in.
function modeFor(view) {
  if (view.state === 'hidden' || view.state === 'signin') return view.state;
  return foldedNow() ? 'folded' : view.state;
}

// ---- Each second, and whenever the app has something new ----

function usageTick(now) {
  const view = usageView(usageData(), now);
  if (view.state === 'wait') noteWait(view, now);
  if (strip.moving) return;
  const mode = modeFor(view);
  if (mode !== strip.mode) {
    const resetCame = strip.mode === 'wait' && strip.waitShown && now >= strip.waitShown.resetsAt - 1000;
    if (resetCame && mode === 'ok' && !calm.matches && !document.body.classList.contains('collapsed')) {
      playReset(view, now);
      return;
    }
    changeMode(mode, view, now);
    return;
  }
  drawStrip(view, now);
}

// When the panel first saw this limit: the wait runs from then to the reset (the vine grows over it), kept across
// launches so it doesn't start over.
function noteWait(view, now) {
  const kept = state.usagePreview ? state.usagePreview.wait : store.get('usageWait', null);
  if (kept?.resetsAt === view.session.resetsAt) return;
  const wait = { resetsAt: view.session.resetsAt, since: now };
  if (state.usagePreview) state.usagePreview.wait = wait;
  else store.set('usageWait', wait);
}

function currentWait() {
  return state.usagePreview ? state.usagePreview.wait : store.get('usageWait', null);
}

// ---- Drawing, in place ----

// The text and widths for what's showing; nothing's touched that hasn't changed.
function drawStrip(view, now) {
  if (strip.mode === 'hidden') return;
  const p = stripParts();
  if (strip.mode === 'wait') {
    const wait = currentWait() || { since: now, resetsAt: view.session.resetsAt };
    setText(p.message, backLine(view.session.left, now, view.session.resetsAt));
    setText(p.right, `Week ${view.week.used}%`);
    if (strip.waitShown?.resetsAt !== wait.resetsAt) {
      waitStyle().build(p.layer);
      strip.waitShown = wait;
    }
    waitStyle().draw(waitProgress(wait.since, wait.resetsAt, now), calm.matches);
  }
  if (strip.mode === 'ok' || strip.mode === 'wait') {
    drawWindow(p.session, view.session, now);
    drawWindow(p.week, view.week, now);
    lineUpTimes([p.session.time, p.week.time]);
    const pace = view.pace || '';
    if (pace !== p.pace.textContent) {
      const before = p.strip.offsetHeight;
      p.pace.textContent = pace;
      p.pace.hidden = !pace;
      easeHeight(p.strip, before);
    }
  }
  if (strip.mode === 'folded') {
    setText(p.miniSession, `${view.session.used}%`);
    p.miniSession.style.color = view.session.severity === 'normal' ? '' : view.session.colour;
    setTimes(p.miniHours, p.miniLeft, p.miniClock, hoursLeft(view.session.left),
             clockAt(view.session.resetsAt, now));
    setText(p.miniWeek, `${view.week.used}%`);
    p.miniWeek.style.color = view.week.severity === 'normal' ? '' : view.week.colour;
  }
}

function drawWindow(parts, win, now) {
  parts.fill.style.width = `${win.used}%`;
  parts.fill.style.background = win.colour;
  setText(parts.pct, `${win.used}%`);
  parts.pct.style.color = win.severity === 'normal' ? '' : win.colour;
  setTimes(parts.time, parts.left, parts.clock, timeLeft(win.left), clockAt(win.resetsAt, now));
}

// Time left, and the clock time it gives way to when pointed at: each column as wide as its text (in the strip, as the
// wider of its two rows': lineUpTimes), so the bar beside it gives way as the clock time is pushed in (usage.css).
function setTimes(column, left, clock, leftText, clockText) {
  if (left.textContent === leftText && clock.textContent === clockText) return;
  left.textContent = leftText;
  clock.textContent = clockText;
  column.widths = { left: leftText ? Math.ceil(textWidth(left, leftText)) + 1 : 0,
                    clock: clockText ? Math.ceil(textWidth(clock, clockText)) + 1 : 0 };
  column.style.setProperty('--left-w', `${column.widths.left}px`);
  column.style.setProperty('--clock-w', `${column.widths.clock}px`);
}

// The strip's two rows read as a table: both time columns as wide as the wider time left, so their percents and their
// bars' ends line up. Pointed at, a row's column still widens to its clock time if that's wider, its bar giving way.
function lineUpTimes(columns) {
  const left = Math.max(...columns.map((c) => c.widths?.left ?? 0));
  for (const c of columns) {
    c.style.setProperty('--left-w', `${left}px`);
    c.style.setProperty('--clock-w', `${Math.max(left, c.widths?.clock ?? 0)}px`);
  }
}

// ---- Changing what's shown ----

// From one mode to another, other than folding and the reset: the new content comes in the panel's way (fading in,
// lifting 3px, sharpening) as the strip's height eases from the old to the new; going, the strip fades as it eases
// away to nothing.
function changeMode(mode, view, now) {
  const animate = !calm.matches && !document.body.classList.contains('collapsed') && strip.mode !== mode;
  if (mode === 'hidden') {
    if (!animate || strip.mode === 'hidden') {
      setMode('hidden');
      return reportHeight();
    }
    strip.moving = true;
    return foldAway(usageEl, () => {
      strip.moving = false;
      setMode('hidden');
      reportHeight();
    });
  }
  const before = strip.mode === 'hidden' ? 0 : usageEl.offsetHeight;
  setMode(mode);
  drawStrip(view, now);
  if (!animate) return reportHeight();
  growIn(usageEl, before);
}

// Shows a mode's parts. Anything but the wait takes the wait style's drawing away, unless it's kept to fade (a fold).
function setMode(mode, keepDrawing = false) {
  stripParts();
  strip.mode = mode;
  showModeClasses(mode);
  usageEl.hidden = mode === 'hidden';
  if (mode !== 'wait' && !keepDrawing) {
    if (strip.waitShown) waitStyle().clear();
    strip.waitShown = null;
    strip.parts.layer.replaceChildren();
  }
}

function showModeClasses(mode) {
  for (const m of ['signin', 'ok', 'wait', 'folded']) usageEl.classList.toggle(`is-${m}`, mode === m);
}

// ---- Folding into one row, and back ----

// The strip folds into its numbers row (fold) or opens from it. What's in both travels between them: "Session", the
// two percents, and Session's time left, which rolls into the hours on the way ("2h 59m" to "3h"). The bars wind into
// their numbers, Session's toward its label and Week's toward its percent; the rest fades. The strip's height and the
// row's ease against each other, and the panel follows. With reduced motion, it just changes.
function foldStrip(fold) {
  if (strip.moving || !['ok', 'wait', 'folded'].includes(strip.mode)) return;
  state.usageFolded = fold;
  store.set('usageFolded', fold);
  const now = Date.now(), view = usageView(usageData(), now), next = modeFor(view);
  if (calm.matches) {
    setMode(next);
    drawStrip(view, now);
    return reportHeight();
  }
  const p = stripParts();
  // Where a piece's text is, in the strip's own coordinates: a percent in the strip sits at the right of its column.
  const textAt = (el, width) => {
    const r = el.getBoundingClientRect(), b = usageEl.getBoundingClientRect();
    const right = getComputedStyle(el).textAlign === 'right';
    return { x: (right ? r.right - width : r.left) - b.left, y: r.top - b.top + r.height / 2 };
  };
  // Where the shared pieces are now, and where they'll be: the new mode drawn and measured, then the old put back.
  // While the session limit is reached, the strip shows only "Session" of them (its line, the week's figure and the
  // vine instead), so only that travels.
  const was = strip.mode, open = fold ? was : next;
  const shared = open === 'wait' ? ['label'] : ['label', 'pct', 'time', 'week'];
  const stripSide = { label: p.session.label, pct: p.session.pct, time: p.session.left, week: p.week.pct };
  const rowSide = { label: p.miniLabel, pct: p.miniSession, time: p.miniLeft, week: p.miniWeek };
  const [fromSide, toSide] = fold ? [stripSide, rowSide] : [rowSide, stripSide];
  const texts = {}, from = {}, to = {};
  for (const k of shared) texts[k] = fromSide[k].textContent;
  const ghostWidth = (el, text) => Math.ceil(textWidth(el, text));
  for (const k of shared) from[k] = textAt(fromSide[k], ghostWidth(fromSide[k], texts[k]));
  const stripHeight = p.strip.offsetHeight;
  // The strip's time columns take any new width at once, so its percents are measured where they'll be.
  const columns = [p.session.time, p.week.time];
  for (const c of columns) c.style.transition = 'none';
  setMode(next, true);
  drawStrip(view, now);
  const intoText = toSide.time.textContent;
  for (const k of shared) to[k] = textAt(toSide[k], ghostWidth(toSide[k], k === 'time' ? intoText : texts[k]));
  for (const c of columns) c.style.transition = '';
  const fullHeight = fold ? stripHeight : p.strip.offsetHeight;
  // Both showing while they move: the strip, laid out as it is while open, its height going to or from nothing, and
  // the row's to or from 26px.
  showModeClasses(open);
  usageEl.classList.add('is-folding');
  strip.moving = true;
  const anims = [];
  const run = (el, frames, ms, delay = 0) => {
    const a = el.animate(frames, { duration: ms, delay, easing: MORPH_EASE, fill: 'both' });
    anims.push(a);
    return a;
  };
  // Their padding and border fold with their height, as morph's lines' do (BOX_KEYS), or the strip stops at a sliver of
  // padding, the row under it sits that much low, and the panel drops the rest at the end.
  const boxOf = (el) => {
    const cs = getComputedStyle(el);
    return Object.fromEntries(BOX_KEYS.map((k) => [k, cs[k]]));
  };
  const shut = { height: '0px', ...FLAT };
  const stripOpen = { height: `${fullHeight}px`, ...boxOf(p.strip) }, miniOpen = { height: '26px', ...boxOf(p.mini) };
  run(p.strip, fold ? [stripOpen, shut] : [shut, stripOpen], 520, fold ? 160 : 0);
  run(p.mini, fold ? [shut, miniOpen] : [miniOpen, shut], 520, fold ? 160 : 0);
  // The copies that travel, centred on each piece's line; the pieces themselves stay hidden till they land.
  const ghosts = [];
  const ghost = (source, html, at) => {
    const cs = getComputedStyle(source), g = document.createElement('span');
    g.className = 'u-ghost';
    g.innerHTML = html;
    Object.assign(g.style, { fontSize: cs.fontSize, color: cs.color, left: `${at.x}px`, top: `${at.y - 8}px` });
    usageEl.appendChild(g);
    ghosts.push(g);
    return g;
  };
  const hidden = shared.flatMap((k) => [stripSide[k], rowSide[k]]);
  // Each sets off after the one ahead of it on the way (folding, they go left; opening, right), so none catches up
  // with another: Session's percent before its time when folding, after it when opening.
  const delays = { label: 80, week: 100, pct: fold ? 60 : 90, time: fold ? 90 : 60 };
  for (const k of ['label', 'pct', 'week']) {
    if (!shared.includes(k)) continue;
    const g = ghost(fromSide[k], esc(texts[k]), from[k]);
    run(g, [{ transform: 'translate(0, 0)' },
            { transform: `translate(${to[k].x - from[k].x}px, ${to[k].y - from[k].y}px)` }], 560, delays[k]);
  }
  // Session's time left, rolling into the hours (or back) as it goes.
  if (shared.includes('time')) {
    const tg = ghost(fromSide.time, `<span>${esc(texts.time)}</span><span>${esc(intoText)}</span>`, from.time);
    tg.classList.add('u-ghost-roll');
    run(tg, [{ transform: 'translate(0, 0)' },
             { transform: `translate(${to.time.x - from.time.x}px, ${to.time.y - from.time.y}px)` }], 600,
        delays.time);
    const [out, into] = tg.children;
    const still = { transform: 'none', opacity: 1 }, above = { transform: 'translateY(-100%)', opacity: 0 },
          below = { transform: 'translateY(100%)', opacity: 0 };
    run(out, [{ ...still, offset: 0 }, { ...still, offset: 0.3 }, { ...above, offset: 0.7 }, above], 600, delays.time);
    run(into, [{ ...below, offset: 0 }, { ...below, offset: 0.3 }, { ...still, offset: 0.7 }, still], 600,
        delays.time);
  }
  for (const el of hidden) el.style.visibility = 'hidden';
  // The bars wind into their numbers, or unwind out of them.
  const wind = fold
    ? [{ transform: 'scaleX(1)', opacity: 1 }, { transform: 'scaleX(.05)', opacity: 1, offset: 0.8 },
       { transform: 'scaleX(0)', opacity: 0 }]
    : [{ transform: 'scaleX(0)', opacity: 0 }, { transform: 'scaleX(.05)', opacity: 1, offset: 0.2 },
       { transform: 'scaleX(1)', opacity: 1 }];
  p.session.track.style.transformOrigin = 'left center';
  p.week.track.style.transformOrigin = 'right center';
  run(p.session.track, wind, 520, fold ? 60 : 300);
  run(p.week.track, wind, 520, fold ? 100 : 340);
  // What only one side has fades: the strip's handle, Week label, week time and pace (or while waiting, its line, the
  // week's figure and the vine); the row's Week (and while waiting, its numbers).
  const fading = [p.handle, p.week.label, p.week.time, p.pace, p.message, p.right, p.layer];
  const rowOnly = open === 'wait' ? [p.miniWeekLabel, p.miniSession, p.miniHours, p.miniWeek] : [p.miniWeekLabel];
  const out3 = [{ opacity: 1, filter: 'blur(0)', transform: 'none' },
                { opacity: 0, filter: 'blur(1.5px)', transform: 'translateY(3px)' }];
  for (const el of fading) run(el, fold ? out3 : [...out3].reverse(), fold ? 240 : 500, fold ? 0 : 380);
  for (const el of rowOnly) run(el, fold ? [...out3].reverse() : out3, fold ? 500 : 220, fold ? 420 : 0);
  followHeight(FOLD_MS + 120);
  Promise.all(anims.map((a) => a.finished)).then(() => {
    usageEl.classList.remove('is-folding');
    setMode(next);
    drawStrip(view, Date.now());
    anims.forEach((a) => a.cancel());
    ghosts.forEach((g) => g.remove());
    for (const el of hidden) el.style.visibility = '';
    p.session.track.style.transformOrigin = p.week.track.style.transformOrigin = '';
    strip.moving = false;
    reportHeight();
    syncHover();  // the pointer hasn't moved, but what's under it has
  }, () => { strip.moving = false; });
}

// ---- The reset ----

// The session limit has reset while you watched: the wait style plays its reset (the vine's: it blooms, its leaves fly
// off, its stem pulls taut into the session's bar, fills it and drains), then the strip is as it normally is.
function playReset(view, now) {
  const p = stripParts(), style = waitStyle();
  // Where the session's bar is in the normal strip, and how tall that is: the strip laid out as it will be and
  // measured, with the wait style's drawing kept (the reset starts from it). The first frame below gives it back its
  // waiting height before anything is painted.
  showModeClasses('ok');
  usageEl.classList.add('is-resetting');
  // The session's time column takes its new width at once (the week's, as the session's is empty as it starts over,
  // and the bar beside it isn't shown yet), so the bar is measured where it ends up, not partway through the column's
  // transition.
  p.session.time.style.transition = 'none';
  drawWindow(p.session, view.session, now);
  drawWindow(p.week, view.week, now);
  lineUpTimes([p.session.time, p.week.time]);
  const layer = p.layer.getBoundingClientRect(), track = p.session.track.getBoundingClientRect();  // in its drawing
  const bar = { x0: track.left - layer.left, x1: track.right - layer.left,
                y: track.top + track.height / 2 - layer.top };
  const heights = { wait: style.height, normal: p.strip.offsetHeight };
  setText(p.message, 'Your move');
  p.message.style.color = 'var(--turn)';
  const stage = { strip: p.strip, message: p.message, right: p.right, track: p.session.track, fill: p.session.fill,
                  percent: p.session.pct, week: p.week.row, weekFill: p.week.fill, weekUsed: view.week.used,
                  bar, heights };
  strip.moving = true;
  p.session.fill.style.transition = p.week.fill.style.transition = 'none';
  const started = performance.now();
  (function frame() {
    const t = performance.now() - started;
    style.resetFrame(Math.min(t, style.resetMs), stage);
    reportHeight();
    if (t < style.resetMs) return requestAnimationFrame(frame);
    for (const el of [p.strip, p.message, p.right, p.session.track, p.session.fill, p.session.pct, p.week.row,
                      p.week.fill])
      el.removeAttribute('style');
    p.session.time.style.transition = '';  // its widths stay: they're set on its style too
    usageEl.classList.remove('is-resetting');
    style.clear();
    strip.parts.layer.replaceChildren();
    strip.waitShown = null;
    strip.moving = false;
    strip.mode = 'ok';
    usageTick(Date.now());
    reportHeight();
  })();
}

// ---- Presses ----

function pressUsage(e) {
  if (e.button !== 0 || strip.moving) return;
  if (e.target.closest('.u-handle')) foldStrip(true);
  else if (e.target.closest('.u-mini')) foldStrip(false);
  else if (e.target.closest('.u-sign-in')) {
    native({ type: 'usageSignIn' });
    const button = e.target.closest('.u-sign-in');
    button.textContent = 'Opening…';
    setTimeout(() => { button.textContent = 'Sign in'; }, 5000);
  }
}

// ---- Preview the Wait ----

// Working on Whozmove's Preview the Wait: a 20-second wait at the session limit, then its reset, then the strip as it
// was. The vine grows smoothly meanwhile, not a step a second as in a real wait of hours.
function playPreviewWait() {
  const now = Date.now();
  if (document.body.classList.contains('collapsed')) toggleCollapsed();
  const real = usageView(state.usage, now);
  state.usagePreview = {
    data: { state: 'ok', session: { used: 100, resetsAt: now + 20000 },
            week: { used: real.week?.used ?? 25, resetsAt: real.week?.resetsAt || now + 40 * 60 * 60000 },
            limits: [], extraUsage: false },
    wait: { resetsAt: now + 20000, since: now },
  };
  usageTick(now);
  (function grow() {
    const preview = state.usagePreview;
    if (!preview || strip.mode !== 'wait' || strip.moving) return;
    waitStyle().draw(waitProgress(preview.wait.since, preview.wait.resetsAt, Date.now()), calm.matches);
    if (Date.now() >= preview.wait.resetsAt) {
      usageTick(Date.now());  // the reset
      setTimeout(endPreview, WAITS.vine.resetMs + 1500);
      return;
    }
    requestAnimationFrame(grow);
  })();
}

function endPreview() {
  if (strip.moving) return setTimeout(endPreview, 200);
  state.usagePreview = null;
  usageTick(Date.now());
}

// ---- What it plugs into ----

// Your plan's usage, as the app found it (app/Usage.m): what the strip shows.
window.setUsage = (usage) => {
  state.usage = usage;
  usageTick(Date.now());
};

// Working on Whozmove's Preview the Wait, in the pawn menu: the strip's wait and reset, played now.
window.previewWait = () => playPreviewWait();

// It keeps time with the rows' updates (its time left, and its wait), and has room made for it under the list.
core.updates.push(usageTick);
core.strips.push('usage');
core.pointerTargets.push('.u-strip', '.u-row', '.u-handle', '.u-mini', '.u-sign-in');
core.starts.push(() => {
  // Its handle folds it into one row, that row opens it again, and Sign in opens a terminal signing Claude Code in.
  // It's outside the list, so it has a listener of its own.
  usageEl.addEventListener('mousedown', (e) => pressUsage(e));
});
