#!/bin/bash
# The waits module's tests. Waits begun and refused, wakes going as the gear has room (oldest first, your own answer at
# once, every one with Usage Gear off or no gear picked), waits ending (a new process, closed, its row gone, its command
# stopped asking), what's kept and found again after a restart, the rows' `wait`, the plain functions, and panel.log
# carrying no word of what came (Whozmove --print-wakes, with a made-up source, in throwaway homes; wakes.expected.txt);
# and its background waits against ask-panel.sh's usage line for `wait` (words.expected.txt).
# Then `ask-panel.sh wait` against a stand-in panel: what it waits through (the panel away longer than a task's wait
# would stand), what ends it, and the words it turns away (asks.expected.txt). Then the page's part (page-cases.js,
# with macOS's jsc in UTC; page.expected.txt).
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   modules/waits/tests/test.sh            run and compare
#   modules/waits/tests/test.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/../../.." || exit 1
. tests/sandboxed.sh "$@"
HERE=modules/waits/tests
# Stops here if there's no temporary folder: an empty T would make the clean-up below delete this checkout. The socket
# goes in a folder of its own with a short path, as a socket's path can't be longer than 103 bytes.
T=$(mktemp -d "${TMPDIR:-/tmp}/whozmove-waits.XXXXXX") || exit 1
T=$(cd "$T" && pwd -P) || exit 1
S=$(mktemp -d /tmp/wz-wait.XXXXXX 2>/dev/null || mktemp -d "${TMPDIR:-/tmp}/wz-wait.XXXXXX") || exit 1
trap 'rm -rf "$T" "$S"' EXIT
. tests/lib.sh
. tests/compare.sh
APP=$(built_app "$T") || exit 1
failed=0

home() {
  mkdir -p "$T/$1"
  echo "$T/$1"
}
out=$(
  echo "## begun, refused, and woken"
  HOME=$(home begun) "$APP" --print-wakes "row s1" "ask s1" "has s1 #12 cant" "ask s1" "has s1 #12" \
    "has s1 PAY-142 other" "ask s1 comments" "rows" "kept" "later 10" "ask s1" "ask s1 now" "came s1 approved" \
    "pass" "rows" "ask s1" "kept" "rows" "ask s1 now" "closed s9" "ask s9" "logged" 2>&1
  echo "## the gear: the oldest wake first, one let go counted as taken, your answer at once"
  HOME=$(home gear) "$APP" --print-wakes "gear 1" "row s2" "row s3" "row s4" "has s2 #12" "has s3 #13" \
    "has s4 PAY-7 other" "ask s2" "ask s3" "ask s4" "later 5" "came s3 approved" "later 5" "came s2 merged" \
    "gear 0" "came s4 answered yours other" "pass" "rows" "ask s4" "ask s2" "ask s3" "gear 1" "pass" "rows" \
    "ask s2" "ask s3" "rows" "later 31" "pass" "rows" "ask s2" "ask s3" "ask s2" "gear 0 s3" "pass" "ask s2" \
    "gear 1 s3" "pass" "ask s2" "logged" 2>&1
  echo "## no gear picked, and Usage Gear off: every wake goes"
  HOME=$(home free) "$APP" --print-wakes "gear unpicked" "row s2" "row s3" "has s2 #12" "has s3 #13" "ask s2" \
    "ask s3" "later 1" "came s2 approved" "came s3 approved" "ask s2" "gear off" "ask s3" 2>&1
  echo "## ended: a new process, closed, its row gone, its command stopped asking"
  HOME=$(home ended) "$APP" --print-wakes "row s5" "row s6" "row s7" "row s8" "has s5 #12" "has s6 #13" \
    "has s7 #14" "has s8 #15" "ask s5" "ask s6" "ask s7" "ask s8" "kept" "newproc s5" "closed s6" "gone s7" \
    "later 50" "pass" "rows" "later 11" "pass" "rows" "kept" "row s5" "ask s5" "newproc s5" "ask s5" "logged" 2>&1
  echo "## a restart: what's kept is read back, kept through a pass before the rows are read, watched again from when"
  echo "## it began on what it began on (though the source can't name it yet), and what came meanwhile wakes it"
  HOME=$(home restart) "$APP" --print-wakes "row s9" "has s9 #12" "ask s9" "later 20" "came s9 approved" \
    "relaunch" "unread" "rows" "kept" "nothing s9" "pass" "rows" "ask s9" "kept" 2>&1
  echo "## the Mac asleep an hour: the wait goes on; awake a minute without an ask: it ends"
  HOME=$(home asleep) "$APP" --print-wakes "row s11" "has s11 #12" "ask s11" "pass" "sleep 3600" "pass" "rows" \
    "ask s11" "later 61" "pass" "rows" "logged" 2>&1
  echo "## nothing it waits on can be read: the row says why, and after 30 minutes the wait ends, saying so"
  HOME=$(home unread) "$APP" --print-wakes "row s10" "has s10 #12" "ask s10" "has s10 #12 cant" "pass" "rows" \
    "later 1700" "ask s10" "pass" "rows" "later 101" "ask s10" "rows" "kept" 2>&1
  echo "## closed while it waits: kept and watched, its row saying so; woken, your move with its notice; its words as"
  echo "## it's opened again, kept through a restart; carried on in its new process, which hears what came"
  HOME=$(home closed) "$APP" --print-wakes "row s12" "has s12 #12" "ask s12" "closed s12" "pass" "rows" "notices" \
    "reopen s12" "later 600" "pass" "rows" "came s12 approved" "pass" "rows" "notices" "kept" "relaunch" "unread" \
    "pass" "rows" "notices" "reopen s12" "newproc s12" "pass" "rows" "ask s12 now" "rows" "notices" "kept" \
    "row s14" "reopen s14" "logged" 2>&1
  echo "## run again in a new process that doesn't ask (opened only to look): after two minutes its row says it no"
  echo "## longer waits, with Resume, whose press says Resume's words into it, and it then hears what came; a copy beside"
  echo "## the running one begins its own"
  HOME=$(home handed) "$APP" --print-wakes "row s13" "has s13 #12" "ask s13" "closed s13" "pass" "later 1" \
    "came s13 approved" "newproc s13" "pass" "later 100" "pass" "rows" "notices" "say s13" "later 21" "pass" "rows" \
    "notices" "say s13" "ask s13 now" "rows" "row s15" "has s15 #13" "ask s15" "newproc s15" "ask s15" "logged" 2>&1
  echo "## a first Resume whose session closed before it asked, then a second ten minutes later: that one has its own"
  echo "## while, and hears what came"
  HOME=$(home again) "$APP" --print-wakes "row s16" "has s16 #12" "ask s16" "closed s16" "pass" "later 1" "came s16 approved" \
    "newproc s16" "pass" "closed s16" "pass" "rows" "later 600" "newproc s16" "pass" "rows" "ask s16 now" "logged" 2>&1
  echo "## the plain functions"
  HOME=$(home cases) "$APP" --print-wakes "cases" "log" 2>&1
)
compare "Waits and wakes" "$HERE/wakes.expected.txt" "$out" "${1:-}" || failed=1

# Its background waits, which the agent's module leaves off a row's jobs, against ask-panel.sh's own usage line for
# `wait`: every order of every set of the flags it lists, and nothing else. A flag added to the script and missed here
# fails, rather than its wait quietly showing as a job again.
usage=$(sed -n 's/^#   ask-panel.sh wait \(.*\)$/\1/p' app/ask-panel.sh | head -1)
words=$(HOME=$(home words) "$APP" --print-wakes "words" 2>&1 | sed -n 's/^wait words: //p')
out=$(python3 -I - "$usage" "$words" <<'PY'
import itertools, re, sys
flags = re.findall(r"\[(--[a-z-]+)\]", sys.argv[1])
wanted = {" ".join(["wait", *order]) for n in range(len(flags) + 1) for order in itertools.permutations(flags, n)}
given = set(line for line in sys.argv[2].splitlines() if line)
print("wait's flags, as ask-panel.sh's usage gives them:", " ".join(flags) or "(none)")
print("the module gives every order of them:", "yes" if given == wanted else "NO")
for words in sorted(wanted - given): print("   missing:", words)
for words in sorted(given - wanted): print("   not in the usage:", words)
PY
)
compare "Its background waits, against ask-panel.sh" "$HERE/words.expected.txt" "$out" "${1:-}" || failed=1

# `ask-panel.sh wait` against a stand-in panel that answers each ask with the next of its lines, or is away for a
# while (away:<seconds>): what ends a wait, and what it waits through.
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
    if line.startswith("away:"):
        server.close()
        os.unlink(path)
        time.sleep(float(line[5:]))
        server = listen()
        continue
    client, _ = server.accept()
    asked = client.recv(65536).decode().strip()
    print("   asked: " + asked, flush=True)
    client.sendall((line + "\n").encode())
    client.close()
server.close()
os.unlink(path)
PY
SOCKETS=$(sockets_refused "$S")
if [ -n "$SOCKETS" ]; then
  echo "The wait's asks: couldn't run here, as $SOCKETS"
  failed=1
else
  # A wait, and (for a task's answer) how the same panel away ends a wait that isn't Whozmove's own.
  waits() {
    local word=$1
    shift
    python3 "$T/panel.py" "$S/w.sock" "$@" &
    for _ in $(seq 1 50); do [ -S "$S/w.sock" ] && break; sleep 0.1; done
    # shellcheck disable=SC2086
    WHOZMOVE_ASK_SOCKET="$S/w.sock" WHOZMOVE_ASK_EVERY=0.2 WHOZMOVE_ASK_UNREACHED=1 app/ask-panel.sh $word
    echo "exit=$?"
    wait
  }
  out=$({
    echo "== Begun, waiting, the panel away 3 seconds (longer than a wait may be out of reach), then woken"
    waits wait "waiting: Waits on #12" "waiting: Waits on #12" away:3 "waiting: Waits on #12" \
      'woke: {"came":[{"kind":"approved","pr":12,"source":"pull request"}]}'
    echo "== The same panel away, for a task's answer: that wait stops"
    waits "task-answer t1 --wait" "waiting: t1 hasn't been answered yet" away:3
    echo "== Held for a seat, then let go"
    waits wait "waiting: for a free seat in the gear: #12 approved" 'woke: {"came":[]}'
    echo "== Nothing to wait for: said at once"
    waits "wait --comments" "nothing to wait for: nothing of this session's waits on someone else now"
    echo "== --now: answered at once, whatever it says"
    waits "wait --now" "nothing yet: Waits on #12"
    echo "== Refused"
    waits wait "refused: only a session that's running can wait"
    echo "== Whozmove not running when it begins: said at once"
    WHOZMOVE_ASK_SOCKET="$S/gone.sock" app/ask-panel.sh wait; echo "exit=$?"
    echo "== Words it turns away, before it asks"
    for args in "--soon" "--now --now --now" "now"; do
      # shellcheck disable=SC2086
      WHOZMOVE_ASK_SOCKET="$S/gone.sock" app/ask-panel.sh wait $args; echo "exit=$?"
    done
  } 2>&1 | sed -e "s|$S|S|g")
  compare "The wait's asks" "$HERE/asks.expected.txt" "$out" "${1:-}" || failed=1
fi

page=$(page_cases "$HERE/page-cases.js") || { echo "$page"; exit 1; }
compare "The waiting note" "$HERE/page.expected.txt" "$page" "${1:-}" || failed=1
exit $failed
