#!/bin/bash
# The notifications module's tests: what it keeps for the user, what they put away and until when
# (Whozmove --print-notices, compared with notices.expected.txt), and its decider (page-cases.js, run with macOS's jsc
# in UTC, compared with page.expected.txt).
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   modules/notifications/tests/test.sh            run and compare
#   modules/notifications/tests/test.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/../../.." || exit 1
. tests/sandboxed.sh "$@"
HERE=modules/notifications/tests
. tests/lib.sh
T=$(throwaway notifications) || exit 1
leave_nothing "$T"
. tests/compare.sh
APP=$(built_app "$T") || exit 1

failed=0
out=$(HOME="$T" "$APP" --print-notices 2>&1)
compare "What notifications keeps" "$HERE/notices.expected.txt" "$out" "${1:-}" || failed=1
page=$(page_cases "$HERE/page-cases.js") || { echo "$page"; exit 1; }
compare "Notifications' decider" "$HERE/page.expected.txt" "$page" "${1:-}" || failed=1
exit $failed
