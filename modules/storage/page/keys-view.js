// Keys, Storage's third tab: each key once, most urgent first: those that have left this Mac or are about to (Do now),
// then those only on it (When you can). A key says what it is, where it is in one sentence, and whether it looks real,
// with its best fix and a ⌄ beside it for the rest, which the app shows as a menu (keysMenu). Show Where folds out its
// places, a file's copies and commits said together, each with what to do there: open the file at its line, open the
// conversation, or show the file in Finder. Moving a file to the Trash is only for a file that's nothing but the key,
// only from the ⌄ menu, and asked once on the file's line (keysAsk). The keys most likely made up for a test aren't
// counted, and wait folded at the foot; under them, the keys marked replaced or not a key, folded, each with Undo.
// Under the list, what the look couldn't look in and the way to it, or what the last press said. The app looks by
// itself and tells the page what it found (setKeys); map-view.js shows it on its tab. Drawn from the panel's dot, caps
// labels, buttons and notices.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// Moving a file to the Trash being asked ({id, place, file, at}: the key, its place, that place's file, and when it was
// asked), what the last press said ({id, why}), the keys whose places are shown, and whether the keys most likely made
// up and those put away are shown.
const keysPage = { confirm: null, said: null, open: [], samplesOpen: false, putAwayOpen: false };

// What Keys reads, said where the list is, so it's plain from the first time it's opened.
const KEYS_READS = 'Keys looks by itself, once a day, in your projects and their commits, in what AI tools keep of '
  + 'your conversations, in your shell history and in who can read your credential files. Nothing leaves this Mac, '
  + 'and no key is kept whole: only how it starts and its last 4 characters.';

// The two groups a counted key is in, with what's true of all the keys in it beside each; and each band's dot, as a
// row's: your move's colour, red for what can't wait, and the hollow ring of what's done with.
const KEYS_BANDS = [
  { id: 'now', title: 'Do now', says: (keys) => (keys.every((key) => key.left)
    ? 'It has left this Mac: make a new one where it came from'
    : keys.some((key) => key.left) ? 'It has left this Mac, or is about to'
      : 'About to leave this Mac: take it out before you push') },
  { id: 'soon', title: 'When you can', says: (keys) => (keys.some((key) => key.left)
    ? 'Only on this Mac, or no longer works' : 'Only on this Mac') },
];
const KEYS_DOT = { now: 'needs', soon: 'turn', sample: 'idle closed' };

const keysOn = () => mapReading() && mapPage.view === 'keys';
const keysKey = (id) => state.keys?.keys?.find((key) => key.id === id);

// Beside the tabs: how far the disk's measuring has got, while it's measured, as on the other two tabs; else how far
// Keys has got, with a bar; else when it looked, and Look Again.
function keysStatusHTML() {
  const k = state.keys;
  if (state.storage?.scanning) return mapMeasuredHTML();
  if (k?.looking) {
    const so = k.soFar || {}, read = so.read || 0, of = so.of || 0;
    const found = read ? ` · ${so.found === 1 ? '1 key' : `${keysNumber(so.found || 0)} keys`} so far` : '';
    return `<span class="map-measured">Read ${read} of ${of} places${found}</span>${of
      ? `<span class="bar map-progress"><i style="width: ${((read / of) * 100).toFixed(1)}%"></i></span>` : ''}`;
  }
  if (!k?.lookedAt) return '';
  return `<span class="map-measured">Looked ${storageAgo(k.lookedAt, Date.now())}</span>`
    + '<button class="button quiet map-again" data-keys-look="1">Look Again</button>';
}

// A key's fix and ⌄ for the rest, as one button cut in two: the main one for a key that has left, a quiet one for a
// key most likely made up.
function keysFixHTML(key) {
  const ways = key.ways || [], band = keysBand(key);
  if (!ways.length) return '';
  const kind = band === 'now' ? 'button main' : band === 'sample' ? 'button quiet' : 'button';
  const more = ways.length > 1 ? `<button class="${kind}" data-keys-more="${esc(key.id)}" title="More">`
    + `${CHEVRON_ICON}</button>` : '';
  return `<span class="split-button${band === 'now' ? ' main' : ''}"><button class="${kind}" `
    + `data-keys-fix="${esc(key.id)}">${esc(ways[0].title)}</button>${more}</span>`;
}

// What a place's line offers, the first it can do: its file at the line, its conversation, or its file in Finder.
const KEYS_PLACE_WAYS = [['open', 'Open at the Line'], ['conversation', 'Open the Conversation'],
                         ['reveal', 'Show in Finder']];

// One of a key's spots (a file with its copies and commits, or another place) on a line of its own: where it is and
// what's there, then what to do there, else in a few words what to do about it; while moving its file to the Trash is
// asked, the question in that button's place.
function keysSpotHTML(key, spot) {
  const place = spot.place, index = spot.index;
  const asked = keysPage.confirm?.id === key.id && keysPage.confirm.file === (place.file ?? null);
  const name = place.file ? place.file.split('/').pop() : '';
  const way = KEYS_PLACE_WAYS.find(([action]) => (place.can || []).includes(action));
  const end = asked ? `<span class="tray-ask"><b>Move ${esc(name)} to the Trash?</b></span>`
    + '<button class="button" data-keys-cancel="1">Cancel</button>'
    + '<button class="button main" data-keys-yes="1">Confirm</button>'
    : way ? `<button class="button quiet" data-keys-place="${esc(key.id)}" data-place="${index}" `
      + `data-action="${way[0]}">${way[1]}</button>`
      : place.keep ? `<small>${esc(place.keep)}</small>` : '';
  const says = keysSpotSays(spot);
  const at = keysAtIsPath(spot) ? `<code>${esc(spot.at)}</code>` : esc(spot.at);
  return `<span class="keys-place"><i>${at}${says ? ` · ${esc(says)}` : ''}</i>${end}</span>`;
}

// A key: its dot, what it is and how it starts and ends, what it's set as or for, where it is, whether it looks real,
// Show Where (its places,
// once shown), and its fix.
function keysKeyHTML(key) {
  const open = keysPage.open.includes(key.id), [real, why] = keysReal(key, Date.now());
  // A credential file's is its path, which the sentence under it says.
  const masked = key.masked && key.rule !== 'readable' ? `<span class="keys-masked">${esc(key.masked)}</span>` : '';
  const named = keysNamed(key) ? `<span class="keys-named">${esc(keysNamed(key))}</span>` : '';
  const places = open ? `<span class="keys-places">${keysSpots(key).map((spot) => keysSpotHTML(key, spot)).join('')}`
    + '</span>' : '';
  return `<div class="keys-key ${KEYS_DOT[keysBand(key)]}"><span class="dot still"></span>`
    + `<span class="keys-words"><span class="keys-name"><b>${esc(key.name)}</b>${masked}${named}</span>`
    + `<span class="keys-where">${esc(keysWhere(key))}</span>`
    + `<span class="keys-real ${esc(key.real || 'file')}"><b>${esc(real)}</b> · ${esc(why)}</span>`
    + `<button class="button quiet keys-show" data-keys-show="${esc(key.id)}">${open ? 'Hide Where' : 'Show Where'}`
    + `</button>${places}</span><span class="keys-fix">${keysFixHTML(key)}</span></div>`;
}

// The keys most likely made up for a test, or ids, at the foot: folded to a line that says how many, until shown.
function keysSamplesHTML(samples) {
  if (!samples.length) return '';
  if (!keysPage.samplesOpen) {
    return `<div class="notice boxed keys-foot"><span class="notice-text">${esc(keysFoldedSays(samples))}</span>`
      + '<button class="button small" data-keys-samples="1">Show</button></div>';
  }
  return '<section class="keys-group"><div class="keys-group-head"><span class="caps">Probably not keys</span>'
    + '<i>Not counted</i><button class="button quiet" data-keys-samples="1">Hide</button></div>'
    + `${samples.map(keysKeyHTML).join('')}</section>`;
}

// The keys marked replaced or not a key, at the foot: folded to their count until pressed, then each with what was
// done and Undo.
function keysPutAwayHTML(away) {
  if (!away?.length) return '';
  const row = (key) => {
    const masked = key.masked ? `<span class="keys-masked">${esc(key.masked)}</span>` : '';
    const done = key.put === 'replaced' ? 'Marked replaced' : 'Marked not a key';
    return `<div class="keys-key idle closed"><span class="dot still"></span><span class="keys-words">`
      + `<span class="keys-name"><b>${esc(key.name)}</b>${masked}</span><span class="keys-where">${done}</span></span>`
      + `<span class="keys-fix"><button class="button quiet" data-keys-undo="${esc(key.id)}">Undo</button></span>`
      + '</div>';
  };
  const many = away.length === 1 ? '1 key' : `${away.length} keys`;
  return '<section class="keys-group"><div class="keys-group-head keys-put" data-keys-put="1" role="button" '
    + `aria-expanded="${keysPage.putAwayOpen}"><span class="caps">Marked replaced or not a key</span>`
    + `<i>${many} · ${keysPage.putAwayOpen ? 'Press to fold' : 'Press to see them'}</i></div>`
    + `${keysPage.putAwayOpen ? away.map(row).join('') : ''}</section>`;
}

// How many keys there are to deal with, and how soon: those to replace now, and how many more are only on this Mac.
function keysLedeHTML(counted) {
  const now = counted.filter((key) => keysBand(key) === 'now'), soon = counted.length - now.length;
  const many = (n) => (n === 1 ? '1 key' : `${n} keys`), left = now.some((key) => key.left);
  if (now.length) {
    return `<div class="clean-lede"><b>${many(now.length)} ${keysToDo(now)}</b><span>${soon
      ? `${soon} more can wait.` : left ? 'Make a new one where each came from, then mark it replaced.'
      : 'Take each out of its commit before you push.'}</span></div>`;
  }
  return `<div class="clean-lede"><b>${many(soon)} to tidy up</b><span>${counted.some((key) => key.left)
    ? 'None needs replacing now.' : 'None has left this Mac.'}</span></div>`;
}

// The tab: how many, and how soon; then each group, most urgent first; then the samples, what's put away, and what
// Keys reads. Before its first look, that it looks a moment after Whozmove opens. While it looks, the keys it has found
// so far, each as it's found (how far it has got is beside the tabs).
function keysBodyHTML() {
  const k = state.keys;
  if (k?.stopped) return `<p class="map-empty">Keys couldn’t look. ${esc(k.stopped)}.</p>`;
  if (!k?.lookedAt && !k?.looking) {
    return `<p class="map-empty">Keys looks a moment after Whozmove opens. ${KEYS_READS}</p>`;
  }
  const counted = keysCounted(k), samples = (k.keys || []).filter((key) => keysBand(key) === 'sample');
  const foot = `${keysSamplesHTML(samples)}${keysPutAwayHTML(k.putAway)}`;
  if (!counted.length) {
    return `<div class="keys"><p class="map-empty">${k.looking ? 'None found so far. Each key shows here as it’s '
      + 'found.' : 'No keys left where they shouldn’t be.'} ${KEYS_READS}</p>${foot}</div>`;
  }
  const groups = KEYS_BANDS.map((band) => [band, counted.filter((key) => keysBand(key) === band.id)])
    .filter(([, keys]) => keys.length).map(([band, keys]) => '<section class="keys-group"><div class="keys-group-head">'
      + `<span class="caps">${band.title}</span><i>${band.says(keys)}</i></div>${keys.map(keysKeyHTML).join('')}`
      + '</section>');
  return `<div class="keys">${keysLedeHTML(counted)}${groups.join('')}${foot}<p class="keys-reads">${KEYS_READS}</p>`
    + '</div>';
}

// Under the list, one thing at a time: what the last press said; the way to get Whozmove again when Keys couldn't
// look; Full Disk Access, for what it left out for want of it; Apple's developer tools, for the projects; what it
// couldn't finish; or a project it looked at only in part.
function keysFootHTML() {
  const k = state.keys || {}, said = (text, button) => `<div class="tray"><span class="tray-said">${esc(text)}`
    + `</span>${button || ''}</div>`;
  if (keysPage.said) return said(keysPage.said.why);
  if (k.stopped && k.again) {
    return said(`${k.again.says}.`, `<button class="button main" data-keys-again="1">${esc(k.again.title)}</button>`);
  }
  const skipped = k.skipped || {};
  if (!k.access && (skipped.protected || skipped.downloads)) {
    return said(skipped.protected ? 'Downloads, and projects in Desktop and Documents, are looked in once Full Disk '
      + 'Access is allowed.' : 'Downloads is looked in once Full Disk Access is allowed.',
                '<button class="button" data-map-allow="1">Allow Full Disk Access</button>');
  }
  if (k.tools) {
    return said('Your projects are looked in once Apple’s developer tools are in.',
                '<button class="button" data-keys-tools="1">Install</button>');
  }
  if (k.problem) return said(`${k.problem}.`);
  if (skipped.most?.length) {
    return said(`Only the first 50,000 files of ${skipped.most.join(' and ')} were looked in.`);
  }
  return '<div class="tray"></div>';
}

core.pointerTargets.push('.keys-fix .button', '.keys-place .button', '.keys-show', '[data-keys-samples]', '.keys-put',
  '[data-keys-look]', '[data-keys-again]', '[data-keys-tools]');

// A press on a key names the file its place is about, so the app acts on that file and no other, even if a look has
// changed the list since it was drawn.
const keysFileOf = (key, place) => (place >= 0 ? key?.places?.[place]?.file : undefined) ?? null;

// ---- Presses ----

core.readerPresses.push(
  // The fix, done at once.
  ['[data-keys-fix]', (el) => {
    const key = keysKey(el.dataset.keysFix), way = key?.ways?.[0];
    if (!way) return;
    keysPage.said = null;
    native({ type: 'keysAction', id: key.id, action: way.action, place: way.place, file: keysFileOf(key, way.place) });
  }],
  // What a place's line offers, done at once.
  ['[data-keys-place]', (el) => {
    const key = keysKey(el.dataset.keysPlace), place = Number(el.dataset.place);
    if (!key) return;
    keysPage.said = null;
    native({ type: 'keysAction', id: key.id, action: el.dataset.action, place, file: keysFileOf(key, place) });
  }],
  ['[data-keys-undo]', (el) => {
    keysPage.said = null;
    native({ type: 'keysAction', id: el.dataset.keysUndo, action: 'undo' });
  }],
  ['[data-keys-show]', (el) => {
    const id = el.dataset.keysShow;
    keysPage.open = keysPage.open.includes(id) ? keysPage.open.filter((each) => each !== id) : [...keysPage.open, id];
    drawReader();
  }],
  ['[data-keys-samples]', () => {
    keysPage.samplesOpen = !keysPage.samplesOpen;
    drawReader();
  }],
  ['[data-keys-put]', () => {
    keysPage.putAwayOpen = !keysPage.putAwayOpen;
    drawReader();
  }],
  ['[data-keys-more]', (el) => {
    const r = el.getBoundingClientRect();
    native({ type: 'keysMenu', id: el.dataset.keysMore, x: r.left - 4, y: r.bottom + 4 });
  }],
  ['[data-keys-cancel]', () => { keysPage.confirm = null; drawReader(); }],
  ['[data-keys-yes]', () => {
    const ask = keysPage.confirm;
    if (!ask || Date.now() - ask.at < FRESH_MS) return;
    native({ type: 'keysAction', id: ask.id, action: 'trash', place: ask.place, file: ask.file });
    keysPage.confirm = null;
    drawReader();
  }],
  ['[data-keys-look]', () => {
    keysPage.said = null;
    native({ type: 'keysLook' });
  }],
  // Getting Whozmove again: a command copied says so; a page opened needs no word.
  ['[data-keys-again]', () => {
    keysPage.said = state.keys?.again?.title === 'Copy Command'
      ? { why: 'Copied. Paste it in your terminal and press Return, then open Whozmove again.' } : null;
    native({ type: 'keysAgain' });
    drawReader();
  }],
  ['[data-keys-tools]', () => {
    keysPage.said = { why: 'macOS asks whether to install them, in a window of its own. Keys looks again once '
      + 'they’re in.' };
    native({ type: 'install', action: 'tools' });
    drawReader();
  }],
);

// ---- What the app calls ----

// What Keys found, whether it's looking, and which keys the line was put away for: the line above the list says it,
// and the tab, while it's open. A question about a key that has gone goes with it.
window.setKeys = (found) => {
  // A new look's list: what the last press said is about the old one. A question about a file that's no longer the
  // key's goes.
  if (found?.lookedAt !== state.keys?.lookedAt) keysPage.said = null;
  state.keys = found;
  const ask = keysPage.confirm;
  if (ask && !keysKey(ask.id)?.places?.some((place) => (place.file ?? null) === ask.file)) keysPage.confirm = null;
  drawStorageLine();
  if (keysOn()) drawReader();
};

// Moving a file to the Trash, picked from the ⌄ menu, asked on the file's line: a press on Confirm that comes sooner
// after it than a press that's seen it (fresh.js's FRESH_MS) doesn't count, so a double click can't answer it. The time
// is kept with the question, not with the sessions' cards, which forget what isn't a session's.
window.keysAsk = (id, place, file) => {
  if (keysFileOf(keysKey(id), place) !== (file ?? null)) return;
  keysPage.said = null;
  // The question is asked on the file's own line, so its places are shown.
  if (!keysPage.open.includes(id)) keysPage.open = [...keysPage.open, id];
  keysPage.confirm = { id, place, file: file ?? null, at: Date.now() };
  if (keysOn()) drawReader();
};

// What a key's action did: nothing more to say when it went (the list comes again without it), else why it didn't.
window.keysActed = (id, why) => {
  keysPage.said = why ? { id, why } : null;
  if (keysOn()) drawReader();
};
