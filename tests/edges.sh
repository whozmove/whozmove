#!/bin/bash
# What the panel's edge does with sample panels and screens (app/core/EdgeIcon.m, SideCat.m and PanelWindow.m), as
# Whozmove --print-edges prints it: the side the icons at its edge are on, where the panel folds round Whozmove beside
# it, whether a two-finger swipe is the panel's and flicks it off the screen's edge, where a flicked panel goes and how
# much of it shows on its way, and which way what comes out of the folded cat goes, the room the window takes in for
# it and where that takes a click, compared with tests/edges.expected.txt.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   tests/edges.sh            run and compare
#   tests/edges.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/.." || exit 1
# Stops here if there's no temporary folder: an empty T would make the clean-up below delete this checkout.
T=$(mktemp -d "${TMPDIR:-/tmp}/whozmove-edges.XXXXXX") || exit 1
T=$(cd "$T" && pwd -P) || exit 1
trap 'rm -rf "$T"' EXIT
. tests/lib.sh
. tests/compare.sh
APP=$(built_app "$T") || exit 1

out=$(HOME="$T" "$APP" --print-edges 2>&1)
compare "The panel's edge" tests/edges.expected.txt "$out" "${1:-}"
