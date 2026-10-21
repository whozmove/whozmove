// The now-playing strip, above the usage strip: the song Spotify is playing (now-playing.js says what shows), with a
// thin line along its top edge for how far in it is. Once you've said yes to lyrics, the line being sung takes the
// place of the song's name while it's sung (lyrics.js says which), and pressing the strip opens them all beside the
// list (lyrics-view.js), or says why it can't yet; until then, pressing it brings Spotify forward. Pointed at, the time
// gives way to back, pause and next, and the line along the top can be pressed to jump. Paused for 15 minutes, it folds
// away into Spotify's token at the panel's corner. A note under it says where to hide it the first time, asks about
// lyrics after that, and says what to do when macOS hasn't allowed Whozmove to control Spotify.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// Like the usage strip, it isn't in the list, so it's built once and only its text, cover and widths change. Its
// motion follows CONTRIBUTING.md's rules: it grows in and folds away with the panel's bottom edge; its words (a new
// song's name, or a line) roll in place as the cover cross-fades; and the time leaves its lane before the controls come
// into it.

// The strip's controls: back, pause or play, and next; and the microphone on the cover once lyrics are on.
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
  mic: '<svg width="12" height="12" viewBox="0 0 12 12"><rect x="4.1" y="1" width="3.8" height="6.2" rx="1.9" '
    + 'fill="currentColor"/><path d="M2.4 5.6a3.6 3.6 0 0 0 7.2 0M6 9.3v1.7" fill="none" stroke="currentColor" '
    + 'stroke-width="1.2" stroke-linecap="round"/></svg>',
};

const npEl = document.getElementById('nowplaying');
const np = {
  built: false, shown: false,
  moving: false,  // growing in or folding away: presses wait, and what changes meanwhile is drawn once it's done
  track: null,    // the song on show
  words: null,    // what its words show (lyricsWords): the song's name, or a line
  wanted: null,   // words that came while others were rolling in, drawn once they have
  art: null,      // the cover wanted
  note: null,     // the note on show: first, refused, lyrics or none
};
// A new song's cover usually comes a moment after it: the last one stays this long for it, then the square shows.
const COVER_WAIT_MS = 4000;
// The strip's words have two rows' room (12px text on 15px rows): a line that needs more is a size smaller.
const NP_WORDS_HEIGHT = 30;

function npParts() {
  if (np.built) return np.parts;
  npEl.innerHTML = `
    <div class="np-strip" title="Open Spotify">
      <span class="np-bar" title="Jump"><span class="np-line"><span class="np-fill"></span></span></span>
      <span class="np-art"><img class="np-img" alt=""><img class="np-img" alt=""><span class="np-mic">${SONG_ICONS.mic}</span></span>
      <span class="np-text"></span>
      <span class="np-side">
        <span class="np-clock"></span>
        <span class="np-controls">
          <button class="np-btn" data-do="previous" title="Back">${SONG_ICONS.previous}</button>
          <button class="np-btn np-play" data-do="playpause" title="Pause">${SONG_ICONS.pause}</button>
          <button class="np-btn" data-do="next" title="Next">${SONG_ICONS.next}</button>
        </span>
      </span>
    </div>
    <div class="np-note" hidden><span class="np-note-text"></span><button class="np-note-btn"></button><button
      class="np-note-btn np-x np-close" hidden>×</button></div>`;
  const q = (sel) => npEl.querySelector(sel);
  np.parts = { strip: q('.np-strip'), fill: q('.np-fill'), art: q('.np-art'),
               imgs: [...npEl.querySelectorAll('.np-img')],
               text: q('.np-text'), clock: q('.np-clock'), play: q('.np-play'),
               note: q('.np-note'), noteText: q('.np-note-text'), noteButton: q('.np-note-btn:not(.np-close)'),
               noteClose: q('.np-close') };
  // A cover fades in once it has loaded, on top of the one before, which goes only once it's covered; one that
  // doesn't load leaves the plain square. The microphone stays above them both.
  for (const img of np.parts.imgs) {
    img.addEventListener('load', () => {
      if (img.dataset.want !== np.art) return;
      const other = np.parts.imgs.find((o) => o !== img);
      img.parentNode.insertBefore(img, img.parentNode.querySelector('.np-mic'));
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

// ---- Each second, whenever the app has something new, and at each change of the lyrics' lines ----

function nowPlayingTick(now) {
  if (np.moving) return;  // drawn again once the strip has grown in or folded away
  const view = nowPlayingView(state.nowPlaying, now, state.songNoteSeen, lyricsAsks(state.nowPlaying));
  if (view.state === 'hidden') {
    if (np.shown) npFold();
    return;
  }
  npParts();
  if (np.shown) return npDraw(view, false, now);
  npDraw(view, true, now);
  np.shown = true;
  npGrow();
}

function npDraw(view, fresh, now) {
  const p = np.parts;
  const newSong = view.track !== np.track;
  npWords(lyricsStripWords(now), view, fresh);
  npFitLine(p.text.querySelector(':scope > .np-lyric'));  // one drawn out of sight, now it can be measured
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
  // Once lyrics are on, the strip opens them (and the cover shows a microphone while it's pointed at).
  const lyrics = lyricsOn();
  npEl.classList.toggle('lyrics-on', lyrics);
  p.strip.title = lyrics ? 'Lyrics' : 'Open Spotify';
  npNote(view.note);
  lyricsFollow(now);
}

// The strip's words (`want`, from lyricsWords): the song's name, or the line being sung. Drawn at once the first time,
// under reduced motion and out of sight (the panel folded into the cat); otherwise they roll in place, up as the song
// moves on and down when it goes back a line, or, for a jump, the old go before the new come. From one song's name to
// the next, its title and its artist each roll on their own, and only if they've changed. Words that come while others
// are on their way wait for them, then go on from what's shown to the newest, so a quick second change never leaves the
// strip blank.
function npWords(want, view, fresh) {
  const p = np.parts;
  if (p.text.rolling) {
    np.wanted = { want, view };
    return;
  }
  const was = np.words;
  let how = lyricsRoll(was, want);
  np.words = want;
  if (how === 'none') {
    // The same words: a song's name is kept as Spotify gives it (its title can come a moment after the song).
    if (!want.text) {
      setText(p.text.querySelector('.np-title'), view.title);
      setText(p.text.querySelector('.np-artist'), view.artist);
    }
    return;
  }
  if (fresh || calm.matches || !npInSight()) how = 'instant';
  if (how !== 'instant' && !want.text && !was.text) return npRollName(view);
  const before = { el: p.text.cloneNode(true), height: p.text.offsetHeight };
  p.text.innerHTML = want.text
    ? `<span class="np-lyric${want.say ? ' np-say' : ''}" dir="auto">${esc(want.text)}</span>`
    : `<span class="np-title">${esc(view.title)}</span><span class="np-artist">${esc(view.artist)}</span>`;
  npFitLine(p.text.querySelector(':scope > .np-lyric'));
  if (how === 'instant') return;
  if (how === 'swap') npSwapWords(p.text, before.el);
  else rollLine(null, p.text, before, how === 'down');
  p.text.rolling = setTimeout(npRolled, how === 'swap' ? 620 : MORPH_MS + 40);
}

// From one song's name to the next: its title and its artist each roll up on their own, and only if they've changed, so
// an album's artist stays put from song to song.
function npRollName(view) {
  const p = np.parts;
  let rolled = false;
  for (const [part, text] of [['.np-title', view.title], ['.np-artist', view.artist]]) {
    const el = p.text.querySelector(`:scope > ${part}`);
    if (!el || el.textContent === text) continue;
    const was = { el: el.cloneNode(true), height: el.offsetHeight };
    el.textContent = text;
    rollLine(null, el, was, false);
    rolled = true;
  }
  if (rolled) p.text.rolling = setTimeout(npRolled, MORPH_MS + 40);
}

// Words have rolled in: any that came meanwhile go on from them.
function npRolled() {
  np.parts.text.rolling = null;
  const next = np.wanted;
  np.wanted = null;
  if (next) npWords(next.want, next.view, false);
}

// Words on their way stop where they are, as the strip has gone out of sight (it folded away, or the panel was folded
// into the cat): they're drawn afresh, at once, when it's back. It gets a new box for them, as a roll's own timers go
// on, and would otherwise change the words drawn next.
function npStopRolling() {
  const p = np.parts, text = document.createElement('span');
  clearTimeout(p.text.rolling);
  np.wanted = null;
  np.words = null;
  text.className = 'np-text';
  p.text.replaceWith(text);
  p.text = text;
}

// Whether the strip can be seen: it's shown, and the panel isn't folded into the cat.
function npInSight() {
  return !npEl.hidden && !document.body.classList.contains('collapsed');
}

// The panel is open again after being folded into the cat: the strip shows what's true at once, rather than rolling to
// it from what it showed as it folded.
function npUnfolded() {
  if (!np.built) return;
  if (np.parts.text.rolling) npStopRolling();
  else np.words = null;
  nowPlayingTick(Date.now());
}

// A line that needs more than the two rows the song's name has goes a size smaller, rather than being cut short. It's
// measured once it can be: one drawn out of sight is measured when it's drawn again in sight.
function npFitLine(lyric) {
  if (!lyric || lyric.dataset.fit) return;
  lyric.classList.add('np-measure');
  const height = lyric.offsetHeight;
  lyric.classList.remove('np-measure');
  if (!height) return;
  lyric.dataset.fit = 'yes';
  lyric.classList.toggle('tight', height > NP_WORDS_HEIGHT);
}

// A jump in the song: the words shown go, and then the new come in the panel's way (fading in, lifting 3px,
// sharpening), so the two never share the strip's room.
function npSwapWords(text, old) {
  const arriving = [...text.children];
  Object.assign(old.style, { position: 'absolute', left: '0', right: '0', top: '0', margin: '0',
                             pointerEvents: 'none' });
  text.append(old);
  tween(old, { opacity: '1' }, { opacity: '0' }, () => old.remove(), 160, 'ease');
  for (const el of arriving)
    el.animate([{ opacity: 0, transform: 'translateY(3px)', filter: 'blur(1.5px)' },
                { opacity: 1, transform: 'none', filter: 'blur(0)' }],
               { duration: 420, delay: 160, easing: MORPH_EASE, fill: 'backwards' });
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
    p.noteClose.hidden = !note.close;
    p.noteClose.dataset.does = note.close || '';
    p.noteClose.title = note.closeTitle || '';
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
  npFitLine(np.parts.text.querySelector(':scope > .np-lyric'));  // drawn before it was shown
  if (calm.matches || document.body.classList.contains('collapsed')) return reportHeight();
  np.moving = true;
  growIn(npEl, 0, npSettled);
}

// Once it has grown in or folded away, whatever changed meanwhile (the song gone, or back) is drawn.
function npSettled() {
  np.moving = false;
  nowPlayingTick(Date.now());
}

// It fades as it eases away to nothing, and the panel's bottom edge comes up with it; the lyrics beside the list close
// once it has gone, so the panel folds back to the list without it. The first note has been seen once the strip has
// shown it.
function npFold() {
  np.shown = false;
  np.track = null;
  clearTimeout(np.parts.text.rolling);  // nothing more rolls in as it goes
  np.parts.text.rolling = null;
  np.wanted = null;
  if (np.note === 'first') seeSongNote();
  // The app is told once it has gone, so Spotify's token comes out only then. Words still rolling stop then: it comes
  // back with what's true when it does, at once.
  const done = () => {
    native({ type: 'spotify', action: 'folded' });
    npEl.hidden = true;
    np.art = null;
    clearTimeout(np.coverTimer);
    np.parts.imgs.forEach((img) => img.classList.remove('on'));
    npStopRolling();
    lyricsFolded();
    reportHeight();
    syncHover();
    npSettled();
  };
  if (calm.matches || document.body.classList.contains('collapsed')) return done();
  np.moving = true;
  foldAway(npEl, done);
}

// The first note has been seen: the question about lyrics comes with the next song, not straight after it.
function seeSongNote() {
  state.songNoteSeen = true;
  state.lyricsAskAfter = state.nowPlaying?.track ?? null;
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
  const does = e.target.closest('.np-note-btn')?.dataset.does;
  if (does === 'dismiss') {
    seeSongNote();
    return nowPlayingTick(Date.now());
  }
  if (does === 'settings') return native({ type: 'spotify', action: 'settings' });
  if (does === 'lyrics' || does === 'nolyrics') return lyricsAnswer(does === 'lyrics');
  // Anywhere else on the strip: its lyrics beside the list once you've said yes to them, and Spotify until then.
  if (!e.target.closest('.np-strip')) return;
  if (lyricsOn()) return pressLyrics(Date.now());
  native({ type: 'spotify', action: 'open' });
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
