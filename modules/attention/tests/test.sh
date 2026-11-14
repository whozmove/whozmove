#!/bin/bash
# The attention module's tests: what each made-up event keeps, in a throwaway home (Whozmove --print-attention,
# compared with attention.expected.txt): an app coming to the front, only whether a session runs in it; away and back,
# each change once; a look at a session, once a minute while you stay on it; each day in its own file, only yours to
# read; and the days past their 14 taken away. Nothing of yours is read or written.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   modules/attention/tests/test.sh            run and compare
#   modules/attention/tests/test.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/../../.." || exit 1
. tests/sandboxed.sh "$@"
HERE=modules/attention/tests
. tests/lib.sh
T=$(throwaway attention) || exit 1
leave_nothing "$T"
. tests/compare.sh
APP=$(built_app "$T") || exit 1

out=$(
echo "== Made-up events, and what's kept of them"
HOME="$T" TZ=UTC "$APP" --print-attention "$HERE/events.json" 2>&1
)
compare "Attention" "$HERE/attention.expected.txt" "$out" "${1:-}" || exit 1

# Your own home refused: checked only where this run's HOME is the account's own (CI, or your own run), which the app
# tells itself, as a test never reaches for that home (tests/checks.sh) and HOME is never pointed at it. Given no
# events, the print run writes nothing either way: in your own home it refuses first, and in a throwaway one (an
# agent's run) it says it needs events, and the case is said to be skipped.
said=$("$APP" --print-attention 2>&1)
case $said in
  *"give it a throwaway one"*) ;;
  *"needs a file of events"*) echo "Attention: your own home's refusal not checked, as this run's HOME is a throwaway one" ;;
  *) echo "Attention: --print-attention with no events said: $said"; exit 1 ;;
esac
