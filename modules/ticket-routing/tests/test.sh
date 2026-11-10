#!/bin/bash
# The ticket routing module's tests: in a made-up repo with two worktrees and a folder outside it, with a made-up
# tracker (Whozmove --print-ticket-routing, in throwaway homes; routing.expected.txt): the card's asks for a project
# with no way yet (the guide, and the field it offers), each way set and what a ticket gets by it, a ticket with no
# option, an option with no folder and a ticket not read, what's kept (only you can read it) and read back after a
# restart, a file changed by hand with a folder outside the project let go, Settings' page with each way's before and
# after, an option's folder picked there, the plain match by name, and panel.log, which names only the project whose
# way changed. Then the page's part (page-cases.js, with macOS's jsc in UTC; page.expected.txt).
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   modules/ticket-routing/tests/test.sh            run and compare
#   modules/ticket-routing/tests/test.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/../../.." || exit 1
. tests/sandboxed.sh "$@"
HERE=modules/ticket-routing/tests
# Stops here if there's no temporary folder: an empty T would make the clean-up below delete this checkout.
T=$(mktemp -d "${TMPDIR:-/tmp}/whozmove-routing.XXXXXX") || exit 1
T=$(cd "$T" && pwd -P) || exit 1
trap 'rm -rf "$T"' EXIT
. tests/lib.sh
. tests/compare.sh
APP=$(built_app "$T") || exit 1
status=0

# A made-up repo, acme-shop, with a worktree for its checkout team beside it, one named for its billing team, and a
# folder outside any repo. git here ignores your personal git settings (signing, hooks, …).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$T/code"
git -C "$T/code" init -q -b main acme-shop
echo one > "$T/code/acme-shop/a.txt"
git -C "$T/code/acme-shop" add a.txt
git -C "$T/code/acme-shop" -c user.email=t@t -c user.name=t commit -q -m init
git -C "$T/code/acme-shop" worktree add -q -b checkout "$T/code/acme-shop-checkout" main
git -C "$T/code/acme-shop" worktree add -q -b team-billing "$T/code/billing" main
mkdir -p "$T/code/elsewhere"
home() {
  mkdir -p "$T/homes/$1"
  echo "$T/homes/$1"
}
R="$T/code/acme-shop"
out=$({
echo "== A project with no way yet: the guide, offering the Team field, whose options match two folders by name"
HOME=$(home first) "$APP" --print-ticket-routing "$R" "team PAY-142 checkout" "ask PAY-142" "match" "kept" 2>&1
echo "== A Team field that lists no options (looked up as you type): the guide offers no field"
HOME=$(home lookup) "$APP" --print-ticket-routing "$R" "lookup" "team PAY-142 checkout" "ask PAY-142" 2>&1
echo "== Outside git: nothing to choose"
HOME=$(home plain) "$APP" --print-ticket-routing "$R" "ask PAY-142 $T/code/elsewhere" 2>&1
echo "== Its own worktree, set from the guide's Start; asked again from one of its worktrees, the same project"
HOME=$(home own) "$APP" --print-ticket-routing "$R" "set own" "ask PAY-142" "ask PAY-150 $T/code/billing" "kept" \
  "logged" 2>&1
echo "== By the Team field: a ticket's option's folder; no option; an option with no folder; not read; a restart"
HOME=$(home field) "$APP" --print-ticket-routing "$R" "team PAY-142 checkout" "ask PAY-142" "set field" \
  "team PAY-150 web" "team PAY-151 none" "team PAY-152 unread" "ask PAY-142" "ask PAY-150" "ask PAY-151" \
  "ask PAY-152" "relaunch" "ask PAY-142" "kept" 2>&1
echo "== Changed by hand: billing's folder outside the project is let go; billing's own worktree in its place again"
HOME=$(home hand) "$APP" --print-ticket-routing "$R" "team PAY-142 checkout" "ask PAY-142" "set field" \
  "hand $T/code/elsewhere" "relaunch" "team PAY-160 billing" "ask PAY-160" "logged" 2>&1
echo "== The project's own folder; then Settings: its page, each way's before and after, an option's folder, and the"
echo "   warning a way into the project's folder gives while another ticket's conversation works there"
HOME=$(home settings) "$APP" --print-ticket-routing "$R" "settings" "team PAY-142 checkout" "ask PAY-142" \
  "set folder" "ask PAY-142" "settings" "pick way field" "settings" "pick option 12 $T/code/billing" "settings" \
  "pick option 12 own" "pick way own" "busy PAY-150" "settings" "logged" 2>&1
} | sed -e "s|$T|T|g" -e "s|${T#/private}|T|g")
out=$out$'\n'$({
echo "== A project whose folder has gone: Settings says so, its way written back as it was, until Forget It"
HOME=$(home gone) "$APP" --print-ticket-routing "$R" "set own" "elsewhere $T/code/elsewhere" "relaunch" "settings" \
  "set folder" "kept" "forget" "settings" "kept" "logged" 2>&1
echo "== An option's folder moved away: Settings says it has gone, and its tickets get their own worktree"
HOME=$(home moved) "$APP" --print-ticket-routing "$R" "team PAY-142 checkout" "ask PAY-142" "set field" 2>&1 >/dev/null
mv "$T/code/billing" "$T/code/billing-moved"
HOME=$(home moved) "$APP" --print-ticket-routing "$R" "settings" "team PAY-160 billing" "ask PAY-160" 2>&1
} | sed -e "s|$T|T|g" -e "s|${T#/private}|T|g")
compare "Ticket routing" "$HERE/routing.expected.txt" "$out" "${1:-}" || status=1

page=$(page_cases "$HERE/page-cases.js") || { echo "$page"; exit 1; }
compare "Ticket routing's page" "$HERE/page.expected.txt" "$page" "${1:-}" || status=1
exit $status
