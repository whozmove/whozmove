// What a session changed: its row's numbers, the card that says how they sit among everyone's, and how the changes view
// groups files and lays out their lines.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// Plain functions: they take what they need and change nothing, so tests/panel.sh can check every case. The view
// shows what isn't committed yet, as git status does ("This session", "All sessions"), or what the commits not on
// GitHub yet changed ("commits", from the island's commits stage). Whose a line is comes from the app (Changes.m): a
// session's id; "outside" (no listed session's record has it: your own edits, a closed session's, what git brought
// in); or "short" (a short or repeated line with nothing around it to tell by). While a session in the checkout ran a
// shell command Claude Code didn't record (`complete` false), or a command's record left out a file's lines (that
// file's `complete` false), an "outside" line could be that command's, so it's named for no one: only its stage is
// said.

// Who a part of the changes is, in words, from a session's side: that session is "This session", another listed one
// goes by its name.
function whoName(who, sid, sessions, complete = true) {
  if (who === sid) return 'This session';
  if (who === 'outside') return complete ? 'Outside these sessions' : 'Other changes';
  if (who === 'short') return 'Short or repeated lines';
  const other = sessions.find((x) => x.sessionId === who);
  return other ? other.name || base(other.cwd) : 'Another session';
}

// The card's parts of what isn't committed in the checkout, from a session's side: that session first, then the others
// in the checkout, biggest first, then what was changed outside these sessions, and short or repeated lines. Each {who,
// name, added, removed}; with the whole's total and this session's share of it, in whole percent.
function branchParts(s, sessions) {
  // Not known: the checkout's total is all there is, with no one's part of it.
  if (s.changes?.known === false) {
    return { parts: [], total: { added: s.changes.added || 0, removed: s.changes.removed || 0 }, share: 0 };
  }
  const parts = s.changes?.parts || {};
  const complete = s.changes?.complete !== false;
  const all = Object.entries(parts).map(([who, [added, removed]]) => ({ who, name: whoName(who, s.sessionId, sessions,
                                                                                           complete),
                                                                         added, removed }));
  const rank = (p) => p.who === s.sessionId ? 0 : ({ outside: 2, short: 3 })[p.who] ?? 1;
  all.sort((a, b) => rank(a) - rank(b) || (b.added + b.removed) - (a.added + a.removed));
  const total = all.reduce((t, p) => ({ added: t.added + p.added, removed: t.removed + p.removed }),
                           { added: 0, removed: 0 });
  const mine = parts[s.sessionId] || [0, 0], size = total.added + total.removed;
  const share = size ? Math.round(100 * (mine[0] + mine[1]) / size) : 0;
  return { parts: all, total, share };
}

// The changes view's list, as groups of files, each [label, who (for its colour, or null), files]. A session's own:
// what isn't staged yet, then what's staged whole. Everyone's, and the commits': by whose they are, a file under the
// first of them to change it.
function changeGroups(view, sid, sessions) {
  const files = view?.files || [];
  if (view?.blind && view.scope === 'commits') return [['Not on GitHub yet', null, files]].filter((g) => g[2].length);
  if (view?.scope === 'session' || view?.blind) {
    return [['Not staged', null, files.filter((f) => !f.saved)], ['Staged', null, files.filter((f) => f.saved)]]
      .filter((g) => g[2].length);
  }
  const whos = [...new Set(files.flatMap((f) => Object.keys(f.counts || {})))];
  const rank = (w) => w === sid ? 0 : ({ outside: 2, short: 3 })[w] ?? 1;
  whos.sort((a, b) => rank(a) - rank(b));
  const groups = whos.map((w) => [whoName(w, sid, sessions, view.complete !== false), w, []]);
  // A file with no lines to count (a picture, a file only renamed, or one whose mode changed) is no one's.
  const lineless = ['No line changes', null, []];
  for (const f of files) {
    const first = whos.find((w) => f.counts?.[w]);
    (first ? groups.find((g) => g[1] === first) : lineless)[2].push(f);
  }
  return [...groups, lineless].filter((g) => g[2].length);
}

// The view of a session whose changes aren't known, as it's shown: no line is anyone's ("none"), so nothing says whose,
// only how far each part has got. `blind` marks it.
function blindView(view) {
  const files = (view.files || []).map((f) => {
    const all = Object.values(f.counts || {}).reduce((t, [a, d]) => [t[0] + a, t[1] + d], [0, 0]);
    // Each line keeps its stage, and the commit it's from.
    const hunks = (f.hunks || []).map((h) => ({ ...h, lines: h.lines.map((l) => l[0] === ' ' ? l
      : [l[0], l[1], 'none', ...l.slice(3)]) }));
    return { ...f, counts: { none: all }, hunks, complete: false };
  });
  return { ...view, files, complete: false, blind: true };
}

// A file's count as the view shows it: this session's lines in its own view, everyone's in the branch's.
function fileCount(f, sid, scope) {
  if (scope !== 'session') {
    return Object.values(f.counts || {}).reduce((t, [a, d]) => [t[0] + a, t[1] + d], [0, 0]);
  }
  return f.counts?.[sid] || [0, 0];
}

// The line under a file's name in the list. A session's own: how often it edited it and when, and whether someone
// else changed it too. The branch's: who changed it.
function fileLine(f, sid, scope, sessions, rowFile, now, complete = true) {
  if (f.counts?.none || !Object.keys(f.counts || {}).length) {
    return f.status === 'new' ? 'New' : f.status === 'gone' ? 'Deleted' : 'Changed';
  }
  if (scope !== 'session') {
    return Object.keys(f.counts || {}).map((w) => w === sid ? 'this session' : whoName(w, sid, sessions, complete))
      .join(', ');
  }
  const edits = rowFile?.edits || 0;
  const again = edits > 2 ? `, then edited ${edits - 1} times` : edits > 1 ? ', then edited once' : '';
  const what = f.status === 'gone' ? 'Deleted' : rowFile?.created ? 'Created' + again
    : edits > 1 ? `Edited ${edits} times` : 'Edited once';
  const when = rowFile?.at ? ' · ' + ago(now - rowFile.at) : '';
  // Shared, as the file's chip says: someone else's lines are in it too (a lone short line is no one's).
  const others = Object.keys(f.counts || {}).filter((w) => w !== sid && w !== 'short');
  return what + when + (others.length ? ' · shared' : '');
}

// A hunk's lines side by side: unchanged lines on both sides, and each run of taken-out lines beside the lines put in
// after it, row by row. Each row [left, right], a side being {line, at} (its line number there) or null.
function splitRows(hunk) {
  const rows = [];
  let old = hunk.oldStart, now = hunk.newStart, i = 0;
  const lines = hunk.lines;
  while (i < lines.length) {
    if (lines[i][0] === ' ') { rows.push([{ line: lines[i], at: old++ }, { line: lines[i], at: now++ }]); i++; continue; }
    const out = [], into = [];
    while (i < lines.length && lines[i][0] === '-') out.push(lines[i++]);
    while (i < lines.length && lines[i][0] === '+') into.push(lines[i++]);
    for (let j = 0; j < Math.max(out.length, into.length); j++)
      rows.push([j < out.length ? { line: out[j], at: old++ } : null, j < into.length ? { line: into[j], at: now++ } : null]);
  }
  return rows;
}

// How many unchanged lines lie between a hunk and the one before it (or the file's start), in the new file.
function linesBetween(prev, hunk) {
  if (!prev) return Math.max(0, hunk.newStart - 1);
  const end = prev.newStart + prev.lines.filter((l) => l[0] !== '-').length;
  return Math.max(0, hunk.newStart - end);
}

// The first line a file's changes are about, for opening it there: the first line its session (or, in the branch's
// view, anyone) put in, else where its first change is.
function firstChangedLine(f, sid, scope) {
  for (const h of f.hunks || []) {
    let at = h.newStart;
    for (const l of h.lines) {
      if (l[0] === '+' && (scope !== 'session' || l[2] === sid)) return at;
      if (l[0] !== '-') at++;
    }
  }
  return f.hunks?.[0]?.newStart || 1;
}
