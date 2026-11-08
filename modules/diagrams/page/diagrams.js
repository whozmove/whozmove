// A ```mermaid block wherever the reader shows Markdown (a plan, its card, notes), drawn as a diagram: a flow read in
// full is drawn here (flow.js), at the width it has once it's on the page; any other block, and a flow whose lines
// would run through its steps, shows as written, with a line saying why. Each diagram drawn has Diagram and As
// written. On the list (a request's card), a block stays code.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// The diagrams you've turned to As written, by their text's key, so they stay that way as the panel draws them again.
moduleState({ diagramsWritten: new Set() });

// Why a block shows as written: it isn't a flow, it has groups, it has a part this doesn't read, or, laid out, its
// lines would run through its steps or its words onto each other.
const DIAGRAM_WHY = {
  kind: 'Only flow diagrams are drawn here, so this shows as written.',
  grouped: 'Flows with groups aren\'t drawn here, so this shows as written.',
  unread: 'Part of this flow can\'t be drawn here, so it shows as written.',
  unclear: 'Drawn here, its lines would cross its steps or its words would overlap, so it shows as written.',
};
// A card's small drawing is at most this high, the whole of it shrunk to fit; with its smallest words (an edge's, or
// else its steps') shrunk below this much of the panel's words, they couldn't be read, so it names its steps in words
// instead.
const DIAGRAM_SMALL_HEIGHT = 200, DIAGRAM_SMALL_LEAST = 0.6;

// A short key for a diagram's text.
function diagramKey(text) {
  let hash = 5381;
  for (const c of String(text)) hash = ((hash * 33) ^ c.codePointAt(0)) >>> 0;
  return `d${hash.toString(36)}${String(text).length.toString(36)}`;
}

// ---- The figure ----

const diagramTabsHTML = (written) => '<div class="tabs dg-tabs" role="group" aria-label="How to show the diagram">'
  + [['drawn', 'Diagram'], ['written', 'As written']].map(([show, words]) => `<button type="button" `
    + `data-dg-show="${show}" aria-pressed="${(show === 'written') === written}">${words}</button>`).join('') + '</div>';

// A block's figure: its kind and how to show it, then the drawing, or the block as written. It goes in holding its
// text, which shows until it's drawn (diagramsDraw), and the line saying why for when its lines wouldn't keep clear
// of its steps, which shows only then, in place of Diagram and As written. One not drawn here shows as written, saying
// why. Only the reader draws one: elsewhere (`place` 'list'), null, so the block shows as code.
function diagramHTML(text, place = 'reader') {
  if (place !== 'reader') return null;
  const kind = diagramKind(text), written = `<pre class="dg-src"><code>${esc(text)}</code></pre>`, read = flowRead(text);
  const top = (tabs) => `<div class="dg-top"><span class="caps dg-kind">${esc(kind.words)}</span>${tabs}</div>`;
  const why = (cls, said) => `<p class="${cls}">${esc(said)}</p>`;
  if (!read.flow) {
    return `<figure class="dg" data-dg-state="written">${top('')}${why('dg-why', DIAGRAM_WHY[read.why])}${written}</figure>`;
  }
  const key = diagramKey(text), asWritten = state.diagramsWritten.has(key);
  return `<figure class="dg" data-dg="${key}" data-dg-state="${asWritten ? 'written' : 'todo'}">`
    + `${top(diagramTabsHTML(asWritten))}${why('dg-why dg-unclear', DIAGRAM_WHY.unclear)}<div class="dg-draw"></div>`
    + `${written}</figure>`;
}

// A card's small drawing of a block: its words until it's drawn, and where it can't be drawn here.
function diagramSmallHTML(text) {
  return `<span class="dg-small" data-dg-state="${flowRead(text).flow ? 'todo' : 'words'}"><span class="dg-draw"></span>`
    + `<span class="dg-small-words">${esc(diagramWords(text))}</span><span class="dg-src" hidden>${esc(text)}</span></span>`;
}

// The diagrams Markdown holds, as the panel's Markdown reads its code blocks (mdFences), so what's counted here is
// what's drawn.
const diagramsIn = (md) => mdFences(md).filter((block) => block.lang === 'mermaid').map((block) => block.body);

// What Markdown that's one diagram and nothing else says in words (a section of a plan that's only its flow), or null.
function diagramMarkdownWords(md) {
  const blocks = mdFences(md), lines = String(md ?? '').trim().split('\n');
  const one = blocks.length === 1 && blocks[0].lang === 'mermaid'
    && lines.length === blocks[0].body.split('\n').length + 2;
  return one ? diagramWords(blocks[0].body) : null;
}

// The first flow in Markdown that has something to show on a card, or null: drawn here, or read well enough to name its
// steps. One read in part would only say "A flow diagram.", which tells nothing.
const diagramFirstFlow = (md) => diagramsIn(md).find((text) => flowParse(text).flow) ?? null;

// ---- Drawing ----

// The size of the panel's words, which a drawing's words take, and of its small words, an edge's (tokens.css).
const diagramTextSize = (token = '--size-body') => parseFloat(getComputedStyle(document.documentElement)
  .getPropertyValue(token)) || 12;

let diagramCanvas = null;
function diagramMeasure(size) {
  if (typeof document.createElement !== 'function') return flowRoughWidth(size);
  diagramCanvas ??= document.createElement('canvas').getContext('2d');
  const font = `${size}px ${getComputedStyle(document.body).fontFamily}`;
  return (words) => {
    diagramCanvas.font = font;
    return diagramCanvas.measureText(String(words)).width;
  };
}

// How far below a line's middle its baseline sits, for words `size` px high: half their capitals' height, measured in
// the page's own font, so a box's words sit in its middle.
function diagramDrop(size) {
  if (typeof document.createElement !== 'function') return flowRoughDrop(size);
  diagramCanvas ??= document.createElement('canvas').getContext('2d');
  diagramCanvas.font = `${size}px ${getComputedStyle(document.body).fontFamily}`;
  return diagramCanvas.measureText('H').actualBoundingBoxAscent / 2;
}

// What's drawn at the width it has: a figure not drawn yet, drawn, or as written because its lines or words wouldn't
// keep clear at that width (unclear), and a small drawing not drawn yet, drawn, or in words only because its room was
// too narrow then or it wouldn't keep clear there (shrunk); either may be drawn at another width, as bands that fail
// at one width can keep clear at another.
const DIAGRAM_DRAWN = '.dg[data-dg-state="todo"], .dg[data-dg-state="drawn"], .dg[data-dg-state="unclear"], '
  + '.dg-small[data-dg-state="todo"], .dg-small[data-dg-state="drawn"], .dg-small[data-dg-state="shrunk"]';

// Each diagram in `root` (and `root` itself) drawn at the width it has: one not drawn yet, or drawn (or shrunk to words)
// at a width that has since changed. One with no width yet (not on the page) waits for the next time. One whose lines
// or words wouldn't keep clear even on one line (flowPlace) shows as written, saying why: a figure without Diagram and
// As written (unclear), a card its steps in words (shrunk).
function diagramsDraw(root) {
  if (!root?.querySelectorAll) return;
  const todo = [...(root.matches?.(DIAGRAM_DRAWN) ? [root] : []), ...root.querySelectorAll(DIAGRAM_DRAWN)];
  if (!todo.length) return;
  const size = diagramTextSize(), width = diagramMeasure(size);
  const drop = { words: diagramDrop(size), edge: diagramDrop(diagramTextSize('--size-small')) };
  for (const el of todo) {
    // Its room is the figure's, less the drawing's own sides: the drawing is hidden until it's drawn.
    const draw = el.querySelector('.dg-draw'), style = getComputedStyle(draw);
    const room = Math.floor(el.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight));
    const measured = ['drawn', 'shrunk', 'unclear'].includes(el.dataset.dgState);
    if (room <= 0 || (measured && Math.abs(room - Number(el.dataset.dgRoom)) < 8)) continue;
    const text = el.querySelector('.dg-src').textContent, flow = flowRead(text).flow;
    if (!flow) continue;
    const placed = flowPlace(flow, room, width, size);
    if (!placed) {
      draw.innerHTML = '';
      el.dataset.dgState = el.classList.contains('dg-small') ? 'shrunk' : 'unclear';
      el.dataset.dgRoom = room;
      continue;
    }
    draw.innerHTML = flowSVG(placed, diagramWords(text), drop);
    const svg = draw.firstElementChild, w = Number(svg.dataset.width), h = Number(svg.dataset.height);
    // Full size, shrinking to fit at most to three quarters, then scrolling sideways; on a card, the whole of it, or
    // its words where it would be too small to read.
    if (el.classList.contains('dg-small')) {
      const shrink = Math.min(1, room / w, DIAGRAM_SMALL_HEIGHT / h);
      const smallest = flow.edges.some((e) => e.label) ? diagramTextSize('--size-small') : size;
      if (shrink * smallest < DIAGRAM_SMALL_LEAST * size) {
        draw.innerHTML = '';
        el.dataset.dgState = 'shrunk';
        el.dataset.dgRoom = room;
        continue;
      }
      svg.style.width = `${Math.round(w * shrink)}px`;
    } else Object.assign(svg.style, { width: `${w}px`, maxWidth: '100%', minWidth: `${Math.round(w * 0.75)}px` });
    el.dataset.dgState = 'drawn';
    el.dataset.dgRoom = room;
  }
}

// ---- Diagram or As written ----

// Pressed, the figure turns to the other: what it showed fades, its room eases to what it shows now (as a strip's
// does, the panel following), and that comes in the panel's way (fading, lifting 3px, sharpening). Under reduced
// motion, the one fades into the other. A press while it turns waits for it.
const DIAGRAM_FADE_MS = 160;
function diagramShow(button) {
  const figure = button.closest('.dg'), written = button.dataset.dgShow === 'written';
  if (!figure || figure.dataset.dgTurning || written === (figure.dataset.dgState === 'written')) return;
  for (const b of figure.querySelectorAll('.dg-tabs button')) {
    b.setAttribute('aria-pressed', String((b.dataset.dgShow === 'written') === written));
  }
  if (written) state.diagramsWritten.add(figure.dataset.dg);
  else state.diagramsWritten.delete(figure.dataset.dg);
  const before = figure.offsetHeight, going = figure.querySelector(written ? '.dg-draw' : '.dg-src');
  const turn = () => {
    delete figure.dataset.dgTurning;
    figure.dataset.dgState = written ? 'written' : 'todo';
    delete figure.dataset.dgRoom;
    if (!written) diagramsDraw(figure);
    // What comes in is the drawing, or, where it can't be drawn clear (unclear), the text again.
    const coming = figure.querySelector(figure.dataset.dgState === 'drawn' ? '.dg-draw' : '.dg-src');
    easeHeight(figure, before);
    coming?.animate(calm.matches ? [{ opacity: 0 }, { opacity: 1 }]
      : [{ opacity: 0, transform: 'translateY(3px)', filter: 'blur(1.5px)' }, { opacity: 1, transform: 'none',
                                                                                filter: 'blur(0)' }],
    { duration: calm.matches ? 300 : 420, easing: MORPH_EASE });
  };
  if (calm.matches || !going) return turn();
  figure.dataset.dgTurning = '1';
  tween(going, { opacity: '1' }, { opacity: '0' }, turn, DIAGRAM_FADE_MS, 'ease');
}

core.readerPresses.push(['.dg-tabs button', diagramShow]);

// ---- What it plugs into ----

core.fences.mermaid = diagramHTML;
core.readerDrawn.push(diagramsDraw);
core.diagrams = {
  smallHTML: diagramSmallHTML,
  words: diagramMarkdownWords,
  says: diagramWords,
  firstFlow: diagramFirstFlow,
  draw: diagramsDraw,
};
