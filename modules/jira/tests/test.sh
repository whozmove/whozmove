#!/bin/bash
# The Jira module's tests: its plain functions (keys and links, the search's JQL, the kinds, the sign-in's PKCE and
# the card on the panel's back in every state; Whozmove --print-jira facts), made-up answers recorded in Atlassian's
# shapes read into tickets (answers/, --print-jira answers), and a whole sign-in and every call against a stand-in for
# Atlassian on 127.0.0.1 (stand-in.py, --print-jira talk): signed in and out, an admin's block, a request to slow down
# and a sign-in that has run out, that other apps can read, that something changed since this build kept it, or that
# reads only; a ticket's place among its project's priorities, the list read once a project, again only for a priority
# not among it, and not at all; a ticket's description as Markdown, as Atlassian's document format and cut when long,
# never in panel.log; and a read failing each way, logged by how it failed, with no word of its answer. Each in a throwaway home, so nothing reaches Atlassian or your Keychain, and nothing
# opens. Compared with jira.expected.txt.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   modules/jira/tests/test.sh            run and compare
#   modules/jira/tests/test.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/../../.." || exit 1
. tests/sandboxed.sh "$@"
HERE=modules/jira/tests
# Stops here if there's no temporary folder: an empty T would make the clean-up below delete this checkout.
T=$(mktemp -d "${TMPDIR:-/tmp}/whozmove-jira.XXXXXX") || exit 1
T=$(cd "$T" && pwd -P) || exit 1
STANDINS=()
trap 'for p in "${STANDINS[@]}"; do kill "$p" 2>/dev/null; done; rm -rf "$T"' EXIT
. tests/lib.sh
. tests/compare.sh
APP=$(built_app "$T") || exit 1

# One talk with a stand-in of its own, in a home of its own: the stand-in's mode, then the steps. Prints what the run
# said, then what the stand-in was asked.
talk() {
  local mode=$1 home="$T/home-${1:-plain}"
  shift
  # Whozmove's own folder, which the app makes as it starts, so panel.log can be written and read back.
  mkdir -p "$home/Library/Application Support/Whozmove"
  # Its own output goes to a file: one left on this run's pipe would hold the $( ) below open.
  python3 -I "$HERE/stand-in.py" "$home/port" "$home/asked" $mode >"$home/stand-in.out" 2>&1 &
  local standin=$!
  STANDINS+=($standin)
  for _ in $(seq 50); do [ -s "$home/port" ] && break; sleep 0.1; done
  echo "## talk${mode:+ ($mode)}"
  HOME="$home" WHOZMOVE_JIRA_SERVER="http://127.0.0.1:$(cat "$home/port")/v2/mcp" "$APP" --print-jira talk acme.atlassian.net "$@" 2>&1
  kill "$standin" 2>/dev/null
  echo "## what the stand-in was asked"
  cat "$home/asked" 2>/dev/null
}

out=$(
  echo "## facts"
  HOME="$T" "$APP" --print-jira facts "$HERE/facts.json" 2>&1
  echo "## answers"
  HOME="$T" "$APP" --print-jira answers "$HERE/answers" acme.atlassian.net 2>&1
  # An entry only this app reads, then one other apps can read (never trusted, nor read, nor changed) and what keeping
  # one afresh does to it. Writing, opening and updating refuse the account's own home; that refusal isn't run here, as
  # tests/checks.sh keeps a test from reaching for it.
  echo "## the Keychain's stand-in, kept afresh"
  for step in has read write has quietly read forget quietly read; do HOME="$T" "$APP" --print-jira keychain $step 2>&1; done
  echo "## the Keychain's stand-in, an entry other apps can read"
  mkdir -p "$T/home-others"
  for step in write open has quietly read update write has update quietly; do
    HOME="$T/home-others" "$APP" --print-jira keychain $step 2>&1
  done
  # One an older build kept, which macOS asks about once, then one this build kept that macOS asks about all the same:
  # something else changed it, so neither read uses it, until it's kept afresh.
  echo "## the Keychain's stand-in, an entry another build kept, or something else changed"
  mkdir -p "$T/home-changed"
  for step in write newbuild quietly read quietly write rewritten has quietly read write quietly; do
    HOME="$T/home-changed" "$APP" --print-jira keychain $step 2>&1
  done
  # Block is turned away by Jira (a field to fill in first): its own words come back, and the ticket stays where it is.
  talk "" "state" "search login" "signin" "kept" "search login" "search PAY-142" "search nothing like it" "read PAY-142" \
    "take PAY-142 41" "take PAY-142 31 The fix is in pull request #57." "take PAY-142 31" "take PAY-142 51" \
    'take PAY-142 51 {"resolution":"Fixed"}' 'take PAY-142 51 {"resolution":"Done"} Signed off.' "read PAY-999" \
    "types PAY" "types NOPE" "create" "read PAY-151" "create refused" "create unread" "fields Task" "fields Task" \
    "fields Epic" "signout" "kept" "state" "log"
  # A ticket's description in Atlassian's document format, read as its plain text; and one longer than a session is
  # handed, cut with a line saying so. Neither reaches panel.log.
  talk adf "signin" "read PAY-142" "log"
  # A read failing each way: HTTP 502, the server's own error, an answer that isn't one, the tool saying it failed (in
  # words, then with a status, then an error with none), and the connection dropped. Each log line says how, in
  # Whozmove's own words, and none of the answer's reaches the log; then how a timeout and macOS's own errors read.
  talk failreads "signin" "read PAY-142" "read PAY-142" "read PAY-142" "read PAY-142" "read PAY-142" "read PAY-142" \
    "read PAY-142" "log" "hows"
  talk longabout "signin" "read PAY-142" "log"
  talk blocked "signin" "state"
  # A project's priorities that can't be read: its ticket reads all the same, with its priority's word and no place;
  # and the fields its tickets take one option of can't be read either, which says so.
  talk nolist "signin" "read PAY-142" "fields Task"
  talk slow "signin" "read PAY-142" "search login"
  # Asked to slow down partway through a read (the search for its type): the read and a move both say so, and the move
  # is never told its step has gone.
  talk slowtype "signin" "read PAY-142" "take PAY-142 31"
  # A move Jira turns away saying nothing is still turned away, which trying again as it is won't change; one Jira
  # answers with a 500, reasons and all, is Jira not managing it just then, which trying again may mend.
  talk silent "signin" "take PAY-142 41"
  talk busy "signin" "take PAY-142 41"
  talk expired "signin" "read PAY-142" "state" "kept"
  # A new build: macOS asks before it gives it the sign-in kept, so nothing reads it until your press of Allow, which
  # keeps it afresh as this build's, so after a restart it's read quietly; then one changed since this build kept it,
  # which macOS asks about all the same: never used, and Sign In Again.
  talk newbuild "signin" "newbuild" "state" "kept" "read PAY-142" "state" "notices" "signin" "read PAY-142" "state" \
    "restart" "read PAY-142" "rewritten" "read PAY-142" "state" "notices" "log" "replaced" "read PAY-142" "state"
  # An entry something else planted, which other apps can read: never used, and signing in again makes a new one.
  talk planted "planted" "state" "read PAY-142" "signin" "read PAY-142" "restart" "read PAY-142" "state" "log"
  # An entry that turns into one other apps can read while Whozmove runs: a refresh isn't kept in it, the new token lives
  # in memory, and once Whozmove starts again the panel says to sign in again.
  talk midsession "signin" "others" "refused" "read PAY-142" "read PAY-142" "log" "restart" "read PAY-142" "state"
  # Writes: one Atlassian refuses for the token's scope says to sign in again, as Jira's page does; and a sign-in kept
  # before Whozmove asked to write still reads, while a move is never sent and the page says to sign in again.
  # A new ticket made, whose answer never comes back: it may have been made, so it's never answered as not made.
  talk drop "signin" "create"
  talk noscope "signin" "card" "take PAY-142 31" "card" "signin" "card" "readonly" "read PAY-142" "take PAY-142 31" \
    "card" "log"
)
compare "Jira" "$HERE/jira.expected.txt" "$out" "${1:-}"
