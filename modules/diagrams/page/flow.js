// A ```mermaid block read and, when it's a flow this reads in full, laid out and drawn as an SVG in the panel's look;
// and what any diagram says in words. Plain functions, checked by the module's page cases.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// ---- Reading a block ----

// The kinds Mermaid knows, by the word a block starts with: what each is called on its figure, and in a sentence.
const DIAGRAM_KINDS = [
  [/^(flowchart|graph)\b/, 'flow', 'Flow', 'flow diagram'], [/^sequenceDiagram\b/, 'sequence', 'Sequence', 'sequence'],
  [/^stateDiagram/, 'state', 'States', 'state diagram'], [/^classDiagram\b/, 'class', 'Classes', 'class diagram'],
  [/^erDiagram\b/, 'data', 'Data', 'data diagram'], [/^gantt\b/, 'gantt', 'Timeline', 'timeline'],
  [/^pie\b/, 'pie', 'Pie chart', 'pie chart'], [/^journey\b/, 'journey', 'Journey', 'journey'],
  [/^mindmap\b/, 'mindmap', 'Mind map', 'mind map'], [/^timeline\b/, 'timeline', 'Timeline', 'timeline'],
  [/^gitGraph\b/, 'git', 'Branches', 'branch diagram'], [/^architecture/, 'architecture', 'Architecture',
    'architecture diagram'],
];
// Its lines, without Mermaid's %% comments or blank lines.
const diagramLines = (text) => String(text).split('\n').map((l) => l.replace(/%%.*$/, '').trim()).filter(Boolean);
function diagramKind(text) {
  const first = diagramLines(text)[0] || '';
  const kind = DIAGRAM_KINDS.find(([word]) => word.test(first));
  return kind ? { key: kind[1], words: kind[2], said: kind[3] } : { key: 'other', words: 'Diagram', said: 'diagram' };
}

// A node's or an edge's words as they read: its quotes and Markdown's stars taken off, and <br> a line break. Anything
// else in angle brackets is words ("Read <id>.json"), never markup: it's drawn as it's written.
function flowLabel(raw) {
  let words = String(raw).trim();
  if (/^".*"$/s.test(words)) words = words.slice(1, -1);
  return words.replace(/^`|`$/g, '').replace(/<br\s*\/?>/gi, '\n').replace(/#quot;/g, '"').replace(/#amp;/g, '&')
    .replace(/\*\*([^*]+)\*\*|\*([^*]+)\*/g, (m, a, b) => a ?? b).trim();
}

// A node's shapes, longest opening first: each drawn as a box, a pill (rounded ends) or a decision (pointed ends).
const FLOW_SHAPES = [['([', '])', 'pill'], ['[[', ']]', 'box'], ['[(', ')]', 'box'], ['((', '))', 'pill'],
  ['{{', '}}', 'decision'], ['[/', '/]', 'box'], ['[\\', '\\]', 'box'], ['[/', '\\]', 'box'], ['[', ']', 'box'],
  ['(', ')', 'round'], ['{', '}', 'decision'], ['>', ']', 'box']];

// What can't be read throws, so the flow is drawn whole or not at all.
const flowUnread = () => { throw new Error('unread'); };

// One node at `i`: its id, and its words and shape where it gives them. A class on it (:::) gives it a colour this
// doesn't draw, so it isn't read.
function flowNode(line, i, flow) {
  const id = line.slice(i).match(/^\s*([\p{L}\p{N}_]+)/u);
  if (!id) return null;
  let j = i + id[0].length, label = null, shape = null;
  for (const [open, close, look] of FLOW_SHAPES) {
    if (!line.startsWith(open, j)) continue;
    let from = j + open.length;
    // A quoted label may hold the closing characters.
    if (line[from] === '"') from = line.indexOf('"', from + 1) + 1 || from;
    const end = line.indexOf(close, from);
    if (end < 0) flowUnread();
    label = flowLabel(line.slice(j + open.length, end));
    shape = look;
    j = end + close.length;
    break;
  }
  if (line.startsWith(':::', j)) flowUnread();
  let node = flow.nodes.get(id[1]);
  if (!node) flow.nodes.set(id[1], node = { id: id[1], label: id[1], shape: 'box', order: flow.nodes.size });
  if (label !== null) Object.assign(node, { label: label || id[1], shape });
  return [id[1], j];
}

// What's drawn at an end, by its mark.
const FLOW_ENDS = { '>': 'arrow', '<': 'arrow', x: 'cross', o: 'circle' };

// One edge at `i`, with its words, read as Mermaid reads it: a line (solid, thick or dotted) with an arrow, a cross, a
// circle or nothing at its end, and the same mark at its start too ("<-->", "x--x", "o--o") or none. A line with its
// end mark is tried before words, as Mermaid does, so "--x B" is a cross, never words starting "x B", and an "x" or
// "o" right after the dashes is an end ("dev---ops" is a circle edge to "ps"). A start mark without its own kind at
// the end, an edge's own name, "~~~" and "-->>" aren't read.
function flowEdge(line, i) {
  // An "x" or "o" straight after a step is part of its name, so it starts an edge only after a space ("A x--x B").
  const start = line.slice(i).match(/^(?:\s*(<)(?=[-=.])|\s+([xo])(?=[-=.]))?/);
  const tail = FLOW_ENDS[start[1] || start[2]] ?? null, at = i + start[0].length, rest = line.slice(at);
  const edge = (mark, end, label, dotted, thick) => {
    const head = FLOW_ENDS[mark] ?? null;
    return tail && tail !== head ? null : { end: at + end, label, dotted, thick, head, tail };
  };
  const plain = rest.match(/^\s*(-{2,}[-xo>]|={2,}[=xo>]|-?\.+-[xo>]?)(?![>xo<=.-])\s*(?:\|([^|]*)\|)?/);
  if (plain) {
    return edge(plain[1].slice(-1), plain[0].length, plain[2] ? flowLabel(plain[2]) : '', plain[1].includes('.'),
                plain[1].startsWith('='));
  }
  // Words close with a line of their own kind: "-- words -->", "== words ==>", "-. words .->".
  const worded = rest.match(/^\s*(--|==|-\.)(?![->.=])\s*(.+?)\s*(-{2,}[xo>]|={2,}[xo>]|\.-+[xo>]|-{3,}|={3,})/);
  if (!worded || worded[3][0] !== { '--': '-', '==': '=', '-.': '.' }[worded[1]]) return null;
  return edge(worded[3].slice(-1), worded[0].length, flowLabel(worded[2]), worded[1] === '-.', worded[1] === '==');
}

// The nodes on one side of an edge: one, or several joined by &.
function flowGroup(line, i, flow) {
  const ids = [];
  for (;;) {
    const node = flowNode(line, i, flow);
    if (!node) return ids.length ? [ids, i] : null;
    ids.push(node[0]);
    i = node[1];
    const and = line.slice(i).match(/^\s*&\s*/);
    if (!and) return [ids, i];
    i += and[0].length;
  }
}

// A line's statements, parted at each ";" that's outside a node's brackets, a quote and an edge's |words|: inside
// them, a ";" is words ("Save it; then open it").
function flowStatements(line) {
  const out = [];
  let depth = 0, quoted = false, piped = false, at = 0;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (c === '"') quoted = !quoted;
    else if (quoted) continue;
    else if (c === '|' && !depth) piped = !piped;
    else if ('[({'.includes(c)) depth++;
    else if (')]}'.includes(c)) depth = Math.max(0, depth - 1);
    else if (c === ';' && !depth && !piped) {
      out.push(line.slice(at, i));
      at = i + 1;
    }
  }
  out.push(line.slice(at));
  return out;
}

// A flow as { flow: { dir, nodes (by id, in the order they first appear), edges } }, or { why } it isn't read here:
// 'kind', it isn't a flow; 'grouped', it has groups (subgraph); 'unread', a part this doesn't read (a colour, an arrow
// it doesn't draw, an edge's own name, words left over, a shape not closed). Every part of every line is read, or
// none of it is: a picture with a piece left out could be approved as the plan. For its words alone (`ungrouped`),
// a group's own lines are passed over, so a flow with groups still says its steps.
function flowParse(text, ungrouped = false) {
  if (diagramKind(text).key !== 'flow') return { why: 'kind' };
  try {
    // A flow written on one line ("graph LR; A-->B") is its header, then its lines.
    const lines = diagramLines(text).flatMap((l, k) => (k ? [l] : flowStatements(l).map((x) => x.trim()).filter(Boolean)));
    const head = lines[0].match(/^(?:flowchart|graph)\s*(LR|RL|TD|TB|BT)?\s*$/);
    if (!head) flowUnread();
    const flow = { dir: (head[1] || 'TD').replace('TB', 'TD'), nodes: new Map(), edges: [] };
    for (const line of lines.slice(1)) {
      if (ungrouped && /^(subgraph\b|end$|direction\s+(LR|RL|TD|TB|BT)$)/.test(line)) continue;
      if (/^subgraph\b/.test(line)) return { why: 'grouped' };
      if (/^(classDef|class|style|linkStyle)\b/.test(line)) flowUnread();
      if (/^click\b/.test(line)) continue;
      for (const part of flowStatements(line)) {
        if (!part.trim()) continue;
        let i = 0, from = null;
        for (;;) {
          const group = flowGroup(part, i, flow) || flowUnread();
          i = group[1];
          if (from) for (const a of from.ids) for (const b of group[0]) flow.edges.push({ ...from.edge, from: a, to: b });
          if (!part.slice(i).trim()) break;
          const edge = flowEdge(part, i) || flowUnread();
          i = edge.end;
          from = { ids: group[0], edge };
        }
      }
    }
    return flow.nodes.size ? { flow } : { why: 'unread' };
  } catch {
    return { why: 'unread' };
  }
}

// A flow drawn here: one read in full, with at most one loop from a step to itself, drawn at its side (a second would
// have nowhere of its own): { why: 'unread' } otherwise. Whether its lines keep clear of its steps is known only once
// it's laid out at its width (flowPlace).
function flowRead(text) {
  const read = flowParse(text);
  if (!read.flow) return read;
  const loops = read.flow.edges.filter((e) => e.from === e.to).map((e) => e.from);
  return new Set(loops).size === loops.length ? read : { why: 'unread' };
}

// ---- What a diagram says in words ----

const diagramOneLine = (words) => String(words).replace(/\s*\n\s*/g, ' ');

// A flow's main path: from its first node, the longest way on, never back (a loop), the first edge winning a tie, so a
// branch that ends at once ("Code, as today") isn't taken for the flow.
function flowPath(flow) {
  const { back } = flowRanks(flow), longest = new Map();
  const on = (id) => {
    if (!longest.has(id)) {
      longest.set(id, [id]);
      let best = [id];
      for (const e of flow.edges) {
        if (e.from !== id || e.from === e.to || back.has(e)) continue;
        const rest = on(e.to);
        if (rest.length + 1 > best.length) best = [id, ...rest];
      }
      longest.set(id, best);
    }
    return longest.get(id);
  };
  return on(flow.nodes.keys().next().value).map((id) => diagramOneLine(flow.nodes.get(id).label));
}

// What a diagram says in words, wherever it isn't drawn (a folded section, a card's line) and as what VoiceOver reads
// for it: its kind, how big, and a flow's steps in order. Read from its text alone, so it's there before anything is
// drawn, and for a flow read in full that isn't drawn here.
function diagramWords(text) {
  const kind = diagramKind(text);
  if (kind.key === 'flow') {
    const flow = flowParse(text).flow ?? flowParse(text, true).flow;
    if (!flow) return `A ${kind.said}.`;
    const path = flowPath(flow), n = flow.nodes.size;
    const shown = path.length > 5 ? [...path.slice(0, 3), '…', path[path.length - 1]] : path;
    return `A flow of ${n} ${n === 1 ? 'step' : 'steps'}: ${shown.join(' → ')}.`;
  }
  if (kind.key === 'sequence') {
    const who = [], named = {};
    const add = (name) => {
      const words = diagramOneLine(String(name).trim());
      if (words && !who.includes(words)) who.push(words);
    };
    let messages = 0;
    for (const line of diagramLines(text).slice(1)) {
      const one = line.match(/^(?:participant|actor)\s+(\S+)(?:\s+as\s+(.+))?$/);
      if (one) {
        named[one[1]] = one[2] || one[1];
        add(named[one[1]]);
        continue;
      }
      const said = line.match(/^([^\s:-]+)\s*-{1,2}(?:>>?|x|\))\s*[+-]?([^\s:]+)\s*:/);
      if (!said) continue;
      messages++;
      add(named[said[1]] || said[1]);
      add(named[said[2]] || said[2]);
    }
    const list = who.length > 1 ? `${who.slice(0, -1).join(', ')} and ${who[who.length - 1]}` : who[0] || 'its parts';
    return `A sequence between ${list}: ${messages} ${messages === 1 ? 'message' : 'messages'}.`;
  }
  // Its title, on a line of its own or after the kind's word ("pie title …").
  const title = diagramLines(text).map((l, i) => l.match(i ? /^title\s+(.+)$/ : /^\S+\s+title\s+(.+)$/)?.[1])
    .find(Boolean);
  return `A ${kind.said}${title ? `: ${diagramOneLine(title)}` : ''}.`;
}

// ---- A flow laid out ----

// Its sizes, for words `size` px high: a node's padding, line and least width, the gaps between ranks, between nodes
// in a rank, and between bands, a stand-in's lane, and how far a loop to itself goes out.
const flowSizes = (size) => {
  const k = size / 12;
  return { size, padX: 12 * k, padY: 7 * k, lineH: Math.round(16 * k), minW: 60 * k, rankGap: 40 * k, nodeGap: 14 * k,
           bandGap: 44 * k, lane: 8 * k, loop: 22 * k };
};

const FLOW_WRAP = 24;  // characters on a node's line before its words wrap
function flowWrap(label) {
  const out = [];
  for (const para of String(label).split('\n')) {
    let line = '';
    for (const word of para.split(/\s+/).filter(Boolean)) {
      if (line && `${line} ${word}`.length > FLOW_WRAP) {
        out.push(line);
        line = word;
      } else line = line ? `${line} ${word}` : word;
    }
    out.push(line);
  }
  return out;
}

// Each node's rank, by its longest path from the start, with any edge back to an earlier node set aside so a loop
// doesn't push its nodes on and on; and those edges.
function flowRanks(flow) {
  const ids = [...flow.nodes.keys()], mark = {}, back = new Set();
  const visit = (id) => {
    mark[id] = 1;
    for (const e of flow.edges) {
      if (e.from !== id || e.from === e.to) continue;
      if (mark[e.to] === 1) back.add(e);
      else if (!mark[e.to]) visit(e.to);
    }
    mark[id] = 2;
  };
  ids.forEach((id) => mark[id] || visit(id));
  const rank = Object.fromEntries(ids.map((id) => [id, 0]));
  for (let pass = 0; pass < ids.length; pass++) {
    for (const e of flow.edges) if (!back.has(e) && e.from !== e.to) rank[e.to] = Math.max(rank[e.to], rank[e.from] + 1);
  }
  return { rank, back };
}

// A path through points, each straight on from the one before, across or down, its corners turned round `r` px.
function flowOrth(ps, r = 6) {
  const pts = ps.filter((p, i) => !i || p[0] !== ps[i - 1][0] || p[1] !== ps[i - 1][1]);
  let d = `M${pts[0]}`;
  pts.slice(1).forEach(([x, y], i) => {
    const [px, py] = pts[i], next = pts[i + 2], run = ([tx, ty]) => (x === px ? ` V${ty}` : ` H${tx}`);
    if (!next) {
      d += run([x, y]);
      return;
    }
    const k = Math.min(r, Math.abs(x - px + y - py) / 2, Math.abs(next[0] - x + next[1] - y) / 2);
    d += `${run([x - Math.sign(x - px) * k, y - Math.sign(y - py) * k])} Q${x},${y} `
      + `${x + Math.sign(next[0] - x) * k},${y + Math.sign(next[1] - y) * k}`;
  });
  return d;
}

// Whether two boxes overlap.
const flowMeets = (a, b) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;

// A point `t` of the way along a curve given by its points (de Casteljau's way).
const flowAt = (ps, t) => (ps.length === 1 ? ps[0]
  : flowAt(ps.slice(1).map((p, i) => [ps[i][0] + (p[0] - ps[i][0]) * t, ps[i][1] + (p[1] - ps[i][1]) * t]), t));

// The flow placed in `room` px across: each node's box, and each edge's path, the tips of its ends and the way each
// points, and its words' box. An edge that goes on more than one rank has a stand-in point in each rank it passes,
// placed among that rank's steps as a narrow step of its own, so it runs beside the steps between, never through them,
// as Mermaid's own layout does. A flow left to right that's wider than its room carries on in a second band under the
// first, as words wrap, the bands filled evenly so no step is left on one of its own. `clear` says whether its lines
// and words keep clear of its steps (flowClear), `banded` whether it's in bands, and `crowded` the ranks whose gap after
// them had no place for an edge's words, which `grow` (px, by rank) makes deeper and `spread` (px, by rank) parts the
// points in the ranks either side of further. `width(words)` measures a line of words.
function flowLayout(flow, room, width, size, grow = [], spread = []) {
  const S = flowSizes(size), { rank, back } = flowRanks(flow), R = 6;  // R: the radius a line turns round
  const across = flow.dir === 'LR' || flow.dir === 'RL';
  const loops = new Map(flow.edges.filter((e) => e.from === e.to).map((e) => [e.from, e]));
  const nodes = [...flow.nodes.values()].map((n) => {
    const lines = flowWrap(n.label), loop = loops.get(n.id), said = loop?.label ? flowWrap(loop.label) : [];
    const w = Math.max(S.minW, Math.ceil(Math.max(...lines.map(width))) + S.padX * 2 + (n.shape === 'decision' ? 16 : 0));
    // A loop to itself goes out at its side (right top down, under it left to right), its words beyond it: room the
    // next point across leaves it.
    const side = !loop ? 0 : S.loop + (!said.length ? 0
      : across ? said.length * S.lineH + 6 : Math.max(...said.map(width)) + 14);
    return { ...n, lines, w, h: lines.length * S.lineH + S.padY * 2, rank: rank[n.id], side };
  });
  const byId = Object.fromEntries(nodes.map((n) => [n.id, n]));
  // Each edge on, as the points it passes from rank to rank: its two steps, with a stand-in in each rank between.
  const forward = flow.edges.filter((e) => e.from !== e.to && !back.has(e)), chains = new Map(), stands = [];
  forward.forEach((e, k) => {
    const between = [];
    for (let r = rank[e.from] + 1; r < rank[e.to]; r++) {
      between.push({ stand: true, edge: e, rank: r, w: across ? 0 : S.lane, h: across ? S.lane : 0, side: 0,
                     order: nodes.length + k });
    }
    // A jumping edge's words go on its own run through the middle rank it passes, its lane there as wide as they are,
    // so they sit beside the steps it goes round, on its line alone.
    if (e.label && between.length) {
      const said = flowWrap(e.label), s = between[Math.floor((between.length - 1) / 2)];
      if (across) s.h = Math.max(S.lane, said.length * S.lineH + 2);
      else s.w = Math.max(S.lane, Math.max(...said.map(width)) + 10);
      s.words = true;
    }
    stands.push(...between);
    chains.set(e, [byId[e.from], ...between, byId[e.to]]);
  });
  const hops = [...chains.values()].flatMap((c) => c.slice(1).map((q, k) => [c[k], q]));
  const ranks = Array.from({ length: Math.max(...nodes.map((n) => n.rank)) + 1 },
                           (_, r) => [...nodes, ...stands].filter((p) => p.rank === r));
  // Within a rank, each point near the points it's linked to in the rank before (two passes), then in the rank after,
  // so two lines that needn't cross don't, then before again; the order they first appear breaking ties, a stand-in
  // after the steps.
  const at = (p) => ranks[p.rank].indexOf(p);
  const near = (r, linked) => {
    ranks[r] = ranks[r].map((p, k) => {
      const by = linked(p).map(at);
      return [by.length ? by.reduce((a, b) => a + b, 0) / by.length : k, p.order, p];
    }).sort((a, b) => a[0] - b[0] || a[1] - b[1]).map((x) => x[2]);
  };
  const before = (p) => hops.filter(([, q]) => q === p).map(([a]) => a);
  const after = (p) => hops.filter(([a]) => a === p).map(([, q]) => q);
  for (let pass = 0; pass < 2; pass++) for (let r = 1; r < ranks.length; r++) near(r, before);
  for (let r = ranks.length - 2; r >= 0; r--) near(r, after);
  for (let r = 1; r < ranks.length; r++) near(r, before);
  // The room each rank takes along the flow, and across it, and the gap after it, as deep as the words on the edges
  // that go from it to the next need, with room either side for an edge's ends: their width along a flow left to
  // right, their lines down a flow top down. A jumping edge's words are on its run, not in a gap.
  const acrossOf = (p) => (across ? p.h : p.w) + p.side;
  const along = ranks.map((list) => Math.max(...list.map((p) => (across ? p.w : p.h))));
  const apart = (r) => S.nodeGap + (spread[r] || 0);
  const breadth = ranks.map((list, r) => list.reduce((s, p) => s + acrossOf(p), 0) + apart(r) * (list.length - 1));
  const gap = ranks.map((_, r) => (grow[r] || 0) + Math.max(S.rankGap, ...forward
    .filter((e) => e.label && rank[e.from] === r && rank[e.to] === r + 1).map((e) => flowWrap(e.label))
    .map((lines) => (across ? Math.max(...lines.map(width)) + 26 : lines.length * S.lineH + 18))));
  const cut = (limit) => {
    const out = [];
    let band = { ranks: [], size: 0 };
    ranks.forEach((_, r) => {
      const need = along[r] + (band.ranks.length ? gap[r - 1] : 0);
      if (across && band.ranks.length && band.size + need > limit) {
        out.push(band);
        band = { ranks: [], size: 0 };
      }
      band.size += band.ranks.length ? need : along[r];
      band.ranks.push(r);
    });
    out.push(band);
    return out;
  };
  let bands = cut(room);
  if (bands.length > 1) {
    const total = along.reduce((a, b) => a + b, 0) + gap.slice(0, -1).reduce((a, b) => a + b, 0);
    const even = cut(Math.min(room, total / bands.length * 1.12));
    if (even.length === bands.length) bands = even;
  }
  // Into the band below: what carries on goes last in its band's last rank, and what comes in goes first in the next
  // band's first rank, so a line drops between bands past no step. Two carrying on would drop through each other, one
  // with a loop to itself would drop through it, and one a loop back comes into or leaves, at either end of the drop,
  // would share it, so the flow isn't clear in bands then.
  let carried = true;
  bands.forEach((b, k) => {
    const last = b.ranks[b.ranks.length - 1], first = b.ranks[0];
    const on = new Set(hops.filter(([p]) => p.rank === last && k < bands.length - 1).map(([p]) => p));
    const come = new Set(hops.filter(([, q]) => q.rank === first && k).map(([, q]) => q));
    const looped = (p) => flow.edges.some((e) => back.has(e) && (e.to === p.id || e.from === p.id));
    if (on.size > 1 || [...on].some((p) => loops.has(p.id) || looped(p)) || [...come].some(looped)) {
      carried = false;
    }
    ranks[last].sort((p, q) => on.has(p) - on.has(q));
    ranks[first].sort((p, q) => come.has(q) - come.has(p));
  });
  // A loop back left to right goes into its step from below where nothing in its rank is under it; else in at its side,
  // from the gap before its rank. One up more than one band, or into a step at the start of its band from the side,
  // goes up outside the bands' left side, each in a lane of its own.
  const bandOf = (r) => bands.findIndex((b) => b.ranks.includes(r));
  // A loop back goes in or out at a step's side (top down) or foot (left to right) only where nothing in its rank is
  // past it there, and it has no loop to itself there.
  const lastIn = (p) => ranks[p.rank][ranks[p.rank].length - 1] === p && !loops.has(p.id);
  const firstIn = (p) => ranks[p.rank][0] === p;
  const lanes = new Map(across ? flow.edges.filter((e) => back.has(e)).filter((e) => {
    const b = byId[e.to];
    return bandOf(rank[e.from]) - bandOf(b.rank) > 1 || (!lastIn(b) && bands[bandOf(b.rank)].ranks[0] === b.rank);
  }).map((e, k) => [e, k]) : []);
  const inset = lanes.size ? S.nodeGap + lanes.size * 8 : 0, span = [];
  // Two loops back up out of one band would run along one line in the gap above it.
  const ups = flow.edges.filter((e) => back.has(e) && bandOf(rank[e.from]) > bandOf(rank[e.to]))
    .map((e) => bandOf(rank[e.from]));
  if (new Set(ups).size < ups.length) carried = false;
  let y0 = 0;
  bands.forEach((b, k) => {
    b.thick = Math.max(...b.ranks.map((r) => breadth[r]));
    let at = inset;
    b.ranks.forEach((r, j) => {
      if (j) at += gap[r - 1];
      span[r] = [at, at + along[r]];
      let cross = (b.thick - breadth[r]) / 2;
      for (const p of ranks[r]) {
        if (across) Object.assign(p, { x: at + (along[r] - p.w) / 2, y: y0 + cross });
        else Object.assign(p, { x: cross, y: at + (along[r] - p.h) / 2 });
        p.band = k;
        cross += acrossOf(p) + apart(r);
      }
      at += along[r];
    });
    b.top = y0;
    b.bottom = y0 + b.thick;
    y0 += b.thick + S.bandGap;
  });
  let W = across ? inset + Math.max(...bands.map((b) => b.size)) : Math.max(...breadth);
  let H = across ? bands[bands.length - 1].bottom
    : along.reduce((a, b) => a + b, 0) + gap.slice(0, -1).reduce((a, b) => a + b, 0);

  // A point's middle across the flow, and the ends of its depth along it: a step's own, a stand-in's its rank's whole.
  const pt = (a, c) => (across ? [a, c] : [c, a]);
  const mid = (p) => (across ? p.y + p.h / 2 : p.x + p.w / 2);
  const depth = (p) => (p.stand ? span[p.rank] : across ? [p.x, p.x + p.w] : [p.y, p.y + p.h]);
  // Two edges between one pair of steps (twins): 10px apart at their ends, and where they have words, bowed apart
  // enough between that each one's words, halfway along, miss the other's line and words.
  const twin = (e) => {
    const all = forward.filter((o) => o.from === e.from && o.to === e.to), at = all.indexOf(e) - (all.length - 1) / 2;
    const room = Math.max(0, ...all.filter((o) => o.label).map((o) => {
      const said = flowWrap(o.label);
      return across ? said.length * S.lineH + 2 : Math.max(...said.map(width)) + 10;
    }));
    return [at * 10, rank[e.to] === rank[e.from] + 1 && room ? at * Math.max(0, room + 4 - 10) / 0.75 : 0];
  };
  // An edge on: soft curves between ranks, straight through each stand-in's rank; into the band below, down from its
  // step's foot, along the gap, and down into the next from above. A stand-in never crosses into a band below in a
  // layout that's drawn: the line along the longest way to its edge's end carries on beside it, so two would drop
  // (`carried`). Edges from one step to the same one are each moved `shift` px across at both ends, so they aren't
  // drawn as one, and bowed `bow` px across between, so each one's words are on its line alone.
  const onward = (chain, shift, bow) => {
    const a = chain[0], b = chain[chain.length - 1], lead = across && a.band !== chain[1].band;
    let pen = lead ? [a.x + a.w / 2 + shift, a.y + a.h] : pt(depth(a)[1], mid(a) + shift), from = 'side';
    const out = { d: `M${pen}`, foot: pen, footWay: lead || !across ? [0, -1] : [-1, 0], hops: [] };
    chain.slice(1).forEach((q, k) => {
      const p = chain[k];
      if (across && p.band !== q.band) {
        const ym = bands[p.band].bottom + S.bandGap / 2, [px] = pen, qx = q.x + q.w / 2 + (q === b ? shift : 0);
        const turn = qx < px ? -R : R, straight = Math.abs(qx - px) < 2 * R, tx = straight ? px : qx;
        out.d += straight ? ` V${q.y}`
          : ` V${ym - R} Q${px},${ym} ${px + turn},${ym} H${qx - turn} Q${qx},${ym} ${qx},${ym + R} V${q.y}`;
        if (!k) out.words = [(px + tx) / 2, ym];
        pen = [tx, q.y];
        from = 'above';
      } else {
        const [x1, y1] = pen, [x2, y2] = pt(depth(q)[0], mid(q) + (q === b ? shift : 0));
        const c = across ? [[(x1 + x2) / 2, y1 + bow], [(x1 + x2) / 2, y2 + bow]]
          : [[x1 + bow, (y1 + y2) / 2], [x2 + bow, (y1 + y2) / 2]];
        out.d += ` C${c[0]} ${c[1]} ${x2},${y2}`;
        out.hops.push([pen, ...c, [x2, y2]]);
        if (!k) out.lead = out.hops[0];
        pen = [x2, y2];
        from = 'side';
      }
      if (!q.stand) return;
      if (q.words) out.side = pt((span[q.rank][0] + span[q.rank][1]) / 2, mid(q));
      out.d += across ? ` H${span[q.rank][1]}` : ` V${span[q.rank][1]}`;
      pen = pt(span[q.rank][1], mid(q));
    });
    return { ...out, tip: pen, way: from === 'above' || !across ? [0, 1] : [1, 0] };
  };
  // Loops back nest by how far back they go, the shortest innermost, each run out far enough beyond the last for its
  // own words, which sit on it: round the right of every rank it passes, top down, under its band, left to right, and
  // past the words on the edges between those ranks, which can reach beyond the steps.
  const wordsOut = (r0, r1, band) => Math.max(-Infinity, ...forward.filter((e) => e.label && rank[e.to] === rank[e.from] + 1
    && rank[e.from] >= r0 && rank[e.to] <= r1 && (band === undefined || byId[e.from].band === band)).map((e) => {
    const said = flowWrap(e.label), a = byId[e.from], b = byId[e.to], [shift, bow] = twin(e);
    return Math.max(mid(a), mid(b)) + Math.max(0, shift + bow * 0.75)
      + (across ? said.length * S.lineH + 2 : Math.max(...said.map(width)) + 10) / 2;
  }));
  const runs = new Map(), outmost = {};
  flow.edges.filter((e) => back.has(e)).sort((e, f) => (rank[e.from] - rank[e.to]) - (rank[f.from] - rank[f.to]))
    .forEach((e, k) => {
      const a = byId[e.from], b = byId[e.to], said = e.label ? flowWrap(e.label) : [], key = across ? a.band : 'right';
      const half = !said.length ? 0 : across ? (said.length * S.lineH + 2) / 2 : (Math.max(...said.map(width)) + 10) / 2;
      const base = across ? Math.max(bands[a.band].bottom, wordsOut(b.rank, a.rank, a.band) - 10) + 18
        : Math.max(...ranks.slice(b.rank, a.rank + 1).flat().map((p) => p.x + p.w + p.side), wordsOut(b.rank, a.rank) - 14) + 22;
      const at = Math.max(base, outmost[key] ?? -Infinity) + half;
      if (!across || a.band === b.band) outmost[key] = at + half + 8;
      runs.set(e, { at, k });
    });
  // Back to an earlier rank, top down: round the right of every rank it passes. Left to right, along a channel: under
  // its band, or, to an earlier band, the gap above its own; out of its step down from its foot (up from its top, to an
  // earlier band) where nothing in its rank is in the way, else out of its side into the gap after its rank; to a band
  // more than one up, along to its lane outside the bands' left side and up it to the gap under the band it goes to;
  // and into its step from below, or at its side from the gap before its rank (its lane, at the start of a band). Two
  // between one pair of steps are moved apart at both ends.
  const backward = (e) => {
    const pair = flow.edges.filter((o) => back.has(o) && o.from === e.from && o.to === e.to);
    const shift = (pair.indexOf(e) - (pair.length - 1) / 2) * 10, { at, k } = runs.get(e);
    const a = byId[e.from], b = byId[e.to], ax = a.x + a.w / 2 + shift, bx = b.x + b.w / 2 + shift;
    const ay = a.y + a.h / 2 + shift, by = b.y + b.h / 2 + shift;
    const off = 8 + (k % 5) * 6;  // in a gap, each a little further out, so two don't run on one line
    if (!across) {
      // Out of its side where nothing in its rank is to its right, else down from its foot and along the gap after
      // its rank; into its step at the side the same way, else from the gap before its rank, down into its top.
      const xr = at, out = lastIn(a), into = lastIn(b), ya = span[a.rank][1] + off, yt = span[b.rank][0] - off;
      const ps = [...(out ? [[a.x + a.w, ay]] : [[ax, a.y + a.h], [ax, ya]]), [xr, out ? ay : ya],
        ...(into ? [[xr, by], [b.x + b.w, by]] : [[xr, yt], [bx, yt], [bx, b.y]])];
      return { d: flowOrth(ps), hops: [[[xr, out ? ay : ya], [xr, into ? by : yt]]], foot: ps[0],
               footWay: out ? [-1, 0] : [0, -1], tip: ps[ps.length - 1], way: into ? [-1, 0] : [0, 1] };
    }
    const same = a.band === b.band, lane = inset - S.nodeGap / 2 - (lanes.get(e) ?? 0) * 8;
    const yc = same ? at : bands[a.band].top - S.bandGap * 0.28;
    const out = same ? lastIn(a) : firstIn(a), ps = out ? [[ax, same ? a.y + a.h : a.y]]
      : [[a.x + a.w, ay], [span[a.rank][1] + off, ay]];
    ps.push([ps[ps.length - 1][0], yc]);
    const run = ps.length - 1;  // where it runs along its channel, its words' place
    let yb = yc;
    if (a.band - b.band > 1) {
      yb = bands[b.band].bottom + S.bandGap * 0.28;
      ps.push([lane, yc], [lane, yb]);
    }
    const into = lastIn(b), xi = bands[b.band].ranks[0] === b.rank ? lane : span[b.rank][0] - off;
    ps.push(...(into ? [[bx, yb], [bx, b.y + b.h]] : [[xi, yb], [xi, by], [b.x, by]]));
    return { d: flowOrth(ps), hops: [[ps[run], ps[run + 1]]], foot: ps[0],
             footWay: out ? [0, same ? -1 : 1] : [-1, 0], tip: ps[ps.length - 1], way: into ? [0, -1] : [1, 0] };
  };
  // A loop to itself: out at its step's side and back, its words beyond it.
  const itself = (e) => {
    const n = byId[e.from], k = S.loop;
    if (across) {
      const x = n.x + n.w / 2, y = n.y + n.h;
      return { d: `M${x - R},${y} C${x - R * 2.5},${y + k} ${x + R * 2.5},${y + k} ${x + R},${y}`,
               words: [x, y + k + (flowWrap(e.label).length * S.lineH + 2) / 2], foot: [x - R, y], footWay: [0, -1],
               tip: [x + R, y], way: [0, -1] };
    }
    const x = n.x + n.w, y = n.y + n.h / 2;
    return { d: `M${x},${y - R} C${x + k},${y - R * 2.5} ${x + k},${y + R * 2.5} ${x},${y + R}`,
             words: [x + k + (e.label ? Math.max(...flowWrap(e.label).map(width)) + 10 : 0) / 2, y], foot: [x, y - R],
             footWay: [-1, 0], tip: [x, y + R], way: [-1, 0] };
  };
  const edges = flow.edges.map((e) => ({ ...e, of: e, lines: e.label ? flowWrap(e.label) : [],
    ...(e.from === e.to ? itself(e) : back.has(e) ? backward(e) : onward(chains.get(e), ...twin(e))) }));
  // Each edge's words, on a box of the panel's ground: a jumping edge's on its own run beside the steps it passes, or
  // halfway along its first hop; or, where that would lie on a step, a stand-in's lane, other words or another edge's
  // line (their ground would cover it, and they'd read as that edge's), further along it, or on a later hop. Words on
  // edges that fan out from one point go on together, as far as they must, out where their lines have parted, and so
  // do words on edges that come in to one, back towards where they come from; then each other edge's on its own, those
  // with fewest hops first, as they have fewest places. Words that fit nowhere stay halfway, the layout isn't clear,
  // and the gaps their edge passes are `crowded`.
  const stood = stands.map((s) => ({ edge: s.edge, ...(across
    ? { x: span[s.rank][0], y: s.y, w: span[s.rank][1] - span[s.rank][0], h: s.h }
    : { x: s.x, y: span[s.rank][0], w: s.w, h: span[s.rank][1] - span[s.rank][0] }) }));
  const placed = [], crowded = new Set(), worded = edges.filter((e) => e.lines.length);
  const boxAt = (e, [x, y]) => {
    const w = Math.max(...e.lines.map(width)) + 10, h = e.lines.length * S.lineH + 2;
    return { x: x - w / 2, y: y - h / 2, w, h };
  };
  const spots = (e, ways) => [...(e.side ? [e.side] : []), ...(e.hops ?? []).flatMap((hop) => ways.map((t) => flowAt(hop, t))),
    ...(e.words ? [e.words] : [])];
  const lined = new Map(edges.map((e) => [e, flowPoints(e.d)]));
  const place = (group, ways) => {
    for (const way of ways) {
      const boxes = group.map((e) => boxAt(e, way(e)));
      const free = boxes.every((b, i) => ![...nodes, ...stood.filter((s) => s.edge !== group[i].of), ...placed,
        ...boxes.slice(i + 1)].some((o) => flowMeets(b, o)) && flowBare(b, edges.filter((o) => o !== group[i]), lined));
      if (free) {
        group.forEach((e, i) => { e.box = boxes[i]; });
        placed.push(...boxes);
        return;
      }
    }
  };
  for (const [end, ways] of [[0, [0.5, 0.6, 0.7, 0.8]], [3, [0.5, 0.4, 0.3, 0.2]]]) {
    const fans = new Map();
    for (const e of worded) if (e.lead && !e.box) fans.set(`${e.lead[end]}`, [...(fans.get(`${e.lead[end]}`) ?? []), e]);
    for (const group of fans.values()) if (group.length > 1) place(group, ways.map((t) => (e) => flowAt(e.lead, t)));
  }
  const fewest = worded.filter((e) => !e.box).sort((a, b) => (a.hops?.length ?? 0) - (b.hops?.length ?? 0));
  for (const e of fewest) place([e], spots(e, [0.5, 0.6, 0.4, 0.7, 0.3, 0.8, 0.2, 0.9, 0.1]).map((spot) => () => spot));
  for (const e of worded) {
    if (e.box) continue;
    placed.push(e.box = boxAt(e, spots(e, [0.5])[0]));
    for (let r = rank[e.from]; r < rank[e.to]; r++) crowded.add(r);  // none for a loop back, or to itself
  }
  for (const e of edges) for (const key of ['hops', 'lead', 'words', 'side', 'of']) delete e[key];
  // Its bounds take in every line and every edge's words, which can reach past its steps: a loop back round them, into
  // a first step from above, words on an edge along its top.
  const reach = [...lined.values()].flat().concat(...edges.filter((e) => e.box)
    .map(({ box: b }) => [[b.x, b.y], [b.x + b.w, b.y + b.h]]));
  const minX = Math.floor(reach.reduce((m, [x]) => Math.min(m, x), 0));
  const minY = Math.floor(reach.reduce((m, [, y]) => Math.min(m, y), 0));
  W = reach.reduce((m, [x]) => Math.max(m, x), W);
  H = reach.reduce((m, [, y]) => Math.max(m, y), H);
  const L = { nodes, edges, x0: minX, y0: minY, W: Math.ceil(W), H: Math.ceil(H), lineH: S.lineH, size, across,
              banded: bands.length > 1, crowded: [...crowded] };
  L.clear = carried && flowClear(L);
  // Right to left and bottom to top are the same flow, turned round within its bounds.
  if (flow.dir === 'RL' || flow.dir === 'BT') {
    const rl = flow.dir === 'RL', X = W + minX, Y = H + minY, flip = (x, y) => (rl ? [X - x, y] : [x, Y - y]);
    const mirrored = ([dx, dy]) => (rl ? [-dx, dy] : [dx, -dy]);
    for (const n of nodes) [n.x, n.y] = rl ? [X - n.x - n.w, n.y] : [n.x, Y - n.y - n.h];
    for (const e of edges) {
      e.d = e.d.replace(/(-?[\d.]+),(-?[\d.]+)/g, (m, x, y) => flip(+x, +y).join(','))
        .replace(/([HV])(-?[\d.]+)/g, (m, c, v) => `${c}${(c === 'H') === rl ? (c === 'H' ? X : Y) - v : v}`);
      Object.assign(e, { tip: flip(...e.tip), way: mirrored(e.way), foot: flip(...e.foot),
                         footWay: mirrored(e.footWay) });
      if (e.box) e.box = rl ? { ...e.box, x: X - e.box.x - e.box.w } : { ...e.box, y: Y - e.box.y - e.box.h };
    }
  }
  return L;
}

// Points along a path as flowLayout writes it (M, H, V, Q and C, each absolute), a few px apart.
function flowPoints(d) {
  const out = [];
  let at = [0, 0];
  for (const part of d.match(/[MHVQC][^MHVQC]*/g) || []) {
    const v = part.slice(1).trim().split(/[\s,]+/).map(Number);
    const to = { M: [v[0], v[1]], H: [v[0], at[1]], V: [at[0], v[0]], Q: [v[2], v[3]], C: [v[4], v[5]] }[part[0]];
    const ps = part[0] === 'Q' ? [at, [v[0], v[1]], to] : part[0] === 'C' ? [at, [v[0], v[1]], [v[2], v[3]], to]
      : [at, to];
    const n = part[0] === 'M' ? 0 : Math.max(1, Math.ceil(Math.hypot(to[0] - at[0], to[1] - at[1]) / 3));
    for (let i = 1; i <= n; i++) out.push(flowAt(ps, i / n));
    if (!n) out.push(to);
    at = to;
  }
  return out;
}

// Whether a box of words lies on none of these edges' lines (their points, from `lined`).
const flowBare = (b, edges, lined) => edges.every((e) => !lined.get(e).some(([x, y]) => x > b.x + 1 && x < b.x + b.w - 1
  && y > b.y + 1 && y < b.y + b.h - 1));

// Whether a layout keeps clear: every line misses every step but its own two, and no edge's words lie on a step, on
// other words or on another edge's line. A line through a step reads as a link that isn't there, and words on another
// line read as that line's, so a layout that doesn't keep clear isn't drawn: drawn whole or not at all.
function flowClear(L) {
  const inside = ([x, y], n) => x > n.x + 1 && x < n.x + n.w - 1 && y > n.y + 1 && y < n.y + n.h - 1;
  const lined = new Map(L.edges.map((e) => [e, flowPoints(e.d)]));
  const worded = L.edges.filter((e) => e.box);
  return L.edges.every((e) => L.nodes.every((n) => n.id === e.from || n.id === e.to
    || !lined.get(e).some((p) => inside(p, n))))
    && worded.every((e, i) => !L.nodes.some((n) => flowMeets(e.box, n))
      && !worded.slice(i + 1).some((o) => flowMeets(e.box, o.box))
      && flowBare(e.box, L.edges.filter((o) => o !== e), lined));
}

// The layout a flow is drawn in at `room`: in bands where they keep clear, else on one line, scrolling sideways as a
// wide flow does; null where even that would put a line through a step or words on words, so it shows as written.
// Each way, a gap whose words found no place grows a line deeper (wider, left to right), and the ranks either side of
// it part their points a little further, so the lines through it part too, until they fit, as Mermaid's own layout
// makes room for an edge's words.
function flowPlace(flow, room, width, size) {
  const settle = (at) => {
    const grow = [], spread = [];
    let L = flowLayout(flow, at, width, size, grow, spread);
    for (let k = 0; k < 8 && !L.clear && L.crowded.length; k++) {
      for (const r of L.crowded) {
        grow[r] = (grow[r] || 0) + L.lineH * (L.across ? 3 : 1) + 4;
        for (const near of [r, r + 1]) spread[near] = (spread[near] || 0) + L.lineH / 2;
      }
      L = flowLayout(flow, at, width, size, grow, spread);
    }
    return L;
  };
  const L = settle(room);
  if (L.clear || !L.banded) return L.clear ? L : null;
  const line = settle(Infinity);
  return line.clear ? line : null;
}

// ---- A flow drawn ----

const flowN = (v) => Math.round(v * 10) / 10;

// A flow laid out (flowPlace), as an SVG in the panel's colours (its classes take the panel's tokens), every word
// escaped; `words` is what VoiceOver reads for it. `drop` is how far below a line's middle its baseline sits, measured
// for the words in a box and an edge's (half their capitals' height), so each box's lines sit in its middle.
function flowSVG(L, words, drop = { words: flowRoughDrop(L.size), edge: flowRoughDrop(L.size) }) {
  const pad = 4;
  const text = (lines, cx, cy, cls, below) => `<text class="${cls}" x="${flowN(cx)}" `
    + `y="${flowN(cy - (lines.length - 1) * L.lineH / 2 + below)}">`
    + lines.map((l, i) => `<tspan x="${flowN(cx)}"${i ? ` dy="${L.lineH}"` : ''}>${esc(l)}</tspan>`).join('') + '</text>';
  const shape = (n) => {
    if (n.shape === 'decision') {
      const k = 9;
      return `<polygon class="dg-node" points="${[[n.x + k, n.y], [n.x + n.w - k, n.y], [n.x + n.w, n.y + n.h / 2],
        [n.x + n.w - k, n.y + n.h], [n.x + k, n.y + n.h], [n.x, n.y + n.h / 2]].map((p) => p.map(flowN).join(','))
        .join(' ')}"/>`;
    }
    const r = n.shape === 'pill' ? n.h / 2 : n.shape === 'round' ? 10 : 5;
    return `<rect class="dg-node" x="${flowN(n.x)}" y="${flowN(n.y)}" width="${flowN(n.w)}" height="${flowN(n.h)}" `
      + `rx="${flowN(r)}"/>`;
  };
  // An end, at its tip, pointing its way: an arrow, a circle on the line's end, or a cross just short of the step.
  const end = (kind, [x, y], [dx, dy]) => {
    const p = (k, across) => `${flowN(x - dx * k - dy * across)},${flowN(y - dy * k + dx * across)}`;
    if (kind === 'arrow') return `<polygon class="dg-arrow" points="${p(0, 0)} ${p(6, 3.6)} ${p(6, -3.6)}"/>`;
    if (kind === 'circle') {
      return `<circle class="dg-arrow" cx="${flowN(x - dx * 3.5)}" cy="${flowN(y - dy * 3.5)}" r="3.5"/>`;
    }
    if (kind === 'cross') return `<path class="dg-cross" d="M${p(2, 3)} L${p(8, -3)} M${p(2, -3)} L${p(8, 3)}"/>`;
    return '';
  };
  const label = (e) => {
    if (!e.box) return '';
    const { x, y, w, h } = e.box;
    // Its ground is the panel's, with what the place it's in lays over the panel (a card's, a press's): the lines go
    // under its words.
    const box = `x="${flowN(x)}" y="${flowN(y)}" width="${flowN(w)}" height="${flowN(h)}" rx="4"`;
    return ['dg-under', 'dg-under over', 'dg-under over-press'].map((cls) => `<rect class="${cls}" ${box}/>`).join('')
      + text(e.lines, x + w / 2, y + h / 2, 'dg-edge-words', drop.edge);
  };
  const w = L.W - L.x0 + pad * 2, h = L.H - L.y0 + pad * 2;
  return `<svg class="dg-svg" viewBox="${L.x0 - pad} ${L.y0 - pad} ${w} ${h}" data-width="${w}" data-height="${h}" `
    + `role="img" aria-label="${esc(words)}">`
    + L.edges.map((e) => `<path class="dg-line${e.dotted ? ' dotted' : ''}${e.thick ? ' thick' : ''}" d="${e.d}"/>`
      + end(e.head, e.tip, e.way) + end(e.tail, e.foot, e.footWay)).join('')
    + L.edges.map(label).join('')
    + L.nodes.map((n) => shape(n) + text(n.lines, n.x + n.w / 2, n.y + n.h / 2, 'dg-words', drop.words)).join('')
    + '</svg>';
}

// A line's width, and how far below its middle its baseline sits, where nothing can measure them (the page's tests):
// the panel's words average about 0.53 of their size a character, and their capitals are about 0.7 of it high.
const flowRoughWidth = (size) => (words) => String(words).length * size * 0.53;
const flowRoughDrop = (size) => size * 0.35;
