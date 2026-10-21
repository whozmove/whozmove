// Spotify's lyrics on the page: the one timer that changes the now-playing strip's words as the song moves on
// (np-strip.js draws them, lyrics.js works out which), the lyrics beside the list (a reader mode about none of the
// sessions), which open only once they're here (until then, the strip says why), and your answer about them.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// The lines follow the song's own clock (songPosition: where Spotify last said it was, moved on since), not the
// once-a-second update: a timer is set for the next change of words, and set again at each update, song, jump, pause
// and switch. The lyrics beside the list move by a CSS transition, and their dots by animations kept to the song's
// clock, so nothing runs every frame. Nothing is built before it's needed, as the page's tests load every script.

// The lyrics beside the list: this wide, with at least this much room for their lines.
const LYRICS_READER_WIDTH = 380, LYRICS_VIEW_HEIGHT = 330;
// Their foot: whether the lines show in the strip too (its state is set on it, so its knob slides: the panel's switch,
// controls.css), and Spotify.
const LYRICS_FOOT = `<button class="ly-switch" role="switch" aria-checked="true">${SWITCH}Show lyrics in the strip`
  + '</button><button class="ly-open">Open Spotify</button>';
const ly = {
  timer: null,  // the next change of the words
  dots: null,   // the dots counting in to the next line beside the list: {line, animations}
  say: null,    // the strip saying why the lyrics don't open, after a press: {track, until}
};

// Whether you've said yes to lyrics: anything but the question unanswered, or off.
function lyricsOn() {
  return !['ask', 'off', undefined].includes(state.lyrics?.state);
}

// The lyrics of `song`, if they're what the app has: a moment after a new song starts, they're still the last one's.
function lyricsOfSong(song) {
  return song && state.lyrics?.track === song.track ? state.lyrics : null;
}

// Whether the strip asks about lyrics now: not answered yet, and once the first note has been seen, from the next song
// on (one note at a time).
function lyricsAsks(song) {
  return !!song && state.lyrics?.state === 'ask' && state.songNoteSeen && state.lyricsAskAfter !== song.track;
}

// The strip's words at `now`: why the lyrics don't open, for a moment after a press; or the line being sung, or the
// song's name.
function lyricsStripWords(now) {
  const song = state.nowPlaying, lyrics = lyricsOfSong(song);
  if (lyricsSaying(song, now)) return lyricsSayWords(song, lyricsMissing(lyrics || { state: 'looking' }));
  return lyricsWords(lyrics, song, songPosition(song, now), state.lyricsInStrip);
}

// Whether the strip is saying why the lyrics don't open, at `now`: only about the song it was pressed for.
function lyricsSaying(song, now) {
  return !!song && ly.say?.track === song.track && now < ly.say.until;
}

function lyricsReading() {
  return state.reading?.mode === 'lyrics' && !state.reading.closing;
}

// The lyrics beside the list as they are at `now`, and a timer for the next change of words: the end of what the strip
// says, and the next line while the song plays and its lines show somewhere (in the strip while it's in sight, or
// beside the list).
function lyricsFollow(now) {
  clearTimeout(ly.timer);
  ly.timer = null;
  const song = state.nowPlaying, lyrics = lyricsOfSong(song);
  if (ly.say && !lyricsSaying(song, now)) ly.say = null;
  if (lyricsReading()) lyricsStep(now);
  let wait = ly.say ? ly.say.until - now : Infinity;
  if (song?.playing && lyrics?.state === 'timed' && ((state.lyricsInStrip && npInSight()) || lyricsReading()))
    wait = Math.min(wait, lyricsNextIn(lyrics, songPosition(song, now), song.durationMs));
  if (wait !== Infinity) ly.timer = setTimeout(() => nowPlayingTick(Date.now()), wait + 10);
}

// The strip has folded away (the song stopped, it was paused long enough, or Spotify was removed): nothing follows the
// song, and its lyrics close, so the panel folds back to the list as it is without the strip.
function lyricsFolded() {
  clearTimeout(ly.timer);
  ly.timer = null;
  ly.say = null;
  if (lyricsReading()) closeReader();
}

// Your answer about lyrics, from the strip's question: the app keeps it, and the strip shows it at once.
function lyricsAnswer(on) {
  native({ type: 'spotify', action: 'lyrics', on });
  const track = state.nowPlaying?.track;
  state.lyrics = !on ? { state: 'off' } : track ? { state: 'looking', track } : { state: 'on' };
  nowPlayingTick(Date.now());
}

function toggleLyrics() {
  toggleReader(null, null, 'lyrics');
}

// The strip pressed, once lyrics are on: the song's lyrics open beside the list if they're here, and close if they're
// open. Until they're here, the strip says why for a moment, and they open if they come meanwhile (lyricsCame).
function pressLyrics(now) {
  if (lyricsReading() || lyricsLoaded(lyricsOfSong(state.nowPlaying))) return toggleLyrics();
  ly.say = { track: state.nowPlaying.track, until: now + LYRICS_SAY_MS };
  nowPlayingTick(now);
}

// The app has said more about the lyrics: if they've come while the strip says they're on their way, they open, unless
// the reader has been opened on something else since (a session's plan, say), which they'd take the place of: then the
// strip just stops saying it.
function lyricsCame(now) {
  if (!lyricsSaying(state.nowPlaying, now) || !lyricsLoaded(lyricsOfSong(state.nowPlaying))) return;
  ly.say = null;
  if (!state.reading) toggleLyrics();
}

// ---- Beside the list ----

// The song's cover, name and singer above; its lines, or what there is instead, in the middle, built again only when
// the song or what's known of its lyrics changes; and the foot.
function drawLyrics() {
  const r = state.reading, song = state.nowPlaying;
  if (!song) return;
  const shown = lyricsOfSong(song) || (lyricsOn() ? { state: 'looking', track: song.track } : state.lyrics);
  const head = `<span class="ly-art">${song.artUrl ? `<img src="${esc(song.artUrl)}" alt="">` : ''}</span>
    <span class="r-title">${esc(song.title || 'Unknown song')}</span><span class="r-sub">${esc(song.artist || '')}</span>
    <button class="r-close" title="Close">${CLOSE_ICON}</button>`;
  let changed = putHTML(reader.querySelector('.r-head'), head);
  const foot = reader.querySelector('.r-answer');
  changed = putHTML(foot, LYRICS_FOOT) || changed;
  foot.querySelector('.ly-switch').setAttribute('aria-checked', String(state.lyricsInStrip));
  const key = `${shown?.track}@${shown?.state}`;
  if (r.lyricsShown === key) {
    if (changed) {
      fitReader();
      syncHover();
    }
    return;
  }
  const first = r.lyricsShown === undefined;
  r.lyricsShown = key;
  const body = reader.querySelector('.r-body');
  const fill = () => {
    lyricsDotsGone();
    body.innerHTML = lyricsBodyHTML(shown);
    r.lyricsAt = -1;
    r.ready = true;
    fitReader();
    syncHover();
    lyricsStep(Date.now(), 'instant');
  };
  if (first || calm.matches) fill();
  else lyricsRefill(body, fill);
}

// The lines, each a button that takes the song there (the dots of a pause too), and where they came from; or plain
// lyrics, which don't follow the song; or why there are none. Their words go in as text.
function lyricsBodyHTML(shown) {
  if (shown?.state === 'timed') {
    const lines = shown.items.map((item, i) => `<button class="ly-line" data-i="${i}" dir="auto">${
      item.kind === 'dots' ? '<span class="ly-dots"><i></i><i></i><i></i></span>' : esc(item.text)}</button>`).join('');
    return `<div class="ly-view" data-track="${esc(shown.track)}"><div class="ly-col">${lines}`
      + '<div class="ly-credit">Lyrics from LRCLIB</div></div></div>';
  }
  if (shown?.state === 'plain') {
    const verses = shown.stanzas.map((stanza) => `<p dir="auto">${stanza.map(esc).join('<br>')}</p>`).join('');
    return `<div class="ly-plain"><p class="ly-note">These lyrics have no timings, so they don’t follow the song.</p>`
      + `${verses}<p class="ly-credit">Lyrics from LRCLIB</p></div>`;
  }
  return `<div class="r-missing">${esc(lyricsMissing(shown))}</div>`;
}

// What's shown goes, then the new comes in the panel's way (fading in, lifting 3px, sharpening): a new song's lyrics,
// or what's known of them changing. Changed again while the old is going (a new song's lyrics are often known a moment
// after it), the newest comes in once it has gone; and nothing comes in if the reader has turned to something else by
// then.
function lyricsRefill(body, fill) {
  const r = state.reading, old = body.firstElementChild;
  if (r.lyricsFill) return void (r.lyricsFill = fill);
  if (!old) return fill();
  r.lyricsFill = fill;
  tween(old, { opacity: '1' }, { opacity: '0' }, () => {
    const latest = r.lyricsFill;
    r.lyricsFill = null;
    if (!latest || state.reading !== r || r.mode !== 'lyrics') return;
    latest();
    body.firstElementChild?.animate([{ opacity: 0, transform: 'translateY(3px)', filter: 'blur(1.5px)' },
                                     { opacity: 1, transform: 'none', filter: 'blur(0)' }],
                                    { duration: 420, easing: MORPH_EASE });
  }, 160, 'ease');
}

// The lines at `now`: the one being sung lit and those sung dimmed, and the column moved so it's about a third of the
// way down, when that's another line, or `again` (the lyrics have changed height), or at once (`instant`: they've just
// been drawn; or under reduced motion). Paused, the lit line dims a little. Only the song's own lines are moved: the
// last song's, going, stay as they were.
function lyricsStep(now, how) {
  const r = state.reading, song = state.nowPlaying, lyrics = lyricsOfSong(song);
  const view = reader.querySelector('.ly-view'), col = view?.firstElementChild;
  if (!r || !col || lyrics?.state !== 'timed' || view.dataset.track !== lyrics.track) return;
  const position = songPosition(song, now), k = lyricsItemAt(lyrics.items, position + LYRICS_LEAD_MS);
  const lines = col.querySelectorAll('.ly-line');
  if (!lines[k]) return;
  if (k !== r.lyricsAt || how) {
    r.lyricsAt = k;
    lines.forEach((line, i) => {
      line.classList.toggle('past', i < k);
      line.classList.toggle('now', i === k);
    });
    const still = how === 'instant' || calm.matches;
    if (still) col.style.transition = 'none';
    col.style.transform = `translateY(${Math.round(view.clientHeight * 0.3) - lines[k].offsetTop}px)`;
    if (still) {
      col.offsetHeight;  // in place before the transition comes back
      col.style.transition = '';
    }
  }
  col.classList.toggle('paused', !song.playing);
  lyricsDots(lyrics.items[k], lines[k], position, song.playing);
}

// A pause's dots count in to the next line: each fills in turn over a third of it, kept to the song's clock, and still
// while the song is paused.
function lyricsDots(item, line, position, playing) {
  if (ly.dots && ly.dots.line !== line) lyricsDotsGone();
  if (item?.kind !== 'dots') return;
  if (!ly.dots) {
    const third = (item.until - item.t) / 3;
    const fill = calm.matches ? [{ opacity: 0.3 }, { opacity: 0.95 }]
                              : [{ opacity: 0.3, transform: 'scale(.8)' }, { opacity: 0.95, transform: 'none' }];
    ly.dots = { line, animations: [...line.querySelectorAll('.ly-dots i')].map((dot, j) =>
      dot.animate(fill, { duration: third, delay: j * third, fill: 'both' })) };
  }
  const into = position + LYRICS_LEAD_MS - item.t;
  for (const animation of ly.dots.animations) {
    if (Math.abs((animation.currentTime ?? 0) - into) > 250) animation.currentTime = into;
    if (!playing) animation.pause();
    else if (animation.playState === 'paused') {
      // A dot that had filled would start again from empty as it plays: it's put back where the song is.
      animation.play();
      animation.currentTime = into;
    }
  }
}

function lyricsDotsGone() {
  ly.dots?.animations.forEach((animation) => animation.cancel());
  ly.dots = null;
}

// A line pressed: the song goes there, in Spotify and at once here.
function lyricsSeek(i) {
  const song = state.nowPlaying, item = lyricsOfSong(song)?.items?.[i];
  if (item && song.durationMs > 0) controlSong('seek', Math.min(1, item.t / song.durationMs));
}

// ---- What it plugs into ----

// The reader's mode, about none of the sessions. What it keeps on the reader (state.reading): the song and state its
// lines were drawn for (lyricsShown), which line was lit (lyricsAt), and what comes in once what's shown has gone
// (lyricsFill).
core.readerModes.lyrics = {
  sessionless: true,
  width: () => LYRICS_READER_WIDTH,
  draw: drawLyrics,
  contentHeight: () => LYRICS_VIEW_HEIGHT,
  shown(r) {
    r.lyricsShown = undefined;
    r.lyricsAt = -1;
    r.lyricsFill = null;
    npEl.classList.add('lyrics-open');
  },
  reset(r) {
    r.lyricsShown = undefined;
    r.lyricsFill = null;
    lyricsDotsGone();
  },
  cls: 'k-lyrics',
};
core.readerPresses.push(
  ['.ly-line[data-i]', (line) => lyricsSeek(Number(line.dataset.i))],
  ['.ly-switch', () => {
    state.lyricsInStrip = !state.lyricsInStrip;
    store.set('lyricsInStrip', state.lyricsInStrip);
    drawReader();
    nowPlayingTick(Date.now());
  }],
  ['.ly-open', () => native({ type: 'spotify', action: 'open' })],
);
// While the lyrics are open, the strip's cover keeps the lyrics mark; it goes once they've closed.
core.afterDraw.push(() => npEl.classList.toggle('lyrics-open', lyricsReading()));
// The panel changing height beside the lyrics changes theirs: the line being sung goes back to its place about a third
// of the way down. As the panel grows for them, that's at once, before they show (reader.css); after, it glides there.
core.starts.push(() => window.addEventListener('resize', () => {
  if (lyricsReading()) lyricsStep(Date.now(), document.body.classList.contains('reader-shown') ? 'again' : 'instant');
}));
