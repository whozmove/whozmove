#!/bin/bash
# The side chat module's tests: what its record keeps as your words move on, whether held words go in by themselves,
# and a reply cut into prose and code (Whozmove --print-side-chat, compared with record.expected.txt); then what it says
# before you send, how far your words got, its replies and Side Chat on the row, and the HTML they're drawn as
# (page-cases.js, run with macOS's jsc in UTC, compared with page.expected.txt).
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   modules/side-chat/tests/test.sh            run and compare
#   modules/side-chat/tests/test.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/../../.." || exit 1
. tests/sandboxed.sh "$@"
HERE=modules/side-chat/tests
# Stops here if there's no temporary folder: an empty T would make the clean-up below delete this checkout.
T=$(mktemp -d "${TMPDIR:-/tmp}/whozmove-side-chat.XXXXXX") || exit 1
T=$(cd "$T" && pwd -P) || exit 1
trap 'rm -rf "$T"' EXIT
. tests/lib.sh
. tests/compare.sh
APP=$(built_app "$T") || exit 1

status=0
out=$(HOME="$T" "$APP" --print-side-chat 2>&1)
compare "The side chat's record" "$HERE/record.expected.txt" "$out" "${1:-}" || status=1

page=$(page_cases "$HERE/page-cases.js") || { echo "$page"; exit 1; }
compare "The side chat's page" "$HERE/page.expected.txt" "$page" "${1:-}" || status=1
exit $status
