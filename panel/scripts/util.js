// Small helpers the panel's scripts share.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// Text made safe to put inside HTML.
const HTML_ENTITIES = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => HTML_ENTITIES[c]);

// The last part of a path: "/work/app" -> "app".
const base = (p) => (p || '').split('/').filter(Boolean).pop() || p || '';

// A message to the app (each type is answered by the module that names it; app/core/Modules.m routes it).
const native = (msg) => window.webkit?.messageHandlers?.panel?.postMessage(msg);

// A switch's track and knob (styles/controls.css), inside what's pressed, whose aria-checked says whether it's on:
// Spotify's lyrics, and the apps' settings on the panel's back.
const SWITCH = '<span class="switch"><i></i></span>';

// What the page keeps across launches, in its local storage: `d` when there's nothing kept, or it can't be read.
const store = {
  get(k, d) { try { const v = localStorage.getItem(k); return v === null ? d : JSON.parse(v); } catch { return d; } },
  set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch {} },
};

// The list is rebuilt every second, which restarts any CSS animation in it: a jump once a second. Starting each
// animation partway in, at the point a never-restarted one would have reached, keeps it seamless across rebuilds:
// a negative delay of (now mod period).
const phase = (periodMs) => `animation-delay:-${Math.round(performance.now() % periodMs)}ms`;

// The colours a gauge goes through as it fills: a session's context ring (commands.js) and the usage strip's bars
// (usage.js). Red-orange is the limit, as it's what blocks you. Each is tokens.css's, so it follows the panel's look.
const GAUGE = { normal: 'var(--level-normal)', warning: 'var(--level-warning)', limit: 'var(--level-limit)' };

// A colour of tokens.css's as the panel's look has it now, for what can't take a var(): an animation's keyframes.
const tokenColour = (name) => getComputedStyle(document.documentElement).getPropertyValue(name).trim();

// "427k", "1M".
const kTokens = (n) => n >= 1e6 ? (n / 1e6).toFixed(n % 1e6 ? 1 : 0) + 'M' : Math.round(n / 1000) + 'k';

// "1,493".
const thousands = (n) => Math.round(n || 0).toLocaleString('en-US');

// How wide a text is in an element's font (the usage card is laid out from its words). From the font's own parts:
// WebKit leaves the `font` shorthand empty when it can't say it in one (tabular figures), and a canvas given that keeps
// its default, a smaller 10px sans-serif.
let textCanvas;
function textWidth(el, text) {
  textCanvas ??= document.createElement('canvas').getContext('2d');
  const cs = getComputedStyle(el);
  textCanvas.font = `${cs.fontStyle} ${cs.fontWeight} ${cs.fontSize} ${cs.fontFamily}`;
  return textCanvas.measureText(text).width;
}
