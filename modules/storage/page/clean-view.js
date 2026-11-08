// Clean up, Storage's first tab: what comes back on its own, in groups, each item ticked or not (or what keeps it,
// with an app to open where that's the way forward), with the command a tool's own runs shown under it; and under
// them, how many are ticked and Clean Up with how much, which asks once. The app works out the list from the map and
// what the tools say (showCleanUp): before the first map, from the usual places it measures first, each project's built
// files joining at the list's foot once the map is done. It cleans what's ticked, each found and checked again
// (storageCleaned). map-view.js shows it on its tab.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

moduleState({ cleanUp: null });  // the list, as the app last sent it
// What's ticked, the items shown before, whether Clean Up is asking, whether it's cleaning now, what the last clean-up
// said (in green when all of it went) and whether projects' built files were listed by then, each row's step as the
// app told it while cleaning and how many were ticked, the next look while a tool can't say yet, whether the press
// that opened Storage turned it on (it says so, with Turn Off, until Storage closes), and what went, kept on the list
// saying so ({id: {item, step}}), with the list as it was when Clean Up was pressed (`order`), each in its place, until
// Clean up closes or the disk is measured again.
const cleanPage = { ticked: new Set(), seen: new Set(), confirm: false, askedAt: 0, cleaning: false, said: null,
                    allWent: false, hadProjects: false, steps: {}, count: 0, again: null, turnedOn: false, went: {},
                    order: null };
// While a tool can't say what it can free yet (Docker starting), the list is asked for again this often, in ms.
const CLEAN_AGAIN_MS = 5000;

// ---- Drawing ----

// A row: its tick, its name and where it is, or what keeps it; and its size, or, while it cleans and after, its step
// there, one that's going in the panel's working shine, and one that stayed saying why and what to do in place of
// where it is. While it cleans, the rows being cleaned keep their tick, with nothing to press, and the rest rest, as a
// locked row does; one that went shows no box, as there's nothing left to tick, its room kept so its words stay put.
function cleanRowHTML(item) {
  const went = cleanPage.went[item.id];
  const mark = `<span class="tickbox${went ? ' went' : ''}" aria-hidden="true"></span>`;
  const step = cleanPage.steps[item.id] || went?.step, said = step ? cleanStepWords(step) : null;
  const command = item.command && !item.lock ? `<code class="clean-command">${esc(item.command)}</code>` : '';
  const open = item.lock && item.open ? `<button class="button clean-open" data-clean-open="${esc(item.open.app)}">`
    + `Open ${esc(item.open.name)}</button>` : '';
  const press = item.lock || went ? '' : cleanPage.cleaning ? (step ? ' aria-checked="true"' : '')
    : ` data-clean-tick="${esc(item.id)}" role="checkbox" aria-checked="${cleanPage.ticked.has(item.id)}"`;
  const resting = cleanPage.cleaning && !step && !item.lock ? ' resting' : '';
  const line = said?.line || (item.lock ? item.lock.says : item.where);
  const size = !said ? (item.size ? mapSize(item.size) : '')
    : ['moving', 'running'].includes(step.state) ? shineHTML(said.word) : esc(said.word);
  return `<div class="clean-row${item.lock ? ' locked' : ''}${resting}${step ? ` ${step.state}` : ''}"${press}>${mark}`
    + `<span class="clean-words"><b>${esc(item.name)}</b><i>${esc(line)}</i>${command}${open}</span>`
    + `<span class="clean-size">${size}</span></div>`;
}

// That Storage just turned on, at the press that opened it, with what it keeps, and Turn Off right there.
const cleanOnHTML = () => (cleanPage.turnedOn ? '<div class="notice boxed clean-on"><span class="notice-text">Storage '
  + 'is on: it keeps a map of your disk’s sizes on this Mac, never what’s in your files.</span>'
  + '<button class="button small" data-storage-off="1">Turn Off</button></div>' : '');

// The tab: each group, with what it adds up to; before the list comes, that it's looking; and while the map is still
// measured, that projects' built files join the list at its foot. Nothing in the usual places: the map, for the rest.
function cleanBodyHTML() {
  const list = state.cleanUp;
  if (!list) return `${cleanOnHTML()}<p class="map-empty">Looking at the usual places…</p>`;
  const later = list.usual ? '<p class="clean-later">Your projects’ built files are added once your disk is '
    + 'measured.</p>' : '';
  const groups = cleanShownGroups(list, cleanPage.order, cleanPage.went).map((group) => {
    const size = group.items.reduce((sum, item) => sum + (item.lock || cleanPage.went[item.id] ? 0 : item.size || 0),
                                    0);
    return `<section class="clean-group"><div class="clean-group-head"><span class="clean-group-words">`
      + `<b class="caps">${esc(group.title)}</b><i>${esc(group.says)}</i></span>`
      + `<span class="clean-size">${size ? mapSize(size) : ''}</span>`
      + `</div>${group.items.map(cleanRowHTML).join('')}</section>`;
  }).join('');
  if (!groups) {
    return `${cleanOnHTML()}${list.tools ? mapToolsHTML() : ''}<p class="map-empty">Nothing to clean in `
      + `${list.usual ? 'the usual places' : 'what comes back on its own'}. The map shows what’s using the rest.</p>`
      + `<p class="map-empty"><button class="button" data-map-view="map">Open the Map</button></p>${later}`;
  }
  // Worktrees you're done with are found with git, which waits for Apple's developer tools (the map's notice).
  return `<div class="clean">${cleanOnHTML()}<div class="clean-lede"><span>Space you can get back. Each of these comes `
    + `back by itself when it’s needed.</span></div>${list.tools ? mapToolsHTML() : ''}${groups}${later}</div>`;
}

// Under it: how many are ticked and Clean Up with how much, there but off until something's ticked; Clean Up's
// question; or what the last clean-up said, while it's cleaning too, and how much projects' built files add, if they
// came since.
function cleanFootHTML() {
  const list = state.cleanUp;
  const off = (said, done) => `<div class="tray"><span class="tray-said${done ? ' done' : ''}">${esc(said)}</span>`
    + '<button class="button main" disabled>Clean Up</button></div>';
  if (!list) return off('');
  const sums = cleanSums(list, cleanPage.ticked);
  if (cleanPage.cleaning) {
    return `<div class="tray"><span class="tray-said">${esc(`${cleanGoing(cleanPage.steps)}. You can close Storage: `
      + 'what it did shows here when you come back.')}</span></div>`;
  }
  if (!sums.ticked) {
    const more = cleanPage.said && !cleanPage.hadProjects ? cleanProjectsMore(list) : '';
    const hint = sums.all ? 'Tick what you want gone.' : '';
    return off(cleanPage.said ? `${cleanPage.said}${more}` : hint, cleanPage.allWent);
  }
  if (cleanPage.confirm) {
    const parts = [], runs = sums.commands.length;
    if (sums.trash) parts.push(`${sums.trash === 1 ? 'One goes' : `${sums.trash} of them go`} to the Trash`);
    if (runs) parts.push(`${runs === 1 ? 'one runs' : `${runs} run`} a tool’s own command, as shown`);
    return `<div class="tray"><span class="tray-ask"><b>Clean up ${mapSize(sums.ticked)}?</b>`
      + `<i>${esc(parts.join(', and ').replace(/^./, (c) => c.toUpperCase()))}. Nothing an agent is working in is `
      + 'touched.</i></span>'
      + '<button class="button" data-clean-cancel="1">Cancel</button>'
      + '<button class="button main" data-clean-yes="1">Confirm</button></div>';
  }
  const ticked = cleanPage.ticked.size;
  return `<div class="tray"><span class="tray-said">${ticked === 1 ? '1 ticked' : `${ticked} ticked`}</span>`
    + `<button class="button main" data-clean-go="1">Clean Up ${mapSize(sums.ticked)}</button></div>`;
}

// How much projects' built files add, once they've joined the list since a clean-up: " Your projects' built files:
// 8 GB more."
function cleanProjectsMore(list) {
  const projects = (list.groups || []).find((group) => group.id === 'projects');
  const size = (projects?.items || []).reduce((sum, item) => sum + (item.lock ? 0 : item.size || 0), 0);
  return size ? ` Your projects’ built files: ${mapSize(size)} more.` : '';
}

// The list asked for again: as the tab opens, once the disk's been measured anew, when agents start or stop work, and
// every few seconds while a tool can't say yet.
function cleanAsk() {
  clearTimeout(cleanPage.again);
  cleanPage.again = null;
  native({ type: 'storageCleanUp' });
}

core.pointerTargets.push('.clean-row[data-clean-tick]', '[data-storage-off]', '.map-empty [data-map-view]');

// ---- Presses ----

core.readerPresses.push(
  ['[data-clean-open]', (el) => native({ type: 'storageOpen', app: el.dataset.cleanOpen })],
  // Turn Off, where Storage said it turned on: the map closes, and what it knew goes.
  ['[data-storage-off]', () => {
    cleanPage.turnedOn = false;
    native({ type: 'storageOff' });
  }],
  ['[data-clean-tick]', (el) => {
    const id = el.dataset.cleanTick;
    if (cleanPage.ticked.has(id)) cleanPage.ticked.delete(id);
    else cleanPage.ticked.add(id);
    Object.assign(cleanPage, { confirm: false, said: null, allWent: false, steps: {} });
    drawReader();
  }],
  // The question comes where Clean Up was: a press on it that comes sooner after it than a press that's seen it
  // (fresh.js's FRESH_MS) doesn't count, so a double click can't answer it. Its time is kept here, not with the
  // sessions' cards, which forget what isn't a session's.
  ['[data-clean-go]', () => {
    cleanPage.confirm = true;
    cleanPage.askedAt = Date.now();
    drawReader();
  }],
  ['[data-clean-cancel]', () => { cleanPage.confirm = false; drawReader(); }],
  ['[data-clean-yes]', () => {
    if (Date.now() - cleanPage.askedAt < FRESH_MS) return;
    // What's ticked, and the map the list was worked out from, so nothing goes if it's been measured again since.
    native({ type: 'storageClean', ids: [...cleanPage.ticked], measuredAt: state.cleanUp?.scannedAt || 0 });
    // Each ticked row waits until the app says it's going; the rows keep their places until it's done.
    const steps = Object.fromEntries([...cleanPage.ticked].map((id) => [id, { id, state: 'waiting' }]));
    Object.assign(cleanPage, { ticked: new Set(), confirm: false, cleaning: true, said: null, allWent: false,
                               hadProjects: !state.cleanUp?.usual, steps, count: cleanPage.ticked.size,
                               order: state.cleanUp, went: {} });
    drawReader();
  }],
);

// ---- What the app calls ----

// The list: what you'd ticked stays ticked while it's still there, and what's new comes ticked or not as it says. From
// another measure, Clean Up's question is put away, as what it asked about has changed. While a tool can't say yet,
// it's asked for again in a few seconds, as long as the tab is open.
window.showCleanUp = (list) => {
  if (list?.scannedAt !== state.cleanUp?.scannedAt) Object.assign(cleanPage, { confirm: false, went: {}, order: null });
  // What went to the Trash or was cleaned, gone from the new list, stays on it, saying so.
  else {
    const now = new Set(cleanItems(list).map((item) => item.id));
    for (const item of cleanItems(state.cleanUp)) {
      const step = cleanPage.steps[item.id];
      if (step && ['trashed', 'done'].includes(step.state) && !now.has(item.id)) cleanPage.went[item.id] = { item, step };
    }
  }
  state.cleanUp = list;
  cleanPage.ticked = cleanTicks(list, cleanPage.ticked, cleanPage.seen);
  cleanPage.seen = new Set(cleanItems(list).map((item) => item.id));
  clearTimeout(cleanPage.again);
  cleanPage.again = cleanItems(list).some((item) => item.waits)
    ? setTimeout(() => { if (mapReading() && mapPage.view === 'clean') cleanAsk(); }, CLEAN_AGAIN_MS) : null;
  if (mapReading()) drawReader();
};

// A row's step as the app cleans it: going to the Trash, in it, its tool's command running, done, or stayed and why.
window.cleanProgress = (step) => {
  if (!step?.id || !cleanPage.cleaning) return;
  cleanPage.steps[step.id] = step;
  if (mapReading() && mapPage.view === 'clean') drawReader();
};

// What cleaning did: how many went and how many stayed, and where the space is, kept until it's been seen, the map
// closed or not; the rows that stayed go on saying why until the next press. The app sends the list again after it,
// and the folder the map shows is asked for again, as what went has left it.
window.storageCleaned = (result) => {
  Object.assign(cleanPage, { cleaning: false, said: cleanSaid(result, cleanPage.count),
                             allWent: !(result.failed || []).length && !!result.freed });
  if (!mapReading()) return;
  if (state.map) mapAskAgain();
  drawReader();
};
