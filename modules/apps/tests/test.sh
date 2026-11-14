#!/bin/bash
# The apps module's tests: what every module lists for the panel's back (Whozmove --print-apps, compared with
# apps.expected.txt), Settings' rows (Whozmove --print-settings, compared with settings.expected.txt), a made-up tool's
# page with groups and what each press makes of it (Whozmove --print-app-page, compared with app-page.expected.txt),
# and what the back's page makes of it (page-cases.js, run with macOS's jsc in UTC with the back page's scripts,
# compared with page.expected.txt).
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   modules/apps/tests/test.sh            run and compare
#   modules/apps/tests/test.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/../../.." || exit 1
. tests/sandboxed.sh "$@"
HERE=modules/apps/tests
. tests/lib.sh
T=$(throwaway apps) || exit 1
leave_nothing "$T"
. tests/compare.sh
APP=$(built_app "$T") || exit 1

status=0
out=$(
echo "== The apps every module lists for the panel's back, in their order, with the switches other modules add"
HOME="$T" "$APP" --print-apps
)
compare "The apps" "$HERE/apps.expected.txt" "$out" "${1:-}" || status=1

out=$(
echo "== Settings' rows, the panel's own and each module's, in their order"
HOME="$T" "$APP" --print-settings
)
compare "The settings" "$HERE/settings.expected.txt" "$out" "${1:-}" || status=1

out=$(
echo "== A made-up tool's page with groups, and what each press makes of it"
HOME="$T" "$APP" --print-app-page
)
compare "A tool's page" "$HERE/app-page.expected.txt" "$out" "${1:-}" || status=1

page=$(page_cases "$HERE/page-cases.js" apps/back) || { echo "$page"; exit 1; }
compare "The back's page" "$HERE/page.expected.txt" "$page" "${1:-}" || status=1
exit $status
