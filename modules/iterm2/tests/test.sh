#!/bin/bash
# The iTerm2 module's tests: what a new tab for a new conversation or Sign in would run, from folders whose names need
# quoting, and what iTerm2 would be told to open it with, only plain words, or that it wouldn't be told (Whozmove
# --print-iterm2-tab, compared with tabs.expected.txt); and what it would be told to find a session's tab, how its
# answers would be read, and what it would be told to type and press there, only into a session alone in its window
# (Whozmove --print-iterm2-typing, compared with typing.expected.txt); and what it would be asked for a cookie for its
# Python API, the request that opens a connection, what would be sent there for text and keys, and how its answers
# would be read (Whozmove --print-iterm2-api, compared with api.expected.txt). Nothing is sent to iTerm2, so it needn't
# be on the Mac.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   modules/iterm2/tests/test.sh            run and compare
#   modules/iterm2/tests/test.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/../../.." || exit 1
HERE=modules/iterm2/tests
# Stops here if there's no temporary folder: an empty T would make the clean-up below delete this checkout.
T=$(mktemp -d "${TMPDIR:-/tmp}/whozmove-iterm2.XXXXXX") || exit 1
T=$(cd "$T" && pwd -P) || exit 1
trap 'rm -rf "$T"' EXIT
. tests/lib.sh
. tests/compare.sh
APP=$(built_app "$T") || exit 1

# A new conversation's command, as Claude Code's module gives it (tests/rows.sh and the starts module's tests check
# that), with its words in a file of their own; and Sign in's.
words="/Users/you/Library/Application Support/Whozmove/starts/0b6f6b9e-3c0f-4f53-8e2a-6e1f0d8b2c11.txt"
start="claude --session-id 0b6f6b9e-3c0f-4f53-8e2a-6e1f0d8b2c11 \"\$(cat '$words')\""
# The file of commands goes in your temporary folder, whose path iTerm2 takes as it is.
files=/private/var/folders/ab/cdef0123_gh/T/whozmove-iterm2
out=$({
echo "== A new conversation, through zsh"
HOME="$T" "$APP" --print-iterm2-tab /bin/zsh "$files/0B6F6B9E-3C0F-4F53-8E2A-6E1F0D8B2C11.sh" /work/app "$start"
echo "== Sign in, through bash, from a folder whose name has a space, quotes, a backslash and \$\$ in it"
HOME="$T" "$APP" --print-iterm2-tab /opt/homebrew/bin/bash "$files/5A1E9C2D-7B44-4E0A-9F3B-2C8D6E1A4B70.sh" \
  "/Users/you/Dad's \"new\" app\\v2 \$\$" "claude auth login"
echo "== A temporary folder whose path iTerm2 wouldn't take as it is"
HOME="$T" "$APP" --print-iterm2-tab /bin/zsh "/Users/you/My Temp/whozmove-iterm2/x.sh" /work/app "$start"
} 2>&1)
compare "iTerm2's new tabs" "$HERE/tabs.expected.txt" "$out" "${1:-}" || status=1

# A session's id as iTerm2 gives it, and the answers finding one can get: alone in its window, sharing it, none, and
# ones that aren't its answer. The text typed is a /compact with its focus, quotes and a backslash in it, and a tab and
# an Escape with "[Z" after it, which would be pressed as keys (the Escape and "[Z" a Shift+Tab) if they went in.
id=4F1C9A2E-7B3D-4E8A-9C21-0D5E6F7A8B90
out=$({
echo "== A session on a terminal device a script can name, and text with quotes, a backslash, a tab and an Escape"
HOME="$T" "$APP" --print-iterm2-typing /dev/ttys012 "$id" $'/compact keep the "draft" plan,\tnot C:\\old\e[Z' \
  "$id alone" "$id shared" "" "$id" "$id alone too" "w0t0p0:$id alone" "$id sideways"
echo "== Names a script can't take"
HOME="$T" "$APP" --print-iterm2-typing '/dev/ttys012"; quit' 'not-an-id"' "x"
} 2>&1)
compare "iTerm2's typing" "$HERE/typing.expected.txt" "$out" "${1:-}" || status=1

# Through its Python API: the same text, sent with what iTerm2 could answer, recorded as it sends them (api.proto):
# taken, no such session, an error, a notification, another request's answer, an answer with a field it doesn't know
# first, a status it doesn't know, an answer cut short, and bytes that aren't a message. The request's lines end in a
# carriage return, as HTTP's do, which git takes off the files it keeps, so it's shown as \r.
out=$({
echo "== A session's id, and text with quotes, a backslash, a tab and an Escape"
HOME="$T" "$APP" --print-iterm2-api "$id" $'/compact keep the "draft" plan,\tnot C:\\old\e[Z' \
  "08 01 da 06 02 08 00" "08 01 da 06 02 08 01" "08 01 12 04 6f 6f 70 73" "c2 3e 02 0a 00" \
  "08 02 da 06 02 08 00" "18 07 08 01 da 06 00" "08 01 da 06 02 08 05" "08 01 da 06 05 08" "ff"
echo "== A name that isn't a session's id"
HOME="$T" "$APP" --print-iterm2-api all "x"
} 2>&1 | LC_ALL=C sed $'s/\r$/\\\\r/')
compare "iTerm2's Python API" "$HERE/api.expected.txt" "$out" "${1:-}" || status=1
exit ${status:-0}
