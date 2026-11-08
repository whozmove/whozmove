#!/bin/bash
# The team board's tests: where each job stands, its goals as tiles, the kinds of what needs you, the lead's order, what
# Take Me There opens, and what the board draws (page-cases.js, run with macOS's jsc in UTC, compared with
# page.expected.txt). What it's told comes from the team module's --print-teams, which tests/rows.sh checks.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   modules/board/tests/test.sh            run and compare
#   modules/board/tests/test.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/../../.." || exit 1
. tests/sandboxed.sh "$@"
HERE=modules/board/tests
. tests/lib.sh
. tests/compare.sh

page=$(page_cases "$HERE/page-cases.js") || { echo "$page"; exit 1; }
compare "The board's page" "$HERE/page.expected.txt" "$page" "${1:-}"
