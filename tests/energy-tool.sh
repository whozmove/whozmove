#!/bin/bash
# tools/energy.sh against a stand-in app this test starts, in a throwaway home: its helpers compile with every warning
# an error; `now` reads the stand-in and names the programs it starts, and the folder each git and gh ran in (git given
# -C, gh started in the folder, as Whozmove starts them), and never prints any other argument they were given (a token
# among them); `launch` reads it since it started, leaving macOS's power log alone, as that's only read for the running
# Whozmove, and reads a made-up one when it's given: an interval from before it started, and when it settled; `week`
# reads a made-up power log, with a quiet hour, a busy one, one the Mac was barely awake and four a Deploy ran in, and
# says what a power log lacks; each report ends with its figures against their targets, marking those past one; nothing
# is written in the home; each app id it takes from a module is still the module's; and each target is the one the
# energy page's table says. The stand-in's figures change
# from run to run, so each of its numbers is written N; the made-up week's are compared as they are, with
# tests/energy-tool.expected.txt.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   tests/energy-tool.sh            run and compare
#   tests/energy-tool.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/.." || exit 1
. tests/sandboxed.sh "$@"
# Stops here if there's no temporary folder: an empty T would make the clean-up below delete this checkout.
T=$(mktemp -d "${TMPDIR:-/tmp}/whozmove-energy-tool.XXXXXX") || exit 1
T=$(cd "$T" && pwd -P) || exit 1
STAND_IN=
trap '[ -n "$STAND_IN" ] && kill "$STAND_IN" 2>/dev/null; rm -rf "$T"' EXIT
. tests/compare.sh

# Each app id tools/energy/hosts.txt takes from a module is still written, quoted, in the file it names: a module that
# changes its id changes it here too.
while IFS=$'\t' read -r id file; do
  case $id in ''|'#'*) continue ;; esac
  [ -z "$file" ] && continue
  grep -qF "\"$id\"" "$file" 2>/dev/null ||
    { echo "tools/energy/hosts.txt: $id isn't in $file any more: take the id that file has now"; exit 1; }
done < tools/energy/hosts.txt

# Each target the reports hold Whozmove to is the one docs/how-it-works/energy.md's table says, in the row it names.
python3 -I - <<'PY' || exit 1
import sys
page = open('docs/how-it-works/energy.md').read()
for line in open('tools/energy/targets.txt'):
    if line.strip() and not line.startswith('#'):
        name, limit, _, row = line.rstrip('\n').split('\t')
        if f"| {row} | under {limit}" not in page:
            sys.exit(f"tools/energy/targets.txt: docs/how-it-works/energy.md's \"{row}\" row doesn't say under "
                     f"{limit}: make the two agree")
PY

# A stand-in git and gh that only wait a moment, so each is seen: programs of their own, as a script's arguments would
# start with its interpreter. And the stand-in app, which starts them over and over: git given the folder, gh started
# in it with a made-up token among its arguments, and gh started in the app's own folder, as a PR's status is asked.
mkdir -p "$T/bin" "$T/home" "$T/shop"
printf '#include <unistd.h>\nint main(void) { usleep(200000); return 0; }\n' > "$T/wait.c"
for name in git gh; do
  clang -O2 -o "$T/bin/$name" "$T/wait.c" || exit 1
done
(
  cd "$T" || exit 1
  while :; do
    "$T/bin/git" -C "$T/shop" status --porcelain
    (cd "$T/shop" && exec "$T/bin/gh" pr view --json state --token made-up-token-1234)
    "$T/bin/gh" pr view https://example.com/pull/1 --json state
    sleep 0.1
  done
) &
STAND_IN=$!
disown "$STAND_IN"
began=$(date +%s)

# A made-up power log for the stand-in's launch: an interval from before it started, a busy one, and a quiet one.
python3 -I - "$T" "$began" <<'PY'
import sqlite3, sys
folder, began = sys.argv[1], int(sys.argv[2])
db = sqlite3.connect(f"{folder}/launch.sqlite")
db.execute("create table PLCoalitionAgent_EventInterval_CoalitionInterval "
           "(timestamp, timestampEnd, LaunchdName, cpu_time, bytesread)")
for start, end, read in ((began - 240, began + 60, 3e8), (began + 60, began + 120, 4e8),
                         (began + 120, began + 180, 1e6)):
    db.execute("insert into PLCoalitionAgent_EventInterval_CoalitionInterval values (?, ?, 'com.whozmove.app', 30, ?)",
               (start, end, read))
db.commit()
PY

raw=$( {
  echo "== now, 3 seconds"
  HOME="$T/home" tools/energy.sh now --seconds 3 --pid "$STAND_IN" 2>&1
  status=$?; echo "exit $([ $status = 0 ] && echo ok || echo failed)"
  echo "== launch"
  HOME="$T/home" tools/energy.sh launch --pid "$STAND_IN" 2>&1
  status=$?; echo "exit $([ $status = 0 ] && echo ok || echo failed)"
  echo "== launch, with a power log"
  HOME="$T/home" tools/energy.sh launch --pid "$STAND_IN" --powerlog "$T/launch.sqlite" 2>&1
  status=$?; echo "exit $([ $status = 0 ] && echo ok || echo failed)"
  echo "== no such process"
  HOME="$T/home" tools/energy.sh now --seconds 1 --pid 999999 2>&1
  status=$?; echo "exit $([ $status = 0 ] && echo ok || echo failed)"
  echo "== no Whozmove running"
  HOME="$T/home" tools/energy.sh launch 2>&1
  status=$?; echo "exit $([ $status = 0 ] && echo ok || echo failed)"
  echo "== written in the home"
  find "$T/home" -mindepth 1 | sed "s|$T|T|"
  echo "(end)"
} )
# Nothing it prints may show an argument but a program's name and folder: the token, here.
case $raw in *made-up-token*) echo "tools/energy.sh printed an argument it shouldn't"; exit 1 ;; esac
# The stand-in's group is the terminal's or the sandbox's, with every process in it, so its lines aren't compared.
out=$(printf '%s\n' "$raw" | grep -v -e '^  its pages' -e '^  also running in its group' -e '^  the whole group' \
  | sed -E -e "s|$T|T|g" -e "s/process $STAND_IN/process PID/" -e 's/(Mon|Tue|Wed|Thu|Fri|Sat|Sun) /DAY /g' \
      -e 's/[0-9]+(\.[0-9]+)?/N/g' \
  | python3 -I -c '
import re, sys
# Programs come most often first, and git and gh take turns, so each list is put in a fixed order before comparing.
# In now, the figures held against the targets are those of the group the stand-in runs in, the terminal or the
# sandbox, which may be over one or under it, so that mark is written MARK there; launch keeps it, from a made-up log.
section = ""
for line in sys.stdin:
    line = line.rstrip("\n")
    if line.startswith("== "):
        section = line
    if section.startswith("== now") and line.startswith("    "):
        line = re.sub(r"^    (over |under) · ", "    MARK  · ", line)
    head, colon, rest = line.partition(": ")
    if head in ("  programs it started, seen", "  by folder") and colon:
        tail = ""
        if head == "  programs it started, seen":
            rest, _, tail = rest.rpartition(" (")
        rest = ", ".join(sorted(rest.split(", "))) + (" (" + tail if tail else "")
    print(head + colon + rest)' )

# A made-up power log for yesterday: 08:00 quiet, 09:00 busy (a terminal at work), 10:00 with the Mac awake 5 minutes,
# 12:00 and 13:00 with a new build of Whozmove going in at 13:20, 15:00 with a Deploy's run from 15:10 to 15:30, and
# 17:00 with another Deploy started at 17:10 (in the home's Whozmove log); one with no LaunchdName; and one with no
# battery rows, as a Mac with no battery keeps.
mkdir -p "$T/home/Library/Application Support/Whozmove"
python3 -I - "$T" <<'PY'
import json, os, sqlite3, sys, time
folder = sys.argv[1]
day = time.localtime(time.time() - 86400)
base = time.mktime((day.tm_year, day.tm_mon, day.tm_mday, 8, 0, 0, 0, 0, -1))
COLUMNS = ("timestamp, timestampEnd, LaunchdName, LaunchdCoalitionId, cpu_time, gpu_time, gpu_energy_nj, bytesread, "
           "interrupt_wakeups, platform_idle_wakeups, tasks_started")
COALITIONS = "PLCoalitionAgent_EventInterval_CoalitionInterval"

def make(name, columns=COLUMNS, battery=True, hours=(0, 1, 2, 4, 5, 7, 9)):
    db = sqlite3.connect(f"{folder}/{name}")
    names = [c.strip() for c in columns.split(',')]
    db.execute(f"create table {COALITIONS} ({columns})")
    db.execute("create table PLBatteryAgent_EventBackward_Battery (timestamp)")
    started = 1000
    for i in hours:
        t = base + i * 3600
        started += 600
        row = dict(timestamp=t, timestampEnd=t + 3600, LaunchdName='com.whozmove.app', LaunchdCoalitionId=7,
                   cpu_time=90 * (i + 1), gpu_time=36, gpu_energy_nj=18e9, bytesread=1e8 * (i + 1),
                   interrupt_wakeups=180000,
                   platform_idle_wakeups=180000, tasks_started=started)
        db.execute(f"insert into {COALITIONS} values ({', '.join('?' * len(names))})", [row[n] for n in names])
        if battery:
            for m in range(5 if i == 2 else 60):
                db.execute("insert into PLBatteryAgent_EventBackward_Battery values (?)", (t + m * 60,))
    if 'LaunchdName' in names:
        db.execute(f"insert into {COALITIONS} (timestamp, timestampEnd, LaunchdName, cpu_time) "
                   "values (?, ?, 'application.com.mitchellh.ghostty.1.2', 1000)", (base + 3600, base + 7200))
    db.commit()

make('week.sqlite')
make('no-name.sqlite', columns="timestamp, timestampEnd, cpu_time, bytesread")
make('no-battery.sqlite', battery=False, hours=(0,))
def logged(t):
    return time.strftime('%Y-%m-%d %H:%M:%S', time.gmtime(t)) + ' +0000'

whozmove = f"{folder}/home/Library/Application Support/Whozmove"
with open(f"{whozmove}/panel.log", 'w') as log:
    log.write(f"{logged(base + 5 * 3600 + 1200)}  swap-in: Restarted Whozmove (its login item)\n")
    log.write(f"{logged(base + 9 * 3600 + 600)}  deploy in shop of shop: ran the command you confirmed "
              "(12 characters)\n")
run = f"{whozmove}/deploys/d1"
os.makedirs(run)
with open(f"{run}/run.json", 'w') as out:
    json.dump({'startedAt': (base + 7 * 3600 + 600) * 1000, 'pid': 0}, out)
for name, text in (('log', 'built\n'), ('status', '0\n')):
    with open(f"{run}/{name}", 'w') as out:
        out.write(text)
    os.utime(f"{run}/{name}", (base + 7 * 3600 + 1800, base + 7 * 3600 + 1800))
PY
week=$( {
  for log in week no-name no-battery; do
    echo "== week, $log"
    HOME="$T/home" tools/energy.sh week --powerlog "$T/$log.sqlite" 2>&1
    status=$?; echo "exit $([ $status = 0 ] && echo ok || echo failed)"
  done
} | sed -E -e 's/(Mon|Tue|Wed|Thu|Fri|Sat|Sun) [0-9]{2} (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)/DAY/g' \
      -e 's/(Mon|Tue|Wed|Thu|Fri|Sat|Sun) ([0-9]{2}:[0-9]{2})/DAY \2/g' )
compare "Energy tool" tests/energy-tool.expected.txt "$out
$week" "${1:-}"
