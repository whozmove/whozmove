// What every card and button on the list goes by: whether it has only just been shown, and a request answered here.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// A press on something that has only just appeared doesn't count: it may have taken the place of what was being
// pressed, and it hasn't been seen yet. state.shownAt holds when each was first shown, by a key the module that draws
// it picks (a request's id, 'compact:<session>', …).
const FRESH_MS = 800;
function justShown(id) { return Date.now() - (state.shownAt[id] || 0) < FRESH_MS; }
// The session or request a first-shown time is kept for: its key less the prefix a module names it with
// (core.forgotten.prefixes).
function shownFor(key) {
  return key.replace(new RegExp(`^(${core.forgotten.prefixes.join('|')}):`), '').replace(/:.*$/, '');
}
// Everything on a session's row counts as only just shown again: the row is back in view after its copy held on at the
// list's edge (sticky.js), and what came on it meanwhile hasn't been seen.
function showAgain(s) {
  const ids = new Set([s.sessionId, s.ask?.id].filter(Boolean)), now = Date.now();
  for (const key of Object.keys(state.shownAt)) if (ids.has(shownFor(key))) state.shownAt[key] = now;
}

// A request answered from the page folds away at once, and comes back after 5s if it's still waiting.
function answered(id, how) { state.answering[id] = how; state.answeredAt[id] = Date.now(); }
function folded(id) { return state.answering[id] && Date.now() - state.answeredAt[id] < 5000; }
