// What the page's tests share: stand-ins for what the page touches when it loads, the page's scripts loaded in the
// order it loads them (passed after --), and a few helpers for printing what's checked. tests/panel.sh and each
// module's page test load it first.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// Stand-ins for what the page touches when it loads.
var window = this;
const element = () => ({
  addEventListener() {}, style: {}, dataset: {}, hidden: true,
  classList: { add() {}, remove() {}, toggle() {}, contains() { return false; } },
  querySelector() { return null; }, querySelectorAll() { return []; },
});
var document = {
  body: element(), getElementById: element, addEventListener() {}, activeElement: null,
  querySelector: element, querySelectorAll() { return []; },
};
var matchMedia = () => ({ matches: true });
var performance = { now: () => 0 };
var requestAnimationFrame = () => {};
var addEventListener = () => {};  // the window's own, as a module's start-up listens for its size

arguments.forEach((file) => load(file));  // the page's scripts, in the order the page loads them

// A fixed "now", so every time reads the same on every run.
const NOW = 2e12;
const min = (n) => NOW - n * 60000;
const show = (name, value) => print(`${name}: ${typeof value === 'string' ? value : JSON.stringify(value)}`);
const section = (title) => print(`\n== ${title}`);
const session = (fields) => Object.assign({
  sessionId: 's', name: 'demo', cwd: '/work/app', status: 'idle', statusUpdatedAt: min(60), entrypoint: 'cli',
  pid: 100, git: { branch: 'main', root: '/work/app' }, prs: [], agent: {},
}, fields);
