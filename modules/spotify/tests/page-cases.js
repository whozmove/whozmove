// The Spotify module's part of the page, run outside the app by test.sh: what the now-playing strip shows for a song
// as Spotify reports it (now-playing.js), and its lyrics (lyrics.js). Nothing is drawn.
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
show('the question about lyrics, once the first note has been seen', nowPlayingView(song(), NOW, true, true).note);
show('the first note before the question', nowPlayingView(song(), NOW, false, true).note);
show('not allowed before the question', nowPlayingView(song({ allowed: false }), NOW, true, true).note);
state.lyrics = { state: 'ask' };
state.songNoteSeen = true;
state.lyricsAskAfter = 'spotify:track:1';
show('the question waits for the song after the one the first note was seen with', lyricsAsks(song()));
show('and comes with the next', lyricsAsks(song({ track: 'spotify:track:2' })));
state.lyrics = { state: 'off' };
show('answered no: not asked again', lyricsAsks(song({ track: 'spotify:track:2' })));

section('Lyrics (lyrics.js)');
show('reading LRC: times in ms, tags and lines without a time left out, word times taken out, a line sung twice given '
     + 'twice', lyricsLines('[ar:Example Artist]\r\n[00:08.00]First line\r\n[00:12.4] Second <00:13.10>line\r\n'
                            + '[01:02.345][01:30.00]Sung twice\r\nno time here\r\n[00:20.00]'));
show('out of order: sorted by time', lyricsLines('[00:05.00]Later\n[00:01.00]Sooner').map((l) => l.text));
show('at most 500 lines', lyricsLines(Array.from({ length: 600 }, (_, i) =>
  `[${String(Math.floor(i / 60)).padStart(2, '0')}:${String(i % 60).padStart(2, '0')}.00]Line ${i}`).join('\n')).length);
const LRC = '[00:08.00]First line\n[00:12.40]Second line\n[00:16.80]Third line\n[00:21.20]\n[00:30.00]After the break'
  + '\n[00:34.00]Last line\n[00:38.00]\n';
const lyrics = lyricsTaken({ state: 'timed', track: 'spotify:track:1', lrc: LRC });
show('the items: dots for the start and the break, the singing over at the last line with no words', lyrics);
show('a short start: no dots before the first line', lyricsItems(lyricsLines('[00:02.00]Early')).items);
show('a short pause: no dots',
     lyricsItems(lyricsLines('[00:01.00]One\n[00:03.00]\n[00:04.50]Two')).items.map((item) => item.kind));
show('nothing marking the end: over a while after the last line', lyricsItems(lyricsLines('[00:05.00]Only line')).over);
const at = (seconds) => seconds * 1000;
const words = (position, l = lyrics, inStrip = true, s = song()) => lyricsWords(l, s, position, inStrip);
show('the start: the song’s name', words(0));
show('just before the first line is lit (301ms early): still the name', words(at(8) - 301));
show('300ms before it: the first line', words(at(8) - 300));
show('in the break: the name again', words(at(25)));
show('after the singing: the name', words(at(38)));
show('the lyrics’ switch off: the name, with no lines in the strip', words(at(10), lyrics, false));
show('plain lyrics: the name', words(at(10), lyricsTaken({ state: 'plain', track: 'spotify:track:1', plain: 'Words' })));
show('another song’s lyrics: the name', words(at(10), lyrics, true, song({ track: 'spotify:track:2' })));
const early = lyricsTaken({ state: 'timed', track: 'spotify:track:1', lrc: '[00:02.00]Early\n[00:05.00]Next' });
show('before a first line with no dots: the name, just before it', words(0, early));
const roll = (a, b) => lyricsRoll(a, b);
show('on to the next line: rolls up', roll(words(at(9)), words(at(13))));
show('back a line: rolls down', roll(words(at(13)), words(at(9))));
show('a jump: the old go, then the new come', roll(words(at(9)), words(at(31))));
show('the same line: no change', roll(words(at(9)), words(at(10))));
show('from the name to the first line: rolls up', roll(words(at(1)), words(at(9))));
show('from the name to a first line with no dots: rolls up', roll(words(0, early), words(at(2), early)));
show('the last line to the end: rolls up', roll(words(at(35)), words(at(39))));
show('another song: rolls up', roll(words(at(9)), words(at(9), lyrics, true, song({ track: 'spotify:track:2' }))));
show('the switch turned off: rolls up', roll(words(at(9)), words(at(9), lyrics, false)));
show('nothing shown yet: at once', roll(null, words(at(9))));
show('the next change, during a line', lyricsNextIn(lyrics, at(10)));
show('the next change, in the break', lyricsNextIn(lyrics, at(22)));
show('after the singing: no more changes', lyricsNextIn(lyrics, at(40)) === Infinity);
const late = lyricsTaken({ state: 'timed', track: 'spotify:track:1', lrc: '[03:14.302]Last line' });
show('a change due just after the song’s end, where its clock stops: it never comes',
     lyricsNextIn(late, 195000, 200000) === Infinity);
show('nor at the end itself', lyricsNextIn(late, 200000, 200000) === Infinity);
show('one due by the end still comes', lyricsNextIn(late, 195000, 201000));
show('a state the page doesn’t know: off', lyricsTaken({ state: 'maybe' }));
show('lyrics with times and no lines: none', lyricsTaken({ state: 'timed', track: 'spotify:track:1', lrc: '[00:01.00]' }));
show('lyrics that aren’t text: none', lyricsTaken({ state: 'timed', track: 'spotify:track:1', lrc: 42 }));
show('plain lyrics in verses', lyricsStanzas('First\nSecond\n\n\nThird\r\nFourth'));
for (const kind of ['looking', 'none', 'failed', 'off'])
  show(`no lines to show, ${kind}`, lyricsMissing({ state: kind }));
show('lyrics to read, with times or without: they open',
     [lyrics, lyricsTaken({ state: 'plain', track: 'spotify:track:1', plain: 'Words' })].map(lyricsLoaded));
show('none to read yet, or at all: they don’t open', ['looking', 'none', 'failed', 'off'].map((state) => lyricsLoaded({ state })));
const say = (kind, s = song()) => lyricsSayWords(s, lyricsMissing({ state: kind }));
show('pressed while they’re on their way: the strip says so', say('looking'));
show('from the song’s name to what’s said: rolls up', roll(words(0), say('looking')));
show('what’s said changing: rolls up', roll(say('looking'), say('none')));
show('what’s said going, back to the name: rolls down', roll(say('none'), words(0)));
show('another song while it’s said: rolls up', roll(say('looking'), words(0, lyrics, true, song({ track: 'spotify:track:2' }))));
