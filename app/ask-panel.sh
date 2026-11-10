#!/bin/sh
# Asks Whozmove's panel to do something you've let this session do, in its row's mode menu, or to show the user a
# task to do, which needs nothing turned on, and prints the panel's answer. Run from inside the session: the panel
# tells which session asks from the process that connects, never from anything said here. Every build carries a copy
# (Contents/Resources).
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
#   ask-panel.sh put-in-place [folder]   Let It Deploy: runs this project's Deploy command, as your press of Deploy
#                                        would, from this session's own checkout (the only folder it may name), once
#                                        no other agent is at work there and you've stepped off the panel, without
#                                        waiting for this session's turn to end
#   ask-panel.sh status [folder]         how that checkout's Deploy stands: asked and waiting, running, or how the last
#                                        one went
#   ask-panel.sh waiting                 May Send Back Plans, May Answer Questions or May Approve Plans: what a team
#                                        member waits on that this session may answer for you, as one line of JSON,
#                                        each with its id, and each plan with what may be done with it and its digest
#   ask-panel.sh send-back <id> < note   May Send Back Plans: sends that plan back with the note given on stdin, as your
#                                        "keep planning" would, marked as this session's; never approves it
#   ask-panel.sh answer <id> < answers   May Answer Questions: answers that question, every question it asks, with the
#                                        JSON given on stdin, {question: {option: label}} (or {options: [labels]} where
#                                        several may be picked, or {written: text}), marked as this session's choice
#   ask-panel.sh approve <id> <digest>   May Approve Plans: approves that plan, as listed with that digest,
#                                        as your own approval in its tab would
#   ask-panel.sh wait [--now] [--comments]
#                                        waits while this session's next step is someone else's: on its pull
#                                        request (a review, an approval, a merge or a close; a comment too with
#                                        --comments). Run in the background as the turn's last step: it asks every 10
#                                        seconds, through Whozmove being away for as long as it takes, and prints
#                                        "woke: " and what came as one line of JSON once it has and the gear has a
#                                        seat for it; or "nothing to wait for: …" at once. --now answers at once with
#                                        what came, or "nothing yet: …"
#   ask-panel.sh task [--pick-for <member>] < task.json
#                                        One Task: hands the user a task to do, given as JSON on stdin in its shape
#                                        (docs/reference/task.md); as many of this session's as wait for an answer,
#                                        up to a ceiling against runaway scripts, and one sent again with the same id
#                                        is its next step. With --pick-for, a team's lead's pick for one of its
#                                        members (its session id, or its name in the team), shown once the team
#                                        file's queue names it
#   ask-panel.sh task-withdraw <id> <why>   takes back a task this session sent (a lead, its pick), as `why` is
#                                        answered (elsewhere), parked or dropped: it leaves the user's line as soon
#                                        as they aren't on it, saying so; "taken back", or "gone" if none waits
#   ask-panel.sh task-answer <id> [--wait]   the user's answer to that task: "answered: " and the answer as one line
#                                        of JSON, or "waiting", "can't now" (put to the back of their line) or "gone";
#                                        with --wait, asks every 10 seconds until it's answered, gone or refused,
#                                        through a restart of the panel, for 10 minutes at most without reaching it
#   ask-panel.sh message --to lead --priority urgent|question|report|note [--about <words>] < text
#                                        writes to the inbox of this project's team's lead: kept first, then it
#                                        prints "kept <id>", where to send the line that tells the lead ("ring:
#                                        <address>"), and that line ("line: …"), for this session to send with
#                                        your agent's own messages; or why there's nothing to ring
#   ask-panel.sh inbox                   a team's lead: the messages waiting in its inbox, most pressing first, one
#                                        line of JSON each without their words, or "empty"
#   ask-panel.sh inbox-next              a team's lead: the most pressing message it hasn't read, whole, as one line
#                                        of JSON, marked read by it; or "empty"
#   ask-panel.sh inbox-answered <id> [< note]   a team's lead: marks that message answered, with a note if one is
#                                        given on stdin
#   ask-panel.sh ticket [--wait]         this session's ticket, as one line of JSON (where it stands, its parent, its
#                                        groups and its next steps, each with the fields it needs), as last read, with
#                                        when; "waiting: …" while it's read or the user's answer is waited for, which
#                                        --wait waits through, as task-answer's does; "not used: …" once they said Not
#                                        Now, or "can't now: …" when it can't be read (or a new ticket couldn't be
#                                        checked or made, said once), both at once, waiting or not
#   ask-panel.sh ticket-use <key or link>   asks to work on that ticket: "Work on it here?" shows on this session's
#                                        row, and only the user's Use It there gives it to this session
#   ask-panel.sh ticket-move <step id> [< move.json]
#                                        moves this session's ticket by one of its next steps, by the id ticket lists
#                                        it with, with {"note": …, "fields": {field id: value}} on stdin, either left
#                                        out: at once with May Move Its Ticket, else "Move PAY-142 to In Review?" shows
#                                        on this session's row for the user's Move It; ticket says how it went
#   ask-panel.sh ticket-stop <step id> < why   marks that next step as a person's (an approval, a sign-off), with why
#                                        on stdin, for this session's row; then say so and stop
#   ask-panel.sh ticket-draft < ticket.json   a new ticket, {"title": …, "group": …, "type": …, "description": …} and
#                                        maybe its "priority", "parent" and "site", on stdin: once its tracker has said
#                                        where it can go, "Create this ticket?" shows on this session's row, and only
#                                        the user's Create Ticket there makes it; ticket --wait then says "created:
#                                        PAY-151…" or "not yet: …", or "can't now: …" once when it couldn't be
#                                        checked or made, which a --wait again waits through
#   ask-panel.sh process-draft < note   how this session's project works, beside its own pages: what those pages
#                                        don't say, a line each, on stdin, 4000 characters at most: "Keep this as how
#                                        acme-web works?" shows on this session's row, against the note as kept, and
#                                        only the user's Keep It there keeps it; after their Not Now, the same lines
#                                        aren't shown again
#
# It exits 1 when the panel refuses, can't be reached or is starting up, when a task's gone, and when a wait stops
# for want of the panel.

wait= forever=
case "${1:-}" in
  *[!a-z-]* | "") echo "Ask with one word, such as put-in-place or status" >&2; exit 2 ;;
esac
asked=$(printf '{"ask": "%s"}' "$1")
if [ "$1" = approve ]; then
  # The plan, by the hook's own id, and the digest of the text read, so a plan written again since isn't approved.
  case "${2:-}" in
    "" | *[!0-9a-f]*) echo "Name the plan by its id, as ask-panel.sh waiting lists it" >&2; exit 2 ;;
  esac
  case "${3:-}" in
    "" | *[!0-9a-f]*) echo "Name the plan's digest too, as ask-panel.sh waiting lists it" >&2; exit 2 ;;
  esac
  asked=$(printf '{"ask": "approve", "id": "%s", "digest": "%s"}' "$2" "$3")
elif [ "$1" = wait ]; then
  # Whether to answer at once, and whether a comment on its pull request wakes it too; nothing else may follow.
  at_once=false comments=false
  [ $# -le 3 ] || { echo "Only --now and --comments may follow wait" >&2; exit 2; }
  for flag in "${2:-}" "${3:-}"; do
    case $flag in
      "") ;;
      --now) at_once=true ;;
      --comments) comments=true ;;
      *) echo "Only --now and --comments may follow wait" >&2; exit 2 ;;
    esac
  done
  asked=$(printf '{"ask": "wait", "now": %s, "comments": %s}' "$at_once" "$comments")
  # Only Whozmove can wake it, so a wait that has begun waits through the panel being out of reach for as long as it
  # takes: one that stopped would wake the session only to say so.
  if [ "$at_once" = false ]; then wait=--wait; forever=yes; fi
elif [ "$1" = answer ]; then
  # The question, by the hook's own id, and the answers, from stdin, base64-encoded as a note is.
  case "${2:-}" in
    "" | *[!0-9a-f]*) echo "Name the question by its id, as ask-panel.sh waiting lists it" >&2; exit 2 ;;
  esac
  answers=$(cat)
  if [ -z "$(printf '%s' "$answers" | tr -d ' \t\n')" ]; then
    echo "Give the answers on stdin, as JSON: {\"the question\": {\"option\": \"its label\"}}" >&2
    exit 2
  fi
  asked=$(printf '{"ask": "answer", "id": "%s", "answers64": "%s"}' "$2" \
    "$(printf '%s' "$answers" | /usr/bin/base64 | tr -d '\n')")
elif [ "$1" = task ]; then
  # A lead's pick names its member: a session id or a name in the team, plain words only, so nothing in it can break
  # the line.
  pickfor=
  case "${2:-}" in
    "") ;;
    --pick-for)
      case "${3:-}" in
        "" | *[!A-Za-z0-9\ ._-]*) echo "Name the member by its session id or its name in the team" >&2; exit 2 ;;
      esac
      pickfor=$3 ;;
    *) echo "Only --pick-for <member> may follow task" >&2; exit 2 ;;
  esac
  # The task, from stdin, base64-encoded as a note is.
  task=$(cat)
  if [ -z "$(printf '%s' "$task" | tr -d ' \t\n')" ]; then
    echo "Give the task on stdin, as JSON: docs/reference/task.md has its shape" >&2
    exit 2
  fi
  task64=$(printf '%s' "$task" | /usr/bin/base64 | tr -d '\n')
  # One ask is 16 KB at most, as the panel reads it: about 12 KB of task once it's base64-encoded.
  if [ "${#task64}" -gt 16000 ]; then
    echo "A task may be 12 KB at most: send it with less in it" >&2
    exit 2
  fi
  if [ -n "$pickfor" ]; then
    asked=$(printf '{"ask": "task", "task64": "%s", "pickFor": "%s"}' "$task64" "$pickfor")
  else
    asked=$(printf '{"ask": "task", "task64": "%s"}' "$task64")
  fi
elif [ "$1" = task-answer ]; then
  case "${2:-}" in
    "" | *[!A-Za-z0-9._-]*) echo "Name the task by the id it was sent with" >&2; exit 2 ;;
  esac
  case "${3:-}" in
    "" | --wait) ;;
    *) echo "Only --wait may follow the task's id" >&2; exit 2 ;;
  esac
  asked=$(printf '{"ask": "task-answer", "id": "%s"}' "$2")
  wait=${3:-}
elif [ "$1" = task-withdraw ]; then
  case "${2:-}" in
    "" | *[!A-Za-z0-9._-]*) echo "Name the task by the id it was sent with" >&2; exit 2 ;;
  esac
  case "${3:-}" in
    answered | parked | dropped) ;;
    *) echo "Say why it's taken back: answered, parked or dropped" >&2; exit 2 ;;
  esac
  asked=$(printf '{"ask": "task-withdraw", "id": "%s", "why": "%s"}' "$2" "$3")
elif [ "$1" = message ]; then
  # A message to the team's lead: whom it's for, how pressing it is and what it's about, then its words, from stdin,
  # base64-encoded as a note is.
  to= priority= about=
  shift
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || { echo "Give $1 its value too" >&2; exit 2; }
    case $1 in
      --to) to=$2 ;;
      --priority) priority=$2 ;;
      --about) about=$2 ;;
      *) echo "Only --to lead, --priority and --about may follow message" >&2; exit 2 ;;
    esac
    shift 2
  done
  if [ "$to" != lead ]; then
    echo "A message goes to your team's lead: --to lead" >&2
    exit 2
  fi
  case $priority in
    urgent | question | report | note) ;;
    *) echo "Say how pressing it is: --priority urgent, question, report or note" >&2; exit 2 ;;
  esac
  if [ "$(printf '%s' "$about" | wc -m)" -gt 40 ]; then
    echo "Say what it's about in 40 characters at most, as a job's id" >&2
    exit 2
  fi
  text=$(cat)
  if [ -z "$(printf '%s' "$text" | tr -d ' \t\n')" ]; then
    echo "Give the message on stdin" >&2
    exit 2
  fi
  text64=$(printf '%s' "$text" | /usr/bin/base64 | tr -d '\n')
  # One ask is 16 KB at most, as the panel reads it: about 12 KB of words once they're base64-encoded.
  if [ "${#text64}" -gt 16000 ]; then
    echo "A message may be 12 KB at most: put the rest in a file and give its path" >&2
    exit 2
  fi
  if [ -n "$about" ]; then
    asked=$(printf '{"ask": "message", "to": "lead", "priority": "%s", "about64": "%s", "text64": "%s"}' "$priority" \
      "$(printf '%s' "$about" | /usr/bin/base64 | tr -d '\n')" "$text64")
  else
    asked=$(printf '{"ask": "message", "to": "lead", "priority": "%s", "text64": "%s"}' "$priority" "$text64")
  fi
elif [ "$1" = inbox ] || [ "$1" = inbox-next ]; then
  if [ $# -gt 1 ]; then
    echo "Nothing may follow $1: it's this session's own inbox" >&2
    exit 2
  fi
elif [ "$1" = inbox-answered ]; then
  case "${2:-}" in
    m-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
    *) echo "Name the message by the id inbox-next gave, as m-7f3a2c" >&2; exit 2 ;;
  esac
  # A note only from what's piped in: a terminal's keyboard is never waited on.
  note=
  [ -t 0 ] || note=$(cat)
  if [ -n "$(printf '%s' "$note" | tr -d ' \t\n')" ]; then
    if [ "$(printf '%s' "$note" | wc -m)" -gt 400 ]; then
      echo "A note may be 400 characters at most: say what was done more briefly" >&2
      exit 2
    fi
    asked=$(printf '{"ask": "inbox-answered", "id": "%s", "note64": "%s"}' "$2" \
      "$(printf '%s' "$note" | /usr/bin/base64 | tr -d '\n')")
  else
    asked=$(printf '{"ask": "inbox-answered", "id": "%s"}' "$2")
  fi
elif [ "$1" = ticket ]; then
  case "${2:-}" in
    "" | --wait) ;;
    *) echo "Only --wait may follow ticket" >&2; exit 2 ;;
  esac
  wait=${2:-}
elif [ "$1" = ticket-use ]; then
  # A key as trackers write them (PAY-142), or a link, base64-encoded so nothing in it can break the line. grep looks
  # line by line, so one with a line break in it is turned away first.
  case ${2:-} in *'
'*) echo "Name the ticket by its key (PAY-142) or its https:// link, on one line" >&2; exit 2 ;; esac
  if printf '%s' "${2:-}" | /usr/bin/grep -Eqx '[A-Z][A-Z0-9_]*-[0-9]+'; then
    asked=$(printf '{"ask": "ticket-use", "key": "%s"}' "$2")
  elif [ "${#2}" -le 2000 ] && printf '%s' "$2" | /usr/bin/grep -Eqx 'https://[^[:space:]]+'; then
    asked=$(printf '{"ask": "ticket-use", "link64": "%s"}' "$(printf '%s' "$2" | /usr/bin/base64 | tr -d '\n')")
  else
    echo "Name the ticket by its key (PAY-142) or its https:// link" >&2
    exit 2
  fi
elif [ "$1" = ticket-move ]; then
  # One of its ticket's next steps, by the id its tracker gave, and what goes with it, from stdin: a note and the fields
  # it sets, as JSON, base64-encoded as a task is. Nothing on stdin (or a terminal) moves it with neither.
  case "${2:-}" in
    "" | *[!A-Za-z0-9._-]*) echo "Name the step by its id, as ask-panel.sh ticket lists it" >&2; exit 2 ;;
  esac
  if [ "${#2}" -gt 64 ]; then
    echo "Name the step by its id, as ask-panel.sh ticket lists it" >&2
    exit 2
  fi
  move=
  [ -t 0 ] || move=$(cat)
  move64=$(printf '%s' "$move" | /usr/bin/base64 | tr -d '\n')
  # One ask is 16 KB at most, as the panel reads it: about 12 KB of note and fields once they're base64-encoded.
  if [ "${#move64}" -gt 16000 ]; then
    echo "A move's note and fields may be 12 KB at most: send them with less in them" >&2
    exit 2
  fi
  asked=$(printf '{"ask": "ticket-move", "id": "%s", "note64": "%s"}' "$2" "$move64")
elif [ "$1" = ticket-stop ]; then
  # The step it stopped at, by the id its tracker gave, and why it's a person's, from stdin, base64-encoded as a note is.
  case "${2:-}" in
    "" | *[!A-Za-z0-9._-]*) echo "Name the step by its id, as ask-panel.sh ticket lists it" >&2; exit 2 ;;
  esac
  if [ "${#2}" -gt 64 ]; then
    echo "Name the step by its id, as ask-panel.sh ticket lists it" >&2
    exit 2
  fi
  why=
  [ -t 0 ] || why=$(cat)
  if [ -z "$(printf '%s' "$why" | tr -d ' \t\n')" ]; then
    echo "Give the why on stdin: whose step it is, and why it's theirs" >&2
    exit 2
  fi
  why64=$(printf '%s' "$why" | /usr/bin/base64 | tr -d '\n')
  # Only what one ask can carry, as for a move: how long a why may be is the panel's to say.
  if [ "${#why64}" -gt 16000 ]; then
    echo "A why may be 12 KB at most: say whose step it is more briefly" >&2
    exit 2
  fi
  asked=$(printf '{"ask": "ticket-stop", "id": "%s", "why64": "%s"}' "$2" "$why64")
elif [ "$1" = ticket-draft ]; then
  # The new ticket, from stdin, base64-encoded as a move's note and fields are.
  draft=
  [ -t 0 ] || draft=$(cat)
  if [ -z "$(printf '%s' "$draft" | tr -d ' \t\n')" ]; then
    echo "Give the new ticket on stdin, as JSON: its title, group, type and description" >&2
    exit 2
  fi
  draft64=$(printf '%s' "$draft" | /usr/bin/base64 | tr -d '\n')
  # Only what one ask can carry, as for a move: how long each part may be is the panel's to say.
  if [ "${#draft64}" -gt 16000 ]; then
    echo "A new ticket may be 12 KB at most: send it with less in it" >&2
    exit 2
  fi
  asked=$(printf '{"ask": "ticket-draft", "draft64": "%s"}' "$draft64")
elif [ "$1" = process-draft ]; then
  # The note, from stdin, base64-encoded as a note is.
  note=
  [ -t 0 ] || note=$(cat)
  if [ -z "$(printf '%s' "$note" | tr -d ' \t\n')" ]; then
    echo "Give the note on stdin: what the project's own pages don't say, a line each" >&2
    exit 2
  fi
  if [ "$(printf '%s' "$note" | wc -m)" -gt 4000 ]; then
    echo "A note may be 4000 characters at most: keep only what the project's own pages don't say" >&2
    exit 2
  fi
  note64=$(printf '%s' "$note" | /usr/bin/base64 | tr -d '\n')
  # One ask is 16 KB at most, as the panel reads it: a note of letters that each take several bytes can pass 4000
  # characters' worth of it.
  if [ "${#note64}" -gt 16000 ]; then
    echo "A note may be 12 KB at most: keep only what the project's own pages don't say" >&2
    exit 2
  fi
  asked=$(printf '{"ask": "process-draft", "note64": "%s"}' "$note64")
elif [ "$1" = send-back ]; then
  # The request, by the hook's own id, and the note, from stdin, base64-encoded so nothing in it can break the line.
  case "${2:-}" in
    "" | *[!0-9a-f]*) echo "Name the plan by its id, as ask-panel.sh waiting lists it" >&2; exit 2 ;;
  esac
  note=$(cat)
  if [ -z "$(printf '%s' "$note" | tr -d ' \t\n')" ]; then
    echo "Give the note on stdin: what should change in the plan" >&2
    exit 2
  fi
  if [ "$(printf '%s' "$note" | wc -m)" -gt 4000 ]; then
    echo "A note may be 4000 characters at most: say what should change more briefly" >&2
    exit 2
  fi
  asked=$(printf '{"ask": "send-back", "id": "%s", "note64": "%s"}' "$2" \
    "$(printf '%s' "$note" | /usr/bin/base64 | tr -d '\n')")
# A folder named, as its real path: the panel checks it's this session's own checkout.
elif [ $# -ge 2 ]; then
  folder=$(cd -- "$2" 2>/dev/null && pwd -P) || { echo "There's no folder at $2" >&2; exit 2; }
  case $folder in
    *'"'* | *'\'* | *'
'*) echo "Whozmove can't be asked about a folder whose path has quotes, backslashes or line breaks in it" >&2; exit 2 ;;
  esac
  asked=$(printf '{"ask": "%s", "folder": "%s"}' "$1" "$folder")
fi
# Whozmove's own folder (AppDir in app/shared/Files.m), unless a test gives another.
socket=${WHOZMOVE_ASK_SOCKET:-"$HOME/Library/Application Support/Whozmove/ask.sock"}
# How often --wait asks again, in seconds, unless a test gives another.
every=${WHOZMOVE_ASK_EVERY:-10}
# And how long --wait goes on without reaching the panel before it stops, in seconds.
unreached_for=${WHOZMOVE_ASK_UNREACHED:-600}
asked_before=
unreached_since=
while :; do
  answer=
  [ -S "$socket" ] && answer=$(printf '%s\n' "$asked" | /usr/bin/nc -U -w 10 "$socket" 2>/dev/null)
  # The panel starting up, or closing, can't tell who asks: a wait takes that as the panel out of reach a moment.
  case $wait:$answer in --wait:starting:*) answer= asked_before=yes ;; esac
  if [ -z "$answer" ]; then
    # Once a wait has begun, the panel gone a moment (restarted, or a new build put in place) is waited through, for
    # a while.
    if [ -n "$wait" ] && [ -n "$asked_before" ]; then
      now=$(date +%s)
      unreached_since=${unreached_since:-$now}
      if [ -z "$forever" ] && [ $((now - unreached_since)) -ge "$unreached_for" ]; then
        if [ "$unreached_for" -ge 60 ]; then gone_for="$((unreached_for / 60)) minutes"; else gone_for="$unreached_for seconds"; fi
        echo "Couldn't reach Whozmove's panel for $gone_for, so stopped waiting: ask again once it's back"
        exit 1
      fi
      sleep "$every"
      continue
    fi
    if [ ! -S "$socket" ]; then
      echo "Whozmove isn't running, so there's no panel to ask"
      exit 1
    fi
    # Nothing back: a socket left behind by a panel that crashed or was stopped, or one a sandboxed session isn't
    # allowed to reach. nc says nothing that tells the two apart, and a sandboxed session may not be able to look at the
    # panel's process either, so both are said, with no agent's setting named (an agent's own skill names it, for the
    # user), and that it's for the user to change, never the session itself.
    echo "Couldn't reach Whozmove's panel at its socket: Whozmove may have stopped, or this session isn't allowed to"
    echo "reach it. Tell the user; don't change any setting yourself: $socket"
    exit 1
  fi
  asked_before=yes
  unreached_since=
  case $wait:$answer in
    --wait:waiting:*) sleep "$every" ;;
    # A task put to the back of the user's line is waited through; a ticket that can't be read is said at once.
    "--wait:can't now:"*) if [ "$1" = task-answer ]; then sleep "$every"; else break; fi ;;
    *) break ;;
  esac
done
# As it is: sh's echo would turn a \n inside the panel's JSON into a line break.
printf '%s\n' "$answer"
case $answer in refused:* | gone:* | starting:*) exit 1 ;; esac
exit 0
