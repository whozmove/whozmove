// The vine, a wait style (waits.js): while the session limit is reached, a vine grows in from the panel's bottom-left
// corner along its bottom edge, a leaf unfurling every so often, and opens a flower at the reset. Then its leaves
// fly off in a wave, and its stem pulls taut into the session's bar, fills it green and drains to nothing as usage
// starts over.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// Its shape and every frame of its reset are worked out here as plain numbers (vineShape, vineGrowth, vineFrame), so
// tests/panel.sh checks them: the stem's two ends start and land together, the drain carries on at the stem's speed,
// no leaf flies into the text lane, and the last frame is the normal strip.

// The stem, in the strip's coordinates (340 wide, VINE_HEIGHT tall, the panel's bottom-left corner at 0,84): cubic
// curves from just outside that corner, so it grows in through the corner's curve, along the bottom edge to the flower.
const VINE_HEIGHT = 84;
const VINE_CURVES = [
  [[-8, 92], [6, 78], [18, 70], [38, 68]],
  [[38, 68], [66, 66], [84, 76], [116, 72]],
  [[116, 72], [148, 68], [168, 58], [202, 64]],
  [[202, 64], [236, 70], [262, 76], [292, 66]],
  [[292, 66], [322, 56], [316, 56], [320, 54]],
];
const VINE_PATH = `M ${VINE_CURVES[0][0].join(' ')}`
  + VINE_CURVES.map(([, b, c, d]) => ` C ${b.join(' ')}, ${c.join(' ')}, ${d.join(' ')}`).join('');
// Where its eight leaves grow, as fractions of the stem inside the panel; each points 50° off the stem, alternately
// up and down. When the limit is over they fly off: up ones up and outward, down ones out past the bottom edge.
const VINE_LEAVES = [0.08, 0.19, 0.3, 0.41, 0.52, 0.63, 0.74, 0.85];
const VINE_FLIGHTS = [-125, 125, -100, 100, -75, 75, -55, 55];  // degrees; negative is up
const VINE_LANE = 32;  // the text lane's bottom edge, with room: nothing of the vine goes above it
const VINE_GREEN = 'var(--vine-green)', VINE_LEAF = 'var(--vine-leaf)', VINE_PETAL = 'var(--vine-petal)',
  VINE_HEART = 'var(--vine-heart)';

// The reset: Bloom 0-0.8s, Joy 0.7-1.77s (the leaves, in a wave from the flower back to the corner), Pull taut
// 1.1-2.1s (both ends on one curve: they start and land together, the stem straightening as it rises into the bar),
// Drain 2.1-2.75s (the bar's right end carrying on at the stem's speed), then the strip as it is (the percent in by
// 3.35s).
const VINE_RESET_MS = 3400;
const VINE_SHRINK = [1100, 1000], VINE_RISE = [1500, 600], VINE_DRAIN = [2100, 650];
// The shrink starts still and lands moving (its slope at the end, 0.6), so the right end can carry straight on.
const vineShrink = (p) => 0.7 * (3 * p * p - 2 * p * p * p) + 0.3 * p * p;
const VINE_SHRINK_END_SLOPE = 0.6;

let vineShapeKept = null;
// The stem as points evenly spaced along it (inside the panel only), its leaves, and its tip. Worked out once.
function vineShape() {
  if (vineShapeKept) return vineShapeKept;
  const dense = [];
  for (const [a, b, c, d] of VINE_CURVES)
    for (let i = dense.length ? 1 : 0; i <= 120; i++) {
      const u = i / 120, v = 1 - u;
      const at = (k) => v * v * v * a[k] + 3 * v * v * u * b[k] + 3 * v * u * u * c[k] + u * u * u * d[k];
      dense.push([at(0), at(1)]);
    }
  const lengths = [0];
  for (let i = 1; i < dense.length; i++)
    lengths.push(lengths[i - 1] + Math.hypot(dense[i][0] - dense[i - 1][0], dense[i][1] - dense[i - 1][1]));
  const total = lengths[lengths.length - 1];
  const pointAt = (s) => {
    let i = lengths.findIndex((l) => l >= s);
    if (i <= 0) return dense[Math.max(0, i)];
    const p = (s - lengths[i - 1]) / (lengths[i] - lengths[i - 1] || 1);
    return [lerp(dense[i - 1][0], dense[i][0], p), lerp(dense[i - 1][1], dense[i][1], p)];
  };
  // Where it comes into the panel: the corner's curve hides what's before.
  const start = lengths[dense.findIndex(([x, y]) => x >= 2 && y <= VINE_HEIGHT - 2)];
  const span = total - start, end = pointAt(total);
  const samples = Array.from({ length: 96 }, (_, i) => pointAt(start + span * i / 95));
  const leaves = VINE_LEAVES.map((f, j) => {
    const s = start + f * span, [x, y] = pointAt(s), [nx, ny] = pointAt(Math.min(total, s + 1));
    const angle = Math.atan2(ny - y, nx - x) * 180 / Math.PI + (j % 2 ? 50 : -50);
    const flight = VINE_FLIGHTS[j] * Math.PI / 180, up = Math.sin(flight) < 0;
    // An up leaf flies only as far as keeps it (and its tip) below the text lane; none lands on the flower.
    const reach = up ? Math.min(22, Math.max(8, (y - VINE_LANE - 14) / -Math.sin(flight))) : 22;
    let dx = Math.cos(flight) * reach;
    const dy = Math.sin(flight) * reach;
    if (Math.hypot(x + dx - end[0], y + dy - end[1]) < 20) dx = -dx;
    return { at: s, x, y, angle, dx, dy, lift: up ? 4 : 5, spin: (j % 2 ? 1 : -1) * (170 + 25 * j) };
  });
  vineShapeKept = { total, start, span, end, samples, leaves, pointAt };
  return vineShapeKept;
}

// The vine `progress` of the way through the wait: how much of the stem is drawn (`drawn`, along its length from the
// corner), how much of it is the thicker trunk, how many leaves are out, and where the bud is (null at either end).
function vineGrowth(progress) {
  const shape = vineShape(), drawn = shape.start + progress * shape.span;
  return {
    drawn, trunk: Math.min(drawn, shape.start + 0.22 * shape.span),
    leaves: shape.leaves.filter((l) => l.at <= drawn + 0.01).length,
    bud: progress > 0 && progress < 1 ? shape.pointAt(drawn) : null,
  };
}

// One leaf `t` ms into the reset: a squash, then off along its flight with a little toss, spinning, shrinking and
// fading. They go in a wave from the flower back to the corner, 60ms apart.
function vineLeafFrame(leaf, j, t) {
  const start = 700 + (7 - j) * 60;
  const resting = { x: leaf.x, y: leaf.y, angle: leaf.angle, scale: 1, opacity: 1 };
  if (t < start - 90) return resting;
  if (t < start) return { ...resting, scale: 1 - 0.15 * Math.sin(((t - start + 90) / 90) * Math.PI) };
  const p = clamp01((t - start) / 650), e = easeOut(p);
  return {
    x: leaf.x + leaf.dx * e, y: leaf.y + leaf.dy * e - leaf.lift * Math.sin(p * Math.PI),
    angle: leaf.angle + leaf.spin * e, scale: 1 - 0.45 * e, opacity: p < 0.55 ? 1 : 1 - (p - 0.55) / 0.45,
  };
}

// The flower `t` ms into the reset, at the stem's tip: it opens (overshooting a little), gives a happy bounce as the
// leaves go, then closes up, turns green and fades into the bar's end.
function vineFlowerFrame(t, tip) {
  let scale = 1, turn = 0, opacity = 1, closed = 0;
  if (t < 800) {
    const p = t / 800;
    scale = p < 0.7 ? 1.2 * easeOut(p / 0.7) : 1.2 - 0.2 * easeOut((p - 0.7) / 0.3);
    turn = -60 * (1 - easeOut(p));
  }
  if (t >= 700 && t < 1100) scale *= 1 + 0.18 * Math.sin(((t - 700) / 400) * Math.PI);
  if (t >= 1100) {
    closed = easeInOut(within(t, 1100, 700));
    scale = lerp(1, 0.3, closed);
    opacity = 1 - within(t, 1800, 250);
  }
  return { x: tip[0], y: tip[1], scale, turn, opacity, closed };
}

// Everything `t` ms into the reset, as numbers. `bar` is where the session's bar is in the normal strip ({x0, x1, y}:
// its ends and middle), and `heights` the strip's height while waiting and as it normally is.
function vineFrame(t, bar, heights) {
  const shape = vineShape(), x0 = bar.x0 + 2, x1 = bar.x1 - 2;  // the stem's round ends reach the bar's ends
  const frame = { stem: null, stemShown: t < VINE_DRAIN[0], stemWidth: 1.6, trunk: 1 };
  if (t >= VINE_SHRINK[0] && t < VINE_DRAIN[0]) {
    const p = within(t, ...VINE_SHRINK), kx = vineShrink(p), ky = easeInOut(p);
    const lineY = lerp(62, bar.y, easeInOut(within(t, ...VINE_RISE)));  // the line it straightens to, rising
    frame.stem = shape.samples.map(([x, y], i) => {
      const u = i / (shape.samples.length - 1);
      return [lerp(x, lerp(x0, x1, u), kx), lerp(y, lineY, ky)];
    });
    frame.stemWidth = lerp(1.6, 4, ky);
    frame.trunk = 1 - within(t, 1300, 300);
  } else if (t >= VINE_DRAIN[0]) frame.trunk = 0;
  const tip = frame.stem ? frame.stem[frame.stem.length - 1] : shape.end;
  frame.leaves = shape.leaves.map((leaf, j) => vineLeafFrame(leaf, j, t));
  frame.flower = t < 2050 ? vineFlowerFrame(t, tip) : null;
  // The strip's own parts: "Your move" and the week's figure at the right leave the session's line before the stem
  // rises into it (the bar reaches across where the figure was); the bar's track as the stem arrives on it, full and
  // green from the moment it lands, then draining at the speed the stem's right end landed with; the strip easing to
  // its normal height as the week row comes back; and the percent once the bar is empty.
  frame.message = t < 1600 ? fadeIn(t, 0, 700) : fadeOut(t, 1600, 250);
  frame.right = t < 1600 ? SHOWN : fadeOut(t, 1600, 250);
  frame.track = within(t, 1950, 150);
  const landSpeed = (shape.end[0] - x1) * VINE_SHRINK_END_SLOPE / VINE_SHRINK[1];  // px a ms, leftward
  const a = Math.max(0, Math.min(3, landSpeed * VINE_DRAIN[1] / (bar.x1 - bar.x0)));
  const drain = (p) => a * p + (3 - 2 * a) * p * p + (a - 2) * p * p * p;  // starts at that speed, stops still
  frame.fill = t < VINE_DRAIN[0] ? null
    : { width: clamp01(1 - drain(within(t, ...VINE_DRAIN))), green: t < VINE_DRAIN[0] + VINE_DRAIN[1] };
  frame.height = lerp(heights.wait, heights.normal, easeInOut(within(t, 2150, 500)));
  frame.week = t < 2300 ? GONE : fadeIn(t, 2300, 600);
  frame.weekFill = easeOut(within(t, 2400, 600));
  frame.percent = t < 2750 ? GONE : fadeIn(t, 2750, 600);
  return frame;
}

WAITS.vine = {
  height: VINE_HEIGHT,
  resetMs: VINE_RESET_MS,

  build(layer) {
    const shape = vineShape(), svg = 'http://www.w3.org/2000/svg';
    // Its colours are tokens.css's, which only a style takes, not an SVG's own fill and stroke.
    const make = (tag, attrs, parent = layer) => {
      const el = document.createElementNS(svg, tag);
      for (const [k, v] of Object.entries(attrs)) {
        if (k === 'fill' || k === 'stroke') el.style[k] = v;
        else el.setAttribute(k, v);
      }
      parent.appendChild(el);
      return el;
    };
    layer.replaceChildren();
    const curve = { d: VINE_PATH, fill: 'none', stroke: VINE_GREEN, 'stroke-linecap': 'round',
                    pathLength: shape.total };
    this.trunk = make('path', { ...curve, 'stroke-width': 2.6 });
    this.stem = make('path', { ...curve, 'stroke-width': 1.6, 'stroke-linejoin': 'round' });
    this.leaves = shape.leaves.map(() => {
      const g = make('g', {});
      const leaf = make('path', { d: 'M0 0 C 3 -4, 8 -4, 11 0 C 8 4, 3 4, 0 0 Z', fill: VINE_LEAF, opacity: 0.85 }, g);
      leaf.style.transform = 'scale(0)';
      return { g, leaf, out: false };
    });
    this.bud = make('circle', { r: 2.4, fill: VINE_GREEN, class: 'u-bud' });
    this.flower = make('g', { opacity: 0 });
    this.bloom = make('g', {}, this.flower);
    const petal = { cx: 0, cy: -4.6, rx: 2.8, ry: 4.4, fill: VINE_PETAL };
    this.petals = [0, 72, 144, 216, 288].map((turn) =>
      make('ellipse', { ...petal, transform: `rotate(${turn})` }, this.bloom));
    this.heart = make('circle', { r: 2.2, fill: VINE_HEART }, this.bloom);
    this.drawn = -1;
  },

  draw(progress, calm) {
    const shape = vineShape(), grown = vineGrowth(progress);
    this.stem.setAttribute('d', VINE_PATH);
    this.stem.style.strokeDasharray = `${shape.total}`;
    this.stem.style.strokeDashoffset = `${shape.total - grown.drawn}`;
    this.trunk.style.strokeDasharray = `${grown.trunk} ${shape.total}`;
    this.leaves.forEach((each, j) => {
      const leaf = shape.leaves[j], out = j < grown.leaves;
      each.g.style.transform = `translate(${leaf.x.toFixed(2)}px, ${leaf.y.toFixed(2)}px)`
        + ` rotate(${leaf.angle.toFixed(1)}deg)`;
      each.g.style.opacity = '';
      // A leaf coming out unfurls, unless it came out before the strip was there to see it.
      if (out && !each.out && this.drawn >= 0 && !calm)
        each.leaf.animate([{ transform: 'scale(0) rotate(-30deg)' },
                           { transform: 'scale(1.15) rotate(4deg)', offset: 0.7 },
                           { transform: 'scale(1) rotate(0deg)' }],
                          { duration: 700, easing: 'cubic-bezier(.2, .8, .2, 1)' });
      each.leaf.style.transform = out ? 'scale(1)' : 'scale(0)';
      each.out = out;
    });
    this.bud.style.display = grown.bud ? '' : 'none';
    if (grown.bud) {
      this.bud.setAttribute('cx', grown.bud[0].toFixed(2));
      this.bud.setAttribute('cy', grown.bud[1].toFixed(2));
    }
    this.bud.classList.toggle('still', !!calm);
    this.flower.setAttribute('opacity', 0);
    this.drawn = progress;
  },

  resetFrame(t, stage) {
    const f = vineFrame(t, stage.bar, stage.heights);
    this.stem.style.display = f.stemShown ? '' : 'none';
    this.stem.style.strokeDasharray = 'none';
    this.stem.style.strokeDashoffset = '0';
    this.stem.setAttribute('d', f.stem ? 'M' + f.stem.map(([x, y]) => `${x.toFixed(2)} ${y.toFixed(2)}`).join(' L')
                                       : VINE_PATH);
    this.stem.setAttribute('stroke-width', f.stemWidth.toFixed(2));
    this.trunk.style.strokeDasharray = `${vineShape().start + 0.22 * vineShape().span} ${vineShape().total}`;
    this.trunk.style.opacity = f.trunk.toFixed(3);
    this.bud.style.display = 'none';
    this.leaves.forEach((each, j) => {
      const l = f.leaves[j];
      each.g.style.transform = `translate(${l.x.toFixed(2)}px, ${l.y.toFixed(2)}px) rotate(${l.angle.toFixed(1)}deg)`
        + ` scale(${l.scale.toFixed(3)})`;
      each.g.style.opacity = l.opacity.toFixed(3);
      each.leaf.style.transform = 'scale(1)';
    });
    if (f.flower) {
      const fl = f.flower;
      this.flower.setAttribute('opacity', fl.opacity.toFixed(3));
      this.flower.setAttribute('transform', `translate(${fl.x.toFixed(2)}, ${fl.y.toFixed(2)})`);
      this.bloom.style.transform = `scale(${fl.scale.toFixed(3)}) rotate(${fl.turn.toFixed(1)}deg)`;
      const petal = mixColour(VINE_PETAL, VINE_GREEN, fl.closed), heart = mixColour(VINE_HEART, VINE_GREEN, fl.closed);
      this.petals.forEach((p) => { p.style.fill = petal; });
      this.heart.style.fill = heart;
    } else this.flower.setAttribute('opacity', 0);
    applyFade(stage.message, f.message);
    applyFade(stage.right, f.right);
    stage.track.style.opacity = f.track.toFixed(3);
    if (f.fill) {
      stage.fill.style.width = `${(f.fill.width * 100).toFixed(2)}%`;
      stage.fill.style.background = f.fill.green ? VINE_GREEN : '';
    } else stage.fill.style.width = '0%';
    stage.strip.style.height = `${f.height.toFixed(2)}px`;
    applyFade(stage.week, f.week);
    stage.weekFill.style.width = `${(stage.weekUsed * f.weekFill).toFixed(2)}%`;
    applyFade(stage.percent, f.percent);
  },

  clear() {
    this.leaves = [];
  },
};

// A colour part of the way from one colour to another, as the panel's look has them.
function mixColour(from, to, p) {
  return `color-mix(in srgb, ${to} ${(clamp01(p) * 100).toFixed(1)}%, ${from})`;
}
