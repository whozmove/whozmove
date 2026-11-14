#!/bin/bash
# The changes module's tests: when a checkout's changes are due a count for sample states (Whozmove --print-count-due,
# compared with count-due.expected.txt). No checkout is read. What the changes view is sent is tests/rows.sh's.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   modules/changes/tests/test.sh            run and compare
#   modules/changes/tests/test.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/../../.." || exit 1
. tests/sandboxed.sh "$@"
HERE=modules/changes/tests
. tests/lib.sh
T=$(throwaway changes) || exit 1
leave_nothing "$T"
. tests/compare.sh
APP=$(built_app "$T") || exit 1

out=$(
echo "== When a checkout's changes are due a count"
HOME="$T" "$APP" --print-count-due 2>&1
)
compare "Changes" "$HERE/count-due.expected.txt" "$out" "${1:-}"
