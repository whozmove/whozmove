# Spotify

The song the Spotify app on this Mac is playing, in the now-playing strip at the panel's bottom, and Spotify's round
token, tucked half under the panel at its corner, which plays, resumes or gets Spotify. Spotify ▸ in the pawn menu hides
the token (Hide Side Icon) or takes the whole module out of the panel (Remove Spotify).

## Its pieces

- `app/SpotifyModule.m`: its face for the core (contracts/Module.h). It makes Spotify and the token when the app starts,
  holds the token under the panel and follows the glass and the pointer for it (PanelWindow's `attachBelow:`,
  `followGlass:`, `followPointer:`), answers the page's `spotify` messages, puts Spotify ▸ in the pawn menu, and has
  the print mode the tests check (`--print-spotify`).
- `app/Spotify.m`: the song, from what Spotify tells the whole Mac when it changes; its cover and its controls through
  Apple events (app/shared/AppleEvents.h) on a queue of its own, not AppleScript, which may run only on the main
  thread. They're sent to its running process, so it's never started but by the token's Play, and nothing at all is
  asked of it while it's removed.
- `app/SpotifyToken.m`: the token, a small window of its own that the panel holds under itself; it takes clicks only
  over its disc.
- `app/SpotifyFacts.h`: everything the module relies on about Spotify that Spotify could change: its app id, what it
  announces and in which fields, the codes in its scripting dictionary, and where to get it. When Spotify changes, the
  fix goes here. The README's "Tested with" names the version they were last checked with.
- `page/now-playing.js`: what the strip shows (plain functions); `page/np-strip.js`: drawing the strip, growing it in
  and folding it away, and its presses; `page/spotify.js`: what the module plugs into the page core
  (panel/scripts/modules.js): its state, what the pointer can point at, its strip, its part of each update and fold,
  and `setNowPlaying`. `page/now-playing.css` is its style. `module.json` lists them for tools/page.sh.
- `tests/test.sh`: what the strip and the token get from what Spotify says and answers (`spotify.expected.txt`), and
  the page's part (`page-cases.js`, `page.expected.txt`). tests/all.sh runs it.

Its two switches are kept in the app's preferences: `showNowPlaying` (Spotify itself) and `spotifySideIcon`. Both are
on until turned off.

## Between the page and the app

- The page sends `spotify`: a press on the now-playing strip, `{action, fraction}`, where `action` is `playpause`,
  `next`, `previous`, `seek`, `open` or `settings`; `folded`, once the strip has folded away, so the token comes out
  only then; and `collapsed`, `{on}`, whether the panel is folded to its header, where the token stands in for the
  strip.
- The app calls `setNowPlaying(song)`: `{track, title, artist, album, durationMs, positionMs, at, playing,
  pausedSince, artUrl, allowed}`, or null.

## Rules

- Spotify is never started but by its token's Play: everything else is sent to the process already running, and
  nothing at all is asked of it while it's removed (Spotify ▸ Remove Spotify).
- Its controls go through Apple events on a queue of its own, never AppleScript, which may run only on the main thread.
- Its switches keep their keys, `showNowPlaying` and `spotifySideIcon`, so a choice made once holds across updates.

## How the token moves

The token moves natively (`SpotifyToken.m`), as a window of its own under the panel. It's always the same token: it
sits on the panel's side facing the screen's middle, and when the panel is dragged across the middle (past a little
leeway) it waits a moment, then the panel takes it in under the glass at one corner, across beneath itself and out at
the other, going a little past where it rests and settling back, once. Near the pointer it leans out and slides along
the edge to meet it, each frame closing a share of the way, so it eases and follows smoothly. Pressed, it squashes and
goes under the glass before Spotify is asked to play, so it's gone before the strip grows; paused for 15 minutes, the
strip folds first and tells the app (`folded`), and only then does the token come out.
