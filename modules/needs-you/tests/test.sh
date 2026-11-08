#!/bin/bash
# The needs-you module's tests: what's new in a session, how much it needs you, whether you're in its tab, what a
# module says beside it, and the notices it sends (page-cases.js, run with macOS's jsc in UTC, compared with
# page.expected.txt).
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   modules/needs-you/tests/test.sh            run and compare
#   modules/needs-you/tests/test.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/../../.." || exit 1
. tests/sandboxed.sh "$@"
HERE=modules/needs-you/tests
. tests/lib.sh
. tests/compare.sh

page=$(page_cases "$HERE/page-cases.js") || { echo "$page"; exit 1; }
compare "What needs you" "$HERE/page.expected.txt" "$page" "${1:-}"
