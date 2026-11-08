#!/bin/bash
# The team module's tests: Group by Team's groups, what its rows say and show (page-cases.js, run with macOS's jsc in
# UTC, compared with page.expected.txt), and who holds a member's seat in its workspace (seats-cases.json, compared
# with seats.expected.txt). What the app reads from the team file is checked with the rows (tests/rows.sh).
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   modules/team/tests/test.sh            run and compare
#   modules/team/tests/test.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/../../.." || exit 1
. tests/sandboxed.sh "$@"
HERE=modules/team/tests
. tests/lib.sh
. tests/compare.sh

page=$(page_cases "$HERE/page-cases.js") || { echo "$page"; exit 1; }
status=0
compare "The team's page" "$HERE/page.expected.txt" "$page" "${1:-}" || status=1

# Who holds a member's seat in its workspace for sample cases (Whozmove --print-seats), compared with
# seats.expected.txt.
T=$(mktemp -d "${TMPDIR:-/tmp}/wz-team.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
APP=$(built_app "$T") || exit 1
seats=$(HOME="$T" "$APP" --print-seats "$HERE/seats-cases.json" 2>&1) || { echo "$seats"; exit 1; }
compare "Who holds a member's seat" "$HERE/seats.expected.txt" "$seats" "${1:-}" || status=1
exit $status
