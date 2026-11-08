#!/bin/bash
# The bring-forward module's tests: what each saved pick reads as, and when sample holds of each pair of keys count
# (Whozmove --print-held-keys, compared with held-keys.expected.txt). Nothing is brought forward, and no key is
# looked at.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   modules/bring-forward/tests/test.sh            run and compare
#   modules/bring-forward/tests/test.sh --update   run and save the output as the new expected (after a change you
#                                                  meant)
cd "$(dirname "$0")/../../.." || exit 1
. tests/sandboxed.sh "$@"
HERE=modules/bring-forward/tests
# Stops here if there's no temporary folder: an empty T would make the clean-up below delete this checkout.
T=$(mktemp -d "${TMPDIR:-/tmp}/whozmove-bring-forward.XXXXXX") || exit 1
T=$(cd "$T" && pwd -P) || exit 1
trap 'rm -rf "$T"' EXIT
. tests/lib.sh
. tests/compare.sh
APP=$(built_app "$T") || exit 1

out=$(
echo "== Saved picks, and when held keys count"
HOME="$T" "$APP" --print-held-keys 2>&1
)
compare "Bring Forward" "$HERE/held-keys.expected.txt" "$out" "${1:-}"
