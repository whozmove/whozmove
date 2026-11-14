#!/bin/bash
# The One Task module's tests: the task's shape as it comes in and what's kept for each session (Whozmove
# --print-tasks, compared with tasks.expected.txt); then the asks, for stand-in sessions in a sample home, Asker, Other
# and Gone (Whozmove --print-task-asks), and ask-panel.sh over a real socket, run from inside Asker's process: a task
# sent, its answer asked for, and asked for with --wait until it's answered; and what ask-panel.sh says to words it
# can't send (compared with asks.expected.txt). Then what ends a wait and what it waits through, against a stand-in
# panel (compared with waits.expected.txt). Then its page's rules: what waits and in what order, each kind's buttons
# and answers, and the line that says a task waits (page-cases.js, run with macOS's jsc in UTC, compared with
# page.expected.txt).
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   modules/one-task/tests/test.sh            run and compare
#   modules/one-task/tests/test.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/../../.." || exit 1
. tests/sandboxed.sh "$@"
HERE=modules/one-task/tests
. tests/lib.sh
# Stand-in processes are kept in $T/pids so they're stopped however this ends. The socket goes in a folder of its own
# with a short path, as a socket's path can't be longer than 103 bytes; T is cleaned up even if that one can't be made.
T=$(throwaway one-task) || exit 1
leave_nothing "$T"
S=$(throwaway --short task) || exit 1
leave_nothing "$T" "$S"
. tests/compare.sh
APP=$(built_app "$T") || exit 1

failed=0
out=$(HOME="$T" "$APP" --print-tasks 2>&1)
compare "One Task's shape and record" "$HERE/tasks.expected.txt" "$out" "${1:-}" || failed=1
# Where a Unix socket can't be made or reached here (Claude Code's sandbox), the asks and the waits, which go over
# one, are left out, saying why, rather than waiting out each timeout.
SOCKETS=$(sockets_refused "$S")
if [ -n "$SOCKETS" ]; then
  echo "One Task's asks and waits: couldn't run here, as $SOCKETS"
  failed=1
else

# A stand-in session, as Claude Code's registry lists it: its process, named, in a folder of the sample home, idle.
mkdir -p "$T/.claude/sessions" "$T/shop"
register() {
  local now
  now=$(python3 -c 'import time; print(int(time.time() * 1000))')
  echo "{\"pid\": $1, \"sessionId\": \"$2\", \"name\": \"$3\", \"kind\": \"interactive\", \"entrypoint\": \"cli\",
         \"cwd\": \"$T/shop\", \"status\": \"idle\", \"startedAt\": $now, \"statusUpdatedAt\": $now}" \
    > "$T/.claude/sessions/$1.json"
}
# Asker's process is a shell that runs ask-panel.sh once $T/go appears, so the script runs from inside it, as a
# session's tool would: a task sent, its answer asked for, then asked for with --wait, asking every fifth of a second.
# shellcheck disable=SC2016
bash -c 'while :; do
  if [ -e "$1/go" ]; then
    rm "$1/go"
    { printf "%s" "{\"id\": \"offline\", \"kind\": \"try\", \"title\": \"Offline maps\", \"why\": \"On TestFlight.\"}" \
        | WHOZMOVE_ASK_SOCKET="$2" "$3" task; echo "exit=$?"
      WHOZMOVE_ASK_SOCKET="$2" "$3" task-answer offline; echo "exit=$?"
      WHOZMOVE_ASK_SOCKET="$2" WHOZMOVE_ASK_EVERY=0.2 "$3" task-answer offline --wait; echo "exit=$?"
      WHOZMOVE_ASK_SOCKET="$2" "$3" task-answer never-sent; echo "exit=$?"
    } > "$1/inside.txt" 2>&1
    touch "$1/went"
  fi
  sleep 0.1
done' asker "$T" "$S/ask.sock" "$PWD/app/ask-panel.sh" >/dev/null 2>&1 &
ASKER=$!; echo $ASKER >> "$T/pids"; disown $ASKER
sleep 600 >/dev/null 2>&1 &
OTHER=$!; echo $OTHER >> "$T/pids"; disown $OTHER
sleep 600 >/dev/null 2>&1 &
GONE=$!; echo $GONE >> "$T/pids"; disown $GONE
# The stand-in sessions ask the panel in their own names, which only Claude Code's program may: they run bash and
# sleep, which the print runs count as it (in a print run only).
export WHOZMOVE_STAND_IN_CLAUDE=/bin/bash:/bin/sleep
register $ASKER s-asker Asker
register $OTHER s-other Other
register $GONE s-gone Gone

out=$({
echo "== The asks, from each stand-in session, and Gone's tasks once its process has ended"
HOME="$T" "$APP" --print-task-asks "$S/ask.sock" 30 > "$T/print.txt" 2>&1 &
PRINT=$!
for _ in $(seq 1 200); do [ -S "$S/ask.sock" ] && break; sleep 0.1; done
touch "$T/go"
for _ in $(seq 1 150); do [ -e "$T/went" ] && break; sleep 0.1; done
touch "$S/ask.sock.done"
wait $PRINT
cat "$T/print.txt"
echo "== From inside Asker's process: a task sent, its answer asked for, then with --wait, then an id never sent"
cat "$T/inside.txt" 2>/dev/null || echo "(it didn't run)"
echo "== ask-panel.sh with words it can't send"
echo "" | app/ask-panel.sh task; echo "exit=$?"
app/ask-panel.sh task-answer; echo "exit=$?"
app/ask-panel.sh task-answer "../other"; echo "exit=$?"
app/ask-panel.sh task-answer offline --soon; echo "exit=$?"
python3 -c 'print("{\"id\": \"big\", \"why\": \"" + "x" * 13000 + "\"}")' | app/ask-panel.sh task; echo "exit=$?"
WHOZMOVE_ASK_SOCKET="$S/gone.sock" app/ask-panel.sh task-answer offline --wait; echo "exit=$?"
} 2>&1 | sed -E -e "s|$T|T|g" -e "s|${T#/private}|T|g" -e "s|$S|S|g" -e 's/"at":[0-9.]+/"at":(when)/g')
compare "One Task's asks" "$HERE/asks.expected.txt" "$out" "${1:-}" || failed=1

# task-answer --wait against a stand-in panel that answers each ask with the next of its lines, or is away a moment
# (away): what ends a wait, and what it waits through.
cat > "$T/panel.py" <<'PY'
import os, socket, sys, time
path, lines = sys.argv[1], sys.argv[2:]
def listen():
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.bind(path)
    s.listen(1)
    s.settimeout(10)
    return s
server = listen()
for line in lines:
    if line == "away":
        server.close()
        os.unlink(path)
        time.sleep(0.6)
        server = listen()
        continue
    client, _ = server.accept()
    client.recv(65536)
    client.sendall((line + "\n").encode())
    client.close()
server.close()
os.unlink(path)
PY
waits() {
  python3 "$T/panel.py" "$S/w.sock" "$@" &
  for _ in $(seq 1 50); do [ -S "$S/w.sock" ] && break; sleep 0.1; done
  WHOZMOVE_ASK_SOCKET="$S/w.sock" WHOZMOVE_ASK_EVERY=0.2 WHOZMOVE_ASK_UNREACHED=2 app/ask-panel.sh task-answer t1 --wait
  echo "exit=$?"
  wait
}
out=$({
echo "== Starting up, away a moment, waiting, put back, then answered"
waits "starting: Whozmove is starting up: ask again in a moment" away "waiting: t1 hasn't been answered yet" \
  "can't now: t1 is at the back of the user's line" 'answered: {"answer":"Works","id":"t1"}'
echo "== Refused while waiting (One Task turned off)"
waits "waiting: t1 hasn't been answered yet" "refused: One Task is off: turn it on in Settings"
echo "== Gone while waiting"
waits "waiting: t1 hasn't been answered yet" "gone: no task t1 from this session waits"
echo "== The panel gone for good while waiting: it stops once it's been out of reach a while (2 seconds here)"
waits "waiting: t1 hasn't been answered yet"
echo "== Without --wait, the panel starting up"
python3 "$T/panel.py" "$S/w.sock" "starting: Whozmove is starting up: ask again in a moment" &
for _ in $(seq 1 50); do [ -S "$S/w.sock" ] && break; sleep 0.1; done
WHOZMOVE_ASK_SOCKET="$S/w.sock" app/ask-panel.sh task-answer t1; echo "exit=$?"
wait
} 2>&1 | sed -e "s|$S|S|g")
compare "One Task's waits" "$HERE/waits.expected.txt" "$out" "${1:-}" || failed=1
fi

page=$(page_cases "$HERE/page-cases.js") || { echo "$page"; exit 1; }
compare "One Task's order and answers" "$HERE/page.expected.txt" "$page" "${1:-}" || failed=1
exit $failed
