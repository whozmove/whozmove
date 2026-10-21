// A row's island: a capsule with where the work in its checkout stands, stage by stage (stagesOf), the files stage a
// gauge of how they're staged; what a press on a stage does; and how the island moves between rebuilds.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// The island (stagesOf): a glass capsule with a segment per stage, open with its count where the stage holds
// something and a dot where it doesn't, the one where your next move is a little brighter. A press on a segment opens
// its menu: what the stage holds, and its steps (the app's, NextSteps' stageMenu). One only just shown doesn't take a
// press yet (justShown). Each segment is keyed by its stage, which is how the animation follows it (morphIsland).
function islandHTML(s, stages) {
  if (!stages) return '';
  state.shownAt['island:' + s.sessionId] ??= Date.now();
  const gauge = stages.some((st) => st.parts);
  // The gauge's part whose files are listed (island-files.js) is drawn lit, so a rebuild doesn't light it afresh.
  const listed = state.filesShown?.startsWith(s.sessionId + ':') ? state.filesShown.slice(s.sessionId.length + 1) : null;
  const segments = stages.map((st) => {
    const cls = ['seg', st.stage, st.count > 0 ? 'open' : '', st.move ? 'move' : '', st.parts ? 'gauge' : '']
      .filter(Boolean).join(' ');
    const data = ` data-stage="${st.stage}" data-count="${st.count}"` + (st.step ? ` data-step="${st.step}"` : '')
      + (st.pr ? ` data-pr="${esc(st.pr)}"` : '');
    if (st.parts) return `<span class="${cls}"${data}${gaugeData(st.parts)}>${gaugeHTML(st, listed)}</span>`;
    const text = st.count > 0 ? `<span class="seg-text">${esc(st.text)}</span>` : '';
    // The commits stage shows its own card when pointed at (island-steps.js), so it has no tooltip as well.
    const tip = st.stage === 'commits' && st.count > 0 ? '' : ` title="${esc(st.tip)}"`;
    return `<span class="${cls}"${data}${tip}>${text}</span>`;
  });
  // The gauge open under the pointer stays open through the rebuild (island-files.js opens and closes it).
  const open = gauge && state.islandOpen === s.sessionId ? ' open' : '';
  return `<div class="island" data-sid="${esc(s.sessionId)}"><span class="cap${open}">${segments.join('')}</span></div>`;
}

// The files stage as a gauge, when git says how its files split (stagesOf's `parts`): shut, its total, over a fill as
// long as the parts are (staged solid, partly staged lighter, unstaged the rest); open, the three parts side by side,
// each with its count, in words or, short of room, as a number alone (layoutIslands picks). A part with no files keeps
// its place with no width, so the others' edges stay where the sizes put them.
const GAUGE_PARTS = [['staged', 'st'], ['partly', 'pt'], ['unstaged', 'un']];
function gaugeData(parts) {
  return GAUGE_PARTS.map(([part]) => ` data-${part}="${parts[part]}"`).join('');
}
function gaugeHTML(st, listed) {
  const bands = GAUGE_PARTS.map(([part, cls]) => {
    const n = st.parts[part], label = n ? `<span class="lbl"><span class="w">${compact(n)} ${part}</span>`
      + `<span class="n">${compact(n)}</span></span>` : '';
    const lit = n && part === listed ? ' is-on' : '';
    return `<span class="band ${cls}${lit}"${n ? ` data-part="${part}"` : ''}>${label}</span>`;
  });
  return bands.join('') + `<span class="seg-text rest">${esc(st.text)}</span>`;
}

// Sizes each island's gauge from its words once it's in the page (after each rebuild, core.drawn): shut, as wide
// as its total; open, its parts in proportion to their counts, each with room for its words, within what the row has
// once the island's other stages have shrunk to dots, and with numbers alone when even that's too little. Where its
// words go in and come out (--c0) is the middle of the partly part, or the edge between the other two. The motion
// itself is CSS, from these sizes (motion.css).
function layoutIslands(root) {
  for (const gauge of root.querySelectorAll('.gauge')) {
    const room = gauge.closest('.main').clientWidth - (gauge.closest('.cap').children.length - 1) * 16 - 8;
    if (room <= 0) continue;  // in a folded group: sized once it opens
    const n = Object.fromEntries(GAUGE_PARTS.map(([part]) => [part, +gauge.dataset[part] || 0]));
    const total = n.staged + n.partly + n.unstaged;
    const need = (which) => Object.fromEntries(GAUGE_PARTS.map(([part, cls]) => {
      const label = gauge.querySelector(`.${cls} .${which}`);
      return [part, label ? textWidth(gauge, label.textContent) + 14 : 0];
    }));
    let want = need('w');
    const terse = want.staged + want.partly + want.unstaged > room;
    if (terse) want = need('n');
    gauge.classList.toggle('terse', terse);
    const shut = textWidth(gauge, gauge.querySelector('.rest').textContent) + 16;
    const sum = want.staged + want.partly + want.unstaged;
    const open = Math.min(Math.max(sum + 36, 150), room), spare = Math.max(0, open - sum);
    const s1 = want.staged + spare * n.staged / total, p1 = want.partly + spare * n.partly / total;
    const u1 = open - s1 - p1;
    const s0 = shut * n.staged / total, p0 = shut * n.partly / total;
    const centre = n.partly ? s0 + p0 / 2 : n.staged && n.unstaged ? s0 : n.staged ? shut : 0;
    // How far past the middle of its part a count waits to come out: half the part, half its words, and a little.
    const beyond = (part, words) => part / 2 + Math.max(0, words - 14) / 2 + 4;
    const sizes = { '--w0': shut, '--w1': open, '--s0': s0, '--p0': p0, '--s1': s1, '--p1': p1, '--c0': centre,
                    '--sx': beyond(s1, want.staged), '--ux': beyond(u1, want.unstaged) };
    for (const [name, px] of Object.entries(sizes)) gauge.style.setProperty(name, px.toFixed(1) + 'px');
  }
}

// A segment of a row's island: its menu (the app's), below it, with what the stage holds and its steps; the commits
// stage, whose menu shows as it's pointed at (island-steps.js), opens what its commits changed instead, in the reader's
// changes view. One only just shown doesn't take a press yet.
function pressStage(seg, e) {
  e.preventDefault();
  const sid = seg.closest('.island')?.dataset.sid, d = seg.dataset;
  if (!sid || justShown('island:' + sid)) return;
  if (d.stage === 'commits' && +d.count > 0) {
    hideSteps();
    toggleReader(sid, null, 'changes', 'commits');
    return;
  }
  const r = seg.getBoundingClientRect();
  const msg = { type: 'stageMenu', sessionId: sid, stage: d.stage, count: +d.count, x: r.left - 4, y: r.bottom + 4 };
  if (d.step) msg.step = d.step;
  if (d.pr) msg.pr = +d.pr;
  native(msg);
}

// ---- Motion ----

// The island's spring: a slight overshoot as a segment opens or closes, and as the capsule comes in. The curve, and the
// usual ease standing in where WebKit lacks linear() easing, are tokens.css's --spring, which the gauge's own motion
// uses too.
const SPRING = 'var(--spring)';
const SPRING_MS = 700, BLUR_MS = 450;

// Each segment of an island, by stage: its width, its count's text, its tint, and whether your next move is there.
// offsetWidth, so a capsule caught growing in (scaled) still gives its segments' real widths.
function islandShape(island) {
  const shape = {};
  for (const seg of island.querySelectorAll('.seg'))
    shape[seg.dataset.stage] = { width: seg.offsetWidth, text: seg.querySelector(':scope > .seg-text')?.textContent ?? '',
                                 bg: getComputedStyle(seg).backgroundColor, move: seg.classList.contains('move') };
  return shape;
}

// The island between rebuilds. Each stage's segment springs from its old width to its new one, so a stage
// that has just filled opens from a dot and one that has emptied closes into one, easing into its new tint as it goes
// (one tween for both, as a second would cancel the first). A count that changed blurs out upward as the new one
// blurs in from below; and a light sweeps once across the stage that has just become where your next move is.
// Returns whether anything moved.
function morphIsland(island, was) {
  let moved = false;
  // While its gauge is open, the counts on show are the gauge's parts' (its total and the other stages' counts are
  // hidden, the others shrunk to dots), so a count changing then just changes.
  const gaugeOpen = !!island.querySelector('.cap.open');
  for (const seg of island.querySelectorAll('.seg')) {
    const old = was[seg.dataset.stage], width = seg.offsetWidth, bg = getComputedStyle(seg).backgroundColor;
    const from = {}, to = {};
    if (old && Math.abs(old.width - width) > 0.5) { from.width = old.width + 'px'; to.width = width + 'px'; }
    if (old && old.bg !== bg) { from.backgroundColor = old.bg; to.backgroundColor = bg; }
    if (Object.keys(to).length) { tween(seg, from, to, null, SPRING_MS, SPRING); moved = true; }
    const text = seg.querySelector(':scope > .seg-text'), now = text?.textContent ?? '';
    if (old && old.text !== now && !gaugeOpen) { blurSwap(seg, text, old.text); moved = true; }
    if (seg.classList.contains('move') && old && !old.move) { sweep(seg, width); moved = true; }
  }
  return moved;
}

// A segment's count changing: the old one (if it had one) blurs out upward as a copy over the segment, and the new one
// (if it has one) blurs in from below.
function blurSwap(seg, text, was) {
  if (was) {
    const leaving = document.createElement('span');
    leaving.className = 'seg-leaving';
    leaving.textContent = was;
    seg.appendChild(leaving);
    tween(leaving, { transform: 'translateY(0)', opacity: '1', filter: 'blur(0px)' },
          { transform: 'translateY(-70%)', opacity: '0', filter: 'blur(3px)' }, () => leaving.remove(), BLUR_MS);
  }
  if (text) tween(text, { transform: 'translateY(70%)', opacity: '0', filter: 'blur(3px)' },
                  { transform: 'translateY(0)', opacity: '1', filter: 'blur(0px)' }, null, SPRING_MS, SPRING);
}

// A light that sweeps once across a segment, all the way across the `width` it's opening to (motion.css), gone before
// the next rebuild.
function sweep(seg, width) {
  const light = document.createElement('span');
  light.className = 'sheen';
  light.style.setProperty('--across', width + 12 + 'px');
  seg.appendChild(light);
  setTimeout(() => light.remove(), 950);
}

// ---- What it plugs into ----

// Its stages, worked out first. Gone, it's forgotten when it was first shown, so one that's back waits again before it
// takes a press.
core.rowLooks.push((row) => {
  row.stages = stagesOf(row.s, row.owner);
  if (!row.stages) delete state.shownAt['island:' + row.s.sessionId];
});
core.slots.underWhere.push((row) => islandHTML(row.s, row.stages));
core.presses.push(['.seg[data-stage]', pressStage]);
core.pointerTargets.push('.seg');
core.forgotten.prefixes.push('island');

// Its line on the row: the capsule comes in springing open from its left end, and squeezes back there on the way out;
// in between, each stage moves by itself (morphIsland).
core.lines['.island'] = {
  place: 'underWhere',
  shape: islandShape,
  morph: morphIsland,
  grow(island) {
    const cap = island.querySelector('.cap');
    if (cap) tween(cap, { transform: 'scaleX(.2)', opacity: '0' }, { transform: 'scaleX(1)', opacity: '1' }, null,
                   SPRING_MS, SPRING);
  },
  fold(island) {
    const cap = island.querySelector('.cap');
    if (cap) tween(cap, { transform: 'scaleX(1)', opacity: '1' }, { transform: 'scaleX(.2)', opacity: '0' }, null,
                   SPRING_MS);
  },
};

// The gauges are sized as soon as the list's HTML is in, before anything below measures them; and as the panel opens
// from its header, as folded the list had no width to size them by, rather than a rebuild later.
core.drawn.push(layoutIslands);
core.collapses.push((collapsed) => { if (!collapsed) layoutIslands(document.getElementById('list')); });
