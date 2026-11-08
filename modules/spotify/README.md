# Spotify

The song the Spotify app on this Mac is playing, in the now-playing strip at the panel's bottom; its lyrics from LRCLIB,
once you've said yes, each line in the strip in place of the song's name while it's sung, and the whole song beside the
list when the strip is pressed, once they're here; Spotify's round token, tucked half under the panel at its corner,
which plays, resumes or gets Spotify; and its music quieter while you talk to Claude by voice, back to exactly where
it was once you've stopped. Its page on the panel's back (the apps module) takes the song and the token out of the
panel (Show the song), turns the lyrics on or off (Lyrics), hides the token (Its icon at the panel's corner), turns
the quieter music on or off (Quieter while you talk to Claude), with how much quieter (A little, Half or Much quieter,
a choice of one under it while it's on), and brings Spotify forward (Open Spotify, as the strip opens the lyrics once
they're on). As the panel turns over, the
token goes from sight, and comes back out from under the glass once the panel is on its list side again; the same as
the panel is flicked off the screen's edge and comes back.

## Its pieces

- `app/SpotifyModule.m`: its face for the core (contracts/Module.h). It makes Spotify, its lyrics, the token and its
  volume when the app starts, has the panel hold the token under its glass (`EdgeIcon`, parts/edge, `holdBy:`), follows
  the core's Talking while the music is to be quieter, answers the page's `spotify` messages, lists Spotify for the
  panel's back with its switches and the card that asks to control it (`appEntries`), and has the print mode the tests
  check (`--print-spotify`).
- `app/Spotify.m`: the song, from what Spotify tells the whole Mac when it changes; its cover and its controls through
  Apple events (app/shared/AppleEvents.h) on a queue of its own, not AppleScript, which may run only on the main thread.
  They're sent to its running process, so it's never started but by a press of yours, and this asks it nothing while the
  song is hidden (the music made quieter while you talk asks it only around a talk). The song's position is stamped with
  when Spotify was asked it, and while its lyrics follow it, it's asked alone every 5 seconds.
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
- `app/SpotifyVolume.m`: the music quieter while you talk to Claude. It follows the core's Talking, and turns Spotify's
  volume down a point at a time to the share you picked as you start, and back up to exactly the volume it had once
  you've stopped, through Apple events on a queue of its own (Spotify's own can wait 20 s on Play), deciding everything
  on the main thread. It keeps the volume it had in the app's preferences before its first change, so a restart or a
  crash (and Spotify, quit while lowered, keeping the low volume) still has it put back, and a Spotify too busy to
  answer is asked again. Whether Whozmove may control Spotify is found for the card on Spotify's page, which asks macOS
  only on your press of Allow (Open Spotify first, while it's closed; Open Settings once it's been refused).
- `app/SpotifyToken.m`: the token, an icon at the panel's edge (EdgeIcon.h in parts/edge, which has its window, the
  glass and the pointer followed, its side, its coming out and its label): what's Spotify's own is its disc, ring and
  badge, the magnet and its press. Its ring, edges and label are the panel's colours, light or dark as the panel is,
  painted again when that changes.
- `app/SpotifyFacts.h`: everything the module relies on about Spotify that Spotify could change: its app id, what it
  announces and in which fields, how a song's track id starts, the codes in its scripting dictionary, and where to get
  it. When Spotify changes, the fix goes here. docs/using/install.md ("What it's tested with") names the
  version they were last checked with.
- `app/LRCLIBFacts.h`: the same for LRCLIB: where a song's lyrics are asked for and searched for, and with what (the
  longest length it takes among it), how it matches songs, what its answer holds, how it turns a question away or says
  to wait, and what Whozmove says it is when it asks.
- `page/now-playing.js`: what the strip shows (plain functions); `page/lyrics.js`: a song's lines and pauses from its
  LRC, and which shows when (plain functions); `page/np-strip.js`: drawing the strip, its words rolling in place,
  growing it in and folding it away, and its presses; `page/lyrics-view.js`: the one timer that changes the lines as the
  song moves on, the lyrics beside the list (the reader's `lyrics` mode, about none of the sessions) and your answer
  about them; `page/spotify.js`: what the module plugs into the page core (parts/bridge/page/modules.js): its state,
  what the pointer can point at, its strip, its part of each update and fold, `setNowPlaying` and `setLyrics`.
  `page/now-playing.css` and `page/lyrics.css` are its styles. `module.json` lists them for tools/page.sh.
- `tests/test.sh`: what the strip and the token get from what Spotify says and answers, where LRCLIB is asked about a
  song and what its answers say (a search's too), how long it's waited before asking again after trouble, what the
  page is told from what this Mac kept, when a position is a jump, and the quieter music's rules: where it goes, its
  turning moment by moment, what's set for Spotify's rounding, whether a volume read is Whozmove's, and whether a record
  a quit left puts it back (`spotify.expected.txt`); and the page's part, lyrics and the quieter sign included
  (`page-cases.js`, `page.expected.txt`). tests/all.sh runs it.

Its switches are kept in the app's preferences: `showNowPlaying` (the song and the token) and `spotifySideIcon`, both
on until turned off; `spotifyLyrics`, off until you say yes; `spotifyLyricsAsked`, whether you've answered the strip's
question; `spotifyQuieter`, on until turned off (macOS 14 and later); and `spotifyQuieterTo`, how much quieter
(`little`, two thirds of the volume; `half`; or `much`, a quarter). While the music is lowered, `spotifyQuieterKept`
holds `{from, to, at}`: the volume to bring back, where it went, and when. Whether the lines show in the strip too
(`lyricsInStrip`, on until turned off at the lyrics' foot) is the page's, kept with its own.

## Between the page and the app

- The page sends `spotify`: a press on the now-playing strip, `{action, fraction}`, where `action` is `playpause`,
  `next`, `previous`, `seek`, `open` (also the lyrics' Open Spotify) or `settings`; `lyrics`, `{on}`, your answer about
  lyrics; `folded`, once the strip has folded away, so the token comes out only then; and `collapsed`, `{on}`, whether
  the panel is folded into the cat, when neither the strip nor the token shows (opening, the token comes out once the
  panel has opened).
- The app calls `setNowPlaying(song)`: `{track, title, artist, album, durationMs, positionMs, at, playing,
  pausedSince, artUrl, allowed, quieter}`, or null, where `positionMs` was right at `at`, and `quieter` is there (true)
  while the music is lowered as you talk, which the strip shows with a sign beside the time.
- The app calls `setLyrics(lyrics)`: `{state}`, `ask` until you've answered, `off`, or `on` with nothing playing; for
  the song playing, `{state, track}`: `looking`, `timed` with `lrc` (the words with when each line starts), `plain`
  with `plain` (the words alone), `none` (LRCLIB doesn't know it, it has no words, or it isn't a song) or `failed`
  (LRCLIB hasn't answered for a while); null while Spotify is removed.

## Rules

- Spotify is never started but by a press of yours: its token's Play, or Open Spotify on the card that asks to
  control it. Everything else is sent to the process already running. With Show the song off, nothing is asked of it
  but around a talk while the music is to be quieter (whether it's playing, and its volume), and with Quieter while you
  talk to Claude off too, nothing but putting back a volume it left lowered.
- The music is lowered only while Spotify plays on this Mac (not to a Spotify Connect speaker) and Whozmove may
  already control it: macOS's question about that comes only on your press of the card's Allow, never in the middle of
  a talk. It's brought back to exactly the
  volume it had, never above it, and never fought: a change you make meanwhile is left as you made it.
- Whozmove never listens: it reads only whether a microphone runs and which process records (CoreAudio, with no
  permission), never a sound.
- Its controls go through Apple events on a queue of its own, never AppleScript, which may run only on the main thread.
- LRCLIB is asked nothing before you've said yes, nothing while Spotify is removed, and nothing in a print run (the
  Lyrics object is made only when the module launches). It's told only a song's name, artist, album and length, with
  Whozmove's name and version, one request at a time, and never sooner than it asks to be. Its connection keeps
  nothing on disk. What it answers is checked for its kind, capped, and goes into the page as text.
- What it found is kept on this Mac only, in Whozmove's folder, for the last 1,000 songs played, and turning lyrics
  off deletes it all. A print run reads and keeps nothing.
- Ads and podcast episodes (by their track ids) aren't looked up.
- Its switches keep their keys, `showNowPlaying`, `spotifySideIcon`, `spotifyLyrics`, `spotifyLyricsAsked`,
  `spotifyQuieter` and `spotifyQuieterTo`, so a choice made once holds across updates.

## Facts

Checked with Spotify 1.3.5:
- What Spotify tells the whole Mac as a song changes carries the song, with no permission needed to hear it; its
  length is in milliseconds and its position in seconds. Anything told to Spotify starts it if it isn't running.
  macOS's own record of what's playing (MediaRemote) has been closed to other apps since macOS 15.4.
- Spotify gives other apps no lyrics: there are none in its Web API or its scripting. LRCLIB is free, needs no key and
  has lines with times; no other source is all three (Musixmatch's is paid).
- LRCLIB answers 404 for a song it doesn't have, 503 while it's busy and 429 when asked too often, each of those two
  with a Retry-After. It matches the length within 2 seconds and the album exactly when one is sent, and of the songs
  that match it answers with its oldest, timed or not, which is why it's asked again without the album, and searched,
  until lyrics with times are found.
- Spotify's scripting has no queue, so the next song's lyrics can't be looked up ahead of it.

## How the token moves

The token moves natively (`SpotifyToken.m`, on `EdgeIcon`, parts/edge), as a window of its own under the panel. It's
always the same token: it sits on the panel's side facing the screen's middle, and when the panel is dragged across the
middle (past a little leeway) it waits a moment, then the panel takes it in under the glass at one corner, across
beneath itself and out at the other, going a little past where it rests and settling back, once. Near the pointer it
leans out and slides along the edge to meet it, each frame closing a share of the way, so it eases and follows smoothly.
Pressed, it squashes and goes under the glass before Spotify is asked to play, so it's gone before the strip grows;
paused for 15 minutes, the strip folds first and tells the app (`folded`), and only then does the token come out.
Opening out of the cat, it waits under the glass until the panel has opened, then comes out with that same small bounce.

## How the lines move

A line is lit 300 ms before it's sung, so it has rolled into the strip by the time the singer starts it. The strip's
words keep two rows' room whatever they are, so the strip never changes height: the song's name, or the line (a size
smaller when it needs more). New words roll in place, the old leaving one way as the new come from the other: up as the
song moves on (and for a new song, or the lines coming into the strip or leaving it), down when it goes back a line;
for a jump, the old go before the new come, so the two never share the room. From one song's name to the next, the
title and the artist each roll on their own, and only the one that has changed. While a line is in the strip, the
lyrics mark (a speech bubble with quote marks) shows over the cover, fading in as the line rolls in and out as the
song's name rolls back. Words that come while others roll wait, then roll on from what's shown. One timer, set for the
next change by the song's own clock, moves them; nothing runs every frame, and nothing at all while the panel is folded
into the cat: its words change at once, out of sight, and the panel opened again shows what's true then.

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

## How the music goes quieter

It follows the recording, not your voice (the core's Talking says when you're talking to Claude): a pause inside one
talk doesn't bring the music up, only the recording stopping does. The moment a recording that counts begins, Spotify is
asked whether it's playing and its volume, and the volume is turned down as a steady hand turns a knob: one point at a
time, one every 60 ms, from wherever it is (70, 69, 68…) to the share you picked, so half of it takes about 3 s. Once
you've stopped, it waits 3 s, so pressing to talk again straight after doesn't bob it up and down, then turns back up
the same way, one point every 30 ms. A talk shorter than 0.3 s (a key pressed by mistake) brings it back at once. A
point Spotify answers late is followed by the next as soon as it has answered, never by a jump to catch up. Spotify
reads a volume back one lower but for multiples of 20, so what's set is the value that reads back the one wanted, and it
answers a moment late just after a change, so a read counts as Whozmove's when it's within one of the last value set, or
of one set a moment before. While it comes back up, the volume is read just before each point, so a change of yours
stops it at once and stays. Talking again on the way up turns it down again from where it is. When Spotify doesn't
answer (busy loading a song, say), the music isn't let go: the bring-back is tried again a second later, a few times,
then as after a quit. A sign beside the strip's time, a speaker with one wave, fades in as the music goes down, lifting
3px as it lands, and fades as it starts back up; its room is always kept, so the time never moves for it. Under reduced
motion it shows and goes at once.
