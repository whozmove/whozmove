#!/bin/bash
# The starts module's tests: what sample starts would run, a terminal tab's command and Claude Desktop's link
# (Whozmove --print-starts, compared with starts.expected.txt), worktrees checked and made in a sample repo (Whozmove
# --print-worktrees, compared with worktrees.expected.txt), and the page's part (page-cases.js, run with macOS's jsc in
# UTC, compared with page.expected.txt).
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   modules/starts/tests/test.sh            run and compare
#   modules/starts/tests/test.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/../../.." || exit 1
HERE=modules/starts/tests
# Stops here if there's no temporary folder: an empty T would make the clean-up below delete this checkout.
T=$(mktemp -d "${TMPDIR:-/tmp}/whozmove-starts.XXXXXX") || exit 1
T=$(cd "$T" && pwd -P) || exit 1
trap 'rm -rf "$T"' EXIT
. tests/lib.sh
. tests/compare.sh
APP=$(built_app "$T") || exit 1

status=0
# The words of a terminal start go in a file in the home folder's Whozmove folder, which the command names. The sample
# home is under /private/var; macOS also gives paths there as /var, so both spellings become T.
out=$({
echo "== New conversations: the command a terminal start runs in its tab, and Claude Desktop's link"
HOME="$T" "$APP" --print-starts | in_minutes
} 2>&1 | sed -e "s|$T|T|g" -e "s|${T#/private}|T|g")
compare Starts "$HERE/starts.expected.txt" "$out" "${1:-}" || status=1

# A sample repo for worktrees: a branch checked out nowhere (release), one taken by name only (taken), a folder in the
# way where Claude Code puts its own, and a folder outside any repo. git here ignores your personal git settings
# (signing, hooks, …).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
git -C "$T" init -q -b main shop
echo one > "$T/shop/a.txt"
git -C "$T/shop" add a.txt
git -C "$T/shop" -c user.email=t@t -c user.name=t commit -q -m init
git -C "$T/shop" branch taken
git -C "$T/shop" branch release
mkdir -p "$T/shop-worktrees/in-the-way" "$T/plain"
out=$({
echo "== Worktrees: what a repo has (its own folder, its worktrees, its branches with no folder), and whether each target"
echo "   can have one (a new branch's name, name:base for another base, +branch for a branch that's there), or why not"
HOME="$T" "$APP" --print-worktrees "$T/shop" fix-login taken in-the-way -dash-first feat/slash two..dots fix-2:release \
  fix-3:nope +release +nope +main | in_minutes
HOME="$T" "$APP" --print-worktrees "$T/plain" fix-login | in_minutes
echo "== Making them: a new branch following the base branch, one following release, and a worktree for release itself;"
echo "   then the repo lists them, and the names are taken"
HOME="$T" "$APP" --print-worktrees --make "$T/shop" fix-login fix-2:release +release | in_minutes
echo "fix-login follows: $(git -C "$T/shop-worktrees/fix-login" rev-parse --abbrev-ref '@{u}')"
echo "fix-2 follows: $(git -C "$T/shop-worktrees/fix-2" rev-parse --abbrev-ref '@{u}')"
echo "release is on: $(git -C "$T/shop-worktrees/release" branch --show-current)"
echo "the repo's own folder is still on: $(git -C "$T/shop" branch --show-current)"
echo "and has nothing new in it: [$(git -C "$T/shop" status --short)]"
HOME="$T" "$APP" --print-worktrees --make "$T/shop" fix-login +release | in_minutes
} 2>&1 | sed -e "s|$T|T|g" -e "s|${T#/private}|T|g")
compare Worktrees "$HERE/worktrees.expected.txt" "$out" "${1:-}" || status=1

page=$(page_cases "$HERE/page-cases.js") || { echo "$page"; exit 1; }
compare "Starts' page" "$HERE/page.expected.txt" "$page" "${1:-}" || status=1
exit $status
