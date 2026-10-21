// The list's motion: each rebuild animates from what was there (morph), and groups slide open and shut.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// The list is rebuilt from scratch every second; morph makes the rebuild look continuous. It notes each row's
// place, height and lines, rebuilds, and animates the difference:
// - a new line (Claude's live line, its reply, a PR) grows in from nothing, fading and lifting into place;
// - a line that's gone stays a moment as a copy that folds away;
// - your message and Claude's line are written: new text writes in from the left, old text erases from the right
//   (rewriteLine), a new one writes in as it grows, and one that's gone erases before it folds;
// - other changed text cross-fades, and a row whose height changed otherwise resizes smoothly;
// - a row or section header that moved slides from where it was, and a new one eases in;
// - one that left view (its session ended, or it went into a folded group) fades out where it was, while the
//   rest close the gap.
const MORPH_MS = 1000, MORPH_EASE = 'cubic-bezier(.2, .8, .2, 1)';
// A line's box beyond its height (margin, padding, border), which has to fold with it, or a padded card stops at
// a sliver of padding until the animation ends.
const BOX_KEYS = ['marginTop', 'paddingTop', 'paddingBottom', 'borderTopWidth', 'borderBottomWidth'];
const FLAT = Object.fromEntries(BOX_KEYS.map((k) => [k, '0px']));
const HEADER_MS = 280;  // section headers ("Working", "Idle", a project) move quicker than the rows

// Of the rows that were there before, the most that keep their old order among themselves (the longest run with
// old positions rising): they slide in step, never passing one another, and the others glide over them
// (.row.glide). Of runs as long, the one that leaves the rows that moved up (the ones with news) to glide.
function keptInOrder(moves) {
  const n = moves.length, len = Array(n).fill(1), up = moves.map((m) => Math.max(0, m.dy)), prev = Array(n).fill(-1);
  for (let i = 0; i < n; i++)
    for (let j = 0; j < i; j++)
      if (moves[j].old.top < moves[i].old.top
          && (len[j] + 1 > len[i] || (len[j] + 1 === len[i] && up[j] + Math.max(0, moves[i].dy) < up[i]))) {
        len[i] = len[j] + 1;
        up[i] = up[j] + Math.max(0, moves[i].dy);
        prev[i] = j;
      }
  let end = -1;
  for (let i = 0; i < n; i++) if (end < 0 || len[i] > len[end] || (len[i] === len[end] && up[i] < up[end])) end = i;
  const kept = new Set();
  for (let i = end; i >= 0; i = prev[i]) kept.add(moves[i].row);
  return kept;
}
// A row's lines, top to bottom (rowHTML): the title, the chat, a card, the work line, a step's note and the bottom line.
// (Claude's line is `.claude.work` while it works, which isn't the work line.)
const ROW_LINES = ['.line1', '.you', '.claude', '.perm', '.work:not(.claude)', '.step-note', '.where'];
function rowParts() { return ROW_LINES; }
// The text that counts as a change for each line (the live line's timer ticks every second; that doesn't, and nor do
// the bits that cross-fade by themselves: the numbers on the work line, and the agent's setup and Deploy's button on
// the bottom line). The work line changes with its pull requests, with which steps it shows, and with the row's note
// said in its place; the bottom line with where the session runs. A card is another one when its data attributes are (which request, session or step it's
// for), or it shows another question, or it was answered. The modules say what counts in their lines (core.lines'
// `text`).
// (`:scope > .what`: a line's own text.)
const PART_TEXT = { '.you': (el) => el.querySelector(':scope > .what')?.textContent,
                    '.claude': (el) => el.dataset.mode + ' ' + el.querySelector(':scope > .what')?.textContent,
                    '.perm': (el) => Object.values(el.dataset).join('') + ' '
                                     + (el.querySelector('.q')?.dataset.q ?? '')
                                     + (el.querySelector('.perm-sent') ? ' sent' : ''),
                    '.work:not(.claude)': (el) => (el.querySelector(':scope > .work-note')?.textContent ?? '') + '|'
                                     + (el.querySelector('.prs, .nopr')?.textContent ?? '') + '|'
                                     + [...el.querySelectorAll('[data-step]')].map((s) => s.dataset.step).join(' '),
                    '.where': (el) => el.querySelector('.place')?.textContent ?? '',
                    '.step-note': (el) => el.textContent };
const partText = (sel) => PART_TEXT[sel] ?? core.lines[sel]?.text;
const calm = matchMedia('(prefers-reduced-motion: reduce)');

function rowKey(row) { return row.dataset.id + (row.closest('.pinned') ? ':pinned' : ''); }

// Where an element sits in the list's scrolled content, and how wide it is.
function place(list, el) {
  const box = list.getBoundingClientRect(), r = el.getBoundingClientRect();
  return { top: r.top - box.top + list.scrollTop, left: r.left - box.left, width: r.width, height: r.height };
}

function snapshot(list) {
  const rows = new Map(), heads = new Map();
  for (const head of list.querySelectorAll('.group[data-key], .project[data-key]'))
    heads.set(head.dataset.key, { ...place(list, head), el: head });
  rows.heads = heads;
  for (const row of list.querySelectorAll('.row[data-id]')) {
    const parts = {};
    for (const sel of rowParts()) {
      const el = row.querySelector(':scope > .main > ' + sel);
      // `shape`: where a line that a module animates by itself had its parts, to animate from.
      const line = core.lines[sel];
      if (el) parts[sel] = { el, text: partText(sel)?.(el), height: el.offsetHeight, shape: line?.shape?.(el) };
    }
    rows.set(rowKey(row), { ...place(list, row), height: row.offsetHeight, parts, el: row,
                            swaps: core.swaps.map((sel) => row.querySelector(sel)?.textContent),
                            // in a folded group
                            hidden: !!row.closest('.prows.closed') || (row.closest('.prows')?.offsetHeight ?? 2) < 2 });
  }
  return rows;
}

// Animates an element's inline styles from `from` to `to` over `ms`, then clears them.
function tween(el, from, to, done, ms = MORPH_MS, ease = MORPH_EASE) {
  el.style.transition = 'none';
  Object.assign(el.style, from);
  el.offsetHeight;  // apply the start before animating from it
  el.style.transition = Object.keys(to)
    .map((k) => `${k.replace(/[A-Z]/g, (c) => '-' + c.toLowerCase())} ${ms}ms ${ease}`).join(', ');
  Object.assign(el.style, to);
  setTimeout(() => {
    el.style.transition = '';
    for (const k of new Set([...Object.keys(from), ...Object.keys(to)])) el.style[k] = '';
    done?.();
  }, ms + 30);
}

// A line taking new text that rolls like a ticker (the header's build name, Spotify's song): the old text rolls out as
// the new rolls in, clipped to the line, and the line eases between their heights. It rolls up, or down with `down`.
// Only the text rolls; a label in the line (`.who`) stays put and just changes. The rolling copies ride inside the line
// (its own text hidden underneath), so they move with it when the line above changes height too.
function rollLine(row, el, was, down) {
  const oldH = was.height, newH = el.offsetHeight;
  const leaving = was.el.cloneNode(true), arriving = el.cloneNode(true);
  for (const copy of [leaving, arriving]) {
    copy.querySelectorAll('.roll-copy').forEach((c) => c.remove());  // the old line may itself have been rolling
    copy.querySelectorAll('.swap').forEach((c) => c.classList.remove('swap'));  // nor replay a cross-fade it had
    copy.classList.add('roll-copy');
    Object.assign(copy.style, { position: 'absolute', left: '0', right: '0', top: '0', margin: '0',
                                visibility: 'visible', pointerEvents: 'none' });
    // A copy's label is there but hidden, so its text sits where the line's own does.
    copy.querySelectorAll(':scope > .who').forEach((label) => { label.style.visibility = 'hidden'; });
  }
  Object.assign(el.style, { position: 'relative', visibility: 'hidden', overflow: 'hidden' });
  const label = el.querySelector(':scope > .who');
  if (label) label.style.visibility = 'visible';  // the line's own label shows throughout, in place
  el.append(leaving, arriving);
  tween(el, { height: oldH + 'px' }, { height: newH + 'px' }, () => {
    leaving.remove();
    arriving.remove();
    Object.assign(el.style, { position: '', visibility: '', overflow: '' });
    if (label) label.style.visibility = '';
  });
  const way = down ? -1 : 1;  // which side the new text comes in from: below (1) or above (-1)
  tween(leaving, { transform: 'translateY(0)', opacity: '1' },
        { transform: `translateY(${-way * oldH}px)`, opacity: '0' });
  tween(arriving, { transform: `translateY(${way * newH}px)`, opacity: '0' },
        { transform: 'translateY(0)', opacity: '1' });
}

// ---- Your message and Claude's line, written in and erased ----
// A chat line's text changes as if written: the old text erases from its end back to its start, then the new text
// writes in from there, each by a soft edge (CHAT_EDGE points wide), so the two never meet. What they share at their
// start, by whole words, stays, and only the rest is rewritten (the next step's "Reading "). A reply on two lines
// writes its first line, then its second, and erases the other way round. Claude's time beside its working text rides
// just past what shows; it's written and erased with the line only when the line turns into or out of working. The
// label changes as the new text starts. Writing keeps a steady pace and lands softly, erasing is its mirror, a little
// quicker, and the whole of it, with both lines', fits in the time the rest of the rebuild's motion takes (MORPH_MS),
// so the next rebuild never cuts it short. A new line writes in as its room opens; one that's gone erases, then folds.
// When both lines change at once, yours goes first and Claude's follows (CHAT_STAGGER); going, Claude's goes first.
const CHAT_EDGE = 26, CHAT_GAP = 40, CHAT_LEAD = 100, CHAT_STAGGER = 240, CHAT_STAGGER_GONE = 140;
const MASK_KEYS = ['webkitMaskImage', 'maskImage', 'webkitMaskSize', 'maskSize', 'webkitMaskPosition', 'maskPosition',
                   'webkitMaskRepeat', 'maskRepeat'];

// The easing a CSS cubic-bezier() draws, as a function of how far through it is (0 to 1), for motion run frame by
// frame (the chat lines' edge) and for the list's height while some of it starts late (listFrames).
function cubicBezier(x1, y1, x2, y2) {
  const cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx;
  const cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by;
  const x = (t) => ((ax * t + bx) * t + cx) * t;
  return (p) => {
    if (!(p > 0)) return 0;
    if (p >= 1) return 1;
    let lo = 0, hi = 1;
    for (let i = 0; i < 24; i++) {
      const mid = (lo + hi) / 2;
      if (x(mid) < p) lo = mid; else hi = mid;
    }
    const t = (lo + hi) / 2;
    return ((ay * t + by) * t + cy) * t;
  };
}
const morphCurve = cubicBezier(0.2, 0.8, 0.2, 1);  // MORPH_EASE's
const writeCurve = cubicBezier(0, 0, 0.58, 1), eraseCurve = cubicBezier(0.42, 0, 1, 1);

// What two texts share at their start, by whole words, which stays as the rest is rewritten: the next step's verb.
// All of it when they're the same; none when they part within their first word.
function sharedStart(a, b) {
  let i = 0;
  while (i < a.length && i < b.length && a[i] === b[i]) i++;
  if ((i === a.length || a[i] === ' ') && (i === b.length || b[i] === ' ')) return i;
  return a.slice(0, i).lastIndexOf(' ') + 1;
}

// How long writing and erasing a stretch of text take, by its length along the way (points): a steady pace, erasing a
// little quicker.
const writeMs = (d) => Math.min(560, Math.max(200, 140 + d * 0.9));
const eraseMs = (d) => Math.min(340, Math.max(140, 100 + d * 0.6));

// When each part of a chat line's change runs, from the start of the rebuild's motion: after `delay`, its old text
// erases (`erase` ms; none for a new line), a moment's pause unless part of it stays (`keeps`), then the new text
// writes (`write` ms; none for a line that's gone). Erasing and writing are made quicker, if they must be, to end
// within MORPH_MS.
function chatTimes(delay, eraseLength, writeLength, keeps) {
  const erase = eraseLength > 0 ? eraseMs(eraseLength) : 0, write = writeLength > 0 ? writeMs(writeLength) : 0;
  const gap = erase && write && !keeps ? CHAT_GAP : 0, total = delay + erase + gap + write, room = MORPH_MS - 40;
  const k = total > room ? Math.max(0, room - delay) / (total - delay) : 1;
  return { delay, erase: erase * k, gap: gap * k, write: write * k };
}

// The list's own height, as keyframes for its easing from `from` to `to`: on the motion's curve from the start, but
// for the chat lines that give up their room only once their old text has gone (`late`: how much each gives, from
// when, for how long, on the same curve), so the panel's bottom edge stays with them.
function listFrames(from, to, late, count = 30) {
  const rest = to - from - late.reduce((sum, l) => sum + l.delta, 0), frames = [];
  for (let i = 0; i <= count; i++) {
    const t = (i / count) * MORPH_MS;
    let h = from + rest * morphCurve(t / MORPH_MS);
    for (const l of late) h += l.delta * morphCurve((t - l.start) / l.ms);
    frames.push({ height: `${h.toFixed(2)}px`, offset: i / count });
  }
  return frames;
}

// Where a chat line's text runs, as rows in reading order, in its `.what`'s own points: each row from the text's start
// to its end, cut at the box's edge (a row cut short ends at the edge, where its "…" is), a row's length and the edge's
// width along the way for each. With `keep`, how far along the way its first `keep` letters end; with `withTime`, the
// time beside Claude's working text as the last part of the way.
function textPath(line, keep, withTime) {
  const what = line.querySelector(':scope > .what'), box = what.getBoundingClientRect();
  const lh = parseFloat(getComputedStyle(what).lineHeight) || 15, range = document.createRange();
  const bandOf = (r) => Math.floor((r.top - box.top + r.height / 2) / lh);
  range.selectNodeContents(what);
  const ends = new Map();
  for (const r of range.getClientRects()) {
    const band = bandOf(r);
    if (r.width < 0.5 || band < 0 || (band + 1) * lh > box.height + 1) continue;  // past the lines it shows
    ends.set(band, Math.max(ends.get(band) ?? 0, Math.min(r.right, box.right) - box.left));
  }
  const rows = [...ends].sort((a, b) => a[0] - b[0]).map(([band, len]) => ({ band, top: band * lh, len }));
  if (rows.length && (what.scrollWidth > what.clientWidth + 1 || what.scrollHeight > what.clientHeight + 1))
    rows[rows.length - 1].len = box.width;
  let off = 0;
  for (const row of rows) { row.off = off; off += row.len + CHAT_EDGE; }
  let keepPos = 0;
  const text = what.querySelector('.shine')?.firstChild ?? what.firstChild;
  if (keep && text?.nodeType === Node.TEXT_NODE) {
    range.setStart(text, 0);
    range.setEnd(text, Math.min(keep, text.length));
    const last = [...range.getClientRects()].filter((r) => r.width >= 0.5).pop();
    const band = last && bandOf(last), row = last && rows.find((r) => r.band === band), end = rows[rows.length - 1];
    if (row) keepPos = row.off + Math.min(last.right, box.right) - box.left;
    else if (last && end && band > end.band) keepPos = end.off + end.len;  // past the lines it shows: all of them stay
  }
  const el = withTime && line.querySelector(':scope > .elapsed');
  const time = el ? { el, off, w: el.getBoundingClientRect().width } : null;
  return { what, rows, lh, width: box.width, keepPos, time, length: off + (time ? time.w + CHAT_EDGE : 0) };
}

function setMask(el, images, sizes, places) {
  const s = el.style;
  s.webkitMaskImage = s.maskImage = images.join(', ') || 'linear-gradient(transparent, transparent)';
  s.webkitMaskSize = s.maskSize = sizes.join(', ');
  s.webkitMaskPosition = s.maskPosition = places.join(', ');
  s.webkitMaskRepeat = s.maskRepeat = 'no-repeat';
}

// Shows a line's text (textPath) up to `pos` along the way, and all of it before `keep`, through a soft edge on each
// row; returns where what shows of its first row ends.
function showPath(path, pos, keep) {
  const images = [], sizes = [], places = [];
  let shown = 0;
  path.rows.forEach((row, i) => {
    const e = Math.min(Math.max(pos - row.off, 0), row.len + CHAT_EDGE);
    const a = Math.max(Math.min(Math.max(keep - row.off, 0), row.len), e - CHAT_EDGE), b = Math.max(a + 0.01, e);
    images.push(`linear-gradient(to right, #000 ${a.toFixed(1)}px, transparent ${b.toFixed(1)}px)`);
    sizes.push(`${path.width}px ${path.lh}px`);
    places.push(`0 ${row.top}px`);
    if (i === 0) shown = Math.min(b, row.len);
  });
  setMask(path.what, images, sizes, places);
  if (path.time) {
    const e = Math.min(Math.max(pos - path.time.off, 0), path.time.w + CHAT_EDGE);
    setMask(path.time.el, [`linear-gradient(to right, #000 ${Math.max(0, e - CHAT_EDGE).toFixed(1)}px, `
                           + `transparent ${Math.max(0.01, e).toFixed(1)}px)`], ['100% 100%'], ['0 0']);
  }
  return shown;
}

// A chat line as it is at rest: no mask, its time and label where they belong. With `whole`, the line's own styles go
// too (a copy of a line that was moving).
function settleLine(line, whole = false) {
  for (const part of line.querySelectorAll(':scope > .what, :scope > .elapsed'))
    for (const k of [...MASK_KEYS, 'transform']) part.style[k] = '';
  const label = line.querySelector(':scope > .who');
  if (label) label.style.visibility = '';
  if (whole) line.removeAttribute('style');
}

// A copy of a line, just put on the page, keeps its breathing label and its shimmer in step with the line it copies:
// a copy starts its animations over, with the delays worked out when that line was drawn (phase), a second or more
// ago.
function keepInStep(copy) {
  for (const el of [copy, ...copy.querySelectorAll('*')]) {
    const ms = parseFloat(getComputedStyle(el).animationDuration) * 1000;
    if (ms > 0) el.style.animationDelay = `-${Math.round(performance.now() % ms)}ms`;
  }
}

// Runs `draw(t)` each frame, `t` being the time since it started, until `ms` have gone, then `done`; or until `el` has
// left the page (a rebuild replaced it), with nothing more to do.
function everyFrame(el, ms, draw, done) {
  const start = performance.now();
  (function step(now) {
    if (!el.isConnected) return;
    const t = Math.min(ms, Math.max(0, now - start));
    draw(t);
    if (t < ms) requestAnimationFrame(step); else done?.();
  })(start);
}

// A chat line taking new text (your next message, Claude's next step, its reply): `was` is the line as it was
// ({el, height}), `delay` when it starts, `late` where to note a fold that starts late for the list's height. A copy of
// the old line lies over the new one and erases (its label hidden, or, when the label's look changes, the new one hidden
// until the new text starts); then the copy goes and the line's own text writes in. The copy is the row's, not the
// line's, so the new line's look (Claude's working line on one line) never reaches the old text, and it follows the
// line's place each frame. A line that grows has its room at once, with the rest of the rebuild; one that shrinks keeps
// its room until its old text has gone.
function rewriteLine(el, was, delay = 0, late = null) {
  const what = el.querySelector(':scope > .what'), label = el.querySelector(':scope > .who');
  const row = el.closest('.row');
  if (!what || !label || !row || !was.el.querySelector(':scope > .what')) return;
  const working = (line) => line.dataset.mode === 'work';
  const ride = working(was.el) && working(el), sameLabel = working(was.el) === working(el);
  const old = was.el.cloneNode(true);
  settleLine(old, true);
  old.classList.add('rewrite-old');
  old.inert = true;
  const place = () => Object.assign(old.style, { top: `${el.offsetTop}px`, left: `${el.offsetLeft}px`,
                                                 width: `${el.offsetWidth}px` });
  Object.assign(old.style, { position: 'absolute', margin: '0', pointerEvents: 'none' });
  place();
  row.append(old);
  keepInStep(old);
  const oldLabel = old.querySelector(':scope > .who');
  if (sameLabel) oldLabel.style.visibility = 'hidden';
  else label.style.visibility = 'hidden';
  const oldWhat = old.querySelector(':scope > .what');
  const keep = was.el.dataset.mode === el.dataset.mode ? sharedStart(oldWhat.textContent, what.textContent) : 0;
  const from = textPath(old, keep, !ride), to = textPath(el, keep, !ride);
  const time = ride && el.querySelector(':scope > .elapsed');
  if (ride) old.querySelector(':scope > .elapsed')?.style.setProperty('visibility', 'hidden');
  // Riding, the time keeps the gap it has at rest from the end of what shows (`shown`, in the text's points): it ends
  // where it belongs as the new text's first row ends.
  const timeAt = to.rows[0]?.len ?? 0;
  const tm = chatTimes(delay, from.length - from.keepPos, to.length - to.keepPos, keep > 0);
  const swapAt = tm.delay + tm.erase + tm.gap;
  const oldH = was.height, newH = el.offsetHeight;
  if (newH > oldH + 0.5) {
    el.style.overflow = 'hidden';
    tween(el, { height: oldH + 'px' }, { height: newH + 'px' }, () => { el.style.overflow = ''; });
  } else if (newH < oldH - 0.5) {
    const start = tm.delay + tm.erase, ms = MORPH_MS - start;
    el.style.height = oldH + 'px';
    late?.push({ delta: newH - oldH, start, ms });
    setTimeout(() => tween(el, { height: oldH + 'px' }, { height: newH + 'px' }, null, ms), start);
  }
  showPath(to, 0, 0);  // all of the new text hidden under the old, what they share too
  let swapped = false;
  everyFrame(el, swapAt + tm.write, (t) => {
    let shown;
    if (t < swapAt) {
      place();
      const p = tm.erase ? eraseCurve((t - tm.delay) / tm.erase) : 1;
      shown = showPath(from, from.length - (from.length - from.keepPos) * p, from.keepPos);
    } else {
      if (!swapped) {
        swapped = true;
        old.remove();
        label.style.visibility = '';
      }
      shown = showPath(to, to.keepPos + (to.length - to.keepPos) * writeCurve((t - swapAt) / tm.write), to.keepPos);
    }
    if (time) time.style.transform = `translateX(${(shown - timeAt).toFixed(1)}px)`;
  }, () => {
    old.remove();
    settleLine(el);
  });
}

// When each of a row's chat lines that changes in a rebuild starts ({'.you': ms, '.claude': ms}, only those that
// change): at once, but when both do, yours first and Claude's after it, or, both going, Claude's first.
function chatDelays(main, old) {
  const changes = {};
  for (const sel of ['.you', '.claude']) {
    const el = main.querySelector(':scope > ' + sel), was = old.parts[sel];
    if (el ? !was || partText(sel)(el) !== was.text : was) changes[sel] = el ? (was ? 'changed' : 'new') : 'gone';
  }
  const sels = Object.keys(changes), both = sels.length === 2;
  const going = both && changes['.you'] === 'gone' && changes['.claude'] === 'gone';
  return Object.fromEntries(sels.map((sel) => [sel, !both ? 0
    : going ? (sel === '.you' ? CHAT_STAGGER_GONE : 0) : (sel === '.claude' ? CHAT_STAGGER : 0)]));
}

// A chat line that's new (a turn starting): its text writes in after `delay`, as its room opens (morph).
function writeIn(el, delay) {
  if (!el.querySelector(':scope > .what')) return;
  const path = textPath(el, 0, true), tm = chatTimes(delay, 0, path.length, false);
  showPath(path, 0, 0);
  everyFrame(el, tm.delay + tm.write,
             (t) => showPath(path, path.length * writeCurve((t - tm.delay) / tm.write), 0), () => settleLine(el));
}

// A chat line that's gone (the session gone quiet), as its copy where it was (`ghost`, .folding): its text erases
// after `delay`, then it folds away, `late` noting the fold for the list's height.
function eraseOut(ghost, delay, late) {
  settleLine(ghost);
  keepInStep(ghost);
  const path = textPath(ghost, 0, true), tm = chatTimes(delay, path.length, 0, false);
  const h = ghost.offsetHeight, start = tm.delay + tm.erase, ms = MORPH_MS - start;
  late?.push({ delta: -(h + (parseFloat(getComputedStyle(ghost).marginTop) || 0)), start, ms });
  showPath(path, path.length, 0);
  everyFrame(ghost, start, (t) => showPath(path, path.length * (1 - eraseCurve((t - tm.delay) / tm.erase)), 0));
  setTimeout(() => tween(ghost, { height: h + 'px', opacity: '1' }, { height: '0px', ...FLAT, opacity: '0' },
                         () => ghost.remove(), ms), start);
}

// A copy of what was there, laid over the list where it was, fading out (.fading, so nothing takes it for the row).
function fadeAway(list, old, ms = MORPH_MS) {
  const ghost = old.el.cloneNode(true);
  ghost.classList.remove('is-hover', 'arrive', 'glide');
  ghost.classList.add('fading');
  Object.assign(ghost.style, { position: 'absolute', top: old.top - list.clientTop + 'px', left: old.left + 'px',
                               width: old.width + 'px', margin: '0', pointerEvents: 'none', zIndex: '1' });
  list.appendChild(ghost);
  tween(ghost, { opacity: '1', transform: 'translateY(0) scale(1)' },
        { opacity: '0', transform: 'translateY(-4px) scale(0.98)' }, () => ghost.remove(), ms);
}

// Which card on the list a box is in, by the card's data attributes (which request, session or step it's for), so the
// rebuild finds it again: to leave a box being read where it was scrolled to (a request, which has to be read to its
// end), and to keep the box being typed in with its caret. Null outside a card.
function cardOf(box) {
  const card = box.closest('.perm');
  return card ? Object.entries(card.dataset).map(([key, value]) => `${key}:${value}`).join(' ') : null;
}

// The list's own box easing from its old height to its new one (morph), kept so that a rebuild or a group's slide
// during it can stop it where it is.
let listResize = null;

// Runs `measure` with the list's own box at the height it's easing to, since a list partway through easing measures
// short (and a list scrolled to its end scrolls back as it grows), and puts the easing back where it was before
// anything is drawn: for what has to land where the list ends up (a new conversation's row, starts.js).
function atListEnd(measure) {
  const ease = listResize?.playState === 'running' ? listResize : null, at = ease?.currentTime ?? 0;
  if (ease) ease.currentTime = MORPH_MS;
  try { return measure(); } finally { if (ease) ease.currentTime = at; }
}

function morph(list, html) {
  const before = state.morphed && !calm.matches ? snapshot(list) : null;
  const wasHeight = before ? list.offsetHeight : 0;  // as it shows now, even partway through easing
  const scrolled = new Map([...list.querySelectorAll('.perm .perm-detail')].map((d) => [cardOf(d), d.scrollTop]));
  // Keep focus and caret in an answer box on the list being typed in (not one beside it, as the reader's).
  const typing = document.activeElement?.closest?.('.perm .q-type'), typedIn = typing && list.contains(typing);
  const caret = typedIn && { card: cardOf(typing), q: typing.dataset.q,
                             start: typing.type === 'number' ? null : typing.selectionStart,
                             end: typing.type === 'number' ? null : typing.selectionEnd };
  list.innerHTML = html;
  listResize?.cancel();
  for (const drawn of core.drawn) drawn(list);  // what the modules size from the new HTML
  for (const d of list.querySelectorAll('.perm .perm-detail')) d.scrollTop = scrolled.get(cardOf(d)) || 0;
  if (caret) {
    const box = [...list.querySelectorAll(`.perm .q-type${caret.q != null ? `[data-q="${caret.q}"]` : ''}`)]
      .find((b) => cardOf(b) === caret.card && !b.closest('.prows.closed'));
    if (box) { box.focus(); if (caret.start != null) box.setSelectionRange(caret.start, caret.end); }
  }
  state.morphed = true;
  if (!before) return;
  const height = list.offsetHeight;  // as rebuilt, before the lines below are given their starting sizes
  let changed = false;
  const rows = [], late = [];  // late: the chat lines' folds that wait for their text to erase (listFrames)
  for (const row of list.querySelectorAll('.row[data-id]')) {
    const old = before.get(rowKey(row));
    if (!old) {
      if (!row.classList.contains('landing')) row.classList.add('arrive');  // a started one's arrives as its copy lands
      changed = true;
      continue;
    }
    if (old.hidden || row.closest('.prows.closed')) continue;  // in a collapsed group: its own slide handles it
    const main = row.querySelector(':scope > .main');
    let grewOrShrank = false;
    const lines = rowParts(), chatAfter = chatDelays(main, old);
    lines.forEach((sel, i) => {
      const el = main.querySelector(':scope > ' + sel), was = old.parts[sel], line = core.lines[sel];
      const chat = sel in chatAfter;
      if (el && !was) {  // a new line: grow it in
        const h = el.offsetHeight, cs = getComputedStyle(el), box = {};
        for (const k of BOX_KEYS) box[k] = cs[k];
        if (chat) writeIn(el, chatAfter[sel] + CHAT_LEAD);  // its text writes in as its room opens
        el.style.overflow = 'hidden';
        tween(el, { height: '0px', ...FLAT, opacity: '0', transform: 'translateY(-4px)' },
                  { height: h + 'px', ...box, opacity: '1', transform: 'translateY(0)' },
                  () => { el.style.overflow = ''; });
        line?.grow?.(el);  // how a module's line comes in, beside growing
        grewOrShrank = changed = true;
      } else if (!el && was) {  // a line that's gone: a copy folds away where it was (.folding)
        const ghost = was.el.cloneNode(true);
        ghost.classList.add('folding');
        const next = lines.slice(i + 1).map((s) => main.querySelector(':scope > ' + s)).find(Boolean);
        main.insertBefore(ghost, next || null);
        ghost.style.overflow = 'hidden';
        ghost.style.pointerEvents = 'none';
        // A chat line's text erases first; one that was already going (a rebuild came as it erased) folds on from
        // where it is, so its text doesn't come back to erase again.
        if (chat && !was.el.classList.contains('folding')) eraseOut(ghost, chatAfter[sel], late);
        else tween(ghost, { height: was.height + 'px', opacity: '1' },
                          { height: '0px', ...FLAT, opacity: '0' }, () => ghost.remove());
        line?.fold?.(ghost);  // and how it goes
        grewOrShrank = changed = true;
      } else if (el && was && partText(sel) && partText(sel)(el) !== was.text) {  // new text in the same line
        // Your message and Claude's line are rewritten (rewriteLine); a module's line cross-fades.
        if (chat) {
          rewriteLine(el, was, chatAfter[sel], late);
          grewOrShrank = true;
        } else (line?.swap ? line.swap(el) : el)?.classList.add('swap');
        changed = true;
      } else if (el && was && line?.morph?.(el, was.shape)) {  // a line a module animates by itself
        changed = true;
      }
    });
    // The modules' bits that cross-fade when their text changes (core.swaps).
    core.swaps.forEach((sel, i) => {
      const bit = row.querySelector(sel);
      if (bit && bit.textContent !== old.swaps[i]) { bit.classList.add('swap'); changed = true; }
    });
    // A row whose height changed for another reason (a reply that now wraps to two lines) resizes.
    const height = row.offsetHeight, from = {}, to = {};
    if (!grewOrShrank && Math.abs(height - old.height) > 1) {
      from.height = old.height + 'px';
      to.height = height + 'px';
      row.style.height = from.height;  // its starting size, before the moves below are measured
    }
    rows.push({ row, old, from, to });
  }
  // A row or header that left view fades out where it was, over the list, while the rest close the gap.
  const shown = new Set([...list.querySelectorAll('.row[data-id]')].filter((r) => !r.closest('.prows.closed'))
    .map(rowKey));
  for (const [key, old] of before) if (!old.hidden && !shown.has(key)) { fadeAway(list, old); changed = true; }
  const heads = new Map([...list.querySelectorAll('.group[data-key], .project[data-key]')]
    .map((h) => [h.dataset.key, h]));
  for (const [key, old] of before.heads) if (!heads.has(key)) { fadeAway(list, old, HEADER_MS); changed = true; }
  for (const [key, head] of heads) {
    const old = before.heads.get(key);
    if (!old) { head.classList.add('arrive'); changed = true; continue; }
    rows.push({ row: head, old, from: {}, to: {}, ms: HEADER_MS });  // a header that moved slides, quickly
  }
  // Rows and headers that moved (to another group, or past one another) slide from where they were; a row
  // passing others glides over them (keptInOrder). Measured with every line and row at its starting size,
  // so only real moves count.
  const moves = rows.map((r) => ({ ...r, dy: r.old.top - place(list, r.row).top }));
  const kept = keptInOrder(moves.filter((m) => m.row.matches('.row')));
  for (const { row, from, to, ms, dy } of moves) {
    if (Math.abs(dy) > 2) { from.transform = `translateY(${dy}px)`; to.transform = 'translateY(0)'; }
    if (!Object.keys(to).length) continue;
    if (to.transform && row.matches('.row') && !kept.has(row)) row.classList.add('glide');
    if (to.height) row.style.overflow = 'hidden';
    // One tween per row, so a resize and a move don't cancel each other.
    tween(row, from, to, () => { row.style.overflow = ''; row.classList.remove('glide'); }, ms);
    changed = true;
  }
  // The list's own box eases between its heights with the rows, so what's below it (the now-playing strip) and the
  // panel's bottom edge move with them, rather than jumping to where they end up while the rows are still on their way.
  if (late.length) {
    listResize = list.animate(listFrames(wasHeight, height, late), { duration: MORPH_MS, easing: 'linear' });
    changed = true;
  } else if (Math.abs(height - wasHeight) > 1) {
    listResize = list.animate([{ height: `${wasHeight}px` }, { height: `${height}px` }],
                              { duration: MORPH_MS, easing: MORPH_EASE });
    changed = true;
  }
  if (changed) {  // the panel follows the list's height while it animates; rebuilds wait till it's done
    const started = performance.now();
    state.settleUntil = started + MORPH_MS + 40;
    (function follow() {
      reportHeight();
      if (performance.now() - started < MORPH_MS + 60) requestAnimationFrame(follow);
    })();
  }
}

// Keeps the panel's window the height of its page, frame by frame, for `ms`: for motion outside the list (a strip's
// under it), which changes the page's height as it goes.
function followHeight(ms) {
  const until = performance.now() + ms;
  (function follow() {
    reportHeight();
    if (performance.now() < until) requestAnimationFrame(follow);
  })();
}

// Opens or closes a group in place: the chevron turns and the body slides between zero and its full
// height, with the panel following frame by frame. The list isn't rebuilt meanwhile (render waits
// for `sliding`), or the slide would be cut short; the render after it settles the final state.
const SLIDE_MS = 200;
function slideGroup(header, collapse) {
  const body = header?.nextElementSibling;
  if (!body?.classList.contains('prows')) return render();
  listResize?.cancel();  // the list's height follows the slide instead
  header.classList.toggle('collapsed', collapse);
  if (!collapse && body.nextElementSibling?.classList.contains('pinned')) body.nextElementSibling.remove();
  const full = body.scrollHeight;
  body.classList.remove('closed');
  body.style.transition = 'none';
  body.style.height = (collapse ? full : 0) + 'px';
  body.style.opacity = collapse ? 1 : 0;
  body.offsetHeight;  // apply the starting size before animating from it
  body.style.transition = '';
  body.style.height = (collapse ? 0 : full) + 'px';
  body.style.opacity = collapse ? 0 : 1;
  state.sliding++;
  const started = performance.now();
  (function follow() {
    reportHeight();
    if (performance.now() - started < SLIDE_MS + 40) requestAnimationFrame(follow);
  })();
  setTimeout(() => { state.sliding--; render(); }, SLIDE_MS + 20);
}
