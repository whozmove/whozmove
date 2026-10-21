# Spotify

The song the Spotify app on this Mac is playing, in the now-playing strip at the panel's bottom; its lyrics from LRCLIB,
once you've said yes, each line in the strip in place of the song's name while it's sung, and the whole song beside the
list when the strip is pressed, once they're here; and Spotify's round token, tucked half under the panel at its
corner, which plays, resumes or gets Spotify. Spotify ▸ in the pawn menu brings Spotify forward (Open Spotify, as the
strip opens the lyrics once they're on), turns the lyrics on or off (Show Lyrics), hides the token (Hide Side Icon) or
takes the whole module out of the panel (Remove Spotify).

## Its pieces

- `app/SpotifyModule.m`: its face for the core (contracts/Module.h). It makes Spotify, its lyrics and the token when
  the app starts, holds the token under the panel and follows the glass and the pointer for it (PanelWindow's
  `attachBelow:`, `followGlass:`, `followPointer:`), answers the page's `spotify` messages, puts Spotify ▸ in the pawn
  menu, and has the print mode the tests check (`--print-spotify`).
- `app/Spotify.m`: the song, from what Spotify tells the whole Mac when it changes; its cover and its controls through
  Apple events (app/shared/AppleEvents.h) on a queue of its own, not AppleScript, which may run only on the main
  thread. They're sent to its running process, so it's never started but by the token's Play, and nothing at all is
  asked of it while it's removed. The song's position is stamped with when Spotify was asked it, and while its lyrics
  follow it, it's asked alone every 5 seconds.
- `app/Lyrics.m`: the song's lyrics, from LRCLIB: asked for only once you've said yes, once a song has played a moment,
  one request at a time, in turn until lyrics with times are found: as Spotify names the song, without its album, with
  its name tidied of what Spotify adds to say which version it is (" - Remastered 2011", "(feat. …)"), and through
  LRCLIB's search, by name and artist, taking a song of the same name and length (the only ask for a song over an
  hour, as LRCLIB takes no longer length). A question LRCLIB won't take isn't asked again: the next ask goes. When
  LRCLIB has trouble answering (it's busy, it's asked too often, or nothing comes back), it's asked again after 1, 2,
  4, 8 and 16 seconds, each a little shorter or longer at random and never sooner than LRCLIB says; then the page is
  told there are none for now (or gets the lyrics without times found already), and LRCLIB is asked once a minute
  while the song plays, for the asks still to go. What it found is remembered for the last 32 songs too, for as long
  as it would count on this Mac.
- `app/LyricsStore.m`: what LRCLIB found, kept on this Mac, so a song played again needs no asking: one file a song, in
  `lyrics/` in Whozmove's folder, for the last 1,000 songs played. Lyrics without times, or none, count for a week,
  then the song is asked about again. Read and written on a queue of its own.
- `app/SpotifyToken.m`: the token, a small window of its own that the panel holds under itself; it takes clicks only
  over its disc.
- `app/SpotifyFacts.h`: everything the module relies on about Spotify that Spotify could change: its app id, what it
  announces and in which fields, how a song's track id starts, the codes in its scripting dictionary, and where to get
  it. When Spotify changes, the fix goes here. The README's "Tested with" names the version they were last checked with.
- `app/LRCLIBFacts.h`: the same for LRCLIB: where a song's lyrics are asked for and searched for, and with what (the
  longest length it takes among it), how it matches songs, what its answer holds, how it turns a question away or says
  to wait, and what Whozmove says it is when it asks.
- `page/now-playing.js`: what the strip shows (plain functions); `page/lyrics.js`: a song's lines and pauses from its
  LRC, and which shows when (plain functions); `page/np-strip.js`: drawing the strip, its words rolling in place,
  growing it in and folding it away, and its presses; `page/lyrics-view.js`: the one timer that changes the lines as the
  song moves on, the lyrics beside the list (the reader's `lyrics` mode, about none of the sessions) and your answer
  about them; `page/spotify.js`: what the module plugs into the page core (panel/scripts/modules.js): its state, what
  the pointer can point at, its strip, its part of each update and fold, `setNowPlaying` and `setLyrics`.
  `page/now-playing.css` and `page/lyrics.css` are its styles. `module.json` lists them for tools/page.sh.
- `tests/test.sh`: what the strip and the token get from what Spotify says and answers, where LRCLIB is asked about a
  song and what its answers say (a search's too), how long it's waited before asking again after trouble, what the
  page is told from what this Mac kept, and when a position is a jump (`spotify.expected.txt`); and the page's part,
  lyrics included (`page-cases.js`, `page.expected.txt`). tests/all.sh runs it.

Its switches are kept in the app's preferences: `showNowPlaying` (Spotify itself) and `spotifySideIcon`, both on until
turned off; `spotifyLyrics`, off until you say yes; and `spotifyLyricsAsked`, whether you've answered the strip's
question. Whether the lines show in the strip too (`lyricsInStrip`, on until turned off at the lyrics' foot) is the
page's, kept with its own.

## Between the page and the app

- The page sends `spotify`: a press on the now-playing strip, `{action, fraction}`, where `action` is `playpause`,
  `next`, `previous`, `seek`, `open` (also the lyrics' Open Spotify) or `settings`; `lyrics`, `{on}`, your answer about
  lyrics; `folded`, once the strip has folded away, so the token comes out only then; and `collapsed`, `{on}`, whether
  the panel is folded into the cat, when neither the strip nor the token shows (opening, the token comes out once the
  panel has opened).
- The app calls `setNowPlaying(song)`: `{track, title, artist, album, durationMs, positionMs, at, playing,
  pausedSince, artUrl, allowed}`, or null, where `positionMs` was right at `at`.
- The app calls `setLyrics(lyrics)`: `{state}`, `ask` until you've answered, `off`, or `on` with nothing playing; for
  the song playing, `{state, track}`: `looking`, `timed` with `lrc` (the words with when each line starts), `plain`
  with `plain` (the words alone), `none` (LRCLIB doesn't know it, it has no words, or it isn't a song) or `failed`
  (LRCLIB hasn't answered for a while); null while Spotify is removed.

## Rules

- Spotify is never started but by its token's Play: everything else is sent to the process already running, and
  nothing at all is asked of it while it's removed (Spotify ▸ Remove Spotify).
- Its controls go through Apple events on a queue of its own, never AppleScript, which may run only on the main thread.
- LRCLIB is asked nothing before you've said yes, nothing while Spotify is removed, and nothing in a print run (the
  Lyrics object is made only when the module launches). It's told only a song's name, artist, album and length, with
  Whozmove's name and version, one request at a time, and never sooner than it asks to be. Its connection keeps
  nothing on disk. What it answers is checked for its kind, capped, and goes into the page as text.
- What it found is kept on this Mac only, in Whozmove's folder, for the last 1,000 songs played, and turning lyrics
  off deletes it all. A print run reads and keeps nothing.
- Ads and podcast episodes (by their track ids) aren't looked up.
- Its switches keep their keys, `showNowPlaying`, `spotifySideIcon`, `spotifyLyrics` and `spotifyLyricsAsked`, so a
  choice made once holds across updates.

## How the token moves

The token moves natively (`SpotifyToken.m`), as a window of its own under the panel. It's always the same token: it
sits on the panel's side facing the screen's middle, and when the panel is dragged across the middle (past a little
leeway) it waits a moment, then the panel takes it in under the glass at one corner, across beneath itself and out at
the other, going a little past where it rests and settling back, once. Near the pointer it leans out and slides along
the edge to meet it, each frame closing a share of the way, so it eases and follows smoothly. Pressed, it squashes and
goes under the glass before Spotify is asked to play, so it's gone before the strip grows; paused for 15 minutes, the
strip folds first and tells the app (`folded`), and only then does the token come out. Opening out of the cat, it
waits under the glass until the panel has opened, then comes out with that same small bounce.

## How the lines move

A line is lit 300 ms before it's sung, so it has rolled into the strip by the time the singer starts it. The strip's
words keep two rows' room whatever they are, so the strip never changes height: the song's name, or the line (a size
smaller when it needs more). New words roll in place, the old leaving one way as the new come from the other: up as the
song moves on (and for a new song, or the lines coming into the strip or leaving it), down when it goes back a line;
for a jump, the old go before the new come, so the two never share the room. From one song's name to the next, the
title and the artist each roll on their own, and only the one that has changed. Words that come while others roll
wait, then roll on from what's shown. One timer, set for the next change by the song's own clock, moves them; nothing
runs every frame, and nothing at all while the panel is folded into the cat: its words change at once, out of sight,
and the panel opened again shows what's true then.

Pressed before the song's lyrics are here, the strip says why in the same place: "Loading lyrics…" while they're on
their way, or "Lyrics not available". It rolls up in place of the song's name, as a new line does, stays two and a half
seconds, then rolls back down to the name; if what's known changes meanwhile, the new words roll up in its place, and
if the lyrics come, they open beside the list and the strip rolls back (only the strip, when the reader beside the list
has been opened on something else since).

Beside the list, the lines sit in a column that moves up by a transition, keeping the one being sung a third of the
way down: it brightens as it's reached, and those sung dim. A pause's three dots fill in turn over a third of it each,
kept to the song's clock and still while it's paused. As the panel grows for them, the line being sung is put in its
place before they show; when it changes height later, the line glides there. A new song's lyrics come in the panel's
way, once what was there has gone (the newest, if they changed meanwhile), and only the new song's lines move. When the
strip folds away with them open, it goes first, then they close, the panel folding back to the list without it. Under
reduced motion, each change is just its end.
