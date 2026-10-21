// Spotify's part of the page: what it plugs into the page core (panel/scripts/modules.js) as it loads, and the
// functions the app calls with the song and its lyrics. The now-playing strip (np-strip.js) and what it shows
// (now-playing.js), and the lyrics (lyrics-view.js, from what lyrics.js works out), do the rest.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// The song Spotify is playing as the app last found it (setNowPlaying), and whether the now-playing strip's first note
// has been seen (kept across launches). Its lyrics as the app has them (setLyrics: lyricsTaken's), whether their lines
// show in the strip (the lyrics' switch, kept across launches), and the song the first note was seen with, as the
// question about lyrics waits for the next.
moduleState({ nowPlaying: null, songNoteSeen: store.get('songNoteSeen', false), lyrics: null,
              lyricsInStrip: store.get('lyricsInStrip', true), lyricsAskAfter: null });
core.pointerTargets.push('.np-strip', '.np-btn', '.np-note-btn');
core.strips.push('nowplaying');
// At the page's own time, as the lyrics' timer goes by it: the update's is when the app sent it, a moment before, which
// would put the song back a little and could light the line before the one being sung.
core.updates.push(() => nowPlayingTick(Date.now()));

// Folded, the panel shows nothing of Spotify's, neither the now-playing strip nor the token: the app is told.
function tellSpotifyCollapsed() {
  native({ type: 'spotify', action: 'collapsed', on: document.body.classList.contains('collapsed') });
}
core.collapses.push(tellSpotifyCollapsed);
core.collapses.push((collapsed) => { if (!collapsed) npUnfolded(); });

core.starts.push(() => {
  // The strip's controls, its line, its note's button and the song itself. It's outside the list, so it has a
  // listener of its own.
  npEl.addEventListener('mousedown', (e) => pressNowPlaying(e));
  tellSpotifyCollapsed();
});

// What Spotify is playing, as the app found it (app/Spotify.m), or null: what the now-playing strip shows, and the
// lyrics beside the list, while they're open.
window.setNowPlaying = (song) => {
  state.nowPlaying = song;
  nowPlayingTick(Date.now());
  if (lyricsReading()) drawReader();
};

// What the app knows of the song's lyrics (app/Lyrics.m), or null: what the strip's words and the lyrics beside the
// list show, which open if the strip was pressed for them while they were on their way. Turned off, the lyrics beside
// the list close: at once, or, with the strip folding away (Spotify removed), once it has gone (lyricsFolded).
window.setLyrics = (sent) => {
  state.lyrics = lyricsTaken(sent);
  lyricsCame(Date.now());
  nowPlayingTick(Date.now());
  if (!lyricsReading()) return;
  if (lyricsOn()) drawReader();
  else if (np.shown) closeReader();
};
