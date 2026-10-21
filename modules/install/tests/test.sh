#!/bin/bash
# The install module's tests: Whozmove setting itself up as it opens (Whozmove --print-install), with stand-ins for
# where it runs from, whether an agent made it, Apple's developer tools, macOS's installer for them and the agent,
# against a throwaway HOME (never your real Whozmove folder), and what the panel's back says of it
# (--print-install-cards), compared with install.expected.txt beside this file; and what the line under the header says
# (page-cases.js, run with macOS's jsc in UTC with the page's scripts), compared with page.expected.txt.
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
echo "== Opened again while it's still so: since when it has been so is kept, so a × on the line still holds"
HOME="$T" "$APP" --print-install turned-off-again
echo "== Install: macOS's installer opens, and while it's open, and once after, macOS is asked again at each look;"
echo "   closed without them, they're missing again; and once they're in, Install asks for nothing"
HOME="$T" "$APP" --print-install install-pressed installer-closed tools-in-first
echo "== Install without the agent, and from outside an Applications folder: for Git's page, it opens the installer all"
echo "   the same"
HOME="$T" "$APP" --print-install install-without-agent install-outside
echo "== Open at Login: on from the very first open, then as you set it; the login item put right for this app"
echo "   wherever it runs from, never loaded into launchd from here, and its job unloaded only when taken out by"
echo "   another copy than the one launchd runs"
HOME="$T" "$APP" --print-install login-first login-kept login-moved login-chosen-off login-turned-off \
  login-turned-off-in-its-copy login-turned-on-again login-outside
echo "== A newer Whozmove: for a copy Homebrew installed, from its tap's cask, Homebrew's copy on this Mac and"
echo "   GitHub's, the newer counting, against this copy's version; never for one Homebrew didn't install"
HOME="$T" "$APP" --print-updates newer same older newer-by-a-part github-ahead github-behind no-network \
  tap-not-published garbled-cask another-tap not-homebrew strange-tap installed-not-restarted test-tap
echo "== …and look by look: a build from a checkout never looks, a version put away stays away across launches until a"
echo "   newer one, and a look GitHub doesn't answer keeps what it said last"
HOME="$T" "$APP" --print-updates checkout-never-looks put-away-stays-away newer-after-put-away \
  offline-keeps-what-github-said
echo "== What the panel's back says: on Git's page, of the developer tools; on the agent's, of its hooks"
HOME="$T" "$APP" --print-install-cards
)
status=0
compare "Install" "$HERE/install.expected.txt" "$out" "${1:-}" || status=1

page=$(page_cases "$HERE/page-cases.js") || { echo "$page"; exit 1; }
compare "The line" "$HERE/page.expected.txt" "$page" "${1:-}" || status=1
exit $status
