// The line under the header when this Mac's disk is running low: what it says is worked out by the app (app/Disk.m), as
// it's told to the page (setDisk). Pressed, it opens Clean up beside the list, turning Storage on first if it's off
// (the press is the yes); its × puts it away until the disk is fuller still, or a day has passed. Once a measure you
// were waiting for is done, and the map isn't open, the line says the map is ready instead, until you open it or put
// the line away. When Keys has found keys left where they shouldn't be, it says how many and where, and opens Keys; its
// × puts it away until another key is found. One line at a time: the disk nearly out, then keys, then the disk low,
// then the map ready.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

const GO_ICON = '<svg viewBox="0 0 10 10" aria-hidden="true"><path d="M3.6 2 6.6 5l-3 3" fill="none" '
  + 'stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"></path></svg>';

moduleState({ disk: null });  // what the app last said of the disk
// The line's place is the dock under the header (panel.html's #dock), which the header and the panel's height make room
// for: it's put there as it comes in, and taken out once it has gone, so the header slides with the list only while it
// isn't there. It goes first, above a new conversation's card. Made the first time it shows; while it folds away, what's
// said next waits for it to have gone, then comes in.
const diskLine = { el: null, going: false, next: null };

function diskLineEl() {
  if (diskLine.el) return diskLine.el;
  const el = diskLine.el = Object.assign(document.createElement('div'), { id: 'diskline' });
  el.addEventListener('mousedown', diskLinePressed);
  return el;
}

// The line: its mark, what's left (and how soon it's full), and what a press leads to, or why it matters once it's
// nearly out; then its ×. Null when it doesn't show.
function diskLineHTML(disk) {
  if (!disk || !disk.show || !disk.head) return null;
  const tone = disk.tone === 'severe' ? ' severe' : '';
  return `<div class="disk-line${tone}" role="button" title="Clean Up"><span class="disk-mark">${DISK_ICON}</span>`
    + `<span class="disk-words"><b>${esc(disk.head)}</b><i>${esc(disk.sub || '')}</i></span>`
    + `<span class="disk-go">${GO_ICON}</span>`
    + `<button class="icon-button small disk-x" title="Not now">${CLOSE_ICON}</button></div>`;
}

// Keys' line: how many keys were found where they shouldn't be, and where the most exposed are; null when there's
// nothing new to say.
function keysLineHTML(found) {
  const words = keysLineWords(found);
  if (!words) return null;
  return `<div class="disk-line keys" role="button" title="See them"><span class="disk-mark">${KEY_ICON}</span>`
    + `<span class="disk-words"><b>${esc(words.head)}</b><i>${esc(words.sub)}</i></span>`
    + `<span class="disk-go">${GO_ICON}</span>`
    + `<button class="icon-button small disk-x" title="Not now">${CLOSE_ICON}</button></div>`;
}

// The line as it shows, one at a time: the disk nearly out; keys found; the disk low; the map's being ready. Null when
// none shows, and while Storage is open beside the list, where what the line would open is already in front of you.
function storageLineHTML(disk, storage, mapOpen, keys) {
  if (mapOpen) return null;
  if (disk?.show && disk.head && disk.tone === 'severe') return diskLineHTML(disk);
  const found = keysLineHTML(keys);
  if (found) return found;
  const low = diskLineHTML(disk);
  if (low || !storage?.ready) return low;
  return `<div class="disk-line ready" role="button" title="Open the Map"><span class="disk-mark">${DISK_ICON}</span>`
    + '<span class="disk-words"><b>Your storage map is ready</b><i>See what fills your disk</i></span>'
    + `<span class="disk-go">${GO_ICON}</span>`
    + `<button class="icon-button small disk-x" title="Not now">${CLOSE_ICON}</button></div>`;
}

function drawStorageLine() {
  showDiskLine(storageLineHTML(state.disk, state.storage, mapReading(), state.keys));
}

// It comes in under the header, the rows moving down to make room, and goes the same way; what it says changes in place,
// easing to its new height when the new words wrap onto another line or come back to one, so the rows below slide
// rather than jump (the list part's easeHeight, which only tells the panel its height when it's the same).
function showDiskLine(html) {
  if (diskLine.going) {
    diskLine.next = html;
    return;
  }
  const el = diskLine.el, shown = !!el?.isConnected;
  if (html && shown) {
    if (el.dataset.drawn !== html) {
      const before = el.offsetHeight;
      el.innerHTML = el.dataset.drawn = html;
      easeHeight(el, before);
    }
    return;
  }
  if (!html === !shown) return;
  if (html) {
    const line = diskLineEl();
    line.innerHTML = line.dataset.drawn = html;
    document.getElementById('dock').prepend(line);
    if (calm.matches) return reportHeight();
    return growIn(line, 0, () => reportHeight());
  }
  const gone = () => {
    el.remove();
    el.innerHTML = el.dataset.drawn = '';
    el.style.removeProperty('height');
    el.style.removeProperty('opacity');
    diskLine.going = false;
    reportHeight();
    const next = diskLine.next;
    diskLine.next = null;
    if (next) showDiskLine(next);
  };
  if (calm.matches) return gone();
  diskLine.going = true;
  foldAway(el, gone);
}

function diskLinePressed(e) {
  if (e.button !== 0) return;
  e.preventDefault();
  const line = e.target.closest('.disk-line');
  if (!line) return;
  const keys = line.classList.contains('keys');
  if (e.target.closest('.disk-x')) {
    showDiskLine(null);
    // Only the keys it spoke for, so one that leaves the Mac later brings it back.
    if (keys) return native({ type: 'keysClosed', ids: keysLineWords(state.keys)?.ids || [] });
    return native(line.classList.contains('ready') ? { type: 'storageNoteClosed', ready: true }
      : { type: 'storageNoteClosed' });
  }
  if (keys) return openStorage('keys');
  if (line.classList.contains('ready')) return openStorage('map');
  // The disk low or nearly out: Clean up, beside the list. Until Storage is on, this press is the yes that turns it on
  // (the app opens Clean up then, saying so, with Turn Off there).
  if (state.disk?.on) return openStorage('clean');
  native({ type: 'storageOn', view: 'clean' });
}
core.pointerTargets.push('.disk-line', '.disk-x');

// What the app says of the disk: whether the line shows, and what it says.
window.setDisk = (disk) => {
  state.disk = disk;
  drawStorageLine();
};
