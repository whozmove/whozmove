// The map of your disk, as plain functions (map-view.js draws it): sizes in words, the rings round the folder you're
// in, each piece's colour, finding a part, what's collected for the Trash, and a step in or out with the piece that
// moves and its shape on the way. Checked by modules/storage/tests/page-cases.js.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// A size as people read it, in the units Finder uses, as the app says it (DiskSize in app/Disk.m): 18 GB, 4.4 GB,
// 820 MB, 12 KB.
function mapSize(bytes) {
  const gb = bytes / 1e9;
  if (gb >= 9.95) return `${Math.round(gb)} GB`;
  if (gb >= 0.995) return `${Math.round(gb * 10) / 10} GB`;
  const mb = bytes / 1e6;
  if (mb >= 0.995) return `${Math.round(mb)} MB`;
  return bytes > 0 ? `${Math.max(1, Math.round(bytes / 1e3))} KB` : '0 KB';
}

// How far a measure has got, against what's in use on the disk (`disk`, as the app says it: {total, free}): "142 of
// 476 GB", the unit said once when both are in it, and the share measured, for the bar; or, before the disk is known,
// "142 GB so far" and no bar. Once it's done, the map says when it was measured instead.
function mapProgress(counted, disk) {
  const used = disk ? disk.total - disk.free : 0;
  if (!(used > 0)) return { words: `${mapSize(counted)} so far`, share: null };
  const [part, partUnit] = mapSize(Math.min(counted, used)).split(' '), whole = mapSize(used);
  return { words: `${part}${whole.endsWith(` ${partUnit}`) ? '' : ` ${partUnit}`} of ${whole}`,
           share: Math.min(1, counted / used) };
}

// The rings: the middle, then three rings round it, each this deep; and the drawing's size.
const MAP_MIDDLE = 54, MAP_RING = 36, MAP_DEPTH = 3, MAP_BOX = 2 * (MAP_MIDDLE + MAP_DEPTH * MAP_RING + 4);

// Each piece of the rings round the folder you're in (as the app sends it: its parts, and theirs, three levels down):
// what it is, its ring, where it starts and ends going round (0 at the top, clockwise), its colour, and the folders
// between it and the middle (`within`, by id). Each folder round the middle has a colour of its own, which what's
// inside it takes; where one folder fills most of the middle, what's in it takes colours of its own too, so its parts
// can be told apart. Anything narrower than about a degree isn't drawn, nor what has no size (a folder it can't look
// inside).
function mapArcs(view) {
  const out = [];
  (function walk(parts, whole, depth, a0, a1, hue, wide, within) {
    if (depth > MAP_DEPTH || !parts || !(whole > 0)) return;
    let a = a0, index = 0;
    for (const part of parts) {
      const span = (a1 - a0) * Math.max(0, part.size) / whole;
      const h = depth === 1 ? index % 6 : depth === 2 && wide ? (hue + index + 1) % 6 : hue;
      if (!part.rest) index++;
      if (span >= 0.016) {
        out.push({ part, depth, a0: a, a1: a + span, hue: h, within });
        walk(part.kids, part.size, depth + 1, a, a + span, h, depth === 1 ? part.size > whole / 2 : wide,
             [...within, part.id]);
      }
      a += span;
    }
  })(view && view.kids, view && view.size, 1, 0, Math.PI * 2, 0, false, []);
  return out;
}

// One piece of a ring as an SVG path, from angle a0 to a1, between radii r0 and r1, with a hair's gap.
function mapArcPath(a0, a1, r0, r1) {
  const c = MAP_BOX / 2, gap = Math.min(1 / r1, (a1 - a0) / 3);
  const s = a0 + gap / 2 - Math.PI / 2, e = Math.min(a1 - gap / 2, a0 + Math.PI * 2 - 0.002) - Math.PI / 2;
  const p = (r, a) => `${(c + r * Math.cos(a)).toFixed(2)} ${(c + r * Math.sin(a)).toFixed(2)}`;
  const large = e - s > Math.PI ? 1 : 0;
  return `M${p(r1, s)}A${r1} ${r1} 0 ${large} 1 ${p(r1, e)}L${p(r0, e)}A${r0} ${r0} 0 ${large} 0 ${p(r0, s)}Z`;
}

// A ring's inner and outer radius, the first round the middle.
function mapRadii(depth) {
  return [MAP_MIDDLE + (depth - 1) * MAP_RING + 1, MAP_MIDDLE + depth * MAP_RING - 1];
}

// Whether the folder now shown, `view`, is a step in or out from the one shown before, `was`, so the map moves a piece
// rather than fading (map-view.js's mapGrow): in, a folder drawn on the old rings, up to three rings out, with that
// piece; out, a folder whose rings hold the old one, up to three rings in, with the old one's piece on the new rings;
// as { arc, down } with the piece as mapArcs gives it, or null for anything else (the same folder again, another
// branch, a piece too small to draw).
function mapStep(was, view) {
  if (!was || !view || was.id === view.id) return null;
  const down = mapArcs(was).find((a) => a.part.id === view.id);
  if (down) return { arc: down, down: true };
  const up = mapArcs(view).find((a) => a.part.id === was.id);
  return up ? { arc: up, down: false } : null;
}

// A piece of the rings on its way into the middle as its folder opens (map-view.js's mapGrow), `t` from 0 (the piece,
// as mapArcs gives it) to 1 (the middle): it widens round the middle from its own centre until it goes all the way
// round, as its inner edge closes in and its outer edge comes to the middle's, so at every moment it's a piece of a
// ring, with no seam and nothing turning inside out. Going up, the same shape from 1 back to 0. An SVG path.
function mapGrowPath(arc, t) {
  const [r0, r1] = mapRadii(arc.depth), mid = (arc.a0 + arc.a1) / 2, whole = Math.PI * 2;
  const span = (arc.a1 - arc.a0) + (whole - (arc.a1 - arc.a0)) * t;
  const inner = Number((r0 * (1 - t)).toFixed(2)), outer = Number((r1 + (MAP_MIDDLE - 3 - r1) * t).toFixed(2));
  if (span < whole - 0.01) return mapArcPath(mid - span / 2, mid + span / 2, inner, outer);
  // All the way round: a ring, its hole closing, or the whole middle.
  const c = MAP_BOX / 2;
  const round = (r, way) => {
    const at = (x) => x.toFixed(2), arc = `A${at(r)} ${at(r)} 0 1 ${way}`;
    return `M${at(c - r)} ${c}${arc} ${at(c + r)} ${c}${arc} ${at(c - r)} ${c}Z`;
  };
  return round(outer, 1) + (inner > 0.5 ? round(inner, 0) : '');
}

// What a piece is drawn in: grey for what can't go, or isn't one thing; else its folder's colour, softer further out,
// and softest for small items counted together.
function mapTint(arc) {
  if (arc.part.grey) return 'grey';
  return `h${arc.hue} d${arc.depth}${arc.part.rest ? ' rest' : ''}`;
}

// The part with this id among `parts` and what's inside them, at any depth, or null. A file has no kids to look in.
function mapFind(parts, id) {
  for (const part of parts || []) {
    if (part.id === id) return part;
    const inside = mapFind(part.kids, id);
    if (inside) return inside;
  }
  return null;
}

// The parts on the way from the folder shown to one inside it, that part last, or null when it isn't there: the
// crumbs a folder further in shows as it opens.
function mapTrail(parts, id) {
  for (const part of parts || []) {
    if (part.id === id) return [part];
    const inside = mapTrail(part.kids, id);
    if (inside) return [part, ...inside];
  }
  return null;
}

// What's collected for the Trash is a list of parts, each with the folders it's in (`within`: their ids, the disk
// first) and what was taken back out of it (`out`, each part with its own `within`).

// The collected part that holds the part with this id: the part itself, or a folder it's in, unless it, or a folder
// between, was taken back out. Null when it isn't collected.
function mapHolder(tray, id, within) {
  const chain = [...within, id];
  return tray.find((t) => {
    const at = chain.indexOf(t.id);
    return at >= 0 && !chain.slice(at + 1).some((c) => t.out.some((o) => o.id === c));
  }) || null;
}

// What's collected once `item`, a part of the folder shown, is pressed. Collected itself, it's put back; collected as
// part of a folder, it's taken out of that folder, which keeps the rest; taken out before, it goes back in; else it's
// collected, and takes in anything collected inside it.
function mapToggle(tray, item, within) {
  const holder = mapHolder(tray, item.id, within);
  if (holder?.id === item.id) return tray.filter((t) => t !== holder);
  const inside = (t) => t.within.includes(item.id);
  if (holder) {
    return tray.map((t) => (t !== holder ? t : { ...t, out: [...t.out.filter((o) => !inside(o)),
                                                              { ...item, within }] }));
  }
  const left = tray.find((t) => t.out.some((o) => o.id === item.id));
  if (left) {
    return tray.filter((t) => !inside(t)).map((t) => (t !== left ? t
      : { ...t, out: t.out.filter((o) => o.id !== item.id) }));
  }
  return [...tray.filter((t) => !inside(t)), { ...item, within, out: [] }];
}

// How much a collected part frees: all of it but what was taken back out.
const mapFrees = (t) => t.size - t.out.reduce((sum, o) => sum + o.size, 0);
