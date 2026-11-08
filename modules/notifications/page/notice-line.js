// The line under the header where notifications says what needs you (core.places.line), in its place under the header
// (#notices, panel.html), where it takes the header's room from the list as a card there does (parts/glass). It shows
// one notice with the kit's pieces: its tag if it has one ("New"), its words (urgent ones in the colour of something to
// put right), with a few quiet words after them if it has them (`after`, "3 waiting"), its one button, a +N chip when
// more wait, and its ×. It eases open under the header, the rows moving down
// with it, and folds away the same way, with the strips' helpers (strips.js); when the notice changes, the old words
// fade before the new come in, the line easing to its new height. A press that comes too soon after the line changed
// doesn't count (FRESH_MS). VoiceOver says each new line once (noticeSaid). A notice whose × folds it (a page sender's
// that says what it folds to: notices.js) becomes a chip at the line's end, its words alone ("3 waiting"), which a
// press opens as its button would.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

const noticesEl = document.getElementById('notices');
const nl = {
  shown: null,    // the notice on show, and how many more wait ({ notice, more }), or null
  next: null,     // what came while it moved, drawn once it's done, or null
  moving: false,  // growing in, folding away or changing its words
  at: 0,          // when its words came, as a press that comes too soon after doesn't count
};

function noticeHTML(n, more) {
  if (n.folded) return `<div class="notice nl-line nl-folded" data-id="${esc(n.id)}">${noticeMoreHTML(more)}`
    + `<button class="tag chip nl-open" title="${esc(n.title || '')}">${esc(n.text)}</button></div>`;
  return `<div class="notice nl-line${n.level === 'urgent' ? ' warn' : ''}" data-id="${esc(n.id)}">`
    + (n.done ? DONE_ICON : '') + (n.tag ? `<span class="tag new">${esc(n.tag)}</span>` : '')
    + `<span class="notice-text">${esc(n.text)}${n.after ? ` <span class="nl-after">· ${esc(n.after)}</span>` : ''}`
    + '</span>'
    + (n.button
      ? `<button class="button main small notice-button"${n.busy ? ' disabled' : ''}>${esc(n.button)}</button>` : '')
    + noticeMoreHTML(more)
    + (n.closes ? '<button class="icon-button small nl-close" title="Not now">×</button>' : '') + '</div>';
}
const noticeMoreHTML = (more) => (more ? `<button class="tag chip nl-more" title="See the next one">+${more}</button>`
  : '');

const sameNotice = (a, b) => a.id === b.id && a.text === b.text && a.button === b.button && a.closes === b.closes
  && a.done === b.done && a.tag === b.tag && a.level === b.level && !!a.folded === !!b.folded
  && a.after === b.after;
// No motion under reduced motion, nor out of sight, while the panel is folded into the cat.
const noticeQuiet = () => calm.matches || document.body.classList.contains('collapsed');

core.places.line = {
  // Seen in the open panel, or while the folded panel's list is out on pointing, or opening round it; not while it's
  // turned over to its back.
  inSight() {
    const body = document.body.classList;
    return (!body.contains('collapsed') || body.contains('peeking') || body.contains('arriving')) && !state.turned;
  },
  show(notice, more) {
    if (nl.moving) {
      nl.next = { notice, more };
      return;
    }
    const was = nl.shown;
    if (!notice) {
      if (was) noticeFold();
      return;
    }
    nl.shown = { notice, more };
    if (!was) return noticeGrow(notice, more);
    // Its × folded it: what's left is its chip. Folded still, only the chip's words change.
    if (was.notice.id === notice.id && notice.folded && !was.notice.folded) return noticeToChip(notice, more);
    if (was.notice.id === notice.id && notice.folded && was.notice.folded && was.more === more) {
      return setText(noticesEl.querySelector('.nl-open'), notice.text);
    }
    if (!sameNotice(was.notice, notice)) return noticeSwap(notice, more);
    // The same notice: only its button's wait and the count change, in place.
    noticesEl.querySelector('.notice-button')?.toggleAttribute('disabled', !!notice.busy);
    if (was.more !== more) noticeCount(more);
  },
};

// How many more wait, changed. A new count is written in place. The chip coming or going changes the room its button
// has, so what's there before and after moves while the rest fades: a chip going fades first, then the button glides
// into its room; one coming makes its room first, the button gliding aside, then fades in. Either way a press just
// after doesn't count, as the button may have moved under it.
function noticeCount(more) {
  const line = noticesEl.querySelector('.nl-line'), chip = line?.querySelector('.nl-more');
  if (!line) return;
  nl.at = Date.now();
  if (chip && more) return setText(chip, `+${more}`);
  const button = line.querySelector('.notice-button');
  const change = () => {
    const before = noticesEl.offsetHeight, from = button?.getBoundingClientRect().left;
    const close = line.querySelector('.nl-close');
    if (chip) chip.remove();
    else if (close) close.insertAdjacentHTML('beforebegin', noticeMoreHTML(more));
    else line.insertAdjacentHTML('beforeend', noticeMoreHTML(more));
    nl.at = Date.now();
    const added = line.querySelector('.nl-more');
    if (noticeQuiet()) return reportHeight();
    easeHeight(noticesEl, before);
    const by = button ? from - button.getBoundingClientRect().left : 0;
    const glide = by ? button.animate([{ transform: `translateX(${by}px)` }, { transform: 'none' }],
                                      { duration: 250, easing: MORPH_EASE }).finished : Promise.resolve();
    if (added) {
      added.style.opacity = '0';
      glide.then(() => added.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 180, easing: 'ease' }).finished)
        .finally(() => added.style.removeProperty('opacity'));
    }
  };
  if (!chip || noticeQuiet()) return change();
  chip.style.pointerEvents = 'none';
  chip.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 150, easing: 'ease', fill: 'forwards' })
    .finished.then(change, change);
}

function noticeSettled() {
  nl.moving = false;
  if (nl.next === null) return;
  const { notice, more } = nl.next;
  nl.next = null;
  core.places.line.show(notice, more);
}

// What VoiceOver says: each new line's words, once, in a place of its own beside the line (#notice-say), there before
// the first line comes; the chip's count and the button's words aren't said. It's emptied as the line goes, so nothing
// stale is found there.
function noticeSaid(notice) {
  document.getElementById('notice-say').textContent = !notice ? ''
    : notice.after ? `${notice.text}, ${notice.after}` : notice.text;
}

function noticeGrow(notice, more) {
  noticesEl.innerHTML = noticeHTML(notice, more);
  noticesEl.hidden = false;
  nl.at = Date.now();
  noticeSaid(notice);
  if (noticeQuiet()) return reportHeight();
  nl.moving = true;
  growIn(noticesEl, 0, noticeSettled);
}

// Its words fade first, so none sit over the rows as they come up; then it eases away to nothing, the rows coming up
// with it, and the header's room is the list's again.
function noticeFold() {
  nl.shown = null;
  noticeSaid(null);
  const done = () => {
    noticesEl.hidden = true;
    noticesEl.innerHTML = '';
    reportHeight();
    syncHover();
    noticeSettled();
  };
  if (noticeQuiet()) return done();
  nl.moving = true;
  const fold = () => foldAway(noticesEl, done);
  const words = noticesEl.firstElementChild;
  if (!words) return fold();
  words.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 120, easing: 'ease', fill: 'forwards' }).finished
    .then(fold, fold);
}

// A new notice: the old words fade first, then the new come in, lifting 3px, as the line eases to its new height.
function noticeSwap(notice, more) {
  const old = noticesEl.firstElementChild;
  const put = () => {
    const before = noticesEl.offsetHeight;
    noticesEl.innerHTML = noticeHTML(notice, more);
    nl.at = Date.now();
    noticeSaid(notice);
    if (noticeQuiet()) {
      reportHeight();
      return noticeSettled();
    }
    easeHeight(noticesEl, before);
    noticesEl.firstElementChild.animate([{ opacity: 0, transform: 'translateY(3px)' },
                                         { opacity: 1, transform: 'none' }], { duration: 300, easing: MORPH_EASE })
      .finished.then(noticeSettled, noticeSettled);
  };
  if (noticeQuiet() || !old) return put();
  nl.moving = true;
  old.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 150, easing: 'ease', fill: 'forwards' })
    .finished.then(put, put);
}

// A notice's × folded it to its chip. What's going fades first (its words, button, New tag and ×, and the +N chip
// unless others still wait), without lifting. Then the chip comes in at the ×'s place, lifting 3px, and a +N chip
// that stays glides to its place before it. Then the line eases down to the chip's height, the rows coming up with it.
// Under reduced motion, or folded into the cat, it's simply the chip.
function noticeToChip(notice, more) {
  const line = noticesEl.querySelector('.nl-line');
  const put = () => {
    noticesEl.innerHTML = noticeHTML(notice, more);
    nl.at = Date.now();
    noticeSaid(notice);
  };
  if (!line || noticeQuiet()) {
    put();
    return reportHeight();
  }
  nl.moving = true;
  const was = line.querySelector('.nl-more'), stays = !!was && more > 0;
  const going = [...line.children].filter((c) => !(stays && c === was));
  Promise.all(going.map((c) => c.animate([{ opacity: 1 }, { opacity: 0 }],
                                         { duration: 150, easing: 'ease', fill: 'forwards' }).finished))
    .then(() => {
      const before = noticesEl.offsetHeight, from = stays ? was.getBoundingClientRect().left : null;
      noticesEl.style.height = `${before}px`;
      put();
      const came = [noticesEl.querySelector('.nl-open').animate(
        [{ opacity: 0, transform: 'translateY(3px)' }, { opacity: 1, transform: 'none' }],
        { duration: 300, easing: MORPH_EASE }).finished];
      const still = stays && noticesEl.querySelector('.nl-more');
      if (still) {
        came.push(still.animate([{ transform: `translateX(${from - still.getBoundingClientRect().left}px)` },
                                 { transform: 'none' }], { duration: 250, easing: MORPH_EASE }).finished);
      }
      return Promise.all(came).then(() => {
        noticesEl.style.removeProperty('height');
        nl.at = Date.now();
        tween(noticesEl, { height: `${before}px`, overflow: 'hidden' }, { height: `${noticesEl.offsetHeight}px` },
              noticeSettled, 300);
        followHeight(340);
      });
    })
    .catch(() => {
      noticesEl.style.removeProperty('height');
      put();
      reportHeight();
      noticeSettled();
    });
}

// A button's words, changed a moment after a press ("Copied"): the old fade, then the new come in. It keeps its width,
// so nothing beside it moves.
function noticeLabel(button, words) {
  if (button.textContent === words) return;
  if (noticeQuiet()) {
    button.textContent = words;
    return;
  }
  button.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 120, easing: 'ease', fill: 'forwards' }).finished
    .then(() => {
      button.textContent = words;
      button.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 180, easing: MORPH_EASE });
    }, () => { button.textContent = words; });
}

// mousedown, as the list's presses are.
noticesEl.addEventListener('mousedown', (e) => {
  if (e.button !== 0) return;
  e.preventDefault();
  const notice = nl.shown?.notice;
  if (!notice || nl.moving || Date.now() - nl.at < FRESH_MS) return;
  if (e.target.closest('.nl-close')) return noticeAway(notice.id);
  if (e.target.closest('.nl-more')) return noticeStep();
  if (e.target.closest('.nl-open')) return noticePressed(notice.id);
  const go = e.target.closest('.notice-button');
  if (!go || go.disabled) return;
  noticePressed(notice.id);
  if (!notice.pressedWord) return;
  go.style.minWidth = `${go.offsetWidth}px`;
  noticeLabel(go, notice.pressedWord);
  setTimeout(() => { if (go.isConnected) noticeLabel(go, notice.button); }, 2000);
});

core.strips.push('notices');
core.pointerTargets.push('#notices .notice-button:not(:disabled)', '#notices .nl-more', '#notices .nl-close',
                         '#notices .nl-open');
