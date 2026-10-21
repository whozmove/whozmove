#!/bin/bash
# The install module's tests: Whozmove setting itself up as it opens (Whozmove --print-install), with stand-ins for
# where it runs from, whether an agent made it, Apple's developer tools and the agent, against a throwaway HOME (never
# your real Whozmove folder), compared with install.expected.txt beside this file.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   modules/install/tests/test.sh            run and compare
#   modules/install/tests/test.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/../../.." || exit 1
HERE=modules/install/tests
# Stops here if there's no temporary folder: an empty T would make the clean-up below delete this checkout.
T=$(mktemp -d "${TMPDIR:-/tmp}/whozmove-install.XXXXXX") || exit 1
T=$(cd "$T" && pwd -P) || exit 1
trap 'rm -rf "$T"' EXIT
. tests/lib.sh
. tests/compare.sh
APP=$(built_app "$T") || exit 1

out=$(
echo "== Where it runs from: only an Applications folder, at any depth, gets anything set up"
HOME="$T" "$APP" --print-install applications nested downloads disk-image translocated build-folder
echo "== A build an agent made: where it runs from is noted, its hooks are left as they are"
HOME="$T" "$APP" --print-install agent-build
echo "== Waiting for the agent, then for Apple's developer tools, then carrying on at the next look"
HOME="$T" "$APP" --print-install no-agent-yet tools-later neither-yet no-command-yet
echo "== Hooks taken out of the agent, or turned off in it, and two presses on the line one after the other"
HOME="$T" "$APP" --print-install taken-out turned-off presses
)
compare "Install" "$HERE/install.expected.txt" "$out" "${1:-}"
