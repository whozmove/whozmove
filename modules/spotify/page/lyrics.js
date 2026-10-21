// The words of the song Spotify is playing, as LRCLIB gives them (app/Lyrics.m): their lines and the pauses between,
// read from LRC, and which line the now-playing strip and the lyrics beside the list show at a time.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// Plain functions: they take what they need and change nothing, so tests/test.sh checks every case. lyrics-view.js
// draws what they work out.

// A line is lit this long before it's sung, so the strip's words have rolled in by the time the singer starts it.
const LYRICS_LEAD_MS = 300;
// A pause between lines this long or longer (a line with no words marks where it starts) shows the song's name in the
// strip, and dots in the lyrics counting in to the next line; so does a start this long before the first line.
const LYRICS_BREAK_MS = 3000;
// When nothing marks the end of the singing, the last line shows this long, then the song's name comes back.
const LYRICS_LAST_MS = 6000;
// The most lines taken, and the most characters of each.
const LYRICS_MOST_LINES = 500, LYRICS_MOST_CHARACTERS = 300;
// Pressed before a song's lyrics are here, the strip says why for this long, in place of the song's name.
const LYRICS_SAY_MS = 2500;

// A line's words as text to show: no control characters, no word timings ("<01:02.50>"), at most so many characters.
function lyricsText(raw) {
  const text = raw.replace(/<\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?>/g, '').replace(/[\u0000-\u001f\u007f]/g, '').trim();
  return Array.from(text).slice(0, LYRICS_MOST_CHARACTERS).join('');
}

// LRC as [{t, text}], by when each line starts (ms): "[01:02.50]words", a line with several times given once for each,
// tags like "[ar:…]" and lines with no time left out.
function lyricsLines(lrc) {
  const lines = [];
  for (const raw of String(lrc || '').split(/\r?\n/)) {
    const times = [];
    let rest = raw, m;
    while ((m = /^\s*\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]/.exec(rest))) {
      const fraction = m[3] ? Number(m[3]) / 10 ** m[3].length : 0;
      times.push(Math.round((Number(m[1]) * 60 + Number(m[2]) + fraction) * 1000));
      rest = rest.slice(m[0].length);
    }
    const text = lyricsText(rest);
    for (const t of times) lines.push({ t, text });
  }
  return lines.sort((a, b) => a.t - b.t).slice(0, LYRICS_MOST_LINES);
}

// What the lyrics step through, in order: {kind: 'dots', t, until} for the quiet before the first line and each long
// pause, and {kind: 'line', t, text} for each line; and when the singing is over (`over`), at a line with no words
// after the last, or a while after it.
function lyricsItems(lines) {
  const sung = lines.filter((l) => l.text);
  if (!sung.length) return { items: [], over: 0 };
  const last = sung[sung.length - 1], end = lines.find((l) => !l.text && l.t > last.t);
  const items = [];
  if (sung[0].t >= LYRICS_BREAK_MS) items.push({ kind: 'dots', t: 0, until: sung[0].t });
  let next = null;  // the next line with words, from the end backwards
  const nexts = [];
  for (let i = lines.length - 1; i >= 0; i--) {
    nexts[i] = next;
    if (lines[i].text) next = lines[i];
  }
  lines.forEach((l, i) => {
    if (l.text) return void items.push({ kind: 'line', t: l.t, text: l.text });
    const following = nexts[i];
    if (!following || following.t - l.t < LYRICS_BREAK_MS || items[items.length - 1]?.kind === 'dots') return;
    items.push({ kind: 'dots', t: l.t, until: following.t });
  });
  return { items, over: end ? end.t : last.t + LYRICS_LAST_MS };
}

// Plain lyrics as their verses, each a list of lines: a line with no words between them.
function lyricsStanzas(plain) {
  const stanzas = [];
  let stanza = [], count = 0;
  for (const raw of String(plain || '').split(/\r?\n/)) {
    const line = lyricsText(raw);
    if (!line) {
      if (stanza.length) stanzas.push(stanza);
      stanza = [];
      continue;
    }
    if (++count > LYRICS_MOST_LINES) break;
    stanza.push(line);
  }
  if (stanza.length) stanzas.push(stanza);
  return stanzas;
}

// Whether `lyrics` have words to read, with times or without, rather than being on their way or not to be had.
function lyricsLoaded(lyrics) {
  return lyrics?.state === 'timed' || lyrics?.state === 'plain';
}

// The page's own copy of what the app says about lyrics (setLyrics): read, and anything unexpected taken as off, or as
// none for a song whose lyrics don't read.
function lyricsTaken(sent) {
  const STATES = ['ask', 'off', 'on', 'looking', 'timed', 'plain', 'none', 'failed'];
  if (!sent || !STATES.includes(sent.state)) return { state: 'off' };
  const track = typeof sent.track === 'string' ? sent.track : null;
  if (sent.state === 'timed') {
    const { items, over } = lyricsItems(lyricsLines(typeof sent.lrc === 'string' ? sent.lrc : ''));
    return items.length ? { state: 'timed', track, items, over } : { state: 'none', track };
  }
  if (sent.state === 'plain') {
    const stanzas = lyricsStanzas(typeof sent.plain === 'string' ? sent.plain : '');
    return stanzas.length ? { state: 'plain', track, stanzas } : { state: 'none', track };
  }
  return { state: sent.state, track };
}

// Which item is the one at `at` (ms into the song): the last to start by then, or the first before any has.
function lyricsItemAt(items, at) {
  let k = 0;
  for (let i = 0; i < items.length && items[i].t <= at; i++) k = i;
  return k;
}

// What the strip's words are at `position` (ms into `song`): the line being sung, while the song's lyrics have times
// and are to show in the strip (`inStrip`); otherwise, and whenever nobody's singing, the song's name. Each has a key
// (another key, other words), whether the lines are in the strip (`lines`), and its place among the lyrics' items
// (`order`: the song's name before the first is just before it, and once the singing's over, after the last), which
// says which way new words roll.
function lyricsWords(lyrics, song, position, inStrip) {
  const name = { key: `song:${song.track}`, track: song.track, lines: false, order: 0 };
  if (!inStrip || lyrics?.state !== 'timed' || lyrics.track !== song.track) return name;
  const at = position + LYRICS_LEAD_MS, k = lyricsItemAt(lyrics.items, at), item = lyrics.items[k];
  if (at >= lyrics.over) return { ...name, lines: true, order: lyrics.items.length };
  if (at < item.t) return { ...name, lines: true, order: k - 1 };
  if (item.kind !== 'line') return { ...name, lines: true, order: k };
  return { key: `line:${song.track}:${k}`, track: song.track, lines: true, order: k, text: item.text };
}

// The strip's words while it says why the lyrics don't open (`text`, as lyricsMissing has it), in place of the song's
// name.
function lyricsSayWords(song, text) {
  return { key: `say:${song.track}:${text}`, track: song.track, lines: false, order: 0, text, say: true };
}

// How the strip's words go from `was` to `want`: not at all (none), all at once (instant: there were none), rolling up
// as the song moves on, another song comes, the lines come into the strip or leave it, or the strip says why the lyrics
// don't open (up), down when it goes back a line or has said it (down), or the old going before the new come, for a
// jump (swap).
function lyricsRoll(was, want) {
  if (!was) return 'instant';
  if (was.key === want.key) return 'none';
  if (was.track !== want.track || want.say) return 'up';
  if (was.say) return 'down';
  if (was.lines !== want.lines) return 'up';
  const step = want.order - was.order;
  return step === 1 ? 'up' : step === -1 ? 'down' : 'swap';
}

// How long from `position` until the words change next (ms), or Infinity when they won't: a change after the end of the
// song (`durationMs`), where its clock stops, never comes.
function lyricsNextIn(lyrics, position, durationMs = 0) {
  if (lyrics?.state !== 'timed') return Infinity;
  const at = position + LYRICS_LEAD_MS, end = durationMs > 0 ? durationMs + LYRICS_LEAD_MS : Infinity;
  const next = lyrics.items.find((item) => item.t > at);
  const times = [next?.t, lyrics.over].filter((t) => t > at && t <= end);
  return times.length ? Math.min(...times) - at : Infinity;
}

// What's said where a song's lyrics would be while there are none to show (beside the list, and in the strip when it's
// pressed): they're on their way, or they're not to be had, as LRCLIB doesn't have them, the song has no words, or
// LRCLIB hasn't answered for a while.
function lyricsMissing(lyrics) {
  if (lyrics?.state === 'looking' || lyrics?.state === 'on') return 'Loading lyrics…';
  if (lyrics?.state === 'none' || lyrics?.state === 'failed') return 'Lyrics not available';
  return 'Lyrics are off.';
}
