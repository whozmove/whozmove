#!/bin/bash
# What the panel's edge does with sample panels and screens (parts/edge, parts/beside and PanelWindow's parts), as
# Whozmove --print-edges prints it: the side the icons at its edge are on, where the panel folds round Whozmove beside
# it, whether a two-finger swipe is the panel's and flicks it off the screen's edge, where a flicked panel goes and how
# much of it shows on its way, how far a swipe on Whozmove there pulls it back out, whether it then comes back, and how
# far that pushes Whozmove in, which way what comes out of the folded cat goes, the room the window takes in for it
# and where that takes a click, the room the window asks for to turn over, where macOS keeps it at the top of the
# screen and how far that moves it, and how tall the header and the list may get on a screen and the open panel where
# it is, with room kept for what hangs below it, compared with tests/edges.expected.txt. Which of the two the app places the page by
# is AppKit's to show, with a window on the screen, so trying the turn on the real app is what checks that.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   tests/edges.sh            run and compare
#   tests/edges.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/.." || exit 1
. tests/sandboxed.sh "$@"
. tests/lib.sh
T=$(throwaway edges) || exit 1
leave_nothing "$T"
. tests/compare.sh
APP=$(built_app "$T") || exit 1

out=$(HOME="$T" "$APP" --print-edges 2>&1)
compare "The panel's edge" tests/edges.expected.txt "$out" "${1:-}"
