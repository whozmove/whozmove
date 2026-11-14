#!/bin/bash
# Measures what Whozmove costs while it runs, and only reads: its share of a core, its wakeups, what it reads and writes
# on disk and its memory; the same for its group (its web pages, and every program it starts, ended ones included: a
# Deploy's runs among them, for any project); and the programs it starts. It finds the running copy by panel.pid in
# Whozmove's folder, compiles its small helpers (tools/energy/) into a temporary folder, writes nothing anywhere else
# and starts nothing of Whozmove's. What it's read against is in docs/how-it-works/energy.md.
#   tools/energy.sh now [MINUTES]   over the next MINUTES (5 if not said): the app, its pages, its group, the programs
#                                   it starts by name and the folder each git and gh ran in, and whether agents were
#                                   at work
#   tools/energy.sh launch          the running copy since it started: what it read and wrote and its memory, and
#                                   the group's reads in each of macOS's power log intervals since, and when they
#                                   settled
#   tools/energy.sh week            the last 7 days of macOS's power log, per hour the Mac was awake: the group's
#                                   share of a core, graphics' time and energy, disk reads, wakeups and programs started,
#                                   quiet hours (nothing at work in a terminal, an editor or Claude Desktop) apart
#                                   from busy ones
#   --pid PID                       with now or launch, reads that process instead (the tests' stand-in)
#   --seconds N                     with now, reads for N seconds instead of minutes (the tests' short reading)
#   --powerlog FILE                 with launch or week, reads that power log instead of macOS's (the tests' own)
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
self=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
cd "$(dirname "$0")/.."
mode=${1:-}
[ $# -gt 0 ] && shift
minutes=5 pid= seconds= given_log=
while [ $# -gt 0 ]; do
  case $1 in
    --pid) shift; pid=${1:-} ;;
    --seconds) shift; seconds=${1:-} ;;
    --powerlog) shift; given_log=${1:-} ;;
    *) minutes=$1 ;;
  esac
  shift
done
case $mode in
  now|launch|week) ;;
  *) sed -n '2,/^# Copyright/p' "$self" | sed '$d' | cut -c3-; exit 2 ;;
esac
case $minutes$seconds in ''|*[!0-9]*) echo "tools/energy.sh: MINUTES and N are whole numbers" >&2; exit 2 ;; esac
seconds=${seconds:-$((minutes * 60))}
appdir="$HOME/Library/Application Support/Whozmove"
# The power log macOS keeps of each app's use, readable without root, with a file for each earlier day in Archives;
# only ever copied, then read from the copy.
powerlogs=/private/var/db/powerlog/Library/BatteryLife
# Whozmove's own bundle id, as its build names it: the power log keeps each app under it.
app_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' app/Info.plist)
T=$(mktemp -d "${TMPDIR:-/tmp}/whozmove-energy.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT

# Copies the power log into the temporary folder as logs/0.sqlite (with its -wal and -shm), and with `days`, each
# earlier day's archive from the last 7 days as logs/<n>.sqlite, unpacked.
copy_powerlogs() {
  mkdir -p "$T/logs"
  if [ -n "$given_log" ]; then
    cp "$given_log" "$T/logs/0.sqlite" 2>/dev/null
    return
  fi
  cp "$powerlogs/CurrentPowerlog.PLSQL" "$T/logs/0.sqlite" 2>/dev/null || return 1
  cp "$powerlogs/CurrentPowerlog.PLSQL-wal" "$T/logs/0.sqlite-wal" 2>/dev/null || true
  cp "$powerlogs/CurrentPowerlog.PLSQL-shm" "$T/logs/0.sqlite-shm" 2>/dev/null || true
  [ "${1:-}" = days ] || return 0
  python3 -I - "$powerlogs/Archives" "$T/logs" <<'PY'
import gzip, os, re, shutil, sys, time, zlib
archives, logs = sys.argv[1], sys.argv[2]
oldest = time.strftime('%Y-%m-%d', time.localtime(time.time() - 8 * 86400))
try:
    names = sorted(n for n in os.listdir(archives) if re.match(r'powerlog_\d{4}-\d\d-\d\d_.*\.PLSQL\.gz$', n))
except OSError:
    names = []
for i, name in enumerate(n for n in names if n[9:19] >= oldest):
    copy = os.path.join(logs, f"{i + 1}.sqlite")
    try:
        with gzip.open(os.path.join(archives, name)) as packed, open(copy, 'wb') as out:
            shutil.copyfileobj(packed, out)
    except (OSError, EOFError, zlib.error):
        # One being written as it's read, or damaged: left out, and named.
        if os.path.exists(copy):
            os.remove(copy)
        with open(os.path.join(logs, 'skipped.txt'), 'a') as skipped:
            skipped.write(name + '\n')
PY
}

if [ "$mode" != week ]; then
  stand_in=yes
  if [ -z "$pid" ]; then
    stand_in=
    pid=$(cat "$appdir/panel.pid" 2>/dev/null) ||
      { echo "tools/energy.sh: Whozmove isn't running: open it, then run this again" >&2; exit 1; }
  fi
  case $pid in ''|*[!0-9]*) echo "tools/energy.sh: no process to read" >&2; exit 1 ;; esac
  for helper in procs programs; do
    clang -O2 -Wall -Wextra -Werror -o "$T/$helper" "tools/energy/$helper.c"
  done
  "$T/procs" "$pid" > "$T/before" || { echo "tools/energy.sh: process $pid isn't running" >&2; exit 1; }
fi

case $mode in
  now)
    since=$(date +%s)
    "$T/programs" "$pid" "$seconds" > "$T/started"
    "$T/procs" "$pid" > "$T/after" || { echo "tools/energy.sh: process $pid ended while it was read" >&2; exit 1; }
    python3 -I - "$T" "$seconds" "$appdir" "$since" <<'PY'
import collections, os, sys
folder, seconds, appdir, since = sys.argv[1], int(sys.argv[2]) or 1, sys.argv[3], float(sys.argv[4])

# A figure for the targets, printed with them once the report ends.
def against(name, label, value, shown):
    with open(os.path.join(folder, 'against'), 'a') as out:
        out.write(f"{name}\t{label}\t{value}\t{shown}\n")
span = (f"{seconds // 60} minute{'s' if seconds != 60 else ''}" if seconds % 60 == 0
        else f"{seconds} second{'s' if seconds != 1 else ''}")

def read(name):
    procs, group = {}, None
    for line in open(os.path.join(folder, name)):
        parts = line.split()
        if parts[0] == 'group':
            group = parts[1] if parts[1] in ('refused', 'totals-refused') else \
                {k: int(v) for k, v in (p.split('=') for p in parts[1:])}
        else:
            procs[int(parts[1])] = dict(kind=parts[0], name=parts[2],
                                        **{k: int(v) for k, v in (p.split('=') for p in parts[3:])})
    return procs, group

before, group_before = read('before')
after, group_after = read('after')

def line(label, was, now, memory=True):
    cpu = (now['cpu'] - was['cpu']) / 1e9 / seconds * 100
    wakeups = (now['wakeups'] - was['wakeups']) / seconds
    read_mb = (now['read'] - was['read']) / 1e6
    written_mb = (now['written'] - was['written']) / 1e6
    held = f", memory {now['memory'] / 1e6:.0f} MB" if memory else ''
    print(f"  {label}: {cpu:.1f}% of a core, {wakeups:.0f} wakeups a second, read {read_mb:.1f} MB, "
          f"wrote {written_mb:.1f} MB{held}")

app = next(p for p, v in after.items() if v['kind'] == 'app')
print(f"{after[app]['name']} (process {app}), over {span}:")
line('the app', before[app], after[app])
keys = ('cpu', 'wakeups', 'read', 'written', 'memory')
members = [p for p, v in after.items() if v['kind'] == 'proc' and p in before]
pages = [p for p in members if after[p]['name'].startswith('com.apple.WebKit')]
others = [p for p in members if p not in pages]
if 'refused' in (group_before, group_after):
    print("  its pages: not read (macOS won't say which group it's in)")
elif pages:
    line(f"its pages ({len(pages)})", {k: sum(before[p][k] for p in pages) for k in keys},
         {k: sum(after[p][k] for p in pages) for k in keys})
if others:
    # Anything else still running in its group: a Deploy's run, say, which counts in the group's figures below.
    names = collections.Counter(after[p]['name'] for p in others)
    print("  also running in its group: " + ', '.join(f"{n} {c}" if c > 1 else n for n, c in names.most_common(8)))
if isinstance(group_before, dict) and isinstance(group_after, dict):
    started = group_after['tasks'] - group_before['tasks']
    line(f"the whole group ({started} programs started)", group_before, group_after, memory=False)
else:
    print("  the whole group: macOS didn't say (its group can't be read here)")
names, folders = collections.Counter(), collections.Counter()
for row in open(os.path.join(folder, 'started')):
    name, _, where = row.rstrip('\n').partition('\t')
    names[name] += 1
    if where:
        folders[f"{name} {os.path.basename(where.rstrip('/'))}"] += 1
    elif name in ('git', 'gh'):
        folders[f"{name} (no folder)"] += 1
told = ', '.join(f"{n} {c}" for n, c in names.most_common()) or 'none seen'
print(f"  programs it started, seen: {told} ({sum(names.values()) / seconds * 60:.0f} a minute)")
if folders:
    print('  by folder: ' + ', '.join(f"{f} {c}" for f, c in folders.most_common(8)))
records = os.path.join(appdir, 'sessions')
try:
    moved = sum(1 for f in os.scandir(records) if f.name.endswith('.json') and f.stat().st_mtime >= since)
    print(f"  agents at work meanwhile: {moved} sessions' records changed" if moved
          else "  agents at work meanwhile: none")
except OSError:
    moved = None
    print("  agents at work meanwhile: couldn't tell (no sessions folder)")
# The targets are the whole group's; where its group can't be read, the app's own figures stand in, and say so. When
# it can't tell whether agents were at work, it's held to the targets for agents at work, the looser ones.
grouped = isinstance(group_before, dict) and isinstance(group_after, dict)
was, now = (group_before, group_after) if grouped else (before[app], after[app])
at_work = moved != 0
against('', "against the targets, " + ("agents at work" if moved else "nothing at work" if moved == 0 else
                                        "agents at work or not (couldn't tell)")
        + ("" if grouped else ", the app's own figures (its group can't be read here)"), 0, '')
cpu = (now['cpu'] - was['cpu']) / 1e9 / seconds * 100
against('busy' if at_work else 'quiet', 'share of a core', cpu, f"{cpu:.1f}%")
wakeups = (now['wakeups'] - was['wakeups']) / seconds
against('wakeups', 'wakeups', wakeups, f"{wakeups:.0f} a second")
reads = (now['read'] - was['read']) / 1e9 / seconds * 3600
against('reads', 'reads', reads, f"{reads:.2f} GB an hour")
writes = (now['written'] - was['written']) / 1e6 / seconds * 3600
against('writes', 'writes', writes, f"{writes:.0f} MB an hour")
if at_work:
    git = names['git'] / seconds * 60
    against('git', 'git runs seen', git, f"{git:.0f} a minute")
memory = after[app]['memory'] / 1e6
against('memory', "the app's memory", memory, f"{memory:.0f} MB")
PY
    ;;
  launch)
    # Whether the power log was read: yes, or why not (another process than Whozmove, or one this Mac won't copy).
    have_log=another
    if [ -z "$stand_in" ] || [ -n "$given_log" ]; then
      have_log=refused
      copy_powerlogs && have_log=yes
    fi
    python3 -I - "$T" "$have_log" "$app_id" <<'PY'
import os, sqlite3, sys, time
folder, have_log, app_id = sys.argv[1], sys.argv[2], sys.argv[3]

# A figure for the targets, printed with them once the report ends.
def against(name, label, value, shown):
    with open(os.path.join(folder, 'against'), 'a') as out:
        out.write(f"{name}\t{label}\t{value}\t{shown}\n")
app = None

# Ends the report with its targets: the app's memory, and the group's reads until it settled, where the power log
# told them.
def finish(read=None, settled=True):
    against('', 'against the targets', 0, '')
    against('memory', "the app's memory", app['memory'] / 1e6, f"{app['memory'] / 1e6:.0f} MB")
    if read is not None:
        label = 'its group read until it settled' if settled else 'its group read so far, not settled yet'
        against('launch', label, read / 1e6, f"{read / 1e6:.0f} MB")
    sys.exit(0)

for line in open(os.path.join(folder, 'before')):
    parts = line.split()
    if parts[0] == 'app':
        app = dict(pid=parts[1], name=parts[2], **{k: int(v) for k, v in (p.split('=') for p in parts[3:])})
# When it started by the clock, sleep included; its age counts only the time the Mac was awake.
started = app['start'] if app['start'] > 0 else time.time() - app['age']
print(f"{app['name']} (process {app['pid']}), started {time.strftime('%a %H:%M', time.localtime(started))}, "
      f"awake {app['age'] // 60} minutes since:")
print(f"  read {app['read'] / 1e6:.0f} MB, wrote {app['written'] / 1e6:.0f} MB, memory {app['memory'] / 1e6:.0f} MB, "
      f"{app['cpu'] / 1e9:.0f} s of CPU")
if have_log == 'another':
    print("  the power log: read only for Whozmove: run this without --pid to see Whozmove's")
    finish()
if have_log != 'yes':
    print("  the power log: can't be read here: run tools/energy.sh launch in your own Terminal")
    finish()
db = sqlite3.connect(f"file:{os.path.join(folder, 'logs', '0.sqlite')}?mode=ro", uri=True)
table = 'PLCoalitionAgent_EventInterval_CoalitionInterval'
columns = {row[1] for row in db.execute(f"pragma table_info({table})")}
missing = {'timestamp', 'timestampEnd', 'LaunchdName', 'bytesread', 'cpu_time'} - columns
if missing:
    print("  the power log: this Mac's doesn't record apps by name, so the group's reads aren't shown")
    finish()
# Its group by its id, which the power log keeps beside its name; else by the name, which is its bundle id for its
# login item and application.<bundle id>.<numbers> for a copy you opened.
if 'coalition' in app and 'LaunchdCoalitionId' in columns:
    which, given = "LaunchdCoalitionId = ?", (app['coalition'],)
else:
    which, given = "(LaunchdName = ? or LaunchdName like ?)", (app_id, f"application.{app_id}.%")
rows = db.execute(f"select timestamp, timestampEnd, bytesread, cpu_time from {table} "
                  f"where {which} and timestampEnd > ? order by timestamp", (*given, started)).fetchall()
if not rows:
    print("  the power log: no interval since it started yet (it writes one every few minutes)")
    finish()
print("  the whole group, each power log interval since:")
settled = None
for i, (start, end, read, cpu) in enumerate(rows):
    span = max(end - start, 1)
    before = " (began before it started: what ran then is in it too)" if start < started else ''
    print(f"    {time.strftime('%H:%M', time.localtime(start))}-{time.strftime('%H:%M', time.localtime(end))}: "
          f"read {read / 1e6:.0f} MB, {cpu / span * 100:.0f}% of a core{before}")
    # Settled: from the end of the first interval after which every later one reads under 5 MB a minute.
    if settled is None and i + 1 < len(rows) and all(r / max(e - s, 1) * 60 < 5e6 for s, e, r, _ in rows[i + 1:]):
        settled = end
if settled:
    print(f"  settled {(settled - started) / 60:.0f} minutes after it started")
elif len(rows) == 1:
    print("  not settled yet: only one interval so far")
else:
    print("  not settled yet: the last interval still read 5 MB a minute or more")
finish(sum(r for s, e, r, _ in rows if not settled or e <= settled), settled is not None)
PY
    ;;
  week)
    copy_powerlogs days ||
      { echo "tools/energy.sh: macOS's power log can't be read here: run tools/energy.sh week in your own Terminal" >&2
        exit 1; }
    # To tell whether a Deploy's run is still running: a pid given again to a later program doesn't count.
    helper=
    clang -O2 -Wall -Wextra -Werror -o "$T/procs" tools/energy/procs.c 2>/dev/null && helper="$T/procs"
    python3 -I - "$T" "$appdir" "$helper" "$app_id" <<'PY'
import calendar, collections, glob, json, os, re, sqlite3, subprocess, sys, time
folder, appdir, helper, app_id = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

# A figure for the targets, printed with them once the report ends.
def against(name, label, value, shown):
    with open(os.path.join(folder, 'against'), 'a') as out:
        out.write(f"{name}\t{label}\t{value}\t{shown}\n")
coalitions, battery = 'PLCoalitionAgent_EventInterval_CoalitionInterval', 'PLBatteryAgent_EventBackward_Battery'
base = ['timestamp', 'timestampEnd', 'LaunchdName']
wanted = ['cpu_time', 'gpu_time', 'gpu_energy_nj', 'bytesread', 'interrupt_wakeups', 'platform_idle_wakeups',
          'tasks_started']
since = time.time() - 7 * 86400

# The start of the hour on this Mac's clock that `t` falls in (a time zone can be half an hour off UTC's hours).
def hour(t):
    return int(t - (t + time.localtime(t).tm_gmtoff) % 3600)

# Each interval's use spread over the hours it covers, by how much of it falls in each.
def spread(start, end, use, into):
    start, end = max(start, since), max(end, start + 1)
    t = start
    while t < end:
        step = min(hour(t) + 3600, end)
        share = (step - t) / (end - start)
        into[hour(t)].update({k: v * share for k, v in use.items()})
        t = step

whozmove, agents = collections.defaultdict(collections.Counter), collections.defaultdict(collections.Counter)
awake, have, first, said, unreadable, unnamed = collections.Counter(), None, None, set(), set(), False
# Each figure in plain words, for a log that lacks it.
figures = dict(cpu_time='CPU time', gpu_time='graphics time', gpu_energy_nj='graphics energy', bytesread='disk reads',
               interrupt_wakeups='wakeups', platform_idle_wakeups='wakeups', tasks_started='programs started')
# The hosts' groups, named for each app's bundle id (application.<id>.<numbers> for an app you opened), from
# tools/energy/hosts.txt, which says where each module's is written.
hosts = [line.split('\t')[0].strip() for line in open('tools/energy/hosts.txt')
         if line.strip() and not line.startswith('#')]
mine, mine_given = "(LaunchdName = ? or LaunchdName like ?)", (app_id, f"application.{app_id}.%")
try:
    for name in open(os.path.join(folder, 'logs', 'skipped.txt')):
        unreadable.add(f"an archive it couldn't unpack ({name.strip()})")
except OSError:
    pass
# The archives oldest first, then the current log; an interval kept in two of them (one spanning midnight) counts once.
paths = sorted(glob.glob(os.path.join(folder, 'logs', '*.sqlite')),
               key=lambda p: int(os.path.basename(p).split('.')[0]) or 10 ** 6)
counted = set()

def once(row):
    if (row[0], row[2]) in counted:
        return False
    counted.add((row[0], row[2]))
    return True

for path in paths:
    try:
        db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        tables = {row[0] for row in db.execute("select name from sqlite_master where type = 'table'")}
    except sqlite3.DatabaseError:
        unreadable.add(f"a file it couldn't read ({os.path.basename(path)})")
        continue
    # A log without each app's intervals by name can't be measured: said in one line below, not table by table.
    columns = {row[1] for row in db.execute(f"pragma table_info({coalitions})")} if coalitions in tables else set()
    if not set(base) <= columns:
        unnamed = True
        continue
    here = [c for c in wanted if c in columns]
    have = here if have is None else [c for c in have if c in here]
    for c in wanted:
        if c not in here:
            said.add(figures[c])
    # Programs started is a running count for each group, so an interval's share is the step from the one before.
    last = {}
    for row in db.execute(f"select timestamp, timestampEnd, LaunchdName, {', '.join(here)} from {coalitions} "
                          f"where {mine} and timestampEnd > ? order by timestamp", (*mine_given, since)):
        use = {k: v or 0 for k, v in zip(here, row[3:])}
        if 'tasks_started' in use:
            count = use['tasks_started']
            use['tasks_started'] = count - last[row[2]] if row[2] in last and count >= last[row[2]] else 0
            last[row[2]] = count
        if not once(row):
            continue
        first = min(first or row[0], row[0])
        spread(row[0], row[1], use, whozmove)
    if 'cpu_time' in here:
        like = ' or '.join("LaunchdName like ?" for _ in hosts)
        for start, end, name, cpu in db.execute(f"select timestamp, timestampEnd, LaunchdName, cpu_time from "
                                                f"{coalitions} where timestampEnd > ? and ({like})",
                                                (since, *[f"%{h}%" for h in hosts])):
            if once((start, end, name)):
                spread(start, end, {'cpu_time': cpu or 0}, agents)
    # Awake: macOS writes a battery row about once a minute while the Mac is awake.
    if battery in tables:
        for (t,) in db.execute(f"select timestamp from {battery} where timestamp > ?", (since,)):
            awake[hour(t)] = min(awake[hour(t)] + 60, 3600)
if have is None:
    if unnamed:
        print("This Mac's power log doesn't record apps by name, so week can't measure here: use now or launch instead.")
    else:
        print("This Mac's power log couldn't be read: " + '; '.join(sorted(unreadable)) + '.')
    sys.exit(0)
if unreadable:
    print("Left out: " + '; '.join(sorted(unreadable)) + '.')
if said:
    print("This Mac's power log doesn't record " + ', '.join(sorted(said)) + ": those figures aren't shown.")
if not awake:
    print("This Mac has no battery, so its power log doesn't say when it was awake: each hour with Whozmove's figures "
          "counts as awake.")
    awake = collections.Counter({h: 3600 for h in whozmove})
# Hours a Deploy ran are left out, since its run counts in Whozmove's group, for any project: each Deploy's latest
# run, from its start to its end as the deploy module tells it (now, while its shell or a process it left running is
# still the one it was; else when it was stopped, or its exit status written; else its log's last line); each other
# start Whozmove's log has, with the hour after it; and each time a new build of Whozmove went in.
deploys, reaches = set(), None

def changed(path):
    try:
        return os.path.getmtime(path)
    except OSError:
        return None

runs = []
for run in glob.glob(os.path.join(appdir, 'deploys', '*', 'run.json')):
    folder_of = os.path.dirname(run)
    try:
        record = json.load(open(run))
        began = record['startedAt'] / 1000
    except (OSError, ValueError, KeyError, TypeError):
        continue
    # Its shell and what it left running, each {pid, start}: a process is the run's only while both still match.
    members = [(record.get('pid'), record.get('processStart'))]
    try:
        members += [(m.get('pid'), m.get('start')) for m in json.load(open(os.path.join(folder_of, 'members.json')))]
    except (OSError, ValueError, TypeError, AttributeError):
        pass
    members = [(p, s) for p, s in members if isinstance(p, int) and p > 0 and isinstance(s, int)]
    runs.append((folder_of, began, members))
started = {}
if helper and runs:
    asked = sorted({p for _, _, members in runs for p, _ in members})
    out = subprocess.run([helper, '--started', *map(str, asked)], capture_output=True, text=True).stdout
    started = {int(p): int(s) for p, s in (row.split() for row in out.splitlines())}
for folder_of, began, members in runs:
    try:
        status = open(os.path.join(folder_of, 'status')).read().strip()
    except OSError:
        status = ''
    running = any(started.get(p) == s for p, s in members)
    ended = ((running and time.time()) or changed(os.path.join(folder_of, 'stopped'))
             or (status.isdigit() and changed(os.path.join(folder_of, 'status')))
             or changed(os.path.join(folder_of, 'log')) or began)
    for h in range(hour(began), hour(max(ended, began)) + 3600, 3600):
        deploys.add(h)
try:
    for line in open(os.path.join(appdir, 'panel.log'), errors='replace'):
        m = re.match(r'(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d) \+0000', line)
        if not m:
            continue
        t = calendar.timegm(time.strptime(m.group(1), '%Y-%m-%d %H:%M:%S'))
        reaches = reaches or t
        if 'swap-in: Restarted Whozmove' in line:
            deploys.update({hour(t), hour(t) - 3600})  # the build ran in the hour before it went in, or in that one
        elif ': ran the command you confirmed' in line:
            deploys.update({hour(t), hour(t) + 3600})
except OSError:
    pass
reach = (f"from {time.strftime('%a %d %b %H:%M', time.localtime(first))}" if first else "nothing in the last 7 days")
print(f"Whozmove's whole group, the last 7 days ({reach}), per hour the Mac was awake at least 30 minutes; "
      f"Deploys' hours left out ({len(deploys & set(whozmove))} hours"
      + (f", Whozmove's restarts known since {time.strftime('%a %H:%M', time.localtime(reaches))}" if reaches else "")
      + "):")
days, sleepy = {}, 0
for h in sorted(whozmove):
    if h in deploys:
        continue
    if awake[h] < 1800:
        sleepy += awake[h] > 0 or whozmove[h]['cpu_time'] > 0
        continue
    kind = 'busy' if agents[h]['cpu_time'] > 0.05 * awake[h] else 'quiet'
    key = time.strftime('%Y-%m-%d', time.localtime(h))
    day = days.setdefault(key, dict(label=time.strftime('%a %d %b', time.localtime(h)), quiet=collections.Counter(),
                                    busy=collections.Counter(), awake=collections.Counter()))
    day[kind].update(whozmove[h])
    day['awake'][kind] += awake[h]

def figures(use, seconds):
    if not seconds:
        return '-'
    hours, out = seconds / 3600, []
    if 'cpu_time' in have:
        out.append(f"{use['cpu_time'] / seconds * 100:.1f}% of a core")
    if 'gpu_time' in have:
        out.append(f"graphics {use['gpu_time'] / seconds * 100:.1f}% of the time")
    if 'gpu_energy_nj' in have:
        out.append(f"graphics {use['gpu_energy_nj'] / 1e9 / hours:.0f} joules an hour")
    if 'bytesread' in have:
        out.append(f"reads {use['bytesread'] / 1e9 / hours:.2f} GB an hour")
    if 'interrupt_wakeups' in have and 'platform_idle_wakeups' in have:
        out.append(f"{(use['interrupt_wakeups'] + use['platform_idle_wakeups']) / seconds:.0f} wakeups a second")
    if 'tasks_started' in have:
        out.append(f"{use['tasks_started'] / hours:.0f} programs an hour")
    return ', '.join(out)

totals = dict(quiet=collections.Counter(), busy=collections.Counter(), awake=collections.Counter())
for key in sorted(days):
    day = days[key]
    for kind in ('quiet', 'busy'):
        totals[kind].update(day[kind])
        totals['awake'][kind] += day['awake'][kind]
    print(f"  {day['label']}: quiet {day['awake']['quiet'] / 3600:.0f} h: "
          f"{figures(day['quiet'], day['awake']['quiet'])}")
    print(f"  {' ' * len(day['label'])}  busy {day['awake']['busy'] / 3600:.0f} h: "
          f"{figures(day['busy'], day['awake']['busy'])}")
if sleepy:
    print(f"  ({sleepy} hour{'s' if sleepy != 1 else ''} the Mac was awake under 30 minutes left out)")
print("The week:")
quiet, busy = totals['awake']['quiet'], totals['awake']['busy']
if quiet:
    print(f"  quiet hours ({quiet / 3600:.0f} h): {figures(totals['quiet'], quiet)}")
else:
    print("  no quiet hours this week")
if busy:
    print(f"  busy hours ({busy / 3600:.0f} h): {figures(totals['busy'], busy)}")
all_use, seconds = totals['quiet'] + totals['busy'], quiet + busy
if seconds:
    against('', 'against the targets', 0, '')
    if 'cpu_time' in have and quiet:
        cpu = totals['quiet']['cpu_time'] / quiet * 100
        against('quiet', "quiet hours' share of a core", cpu, f"{cpu:.1f}%")
    if 'cpu_time' in have and busy:
        cpu = totals['busy']['cpu_time'] / busy * 100
        against('busy', "busy hours' share of a core", cpu, f"{cpu:.1f}%")
    if 'gpu_time' in have:
        gpu = all_use['gpu_time'] / seconds * 100
        against('graphics', 'graphics', gpu, f"{gpu:.1f}% of the time")
    if 'bytesread' in have:
        reads = all_use['bytesread'] / 1e9 / (seconds / 3600)
        against('reads', 'reads', reads, f"{reads:.2f} GB an hour")
    if 'interrupt_wakeups' in have and 'platform_idle_wakeups' in have:
        wakeups = (all_use['interrupt_wakeups'] + all_use['platform_idle_wakeups']) / seconds
        against('wakeups', 'wakeups', wakeups, f"{wakeups:.0f} a second")
PY
    ;;
esac

# Each report's figures against their targets, from the one list of them (tools/energy/targets.txt), each marked
# first, where the eye starts: over its target, or under it.
if [ -s "$T/against" ]; then
  python3 -I - "$T/against" <<'PY'
import sys
targets = {}
for line in open('tools/energy/targets.txt'):
    if line.strip() and not line.startswith('#'):
        name, limit, unit, _ = line.rstrip('\n').split('\t')
        targets[name] = float(limit), unit
for line in open(sys.argv[1]):
    name, label, value, shown = line.rstrip('\n').split('\t')
    if not name:
        print(f"  {label}:")
        continue
    limit, unit = targets[name]
    mark = 'over' if float(value) >= limit else 'under'
    print(f"    {mark:<5} · {label}: {shown} (target under {limit:g}{unit})")
PY
fi
