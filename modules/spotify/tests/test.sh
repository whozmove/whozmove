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

status=0
out=$(
echo "== What the now-playing strip gets from what Spotify tells the Mac and answers (null: nothing playing), and"
echo "   whether an Apple event's error is macOS refusing Whozmove control of Spotify; what its token shows, and its side"
HOME="$T" "$APP" --print-spotify "$T"/spotify/* | in_minutes
)
compare Spotify "$HERE/spotify.expected.txt" "$out" "${1:-}" || status=1

page=$(page_cases "$HERE/page-cases.js") || { echo "$page"; exit 1; }
compare "Spotify's page" "$HERE/page.expected.txt" "$page" "${1:-}" || status=1
exit $status
