// The Spotify module's part of the page, run outside the app by test.sh: what the now-playing strip shows for a song
// as Spotify reports it (now-playing.js). Nothing is drawn.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

load('tests/page-harness.js');  // the stand-ins, the page's scripts and the helpers below use

section('Now playing (now-playing.js)');
const song = (fields) => Object.assign({
  track: 'spotify:track:1', title: 'Example Song', artist: 'Example Artist', album: 'Example Album', durationMs: 200000,
  positionMs: 60000,
  at: NOW, playing: true,
}, fields);
show('playing, as the app found it', nowPlayingView(song(), NOW, true));
show('playing, 7s later: the line and the time move on', nowPlayingView(song(), NOW + 7000, true));
show('never past the end', nowPlayingView(song(), NOW + 600000, true).clock);
show('paused just now: the time stands still, and says so',
     nowPlayingView(song({ playing: false, pausedSince: NOW }), NOW + 7000, true));
show('paused 14 minutes: still in the strip', nowPlayingView(song({ playing: false, pausedSince: NOW }), NOW + 14 * 60000, true).state);
show('paused 15 minutes: folded into the token', nowPlayingView(song({ playing: false, pausedSince: NOW }), NOW + 15 * 60000, true).state);
show('found paused (Whozmove just started): in the token', nowPlayingView(song({ playing: false, pausedSince: 0 }), NOW, true).state);
show('nothing playing', nowPlayingView(null, NOW, true).state);
show('with a cover', nowPlayingView(song({ artUrl: 'https://i.scdn.co/image/ab67' }), NOW, true).art);
show('no title or length', nowPlayingView(song({ title: '', durationMs: 0 }), NOW, true));
show('the first note, until seen', nowPlayingView(song(), NOW, false).note);
show('not allowed: the note says what to do, even before the first is seen',
     nowPlayingView(song({ allowed: false }), NOW, false).note);
show('allowed', nowPlayingView(song({ allowed: true }), NOW, true).note);
show('an hour-long song', songClock(3725000));
