#!/bin/bash
# The Claude Desktop module's tests: how panel.log says what's written in a conversation's message box, a slash command
# by its first word and anything else as "words", and what Claude's window shows round it, naming only Claude's own
# labels, each from sample words holding a made-up token that never comes back (Whozmove --print-desktop-logs),
# compared with logs.expected.txt.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   modules/claude-desktop/tests/test.sh            run and compare
#   modules/claude-desktop/tests/test.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/../../.." || exit 1
. tests/sandboxed.sh "$@"
HERE=modules/claude-desktop/tests
. tests/lib.sh
. tests/compare.sh
# Stops here if there's no temporary folder: an empty T would make the clean-up below delete this checkout.
T=$(mktemp -d "${TMPDIR:-/tmp}/wz-desktop.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
APP=$(built_app "$T") || exit 1
out=$(HOME="$T" "$APP" --print-desktop-logs 2>&1)
compare "How the log says Claude Desktop's words" "$HERE/logs.expected.txt" "$out" "${1:-}"
