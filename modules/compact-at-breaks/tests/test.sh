#!/bin/bash
# The compact-at-breaks module's tests: whether Compact at Breaks would compact each sample session now, or why not,
# and whether nobody's on it (Whozmove --print-compact-for-you, compared with for-you.expected.txt), and what a row
# says once it has (page-cases.js, run with macOS's jsc in UTC, compared with page.expected.txt). Nothing is compacted,
# and nothing is typed into a session.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   modules/compact-at-breaks/tests/test.sh            run and compare
#   modules/compact-at-breaks/tests/test.sh --update   run and save the output as the new expected (after a change
#                                                      you meant)
cd "$(dirname "$0")/../../.." || exit 1
. tests/sandboxed.sh "$@"
HERE=modules/compact-at-breaks/tests
. tests/lib.sh
T=$(throwaway compact-at-breaks) || exit 1
leave_nothing "$T"
. tests/compare.sh
APP=$(built_app "$T") || exit 1

status=0
out=$(
echo "== Whether Compact at Breaks would compact a session at a break now, or why not, and whether nobody's on it"
HOME="$T" "$APP" --print-compact-for-you 2>&1
)
compare "Compact at Breaks" "$HERE/for-you.expected.txt" "$out" "${1:-}" || status=1

page=$(page_cases "$HERE/page-cases.js") || { echo "$page"; exit 1; }
compare "Compact at Breaks' page" "$HERE/page.expected.txt" "$page" "${1:-}" || status=1
exit $status
