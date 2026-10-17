// Claude Desktop's part of the page: how a row of one of its conversations is named, its scratch conversations' group,
// and "Switch model?" (switch-model.js).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// The folders Claude Desktop makes for conversations started with no folder of yours: they share one group, Scratch,
// which has no folder to start a new conversation in.
const SCRATCH_DIR = '/Library/Application Support/Claude/scratch-workspaces/';

core.hosts.push({
  holds: (s) => s.entrypoint === 'claude-desktop',
  name: 'Claude Desktop', icon: DESKTOP_ICON, openNow: 'Open in Claude now', inName: ' in Claude',
  // Claude's log says which conversation it shows a second or so after a click, so a click here marks it at once.
  marksOpenAtOnce: true,
  project: (s) => ((s.cwd || '').includes(SCRATCH_DIR) ? { key: 'scratch', name: 'Scratch', scratch: true } : null),
});
