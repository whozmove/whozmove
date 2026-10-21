// The list's motion: each rebuild animates from what was there (morph), and groups slide open and shut.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// The list is rebuilt from scratch every second; morph makes the rebuild look continuous. It notes each row's
// place, height and lines, rebuilds, and animates the difference:
// - a new line (Claude's live line, its reply, a PR) grows in from nothing, fading and lifting into place;
// - a line that's gone stays a moment as a copy that folds away;
// - changed text cross-fades, and a row whose height changed otherwise resizes smoothly;
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
// A row's lines, top to bottom (rowHTML): the core's, with the lines the modules draw in its places put where those
// are (core.lines, each with its `place`: the island under the details' first line, the pull requests at the end).
// Listed once the modules start, when every line they draw is there (they add them as their scripts load).
function listLines() {
  const placed = (place) => Object.keys(core.lines).filter((sel) => core.lines[sel].place === place);
  return ['.line1', '.you', '.claude', '.perm', '.where', ...placed('underWhere'), '.step-note', '.setup',
          ...placed('after')];
}
let lineOrder = null;
core.starts.push(() => { lineOrder = listLines(); });
function rowParts() { return lineOrder ?? listLines(); }
// The text that counts as a change for each line (the live line's timer ticks every second; that doesn't, and nor do
// Deploy's button changing, which animates by itself, on the title line, the counts at the end of the details line,
// which swap by themselves, or a line that animates by itself, as the island does each of its stages). A card is
// another one when its data attributes are (which request, session or step it's for), or it shows another question, or
// it was answered. The modules say what counts in their lines (core.lines' `text`).
// (`:scope > .what`: a line's own text, not that of the copies rolling inside it.)
const PART_TEXT = { '.you': (el) => el.querySelector(':scope > .what')?.textContent,
                    '.claude': (el) => el.dataset.mode + ' ' + el.querySelector(':scope > .what')?.textContent,
                    '.perm': (el) => Object.values(el.dataset).join('') + ' '
                                     + (el.querySelector('.q')?.dataset.q ?? '')
                                     + (el.querySelector('.perm-sent') ? ' sent' : ''),
                    '.where': (el) => [...el.childNodes].map((n) => (n.classList?.contains('end') ? '#' : n.textContent))
                                     .join(''),
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
      // `shape`: where a line that animates by itself had its parts (the island's segments), to animate from.
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

// A chat line taking new text (your next message, or Claude's line going from working to its reply): the old text
// rolls out as the new rolls in, clipped to the line like a ticker, and the line eases between their heights.
// Yours rolls up (sent, as in a chat) and Claude's down (arriving from its side): `down` is true for Claude's line.
// Only the text rolls; the label ("You", "Claude") stays put and just changes. The rolling copies ride inside
// the line (its own text hidden underneath), so they move with it when the line above changes height too.
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

// A copy of what was there, laid over the list where it was, fading out.
function fadeAway(list, old, ms = MORPH_MS) {
  const ghost = old.el.cloneNode(true);
  ghost.classList.remove('is-hover', 'arrive', 'glide');
  Object.assign(ghost.style, { position: 'absolute', top: old.top - list.clientTop + 'px', left: old.left + 'px',
                               width: old.width + 'px', margin: '0', pointerEvents: 'none', zIndex: '1' });
  list.appendChild(ghost);
  tween(ghost, { opacity: '1', transform: 'translateY(0) scale(1)' },
        { opacity: '0', transform: 'translateY(-4px) scale(0.98)' }, () => ghost.remove(), ms);
}

// Which card on the list a box is in, by the card's data attributes (which request, session or step it's for), so the
// rebuild finds it again: to leave a box being read where it was scrolled to (a request, the extra stage's command,
// which has to be read to its end), and to keep the box being typed in with its caret. Null outside a card.
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
  for (const drawn of core.drawn) drawn(list);  // what the modules size from the new HTML (the island's gauges)
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
  const rows = [];
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
    const lines = rowParts();
    lines.forEach((sel, i) => {
      const el = main.querySelector(':scope > ' + sel), was = old.parts[sel], line = core.lines[sel];
      if (el && !was) {  // a new line: grow it in
        const h = el.offsetHeight, cs = getComputedStyle(el), box = {};
        for (const k of BOX_KEYS) box[k] = cs[k];
        el.style.overflow = 'hidden';
        tween(el, { height: '0px', ...FLAT, opacity: '0', transform: 'translateY(-4px)' },
                  { height: h + 'px', ...box, opacity: '1', transform: 'translateY(0)' },
                  () => { el.style.overflow = ''; });
        line?.grow?.(el);  // how a module's line comes in, beside growing (the island's capsule springs open)
        grewOrShrank = changed = true;
      } else if (!el && was) {  // a line that's gone: a copy folds away where it was
        const ghost = was.el.cloneNode(true);
        const next = lines.slice(i + 1).map((s) => main.querySelector(':scope > ' + s)).find(Boolean);
        main.insertBefore(ghost, next || null);
        ghost.style.overflow = 'hidden';
        ghost.style.pointerEvents = 'none';
        tween(ghost, { height: was.height + 'px', opacity: '1' },
                     { height: '0px', ...FLAT, opacity: '0' }, () => ghost.remove());
        line?.fold?.(ghost);  // and how it goes
        grewOrShrank = changed = true;
      } else if (el && was && partText(sel) && partText(sel)(el) !== was.text) {  // new text in the same line
        // Your message (rolling up), and Claude's line turning from one thing to another (its reply arriving where
        // it was working, or the start of a turn, rolling down) roll like a ticker; the next step while it works
        // cross-fades.
        const step = sel === '.claude' && el.dataset.mode === 'work' && was.el.dataset.mode === 'work';
        if (sel === '.you' || (sel === '.claude' && !step)) {
          rollLine(row, el, was, sel === '.claude');
          grewOrShrank = true;
        } else (step ? el.querySelector(':scope > .what') : line?.swap ? line.swap(el) : el)?.classList.add('swap');
        changed = true;
      } else if (el && was && line?.morph?.(el, was.shape)) {  // a line that animates by itself (the island)
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
  // The list's own box eases between its heights with the rows, so what's below it (the usage strip) and the panel's
  // bottom edge move with them, rather than jumping to where they end up while the rows are still on their way.
  if (Math.abs(height - wasHeight) > 1) {
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

// Keeps the panel's window the height of its page, frame by frame, for `ms`: for motion outside the list (the usage
// strip's), which changes the page's height as it goes.
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
