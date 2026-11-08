#!/bin/bash
# The edit each key does in a web view being typed in (app/shared/EditKeys.m), the panel's page and a Browser's alike, as
# Whozmove --print-edit-keys prints it: ⌘V, ⌘C, ⌘X, ⌘A, ⌘Z and ⇧⌘Z, and none while nothing in it has the keyboard,
# compared with tests/keys.expected.txt.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   tests/keys.sh            run and compare
#   tests/keys.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/.." || exit 1
. tests/sandboxed.sh "$@"
# Stops here if there's no temporary folder: an empty T would make the clean-up below delete this checkout.
T=$(mktemp -d "${TMPDIR:-/tmp}/whozmove-keys.XXXXXX") || exit 1
T=$(cd "$T" && pwd -P) || exit 1
trap 'rm -rf "$T"' EXIT
. tests/lib.sh
. tests/compare.sh
APP=$(built_app "$T") || exit 1

out=$(HOME="$T" "$APP" --print-edit-keys 2>&1)
compare "The edit keys" tests/keys.expected.txt "$out" "${1:-}"
