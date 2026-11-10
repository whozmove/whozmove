#!/bin/bash
# The process-notes module's tests: drafts of how a made-up project works asked for, shown, turned away, kept with Keep
# It, declined with Not Now and drafted again, two sessions drafting at once, a worktree and its repo sharing one note,
# a folder outside git, Keep It that can't write and then Try Again, what's kept and read back, and panel.log, which
# holds no word of a note (Whozmove --print-process, compared with notes.expected.txt); `ask-panel.sh process-draft`
# against a stand-in panel, and what it turns away before it asks (asks.expected.txt); and the Keep It card in each of
# its states (page-cases.js, run with macOS's jsc in UTC, compared with page.expected.txt).
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   modules/process-notes/tests/test.sh            run and compare
#   modules/process-notes/tests/test.sh --update   run and save the output as the new expected (after a change you
#                                                  meant)
cd "$(dirname "$0")/../../.." || exit 1
. tests/sandboxed.sh "$@"
HERE=modules/process-notes/tests
# Stops here if there's no temporary folder: an empty T would make the clean-up below delete this checkout.
T=$(mktemp -d "${TMPDIR:-/tmp}/whozmove-process-notes.XXXXXX") || exit 1
T=$(cd "$T" && pwd -P) || exit 1
S=$(mktemp -d /tmp/wz-pn.XXXXXX 2>/dev/null || mktemp -d "${TMPDIR:-/tmp}/wz-pn.XXXXXX") || exit 1
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
  echo "## a first note: drafted, shown, kept with Keep It, and handed to a session on a worktree of the same project"
  HOME=$(home first) "$APP" --print-process "row s1 repo" "row s2 tree" "way s1" "draft s1 listed" "rows" "way s1" \
    "later 30" "keep s1" "rows" "kept" "way s1" "way s2" "draft s2 first" "logged" 2>&1
  echo "## drafted again: against the note as kept, each change marked; a second draft takes the first's place"
  HOME=$(home again) "$APP" --print-process "row s1 repo" "draft s1 first" "keep s1" "later 60" "draft s1 newline" \
    "rows" "draft s1 again" "rows" "later 5" "stale s1" "rows" "keep s1" "kept" "way s1" 2>&1
  echo "## Not Now: the same lines aren't shown again on another row, fewer neither, a line that wasn't there is"
  HOME=$(home declined) "$APP" --print-process "row s1 repo" "row s2 tree" "draft s1 first" "later 10" "notnow s1" \
    "rows" "way s1" "draft s2 first" "way s2" "draft s2 listed" "draft s1 again" "rows" "later 10" "keep s1" "draft s2 first" "rows" "logged" 2>&1
  echo "## Not Now, then the user changes their mind: the same session's draft shows again, saying nothing of Not Now"
  HOME=$(home mind) "$APP" --print-process "row s1 repo" "draft s1 first" "notnow s1" "draft s1 first" "rows" \
    "keep s1" "kept" 2>&1
  echo "## Not Now on one of two cards with the same lines: the other goes too"
  HOME=$(home twins) "$APP" --print-process "row s1 repo" "row s2 tree" "draft s1 first" "draft s2 listed" "rows" \
    "notnow s1" "rows" "way s2" "logged" 2>&1
  echo "## after Not Now on a change, a draft taking a kept line out is a change of its own, and shown"
  HOME=$(home takeout) "$APP" --print-process "row s1 repo" "row s2 tree" "draft s1 first" "keep s1" \
    "draft s1 newline" "notnow s1" "draft s2 again" "rows" 2>&1
  echo "## two sessions on one project draft at once: Keep It on one takes the other back"
  HOME=$(home both) "$APP" --print-process "row s1 repo" "row s2 tree" "draft s1 first" "draft s2 cards" "rows" \
    "keep s2" "rows" "way s1" "way s2" "kept" 2>&1
  echo "## its session ends: its draft goes with it, and nothing is kept"
  HOME=$(home ended) "$APP" --print-process "row s1 repo" "draft s1 first" "ended s1" "rows" "way s1" "kept" "logged" 2>&1
  echo "## Keep It can't write: the draft waits, saying why, and Try Again keeps it"
  HOME=$(home locked) "$APP" --print-process "row s1 repo" "locked" "draft s1 first" "keep s1" "rows" "way s1" \
    "unlocked" "keep s1" "rows" "kept" "logged" 2>&1
  echo "## a restart reads the notes back; a folder outside git is its own project; one with no folder has none"
  HOME=$(home restart) "$APP" --print-process "row s1 repo" "draft s1 first" "keep s1" "relaunch" "row s3 plain" \
    "row s4 none" "way s1" "way s3" "draft s3 again" "rows" "draft s4 first" "way s4" 2>&1
  echo "## drafts turned away"
  HOME=$(home refused) "$APP" --print-process "row s1 repo" "draft s1 empty" "draft s1 secret" "draft s1 control" \
    "draft s1 long" "draft s1 wide" "draft s1 huge" "rows" "kept" "logged" "log" 2>&1
  echo "## the plain functions"
  HOME=$(home cases) "$APP" --print-process "cases" 2>&1
  echo "## and every run's panel.log"
  for each in first again declined both ended locked restart refused; do
    printf '%s: ' "$each"
    HOME="$T/$each" "$APP" --print-process "log" 2>&1 | tail -1
  done
)
compare "Process notes" "$HERE/notes.expected.txt" "$out" "${1:-}" || failed=1

# `ask-panel.sh process-draft` against a stand-in panel that answers each ask with the next of its lines: what it sends,
# and what it turns away before it asks.
cat > "$T/panel.py" <<'PY'
import base64, json, socket, sys
path, lines = sys.argv[1], sys.argv[2:]
server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(path)
server.listen(1)
server.settimeout(10)
for line in lines:
    client, _ = server.accept()
    asked = json.loads(client.recv(65536).decode().strip())
    note = base64.b64decode(asked.pop("note64", "")).decode()
    print("   asked: " + json.dumps(asked) + ", its note: " + json.dumps(note), flush=True)
    client.sendall((line + "\n").encode())
    client.close()
server.close()
PY
SOCKETS=$(sockets_refused "$S")
if [ -n "$SOCKETS" ]; then
  echo "process-draft's asks: couldn't run here, as $SOCKETS"
  failed=1
else
  asks() {
    local note=$1
    shift
    python3 "$T/panel.py" "$S/p.sock" "$@" &
    for _ in $(seq 1 50); do [ -S "$S/p.sock" ] && break; sleep 0.1; done
    printf '%s' "$note" | WHOZMOVE_ASK_SOCKET="$S/p.sock" app/ask-panel.sh process-draft
    echo "exit=$?"
    wait
    rm -f "$S/p.sock"
  }
  long=$(python3 -c 'print("Checks: npm test. " * 223)')
  wide=$(python3 -c 'print("é" * 3990)')
  out=$({
    echo "== Shown"
    asks "$(printf 'Staging link: QA wants it in each pull request. (you, on PAY-142)\nScreenshots: before and after. (the review on #57)')" \
      "shown on your row: “Keep this as how acme-web works?”, for the user's Keep It."
    echo "== Refused by the panel"
    asks "Deploys: with the key in it" "refused: line 1 holds something shaped like a key or a token, which never goes in a note: draft it again"
    echo "== Turned away before it asks: nothing, too long"
    printf '  \n\n' | WHOZMOVE_ASK_SOCKET="$S/gone.sock" app/ask-panel.sh process-draft; echo "exit=$?"
    printf '%s' "$long" | WHOZMOVE_ASK_SOCKET="$S/gone.sock" app/ask-panel.sh process-draft; echo "exit=$?"
    echo "== 3990 letters that each take two bytes: within 4000 characters and one ask"
    printf '%s' "$wide" | WHOZMOVE_ASK_SOCKET="$S/gone.sock" app/ask-panel.sh process-draft; echo "exit=$?"
  } 2>&1 | sed -e "s|$S|S|g")
  compare "process-draft's asks" "$HERE/asks.expected.txt" "$out" "${1:-}" || failed=1
fi

page=$(page_cases "$HERE/page-cases.js") || { echo "$page"; exit 1; }
compare "The Keep It card" "$HERE/page.expected.txt" "$page" "${1:-}" || failed=1
exit $failed
