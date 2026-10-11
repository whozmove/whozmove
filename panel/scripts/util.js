// Small helpers the panel's scripts share.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// Text made safe to put inside HTML.
const HTML_ENTITIES = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => HTML_ENTITIES[c]);

// The last part of a path: "/work/app" -> "app".
const base = (p) => (p || '').split('/').filter(Boolean).pop() || p || '';

// A message to the app (handled in AppDelegate.m's page:said:).
const native = (msg) => window.webkit?.messageHandlers?.panel?.postMessage(msg);

// What the page keeps across launches, in its local storage: `d` when there's nothing kept, or it can't be read.
const store = {
  get(k, d) { try { const v = localStorage.getItem(k); return v === null ? d : JSON.parse(v); } catch { return d; } },
  set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch {} },
};

// The list is rebuilt every second, which restarts any CSS animation in it: a jump once a second. Starting each
// animation partway in, at the point a never-restarted one would have reached, keeps it seamless across rebuilds:
// a negative delay of (now mod period).
const phase = (periodMs) => `animation-delay:-${Math.round(performance.now() % periodMs)}ms`;

// "427k", "1M".
const kTokens = (n) => n >= 1e6 ? (n / 1e6).toFixed(n % 1e6 ? 1 : 0) + 'M' : Math.round(n / 1000) + 'k';
