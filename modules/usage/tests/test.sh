#!/bin/bash
# The usage module's tests: what the usage card shows from what the app found, and the vine's growth and reset frame by
# frame (page-cases.js, run with macOS's jsc in UTC with the card page's scripts, compared with page.expected.txt).
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   modules/usage/tests/test.sh            run and compare
#   modules/usage/tests/test.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/../../.." || exit 1
HERE=modules/usage/tests
. tests/lib.sh
. tests/compare.sh
page=$(page_cases "$HERE/page-cases.js" usage/card) || { echo "$page"; exit 1; }
compare "Usage's page" "$HERE/page.expected.txt" "$page" "${1:-}"
