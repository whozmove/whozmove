#!/bin/bash
# The Spotify module's tests: what the now-playing strip and Spotify's token get from what Spotify tells the Mac and
# answers (Whozmove --print-spotify, compared with spotify.expected.txt), and the page's part (page-cases.js, run with
# macOS's jsc in UTC, compared with page.expected.txt).
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   modules/spotify/tests/test.sh            run and compare
#   modules/spotify/tests/test.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/../../.." || exit 1
HERE=modules/spotify/tests
# Stops here if there's no temporary folder: an empty T would make the clean-up below delete this checkout.
T=$(mktemp -d "${TMPDIR:-/tmp}/whozmove-spotify.XXXXXX") || exit 1
T=$(cd "$T" && pwd -P) || exit 1
trap 'rm -rf "$T"' EXIT
. tests/lib.sh
. tests/compare.sh
APP=$(built_app "$T") || exit 1

# What Spotify tells the whole Mac when the song or its state changes (in the shape Spotify 1.3.5 sends, fields the
# panel doesn't use included), what the reading gets back from it (Spotify.m), and why an Apple event to it failed:
# macOS refusing, and Spotify not running.
mkdir -p "$T/spotify"
cat > "$T/spotify/announce-playing.json" <<'JSON'
{"Album": "Example Album", "Album Artist": "Example Artist", "Artist": "Example Artist", "Disc Number": 1,
 "Duration": 200000, "Has Artwork": true, "Name": "Example Song", "Play Count": 0, "Playback Position": 61.204,
 "Player State": "Playing", "Popularity": 50, "Track ID": "spotify:track:0000000000000000000001", "Track Number": 1}
JSON
echo '{"Name": "Example Song", "Artist": "Example Artist", "Album": "Example Album", "Duration": 200000,
       "Playback Position": 90.5, "Player State": "Paused", "Track ID": "spotify:track:0000000000000000000001"}' \
  > "$T/spotify/announce-paused.json"
echo '{"Player State": "Stopped"}' > "$T/spotify/announce-stopped.json"
echo '{"Player State": "Playing", "Name": "No id"}' > "$T/spotify/announce-no-track.json"
echo '["spotify:track:0000000000000000000001", "Example Song", "Example Artist", "Example Album", 200000, 61.25,
       "playing", "https://i.scdn.co/image/ab67616d0000b273"]' > "$T/spotify/reply-playing.json"
echo '["spotify:track:0000000000000000000001", "Example Song", "Example Artist", "Example Album", 200000, 3, "paused",
       null]' > "$T/spotify/reply-no-cover.json"
echo '[]' > "$T/spotify/reply-stopped.json"
echo '-1743' > "$T/spotify/error-refused.json"
echo '-600' > "$T/spotify/error-not-running.json"
# Spotify's token: what it shows, and which side of the panel it's on, the side facing the screen's middle (a
# 1440-wide screen; the panel 340 wide).
PLAYING='{"track": "spotify:track:1", "title": "Example Song", "artist": "Example Artist", "durationMs": 200000,
          "positionMs": 50000, "playing": true, "artUrl": "https://i.scdn.co/image/ab67"}'
PAUSED="${PLAYING/\"playing\": true/\"playing\": false}"
echo '{"installed": false}' > "$T/spotify/token-not-installed.json"
echo '{"installed": true}' > "$T/spotify/token-closed.json"
echo "{\"installed\": true, \"song\": $PAUSED}" > "$T/spotify/token-paused-when-found.json"
for minutes in 14 15; do
  echo "{\"installed\": true, \"song\": ${PAUSED%\}}, \"pausedMinutesAgo\": $minutes}}" \
    > "$T/spotify/token-paused-$minutes-minutes.json"
done
echo "{\"installed\": true, \"song\": $PLAYING}" > "$T/spotify/token-playing.json"
echo '{"installed": true, "starting": true}' > "$T/spotify/token-starting.json"
echo "{\"installed\": true, \"song\": $PLAYING, \"collapsed\": true}" > "$T/spotify/token-playing-panel-folded.json"
echo "{\"installed\": true, \"song\": $PAUSED, \"allowed\": false}" > "$T/spotify/token-refused.json"
echo "{\"installed\": true, \"song\": $PLAYING, \"allowed\": false}" > "$T/spotify/token-refused-playing.json"
SCREEN='"screen": [0, 0, 1440, 900]'
echo "{\"list\": [64, 400, 340, 300], $SCREEN}" > "$T/spotify/side-panel-at-left.json"
echo "{\"list\": [1050, 400, 340, 300], $SCREEN}" > "$T/spotify/side-panel-at-right.json"
echo "{\"list\": [564, 400, 340, 300], $SCREEN, \"current\": \"right\"}" > "$T/spotify/side-just-past-middle-stays.json"
echo "{\"list\": [524, 400, 340, 300], $SCREEN, \"current\": \"left\"}" > "$T/spotify/side-within-leeway-stays.json"
echo "{\"list\": [444, 400, 340, 300], $SCREEN, \"current\": \"left\"}" > "$T/spotify/side-past-leeway-moves.json"
# Its lyrics: where LRCLIB is asked about a song, in turn (none: nothing to ask about); what one of LRCLIB's answers says
# (in the shape LRCLIB answers, fields the panel doesn't use included), a search's too; how long it's waited before
# asking again after trouble; what the page is told from what this Mac kept about a song; and whether a position Spotify
# gives is a jump the page is told. Nothing is asked of LRCLIB, and nothing is read or kept on disk.
SONG='"track": "spotify:track:0000000000000000000001", "title": "Example Song", "artist": "Example Artist",
      "album": "Example Album"'
echo "{$SONG, \"durationMs\": 200400}" > "$T/spotify/lyrics-ask-song.json"
echo "{$SONG, \"durationMs\": 200500}" > "$T/spotify/lyrics-ask-rounds-up.json"
echo '{"track": "spotify:track:0000000000000000000002", "title": "Café & Crème + 1/2?", "artist": "Ïda North",
       "album": "Example Album", "durationMs": 180000}' > "$T/spotify/lyrics-ask-encoded.json"
echo "{${SONG/Example Album/}, \"durationMs\": 200000}" > "$T/spotify/lyrics-ask-no-album.json"
echo "{${SONG/spotify:track:0000000000000000000001/spotify:local:Example+Artist:Example+Album:Example+Song:200},
       \"durationMs\": 200000}" > "$T/spotify/lyrics-ask-local-file.json"
echo "{${SONG/spotify:track:/spotify:ad:}, \"durationMs\": 30000}" > "$T/spotify/lyrics-ask-ad.json"
echo "{${SONG/spotify:track:/spotify:episode:}, \"durationMs\": 1800000}" > "$T/spotify/lyrics-ask-episode.json"
echo "{$SONG, \"durationMs\": 0}" > "$T/spotify/lyrics-ask-no-length.json"
echo "{${SONG/Example Artist/ }, \"durationMs\": 200000}" > "$T/spotify/lyrics-ask-no-artist.json"
echo "{${SONG/Example Song/Example Song - Remastered 2011}, \"durationMs\": 200000}" \
  > "$T/spotify/lyrics-ask-remastered.json"
echo "{${SONG/Example Song/Example Song (feat. Other Artist) [Mono]}, \"durationMs\": 200000}" \
  > "$T/spotify/lyrics-ask-featuring.json"
echo "{${SONG/Example Song/Example Song – Live at Example Hall}, \"durationMs\": 260000}" \
  > "$T/spotify/lyrics-ask-live.json"
echo "{${SONG/Example Song/Example Song - Instrumental}, \"durationMs\": 200000}" \
  > "$T/spotify/lyrics-ask-instrumental.json"
echo "{${SONG/Example Song/(Example Song)}, \"durationMs\": 200000}" > "$T/spotify/lyrics-ask-all-in-brackets.json"
echo "{$SONG, \"durationMs\": 3600400}" > "$T/spotify/lyrics-ask-an-hour.json"
echo "{$SONG, \"durationMs\": 3600500}" > "$T/spotify/lyrics-ask-over-an-hour.json"
ANSWER='"id": 1, "trackName": "Example Song", "artistName": "Example Artist", "albumName": "Example Album",
        "duration": 200, "instrumental": false'
echo "{\"status\": 200, \"body\": {$ANSWER, \"plainLyrics\": \"First line\nSecond line\",
       \"syncedLyrics\": \"[00:08.00] First line\n[00:12.40] Second line\n[00:16.00] \"}}" \
  > "$T/spotify/lyrics-answer-timed.json"
echo "{\"status\": 200, \"body\": {$ANSWER, \"plainLyrics\": \"First line\nSecond line\", \"syncedLyrics\": null}}" \
  > "$T/spotify/lyrics-answer-plain.json"
echo "{\"status\": 200, \"body\": {${ANSWER/false/true}, \"plainLyrics\": null, \"syncedLyrics\": null}}" \
  > "$T/spotify/lyrics-answer-instrumental.json"
echo "{\"status\": 200, \"body\": {$ANSWER, \"plainLyrics\": \" \", \"syncedLyrics\": \"\"}}" \
  > "$T/spotify/lyrics-answer-empty.json"
echo "{\"status\": 200, \"body\": {$ANSWER, \"plainLyrics\": [\"a\"], \"syncedLyrics\": 42}}" \
  > "$T/spotify/lyrics-answer-wrong-kinds.json"
echo "{\"status\": 200, \"body\": {$ANSWER, \"plainLyrics\": \"First line\",
       \"syncedLyrics\": \"[ar: Example Artist]\n[00:08.00]\n[00:12.40] <00:12.50> \n[00:16.00]\"}}" \
  > "$T/spotify/lyrics-answer-timed-no-words.json"
echo "{\"status\": 200, \"body\": {$ANSWER, \"plainLyrics\": null, \"syncedLyrics\": \"[00:08.00]\n[00:16.00]\"}}" \
  > "$T/spotify/lyrics-answer-timed-no-words-at-all.json"
echo '{"status": 404, "body": {"code": 404, "name": "TrackNotFound", "message": "Failed to find specified track"}}' \
  > "$T/spotify/lyrics-answer-not-found.json"
echo '{"status": 503, "body": {"code": 503, "name": "ServerOverloaded",
       "message": "The server is busy, please retry in a moment"}}' > "$T/spotify/lyrics-answer-busy.json"
echo '{"status": 429, "text": "Too Many Requests"}' > "$T/spotify/lyrics-answer-too-many.json"
echo '{"status": 400, "body": {"code": 400, "name": "ValidationError",
       "message": "duration: must be between 1 and 3600"}}' > "$T/spotify/lyrics-answer-refused.json"
echo '{"status": 500, "text": "Internal Server Error"}' > "$T/spotify/lyrics-answer-server-error.json"
echo '{"status": 0}' > "$T/spotify/lyrics-answer-nothing-came.json"
echo '{"status": 200, "text": "<html>Not lyrics</html>"}' > "$T/spotify/lyrics-answer-not-json.json"
python3 -I -c 'import json; print(json.dumps({"status": 200, "text": "x" * 1100000}))' \
  > "$T/spotify/lyrics-answer-too-big.json"
python3 -I -c '
import json
lines = "\n".join("[%02d:%02d.00] Example line %05d" % (n // 60 % 60, n % 60, n) for n in range(3000))
print(json.dumps({"status": 200, "body": {"syncedLyrics": lines, "plainLyrics": None, "instrumental": False}}))' \
  > "$T/spotify/lyrics-answer-long.json"
FOUND='"id": 2, "artistName": "Example Artist", "albumName": "Example Album", "instrumental": false,
       "hasWordSync": false, "lyricsfile": null'
TIMED='"plainLyrics": "First line", "syncedLyrics": "[00:08.00] First line"'
echo "{\"status\": 200, \"body\": [
  {$FOUND, \"trackName\": \"Example Song 2\", \"duration\": 200, $TIMED},
  {$FOUND, \"trackName\": \"Example Song (Remastered)\", \"duration\": 260, $TIMED},
  {$FOUND, \"trackName\": \"Example Song - Live\", \"duration\": 201, \"plainLyrics\": \"Live words\",
   \"syncedLyrics\": null},
  {${FOUND/false/true}, \"trackName\": \"Example Song\", \"duration\": 199, \"plainLyrics\": null,
   \"syncedLyrics\": null},
  {$FOUND, \"trackName\": \"Example Song [Remastered]\", \"duration\": 201.5,
   \"plainLyrics\": \"Timed words\", \"syncedLyrics\": \"[00:08.00] Timed words\"}]}" \
  > "$T/spotify/lyrics-answer-search.json"
echo "{\"status\": 200, \"body\": [{$FOUND, \"trackName\": \"Example Song - Live\", \"duration\": 201,
       \"plainLyrics\": \"Live words\", \"syncedLyrics\": null}]}" > "$T/spotify/lyrics-answer-search-untimed.json"
echo "{\"status\": 200, \"body\": [{${FOUND/false/true}, \"trackName\": \"Example Song\", \"duration\": 200,
       \"plainLyrics\": null, \"syncedLyrics\": null}]}" > "$T/spotify/lyrics-answer-search-instrumental.json"
echo '{"status": 200, "body": []}' > "$T/spotify/lyrics-answer-search-nothing.json"
echo "{\"status\": 200, \"song\": {\"title\": \"Café Crème\", \"durationMs\": 180000}, \"body\": [{$FOUND,
       \"trackName\": \"Cafe Creme\", \"duration\": 180, $TIMED}]}" > "$T/spotify/lyrics-answer-search-accents.json"
echo '{"tries": [1, 2, 3, 4, 5, 6, 7], "asked": 0, "chance": 0.5}' > "$T/spotify/lyrics-wait-each-try.json"
echo '{"tries": [1, 5, 6], "asked": 0, "chance": 0}' > "$T/spotify/lyrics-wait-shortest.json"
echo '{"tries": [1, 5, 6], "asked": 0, "chance": 1}' > "$T/spotify/lyrics-wait-longest.json"
echo '{"tries": [1, 6], "asked": 30, "chance": 0.5}' > "$T/spotify/lyrics-wait-as-asked.json"
echo '{"tries": [1], "asked": 86400, "chance": 0.5}' > "$T/spotify/lyrics-wait-at-most-an-hour.json"
TRACK='"track": "spotify:track:0000000000000000000001"'
echo "{$TRACK, \"kept\": {$TRACK, \"state\": \"timed\", \"lrc\": \"[00:08.00] First line\", \"keptDaysAgo\": 400}}" \
  > "$T/spotify/lyrics-kept-timed-long-ago.json"
echo "{$TRACK, \"kept\": {$TRACK, \"state\": \"plain\", \"plain\": \"First line\", \"keptDaysAgo\": 3}}" \
  > "$T/spotify/lyrics-kept-untimed-this-week.json"
echo "{$TRACK, \"kept\": {$TRACK, \"state\": \"plain\", \"plain\": \"First line\", \"keptDaysAgo\": 8}}" \
  > "$T/spotify/lyrics-kept-untimed-a-week-ago.json"
echo "{$TRACK, \"kept\": {$TRACK, \"state\": \"none\", \"keptDaysAgo\": 3}}" > "$T/spotify/lyrics-kept-none-this-week.json"
echo "{$TRACK, \"kept\": {$TRACK, \"state\": \"none\", \"keptDaysAgo\": 8}}" > "$T/spotify/lyrics-kept-none-a-week-ago.json"
echo "{$TRACK, \"kept\": {\"track\": \"spotify:track:0000000000000000000002\", \"state\": \"timed\",
       \"lrc\": \"[00:08.00] First line\", \"keptDaysAgo\": 1}}" > "$T/spotify/lyrics-kept-another-song.json"
echo "{$TRACK, \"kept\": {$TRACK, \"state\": \"timed\", \"lrc\": 42, \"keptDaysAgo\": 1}}" \
  > "$T/spotify/lyrics-kept-wrong-kinds.json"
echo "{$TRACK, \"kept\": {$TRACK, \"state\": \"timed\", \"lrc\": \"[00:08.00]\n[00:16.00]\", \"keptDaysAgo\": 1}}" \
  > "$T/spotify/lyrics-kept-timed-no-words.json"
echo "{$TRACK, \"kept\": {$TRACK, \"state\": \"failed\", \"keptDaysAgo\": 1}}" > "$T/spotify/lyrics-kept-failed.json"
echo '{"track": "spotify:local:Example+Artist:Example+Album:Example+Song:200"}' > "$T/spotify/lyrics-kept-local-file.json"
echo '{"song": {"playing": true, "positionMs": 60000, "atSecondsAgo": 10}, "readMs": 70100}' \
  > "$T/spotify/position-on-time.json"
echo '{"song": {"playing": true, "positionMs": 60000, "atSecondsAgo": 10}, "readMs": 100000}' \
  > "$T/spotify/position-jumped.json"
echo '{"song": {"playing": false, "positionMs": 60000, "atSecondsAgo": 10}, "readMs": 100000}' \
  > "$T/spotify/position-paused.json"

status=0
out=$(
echo "== What the now-playing strip gets from what Spotify tells the Mac and answers (null: nothing playing), and"
echo "   whether an Apple event's error is macOS refusing Whozmove control of Spotify; what its token shows, and its side;"
echo "   where LRCLIB is asked about a song, what its answers say, the waits after trouble and what's kept on this Mac;"
echo "   and whether a position is a jump"
HOME="$T" "$APP" --print-spotify "$T"/spotify/* | in_minutes
)
compare Spotify "$HERE/spotify.expected.txt" "$out" "${1:-}" || status=1

page=$(page_cases "$HERE/page-cases.js") || { echo "$page"; exit 1; }
compare "Spotify's page" "$HERE/page.expected.txt" "$page" "${1:-}" || status=1
exit $status
