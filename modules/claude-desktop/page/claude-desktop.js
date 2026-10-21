// Claude Desktop's part of the page: how a row of one of its conversations is named, and its scratch conversations'
// group. "Switch model?" is the commands module's (switch-model.js).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// The folders Claude Desktop makes for conversations started with no folder of yours: they share one group, Scratch,
// which has no folder to start a new conversation in.
const SCRATCH_DIR = '/Library/Application Support/Claude/scratch-workspaces/';

core.hosts.push({
  holds: (s) => s.entrypoint === 'claude-desktop',
  name: 'Claude Desktop', openNow: 'Open in Claude now', inName: ' in Claude',
  closedTip: () => 'Not running: click to open it in Claude',
  project: (s) => ((s.cwd || '').includes(SCRATCH_DIR) ? { key: 'scratch', name: 'Scratch', scratch: true } : null),
});
