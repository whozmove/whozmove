#!/bin/bash
# The tickets module's tests: a made-up tracker's tickets given to sample sessions by a start and by Use It, never by
# an ask or a file written by hand; what `ask-panel.sh ticket` and `ticket-use` answer at once, with and without a
# ticket, an offer waiting or a Not Now; the rows' `ticket`; what's kept for a later copy of the panel and offered back
# only to the same process; and panel.log carrying no ticket's words, and no file in Whozmove's folder its description,
# which only `ticket`'s answer carries (Whozmove --print-tickets, in a throwaway home).
# Then moves, in another: ticket-move refused, shown on the row for Move It or Not Now, asked again in the first's
# place, failing then tried again, its step gone when pressed, gone as the session ends, and taken by itself under May
# Move Its Ticket, which ends once the ticket changes; ticket-stop marking a person's step, and the mark going; and
# panel.log carrying no note, field or why. Then new tickets, in a third: ticket-draft turned away, checked with the
# tracker, shown for Create Ticket or Not Yet, made only by that press and then the session's ticket, and panel.log
# carrying none of their words. Then a project's conversations reading your tickets, in a fourth: none until a
# conversation in the repo where macOS says it works is given a ticket, or it's turned on, then for all of its worktrees,
# after that conversation ends and across a restart; read and told once, only those changed since, one whole, the
# project's choice off and on, a read that fails, and signed out. Then ask-panel.sh
# turning away a key, a link, a step id, a time or a word that
# isn't one, and stdin too long, before it asks, and the page's part (page-cases.js, with macOS's jsc in UTC).
# Compared with tickets.expected.txt.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   modules/tickets/tests/test.sh            run and compare
#   modules/tickets/tests/test.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/../../.." || exit 1
. tests/sandboxed.sh "$@"
HERE=modules/tickets/tests
# Stops here if there's no temporary folder: an empty T would make the clean-up below delete this checkout.
T=$(mktemp -d "${TMPDIR:-/tmp}/whozmove-tickets.XXXXXX") || exit 1
T=$(cd "$T" && pwd -P) || exit 1
trap 'rm -rf "$T"' EXIT
. tests/lib.sh
. tests/compare.sh
APP=$(built_app "$T") || exit 1

# When each was read, and when to read again, as the app says them (ms since 1970, and a time of day), read the same
# on every run.
same_times() {
  sed -E -e 's/"readAt":[0-9]+/"readAt":"(when read)"/g' -e 's/"readAt":"[0-9T:Z-]+"/"readAt":"(when read)"/g' \
    -e 's/"retryAt":[0-9]+/"retryAt":"(in ten minutes)"/g' -e 's/"at":[0-9]+/"at":"(when)"/g'
}

out=$(
  echo "## given, asked and kept"
  HOME="$T" "$APP" --print-tickets "row s1" "row s2" "ended s3" \
    "ask s1 ticket" "start s1 ABC-1" "ask s1 ticket" "rows" "kept" \
    "ask s2 ticket-use ABC-2" "ask s2 ticket" "rows" "press s2 notNow" "ask s2 ticket" "ask s2 ticket" \
    "ask s2 ticket-link https://one.example/t/ABC-2" "press s2 use" "ask s2 ticket" \
    "ask s2 ticket-use ABC-2" "ask s1 ticket-use ABC-2" "rows" "press s1 notNow" "ask s1 ticket" "ask s1 ticket" \
    "ask s1 ticket-use not-a-key" "ask s1 ticket-link https://elsewhere.test/t/ABC-1" \
    "start s3 not a key" "start s3 ABC-9" "ask s3 ticket" "fails slow" "start s3 ABC-2" "ask s3 ticket" "ask s3 ticket-use ABC-1" "rows" \
    "fails signIn" "start s3 ABC-1" "ask s3 ticket" "fails failed" "start s3 ABC-1" "ask s3 ticket" \
    "hand-kept s4 ABC-1" "row s4" "ask s4 ticket" "relaunch" "rows" "ask s4 ticket" "press s4 use" "rows" \
    "fails failed" "ask s1 ticket-use ABC-2" "rows" "ask s1 ticket-use ABC-2" "rows" "ask s1 ticket-use ABC-9" "rows" \
    "press s2 notNow" "kept" "log" 2>&1 | same_times
  echo "## moves"
  mkdir -p "$T/moves"
  note='{"note": "Ready: pull request 57"}'
  finish='{"note": "The fix is in pull request 57", "fields": {"resolution": "Fixed", "fixVersion": ["2.1"]}}'
  HOME="$T/moves" "$APP" --print-tickets "row s5" "row s6" "menu s5" "move s5 8" "stop s5 6 Only QA signs off" \
    "fails failed" "start s6 ABC-3" "move s6 8" "stop s6 6 Only QA signs off" \
    "start s5 ABC-3" "menu s5" "move s5 99" "move s5 8 [1]" "move s5 8 {\"note\": 5}" "move s5 8 {\"fields\": [1]}" \
    "move s5 8 {\"note\": \"Ready\", \"extra\": 2}" "move s5 8 {\"fields\": {\"resolution\": \"Fixed\"}}" \
    "move s5 5 {\"note\": \"Done in pull request 57\"}" "move s5 5 {\"fields\": {\"resolution\": \"Fixed\", \"odd\": 1}}" \
    "move s5 8 too-long" "move s5 5 {\"fields\": {\"resolution\": \"Done\"}}" \
    "move s5 5 {\"fields\": {\"resolution\": [\"Fixed\"]}}" "move s5 5 {\"fields\": {\"resolution\": true}}" \
    "move s5 5 {\"fields\": {\"resolution\": \"Fixed\", \"fixVersion\": []}}" \
    "move s5 5 {\"fields\": {\"resolution\": \"Fixed\", \"fixVersion\": {\"name\": \"2.1\"}}}" \
    "move s5 5 {\"fields\": {\"resolution\": {\"name\": \"Fixed\", \"id\": \"10009\"}}}" \
    "move s5 8 $note" "ask s5 ticket" "moves" "move s5 5 $finish" "moves" \
    "move s5 5 {\"fields\": {\"resolution\": \"Fixed\", \"fixVersion\": null}}" "moves" \
    "press-move s5 move ABC-3 8" "press-move s5 move ABC-4 5" "press-move s5 move ABC-3 5 stale" "took" \
    "fails failed" "press-move s5 move ABC-3 5" "moves" "ask s5 ticket" "press-move s5 move ABC-3 5" "took" "moves" \
    "ask s5 ticket" "ask s5 ticket" \
    "afresh ABC-3" "read s5" "move s5 5 $finish" "fails refused" "press-move s5 move ABC-3 5" "moves" "ask s5 ticket" \
    "press-move s5 notNow ABC-3 5" "ask s5 ticket" \
    "afresh ABC-3" "read s5" "move s5 8" "press-move s5 notNow ABC-3 8" "moves" "took" "ask s5 ticket" "ask s5 ticket" \
    "move s5 8 $note" "elsewhere ABC-3 5" "press-move s5 move ABC-3 8" "took" "moves" "ask s5 ticket" "read s5" "moves" \
    "afresh ABC-3" "read s6" "move s6 8 $note" "ended s6" "moves" "press-move s6 move ABC-3 8" "took" \
    "afresh ABC-3" "read s5" "stop s5 99 Only QA" "stop s5 6" "stop s5 6 too-long" \
    "stop s5 6 Only QA signs off on payment changes" "moves" "ask s5 ticket" "elsewhere ABC-3 8" "read s5" "moves" \
    "afresh ABC-3" "read s5" "stop s5 6 Only QA signs off on payment changes" "move s5 8 $note" "switch s5 on" \
    "menu s5" "moves" "move s5 8 $note" "took" "ask s5 ticket" "menu s5" "moves" \
    "afresh ABC-3" "read s5" "fails failed" "move s5 8" "took" "ask s5 ticket" "moves" \
    "afresh ABC-3" "read s5" "fails refused" "move s5 8" "took" "ask s5 ticket" "moves" \
    "afresh ABC-3" "read s5" "fails signIn" "move s5 8" "took" "ask s5 ticket" "moves" "press-move s5 move ABC-3 8" \
    "took" "moves" \
    "ask s5 ticket-use ABC-1" "press s5 use" "menu s5" "moves" "menu s5" \
    "signout" "menu s5" "switch s5 on" "log" "logged" 2>&1 | same_times
  # New tickets: a start from Create a ticket, drafts turned away for their shape, their site, their parent, a group
  # there isn't or a type it doesn't take, then shown for Create Ticket; Not Yet; a press meant for the card before; a
  # tracker that couldn't check or make it, and Try Again; one made, which is then the session's ticket; one drafted
  # beside a ticket it has, which takes its place; and drafts gone with their session, or stopped by the sign-in.
  echo "## new tickets"
  mkdir -p "$T/drafts"
  bug='{"title": "Saved cards vanish after an update", "group": "ABC", "type": "bug", "priority": "Highest", "parent": "ABC-1", "description": "Since 3.2, every saved card is gone.\nThe website keeps them."}'
  task='{"title": "Saved cards: a test for the update", "group": "ABC", "type": "Task"}'
  HOME="$T/drafts" "$APP" --print-tickets "row s7" "row s8" "row s9" "create s7" "drafts" "ask s7 ticket" \
    "draft s7" "draft s7 [1]" "draft s7 {\"title\": \"\"}" "draft s7 {\"title\": \"A\", \"group\": \"ABC\"}" \
    "draft s7 {\"title\": \"A\", \"group\": \"A B\", \"type\": \"Task\"}" "draft s7 too-long" \
    "draft s7 {\"title\": \"A\", \"group\": \"ABC\", \"type\": \"Task\", \"labels\": [1]}" \
    "draft s7 {\"title\": \"A\", \"group\": \"ABC\", \"type\": \"Task\", \"priority\": 1}" \
    "draft s7 {\"title\": \"A\", \"group\": \"ABC\", \"type\": \"Task\", \"parent\": \"nope\"}" \
    "draft s7 {\"title\": \"A\", \"group\": \"ABC\", \"type\": \"Task\", \"site\": \"two.example\"}" \
    "draft s7 {\"title\": \"A\", \"group\": \"XYZ\", \"type\": \"Task\"}" "drafts" "ask s7 ticket" "ask s7 ticket" \
    "draft s7 {\"title\": \"A\", \"group\": \"AB_C\", \"type\": \"Task\"}" "ask s7 ticket" \
    "draft s7 {\"title\": \"A\", \"group\": \"A\tB\", \"type\": \"Task\"}" \
    "draft s7 {\"title\": \"A\", \"group\": \"ABC\", \"type\": \"Epic\"}" "ask s7 ticket" \
    "draft s7 $bug" "drafts" "ask s7 ticket" "press-draft s7 notYet" "drafts" "ask s7 ticket" "ask s7 ticket" \
    "draft s7 $bug" "draft s7 $bug" "drafts" "press-draft s7 create stale" "took" \
    "fails failed" "press-draft s7 create" "drafts" "ask s7 ticket" "ask s7 ticket" "took" \
    "press-draft s7 create" "took" "drafts" "ask s7 ticket" "ask s7 ticket" "read s7" "ask s7 ticket" "menu s7" \
    "start s8 ABC-1" "fails failed" "draft s8 $task" "drafts" "ask s8 ticket" "press-draft s8 create" "drafts" \
    "press-draft s8 check" "drafts" "press-draft s8 create" "took" "drafts" "ask s8 ticket" \
    "draft s9 $task" "drafts" "ended s9" "drafts" "ask s9 ticket" \
    "row s11" "create s11" "draft s11 {\"title\": \"A\", \"group\": \"ABC\", \"type\": \"Task\", \"priority\": \"\"}" \
    "drafts" "fails refused" "press-draft s11 create" "drafts" "ask s11 ticket" "draft s11 $task" "press-draft s11 check" \
    "took" "drafts" "press-draft s11 notYet" \
    "drafts" "draft s11 $task" "fails unread" "press-draft s11 create" "took" "drafts" "ask s11 ticket" "ask s11 ticket" \
    "signout" "draft s8 $task" "drafts" "ask s8 ticket" "ask s8 ticket" "row s10" "draft s10 $task" "drafts" \
    "ask s10 ticket" "row s12" "draft s12 {\"title\": \"A\", \"group\": \"ABC\", \"type\": \"Task\", \"site\": \"two.example\"}" \
    "signin" "drafts" "ask s10 ticket" "ask s12 ticket" "drafts" "draft-cases" "log" "logged" 2>&1 | same_times
  # A project's conversations read every ticket you can see, with nothing to answer, once one there is given a ticket
  # or it's turned on, and a session outside a project (a folder that isn't a repo's, or none) reads none: read and
  # told once, its words said to be their writers', only those changed since, one whole, and the list said to be cut;
  # then the project's choice turned off (its worktrees' sessions too, each told so, and which projects read kept,
  # where only you can read it) and on again; a read that fails, naming its site; and signed out, said before a
  # project that reads none.
  echo "## a project's conversations read your tickets"
  # A repo with a worktree, another repo, and a folder that's in none, made here; git ignores your own settings.
  mkdir -p "$T/reads" "$T/projects/notes"
  shop="$T/projects/acme-shop" wt="$T/projects/acme-shop-pay" web="$T/projects/acme-web" notes="$T/projects/notes"
  api="$T/projects/acme-api" docs="$T/projects/acme-docs"
  for repo in "$shop" "$web" "$api" "$docs"; do
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git init -q -b main "$repo"
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$repo" -c user.email=t@t -c user.name=t \
      commit -q --allow-empty -m init
  done
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$shop" worktree add -q -b pay-142 "$wt" main
  # Each session's record names a folder (in); the one its process works in, as macOS says, is what counts
  # (process-in). Reading starts once a session in the repo is given a ticket, lasts after it ends and across a
  # restart, and counts for every worktree; a repo never given one reads none until it's turned on. A listing marks
  # only from a process checked as the session's Claude Code, which these sample rows aren't, so each session marks
  # its repo as it asks; acme-api's page is there once a session there is told it reads none, though its record names
  # another folder; and signed out, a repo never given one is told to sign in first (acme-docs).
  HOME="$T/reads" "$APP" --print-tickets "row s1" "row s2" "row s3" "row s4" "in s1 $shop" "in s2 $wt" \
    "in s3 $notes" "in s4 $web" "rows" "settings $shop" "process-in $notes" "ask s3 tickets" "process-in $shop" \
    "ask s1 tickets" "in s3 $shop" "process-in $notes" "ask s3 tickets" "start s1 ABC-1" "process-in $shop" "rows" \
    "reading" "settings $shop" "ask s1 tickets" "ask s1 tickets" "ask s1 tickets" "process-in $wt" \
    "ask s2 tickets --full ABC-2" "ask s2 tickets --full ABC-2" "ask s2 tickets --full ABC-2 --site two.example" \
    "ask s2 tickets --full ABC-2 --site one.example" "ask s2 tickets --full ABC-2 --site one.example" \
    "process-in $shop" "ask s1 tickets --since now" "ask s1 tickets" "ask s2 tickets --full nope" \
    "ask s1 tickets --since now" "ask s1 tickets --since now" "ask s1 tickets --since 2999-01-01T00:00:00Z" \
    "ask s1 tickets --since yesterday" "ended s1" "rows" "relaunch" "row s5" "in s5 $notes" "process-in $api" \
    "ask s5 tickets" "settings $api" "reads-said $api" "reads-said $wt" "reads-said $notes" "reads-said relative" \
    "ask s5 ticket-use ABC-2" "rows" "press s5 use" "rows" "reading" "ask s5 tickets" "reading" "settings $api" \
    "reads-said $api" \
    "process-in $wt" "ask s2 tickets" \
    "ask s2 tickets" "process-in $web" "ask s4 tickets" "settings $web" "pick-reads $web on" "ask s4 tickets" \
    "ask s4 tickets" "off $shop" "reads-said $shop" "process-in $wt" "ask s2 tickets" "ask s2 tickets --full ABC-2" "reading" \
    "settings $shop" "on $shop" "reading" "settings $shop" "pick-reads $shop off" "settings $shop" \
    "pick-reads $shop on" "ask s2 tickets" "ask s2 tickets" "fails failed" "ask s2 tickets" "ask s2 tickets" \
    "signout" "rows" "ask s2 tickets" "settings $shop" "row s6" "process-in $docs" "ask s6 tickets" "log" "logged" 2>&1 | same_times | sed "s|$T|(T)|g"
  echo "## ask-panel.sh, before it asks"
  for given in "" "--wait" "--since 2030-01-06T06:30:00Z" "--since 2030-01-06T06:30:00.000+02:00 --wait" \
               "--since nope" "--since" "--full PAY-142" "--full pay-142" "--full" "--full PAY-1 --since x" "--now" \
               "--full PAY-1 --site acme.atlassian.net" "--site acme.atlassian.net" "--full PAY-1 --site Bad_Host" \
               "--full PAY-1 --site"; do
    printf 'tickets %s: ' "$given"
    WHOZMOVE_ASK_SOCKET="$T/none.sock" sh app/ask-panel.sh tickets $given 2>&1
  done
  printf 'tickets --full, two lines: '
  WHOZMOVE_ASK_SOCKET="$T/none.sock" sh app/ask-panel.sh tickets --full "$(printf 'PAY-1\n"x')" 2>&1
  for given in "PAY-142" "pay-142" "PAY-142 and more" "$(printf 'PAY-1\nPAY-2')" "https://acme.atlassian.net/browse/PAY-1" \
               "http://acme.atlassian.net/browse/PAY-1" "https://acme.atlassian.net/browse/PAY 1" ""; do
    printf '%s: ' "$(printf '%s' "$given" | tr '\n' '|')"
    WHOZMOVE_ASK_SOCKET="$T/none.sock" sh app/ask-panel.sh ticket-use "$given" 2>&1
  done
  for given in "" "--wait" "--now"; do
    printf 'ticket %s: ' "$given"
    WHOZMOVE_ASK_SOCKET="$T/none.sock" sh app/ask-panel.sh ticket $given 2>&1
  done
  # A step id as trackers give them, and nothing else; then stdin too long for each, and no why for ticket-stop.
  for word in ticket-move ticket-stop; do
    for given in "31" "a.b_c-9" "" "31 41" "31;x" '31"' "$(printf '31\n41')" "$(printf 'x%.0s' $(seq 64))" \
                 "$(printf 'x%.0s' $(seq 65))"; do
      printf '%s %s: ' "$word" "$(printf '%s' "$given" | tr '\n' '|')"
      echo "why" | WHOZMOVE_ASK_SOCKET="$T/none.sock" sh app/ask-panel.sh "$word" "$given" 2>&1
    done
  done
  printf 'ticket-move, nothing on stdin: '
  WHOZMOVE_ASK_SOCKET="$T/none.sock" sh app/ask-panel.sh ticket-move 31 </dev/null 2>&1
  printf 'ticket-move, 12 KB: '
  printf 'a%.0s' $(seq 12000) | WHOZMOVE_ASK_SOCKET="$T/none.sock" sh app/ask-panel.sh ticket-move 31 2>&1
  printf 'ticket-move, more than 12 KB: '
  printf 'a%.0s' $(seq 12100) | WHOZMOVE_ASK_SOCKET="$T/none.sock" sh app/ask-panel.sh ticket-move 31 2>&1
  printf 'ticket-stop, nothing on stdin: '
  WHOZMOVE_ASK_SOCKET="$T/none.sock" sh app/ask-panel.sh ticket-stop 31 </dev/null 2>&1
  printf 'ticket-stop, only spaces: '
  printf '  \n ' | WHOZMOVE_ASK_SOCKET="$T/none.sock" sh app/ask-panel.sh ticket-stop 31 2>&1
  printf 'ticket-draft, nothing on stdin: '
  WHOZMOVE_ASK_SOCKET="$T/none.sock" sh app/ask-panel.sh ticket-draft </dev/null 2>&1
  printf 'ticket-draft, 12 KB: '
  printf 'a%.0s' $(seq 12000) | WHOZMOVE_ASK_SOCKET="$T/none.sock" sh app/ask-panel.sh ticket-draft 2>&1
  printf 'ticket-draft, more than 12 KB: '
  printf 'a%.0s' $(seq 12100) | WHOZMOVE_ASK_SOCKET="$T/none.sock" sh app/ask-panel.sh ticket-draft 2>&1
  printf 'ticket-stop, 12 KB: '
  printf 'a%.0s' $(seq 12000) | WHOZMOVE_ASK_SOCKET="$T/none.sock" sh app/ask-panel.sh ticket-stop 31 2>&1
  printf 'ticket-stop, more than 12 KB: '
  printf 'a%.0s' $(seq 12100) | WHOZMOVE_ASK_SOCKET="$T/none.sock" sh app/ask-panel.sh ticket-stop 31 2>&1
  echo "## the page"
  page_cases "$HERE/page-cases.js"
)
compare "Tickets" "$HERE/tickets.expected.txt" "$out" "${1:-}"
