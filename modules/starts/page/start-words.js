// What the new-conversation card reads in your words: `@` for the project it starts in, and `#` for where in it, its
// own folder, a worktree that's there, a branch with no folder yet, or a new worktree (`#name from branch`). And a new
// worktree's name, as the card makes it from your words and as you write it. Plain functions, checked by the module's
// page cases.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// Words that say nothing about the work, left out of a name made from your words.
const NAME_SKIPS = new Set(['a', 'an', 'the', 'to', 'of', 'for', 'in', 'on', 'at', 'and', 'or', 'with', 'from', 'by',
  'please', 'can', 'could', 'would', 'you', 'we', 'i', 'me', 'my', 'our', 'your', 'it', 'its', 'is', 'be', 'this',
  'that', 'so', 'just', 'some']);
const NAME_LONGEST = 40, NAME_MOST = 60;

// Letters as plain letters: é as e, and so on.
function plainLetters(text) {
  return String(text ?? '').normalize('NFKD').replace(/[̀-ͯ]/g, '');
}

// A name from your words: their first four words that say something, in lower case, joined by dashes, within 40
// characters ("Add a dark mode switch, please" makes add-dark-mode-switch). Anything but letters and digits goes. With
// nothing to go on, "new-work". An `@` or `#` and what follows it are where it starts, not what it does.
function worktreeName(words) {
  const said = String(words ?? '').replace(/(^|\s)[@#]\S*(\s+from\s+\S*)?/g, ' ');
  const all = plainLetters(said).toLowerCase().match(/[a-z0-9]+/g) || [];
  const kept = all.filter((word) => !NAME_SKIPS.has(word));
  let name = '';
  for (const word of (kept.length ? kept : all).slice(0, 4)) {
    const longer = name ? `${name}-${word}` : word;
    if (longer.length > NAME_LONGEST) break;
    name = longer;
  }
  return name || (kept[0] || all[0] || '').slice(0, NAME_LONGEST) || 'new-work';
}

// A name as you write it: spaces become dashes, and what a branch's name can't hold goes. That leaves letters, digits,
// dots, dashes and underscores, never two dots or two dashes in a row, starting with a letter or a digit, at most 60.
function cleanName(text) {
  return plainLetters(text).replace(/\s+/g, '-').replace(/[^A-Za-z0-9._-]/g, '').replace(/\.{2,}/g, '.')
    .replace(/-{2,}/g, '-').replace(/^[^A-Za-z0-9]+/, '').slice(0, NAME_MOST);
}

// A name once it's settled: cleaned, with no dot, dash or underscore left at its end, and never ending in ".lock",
// which git keeps for itself.
function trimName(text) {
  let name = cleanName(text).replace(/[._-]+$/, '');
  while (name.endsWith('.lock')) name = name.slice(0, -5).replace(/[._-]+$/, '');
  return name;
}

// The `@` or `#` being written, right before the caret, or null: { kind: '@' or '#', query, from (a `#name from
// branch`'s branch, as far as it's written; undefined without "from"), start, end }, where start and end are where it
// sits in the words, for taking it out once something is chosen.
function startToken(text, caret = String(text ?? '').length) {
  const before = String(text ?? '').slice(0, caret);
  const m = /(^|\s)(@|#)([\w./-]*)(?:\s+from\s+([\w./-]*))?$/.exec(before);
  if (!m) return null;
  if (m[2] === '@' && m[4] !== undefined) return null;
  return { kind: m[2], query: m[3], from: m[4], start: m.index + m[1].length, end: caret };
}

// The projects `@` offers, those whose name holds what's written after it, as many as the list shows.
function projectChoices(projects, query) {
  const q = String(query ?? '').toLowerCase();
  return projects.filter((p) => p.name.toLowerCase().includes(q)).slice(0, 8);
}

// What `#` offers in a repo (`repo`, as the app listed it: { here, worktrees, branches, base }), those holding what's
// written after it. Each choice is a target: the repo's own folder ({ kind: 'here' }), a worktree that's there
// ({ kind: 'open', branch, path, where }), a branch with no folder yet ({ kind: 'branch', name }), or a new worktree
// ({ kind: 'new', name, base }). A name that isn't there offers a new worktree by that name (else one named from your
// words), from the repo's base branch; with "from", it's a new worktree from each branch that holds what follows.
function worktreeChoices(repo, query, from, words) {
  const q = String(query ?? '');
  const name = q ? trimName(q) : worktreeName(words);
  const all = [repo.here?.branch, ...repo.worktrees.map((w) => w.branch), ...repo.branches].filter(Boolean);
  if (from !== undefined) {
    return all.filter((b) => b.includes(from)).slice(0, 8).map((b) => ({ kind: 'new', name, base: b }));
  }
  const out = [];
  if (repo.here?.branch?.includes(q) || !q) out.push({ kind: 'here', branch: repo.here?.branch || null });
  for (const w of repo.worktrees) if (w.branch.includes(q)) out.push({ kind: 'open', branch: w.branch, path: w.path, where: w.where });
  for (const b of repo.branches) if (b.includes(q)) out.push({ kind: 'branch', name: b });
  if (name && !all.includes(name)) out.push({ kind: 'new', name, base: repo.base });
  return out.slice(0, 8);
}

// Whether a target is a worktree, one that's there or one to make: any of them starts in the terminal.
function inWorktree(target) {
  return !!target && target.kind !== 'here';
}
