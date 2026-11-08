#!/bin/bash
# A plan at a glance, its tests: the short view read from a plan's own block, or pulled only from headings that are each
# slot; the sections it folds; the words picks go back in; and what the reader and the plan card are given to draw,
# escaped (page-cases.js, run with macOS's jsc in UTC, compared with page.expected.txt).
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   modules/plans/tests/test.sh            run and compare
#   modules/plans/tests/test.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/../../.." || exit 1
. tests/sandboxed.sh "$@"
HERE=modules/plans/tests
. tests/lib.sh
. tests/compare.sh

page=$(page_cases "$HERE/page-cases.js") || { echo "$page"; exit 1; }
compare "A plan at a glance" "$HERE/page.expected.txt" "$page" "${1:-}"
