// Keys, Storage's third part: the keys left where they shouldn't be, as the app's look found them (app/KeyScan.m), as
// plain functions: how soon each needs you, how many count, what the line above the list says of them, whether each
// looks real, and where it is, in one sentence and place by place (keys-view.js draws them); and how long ago
// something was, as the map says it too. Checked by modules/storage/tests/page-cases.js.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

moduleState({ keys: null });  // what Keys last found, as the app told it (setKeys)

// The groups the app files a key under by its most exposed place whose key has left this Mac, or is about to: pushed,
// sent to Claude or another AI tool, or in a commit not pushed yet.
const KEYS_GONE = ['commit', 'pushed', 'claude', 'ai'];

// How soon a key needs you, as the app worked it out: now (it has left this Mac, or is about to), soon (it's only on
// this Mac), or not at all (sample: most likely made up for a test, which isn't counted). A key from a look before the
// app said so is placed by its group.
const keysBand = (key) => key.band || (key.sample ? 'sample' : KEYS_GONE.includes(key.group) ? 'now' : 'soon');

// The keys that count: all but those most likely made up for a test.
const keysCounted = (found) => (found?.keys || []).filter((key) => keysBand(key) !== 'sample');

// Where keys that have left are, in a few words each, most exposed first, as the line above the list says it: with
// an AI tool's makers, where it can't be called back, then on a remote, then in a commit not pushed yet.
const KEYS_WHERE = { claude: 'sent to Claude', ai: 'in other AI tools', pushed: 'pushed', commit: 'not pushed yet' };

// What's to do about the keys that have left this Mac or are about to, as the line above the list and the tab say it:
// replace them where they came from, or, when none has left yet, take them out before they're pushed.
const keysToDo = (now) => (now.some((key) => key.left) ? 'to replace now' : 'to take out before you push');

// What the line above the list says: only of the keys that have left this Mac or are about to, once there's one it
// hasn't been put away for; how many there are and what to do, then where; and the keys it speaks for (`ids`), which
// its × puts away, so a key it didn't speak for still brings it back once it leaves. Each line is short enough to read
// at a glance: two places at most, so with more it names the most exposed and says how many more are elsewhere (and
// should its words not fit the panel's width, they wrap, storage.css). Null when there's nothing to say.
function keysLineWords(found) {
  if (!found || found.stopped) return null;
  const now = keysCounted(found).filter((key) => keysBand(key) === 'now');
  if (!now.some((key) => !(found.closed || []).includes(key.id))) return null;
  const many = now.length, head = `${many === 1 ? 'A key' : `${many} keys`} ${keysToDo(now)}`;
  const where = Object.keys(KEYS_WHERE).map((group) => [KEYS_WHERE[group], now.filter((key) => key.group === group)
    .length]).filter(([, n]) => n);
  const other = many - where.reduce((sum, [, n]) => sum + n, 0);
  if (other) where.push(['elsewhere', other]);
  const said = where.length > 2 ? [where[0], ['more elsewhere', many - where[0][1]]] : where;
  return { head, sub: said.map(([words, n]) => `${n} ${words}`).join(' · '), ids: now.map((key) => key.id) };
}

// Whether a key looks real, and why, from what the app knows of it without asking anyone: [how real, why].
const KEYS_REAL = {
  sample: ['Probably made up', 'it’s only in tests’ and examples’ files'],
  said: ['Probably made up', 'the conversation it was in calls it made up'],
  made: ['Probably made up', 'an agent first wrote it in a conversation, and it’s nowhere else'],
  id: ['Probably not a key', 'it’s shaped like an id (a UUID), and nothing around it calls it a key'],
  test: ['Could be real', 'it’s only in tests’ files, but has its kind’s own shape'],
  shape: ['Looks real', 'it has its kind’s own shape'],
  kept: ['Looks real', 'it’s a file of sign-ins'],
  typed: ['Looks real', 'you typed it'],
  sent: ['Looks real', 'it was sent in a message'],
  file: ['Could be real', 'it looks like a key in a file'],
};
function keysReal(key, now) {
  if (key.real === 'ended') {
    return ['Probably no longer works', `it ran out ${storageAgo(key.ends, now)}, by the date written in it`];
  }
  return KEYS_REAL[key.real] || KEYS_REAL.file;
}

// What the foot says of the keys not counted, folded: samples made up for tests, those their conversation calls made
// up, ids, or a mix.
function keysFoldedSays(folded) {
  const n = folded.length, ids = folded.filter((key) => key.real === 'id').length;
  const said = folded.filter((key) => key.real === 'said').length;
  const byAgent = folded.filter((key) => key.real === 'made').length;
  const samples = n - ids;
  const one = n === 1;
  let made = one ? 'like a sample in a test or example file' : 'like samples in test or example files';
  if (said === samples) made = one ? 'made up, as its conversation says' : 'made up, as their conversations say';
  else if (byAgent === samples) made = one ? 'made up by an agent' : 'made up by agents';
  else if (said || byAgent) made = 'made up, for tests or by agents';
  if (!ids) {
    return one ? `1 more looks ${made}, so it isn’t counted.`
      : `${n} more look ${made}, so they aren’t counted.`;
  }
  if (ids === n) {
    return n === 1 ? '1 more looks like an id, not a key, so it isn’t counted.'
      : `${n} more look like ids, not keys, so they aren’t counted.`;
  }
  return `${n} more look ${made}, or like ids, so they aren’t counted.`;
}

// A number as people write it: 4,410.
const keysNumber = (n) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ',');

// A file's lines as said: line 12; lines 8, 9 and 31; 23 lines, from line 812 to line 4,410.
function keysLines(lines) {
  const sorted = [...new Set(lines)].sort((a, b) => a - b);
  if (sorted.length === 1) return `line ${keysNumber(sorted[0])}`;
  if (sorted.length <= 3) {
    const all = sorted.map(keysNumber);
    return `lines ${all.slice(0, -1).join(', ')} and ${all[all.length - 1]}`;
  }
  return `${sorted.length} lines, from line ${keysNumber(sorted[0])} to line ${keysNumber(sorted[sorted.length - 1])}`;
}
const keysOnLines = (lines) => (new Set(lines).size === 1 ? `on line ${keysNumber(lines[0])}`
  : `on ${keysNumber(new Set(lines).size)} lines`);

// A key's places, gathered where it's in the same file: each spot {place, index (its first place), what (a project's
// file, history, startup (your shell's settings), downloads, remote, or record), at (where, in a few words), lines,
// copies (which of a project's checkouts: main or a worktree's folder), unpushed and pushed (its commits)}, most
// exposed first.
function keysSpots(key) {
  const spots = [], byFile = new Map();
  (key.places || []).forEach((place, index) => {
    // A project's file, told apart by its shared git folder (two clones can share a name), and named by its project;
    // a remote's address, once for every copy of its project, as they share it.
    const file = place.inProject && !place.remote ? `${place.project}/${place.inProject}` : null;
    const same = file ? `${place.repo || place.project}/${place.inProject}`
      : place.remote ? `remote ${place.repo || place.project} ${place.remote}` : place.file;
    let spot = same && byFile.get(same);
    if (!spot) {
      const what = place.remote ? 'remote' : place.inProject ? 'project' : place.history ? 'history'
        : place.startup ? 'startup' : place.downloads ? 'downloads'
          : place.line && place.group === 'files' ? 'file' : 'record';
      const at = what === 'project' ? file : what === 'remote' ? `${place.project}’s remote ${place.remote}`
        : (place.where || '').split(' · ')[0].replace(/:\d+$/, '');
      spot = { place, index, what, at, lines: [], copies: [], unpushed: [], pushed: [] };
      spots.push(spot);
      if (same) byFile.set(same, spot);
    }
    // The line's place, what its press acts on: the main copy's, else the first.
    if (place.copy === 'main' && spot.place.copy !== 'main') Object.assign(spot, { place, index });
    if (place.line) spot.lines.push(place.line);
    if (place.copy && !spot.copies.includes(place.copy)) spot.copies.push(place.copy);
    if (place.commit) {
      const list = place.group === 'pushed' ? spot.pushed : spot.unpushed;
      if (!list.includes(place.commit)) list.push(place.commit);
    }
  });
  return spots;
}

// Which copies of a project a file is in, said after it: in main and 31 worktrees; in 2 worktrees; in its worktree
// done. Nothing for main alone.
function keysCopies(copies) {
  const main = copies.includes('main'), others = copies.filter((copy) => copy !== 'main');
  if (!others.length) return '';
  if (main) return ` in main and ${others.length === 1 ? 'a worktree' : `${others.length} worktrees`}`;
  return others.length === 1 ? ` in its worktree ${others[0]}` : ` in ${others.length} worktrees`;
}

// Its commits, said after it: and in a commit not pushed yet; and in 3 commits, 2 of them pushed.
function keysCommits(spot) {
  const on = spot.pushed.length, all = on + spot.unpushed.length;
  if (!all) return '';
  if (all === 1) return on ? ', and in a commit that’s pushed' : ', and in a commit not pushed yet';
  return `, and in ${all} commits${on === all ? ', all pushed' : on ? `, ${on} of them pushed` : ', not pushed yet'}`;
}

// Where a key is, in one sentence: its most exposed place, then how many more there are.
function keysWhere(key) {
  const spots = keysSpots(key), first = spots[0];
  if (!first) return '';
  const lines = first.lines.length ? keysOnLines(first.lines) : '';
  let said;
  if (key.rule === 'readable') said = `In ${key.masked}, which other accounts on this Mac can read`;
  else if (first.what === 'project') {
    const [project, ...path] = first.at.split('/');
    said = `In ${project}’s ${path.join('/')}${lines ? `, ${lines}` : ''},${keysCopies(first.copies)}`
      .replace(/,$/, '') + keysCommits(first);
  } else if (first.what === 'history') said = `In your shell history, ${lines}`;
  else if (first.what === 'startup') said = `In ${first.at}, your shell’s settings, ${lines}`;
  else if (first.what === 'downloads') said = `In ${first.at.split('/').pop()} in your Downloads, ${lines}`;
  else if (first.what === 'remote') said = `In the address of ${first.at}`;
  else if (first.what === 'file') said = `In ${first.at}, ${lines}`;
  else said = first.place.where || '';
  const more = spots.length - 1;
  // Only in a commit not pushed yet: it can still be kept from leaving.
  const unpushed = (key.places || []).length && key.places.every((place) => place.group === 'commit')
    ? ' Take it out of that commit before you push.' : '';
  return `${said}.${more ? ` And in ${more === 1 ? 'one more place' : `${more} more places`}.` : ''}${unpushed}`;
}

// What a key is for, where its line says it plainly: the name it's set as, or the host it's the password for or sent
// to, from the first of its places that says one; '' when none does.
function keysNamed(key) {
  const named = (key.places || []).find((place) => place.named)?.named;
  if (!named) return '';
  return named.as ? `set as ${named.as}` : named.for ? `for ${named.for}` : named.to ? `to ${named.to}` : '';
}

// Whether where a spot is is a path (a project's file, or one from your home folder or the disk's top), set in code
// type, or words (your message in a conversation, a project's remote), set as the rest of its line is.
const keysAtIsPath = (spot) => spot.what === 'project' || /^[~/]/.test(spot.at);

// What a spot's line says beside where it is: its lines, its copies, its commits.
function keysSpotSays(spot) {
  const parts = [];
  if (spot.lines.length) parts.push(keysLines(spot.lines));
  const copies = keysCopies(spot.copies).trim();
  if (copies) parts.push(copies);
  if (spot.unpushed.length) parts.push(`not pushed yet in ${spot.unpushed.join(', ')}`);
  if (spot.pushed.length) parts.push(`pushed in ${spot.pushed.join(', ')}`);
  return parts.join(' · ');
}

// How long ago something was, as the panel says it: just now, 4 min ago, an hour ago, 3 hours ago, a day ago, 4 days
// ago.
function storageAgo(at, now) {
  const minutes = Math.max(0, Math.round((now - at) / 60000));
  const hours = Math.round(minutes / 60), days = Math.round(minutes / 1440);
  return minutes < 1 ? 'just now' : minutes < 60 ? `${minutes} min ago` : minutes < 90 ? 'an hour ago'
    : hours < 36 ? `${hours} hours ago` : days < 2 ? 'a day ago' : `${days} days ago`;
}
