// The now-playing strip, above the usage strip: the song Spotify is playing (now-playing.js says what shows), with a
// thin line along its top edge for how far in it is. Pointed at, the time gives way to back, pause and next, and the
// line can be pressed to jump; pressing the song brings Spotify forward. Paused for 15 minutes, it folds away into
// Spotify's token at the panel's corner. A note under it says where to hide it the first time, and what to do when macOS hasn't allowed
// Whozmove to control Spotify.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// Like the usage strip, it isn't in the list, so it's built once and only its text, cover and widths change. Its
// motion follows CONTRIBUTING.md's rules: it grows in and folds away with the panel's bottom edge; a new song's title
// and artist roll in place as the cover cross-fades; and the time leaves its lane before the controls come into it.

// The strip's controls: back, pause or play, and next.
const SONG_ICONS = {
  previous: '<svg width="12" height="12" viewBox="0 0 12 12"><rect x="1.5" y="2" width="1.6" height="8" rx=".6" '
    + 'fill="currentColor"/><path fill="currentColor" d="M10.5 2.6v6.8a.6.6 0 0 1-.92.5L4.4 6.5a.6.6 0 0 1 '
    + '0-1l5.18-3.4a.6.6 0 0 1 .92.5Z"/></svg>',
  next: '<svg width="12" height="12" viewBox="0 0 12 12"><rect x="8.9" y="2" width="1.6" height="8" rx=".6" '
    + 'fill="currentColor"/><path fill="currentColor" d="M1.5 2.6v6.8a.6.6 0 0 0 .92.5L7.6 6.5a.6.6 0 0 0 0-1L2.42 '
    + '2.1a.6.6 0 0 0-.92.5Z"/></svg>',
  pause: '<svg width="12" height="12" viewBox="0 0 12 12"><rect x="2.5" y="1.8" width="2.4" height="8.4" rx=".7" '
    + 'fill="currentColor"/><rect x="7.1" y="1.8" width="2.4" height="8.4" rx=".7" fill="currentColor"/></svg>',
  play: '<svg width="12" height="12" viewBox="0 0 12 12"><path fill="currentColor" d="M3 2.1v7.8a.6.6 0 0 0 '
    + '.9.52l6.3-3.9a.6.6 0 0 0 0-1.04L3.9 1.58A.6.6 0 0 0 3 2.1Z"/></svg>',
};

const npEl = document.getElementById('nowplaying');
const np = {
  built: false, shown: false,
  moving: false,  // growing in or folding away: presses wait, and what changes meanwhile is drawn once it's done
  track: null,    // the song on show, so a new one rolls in
  art: null,      // the cover wanted
  note: null,     // the note on show: first, refused or none
};
// A new song's cover usually comes a moment after it: the last one stays this long for it, then the square shows.
const COVER_WAIT_MS = 4000;

function npParts() {
  if (np.built) return np.parts;
  npEl.innerHTML = `
    <div class="np-strip">
      <span class="np-bar"><span class="np-line"><span class="np-fill"></span></span></span>
      <span class="np-art"><img class="np-img" alt=""><img class="np-img" alt=""></span>
      <span class="np-text" title="Open Spotify"><span class="np-title"></span><span class="np-artist"></span></span>
      <span class="np-side">
        <span class="np-clock"></span>
        <span class="np-controls">
          <button class="np-btn" data-do="previous" title="Back">${SONG_ICONS.previous}</button>
          <button class="np-btn np-play" data-do="playpause" title="Pause">${SONG_ICONS.pause}</button>
          <button class="np-btn" data-do="next" title="Next">${SONG_ICONS.next}</button>
        </span>
      </span>
    </div>
    <div class="np-note" hidden><span class="np-note-text"></span><button class="np-note-btn"></button></div>`;
  const q = (sel) => npEl.querySelector(sel);
  np.parts = { strip: q('.np-strip'), fill: q('.np-fill'), art: q('.np-art'),
               imgs: [...npEl.querySelectorAll('.np-img')],
               title: q('.np-title'), artist: q('.np-artist'), clock: q('.np-clock'), play: q('.np-play'),
               note: q('.np-note'), noteText: q('.np-note-text'), noteButton: q('.np-note-btn') };
  // A cover fades in once it has loaded, on top of the one before, which goes only once it's covered; one that
  // doesn't load leaves the plain square.
  for (const img of np.parts.imgs) {
    img.addEventListener('load', () => {
      if (img.dataset.want !== np.art) return;
      const other = np.parts.imgs.find((o) => o !== img);
      img.parentNode.append(img);
      img.classList.add('on');
      clearTimeout(np.coverSwap);
      np.coverSwap = setTimeout(() => other.classList.remove('on'), 520);
    });
    img.addEventListener('error', () => {
      if (img.dataset.want === np.art) np.parts.imgs.forEach((o) => o.classList.remove('on'));
    });
  }
  np.built = true;
  return np.parts;
}

// ---- Each second, and whenever the app has something new ----

function nowPlayingTick(now) {
  if (np.moving) return;  // drawn again once the strip has grown in or folded away
  const view = nowPlayingView(state.nowPlaying, now, state.songNoteSeen);
  if (view.state === 'hidden') {
    if (np.shown) npFold();
    return;
  }
  npParts();
  if (np.shown) return npDraw(view);
  npDraw(view, true);
  np.shown = true;
  npGrow();
}

function npDraw(view, fresh = false) {
  const p = np.parts;
  const newSong = view.track !== np.track;
  if (newSong && !fresh && !calm.matches) {
    npRoll(p.title, view.title);
    npRoll(p.artist, view.artist);
  } else {
    for (const [el, text] of [[p.title, view.title], [p.artist, view.artist]])
      if (el.rolling) el.next = text;
      else setText(el, text);
  }
  np.track = view.track;
  npCover(view.art, view.note !== 'refused');
  // The line moves on each second, smoothly; a new song or a jump starts it where it is, without sliding back.
  const width = `${(Math.min(1, view.progress) * 100).toFixed(2)}%`;
  const jump = newSong || Math.abs(parseFloat(p.fill.style.width || '0') - parseFloat(width)) > 3;
  p.fill.classList.toggle('jump', jump);
  p.fill.style.width = width;
  setText(p.clock, view.clock);
  npEl.classList.toggle('is-paused', view.state === 'paused');
  const icon = view.state === 'playing' ? 'pause' : 'play';
  if (p.play.dataset.icon !== icon) {
    p.play.dataset.icon = icon;
    p.play.innerHTML = SONG_ICONS[icon];
    p.play.title = icon === 'pause' ? 'Pause' : 'Play';
  }
  npNote(view.note);
}

// A new song's title or artist rolls in place, up from below. One already rolling finishes first, then rolls on to
// the newest text, so a quick second skip never leaves it blank.
function npRoll(el, text) {
  if (el.rolling) {
    el.next = text;
    return;
  }
  if (el.textContent === text) return;
  const was = { el: el.cloneNode(true), height: el.offsetHeight };
  el.textContent = text;
  rollLine(null, el, was, false);
  el.rolling = setTimeout(() => {
    el.rolling = null;
    const next = el.next;
    el.next = undefined;
    if (next !== undefined) npRoll(el, next);
  }, MORPH_MS + 40);
}

// The cover cross-fades to a new one once it has loaded. A new song without one yet keeps the last for a moment, as
// its own is usually on its way (`waits`), and otherwise shows the plain square.
function npCover(art, waits) {
  if (art === np.art) return;
  np.art = art;
  clearTimeout(np.coverTimer);
  const clear = () => np.parts.imgs.forEach((img) => img.classList.remove('on'));
  if (!art) {
    if (waits) np.coverTimer = setTimeout(clear, COVER_WAIT_MS);
    else clear();
    return;
  }
  const next = np.parts.imgs.find((img) => !img.classList.contains('on')) ?? np.parts.art.firstElementChild;
  next.classList.remove('on');
  next.dataset.want = art;
  next.src = art;
}

// The note under the strip comes and goes as the strip's height eases.
function npNote(kind) {
  if (kind === np.note) return;
  const p = np.parts, before = npEl.offsetHeight;
  np.note = kind;
  p.note.hidden = !kind;
  p.note.classList.toggle('refused', kind === 'refused');
  if (kind) {
    const note = SONG_NOTES[kind];
    p.noteText.textContent = note.text;
    p.noteButton.textContent = note.button;
    p.noteButton.dataset.does = note.does;
    p.noteButton.classList.toggle('np-x', note.does === 'dismiss');
  }
  if (np.moving || !np.shown) return;
  // While it eases, the strip counts as moving, so a fold waits for it rather than being undone by its end.
  const easing = !calm.matches && Math.abs(npEl.offsetHeight - before) >= 1;
  easeHeight(npEl, before);
  if (!easing) return;
  np.moving = true;
  setTimeout(npSettled, 340);
}

// ---- Coming and going ----

// The strip grows in from nothing as the panel's bottom edge moves down with it, its content coming in the panel's
// way (fading in, lifting 3px, sharpening).
function npGrow() {
  npEl.hidden = false;
  if (calm.matches || document.body.classList.contains('collapsed')) return reportHeight();
  np.moving = true;
  growIn(npEl, 0, npSettled);
}

// Once it has grown in or folded away, whatever changed meanwhile (the song gone, or back) is drawn.
function npSettled() {
  np.moving = false;
  nowPlayingTick(Date.now());
}

// It fades as it eases away to nothing, and the panel's bottom edge comes up with it. The first note has been seen
// once the strip has shown it.
function npFold() {
  np.shown = false;
  np.track = null;
  if (np.note === 'first') seeSongNote();
  // The app is told once it has gone, so Spotify's token comes out only then.
  const done = () => {
    native({ type: 'spotify', action: 'folded' });
    npEl.hidden = true;
    np.art = null;
    clearTimeout(np.coverTimer);
    np.parts.imgs.forEach((img) => img.classList.remove('on'));
    reportHeight();
    syncHover();
    npSettled();
  };
  if (calm.matches || document.body.classList.contains('collapsed')) return done();
  np.moving = true;
  foldAway(npEl, done);
}

function seeSongNote() {
  state.songNoteSeen = true;
  store.set('songNoteSeen', true);
}

// ---- Presses ----

function pressNowPlaying(e) {
  if (e.button !== 0 || np.moving || !state.nowPlaying) return;
  const button = e.target.closest('.np-btn');
  if (button) return controlSong(button.dataset.do);
  const bar = e.target.closest('.np-bar');
  if (bar) {
    const r = bar.getBoundingClientRect();
    return controlSong('seek', Math.max(0, Math.min(1, (e.clientX - r.left) / r.width)));
  }
  const noteButton = e.target.closest('.np-note-btn');
  if (noteButton?.dataset.does === 'dismiss') {
    seeSongNote();
    return nowPlayingTick(Date.now());
  }
  if (noteButton?.dataset.does === 'settings') return native({ type: 'spotify', action: 'settings' });
  if (e.target.closest('.np-text, .np-art')) native({ type: 'spotify', action: 'open' });
}

// Sends a control to Spotify. Pause and a jump show at once, as Spotify will; what Spotify then says settles it, and
// the app tells the page what's true if it didn't go through. While
// macOS hasn't allowed Whozmove to control it, nothing is shown ahead: the press is only to ask again.
function controlSong(action, fraction) {
  const song = state.nowPlaying, now = Date.now();
  if (action === 'seek' && !(song.durationMs > 0)) return;  // nowhere to jump to in something without a length
  native(fraction === undefined ? { type: 'spotify', action } : { type: 'spotify', action, fraction });
  if (song.allowed === false) return;
  // Paused here, it's paused from now: the strip stays, as it will once the app says so too.
  if (action === 'playpause')
    state.nowPlaying = { ...song, positionMs: songPosition(song, now), at: now, playing: !song.playing,
                         pausedSince: song.playing ? now : song.pausedSince };
  else if (action === 'seek') state.nowPlaying = { ...song, positionMs: fraction * song.durationMs, at: now };
  else return;
  nowPlayingTick(now);
}
