// The island's gauge pointed at: it opens, and the files of the part the pointer is on are listed below it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// The session whose gauge is open; the part whose files are listed ('<session>:<part>') and where its list ends; and
// each checkout's files by kind, as the app last sent them (setCheckoutFiles).
moduleState({ islandOpen: null, filesShown: null, filesBottom: 0, checkoutFiles: {} });

// The island's gauge (the files stage, gaugeHTML) opens while the pointer is on it, or on the list it opened, and the
// list (#files) shows the files of the part the pointer is on. Both close as soon as the pointer is on neither: the gap
// between them counts as the list (cards.css), so the pointer can go down into the list, to scroll it, without
// leaving. The open gauge stays open through rebuilds (islandHTML), and the rebuild after its opening or closing waits
// for the motion to finish.
const filesCard = document.getElementById('files');
const FILES_SAID = {
  staged: ['Staged files', 'Ready to commit as they are.'],
  partly: ['Modified staged files', 'Staged earlier, then changed again. A commit now takes the staged version; the '
           + 'later changes stay behind.'],
  unstaged: ['Unstaged files', 'Changed but not added yet, new files included. A commit now leaves them out.'],
};

function syncIsland(el) {
  const gauge = el?.closest('.island .gauge'), onList = !!el?.closest('#files');
  const sid = gauge ? gauge.closest('.island').dataset.sid : onList ? state.islandOpen : null;
  if (sid) openIsland(sid);
  else if (state.islandOpen) openIsland(null);
  const part = el?.closest('.gauge [data-part]');
  if (part && sid) showFiles(sid, part.dataset.part);
  else if (!onList) hideFiles();
}

// The app reports the pointer only when it moves, and opening or closing moves the parts under one that's still: once
// the motion is done, what's under it is looked at again, so the list is the part it's really on.
let islandSettled;
function openIsland(sid) {
  if (state.islandOpen === sid) return;
  state.islandOpen = sid;
  for (const island of document.querySelectorAll('.island'))
    island.querySelector('.gauge')?.closest('.cap').classList.toggle('open', island.dataset.sid === sid);
  state.settleUntil = Math.max(state.settleUntil, performance.now() + 560);
  if (!sid) hideFiles();
  clearTimeout(islandSettled);
  islandSettled = setTimeout(() => { if (state.pointer) syncHover(); }, 520);
}

// The list for the part the pointer is on. It grows out of the pointer, just below the gauge, a tenth of a second after
// the pointer lands (the gauge is nearly open by then, so the part is the one it will stay on), and from then on follows
// the pointer along the gauge, its list changing at once as the pointer crosses into another part. Gone down into the
// list (to scroll it), the pointer isn't followed: the list holds still under it.
//
// The wait starts once, when the pointer reaches the gauge: the pointer moving (reported many times a second) doesn't
// start it again, or a pointer that kept moving would never see the list. filesWanted is the part it's on meanwhile.
let filesWanted = null, filesWait = null;
function showFiles(sid, part) {
  const anchor = partAt(sid, part);
  if (state.filesShown === sid + ':' + part) {
    if (anchor) { refreshFiles(sid, part, anchor); placeFiles(anchor); }
    return;
  }
  filesWanted = { sid, part };
  if (state.filesShown) showWanted();  // already up: the list changes at once
  else filesWait ??= setTimeout(() => { filesWait = null; showWanted(); }, 100);
}

// The list that's up, brought up to date when the checkout's files have changed under it (each rebuild looks again),
// where it was scrolled to. filesListed is what it shows now.
let filesListed = '';
function refreshFiles(sid, part, anchor) {
  const s = state.last.sessions.find((x) => x.sessionId === sid);
  if (!s) return;
  const html = filesHTML(s, part, +anchor.closest('.gauge').dataset[part]);
  if (html === filesListed) return;
  const scrolled = filesCard.querySelector('.f-list')?.scrollTop || 0;
  filesCard.innerHTML = filesListed = html;
  const list = filesCard.querySelector('.f-list');
  if (list) list.scrollTop = scrolled;
}

function cancelShow() {
  clearTimeout(filesWait);
  filesWait = filesWanted = null;
}

// A part of a row's gauge, the one in view: a row pinned below its folded group is there twice, and the original,
// inside the fold, isn't the one pointed at.
function partAt(sid, part) {
  return [...document.querySelectorAll(`.island[data-sid="${CSS.escape(sid)}"] [data-part="${part}"]`)]
    .find((band) => !band.closest('.closed')) || null;
}

function showWanted() {
  const want = filesWanted;
  // The gauge has been opening under a pointer that may not have moved since it got there: the part under it now is
  // the one it's on.
  const under = state.pointer && document.elementFromPoint(state.pointer.x, state.pointer.y)
    ?.closest('.gauge [data-part]');
  if (want && under && under.closest('.island')?.dataset.sid === want.sid) want.part = under.dataset.part;
  const s = want && state.last.sessions.find((x) => x.sessionId === want.sid);
  const at = want && partAt(want.sid, want.part);
  if (!s || !at) return;
  const opening = !state.filesShown;
  filesCard.innerHTML = filesListed = filesHTML(s, want.part, +at.closest('.gauge').dataset[want.part]);
  state.filesShown = want.sid + ':' + want.part;
  document.querySelectorAll('.gauge .band.is-on').forEach((b) => b.classList.remove('is-on'));
  at.classList.add('is-on');
  if (opening) {
    // Put where it grows from, with no motion, then grow it from there.
    filesCard.classList.add('still');
    placeFiles(at);
    filesCard.offsetHeight;
    filesCard.classList.remove('still');
    filesCard.classList.add('on');
  } else {
    placeFiles(at);
  }
  reportHeight();
}

function filesHTML(s, part, count) {
  const lists = state.checkoutFiles[(s.workGit || s.git)?.root] || {};
  const paths = (lists[part] || []).map((p) => [p, false])
    .concat(part === 'unstaged' ? (lists.new || []).map((p) => [p, true]) : []).slice(0, 100);
  const files = paths.map(([path, made]) => {
    const cut = path.lastIndexOf('/') + 1;
    return `<div class="f-file"><span class="f-dir">${esc(path.slice(0, cut))}</span>${esc(path.slice(cut))}`
      + `${made ? ' <span class="f-new">new</span>' : ''}</div>`;
  }).join('');
  const more = count > paths.length
    ? `<div class="f-more">and ${(count - paths.length).toLocaleString('en-US')} more</div>` : '';
  return `<div class="f-head"><span>${FILES_SAID[part][0]}</span>`
    + `<span class="f-n">${count.toLocaleString('en-US')}</span></div>`
    + `<div class="f-help">${FILES_SAID[part][1]}</div><div class="f-list">${files}${more}</div>`;
}

// Just below the gauge (above it when the panel can't grow to fit it below), with the pointer near its left end as far
// as the panel's edges allow. Where the pointer is on it (--ox, --oy) is what it grows from and shrinks back to; --reach
// is far enough from there to show all of it.
function placeFiles(anchor) {
  const gauge = anchor.closest('.gauge').getBoundingClientRect(), h = filesCard.offsetHeight, w = filesCard.offsetWidth;
  const x = state.pointer?.x ?? anchor.getBoundingClientRect().left;
  const column = document.getElementById('root').getBoundingClientRect();
  const left = Math.max(column.left + 10, Math.min(x - 28, column.right - w - 10));
  const below = gauge.bottom + 6 + h + 8 <= state.panelMax;
  const top = below ? gauge.bottom + 6 : Math.max(6, gauge.top - h - 6);
  filesCard.style.left = left + 'px';
  filesCard.style.top = top + 'px';
  filesCard.classList.toggle('above', !below);  // where the gap it bridges is (cards.css)
  filesCard.style.setProperty('--ox', Math.round(x - left) + 'px');
  filesCard.style.setProperty('--oy', below ? '-6px' : h + 6 + 'px');
  filesCard.style.setProperty('--reach', Math.ceil(Math.hypot(w, h) + 12) + 'px');
  state.filesBottom = Math.ceil(top + h + 8);
}

// Folds the list back up; the panel shrinks once it has.
function hideFiles() {
  cancelShow();
  if (!state.filesShown) return;
  state.filesShown = null;
  filesCard.classList.remove('on');
  document.querySelectorAll('.gauge .band.is-on').forEach((b) => b.classList.remove('is-on'));
  setTimeout(reportHeight, 200);
}

// The files in each listed checkout, by kind (staged, partly, unstaged, new), the first 100 of each, whenever they
// change: what the gauge lists when one of its parts is pointed at.
window.setCheckoutFiles = (files) => { state.checkoutFiles = files || {}; };

core.pointerWatchers.push(syncIsland);
core.overhangs.push(() => (state.filesShown ? state.filesBottom : 0));
