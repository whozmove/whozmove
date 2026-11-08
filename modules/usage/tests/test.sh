#!/bin/bash
# The usage module's tests: what the usage card shows from what the app found, and the vine's growth and reset frame by
# frame (page-cases.js, run with macOS's jsc in UTC with the card page's scripts, compared with page.expected.txt), its
# part of the panel's page (panel-cases.js, compared with panel.expected.txt); and
# when the usage is asked (checks-cases.json, compared with checks.expected.txt), what's kept of an answer
# (kept-usage.json, compared with kept.expected.txt), your gear (gear-cases.json, compared with gear.expected.txt), what
# the log says as each answer comes (said-answers.json, compared with said.expected.txt), and why Sign in can't open
# with no terminal, and what the card says with the command to run yourself (compared with sign-in.expected.txt).
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   modules/usage/tests/test.sh            run and compare
#   modules/usage/tests/test.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/../../.." || exit 1
. tests/sandboxed.sh "$@"
HERE=modules/usage/tests
. tests/lib.sh
. tests/compare.sh
page=$(page_cases "$HERE/page-cases.js" usage/card) || { echo "$page"; exit 1; }
status=0
compare "Usage's page" "$HERE/page.expected.txt" "$page" "${1:-}" || status=1

# Its part of the panel's page (panel-cases.js, with the panel page's scripts): the gear beyond the card, and Over the
# gear on the rows working beyond it, compared with panel.expected.txt.
panel=$(page_cases "$HERE/panel-cases.js") || { echo "$panel"; exit 1; }
compare "Usage on the panel's page" "$HERE/panel.expected.txt" "$panel" "${1:-}" || status=1

# When the usage would be asked over sample stretches of time (Whozmove --print-usage-checks), compared with
# checks.expected.txt.
T=$(mktemp -d "${TMPDIR:-/tmp}/wz-usage.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
APP=$(built_app "$T") || exit 1
checks=$("$APP" --print-usage-checks "$HERE/checks-cases.json" 2>&1) || { echo "$checks"; exit 1; }
compare "Usage's checks" "$HERE/checks.expected.txt" "$checks" "${1:-}" || status=1

# What's kept of an answer for a script of yours to read (Whozmove --print-usage-kept, in a throwaway home): the
# checked time and each window's percent and reset, nothing else, compared with kept.expected.txt.
kept=$(HOME="$T" "$APP" --print-usage-kept "$HERE/kept-usage.json" 2>&1) || { echo "$kept"; exit 1; }
compare "What's kept of the usage" "$HERE/kept.expected.txt" "$kept" "${1:-}" || status=1

# Your gear (Whozmove --print-gear, in a throwaway home, as it writes gear.json): who's counted as working, what the reads
# add up, what the kept answers measure, a press, what's kept and gear.json, compared with gear.expected.txt.
gear=$(HOME="$T" "$APP" --print-gear "$HERE/gear-cases.json" 2>&1) || { echo "$gear"; exit 1; }
compare "Your gear" "$HERE/gear.expected.txt" "$gear" "${1:-}" || status=1

# What panel.log says as each answer comes (Whozmove --print-usage-said, in a throwaway home, as it writes panel.log):
# with the card hidden, why, once each time the reason changes and once as Whozmove starts; else the state, as always.
# Made-up answers, compared with said.expected.txt.
said=$(HOME="$T" "$APP" --print-usage-said "$HERE/said-answers.json" 2>&1) || { echo "$said"; exit 1; }
compare "What the log says of the usage" "$HERE/said.expected.txt" "$said" "${1:-}" || status=1

# Why Sign in can't open with no terminal on this Mac (Whozmove --print-sign-in): naming the terminals Whozmove opens,
# those the core finds, so a terminal module added or taken out changes it, and for none, one and two; then the reason
# with the command to run yourself, for a sample command, with none and for a reason ending in a full stop, compared
# with sign-in.expected.txt.
signin=$(HOME="$T" "$APP" --print-sign-in 2>&1) || { echo "$signin"; exit 1; }
compare "Sign in when it can't open" "$HERE/sign-in.expected.txt" "$signin" "${1:-}" || status=1
exit $status
