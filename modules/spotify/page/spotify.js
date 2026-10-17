// Spotify's part of the page: what it plugs into the page core (panel/scripts/modules.js) as it loads, and the function
// the app calls with the song. The now-playing strip (np-strip.js) and what it shows (now-playing.js) do the rest.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// The song Spotify is playing as the app last found it (setNowPlaying), and whether the now-playing strip's first note
// has been seen (kept across launches).
moduleState({ nowPlaying: null, songNoteSeen: store.get('songNoteSeen', false) });
core.pointerTargets.push('.np-strip', '.np-btn', '.np-text', '.np-note-btn');
core.strips.push('nowplaying');
core.updates.push((now) => nowPlayingTick(now));

// Folded, the panel has no room for the now-playing strip, so Spotify's token stands in for it: the app is told.
function tellSpotifyCollapsed() {
  native({ type: 'spotify', action: 'collapsed', on: document.body.classList.contains('collapsed') });
}
core.collapses.push(tellSpotifyCollapsed);

core.starts.push(() => {
  // The strip's controls, its line, its note's button and the song itself. It's outside the list, so it has a
  // listener of its own.
  npEl.addEventListener('mousedown', (e) => pressNowPlaying(e));
  tellSpotifyCollapsed();
});

// What Spotify is playing, as the app found it (app/Spotify.m), or null: what the now-playing strip shows.
window.setNowPlaying = (song) => {
  state.nowPlaying = song;
  nowPlayingTick(Date.now());
};
