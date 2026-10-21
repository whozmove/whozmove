// What isn't committed in a row's checkout, as git shows it: the row's numbers, the card they show, and how the changes
// view lists files and lays out their lines.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// Plain functions: they take what they need and change nothing, so tests/panel.sh can check every case. The view has
// git status's own tabs: Changes (what `git diff` shows, then the files git doesn't track yet), Staged (`git diff
// --cached`) and Outgoing (the commits not on GitHub yet, one by one). A file staged and then changed again is in both
// of the first two, as git status lists it.

// The view's tabs, in order: their scope (as the app's views are named) and their name.
const CHANGE_TABS = [['unstaged', 'Changes'], ['staged', 'Staged'], ['outgoing', 'Outgoing']];

const filesWord = (n) => `${thousands(n)} ${n === 1 ? 'file' : 'files'}`;
const commitsWord = (n) => `${thousands(n)} ${n === 1 ? 'commit' : 'commits'}`;

// A file's letter in the list, as git status and VS Code mark it, with its colour: U a file git doesn't track yet, A
// added, D deleted, R renamed, M changed.
function gitLetter(f) {
  if (f.untracked) return ['new', 'U'];
  if (f.status === 'new') return ['new', 'A'];
  if (f.status === 'gone') return ['gone', 'D'];
  if (f.status === 'renamed') return ['changed', 'R'];
  return ['changed', 'M'];
}

// A file's lines put in and taken out, [added, removed]: counted from its lines, or, for one sent without them (cut
// short in a long view), as the app counted them.
function fileCount(f) {
  if (f.cut) return [f.added || 0, f.removed || 0];
  let added = 0, removed = 0;
  for (const h of f.hunks || []) {
    for (const l of h.lines) {
      if (l[0] === '+') added++;
      else if (l[0] === '-') removed++;
    }
  }
  return [added, removed];
}

// Where else git lists a file, said under its name and on its head: a file git doesn't track yet, one with staged
// changes as well (in Changes), and one changed again since it was staged (in Staged).
function fileNote(f, scope) {
  if (scope === 'unstaged') return f.untracked ? 'Untracked' : f.alsoStaged ? 'Also staged' : '';
  if (scope === 'staged') return f.alsoUnstaged ? 'Also in Changes' : '';
  return '';
}

// The view's files in its order, each with the key the list and the view find it by: its path; in Outgoing, its
// commit's too (a file can be in more than one), with the commit it's from.
function viewFiles(view) {
  if (view?.scope === 'outgoing') {
    return (view.commits || []).flatMap((k) => (k.files || []).map((f) => ({ ...f, key: `${k.hash}:${f.path}`,
                                                                           commit: k })));
  }
  return (view?.files || []).map((f) => ({ ...f, key: f.path }));
}

// What the view's head says under the session's name, in git's words: how many files aren't staged or are, or how far
// the branch is ahead of its copy on GitHub ("Ahead of origin/main by 2 commits"), or that it was never published.
// `all` is the row's count of what isn't committed (the app's), `view` Outgoing's view once it's come.
function changesSub(scope, all, view) {
  if (scope === 'unstaged') return `${filesWord(all?.unstaged?.files || 0)} not staged`;
  if (scope === 'staged') return `${filesWord(all?.staged?.files || 0)} staged`;
  if (!view || view.missing) return 'Commits not on GitHub yet';
  const n = (view.commits?.length || 0) + (view.more || 0);
  if (!n) return view.upstream ? `Up to date with ${view.upstream}` : 'No commits to publish';
  return view.upstream ? `Ahead of ${view.upstream} by ${commitsWord(n)}` : `Not published: ${commitsWord(n)}`;
}

// What an empty tab says, as git status would.
function emptyWords(scope) {
  return { unstaged: 'No changes.', staged: 'Nothing staged.', outgoing: 'No commits to push.' }[scope];
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

// The line a file opens at in your editor: the first line put in, else where its first change is.
function firstChangedLine(f) {
  for (const h of f.hunks || []) {
    let at = h.newStart;
    for (const l of h.lines) {
      if (l[0] === '+') return at;
      if (l[0] !== '-') at++;
    }
  }
  return f.hunks?.[0]?.newStart || 1;
}
