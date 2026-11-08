// The list's motion: each rebuild animates from what was there (morph), and groups slide open and shut.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// The list is rebuilt from scratch whenever what it shows changes; morph makes the rebuild look continuous. It notes
// each row's place, height and lines, rebuilds, and animates the difference (but the first time, or `still`: drawn as it
// is, as when the panel is seen again after it couldn't be):
// - a new line (Claude's live line, its reply, a PR) grows in from nothing, fading and lifting into place;
// - a line that's gone stays a moment as a copy that folds away;
// - your message and Claude's line are written: new text writes in from the left, old text erases from the right
//   (rewriteLine, and rewriteText for any other line), a new one writes in as it grows, and one that's gone erases
//   before it folds;
// - other changed text cross-fades, and a row whose height changed otherwise resizes smoothly;
// - a row or project header that moved slides from where it was, and a new one eases in;
// - one that left view (its session ended, or it went into a folded group) fades out where it was, while the
//   rest close the gap.
const MORPH_MS = 1000, MORPH_EASE = 'cubic-bezier(.2, .8, .2, 1)';
// A line's box beyond its height (margin, padding, border), which has to fold with it, or a padded card stops at
// a sliver of padding until the animation ends.
const BOX_KEYS = ['marginTop', 'paddingTop', 'paddingBottom', 'borderTopWidth', 'borderBottomWidth'];
const FLAT = Object.fromEntries(BOX_KEYS.map((k) => [k, '0px']));
const HEADER_MS = 280;  // project headers move quicker than the rows

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
// A row's lines, top to bottom (rowHTML): the title, the chat, a card, what it runs in the background, the work line, a
// step's note, the bottom line and the row's details (parts/details). (Claude's line is `.claude.work` while it works,
// which isn't the work line.)
const ROW_LINES = ['.line1', '.you', '.claude', '.perm', '.background-work', '.work:not(.claude)', '.step-note',
                   '.where', '.details'];
function rowParts() { return ROW_LINES; }
// The text that counts as a change for each line (the live line's timer ticks every second; that doesn't, and nor do
// the bits that cross-fade by themselves: the numbers on the work line, and the agent's setup and Deploy's button on
// the bottom line). The work line changes with its pull requests, with which steps it shows, and with the row's note
// said in its place; the bottom line with where the session runs. A card is another one when its data attributes are
// (which request, session or step it's for, and its state: data-stage). The modules say what counts in their lines
// (core.lines' `text`).
// (`:scope > .what`: a line's own text.)
const PART_TEXT = { '.you': (el) => el.querySelector(':scope > .what')?.textContent,
                    '.claude': (el) => el.dataset.mode + ' ' + wordsOf(el.querySelector(':scope > .what'))?.textContent,
                    '.perm': (el) => Object.values(el.dataset).join(''),
                    '.work:not(.claude)': (el) => (el.querySelector(':scope > .work-note')?.textContent ?? '') + '|'
                                     + (el.querySelector('.prs, .nopr')?.textContent ?? '') + '|'
                                     + [...el.querySelectorAll('[data-step]')].map((s) => s.dataset.step).join(' '),
                    '.background-work': (el) => el.textContent,
                    '.where': (el) => el.querySelector('.place')?.textContent ?? '',
                    '.step-note': (el) => el.textContent };
const partText = (sel) => PART_TEXT[sel] ?? core.lines[sel]?.text;

// What holds a line's words: the words themselves when a band of light crosses them (shineHTML), without the copy of
// them it shows, which is neither read nor measured; else the line's text.
const wordsOf = (what) => what?.querySelector('.shine') ?? what;
const calm = matchMedia('(prefers-reduced-motion: reduce)');

function rowKey(row) { return row.dataset.id + (row.closest('.pinned') ? ':pinned' : ''); }

// Where an element sits in the list's scrolled content, and how wide it is.
function place(list, el) {
  const box = list.getBoundingClientRect(), r = el.getBoundingClientRect();
  return { top: r.top - box.top + list.scrollTop, left: r.left - box.left, width: r.width, height: r.height };
}

// The rows out of the list's visible part (inside its edges; one under the header counts as in it) both where they were
// and where the rebuilt list puts them, measured before anything is given its starting size: their lines' text takes
// its new words as they are, as nobody would see them write in and writing them draws the page again every frame.
// Their room still grows and folds as ever, so what can be seen moves as it always does. The row you're on always
// writes in, as its copy may be held at the list's edge.
function outOfSight(list, before) {
  const top = list.scrollTop, bottom = top + list.clientHeight;
  const off = (r) => r.top + r.height <= top || r.top >= bottom;
  return new Set([...list.querySelectorAll('.row[data-id]')].filter((row) => {
    const old = before.get(rowKey(row));
    return old && !row.classList.contains('focused') && off(old) && off(place(list, row));
  }));
}

function snapshot(list) {
  const rows = new Map(), heads = new Map();
  for (const head of list.querySelectorAll('.project[data-key]'))
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
// Any other line of text, a module's own, takes new words the same way (rewriteText).
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

// Where a chat line's text runs (textOn, for its `.what`); with `withTime`, the time beside Claude's working text as the
// last part of the way.
function textPath(line, keep, withTime) {
  return textOn(line.querySelector(':scope > .what'), keep, withTime && line.querySelector(':scope > .elapsed'));
}

// Where an element's text runs, as rows in reading order, in its own points: each row from the text's start to its end,
// cut at the box's edge (a row cut short ends at the edge, where its "…" is), a row's length and the edge's width along
// the way for each. With `keep`, how far along the way its first `keep` letters end; with `time`, an element beside the
// text as the last part of the way.
function textOn(what, keep, time = null) {
  const box = what.getBoundingClientRect();
  const lh = parseFloat(getComputedStyle(what).lineHeight) || 15, range = document.createRange();
  const bandOf = (r) => Math.floor((r.top - box.top + r.height / 2) / lh);
  range.selectNodeContents(wordsOf(what));
  const ends = new Map();
  for (const r of range.getClientRects()) {
    const band = bandOf(r);
    if (r.width < 0.5 || band < 0 || (band + 1) * lh > box.height + 1) continue;  // past the lines it shows
    ends.set(band, Math.max(ends.get(band) ?? 0, Math.min(r.right, box.right) - box.left));
  }
  const rows = [...ends].sort((a, b) => a[0] - b[0]).map(([band, len]) => ({ band, top: band * lh, len }));
  // Cut short with a "…": the words wider than the box that shows them (its scroll width would count the band's
  // moving copy too), else the line's text wider or taller than its box.
  const shining = what.querySelector(':scope > .shining');
  const cut = shining ? wordsOf(what).getBoundingClientRect().width > shining.clientWidth + 1
    : what.scrollWidth > what.clientWidth + 1 || what.scrollHeight > what.clientHeight + 1;
  if (rows.length && cut)
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
  const beside = time ? { el: time, off, w: time.getBoundingClientRect().width } : null;
  return { what, rows, lh, width: box.width, keepPos, time: beside, length: off + (beside ? beside.w + CHAT_EDGE : 0) };
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
  for (const part of line.querySelectorAll(':scope > .what, :scope > .elapsed, :scope > .chat-end'))
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
    // The band's copy takes its window's start (controls.css), so the two never drift apart.
    if (el.parentElement?.classList.contains('glint')) continue;
    // A waiting dot's ring is its ::after, and a working dot's fill its ::before, which take the dot's delay (rows.css).
    const ms = Math.max(parseFloat(getComputedStyle(el).animationDuration) || 0,
                        parseFloat(getComputedStyle(el, '::before').animationDuration) || 0,
                        parseFloat(getComputedStyle(el, '::after').animationDuration) || 0) * 1000;
    if (ms > 0) el.style.animationDelay = `-${Math.round(performance.now() % ms)}ms`;
  }
}

// Runs `draw(t)` each frame, `t` being the time since it started, until `ms` have gone, then `done`; or until `el` has
// left the page (a rebuild replaced it), with nothing more to do but `gone`.
function everyFrame(el, ms, draw, done, gone) {
  const start = performance.now();
  (function step(now) {
    if (!el.isConnected) return gone?.();
    const t = Math.min(ms, Math.max(0, now - start));
    draw(t);
    if (t < ms) requestAnimationFrame(step); else done?.();
  })(start);
}

// A chat line taking new text (your next message, Claude's next step, its reply): `was` is the line as it was
// ({el, height}), `delay` when it starts, `late` where to note a fold that starts late for the list's height. A copy of
// the old line lies over the new one and erases (its label hidden, or, when the label changes, the new one hidden
// until the new text starts); then the copy goes and the line's own text writes in. The copy is the row's, not the
// line's, so the new line's look (Claude's working line on one line) never reaches the old text, and it follows the
// line's place each frame. A line that grows has its room at once, with the rest of the rebuild; one that shrinks keeps
// its room until its old text has gone. What a module put after Claude's words (.chat-end) is the line's own, never the
// copy's: it rides the end of the words that show, old then new, so it never crosses them, and lands where it belongs.
function rewriteLine(el, was, delay = 0, late = null) {
  const what = el.querySelector(':scope > .what'), label = el.querySelector(':scope > .who');
  const row = el.closest('.row');
  if (!what || !label || !row || !was.el.querySelector(':scope > .what')) return;
  const working = (line) => line.dataset.mode === 'work';
  // The label's look changes with Claude's working line, and its words with who sent your line's message.
  const sameLabel = working(was.el) === working(el)
    && was.el.querySelector(':scope > .who')?.textContent === label.textContent;
  const ride = working(was.el) && working(el);
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
  old.querySelector(':scope > .chat-end')?.style.setProperty('visibility', 'hidden');
  const oldLabel = old.querySelector(':scope > .who');
  if (sameLabel) oldLabel.style.visibility = 'hidden';
  else label.style.visibility = 'hidden';
  const oldWhat = old.querySelector(':scope > .what');
  const keep = was.el.dataset.mode === el.dataset.mode
    ? sharedStart(wordsOf(oldWhat).textContent, wordsOf(what).textContent) : 0;
  const from = textPath(old, keep, !ride), to = textPath(el, keep, !ride);
  const time = ride && el.querySelector(':scope > .elapsed'), end = el.querySelector(':scope > .chat-end');
  if (ride) old.querySelector(':scope > .elapsed')?.style.setProperty('visibility', 'hidden');
  // Riding, the time keeps the gap it has at rest from the end of what shows (`shown`, in the text's points): it ends
  // where it belongs as the new text's first row ends.
  const timeAt = to.rows[0]?.len ?? 0;
  const tm = chatTimes(delay, from.length - from.keepPos, to.length - to.keepPos, keep > 0);
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
  eraseThenWrite(el, old, from, to, tm, {
    frame(shown, erasing) {
      if (erasing) place();
      if (time) time.style.transform = `translateX(${(shown - timeAt).toFixed(1)}px)`;
      if (end) end.style.transform = `translateX(${(shown - timeAt).toFixed(1)}px)`;
    },
    swap() { label.style.visibility = ''; },
  }).then((written) => { if (written) settleLine(el); });
}

// Where a rewrite has got to `t` ms in (eraseThenWrite), for old text erasing down to what it shares with the new, then
// the new writing in from there (`from` and `to`, each { length, keepPos } along its way: textOn), on times `tm`
// (chatTimes): { erasing: true, pos } as the old erases, then { erasing: false, pos } as the new writes.
function rewriteAt(t, from, to, tm) {
  const swapAt = tm.delay + tm.erase + tm.gap;
  if (t < swapAt) {
    const p = tm.erase ? eraseCurve((t - tm.delay) / tm.erase) : 1;
    return { erasing: true, pos: from.length - (from.length - from.keepPos) * p };
  }
  return { erasing: false, pos: to.keepPos + (to.length - to.keepPos) * writeCurve((t - swapAt) / tm.write) };
}

// The old text erasing on `old`, a copy of it laid over `el`, then the copy going and `el`'s own text writing in, along
// their ways (`from`, `to`: textOn) on times `tm` (chatTimes): all of the new text is hidden under the old till then,
// what they share too. Each frame, `frame(shown, erasing)`, with where what shows of the first row ends; `swap()` as
// the copy goes and the new text starts. Resolves true once all of it is written, or false if `el` left the page first.
function eraseThenWrite(el, old, from, to, tm, { frame, swap } = {}) {
  showPath(to, 0, 0);
  let swapped = false;
  return new Promise((resolve) => everyFrame(el, tm.delay + tm.erase + tm.gap + tm.write, (t) => {
    const at = rewriteAt(t, from, to, tm);
    if (!at.erasing && !swapped) {
      swapped = true;
      old.remove();
      swap?.();
    }
    const shown = showPath(at.erasing ? from : to, at.pos, at.erasing ? from.keepPos : to.keepPos);
    frame?.(shown, at.erasing);
  }, () => {
    old.remove();
    resolve(true);
  }, () => {
    old.remove();
    resolve(false);
  }));
}

// Any line of text taking new words as a chat line does (rewriteLine), such as a step's word in a module's own view:
// `el` already says what it says now, `was` what it said. What they share at their start, by whole words, stays; the
// rest of the old erases from its end, on a copy laid over the line, then the new writes in from there, at the chat
// line's pace and on its curves. `writing` is told as the new words start (with nothing to erase, at once). Under
// reduced motion, or with the same words, they're simply there. Resolves once all of them are, or the line has gone.
function rewriteText(el, was, { writing } = {}) {
  const now = el.textContent;
  if (calm.matches || was === now || !el.isConnected) {
    writing?.();
    return Promise.resolve();
  }
  const old = el.cloneNode(false);
  old.textContent = was;
  old.classList.add('rewrite-old');
  old.inert = true;
  for (const k of MASK_KEYS) old.style[k] = '';
  Object.assign(old.style, { position: 'absolute', margin: '0', pointerEvents: 'none', top: `${el.offsetTop}px`,
                             left: `${el.offsetLeft}px`, width: `${el.offsetWidth}px` });
  el.after(old);
  const keep = sharedStart(was, now), from = textOn(old, keep), to = textOn(el, keep);
  const tm = chatTimes(0, from.length - from.keepPos, to.length - to.keepPos, keep > 0);
  return eraseThenWrite(el, old, from, to, tm, { swap: writing }).then(() => {
    for (const k of MASK_KEYS) el.style[k] = '';
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

// Each box morph draws in (the list, and a chat beside the folded cat, chats.js) easing from its old height to its new
// one, kept so that a rebuild or a group's slide during it can stop it where it is; and the boxes drawn once already,
// whose next rebuild animates. Each box's own, so a chat's rebuild never cuts the list's short.
const resizes = new WeakMap(), drawnBefore = new WeakSet();

// Runs `measure` with a box morph draws in at the height it's easing to, since a box partway through easing measures
// short (and a list scrolled to its end scrolls back as it grows), and puts the easing back where it was before
// anything is drawn: for what has to land where the list ends up (a new conversation's row, starts.js), or the room a
// chat beside the folded cat needs once its row has grown (chats.js). The easing is held at its end rather than run
// past it, where it would no longer set the box's height, and the box would measure as its lines are now, each only
// starting to grow or fold.
function atMorphEnd(box, measure) {
  const resize = resizes.get(box);
  const ease = resize?.playState === 'running' ? resize : null, at = ease?.currentTime ?? 0;
  if (ease) {
    ease.effect.updateTiming({ fill: 'forwards' });
    ease.currentTime = MORPH_MS;
  }
  try { return measure(); } finally {
    if (ease) {
      ease.effect.updateTiming({ fill: 'auto' });
      ease.currentTime = at;
    }
  }
}

// How much taller than where it ends a box morph draws in gets on the rest of its way there, from where it is now, 0
// once it has got there: one that shrinks is taller only till it has shrunk, and one whose lines grow at once while
// others fold late (listFrames) goes past both its ends (overshootAhead).
function morphOvershoot(box) {
  const ease = resizes.get(box);
  if (ease?.playState !== 'running') return 0;
  const frames = ease.effect.getKeyframes().map((k) => ({ offset: k.computedOffset, height: parseFloat(k.height) }));
  return overshootAhead(frames, ease.effect.getComputedTiming().progress ?? 0, box.offsetHeight);
}

// How much taller than its last keyframe's height a box gets from `done` (0 to 1) of its way on, given its keyframes,
// each { offset, height }, and its height `now`: what it has passed no longer counts.
function overshootAhead(frames, done, now) {
  const end = frames[frames.length - 1].height;
  return Math.max(0, now - end, ...frames.filter((k) => k.offset >= done).map((k) => k.height - end));
}

const atListEnd = (measure) => atMorphEnd(document.getElementById('list'), measure);

function morph(list, html, { still = false } = {}) {
  const before = drawnBefore.has(list) && !calm.matches && !still ? snapshot(list) : null;
  const wasHeight = before ? list.offsetHeight : 0;  // as it shows now, even partway through easing
  const scrolled = new Map([...list.querySelectorAll('.perm .perm-detail')].map((d) => [cardOf(d), d.scrollTop]));
  // Keep focus and caret in an answer box on the list being typed in (not one beside it, as the reader's).
  const typing = document.activeElement?.closest?.('.perm .q-type'), typedIn = typing && list.contains(typing);
  const caret = typedIn && { card: cardOf(typing), q: typing.dataset.q,
                             start: typing.type === 'number' ? null : typing.selectionStart,
                             end: typing.type === 'number' ? null : typing.selectionEnd };
  list.innerHTML = html;
  resizes.get(list)?.cancel();
  for (const drawn of core.drawn) drawn(list);  // what the modules size from the new HTML
  for (const d of list.querySelectorAll('.perm .perm-detail')) d.scrollTop = scrolled.get(cardOf(d)) || 0;
  if (caret) {
    const box = [...list.querySelectorAll(`.perm .q-type${caret.q != null ? `[data-q="${caret.q}"]` : ''}`)]
      .find((b) => cardOf(b) === caret.card && !b.closest('.prows.closed'));
    // Not scrolled to: the box is where it was, and one partly out of view would have WebKit centre it, the list
    // jumping under you as you type.
    if (box) {
      box.focus({ preventScroll: true });
      if (caret.start != null) box.setSelectionRange(caret.start, caret.end);
    }
  }
  drawnBefore.add(list);
  if (!before) return;
  const height = list.offsetHeight;  // as rebuilt, before the lines below are given their starting sizes
  const unseenRows = outOfSight(list, before);
  // changed: anything animates; moved: something changes size or place, which the panel's height and the copy of the
  // row you're on held at the list's edge follow.
  let changed = false, moved = false;
  const rows = [], late = [];  // late: the chat lines' folds that wait for their text to erase (listFrames)
  for (const row of list.querySelectorAll('.row[data-id]')) {
    const old = before.get(rowKey(row));
    if (!old) {
      if (!row.classList.contains('landing')) row.classList.add('arrive');  // a started one's arrives as its copy lands
      changed = moved = true;
      continue;
    }
    if (old.hidden || row.closest('.prows.closed')) continue;  // in a collapsed group: its own slide handles it
    const main = row.querySelector(':scope > .main');
    let grewOrShrank = false;
    const lines = rowParts(), chatAfter = chatDelays(main, old), unseen = unseenRows.has(row);
    lines.forEach((sel, i) => {
      const el = main.querySelector(':scope > ' + sel), was = old.parts[sel], line = core.lines[sel];
      const chat = sel in chatAfter && !unseen;
      if (el && !was) {  // a new line: grow it in
        const h = el.offsetHeight, cs = getComputedStyle(el), box = {};
        for (const k of BOX_KEYS) box[k] = cs[k];
        if (chat) writeIn(el, chatAfter[sel] + CHAT_LEAD);  // its text writes in as its room opens
        el.style.overflow = 'hidden';
        tween(el, { height: '0px', ...FLAT, opacity: '0', transform: 'translateY(-4px)' },
                  { height: h + 'px', ...box, opacity: '1', transform: 'translateY(0)' },
                  () => { el.style.overflow = ''; });
        line?.grow?.(el);  // how a module's line comes in, beside growing
        grewOrShrank = changed = moved = true;
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
        grewOrShrank = changed = moved = true;
      } else if (el && was && partText(sel) && partText(sel)(el) !== was.text) {  // new text in the same line
        // Your message and Claude's line are rewritten (rewriteLine); a module's line cross-fades. Out of sight, a
        // chat line just has its new words, its own room easing to its new height. Measured before rewriteLine puts it
        // back at its old height to ease from.
        const resized = Math.abs(el.offsetHeight - was.height) > 1;
        if (chat) {
          rewriteLine(el, was, chatAfter[sel], late);
          grewOrShrank = true;
          if (resized) moved = true;
        } else if (sel in chatAfter) {
          if (resized) {
            const h = el.offsetHeight;
            el.style.overflow = 'hidden';
            tween(el, { height: was.height + 'px' }, { height: h + 'px' }, () => { el.style.overflow = ''; });
            grewOrShrank = moved = true;
          }
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
  for (const [key, old] of before) if (!old.hidden && !shown.has(key)) { fadeAway(list, old); changed = moved = true; }
  const heads = new Map([...list.querySelectorAll('.project[data-key]')]
    .map((h) => [h.dataset.key, h]));
  for (const [key, old] of before.heads)
    if (!heads.has(key)) { fadeAway(list, old, HEADER_MS); changed = moved = true; }
  for (const [key, head] of heads) {
    const old = before.heads.get(key);
    if (!old) { head.classList.add('arrive'); changed = moved = true; continue; }
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
    changed = moved = true;
  }
  // The list's own box eases between its heights with the rows, so what's below it (the now-playing strip) and the
  // panel's bottom edge move with them, rather than jumping to where they end up while the rows are still on their way.
  if (late.length) {
    resizes.set(list, list.animate(listFrames(wasHeight, height, late), { duration: MORPH_MS, easing: 'linear' }));
    changed = moved = true;
  } else if (Math.abs(height - wasHeight) > 1) {
    resizes.set(list, list.animate([{ height: `${wasHeight}px` }, { height: `${height}px` }],
                                   { duration: MORPH_MS, easing: MORPH_EASE }));
    changed = moved = true;
  }
  if (changed) {  // the panel follows the list's height while it animates; rebuilds wait till it's done
    const started = performance.now();
    state.settleUntil = started + MORPH_MS + 40;
    // Frame by frame only while something changes size or place: when only words change, the panel's height and the
    // copy of the row you're on stay as they are, and following them would draw the page again every frame for
    // nothing.
    if (moved) {
      (function follow() {
        reportHeight();
        if (performance.now() - started < MORPH_MS + 60) requestAnimationFrame(follow);
      })();
    } else reportHeight();
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
// height, with the panel following frame by frame. The list isn't rebuilt meanwhile (what draws it again waits
// for `sliding`: renderWhenSettled), or the slide would be cut short; once it's done, `done` runs (the list's own
// drawing again, which settles the final state), or at once when there's no group to slide.
const SLIDE_MS = 200;
function slideGroup(header, collapse, done) {
  const body = header?.nextElementSibling;
  if (!body?.classList.contains('prows')) return done();
  resizes.get(document.getElementById('list'))?.cancel();  // the list's height follows the slide instead
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
  setTimeout(() => { state.sliding--; done(); }, SLIDE_MS + 20);
}

// ---- A scroll's last bit: pulled on, then the click ----

// How long a pull over its whole reach takes (ms), about a tenth of a second; a shorter one takes less, by the square
// root of its share of the reach, so it's still seen to snap rather than slide.
const PULL_MS = 110;
// The click it ends on: a spring of one swing in CLICK_RESPONSE ms, CLICK_DAMPING of each swing taken out, carrying past
// its place by CLICK_GIVE points at most. It's at rest once it's within CLICK_REST of its place, moving less than a
// point a frame.
const CLICK_RESPONSE = 220, CLICK_DAMPING = 0.88, CLICK_GIVE = 1, CLICK_REST = 0.25;

// The click as a function of time: from its place, moving `speed` points a millisecond on past it, where it is `t` ms
// on (points past its place), and when it's at rest (`ms`). How far past it carries is held to CLICK_GIVE.
function clickSpring(speed) {
  const w0 = (2 * Math.PI) / CLICK_RESPONSE, z = CLICK_DAMPING, wd = w0 * Math.sqrt(1 - z * z), b = speed / wd;
  const raw = (t) => Math.exp(-z * w0 * t) * b * Math.sin(wd * t);
  let peak = 0, ms = 0;
  for (let t = 4; t <= 1000; t += 4) {
    const x = raw(t);
    peak = Math.max(peak, x);
    ms = t;
    if (Math.abs(x) < CLICK_REST && Math.abs(raw(t + 16) - x) < 1) break;
  }
  const k = peak > CLICK_GIVE ? CLICK_GIVE / peak : 1;
  return { at: (t) => (t >= ms ? 0 : raw(t) > 0 ? raw(t) * k : raw(t)), ms };
}

// Scrolls `el` the last bit to where `target()` says it ends up (its scrollTop, measured again each frame, so it gets
// there whatever moves meanwhile): from rest, speeding up all the way (as p squared, so it arrives at twice its
// average speed), in PULL_MS over the most it's pulled (`reach`, points) and less over less, then the click. `frame`
// runs after each step; `done` once it's there. Under reduced motion it's there at once. Returns what stops it, for a
// scroll of yours to take over.
function pullScroll(el, target, reach, frame, done) {
  if (calm.matches) {
    el.scrollTop = target();
    frame?.();
    done?.();
    return () => {};
  }
  const from = el.scrollTop, d = Math.abs(target() - from), took = Math.max(50, PULL_MS * Math.sqrt(d / reach));
  const dir = Math.sign(target() - from), spring = clickSpring((2 * d) / took), start = performance.now();
  let id = 0;
  const step = (now) => {
    const t = now - start, to = target();
    if (t < took) el.scrollTop = from + (to - from) * (t / took) ** 2;
    else el.scrollTop = to + dir * spring.at(t - took);
    frame?.();
    if (t < took + spring.ms) id = requestAnimationFrame(step);
    else done?.();
  };
  id = requestAnimationFrame(step);
  return () => cancelAnimationFrame(id);
}
