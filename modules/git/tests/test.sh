#!/bin/bash
# The git module's tests: whether a checkout's branch keeps a pull request of its own, and when it's due its look-up,
# never on the repo's base branch (Whozmove --print-pr-due, compared with pr-due.expected.txt). Which checkouts each
# kind of change is told for (Whozmove --print-watched, compared with watched.expected.txt), so git runs only for the
# checkouts that changed. A throwaway repo, shop, with a worktree its repo lists (shop-try), a submodule inside it
# (parts), and shop listed by a link to it (shop-link), as a session's folder can be; each change is made in turn, and
# what macOS tells of it is noted. Then whether sample branches are on a remote, loose and packed, and when a
# checkout's git status is due a read. Then what wakes a session waiting on a pull request (Whozmove --print-pr-wakes,
# from a made-up answer of gh's, compared with pr-wakes.expected.txt).
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   modules/git/tests/test.sh            run and compare
#   modules/git/tests/test.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/../../.." || exit 1
. tests/sandboxed.sh "$@"
HERE=modules/git/tests
# Stops here if there's no temporary folder: an empty T would make the clean-up below delete this checkout.
T=$(mktemp -d "${TMPDIR:-/tmp}/whozmove-git.XXXXXX") || exit 1
T=$(cd "$T" && pwd -P) || exit 1
trap 'rm -rf "$T"' EXIT
. tests/lib.sh
. tests/compare.sh
APP=$(built_app "$T") || exit 1

# When a branch's pull request is looked up: every 60s, at once after a switch, and never on the base branch, which
# pull requests go into. It needs no file events, so it's compared first.
due=$(HOME="$T" "$APP" --print-pr-due 2>&1)
compare "When a branch's pull request is looked up" "$HERE/pr-due.expected.txt" "$due" "${1:-}"
prdue=$?

# git here ignores your personal git settings, and records with a made-up name.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
G="git -c user.email=t@example.invalid -c user.name=t -c protocol.file.allow=always"
$G -C "$T" init -q -b main parts-src
echo a > "$T/parts-src/p.txt"
$G -C "$T/parts-src" add p.txt
$G -C "$T/parts-src" commit -q -m init
$G -C "$T" init -q -b main shop
echo a > "$T/shop/a.txt"
$G -C "$T/shop" add a.txt
$G -C "$T/shop" commit -q -m init
$G -C "$T/shop" submodule -q add "$T/parts-src" parts 2>/dev/null
$G -C "$T/shop" commit -q -m parts
$G -C "$T/shop" worktree add -q -b try "$T/shop-try"
ln -s "$T/shop" "$T/shop-link"

# Each change is made here, then named to the app once macOS has had time to tell it (a slow or busy Mac, as a CI
# runner can be, tells it seconds later), and the next waits until the app has counted it.
reads() {
  for r in "$T/shop" "$T/shop-try" "$T/shop/parts"; do
    for c in status "log -1" show "diff HEAD"; do git --no-optional-locks -C "$r" $c >/dev/null; done
  done
}
changes() {
  sleep 2  # the app starting to watch
  step() { "${@:2}" >/dev/null; sleep 2; echo "$1"; sleep 2; }
  step "nothing" true
  step "git reads in each, as Whozmove reads (status, log, show, diff)" reads
  step "a file edited in the worktree" sh -c "echo x >> '$T/shop-try/a.txt'"
  step "a file edited in shop, through its link" sh -c "echo x >> '$T/shop-link/a.txt'"
  step "a new file in shop" sh -c "echo n > '$T/shop/new.txt'"
  step "a file edited in the submodule" sh -c "echo x >> '$T/shop/parts/p.txt'"
  step "staged in the worktree" $G -C "$T/shop-try" add a.txt
  step "a commit in the worktree" $G -C "$T/shop-try" commit -q -m w
  step "a commit in the submodule" $G -C "$T/shop/parts" commit -q -am p
  # Each commit in shop commits something it stages, so git writes its index whatever its version: one with nothing
  # new may leave the index as it was, or write it.
  step "a commit in shop, on main, the base with no copy on a remote" sh -c "$G -C '$T/shop' add a.txt \
    && $G -C '$T/shop' commit -q -m m1"
  step "a remote added (config)" $G -C "$T/shop" remote add origin "$T/parts-src"
  step "a remote branch moves (a packed ref)" sh -c "$G -C '$T/shop' update-ref refs/remotes/origin/main HEAD \
    && $G -C '$T/shop' pack-refs --all"
  step "a commit in shop, on main, now with a copy on a remote" sh -c "$G -C '$T/shop' add new.txt \
    && $G -C '$T/shop' commit -q -m m2"
  step "another branch made in shop" $G -C "$T/shop" branch other
  echo branches
  printf '%s\t%s\n' "$T/shop" main "$T/shop" try "$T/shop" nosuch "$T/shop-try" main
}
out=$(changes | "$APP" --print-watched "$T/shop-link" "$T/shop-try" "$T/shop/parts" 2>&1 | sed -e "s|$T|T|g")
compare "Watched checkouts" "$HERE/watched.expected.txt" "$out" "${1:-}"
watched=$?

# What wakes a session waiting on a pull request, from a made-up answer of gh's (pr-activity.json) for a wait begun at
# 12:00: only people GitHub marks as able to change the repo, never a stranger or a bot, nothing from before the wait,
# comments only when the wait asked for them, and the merge.
pr=$(HOME="$T" "$APP" --print-pr-wakes "$HERE/pr-activity.json" 2030-01-01T12:00:00Z 2>&1)
compare "What wakes a session waiting on a pull request" "$HERE/pr-wakes.expected.txt" "$pr" "${1:-}"
exit $((prdue | watched | $?))
