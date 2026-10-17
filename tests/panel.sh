#!/bin/bash
# Runs the panel page's logic outside the app with macOS's JavaScriptCore (jsc): which section, label and
# colour each sample session gets, how rows sort, and the HTML of sample rows (tests/panel-cases.js).
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Compares the output with tests/panel.expected.txt; prints the difference and exits 1 if anything changed.
#   tests/panel.sh            run and compare
#   tests/panel.sh --update   run and save the output as the new expected (after a change you meant)
# Needs nothing beyond macOS. Takes under a second.
cd "$(dirname "$0")/.." || exit 1
REPO=$PWD
. "$REPO/tests/lib.sh"
. "$REPO/tests/compare.sh"
out=$(page_cases tests/panel-cases.js) || { echo "$out"; exit 1; }
compare Panel "$REPO/tests/panel.expected.txt" "$out" "${1:-}"
