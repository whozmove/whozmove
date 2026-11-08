// The build of Whozmove running now, as the header names it in Show Build in Header (Working on Whozmove ▸ in the
// pawn menu, while ⌥ is held), from what build.sh recorded in it (setRunningBuild).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// Plain functions: they take what they need and change nothing, so tests/panel.sh can check every case.

// A build's name: its worktree, else its branch, else the commit it was built from, else its folder.
function buildLabel(b) {
  return b.worktree || b.branch || (b.detached && 'detached @' + b.detached) || base(b.root) || 'build';
}

// The header's name for the running build: "fix-hover · 2m ago".
function headerBuild(running, now) {
  const t = ago(now - (running.builtAt || now));
  return `${buildLabel(running)} · ${t === 'now' ? 'just now' : t + ' ago'}`;
}
