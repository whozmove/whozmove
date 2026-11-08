#!/bin/bash
# The switches a session may use by itself that last only while Whozmove runs (app/core/Allowed.m): what is kept in
# ticked.json as they change, what a copy that starts after a restart offers back and what it doesn't, what one press at
# the foot of the mode menu (bringBack:) turns on again and what it refuses, what Turn Back On says before it
# (bringableFor:among:why:), and what a Quit, a restart and a print run leave of the file, as Whozmove --print-ticked
# runs each in a throwaway home, compared with tests/ticked.expected.txt.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   tests/ticked.sh            run and compare
#   tests/ticked.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/.." || exit 1
. tests/sandboxed.sh "$@"
# Stops here if there's no temporary folder: an empty T would make the clean-up below delete this checkout.
T=$(mktemp -d "${TMPDIR:-/tmp}/whozmove-ticked.XXXXXX") || exit 1
T=$(cd "$T" && pwd -P) || exit 1
PIDS=
# A folder a case locked is unlocked before it goes.
trap '[ -n "$PIDS" ] && kill $PIDS 2>/dev/null; chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT
. tests/lib.sh
. tests/compare.sh
APP=$(built_app "$T") || exit 1
H="$T/home"
FILE="$H/Library/Application Support/Whozmove/ticked.json"

# Session processes: two still running, and one that will have ended by case 3.
sleep 600 & L=$!; disown
sleep 600 & L2=$!; disown
# Its parent is launchd's, which reaps it as soon as it's killed, so it is gone and not left as a zombie.
DYING=$(sleep 600 >/dev/null 2>&1 & echo $!)
PIDS="$L $L2 $DYING"

fresh() { chmod -R u+rwx "$H" 2>/dev/null; rm -rf "$H"; mkdir -p "$H"; }
run() { HOME="$H" "$APP" --print-ticked "$@" 2>&1; }  # one copy of the panel, each argument a step it takes
# What ticked.json says, by session and switch: the count, and whether it names the process.
dump() {
  python3 -I -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except OSError:
    print("   (no ticked.json)"); sys.exit()
for s in sorted(d):
    if s == "workspaces":
        for f in sorted(d[s]):
            for k in sorted(d[s][f]):
                print("   folder %s %s: %s" % (f, k, ", ".join(sorted(d[s][f][k]))))
        continue
    for k in sorted(d[s]):
        r = d[s][k]
        print("   %s %s count=%s %s" % (s, k, r.get("count", "none"),
                                       "process named" if r.get("pid") and r.get("processStart") else "no process"))
' "$FILE"
}
# Changes ticked.json as another program running as you could: the python given says how (d is the file's JSON).
edit() {
  python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1]))
exec(sys.argv[2])
json.dump(d, open(sys.argv[1], "w"))
' "$FILE" "$@"
}
# A copy in which the user ticks three switches on a session's row, which answers for them a few times.
first() {  # first <session> <pid>
  run "row $1 $2" start \
    "on $1 runB" "on $1 runA" "on $1 runC" \
    "count $1 runB" "count $1 runB" "count $1 runB" "count $1 runC" >/dev/null
}

out=$(
echo "== 1 ticking writes the file and a count goes in; unticking takes a switch out at once, and the file with the last"
fresh
run "row s-live $L" start "on s-live runB" "on s-live runA" "on s-live runC" \
  "count s-live runB" "count s-live runB" "count s-live runB" file show
dump
run "row s-live $L" start "off s-live runA" show
fresh
run "row s-live $L" start "on s-live runA" "on s-live runC" "count s-live runC" "off s-live runA" \
  show file
dump
run "row s-live $L" start "off s-live runC" show file

echo "== 2 a new copy has nothing on, and the live session's switches wait, with their counts"
fresh
first s-live "$L"
dump
run "row s-live $L" start show "ask s-live runB" "ask s-live runA"
dump

echo "== 3 not waiting: an ended session's, an id that isn't one, a switch Whozmove hasn't, a switch kept in a file, a process started at another time"
fresh
first s-live "$L"
first s-dying "$DYING"
first s-start "$L"
kill $DYING; while kill -0 $DYING 2>/dev/null; do sleep 0.1; done
edit '
good = d["s-live"]["runB"]
d["s-live"]["noSuchSwitch"] = good
d["s-live"]["dontWait"] = good
d["../not-an-id"] = {"runB": good}
d["s-start"] = {"runB": dict(good, processStart=good["processStart"] + 1)}
'
run "row s-live $L" "row s-dying $DYING" "row s-start $L" start show
echo "   what the file keeps now:"
dump

echo "== 4 one press brings them back with their counts, a second does nothing, and the file says they are on"
fresh
first s-live "$L"
run "row s-live $L" start "bring s-live" "bring s-live" show file
dump
echo "   and a copy that starts after that one offers them again:"
run "row s-live $L" start show

echo "== 5 a press is refused, and says why: the session open twice, the row following another process now"
fresh
first s-live "$L"
run "row s-live $L twice" start show "bring s-live" "ask s-live runB" show
run "row s-live $L2" start show "bring s-live" "ask s-live runB"
echo "   with the process the same, it goes through:"
run "row s-live $L" start "bring s-live"

echo "== 6 a Quit takes the file away and nothing writes it again; a restart leaves it for the next copy"
fresh
run "row s-live $L" start "on s-live runB" quit file "on s-live runA" file
fresh
run "row s-live $L" start "on s-live runB" restart file
run "row s-live $L" start show

echo "== 7 a switch that waits answers an ask with why, in plain words; one never ticked says the usual; ticked by hand it is on"
fresh
first s-live "$L"
run "row s-live $L" start "ask s-live runC" "ask s-live runA" "on s-live runC" \
  "ask s-live runC" show

echo "== 8 a print run that sets switches leaves a ticked.json in its home exactly as it was"
fresh
first s-live "$L"
before=$(shasum "$FILE")
run "row s-live $L" "on s-live runB" "off s-live runC" "count s-live runB" list quit file
[ "$(shasum "$FILE")" = "$before" ] && echo "   ticked.json: untouched" || echo "   ticked.json: CHANGED"

echo "== 9 refused when the session isn't the team's lead now; a count of -5 comes back as 0; an untick holds when the folder can't be written"
fresh
first s-live "$L"
run "row s-live $L member" start show "bring s-live" list
dump
fresh
first s-live "$L"
edit 'd["s-live"]["runB"]["count"] = -5'
run "row s-live $L" start "bring s-live"
fresh
run "row s-live $L" start "on s-live runB" "on s-live runA" lock "off s-live runB" show unlock list file
echo "   once the folder can be written the file is written again, without it:"
dump
fresh
echo "   unticked while the folder can't be changed, then a restart: the next copy is offered nothing for it"
run "row s-live $L" start "on s-live runB" lock "off s-live runB" restart unlock
dump
run "row s-live $L" start show

# Two folders a team works in, real paths, as the app keeps a folder.
F="$T/shop"; G="$T/other"
mkdir -p "$F" "$G"

echo "== 10 a switch kept for a folder: a new session there holds it, with nothing to press, counting afresh, only for asks from its own process; the file names the folder and switch only"
fresh
run "row s-a $L in=$F" start "on s-a keptOne" "count s-a keptOne" "count s-a keptOne" show \
  "row s-a $L member in=$F" "row s-b $L2 in=$F" list show "held s-b" "ask s-b keptOne" \
  "askfrom s-b keptOne $L" "askfrom s-b keptOne $L2" file
dump

echo "== 11 off, with why, for: a lead in another folder, a member there, one open twice, one not running, one blocked from holding it"
fresh
run "row s-a $L in=$F" start "on s-a keptOne" "row s-x $L2 in=$G" "row s-m $L2 member in=$F" "row s-t $L2 twice in=$F" \
  "row s-z 0 in=$F" show "ask s-x keptOne" "ask s-m keptOne" "ask s-t keptOne" "ask s-z keptOne" \
  "block s-a" "ask s-a keptOne" show "unblock s-a" "ask s-a keptOne"

echo "== 12 the session it was ticked in ending doesn't end it; your untick does, from any row in the folder, held or not"
fresh
run "row s-a $L in=$F" start "on s-a keptOne" "on s-a keptTwo" "row s-a 0 in=$F" list "row s-b $L in=$F" show \
  "block s-b" show "off s-b keptOne" "row s-m $L2 member in=$F" "off s-m keptTwo" show file

echo "== 13 a restart and a Quit leave it waiting for one press on any session in the folder, which it's then given in"
fresh
run "row s-a $L in=$F" start "on s-a keptOne" "on s-a runB" restart
dump
run "row s-b $L2 in=$F" start show "ask s-b keptOne" "bring s-b" show "held s-b"
fresh
run "row s-a $L in=$F" start "on s-a keptOne" "on s-a runB" quit file
echo "   a Quit keeps only what's kept for a folder:"
dump
run "row s-b $L2 in=$F" "block s-b" start show "bring s-b" "unblock s-b" "bring s-b" show

echo "== 14 what ticked.json says of folders is only offered: a folder that isn't one, a switch not kept by folder and a session it names are refused or ignored"
fresh
run "row s-a $L in=$F" start "on s-a keptOne" restart
edit '
d["workspaces"][sys.argv[3]]["keptOne"]["session"] = "s-evil"
d["workspaces"][sys.argv[3]]["runB"] = {"at": 1}
d["workspaces"]["relative/folder"] = {"keptOne": {"at": 1}}
d["workspaces"][sys.argv[3] + "/gone"] = {"keptOne": {"at": 1}}
d["workspaces"][sys.argv[3] + "/../shop"] = {"keptTwo": {"at": 1}}
' "$F"
run "row s-b $L2 in=$F" start show "ask s-b keptOne" "bring s-b" "held s-b"
dump

echo "== 15 a switch kept for a folder lapses once no session there has held it for 7 days: one held 8 days ago isn't offered back, one held 6 days ago is"
fresh
run "row s-a $L in=$F" start "on s-a keptOne" "on s-a keptTwo" restart
edit '
import time
now = time.time() * 1000
d["workspaces"][sys.argv[3]]["keptOne"]["held"] = now - 8 * 24 * 3600 * 1000
d["workspaces"][sys.argv[3]]["keptTwo"]["held"] = now - 6 * 24 * 3600 * 1000
' "$F"
run "row s-b $L2 in=$F" start show
dump

echo "== 16 Turn Back On's reason is one for a switch it offers: Switch B, ticked in another process, isn't offered, so the reason is Kept One's"
fresh
run "row s-a $L in=$F" start "on s-a runB" "on s-a keptOne" restart
run "row s-a $L2 in=$F" "block s-a" start show "back s-a" "bring s-a" "unblock s-a" "back s-a" "bring s-a"
)
# The processes' pids, named for what they are, so the output reads the same on every run.
out=$(echo "$out" | sed "s|$T|T|g" | perl -pe "s/(?<![0-9])$L(?![0-9])/<live>/g; s/(?<![0-9])$L2(?![0-9])/<other>/g; s/(?<![0-9])$DYING(?![0-9])/<dying>/g")
# A recording in which nothing waited would pass the cases that expect refusals, so case 2 must offer the three
# switches, or the run fails, --update or not.
if ! echo "$out" | grep -q 'waiting \[runA 0, runB 3, runC 1\]'; then
  echo "$out"
  echo "Switches kept across a restart: case 2 offered nothing back, so ticked.json itself is broken." >&2
  exit 1
fi
compare "Switches kept across a restart" tests/ticked.expected.txt "$out" "${1:-}"
