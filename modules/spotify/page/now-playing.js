// What the now-playing strip shows (np-strip.js draws it), from the song Spotify is playing as the app found it
// (app/Spotify.m): the song, where it's at, and the note under it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// Plain functions: they take what they need (`now` among it) and change nothing, so tests/panel.sh checks every case.

// A song paused stays in the strip this long, then folds into Spotify's token at the panel's corner
// (app/SpotifyToken.m); app/Spotify.m's kPausedInStripMs is the same, so the two hand over together.
const PAUSED_IN_STRIP_MS = 15 * 60 * 1000;

// Where the song is at `now`, in ms: where it was when the app last looked, moved on since while it plays, and never
// past its end.
function songPosition(song, now) {
  const at = song.positionMs + (song.playing ? Math.max(0, now - song.at) : 0);
  return song.durationMs > 0 ? Math.min(at, song.durationMs) : at;
}

// "3:07", "1:02:45".
function songClock(ms) {
  const s = Math.floor(Math.max(0, ms) / 1000), h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60;
  const ss = String(s % 60).padStart(2, '0');
  return h ? `${h}:${String(m).padStart(2, '0')}:${ss}` : `${m}:${ss}`;
}

// The strip for a song at `now`: while it plays, and for a while after it's paused (since `pausedSince`; 0 for one
// found paused); then it folds into the token. `noteSeen` is whether the first note ("Spotify's song shows here…") has
// been seen; a refusal from macOS takes its place, as it needs you. Once it's been seen, the question about lyrics comes
// while `askLyrics` (one note at a time).
function nowPlayingView(song, now, noteSeen, askLyrics = false) {
  if (!song || (!song.playing && now - (song.pausedSince || 0) >= PAUSED_IN_STRIP_MS)) return { state: 'hidden' };
  const at = songPosition(song, now);
  return {
    state: song.playing ? 'playing' : 'paused',
    track: song.track,
    title: song.title || 'Unknown song',
    artist: song.artist || '',
    art: song.artUrl || null,
    progress: song.durationMs > 0 ? at / song.durationMs : 0,
    clock: song.playing ? songClock(at) : 'Paused',
    note: song.allowed === false ? 'refused' : !noteSeen ? 'first' : askLyrics ? 'lyrics' : null,
  };
}

// The note's words and its button, by kind, and a × beside it (`close`, saying what it does: `closeTitle`) for one that
// has two answers.
const SONG_NOTES = {
  first: { text: 'Spotify’s song shows here while it plays. Spotify, on the panel’s back, can turn it off.',
           button: '×', does: 'dismiss' },
  refused: { text: 'Whozmove isn’t allowed to control Spotify.', button: 'Open Settings', does: 'settings' },
  lyrics: { text: 'Show lyrics as they’re sung? Whozmove finds them on LRCLIB.', button: 'Show Lyrics', does: 'lyrics',
            close: 'nolyrics', closeTitle: 'Don’t show lyrics. Spotify, on the panel’s back, can turn them on.' },
};
