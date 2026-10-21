// The reader: beside the list in the panel, what one of its modes shows of a session (core.readerModes): what it wrote
// (writings.js), or what it changed (changes-view.js); or what a mode about none of them shows (Spotify's lyrics).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// Pressing a row's tag (or its numbers) grows the panel beside the list (the app does that, PanelWindow's
// expandReader): the list stays where it was, and the reader opens beside it. The panel grows only as much as what's
// shown needs, and changes size with it. It grows as soon as it's pressed: until what it shows is in, the reader says
// where that's coming from (readerWait), and the panel then grows or shrinks to fit it.
//
// A mode is { draw(), and as it needs: sessionless (it's about none of the sessions: it opens with none,
// toggleReader(null, null, mode), and shows whatever the list holds), width(r) (its own width, rather than one of the
// two below), wide(r, s) (shown at a page's width, not a reading column's), contentHeight(page) (what it shows is as
// tall as this, not as it measures), shown(r) (it's what the reader shows now: what it keeps on `r` is made ready),
// reset(r) (the reader turns to another session or mode: what it kept goes), turn(r, scope) (pressed again where it's
// open: whether it turned to `scope`, or else it closes), laidOut(r, width) (the reader is laid out at this width, as
// the panel grows to it: where its parts are now is where they'll show), closed(r) (the panel has folded back, the
// reader out of sight), cls (a class the reader's box has while it shows) }. `r` is state.reading.

const reader = document.getElementById('reader');
// How wide the reader is: a list down its side (230px) beside a reading column of about 70 characters with its
// margins, or, for what's wide (a prototype, a session's changes), a laptop-sized page.
const READER_TEXT_WIDTH = 230 + 640, READER_PAGE_WIDTH = 230 + 1024;

// ---- Opening and closing ----

// The session as last listed: one that's gone from the list since stays readable until the reader closes.
function readerSession() {
  const r = state.reading;
  const s = r && state.last.sessions.find((x) => x.sessionId === r.sessionId);
  if (s) r.session = s;
  return r?.session;
}

// `mode` is what it shows, `wid` what it opens on, if anything in particular, and `scope` which part of it, when not
// the mode's first (the changes view's: the session's own changes, all sessions', or the commits). Switching to another
// session or mode starts the view afresh, in the panel as it is.
function openReader(sid, wid, mode = 'writings', scope = null) {
  const s = state.last.sessions.find((x) => x.sessionId === sid), m = core.readerModes[mode];
  if (!m || (!s && !m.sessionless)) return;
  // Pressed on a chat beside the folded cat (chats.js), or in its list (peek.js), the panel opens for good first: the
  // reader grows from the list once it has (the app holds it till then, PanelWindow's expandReader).
  if (stillFolded()) return openFromCat(() => openReader(sid, wid, mode, scope));
  if (!state.reading) {
    state.reading = { mode, sessionId: sid, id: wid, session: s, scope };
    headerGlideTo(0);  // the header is all there while the reader is open (header.js)
    document.body.classList.add('reading');
    reader.innerHTML = `<div class="r-in"><div class="r-head"></div><div class="r-main"><nav class="r-shelf"></nav>
        <div class="r-view"><div class="r-src"></div><div class="r-body"></div><div class="r-answer"></div></div>
      </div></div>`;
    // The panel grows at once, as wide as the mode needs and as tall as the list (fitReader), so the press is seen
    // to work however long what's shown takes to come in.
  } else {
    const r = state.reading;
    if (r.mode !== mode || r.sessionId !== sid) {
      for (const el of reader.querySelectorAll('[data-drawn]')) { el.innerHTML = ''; delete el.dataset.drawn; }
      // What the last one showed goes too, so it never sits under another's head.
      reader.querySelector('.r-body').innerHTML = '';
      r.ready = false;
      for (const other of Object.values(core.readerModes)) other.reset?.(r);
    }
    Object.assign(r, { mode, sessionId: sid, id: wid, session: s, scope });
  }
  state.reading.refill = null;  // what was to come in once the old had gone (readerRefill)
  m.shown?.(state.reading);
  for (const other of Object.values(core.readerModes))
    if (other.cls) reader.querySelector('.r-in').classList.toggle(other.cls, other === m);
  drawReader();
}

// How tall the panel is with the list alone: as reportHeight measures it once the reader has closed (the header and the
// list's rows, together at most 640pt as base.css keeps them, and the strips on top of that, within the room it has),
// measured now, so the panel folds straight to it. The header lies over the list's top, in room the list keeps for it
// (base.css), which its rows' places count from, unless the setup line or a card under the header takes that room
// above the list; they're strips too (core.strips), so they come on top of the 640pt with the others.
function listHeight() {
  const list = document.getElementById('list'), last = list.lastElementChild;
  const rows = last ? last.offsetTop + last.offsetHeight : 0;
  const under = ['install', 'dock'].reduce((sum, id) => sum + (document.getElementById(id)?.offsetHeight || 0), 0);
  const strips = core.strips.reduce((sum, id) => sum + (document.getElementById(id)?.offsetHeight || 0), 0);
  const head = list.offsetTop - under + list.clientTop;
  return Math.min(Math.ceil(Math.min(head + rows + 6, 640) + strips), state.panelMax || 640);
}

// A row's tag (or its numbers, for its changes) opens the reader on that session, or, where it's open already in that
// mode, turns it to `scope` if the mode can (turn), or else closes it. While the panel folds back, a press waits for it
// to finish.
function toggleReader(sid, wid, mode = 'writings', scope = null) {
  const r = state.reading;
  if (r?.closing) return;
  if (r?.sessionId === sid && r.mode === mode) {
    if (!core.readerModes[mode]?.turn?.(r, scope)) closeReader();
  } else openReader(sid, wid, mode, scope);
}

function closeReader() {
  if (!state.reading || state.reading.closing) return;
  state.reading.closing = true;
  // What's shown stays while the panel folds, so its edge slides over it, as opening uncovered it; it goes once the
  // panel has folded (readerClosed), out of sight by then.
  wantKeyboard(false);
  render();  // the tag no longer shows as pressed
  native({ type: 'collapse', height: listHeight() });
}

// The app has worked out which side the list stays on and how wide the reader can be, and is sizing the panel. The
// reader is laid out at that width now, so the panel growing only uncovers it. Where the screen leaves less room
// than was asked for, the text wraps to the narrower width, so it's measured again.
window.readerOpened = (side, width) => {
  const r = state.reading;
  if (!r || r.closing) return;
  document.body.classList.toggle('list-left', side === 'left');
  // Beside the list's column: ending where it starts, or starting where it ends (--side, --column in tokens.css).
  const column = document.getElementById('root').getBoundingClientRect();
  reader.style.left = (side === 'left' ? column.right : column.left - width) + 'px';
  reader.style.width = width + 'px';
  reader.querySelector('.r-in').style.width = width + 'px';
  requestAnimationFrame(() => document.body.classList.add('reader-shown'));
  if (width < r.askedWidth - 1) { r.maxWidth = width; fitReader(); }
  core.readerModes[r.mode]?.laidOut?.(r, width);
};

// Asks the app for the room what's shown needs: the reader's width, and its height (header, then the taller of the
// list down its side and the page being read with its answer bar), or the list's, or what hangs below it, if that's
// taller: a new conversation's card opening under the header, or a card under a low row, grows the panel, as it does
// with the list alone, rather than squeezing the rows or being cut off. The app keeps the panel at least as tall as the
// list was, and within the screen. Asked only when it changes. While what's shown is on its way (not `ready`), the
// panel keeps the height it has, so turning to another session or tab doesn't fold it only to grow it again.
function fitReader() {
  const r = state.reading, s = readerSession();
  if (!r || r.closing) return;
  const m = core.readerModes[r.mode];
  if (!s && !m.sessionless) return;
  const width = Math.min(m.width?.(r) ?? (m.wide?.(r, s) ? READER_PAGE_WIDTH : READER_TEXT_WIDTH),
                         r.maxWidth || Infinity);
  const inner = reader.querySelector('.r-in');
  inner.style.width = width + 'px';
  const body = reader.querySelector('.r-body'), page = body.firstElementChild;
  const content = m.contentHeight?.(page) ?? (page?.offsetHeight || 0);
  const view = reader.querySelector('.r-src').offsetHeight + content + reader.querySelector('.r-answer').offsetHeight;
  const height = Math.max(listHeight(), hangingBelow(), reader.querySelector('.r-head').offsetHeight + 1
    + Math.max(view, reader.querySelector('.r-shelf').scrollHeight), r.ready ? 0 : r.askedHeight || 0);
  if (r.askedWidth === width && Math.abs((r.askedHeight || 0) - height) < 2) return;
  r.askedWidth = width;
  r.askedHeight = height;
  native({ type: 'expand', width, height: Math.ceil(height) });
}

// The panel is back where it was: the list alone again.
window.readerClosed = () => {
  const r = state.reading;
  if (r) core.readerModes[r.mode]?.closed?.(r);
  state.reading = null;
  document.body.classList.remove('reading', 'list-left', 'reader-shown');
  reader.innerHTML = '';
  render();
  // The header's four squares were pressed with the reader open: the panel turns over now that it has folded back.
  if (state.turnAfterReader) {
    state.turnAfterReader = false;
    native({ type: 'turn', on: true });
  }
};

// ---- Drawing ----

// What the reader shows, from the newest rows, by its mode.
function drawReader() {
  const r = state.reading, s = readerSession();
  if (!r || !reader.firstChild || (!s && !core.readerModes[r.mode].sessionless)) return;
  core.readerModes[r.mode].draw();
}

// What the reader's body says while what it's to show is on its way: where it's coming from, breathing until it's in
// (motion.css). Put in again only when the words change, so the breathing carries on.
function readerWait(body, words) {
  if (body.querySelector(':scope > .r-wait')?.textContent === words) return;
  body.innerHTML = `<div class="r-missing r-wait">${esc(words)}</div>`;
}

// What the reader's body shows goes, then `fill` puts the new in, which comes in the panel's way (fading in, lifting
// 3px, sharpening): what came in place of readerWait's words, or a song's lyrics in place of another's. Asked again
// while the old is going, the newest comes in once it has gone; and nothing comes in if the reader has turned to
// another session or mode by then. Under reduced motion it's put in at once.
function readerRefill(body, fill) {
  const r = state.reading, old = body.firstElementChild;
  if (r.refill) return void (r.refill = fill);
  if (!old || calm.matches) return fill();
  r.refill = fill;
  const { mode, sessionId } = r;
  tween(old, { opacity: '1' }, { opacity: '0' }, () => {
    const latest = r.refill;
    r.refill = null;
    if (!latest || state.reading !== r || r.mode !== mode || r.sessionId !== sessionId) return;
    latest();
    body.firstElementChild?.animate([{ opacity: 0, transform: 'translateY(3px)', filter: 'blur(1.5px)' },
                                     { opacity: 1, transform: 'none', filter: 'blur(0)' }],
                                    { duration: 420, easing: MORPH_EASE });
  }, 160, 'ease');
}

// Puts `html` in `el` unless it's there already (as last put in), and says whether it did.
function putHTML(el, html) {
  if (el.dataset.drawn === html) return false;
  el.innerHTML = html;
  el.dataset.drawn = html;
  return true;
}

// ---- Presses ----

// A press in the reader: the modes' (core.readerPresses), then its ✕. The row it's beside stays where it is.
reader.addEventListener('mousedown', (e) => {
  if (e.button !== 0 || !state.reading) return;
  keepInPlace(state.reading.sessionId);
  for (const [selector, press] of [...core.readerPresses, ['.r-close', () => closeReader()]]) {
    const target = e.target.closest(selector);
    if (target) { if (target.tagName === 'BUTTON') e.preventDefault(); return press(target, e); }
  }
});
reader.addEventListener('focusin', (e) => { if (e.target.closest(TEXT_BOX)) wantKeyboard(true); });
reader.addEventListener('focusout', (e) => { if (e.target.closest(TEXT_BOX)) wantKeyboard(false); });
