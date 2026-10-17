// What a Claude Code session's details mean: its model's name, its permission mode's, its context window and where
// auto-compact starts. The parts of the page that show them (the row's setup line, the Compact card, "Switch model?")
// ask through core.agent, so they never depend on which agent it is.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// Plain functions: they take what they need and change nothing, so tests/panel.sh can check every case.

const MODE_NAMES = {
  default: 'Ask', acceptEdits: 'Edits', plan: 'Plan', auto: 'Auto', bypassPermissions: 'Bypass', dontAsk: "Don't ask",
};

// "claude-opus-5-5" -> "Opus 5.5"; "claude-sonnet-5-5[1m]" -> "Sonnet 5.5".
function modelName(id) {
  const m = /claude-([a-z]+)-(\d+)(?:-(\d{1,2}))?(?!\d)/.exec(id || '');
  return m ? `${m[1][0].toUpperCase()}${m[1].slice(1)} ${m[2]}${m[3] ? '.' + m[3] : ''}` : (id || '');
}

// The context window: 1M for Opus and Fable 5.x and "[1m]" models, else 200k. A session using more than 200k
// can only have the larger window, so it gets 1M too.
function contextWindow(model, tokens) {
  const large = /\[1m\]/.test(model) || /claude-(opus|fable)-5/.test(model) || tokens > 200000;
  return large ? 1000000 : 200000;
}

// Where auto-compact starts: your own setting (/autocompact), else about 967k with a 1M window (Claude Code's
// default), else the end of the window.
const AUTO_COMPACT_1M = 967000;
function compactLimit(a) {
  const window = contextWindow(a.model, a.tokens);
  return a.compactWindow > 0 ? Math.min(a.compactWindow, window) : window >= 1e6 ? AUTO_COMPACT_1M : window;
}

Object.assign(core.agent, { modelName, modeName: (mode) => MODE_NAMES[mode] || mode, contextWindow, compactLimit });
