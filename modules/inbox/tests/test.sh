#!/bin/bash
# The inbox module's tests: the record's rules over made-up messages (Whozmove --print-inbox, compared with
# inbox.expected.txt); then the asks, for stand-in sessions in a sample home, Lead, Lead2, Pip (in a worktree of the
# shop), Chief, You and Lone (in a folder with no team), with a stand-in agent saying what became of their messages, a
# fresh lead after it, and no agent at all (Whozmove --print-inbox-asks); ask-panel.sh over a real socket, from inside
# Pip's process and then the lead's: a message written, the inbox listed, read and answered; what ask-panel.sh says to
# words it can't send; and what panel.log kept of it all, which has no message's words (compared with
# asks.expected.txt, the socket's part with socket.expected.txt). Then its page's rules: every state's words, the filters, one session's messages and a pair, and
# what the view draws (page-cases.js, run with macOS's jsc in UTC, compared with page.expected.txt).
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   modules/inbox/tests/test.sh            run and compare
#   modules/inbox/tests/test.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/../../.." || exit 1
. tests/sandboxed.sh "$@"
HERE=modules/inbox/tests
# Stops here if there's no temporary folder: an empty T would make the clean-up below delete this checkout. The socket
# goes in a folder of its own with a short path, as a socket's path can't be longer than 103 bytes.
T=$(mktemp -d "${TMPDIR:-/tmp}/whozmove-inbox.XXXXXX") || exit 1
T=$(cd "$T" && pwd -P) || exit 1
S=$(mktemp -d /tmp/wz-inbox.XXXXXX 2>/dev/null || mktemp -d "${TMPDIR:-/tmp}/wz-inbox.XXXXXX") || exit 1
# Stand-in processes are kept in $T/pids so they're stopped however this ends.
trap 'kill $(cat "$T/pids" 2>/dev/null) 2>/dev/null; rm -rf "$T" "$S"' EXIT
. tests/lib.sh
. tests/compare.sh
APP=$(built_app "$T") || exit 1

# Each message's id is made up as it's kept, so each is shown as the order it first came in (m-1, m-2…), but for the
# example the words give (m-7f3a2c); and each time as when. Only sed and awk, which every Mac has, so the trip over a
# socket can be recorded on a Mac without the developer tools.
stable() {
  sed -E 's/"(at|readAt|answeredAt|deliveryAt)":[0-9.]+/"\1":(when)/g' | awk '
    BEGIN { seen["m-7f3a2c"] = "m-7f3a2c" }
    {
      out = ""; rest = $0
      while (match(rest, /m-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]/)) {
        id = substr(rest, RSTART, RLENGTH)
        before = RSTART > 1 ? substr(rest, RSTART - 1, 1) : ""
        after = substr(rest, RSTART + RLENGTH, 1)
        if (before ~ /[A-Za-z0-9_]/ || after ~ /[A-Za-z0-9_]/) {
          out = out substr(rest, 1, RSTART + RLENGTH - 1)
        } else {
          if (!(id in seen)) seen[id] = "m-" (++n)
          out = out substr(rest, 1, RSTART - 1) seen[id]
        }
        rest = substr(rest, RSTART + RLENGTH)
      }
      print out rest
    }'
}

failed=0
out=$(TZ=UTC HOME="$T" "$APP" --print-inbox 2>&1 | stable)
compare "The inbox's record" "$HERE/inbox.expected.txt" "$out" "${1:-}" || failed=1

# The shop, a repo with a worktree Pip works in, as git keeps them (only what's read without running git), and a
# folder of no project's.
mkdir -p "$T/.claude/sessions" "$T/shop/.git/worktrees/pip" "$T/pip" "$T/elsewhere"
echo "ref: refs/heads/main" > "$T/shop/.git/HEAD"
echo "ref: refs/heads/pip" > "$T/shop/.git/worktrees/pip/HEAD"
echo "gitdir: $T/shop/.git/worktrees/pip" > "$T/pip/.git"
# A stand-in session, as Claude Code's registry lists it: its process, named, in a folder of the sample home, idle.
register() {
  local now
  now=$(($(date +%s) * 1000))
  echo "{\"pid\": $1, \"sessionId\": \"$2\", \"name\": \"$3\", \"kind\": \"interactive\", \"entrypoint\": \"cli\",
         \"cwd\": \"$4\", \"status\": \"idle\", \"startedAt\": $now, \"statusUpdatedAt\": $now}" \
    > "$T/.claude/sessions/$1.json"
}
# Pip's process and Lead's are shells that run ask-panel.sh once $T/go-pip or $T/go-lead appears, so the script runs
# from inside them, as a session's tool would.
# shellcheck disable=SC2016
bash -c 'while :; do
  if [ -e "$1/go-pip" ]; then
    rm "$1/go-pip"
    { printf "%s" "Done: the coupon field is in, with 14 tests." \
        | WHOZMOVE_ASK_SOCKET="$2" "$3" message --to lead --priority report --about J7; echo "exit=$?"
    } > "$1/inside-pip.txt" 2>&1
    touch "$1/went-pip"
  fi
  sleep 0.1
done' pip "$T" "$S/ask.sock" "$PWD/app/ask-panel.sh" >/dev/null 2>&1 &
PIP=$!; echo $PIP >> "$T/pids"; disown $PIP
# shellcheck disable=SC2016
bash -c 'while :; do
  if [ -e "$1/go-lead" ]; then
    rm "$1/go-lead"
    { WHOZMOVE_ASK_SOCKET="$2" "$3" inbox; echo "exit=$?"
      next=$(WHOZMOVE_ASK_SOCKET="$2" "$3" inbox-next); echo "$next"; echo "exit=$?"
      id=$(printf "%s" "$next" | sed -n "s/.*\"id\":\"\(m-[0-9a-f]*\)\".*/\1/p")
      echo "Merged it" | WHOZMOVE_ASK_SOCKET="$2" "$3" inbox-answered "$id"; echo "exit=$?"
      WHOZMOVE_ASK_SOCKET="$2" "$3" inbox-next; echo "exit=$?"
    } > "$1/inside-lead.txt" 2>&1
    touch "$1/went-lead"
  fi
  sleep 0.1
done' lead "$T" "$S/ask.sock" "$PWD/app/ask-panel.sh" >/dev/null 2>&1 &
LEAD=$!; echo $LEAD >> "$T/pids"; disown $LEAD
for name in Lead2 Chief You Lone; do
  sleep 600 >/dev/null 2>&1 &
  eval "${name}_PID=\$!"; echo $! >> "$T/pids"; disown $!
done
# The stand-in sessions ask the panel in their own names, which only Claude Code's program may: they run bash and
# sleep, which the print runs count as it (in a print run only).
export WHOZMOVE_STAND_IN_CLAUDE=/bin/bash:/bin/sleep
register "$LEAD" s-lead Lead "$T/shop"
register "$Lead2_PID" s-lead-2 Lead2 "$T/shop"
register "$PIP" s-pip Pip "$T/pip"
register "$Chief_PID" s-chief Chief "$T/shop"
register "$You_PID" s-you You "$T/shop"
register "$Lone_PID" s-lone Lone "$T/elsewhere"

out=$({
echo "== Lead leads the shop's team; the agent says what became of the lines"
HOME="$T" "$APP" --print-inbox-asks first 2>&1
echo "== Lead2 leads it now, a fresh lead, not running as the agent says"
HOME="$T" "$APP" --print-inbox-asks fresh 2>&1
echo "== No agent says where sessions listen"
HOME="$T" "$APP" --print-inbox-asks none 2>&1
echo "== ask-panel.sh with words it can't send"
echo "Hi" | app/ask-panel.sh message --priority note; echo "exit=$?"
echo "Hi" | app/ask-panel.sh message --to s-other --priority note; echo "exit=$?"
echo "Hi" | app/ask-panel.sh message --to lead --priority soon; echo "exit=$?"
echo "Hi" | app/ask-panel.sh message --to lead --priority note --about; echo "exit=$?"
echo "Hi" | app/ask-panel.sh message --to lead --priority note --about "$(printf 'w%.0s' $(seq 1 41))"; echo "exit=$?"
echo "Hi" | app/ask-panel.sh message --to lead --priority note --soon yes; echo "exit=$?"
echo "" | app/ask-panel.sh message --to lead --priority note; echo "exit=$?"
python3 -c 'print("w" * 13000)' | app/ask-panel.sh message --to lead --priority note; echo "exit=$?"
app/ask-panel.sh inbox everything; echo "exit=$?"
app/ask-panel.sh inbox-next m-7f3a2c; echo "exit=$?"
app/ask-panel.sh inbox-answered; echo "exit=$?"
app/ask-panel.sh inbox-answered "../m-7f3a2c" < /dev/null; echo "exit=$?"
python3 -c 'print("w" * 401)' | app/ask-panel.sh inbox-answered m-7f3a2c; echo "exit=$?"
echo "== What panel.log kept"
grep -o 'inbox: .*' "$T/Library/Application Support/Whozmove/panel.log"
} 2>&1 | sed -E -e "s|$T|T|g" -e "s|${T#/private}|T|g" -e "s|$S|S|g" | stable)
compare "The inbox's asks" "$HERE/asks.expected.txt" "$out" "${1:-}" || failed=1
grep -o 'inbox: .*' "$T/Library/Application Support/Whozmove/panel.log" > "$T/log-before" 2>/dev/null

# Where a Unix socket can't be made or reached here (Claude Code's sandbox), ask-panel.sh's own trip over one is left
# out, saying why, rather than waiting out each timeout.
SOCKETS=$(sockets_refused "$S")
if [ -n "$SOCKETS" ]; then
  echo "The inbox's asks over a socket: couldn't run here, as $SOCKETS"
  failed=1
else
out=$({
echo "== Over the socket: Pip writes, then the lead lists, reads and answers"
rm -rf "$T/Library/Application Support/Whozmove/inbox"
HOME="$T" "$APP" --print-inbox-asks none "$S/ask.sock" 30 > "$T/print.txt" 2>&1 &
PRINT=$!
for _ in $(seq 1 200); do [ -S "$S/ask.sock" ] && break; sleep 0.1; done
touch "$T/go-pip"
for _ in $(seq 1 150); do [ -e "$T/went-pip" ] && break; sleep 0.1; done
touch "$T/go-lead"
for _ in $(seq 1 150); do [ -e "$T/went-lead" ] && break; sleep 0.1; done
touch "$S/ask.sock.done"
wait $PRINT
echo "exit=$?"
echo "-- What the panel printed"
cat "$T/print.txt"
echo "-- From inside Pip's process"
cat "$T/inside-pip.txt" 2>/dev/null || echo "(it didn't run)"
echo "-- From inside Lead's process"
cat "$T/inside-lead.txt" 2>/dev/null || echo "(it didn't run)"
echo "-- What panel.log kept of it"
grep -o 'inbox: .*' "$T/Library/Application Support/Whozmove/panel.log" | tail -n +$(($(wc -l < "$T/log-before") + 1))
} 2>&1 | sed -E -e "s|$T|T|g" -e "s|${T#/private}|T|g" -e "s|$S|S|g" | stable)
compare "The inbox's asks over a socket" "$HERE/socket.expected.txt" "$out" "${1:-}" || failed=1
fi

page=$(page_cases "$HERE/page-cases.js") || { echo "$page"; exit 1; }
compare "Messages' words and drawing" "$HERE/page.expected.txt" "$page" "${1:-}" || failed=1
exit $failed
