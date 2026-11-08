#!/bin/bash
# The commands module's tests: how panel.log says each kind of command, never its words, and a /compact whose focus
# holds a made-up token sent to a stand-in session named Compacter, which nothing can type into, with the token in none
# of the log (Whozmove --print-command-logs, in a throwaway home), compared with logs.expected.txt.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   modules/commands/tests/test.sh            run and compare
#   modules/commands/tests/test.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/../../.." || exit 1
. tests/sandboxed.sh "$@"
HERE=modules/commands/tests
. tests/lib.sh
. tests/compare.sh
# Stops here if there's no temporary folder: an empty T would make the clean-up below delete this checkout.
T=$(mktemp -d "${TMPDIR:-/tmp}/wz-commands.XXXXXX") || exit 1
T=$(cd "$T" && pwd -P) || exit 1
# The stand-in's process is kept in $T/pids so it's stopped however this ends.
trap 'kill $(cat "$T/pids" 2>/dev/null) 2>/dev/null; rm -rf "$T"' EXIT
APP=$(built_app "$T") || exit 1

# Compacter: a stand-in session, as Claude Code's registry lists it, idle in a folder of its own, its process a sleep
# this test started.
mkdir -p "$T/.claude/sessions" "$T/work"
sleep 600 >/dev/null 2>&1 &
COMPACTER=$!; echo $COMPACTER >> "$T/pids"; disown $COMPACTER
now=$(python3 -c 'import time; print(int(time.time() * 1000))')
echo "{\"pid\": $COMPACTER, \"sessionId\": \"s-compacter\", \"name\": \"Compacter\", \"kind\": \"interactive\",
       \"entrypoint\": \"cli\", \"cwd\": \"$T/work\", \"status\": \"idle\", \"startedAt\": $now,
       \"statusUpdatedAt\": $now}" > "$T/.claude/sessions/$COMPACTER.json"

out=$(HOME="$T" "$APP" --print-command-logs 2>&1)
compare "How the log says a command" "$HERE/logs.expected.txt" "$out" "${1:-}"
