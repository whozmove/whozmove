// The usage card behind the panel: a page of its own, in the card's own window under the panel (app/UsageCard.m).
// Folded, the card's background is the bar of the window nearer its limit, or of the only one with a reading (edgeView
// in usage.js), only a thin line of it showing under the panel's bottom edge; pointed at, the card slides out with the
// numbers on it. Pressed, it opens: it grows further down, and its background shrinks into the bar of its own row as
// the strip comes in on it: your plan's session and week (usage.js says what), how long until each resets (pointing at
// one shows the clock time instead), where each ends up by its reset at this pace (beside its percent, and dotted on
// along its bar), a line saying what that comes to and what to do about it (or, with a gear set, where the week ends at
// it), your gear with its seats (gear.js), and the wait style while the session limit is reached (waits.js). A press
// anywhere on it but your gear's line folds it back. Signed out, it's open, with Sign in. Open or folded is kept across
// launches.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// Its motion follows CONTRIBUTING.md's rules. What's in both the folded card and the open one moves: the card itself,
// its coloured background, which becomes its row's bar, and the words on it, which travel to their places in the rows,
// each measured where it is and where it lands; the rest fades. Words keep to their lanes: those going to the second
// row go down first, those staying go along the first, and what's in the way leaves before anything passes it.

// Where the panel is in this page: the card's window starts this far left of the panel and this far above its bottom
// edge (kBeside and kCorner in app/UsageCard.m), and the open card is as wide as the panel.
const UC_LEFT = 24, UC_TOP = 24, UC_WIDTH = 340;
// What shows of the card under the panel's edge at rest, how much more slides out when it's pointed at, how far up
// into the panel the pointer brings it out from, and the card's corners (the panel's). Folded, the card is in from
// each of the panel's sides by the panel's corner, so what shows at rest is a straight line under the flat of the
// panel's edge, its ends drawn in by the card's own corners, and not a second outline of the panel; slid out, it's in
// by half that, widening a little as it comes out (usage.css). Open, it's as wide as the panel.
const UC_LINE = 3, UC_SLIDE = 24, UC_BAND = 8, UC_CORNER = 24, UC_INSET = 24, UC_OUT_INSET = 12;
// The colour's box and the words' boxes start this far up behind the panel, and are this tall: the card's background
// and the band's words are drawn in them, and they're measured from there.
const UC_ABOVE = 100, UC_BOX = 300;
// The panel's own curve (MORPH_EASE in parts/morph/page/morph.js).
const UC_EASE = 'cubic-bezier(.2, .8, .2, 1)';
const ucCalm = matchMedia('(prefers-reduced-motion: reduce)');
// Nothing moves with reduced motion, nor in the one look the card takes as it comes back into sight (cardAppear).
const ucStill = () => ucCalm.matches || uc.still;

// How the card opens and folds back: each part's [delay, duration] in ms, and for each word its [delay, duration] along
// (x) and down (y). Opening, the card grows and its background shrinks into its row's bar; words going to the second
// row go down first, clearing the first, then along it; words staying in the first row go along it, the dot and "left"
// going before anything passes them; the other row's time, the tracks, its bar and the pace note come in last. When the
// card's own window is the second row (the week nearer its limit, or the only one with a reading), its words go down
// and along quicker and its background waits a moment, so they're past the bar's place before it lands. Folding starts
// at once: the card shrinks back under the panel as, on the same timing, its row's bar spreads back into its
// background, and the words go back up and along with them; the other row's words, its bar, the tracks and the pace
// note go first, and the other row's name and percent, the dot and "left" come back on the card last.
const UC_OPENING = {
  card: [0, 420], fill: [40, 520], fillLate: [160, 500],
  down: { x: [120, 400], y: [0, 260] }, down1: { x: [50, 320], y: [0, 200] },
  stay: { x: [40, 400], y: [40, 400] }, side: { x: [100, 420], y: [100, 420] },
  fade: [0, 90], appear: [400, 300], tracks: [380, 300], bar2: [480, 550], pace: [620, 300],
};
const UC_FOLDING = {
  card: [0, 420], fill: [0, 420], fillLate: [0, 420],
  down: { x: [0, 400], y: [0, 340] }, down1: { x: [0, 400], y: [0, 340] },
  stay: { x: [0, 400], y: [0, 400] }, side: { x: [0, 400], y: [0, 400] },
  fade: [320, 140], appear: [0, 90], tracks: [0, 160], bar2: [0, 200], pace: [0, 120],
};

// Your plan's usage as the app last found it (setUsage; app/Usage.m), Preview the Wait's stand-in while one plays,
// whether you've folded the card (kept across launches), and what's showing: the mode (hidden, signin, ok or wait),
// whether the strip is open on the card, whether something's moving (presses and changes wait), the wait being shown
// ({ resetsAt, since }), whether the card is slid out for the pointer, where the pointer is, what it's on, and what the
// app was last told (whether there's a card, and how much of it shows); its clock, which runs only while its window
// can be seen (from cardAppear to cardGone), and whether the look it takes as it comes is under way (still); and while
// Sign in opens a terminal, its timer (signingIn).
const uc = {
  usage: null, preview: null, folded: store.get('usageFolded', false),
  mode: 'hidden', open: false, moving: false, travelling: false, waitShown: null,
  pointed: false, pointer: null, hovered: new Set(), extent: 0, told: '',
  clock: 0, still: false, pressedAt: 0, signingIn: 0,
};

// The words on the folded card: the shown window's name, percent and time left (at the session limit, when it's
// back), then the other window's name and percent. They're there twice, alike: light on the card, and dark in its
// colour, which is drawn over the light ones, so a word the colour ends in changes colour there.
const UC_BAND_WORDS = '<span class="uc-l1"></span><b class="uc-p1"></b><span class="uc-d"><span class="uc-dot">·</span> ' +
                      '<span class="uc-t1"></span> <span class="uc-after"></span></span><span class="uc-gap"></span>' +
                      '<span class="uc-l2"></span><b class="uc-p2"></b>';

// What Sign in's line says, signed out, until a terminal couldn't open it (signInFailed).
const UC_SIGN_IN_SAYS = 'See your session and weekly usage here';

const ucRoot = document.getElementById('uc');
let ucParts = null;

// The card's parts, built as the page starts: the slide that brings it out, its dark, the strip on it, the band's
// light words, the layer words travel in, and its colour, cut to the card's shape, with the band's dark words and their
// own travel layer; and
// the panel's shadow on it where it's out from under the panel.
function buildCard() {
  ucRoot.innerHTML = `
    <div class="uc-slide">
      <div class="uc-shell"></div>
      <div id="usage">
        <div class="u-strip">
          <span class="u-handle" title="Hide usage"></span>
          ${['session', 'week'].map((w) => `
          <div class="u-row u-${w}">
            <span class="u-label">${w === 'session' ? 'Session' : 'Week'}</span>
            <span class="bar firm u-track"><span class="u-fill"></span><span class="u-ends" hidden></span></span>
            <span class="u-pct"></span>
            <span class="u-x"></span>
            <span class="u-time"><span class="u-left"></span><span class="u-clock"></span></span>
            ${w === 'session' ? '<span class="u-message"></span><span class="u-right"></span>' : ''}
          </div>`).join('')}
          <div class="u-pace" hidden></div>
          <div class="u-gear" hidden>
            <div class="u-gear-top"><span class="u-gear-says"><span class="u-gear-line"><span
              class="u-gear-main"></span><span class="u-gear-over"></span></span><span
              class="u-gear-tip"></span></span>${gearSeatsHTML()}</div>
            <div class="u-gear-why" hidden></div>
          </div>
          <div class="u-heavy" hidden><span class="u-heavy-says"><span class="u-heavy-name"></span><span
            class="u-heavy-rest"></span></span></div>
          <div class="u-signin notice"><span class="notice-text">${UC_SIGN_IN_SAYS}</span>
            <button class="button main small u-sign-in">Sign in</button></div>
          <svg class="u-layer" width="340" height="${WAITS.vine.height}" viewBox="0 0 340 ${WAITS.vine.height}"
               aria-hidden="true"></svg>
        </div>
      </div>
      <div class="uc-band uc-light">${UC_BAND_WORDS}</div>
      <div class="uc-travel"></div>
      <div class="uc-face">
        <div class="uc-fill"><div class="uc-band uc-ink">${UC_BAND_WORDS}</div><div class="uc-travel"></div></div>
        <div class="uc-even"></div>
      </div>
    </div>
    <div class="uc-shade"></div>`;
  const q = (sel) => ucRoot.querySelector(sel);
  const row = (w) => ({ row: q(`.u-${w}`), track: q(`.u-${w} .u-track`), fill: q(`.u-${w} .u-fill`),
                        pct: q(`.u-${w} .u-pct`), time: q(`.u-${w} .u-time`), left: q(`.u-${w} .u-left`),
                        clock: q(`.u-${w} .u-clock`), label: q(`.u-${w} .u-label`), x: q(`.u-${w} .u-x`),
                        ends: q(`.u-${w} .u-ends`) });
  const band = (box) => Object.fromEntries(['l1', 'p1', 'd', 'dot', 't1', 'after', 'l2', 'p2'].map(
    (key) => [key, box.querySelector(`.uc-${key}`)]));
  ucParts = {
    slide: q('.uc-slide'), shell: q('.uc-shell'), shade: q('.uc-shade'), usage: q('#usage'), strip: q('.u-strip'),
    handle: q('.u-handle'),
    session: row('session'), week: row('week'), pace: q('.u-pace'), message: q('.u-message'), right: q('.u-right'),
    heavy: q('.u-heavy'), heavyName: q('.u-heavy-name'), heavyRest: q('.u-heavy-rest'),
    gear: q('.u-gear'), gearSays: q('.u-gear-says'), gearMain: q('.u-gear-main'), gearOver: q('.u-gear-over'),
    gearTip: q('.u-gear-tip'), gearWhy: q('.u-gear-why'),
    signIn: q('.u-sign-in'), signInSays: q('.u-signin .notice-text'), layer: q('.u-layer'), light: q('.uc-light'),
    travel: q('.uc-slide > .uc-travel'), face: q('.uc-face'), fill: q('.uc-fill'), even: q('.uc-even'),
    inkTravel: q('.uc-fill > .uc-travel'),
    bandLight: band(q('.uc-light')),
    bandInk: band(q('.uc-ink')),
  };
}

// What the card goes by: a preview (Working on Whozmove's Preview the Wait) while one plays, else the app's.
const ucData = () => uc.preview?.data ?? uc.usage;
// Folded, it's the line under the panel; not while a preview plays, which is there to be seen.
const ucFoldedNow = () => uc.folded && !uc.preview;
// Whether the strip shows on the card: signed out it always does, with Sign in; otherwise unless it's folded.
const ucOpenFor = (mode) => mode === 'signin' || (mode !== 'hidden' && !ucFoldedNow());

// ---- Each second, and whenever the app has something new ----

function ucTick(now) {
  const view = usageView(ucData(), now);
  if (view.state === 'wait') ucNoteWait(view, now);
  if (uc.moving) return;
  if (view.state !== uc.mode) {
    const resetCame = uc.mode === 'wait' && uc.waitShown && now >= uc.waitShown.resetsAt - 1000;
    if (resetCame && view.state === 'ok' && uc.open && !ucStill()) return ucPlayReset(view, now);
    return ucChangeMode(view.state, view, now);
  }
  ucDraw(view, now);
  const open = ucOpenFor(uc.mode);
  if (open !== uc.open) ucSetOpen(open, true);
}

// When the card first saw this limit: the wait runs from then to the reset (the vine grows over it), kept across
// launches so it doesn't start over.
function ucNoteWait(view, now) {
  const kept = uc.preview ? uc.preview.wait : store.get('usageWait', null);
  if (kept?.resetsAt === view.session.resetsAt) return;
  const wait = { resetsAt: view.session.resetsAt, since: now };
  if (uc.preview) uc.preview.wait = wait;
  else store.set('usageWait', wait);
}

function ucCurrentWait() {
  return uc.preview ? uc.preview.wait : store.get('usageWait', null);
}

// ---- Drawing, in place ----

function ucSetText(el, text) {
  if (el.textContent !== text) el.textContent = text;
}

function ucDraw(view, now) {
  if (uc.mode === 'ok' || uc.mode === 'wait') ucDrawBand(view, now);
  if (uc.mode !== 'hidden') ucDrawStrip(view, now);
}

// The folded card: its colour as far along as the window it shows is used (all of it, rounding both corners, at 100%),
// the words on it, and the mark at its bottom edge where even use would be by now.
function ucDrawBand(view, now) {
  const p = ucParts, edge = edgeView(view, now);
  const shown = edge.window === 'week' ? view.week : view.session;
  const { back, time } = edge;
  for (const b of [p.bandLight, p.bandInk]) {
    ucSetText(b.l1, edge.label);
    ucSetText(b.p1, edge.usedText);
    ucSetText(b.t1, time);
    ucSetText(b.after, edge.after);
    b.d.hidden = !time;
    ucSetText(b.l2, edge.other.label);
    ucSetText(b.p2, edge.other.usedText);
  }
  ucRoot.style.setProperty('--uc-u', `${edge.used / 100}`);
  ucRoot.style.setProperty('--uc-even', `${shown.even ?? 0}`);
  ucRoot.classList.toggle('has-even', shown.even != null && !back);
  ucRoot.style.setProperty('--uc-colour', edge.colour);
  ucRoot.classList.toggle('is-full', edge.used >= 100);
}

// The strip on the card: its text and widths for what's showing; nothing's touched that hasn't changed.
function ucDrawStrip(view, now) {
  const p = ucParts;
  if (uc.mode === 'wait') {
    const wait = ucCurrentWait() || { since: now, resetsAt: view.session.resetsAt };
    ucSetText(p.message, backLine(view.session.left, now, view.session.resetsAt));
    ucSetText(p.right, `Week ${percentText(view.week)}`);
    if (uc.waitShown?.resetsAt !== wait.resetsAt) {
      waitStyle().build(p.layer);
      uc.waitShown = wait;
    }
    waitStyle().draw(waitProgress(wait.since, wait.resetsAt, now), ucCalm.matches, ucStill());
  }
  if (uc.mode === 'ok' || uc.mode === 'wait') {
    ucDrawWindow(p.session, view.session, now);
    ucDrawWindow(p.week, view.week, now);
    const under = underRows(view, gearNow.facts, now);
    ucSwapText(p.pace, under?.text || '', () => p.pace.classList.toggle('is-fast', under?.kind === 'fast'));
    ucDrawGear();
  }
}

// Your gear under the line under the rows: its seats (gear.js draws them), each session working lighting one, with
// what they don't show on the line over them ("No gear yet", "2 over the gear" in the line's grey: seatsLine), and why
// none is recommended yet under them. Nothing until the app has said, nor while the gear is off in Settings.
function ucDrawGear() {
  const p = ucParts, facts = gearNow.facts, shown = !!facts && uc.mode === 'ok';
  const line = shown ? seatsLine(facts) : null, why = shown ? gearNotYet(facts) || '' : '';
  if (p.gear.hidden === !shown && (!shown || (p.gearMain.textContent === line.says
      && p.gearOver.textContent === line.over && p.gearWhy.textContent === why))) return;
  const before = p.strip.offsetHeight;
  if (shown) {
    ucSetText(p.gearMain, line.says);
    ucSetText(p.gearOver, line.over);
    ucSetText(p.gearWhy, why);
    p.gearWhy.hidden = !why;
  }
  p.gear.hidden = !shown;
  p.usage.classList.toggle('has-gear', shown);
  if (uc.open) ucEaseStrip(before);
}

// A line under the rows taking new words, `then` styling it as they show. Just after your press on a seat, the old
// words clear (120 ms) once the gear's number has turned, then the new ones come in, lifting 3px into place, so nothing
// passes through text; otherwise they change in place. Either way the strip's height eases to the new one.
function ucSwapText(el, text, then) {
  el.swapThen = then;
  if (el.swapFade) {
    // A swap on its way shows the latest words; back to the words it has (a second press undid the first), it stops.
    if (text !== el.textContent) {
      el.swappingTo = text;
      return;
    }
    el.swapFade.cancel();
    el.swapFade = el.swappingTo = null;
  }
  if (text === el.textContent) return then();
  const show = (words) => {
    const before = ucParts.strip.offsetHeight;
    el.textContent = words;
    el.hidden = !words;
    el.swapThen();
    if (uc.open) ucEaseStrip(before);
  };
  if (!uc.open || ucStill() || el.hidden || Date.now() - uc.pressedAt > 1000) return show(text);
  el.swappingTo = text;
  // Only its own fade is cancelled, never the card's opening or folding, which moves the same line.
  const fade = el.swapFade = el.animate([{ opacity: 1 }, { opacity: 0 }],
                                        { delay: 100, duration: 120, easing: 'ease', fill: 'forwards' });
  fade.finished.then(() => {
    if (el.swapFade !== fade) return;
    const words = el.swappingTo;
    el.swapFade = el.swappingTo = null;
    show(words);
    fade.cancel();
    el.animate([{ opacity: 0, transform: 'translateY(3px)' }, { opacity: 1, transform: 'none' }],
               { duration: 200, easing: UC_EASE });
  }, () => {});
}

function ucDrawWindow(parts, win, now) {
  parts.fill.style.width = `${win.used}%`;
  parts.fill.style.background = win.colour;
  ucSetText(parts.pct, percentText(win));
  parts.pct.style.color = win.severity === 'normal' ? '' : win.colour;
  ucSetEnds(parts.x, win.even == null ? '' : endsText(win, now));
  parts.x.dataset.kind = parts.ends.dataset.kind = paceKind(win.pace) || '';
  parts.ends.hidden = !(win.ends > win.used);
  if (!parts.ends.hidden) Object.assign(parts.ends.style, { left: `${win.used}%`, width: `${win.ends - win.used}%` });
  ucSetTimes(parts.time, parts.left, parts.clock, resetsText(win), clockAt(win.resetsAt, now));
  // With no reading there's no clock time to swap in, so pointing at the row leaves "no reading" as it is (usage.css).
  parts.row.classList.toggle('no-reading', !win.known);
}

// Time left, and the clock time it gives way to when pointed at: the column as wide as its own row's time left, never
// the other row's, as each row's words take only their own room and its bar the rest; pointed at, as wide as its clock
// time if that's wider, so the bar beside it gives way as the clock time is pushed in (usage.css).
function ucSetTimes(column, left, clock, leftText, clockText) {
  if (left.textContent === leftText && clock.textContent === clockText) return;
  left.textContent = leftText;
  clock.textContent = clockText;
  const leftWidth = ucTextWidth(left), clockWidth = ucTextWidth(clock);
  column.style.setProperty('--left-w', `${leftWidth}px`);
  column.style.setProperty('--clock-w', `${Math.max(leftWidth, clockWidth)}px`);
}

// Where a row ends up ("→ 30%", "out 1:41 PM"), in a column as wide as its own words, never the other row's: it eases
// to its new width as the words change, as the time beside it does, so the bar's end and the percent move there
// rather than jump (usage.css).
function ucSetEnds(x, text) {
  if (x.textContent === text) return;
  x.textContent = text;
  x.style.setProperty('--x-w', `${ucTextWidth(x)}px`);
}

// How wide an element's text is drawn, in whole points with one to spare: measured as laid out, in its own font with
// its tabular figures, which a canvas measure leaves out (a column that much too narrow cuts its first letter). While
// the row isn't laid out (signed out), the canvas measure with a little more to spare.
function ucTextWidth(el) {
  if (!el.textContent) return 0;
  const range = document.createRange();
  range.selectNodeContents(el);
  const drawn = range.getBoundingClientRect().width;
  return drawn > 0 ? Math.ceil(drawn) + 1 : Math.ceil(textWidth(el, el.textContent)) + 3;
}

// The strip's height easing from `before` to what it is now, the card following it (its observer).
function ucEaseStrip(before) {
  const p = ucParts, after = p.strip.offsetHeight;
  if (Math.abs(after - before) < 1 || ucStill()) return;
  p.strip.animate([{ height: `${before}px`, overflow: 'hidden' }, { height: `${after}px`, overflow: 'hidden' }],
                  { duration: 300, easing: UC_EASE });
}

// ---- What the card shows ----

// From one mode to another, other than the reset. Open, the new content comes in the panel's way (fading in, lifting
// 3px, sharpening) as the strip's height eases from the old to the new, the card following; signed out, the card opens
// for Sign in; with nothing to show, it goes (the app fades its window).
function ucChangeMode(mode, view, now) {
  const p = ucParts, was = uc.mode, before = uc.open ? p.strip.offsetHeight : 0;
  ucSetMode(mode);
  ucDraw(view, now);
  ucTell();
  if (mode === 'hidden') {
    uc.pointed = false;
    return ucOpenAtOnce(false);
  }
  const open = ucOpenFor(mode);
  if (was === 'hidden') return ucOpenAtOnce(open);
  if (open !== uc.open) return ucSetOpen(open, true);
  if (!uc.open || ucStill()) return;
  ucEaseStrip(before);
  p.strip.animate([{ opacity: 0, filter: 'blur(1.5px)', transform: 'translateY(3px)' },
                   { opacity: 1, filter: 'blur(0)', transform: 'none' }], { duration: 600, easing: UC_EASE });
}

// Shows a mode's parts. Anything but the wait takes the wait style's drawing away, unless it's kept (the reset).
function ucSetMode(mode, keepDrawing = false) {
  const p = ucParts;
  if (mode === 'signin' && uc.mode !== 'signin') ucSignInSays(UC_SIGN_IN_SAYS, false);  // signed out again: afresh
  uc.mode = mode;
  for (const m of ['signin', 'ok', 'wait']) p.usage.classList.toggle(`is-${m}`, mode === m);
  if (mode !== 'wait' && !keepDrawing) {
    if (uc.waitShown) waitStyle().clear();
    uc.waitShown = null;
    p.layer.replaceChildren();
  }
}

// How much of the card shows under the panel's edge, and how far in from the panel's sides, for the app: where its
// clicks go. Told only when it changes.
function ucSetExtent(px) {
  uc.extent = Math.ceil(px);
  ucTell();
}

function ucTell() {
  const shown = uc.mode !== 'hidden', extent = shown ? uc.extent : 0;
  const inset = uc.open || uc.moving ? 0 : ucFoldedInset();
  const said = `${shown}:${extent}:${inset}`;
  if (said === uc.told) return;
  uc.told = said;
  native({ type: 'usageCard', shown, extent, inset });
}

// How far in from the panel's sides the folded card is now: less while it's slid out.
const ucFoldedInset = () => uc.pointed ? UC_OUT_INSET : UC_INSET;

// The open card is as tall as the strip on it, and follows it as it changes (a pace note, the wait, the reset), unless
// it's opening or folding, which moves it itself.
function ucFollowStrip() {
  if (!uc.open || uc.travelling) return;
  const tall = ucParts.strip.offsetHeight;
  ucRoot.style.setProperty('--uc-tall', `${tall}px`);
  ucSetExtent(tall);
}

// Classes changed as the card's own moves end, without anything easing to them from where it was before those moves
// (usage.css): the moves have just put everything there.
function ucSettle(change) {
  ucRoot.classList.add('is-settling');
  change();
  void ucRoot.offsetWidth;
  ucRoot.classList.remove('is-settling');
}

// ---- Opening and folding ----

function ucSetOpen(open, animate) {
  if (open === uc.open) return;
  if (!animate || ucStill() || uc.mode === 'hidden') return ucOpenAtOnce(open);
  if (uc.mode === 'ok') return ucTravel(open);
  ucCrossFade(open);
}

function ucOpenAtOnce(open) {
  uc.open = open;
  ucSettle(() => {
    ucRoot.classList.toggle('is-open', open);
    ucRoot.classList.toggle('is-out', open || uc.pointed);
    if (open) ucFollowStrip();
    else ucSetExtent(uc.pointed ? UC_LINE + UC_SLIDE : UC_LINE);
  });
  ucPointAt(uc.pointer);
}

// A rectangle in a box's coordinates, as clip-path's inset() gives it, rounded as `radii` (top-left, top-right,
// bottom-right, bottom-left).
function ucInset(r, radii) {
  return `inset(${r.y}px ${UC_WIDTH - r.x - r.w}px ${UC_BOX - r.y - r.h}px ${r.x}px round ${
    radii.map((v) => `${v}px`).join(' ')})`;
}

// The folded card's colour, in its box: from the card's left (`inset` in from the panel's) as far as `used` goes, down
// to the line at rest, round at the card's corner (and at the far one too, at 100%), as usage.css draws it.
function ucBandClip(used, inset, w = Math.round((UC_WIDTH - 2 * inset) * used / 100)) {
  return ucInset({ x: inset, y: 0, w, h: UC_ABOVE + UC_LINE }, [0, 0, used >= 100 ? UC_CORNER : 0, UC_CORNER]);
}

// The card from slid out to open, as wide as the panel and reaching down as far as the strip on it (`tall`), its top
// still behind the panel (or back), as usage.css has it at either end; what cuts its colour to its shape, and the
// panel's shadow on it, widen with it.
function ucWiden(open, tall, run, timing) {
  const out = { left: `${UC_OUT_INSET}px`, right: `${UC_OUT_INSET}px`, height: '200px' };
  const wide = { left: '0px', right: '0px', height: `${tall + 173}px` };
  run(ucParts.shell, open ? [out, wide] : [wide, out], timing);
  const shape = (inset, height) => ({ height, clipPath: `inset(0px ${inset}px 0px ${inset}px round ${UC_CORNER}px)` });
  const [faceOut, faceWide] = [shape(UC_OUT_INSET, out.height), shape(0, wide.height)];
  run(ucParts.face, open ? [faceOut, faceWide] : [faceWide, faceOut], timing);
  const sides = (inset) => ({ clipPath: `inset(0px ${inset}px 0px ${inset}px)` });
  run(ucParts.shade, open ? [sides(UC_OUT_INSET), sides(0)] : [sides(0), sides(UC_OUT_INSET)], timing);
}

// The card opens (or folds) as one: it grows (or shrinks), its colour shrinks into its row's bar (or spreads back from
// it), and the words on it travel between their places on the band and in the rows; the rest of the strip comes in
// (or goes) around them. Each word travels as two copies, light under the colour and dark in it, so it changes colour
// as it leaves the colour or comes onto it.
function ucTravel(open) {
  const p = ucParts, now = Date.now(), view = usageView(ucData(), now), edge = edgeView(view, now);
  const T = open ? UC_OPENING : UC_FOLDING;
  const first = edge.window === 'week' ? p.week : p.session, second = first === p.week ? p.session : p.week;
  const low = first === p.week;  // the card's own window is the strip's second row
  uc.moving = uc.travelling = true;
  // The strip as it is open, its bars and time columns at their ends (they'd ease there otherwise), measured; and the
  // band as it is. Opening, no row is pointed at, so each time left is in its place rather than giving way to its clock
  // time; folding, it's measured as it's seen, a row pointed at keeping its clock time, so nothing on it jumps before
  // its words leave. Nothing's painted before the animations below start.
  const settled = [p.session.fill, p.week.fill, p.session.time, p.week.time, p.session.left, p.week.left,
                   p.session.clock, p.week.clock, p.session.x, p.week.x];
  for (const el of settled) el.style.transition = 'none';
  if (open) {
    for (const target of uc.hovered) target.classList.remove('is-hover');
    uc.hovered = new Set();
  }
  ucDrawStrip(view, now);
  const tall = p.strip.offsetHeight, grow = tall - (UC_LINE + UC_SLIDE);
  const layerBox = p.travel.getBoundingClientRect(), fillBox = p.fill.getBoundingClientRect();
  const where = (el, box) => {
    const r = el.getBoundingClientRect();
    return { x: r.left - box.left, y: r.top - box.top, w: r.width, h: r.height };
  };
  // Folding, the other window's words fade from the strip at once and come back on the card at the end, as the dot
  // and "left" do, so nothing crosses the words going back to the card's own lane as it shrinks.
  const other = (key, target) => open ? [key, target, low ? 'side' : 'down', key === 'p2'] : [key, null, 'fade'];
  // Folding from its row pointed at, the clock time shows in the time left's place: the time left leaves from there
  // unseen, coming in on its way back to the card as the clock time fades.
  const clocked = !open && first.row.classList.contains('is-hover');
  const words = [['l1', first.label, low ? 'down' : 'stay'], ['p1', first.pct, low ? 'down1' : 'side', true],
                 ['t1', clocked ? first.time : first.left, low ? 'down1' : 'side', clocked, clocked],
                 other('l2', second.label), other('p2', second.pct), ['dot', null, 'fade'], ['after', null, 'fade']];
  const moves = [];
  for (const [key, target, role, alignRight, unseen] of words) {
    const band = p.bandLight[key], text = band.textContent;
    if (!text || band.closest('[hidden]')) continue;
    const a = where(band, layerBox), ca = getComputedStyle(band);
    const at = { x: a.x, y: a.y, h: a.h, size: ca.fontSize, weight: ca.fontWeight, colour: ca.color, opacity: 1 };
    let to = { ...at, opacity: 0 };
    if (target) {
      const b = where(target, layerBox), cb = getComputedStyle(target);
      to = { x: alignRight ? b.x + b.w - textWidth(target, text) : b.x, y: b.y, h: b.h, size: cb.fontSize,
             weight: cb.fontWeight, colour: cb.color, opacity: unseen ? 0 : 1 };
    }
    moves.push({ text, role, from: open ? at : to, to: open ? to : at,
                 ink: getComputedStyle(p.bandInk[key]).color });
  }
  const bandClip = ucBandClip(edge.used, UC_OUT_INSET);
  const barClip = ucInset(where(first.fill, fillBox), [2, 2, 2, 2]);
  const trackColour = getComputedStyle(first.track).backgroundColor;
  for (const el of settled) el.style.transition = '';

  // What's in both waits out of sight in the strip until the copies land on it; then it's the strip's own.
  // The clock time pointing at its row shows goes too, as its time left is what travels: at once, or, showing as the
  // card folds, fading (below).
  const waiting = [first.label, first.pct, first.left, ...(clocked ? [] : [first.clock]), first.fill,
                   ...(open ? [second.label, second.pct] : [])];
  for (const el of waiting) el.style.visibility = 'hidden';
  ucRoot.classList.add('is-moving', 'is-travel', 'is-out');
  if (open) ucRoot.classList.add('is-open');
  ucSetExtent(Math.max(tall, UC_LINE + UC_SLIDE));

  const runs = [];
  const run = (el, frames, [delay, duration]) => {
    runs.push(el.animate(frames, { delay, duration, easing: UC_EASE, fill: 'both' }));
  };
  const swap = (a, b) => open ? [a, b] : [b, a];
  ucWiden(open, tall, run, T.card);
  // The light words show only on the card, as it grows or shrinks.
  const onCard = (g) => `inset(0px 0px ${UC_BOX - (UC_ABOVE + UC_LINE + g)}px 0px)`;
  run(p.travel, swap({ clipPath: onCard(0) }, { clipPath: onCard(grow) }), T.card);
  run(p.fill, swap({ clipPath: bandClip }, { clipPath: barClip }), low ? T.fillLate : T.fill);
  const made = [];
  for (const m of moves) {
    const timing = m.role === 'fade' ? { x: T.fade, y: T.fade } : T[m.role];
    for (const [layer, ink] of [[p.travel, false], [p.inkTravel, true]]) {
      const el = document.createElement('span');
      el.className = 'uc-traveler';
      el.textContent = m.text;
      layer.appendChild(el);
      made.push(el);
      const colour = (look) => ink ? m.ink : look.colour;
      run(el, [{ left: `${m.from.x}px` }, { left: `${m.to.x}px` }], timing.x);
      run(el, [{ top: `${m.from.y}px`, lineHeight: `${m.from.h}px` }, { top: `${m.to.y}px`, lineHeight: `${m.to.h}px` }],
          timing.y);
      run(el, [{ fontSize: m.from.size, fontWeight: m.from.weight, color: colour(m.from), opacity: m.from.opacity },
               { fontSize: m.to.size, fontWeight: m.to.weight, color: colour(m.to), opacity: m.to.opacity }], timing.x);
    }
  }
  // The rest of the strip: the other row's time, where both end up, the tracks and their dots, the other row's bar
  // drawing from its start, the pace line. The folded card's mark goes as the dot and "left" do, and comes back with
  // them.
  const lift = (el, timing) => run(el, swap({ opacity: 0, transform: 'translateY(3px)' },
                                            { opacity: 1, transform: 'none' }), timing);
  lift(second.time, T.appear);
  if (clocked) run(first.clock, [{ opacity: 1 }, { opacity: 0 }], T.appear);
  for (const row of [first, second]) {
    lift(row.x, T.appear);
    if (!row.ends.hidden) run(row.ends, swap({ opacity: 0 }, { opacity: 1 }), T.tracks);
  }
  run(p.even, swap({ opacity: 1 }, { opacity: 0 }), T.fade);
  if (!open) for (const el of [second.label, second.pct]) lift(el, T.appear);
  for (const track of [first.track, second.track])
    run(track, swap({ backgroundColor: 'rgba(255, 255, 255, 0)' }, { backgroundColor: trackColour }), T.tracks);
  second.fill.style.transformOrigin = 'left center';
  run(second.fill, swap({ transform: 'scaleX(0)' }, { transform: 'scaleX(1)' }), T.bar2);
  if (!p.pace.hidden) lift(p.pace, T.pace);
  if (!p.gear.hidden) lift(p.gear, T.pace);
  if (!p.heavy.hidden) lift(p.heavy, T.pace);

  let done = false;
  const finish = () => {
    if (done) return;
    done = true;
    runs.forEach((a) => a.cancel());
    made.forEach((el) => el.remove());
    for (const el of waiting) el.style.visibility = '';
    second.fill.style.transformOrigin = '';
    uc.open = open;
    uc.moving = uc.travelling = false;
    // Folded, it's out as if pointed at, as the pointer that pressed it may still be on it; it goes back once the
    // pointer's been seen elsewhere.
    if (!open) uc.pointed = true;
    ucSettle(() => {
      ucRoot.classList.remove('is-moving', 'is-travel');
      ucRoot.classList.toggle('is-open', open);
      ucRoot.classList.add('is-out');
      if (open) ucFollowStrip();
      else ucSetExtent(UC_LINE + UC_SLIDE);
    });
    ucPointAt(uc.pointer);  // the pointer hasn't moved, but what's under it has
  };
  Promise.all(runs.map((a) => a.finished)).then(finish, finish);
}

// Opening or folding into the wait at the session limit, or for Sign in: the strip and the band cross-fade as the
// card grows or shrinks, as there's no bar for the colour to land on (the vine's there instead).
function ucCrossFade(open) {
  const p = ucParts, tall = p.strip.offsetHeight;
  uc.moving = uc.travelling = true;
  // The strip and the band both show while they cross-fade; the end says which stays.
  ucRoot.classList.remove('is-open');
  ucRoot.classList.add('is-moving', 'is-out');
  ucSetExtent(Math.max(tall, UC_LINE + UC_SLIDE));
  const runs = [];
  const run = (el, frames, delay, duration) => {
    runs.push(el.animate(frames, { delay, duration, easing: UC_EASE, fill: 'both' }));
  };
  const shown = [{ opacity: 0, filter: 'blur(1.5px)', transform: 'translateY(3px)' },
                 { opacity: 1, filter: 'blur(0)', transform: 'none' }];
  ucWiden(open, tall, (el, frames, [delay, duration]) => run(el, frames, delay, duration), [open ? 0 : 150, 420]);
  run(p.usage, open ? shown : [...shown].reverse(), open ? 200 : 0, open ? 300 : 150);
  for (const el of [p.light, p.fill])
    run(el, open ? [{ opacity: 1 }, { opacity: 0 }] : [{ opacity: 0 }, { opacity: 1 }], open ? 0 : 300, 200);
  let done = false;
  const finish = () => {
    if (done) return;
    done = true;
    runs.forEach((a) => a.cancel());
    uc.moving = uc.travelling = false;
    ucRoot.classList.remove('is-moving');
    ucOpenAtOnce(open);
  };
  Promise.all(runs.map((a) => a.finished)).then(finish, finish);
}

// The card coming back into sight (the reader closed, the panel opened out of the cat): folded, its line draws in from
// the panel's corner.
function ucDrawIn() {
  if (uc.open || uc.moving || ucStill() || !(uc.mode === 'ok' || uc.mode === 'wait')) return;
  const view = usageView(ucData(), Date.now()), used = edgeView(view, Date.now()).used;
  ucParts.fill.animate([{ clipPath: ucBandClip(used, UC_INSET, 0) }, { clipPath: ucBandClip(used, UC_INSET) }],
                       { duration: 500, easing: UC_EASE });
}

// ---- The pointer, and presses ----

// Where the pointer is in this page, as the app says (it polls it, as the card's window is never key), or null once
// it has gone: along the panel's bottom edge over the folded card, or on it, the card slides out (and back a moment
// after it has gone, usage.css); on the open card, what it's on is marked (a row shows its clock time, the strip its
// handle).
function ucPointAt(at) {
  const inside = at && at.x >= UC_LEFT + ucFoldedInset() && at.x < UC_LEFT + UC_WIDTH - ucFoldedInset();
  const reach = uc.pointed ? UC_LINE + UC_SLIDE : UC_LINE;
  const near = !!inside && at.y >= UC_TOP - UC_BAND && at.y < UC_TOP + reach;
  const peek = near && !uc.open && !uc.moving && (uc.mode === 'ok' || uc.mode === 'wait');
  if (peek !== uc.pointed && !uc.moving) {
    uc.pointed = peek;
    ucRoot.classList.toggle('is-out', peek || uc.open);
    if (!uc.open) ucSetExtent(peek ? UC_LINE + UC_SLIDE : UC_LINE);
  }
  const el = at && at.y >= UC_TOP && !uc.moving ? document.elementFromPoint(at.x, at.y) : null;
  const on = new Set();
  for (const sel of ['.u-strip', '.u-row', '.u-handle', '.u-sign-in', '.u-seat']) {
    const target = el?.closest(sel);
    if (target) on.add(target);
  }
  for (const target of uc.hovered) if (!on.has(target)) target.classList.remove('is-hover');
  for (const target of on) target.classList.add('is-hover');
  uc.hovered = on;
  // A seat pointed at says what a press there does, in the gear line's place, and shows the box it would make: the
  // card's window gets no mouse moves, so it's drawn from here.
  const facts = gearNow.facts, seat = facts && el?.closest('.u-seat'), to = seat ? Number(seat.dataset.to) : null;
  if (seat) ucSetText(ucParts.gearTip, gearTip(facts, to));
  ucParts.gearSays.classList.toggle('is-tip', !!seat);
  gearRing(ucRoot, to);
}

// Folded, a press on the card opens it; open, a press anywhere on it folds it, but Sign in, which opens a terminal
// signing Claude Code in, and your gear's line, whose seats set your gear (elsewhere on the line, a press does nothing,
// so one that just misses a seat doesn't fold the card away).
function ucPress(e) {
  if (e.button !== 0 || uc.moving) return;
  if (!uc.open) {
    if (uc.mode === 'ok' || uc.mode === 'wait') ucFold(false);
    return;
  }
  if (e.target.closest('.u-gear')) {
    e.preventDefault();
    const seat = e.target.closest('.u-seat');
    if (seat) gearPress(seat);
    return;
  }
  if (!e.target.closest('.u-sign-in')) {
    if (uc.mode === 'ok' || uc.mode === 'wait') ucFold(true);
  } else if (!uc.signingIn) {
    native({ type: 'usageSignIn' });
    ucSignInSays(UC_SIGN_IN_SAYS, true);
  }
}

// Sign in's line saying `says`, its button saying "Opening…" for 5 s while a terminal opens (a press then opens no
// second one), or Sign in, to press again; the card's height easing to the line's.
function ucSignInSays(says, opening) {
  const p = ucParts, before = p.strip.offsetHeight;
  clearTimeout(uc.signingIn);
  uc.signingIn = opening ? setTimeout(() => ucSignInSays(p.signInSays.textContent, false), 5000) : 0;
  ucSetText(p.signInSays, says);
  ucSetText(p.signIn, opening ? 'Opening…' : 'Sign in');
  if (uc.open) ucEaseStrip(before);
}

function ucFold(fold) {
  uc.folded = fold;
  store.set('usageFolded', fold);
  const open = ucOpenFor(uc.mode);
  if (open !== uc.open) ucSetOpen(open, true);
}

// ---- The reset ----

// The session limit has reset while you watched: the wait style plays its reset (the vine's: it blooms, its leaves fly
// off, its stem pulls taut into the session's bar, fills it and drains), then the strip is as it normally is, the card
// following its height.
function ucPlayReset(view, now) {
  const p = ucParts, style = waitStyle();
  // Where the session's bar is in the normal strip, and how tall that is: the strip laid out as it will be and
  // measured, with the wait style's drawing kept (the reset starts from it). The first frame below gives it back its
  // waiting height before anything is painted.
  for (const m of ['ok', 'wait']) p.usage.classList.toggle(`is-${m}`, m === 'ok');
  p.usage.classList.add('is-resetting');
  // The session's time column and where it ends up take their new widths at once, so the bar is measured where it
  // ends up, not partway through the columns' transitions.
  p.session.time.style.transition = p.session.x.style.transition = 'none';
  ucDrawWindow(p.session, view.session, now);
  ucDrawWindow(p.week, view.week, now);
  const layer = p.layer.getBoundingClientRect(), track = p.session.track.getBoundingClientRect();
  const bar = { x0: track.left - layer.left, x1: track.right - layer.left,
                y: track.top + track.height / 2 - layer.top };
  const heights = { wait: style.height, normal: p.strip.offsetHeight };
  ucSetText(p.message, 'Your move');
  p.message.style.color = 'var(--turn-words)';
  const stage = { strip: p.strip, message: p.message, right: p.right, track: p.session.track, fill: p.session.fill,
                  percent: p.session.pct, week: p.week.row, weekFill: p.week.fill, weekUsed: view.week.used,
                  bar, heights };
  uc.moving = true;
  p.session.fill.style.transition = p.week.fill.style.transition = 'none';
  const started = performance.now();
  (function frame() {
    const t = performance.now() - started;
    style.resetFrame(Math.min(t, style.resetMs), stage);
    if (t < style.resetMs) return requestAnimationFrame(frame);
    for (const el of [p.strip, p.message, p.right, p.session.track, p.session.fill, p.session.pct, p.week.row,
                      p.week.fill])
      el.removeAttribute('style');
    p.session.time.style.transition = p.session.x.style.transition = '';  // widths stay: they're set on style too
    p.usage.classList.remove('is-resetting');
    style.clear();
    p.layer.replaceChildren();
    uc.waitShown = null;
    uc.moving = false;
    uc.mode = 'ok';
    ucTick(Date.now());
  })();
}

// ---- Preview the Wait ----

// Working on Whozmove's Preview the Wait: a 20-second wait at the session limit, then its reset, then the card as it
// was. The vine grows smoothly meanwhile, not a step a second as in a real wait of hours.
function ucPlayPreview() {
  const now = Date.now(), real = usageView(uc.usage, now);
  uc.preview = {
    data: { state: 'ok', session: { used: 100, resetsAt: now + 20000 },
            week: { used: real.week?.used ?? 25, resetsAt: real.week?.resetsAt || now + 40 * 60 * 60000 },
            limits: [], extraUsage: false },
    wait: { resetsAt: now + 20000, since: now },
  };
  ucTick(now);
  (function grow() {
    const preview = uc.preview;
    if (!preview) return;
    if (uc.mode === 'wait' && !uc.moving)
      waitStyle().draw(waitProgress(preview.wait.since, preview.wait.resetsAt, Date.now()), ucCalm.matches);
    if (Date.now() >= preview.wait.resetsAt) {
      ucTick(Date.now());  // the reset
      setTimeout(ucEndPreview, WAITS.vine.resetMs + 1500);
      return;
    }
    requestAnimationFrame(grow);
  })();
}

function ucEndPreview() {
  if (uc.moving) return setTimeout(ucEndPreview, 200);
  uc.preview = null;
  ucTick(Date.now());
}

// ---- What the app calls ----

// Your plan's usage, as the app found it (app/Usage.m): what the card shows.
window.setUsage = (usage) => {
  uc.usage = usage;
  ucTick(Date.now());
};

// The session that has used the most today ({name, share, tokens}), or null with no one to name (app/UsageModule.m):
// the line at the foot of the open card, the card growing or shrinking to take it in.
window.setHeaviest = (heaviest) => {
  const p = ucParts, line = heaviestLine(heaviest);
  if (!p) return;
  const before = p.strip.offsetHeight;
  ucSetText(p.heavyName, line?.name ?? '');
  ucSetText(p.heavyRest, line?.rest ?? '');
  if (p.heavy.hidden === !line) return;
  p.heavy.hidden = !line;
  if (uc.open) ucEaseStrip(before);
};

// Your gear, as the app last said it (gear.js keeps it and draws the seats), or null with the gear turned off: the card
// draws the rest at once, and after your press the line under the rows follows the gear's number.
gearWatchers.push((facts, pressed) => {
  if (pressed) uc.pressedAt = Date.now();
  if (!ucParts || uc.moving || uc.mode !== 'ok') return;
  ucDrawStrip(usageView(ucData(), Date.now()), Date.now());
  ucPointAt(uc.pointer);  // the seat under a still pointer says what a press there does now
});

// Sign in didn't open a terminal, and why, as the terminal says it, with the command to run yourself (app/Usage.m): on
// Sign in's line, its button back to press again.
window.signInFailed = (why) => {
  if (ucParts) ucSignInSays(why, false);
};

// Working on Whozmove's Preview the Wait, in the pawn menu: the card's wait and reset, played now.
window.previewWait = () => ucPlayPreview();

// Where the pointer is in this page, or null once it has gone, with where it was at the app's look before (`from`,
// app/UsageCard.m). A quick hand can cross the panel's edge between two looks, never seen along it: while the card
// isn't slid out, the page is first pointed where the hand crossed (edgeCrossing), so the card slides out as for a slow
// hand seen there. Only where the pointer is now is kept, so a later look at a still pointer never crosses again.
window.cardPointer = (at) => {
  const crossed = at && !uc.pointed ? edgeCrossing(at.from, at, UC_TOP) : null;
  if (crossed) ucPointAt(crossed);
  uc.pointer = at && { x: at.x, y: at.y };
  ucPointAt(uc.pointer);
};

// The card's window has faded in (`drawIn`, its fill drawing in), or come back into sight with the panel: with its
// clock stopped meanwhile (or not started yet), it first looks once, at once, so what came while it was away (a reset)
// is there as it shows, rather than playing then.
window.cardAppear = (drawIn) => {
  if (!uc.clock) {
    uc.still = true;
    try {
      ucSettle(() => ucTick(Date.now()));  // nor do its styles ease into what changed (is-settling)
    } finally {
      uc.still = false;
      uc.clock = setInterval(() => ucTick(Date.now()), 1000);
    }
  }
  if (drawIn) ucDrawIn();
};

// The card's window has faded out, or gone from sight with the panel: its clock stops until it's back (cardAppear).
window.cardGone = () => {
  clearInterval(uc.clock);
  uc.clock = 0;
};

// It starts once it's in its window (the app's), not in the page's tests, which only load its plain functions.
if (window.webkit?.messageHandlers?.panel) {
  buildCard();
  ucTell();
  document.addEventListener('mousedown', (e) => ucPress(e));
  new ResizeObserver(() => ucFollowStrip()).observe(ucParts.strip);
}
